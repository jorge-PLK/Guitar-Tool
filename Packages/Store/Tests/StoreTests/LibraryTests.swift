import XCTest
@testable import Store

final class LibraryTests: XCTestCase {
    func testImportCreatesProjectAndSeparatesWithPersistedStates() async throws {
        let env = try await Env()
        await env.separator.setGated(true)
        let src = try env.makeSource("one.mp3", content: "AAA")
        let id = try await env.library.importSong(from: src)

        var p = try await env.project(id)
        XCTAssertEqual(p.song.sourceSHA256.count, 64)
        XCTAssertEqual(p.song.source, "source/original.mp3")
        XCTAssertEqual(p.song.sampleRate, 44100)
        XCTAssertEqual(p.song.title, "one")
        let folder = try env.folder(id)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("audio/song.wav"), encoding: .utf8), "wav@44100")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("source/original.mp3").path))

        let running = await waitUntil { await env.separator.active == 1 }
        XCTAssertTrue(running)
        p = try await env.project(id)
        XCTAssertEqual(p.separation.state, .running)

        await env.separator.setGated(false)
        await env.library.waitForSeparations()
        p = try await env.project(id)
        XCTAssertEqual(p.separation.state, .done)
        XCTAssertEqual(p.separation.model, "mock@1")
        XCTAssertEqual(p.stems.map(\.kind), StemKind.allCases)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ProjectLayout(folder: folder).stemsPartialDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ProjectLayout(folder: folder).stemURL(.guitar).path))
        let seen = await env.separator.statesSeen
        XCTAssertEqual(seen, ["running"])
        let e = try await env.library.entries()
        XCTAssertEqual(e.first?.separationState, "done")
        XCTAssertEqual(e.first?.stemCount, 6)
    }

    func testTwoImportsSeparateInSeriesAndQueuedIsPersisted() async throws {
        let env = try await Env()
        await env.separator.setGated(true)
        let a = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let b = try await env.library.importSong(from: try env.makeSource("b.mp3", content: "B"))
        let running = await waitUntil { await env.separator.active == 1 }
        XCTAssertTrue(running)
        let pa = try await env.project(a)
        let pb = try await env.project(b)
        XCTAssertEqual(pa.separation.state, .running)
        XCTAssertEqual(pb.separation.state, .queued)

        await env.separator.setGated(false)
        await env.library.waitForSeparations()
        let calls = await env.separator.calls
        let maxActive = await env.separator.maxActive
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(maxActive, 1)
        let finalA = try await env.project(a)
        let finalB = try await env.project(b)
        XCTAssertEqual(finalA.separation.state, .done)
        XCTAssertEqual(finalB.separation.state, .done)
    }

    func testFailureMarksFailedAndRemovesPartial() async throws {
        let env = try await Env()
        await env.separator.setBehavior(.fail)
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        await env.library.waitForSeparations()
        let p = try await env.project(id)
        XCTAssertEqual(p.separation.state, .failed)
        XCTAssertEqual(p.separation.error, "modelo roto")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ProjectLayout(folder: try env.folder(id)).stemsPartialDir.path))

        // Relanzar con éxito
        await env.separator.setBehavior(.succeed)
        try await env.library.separate(id: id)
        await env.library.waitForSeparations()
        let again = try await env.project(id)
        XCTAssertEqual(again.separation.state, .done)
        XCTAssertNil(again.separation.error)
    }

    func testCancelRunningAndQueued() async throws {
        let env = try await Env()
        await env.separator.setBehavior(.hang)
        let a = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let b = try await env.library.importSong(from: try env.makeSource("b.mp3", content: "B"))
        let running = await waitUntil { await env.separator.active == 1 }
        XCTAssertTrue(running)

        try await env.library.cancelSeparation(id: b)
        let pb = try await env.project(b)
        XCTAssertEqual(pb.separation.state, .none)

        try await env.library.cancelSeparation(id: a)
        let pa = try await env.project(a)
        XCTAssertEqual(pa.separation.state, .none)
        XCTAssertEqual(pa.stems, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: ProjectLayout(folder: try env.folder(a)).stemsPartialDir.path))
        await env.library.waitForSeparations()
        let calls = await env.separator.calls
        XCTAssertEqual(calls, 1)
    }

    func testDuplicateBySHA() async throws {
        let env = try await Env(autoSeparate: false)
        let first = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "SAME"))
        do {
            _ = try await env.library.importSong(from: try env.makeSource("copy.mp3", content: "SAME"))
            XCTFail("debía lanzar duplicate")
        } catch {
            XCTAssertEqual(error as? LibraryError, .duplicate(first))
        }
        XCTAssertEqual(ProjectScanner.scan(root: env.root).found.count, 1)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: env.root.path)
        XCTAssertEqual(leftovers.filter { $0.hasPrefix(".importing") }, [])
        let p = try await env.project(first)
        XCTAssertEqual(p.separation.state, .none, "autoSeparate=false no encola")
    }

    func testFolderNameUsesMetadataAndAvoidsCollisions() async throws {
        let env = try await Env(autoSeparate: false)
        await env.importer.setMeta(title: "Tema", artist: "Banda")
        _ = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        _ = try await env.library.importSong(from: try env.makeSource("b.mp3", content: "B"))
        let names = try FileManager.default.contentsOfDirectory(atPath: env.root.path).sorted()
        XCTAssertEqual(names, ["Banda - Tema", "Banda - Tema (2)"])
    }

    func testRecoverInterrupted() async throws {
        let env = try await Env(autoSeparate: false)
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let folder = try env.folder(id)
        var p = try ProjectFile.load(folder: folder)
        p.separation = SeparationState(state: .running)
        try ProjectFile.save(p, to: folder)
        try FileManager.default.createDirectory(at: ProjectLayout(folder: folder).stemsPartialDir, withIntermediateDirectories: true)

        let recovered = try await env.library.recoverInterrupted()
        XCTAssertEqual(recovered, [id])
        let after = try await env.project(id)
        XCTAssertEqual(after.separation.state, .failed)
        XCTAssertEqual(after.separation.error, "interrumpida")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ProjectLayout(folder: folder).stemsPartialDir.path))
    }

    func testCleanupAndDiskUsage() async throws {
        let env = try await Env()
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        await env.library.waitForSeparations()
        let usage = await env.library.diskUsage()
        XCTAssertEqual(usage.projects.count, 1)
        XCTAssertGreaterThan(usage.regenerableBytes, 0)
        XCTAssertGreaterThanOrEqual(usage.totalBytes, usage.regenerableBytes)

        let freed = try await env.library.cleanup(id: id)
        XCTAssertGreaterThan(freed, 0)
        let p = try await env.project(id)
        XCTAssertEqual(p.separation.state, .none)
        XCTAssertEqual(p.stems, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: ProjectLayout(folder: try env.folder(id)).audioFile.path))
        let after = await env.library.diskUsage()
        XCTAssertEqual(after.regenerableBytes, 0)
        _ = try await env.library.cleanupAll()
    }
}

