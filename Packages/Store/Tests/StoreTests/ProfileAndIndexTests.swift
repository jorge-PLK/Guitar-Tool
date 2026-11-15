import XCTest
@testable import Store

final class ProfileTests: XCTestCase {
    func testDefaults() throws {
        let store = ProfileStore(url: try makeTempDir().appendingPathComponent("p/profile.json"))
        let p = try store.load()
        XCTAssertNil(p.projectsFolder)
        XCTAssertEqual(p.workingSampleRate, 44100)
        XCTAssertTrue(p.guitars.isEmpty)
    }

    func testRoundTrip() throws {
        let dir = try makeTempDir()
        let store = ProfileStore(url: dir.appendingPathComponent("p/profile.json"))
        var p = EquipmentProfile(projectsFolder: dir.appendingPathComponent("Songs"), workingSampleRate: 48000,
                                 guitars: [OwnedGuitar(name: "Strat"), OwnedGuitar(name: "EMG", pickups: .active)])
        p.setDefaultGuitar(p.guitars[1].id)
        try store.save(p)
        XCTAssertEqual(try store.load(), p)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.url.deletingLastPathComponent().path), ["profile.json"])
    }

    func testOnlyOneDefaultGuitarAndValidRate() {
        var p = EquipmentProfile(workingSampleRate: 96000, guitars: [
            OwnedGuitar(name: "A", isDefault: true), OwnedGuitar(name: "B", isDefault: true)])
        XCTAssertEqual(p.workingSampleRate, 44100)
        XCTAssertEqual(p.guitars.filter(\.isDefault).count, 1)
        XCTAssertTrue(p.guitars[0].isDefault)
        p.guitars.append(OwnedGuitar(name: "C", isDefault: true))
        XCTAssertEqual(p.guitars.filter(\.isDefault).count, 1)
        p.setDefaultGuitar(p.guitars[2].id)
        XCTAssertEqual(p.guitars.filter(\.isDefault).map(\.name), ["C"])
        p.workingSampleRate = 22050
        XCTAssertEqual(p.workingSampleRate, 44100)
    }
}

final class LibraryIndexTests: XCTestCase {
    private func writeProject(_ root: URL, name: String, title: String, updated: TimeInterval) throws -> Project {
        let folder = root.appendingPathComponent(name)
        try ProjectLayout(folder: folder).createSkeleton()
        let p = Project(song: makeSong(title: title), createdAt: Date(timeIntervalSince1970: 1000),
                        updatedAt: Date(timeIntervalSince1970: updated))
        try ProjectFile.save(p, to: folder)
        return p
    }

    func testRebuildAddsUpdatesRemovesAndSkipsCorrupt() async throws {
        let dir = try makeTempDir()
        let root = dir.appendingPathComponent("R")
        let a = try writeProject(root, name: "A", title: "A", updated: 3000)
        _ = try writeProject(root, name: "B", title: "B", updated: 2000)
        _ = try writeProject(root, name: "C", title: "C", updated: 1000)
        let index = try LibraryIndex.make(storeURL: dir.appendingPathComponent("Library.store"))

        var r = try await index.rebuild(root: root)
        XCTAssertEqual(r.added, 3)
        XCTAssertEqual(r.removed, 0)
        var entries = try await index.entries()
        XCTAssertEqual(entries.map(\.title), ["A", "B", "C"])
        XCTAssertEqual(entries[0].id, a.id)
        XCTAssertEqual(entries[0].folderName, "A")

        try FileManager.default.removeItem(at: root.appendingPathComponent("C"))
        try Data("{ no es json".utf8).write(to: root.appendingPathComponent("B/project.json"))
        r = try await index.rebuild(root: root)
        XCTAssertEqual(r.removed, 2, "C borrada y B ilegible salen del índice")
        XCTAssertEqual(r.updated, 1)
        XCTAssertEqual(r.skipped.map(\.folderName), ["B"])
        entries = try await index.entries()
        XCTAssertEqual(entries.map(\.title), ["A"])
    }

    func testUpsertAndRemove() async throws {
        let dir = try makeTempDir()
        let root = dir.appendingPathComponent("R")
        let p = try writeProject(root, name: "A", title: "A", updated: 10)
        let index = try LibraryIndex.make(storeURL: dir.appendingPathComponent("Library.store"))
        try await index.upsert(project: p, folder: root.appendingPathComponent("A"))
        var q = p
        q.song.title = "A2"
        q.stems = [Stem(kind: .bass, file: "stems/bass.wav")]
        try await index.upsert(project: q, folder: root.appendingPathComponent("A"))
        let e = try await index.entries()
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].title, "A2")
        XCTAssertEqual(e[0].stemCount, 1)
        try await index.remove(id: p.id)
        let e2 = try await index.entries()
        XCTAssertTrue(e2.isEmpty)
    }
}
