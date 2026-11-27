import XCTest
import Foundation
@testable import AppCore

/// Medición de la exportación de montaje con una copia de proyectos real (se salta sin las variables). Pensada para el PC:
/// `TF_EXPORT_BENCH_PROJECTS`, `TF_EXPORT_BENCH_SUPPORT` y `TF_EXPORT_BENCH_PROJECT` (id). Con `TF_EXPORT_PROFILE=1` la
/// exportación imprime la tabla por fase (stderr) y `TF_EXPORT_FRAMES=N` limita los fotogramas.
final class MontageExportBenchTests: XCTestCase {
    @MainActor
    func testRealProjectExport() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let projects = env["TF_EXPORT_BENCH_PROJECTS"], let support = env["TF_EXPORT_BENCH_SUPPORT"],
              let pid = env["TF_EXPORT_BENCH_PROJECT"] else { throw XCTSkip("sin TF_EXPORT_BENCH_*") }
        let bridge = try Bridge(options: LaunchOptions(projectsFolder: URL(fileURLWithPath: projects), supportDir: URL(fileURLWithPath: support), audio: .simulated),
                                mediaBase: "m", reveal: nil, videoHooks: RecordFixtureWorld.noConversionHooks)
        let open = await bridge.router.handle("{\"id\":1,\"method\":\"montage.open\",\"params\":{\"projectId\":\"\(pid)\"}}")
        print("BENCH open -> \(open.prefix(120))")
        let c = try XCTUnwrap(bridge.montageService.current)
        var waited = 0.0
        while !c.canExport && waited < 120 { try await Task.sleep(nanoseconds: 250_000_000); waited += 0.25 }
        XCTAssertTrue(c.canExport, "no se puede exportar: \(c.videoStates)")
        let t0 = Date()
        let out = await bridge.router.handle("{\"id\":2,\"method\":\"montage.startExport\",\"params\":{}}")
        print("BENCH startExport -> \(out.prefix(120))")
        while c.isExporting && Date().timeIntervalSince(t0) < 3000 { try await Task.sleep(nanoseconds: 250_000_000) }
        print("BENCH total \(String(format: "%.2f", Date().timeIntervalSince(t0))) s, estado \(c.exportPhase)")
        guard case .done = c.exportPhase else { return XCTFail("exportación no terminada: \(c.exportPhase)") }
    }
}
