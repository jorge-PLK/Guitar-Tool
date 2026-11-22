import Foundation
import SourceKit
import Store
import StudyKit
import XCTest
@testable import AppCore
@testable import TabKit
import struct TabKit.SongsterrTrack   // (también existe en SourceKit)

// Hoja de Songsterr (W2-G). Navegador oculto simulado, HTML y JSON SINTÉTICOS (nada de Songsterr real, sin red).

private let searchJSON = """
[{"songId":7,"artist":"Banda","title":"Tema","tracks":[{"partId":0}],"isJunk":false},
 {"songId":8,"artist":"Banda","title":"Tema (live)","tracks":[],"isJunk":false}]
"""

private func songState(_ id: Int) -> String {
    """
    {"meta":{"current":{"songId":\(id),"revisionId":\(id * 100),"artist":"Banda","title":"Tema \(id)","image":"v0-1-abc_D",
     "tracks":[
      {"instrumentId":29,"instrument":"Overdriven Guitar","name":"Rítmica","partId":0,"tuning":[64,59,55,50,45,40],"isGuitar":true},
      {"instrumentId":33,"instrument":"Bass","name":"Bajo","partId":1,"tuning":[43,38,33,28],"isBassGuitar":true},
      {"instrumentId":1024,"instrument":"Drums","name":"Batería","partId":2,"isDrums":true}]}}}
    """
}

private func page(_ id: Int) -> String {
    "<html><head><script id=\"state\" type=\"application/json\">\(songState(id))</script></head><body></body></html>"
}

/// Navegador oculto simulado: devuelve páginas por URL y anota cómo se le llamó.
final class FakePages: HostServices, @unchecked Sendable {
    struct Call: Equatable { var url: URL; var userAgent: String?; var readyScript: String?; var timeout: TimeInterval }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var results: [String: Result<HiddenPage, HiddenPageError>] = [:]
    var calls: [Call] { lock.withLock { _calls } }

    func pickFile(types: [String]) async -> URL? { nil }
    func pickFolder() async -> URL? { nil }
    func load(url: URL, userAgent: String?, readyScript: String?, timeout: TimeInterval) async throws -> HiddenPage {
        lock.withLock { _calls.append(Call(url: url, userAgent: userAgent, readyScript: readyScript, timeout: timeout)) }
        guard let r = results[url.absoluteString] else { throw HiddenPageError.offline }
        return try r.get()
    }
}

final class SongsterrFakeFetcher: HTTPFetching, @unchecked Sendable {
    var result: Result<Data, SourceError> = .success(Data(searchJSON.utf8))
    func data(from url: URL, headers: [String: String]) async throws -> Data { try result.get() }
}

/// `SongsterrClient` real con navegador y HTTP simulados; `prepare` devuelve un plan sintético.
struct SongsterrTestBackend: SongsterrBackend {
    let client: SongsterrClient
    var prepareError: Error?
    let inputs: InputLog

