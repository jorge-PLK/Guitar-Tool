import Foundation
import XCTest
@testable import SourceKit

private func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
    return try Data(contentsOf: url)
}

private let listID = "37i9dQZF1DWUNNEvaozpW5"
private let albumID = "2Ly1vNk9Det1V3uc4pVU4o"
private let h = URL(fileURLWithPath: "/h")

private struct FixedHTTP: HTTPFetching {
    var responses: [String: Data]
    func data(from url: URL, headers: [String: String]) async throws -> Data {
        guard let d = responses[url.absoluteString] else { throw SourceError.httpStatus(404) }
        return d
    }
}

private func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("sourcekit-pl-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

/// HTML de embed mínimo con `trackList` generado.
private func embedHTML(name: String, tracks: [(id: String, title: String, artist: String, ms: Int)]) -> Data {
    let list = tracks.map {
        #"{"uri":"spotify:track:\#($0.id)","title":"\#($0.title)","subtitle":"\#($0.artist)","duration":\#($0.ms),"isExplicit":false}"#
    }.joined(separator: ",")
    let json = #"{"props":{"pageProps":{"state":{"data":{"entity":{"name":"\#(name)","id":"x","trackList":[\#(list)]}}}}}}"#
    return Data(#"<html><script id="__NEXT_DATA__" type="application/json">\#(json)</script></html>"#.utf8)
}

private func searchJSON(_ entries: [(id: String, title: String, duration: Double)]) -> String {
    let e = entries.map { #"{"id":"\#($0.id)","title":"\#($0.title)","channel":"Canal","duration":\#($0.duration)}"# }.joined(separator: ",")
    return #"{"entries":[\#(e)]}"#
}

/// Envuelve un `ScriptedProcessRunner` y permite fallos programados (por trozo de comando y número de veces).
private final class FlakyRunner: ProcessRunning, @unchecked Sendable {
    let base = ScriptedProcessRunner()
    private let lock = NSLock()
    private var failures: [(needle: String, stderr: String, times: Int)] = []
    private var counts: [String: Int] = [:]

    func fail(_ needle: String, stderr: String, times: Int = .max) { lock.withLock { failures.append((needle, stderr, times)) } }
    func clearFailures() { lock.withLock { failures = []; hangs = [] } }
    private var hangs: [String] = []
    func hangOn(_ needle: String) { lock.withLock { hangs.append(needle) } }
    func count(_ needle: String) -> Int { lock.withLock { counts[needle, default: 0] } }

    func run(_ request: ProcessRequest, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        let key = ([request.executable.lastPathComponent] + request.arguments).joined(separator: " ")
        let hit: String? = lock.withLock {
            for i in failures.indices where key.contains(failures[i].needle) && failures[i].times > 0 {
                counts[failures[i].needle, default: 0] += 1
                if failures[i].times != .max { failures[i].times -= 1 }
                return failures[i].stderr
            }
            return nil
        }
        if lock.withLock({ hangs.contains { key.contains($0) } }) {
            do { while true { try await Task.sleep(for: .milliseconds(10)) } } catch { throw SourceError.cancelled }
        }
        if let hit { return ProcessResult(status: 1, stderr: hit) }
        return try await base.run(request, onLine: onLine)
    }
}

// MARK: - Enlaces

final class PlaylistLinkTests: XCTestCase {
    func testValidLists() throws {
        let sp = PlaylistLink.spotify(playlistID: listID)
        for s in ["https://open.spotify.com/playlist/\(listID)", "https://open.spotify.com/intl-es/playlist/\(listID)?si=abc",
                  "spotify:playlist:\(listID)"] {
            XCTAssertEqual(try PlaylistLink.parse(s), sp, s)
        }
        let yt = PlaylistLink.youtube(listID: "PLabc_123-x")
        for s in ["https://www.youtube.com/playlist?list=PLabc_123-x", "https://music.youtube.com/playlist?list=PLabc_123-x&si=1",
                  "youtube.com/playlist?list=PLabc_123-x"] {
            XCTAssertEqual(try PlaylistLink.parse(s), yt, s)
        }
        let al = PlaylistLink.spotifyAlbum(albumID: albumID)
        for s in ["https://open.spotify.com/album/\(albumID)?si=x", "https://open.spotify.com/intl-es/album/\(albumID)",
                  "spotify:album:\(albumID)"] {
            XCTAssertEqual(try PlaylistLink.parse(s), al, s)
        }
    }

    func testRejectedLists() {
        for s in ["", "https://www.youtube.com/playlist", "https://www.youtube.com/playlist?list=",
                  "https://www.youtube.com/watch?v=4CJwzwOIPAY&list=PL1", "https://open.spotify.com/playlist/corto",
                  "https://open.spotify.com/track/\(listID)", "spotify:playlist:corto", "https://example.com/playlist?list=PL1"] {
            XCTAssertThrowsError(try PlaylistLink.parse(s), s) { XCTAssertEqual($0 as? SourceError, .unsupportedLink, s) }
        }
    }

    func testWatchWithListIsSingleVideo() throws {
        let url = "https://www.youtube.com/watch?v=4CJwzwOIPAY&list=PL1"
        XCTAssertEqual(try SourceInput.parse(url), .single(.youtube(videoID: "4CJwzwOIPAY")))
        XCTAssertEqual(try SourceInput.parse("https://open.spotify.com/playlist/\(listID)"), .playlist(.spotify(playlistID: listID)))
        XCTAssertThrowsError(try SourceInput.parse("https://open.spotify.com/episode/\(listID)"))
        // `SourceLink.parse` sigue rechazando listas.
        XCTAssertThrowsError(try SourceLink.parse("https://open.spotify.com/playlist/\(listID)"))
    }
}

// MARK: - Lectura

final class PlaylistReadingTests: XCTestCase {
    func testRecordedPlaylistEmbed() async throws {
        let http = FixedHTTP(responses: ["https://open.spotify.com/embed/playlist/\(listID)": try fixture("playlist_embed.html")])
        let p = try await SpotifyEmbedClient(http: http).playlist(id: listID)
        XCTAssertEqual(p.name, "Rock Español")
        XCTAssertEqual(p.tracks.count, 5)
        XCTAssertFalse(p.mayBeTruncated)
        XCTAssertEqual(p.tracks[0].id, "1p7m9H4H8s0Y7SgRm7j3ED")
        XCTAssertEqual(p.tracks[0].title, "Flaca")
        XCTAssertEqual(p.tracks[0].artists, ["Andrés Calamaro"])
        XCTAssertEqual(p.tracks[0].durationSeconds, 277.653, accuracy: 0.001)
    }

    func testRecordedAlbumEmbed() async throws {
        let http = FixedHTTP(responses: ["https://open.spotify.com/embed/album/\(albumID)": try fixture("album_embed.html")])
        let p = try await SpotifyEmbedClient(http: http).album(id: albumID)
        XCTAssertEqual(p.name, "Mi Madre es una Yonki")
        XCTAssertEqual(p.tracks.count, 4)
        // El embed separa artistas con coma y espacio duro.
        XCTAssertEqual(p.tracks[0].artists, ["Narco", "Erre"])
        XCTAssertEqual(p.tracks[0].firstArtist, "Narco")
    }

    func testExactly100TracksMayBeTruncated() throws {
        func make(_ n: Int) -> String {
            String(decoding: embedHTML(name: "L", tracks: (0..<n).map { ("id\($0)", "T\($0)", "A", 180_000) }), as: UTF8.self)
        }
        XCTAssertTrue(try SpotifyEmbedClient.parsePlaylist(html: make(100), id: listID).mayBeTruncated)
        XCTAssertEqual(try SpotifyEmbedClient.parsePlaylist(html: make(100), id: listID).tracks.count, 100)
        XCTAssertFalse(try SpotifyEmbedClient.parsePlaylist(html: make(99), id: listID).mayBeTruncated)
    }

    func testUnreadablePlaylist() {
        XCTAssertThrowsError(try SpotifyEmbedClient.parsePlaylist(html: "<html></html>", id: listID)) {
            XCTAssertEqual($0 as? SourceError, .spotifyMetadataUnreadable)
        }
    }

    func testYouTubePlaylistJSON() async throws {
        let json = #"""
        {"_type":"playlist","id":"PL1","title":"Mi lista","channel":"Jorge","entries":[
          {"id":"aaaaaaaaaaa","url":"https://www.youtube.com/watch?v=aaaaaaaaaaa","title":"Uno","channel":"Canal A","duration":201},
          {"id":"bbbbbbbbbbb","title":"Dos","uploader":"Canal B","duration":95.5}]}
        """#
        let runner = ScriptedProcessRunner()
        runner.on("--flat-playlist -J https://www.youtube.com/playlist?list=PL1", ScriptedResponse(stdout: json))
        let p = try await YtDlpClient(executable: h.appendingPathComponent("yt-dlp"), deno: h.appendingPathComponent("deno"), runner: runner)
            .playlist(url: URL(string: "https://www.youtube.com/playlist?list=PL1")!)
        XCTAssertEqual(p.title, "Mi lista")
        XCTAssertEqual(p.entries.map(\.id), ["aaaaaaaaaaa", "bbbbbbbbbbb"])
        XCTAssertEqual(p.entries[1].channel, "Canal B")
        XCTAssertEqual(p.entries[1].durationSeconds, 95.5)
        XCTAssertEqual(p.entries[1].url.absoluteString, "https://www.youtube.com/watch?v=bbbbbbbbbbb")
    }
}

// MARK: - «Directo», límite y 403

final class LiveAndErrorTests: XCTestCase {
    func testLiveDetector() {
        for t in ["Tema (Directo)", "Tema - En Directo", "Tema EN VIVO 2019", "Tema (Live at Wembley)", "Concierto completo",
                  "Tema - DIRECTO Málaga", "Tema en  vivo"] {
            XCTAssertTrue(CandidateRanker.isLive(title: t), t)
        }
        for t in ["Oliver", "Tema oficial", "Vivo por ella", "Delivery", "Directors cut", "Alive"] {
            XCTAssertFalse(CandidateRanker.isLive(title: t), t)
        }
    }

    private func cand(_ id: String, _ title: String, _ d: Double) -> Candidate {
        Candidate(id: id, url: URL(string: "https://www.youtube.com/watch?v=\(id)")!, title: title, channel: "C", durationSeconds: d)
    }

    func testStudioFirstThenLive() {
        let cs = [cand("live", "Tema (En directo)", 100.5), cand("st1", "Tema", 104), cand("st2", "Tema (Lyric)", 101)]
        let r = CandidateRanker.rank(cs, referenceDuration: 100, referenceTitle: "Tema")
        XCTAssertEqual(r.map(\.id), ["st2", "st1", "live"])
        XCTAssertEqual(r.map(\.isLive), [false, false, true])
        XCTAssertEqual(r.map(\.isClose), [true, false, true])
    }

    func testLiveReferencePutsLiveFirst() {
        let cs = [cand("st", "Tema", 100.2), cand("live", "Tema - Directo Málaga", 102)]
        let r = CandidateRanker.rank(cs, referenceDuration: 100, referenceTitle: "Tema - Directo Málaga")
        XCTAssertEqual(r.map(\.id), ["live", "st"])
    }

    func testRealCaseLiveAtMinus04AndStudioFar() {
        let cs = [cand("live", "Mi madre es una yonki (Directo)", 280.6), cand("st", "Mi madre es una yonki", 346.6)]
        let r = CandidateRanker.rank(cs, referenceDuration: 281, referenceTitle: "Mi Madre es una Yonki")
        XCTAssertEqual(r.map(\.id), ["st", "live"])
        XCTAssertFalse(r[0].isClose)
        XCTAssertTrue(r[1].isClose && r[1].isLive)
    }

    func testRateLimitClassification() {
        for s in ["ERROR: [youtube] x: Sign in to confirm you're not a bot. Use --cookies",
                  "ERROR: unable to download video data: HTTP Error 429: Too Many Requests"] {
            XCTAssertEqual(YtDlpClient.classify(stderr: s, status: 1, version: nil, context: .download), .rateLimited, s)
        }
    }

    private func download(_ runner: FlakyRunner, _ dir: URL) async throws -> DownloadedAudio {
        runner.base.on("-f ", ScriptedResponse(sideEffect: { _ in try Data("x".utf8).write(to: dir.appendingPathComponent("audio.webm")) }))
        runner.base.on("--version", ScriptedResponse(stdout: "2025.11.12\n"))
        return try await YtDlpClient(executable: h.appendingPathComponent("yt-dlp"), deno: h.appendingPathComponent("deno"), runner: runner)
            .download(url: URL(string: "https://youtu.be/abcdefghijk")!, into: dir)
    }

    func testTransient403IsRetriedOnce() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let runner = FlakyRunner()
        runner.fail("-f ", stderr: "ERROR: unable to download video data: HTTP Error 403: Forbidden", times: 1)
        let a = try await download(runner, dir)
        XCTAssertEqual(a.codec, "opus")
        XCTAssertEqual(runner.count("-f "), 1)
    }

    func testRepeated403IsExtractorBroken() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let runner = FlakyRunner()
        runner.fail("-f ", stderr: "ERROR: unable to download video data: HTTP Error 403: Forbidden")
        do {
            _ = try await download(runner, dir)
            XCTFail()
        } catch {
            guard case .extractorBroken(let v, _) = error as? SourceError else { return XCTFail("\(error)") }
            XCTAssertEqual(v, "2025.11.12")
        }
        XCTAssertEqual(runner.count("-f "), 2)
    }
}

// MARK: - PlaylistImporter

@MainActor
private final class Handled {
    var titles: [String] = []
    var origins: [ImportedOrigin] = []
    var failTitle: String?
}

@MainActor
final class PlaylistImporterTests: XCTestCase {
    private let tracks: [(id: String, title: String, artist: String, ms: Int)] = [
        ("sp-A", "Tema A", "Artista A", 200_000),
        ("sp-B", "Tema B", "Artista B", 180_000),
        ("sp-C", "Tema C", "Artista C", 240_000)
    ]

    private func makeRunner(searches: [String: [(id: String, title: String, duration: Double)]]) -> FlakyRunner {
        let r = FlakyRunner()
        r.base.on("--version", ScriptedResponse(stdout: "2025.11.12\n"))
        for (q, e) in searches { r.base.on("ytsearch5:\(q)", ScriptedResponse(stdout: searchJSON(e))) }
        r.base.on("-f ", ScriptedResponse(sideEffect: { req in
            let i = try XCTUnwrap(req.arguments.firstIndex(of: "-o"))
            try Data("a".utf8).write(to: URL(fileURLWithPath: req.arguments[i + 1].replacingOccurrences(of: "%(ext)s", with: "webm")))
        }))
        r.base.on("ffmpeg", ScriptedResponse(sideEffect: { req in
            try Data("wav".utf8).write(to: URL(fileURLWithPath: try XCTUnwrap(req.arguments.last)))
        }))
        return r
    }

    private let studio: [String: [(id: String, title: String, duration: Double)]] = [
        "Artista A Tema A": [("vidA", "Tema A", 200.5), ("vidA2", "Otro", 230)],
        "Artista B Tema B": [("vidB", "Tema B", 180.2)],
        "Artista C Tema C": [("vidC", "Tema C", 240.1)]
    ]

    private func make(_ runner: FlakyRunner, handled: Handled, root: URL,
                      tracks: [(id: String, title: String, artist: String, ms: Int)]? = nil) -> PlaylistImporter {
        let http = FixedHTTP(responses: [
            "https://open.spotify.com/embed/playlist/\(listID)": embedHTML(name: "Mi lista", tracks: tracks ?? self.tracks)
        ])
        let imp = PlaylistImporter(
            ytDlp: YtDlpClient(executable: h.appendingPathComponent("yt-dlp"), deno: h.appendingPathComponent("deno"), runner: runner),
            transcoder: AudioTranscoder(ffmpeg: h.appendingPathComponent("ffmpeg"), runner: runner),
            http: http, spotify: SpotifyEmbedClient(http: http), workRoot: root) { src in
            if src.title == handled.failTitle { throw SourceError.ffmpegFailed("fallo del cierre") }
            handled.titles.append(src.title)
            handled.origins.append(src.origin)
        }
        return imp
    }

    private func loaded(_ imp: PlaylistImporter, select: [String] = ["sp-A", "sp-B", "sp-C"]) async throws {
        try await imp.load("https://open.spotify.com/playlist/\(listID)")
        for id in select { imp.setSelected(id, true) }
    }

    private func status(_ imp: PlaylistImporter, _ id: String) -> PlaylistTrackStatus? { imp.items.first { $0.id == id }?.status }

    func testLoadStartsUnselected() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let imp = make(makeRunner(searches: studio), handled: Handled(), root: root)
        try await imp.load("https://open.spotify.com/playlist/\(listID)")
        XCTAssertEqual(imp.name, "Mi lista")
        XCTAssertEqual(imp.phase, .tracks)
        XCTAssertEqual(imp.items.count, 3)
        XCTAssertTrue(imp.items.allSatisfy { !$0.isSelected && $0.status == .pending })
        XCTAssertFalse(imp.mayBeTruncated)
        imp.selectAll()
        XCTAssertEqual(imp.totals.selected, 3)
        imp.selectNone()
        XCTAssertEqual(imp.totals.selected, 0)
    }

    func testTruncationWarningAt100() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let many = (0..<100).map { (id: "sp-\($0)", title: "T\($0)", artist: "A", ms: 180_000) }
        let imp = make(makeRunner(searches: [:]), handled: Handled(), root: root, tracks: many)
        try await imp.load("spotify:playlist:\(listID)")
        XCTAssertTrue(imp.mayBeTruncated)
        XCTAssertEqual(imp.items.count, 100)
    }

    func testProposalAndDoubtful() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        var s = studio
        s["Artista B Tema B"] = [("vidB", "Tema B", 190)]                        // a 10 s: no cercano
        s["Artista C Tema C"] = [("vidCl", "Tema C (En directo)", 240.1), ("vidC", "Tema C", 300)]  // directo cercano, estudio lejos
        let imp = make(makeRunner(searches: s), handled: Handled(), root: root)
        try await loaded(imp)
        await imp.searchCandidates()
        XCTAssertEqual(imp.phase, .review)
        XCTAssertEqual(status(imp, "sp-A"), .proposed)
        XCTAssertEqual(imp.items[0].chosen?.id, "vidA")
        XCTAssertEqual(imp.items[0].candidates.count, 2)
        XCTAssertEqual(status(imp, "sp-B"), .doubtful)
        XCTAssertNil(imp.items[1].chosen)
        // El directo cercano nunca se propone: el de estudio va delante y no es cercano.
        XCTAssertEqual(status(imp, "sp-C"), .doubtful)
        XCTAssertEqual(imp.items[2].candidates.map(\.id), ["vidC", "vidCl"])
    }

    func testLiveSpotifyTrackProposesLive() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let t = [(id: "sp-A", title: "Tema A - Directo", artist: "Artista A", ms: 200_000)]
        let s = ["Artista A Tema A - Directo": [("vidSt", "Tema A", 200.1), ("vidLive", "Tema A (directo)", 201)]]
        let imp = make(makeRunner(searches: s), handled: Handled(), root: root, tracks: t)
        try await loaded(imp, select: ["sp-A"])
        await imp.searchCandidates()
        XCTAssertEqual(imp.items[0].chosen?.id, "vidLive")
    }

    func testChangeAndClearCandidate() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let handled = Handled()
        let imp = make(makeRunner(searches: studio), handled: handled, root: root)
        try await loaded(imp)
        await imp.searchCandidates()
        imp.choose(imp.items[0].candidates[1].candidate, for: "sp-A")
        XCTAssertEqual(imp.items[0].chosen?.id, "vidA2")
        imp.clearCandidate(for: "sp-B")
        XCTAssertEqual(status(imp, "sp-B"), .skipped)
        await imp.run()
        XCTAssertEqual(handled.titles, ["Tema A", "Tema C"])
        XCTAssertEqual(imp.phase, .finished)
        XCTAssertEqual(imp.totals.imported, 2)
        XCTAssertEqual(imp.totals.skipped, 1)
        XCTAssertEqual(handled.origins[0].videoID, "vidA2")
    }

    func testFullQueueDeliversOriginWithPlaylist() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let handled = Handled()
        let imp = make(makeRunner(searches: studio), handled: handled, root: root)
        try await loaded(imp)
        await imp.searchCandidates()
        await imp.run()
        XCTAssertEqual(handled.titles, ["Tema A", "Tema B", "Tema C"])
        XCTAssertEqual(handled.origins[0].playlistID, listID)
        XCTAssertEqual(handled.origins[0].playlistName, "Mi lista")
        XCTAssertEqual(handled.origins[0].kind, .spotify)
        XCTAssertEqual(handled.origins[0].spotifyID, "sp-A")
        XCTAssertEqual(imp.totals.remaining, 0)
        XCTAssertEqual(imp.queueProgress, 1, accuracy: 0.001)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        XCTAssertTrue(leftovers.isEmpty, "\(leftovers)")
    }

    func testFailureOfOneTrackDoesNotStopQueueAndRetryWorks() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let handled = Handled()
        handled.failTitle = "Tema B"
        let runner = makeRunner(searches: studio)
        runner.fail("vidA", stderr: "ERROR: Video unavailable")   // solo vidA (vidA2 no coincide en la elegida)
        let imp = make(runner, handled: handled, root: root)
        try await loaded(imp)
        await imp.searchCandidates()
        await imp.run()
        XCTAssertEqual(imp.phase, .finished)
        XCTAssertEqual(status(imp, "sp-A"), .failed(.unavailable(.removed)))
        XCTAssertEqual(status(imp, "sp-B"), .failed(.ffmpegFailed("fallo del cierre")))
        XCTAssertEqual(status(imp, "sp-C"), .imported)
        XCTAssertEqual(imp.totals.failed, 2)
        runner.clearFailures()
        handled.failTitle = nil
        XCTAssertEqual(imp.retryFailed(), 2)
        await imp.run()
        XCTAssertEqual(imp.totals.imported, 3)
        XCTAssertEqual(imp.totals.failed, 0)
        XCTAssertEqual(Set(handled.titles), ["Tema A", "Tema B", "Tema C"])
    }

    func testRateLimitStopsQueueAndResumes() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let handled = Handled()
        let runner = makeRunner(searches: studio)
        runner.fail("vidB", stderr: "ERROR: [youtube] x: Sign in to confirm you're not a bot")
        let imp = make(runner, handled: handled, root: root)
        try await loaded(imp)
        await imp.searchCandidates()
        await imp.run()
        XCTAssertEqual(imp.phase, .stopped(.rateLimited))
        XCTAssertEqual(handled.titles, ["Tema A"])
        XCTAssertEqual(status(imp, "sp-B"), .proposed)
        XCTAssertEqual(status(imp, "sp-C"), .proposed)   // no se intentó
        runner.clearFailures()
        await imp.resume()
        XCTAssertEqual(imp.phase, .finished)
        XCTAssertEqual(handled.titles, ["Tema A", "Tema B", "Tema C"])
    }

    func testExtractorErrorStopsQueue() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let handled = Handled()
        let runner = makeRunner(searches: studio)
        runner.fail("vidB", stderr: "ERROR: Unable to extract nsig function")
        let imp = make(runner, handled: handled, root: root)
        try await loaded(imp)
        await imp.searchCandidates()
        await imp.run()
        guard case .stopped(let e) = imp.phase else { return XCTFail("\(imp.phase)") }
        XCTAssertTrue(e.suggestsYtDlpUpdate)
        XCTAssertEqual(handled.titles, ["Tema A"])
        XCTAssertEqual(status(imp, "sp-C"), .proposed)
    }

    func testRateLimitDuringSearchStops() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let runner = makeRunner(searches: studio)
        runner.fail("ytsearch5:Artista B", stderr: "HTTP Error 429: Too Many Requests")
        let imp = make(runner, handled: Handled(), root: root)
        try await loaded(imp)
        await imp.searchCandidates()
        XCTAssertEqual(imp.phase, .stopped(.rateLimited))
        XCTAssertEqual(status(imp, "sp-A"), .proposed)
        XCTAssertEqual(status(imp, "sp-B"), .pending)
        runner.clearFailures()
        await imp.searchCandidates()
        XCTAssertEqual(imp.phase, .review)
        XCTAssertEqual(status(imp, "sp-C"), .proposed)
    }

    func testCancelKeepsWhatWasDone() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let handled = Handled()
        let runner = makeRunner(searches: studio)
        let imp = make(runner, handled: handled, root: root)
        try await loaded(imp)
        await imp.searchCandidates()
        runner.hangOn("vidB")   // la descarga de B no termina hasta que se cancela
        let task = Task { await imp.run() }
        for _ in 0..<500 {
            if case .downloading = status(imp, "sp-B") { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        imp.cancel()
        await task.value
        XCTAssertEqual(imp.phase, .cancelled)
        XCTAssertEqual(handled.titles, ["Tema A"])
        XCTAssertEqual(status(imp, "sp-A"), .imported)
        XCTAssertEqual(status(imp, "sp-B"), .proposed)
        XCTAssertEqual(status(imp, "sp-C"), .proposed)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        XCTAssertTrue(leftovers.isEmpty, "\(leftovers)")
    }

    func testDuplicatesBySpotifyIDAndVideoID() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let handled = Handled()
        let runner = makeRunner(searches: studio)
        let imp = make(runner, handled: handled, root: root)
        imp.isSpotifyIDInLibrary = { $0 == "sp-A" }
        imp.isVideoIDInLibrary = { $0 == "vidB" }
        try await loaded(imp)
        XCTAssertEqual(status(imp, "sp-A"), .inLibrary)
        XCTAssertFalse(imp.items[0].isSelected)
        await imp.searchCandidates()
        XCTAssertFalse(runner.base.requests.contains { $0.arguments.contains { $0.contains("Tema A") } })
        await imp.run()
        XCTAssertEqual(status(imp, "sp-B"), .inLibrary)
        XCTAssertEqual(handled.titles, ["Tema C"])
        XCTAssertFalse(runner.base.requests.contains { $0.arguments.contains { $0.contains("vidB") } && $0.arguments.contains("-f") })
    }

    func testYouTubePlaylistHasNoSearchStep() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let handled = Handled()
        let runner = makeRunner(searches: [:])
        runner.base.on("--flat-playlist -J https://www.youtube.com/playlist?list=PL1", ScriptedResponse(stdout: """
            {"id":"PL1","title":"Lista YT","entries":[{"id":"aaaaaaaaaaa","title":"Uno","channel":"Canal","duration":100},
            {"id":"bbbbbbbbbbb","title":"Dos","channel":"Canal","duration":120}]}
            """))
        let imp = make(runner, handled: handled, root: root)
        try await imp.load("https://www.youtube.com/playlist?list=PL1")
        XCTAssertEqual(imp.name, "Lista YT")
        imp.setSelected("bbbbbbbbbbb", true)
        await imp.run()
        XCTAssertEqual(handled.titles, ["Dos"])
        XCTAssertEqual(handled.origins[0].kind, .youtube)
        XCTAssertEqual(handled.origins[0].playlistID, "PL1")
        XCTAssertEqual(status(imp, "aaaaaaaaaaa"), .pending)
    }

    func testAlbumLoadsLikeAPlaylist() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let runner = makeRunner(searches: [:])
        let http = FixedHTTP(responses: ["https://open.spotify.com/embed/album/\(albumID)": try fixture("album_embed.html")])
        let imp = PlaylistImporter(
            ytDlp: YtDlpClient(executable: h.appendingPathComponent("yt-dlp"), deno: h.appendingPathComponent("deno"), runner: runner),
            transcoder: AudioTranscoder(ffmpeg: h.appendingPathComponent("ffmpeg"), runner: runner),
            http: http, spotify: SpotifyEmbedClient(http: http), workRoot: root) { _ in }
        try await imp.load("https://open.spotify.com/album/\(albumID)")
        XCTAssertEqual(imp.name, "Mi Madre es una Yonki")
        XCTAssertEqual(imp.items.count, 4)
        XCTAssertEqual(imp.items[0].track.artist, "Narco, Erre")
    }

    func testRealCaseLiveCloseStudioFarGivesNoProposal() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let t = [(id: "sp-A", title: "Mi Madre es una Yonki", artist: "Narco", ms: 280_986)]
        let s = ["Narco Mi Madre es una Yonki": [("vidLive", "Mi Madre es una Yonki (Directo)", 280.6), ("vidSt", "Mi Madre es una Yonki", 346.6)]]
        let imp = make(makeRunner(searches: s), handled: Handled(), root: root, tracks: t)
        try await loaded(imp, select: ["sp-A"])
        await imp.searchCandidates()
        XCTAssertEqual(status(imp, "sp-A"), .doubtful)
        XCTAssertEqual(imp.items[0].candidates.map(\.id), ["vidSt", "vidLive"])
    }
}
