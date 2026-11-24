import CAppCoreFFI
import CoreVideo
import Foundation
import Testing
@testable import AppCoreFFI

/// Recoge los mensajes del núcleo (el sumidero de los tests) y deja esperar al que cumpla una condición.
private final class Inbox: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []
    func add(_ m: String) { lock.lock(); messages.append(m); lock.unlock() }
    private func find(_ text: String) -> String? { lock.withLock { messages.first { $0.contains(text) } } }
    func first(containing text: String, timeout: TimeInterval = 5) async -> String? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            let hit = find(text)
            if let hit { return hit }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return nil
    }
}

private func options() throws -> String {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tf-ffi-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let args = ["--projects-folder", dir.appendingPathComponent("p").path, "--support-dir", dir.appendingPathComponent("s").path,
                "--audio", "simulated"]
    return String(decoding: try JSONSerialization.data(withJSONObject: ["args": args]), as: UTF8.self)
}

private func started() throws -> (CoreState, Inbox) {
    let core = CoreState(), inbox = Inbox()
    #expect(core.start(optionsJSON: try options(), sink: .handler { inbox.add($0) }) == 0)
    return (core, inbox)
}

@Suite struct AppCoreFFITests {
    @Test func startTwiceReturnsOne() throws {
        let (core, inbox) = try started()
        #expect(core.start(optionsJSON: try options(), sink: .handler { inbox.add($0) }) == 1)
        core.shutdown(timeoutMs: 1000)
    }

    @Test func invalidOptionsReturnTwo() {
        let core = CoreState()
        #expect(core.start(optionsJSON: "no es json", sink: .none) == 2)
        #expect(core.start(optionsJSON: #"{"args":[1,2]}"#, sink: .none) == 2)
        #expect(core.start(optionsJSON: #"{"sin":"args"}"#, sink: .none) == 2)
        #expect(ffiCoreStart(nil, 0) == 2)
    }

    @Test func requestGetsResponseOnSink() async throws {
        let (core, inbox) = try started()
        core.send(#"{"id":41,"method":"app.info","params":{}}"#)
        let response = await inbox.first(containing: #""id":41"#)
        #expect(response?.contains("result") == true)
        core.shutdown(timeoutMs: 1000)
    }

    @Test func hostRequestIsResolvedByHostResponse() async throws {
        let (core, inbox) = try started()
        core.send(#"{"id":7,"method":"host.pickAudioFile","params":{}}"#)
        let request = try #require(await inbox.first(containing: "hostRequest"))
        let obj = try #require(try JSONSerialization.jsonObject(with: Data(request.utf8)) as? [String: Any])
        let hr = try #require(obj["hostRequest"] as? [String: Any])
        #expect(hr["method"] as? String == "pickFile")
        let id = try #require(hr["id"] as? Int)
        core.send(#"{"hostResponse":{"id":\#(id),"result":{"path":"/tmp/x.wav"}}}"#)
        let response = try #require(await inbox.first(containing: #""id":7"#))
        #expect(response.contains("/tmp/x.wav"))
        core.shutdown(timeoutMs: 1000)
    }

    @Test func shutdownEmitsCoreShutdownWithinBudget() async throws {
        let (core, inbox) = try started()
        let t0 = Date()
        core.shutdown(timeoutMs: 4000)
        let event = try #require(await inbox.first(containing: "core.shutdown", timeout: 6))
        #expect(event.contains(#""clean""#))
        #expect(Date().timeIntervalSince(t0) < 4.5)
    }
}

// Estado global (tabla de texturas y canales): serializado y con la tabla restaurada al salir.
private nonisolated(unsafe) var availableCalls: [Int64] = []
private let availableLock = NSLock()

private func makePixels(_ w: Int, _ h: Int) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, nil, &pb)
    return pb!
}

@Suite(.serialized) struct FrameChannelTests {
    @Test func frameCopyOfTakeChannelIsNil() {
        ffiCoreSetTextureHost(nil)
        #expect(ffiFrameCopy(2) == nil)
        #expect(ffiTextureCreate(0) == -1)  // sin tabla de texturas
    }

    @Test func montageSinkPublishesToChannelOne() throws {
        availableLock.withLock { availableCalls = [] }
        var host = tf_texture_host()
        host.register_texture = { channel in 100 + Int64(channel) }
        host.frame_available = { id in availableLock.withLock { availableCalls.append(id) } }
        host.unregister_texture = { _ in }
        ffiCoreSetTextureHost(&host)
        defer { ffiTextureDispose(1); ffiCoreSetTextureHost(nil) }
        #expect(ffiTextureCreate(1) == 101)

        montageFrameSink(makePixels(640, 360), 0)
        #expect(availableLock.withLock { availableCalls } == [101])
        let raw = try #require(ffiFrameCopy(1))
        let pb = Unmanaged<CVPixelBuffer>.fromOpaque(raw).takeRetainedValue()
        #expect(CVPixelBufferGetWidth(pb) == 640)
        #expect(CVPixelBufferGetHeight(pb) == 360)
        #expect(ffiFrameCopy(0) == nil)  // la cámara no ha publicado
    }

    @Test func cameraSinkPublishesToChannelZero() throws {
        var host = tf_texture_host()
        host.register_texture = { channel in 100 + Int64(channel) }
        host.frame_available = { _ in }
        host.unregister_texture = { _ in }
        ffiCoreSetTextureHost(&host)
        defer { ffiTextureDispose(0); ffiCoreSetTextureHost(nil) }
        #expect(ffiTextureCreate(0) == 100)
        cameraFrameSink(makePixels(320, 180), 0)
        let raw = try #require(ffiFrameCopy(0))
        let pb = Unmanaged<CVPixelBuffer>.fromOpaque(raw).takeRetainedValue()
        #expect(CVPixelBufferGetWidth(pb) == 320)
    }

    @Test func withoutTextureTableLatestWinsAndNothingAccumulates() throws {
        ffiCoreSetTextureHost(nil)
        weak var first: CVPixelBuffer?
        autoreleasepool {
            let pb = makePixels(64, 64)
            first = pb
            montageFrameSink(pb, 0)
        }
        for i in 1...100 { montageFrameSink(makePixels(64, 32 + i % 2), Double(i)) }
        #expect(first == nil)  // el primero ya no se retiene: solo queda el último
        let raw = try #require(ffiFrameCopy(1))
        let pb = Unmanaged<CVPixelBuffer>.fromOpaque(raw).takeRetainedValue()
        #expect(CVPixelBufferGetHeight(pb) == 32)  // i = 100 -> 32 + 0
        frameChannels.get(1)?.clear()
    }
}
