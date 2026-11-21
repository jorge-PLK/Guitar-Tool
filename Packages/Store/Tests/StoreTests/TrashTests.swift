import XCTest
@testable import Store

final class TrashProjectTests: XCTestCase {
    private struct NoTrash: Error {}

    /// Papelera simulada: mueve la carpeta a un directorio temporal propio.
    private func fakeTrash(_ env: Env) throws -> (@Sendable (URL) throws -> Void, URL) {
        let bin = env.dir.appendingPathComponent("FakeTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        return ({ url in
            try FileManager.default.moveItem(at: url, to: bin.appendingPathComponent(url.lastPathComponent))
        }, bin)
    }

    func testTrashRemovesFromIndexAndDisk() async throws {
        let env = try await Env(autoSeparate: false)
        let (trasher, bin) = try fakeTrash(env)
        await env.library.setProjectTrasher(trasher)
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let other = try await env.library.importSong(from: try env.makeSource("b.mp3", content: "B"))
        let folder = try env.folder(id)
        let log = EventLog()
        let task = log.collect(env.library.events)

        try await env.library.trashProject(id: id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bin.appendingPathComponent(folder.lastPathComponent).path))
        let ids = try await env.library.entries().map(\.id)
        XCTAssertEqual(ids, [other])
        let seen = await waitUntil { await log.events.contains(.trashed(id)) }
        XCTAssertTrue(seen)
        task.cancel()
    }

    func testTrashFailureLeavesEverythingIntact() async throws {
        let env = try await Env(autoSeparate: false)
        await env.library.setProjectTrasher { _ in throw NoTrash() }
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let folder = try env.folder(id)

        do {
            try await env.library.trashProject(id: id)
            XCTFail("debía fallar")
        } catch is NoTrash {}

        XCTAssertTrue(FileManager.default.fileExists(atPath: ProjectLayout(folder: folder).projectFile.path))
        let ids = try await env.library.entries().map(\.id)
        XCTAssertEqual(ids, [id])
    }

    func testTrashCancelsQueuedSeparationFirst() async throws {
        let env = try await Env()
        await env.separator.setBehavior(.hang)
        let (trasher, _) = try fakeTrash(env)
        await env.library.setProjectTrasher(trasher)
        let running = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let queued = try await env.library.importSong(from: try env.makeSource("b.mp3", content: "B"))
        _ = await waitUntil { (try? await env.project(running))?.separation.state == .running }

        try await env.library.trashProject(id: queued)
        try await env.library.trashProject(id: running)
        await env.library.waitForSeparations()

        let remaining = try await env.library.entries()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(ProjectScanner.scan(root: env.root).found.isEmpty)
    }

    func testTrashUnknownIdThrows() async throws {
        let env = try await Env(autoSeparate: false)
        let (trasher, _) = try fakeTrash(env)
        await env.library.setProjectTrasher(trasher)
        let ghost = UUID()
        do {
            try await env.library.trashProject(id: ghost)
            XCTFail("debía fallar")
        } catch let e as LibraryError {
            XCTAssertEqual(e, .projectNotFound(ghost))
        }
    }
}

final class DeleteProjectTests: XCTestCase {
    private struct NoDelete: Error {}

