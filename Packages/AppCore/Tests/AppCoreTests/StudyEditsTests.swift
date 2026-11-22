import Foundation
import Store
import XCTest
@testable import AppCore

// 8.5b: ediciones del estudio (análisis, tonalidad, acordes, secciones, guitarras). Todo en `--audio simulated`, proyectos
// temporales y analizador simulado.

struct EditsImporter: AudioImporting {
    func importAudio(from source: URL, to destination: URL, sampleRate: Double,
                     progress: @escaping @Sendable (Double) -> Void) async throws -> ImportedAudioInfo {
        throw SeparationFailure(message: "no se usa")
    }
    func resample(_ file: URL, to destination: URL, sampleRate: Double) async throws {}
}

struct EditsSeparator: StemSeparating {
    var modelIdentifier: String? { "fake@1" }
    func separate(input: URL, outputDirectory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {}
}

final class AnalyzerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _fail: String?
    var fail: String? { get { lock.withLock { _fail } } set { lock.withLock { _fail = newValue } } }
}

/// Escribe una caché vigente tras una espera corta (o falla mientras `box.fail` tenga un mensaje).
struct EditsAnalyzer: StudyAnalyzing {
    let box: AnalyzerBox
    var delay: UInt64 = 300_000_000
    func source(_ p: Project) -> StudyKitBridge.Source {
        StudyKitBridge.Source(separationModel: p.separation.model, separationFinishedAt: p.separation.finishedAt,
                              sourceSHA256: p.song.sourceSHA256)
    }
    func isCurrent(project: Project, layout: ProjectLayout) async -> Bool {
        StudyKitBridge.loadCached(source(project), cache: layout.analysisCache) != nil
    }
    func analyze(project: Project, layout: ProjectLayout) async throws {
        try await Task.sleep(nanoseconds: delay)
        if let m = box.fail { throw SeparationFailure(message: m) }
        let chords = [StudyKitBridge.Chord(start: 0, end: 2, index: 0), StudyKitBridge.Chord(start: 2, end: 4, index: 7)]
        try StudyKitBridge.saveCache(
            StudyKitBridge.Analysis(beats: [0.5, 1.0, 1.5, 2.0, 2.5, 3.0], downbeats: [0.5, 2.5], bpm: 120, beatsPerBar: 4,
                                    chords: chords, key: "C:maj", keyConfidence: 0.4),
            source: source(project), cache: layout.analysisCache)
    }
}

/// Almacén que siempre falla al escribir (disco lleno simulado).
struct FailingStudyStore: StudyStoring {
    struct Full: LocalizedError { var errorDescription: String? { "disco lleno" } }
    func saveStudy(id: UUID, study: StudyState, sections: [Section]) async throws { throw Full() }
    func saveGuitarNames(id: UUID, names: [GuitarRole: String]) async throws { throw Full() }
    func saveGuitarStereoSplit(id: UUID, _ on: Bool) async throws -> GuitarOptions { throw Full() }
}

