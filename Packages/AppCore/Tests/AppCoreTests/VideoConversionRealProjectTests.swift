import XCTest
import Foundation
import Store
import VideoKit
@testable import AppCore

/// Guarda de diagnóstico con una copia de proyectos real (se salta sin las variables). Pensada para el PC Windows:
/// `TF_HEVC_DIAG_PROJECTS` (carpeta de proyectos), `TF_HEVC_DIAG_SUPPORT` (support-dir) y `TF_HEVC_DIAG_PROJECT` (id).
/// Muestra el sondeo de cada `video.mov`, el veredicto del motor de producción y si se encola la conversión.
final class VideoConversionRealProjectTests: XCTestCase {
    private func say(_ s: String) { print("DIAG \(s)") }

    @MainActor
    func testRealProjectQueuesHEVCConversion() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let projects = env["TF_HEVC_DIAG_PROJECTS"], let support = env["TF_HEVC_DIAG_SUPPORT"],
              let pid = env["TF_HEVC_DIAG_PROJECT"], let id = UUID(uuidString: pid) else {
            throw XCTSkip("sin TF_HEVC_DIAG_*")
        }
        let root = URL(fileURLWithPath: projects), sup = URL(fileURLWithPath: support)
        let bridge = try Bridge(options: LaunchOptions(projectsFolder: root, supportDir: sup, audio: .simulated), mediaBase: "m")
        let folder = try Bridge.service(root).folder(id: id)
        let project = try ProjectFile.load(folder: folder)
        let layout = ProjectLayout(folder: folder)
        let engine = bridge.videoConversion

        var files: [URL] = []
        for t in project.takes {
            let url = layout.videoURL(takeId: t.id)
            files.append(url)
            let exists = FileManager.default.fileExists(atPath: url.path)
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            say("take \(t.id) \(url.path) exists=\(exists) size=\(String(describing: attrs?[.size])) date=\(String(describing: attrs?[.modificationDate]))")
            do {
                let p = try TakeVideoProbe.read(url)
                say("  probe=\(p.map { "\($0.codec)" } ?? "nil")")
                if let p { say("  policy.needs=\(VideoConversionEngine.Hooks.platformPolicy(p))") }
            } catch { say("  probe ERROR \(error)") }
            say("  needsConversion=\(engine.needsConversion(url))")
        }
        say("platformAssumeNeedsWhenUnprobed=\(VideoConversionEngine.Hooks.platformAssumeNeedsWhenUnprobed)")
        do { say("ffmpegURL=\(try await ExternalSources.production(supportDir: sup, environment: env).ffmpegURL().path)") }
        catch { say("ffmpegURL ERROR \(error)") }

        // Como `MontageMethods.open`: el motor se consulta con la base y los punches de cada toma que el plan lleve.
        let out = await bridge.router.handle("{\"id\":1,\"method\":\"montage.open\",\"params\":{\"projectId\":\"\(pid)\"}}")
        say("montage.open -> \(out.prefix(300))")
        for t in project.takes {
            say("take \(t.id) currentState=\(engine.currentState(takeId: t.id))")
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        for t in project.takes {
            say("(+3 s) take \(t.id) currentState=\(engine.currentState(takeId: t.id))")
        }
        if let c = bridge.montageService.current {
            say("gate set=\(c.videoGate != nil) videoLanes=\(c.videoLanes.count) videoStates=\(c.videoStates)")
            for l in c.videoLanes {
                say("lane \(l.takeID) video=\(l.video.map { $0.url?.path ?? "url nil" } ?? "nil") punches=\(l.video?.punches.count ?? -1)")
            }
            for l in c.lanes { say("alllane \(l.takeID) hasVideo=\(l.hasVideo) presence=\(l.presence.count) video=\(l.video?.url?.path ?? "nil")") }
            for p in c.draft?.plan.parts ?? [] {
                say("planpart \(p.name) presence=\(p.presence.count) url=\(p.video?.url?.path ?? "nil") punches=\(p.video?.punches.map { $0.videoURL?.path ?? "nil" } ?? [])")
            }
            say("previewError=\(c.previewError ?? "nil")")
        } else { say("montage.current = nil") }
        say("engine wired into montageService=\(bridge.montageService.videoConversion != nil)")
        let snap = await bridge.router.handle("{\"id\":2,\"method\":\"montage.snapshot\",\"params\":{}}")
        say("snapshot preview: \(snap.range(of: "preview").map { String(snap[$0.lowerBound...].prefix(250)) } ?? "?")")
        _ = await bridge.router.handle("{\"id\":3,\"method\":\"montage.close\",\"params\":{}}")
        XCTAssertFalse(files.isEmpty)
    }
}
