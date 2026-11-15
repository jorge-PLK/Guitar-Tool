import XCTest
@testable import Store

final class FilesTests: XCTestCase {
    func testProjectRoundTripWithAllEntities() throws {
        let dir = try makeTempDir()
        let p = makeFullProject()
        try ProjectFile.save(p, to: dir)
        XCTAssertEqual(try ProjectFile.load(folder: dir), p)
        let text = try String(contentsOf: ProjectLayout(folder: dir).projectFile, encoding: .utf8)
        XCTAssertTrue(text.contains("\"source/original.mp3\""), "rutas relativas con / sin escapar")
        XCTAssertTrue(text.contains("T"), "fechas ISO 8601")
    }

    func testNewerSchemaThrowsTypedError() throws {
        let dir = try makeTempDir()
        var p = makeFullProject()
        p.schemaVersion = 3
        try ProjectFile.save(p, to: dir)
        XCTAssertThrowsError(try ProjectFile.load(folder: dir)) {
            XCTAssertEqual($0 as? ProjectFileError, .unsupportedSchema(found: 3, supported: 2))
        }
    }

    func testV1ProjectReadsAsV2AndSavesAsV2() throws {
        let dir = try makeTempDir()
        try ProjectFile.save(makeFullProject(), to: dir)
        let file = ProjectLayout(folder: dir).projectFile
        // Reescribe como v1: versión 1 y sin la clave `study`.
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        var v1 = obj
        v1["schemaVersion"] = 1
        v1.removeValue(forKey: "study")
        try JSONSerialization.data(withJSONObject: v1).write(to: file)

        let loaded = try ProjectFile.load(folder: dir)
        XCTAssertEqual(loaded.schemaVersion, 2)
        XCTAssertEqual(loaded.study, StudyState())
        try ProjectFile.save(loaded, to: dir)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        XCTAssertEqual(saved["schemaVersion"] as? Int, 2)
        XCTAssertNotNil(saved["study"])
    }

    func testV2StudyStateRoundTrip() throws {
        let dir = try makeTempDir()
        var p = makeFullProject()
        p.study = StudyState(
            chordOverrides: [ChordOverride(start: 1.5, end: 3, index: 15)],
            keyOverride: "A minor",
            loops: [Loop(name: "Solo", start: 10, end: 20.5)],
            mixer: [StemMix(kind: .guitar, gainDB: -6, muted: true), StemMix(kind: .vocals, solo: true)],
            player: PlayerSettings(rate: 0.7, transpose: -2, fineCents: 15, capo: 3, metronomeOn: true, metronomeGainDB: -4))
        try ProjectFile.save(p, to: dir)
        XCTAssertEqual(try ProjectFile.load(folder: dir), p)
        XCTAssertEqual(try ProjectFile.load(folder: dir).schemaVersion, 2)
    }

    func testCleanerRemovesAnalysisCache() throws {
        let dir = try makeTempDir()
        let l = ProjectLayout(folder: dir)
        try l.createSkeleton()
        XCTAssertEqual(l.analysisCache.path, dir.appendingPathComponent("cache/analysis.json").path)
        try Data("{}".utf8).write(to: l.analysisCache)
        let p = makeFullProject()
        try ProjectFile.save(p, to: dir)
        let plan = ProjectCleaner.plan(folder: dir, project: p)
        XCTAssertTrue(plan.urls.contains { $0.lastPathComponent == "analysis.json" })
        try ProjectCleaner.execute(plan)
        XCTAssertFalse(FileManager.default.fileExists(atPath: l.analysisCache.path))
    }

    func testAtomicWriteLeavesNoTemporaries() throws {
        let dir = try makeTempDir()
        for _ in 0..<3 { try ProjectFile.save(makeFullProject(), to: dir) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["project.json"])
    }

