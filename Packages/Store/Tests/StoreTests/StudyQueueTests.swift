import XCTest
@testable import Store

actor EventLog {
    private(set) var events: [LibraryEvent] = []
    func add(_ e: LibraryEvent) { events.append(e) }
    nonisolated func collect(_ stream: AsyncStream<LibraryEvent>) -> Task<Void, Never> {
        Task { for await e in stream { await add(e) } }
    }
}

final class StemEmptyAndAnalysisTests: XCTestCase {
    func testStemDecodesWithoutEmptyFields() throws {
        let json = #"{"kind":"bass","file":"stems/bass.wav"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Stem.self, from: json)
        XCTAssertFalse(s.isEmpty)
        XCTAssertFalse(s.levelMeasured)
        let round = try JSONDecoder().decode(Stem.self, from: JSONEncoder().encode(Stem(kind: .piano, file: "x", isEmpty: true, levelMeasured: true)))
        XCTAssertTrue(round.isEmpty)
        XCTAssertTrue(round.levelMeasured)
    }

    func testSeparationMarksEmptyStemsAndDeletesTheirFiles() async throws {
        let env = try await Env(withMeter: true)
        await env.meter.setSilent(["other.wav", "piano.wav"])
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        await env.library.waitForSeparations()
        let p = try await env.project(id)
        let layout = ProjectLayout(folder: try env.folder(id))
        XCTAssertEqual(p.separation.state, .done)
        XCTAssertEqual(Set(p.stems.filter(\.isEmpty).map(\.kind)), [.other, .piano])
        XCTAssertTrue(p.stems.allSatisfy(\.levelMeasured))
        XCTAssertEqual(p.stems.count, 6)
        for k in StemKind.allCases {
            let exists = FileManager.default.fileExists(atPath: layout.stemURL(k).path)
            XCTAssertEqual(exists, !(k == .other || k == .piano), "\(k)")
        }
    }

