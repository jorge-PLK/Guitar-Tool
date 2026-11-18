import XCTest
@testable import Store

final class ProfileTests: XCTestCase {
    func testDefaults() throws {
        let store = ProfileStore(url: try makeTempDir().appendingPathComponent("p/profile.json"))
        let p = try store.load()
        XCTAssertNil(p.projectsFolder)
        XCTAssertEqual(p.workingSampleRate, 44100)
    }

    func testRoundTrip() throws {
        let dir = try makeTempDir()
        let store = ProfileStore(url: dir.appendingPathComponent("p/profile.json"))
        let p = EquipmentProfile(projectsFolder: dir.appendingPathComponent("Songs"), workingSampleRate: 48000)
        try store.save(p)
        XCTAssertEqual(try store.load(), p)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.url.deletingLastPathComponent().path), ["profile.json"])
    }

    func testMasterGainDefaultsToZeroAndRoundTrips() throws {
        let dir = try makeTempDir()
        let store = ProfileStore(url: dir.appendingPathComponent("p/profile.json"))
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"workingSampleRate":48000,"guitars":[]}"#.utf8).write(to: store.url)   // perfil anterior a P8
        var p = try store.load()
        XCTAssertEqual(p.masterGainDB, 0)
        XCTAssertEqual(p.workingSampleRate, 48000)
        p.masterGainDB = -4.5
        try store.save(p)
        XCTAssertEqual(try store.load().masterGainDB, -4.5)
    }

    func testValidRate() {
        var p = EquipmentProfile(workingSampleRate: 96000)
        XCTAssertEqual(p.workingSampleRate, 44100)
        p.workingSampleRate = 22050
        XCTAssertEqual(p.workingSampleRate, 44100)
    }

    /// Fase 7b, punto 10: las guitarras del perfil se ignoran al leer y desaparecen al guardar; el resto, intacto.
    func testProfileWithGuitarsLoadsAndIsRewrittenWithoutThem() throws {
        let dir = try makeTempDir()
        let store = ProfileStore(url: dir.appendingPathComponent("p/profile.json"))
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let old = #"""
        {"workingSampleRate":48000,"masterGainDB":-3.5,"projectsFolder":"file:///tmp/Songs/",
         "audio":{"outputDeviceUID":"X","bufferFrames":256},
         "guitars":[{"id":"6F1C2D3E-0000-4000-8000-000000000001","name":"Strat","pickups":"passive","isDefault":true},
                    {"id":"6F1C2D3E-0000-4000-8000-000000000002","name":"EMG","pickups":"active","isDefault":false}]}
        """#
        try Data(old.utf8).write(to: store.url)
        let p = try store.load()
        XCTAssertEqual(p.workingSampleRate, 48000)
        XCTAssertEqual(p.masterGainDB, -3.5)
        XCTAssertEqual(p.projectsFolder?.path, "/tmp/Songs")
        XCTAssertEqual(p.audio?.outputDeviceUID, "X")
        XCTAssertEqual(p.audio?.bufferFrames, 256)
        try store.save(p)
        let text = try String(contentsOf: store.url, encoding: .utf8)
        XCTAssertFalse(text.contains("guitars"))
        XCTAssertFalse(text.contains("Strat"))
        XCTAssertEqual(try store.load(), p)
    }

    /// Fase 7b, punto 10: un `project.json` con `guitarId` en las tomas se abre y se guarda sin él.
    func testProjectWithTakeGuitarIdOpensAndIsSavedWithoutIt() throws {
        let folder = try makeTempDir().appendingPathComponent("Song")
        try ProjectLayout(folder: folder).createSkeleton()
        var project = makeFullProject()
        try ProjectFile.save(project, to: folder)
        let url = ProjectLayout(folder: folder).projectFile
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var takes = try XCTUnwrap(root["takes"] as? [[String: Any]])
        XCTAssertFalse(takes.isEmpty)
        for i in takes.indices { takes[i]["guitarId"] = "6F1C2D3E-0000-4000-8000-000000000001" }
        root["takes"] = takes
        try JSONSerialization.data(withJSONObject: root).write(to: url)

        project = try ProjectFile.load(folder: folder)
        XCTAssertEqual(project.takes.count, takes.count)
        try ProjectFile.save(project, to: folder)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("guitarId"))
        XCTAssertEqual(try ProjectFile.load(folder: folder).takes, project.takes)
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