    final class InputLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _items: [SongsterrImportInput] = []
        var items: [SongsterrImportInput] { lock.withLock { _items } }
        func add(_ i: SongsterrImportInput) { lock.withLock { _items.append(i) } }
    }

    func search(artist: String, title: String) async throws -> [SongsterrSearchResult] { try await client.search(artist: artist, title: title) }
    func song(songId: Int) async throws -> SongsterrSong { try await client.song(songId: songId) }
    func song(link: String) async throws -> SongsterrSong { try await client.song(link: link) }

    func prepare(_ input: SongsterrImportInput) async throws -> SongsterrPrepared {
        inputs.add(input)
        input.progress("Alineando con el audio…")
        if let prepareError { throw prepareError }
        let song: SongsterrSong
        if let s = input.song { song = s } else { song = try await client.song(songId: input.songId) }
        return SongsterrPrepared(song: song, plan: Self.plan(song: song, slots: input.slots, beats: input.beats, downbeats: input.downbeats),
                                 grid: SongsterrGridFile(songId: song.songId, revisionId: song.revisionId, beats: [0.4, 0.9, 1.4, 1.9],
                                                         downbeats: [0.4], writtenTempo: 120))
    }

    static func tkTrack(_ name: String, _ kind: TabTrackKind, part: Int, ornaments: Int = 0) -> SongsterrTrack {
        var report = SongsterrImportReport()
        report.notesWithOrnaments = ornaments
        return SongsterrTrack(name: name, instrumentId: nil, songId: 7, revisionId: 700, partId: part, kind: kind,
                                     tuningStrings: kind == .drums ? [] : [64, 59, 55, 50, 45, 40], bars: [],
                                     tempoChanges: [], notes: [], hits: [], report: report)
    }

    /// 0 guitarra (sin stem: extra), 1 bajo, 2 batería. El alineador propone bajo -> 1 (80 %) y batería -> 2 (90 %).
    static func plan(song: SongsterrSong, slots: [SongsterrStemSlot], beats: [Double], downbeats: [Double]) -> SongsterrImportPlan {
        let tracks = [tkTrack("Rítmica", .guitar, part: 0, ornaments: 3), tkTrack("Bajo", .bass, part: 1), tkTrack("Batería", .drums, part: 2)]
        var score = try! TabScore(beatTimes: BeatTimes(beats: beats, downbeats: downbeats, beatsPerBar: 4), duration: 8)
        let subs = Array(repeating: Subdivision.sixteenths, count: score.beats.count)
        score.tracks = tracks.indices.map { i in
            TabTrack(id: SongsterrImportPlan.extraID(i), name: tracks[i].name, kind: tracks[i].kind,
                     tuning: tracks[i].kind == .drums ? nil : (tracks[i].kind == .bass ? Tuning.bass(.standard) : Tuning.guitar(.standard)),
                     source: nil, subdivisions: subs)
        }
        let pairs = [SongsterrStemPair(role: .bass, track: 1, confidence: 0.8, margin: nil),
                     SongsterrStemPair(role: .drums, track: 2, confidence: 0.9, margin: nil)]
        let alignment = SongsterrAlignment(
            offsetBeats: 0, fineOffset: 0, blocks: [], usesBlocks: false, globalSalience: 0, blockSalience: 0,
            structureWarnings: [], score: score,
            placements: tracks.indices.map { SongsterrTrackPlacement(id: SongsterrImportPlan.extraID($0)) },
            pairs: pairs, candidates: pairs.map { SongsterrPairCandidate(role: $0.role, track: $0.track, similarity: $0.confidence) },
            extraTracks: [], timedNotes: [])
        return SongsterrImportPlan(alignment: alignment, tracks: tracks, slots: slots, songId: song.songId, revisionId: song.revisionId)
    }
}

@MainActor
final class SongsterrTests: XCTestCase {
    struct Fixture {
        var folder: URL
        var project: Project
        var bridge: Bridge
        var events: StudyTests.Events
        var pages: FakePages
        var fetcher: SongsterrFakeFetcher
        var log: SongsterrTestBackend.InputLog
    }

    /// Tema con stems de bajo y batería, sin fuente de tablatura. `withHost` = el anfitrión tiene navegador oculto simulado.
    private func makeFixture(source: TabSourceChoice? = nil, withHost: Bool = true, prepareError: Error? = nil) throws -> Fixture {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("sgs-\(UUID().uuidString)", isDirectory: true)
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

        let pages = FakePages()
        pages.results["https://www.songsterr.com/a/wsa/song-tab-s7"] = .success(HiddenPage(status: 200, html: page(7)))
        pages.results["https://www.songsterr.com/a/wsa/song-tab-s8"] = .success(HiddenPage(status: 200, html: page(8)))
        let fetcher = SongsterrFakeFetcher()
        let log = SongsterrTestBackend.InputLog()
        let songsterr = SongsterrServices { loader in
            SongsterrTestBackend(client: SongsterrClient(loader: HiddenPageSongsterrLoader(pages: loader), fetcher: fetcher,
                                                retryDelay: .milliseconds(1)),
                        prepareError: prepareError, inputs: log)
        }
        let events = StudyTests.Events()
        let services = TabServices(transcriber: FakeTabTranscriber(), synth: FakeTabSynth(), songsterr: songsterr)
        let bridge = try Bridge(options: LaunchOptions(projectsFolder: root, supportDir: support, audio: .simulated),
                                mediaBase: "https://tf.media/", reveal: nil, tab: services)
        bridge.send = { events.add($0) }
        if withHost { bridge.host = pages }
        return Fixture(folder: folder, project: p, bridge: bridge, events: events, pages: pages, fetcher: fetcher, log: log)
    }

