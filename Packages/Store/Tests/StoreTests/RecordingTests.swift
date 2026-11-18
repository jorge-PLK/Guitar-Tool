import Foundation
import XCTest
@testable import Store

final class RecordingTests: XCTestCase {
    private func sampleTake(part: UUID) -> Take {
        Take(processedFile: "takes/x/processed.wav", createdAt: whole(),
             partID: part, videoFile: "takes/x/video.mov", videoOffset: 0.012,
             videoFormat: TakeVideoFormat(cameraUID: "cam-1", cameraName: "iPhone", width: 1920, height: 1080, fps: 30),
             punches: [TakePunch(start: 10, end: 12.5, processedFile: "takes/x/punch-1/processed.wav",
                                 videoFile: "takes/x/punch-1/video.mov", videoOffset: -0.004)],
             baseProcessedFile: "takes/x/base/processed.wav")
    }

    private func roundTripProject(_ p: Project) throws -> Project {
        let dir = try makeTempDir()
        try ProjectFile.save(p, to: dir)
        return try ProjectFile.load(folder: dir)
    }

    // MARK: JSON

    func testProjectRoundTripWithRecording() throws {
        var p = makeFullProject()
        let section = p.sections[0]
        var part = RecordingPart(name: "Solo", replaces: .lead)
        let take = sampleTake(part: part.id)
        part.addTake(take.id)
        p.takes.append(take)
        p.recording = RecordingState(parts: [part], mix: [StemMix(kind: .drums, gainDB: -3, muted: true)],
                                     partMix: [PartMix(partID: part.id, gainDB: -4.5, muted: true)],
                                     startSectionID: section.id, countIn: false, preRollBars: 1)
        let back = try roundTripProject(p)
        XCTAssertEqual(back, p)
        XCTAssertEqual(back.recording?.partMix(for: part.id).gainDB, -4.5)
        XCTAssertEqual(back.takes.last?.punches?.first?.end, 12.5)
        XCTAssertEqual(back.schemaVersion, p.schemaVersion)
    }

    func testProfileRoundTripWithVideo() throws {
        let store = ProfileStore(url: try makeTempDir().appendingPathComponent("p/profile.json"))
        var v = VideoSettings(cameraUID: "cam-1", resolution: .hd720, fps: 60,
                              export: VideoExportDefaults(codec: .h264, resolution: .uhd4K, titleOverlay: false, exportStemWAVs: false))
        v.setDefaultOffset(0.035, for: "cam-1")
        try store.save(EquipmentProfile(video: v))
        let back = try store.load()
        XCTAssertEqual(back.video, v)
        XCTAssertEqual(back.video?.defaultOffset(for: "cam-1"), 0.035)
        XCTAssertEqual(back.video?.defaultOffset(for: "otra"), 0)
    }

    func testVideoDefaults() {
        let v = VideoSettings()
        XCTAssertNil(v.cameraUID)
        XCTAssertEqual(v.resolution, VideoResolution(width: 1920, height: 1080))
        XCTAssertEqual(v.fps, 30)
        XCTAssertEqual(v.export.codec, .hevc)
        XCTAssertTrue(v.export.titleOverlay)
        XCTAssertTrue(v.export.exportStemWAVs)
        XCTAssertEqual(v.export.normalizeLUFS, -14)
    }

    func testOldProfileAndProjectStillLoad() throws {
        let store = ProfileStore(url: try makeTempDir().appendingPathComponent("p/profile.json"))
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"workingSampleRate":48000,"guitars":[]}"#.utf8).write(to: store.url)
        XCTAssertNil(try store.load().video)

