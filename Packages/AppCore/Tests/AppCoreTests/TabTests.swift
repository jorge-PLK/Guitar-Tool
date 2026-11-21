import Foundation
import Store
import TabKit
import XCTest
@testable import AppCore

/// Tablatura (8.7): transcriptor y sintetizador simulados, `--audio simulated` y proyectos temporales.
struct FakeTabTranscriber: TabTranscribing {
    var slow = false
    func pitched(url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [NoteEvent] {
        progress(0.5)
        if slow { for _ in 0..<200 { try await Task.sleep(nanoseconds: 20_000_000); try Task.checkCancellation() } }
        progress(1)
        return [NoteEvent(start: 0.5, end: 0.9, pitch: 40, amplitude: 0.8), NoteEvent(start: 1.0, end: 1.4, pitch: 43, amplitude: 0.8),
                NoteEvent(start: 1.5, end: 1.9, pitch: 45, amplitude: 0.8)]
    }
    func drums(url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [TranscribedDrumHit] {
        progress(0.5)
        if slow { for _ in 0..<200 { try await Task.sleep(nanoseconds: 20_000_000); try Task.checkCancellation() } }
        return [TranscribedDrumHit(time: 0.5, midi: 35), TranscribedDrumHit(time: 1.0, midi: 38), TranscribedDrumHit(time: 1.5, midi: 35)]
    }
}

struct FakeTabSynth: TabSynthesizing {
    func render(track: TabTrack, in score: TabScore, sampleRate: Double, duration: Double, to url: URL) async throws {
        try await MainActor.run { try StudyTests.writeSine(url, frequency: 220, seconds: duration) }
    }
}

struct FakeSaveHost: HostServices {
    var save: URL?
    func pickFile(types: [String]) async -> URL? { nil }
    func pickFolder() async -> URL? { nil }
    func saveFile(suggestedName: String, types: [String]) async -> URL? { save }
}

@MainActor
final class TabTests: XCTestCase {
    struct Fixture {
        var folder: URL
        var project: Project
        var bridge: Bridge
        var events: StudyTests.Events
    }

    func makeFixture(source: TabSourceChoice? = .automatic, slow: Bool = false) throws -> Fixture {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tab-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("projects", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }

        var p = Project(song: Song(title: "Tema", artist: "Banda", source: "source/original.wav", sourceSHA256: "abc",
                                   sourceFormat: "wav", sourceSampleRate: StudyTests.sampleRate, sourceChannels: 2,
                                   sampleRate: StudyTests.sampleRate, duration: StudyTests.seconds))
        p.separation = SeparationState(state: .done, model: "m", finishedAt: Date(timeIntervalSince1970: 1_700_000_000))
        p.stems = [Stem(kind: .bass, file: "stems/bass.wav"), Stem(kind: .drums, file: "stems/drums.wav")]
        p.tabSource = source
        let folder = root.appendingPathComponent("Banda - Tema", isDirectory: true)
        let layout = ProjectLayout(folder: folder)
        try layout.createSkeleton()
        try StudyTests.writeSine(layout.stemURL(.bass), frequency: 110)
        try StudyTests.writeSine(layout.stemURL(.drums), frequency: 330)
        let src = StudyKitBridge.Source(separationModel: "m", separationFinishedAt: p.separation.finishedAt, sourceSHA256: "abc")
        try StudyKitBridge.saveCache(
            StudyKitBridge.Analysis(beats: [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0], downbeats: [0.5, 2.5], bpm: 120, beatsPerBar: 4,
                                    chords: [StudyKitBridge.Chord(start: 0, end: 2, index: 0)], key: "C:maj", keyConfidence: 0.4),
            source: src, cache: layout.analysisCache)
        try ProjectFile.save(p, to: folder)

        let events = StudyTests.Events()
        let services = TabServices(transcriber: FakeTabTranscriber(slow: slow), synth: FakeTabSynth())
        let bridge = try Bridge(options: LaunchOptions(projectsFolder: root, supportDir: support, audio: .simulated),
                                mediaBase: "https://tf.media/", reveal: nil, tab: services)
        bridge.send = { events.add($0) }
        return Fixture(folder: folder, project: p, bridge: bridge, events: events)
    }

    func call(_ f: Fixture, _ method: String, _ params: String = "{}") async -> [String: Any] {
        let out = await f.bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        return (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] ?? [:]
    }

    func result(_ f: Fixture, _ method: String, _ params: String = "{}") async throws -> [String: Any] {
        let r = await call(f, method, params)
        return try XCTUnwrap(r["result"] as? [String: Any], "\(method): \(r)")
    }

    func openTab(_ f: Fixture) async throws -> [String: Any] {
        try await result(f, "tab.open", "{\"projectId\":\"\(f.project.id.uuidString)\"}")
    }

    func tracks(_ s: [String: Any]) -> [[String: Any]] { s["tracks"] as? [[String: Any]] ?? [] }
    func track(_ s: [String: Any], _ id: String) -> [String: Any]? { tracks(s).first { $0["id"] as? String == id } }

    func waitFor(_ timeout: Double = 10, _ cond: () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if await cond() { return true }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        return await cond()
    }

    /// Abre y transcribe todo con los simulados; deja la tablatura lista.
    func openAndTranscribe(_ f: Fixture) async throws -> [String: Any] {
        _ = try await openTab(f)
        _ = try await result(f, "tab.transcribe")
        return try await openAndTranscribeWait(f)
    }

    // MARK: Abrir

    func testChoosingSourceThenAutomatic() async throws {
        let f = try await makeFixture(source: nil)
        var s = try await openTab(f)
        XCTAssertEqual(s["phase"] as? String, "choosingSource")
        let bad = await call(f, "tab.setSource", "{\"source\":\"songsterr\"}")
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? String, "unsupported")
        s = try await result(f, "tab.setSource", "{\"source\":\"automatic\"}")
        XCTAssertEqual(s["phase"] as? String, "ready")
        XCTAssertEqual(s["source"] as? String, "automatic")
    }

    func testOpenListsPendingTracksAndScoreNotReady() async throws {
        let f = try await makeFixture()
        let s = try await openTab(f)
        XCTAssertEqual(s["phase"] as? String, "ready")
        XCTAssertEqual(tracks(s).compactMap { $0["id"] as? String }, ["bass", "drums"])
        XCTAssertEqual(track(s, "bass")?["transcription"] as? String, "queued")
        XCTAssertNotNil(track(s, "bass")?["fingerprint"])
        let r = await call(f, "tab.score")
        XCTAssertEqual((r["error"] as? [String: Any])?["code"] as? String, "not-ready")
        let noStudy = await call(f, "tab.close")
        XCTAssertNotNil(noStudy["result"])
    }

    func testNotOpenErrors() async throws {
        let f = try await makeFixture()
        let r = await call(f, "tab.transcribe")
        XCTAssertEqual((r["error"] as? [String: Any])?["code"] as? String, "not-open")
    }

    // MARK: Transcribir

    func testTranscribeProgressSavesFileAndScoreMatches() async throws {
        let f = try await makeFixture()
        _ = try await openTab(f)
        let q = try await result(f, "tab.transcribe")
        XCTAssertEqual(q["queued"] as? [String], ["bass", "drums"])
        let s = try await openAndTranscribeWait(f)
        XCTAssertEqual(track(s, "bass")?["noteCount"] as? Int, 3)
        XCTAssertEqual(track(s, "drums")?["noteCount"] as? Int, 3)
        let progress = f.events.all("tab.progress")
        XCTAssertTrue(progress.contains { $0.payload["track"] as? String == "bass" && $0.payload["state"] as? String == "transcribing" })
        XCTAssertTrue(progress.contains { $0.payload["track"] as? String == "drums" && $0.payload["state"] as? String == "done" })
        let layout = ProjectLayout(folder: f.folder)
        let saved = try XCTUnwrap(TabService.loadSaved(layout.tabScoreFile))
        XCTAssertEqual(saved.tracks.map(\.id), ["bass", "drums"])
        // tab.score = JSON v1 del exportador sobre lo guardado.
        let expected = try AlphaTabExporter.make(score: saved, title: "Tema", artist: "Banda")
        let r = try await result(f, "tab.score")
        XCTAssertEqual(r["json"] as? String, expected.json)
        XCTAssertEqual(r["trackIDs"] as? [String], expected.trackIDs)
        let drums = try await result(f, "tab.score", "{\"track\":\"drums\"}")
        XCTAssertEqual(drums["trackIndex"] as? Int, 1)
        // Reabrir: lo guardado con huella al día no se rehace.
        _ = try await result(f, "tab.close")
        let again = try await openTab(f)
        XCTAssertEqual(tracks(again).compactMap { $0["transcription"] as? String }, ["ready", "ready"])
        let r2 = try await result(f, "tab.score")
        XCTAssertEqual(r2["json"] as? String, expected.json)
    }

    func openAndTranscribeWait(_ f: Fixture) async throws -> [String: Any] {
        let done = await waitFor {
            guard let s = try? await self.result(f, "tab.state") else { return false }
            return self.tracks(s).allSatisfy { $0["transcription"] as? String == "ready" }
        }
        XCTAssertTrue(done)
        return try await result(f, "tab.state")
    }

    func testCancelLeavesNoFile() async throws {
        let f = try await makeFixture(slow: true)
        _ = try await openTab(f)
        _ = try await result(f, "tab.transcribe", "{\"track\":\"bass\"}")
        let started = await waitFor { f.events.all("tab.progress").contains { $0.payload["state"] as? String == "transcribing" } }
        XCTAssertTrue(started)
        let c = try await result(f, "tab.cancel")
        XCTAssertEqual(c["cancelled"] as? Bool, true)
        let cancelled = await waitFor { f.events.all("tab.progress").contains { $0.payload["state"] as? String == "cancelled" } }
        XCTAssertTrue(cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ProjectLayout(folder: f.folder).tabScoreFile.path))
        let s = try await result(f, "tab.state")
        XCTAssertEqual(track(s, "bass")?["transcription"] as? String, "queued")
    }

