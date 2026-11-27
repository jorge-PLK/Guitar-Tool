import XCTest
import Foundation
import SourceKit
import Store
import VideoKit
@testable import AppCore

/// Medición del camino completo de conversión con el motor real y ffmpeg real (se salta sin las variables). Pensada para
/// el PC Windows: `TF_HEVC_PHASES_SRC` (carpeta con las tomas HEVC, se copian a una carpeta de trabajo y no se tocan),
/// `TF_HEVC_PHASES_FILES` (nombres separados por comas), `TF_HEVC_PHASES_FFMPEG` (ruta de ffmpeg) y, opcional,
/// `TF_HEVC_PHASES_CONCURRENT` (por omisión la del motor). Con `TF_TRACE_CONVERSION=1` el motor traza las fases.
final class VideoConversionPhasesTests: XCTestCase {
    func testRealConversionPhases() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let src = env["TF_HEVC_PHASES_SRC"], let names = env["TF_HEVC_PHASES_FILES"], let ff = env["TF_HEVC_PHASES_FFMPEG"] else {
            throw XCTSkip("sin TF_HEVC_PHASES_*")
        }
        let fm = FileManager.default
        let work = URL(fileURLWithPath: src).appendingPathComponent("work-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: work) }
        var takes: [(UUID, URL)] = []
        let copyStart = Date()
        for n in names.split(separator: ",").map(String.init) {
            let id = UUID()
            let dir = work.appendingPathComponent(id.uuidString, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dst = dir.appendingPathComponent("video.mov")
            try fm.copyItem(at: URL(fileURLWithPath: src).appendingPathComponent(n), to: dst)
            takes.append((id, dst))
        }
        print("PHASES copy \(String(format: "%.2f", Date().timeIntervalSince(copyStart))) s")

        let jobEngine = JobEngine(root: nil, profileStore: ProfileStore(url: work.appendingPathComponent("p.json")), indexURL: nil,
                                  services: { fatalError("no se usa") })
        jobEngine.setSinks(job: { _ in }, changed: {})
        var hooks = VideoConversionEngine.Hooks(ffmpeg: { URL(fileURLWithPath: ff) }, runner: SystemProcessRunner(),
                                                needsConversion: { $0.codec != .h264 })
        if let c = env["TF_HEVC_PHASES_CONCURRENT"].flatMap(Int.init) { hooks.maxConcurrent = c }
        // `TF_HEVC_PHASES_CPUDECODE=1`: solo NVENC con decodificación en CPU (el camino anterior a 741724a, para comparar).
        if env["TF_HEVC_PHASES_CPUDECODE"] == "1" { hooks.attempts = [.init(encoder: TakeVideoTranscode.nvencEncoder, hwDecode: false)] }
        let engine = VideoConversionEngine(jobs: jobEngine, hooks: hooks)

        let t0 = Date()
        for (id, url) in takes { _ = engine.state(takeId: id, files: [url], title: "t") }
        for (id, _) in takes { await engine.wait(takeId: id) }
        print("PHASES total \(String(format: "%.2f", Date().timeIntervalSince(t0))) s concurrent=\(hooks.maxConcurrent)")
        for (id, url) in takes {
            XCTAssertEqual(engine.currentState(takeId: id), .ready)
            XCTAssertEqual(try TakeVideoProbe.read(url)?.codec, .h264)
        }
    }
}