        // Proyecto sin `recording` ni campos nuevos de toma.
        let dir = try makeTempDir()
        try ProjectFile.save(makeFullProject(), to: dir)
        let url = ProjectLayout(folder: dir).projectFile
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertNil(json["recording"])
        let takes = try XCTUnwrap(json["takes"] as? [[String: Any]])
        for t in takes { for k in ["partID", "videoFile", "videoOffset", "videoFormat", "punches", "baseProcessedFile"] { XCTAssertNil(t[k]) } }
        json["takes"] = takes
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let p = try ProjectFile.load(folder: dir)
        XCTAssertNil(p.recording)
        XCTAssertNil(p.takes[0].partID)
        XCTAssertNil(p.takes[0].punches)
    }

    func testPartMixMissingDecodesAsZeroDB() throws {
        let old = #"{"parts":[],"mix":[],"countIn":true,"preRollBars":2}"#
        let s = try JSONDecoder().decode(RecordingState.self, from: Data(old.utf8))
        XCTAssertTrue(s.partMix.isEmpty)
        let id = UUID()
        XCTAssertEqual(s.partMix(for: id), PartMix(partID: id, gainDB: 0, muted: false))
    }

    func testRecordingStateDefaultsAndPreRollClamp() throws {
        let s = RecordingState()
        XCTAssertTrue(s.countIn)
        XCTAssertEqual(s.preRollBars, 2)
        XCTAssertEqual(RecordingState(preRollBars: 7).preRollBars, 2)
        XCTAssertEqual(RecordingState(preRollBars: -1).preRollBars, 0)
        var t = RecordingState(preRollBars: 0)
        t.preRollBars = 5
        XCTAssertEqual(t.preRollBars, 2)
        let decoded = try JSONDecoder().decode(RecordingState.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, RecordingState())
    }

    // MARK: Partes

    func testProposedPartsFromGuitars() {
        let parts = RecordingPart.proposed(from: [Guitar(role: .rhythm, name: "Ritmo"), Guitar(role: .lead, name: "Solo")])
        XCTAssertEqual(parts.map(\.name), ["Ritmo", "Solo"])
        XCTAssertEqual(parts.map(\.replaces), [.rhythm, .lead])
        XCTAssertEqual(parts.map(\.isLead), [false, true])
        XCTAssertTrue(parts.allSatisfy { $0.takeIDs.isEmpty && $0.bestTakeID == nil })
        XCTAssertEqual(RecordingPart.proposed(from: []), [])
    }

    func testRecordingOrInitialCopiesBackingMix() {
        var p = makeFullProject()
        p.study.mixer = [StemMix(kind: .bass, gainDB: -2)]
        let r = p.recordingOrInitial()
        XCTAssertEqual(r.parts.map(\.name), ["Strat"])
        XCTAssertEqual(r.mix, p.study.mixer)
        var existing = RecordingState(mix: [])
        existing.countIn = false
        p.recording = existing
        XCTAssertEqual(p.recordingOrInitial(), existing)
    }

    func testBestTakeIsLastUntilChosen() {
        var part = RecordingPart(name: "A")
        let a = UUID(), b = UUID(), c = UUID()
        part.addTake(a)
        XCTAssertEqual(part.bestTakeID, a)
        part.addTake(b)
        XCTAssertEqual(part.bestTakeID, b)
        XCTAssertTrue(part.setBest(a))
        XCTAssertEqual(part.bestTakeID, a)
        XCTAssertFalse(part.setBest(c))
        XCTAssertEqual(part.bestTakeID, a)
        part.addTake(c)
        XCTAssertEqual(part.bestTakeID, c)
        XCTAssertEqual(part.takeIDs, [a, b, c])
    }

    func testMutedGuitarAndBackingTakes() {
        var rhythm = RecordingPart(name: "Ritmo", replaces: .rhythm)
        var lead = RecordingPart(name: "Solo", replaces: .lead)
        let extra = RecordingPart(name: "Armonía")
        let r1 = UUID(), r2 = UUID(), l1 = UUID()
        rhythm.addTake(r1); rhythm.addTake(r2)
        lead.addTake(l1)
        let s = RecordingState(parts: [rhythm, lead, extra])
        XCTAssertEqual(s.mutedGuitar(whileRecording: lead.id), .lead)
        XCTAssertNil(s.mutedGuitar(whileRecording: extra.id))
        XCTAssertNil(s.mutedGuitar(whileRecording: UUID()))
        let forExtra = s.backingTakes(whileRecording: extra.id)
        XCTAssertEqual(forExtra.map(\.takeID), [r2, l1])
        XCTAssertEqual(forExtra.map(\.channelName), ["Tú · Ritmo", "Tú · Solo"])
        XCTAssertEqual(s.backingTakes(whileRecording: lead.id).map(\.takeID), [r2])
    }

    func testRemoveTakeReassignsBest() {
        var part = RecordingPart(name: "A")
        let a = UUID(), b = UUID(), c = UUID()
        [a, b, c].forEach { part.addTake($0) }
        part.setBest(b)
        part.removeTake(a)                       // no era la mejor
        XCTAssertEqual(part.bestTakeID, b)
        part.removeTake(b)                       // era la mejor: pasa a la última que queda
        XCTAssertEqual(part.bestTakeID, c)
        part.removeTake(c)
        XCTAssertNil(part.bestTakeID)
        XCTAssertTrue(part.takeIDs.isEmpty)
    }

    func testProjectRemoveTake() {
        var p = makeFullProject()
        var part = RecordingPart(name: "A")
        let t1 = Take(), t2 = Take()
        p.takes = [t1, t2]
        part.addTake(t1.id); part.addTake(t2.id)
        p.recording = RecordingState(parts: [part])
        p.removeTake(t2.id)
        XCTAssertEqual(p.takes.map(\.id), [t1.id])
        XCTAssertEqual(p.recording?.parts[0].takeIDs, [t1.id])
        XCTAssertEqual(p.recording?.parts[0].bestTakeID, t1.id)
    }

    // MARK: Rutas

    func testLayoutPaths() {
        let folder = URL(fileURLWithPath: "/tmp/proj")
        let l = ProjectLayout(folder: folder)
        let id = UUID()
        XCTAssertEqual(l.videoURL(takeId: id).path, "/tmp/proj/takes/\(id.uuidString)/video.mov")
        XCTAssertEqual(l.baseProcessedURL(takeId: id).path, "/tmp/proj/takes/\(id.uuidString)/base/processed.wav")
        XCTAssertEqual(l.punchDirectory(takeId: id, n: 2).path, "/tmp/proj/takes/\(id.uuidString)/punch-2")
        XCTAssertEqual(ProjectLayout.videoRelativePath(takeId: id), "takes/\(id.uuidString)/video.mov")
    }

    // MARK: Library

    func testSaveRecordingAndDeleteTake() async throws {
        let env = try await Env(autoSeparate: false)
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let layout = ProjectLayout(folder: try env.folder(id))
        var part = RecordingPart(name: "Ritmo", replaces: .rhythm)
        let t1 = Take(), t2 = Take()
        part.addTake(t1.id); part.addTake(t2.id)
        var t1p = t1, t2p = t2
        t1p.partID = part.id; t2p.partID = part.id
        try await env.library.saveTakes(id: id, [t1p, t2p])
        try await env.library.saveRecording(id: id, RecordingState(parts: [part], countIn: false))
        for t in [t1, t2] {
            let dir = layout.takeDirectory(takeId: t.id)
            try FileManager.default.createDirectory(at: layout.punchDirectory(takeId: t.id, n: 1), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: dir.appendingPathComponent("processed.wav"))
        }
        var saved = try await env.project(id)
        XCTAssertEqual(saved.recording?.parts.first?.bestTakeID, t2.id)
        XCTAssertEqual(saved.recording?.countIn, false)

        try await env.library.deleteTake(projectID: id, takeID: t2.id)
        saved = try await env.project(id)
        XCTAssertEqual(saved.takes.map(\.id), [t1.id])
        XCTAssertEqual(saved.recording?.parts.first?.takeIDs, [t1.id])
        XCTAssertEqual(saved.recording?.parts.first?.bestTakeID, t1.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.takeDirectory(takeId: t2.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.takeDirectory(takeId: t1.id).path))

        let bogus = UUID()
        do { try await env.library.deleteTake(projectID: id, takeID: bogus); XCTFail() }
        catch { XCTAssertEqual(error as? LibraryError, .takeNotFound(bogus)) }
    }
}
