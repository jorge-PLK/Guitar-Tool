import Foundation
import SourceKit
import Store
import XCTest
@testable import AppCore
@testable import TabKit
import struct TabKit.SongsterrTrack

// 2.C1b: fixtures del área `tab` (20 métodos `tab.*`, 15 `tab.songsterr.*`, eventos tab.state/progress/selection/range
// y tab.songsterr.state). Reutiliza los ayudantes de `ContractFixtures+Study.swift` y los dobles de TabTests/SongsterrTests.

private let tabSearchJSON = """
[{"songId":7,"artist":"Banda","title":"Tema","tracks":[{"partId":0}],"isJunk":false},
 {"songId":8,"artist":"Banda","title":"Tema (live)","tracks":[],"isJunk":false}]
"""

private func tabSongState(_ id: Int) -> String {
    """
    {"meta":{"current":{"songId":\(id),"revisionId":\(id * 100),"artist":"Banda","title":"Tema \(id)","image":"v0-1-abc_D",
     "tracks":[
      {"instrumentId":29,"instrument":"Overdriven Guitar","name":"Rítmica","partId":0,"tuning":[64,59,55,50,45,40],"isGuitar":true},
      {"instrumentId":33,"instrument":"Bass","name":"Bajo","partId":1,"tuning":[43,38,33,28],"isBassGuitar":true},
      {"instrumentId":1024,"instrument":"Drums","name":"Batería","partId":2,"isDrums":true}]}}}
    """
}

private func tabPage(_ id: Int) -> String {
    "<html><head><script id=\"state\" type=\"application/json\">\(tabSongState(id))</script></head><body></body></html>"
}

/// Navegador oculto simulado (copia privada del de SongsterrTests, que es `final class` interno pero con su propio estado).
private final class TabFakePages: HostServices, @unchecked Sendable {
    var results: [String: Result<HiddenPage, HiddenPageError>] = [:]
    func pickFile(types: [String]) async -> URL? { nil }
    func pickFolder() async -> URL? { nil }
    func load(url: URL, userAgent: String?, readyScript: String?, timeout: TimeInterval) async throws -> HiddenPage {
        guard let r = results[url.absoluteString] else { throw HiddenPageError.offline }
        return try r.get()
    }
}

/// Compuerta de la búsqueda simulada: mientras está cerrada, `data(from:)` espera sin depender del tiempo.
private final class TabSearchGate: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func close() { lock.withLock { closed = true } }
    func open() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            closed = false
            defer { waiters = [] }
            return waiters
        }
        pending.forEach { $0.resume() }
    }
    func pass() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let wait = lock.withLock { () -> Bool in
                if closed { waiters.append(c) }
                return closed
            }
            if !wait { c.resume() }
        }
    }
}

private struct TabFetcher: HTTPFetching {
    var gate: TabSearchGate?
    func data(from url: URL, headers: [String: String]) async throws -> Data {
        await gate?.pass()
        return Data(tabSearchJSON.utf8)
    }
}

private func phase(_ s: [String: Any]) -> String? { (s["search"] as? [String: Any])?["phase"] as? String }

/// Proyecto de `tab` con la fecha de modificación de los stems fijada (entra en `fingerprint.modifiedMillis`).
@MainActor
private func seedTab(in root: URL, analysis: Bool = true, tabSource: TabSourceChoice? = nil) throws -> Project {
    let p = try FixtureSeed.project(in: root, analysis: analysis, tabSource: tabSource)
    let layout = ProjectLayout(folder: root.appendingPathComponent("Banda - Tema", isDirectory: true))
    for kind in [StemKind.bass, .drums] {
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
                                              ofItemAtPath: layout.stemURL(kind).path)
    }
    return p
}

@MainActor
final class ContractFixturesTabTests: XCTestCase {
    func openParams(_ p: Project) -> String { "{\"projectId\":\"\(p.id.uuidString)\"}" }

    private func result(_ r: [String: Any]) -> [String: Any] { r["result"] as? [String: Any] ?? [:] }
    private func tracks(_ s: [String: Any]) -> [[String: Any]] { s["tracks"] as? [[String: Any]] ?? [] }

    // MARK: tab.* con fuente automática

