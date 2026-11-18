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

    func testContainerDefaultRoundTripAndURL() throws {
        XCTAssertEqual(MontageExport().container, .mov)
        let old = try JSONDecoder().decode(MontageExport.self, from: Data(#"{"fps":25}"#.utf8))
        XCTAssertEqual(old.container, .mov)
        let m = MontageExport(container: .mp4)
        let back = try JSONDecoder().decode(MontageExport.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(back.container, .mp4)
        XCTAssertEqual(back, m)
        let l = ProjectLayout(folder: URL(fileURLWithPath: "/tmp/Artista - Tema"))
        XCTAssertEqual(l.montageVideoURL(layout: .side, container: .mp4).path, "/tmp/Artista - Tema/video/Artista - Tema-side.mp4")
        XCTAssertEqual(l.montageVideoURL(layout: .side, container: .mov).path, "/tmp/Artista - Tema/video/Artista - Tema-side.mov")
        XCTAssertEqual(l.montageVideoURL(layout: .single, songName: "A/B: C", container: .mp4).lastPathComponent, "AB C-single.mp4")
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

final class MontagePartOrderTests: XCTestCase {
    func testOldStateWithoutOrderDecodes() throws {
        let json = #"{"layout":"side","caption":true,"cutGaps":false}"#
        let s = try JSONDecoder().decode(MontageState.self, from: Data(json.utf8))
        XCTAssertEqual(s.partOrder, [])
        let ids = [UUID(), UUID(), UUID()]
        XCTAssertEqual(s.effectiveOrder(of: ids), ids)
    }

    func testOrderRoundTripAndNoKeyWhenEmpty() throws {
        let a = UUID(), b = UUID()
        var s = MontageState()
        s.partOrder = [b, a]
        let back = try JSONDecoder().decode(MontageState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
        let empty = String(decoding: try JSONEncoder().encode(MontageState()), as: UTF8.self)
        XCTAssertFalse(empty.contains("partOrder"))
    }

    func testEffectiveOrderNewPartsLastAndVanishedIgnored() {
        let a = UUID(), b = UUID(), c = UUID(), gone = UUID()
        var s = MontageState()
        s.partOrder = [c, gone, a, c]
        XCTAssertEqual(s.effectiveOrder(of: [a, b, c]), [c, a, b])
    }
}

final class MontageSingleCutTests: XCTestCase {
    private let a = UUID(), b = UUID()

    func testOldStateDecodesWithDefaults() throws {
        let s = try JSONDecoder().decode(MontageState.self, from: Data(#"{"layout":"single","caption":true}"#.utf8))
        XCTAssertTrue(s.showPartLabels)
        XCTAssertFalse(s.keepVideoAspect)
        XCTAssertEqual(s.singleCuts, [])
        let json = String(decoding: try JSONEncoder().encode(MontageState()), as: UTF8.self)
        XCTAssertFalse(json.contains("singleCuts"))
    }

    func testRoundTripAllNewFields() throws {
        var s = MontageState(layout: .singleLandscape, showPartLabels: false, keepVideoAspect: true,
                             singleCuts: [MontageSingleCut(time: 3, partID: a), MontageSingleCut(time: 9, partID: nil)])
        s.partOrder = [a]
        let back = try JSONDecoder().decode(MontageState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
        XCTAssertEqual(back.layout, .singleLandscape)
    }

    func testLandscapeSingleURLAndProperties() {
        let l = ProjectLayout(folder: URL(fileURLWithPath: "/tmp/Artista - Tema"))
        XCTAssertEqual(l.montageVideoURL(layout: .singleLandscape).path, "/tmp/Artista - Tema/video/Artista - Tema-single-landscape.mov")
        XCTAssertEqual(l.montageTracksDirectory(layout: .singleLandscape).lastPathComponent, "Artista - Tema-single-landscape-pistas")
        XCTAssertFalse(MontageLayoutKind.singleLandscape.isPortrait)
        XCTAssertTrue(MontageLayoutKind.single.isPortrait)
        XCTAssertTrue(MontageLayoutKind.singleLandscape.isSingleShot)
        XCTAssertFalse(MontageLayoutKind.grid.isSingleShot)
        XCTAssertEqual(MontageLayoutKind.singleLandscape.canvasSize.width, 1920)
        XCTAssertEqual(MontageLayoutKind.singleLandscape.canvasSize.height, 1080)
    }

    func testNormalization() {
        let cuts = [MontageSingleCut(time: 10, partID: b), MontageSingleCut(time: 2, partID: nil),
                    MontageSingleCut(time: 4, partID: a), MontageSingleCut(time: 6, partID: a),
                    MontageSingleCut(time: 4, partID: b)]
        let n = cuts.normalizedSingleCuts()
        // 2: auto inicial (descartado); 4: gana b (último); 6: b a... a cambia; 10: b cambia
        XCTAssertEqual(n.map(\.time), [4, 6, 10])
        XCTAssertEqual(n.map(\.partID), [b, a, b])
        let dup = [MontageSingleCut(time: 5, partID: a), MontageSingleCut(time: 8, partID: a)]
        XCTAssertEqual(dup.normalizedSingleCuts().count, 1)
    }

    func testResolution() {
        let s = MontageState(singleCuts: [MontageSingleCut(time: 10, partID: a), MontageSingleCut(time: 20, partID: nil),
                                          MontageSingleCut(time: 30, partID: b)])
        XCTAssertNil(s.singlePart(at: 5, existingPartIDs: [a, b]))
        XCTAssertEqual(s.singlePart(at: 10, existingPartIDs: [a, b]), a)
        XCTAssertEqual(s.singlePart(at: 15, existingPartIDs: [a, b]), a)
        XCTAssertNil(s.singlePart(at: 25, existingPartIDs: [a, b]))
        XCTAssertEqual(s.singlePart(at: 99, existingPartIDs: [a, b]), b)
        // b desaparece: su corte se ignora (manda el automático vigente) y no se borra.
        XCTAssertNil(s.singlePart(at: 99, existingPartIDs: [a]))
        XCTAssertEqual(s.singleCuts.count, 3)
        // a desaparece: se ignora y no hay corte válido anterior.
        XCTAssertNil(s.singlePart(at: 15, existingPartIDs: [b]))
    }

    func testEditingHelpers() {
        var s = MontageState()
        s = s.addingSingleCut(at: 8, partID: a)
        s = s.addingSingleCut(at: 2, partID: b)
        XCTAssertEqual(s.singleCuts.map(\.time), [2, 8])
        s = s.addingSingleCut(at: 8, partID: b)  // mismo instante: gana el nuevo y, al igualar al anterior, se descarta
        XCTAssertEqual(s.singleCuts.map(\.time), [2])
        let id = s.singleCuts[0].id
        s = s.movingSingleCut(id, to: 12)
        XCTAssertEqual(s.singleCuts.first?.time, 12)
        s = s.addingSingleCut(at: 20, partID: a)
        s = s.movingSingleCut(id, to: 20)  // gana el movido
        XCTAssertEqual(s.singleCuts.map(\.partID), [b])
        s = s.settingSingleCut(id, partID: nil)  // automático desde el inicio: no cambia nada
        XCTAssertEqual(s.singleCuts, [])
        s = s.addingSingleCut(at: 1, partID: a)
        s = s.removingSingleCut(s.singleCuts[0].id)
        XCTAssertEqual(s.singleCuts, [])
    }
}