    func testEmptyStemWithoutFileDoesNotBreakMigrationCleanupOrUsage() async throws {
        let env = try await Env(withMeter: true)
        await env.meter.setSilent(["other.wav"])
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        await env.library.waitForSeparations()
        try env.profile.save(EquipmentProfile(projectsFolder: env.root, workingSampleRate: 48000))
        _ = try await env.library.open(id: id)
        await env.library.waitForMigrations()
        let layout = ProjectLayout(folder: try env.folder(id))
        XCTAssertEqual(try ProjectFile.load(folder: layout.folder).song.sampleRate, 48000, "la reconversión no falla por el stem vacío")
        XCTAssertEqual(try String(contentsOf: layout.stemURL(.bass), encoding: .utf8), "stem@48000")
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.stemURL(.other).path))
        XCTAssertEqual(try ProjectFile.load(folder: layout.folder).separation.state, .done)
        let usage = await env.library.diskUsage()
        XCTAssertGreaterThan(usage.regenerableBytes, 0)
        _ = try await env.library.cleanup(id: id)
        let after = try await env.project(id)
        XCTAssertEqual(after.stems, [])
    }

    func testRecoverInterruptedIgnoresDoneProjectWithEmptyStem() async throws {
        let env = try await Env(withMeter: true)
        await env.meter.setSilent(["other.wav"])
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        await env.library.waitForSeparations()
        let recovered = try await env.library.recoverInterrupted()
        XCTAssertEqual(recovered, [])
        let p = try await env.project(id)
        XCTAssertEqual(p.separation.state, .done)
    }

    func testOpenMeasuresUnmeasuredProjectsOnce() async throws {
        let env = try await Env()   // proyecto separado "antiguo": sin medidor
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        await env.library.waitForSeparations()
        let old = try await env.project(id)
        XCTAssertTrue(old.stems.allSatisfy { !$0.levelMeasured })

        let env2 = try await Env(withMeter: true)
        // Reutiliza la carpeta del primero con una Library nueva con medidor.
        let lib = Library(root: env.root, profile: env.profile, index: env.index, importer: env.importer,
                          separator: env.separator, autoSeparate: false, levelMeter: env2.meter)
        await env2.meter.setSilent(["piano.wav"])
        _ = try await lib.open(id: id)
        await lib.waitForSeparations()
        var p = try await env.project(id)
        XCTAssertEqual(p.stems.filter(\.isEmpty).map(\.kind), [.piano])
        XCTAssertTrue(p.stems.allSatisfy(\.levelMeasured))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ProjectLayout(folder: try env.folder(id)).stemURL(.piano).path))
        let first = await env2.meter.measured.count
        XCTAssertEqual(first, 6)

        _ = try await lib.open(id: id)
        await lib.waitForSeparations()
        let second = await env2.meter.measured.count
        XCTAssertEqual(second, 6, "no se vuelve a medir")
        p = try await env.project(id)
        XCTAssertEqual(p.stems.filter(\.isEmpty).count, 1)
    }

    func testAnalysisIsQueuedAfterSeparationOneAtATime() async throws {
        let env = try await Env(withMeter: true, withAnalyzer: true)
        await env.meter.setSilent(["other.wav"])
        await env.analyzer.setGated(true)
        let log = EventLog()
        let collector = log.collect(env.library.events)
        let a = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let b = try await env.library.importSong(from: try env.makeSource("b.mp3", content: "B"))
        let started = await waitUntil { await env.analyzer.active == 1 }
        XCTAssertTrue(started)
        await env.analyzer.setGated(false)
        await env.library.waitForSeparations()
        try await Task.sleep(for: .milliseconds(50))
        collector.cancel()
        let events = await log.events

        let calls = await env.analyzer.calls
        XCTAssertEqual(Set(calls), [a, b])
        XCTAssertEqual(calls.count, 2)
        let maxActive = await env.analyzer.maxActive
        XCTAssertEqual(maxActive, 1)
        // El analizador ve los stems ya marcados: sin el vacío.
        let seen = await env.analyzer.stemsSeen
        XCTAssertTrue(seen.allSatisfy { !$0.contains(.other) && $0.count == 5 })
        for id in [a, b] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: ProjectLayout(folder: try env.folder(id)).analysisCache.path))
            XCTAssertTrue(events.contains(.analysisQueued(id)))
            XCTAssertTrue(events.contains(.analysisStarted(id)))
            XCTAssertTrue(events.contains(.analysisFinished(id)))
        }
        let state = try await env.library.ensureAnalysis(id: a)
        XCTAssertEqual(state, .ready)
    }

    func testAnalysisFailureEmitsEventAndOpenRetries() async throws {
        let env = try await Env(withAnalyzer: true)
        await env.analyzer.setFailNext(true)
        let log = EventLog()
        let collector = log.collect(env.library.events)
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        await env.library.waitForSeparations()
        try await Task.sleep(for: .milliseconds(50))
        collector.cancel()
        let events = await log.events
        XCTAssertTrue(events.contains(.analysisFailed(id, "sin modelo")))
        let p = try await env.project(id)
        XCTAssertEqual(p.separation.state, .done, "un fallo de análisis no estropea la separación")

        _ = try await env.library.open(id: id)
        await env.library.waitForSeparations()
        let calls = await env.analyzer.calls.count
        XCTAssertEqual(calls, 2)
        let state = try await env.library.ensureAnalysis(id: id)
        XCTAssertEqual(state, .ready)
    }

    func testOpenTriggersAnalysisWhenMissingOrStaleButNotWhenCurrent() async throws {
        let env = try await Env(withAnalyzer: true)
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        await env.library.waitForSeparations()
        var calls = await env.analyzer.calls.count
        XCTAssertEqual(calls, 1)

        // Vigente: abrir no analiza.
        _ = try await env.library.open(id: id)
        await env.library.waitForSeparations()
        calls = await env.analyzer.calls.count
        XCTAssertEqual(calls, 1)

        // Desfasado (cambia la huella): abrir lo recalcula.
        await env.analyzer.setVersion("v2")
        _ = try await env.library.open(id: id)
        await env.library.waitForSeparations()
        calls = await env.analyzer.calls.count
        XCTAssertEqual(calls, 2)

        // Falta: se borra la caché.
        try FileManager.default.removeItem(at: ProjectLayout(folder: try env.folder(id)).analysisCache)
        _ = try await env.library.open(id: id)
        await env.library.waitForSeparations()
        calls = await env.analyzer.calls.count
        XCTAssertEqual(calls, 3)
    }

    func testReseparationRegeneratesAndMeasuresAgain() async throws {
        let env = try await Env(withMeter: true, withAnalyzer: true)
        await env.meter.setSilent(["other.wav"])
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        await env.library.waitForSeparations()
        let first = try await env.project(id)
        XCTAssertEqual(first.stems.filter(\.isEmpty).map(\.kind), [.other])

        await env.meter.setSilent(["piano.wav"])
        try await Task.sleep(for: .milliseconds(1100))   // finishedAt se guarda en segundos enteros
        try await env.library.separate(id: id)
        await env.library.waitForSeparations()
        let p = try await env.project(id)
        XCTAssertEqual(p.stems.filter(\.isEmpty).map(\.kind), [.piano])
        let layout = ProjectLayout(folder: try env.folder(id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.stemURL(.other).path))
        let calls = await env.analyzer.calls.count
        XCTAssertEqual(calls, 2, "reseparar invalida y recalcula")
    }

    func testSaveStudyPersistsOnlyStudyAndSections() async throws {
        let env = try await Env()
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        await env.library.waitForSeparations()
        let study = StudyState(chordOverrides: [ChordOverride(start: 1, end: 2, index: 1)], keyOverride: "A:min",
                               loops: [Loop(name: "L", start: 3, end: 4)], player: PlayerSettings(rate: 0.7, capo: 2))
        let sections = [Section(name: "Intro", start: 0, end: 8, kind: "intro")]
        try await env.library.saveStudy(id: id, study: study, sections: sections)
        let p = try await env.project(id)
        XCTAssertEqual(p.study, study)
        XCTAssertEqual(p.sections, sections)
        XCTAssertEqual(p.separation.state, .done)
        XCTAssertEqual(p.stems.count, 6)
    }

    func testSaveTakesAddsAndReplacesByIdWithoutTouchingStudy() async throws {
        let env = try await Env()
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        await env.library.waitForSeparations()
        let key = CalibrationKey(inputUID: "in", outputUID: "", sampleRate: 48_000, bufferFrames: 512,
                                 inputChannel: 1, outputChannel: 1)
        var take = Take(processedFile: ProjectLayout.processedRelativePath(takeId: UUID()), createdAt: whole(),
                        songStart: 12, sampleRate: 48_000, latencySamples: 1_200, latencyCalibrated: false,
                        calibrationKey: key, clock: .single)
        try await env.library.saveTake(id: id, take: take)
        var p = try await env.project(id)
        XCTAssertEqual(p.takes, [take])
        let other = Take(createdAt: whole())
        take.latencyCalibrated = true
        take.songStart = 11.9
        try await env.library.saveTakes(id: id, [take, other])
        p = try await env.project(id)
        XCTAssertEqual(p.takes, [take, other])
        XCTAssertEqual(p.separation.state, .done)
    }

    private struct Boom: Error {}

    /// Interrupción al medir un proyecto ya separado: project.json queda con isEmpty antes de borrar el WAV,
    /// y al abrir se completa el borrado.
    func testInterruptedDeletionWhileMeasuringIsCompletedOnOpen() async throws {
        let env = try await Env()
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        await env.library.waitForSeparations()
        let layout = ProjectLayout(folder: try env.folder(id))

        let meter = MockMeter()
        await meter.setSilent(["other.wav"])
        let crashing = Library(root: env.root, profile: env.profile, index: env.index, importer: env.importer,
                               separator: env.separator, autoSeparate: false, levelMeter: meter)
        await crashing.setStemFileRemover { _ in throw Boom() }
        _ = try await crashing.open(id: id)
        await crashing.waitForSeparations()

        var p = try await env.project(id)
        let other = try XCTUnwrap(p.stems.first { $0.kind == .other })
        XCTAssertTrue(other.isEmpty)
        XCTAssertTrue(other.levelMeasured)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.stemURL(.other).path), "el WAV sigue: el proceso «murió» antes de borrarlo")

        let recovering = Library(root: env.root, profile: env.profile, index: env.index, importer: env.importer,
                                 separator: env.separator, autoSeparate: false, levelMeter: meter)
        _ = try await recovering.open(id: id)
        await recovering.waitForSeparations()
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.stemURL(.other).path))
        p = try await env.project(id)
        XCTAssertTrue(p.stems.first { $0.kind == .other }!.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.stemURL(.bass).path))
    }

    /// Mismo orden tras separar: project.json con isEmpty (done) antes de borrar; el WAV restante se limpia al abrir.
    func testInterruptedDeletionAfterSeparationKeepsProjectConsistent() async throws {
        let env = try await Env(withMeter: true)
        await env.meter.setSilent(["other.wav"])
        await env.library.setStemFileRemover { _ in throw Boom() }
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        await env.library.waitForSeparations()
        let p = try await env.project(id)
        XCTAssertTrue(p.stems.first { $0.kind == .other }!.isEmpty)
        XCTAssertTrue(p.stems.first { $0.kind == .other }!.levelMeasured)
        XCTAssertFalse(p.stems.contains { !$0.isEmpty && !FileManager.default.fileExists(atPath: ProjectLayout(folder: try! env.folder(id)).stemURL($0.kind).path) })
        let needs = try await env.library.needsReseparation(id: id)
        XCTAssertFalse(needs)

        await env.library.setStemFileRemover { url in try? FileManager.default.removeItem(at: url) }
        _ = try await env.library.open(id: id)
        await env.library.waitForSeparations()
        XCTAssertFalse(FileManager.default.fileExists(atPath: ProjectLayout(folder: try env.folder(id)).stemURL(.other).path))
    }

    /// Estado dañado de proyectos ya afectados: isEmpty == false y sin WAV → necesita reseparar; no rompe abrir.
    func testMissingNonEmptyStemNeedsReseparationAndDoesNotBreakOpen() async throws {
        let env = try await Env(withMeter: true)
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        await env.library.waitForSeparations()
        let layout = ProjectLayout(folder: try env.folder(id))
        try FileManager.default.removeItem(at: layout.stemURL(.other))
        let needs = try await env.library.needsReseparation(id: id)
        XCTAssertTrue(needs)
        try env.profile.save(EquipmentProfile(projectsFolder: env.root, workingSampleRate: 48000))
        let opened = try await env.library.open(id: id)
        await env.library.waitForMigrations()
        XCTAssertEqual(opened.separation.state, .done)
        XCTAssertEqual(try ProjectFile.load(folder: layout.folder).song.sampleRate, 48000, "la reconversión salta el stem que falta")
    }
}