    func testTabAutomatic() async throws {
        let rig = try FixtureRig(area: "tab", services: nil,
                                 tab: TabServices(transcriber: FakeTabTranscriber(), synth: FakeTabSynth(), songsterr: nil))
        defer { rig.cleanup() }
        let p = try seedTab(in: rig.projects, tabSource: .automatic)

        // Sin tablatura abierta.
        try await rig.run("tab.state", paramsOnly: true)
        try await rig.run("tab.keyMap")   // estático: vale con la tablatura cerrada
        try await rig.runExpectingError("tab.state", params: "{}")

        let opened = try await rig.run("tab.open", params: openParams(p))
        try rig.variant("tab.open", "working", opened)
        try rig.eventFromResult("tab.state", opened)

        // TB10: `tab.open` ya arranca la cola; se espera a que termine y luego se rehace una pista a mano.
        var last: [String: Any] = [:]
        func allReady() async throws -> Bool {
            last = try await rig.call("tab.state")
            let t = tracks(result(last))
            return !t.isEmpty && t.allSatisfy { $0["transcription"] as? String == "ready" }
        }
        var ready = try await rig.until { try await allReady() }
        XCTAssertTrue(ready, "\(last)")
        let queued = try await rig.run("tab.transcribe", params: "{\"track\":\"bass\"}")
        XCTAssertEqual(result(queued)["queued"] as? [String], ["bass"], "\(queued)")
        ready = try await rig.until { try await allReady() }
        XCTAssertTrue(ready, "\(last)")
        try rig.variant("tab.open", "ready", ["result": result(last)])
        try await rig.run("tab.state")

        let ids = tracks(result(last)).compactMap { $0["id"] as? String }
        XCTAssertTrue(ids.contains("bass"), "\(ids)")
        try await rig.run("tab.score", params: "{\"track\":\"bass\"}")
        try await rig.run("tab.selectTrack", params: "{\"track\":\"drums\"}")
        _ = try await rig.call("tab.selectTrack", "{\"track\":\"bass\"}")
        try await rig.run("tab.toggleMute", params: "{\"track\":\"drums\"}")
        try await rig.run("tab.toggleSolo", params: "{\"track\":\"bass\"}")
        try await rig.run("tab.setListening", params: "{\"track\":\"bass\",\"on\":true}")
        try await rig.run("tab.setAllListening", params: "{\"on\":false}")
        try await rig.run("tab.beatClick", params: "{\"track\":0,\"bar\":1,\"beat\":1}")
        try await rig.run("tab.beatDrag", params: "{\"track\":0,\"bar\":1,\"beat\":3}")
        try await rig.run("tab.noteClick", params: "{\"track\":0,\"bar\":0,\"beat\":1,\"string\":2,\"shift\":false}")
        try await rig.run("tab.select", params: "{\"track\":\"bass\",\"beat\":5,\"tick\":0,\"string\":2}")
        try await rig.run("tab.span", params: "{\"action\":\"extendForward\"}")

        // Ediciones: una por `op` (cada una pisa `tab.edit.params/result`, así que se vuelcan como variantes).
        try await rig.run("tab.edit", params: "{\"op\":\"editMode\",\"on\":true}")
        let ops: [(String, String)] = [
            ("digit", "{\"op\":\"digit\",\"value\":5}"),
            ("ornament", "{\"op\":\"ornament\",\"name\":\"vibrato\"}"),
            ("key", "{\"op\":\"key\",\"key\":\"ArrowRight\"}"),
            ("tuning", "{\"op\":\"tuning\",\"track\":\"bass\",\"preset\":\"dropD\"}"),
            ("moveString", "{\"op\":\"moveString\",\"up\":false}"),
            ("duration", "{\"op\":\"duration\",\"sign\":1}"),
            ("addNote", "{\"op\":\"addNote\"}"),
            ("move", "{\"op\":\"move\",\"forward\":true}"),
            ("undo", "{\"op\":\"undo\"}"),
            ("redo", "{\"op\":\"redo\"}"),
            ("delete", "{\"op\":\"delete\"}"),
            ("deselect", "{\"op\":\"deselect\"}")]
        for (name, params) in ops {
            let r = try await rig.call("tab.edit", params)
            if r["result"] == nil { XCTFail("tab.edit \(name): \(r)"); continue }
            try rig.goldenFile("tab.edit.params.\(name).json", params)
            try rig.variant("tab.edit", name, r)
        }
        // «Sin bucle» conservando el ancla, y cierre de avisos (después de las ediciones: dejan de ver el tramo).
        try rig.goldenFile("tab.span.params.clearKeepAnchor.json", "{\"action\":\"clear\",\"keepAnchor\":true}")
        try rig.variant("tab.span", "clearKeepAnchor", try await rig.call("tab.span", "{\"action\":\"clear\",\"keepAnchor\":true}"))
        try await rig.run("tab.dismissNotices")
        // Batería: golpe.
        _ = try await rig.call("tab.selectTrack", "{\"track\":\"drums\"}")
        try rig.variant("tab.select", "drums", try await rig.call("tab.select", "{\"track\":\"drums\",\"beat\":5,\"tick\":0}"))
        try rig.goldenFile("tab.select.params.drums.json", "{\"track\":\"drums\",\"beat\":5,\"tick\":0}")
        let hit = try await rig.call("tab.edit", "{\"op\":\"hit\",\"piece\":\"kick\"}")
        if hit["result"] != nil {
            try rig.goldenFile("tab.edit.params.hit.json", "{\"op\":\"hit\",\"piece\":\"kick\"}")
            try rig.variant("tab.edit", "hit", hit)
        } else { try rig.goldenFile("tab.edit.error.hit.json", try FixtureRig.text(hit["error"] ?? [:])) }
        try await rig.runExpectingError("tab.edit", params: "{\"op\":\"nope\"}")

        try await rig.run("tab.exportName")
        let gp = rig.dir.appendingPathComponent("tema.gp").path
        try await rig.run("tab.export", params: "{\"data\":\"R1AF\",\"path\":\(rig.jsonString(gp))}")
        try rig.variant("tab.export", "unsaved", try await rig.call("tab.export", "{\"data\":\"R1AF\"}"))
        try await rig.run("tab.cancel")
        try await rig.run("tab.close")

        // Eventos que dependen del reloj o de la transcripción: DTO construido a mano.
        try rig.event("tab.progress", TabProgressEvent(state: "transcribing", track: "bass", fraction: 0.4, error: nil))
        try rig.goldenFile("tab.progress.event.failed.json",
                           try FixtureRig.text(["state": "failed", "track": "bass", "fraction": 0.4, "error": "No se pudo transcribir la pista."]))
        try rig.goldenFile("tab.progress.event.done.json", try FixtureRig.text(["state": "done", "track": "bass", "fraction": 1]))
        try rig.event("tab.selection", TabSelectionEvent(bar: 2, fraction: 0.25))
        try rig.goldenFile("tab.selection.event.none.json", try FixtureRig.text(["bar": -1, "fraction": 0]))
        try rig.event("tab.range", TabRangeEvent(startBar: 1, startFraction: 0.5, endBar: 3, endFraction: 0.25))
        try rig.goldenFile("tab.range.event.none.json",
                           try FixtureRig.text(["startBar": -1, "startFraction": 0, "endBar": -1, "endFraction": 0]))
    }

