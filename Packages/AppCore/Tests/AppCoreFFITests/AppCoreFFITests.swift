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

    @Test func frameCopyOfTakeChannelIsNil() {
        #expect(ffiFrameCopy(2) == nil)
        #expect(ffiTextureCreate(0) == -1)  // sin tabla de texturas
    }
}