    func testDeleteRemovesFromDiskAndIndex() async throws {
        let env = try await Env(autoSeparate: false)
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let other = try await env.library.importSong(from: try env.makeSource("b.mp3", content: "B"))
        let folder = try env.folder(id)
        try await env.library.deleteProject(id: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        let ids = try await env.library.entries().map(\.id)
        XCTAssertEqual(ids, [other])
    }

    func testDeleteFailureLeavesIndexIntact() async throws {
        let env = try await Env(autoSeparate: false)
        await env.library.setProjectDeleter { _ in throw NoDelete() }
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        do { try await env.library.deleteProject(id: id); XCTFail("debía fallar") } catch is NoDelete {}
        let ids = try await env.library.entries().map(\.id)
        XCTAssertEqual(ids, [id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: ProjectLayout(folder: try env.folder(id)).projectFile.path))
    }

    func testDeleteCancelsQueuedSeparation() async throws {
        let env = try await Env()
        await env.separator.setBehavior(.hang)
        let running = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let queued = try await env.library.importSong(from: try env.makeSource("b.mp3", content: "B"))
        _ = await waitUntil { (try? await env.project(running))?.separation.state == .running }
        let qf = try env.folder(queued)
        try await env.library.deleteProject(id: queued)
        XCTAssertFalse(FileManager.default.fileExists(atPath: qf.path))
        let rf = try env.folder(running)
        try await env.library.deleteProject(id: running)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rf.path))
        await env.library.waitForSeparations()
        let ids = try await env.library.entries().map(\.id)
        XCTAssertEqual(ids, [])
    }

    func testDeleteUnknownIDThrows() async throws {
        let env = try await Env(autoSeparate: false)
        let bogus = UUID()
        do { try await env.library.deleteProject(id: bogus); XCTFail() }
        catch { XCTAssertEqual(error as? LibraryError, .projectNotFound(bogus)) }
    }

    func testSafeguardRefusesFolderWithoutProjectJSON() async throws {
        let env = try await Env(autoSeparate: false)
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let folder = try env.folder(id)
        try FileManager.default.removeItem(at: ProjectLayout(folder: folder).projectFile)
        // El índice aún apunta a la carpeta; sin project.json no se borra.
        do { try await env.library.deleteProject(id: id); XCTFail("debía negarse") }
        catch { XCTAssertNotNil(error) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func testSafeguardRefusesFolderOutsideRoot() async throws {
        let env = try await Env(autoSeparate: false)
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        // Una carpeta de proyecto válida pero anidada (no hija directa de la raíz) tampoco se borra.
        let folder = try env.folder(id)
        let nestedParent = env.root.appendingPathComponent("Grupo", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedParent, withIntermediateDirectories: true)
        let nested = nestedParent.appendingPathComponent(folder.lastPathComponent)
        try FileManager.default.moveItem(at: folder, to: nested)
        try await env.index.upsert(project: try ProjectFile.load(folder: nested), folder: nested)
        do { try await env.library.deleteProject(id: id); XCTFail("debía negarse") }
        catch { XCTAssertNotNil(error) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }
}

final class UpdateSongInfoTests: XCTestCase {
    func testChangesAndPersists() async throws {
        let env = try await Env(autoSeparate: false)
        await env.importer.setMeta(title: "Artista", artist: "Titulo")
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let folder = try env.folder(id)
        let before = try ProjectFile.load(folder: folder)
        try await env.library.updateSongInfo(id: id, title: "  Titulo ", artist: " Artista  ")
        let p = try ProjectFile.load(folder: folder)
        XCTAssertEqual(p.song.title, "Titulo")
        XCTAssertEqual(p.song.artist, "Artista")
        XCTAssertEqual(p.song.source, before.song.source)
        XCTAssertEqual(p.song.origin, before.song.origin)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path), "la carpeta no se renombra")
        let e = try await env.library.entries().first { $0.id == id }
        XCTAssertEqual(e?.title, "Titulo")
        XCTAssertEqual(e?.artist, "Artista")
        XCTAssertEqual(e?.folderName, folder.lastPathComponent)
    }

    func testEmptyTitleDoesNotSaveAndEmptyArtistIsNil() async throws {
        let env = try await Env(autoSeparate: false)
        await env.importer.setMeta(title: "T", artist: "A")
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        do { try await env.library.updateSongInfo(id: id, title: "   ", artist: "X"); XCTFail() }
        catch { XCTAssertEqual(error as? LibraryError, .emptyTitle) }
        let same = try await env.project(id)
        XCTAssertEqual(same.song.title, "T")
        XCTAssertEqual(same.song.artist, "A")
        try await env.library.updateSongInfo(id: id, title: "T2", artist: "  ")
        let p = try await env.project(id)
        XCTAssertNil(p.song.artist)
        let e = try await env.library.entries().first { $0.id == id }
        XCTAssertNil(e?.artist)
    }

    func testUnknownID() async throws {
        let env = try await Env(autoSeparate: false)
        let bogus = UUID()
        do { try await env.library.updateSongInfo(id: bogus, title: "T", artist: nil); XCTFail() }
        catch { XCTAssertEqual(error as? LibraryError, .projectNotFound(bogus)) }
    }
}

#if os(Windows)
/// Papelera de reciclaje real de Windows (SHFileOperationW). Usa nombres únicos en una carpeta temporal.
final class WindowsRecycleBinTests: XCTestCase {
    func testFileAndFolderLeaveTheirPath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tf-recycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("fichero-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        let folder = dir.appendingPathComponent("carpeta-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data("y".utf8).write(to: folder.appendingPathComponent("sub/a.txt"))

        try windowsMoveToRecycleBin(file)
        try windowsMoveToRecycleBin(folder)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testMissingItemThrows() {
        let ghost = FileManager.default.temporaryDirectory.appendingPathComponent("tf-no-existe-\(UUID().uuidString)")
        XCTAssertThrowsError(try windowsMoveToRecycleBin(ghost))
    }
}
#endif