    // MARK: Estados de tab.open

    func testTabOpenStates() async throws {
        // waitingAnalysis: sin análisis y con analizador lento.
        do {
            let rig = try FixtureRig(area: "tab", services: JobServices(importer: EditsImporter(), separator: EditsSeparator(), levelMeter: nil,
                analyzer: EditsAnalyzer(box: AnalyzerBox(), delay: 3_000_000_000), guitarSplitter: nil),
                tab: TabServices(transcriber: FakeTabTranscriber(), synth: FakeTabSynth(), songsterr: nil))
            defer { rig.cleanup() }
            let p = try seedTab(in: rig.projects, analysis: false, tabSource: .automatic)
            try rig.variant("tab.open", "waitingAnalysis", try await rig.call("tab.open", openParams(p)))
        }
        // choosingSource: sin fuente elegida.
        do {
            let rig = try FixtureRig(area: "tab", services: nil,
                                     tab: TabServices(transcriber: FakeTabTranscriber(), synth: FakeTabSynth(), songsterr: nil))
            defer { rig.cleanup() }
            let p = try seedTab(in: rig.projects)
            try rig.variant("tab.open", "choosingSource", try await rig.call("tab.open", openParams(p)))
            try rig.variant("tab.setSource", "automatic", try await rig.call("tab.setSource", "{\"source\":\"automatic\"}"))
            try rig.goldenFile("tab.setSource.params.automatic.json", "{\"source\":\"automatic\"}")
        }
    }

