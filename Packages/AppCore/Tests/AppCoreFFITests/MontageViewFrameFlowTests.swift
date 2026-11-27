#if os(macOS)
import CAppCoreFFI
import CoreVideo
import Foundation
import os
import Testing
@testable import AppCoreFFI

// Diagnóstico «Vista previa en negro» (fase 7f): el recorrido real de Montaje por el núcleo FFI (`CoreState` con los sumideros
// instalados, exports reales, anfitrión de texturas falso). Solo corre con `TF_REAL_MONTAGE_FFI=<carpeta del tema>` (p. ej.
// `~/Music/ToneForge-prueba-7f/El roce de tu cuerpo - Platero Y Tu`; se clona, nunca se escribe) y `TF_REAL_MONTAGE_SUPPORT=<soporte>`.
// Mide qué fotogramas llegan al id de la textura del canal 1 y si `tf_frame_copy` da píxeles con luz.

private final class Inbox: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []
    func add(_ m: String) { lock.lock(); messages.append(m); lock.unlock() }
    func count(containing text: String) -> Int { lock.withLock { messages.filter { $0.contains(text) }.count } }
    func first(containing text: String, timeout: TimeInterval = 20) async -> String? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let hit = lock.withLock({ messages.first { $0.contains(text) } }) { return hit }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return nil
    }
}

private nonisolated(unsafe) var availableByID: [Int64: Int] = [:]
private nonisolated(unsafe) var lumas: [Double] = []
private let mLock = NSLock()
private let ioSurfaceFlags = OSAllocatedUnfairLock(initialState: [Bool]())

private func luma(_ pb: CVPixelBuffer) -> Double {
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
    let planar = CVPixelBufferIsPlanar(pb)
    let w = CVPixelBufferGetWidthOfPlane(pb, 0), h = CVPixelBufferGetHeightOfPlane(pb, 0)
    let row = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
    let p = CVPixelBufferGetBaseAddressOfPlane(pb, 0)!.assumingMemoryBound(to: UInt8.self)
    var sum = 0.0, n = 0.0
    for y in stride(from: 0, to: h, by: 4) {
        for x in stride(from: 0, to: w, by: 4) {
            if planar { sum += Double(p[y * row + x]); n += 1 } else {
                let o = y * row + x * 4
                sum += Double(p[o]) + Double(p[o + 1]) + Double(p[o + 2]); n += 3
            }
        }
    }
    return n > 0 ? sum / n : 0
}

extension FrameChannelTests {
    @Test func realMontageSimulatedAudioTextureBefore() async throws { try await run(textureBeforeOpen: true, audio: "simulated") }
    @Test func realMontageSimulatedAudioTextureAfter() async throws { try await run(textureBeforeOpen: false, audio: "simulated") }
    @Test func realMontageRealAudioTextureBefore() async throws { try await run(textureBeforeOpen: true, audio: nil) }
    @Test func realMontageRealAudioTextureAfter() async throws { try await run(textureBeforeOpen: false, audio: nil) }

