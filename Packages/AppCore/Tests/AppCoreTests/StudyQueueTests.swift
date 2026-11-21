import Foundation
import Store
import XCTest
@testable import AppCore

/// 8.3a + 8.5: el estudio y la cola escriben `project.json` por la misma `Library` (un solo escritor).
extension StudyTests {
    func testStudySaveAndQueueEditsBothSurvive() async throws {
        let f = try makeFixture()
        _ = try await open(f)
        // `setLoop` es transitorio (no se guarda); la cejilla sí va a `study.player` con rebote.
        let capo = await call(f, "study.setCapo", "{\"capo\":3}")
        XCTAssertNil(capo["error"], "\(capo)")
        // Renombrar por la cola mientras el estudio tiene un guardado pendiente (rebote de 0,5 s).
        let r = await call(f, "library.rename", "{\"id\":\"\(f.project.id.uuidString)\",\"title\":\"Otro\",\"artist\":\"Grupo\"}")
        XCTAssertNil(r["error"], "\(r)")
        // Cerrar la app: guarda el estudio y cancela la cola.
        await f.bridge.shutdownAsync()
        let p = try savedProject(f)
        XCTAssertEqual(p.song.title, "Otro")
        XCTAssertEqual(p.song.artist, "Grupo")
        XCTAssertEqual(p.study.player.capo, 3)
        XCTAssertTrue(p.study.loops.contains { $0.name == "Riff" })
        XCTAssertEqual(p.sections.count, 2)
        XCTAssertEqual(StudyKitBridge.algorithmVersion, PortableStudyAnalyzer.algorithmVersion)
    }
}
