import XCTest
@testable import Store

final class GuitarDataTests: XCTestCase {
    func testOptionsNamesAndPerRoleMixRoundTrip() throws {
        let dir = try makeTempDir("guitars")
        var p = makeFullProject()
        p.guitarSettings = GuitarSettings(stereoSplit: true)
        p.sections = [Section(name: "Estrofa", start: 10, end: 40),
                      Section(name: "Solo", start: 78, end: 90, solo: true),
                      Section(name: "Solo 2", start: 120, end: 140.5, solo: true)]
        p.guitars = [Guitar(role: .left, name: "Robe", file: "stems/guitar_L.wav", confidence: .high),
                     Guitar(role: .right, file: "stems/guitar_R.wav", confidence: .low),
                     Guitar(role: .lead, file: "stems/guitar_lead.wav")]
        p.guitarApplied = GuitarAppliedState(inputFingerprint: "12-1.0", options: p.guitarOptions, finishedAt: whole())
        p.study.mixer = [StemMix(kind: .bass, gainDB: -3),
                         StemMix(kind: .guitar, gainDB: -6, muted: true, guitarRole: .left),
                         StemMix(kind: .guitar, solo: true, guitarRole: .lead)]
        try ProjectFile.save(p, to: dir)
        let r = try ProjectFile.load(folder: dir)
        XCTAssertEqual(r, p)
        XCTAssertEqual(r.guitarOptions.soloSpans, [GuitarSoloSpan(start: 78, end: 90), GuitarSoloSpan(start: 120, end: 140.5)])
        XCTAssertFalse(r.sections[0].isSolo)
        XCTAssertTrue(r.guitarOptions.stereoSplit)
        XCTAssertEqual(r.guitarName(.left), "Robe")
        XCTAssertEqual(r.guitarName(.right), "Guitarra der.")
        XCTAssertEqual(r.guitarName(.rhythm), "Guitarra rítmica")
        XCTAssertEqual(r.guitarTracks.map(\.role), [.left, .right, .lead])
        XCTAssertEqual(r.guitars[0].file, "stems/guitar_L.wav")
        XCTAssertEqual(r.study.mixer[1].guitarRole, .left)
        XCTAssertEqual(r.study.mixer[2].guitarRole, .lead)
        XCTAssertNil(r.study.mixer[0].guitarRole)
        XCTAssertEqual(GuitarRole.lead.defaultName, "Guitarra solista")
        XCTAssertEqual(GuitarRole.rhythm.relativePath, "stems/guitar_rhythm.wav")
    }

    func testOlderV2ProjectJSONOpensAsOneTrackWithoutSpans() throws {
        let json = """
        {"schemaVersion":2,"id":"11111111-1111-1111-1111-111111111111",
         "song":{"title":"T","source":"source/original.mp3","sourceSHA256":"a","sourceFormat":"mp3","sourceSampleRate":44100,
                 "sourceChannels":2,"audio":"audio/song.wav","sampleRate":44100,"duration":10},
         "separation":{"state":"done"},
         "stems":[{"kind":"guitar","file":"stems/guitar.wav"}],
         "guitars":[{"id":"22222222-2222-2222-2222-222222222222","name":"Strat","stem":"guitar","side":"left"}],
         "sections":[],"rigs":[],"takes":[],"videos":[],
         "study":{"mixer":[{"kind":"guitar","gainDB":-2,"muted":false,"solo":true}]},
         "createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}
        """
        let dir = try makeTempDir("v2old")
        try json.write(to: ProjectLayout(folder: dir).projectFile, atomically: true, encoding: .utf8)
        let p = try ProjectFile.load(folder: dir)
        XCTAssertEqual(p.schemaVersion, 2)
        XCTAssertEqual(p.guitarSettings, GuitarSettings())
        XCTAssertEqual(p.guitarOptions, GuitarOptions())
        XCTAssertFalse(p.guitarOptions.stereoSplit)
        XCTAssertEqual(p.guitarOptions.soloSpans, [])
        XCTAssertFalse(p.guitarOptions.needsProcessing)
        XCTAssertEqual(p.guitars, [])   // entrada del formato antiguo: se ignora, no rompe la lectura
        XCTAssertNil(p.guitarApplied)
        XCTAssertNil(p.study.mixer[0].guitarRole)
        XCTAssertTrue(p.study.mixer[0].solo)
    }

    func testSectionSoloFlagIsOptionalInJSON() throws {
        let plain = try JSONEncoder().encode(Section(name: "A", start: 0, end: 1))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("solo"))
        let old = Data(#"{"id":"11111111-1111-1111-1111-111111111111","name":"A","start":0,"end":1}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(Section.self, from: old).isSolo)
        let solo = try JSONDecoder().decode(Section.self, from: JSONEncoder().encode(Section(name: "S", start: 0, end: 1, solo: true)))
        XCTAssertTrue(solo.isSolo)
    }

