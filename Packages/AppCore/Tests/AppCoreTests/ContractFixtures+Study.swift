import Foundation
import Store
import XCTest
@testable import AppCore

// 2.C1: fixtures del área `study` (28 métodos, eventos study.state/position/levels/analysis/guitars).
// Proyecto sembrado separado, con análisis (beats, downbeats, acordes), dos secciones (una solo), bucle guardado y guitarras L/R.

// MARK: - Ayudantes comunes a `study` y `tab`

extension FixtureRig {
    /// Rig con el modo de audio simulado y servicios propios (el `init(area:)` original no los admite).
    init(area: String, services: JobServices?, tab: TabServices? = nil) throws {
        self.area = area
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-fixtures-\(UUID().uuidString)", isDirectory: true)
        projects = dir.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        bridge = try Bridge(options: LaunchOptions(projectsFolder: projects, supportDir: dir.appendingPathComponent("Support"),
                                                   audio: .simulated),
                            mediaBase: "https://tf.media/", reveal: nil, services: services, tab: tab)
    }

    /// Llama al Router sin volcar nada.
    func call(_ method: String, _ params: String = "{}") async throws -> [String: Any] {
        let r = await bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
    }

    /// Como `golden`, con el nombre de fichero completo (`<método>.result.<sufijo>.json`).
    func goldenFile(_ fileName: String, _ json: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = Self.fixturesRoot.appendingPathComponent(area).appendingPathComponent(fileName)
        let text = try canonical(json)
        if ProcessInfo.processInfo.environment["TF_WRITE_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        } else {
            XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), text, "Deriva del contrato en \(area)/\(fileName)", file: file, line: line)
        }
    }

    /// Resultado de una llamada ya hecha, volcado con sufijo de estado: `<método>.result.<sufijo>.json`.
    func variant(_ method: String, _ suffix: String, _ response: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws {
        let result = try XCTUnwrap(response["result"], "\(method): \(response)", file: file, line: line)
        try goldenFile("\(method).result.\(suffix).json", try Self.text(result), file: file, line: line)
    }

    /// Evento cuyo payload es el de una respuesta (`study.state` = `StudyTransport`, `tab.state` = `TabState`).
    func eventFromResult(_ name: String, _ response: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws {
        try golden(name, .event, try Self.text(try XCTUnwrap(response["result"], "\(name): \(response)", file: file, line: line)),
                   file: file, line: line)
    }

    /// Espera hasta que se cumpla la condición (máx. 10 s).
    @MainActor
    func until(_ cond: @MainActor () async throws -> Bool) async throws -> Bool {
        let end = Date().addingTimeInterval(10)
        while Date() < end {
            if try await cond() { return true }
            try await Task.sleep(for: .milliseconds(30))
        }
        return try await cond()
    }
}

/// Siembra un tema separado en `projects` (bajo, batería y, si se pide, guitarras L/R) con análisis opcional.
@MainActor
enum FixtureSeed {
    static let analysis = StudyKitBridge.Analysis(
        beats: [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0], downbeats: [0.5, 2.5], bpm: 120, beatsPerBar: 4,
        chords: [StudyKitBridge.Chord(start: 0, end: 2, index: 0), StudyKitBridge.Chord(start: 2, end: 4, index: 7)],
        key: "C:maj", keyConfidence: 0.4)

    @discardableResult
    static func project(in root: URL, analysis withAnalysis: Bool = true, separated: Bool = true, guitars: Bool = false,
                        sections: Bool = false, tabSource: TabSourceChoice? = nil) throws -> Project {
        var p = Project(song: Song(title: "Tema", artist: "Banda", source: "source/original.wav", sourceSHA256: "abc",
                                   sourceFormat: "wav", sourceSampleRate: StudyTests.sampleRate, sourceChannels: 2,
                                   sampleRate: StudyTests.sampleRate, duration: StudyTests.seconds))
        p.separation = SeparationState(state: separated ? .done : .none, model: "m",
                                       finishedAt: separated ? Date(timeIntervalSince1970: 1_700_000_000) : nil)
        p.stems = [Stem(kind: .bass, file: "stems/bass.wav"), Stem(kind: .drums, file: "stems/drums.wav")]
        if sections {
            p.sections = [Section(name: "Intro", start: 0, end: 2), Section(name: "Solo", start: 2, end: 4, solo: true)]
            p.study.loops = [Loop(name: "Riff", start: 1, end: 2)]
        }
        if guitars {
            p.stems.append(Stem(kind: .guitar, file: "stems/guitar.wav"))
            p.guitars = [Guitar(role: .left, file: GuitarRole.left.relativePath), Guitar(role: .right, file: GuitarRole.right.relativePath)]
        }
        p.tabSource = tabSource
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
        if withAnalysis, separated {
            let src = StudyKitBridge.Source(separationModel: "m", separationFinishedAt: p.separation.finishedAt, sourceSHA256: "abc")
            try StudyKitBridge.saveCache(analysis, source: src, cache: layout.analysisCache)
        }
        try ProjectFile.save(p, to: folder)
        return p
    }
}

// MARK: - study

@MainActor
final class ContractFixturesStudyTests: XCTestCase {
    func openParams(_ p: Project) -> String { "{\"projectId\":\"\(p.id.uuidString)\"}" }

    func testStudyArea() async throws {
        let box = AnalyzerBox()
        let rig = try FixtureRig(area: "study", services: JobServices(importer: EditsImporter(), separator: EditsSeparator(), levelMeter: nil,
                                                                       analyzer: EditsAnalyzer(box: box, delay: 0), guitarSplitter: nil))
        defer { rig.cleanup() }
        let p = try FixtureSeed.project(in: rig.projects, guitars: true, sections: true)
        let captured = StudyCoreDeviationsTests.Captured()
        rig.bridge.send = { captured.add($0) }

        // Sin tema abierto, todo método salvo open/close da not-open.
        try await rig.run("study.play", paramsOnly: true)
        try await rig.runExpectingError("study.play", params: "{}")

        let opened = try await rig.run("study.open", params: openParams(p))
        let sections = try XCTUnwrap((opened["result"] as? [String: Any])?["sections"] as? [[String: Any]])
        let introId = try XCTUnwrap(sections.first?["id"] as? String)
        let soloId = try XCTUnwrap(sections.last?["id"] as? String)
        try await rig.run("study.snapshot")

        // Transporte (cada respuesta es también el payload de `study.state`).
        try await rig.run("study.play")
        // El reloj simulado avanza entre `play` y `pause` (position 0,0091 a veces): se fija a 0 en el volcado.
        let paused = try await rig.runNormalized("study.pause", zero: ["position"])
        try eventFromResult("study.state", paused, rig)
        try await rig.run("study.seek", params: "{\"seconds\":1.5}")
        try await rig.run("study.setRate", params: "{\"rate\":0.75}")
        try await rig.run("study.setTranspose", params: "{\"semitones\":-2,\"fineCents\":15}")
        try await rig.run("study.setCapo", params: "{\"capo\":3}")
        // K7/K8: el cambio de capo reemite `study.analysis` con el análisis al día (acordes con display y shape).
        let analysisEvent = try XCTUnwrap(captured.payloads("study.analysis").last { $0["analysis"] != nil }, "study.setCapo debía reemitir study.analysis")
        try rig.goldenFile("study.analysis.event.withChords.json", try FixtureRig.text(analysisEvent))
        try await rig.run("study.setLoop", params: "{\"start\":1,\"end\":2,\"name\":\"Riff\"}")
        // Ajuste por arrastre (D-3): `chord` (pulsos) y `bar` (compases, ⌥), con el nombre por defecto de SwiftUI.
        for snap in ["chord", "bar"] {
            let r = try await rig.call("study.setLoop", "{\"start\":0.7,\"end\":2.2,\"snap\":\"\(snap)\"}")
            try rig.goldenFile("study.setLoop.params.\(snap).json", "{\"start\":0.7,\"end\":2.2,\"snap\":\"\(snap)\"}")
            try rig.variant("study.setLoop", snap, r)
        }
        _ = try await rig.call("study.setLoop", "{\"start\":1,\"end\":2,\"name\":\"Riff\"}")   // vuelve al bucle de antes
        try await rig.run("study.setMetronome", params: "{\"on\":true,\"gainDB\":-6}")
        try await rig.run("study.setMix", params: "{\"channel\":\"bass\",\"gainDB\":-3,\"mute\":false,\"solo\":true}")
        try await rig.run("study.setMaster", params: "{\"gainDB\":-1.5}")

        // Ediciones.
        try await rig.run("study.analyze")
        try await rig.run("study.setKey", params: "{\"key\":\"A:min\"}")
        // K8: la interfaz manda la tonalidad como la ve (transpuesta -2); el núcleo deshace la transposición.
        do {
            let params = "{\"shown\":{\"tonic\":\"G\",\"mode\":\"min\"}}"
            try rig.goldenFile("study.setKey.params.shown.json", params)
            try rig.variant("study.setKey", "shown", try await rig.call("study.setKey", params))
        }
        // K7: forma del acorde mostrado con el capo del transporte (3) y con otro capo.
        try await rig.run("study.chordShape", params: "{\"index\":15}")
        do {
            let params = "{\"index\":15,\"capo\":0}"
            try rig.goldenFile("study.chordShape.params.capo0.json", params)
            try rig.variant("study.chordShape", "capo0", try await rig.call("study.chordShape", params))
        }
        // Vocabulario de la hoja «Acorde» (no exige tema abierto) y `shown` (con transpose -2: «C mayor» visto = D mayor guardado).
        try await rig.run("study.chordVocabulary")
        try await rig.run("study.setChord", params: "{\"start\":2,\"end\":4,\"index\":9}")
        do {
            let params = "{\"start\":2,\"end\":4,\"shown\":{\"root\":0,\"quality\":1}}"
            try rig.goldenFile("study.setChord.params.shown.json", params)
            try rig.variant("study.setChord", "shown", try await rig.call("study.setChord", params))
        }
        try await rig.run("study.splitChord", params: "{\"at\":1}")
        try await rig.run("study.removeChordOverrides", params: "{\"start\":0,\"end\":1}")
        try await rig.run("study.clearChordOverrides")
        let marked = try await rig.run("study.markSection", params: "{\"start\":4.5,\"end\":7,\"solo\":false,\"snap\":\"none\"}")
        let added = try XCTUnwrap((marked["result"] as? [String: Any])?["added"] as? String)
        try await rig.run("study.updateSection", params: "{\"id\":\(rig.jsonString(introId)),\"name\":\"Estrofa\",\"color\":2,\"snap\":\"beat\"}")
        try await rig.run("study.previewSectionEdge", params: "{\"id\":\(rig.jsonString(soloId)),\"start\":true,\"to\":2.5}")
        // Imán del arrastre de bordes (D-2): `chord` y `bar` (⌥) con la regla de `SectionEdgeDrag`.
        for snap in ["chord", "bar"] {
            let params = "{\"id\":\(rig.jsonString(soloId)),\"start\":true,\"to\":2.4,\"snap\":\"\(snap)\"}"
            try rig.goldenFile("study.previewSectionEdge.params.\(snap).json", params)
            try rig.variant("study.previewSectionEdge", snap, try await rig.call("study.previewSectionEdge", params))
        }
        try await rig.run("study.nudgeSectionEdge", params: "{\"id\":\(rig.jsonString(soloId)),\"start\":false,\"forward\":false,\"bar\":true}")
        try await rig.run("study.deleteSection", params: "{\"id\":\(rig.jsonString(added))}")
        try await rig.run("study.applySections")
        try await rig.run("study.discardSections")
        try await rig.run("study.renameGuitar", params: "{\"role\":\"left\",\"name\":\"Guitarra de Ana\"}")
        try await rig.run("study.setGuitarStereo", params: "{\"on\":true}")
        try await rig.runExpectingError("study.setMix", params: "{\"channel\":\"no-existe\",\"gainDB\":0}")
        try await rig.run("study.close")

        // Eventos que dependen del reloj o del audio: DTO construido a mano.
        try rig.event("study.position", StudyPositionEvent(seconds: 1.5, playing: true))
        try rig.event("study.levels", StudyLevelsEvent(channels: [
            "bass": StudyMeter(rmsDB: -18.5, peakDB: -9.2), "drums": StudyMeter(rmsDB: -22, peakDB: -11.4),
            "guitar_L": StudyMeter(rmsDB: -120, peakDB: -120)]))
        try rig.event("study.analysis", StudyAnalysisEvent(state: "failed", error: "No se pudo analizar el tema."))
        try rig.event("study.guitars", StudyAnalysisEvent(state: "processing", error: nil))
        try rig.goldenFile("study.analysis.event.analyzing.json", try FixtureRig.text(["state": "analyzing"]))
        try rig.goldenFile("study.analysis.event.ready.json", try FixtureRig.text(["state": "ready"]))
        try rig.goldenFile("study.guitars.event.idle.json", try FixtureRig.text(["state": "idle"]))
        // K12: `study.error` ya no existe (nunca se emitió); su fixture se borró.
    }

    private func eventFromResult(_ name: String, _ r: [String: Any], _ rig: FixtureRig) throws { try rig.eventFromResult(name, r) }

    /// Estados de `study.open` según el análisis: missing, analyzing, failed.
    func testStudyOpenAnalysisStates() async throws {
        // missing: separado, sin análisis y sin analizador.
        do {
            let rig = try FixtureRig(area: "study", services: JobServices(importer: EditsImporter(), separator: EditsSeparator(),
                                                                           levelMeter: nil, analyzer: nil, guitarSplitter: nil))
            defer { rig.cleanup() }
            let p = try FixtureSeed.project(in: rig.projects, analysis: false)
            try rig.variant("study.open", "missing", try await rig.call("study.open", openParams(p)))
        }
        // analyzing: el analizador tarda.
        do {
            let rig = try FixtureRig(area: "study", services: JobServices(importer: EditsImporter(), separator: EditsSeparator(),
                levelMeter: nil, analyzer: EditsAnalyzer(box: AnalyzerBox(), delay: 3_000_000_000), guitarSplitter: nil))
            defer { rig.cleanup() }
            let p = try FixtureSeed.project(in: rig.projects, analysis: false)
            let o = try await rig.call("study.open", openParams(p))
            XCTAssertEqual(((o["result"] as? [String: Any])?["analysis"] as? [String: Any])?["state"] as? String, "analyzing")
            try rig.variant("study.open", "analyzing", o)
        }
        // failed: el analizador falla.
        do {
            let box = AnalyzerBox()
            box.fail = "No se pudo analizar el tema."
            let rig = try FixtureRig(area: "study", services: JobServices(importer: EditsImporter(), separator: EditsSeparator(),
                levelMeter: nil, analyzer: EditsAnalyzer(box: box, delay: 0), guitarSplitter: nil))
            defer { rig.cleanup() }
            let p = try FixtureSeed.project(in: rig.projects, analysis: false)
            _ = try await rig.call("study.open", openParams(p))
            var last: [String: Any] = [:]
            let ok = try await rig.until {
                last = try await rig.call("study.snapshot")
                return ((last["result"] as? [String: Any])?["analysis"] as? [String: Any])?["state"] as? String == "failed"
            }
            XCTAssertTrue(ok)
            try rig.variant("study.snapshot", "failed", last)
        }
    }
}