    private func call(_ f: Fixture, _ method: String, _ params: String = "{}") async -> [String: Any] {
        let out = await f.bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        return (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] ?? [:]
    }

    private func result(_ f: Fixture, _ method: String, _ params: String = "{}") async throws -> [String: Any] {
        let r = await call(f, method, params)
        return try XCTUnwrap(r["result"] as? [String: Any], "\(method): \(r)")
    }

    private func errorCode(_ r: [String: Any]) -> String? { (r["error"] as? [String: Any])?["code"] as? String }

    private func openTab(_ f: Fixture) async throws -> [String: Any] {
        try await result(f, "tab.open", "{\"projectId\":\"\(f.project.id.uuidString)\"}")
    }

    private func waitFor(_ timeout: Double = 10, _ cond: () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if await cond() { return true }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        return await cond()
    }

    /// Espera a que `tab.songsterr.state` cumpla la condición.
    private func waitSheet(_ f: Fixture, _ cond: ([String: Any]) -> Bool) async throws -> [String: Any] {
        var last: [String: Any] = [:]
        let ok = await waitFor {
            let s = (try? await result(f, "tab.songsterr.state")) ?? [:]
            last = s
            return cond(s)
        }
        XCTAssertTrue(ok, "\(last)")
        return last
    }

    // MARK: Navegador oculto

    func testLoaderAdapterPassesScriptAndMapsErrors() async throws {
        let pages = FakePages()
        let url = URL(string: "https://www.songsterr.com/a/wsa/song-tab-s7")!
        pages.results[url.absoluteString] = .success(HiddenPage(status: 200, html: "<html>ok</html>"))
        let loader = HiddenPageSongsterrLoader(pages: pages)
        let html = try await loader.html(for: url)
        XCTAssertEqual(html, "<html>ok</html>")
        XCTAssertEqual(pages.calls, [FakePages.Call(url: url, userAgent: SongsterrHiddenPage.userAgent,
                                                    readyScript: "document.getElementById('state') !== null", timeout: 30)])

        let cases: [(Result<HiddenPage, HiddenPageError>, SongsterrError)] = [
            (.failure(.offline), .offline), (.failure(.readyTimeout), .unknownFormat("sin script de estado")),
            (.failure(.httpStatus(429)), .rateLimited), (.failure(.httpStatus(503)), .httpStatus(503)),
            (.failure(.cancelled), .cancelled),
            (.success(HiddenPage(status: 429, html: "")), .rateLimited), (.success(HiddenPage(status: 404, html: "")), .httpStatus(404))]
        for (r, expected) in cases {
            pages.results[url.absoluteString] = r
            do { _ = try await loader.html(for: url); XCTFail("debía fallar: \(r)") } catch let e as SongsterrError { XCTAssertEqual(e, expected) }
        }
        pages.results[url.absoluteString] = .failure(.unsupported)
        do { _ = try await loader.html(for: url); XCTFail() } catch { XCTAssertEqual(error as? HiddenPageError, .unsupported) }

        // Solo https y host de Songsterr: sin llamar al navegador.
        let before = pages.calls.count
        do { _ = try await loader.html(for: URL(string: "https://example.com/x-s7")!); XCTFail() } catch {
            XCTAssertEqual(error as? SongsterrError, .invalidHost)
        }
        XCTAssertEqual(pages.calls.count, before)
    }

    func testHostWithoutHiddenPagesDefaultsToUnsupported() async throws {
        struct Plain: HostServices {
            func pickFile(types: [String]) async -> URL? { nil }
            func pickFolder() async -> URL? { nil }
        }
        do {
            _ = try await Plain().load(url: URL(string: "https://www.songsterr.com")!, userAgent: nil, readyScript: nil, timeout: 1)
            XCTFail()
        } catch { XCTAssertEqual(error as? HiddenPageError, .unsupported) }
    }