final class RateMigrationTests: XCTestCase {
    private func setUpProject(rateProfile: Double) async throws -> (Env, UUID) {
        let env = try await Env(autoSeparate: true, rate: 44100)
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        await env.library.waitForSeparations()
        try env.profile.save(EquipmentProfile(projectsFolder: env.root, workingSampleRate: rateProfile))
        return (env, id)
    }

    func testOpenMigratesToProfileRate() async throws {
        let (env, id) = try await setUpProject(rateProfile: 48000)
        let opened = try await env.library.open(id: id)
        XCTAssertEqual(opened.song.sampleRate, 44100, "open no bloquea: devuelve el estado previo")
        await env.library.waitForMigrations()
        let folder = try env.folder(id)
        let layout = ProjectLayout(folder: folder)
        XCTAssertEqual(try String(contentsOf: layout.audioFile, encoding: .utf8), "wav@48000")
        for kind in StemKind.allCases {
            XCTAssertEqual(try String(contentsOf: layout.stemURL(kind), encoding: .utf8), "stem@48000")
        }
        let p = try ProjectFile.load(folder: folder)
        XCTAssertEqual(p.song.sampleRate, 48000)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix(".migrating") }, [])
    }

    func testFailureMidwayKeepsPreviousFiles() async throws {
        let (env, id) = try await setUpProject(rateProfile: 48000)
        await env.importer.setFailResample(at: 2)
        _ = try await env.library.open(id: id)
        await env.library.waitForMigrations()
        let folder = try env.folder(id)
        let layout = ProjectLayout(folder: folder)
        XCTAssertEqual(try String(contentsOf: layout.audioFile, encoding: .utf8), "wav@44100")
        XCTAssertEqual(try String(contentsOf: layout.stemURL(.bass), encoding: .utf8), "stem")
        XCTAssertEqual(try ProjectFile.load(folder: folder).song.sampleRate, 44100)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix(".migrating") }, [])
    }

    func testNoMigrationWhenRateMatches() async throws {
        let (env, id) = try await setUpProject(rateProfile: 44100)
        _ = try await env.library.open(id: id)
        await env.library.waitForMigrations()
        let calls = await env.importer.resampleCalls
        XCTAssertEqual(calls, 0)
    }
}