    // MARK: Mezcla y escucha

    func testMuteSoloAndListening() async throws {
        let f = try await makeFixture()
        _ = try await openTab(f)
        _ = try await result(f, "tab.transcribe")
        _ = try await openAndTranscribeWait(f)
        var s = try await result(f, "tab.toggleMute", "{\"track\":\"bass\"}")
        XCTAssertEqual(track(s, "bass")?["muted"] as? Bool, true)
        XCTAssertEqual(track(s, "drums")?["muted"] as? Bool, false)
        let study = try await result(f, "study.setMix", "{\"channel\":\"drums\",\"solo\":true}")
        XCTAssertEqual(study["anySolo"] as? Bool, true)
        s = try await result(f, "tab.state")
        XCTAssertEqual(track(s, "drums")?["solo"] as? Bool, true)
        XCTAssertEqual(track(s, "bass")?["dimmed"] as? Bool, true)
        s = try await result(f, "tab.toggleMute", "{\"track\":\"bass\"}")
        XCTAssertEqual(track(s, "bass")?["muted"] as? Bool, false)
        s = try await result(f, "tab.toggleSolo", "{\"track\":\"drums\"}")
        XCTAssertEqual(track(s, "drums")?["solo"] as? Bool, false)

        XCTAssertEqual(s["listenMode"] as? String, "stems")
        s = try await result(f, "tab.setAllListening", "{\"on\":true}")
        XCTAssertEqual(s["listenMode"] as? String, "transcription")
        let ready = await waitFor {
            guard let st = try? await self.result(f, "tab.state") else { return false }
            return self.tracks(st).allSatisfy { $0["synth"] as? String == "ready" }
        }
        XCTAssertTrue(ready)
        let layout = ProjectLayout(folder: f.folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.tabSynthURL(trackID: "bass").path))
        do {
            let extras = f.bridge.studyService.current?.controller.extraTracks.map(\.id).sorted()
            XCTAssertEqual(extras, ["tab-bass", "tab-drums"])
            XCTAssertEqual(f.bridge.studyService.current?.controller.substitutedStems, ["bass", "drums"])
        }
        s = try await result(f, "tab.setAllListening", "{\"on\":false}")
        XCTAssertEqual(s["listenMode"] as? String, "stems")
        do { XCTAssertEqual(f.bridge.studyService.current?.controller.substitutedStems, []) }
        // Cerrar la tablatura suelta la síntesis del reproductor.
        _ = try await result(f, "tab.setListening", "{\"track\":\"bass\",\"on\":true}")
        _ = try await result(f, "tab.close")
        do { XCTAssertEqual(f.bridge.studyService.current?.controller.extraTracks.count, 0) }
    }

    func testSpanLoopThroughBeatClicks() async throws {
        let f = try await makeFixture()
        let s0 = try await openAndTranscribe(f)
        XCTAssertEqual(s0["selectedTrack"] as? String, "bass")
        _ = try await result(f, "tab.beatClick", "{\"track\":0,\"bar\":1,\"beat\":0}")
        let s = try await result(f, "tab.beatClick", "{\"track\":0,\"bar\":1,\"beat\":4,\"shift\":true}")
        XCTAssertNotNil(s["span"] as? [String: Any])
        let t = try await result(f, "study.setRate", "{\"rate\":1}")
        XCTAssertEqual((t["loop"] as? [String: Any])?["name"] as? String, "Selección")
        let cleared = try await result(f, "tab.span", "{\"action\":\"clear\"}")
        XCTAssertNil(cleared["span"] as? [String: Any])
        let t2 = try await result(f, "study.setRate", "{\"rate\":1}")
        XCTAssertNil(t2["loop"] as? [String: Any])
    }

    func testSelectionCarriesBarRangeForBarLoop() async throws {
        let f = try await makeFixture()
        _ = try await openAndTranscribe(f)
        let s = try await result(f, "tab.beatClick", "{\"track\":0,\"bar\":1,\"beat\":0}")
        let r = try XCTUnwrap((s["selection"] as? [String: Any])?["barRange"] as? [String: Any])
        XCTAssertEqual(r["bar"] as? Int, 1)
        let a = try XCTUnwrap(r["start"] as? Double), b = try XCTUnwrap(r["end"] as? Double)
        XCTAssertGreaterThan(b, a)
    }

    // MARK: Edición

    func testEditWithUndoRedoAndTuning() async throws {
        let f = try await makeFixture()
        _ = try await openAndTranscribe(f)
        var s = try await result(f, "tab.edit", "{\"op\":\"editMode\",\"on\":true}")
        XCTAssertEqual(s["editMode"] as? Bool, true)
        let before = track(s, "bass")?["noteCount"] as? Int ?? 0
        // Un pulso sin nota: punto 6 (3.5 s), cuerda 2.
        s = try await result(f, "tab.select", "{\"track\":\"bass\",\"beat\":5,\"tick\":0,\"string\":2}")
        XCTAssertNotNil(s["selection"] as? [String: Any])
        s = try await result(f, "tab.edit", "{\"op\":\"digit\",\"value\":3}")
        XCTAssertEqual(track(s, "bass")?["noteCount"] as? Int, before + 1)
        XCTAssertEqual(s["canUndo"] as? Bool, true)
        let rev = s["revision"] as? Int ?? 0
        s = try await result(f, "tab.edit", "{\"op\":\"digit\",\"value\":5}")   // cambia el traste de la nota nueva
        XCTAssertEqual(track(s, "bass")?["noteCount"] as? Int, before + 1)
        XCTAssertGreaterThan(s["revision"] as? Int ?? 0, rev)
        s = try await result(f, "tab.edit", "{\"op\":\"undo\"}")
        XCTAssertEqual(track(s, "bass")?["noteCount"] as? Int, before + 1)
        s = try await result(f, "tab.edit", "{\"op\":\"undo\"}")
        XCTAssertEqual(track(s, "bass")?["noteCount"] as? Int, before)
        XCTAssertEqual(s["canRedo"] as? Bool, true)
        s = try await result(f, "tab.edit", "{\"op\":\"redo\"}")
        XCTAssertEqual(track(s, "bass")?["noteCount"] as? Int, before + 1)
        // Adorno por tecla (nota seleccionada) y modo adorno.
        s = try await result(f, "tab.edit", "{\"op\":\"select\"}".replacingOccurrences(of: "\"select\"", with: "\"deselect\""))
        XCTAssertNil(s["selection"] as? [String: Any])
        // Afinación
        s = try await result(f, "tab.edit", "{\"op\":\"tuning\",\"track\":\"bass\",\"preset\":\"dropD\"}")
        XCTAssertEqual((track(s, "bass")?["tuning"] as? [String: Any])?["preset"] as? String, "dropD")
        let bad = await call(f, "tab.edit", "{\"op\":\"nope\"}")
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? String, "bad-params")
        // Se guarda con rebote: tras cerrar está en disco.
        _ = try await result(f, "tab.close")
        let saved = try XCTUnwrap(TabService.loadSaved(ProjectLayout(folder: f.folder).tabScoreFile))
        XCTAssertEqual(saved.tracks.first { $0.id == "bass" }?.tuning?.preset, .dropD)
    }

    func testKeyOrnamentAndGraceMode() async throws {
        let f = try await makeFixture()
        _ = try await openAndTranscribe(f)
        _ = try await result(f, "tab.edit", "{\"op\":\"editMode\",\"on\":true}")
        let sel = try await result(f, "tab.beatClick", "{\"track\":0,\"bar\":1,\"beat\":0}")
        XCTAssertNotNil(sel["selection"] as? [String: Any])
        var s = try await result(f, "tab.edit", "{\"op\":\"key\",\"key\":\"g\"}")
        XCTAssertEqual(s["handled"] as? Bool, true)
        XCTAssertEqual(s["graceMode"] as? Bool, true)
        s = try await result(f, "tab.edit", "{\"op\":\"key\",\"key\":\"ArrowRight\"}")
        XCTAssertEqual(s["graceMode"] as? Bool, false)
        s = try await result(f, "tab.edit", "{\"op\":\"key\",\"key\":\"q\"}")
        XCTAssertEqual(s["handled"] as? Bool, false)
        s = try await result(f, "tab.edit", "{\"op\":\"ornament\",\"name\":\"nope\"}".replacingOccurrences(of: "nope", with: "palmMute"))
        XCTAssertNotNil(s["revision"])
    }

    // MARK: Exportar

    func testExportWritesBytesToPathOrHostDialog() async throws {
        let f = try await makeFixture()
        _ = try await openAndTranscribe(f)
        let name = try await result(f, "tab.exportName")
        XCTAssertEqual(name["fileName"] as? String, "Banda - Tema.gp")
        let bytes = Data([0x50, 0x4B, 3, 4, 9, 8, 7])
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).gp")
        addTeardownBlock { try? FileManager.default.removeItem(at: out) }
        let p = out.path.replacingOccurrences(of: "\\", with: "\\\\")
        let r = try await result(f, "tab.export", "{\"data\":\"\(bytes.base64EncodedString())\",\"path\":\"\(p)\"}")
        XCTAssertEqual(r["saved"] as? Bool, true)
        XCTAssertEqual(try Data(contentsOf: out), bytes)
        // Sin ruta: sin anfitrión = cancelado; con anfitrión, donde diga el diálogo.
        let none = try await result(f, "tab.export", "{\"data\":\"\(bytes.base64EncodedString())\"}")
        XCTAssertEqual(none["saved"] as? Bool, false)
        let out2 = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).gp")
        addTeardownBlock { try? FileManager.default.removeItem(at: out2) }
        f.bridge.host = FakeSaveHost(save: out2)
        let viaHost = try await result(f, "tab.export", "{\"data\":\"\(bytes.base64EncodedString())\"}")
        XCTAssertEqual(viaHost["saved"] as? Bool, true)
        XCTAssertEqual(try Data(contentsOf: out2), bytes)
        let bad = await call(f, "tab.export", "{\"data\":\"%%%\"}")
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? String, "bad-params")
    }

    func testExportFileNameCleansSeparators() {
        XCTAssertEqual(TabService.exportFileName(title: "A/B", artist: nil), "A-B.gp")
        XCTAssertEqual(TabService.exportFileName(title: "T", artist: "x:y"), "x-y - T.gp")
    }
}