    private func run(textureBeforeOpen: Bool, audio: String?) async throws {
        let env = ProcessInfo.processInfo.environment
        guard let src = env["TF_REAL_MONTAGE_FFI"], let supportSrc = env["TF_REAL_MONTAGE_SUPPORT"] else { return }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let work = home.appendingPathComponent("Music/ToneForge-mo-ffi-\(UUID().uuidString.prefix(6))")
        defer { try? fm.removeItem(at: work) }
        let projects = work.appendingPathComponent("p"), support = work.appendingPathComponent("s")
        try fm.createDirectory(at: projects, withIntermediateDirectories: true)
        let folder = URL(fileURLWithPath: src)
        try fm.copyItem(at: folder, to: projects.appendingPathComponent(folder.lastPathComponent))
        try fm.copyItem(at: URL(fileURLWithPath: supportSrc), to: support)
        // profile.json apunta a la copia.
        let pj = support.appendingPathComponent("profile.json")
        if var prof = try JSONSerialization.jsonObject(with: Data(contentsOf: pj)) as? [String: Any] {
            prof["projectsFolder"] = projects.absoluteString
            try JSONSerialization.data(withJSONObject: prof).write(to: pj)
        }
        let project = try JSONSerialization.jsonObject(with: Data(contentsOf: projects.appendingPathComponent(folder.lastPathComponent)
            .appendingPathComponent("project.json"))) as! [String: Any]
        let pid = project["id"] as! String

        mLock.withLock { availableByID = [:]; lumas = [] }
        ioSurfaceFlags.withLock { $0 = [] }
        var host = tf_texture_host()
        host.register_texture = { channel in 300 + Int64(channel) }
        host.frame_available = { id in
            mLock.withLock { availableByID[id, default: 0] += 1 }
            if let raw = ffiFrameCopy(Int32(TF_CHANNEL_MONTAGE)) {
                let pb = Unmanaged<CVPixelBuffer>.fromOpaque(raw).takeRetainedValue()
                let l = luma(pb)
                let ios = CVPixelBufferGetIOSurface(pb) != nil
                mLock.withLock { lumas.append(l) }
                ioSurfaceFlags.withLock { $0.append(ios) }
            }
        }
        host.unregister_texture = { _ in }
        ffiCoreSetTextureHost(&host)
        defer { ffiTextureDispose(Int32(TF_CHANNEL_MONTAGE)); ffiCoreSetTextureHost(nil) }

        let core = CoreState(), inbox = Inbox()
        var args = ["--projects-folder", projects.path, "--support-dir", support.path]
        if let audio { args += ["--audio", audio] }
        let opts = String(decoding: try JSONSerialization.data(withJSONObject: ["args": args]), as: UTF8.self)
        #expect(core.start(optionsJSON: opts, sink: .handler { inbox.add($0) }) == 0)
        defer { core.shutdown(timeoutMs: 2000) }

        var nextId = 1
        @discardableResult func rpc(_ method: String, _ params: String = "{}") async -> [String: Any]? {
            let id = nextId; nextId += 1
            core.send(#"{"id":\#(id),"method":"\#(method)","params":\#(params)}"#)
            guard let m = await inbox.first(containing: #""id":\#(id)"#, timeout: 30),
                  let o = try? JSONSerialization.jsonObject(with: Data(m.utf8)) as? [String: Any] else { return nil }
            return o
        }
        func phase(_ o: [String: Any]?) -> String? {
            ((o?["result"] as? [String: Any])?["preview"] as? [String: Any])?["phase"] as? String
        }

        let montage = Int32(TF_CHANNEL_MONTAGE)
        var texID: Int64 = -2
        if textureBeforeOpen { texID = ffiTextureCreate(montage) }
        let opened = await rpc("montage.open", #"{"projectId":"\#(pid)"}"#)
        #expect(opened?["result"] != nil, "\(String(describing: opened))")
        if !textureBeforeOpen { texID = ffiTextureCreate(montage) }
        var ph = phase(opened)
        let t0 = Date()
        while ph != "ready", ph != "failed", Date().timeIntervalSince(t0) < 60 {
            try await Task.sleep(nanoseconds: 300_000_000)
            ph = phase(await rpc("montage.pause"))
        }
        #expect(ph == "ready", "fase \(ph ?? "nil")")
        let readyAvail = mLock.withLock { availableByID[texID] ?? 0 }
        let readyLumas = mLock.withLock { lumas.count }
        await rpc("montage.seek", #"{"seconds":5}"#)
        try await Task.sleep(nanoseconds: 500_000_000)
        let seekAvail = mLock.withLock { availableByID[texID] ?? 0 }
        await rpc("montage.play")
        try await Task.sleep(nanoseconds: 2_000_000_000)
        await rpc("montage.pause")
        let playAvail = mLock.withLock { availableByID[texID] ?? 0 }
        let ls = mLock.withLock { lumas }
        let relay = inbox.count(containing: "frames.montage")
        let direct = ffiFrameCopy(montage).map { Unmanaged<CVPixelBuffer>.fromOpaque($0).takeRetainedValue() }
        print("MONTAGE-FFI texBefore=\(textureBeforeOpen) audio=\(audio ?? "real") texID=\(texID) availAtReady=\(readyAvail) lumasAtReady=\(readyLumas) availAfterSeek=\(seekAvail) availAfterPlay=\(playAvail) relayMsgs=\(relay) copyBuffer=\(direct != nil) copyLuma=\(direct.map(luma) ?? -1) lumaMin=\(ls.min() ?? -1) lumaMax=\(ls.max() ?? -1) n=\(ls.count)")
        #expect(texID == 301)
        #expect(playAvail > 10, "pocos frame_available durante play")
        #expect(direct != nil)
        #expect(direct.map { CVPixelBufferGetIOSurface($0) != nil } == true, "búfer sin IOSurface (textura negra en Flutter)")
        #expect(ioSurfaceFlags.withLock { $0 }.allSatisfy { $0 } && !ioSurfaceFlags.withLock { $0 }.isEmpty, "frame_available con búfer sin IOSurface")
        #expect((ls.max() ?? 0) > 5, "fotogramas negros")
        #expect(relay == 0, "fotogramas por el relevo JPEG")
        await rpc("montage.close")
    }
}
#endif
