import Foundation
import XCTest
@testable import Store

final class MontageTests: XCTestCase {
    private func sampleMontage(take: UUID) -> MontageState {
        MontageState(layout: .grid, singleRhythmPartID: UUID(), caption: false,
                     export: MontageExport(codec: .h264, resolution: .hd720, fps: 25, normalize: false, trackWAVs: false),
                     framing: [take: TakeFraming(mode: .follow, manualBox: NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6),
                                                 followZoom: 1.4, followOffset: FramingOffset(x: 0.05, y: -0.02))])
    }

    func testMontageRoundTrip() throws {
        let take = UUID()
        var p = makeFullProject()
        p.montage = sampleMontage(take: take)
        let dir = try makeTempDir()
        try ProjectFile.save(p, to: dir)
        let back = try ProjectFile.load(folder: dir)
        XCTAssertEqual(back.montage, p.montage)
        XCTAssertEqual(back.schemaVersion, Project.currentSchemaVersion)
        XCTAssertEqual(back.montage?.framing(for: take).mode, .follow)
        XCTAssertEqual(back.montage?.framing(for: UUID()), TakeFraming())
    }

    func testProjectsWithoutMontageStillLoad() throws {
        // Anterior a la Fase 6: sin `recording` ni `montage`.
        let dir = try makeTempDir()
        try ProjectFile.save(makeFullProject(), to: dir)
        var p = try ProjectFile.load(folder: dir)
        XCTAssertNil(p.montage)
        XCTAssertNil(p.recording)

        // De la Fase 6: con `recording`, sin `montage`.
        p.recording = RecordingState(parts: [RecordingPart(name: "Ritmo", replaces: .rhythm)], countIn: false)
        try ProjectFile.save(p, to: dir)
        let url = ProjectLayout(folder: dir).projectFile
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertNil(json["montage"])
        let back = try ProjectFile.load(folder: dir)
        XCTAssertNil(back.montage)
        XCTAssertEqual(back.recording?.parts.count, 1)
        XCTAssertEqual(back.montageOrInitial(), MontageState())
    }

    func testTolerantDecoding() throws {
        let s = try JSONDecoder().decode(MontageState.self, from: Data(#"{"layout":"stack","framing":{"no-uuid":{}}}"#.utf8))
        XCTAssertEqual(s.layout, .stack)
        XCTAssertTrue(s.caption)
        XCTAssertTrue(s.export.normalize)
        XCTAssertTrue(s.export.trackWAVs)
        XCTAssertEqual(s.export.fps, 30)
        XCTAssertTrue(s.framing.isEmpty)
        let unknown = try JSONDecoder().decode(MontageState.self, from: Data(#"{"layout":"cube"}"#.utf8))
        XCTAssertEqual(unknown.layout, .side)
        let f = try JSONDecoder().decode(TakeFraming.self, from: Data("{}".utf8))
        XCTAssertEqual(f, TakeFraming())
        XCTAssertEqual(f.mode, .fixed)
        XCTAssertEqual(f.followZoom, 1)
    }

    func testInitialFromVideoSettings() {
        XCTAssertEqual(MontageState.initial(from: nil), MontageState())
        XCTAssertEqual(MontageState().layout, .side)
        let v = VideoSettings(fps: 60, export: VideoExportDefaults(codec: .h264, resolution: .hd720, titleOverlay: false,
                                                                    exportStemWAVs: false))
        let m = MontageState.initial(from: v)
        XCTAssertEqual(m.export, MontageExport(codec: .h264, resolution: .hd720, fps: 60, normalize: true, trackWAVs: false))
        XCTAssertFalse(m.caption)
    }

    func testCutGapsRoundTripAndDefault() throws {
        XCTAssertFalse(MontageState().cutGaps)
        let old = try JSONDecoder().decode(MontageState.self, from: Data(#"{"layout":"grid"}"#.utf8))
        XCTAssertFalse(old.cutGaps)
        var m = MontageState(cutGaps: true)
        let back = try JSONDecoder().decode(MontageState.self, from: JSONEncoder().encode(m))
        XCTAssertTrue(back.cutGaps)
        XCTAssertEqual(back, m)
        m.cutGaps = false
        XCTAssertFalse(try JSONDecoder().decode(MontageState.self, from: JSONEncoder().encode(m)).cutGaps)
    }

    func testLimiterRoundTripAndDefault() throws {
        XCTAssertTrue(MontageExport().limiter)
        let old = try JSONDecoder().decode(MontageExport.self, from: Data(#"{"fps":25}"#.utf8))
        XCTAssertTrue(old.limiter)
        let m = MontageExport(limiter: false)
        let back = try JSONDecoder().decode(MontageExport.self, from: JSONEncoder().encode(m))
        XCTAssertFalse(back.limiter)
        XCTAssertEqual(back, m)
    }

    func testFramingReset() {
        var f = TakeFraming(mode: .follow, manualBox: NormalizedRect(x: 0, y: 0, width: 1, height: 1), followZoom: 2,
                            followOffset: FramingOffset(x: 1, y: 1))
        f.reset()
        XCTAssertEqual(f, TakeFraming(mode: .follow))
    }

    func testLayoutPaths() {
        let l = ProjectLayout(folder: URL(fileURLWithPath: "/tmp/Artista - Tema"))
        let id = UUID()
        XCTAssertEqual(l.framingCacheURL(takeId: id).path, "/tmp/Artista - Tema/cache/framing/\(id.uuidString).json")
        XCTAssertEqual(l.montageVideoURL(layout: .side).path, "/tmp/Artista - Tema/video/Artista - Tema-side.mov")
        XCTAssertEqual(l.montageTracksDirectory(layout: .stack).path, "/tmp/Artista - Tema/video/Artista - Tema-stack-pistas")
        XCTAssertEqual(l.montageVideoURL(layout: .single, songName: "A/B: C").lastPathComponent, "AB C-single.mov")
    }

    func testDeleteTakeRemovesFraming() async throws {
        let env = try await Env(autoSeparate: false)
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let layout = ProjectLayout(folder: try env.folder(id))
        let t1 = Take(), t2 = Take()
        try await env.library.saveTakes(id: id, [t1, t2])
        var m = sampleMontage(take: t1.id)
        m.framing[t2.id] = TakeFraming(mode: .follow)
        try await env.library.saveMontage(id: id, m)
        for t in [t1, t2] {
            try FileManager.default.createDirectory(at: layout.framingCacheURL(takeId: t.id).deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: layout.framingCacheURL(takeId: t.id))
            try FileManager.default.createDirectory(at: layout.takeDirectory(takeId: t.id), withIntermediateDirectories: true)
        }
        var saved = try await env.project(id)
        XCTAssertEqual(saved.montage?.framing.count, 2)

        try await env.library.deleteTake(projectID: id, takeID: t2.id)
        saved = try await env.project(id)
        XCTAssertEqual(Set(saved.montage?.framing.keys ?? [:].keys), [t1.id])
        XCTAssertEqual(saved.montage?.layout, .grid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.framingCacheURL(takeId: t2.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.framingCacheURL(takeId: t1.id).path))
    }

    func testCleanerTreatsFramingCacheAsCache() throws {
        let dir = try makeTempDir()
        let layout = ProjectLayout(folder: dir)
        try layout.createSkeleton()
        let id = UUID()
        try FileManager.default.createDirectory(at: layout.framingCacheURL(takeId: id).deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: layout.framingCacheURL(takeId: id))
        var p = makeFullProject()
        p.montage = sampleMontage(take: id)
        let plan = ProjectCleaner.plan(folder: dir, project: p)
        XCTAssertTrue(plan.urls.contains { $0.standardizedFileURL.path.hasPrefix(layout.cacheDir.standardizedFileURL.path + "/framing") })
        try ProjectCleaner.execute(plan)
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.framingCacheURL(takeId: id).path))
        XCTAssertEqual(try ProjectFile.load(folder: dir).montage, p.montage)
    }
}
