import XCTest
@testable import Store

final class RecoveryTests: XCTestCase {
    private func set(_ env: Env, _ id: UUID, _ state: SeparationStatus, updated: TimeInterval = 0,
                     partial: Bool = false) throws {
        let folder = try env.folder(id)
        var p = try ProjectFile.load(folder: folder)
        p.separation = SeparationState(state: state)
        p.updatedAt = Date(timeIntervalSince1970: 1_700_000_000 + updated)
        try ProjectFile.save(p, to: folder)
        if partial {
            try FileManager.default.createDirectory(at: ProjectLayout(folder: folder).stemsPartialDir, withIntermediateDirectories: true)
        }
    }

    func testRequeuesInOrderRunningFirstThenQueuedByDate() async throws {
        let env = try await Env(autoSeparate: false)
        let a = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let b = try await env.library.importSong(from: try env.makeSource("b.mp3", content: "B"))
        let c = try await env.library.importSong(from: try env.makeSource("c.mp3", content: "C"))
        let d = try await env.library.importSong(from: try env.makeSource("d.mp3", content: "D"))
        try set(env, a, .queued, updated: 30)
        try set(env, b, .queued, updated: 10)
        try set(env, c, .running, updated: 50, partial: true)
        try set(env, d, .failed, updated: 1)

        let recovered = try await env.library.recoverInterrupted()
        XCTAssertEqual(recovered, [c, b, a])
        await env.library.waitForSeparations()
        for id in [a, b, c] { let p = try await env.project(id); XCTAssertEqual(p.separation.state, .done) }
        let pd = try await env.project(d)
        XCTAssertEqual(pd.separation.state, .failed, "los ya fallidos no se tocan")
        let calls = await env.separator.calls
        XCTAssertEqual(calls, 3)
    }

    func testProjectWithoutAudioFails() async throws {
        let env = try await Env(autoSeparate: false)
        let a = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let b = try await env.library.importSong(from: try env.makeSource("b.mp3", content: "B"))
        try set(env, a, .queued, updated: 1)
        try set(env, b, .queued, updated: 2)
        let la = ProjectLayout(folder: try env.folder(a))
        try FileManager.default.removeItem(at: la.audioFile)
        try FileManager.default.removeItem(at: la.url(relative: "source/original.mp3"))

        _ = try await env.library.recoverInterrupted()
        await env.library.waitForSeparations()
        let pa = try await env.project(a)
        XCTAssertEqual(pa.separation.state, .failed)
        XCTAssertEqual(pa.separation.error, Library.missingAudioMessage)
        let pb = try await env.project(b)
        XCTAssertEqual(pb.separation.state, .done, "no bloquea a los demás")
    }

    func testInterruptedReseparationKeepsPreviousStems() async throws {
        let env = try await Env()
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        await env.library.waitForSeparations()
        let layout = ProjectLayout(folder: try env.folder(id))
        let before = try String(contentsOf: layout.stemURL(.guitar), encoding: .utf8)
        try "old".write(to: layout.stemURL(.guitar), atomically: true, encoding: .utf8)
        _ = before
        // Reseparación interrumpida: estado running con los stems anteriores y un .partial a medias.
        let folder = layout.folder
        var p = try ProjectFile.load(folder: folder)
        p.separation = SeparationState(state: .running)
        try ProjectFile.save(p, to: folder)
        try FileManager.default.createDirectory(at: layout.stemsPartialDir, withIntermediateDirectories: true)

        await env.separator.setGated(true)
        _ = try await env.library.recoverInterrupted()
        let running = await waitUntil { await env.separator.active == 1 }
        XCTAssertTrue(running)
        XCTAssertEqual(try String(contentsOf: layout.stemURL(.guitar), encoding: .utf8), "old", "se conservan hasta que termine")
        let mid = try ProjectFile.load(folder: folder)
        XCTAssertEqual(mid.stems.count, 6)

        await env.separator.setGated(false)
        await env.library.waitForSeparations()
        XCTAssertEqual(try ProjectFile.load(folder: folder).separation.state, .done)
        XCTAssertEqual(try String(contentsOf: layout.stemURL(.guitar), encoding: .utf8), "stem")
    }

    func testStopAllForShutdownKeepsStoredState() async throws {
        let env = try await Env()
        await env.separator.setBehavior(.hang)
        let a = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let b = try await env.library.importSong(from: try env.makeSource("b.mp3", content: "B"))
        let running = await waitUntil { await env.separator.active == 1 }
        XCTAssertTrue(running)
        await env.library.stopAllForShutdown()
        let pa = try await env.project(a), pb = try await env.project(b)
        XCTAssertEqual(pa.separation.state, .running)
        XCTAssertEqual(pb.separation.state, .queued)
        let calls = await env.separator.calls
        XCTAssertEqual(calls, 1)
    }

    func testRemoveOrphanTemporaries() async throws {
        let env = try await Env(autoSeparate: false)
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let fm = FileManager.default
        let folder = try env.folder(id)
        let importing = env.root.appendingPathComponent(".importing-\(UUID().uuidString)")
        let migrating = folder.appendingPathComponent(".migrating-\(UUID().uuidString)")
        let other = env.root.appendingPathComponent(".importing")          // prefijo no exacto
        let hidden = folder.appendingPathComponent(".migrated-keep")
        for u in [importing, migrating, other, hidden] {
            try fm.createDirectory(at: u, withIntermediateDirectories: true)
            try "x".write(to: u.appendingPathComponent("f"), atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(Library.removeOrphanTemporaries(in: env.root), 2)
        XCTAssertFalse(fm.fileExists(atPath: importing.path))
        XCTAssertFalse(fm.fileExists(atPath: migrating.path))
        XCTAssertTrue(fm.fileExists(atPath: other.path))
        XCTAssertTrue(fm.fileExists(atPath: hidden.path))
        XCTAssertTrue(fm.fileExists(atPath: ProjectLayout(folder: folder).projectFile.path))
    }
}