    func testOptionsNormalizeSpans() {
        let o = GuitarOptions(stereoSplit: false, soloSpans: [GuitarSoloSpan(start: 30, end: 40), GuitarSoloSpan(start: 5, end: 5),
                                                              GuitarSoloSpan(start: 10, end: 20), GuitarSoloSpan(start: 18, end: 32)])
        XCTAssertEqual(o.normalized.soloSpans, [GuitarSoloSpan(start: 10, end: 40)])
        XCTAssertTrue(o.needsProcessing)
    }

    func testCleanerIncludesGuitarTracksAndKeepsNamesAndOptions() throws {
        let folder = try makeTempDir("clean")
        let layout = ProjectLayout(folder: folder)
        try layout.createSkeleton()
        try "x".write(to: layout.guitarURL(.left), atomically: true, encoding: .utf8)
        var p = makeFullProject()
        p.guitarSettings = GuitarSettings(stereoSplit: true)
        p.guitars = [Guitar(role: .left, name: "Robe", file: "stems/guitar_L.wav", confidence: .high)]
        p.guitarApplied = GuitarAppliedState(inputFingerprint: "a", options: p.guitarOptions)
        let plan = ProjectCleaner.plan(folder: folder, project: p)
        XCTAssertTrue(plan.urls.map(\.lastPathComponent).contains("guitar_L.wav"))
        XCTAssertNil(plan.resultingProject.guitarApplied)
        XCTAssertEqual(plan.resultingProject.guitarOptions, p.guitarOptions)
        XCTAssertEqual(plan.resultingProject.guitars, [Guitar(role: .left, name: "Robe")])
    }
}

final class GuitarQueueTests: XCTestCase {
    private func isFinished(_ e: LibraryEvent) -> Bool { if case .guitarSplitFinished = e { return true } else { return false } }

    /// Importa y deja la canción separada y analizada (con las opciones por defecto).
    private func imported(_ env: Env, _ name: String = "a.mp3") async throws -> (UUID, EventLog, Task<Void, Never>) {
        let log = EventLog()
        let t = log.collect(env.library.events)
        let id = try await env.library.importSong(from: try env.makeSource(name, content: name))
        await env.library.waitForSeparations()
        return (id, log, t)
    }

    func testDefaultOptionsNeverCallTheSplitter() async throws {
        let env = try await Env(withMeter: true, withAnalyzer: true, withGuitars: true)
        let (id, log, t) = try await imported(env)
        t.cancel()
        let calls = await env.splitter.calls
        XCTAssertEqual(calls, 0)
        let analyses = await env.analyzer.calls.count
        XCTAssertEqual(analyses, 1)
        let evs = await log.events
        XCTAssertFalse(evs.contains { if case .guitarSplitStarted = $0 { return true } else { return false } })
        let p = try await env.project(id)
        XCTAssertEqual(p.guitars, [])
        let st = await env.library.guitarSplitState(id: id)
        XCTAssertEqual(st, .done)
        _ = try await env.library.ensureAnalysis(id: id)
        await env.library.waitForSeparations()
        let after = await env.splitter.calls
        XCTAssertEqual(after, 0)
    }

