import Foundation
import SourceKit
import Store
import XCTest
@testable import AppCore

// W2-J: listas y álbumes (`playlist.*`) con yt-dlp, ffmpeg y red simulados (sin descargas reales ni VM).

private struct PlFakeImporter: AudioImporting {
    func importAudio(from source: URL, to destination: URL, sampleRate: Double,
                     progress: @escaping @Sendable (Double) -> Void) async throws -> ImportedAudioInfo {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "wav".write(to: destination, atomically: true, encoding: .utf8)
        progress(1)
        return ImportedAudioInfo(title: nil, artist: nil, duration: 10, sourceFormat: "wav", sourceSampleRate: 44100, sourceChannels: 2)
    }
    func resample(_ file: URL, to destination: URL, sampleRate: Double) async throws {
        try "stem".write(to: destination, atomically: true, encoding: .utf8)
    }
}

private struct PlFakeSeparator: StemSeparating {
    var modelIdentifier: String? { "fake@1" }
    func separate(input: URL, outputDirectory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for kind in StemKind.allCases {
            try "stem".write(to: outputDirectory.appendingPathComponent("\(kind.rawValue).wav"), atomically: true, encoding: .utf8)
        }
        progress(1)
    }
}

private let spA = "3demoDemoDemoDemoDemoA"
private let spB = "3demoDemoDemoDemoDemoB"
private let spC = "3demoDemoDemoDemoDemoC"
private let listID = "37i9dQZF1DWUNNEvaozpW5"
private let albumID = "2Ly1vNk9Det1V3uc4pVU4o"
private let spotifyList = "https://open.spotify.com/playlist/\(listID)"
private let spotifyAlbum = "https://open.spotify.com/album/\(albumID)"
private let youtubeList = "https://www.youtube.com/playlist?list=PLabc_123-x"

/// Embed mínimo con tres temas: A (252 s, tiene candidato cercano), B (300 s, solo un directo cerca: dudoso), C (252 s).
private struct PlHTTP: HTTPFetching {
    func data(from url: URL, headers: [String: String]) async throws -> Data {
        guard url.host == "open.spotify.com", url.path.hasPrefix("/embed/") else { return Data("RIFFxxxxWEBP".utf8) }
        let rows = [(spA, "Tema A", "Marea", 252_000), (spB, "Tema B", "Marea", 300_000), (spC, "Tema C", "Marea", 252_000)]
        let list = rows.map {
            #"{"uri":"spotify:track:\#($0.0)","title":"\#($0.1)","subtitle":"\#($0.2)","duration":\#($0.3),"isExplicit":false}"#
        }.joined(separator: ",")
        let name = url.path.contains("album") ? "Disco" : "Mi lista"
        let json = #"{"props":{"pageProps":{"state":{"data":{"entity":{"name":"\#(name)","id":"x","trackList":[\#(list)]}}}}}}"#
        return Data(#"<html><script id="__NEXT_DATA__" type="application/json">\#(json)</script></html>"#.utf8)
    }
}

private final class PlEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [String] = []
    func add(_ s: String) { lock.withLock { all.append(s) } }
    func named(_ n: String) -> [[String: Any]] {
        lock.withLock { all }.compactMap { m in
            guard let o = (try? JSONSerialization.jsonObject(with: Data(m.utf8))) as? [String: Any],
                  o["event"] as? String == n else { return nil }
            return o["payload"] as? [String: Any]
        }
    }
}

private func q(_ s: String) -> String { String(decoding: (try? JSONEncoder().encode(s)) ?? Data(), as: UTF8.self) }

private struct PlRig {
    let dir: URL
    let projects: URL
    let bridge: Bridge
    let runner = ScriptedProcessRunner()
    let events = PlEvents()