final class RelocateTests: XCTestCase {
    private func twoProjects() async throws -> (Env, UUID, UUID) {
        let env = try await Env(autoSeparate: false)
        let a = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let b = try await env.library.importSong(from: try env.makeSource("b.mp3", content: "B"))
        return (env, a, b)
    }

    func testPointOnlyReindexes() async throws {
        let (env, _, _) = try await twoProjects()
        let other = env.dir.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try await env.library.relocate(to: other, mode: .pointOnly)
        let e = try await env.library.entries()
        XCTAssertTrue(e.isEmpty)
        XCTAssertEqual(try env.profile.load().projectsFolder, other)
        XCTAssertEqual(ProjectScanner.scan(root: env.root).found.count, 2, "no toca los originales")
    }

    func testMoveCopiesAndDeletesOriginalAtTheEnd() async throws {
        let (env, a, _) = try await twoProjects()
        let dest = env.dir.appendingPathComponent("Moved")
        let progress = ProgressBox()
        try await env.library.relocate(to: dest, mode: .move(progress: { progress.add($0) }))
        XCTAssertEqual(ProjectScanner.scan(root: dest).found.count, 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: env.root.path), [])
        XCTAssertEqual(try env.profile.load().projectsFolder, dest)
        let e = try await env.library.entries()
        XCTAssertEqual(e.count, 2)
        XCTAssertTrue(progress.values.contains(1))
        let opened = try await env.library.open(id: a)
        XCTAssertEqual(opened.id, a)
    }

    func testMoveFailureMidwayKeepsOriginal() async throws {
        let (env, _, _) = try await twoProjects()
        // Un fichero ilegible que se copia el último (orden alfabético) hace fallar la copia a mitad.
        let bad = env.root.appendingPathComponent("zzz/locked.bin")
        try FileManager.default.createDirectory(at: bad.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: bad)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: bad.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: bad.path) }

        let dest = env.dir.appendingPathComponent("Moved")
        do {
            try await env.library.relocate(to: dest, mode: .move(progress: { _ in }))
            XCTFail("debía fallar")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path), "copia parcial borrada")
        XCTAssertEqual(ProjectScanner.scan(root: env.root).found.count, 2)
        XCTAssertEqual(try env.profile.load().projectsFolder, env.root)
        let r = await env.library.root
        XCTAssertEqual(r, env.root)
    }
}

final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Double] = []
    func add(_ v: Double) { lock.lock(); _values.append(v); lock.unlock() }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return _values }
}
