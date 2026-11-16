import XCTest
@testable import Store

final class TabSourcesTests: XCTestCase {
    private func project(guitars: [Guitar], stems: [Stem]) -> Project {
        var p = makeFullProject()
        p.guitars = guitars
        p.stems = stems
        return p
    }

    private let allStems = [Stem(kind: .guitar, file: "stems/guitar.wav"), Stem(kind: .bass, file: "stems/bass.wav"),
                            Stem(kind: .drums, file: "stems/drums.wav"), Stem(kind: .vocals, file: "stems/vocals.wav")]

    func testOneSourcePerSeparatedGuitarWithItsNameThenBassAndDrums() {
        let p = project(guitars: [Guitar(role: .left, name: "Robe", file: "stems/guitar_L.wav"),
                                  Guitar(role: .right, file: "stems/guitar_R.wav"),
                                  Guitar(role: .lead, file: "stems/guitar_lead.wav")], stems: allStems)
        let s = p.tabSources { _ in true }
        XCTAssertEqual(s.map(\.id), ["guitar-left", "guitar-right", "guitar-lead", "bass", "drums"])
        XCTAssertEqual(s.map(\.name), ["Robe", "Guitarra der.", "Guitarra solista", "Bajo", "Batería"])
        XCTAssertEqual(s[0].playerTrackID, "guitar_L")
        XCTAssertEqual(s[3].relativePath, "stems/bass.wav")
    }

    func testPlainGuitarStemWhenNoSeparatedTracksAndEmptyStemsAreSkipped() {
        var stems = allStems
        stems[1].isEmpty = true
        let p = project(guitars: [Guitar(role: .rhythm)], stems: stems)   // sin fichero: no hay pista
        let s = p.tabSources { _ in true }
        XCTAssertEqual(s.map(\.id), ["guitar", "drums"])
        XCTAssertEqual(s[0].playerTrackID, "guitar")
    }

    func testMissingFilesAreSkipped() {
        let p = project(guitars: [], stems: allStems)
        XCTAssertEqual(p.tabSources { $0 != "stems/drums.wav" }.map(\.id), ["guitar", "bass"])
    }

    func testTabPathsAndCleanup() throws {
        let dir = try makeTempDir("tabclean")
        let layout = ProjectLayout(folder: dir)
        XCTAssertEqual(layout.tabScoreFile.path, dir.appendingPathComponent("tab/score.json").path)
        XCTAssertEqual(layout.tabSynthURL(trackID: "bass").path, dir.appendingPathComponent("cache/tab/synth_bass.wav").path)
        try FileManager.default.createDirectory(at: layout.tabDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: layout.tabCacheDir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: layout.tabScoreFile)
        try Data("x".utf8).write(to: layout.tabSynthURL(trackID: "bass"))
        let plan = ProjectCleaner.plan(folder: dir, project: makeFullProject())
        let paths = plan.urls.map { $0.resolvingSymlinksInPath().path }
        XCTAssertTrue(paths.contains(layout.tabCacheDir.resolvingSymlinksInPath().path))
        let tabRoot = layout.tabDir.resolvingSymlinksInPath().path
        XCTAssertFalse(paths.contains { $0 == tabRoot || $0.hasPrefix(tabRoot + "/") })
        try ProjectCleaner.execute(plan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.tabScoreFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.tabCacheDir.path))
    }
}