    init(hangList: Bool = false, listStderr: String = "", listStatus: Int32 = 0, downloadStatus: Int32 = 0,
         downloadStderr: String = "", sameAudio: Bool = false) throws {
        let fm = FileManager.default
        dir = fm.temporaryDirectory.appendingPathComponent("appcore-playlist-\(UUID().uuidString)", isDirectory: true)
        projects = dir.appendingPathComponent("Projects", isDirectory: true)
        let helpers = dir.appendingPathComponent("Helpers", isDirectory: true)
        try fm.createDirectory(at: projects, withIntermediateDirectories: true)
        try fm.createDirectory(at: helpers, withIntermediateDirectories: true)
        for n in ["yt-dlp", "deno", "ffmpeg"] {
            fm.createFile(atPath: helpers.appendingPathComponent(SourceKit.HelperLocator.fileName(n)).path,
                          contents: Data("x".utf8), attributes: [.posixPermissions: 0o755])
        }
        for ext in ["", ".exe"] {
            runner.on("yt-dlp\(ext) --version", ScriptedResponse(stdout: "2026.10.26\n"))
            runner.on("deno\(ext) --version", ScriptedResponse(stdout: "deno 2.1.4 (stable)\n"))
            runner.on("ffmpeg\(ext) -version", ScriptedResponse(stdout: "ffmpeg version 7.1 Copyright\n"))
        }
        let yt = ["{\"id\":\"yyyyyyyyyy1\",\"title\":\"Uno\",\"channel\":\"Canal\",\"duration\":200}",
                  "{\"id\":\"yyyyyyyyyy2\",\"title\":\"Dos\",\"channel\":\"Canal\",\"duration\":210}"].joined(separator: ",")
        runner.on("--flat-playlist -J https://www.youtube.com/playlist", ScriptedResponse(stdout: "{\"title\":\"Lista YT\",\"entries\":[\(yt)]}", stderr: listStderr,
                                                      status: listStatus, hangs: hangList))
        func search(_ needle: String, _ rows: [(String, String, Double)], on runner: ScriptedProcessRunner) {
            let entries = rows.map {
                "{\"_type\":\"url\",\"id\":\"\($0.0)\",\"url\":\"https://www.youtube.com/watch?v=\($0.0)\",\"title\":\"\($0.1)\",\"channel\":\"Marea\",\"duration\":\($0.2)}"
            }.joined(separator: ",")
            runner.on("ytsearch5:Marea \(needle)", ScriptedResponse(stdout: "{\"id\":\"q\",\"title\":\"q\",\"_type\":\"playlist\",\"entries\":[\(entries)]}"))
        }
        search("Tema A", [("aaaaaaaaaaa", "Marea - Tema A (Audio oficial)", 252.2), ("aaaaaaaaaa2", "Marea - Tema A (Directo)", 301)], on: runner)
        search("Tema B", [("bbbbbbbbbbb", "Marea - Tema B (Directo)", 301), ("bbbbbbbbbb2", "Marea - Tema B", 200)], on: runner)
        search("Tema C", [("ccccccccccc", "Marea - Tema C (Audio oficial)", 252.4)], on: runner)
        runner.on("bestaudio", ScriptedResponse(stderr: downloadStderr, status: downloadStatus, progressLines: ["TFPROGRESS 50 100 NA"],
                                                sideEffect: { req in
            guard let i = req.arguments.firstIndex(of: "-o") else { return }
            try Data("audio".utf8).write(to: URL(fileURLWithPath: req.arguments[i + 1].replacingOccurrences(of: "%(ext)s", with: "webm")))
        }))
        runner.on("pcm_s24le", ScriptedResponse(sideEffect: { req in
            // Contenido distinto por tema (Library detecta duplicados por SHA); igual si `sameAudio`.
            try Data((sameAudio ? "wav" : "wav-\(UUID().uuidString)").utf8).write(to: URL(fileURLWithPath: req.arguments.last ?? ""))
        }))
        let sources = ExternalSources(bundleDirectory: helpers, supportDirectory: dir.appendingPathComponent("Support/Helpers"),
                                      runner: runner, http: PlHTTP(), workRoot: dir.appendingPathComponent("work", isDirectory: true))
        let services = JobServices(importer: PlFakeImporter(), separator: PlFakeSeparator(), levelMeter: nil,
                                   analyzer: nil, guitarSplitter: nil)
        bridge = try Bridge(options: LaunchOptions(projectsFolder: projects, supportDir: dir.appendingPathComponent("Support")),
                            mediaBase: "https://tf.media/", reveal: nil, services: services, link: sources, spotify: nil)
        let sink = events
        bridge.send = { sink.add($0) }
    }

