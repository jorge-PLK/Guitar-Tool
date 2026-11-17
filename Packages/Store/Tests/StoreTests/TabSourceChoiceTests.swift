import XCTest
@testable import Store

final class TabSourceChoiceTests: XCTestCase {
    func testRoundTripSongsterrAndAutomatic() throws {
        let dir = try makeTempDir("tabsource")
        var p = makeFullProject()
        p.tabSource = .songsterr(songId: 7, revisionId: 900, pairings: [
            TabStemPairing(stemID: "guitar-left", partId: 0), TabStemPairing(stemID: "bass", partId: 1),
            TabStemPairing(stemID: "drums", partId: nil)])
        try ProjectFile.save(p, to: dir)
        let r = try ProjectFile.load(folder: dir)
        XCTAssertEqual(r, p)
        XCTAssertEqual(r.tabSource?.partId(forStem: "bass"), 1)
        XCTAssertNil(r.tabSource?.partId(forStem: "drums"))
        XCTAssertNil(r.tabSource?.partId(forStem: "guitar-right"))
        p.tabSource = .automatic
        try ProjectFile.save(p, to: dir)
        XCTAssertEqual(try ProjectFile.load(folder: dir).tabSource, .automatic)
        XCTAssertNil(TabSourceChoice.automatic.partId(forStem: "bass"))
    }

    func testProjectWithoutFieldDecodesAsNil() throws {
        let dir = try makeTempDir("tabsource-old")
        var p = makeFullProject()
        p.tabSource = .automatic
        try ProjectFile.save(p, to: dir)
        let url = dir.appendingPathComponent("project.json")
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertNotNil(obj["tabSource"])
        obj.removeValue(forKey: "tabSource")
        try JSONSerialization.data(withJSONObject: obj).write(to: url)
        XCTAssertNil(try ProjectFile.load(folder: dir).tabSource)
    }

    func testSaveTabSourceOnlyTouchesThatField() async throws {
        let env = try await Env()
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "a"))
        await env.library.waitForSeparations()
        let before = try await env.project(id)
        let choice = TabSourceChoice.songsterr(songId: 1, revisionId: 2, pairings: [TabStemPairing(stemID: "bass", partId: 3)])
        try await env.library.saveTabSource(choice, for: id)
        var after = try await env.project(id)
        XCTAssertEqual(after.tabSource, choice)
        after.tabSource = nil
        after.updatedAt = before.updatedAt
        XCTAssertEqual(after, before)
        try await env.library.saveTabSource(nil, for: id)
        let cleared = try await env.project(id)
        XCTAssertNil(cleared.tabSource)
    }

    func testSongsterrCacheDirIsUnderCache() {
        let l = ProjectLayout(folder: URL(fileURLWithPath: "/tmp/p"))
        XCTAssertEqual(l.songsterrCacheDir(songId: 7, revisionId: 9).path, "/tmp/p/cache/songsterr/7/9")
        // La rejilla de Songsterr va con la tablatura, fuera de `cache/`.
        XCTAssertEqual(l.tabSongsterrGridFile.path, "/tmp/p/tab/songsterr-grid.json")
    }

    /// Solista por secciones de solo: campo aditivo, el JSON de antes (sin `solos`) sigue leyéndose igual.
    func testSoloPairingsAreAdditive() throws {
        let old = Data(#"{"kind":"songsterr","songId":7,"revisionId":9,"pairings":[{"stemID":"guitar-lead","partId":1}]}"#.utf8)
        let decoded = try JSONDecoder().decode(TabSourceChoice.self, from: old)
        XCTAssertEqual(decoded, .songsterr(songId: 7, revisionId: 9, pairings: [TabStemPairing(stemID: "guitar-lead", partId: 1)]))
        XCTAssertTrue(decoded.importsSongsterr(forStem: "guitar-lead"))

        let solos = [TabSoloPairing(start: 158.3, end: 183.5, partId: 0, confidence: 0.41),
                     TabSoloPairing(start: 200, end: 210, partId: nil, confidence: nil)]
        let choice = TabSourceChoice.songsterr(songId: 7, revisionId: 9, pairings: [
            TabStemPairing(stemID: "guitar-left", partId: 1), TabStemPairing(stemID: "guitar-lead", partId: nil, solos: solos),
            TabStemPairing(stemID: "guitar-right", partId: nil, solos: [solos[1]])])
        let data = try JSONEncoder().encode(choice)
        XCTAssertEqual(try JSONDecoder().decode(TabSourceChoice.self, from: data), choice)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(TabStemPairing(stemID: "bass", partId: 2)), as: UTF8.self)
            .contains("solos"), "sin secciones no se escribe el campo")
        XCTAssertNil(choice.partId(forStem: "guitar-lead"))
        XCTAssertTrue(choice.importsSongsterr(forStem: "guitar-lead"), "una sección con pista basta")
        XCTAssertFalse(choice.importsSongsterr(forStem: "guitar-right"), "secciones sin pista = automática")
        XCTAssertTrue(choice.importsSongsterr(forStem: "guitar-left"))
        XCTAssertFalse(TabSourceChoice.automatic.importsSongsterr(forStem: "guitar-left"))
    }
}