    // MARK: Hoja

    func testOpenWithoutHostIsUnsupportedAndSetSourceStillWorks() async throws {
        let f = try makeFixture(withHost: false)
        // `TabServices.songsterr` de los tests existe, pero un anfitrión real sin navegador da `unsupported` desde el cargador:
        // sin servicios simulados y sin anfitrión, la hoja ni abre.
        let bare = try Bridge(options: LaunchOptions(projectsFolder: f.folder.deletingLastPathComponent(), audio: .simulated),
                              mediaBase: "https://tf.media/", reveal: nil,
                              tab: TabServices(transcriber: FakeTabTranscriber(), synth: FakeTabSynth()))
        let id = f.project.id.uuidString
        _ = await bare.router.handle("{\"id\":1,\"method\":\"tab.open\",\"params\":{\"projectId\":\"\(id)\"}}")
        let out = await bare.router.handle("{\"id\":2,\"method\":\"tab.setSource\",\"params\":{\"source\":\"songsterr\"}}")
        let r = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] ?? [:]
        XCTAssertEqual(errorCode(r), "unsupported")
        let bad = await call(f, "tab.setSource", "{\"source\":\"otra\"}")
        XCTAssertEqual(errorCode(bad), "not-open")
    }

    func testSearchSelectAndSheetEvents() async throws {
        let f = try makeFixture()
        var tab = try await openTab(f)
        XCTAssertEqual(tab["phase"] as? String, "choosingSource")
        let first = try await result(f, "tab.setSource", "{\"source\":\"songsterr\"}")
        XCTAssertEqual(first["phase"] as? String, "choosingSource")

        var s = try await waitSheet(f) { ($0["selected"] as? [String: Any]) != nil }
        XCTAssertEqual(s["open"] as? Bool, true)
        XCTAssertEqual(s["stage"] as? String, "choosing")
        XCTAssertEqual(s["query"] as? String, "Banda · Tema")
        XCTAssertEqual((s["search"] as? [String: Any])?["phase"] as? String, "results")
        let results = try XCTUnwrap(s["results"] as? [[String: Any]])
        XCTAssertEqual(results.map { $0["songId"] as? Int }, [7, 8])
        XCTAssertEqual(results[0]["selected"] as? Bool, true)
        XCTAssertEqual(results[0]["previewUrl"] as? String, "https://www.songsterr.com/a/wsa/song-tab-s7")
        let sel = try XCTUnwrap(s["selected"] as? [String: Any])
        XCTAssertEqual(sel["songId"] as? Int, 7)
        XCTAssertEqual(sel["revisionId"] as? Int, 700)
        let tracks = try XCTUnwrap(sel["tracks"] as? [[String: Any]])
        XCTAssertEqual(tracks.map { $0["name"] as? String }, ["Rítmica", "Bajo", "Batería"])
        XCTAssertEqual(tracks[0]["tuningText"] as? String, "E A D G B E")
        XCTAssertEqual(tracks[1]["tuningText"] as? String, "E A D G")
        XCTAssertEqual(tracks[2]["tuningText"] as? String, "-")
        XCTAssertEqual(s["canUse"] as? Bool, true)
        // Se leyó con el user agent y el script del contrato.
        let c = try XCTUnwrap(f.pages.calls.first)
        XCTAssertEqual(c.readyScript, SongsterrHiddenPage.readyScript)
        XCTAssertEqual(c.userAgent, SongsterrHiddenPage.userAgent)
        XCTAssertFalse(f.events.all("tab.songsterr.state").isEmpty)

        _ = try await result(f, "tab.songsterr.select", "{\"songId\":8}")
        s = try await waitSheet(f) { ($0["selected"] as? [String: Any])?["songId"] as? Int == 8 }
        XCTAssertEqual((s["results"] as? [[String: Any]])?.map { $0["selected"] as? Bool }, [false, true])
        tab = try await result(f, "tab.state")
        XCTAssertEqual(tab["phase"] as? String, "choosingSource")

        let closed = try await result(f, "tab.songsterr.close")
        XCTAssertEqual(closed["open"] as? Bool, false)
    }

    func testSearchFailuresCarryMacLiterals() async throws {
        let f = try makeFixture()
        f.fetcher.result = .success(Data("[]".utf8))
        _ = try await openTab(f)
        _ = try await result(f, "tab.songsterr.open")
        var s = try await waitSheet(f) { ($0["search"] as? [String: Any])?["phase"] as? String == "failed" }
        var issue = try XCTUnwrap((s["search"] as? [String: Any])?["issue"] as? [String: Any])
        XCTAssertEqual(issue["kind"] as? String, "noResults")
        XCTAssertEqual(issue["message"] as? String, "No está en Songsterr.")
        XCTAssertEqual(issue["suggestion"] as? String, "Puedes transcribir el tema automáticamente.")
        XCTAssertEqual(issue["canRetry"] as? Bool, false)

        f.fetcher.result = .failure(SourceError.httpStatus(429))
        _ = try await result(f, "tab.songsterr.retry")
        s = try await waitSheet(f) { (($0["search"] as? [String: Any])?["issue"] as? [String: Any])?["kind"] as? String == "rateLimited" }
        issue = try XCTUnwrap((s["search"] as? [String: Any])?["issue"] as? [String: Any])
        XCTAssertEqual(issue["message"] as? String, "Songsterr está limitando las peticiones. Espera un poco y vuelve a intentarlo.")
        XCTAssertEqual(issue["canRetry"] as? Bool, true)
        XCTAssertNil(issue["suggestion"])
    }

    func testLinkAndDetailFailure() async throws {
        let f = try makeFixture()
        _ = try await openTab(f)
        _ = try await result(f, "tab.songsterr.open")
        _ = try await waitSheet(f) { $0["canUse"] as? Bool == true }
        _ = try await result(f, "tab.songsterr.link", "{\"link\":\"https://example.com/x-s9\"}")
        var s = try await waitSheet(f) { $0["linkIssue"] != nil }
        XCTAssertEqual((s["linkIssue"] as? [String: Any])?["message"] as? String, "Ese enlace no es de Songsterr.")
        // Enlace bueno: se añade arriba y queda marcado.
        f.pages.results["https://www.songsterr.com/a/wsa/song-tab-s9"] = .success(HiddenPage(status: 200, html: page(9)))
        _ = try await result(f, "tab.songsterr.link", "{\"link\":\"https://www.songsterr.com/a/wsa/song-tab-s9\"}")
        s = try await waitSheet(f) { ($0["selected"] as? [String: Any])?["songId"] as? Int == 9 }
        XCTAssertEqual((s["results"] as? [[String: Any]])?.first?["songId"] as? Int, 9)
        XCTAssertNil(s["linkIssue"])
        // 429 de la página del tema al marcar otro resultado.
        f.pages.results["https://www.songsterr.com/a/wsa/song-tab-s8"] = .failure(.httpStatus(429))
        _ = try await result(f, "tab.songsterr.select", "{\"songId\":8}")
        s = try await waitSheet(f) { $0["detailIssue"] != nil }
        XCTAssertEqual((s["detailIssue"] as? [String: Any])?["kind"] as? String, "rateLimited")
        XCTAssertEqual(s["canUse"] as? Bool, false)
    }

    func testUseAssignAcceptWritesScoreGridAndSource() async throws {
        let f = try makeFixture()
        _ = try await openTab(f)
        _ = try await result(f, "tab.songsterr.open")
        _ = try await waitSheet(f) { $0["canUse"] as? Bool == true }
        let working = try await result(f, "tab.songsterr.use")
        XCTAssertNotEqual(working["stage"] as? String, "choosing")
        let s = try await waitSheet(f) { $0["stage"] as? String == "pairing" }
        // La entrada de la importación: stems de bajo y batería, 8 pulsos del análisis, sin secciones de solo.
        let input = try XCTUnwrap(f.log.items.first)
        XCTAssertEqual(input.songId, 7)
        XCTAssertEqual(Set(input.stems.keys), [.bass, .drums])
        XCTAssertEqual(input.beats.count, 8)
        XCTAssertEqual(input.slots.map(\.id), ["bass", "drums"])
        XCTAssertTrue(input.soloSpans.isEmpty)

        let pairing = try XCTUnwrap(s["pairing"] as? [String: Any])
        XCTAssertEqual(pairing["intro"] as? String, "Qué pista de Songsterr va con cada stem. La confianza es el parecido medido con el audio.")
        let slots = try XCTUnwrap(pairing["slots"] as? [[String: Any]])
        XCTAssertEqual(slots.map { $0["stemId"] as? String }, ["bass", "drums"])
        XCTAssertEqual(slots[0]["track"] as? Int, 1)
        XCTAssertEqual(slots[0]["confidenceText"] as? String, "80 %")
        XCTAssertEqual((slots[0]["choices"] as? [[String: Any]])?.first?["label"] as? String, "Bajo (80 %)")
        XCTAssertEqual(pairing["extraNames"] as? [String], ["Rítmica"])
        XCTAssertEqual(pairing["extraText"] as? String,
                       "Pistas extra, sin stem: Rítmica. Entran en la tablatura y en el .gp y solo suenan con «Oír transcripción».")
        XCTAssertEqual((pairing["warnings"] as? [String])?.count, 1)

        // Batería a automática, y de vuelta al bajo.
        var a = try await result(f, "tab.songsterr.assign", "{\"stemId\":\"drums\",\"track\":null}")
        XCTAssertNil(((a["pairing"] as? [String: Any])?["slots"] as? [[String: Any]])?[1]["track"] as? Int)
        a = try await result(f, "tab.songsterr.assign", "{\"stemId\":\"drums\",\"track\":2}")
        XCTAssertEqual((((a["pairing"] as? [String: Any])?["slots"] as? [[String: Any]])?[1])?["track"] as? Int, 2)
        // Una pista de otro tipo no vale: sigue como estaba.
        a = try await result(f, "tab.songsterr.assign", "{\"stemId\":\"bass\",\"track\":2}")
        XCTAssertEqual((((a["pairing"] as? [String: Any])?["slots"] as? [[String: Any]])?[0])?["track"] as? Int, 1)

        let tab = try await result(f, "tab.songsterr.accept")
        XCTAssertEqual(tab["phase"] as? String, "ready")
        XCTAssertEqual(tab["source"] as? String, "songsterr")
        let ids = (tab["tracks"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
        XCTAssertEqual(Set(ids ?? []), ["bass", "drums", "songsterr-0"])
        let origins = Dictionary(uniqueKeysWithValues: ((tab["tracks"] as? [[String: Any]]) ?? []).map { ($0["id"] as! String, $0["origin"] as! String) })
        XCTAssertEqual(origins["bass"], "songsterr")
        XCTAssertEqual((tab["notices"] as? [String])?.count, 1)

        let layout = ProjectLayout(folder: f.folder)
        let saved = try XCTUnwrap(TabService.loadSaved(layout.tabScoreFile))
        XCTAssertEqual(Set(saved.tracks.map(\.id)), ["bass", "drums", "songsterr-0"])
        XCTAssertTrue(saved.tracks.allSatisfy { $0.imported != nil })
        let grid = try XCTUnwrap(SongsterrGridFile.load(layout.tabSongsterrGridFile))
        XCTAssertEqual(grid.songId, 7)
        XCTAssertEqual(grid.revisionId, 700)
        XCTAssertEqual(grid.beats, [0.4, 0.9, 1.4, 1.9])
        let project = try ProjectFile.load(folder: f.folder)
        guard case let .songsterr(songId, revisionId, pairings)? = project.tabSource else { return XCTFail("\(String(describing: project.tabSource))") }
        XCTAssertEqual([songId, revisionId], [7, 700])
        XCTAssertEqual(pairings.map(\.stemID), ["bass", "drums"])
        XCTAssertEqual(pairings.map(\.partId), [1, 2])
        // Hoja cerrada tras aceptar.
        let after = try await result(f, "tab.songsterr.state")
        XCTAssertEqual(after["open"] as? Bool, false)
    }

    func testAllAutomaticAcceptLeavesStemsToTranscribe() async throws {
        let f = try makeFixture()
        _ = try await openTab(f)
        _ = try await result(f, "tab.songsterr.open")
        _ = try await waitSheet(f) { $0["canUse"] as? Bool == true }
        _ = try await result(f, "tab.songsterr.use")
        _ = try await waitSheet(f) { $0["stage"] as? String == "pairing" }
        _ = try await result(f, "tab.songsterr.allAutomatic")
        let tab = try await result(f, "tab.songsterr.accept")
        let by = Dictionary(uniqueKeysWithValues: ((tab["tracks"] as? [[String: Any]]) ?? []).map { ($0["id"] as! String, $0) })
        // bajo y batería quedan para la automática (sin pista guardada), la extra de Songsterr se conserva.
        XCTAssertEqual(by["bass"]?["transcription"] as? String, "queued")
        XCTAssertEqual(by["drums"]?["transcription"] as? String, "queued")
        XCTAssertEqual(by["songsterr-0"]?["origin"] as? String, "songsterr")
    }

    func testImportFailuresAndBack() async throws {
        let f = try makeFixture(prepareError: SongsterrFormatError(reason: "x"))
        _ = try await openTab(f)
        _ = try await result(f, "tab.songsterr.open")
        _ = try await waitSheet(f) { $0["canUse"] as? Bool == true }
        _ = try await result(f, "tab.songsterr.use")
        var s = try await waitSheet(f) { $0["stage"] as? String == "failed" }
        XCTAssertEqual((s["failure"] as? [String: Any])?["message"] as? String, "Songsterr ha cambiado su formato.")
        let retried = try await result(f, "tab.songsterr.retryImport")
        XCTAssertNotNil(retried["stage"])
        _ = try await waitSheet(f) { $0["stage"] as? String == "failed" }
        XCTAssertEqual(f.log.items.count, 2)
        s = try await result(f, "tab.songsterr.back")
        XCTAssertEqual(s["stage"] as? String, "choosing")
        let noPlan = await call(f, "tab.songsterr.accept")
        XCTAssertEqual(errorCode(noPlan), "not-ready")
    }

    func testAutomaticReturnsToAutomaticSource() async throws {
        let f = try makeFixture()
        _ = try await openTab(f)
        _ = try await result(f, "tab.songsterr.open")
        let tab = try await result(f, "tab.songsterr.automatic")
        XCTAssertEqual(tab["phase"] as? String, "ready")
        XCTAssertEqual(tab["source"] as? String, "automatic")
        XCTAssertEqual(try ProjectFile.load(folder: f.folder).tabSource, .automatic)
        let s = try await result(f, "tab.songsterr.state")
        XCTAssertEqual(s["open"] as? Bool, false)
    }

    func testReviewPairingKeepsPreviousChoices() async throws {
        let f = try makeFixture(source: .songsterr(songId: 7, revisionId: 700, pairings: [
            TabStemPairing(stemID: "bass", partId: 1, solos: nil), TabStemPairing(stemID: "drums", partId: nil, solos: nil)]))
        // Con la fuente ya guardada pero sin partitura importada la pantalla pide elegir de nuevo.
        let tab = try await openTab(f)
        XCTAssertEqual(tab["phase"] as? String, "choosingSource")
        let w = try await result(f, "tab.songsterr.review")
        XCTAssertEqual(w["open"] as? Bool, true)
        let s = try await waitSheet(f) { $0["stage"] as? String == "pairing" }
        let slots = try XCTUnwrap((s["pairing"] as? [String: Any])?["slots"] as? [[String: Any]])
        XCTAssertEqual(slots[0]["track"] as? Int, 1)
        XCTAssertNil(slots[1]["track"] as? Int)   // la batería se había dejado en automática
        XCTAssertEqual(f.log.items.first?.song, nil)   // se lee de nuevo el tema
    }

    func testNotOpenErrors() async throws {
        let f = try makeFixture()
        let a = await call(f, "tab.songsterr.open")
        XCTAssertEqual(errorCode(a), "not-open")
        _ = try await openTab(f)
        let b = await call(f, "tab.songsterr.select", "{\"songId\":7}")
        XCTAssertEqual(errorCode(b), "not-open")
    }
}