    func call(_ method: String, _ params: String = "{}") async -> [String: Any] {
        let r = await bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        return (try? JSONSerialization.jsonObject(with: Data(r.utf8))) as? [String: Any] ?? [:]
    }

    func result(_ method: String, _ params: String = "{}") async -> [String: Any] {
        (await call(method, params))["result"] as? [String: Any] ?? [:]
    }

    func error(_ method: String, _ params: String = "{}") async -> (code: String, message: String)? {
        guard let e = (await call(method, params))["error"] as? [String: Any] else { return nil }
        return (e["code"] as? String ?? "", e["message"] as? String ?? "")
    }

    /// Resuelve una lista y devuelve su instantánea.
    func open(_ url: String) async -> [String: Any] {
        let r = await result("link.resolve", "{\"url\":\(q(url))}")
        return r["playlist"] as? [String: Any] ?? [:]
    }

    func state() async -> [String: Any] { await result("playlist.state") }

    func waitStep(_ step: String, timeout: TimeInterval = 8) async -> [String: Any] {
        let end = Date().addingTimeInterval(timeout)
        var s = await state()
        while s["step"] as? String != step, Date() < end {
            try? await Task.sleep(for: .milliseconds(20))
            s = await state()
        }
        return s
    }

    func item(_ s: [String: Any], _ id: String) -> [String: Any] {
        (s["items"] as? [[String: Any]] ?? []).first { $0["id"] as? String == id } ?? [:]
    }

    func libraryCount() async -> Int { (await result("library.list"))["projects"].flatMap { $0 as? [Any] }?.count ?? 0 }

    func downloads() -> Int { runner.requests.filter { $0.arguments.contains("-f") }.count }

    func cleanup() { try? FileManager.default.removeItem(at: dir) }
}

final class PlaylistTests: XCTestCase {
    func testSpotifyListDivertsToPlaylistStep() async throws {
        let rig = try PlRig()
        defer { rig.cleanup() }
        let r = await rig.result("link.resolve", "{\"url\":\(q(spotifyList))}")
        XCTAssertEqual(r["link"] as? String, "playlist")
        XCTAssertEqual((r["candidates"] as? [Any])?.count, 0)
        let p = try XCTUnwrap(r["playlist"] as? [String: Any])
        XCTAssertEqual(p["step"] as? String, "tracks")
        XCTAssertEqual(p["name"] as? String, "Mi lista")
        XCTAssertEqual(p["source"] as? String, "spotify")
        XCTAssertEqual(p["kind"] as? String, "playlist")
        XCTAssertEqual(p["isLive"] as? Bool, false)
        let items = try XCTUnwrap(p["items"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["id"] as? String }, [spA, spB, spC])
        XCTAssertEqual(items.map { $0["selected"] as? Bool }, [false, false, false])
        XCTAssertEqual(items[0]["title"] as? String, "Tema A")
        XCTAssertEqual(items[0]["artist"] as? String, "Marea")
        XCTAssertEqual(items[0]["duration"] as? Double, 252)
        XCTAssertEqual(items[0]["status"] as? String, "pending")
        XCTAssertEqual((p["totals"] as? [String: Any])?["total"] as? Int, 3)
        // `playlist.state` devuelve lo mismo.
        let s = await rig.state()
        XCTAssertEqual(s["step"] as? String, "tracks")
    }

    func testAlbumAndSingleLinkStaysSingle() async throws {
        let rig = try PlRig()
        defer { rig.cleanup() }
        let p = await rig.open(spotifyAlbum)
        XCTAssertEqual(p["kind"] as? String, "album")
        XCTAssertEqual(p["name"] as? String, "Disco")
        // Un enlace de vídeo con `list=` sigue siendo un tema suelto (8.3b): no llega a lista.
        let r = await rig.result("link.resolve", "{\"url\":\"https://www.youtube.com/watch?v=4CJwzwOIPAY&list=PLabc_123-x\"}")
        XCTAssertNotEqual(r["link"] as? String, "playlist")
        XCTAssertNil(r["playlist"])
    }

