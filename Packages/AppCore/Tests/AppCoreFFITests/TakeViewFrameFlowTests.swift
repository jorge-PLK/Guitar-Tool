#if canImport(AVFoundation)
import CAppCoreFFI
import CoreVideo
import Foundation
import Testing
@testable import AppCoreFFI

// Recorrido real de la app SIN Flutter (ola 3.3.AU): `takeview.open` / `takeview.openOffset` por el núcleo (`CoreState`, con los
// sumideros de AppCoreFFI instalados), un `tf_texture_host` falso y la textura creada DESPUÉS de abrir (como Dart). El visor
// abre en pausa: tiene que llegar `frame_available` y `tf_frame_copy(TF_CHANNEL_TAKE)` tiene que dar el fotograma sin pulsar play.

private final class Inbox: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []
    func add(_ m: String) { lock.lock(); messages.append(m); lock.unlock() }
    func first(containing text: String, timeout: TimeInterval = 15) async -> String? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let hit = lock.withLock({ messages.first { $0.contains(text) } }) { return hit }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return nil
    }
}

/// Lo que haría el runner: en cada `frame_available` pide `tf_frame_copy` y se queda con el último fotograma no nulo.
private nonisolated(unsafe) var flowCalls: [Int64] = []
private nonisolated(unsafe) var flowFrames: [CVPixelBuffer] = []
private let flowLock = NSLock()
private func callCount() -> Int { flowLock.withLock { flowCalls.count } }
private func frameCount() -> Int { flowLock.withLock { flowFrames.count } }
private func lastFrame() -> CVPixelBuffer? { flowLock.withLock { flowFrames.last } }

private struct Fixture { let projectsDir: URL; let projectId: String; let takeId: String; let work: URL }

/// COPIA (clon APFS) de un proyecto de `Temp/flutter/val-projects` con toma de vídeo. Skip si no hay.
private func makeFixture(named wanted: String? = nil) throws -> Fixture? {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let src = repo.appendingPathComponent("Temp/flutter/val-projects")
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: src.path) else { return nil }
    for name in names.sorted() where wanted == nil || name.contains(wanted!) {
        let folder = src.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("project.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = json["id"] as? String, let takes = json["takes"] as? [[String: Any]] else { continue }
        for t in takes {
            guard let tid = t["id"] as? String, let v = t["videoFile"] as? String, let a = t["processedFile"] as? String,
                  t["songStart"] != nil,
                  fm.fileExists(atPath: folder.appendingPathComponent(v).path),
                  fm.fileExists(atPath: folder.appendingPathComponent(a).path) else { continue }
            // Dentro del repo (mismo volumen APFS): la copia es un clon, no 1 GB de E/S.
            let work = repo.appendingPathComponent("Temp/flutter/tmp-au-\(UUID().uuidString)")
            let projects = work.appendingPathComponent("p")
            try fm.createDirectory(at: projects, withIntermediateDirectories: true)
            try fm.copyItem(at: folder, to: projects.appendingPathComponent(name))
            return Fixture(projectsDir: projects, projectId: pid, takeId: tid, work: work)
        }
    }
    return nil
}

extension FrameChannelTests {
    /// Toma 1920 HEVC («El roce»).
    @Test func takeOpenInPauseDeliversFrameWithoutPlay() async throws { try await openInPause(project: "El roce") }
    /// Toma 640 HEVC (Megadeth).
    @Test func takeOpenInPauseDeliversFrameWithoutPlay640() async throws { try await openInPause(project: "Megadeth") }

    private func openInPause(project: String) async throws {
        guard let fx = try makeFixture(named: project) else { return }  // sin val-projects con toma de vídeo: nada que probar
        defer { try? FileManager.default.removeItem(at: fx.work) }

        flowLock.withLock { flowCalls = []; flowFrames = [] }
        var host = tf_texture_host()
        host.register_texture = { channel in 200 + Int64(channel) }
        host.frame_available = { id in
            flowLock.withLock { flowCalls.append(id) }
            if let raw = ffiFrameCopy(Int32(TF_CHANNEL_TAKE)) {
                let pb = Unmanaged<CVPixelBuffer>.fromOpaque(raw).takeRetainedValue()
                flowLock.withLock { flowFrames.append(pb) }
            }
        }
        host.unregister_texture = { _ in }
        ffiCoreSetTextureHost(&host)
        defer { ffiTextureDispose(Int32(TF_CHANNEL_TAKE)); ffiCoreSetTextureHost(nil) }

        let core = CoreState(), inbox = Inbox()
        let args = ["--projects-folder", fx.projectsDir.path, "--support-dir", fx.work.appendingPathComponent("s").path,
                    "--audio", "simulated"]
        let opts = String(decoding: try JSONSerialization.data(withJSONObject: ["args": args]), as: UTF8.self)
        #expect(core.start(optionsJSON: opts, sink: .handler { inbox.add($0) }) == 0)
        defer { core.shutdown(timeoutMs: 2000) }

        core.send(#"{"id":1,"method":"takeview.open","params":{"projectId":"\#(fx.projectId)","takeId":"\#(fx.takeId)"}}"#)
        let opened = try #require(await inbox.first(containing: #""id":1"#))
        #expect(opened.contains("result"), "\(opened)")

        // Dart crea la textura tras el resultado de `takeview.open`.
        let take = Int32(TF_CHANNEL_TAKE)
        #expect(ffiTextureCreate(take) == 202)
        let t0 = Date()
        while frameCount() == 0, Date().timeIntervalSince(t0) < 1 { try await Task.sleep(nanoseconds: 5_000_000) }
        #expect(frameCount() >= 1, "sin fotograma en 1 s tras crear la textura (avisos: \(callCount()))")
        let first = try #require(lastFrame())
        #expect(CVPixelBufferGetWidth(first) > 0 && CVPixelBufferGetHeight(first) > 0)

        // Seek en pausa: nuevo aviso y nuevo fotograma (a 2 s y de vuelta a 0).
        for (n, seconds) in [(2, 2.0), (3, 0.0)] {
            let before = frameCount()
            let prev = lastFrame()
            core.send(#"{"id":\#(n),"method":"takeview.seek","params":{"seconds":\#(seconds)}}"#)
            let t = Date()
            while frameCount() == before, Date().timeIntervalSince(t) < 3 { try await Task.sleep(nanoseconds: 5_000_000) }
            #expect(frameCount() > before, "sin fotograma tras seek a \(seconds)")
            #expect(lastFrame() !== prev, "mismo fotograma tras seek a \(seconds)")
        }
        core.send(#"{"id":9,"method":"takeview.close","params":{}}"#)
        _ = await inbox.first(containing: #""id":9"#, timeout: 3)
    }
}
#endif
