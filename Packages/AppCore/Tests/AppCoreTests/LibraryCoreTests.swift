import Foundation
import Store
import XCTest
@testable import AppCore

/// Fase 7f, parte 1.1: `library.markBest`, cierre de sesión en `library.trash/delete` y `ProjectSummary.separationError`.
@MainActor
final class LibraryCoreTests: XCTestCase {
    struct Rig {
        var bridge: Bridge
        var root: URL
        var a: Project
        var b: Project
        var takes: [UUID]
    }

    func makeRig() throws -> Rig {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("libcore-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("projects", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }

        func make(_ title: String, _ name: String) throws -> Project {
            var p = Project(song: Song(title: title, artist: "Banda", source: "source/original.wav", sourceSHA256: "abc",
                                       sourceFormat: "wav", sourceSampleRate: 44100, sourceChannels: 2,
                                       sampleRate: 44100, duration: 1))
            p.separation = SeparationState(state: .done, model: "m", finishedAt: Date(timeIntervalSince1970: 1_700_000_000))
            p.stems = [Stem(kind: .bass, file: "stems/bass.wav")]
            let folder = root.appendingPathComponent(name, isDirectory: true)
            let layout = ProjectLayout(folder: folder)
            try layout.createSkeleton()
            try StudyTests.writeSine(layout.stemURL(.bass), frequency: 110, seconds: 1)
            try ProjectFile.save(p, to: folder)
            return p
        }
        var a = try make("Tema A", "Banda - Tema A")
        let b = try make("Tema B", "Banda - Tema B")
        let t1 = Take(), t2 = Take()
        a.takes = [t1, t2]
        a.recording = RecordingState(parts: [RecordingPart(name: "Rítmica", takeIDs: [t1.id, t2.id], bestTakeID: t1.id)])
        try ProjectFile.save(a, to: root.appendingPathComponent("Banda - Tema A", isDirectory: true))

        let services = JobServices(importer: FixtureImporter(), separator: FixtureSeparator(gate: FixtureGate()),
                                   levelMeter: nil, analyzer: nil, guitarSplitter: nil)
        let bridge = try Bridge(options: LaunchOptions(projectsFolder: root, supportDir: support, audio: .simulated),
                                mediaBase: "https://tf.media/", reveal: nil, services: services)
        return Rig(bridge: bridge, root: root, a: a, b: b, takes: [t1.id, t2.id])
    }

    func call(_ r: Rig, _ method: String, _ params: String = "{}") async -> [String: Any] {
        let out = await r.bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        return (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] ?? [:]
    }

    func errorCode(_ o: [String: Any]) -> String? { (o["error"] as? [String: Any])?["code"] as? String }

    // MARK: L1

    func testMarkBestSetsAndKeepsOnePerPart() async throws {
        let r = try makeRig()
        let id = r.a.id.uuidString
        let o = await call(r, "library.markBest", "{\"id\":\"\(id)\",\"takeId\":\"\(r.takes[1].uuidString)\"}")
        XCTAssertEqual((o["result"] as? [String: Any])?["marked"] as? Bool, true, "\(o)")
        let saved = try ProjectFile.load(folder: r.root.appendingPathComponent("Banda - Tema A"))
        XCTAssertEqual(saved.recording?.parts.first?.bestTakeID, r.takes[1])
        // Fija, no alterna: repetirlo no la desmarca.
        _ = await call(r, "library.markBest", "{\"id\":\"\(id)\",\"takeId\":\"\(r.takes[1].uuidString)\"}")
        let again = try ProjectFile.load(folder: r.root.appendingPathComponent("Banda - Tema A"))
        XCTAssertEqual(again.recording?.parts.first?.bestTakeID, r.takes[1])
    }

    func testMarkBestErrors() async throws {
        let r = try makeRig()
        let id = r.a.id.uuidString
        var o = await call(r, "library.markBest", "{\"id\":\"\(id)\",\"takeId\":\"\(UUID().uuidString)\"}")
        XCTAssertEqual(errorCode(o), "not-found")
        o = await call(r, "library.markBest", "{\"id\":\"\(UUID().uuidString)\",\"takeId\":\"\(r.takes[0].uuidString)\"}")
        XCTAssertEqual(errorCode(o), "not-found")
        o = await call(r, "library.markBest", "{\"id\":\"x\",\"takeId\":\"\(r.takes[0].uuidString)\"}")
        XCTAssertEqual(errorCode(o), "bad-params")
        o = await call(r, "library.markBest", "{\"id\":\"\(id)\",\"takeId\":\"y\"}")
        XCTAssertEqual(errorCode(o), "bad-params")
    }

    // MARK: L2

    func testDeleteClosesOpenStudyOfThatProject() async throws {
        let r = try makeRig()
        let open = await call(r, "study.open", "{\"projectId\":\"\(r.b.id.uuidString)\"}")
        XCTAssertNotNil(open["result"], "\(open)")
        XCTAssertEqual(r.bridge.studyService.current?.session.projectID, r.b.id)
        let o = await call(r, "library.delete", "{\"id\":\"\(r.b.id.uuidString)\"}")
        XCTAssertEqual((o["result"] as? [String: Any])?["removed"] as? Bool, true, "\(o)")
        XCTAssertNil(r.bridge.studyService.current, "la sesión del tema borrado se cierra")
        XCTAssertFalse(FileManager.default.fileExists(atPath: r.root.appendingPathComponent("Banda - Tema B").path))
    }

    func testDeleteOfAnotherProjectKeepsStudyOpen() async throws {
        let r = try makeRig()
        _ = await call(r, "study.open", "{\"projectId\":\"\(r.b.id.uuidString)\"}")
        let o = await call(r, "library.delete", "{\"id\":\"\(r.a.id.uuidString)\"}")
        XCTAssertEqual((o["result"] as? [String: Any])?["removed"] as? Bool, true, "\(o)")
        XCTAssertEqual(r.bridge.studyService.current?.session.projectID, r.b.id, "otro tema abierto: no se toca")
    }

    // MARK: L3

    func testSummaryCarriesSeparationErrorAndNullOtherwise() async throws {
        let r = try makeRig()
        var failed = r.b
        failed.separation = SeparationState(state: .failed, model: "m", error: "Modelo no encontrado")
        try ProjectFile.save(failed, to: r.root.appendingPathComponent("Banda - Tema B"))
        let o = await call(r, "library.list")
        let projects = try XCTUnwrap((o["result"] as? [String: Any])?["projects"] as? [[String: Any]])
        let byTitle = Dictionary(uniqueKeysWithValues: projects.map { ($0["title"] as! String, $0) })
        XCTAssertEqual(byTitle["Tema B"]?["separationError"] as? String, "Modelo no encontrado")
        XCTAssertTrue(byTitle["Tema A"]?["separationError"] is NSNull, "sin fallo: null, no ausente")
        let d = await call(r, "library.project", "{\"id\":\"\(r.b.id.uuidString)\"}")
        XCTAssertEqual((d["result"] as? [String: Any])?["separationError"] as? String, "Modelo no encontrado")
    }
}