    func testSavingOptionsRequeuesOnlyGuitarsWithSavedOptions() async throws {
        let env = try await Env(withMeter: true, withAnalyzer: true, withGuitars: true)
        let (id, log, t) = try await imported(env)
        let first = try await env.library.saveGuitarStereoSplit(id: id, true)
        XCTAssertEqual(first, GuitarOptions(stereoSplit: true))
        await env.library.waitForSeparations()
        try await env.library.saveStudy(id: id, study: StudyState(), sections: [
            Section(name: "Mal", start: 20, end: 10, solo: true), Section(name: "Solo", start: 30, end: 40, solo: true)])
        let saved = GuitarOptions(stereoSplit: true, soloSpans: [GuitarSoloSpan(start: 30, end: 40)])
        let queued = await env.library.guitarSplitState(id: id)
        XCTAssertNotEqual(queued, .done)
        await env.library.waitForSeparations()
        let seenFinish = await waitUntil { await log.events.contains { if case .guitarSplitFinished = $0 { return true } else { return false } } }
        XCTAssertTrue(seenFinish)
        t.cancel()
        let evs = await log.events
        XCTAssertTrue(evs.contains(.guitarSplitQueued(id)))
        XCTAssertTrue(evs.contains(where: isFinished))
        let seen = await env.splitter.optionsSeen
        XCTAssertEqual(seen, [first, saved])
        // Solo guitarras: ni un análisis más.
        let analyses = await env.analyzer.calls.count
        XCTAssertEqual(analyses, 1)
        let p = try await env.project(id)
        let layout = ProjectLayout(folder: try env.folder(id))
        XCTAssertEqual(p.guitarOptions, saved)
        XCTAssertEqual(p.guitarTracks.map(\.role), [.left, .right, .lead])
        XCTAssertEqual(p.guitarApplied?.options, saved)
        XCTAssertEqual(p.guitarApplied?.inputFingerprint, layout.guitarInputFingerprint)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.guitarURL(.lead).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.guitarURL(.rhythm).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.guitarsPartialDir.path))
        let st = await env.library.guitarSplitState(id: id)
        XCTAssertEqual(st, .done)
        // Mismas opciones otra vez: no hace nada. Renombrar un solo o tocar otra sección tampoco reprocesa.
        let before = await env.splitter.calls
        XCTAssertEqual(before, 2)
        _ = try await env.library.saveGuitarStereoSplit(id: id, true)
        try await env.library.saveStudy(id: id, study: StudyState(), sections: [
            Section(name: "Mal", start: 20, end: 10, solo: true), Section(name: "Solo del puente", start: 30, end: 40, solo: true),
            Section(name: "Estrofa", start: 0, end: 20)])
        await env.library.waitForSeparations()
        let calls = await env.splitter.calls
        XCTAssertEqual(calls, before)
        // Quitar la marca de solo sí reprocesa (la solista desaparece).
        try await env.library.saveStudy(id: id, study: StudyState(), sections: [Section(name: "Solo del puente", start: 30, end: 40)])
        await env.library.waitForSeparations()
        let after = try await env.project(id)
        XCTAssertEqual(after.guitarTracks.map(\.role), [.left, .right])
        let calls2 = await env.splitter.calls
        XCTAssertEqual(calls2, before + 1)
    }

    func testTurningOptionsOffRemovesTracksButKeepsNamesAndMix() async throws {
        let env = try await Env(withMeter: true, withAnalyzer: true, withGuitars: true)
        let (id, _, t) = try await imported(env)
        _ = try await env.library.saveGuitarStereoSplit(id: id, true)
        await env.library.waitForSeparations()
        try await env.library.saveGuitarNames(id: id, names: [.left: "  Robe ", .right: ""])
        var study = try await env.project(id).study
        study.mixer = [StemMix(kind: .guitar, gainDB: -4, muted: true, guitarRole: .left)]
        try await env.library.saveStudy(id: id, study: study, sections: [])
        _ = try await env.library.saveGuitarStereoSplit(id: id, false)
        await env.library.waitForSeparations()
        t.cancel()
        let p = try await env.project(id)
        let layout = ProjectLayout(folder: try env.folder(id))
        XCTAssertEqual(p.guitarTracks, [])
        XCTAssertNil(p.guitarApplied)
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.guitarURL(.left).path))
        XCTAssertEqual(p.guitarName(.left), "Robe")
        XCTAssertEqual(p.guitarName(.right), "Guitarra der.")
        XCTAssertEqual(p.study.mixer, study.mixer)
        let calls = await env.splitter.calls
        XCTAssertEqual(calls, 1)   // retirar pistas no llama al separador
        // Y al volver a activarlas, el nombre sigue.
        _ = try await env.library.saveGuitarStereoSplit(id: id, true)
        await env.library.waitForSeparations()
        let again = try await env.project(id)
        XCTAssertEqual(again.guitars.first { $0.role == .left }?.name, "Robe")
        XCTAssertTrue(again.guitars.first { $0.role == .left }?.isPresent ?? false)
    }

    func testOptionsChangedWhileProcessingReprocessWithLatest() async throws {
        let env = try await Env(withMeter: true, withAnalyzer: true, withGuitars: true)
        let (id, _, t) = try await imported(env)
        await env.splitter.setGated(true)
        _ = try await env.library.saveGuitarStereoSplit(id: id, true)
        let started = await waitUntil { await env.splitter.calls == 1 }
        XCTAssertTrue(started)
        let latest = GuitarOptions(stereoSplit: false, soloSpans: [GuitarSoloSpan(start: 1, end: 9)])
        _ = try await env.library.saveGuitarStereoSplit(id: id, false)
        try await env.library.saveStudy(id: id, study: StudyState(), sections: [Section(name: "Solo", start: 1, end: 9, solo: true)])
        await env.splitter.setGated(false)
        await env.library.waitForSeparations()
        t.cancel()
        let seen = await env.splitter.optionsSeen
        XCTAssertEqual(seen.count, 2)
        XCTAssertEqual(seen.last, latest)
        let p = try await env.project(id)
        XCTAssertEqual(p.guitarApplied?.options, latest)
        XCTAssertEqual(p.guitarTracks.map(\.role), [.rhythm, .lead])
        let layout = ProjectLayout(folder: try env.folder(id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.guitarURL(.left).path))
        let analyses = await env.analyzer.calls.count
        XCTAssertEqual(analyses, 1)
    }

    func testChangedGuitarStemRedoesGuitarsWithSavedOptions() async throws {
        let env = try await Env(withMeter: true, withAnalyzer: true, withGuitars: true)
        let (id, _, t) = try await imported(env)
        let options = GuitarOptions(stereoSplit: true)
        _ = try await env.library.saveGuitarStereoSplit(id: id, true)
        await env.library.waitForSeparations()
        try await env.library.saveGuitarNames(id: id, names: [.left: "Robe"])
        let folder = try env.folder(id)
        try "otro guitar distinto".write(to: ProjectLayout(folder: folder).stemURL(.guitar), atomically: true, encoding: .utf8)
        _ = try await env.library.ensureAnalysis(id: id)
        await env.library.waitForSeparations()
        t.cancel()
        let seen = await env.splitter.optionsSeen
        XCTAssertEqual(seen, [options, options])
        let p = try ProjectFile.load(folder: folder)
        XCTAssertEqual(p.guitarName(.left), "Robe")
        XCTAssertEqual(p.guitarApplied?.inputFingerprint, ProjectLayout(folder: folder).guitarInputFingerprint)
        // Ya al día: no vuelve a encolar.
        _ = try await env.library.ensureAnalysis(id: id)
        await env.library.waitForSeparations()
        let calls = await env.splitter.calls
        XCTAssertEqual(calls, 2)
    }

    func testFailureKeepsSongUsableAndIsNotRetriedUntilOptionsChange() async throws {
        let env = try await Env(withMeter: true, withAnalyzer: true, withGuitars: true)
        let (id, log, t) = try await imported(env)
        await env.splitter.setFailNext(true)
        _ = try await env.library.saveGuitarStereoSplit(id: id, true)
        await env.library.waitForSeparations()
        // Espera determinista: el evento llega al registro por otra tarea; no se cancela hasta verlo.
        let seenFailure = await waitUntil { await log.events.contains(.guitarSplitFailed(id, "sin modelo")) }
        XCTAssertTrue(seenFailure)
        t.cancel()
        let evs = await log.events
        XCTAssertTrue(evs.contains(.guitarSplitFailed(id, "sin modelo")))
        let st = await env.library.guitarSplitState(id: id)
        XCTAssertEqual(st, .failed("sin modelo"))
        let p = try await env.project(id)
        XCTAssertEqual(p.separation.state, .done)
        XCTAssertEqual(p.guitarTracks, [])
        XCTAssertNil(p.guitarApplied)
        _ = try await env.library.open(id: id)
        await env.library.waitForSeparations()
        let calls = await env.splitter.calls
        XCTAssertEqual(calls, 1)
        // Cambiar las opciones lo reintenta.
        try await env.library.saveStudy(id: id, study: StudyState(), sections: [Section(name: "Solo", start: 1, end: 2, solo: true)])
        await env.library.waitForSeparations()
        let done = await env.library.guitarSplitState(id: id)
        XCTAssertEqual(done, .done)
        let final = try await env.project(id)
        XCTAssertEqual(final.guitarTracks.count, 3)
    }

    func testAlreadySeparatedProjectWithSavedOptionsGetsGuitarsOnOpen() async throws {
        let plain = try await Env(withMeter: true, withAnalyzer: true)
        let id = try await plain.library.importSong(from: try plain.makeSource("a.mp3", content: "A"))
        await plain.library.waitForSeparations()
        let folder = try plain.folder(id)
        var p = try ProjectFile.load(folder: folder)
        p.guitarSettings = GuitarSettings(stereoSplit: true)
        try ProjectFile.save(p, to: folder)
        let library = Library(root: plain.root, profile: plain.profile, index: plain.index, importer: plain.importer,
                              separator: plain.separator, autoSeparate: false, levelMeter: plain.meter, analyzer: plain.analyzer,
                              guitarSplitter: plain.splitter)
        let state = try await library.ensureAnalysis(id: id)
        XCTAssertEqual(state, .analyzing)
        await library.waitForSeparations()
        let seen = await plain.splitter.optionsSeen
        XCTAssertEqual(seen, [GuitarOptions(stereoSplit: true)])
        let final = try await plain.project(id)
        XCTAssertEqual(final.guitarTracks.map(\.role), [.left, .right])
        let again = try await library.ensureAnalysis(id: id)
        XCTAssertEqual(again, .ready)
    }
}