@MainActor
final class StudyEditsTests: XCTestCase {
    final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(name: String, payload: [String: Any])] = []
        func add(_ json: String) {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
                  let name = o["event"] as? String else { return }
            lock.withLock { items.append((name, o["payload"] as? [String: Any] ?? [:])) }
        }
        func all(_ name: String) -> [[String: Any]] { lock.withLock { items.filter { $0.name == name }.map(\.payload) } }
    }

    struct Rig {
        var folder: URL
        var project: Project
        var bridge: Bridge
        var events: Events
        var box: AnalyzerBox
    }

    func makeRig(analysis: Bool = true, separated: Bool = true, analyzer: Bool = true, guitars: Bool = false) throws -> Rig {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("edits-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("projects", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }

        var p = Project(song: Song(title: "Tema", artist: "Banda", source: "source/original.wav", sourceSHA256: "abc",
                                   sourceFormat: "wav", sourceSampleRate: StudyTests.sampleRate, sourceChannels: 2,
                                   sampleRate: StudyTests.sampleRate, duration: StudyTests.seconds))
        p.separation = SeparationState(state: separated ? .done : .none, model: "m",
                                       finishedAt: separated ? Date(timeIntervalSince1970: 1_700_000_000) : nil)
        p.stems = [Stem(kind: .bass, file: "stems/bass.wav"), Stem(kind: .drums, file: "stems/drums.wav")]
        p.sections = [Section(name: "Intro", start: 0, end: 2), Section(name: "Solo", start: 2, end: 4, solo: true)]
        p.study.loops = [Loop(name: "Riff", start: 1, end: 2)]
        if guitars {
            p.stems.append(Stem(kind: .guitar, file: "stems/guitar.wav"))
            p.guitars = [Guitar(role: .left, file: GuitarRole.left.relativePath), Guitar(role: .right, file: GuitarRole.right.relativePath)]
        }
        let folder = root.appendingPathComponent("Banda - Tema", isDirectory: true)
        let layout = ProjectLayout(folder: folder)
        try layout.createSkeleton()
        try StudyTests.writeSine(layout.stemURL(.bass), frequency: 110)
        try StudyTests.writeSine(layout.stemURL(.drums), frequency: 330)
        if guitars {
            try StudyTests.writeSine(layout.stemURL(.guitar), frequency: 220)
            try StudyTests.writeSine(layout.guitarURL(.left), frequency: 220)
            try StudyTests.writeSine(layout.guitarURL(.right), frequency: 247)
        }
        let box = AnalyzerBox()
        if analysis, separated {
            let a = EditsAnalyzer(box: box, delay: 0)
            let source = a.source(p)
            try StudyKitBridge.saveCache(
                StudyKitBridge.Analysis(beats: [0.5, 1.0, 1.5, 2.0, 2.5, 3.0], downbeats: [0.5, 2.5], bpm: 120, beatsPerBar: 4,
                    chords: [StudyKitBridge.Chord(start: 0, end: 2, index: 0), StudyKitBridge.Chord(start: 2, end: 4, index: 7)],
                    key: "C:maj", keyConfidence: 0.4), source: source, cache: layout.analysisCache)
        }
        try ProjectFile.save(p, to: folder)
        let services = JobServices(importer: EditsImporter(), separator: EditsSeparator(), levelMeter: nil,
                                   analyzer: analyzer ? EditsAnalyzer(box: box) : nil, guitarSplitter: nil)
        let events = Events()
        let bridge = try Bridge(options: LaunchOptions(projectsFolder: root, supportDir: support, audio: .simulated),
                                mediaBase: "https://tf.media/", reveal: nil, services: services)
        bridge.send = { events.add($0) }
        return Rig(folder: folder, project: p, bridge: bridge, events: events, box: box)
    }

    func call(_ r: Rig, _ method: String, _ params: String = "{}") async -> [String: Any] {
        let out = await r.bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        return (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] ?? [:]
    }

    /// Llama y devuelve el `result` (falla el test si hay error).
    func ok(_ r: Rig, _ method: String, _ params: String = "{}", file: StaticString = #filePath, line: UInt = #line) async throws -> [String: Any] {
        let o = await call(r, method, params)
        return try XCTUnwrap(o["result"] as? [String: Any], "\(method): \(o)", file: file, line: line)
    }

    func errorCode(_ r: Rig, _ method: String, _ params: String = "{}") async -> String? {
        ((await call(r, method, params))["error"] as? [String: Any])?["code"] as? String
    }

    func open(_ r: Rig) async throws -> [String: Any] {
        try await ok(r, "study.open", "{\"projectId\":\"\(r.project.id.uuidString)\"}")
    }

    func saved(_ r: Rig) throws -> Project { try ProjectFile.load(folder: r.folder) }

    func waitFor(_ timeout: Double = 6, _ cond: @escaping @MainActor () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond() { return true }; try? await Task.sleep(nanoseconds: 20_000_000) }
        return cond()
    }

    func chords(_ s: [String: Any]) -> [[String: Any]] { (s["analysis"] as? [String: Any])?["chords"] as? [[String: Any]] ?? [] }
    func sections(_ s: [String: Any]) -> [[String: Any]] { s["sections"] as? [[String: Any]] ?? [] }
    func state(_ s: [String: Any]) -> String? { (s["analysis"] as? [String: Any])?["state"] as? String }

    // MARK: Análisis

    func testAnalyzeWhilePlayingKeepsPlaybackAndLoop() async throws {
        let r = try makeRig(analysis: false)
        let opened = try await open(r)
        XCTAssertEqual(state(opened), "analyzing", "study.open ya pide el análisis")
        XCTAssertTrue(chords(opened).isEmpty)
        _ = try await ok(r, "study.setLoop", "{\"start\":1,\"end\":3,\"name\":\"Zona\"}")
        _ = try await ok(r, "study.play")
        let started = try await ok(r, "study.analyze")
        XCTAssertTrue(["analyzing", "ready"].contains(state(started) ?? ""))
        let done = await waitFor { r.events.all("study.analysis").contains { $0["state"] as? String == "ready" } }
        XCTAssertTrue(done, "\(r.events.all("study.analysis"))")
        XCTAssertEqual(r.events.all("study.analysis").compactMap { $0["state"] as? String }, ["analyzing", "ready"])
        let snap = try await ok(r, "study.snapshot")
        XCTAssertEqual(state(snap), "ready")
        XCTAssertEqual(chords(snap).count, 2)
        XCTAssertEqual(((snap["analysis"] as? [String: Any])?["key"] as? [String: Any])?["detected"] as? String, "C:maj")
        let t = try XCTUnwrap(snap["transport"] as? [String: Any])
        XCTAssertEqual(t["playing"] as? Bool, true, "el análisis no corta la reproducción")
        let loop = try XCTUnwrap(t["loop"] as? [String: Any], "el bucle se conserva")
        XCTAssertEqual(loop["start"] as? Double, 1)
        XCTAssertEqual(loop["name"] as? String, "Zona")
        XCTAssertEqual((t["metronome"] as? [String: Any])?["available"] as? Bool, true)
        _ = try await ok(r, "study.pause")
    }

    func testAnalyzeFailureThenRetry() async throws {
        let r = try makeRig(analysis: false)
        r.box.fail = "modelo roto"
        _ = try await open(r)
        _ = try await ok(r, "study.analyze")
        let failed = await waitFor { r.events.all("study.analysis").contains { $0["state"] as? String == "failed" } }
        XCTAssertTrue(failed)
        let f = r.events.all("study.analysis").first { $0["state"] as? String == "failed" }
        XCTAssertEqual(f?["error"] as? String, "modelo roto")
        let failedSnap = try await ok(r, "study.snapshot")
        XCTAssertEqual(state(failedSnap), "failed")
        r.box.fail = nil
        let again = try await ok(r, "study.analyze")
        XCTAssertEqual(state(again), "analyzing")
        let ready = await waitFor { r.events.all("study.analysis").contains { $0["state"] as? String == "ready" } }
        XCTAssertTrue(ready, "\(r.events.all("study.analysis"))")
        let finalSnap = try await ok(r, "study.snapshot")
        XCTAssertEqual(chords(finalSnap).count, 2)
    }

    func testAnalyzeErrors() async throws {
        let r = try makeRig(analysis: false)
        let code = await errorCode(r, "study.analyze")
        XCTAssertEqual(code, "not-open")
        let none = try makeRig(analysis: false, analyzer: false)
        _ = try await open(none)
        let unavailable = await errorCode(none, "study.analyze")
        XCTAssertEqual(unavailable, "analysis-unavailable")
        let pending = try makeRig(analysis: false, separated: false)
        _ = try await open(pending)
        let notSeparated = await errorCode(pending, "study.analyze")
        XCTAssertEqual(notSeparated, "not-separated")
        // Ya vigente: ready sin emitir trabajo.
        let ready = try makeRig()
        _ = try await open(ready)
        let again = try await ok(ready, "study.analyze")
        XCTAssertEqual(state(again), "ready")
    }

    /// `study.open` pide el análisis como el Mac; sin analizador o sin separación se queda en `missing`.
    func testOpenRequestsAnalysis() async throws {
        let r = try makeRig(analysis: false)
        let opened = try await open(r)
        XCTAssertEqual(state(opened), "analyzing")
        let done = await waitFor { r.events.all("study.analysis").contains { $0["state"] as? String == "ready" } }
        XCTAssertTrue(done, "\(r.events.all("study.analysis"))")
        let none = try makeRig(analysis: false, analyzer: false)
        let sNone = try await open(none)
        XCTAssertEqual(state(sNone), "missing")
        let pending = try makeRig(analysis: false, separated: false)
        let sPending = try await open(pending)
        XCTAssertEqual(state(sPending), "missing")
        let ready = try makeRig()
        let sReady = try await open(ready)
        XCTAssertEqual(state(sReady), "ready")
    }

    // MARK: Tonalidad

    func testSetKey() async throws {
        let r = try makeRig()
        _ = try await open(r)
        let s = try await ok(r, "study.setKey", "{\"key\":\"Db:maj\"}")
        let key = try XCTUnwrap((s["analysis"] as? [String: Any])?["key"] as? [String: Any])
        XCTAssertEqual(key["override"] as? String, "C#:maj")
        XCTAssertEqual(key["effective"] as? String, "C#:maj")
        XCTAssertEqual(key["detected"] as? String, "C:maj")
        for bad in ["H:maj", "C", "C:7", "", "A:min:x"] {
            let c = await errorCode(r, "study.setKey", "{\"key\":\"\(bad)\"}")
            XCTAssertEqual(c, "bad-params", bad)
        }
        // El rebote de 0,5 s: aún no está escrito; luego sí.
        XCTAssertNil(try saved(r).study.keyOverride)
        let wrote = await waitFor { (try? self.saved(r))?.study.keyOverride == "C#:maj" }
        XCTAssertTrue(wrote)
        let back = try await ok(r, "study.setKey", "{\"key\":null}")
        XCTAssertNil(((back["analysis"] as? [String: Any])?["key"] as? [String: Any])?["override"] as? String)
        await r.bridge.shutdownAsync()
        XCTAssertNil(try saved(r).study.keyOverride)
        let plain = try makeRig(analysis: false)
        _ = try await open(plain)
        let none = await errorCode(plain, "study.setKey", "{\"key\":\"A:min\"}")
        XCTAssertEqual(none, "no-analysis")
        let closed = try makeRig()
        let notOpen = await errorCode(closed, "study.setKey", "{\"key\":null}")
        XCTAssertEqual(notOpen, "not-open")
    }

    // MARK: Acordes

    func testChordEditsAndPersistence() async throws {
        let r = try makeRig()
        _ = try await open(r)
        var s = try await ok(r, "study.setChord", "{\"start\":0,\"end\":2,\"label\":\"D:min\"}")
        let first = try XCTUnwrap(chords(s).first)
        XCTAssertEqual(first["overridden"] as? Bool, true)
        let expected = StudyEditsBridge.chordIndex(label: "D:min")
        XCTAssertEqual(first["index"] as? Int, expected)
        XCTAssertEqual(first["name"] as? String, "Dm")
        s = try await ok(r, "study.setChord", "{\"start\":2,\"end\":4,\"index\":169}")
        XCTAssertEqual(chords(s).last?["name"] as? String, "N")
        XCTAssertEqual((s["chordOverrides"] as? [[String: Any]])?.count, 2)
        // Validación.
        for bad in ["{\"start\":2,\"end\":2,\"index\":1}", "{\"start\":-1,\"end\":2,\"index\":1}", "{\"start\":0,\"end\":2,\"index\":170}",
                    "{\"start\":0,\"end\":2,\"label\":\"Z\"}", "{\"start\":0,\"end\":2}", "{\"start\":0,\"end\":2,\"index\":1,\"label\":\"C\"}"] {
            let c = await errorCode(r, "study.setChord", bad)
            XCTAssertEqual(c, "bad-params", bad)
        }
        let order = await errorCode(r, "study.removeChordOverrides", "{\"start\":3,\"end\":1}")
        XCTAssertEqual(order, "bad-params")
        s = try await ok(r, "study.removeChordOverrides", "{\"start\":0.5,\"end\":1}")
        XCTAssertEqual((s["chordOverrides"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(chords(s).first?["overridden"] as? Bool, false)
        await r.bridge.shutdownAsync()   // guarda ya
        let p = try saved(r)
        XCTAssertEqual(p.study.chordOverrides.count, 1)
        XCTAssertEqual(p.study.chordOverrides.first?.index, 169, "\(p.study.chordOverrides)")
    }

    func testSplitAndClearChords() async throws {
        let r = try makeRig()
        _ = try await open(r)
        var s = try await ok(r, "study.splitChord", "{\"at\":1.1}")
        XCTAssertEqual((s["chordOverrides"] as? [[String: Any]])?.count, 2)
        // Como el Mac: dos tramos con el índice del acorde (no cambia lo que se ve hasta editar una mitad).
        let ov = try XCTUnwrap(s["chordOverrides"] as? [[String: Any]])
        XCTAssertEqual(ov.map { $0["start"] as? Double }, [0, 1])
        XCTAssertEqual(ov.map { $0["end"] as? Double }, [1, 2])
        s = try await ok(r, "study.setChord", "{\"start\":0,\"end\":1,\"label\":\"D:min\"}")
        XCTAssertEqual(chords(s).prefix(2).map { $0["name"] as? String }, ["Dm", "Cm"])
        var code = await errorCode(r, "study.splitChord", "{\"at\":2.02}")   // pulso 2.0 a < 50 ms del inicio
        XCTAssertEqual(code, "cannot-split")
        code = await errorCode(r, "study.splitChord", "{\"at\":20}")
        XCTAssertEqual(code, "cannot-split")
        s = try await ok(r, "study.clearChordOverrides")
        XCTAssertEqual((s["chordOverrides"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(chords(s).count, 2)
    }

    // MARK: Secciones

    func testPreviewSectionEdge() async throws {
        let r = try makeRig()
        _ = try await open(r)
        var s = try await ok(r, "study.markSection", "{\"start\":4,\"end\":6}")
        let a = try XCTUnwrap(s["added"] as? String)
        s = try await ok(r, "study.markSection", "{\"start\":6,\"end\":8}")
        let b = try XCTUnwrap(s["added"] as? String)
        let before = try await ok(r, "study.snapshot")
        let n = r.events.all("study.state").count
        func range(_ o: [String: Any], _ id: String) -> (Double, Double) {
            let x = sections(o).first { $0["id"] as? String == id } ?? [:]
            return (x["start"] as? Double ?? -1, x["end"] as? Double ?? -1)
        }
        // Vecina empujada.
        var o = try await ok(r, "study.previewSectionEdge", "{\"id\":\"\(a)\",\"start\":false,\"to\":7}")
        XCTAssertEqual(range(o, a).1, 7, accuracy: 0.001)
        XCTAssertEqual(range(o, b).0, 7, accuracy: 0.001)
        XCTAssertEqual(range(o, b).1, 8, accuracy: 0.001)
        // Mínimo 0,5 s para la vecina.
        o = try await ok(r, "study.previewSectionEdge", "{\"id\":\"\(a)\",\"start\":false,\"to\":99}")
        XCTAssertEqual(range(o, a).1, 7.5, accuracy: 0.001)
        XCTAssertEqual(range(o, b).0, 7.5, accuracy: 0.001)
        // Un solo frena el borde (el solo es 2...4).
        o = try await ok(r, "study.previewSectionEdge", "{\"id\":\"\(a)\",\"start\":true,\"to\":3}")
        XCTAssertEqual(range(o, a).0, 4, accuracy: 0.001)
        // Errores.
        var code = await errorCode(r, "study.previewSectionEdge", "{\"id\":\"\(UUID().uuidString)\",\"start\":true,\"to\":3}")
        XCTAssertEqual(code, "not-found")
        code = await errorCode(r, "study.previewSectionEdge", "{\"id\":\"no\",\"start\":true,\"to\":3}")
        XCTAssertEqual(code, "bad-params")
        code = await errorCode(r, "study.previewSectionEdge", "{\"id\":\"\(a)\",\"start\":true,\"to\":1e999}")
        XCTAssertNotNil(code)
        // Sin efectos.
        let after = try await ok(r, "study.snapshot")
        XCTAssertEqual(sections(after).map { range(["sections": [$0]], $0["id"] as? String ?? "").1 },
                       sections(before).map { range(["sections": [$0]], $0["id"] as? String ?? "").1 })
        XCTAssertEqual(sections(after).map { range(["sections": [$0]], $0["id"] as? String ?? "").0 },
                       sections(before).map { range(["sections": [$0]], $0["id"] as? String ?? "").0 })
        XCTAssertEqual(r.events.all("study.state").count, n, "no emite eventos")
        XCTAssertEqual(try saved(r).sections.count, 2)
        let closed = try makeRig()
        let c = await errorCode(closed, "study.previewSectionEdge", "{\"id\":\"\(a)\",\"start\":true,\"to\":3}")
        XCTAssertEqual(c, "not-open")
    }

    func testSectionsMarkUpdateApplyDiscard() async throws {
        let r = try makeRig()
        _ = try await open(r)
        var s = try await ok(r, "study.markSection", "{\"start\":5,\"end\":7}")
        let id = try XCTUnwrap(s["added"] as? String)
        XCTAssertEqual(sections(s).count, 3)
        XCTAssertEqual(sections(s).last?["name"] as? String, "Sección 1")
        XCTAssertEqual(s["unappliedSections"] as? Bool, true)
        XCTAssertEqual(try saved(r).sections.count, 2, "sin aplicar no se escribe")
        // Reglas del Mac: no se crea empezando dentro de otra sección ni más corta que 0,5 s.
        var code = await errorCode(r, "study.markSection", "{\"start\":3,\"end\":6}")
        XCTAssertEqual(code, "section-not-created")
        code = await errorCode(r, "study.markSection", "{\"start\":4.2,\"end\":4.4}")
        XCTAssertEqual(code, "section-not-created")
        code = await errorCode(r, "study.markSection", "{\"start\":6,\"end\":5}")
        XCTAssertEqual(code, "bad-params")
        code = await errorCode(r, "study.markSection", "{\"start\":6,\"end\":99}")
        XCTAssertEqual(code, "bad-params")
        code = await errorCode(r, "study.markSection", "{\"start\":4.2,\"end\":5,\"snap\":\"x\"}")
        XCTAssertEqual(code, "bad-params")
        // Hueco que entra en la siguiente: se queda en su borde.
        s = try await ok(r, "study.markSection", "{\"start\":4.1,\"end\":5.4,\"solo\":true}")
        let soloAdded = try XCTUnwrap(sections(s).first { $0["id"] as? String == s["added"] as? String })
        XCTAssertEqual(soloAdded["solo"] as? Bool, true)
        XCTAssertEqual(soloAdded["name"] as? String, "Solo 2")
        XCTAssertEqual(soloAdded["end"] as? Double ?? 0, 5, accuracy: 0.001)
        // Actualizar: nombre, color, borde.
        s = try await ok(r, "study.updateSection", "{\"id\":\"\(id)\",\"name\":\"Puente\",\"color\":3,\"end\":7.5}")
        var sec = try XCTUnwrap(sections(s).first { $0["id"] as? String == id })
        XCTAssertEqual(sec["name"] as? String, "Puente")
        XCTAssertEqual(sec["color"] as? Int, 3)
        XCTAssertEqual(sec["end"] as? Double, 7.5)
        s = try await ok(r, "study.updateSection", "{\"id\":\"\(id)\",\"color\":null}")
        sec = try XCTUnwrap(sections(s).first { $0["id"] as? String == id })
        XCTAssertNil(sec["color"] as? Int)
        s = try await ok(r, "study.updateSection", "{\"id\":\"\(id)\",\"name\":\"X\"}")
        sec = try XCTUnwrap(sections(s).first { $0["id"] as? String == id })
        XCTAssertEqual(sec["color"] as? Int, nil)
        // Borde con ajuste a pulso (2.6 -> pulso 2.5) contra un solo: el inicio no entra en el solo (2...4): se para en 4.
        s = try await ok(r, "study.updateSection", "{\"id\":\"\(id)\",\"start\":2.6,\"snap\":\"beat\"}")
        sec = try XCTUnwrap(sections(s).first { $0["id"] as? String == id })
        XCTAssertEqual(sec["start"] as? Double ?? 0, 5, accuracy: 0.001, "tope del solo vecino (5 = fin del solo marcado)")
        code = await errorCode(r, "study.updateSection", "{\"id\":\"\(id)\",\"color\":9}")
        XCTAssertEqual(code, "bad-params")
        code = await errorCode(r, "study.updateSection", "{\"id\":\"\(UUID().uuidString)\",\"name\":\"a\"}")
        XCTAssertEqual(code, "not-found")
        code = await errorCode(r, "study.updateSection", "{\"id\":\"no\",\"name\":\"a\"}")
        XCTAssertEqual(code, "bad-params")
        // Descartar vuelve a lo guardado.
        s = try await ok(r, "study.discardSections")
        XCTAssertEqual(sections(s).count, 2)
        XCTAssertEqual(s["unappliedSections"] as? Bool, false)
        // Marcar, borrar y aplicar.
        s = try await ok(r, "study.markSection", "{\"start\":5,\"end\":7}")
        let id2 = try XCTUnwrap(s["added"] as? String)
        s = try await ok(r, "study.markSection", "{\"start\":7,\"end\":7.9}")
        let id3 = try XCTUnwrap(s["added"] as? String)
        s = try await ok(r, "study.deleteSection", "{\"id\":\"\(id3)\"}")
        XCTAssertEqual(sections(s).count, 3)
        code = await errorCode(r, "study.deleteSection", "{\"id\":\"\(id3)\"}")
        XCTAssertEqual(code, "not-found")
        s = try await ok(r, "study.updateSection", "{\"id\":\"\(id2)\",\"name\":\"Final\"}")
        s = try await ok(r, "study.applySections")
        XCTAssertEqual(s["unappliedSections"] as? Bool, false)
        let p = try saved(r)
        XCTAssertEqual(p.sections.map(\.name), ["Intro", "Solo", "Final"])
        XCTAssertEqual(p.study.loops.count, 1)
    }

    /// 8.6d-C: `study.open` y `study.snapshot` traen `guitars` y `unappliedSections` (sin llamar a `discardSections`).
    func testOpenAndSnapshotCarryGuitarsAndUnapplied() async throws {
        let r = try makeRig()
        var o = try await open(r)
        var g = try XCTUnwrap(o["guitars"] as? [String: Any])
        XCTAssertEqual(g["process"] as? String, "idle")
        XCTAssertEqual(g["stereoSplit"] as? Bool, false)
        XCTAssertEqual((g["names"] as? [String: String])?["rhythm"], GuitarRole.rhythm.defaultName)
        XCTAssertEqual(o["unappliedSections"] as? Bool, false)
        XCTAssertEqual(o["audio"] as? [String: String], ["mode": "simulated", "outputName": StudyAudio.simulatedOutputName])
        _ = try await ok(r, "study.markSection", "{\"start\":5,\"end\":7}")
        o = try await ok(r, "study.snapshot")
        g = try XCTUnwrap(o["guitars"] as? [String: Any])
        XCTAssertEqual(o["unappliedSections"] as? Bool, true)
        XCTAssertNil(g["saveError"] as? String)
        let t = try XCTUnwrap(o["transport"] as? [String: Any])
        XCTAssertEqual(t["outputName"] as? String, StudyAudio.simulatedOutputName)
    }

    /// `study.applySections` con la escritura fallando: `save-failed`, y las secciones siguen sin aplicar.
    func testApplySectionsSaveFailed() async throws {
        let r = try makeRig()
        r.bridge.studyService.storeFactory = { _ in FailingStudyStore() }
        _ = try await open(r)
        _ = try await ok(r, "study.markSection", "{\"start\":5,\"end\":7}")
        let out = await call(r, "study.applySections")
        let e = try XCTUnwrap(out["error"] as? [String: Any], "\(out)")
        XCTAssertEqual(e["code"] as? String, "save-failed")
        XCTAssertTrue((e["message"] as? String ?? "").contains("disco lleno"))
        XCTAssertEqual(try saved(r).sections.count, 2, "no se escribió nada")
    }

    func testSectionSnapOnMarkAndNudge() async throws {
        let r = try makeRig()
        _ = try await open(r)
        var s = try await ok(r, "study.markSection", "{\"start\":4.1,\"end\":4.9,\"snap\":\"none\"}")
        let id = try XCTUnwrap(s["added"] as? String)
        // Sin rejilla más allá de 3 s, el ajuste lleva ambos extremos al último pulso: queda fuera del hueco libre.
        s = try await ok(r, "study.nudgeSectionEdge", "{\"id\":\"\(id)\",\"start\":false,\"forward\":false,\"bar\":true}")
        XCTAssertEqual(sections(s).count, 3)
        s = try await ok(r, "study.updateSection", "{\"id\":\"\(id)\",\"end\":6.1,\"snap\":\"chord\"}")
        let sec = try XCTUnwrap(sections(s).first { $0["id"] as? String == id })
        XCTAssertEqual(sec["end"] as? Double ?? 0, 4.6, accuracy: 0.001, "imán al acorde más cercano (4.0); el mínimo de 0,5 s sobre el inicio (4.1) lo sube")
    }

    // MARK: Guitarras

    /// B1-UI: encolar, avanzar y fallar el trabajo de guitarras avisa a la página (`study.guitars` y `study.state`).
    func testGuitarJobQueuedAndFailedNotifyThePage() async throws {
        let r = try makeRig()
        _ = try await open(r)
        let id = r.project.id
        let before = r.events.all("study.state").count
        r.bridge.studyService.libraryEvent(.guitarSplitQueued(id))
        XCTAssertEqual(r.events.all("study.guitars").last?["state"] as? String, "processing")
        let stateEvent = await waitFor { r.events.all("study.state").count > before }
        XCTAssertTrue(stateEvent, "encolar pide study.state")
        var snap = try await ok(r, "study.snapshot")
        XCTAssertEqual((snap["guitars"] as? [String: Any])?["process"] as? String, "processing")
        let mid = r.events.all("study.state").count
        r.bridge.studyService.libraryEvent(.guitarSplitFailed(id, "Modelo de solista no disponible"))
        let last = r.events.all("study.guitars").last
        XCTAssertEqual(last?["state"] as? String, "failed")
        XCTAssertEqual(last?["error"] as? String, "Modelo de solista no disponible")
        let failEvent = await waitFor { r.events.all("study.state").count > mid }
        XCTAssertTrue(failEvent, "fallar pide study.state")
        snap = try await ok(r, "study.snapshot")
        XCTAssertEqual((snap["guitars"] as? [String: Any])?["process"] as? String, "failed")
    }

    /// B2 (decisión de Jorge): `library.relocate` cierra el estudio abierto y suelta sus ficheros antes de mover.
    func testRelocateMoveClosesOpenStudyAndLeavesNothingBehind() async throws {
        let r = try makeRig()
        _ = try await open(r)
        _ = try await ok(r, "study.play")
        let oldRoot = r.folder.deletingLastPathComponent()
        let dest = oldRoot.deletingLastPathComponent().appendingPathComponent("relocated-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dest) }
        let moved = try await ok(r, "library.relocate", "{\"path\":\"\(dest.path)\",\"mode\":\"move\"}")
        XCTAssertEqual(moved["path"] as? String, dest.path)
        let code = await errorCode(r, "study.snapshot")
        XCTAssertEqual(code, "not-open", "el estudio se cerró")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent(r.folder.lastPathComponent + "/project.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: r.folder.path), "nada queda en la carpeta vieja")
        XCTAssertTrue(r.events.all("library.relocated").count == 1)
    }

    func testGuitarRenameAndStereo() async throws {
        let r = try makeRig(guitars: true)
        let opened = try await open(r)
        XCTAssertEqual(opened["usesSeparatedGuitars"] as? Bool, true)
        var s = try await ok(r, "study.renameGuitar", "{\"role\":\"left\",\"name\":\"  Robe \"}")
        let names = try XCTUnwrap((s["guitars"] as? [String: Any])?["names"] as? [String: String])
        XCTAssertEqual(names["left"], "Robe")
        var channels = try XCTUnwrap((s["transport"] as? [String: Any])?["channels"] as? [[String: Any]])
        XCTAssertEqual(channels.first { $0["id"] as? String == "guitar_L" }?["name"] as? String, "Robe")
        XCTAssertEqual(channels.first { $0["id"] as? String == "guitar_R" }?["name"] as? String, GuitarRole.right.defaultName)
        s = try await ok(r, "study.renameGuitar", "{\"role\":\"right\",\"name\":\"\"}")
        channels = try XCTUnwrap((s["transport"] as? [String: Any])?["channels"] as? [[String: Any]])
        XCTAssertEqual(channels.first { $0["id"] as? String == "guitar_R" }?["name"] as? String, GuitarRole.right.defaultName)
        let bad = await errorCode(r, "study.renameGuitar", "{\"role\":\"bass\",\"name\":\"x\"}")
        XCTAssertEqual(bad, "bad-params")
        // Mezcla: el nombre nuevo no pierde lo ajustado en el canal.
        _ = try await ok(r, "study.setMix", "{\"channel\":\"guitar_L\",\"gainDB\":-6,\"mute\":true}")
        s = try await ok(r, "study.setGuitarStereo", "{\"on\":true}")
        XCTAssertEqual((s["guitars"] as? [String: Any])?["stereoSplit"] as? Bool, true)
        XCTAssertEqual(try saved(r).guitarSettings.stereoSplit, true, "se guarda ya, sin esperar al rebote")
        channels = try XCTUnwrap((s["transport"] as? [String: Any])?["channels"] as? [[String: Any]])
        let left = try XCTUnwrap(channels.first { $0["id"] as? String == "guitar_L" })
        XCTAssertEqual(left["muted"] as? Bool, true)
        XCTAssertEqual(left["gainDB"] as? Double, -6)
        s = try await ok(r, "study.setGuitarStereo", "{\"on\":false}")
        XCTAssertEqual(try saved(r).guitarSettings.stereoSplit, false)
        await r.bridge.shutdownAsync()
        let p = try saved(r)
        XCTAssertEqual(p.guitars.first { $0.role == .left }?.name, "Robe")
        XCTAssertEqual(p.guitars.first { $0.role == .right }?.name, GuitarRole.right.defaultName)
        XCTAssertEqual(p.study.mixer.first { $0.guitarRole == .left }?.muted, true)
    }

    // MARK: Un solo escritor

    func testEditsAndQueueRenameBothSurvive() async throws {
        let r = try makeRig()
        _ = try await open(r)
        _ = try await ok(r, "study.setKey", "{\"key\":\"A:min\"}")
        _ = try await ok(r, "study.setChord", "{\"start\":0,\"end\":1,\"index\":3}")
        let rename = await call(r, "library.rename", "{\"id\":\"\(r.project.id.uuidString)\",\"title\":\"Otro\",\"artist\":\"G\"}")
        XCTAssertNil(rename["error"], "\(rename)")
        await r.bridge.shutdownAsync()
        let p = try saved(r)
        XCTAssertEqual(p.song.title, "Otro")
        XCTAssertEqual(p.study.keyOverride, "A:min")
        XCTAssertEqual(p.study.chordOverrides.count, 1)
    }
}