    func testMissingOptionalCollectionsDecode() throws {
        let dir = try makeTempDir()
        var p = makeFullProject()
        p.stems = []
        try ProjectFile.save(p, to: dir)
        var text = try String(contentsOf: ProjectLayout(folder: dir).projectFile, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"videos\"", with: "\"videosX\"")
        try text.write(to: ProjectLayout(folder: dir).projectFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(try ProjectFile.load(folder: dir).videos, [])
    }

    func testLayoutAndSkeleton() throws {
        let dir = try makeTempDir()
        let l = ProjectLayout(folder: dir)
        try l.createSkeleton()
        XCTAssertEqual(l.audioFile.path, dir.appendingPathComponent("audio/song.wav").path)
        XCTAssertEqual(l.stemsPartialDir.path, dir.appendingPathComponent("stems/.partial").path)
        XCTAssertEqual(l.stemURL(.guitar).lastPathComponent, "guitar.wav")
        for d in [l.sourceDir, l.stemsDir, l.takesDir, l.videoDir, l.rigsDir, l.cacheDir] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: d.path), d.lastPathComponent)
        }
    }

    func testFolderNaming() throws {
        XCTAssertEqual(FolderNaming.baseName(title: "Título", artist: "Los Ñandúes"), "Los Ñandúes - Título")
        XCTAssertEqual(FolderNaming.baseName(title: "A/B: C\\D\u{0007}", artist: nil), "AB CD")
        XCTAssertEqual(FolderNaming.baseName(title: "T", artist: "AC/DC"), "ACDC - T")
        XCTAssertEqual(FolderNaming.baseName(title: "  ", artist: nil), "Sin título")
        let root = try makeTempDir()
        for expected in ["X", "X (2)", "X (3)"] {
            let n = FolderNaming.uniqueName(base: "X", in: root)
            XCTAssertEqual(n, expected)
            try FileManager.default.createDirectory(at: root.appendingPathComponent(n), withIntermediateDirectories: false)
        }
    }

    func testCleanerPlanExecuteAndProtection() throws {
        let dir = try makeTempDir()
        let l = ProjectLayout(folder: dir)
        try l.createSkeleton()
        let fm = FileManager.default
        func touch(_ rel: String) throws {
            let u = l.url(relative: rel)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 4096).write(to: u)
        }
        for f in ["source/original.mp3", "audio/song.wav", "stems/drums.wav", "stems/.partial/bass.wav",
                  "cache/x.bin", "takes/live.wav", "takes/dead-di.wav", "takes/dead-mic.wav", "rigs/r.rig", "video/v.mov"] {
            try touch(f)
        }
        var p = makeFullProject()
        p.stems = [Stem(kind: .drums, file: "stems/drums.wav")]
        p.takes = [Take(diFile: "takes/live.wav", discarded: false),
                   Take(diFile: "takes/dead-di.wav", micFile: "takes/dead-mic.wav", discarded: true)]
        try ProjectFile.save(p, to: dir)

        let plan = ProjectCleaner.plan(folder: dir, project: p)
        let base = dir.resolvingSymlinksInPath().path + "/"
        let rel = Set(plan.urls.map { $0.resolvingSymlinksInPath().path.replacingOccurrences(of: base, with: "") })
        XCTAssertEqual(rel, ["stems/drums.wav", "stems/.partial", "audio/song.wav", "cache/x.bin",
                             "takes/dead-di.wav", "takes/dead-mic.wav"])
        XCTAssertGreaterThan(plan.bytes, 0)

        try ProjectCleaner.execute(plan)
        for protected in ["source/original.mp3", "takes/live.wav", "rigs/r.rig", "video/v.mov", "project.json"] {
            XCTAssertTrue(fm.fileExists(atPath: l.url(relative: protected).path), protected)
        }
        for gone in rel { XCTAssertFalse(fm.fileExists(atPath: l.url(relative: gone).path), gone) }
        let after = try ProjectFile.load(folder: dir)
        XCTAssertEqual(after.stems, [])
        XCTAssertEqual(after.separation.state, .none)
        XCTAssertEqual(after.takes.count, 1)
        XCTAssertFalse(after.takes[0].discarded)
    }

    func testDiskSize() throws {
        let dir = try makeTempDir()
        try Data(repeating: 7, count: 100_000).write(to: dir.appendingPathComponent("a.bin"))
        XCTAssertGreaterThanOrEqual(DiskSize.allocatedBytes(of: dir), 100_000)
        XCTAssertEqual(DiskSize.allocatedBytes(of: dir.appendingPathComponent("nope")), 0)
    }
}