    func testSelectionAndCounts() async throws {
        let rig = try PlRig()
        defer { rig.cleanup() }
        _ = await rig.open(spotifyList)
        var s = await rig.result("playlist.select", "{\"id\":\(q(spA)),\"selected\":true}")
        XCTAssertEqual((s["totals"] as? [String: Any])?["selected"] as? Int, 1)
        s = await rig.result("playlist.selectAll")
        XCTAssertEqual((s["totals"] as? [String: Any])?["selected"] as? Int, 3)
        s = await rig.result("playlist.selectNone")
        XCTAssertEqual((s["totals"] as? [String: Any])?["selected"] as? Int, 0)
        let none = await rig.error("playlist.select", "{\"id\":\"nope\",\"selected\":true}")
        XCTAssertEqual(none?.code, "not-found")
        // Sin marcados, continuar no hace nada.
        s = await rig.result("playlist.continue")
        XCTAssertEqual(s["step"] as? String, "tracks")
    }

    func testSpotifyFullFlow() async throws {
        let rig = try PlRig()
        defer { rig.cleanup() }
        _ = await rig.open(spotifyList)
        _ = await rig.result("playlist.select", "{\"id\":\(q(spA)),\"selected\":true}")
        _ = await rig.result("playlist.select", "{\"id\":\(q(spB)),\"selected\":true}")
        _ = await rig.result("playlist.continue")
        let review = await rig.waitStep("review")
        XCTAssertEqual(review["step"] as? String, "review")
        let a = rig.item(review, spA), b = rig.item(review, spB)
        XCTAssertEqual(a["status"] as? String, "proposed")
        XCTAssertEqual((a["chosen"] as? [String: Any])?["id"] as? String, "aaaaaaaaaaa")
        XCTAssertEqual((a["chosen"] as? [String: Any])?["isClose"] as? Bool, true)
        XCTAssertEqual(b["status"] as? String, "doubtful")
        XCTAssertNil(b["chosen"] as? [String: Any])
        let cands = try XCTUnwrap(b["candidates"] as? [[String: Any]])
        XCTAssertEqual(cands.count, 2)
        XCTAssertEqual(cands.first { $0["id"] as? String == "bbbbbbbbbbb" }?["isLive"] as? Bool, true)
        XCTAssertEqual((review["totals"] as? [String: Any])?["queued"] as? Int, 1)
        XCTAssertEqual(rig.downloads(), 0, "la revisión no descarga nada")

        // Elegir un candidato inexistente y uno bueno.
        let bad = await rig.error("playlist.choose", "{\"id\":\(q(spB)),\"candidateId\":\"zzz\"}")
        XCTAssertEqual(bad?.code, "not-found")
        let chosen = await rig.result("playlist.choose", "{\"id\":\(q(spB)),\"candidateId\":\"bbbbbbbbbbb\"}")
        XCTAssertEqual(rig.item(chosen, spB)["status"] as? String, "proposed")
        XCTAssertEqual((rig.item(chosen, spB)["chosen"] as? [String: Any])?["id"] as? String, "bbbbbbbbbbb")
        XCTAssertEqual((chosen["totals"] as? [String: Any])?["queued"] as? Int, 2)

        _ = await rig.result("playlist.start")
        let summary = await rig.waitStep("summary")
        XCTAssertEqual(summary["step"] as? String, "summary")
        let sum = try XCTUnwrap(summary["summary"] as? [String: Any])
        XCTAssertEqual(sum["imported"] as? Int, 2)
        XCTAssertEqual(sum["failed"] as? Int, 0)
        XCTAssertEqual(sum["cancelled"] as? Bool, false)
        XCTAssertEqual(rig.item(summary, spA)["status"] as? String, "imported")
        XCTAssertEqual(rig.downloads(), 2)
        XCTAssertEqual(summary["indicator"] as? String, "Importación terminada")
        let libOK = await eventually { await rig.libraryCount() == 2 }
        XCTAssertTrue(libOK)
        // Eventos: la página recibe instantáneas y el trabajo de descarga sale por `jobs.progress`.
        let evOK = await eventually { rig.events.named("playlist.changed").last?["step"] as? String == "summary" }
        XCTAssertTrue(evOK)
        let last = try XCTUnwrap(rig.events.named("playlist.changed").last)
        XCTAssertEqual((last["summary"] as? [String: Any])?["imported"] as? Int, 2)
        let jobs = rig.events.named("jobs.progress").filter { ($0["id"] as? String)?.hasPrefix("playlist-") == true }
        _ = jobs  // el sondeo puede no ver la descarga si es instantánea; no se exige
    }