    // MARK: Songsterr

    private func sheet(_ rig: FixtureRig, _ cond: @escaping ([String: Any]) -> Bool) async throws -> [String: Any] {
        var last: [String: Any] = [:]
        let ok = try await rig.until {
            last = result(try await rig.call("tab.songsterr.state"))
            return cond(last)
        }
        XCTAssertTrue(ok, "\(last)")
        return last
    }

    func testTabSongsterr() async throws {
        let pages = TabFakePages()
        let gate = TabSearchGate()
        defer { gate.open() }
        pages.results["https://www.songsterr.com/a/wsa/song-tab-s7"] = .success(HiddenPage(status: 200, html: tabPage(7)))
        pages.results["https://www.songsterr.com/a/wsa/song-tab-s8"] = .success(HiddenPage(status: 200, html: tabPage(8)))
        let songsterr = SongsterrServices { loader in
            SongsterrTestBackend(client: SongsterrClient(loader: HiddenPageSongsterrLoader(pages: loader), fetcher: TabFetcher(gate: gate),
                                                         retryDelay: .milliseconds(1)),
                                 prepareError: nil, inputs: .init())
        }
        let rig = try FixtureRig(area: "tab", services: nil,
                                 tab: TabServices(transcriber: FakeTabTranscriber(), synth: FakeTabSynth(), songsterr: songsterr))
        defer { rig.cleanup() }
        rig.bridge.host = pages
        let p = try seedTab(in: rig.projects)

        try await rig.run("tab.songsterr.retry", paramsOnly: true)
        try await rig.runExpectingError("tab.songsterr.retry", params: "{}")
        try await rig.call("tab.open", openParams(p)).isEmpty ? XCTFail() : ()
        let sourced = try await rig.call("tab.setSource", "{\"source\":\"songsterr\"}")
        try rig.goldenFile("tab.setSource.params.songsterr.json", "{\"source\":\"songsterr\"}")
        try rig.variant("tab.setSource", "songsterr", sourced)

        _ = try await rig.call("tab.songsterr.open")
        _ = try await sheet(rig) { phase($0) == "results" }
        try await rig.run("tab.songsterr.open", params: "{}")
        let st = try await sheet(rig) { phase($0) == "results" && ($0["busy"] as? Bool) == false }
        try rig.variant("tab.songsterr.state", "results", ["result": st])
        try rig.goldenFile("tab.songsterr.state.event.json", try FixtureRig.text(st))
        try await rig.run("tab.songsterr.state")
        try await rig.run("tab.songsterr.select", params: "{\"songId\":7}")
        _ = try await sheet(rig) { ($0["canUse"] as? Bool) == true }
        try await rig.run("tab.songsterr.link", params: "{\"link\":\"https://www.songsterr.com/a/wsa/song-tab-s8\"}")
        _ = try await sheet(rig) { ($0["busy"] as? Bool) == false }
        // La respuesta de `search` es el estado tras un solo `yield`: se retiene la búsqueda para que sea «searching» por construcción.
        gate.close()
        try await rig.run("tab.songsterr.search")
        gate.open()
        _ = try await sheet(rig) { phase($0) == "results" && ($0["busy"] as? Bool) == false }
        try await rig.run("tab.songsterr.retry")
        _ = try await sheet(rig) { phase($0) == "results" && ($0["busy"] as? Bool) == false }
        _ = try await rig.call("tab.songsterr.select", "{\"songId\":7}")
        _ = try await sheet(rig) { ($0["canUse"] as? Bool) == true }

        let using = try await rig.run("tab.songsterr.use")
        try rig.variant("tab.songsterr.use", "working", using)
        let pairing = try await sheet(rig) { ($0["stage"] as? String) == "pairing" }
        try rig.variant("tab.songsterr.state", "pairing", ["result": pairing])
        let slots = (pairing["pairing"] as? [String: Any])?["slots"] as? [[String: Any]] ?? []
        let stemId = try XCTUnwrap(slots.first?["stemId"] as? String, "\(pairing)")
        try await rig.run("tab.songsterr.assign", params: "{\"stemId\":\(rig.jsonString(stemId)),\"track\":0}")
        try await rig.run("tab.songsterr.allAutomatic")
        try await rig.run("tab.songsterr.back")
        _ = try await sheet(rig) { ($0["stage"] as? String) == "choosing" }
        _ = try await rig.call("tab.songsterr.use")
        _ = try await sheet(rig) { ($0["stage"] as? String) == "pairing" }
        try await rig.run("tab.songsterr.retryImport")
        _ = try await sheet(rig) { ($0["stage"] as? String) == "pairing" }
        try await rig.run("tab.songsterr.accept")
        // La búsqueda que arranca `review` queda retenida: el result es «searching» por construcción, no por carrera de tiempos.
        gate.close()
        try await rig.run("tab.songsterr.review")
        gate.open()
        _ = try await sheet(rig) { ($0["stage"] as? String) == "pairing" }
        try await rig.run("tab.songsterr.close")
        try await rig.run("tab.songsterr.automatic")

        // Variantes de estado construidas a mano.
        let failed = SongsterrSheetState(
            open: true, stage: "choosing", query: "Banda · Tema", search: SongsterrSearchInfo(phase: "failed", issue: SongsterrIssueInfo(.offline)),
            results: [], selected: nil, loadingSongId: nil, detailIssue: nil, linkIssue: nil, busy: false, canUse: false,
            workingText: nil, failure: nil, pairing: nil)
        try rig.goldenFile("tab.songsterr.state.result.searchFailed.json", try Self.encode(failed))

        // Paso working (descarga de pistas) y paso failed (fallo de importación reintentable).
        let working = SongsterrSheetState(
            open: true, stage: "working", query: "Banda · Tema", search: SongsterrSearchInfo(phase: "results", issue: nil),
            results: [], selected: nil, loadingSongId: nil, detailIssue: nil, linkIssue: nil, busy: false, canUse: true,
            workingText: SongsterrSheet.downloadingText, failure: nil, pairing: nil)
        try rig.goldenFile("tab.songsterr.state.result.working.json", try Self.encode(working))
        let importFailed = SongsterrSheetState(
            open: true, stage: "failed", query: "Banda · Tema", search: SongsterrSearchInfo(phase: "results", issue: nil),
            results: [], selected: nil, loadingSongId: nil, detailIssue: nil, linkIssue: nil, busy: false, canUse: true,
            workingText: nil, failure: SongsterrIssueInfo(.offline), pairing: nil)
        try rig.goldenFile("tab.songsterr.state.result.failed.json", try Self.encode(importFailed))

        let choices = [SongsterrChoiceInfo(track: 0, name: "Rítmica", similarity: 0.82, label: "Rítmica (82 %)"),
                       SongsterrChoiceInfo(track: 1, name: "Solista", similarity: nil, label: "Solista")]
        let solos = SongsterrPairingInfo(
            intro: SongsterrSheet.pairingIntro,
            slots: [SongsterrSlotInfo(stemId: "guitar", name: "Guitarra", kind: "guitar", role: "lead", track: nil, confidence: nil,
                                      confidenceText: nil, choices: choices,
                                      solos: [SongsterrSoloRowInfo(index: 0, start: 12, end: 20, clock: "0:12", track: 1, confidence: 0.82,
                                                                   confidenceText: "82 %", choices: choices),
                                              SongsterrSoloRowInfo(index: 1, start: 61, end: 70, clock: "1:01", track: nil, confidence: nil,
                                                                   confidenceText: nil, choices: choices)]),
                    SongsterrSlotInfo(stemId: "bass", name: "Bajo", kind: "bass", role: "bass", track: 1, confidence: 0.8,
                                      confidenceText: "80 %", choices: choices, solos: [])],
            extraNames: ["Rítmica"], extraText: "Pistas extra, sin stem: Rítmica",
            warnings: ["La estructura del tema difiere de la del audio."])
        let pairingSolos = SongsterrSheetState(
            open: true, stage: "pairing", query: "Banda · Tema", search: SongsterrSearchInfo(phase: "results", issue: nil),
            results: [], selected: nil, loadingSongId: nil, detailIssue: nil, linkIssue: nil, busy: false, canUse: true,
            workingText: nil, failure: nil, pairing: solos)
        try rig.goldenFile("tab.songsterr.state.result.pairingSolos.json", try Self.encode(pairingSolos))
    }

    private static func encode<T: Encodable>(_ v: T) throws -> String {
        String(decoding: try JSONEncoder().encode(v), as: UTF8.self)
    }
}