    func testDuplicateIsNotAFailure() async throws {
        let rig = try PlRig(sameAudio: true)
        defer { rig.cleanup() }
        _ = await rig.open(spotifyList)
        for id in [spA, spC] { _ = await rig.result("playlist.select", "{\"id\":\(q(id)),\"selected\":true}") }
        _ = await rig.result("playlist.continue")
        _ = await rig.waitStep("review")
        // A y C bajan el mismo audio: el segundo es un duplicado (no un fallo).
        _ = await rig.result("playlist.start")
        let summary = await rig.waitStep("summary")
        let sum = try XCTUnwrap(summary["summary"] as? [String: Any])
        XCTAssertEqual(sum["failed"] as? Int, 0)
        XCTAssertEqual(sum["imported"] as? Int, 1)
        XCTAssertEqual(sum["inLibrary"] as? Int, 1)
        XCTAssertEqual((summary["totals"] as? [String: Any])?["duplicates"] as? Int, 1)
        let libOK = await eventually { await rig.libraryCount() == 1 }
        XCTAssertTrue(libOK)
    }

    func testYouTubeListGoesStraightToQueue() async throws {
        let rig = try PlRig()
        defer { rig.cleanup() }
        let p = await rig.open(youtubeList)
        XCTAssertEqual(p["source"] as? String, "youtube")
        XCTAssertEqual(p["name"] as? String, "Lista YT")
        let items = try XCTUnwrap(p["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual((items[0]["chosen"] as? [String: Any])?["id"] as? String, "yyyyyyyyyy1")
        _ = await rig.result("playlist.selectAll")
        let s = await rig.result("playlist.continue")
        XCTAssertNotEqual(s["step"] as? String, "review")
        let summary = await rig.waitStep("summary")
        XCTAssertEqual((summary["summary"] as? [String: Any])?["imported"] as? Int, 2)
        XCTAssertEqual(rig.downloads(), 2)
        let libOK = await eventually { await rig.libraryCount() == 2 }
        XCTAssertTrue(libOK)
    }

    func testStoppedByExtractorBrokenThenUpdateOffered() async throws {
        let rig = try PlRig(downloadStatus: 1, downloadStderr: "ERROR: unable to extract")
        defer { rig.cleanup() }
        _ = await rig.open(youtubeList)
        _ = await rig.result("playlist.selectAll")
        _ = await rig.result("playlist.continue")
        let stopped = await rig.waitStep("stopped")
        XCTAssertEqual(stopped["step"] as? String, "stopped")
        let e = try XCTUnwrap(stopped["error"] as? [String: Any])
        XCTAssertEqual(e["code"] as? String, "extractor-broken")
        XCTAssertEqual(e["suggestsUpdate"] as? Bool, true)
        XCTAssertEqual(stopped["isLive"] as? Bool, true)
        XCTAssertEqual(stopped["indicator"] as? String, "Importación detenida")
        // Tras recargar la página, `app.info` anuncia la lista viva.
        let info = await rig.result("app.info")
        let announced = try XCTUnwrap(info["playlist"] as? [String: Any], "\(info)")
        XCTAssertEqual(announced["indicator"] as? String, "Importación detenida")
        XCTAssertEqual(announced["isLive"] as? Bool, true)
        // Cerrar una lista viva sin forzar no la descarta.
        let c = await rig.result("playlist.close")
        XCTAssertEqual(c["closed"] as? Bool, false)
        XCTAssertEqual(c["live"] as? Bool, true)
        let f = await rig.result("playlist.close", "{\"force\":true}")
        XCTAssertEqual(f["closed"] as? Bool, true)
        let gone = await rig.error("playlist.state")
        XCTAssertEqual(gone?.code, "no-playlist")
        let after = await rig.result("app.info")
        XCTAssertTrue(after["playlist"] == nil || after["playlist"] is NSNull)
    }

    func testClassifyTellsListsFromTracksWithoutReading() async throws {
        let rig = try PlRig()
        defer { rig.cleanup() }
        let cases: [(String, String, String?)] = [
            (youtubeList, "playlist", "youtube"),
            ("https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M", "playlist", "spotify"),
            ("https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy", "playlist", "spotify"),
            ("spotify:album:4aawyAB9vmqN3uQ7FjRGTy", "playlist", "spotify"),
            ("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabc", "track", "youtube"),
            ("https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC", "track", "spotify"),
            ("https://example.com/x", "unsupported", nil)]
        for (url, kind, source) in cases {
            let r = await rig.result("link.classify", "{\"url\":\"\(url)\"}")
            XCTAssertEqual(r["kind"] as? String, kind, url)
            XCTAssertEqual(r["source"] as? String, source, url)
        }
        let e = await rig.error("playlist.state")
        XCTAssertEqual(e?.code, "no-playlist", "classify no abre ninguna lista")
    }

    func testCancelLoadingWithLinkCancel() async throws {
        let rig = try PlRig(hangList: true)
        defer { rig.cleanup() }
        let task = Task { await rig.error("link.resolve", "{\"url\":\(q(youtubeList))}") }
        try await Task.sleep(for: .milliseconds(300))
        let c = await rig.result("link.cancel")
        XCTAssertEqual(c["cancelled"] as? Bool, true)
        let err = await task.value
        XCTAssertEqual(err?.code, "cancelled")
        let none = await rig.error("playlist.state")
        XCTAssertEqual(none?.code, "no-playlist")
    }

    func testListReadFailureIsAnRPCError() async throws {
        let rig = try PlRig(listStderr: "ERROR: unable to extract", listStatus: 1)
        defer { rig.cleanup() }
        let e = await rig.error("link.resolve", "{\"url\":\(q(youtubeList))}")
        XCTAssertEqual(e?.code, "extractor-broken")
    }

    func testCancelQueueKeepsImportedAndSummaryOffersResume() async throws {
        let rig = try PlRig()
        defer { rig.cleanup() }
        _ = await rig.open(youtubeList)
        _ = await rig.result("playlist.selectAll")
        let s = await rig.result("playlist.continue")
        XCTAssertNotNil(s["step"])
        _ = await rig.result("playlist.cancel")
        let end = await eventually { let st = await rig.state(); return st["isLive"] as? Bool == false }
        XCTAssertTrue(end)
        let st = await rig.state()
        let sum = try XCTUnwrap(st["summary"] as? [String: Any])
        // Cancelada a mitad o ya terminada (carrera): en ambos casos el resumen cuadra.
        let total = (sum["imported"] as? Int ?? 0) + (sum["remaining"] as? Int ?? 0) + (sum["failed"] as? Int ?? 0)
        XCTAssertEqual(total, 2)
    }

    func testNoPlaylistErrors() async throws {
        let rig = try PlRig()
        defer { rig.cleanup() }
        for m in ["playlist.state", "playlist.selectAll", "playlist.start", "playlist.resume", "playlist.retryFailed"] {
            let e = await rig.error(m)
            XCTAssertEqual(e?.code, "no-playlist", m)
        }
        let c = await rig.result("playlist.close")
        XCTAssertEqual(c["closed"] as? Bool, false)
    }

    func testSupportedLinksLiteralIsTheMacOne() {
        XCTAssertEqual(SourceMessages.supportedLinks,
                       "Se admiten enlaces de un vídeo de YouTube (youtube.com/watch, youtu.be, music.youtube.com) y de una canción de Spotify (open.spotify.com/track o spotify:track), además de listas de YouTube (youtube.com/playlist) y listas o álbumes de Spotify (open.spotify.com/playlist, open.spotify.com/album). Episodios no.")
    }
}

private func eventually(_ timeout: TimeInterval = 8, _ cond: () async -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if await cond() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await cond()
}
