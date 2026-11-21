import Foundation
import XCTest
@testable import SourceKit

private func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
    return try Data(contentsOf: url)
}

private let spotifyID = "16taQAqrrfqCwbkbKFr2OH"
private let ytID = "4CJwzwOIPAY"

private struct StubHTTP: HTTPFetching {
    var responses: [String: Data] = [:]
    var error: SourceError?
    func data(from url: URL, headers: [String: String]) async throws -> Data {
        if let error { throw error }
        guard let d = responses[url.absoluteString] else { throw SourceError.httpStatus(404) }
        return d
    }
}

private func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("sourcekit-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

// MARK: - Enlaces

final class SourceLinkTests: XCTestCase {
    func testValidLinks() throws {
        let yt = SourceLink.youtube(videoID: ytID)
        for s in ["https://www.youtube.com/watch?v=\(ytID)", "https://youtube.com/watch?v=\(ytID)&list=PL1",
                  "https://music.youtube.com/watch?v=\(ytID)", "https://youtu.be/\(ytID)?si=abc", "youtu.be/\(ytID)",
                  "  https://m.youtube.com/watch?v=\(ytID)  "] {
            XCTAssertEqual(try SourceLink.parse(s), yt, s)
        }
        let sp = SourceLink.spotify(trackID: spotifyID)
        for s in ["https://open.spotify.com/track/\(spotifyID)", "https://open.spotify.com/intl-es/track/\(spotifyID)?si=x",
                  "spotify:track:\(spotifyID)"] {
            XCTAssertEqual(try SourceLink.parse(s), sp, s)
        }
    }

    func testRejectedLinks() {
        for s in ["", "hola", "https://www.youtube.com/playlist?list=PL123", "https://www.youtube.com/watch",
                  "https://www.youtube.com/@canal", "https://open.spotify.com/album/\(spotifyID)",
                  "https://open.spotify.com/episode/\(spotifyID)", "spotify:album:\(spotifyID)",
                  "https://open.spotify.com/track/corto", "https://example.com/watch?v=\(ytID)", "ftp://youtu.be/\(ytID)"] {
            XCTAssertThrowsError(try SourceLink.parse(s), s) { XCTAssertEqual($0 as? SourceError, .unsupportedLink, s) }
        }
    }
}

// MARK: - Spotify

final class SpotifyEmbedTests: XCTestCase {
    func testParsesRecordedEmbed() throws {
        let html = String(decoding: try fixture("embed.html"), as: UTF8.self)
        let t = try SpotifyEmbedClient.parse(html: html, id: spotifyID)
        XCTAssertEqual(t.title, "La luna me sabe a poco")
        XCTAssertEqual(t.artists, ["Marea"])
        XCTAssertEqual(t.durationSeconds, 267.186, accuracy: 0.001)
        XCTAssertEqual(t.artworkURL?.absoluteString, "https://image-cdn-fa.spotifycdn.com/image/ab67616d0000b2730e26f0c8d9b01100a89574ec")
    }

    func testClientFetchesEmbedURL() async throws {
        let http = StubHTTP(responses: ["https://open.spotify.com/embed/track/\(spotifyID)": try fixture("embed.html")])
        let t = try await SpotifyEmbedClient(http: http).track(id: spotifyID)
        XCTAssertEqual(t.id, spotifyID)
    }

    func testUnreadableEmbed() async {
        XCTAssertThrowsError(try SpotifyEmbedClient.parse(html: "<html></html>", id: spotifyID)) {
            XCTAssertEqual($0 as? SourceError, .spotifyMetadataUnreadable)
        }
        let noTitle = #"<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"state":{"data":{"entity":{"id":"x"}}}}}}</script>"#
        XCTAssertThrowsError(try SpotifyEmbedClient.parse(html: noTitle, id: "x"))
        let http = StubHTTP(responses: [:])   // 404
        do { _ = try await SpotifyEmbedClient(http: http).track(id: spotifyID); XCTFail() } catch {
            XCTAssertEqual(error as? SourceError, .spotifyMetadataUnreadable)
        }
    }

    func testOfflinePropagates() async {
        do { _ = try await SpotifyEmbedClient(http: StubHTTP(error: .offline)).track(id: spotifyID); XCTFail() } catch {
            XCTAssertEqual(error as? SourceError, .offline)
        }
    }
}

// MARK: - yt-dlp

final class YtDlpClientTests: XCTestCase {
    private let exe = URL(fileURLWithPath: "/h/yt-dlp"), deno = URL(fileURLWithPath: "/h/deno")

    func testSearchParsesRecordedJSON() async throws {
        let runner = ScriptedProcessRunner()
        runner.on("ytsearch5:", ScriptedResponse(stdout: String(decoding: try fixture("search_yt.json"), as: UTF8.self)))
        let found = try await YtDlpClient(executable: exe, deno: deno, runner: runner).search(query: "Marea La luna me sabe a poco")
        XCTAssertEqual(found.count, 5)
        XCTAssertEqual(found[0].id, ytID)
        XCTAssertEqual(found[0].channel, "Marea")
        XCTAssertEqual(found[0].durationSeconds, 268)
        XCTAssertTrue(runner.requests[0].arguments.contains("--flat-playlist"))
        XCTAssertTrue(runner.requests[0].arguments.contains("ytsearch5:Marea La luna me sabe a poco"))
    }

    func testInfoPrefersTrackAndArtist() async throws {
        let runner = ScriptedProcessRunner()
        runner.on("-J", ScriptedResponse(stdout: #"{"id":"abcdefghijk","title":"Video (Official)","track":"Tema","artist":"Banda","channel":"Canal","duration":200,"thumbnail":"https://i/x.jpg"}"#))
        let v = try await YtDlpClient(executable: exe, deno: deno, runner: runner).info(url: URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!)
        XCTAssertEqual([v.title, v.artist, v.channel], ["Tema", "Banda", "Canal"])
        XCTAssertEqual(v.durationSeconds, 200)
        XCTAssertTrue(runner.requests[0].arguments.contains("--no-playlist"))
    }

    func testInfoFallsBackToTitleAndChannel() async throws {
        let runner = ScriptedProcessRunner()
        runner.on("-J", ScriptedResponse(stdout: #"{"id":"abcdefghijk","title":"Video","channel":"Canal","duration":10}"#))
        let v = try await YtDlpClient(executable: exe, deno: deno, runner: runner).info(url: URL(string: "https://youtu.be/abcdefghijk")!)
        XCTAssertEqual([v.title, v.artist], ["Video", "Canal"])
    }

    func testProgressParsing() {
        XCTAssertEqual(YtDlpClient.parseProgress("TFPROGRESS 50 100 NA"), 0.5)
        XCTAssertEqual(YtDlpClient.parseProgress("TFPROGRESS 25 NA 100"), 0.25)
        XCTAssertNil(YtDlpClient.parseProgress("TFPROGRESS 25 NA NA"))
        XCTAssertNil(YtDlpClient.parseProgress("[download] 10%"))
    }

    private func classify(_ stderr: String, _ context: YtDlpClient.Context = .metadata) -> SourceError {
        YtDlpClient.classify(stderr: stderr, status: 1, version: "2025.10.22", context: context)
    }

    func testErrorClassification() {
        XCTAssertEqual(classify("ERROR: [youtube] x: Sign in to confirm your age. This video may be inappropriate"), .ageRestricted)
        XCTAssertEqual(classify("ERROR: [youtube] x: The uploader has not made this video available in your country"), .unavailable(.region))
        XCTAssertEqual(classify("ERROR: [youtube] x: Private video. Sign in if you've been granted access"), .unavailable(.privateVideo))
        XCTAssertEqual(classify("ERROR: [youtube] x: Video unavailable"), .unavailable(.removed))
        XCTAssertEqual(classify("ERROR: [youtube] x: Requested format is not available. Use --list-formats", .download), .noAudioFormat)
        XCTAssertEqual(classify("ERROR: [youtube] Unable to download webpage: <urlopen error [Errno 8] nodename nor servname provided, or not known>"), .offline)
        XCTAssertEqual(classify("ERROR: Unable to download API page: [Errno -3] Temporary failure in name resolution"), .offline)
        for broken in ["ERROR: [youtube] x: Unable to extract initial player response",
                       "WARNING: nsig extraction failed: Some formats may be missing\nERROR: unable to decode",
                       "ERROR: unable to download video data: HTTP Error 403: Forbidden",
                       "algo raro que no se reconoce"] {
            guard case .extractorBroken(let v, _) = classify(broken) else { return XCTFail(broken) }
            XCTAssertEqual(v, "2025.10.22")
        }
        XCTAssertTrue(classify("Unable to extract").suggestsYtDlpUpdate)
        // «Requested format…» solo es «sin audio» al descargar.
        XCTAssertTrue(classify("Requested format is not available", .metadata).suggestsYtDlpUpdate)
    }

    func testClientClassifiesFailureWithVersion() async {
        let runner = ScriptedProcessRunner()
        runner.on("--version", ScriptedResponse(stdout: "2025.10.22\n"))
        runner.on("-J", ScriptedResponse(stderr: "ERROR: Unable to extract nsig", status: 1))
        do {
            _ = try await YtDlpClient(executable: exe, deno: deno, runner: runner).info(url: URL(string: "https://youtu.be/abcdefghijk")!)
            XCTFail()
        } catch {
            guard case .extractorBroken(let v, _) = error as? SourceError else { return XCTFail("\(error)") }
            XCTAssertEqual(v, "2025.10.22")
        }
    }

    func testDownloadAddsNoCookiesAndUsesFormatSelector() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let runner = ScriptedProcessRunner()
        runner.on("-f", ScriptedResponse(progressLines: ["TFPROGRESS 50 100 NA", "ruido"], sideEffect: { _ in
            try Data("x".utf8).write(to: dir.appendingPathComponent("audio.webm"))
        }))
        let seen = Seen()
        let a = try await YtDlpClient(executable: exe, deno: deno, runner: runner)
            .download(url: URL(string: "https://youtu.be/abcdefghijk")!, into: dir) { seen.add($0) }
        XCTAssertEqual(a.codec, "opus")
        XCTAssertFalse(a.fellBackToM4A)
        XCTAssertEqual(seen.values, [0.5])
        let args = runner.requests[0].arguments
        XCTAssertTrue(args.contains("bestaudio[acodec=opus]/bestaudio[ext=m4a]"))
        XCTAssertTrue(args.contains("deno:/h/deno"))
        XCTAssertEqual(runner.requests[0].timeout, .idle(60))
    }

    func testDownloadReportsM4ACodec() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let runner = ScriptedProcessRunner()
        runner.on("-f", ScriptedResponse(sideEffect: { _ in try Data("x".utf8).write(to: dir.appendingPathComponent("audio.m4a")) }))
        let a = try await YtDlpClient(executable: exe, deno: deno, runner: runner)
            .download(url: URL(string: "https://youtu.be/abcdefghijk")!, into: dir)
        XCTAssertEqual(a.codec, "aac")
        XCTAssertTrue(a.fellBackToM4A)
    }
}

private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var v: [Double] = []
    func add(_ x: Double) { lock.withLock { v.append(x) } }
    var values: [Double] { lock.withLock { v } }
}

// MARK: - Candidatos

final class CandidateRankerTests: XCTestCase {
    private func c(_ id: String, _ d: Double?) -> Candidate {
        Candidate(id: id, url: URL(string: "https://youtu.be/\(id)")!, title: id, durationSeconds: d)
    }

    func testOrderAndThreshold() {
        let r = CandidateRanker.rank([c("far", 300), c("nil", nil), c("edge", 270), c("under", 262), c("exact", 267)], referenceDuration: 267)
        XCTAssertEqual(r.map(\.id), ["exact", "edge", "under", "far", "nil"])
        XCTAssertEqual(r.map(\.isClose), [true, true, false, false, false])   // 3,0 s entra; 5 s no
        XCTAssertEqual(r[1].difference, 3)
        XCTAssertEqual(r[2].difference, -5)
    }

    func testRecordedSearchAgainstSpotifyDuration() async throws {
        let found = try YtDlpClient.parseSearch(try fixture("search_yt.json"))
        let r = CandidateRanker.rank(found, referenceDuration: 267.186)
        XCTAssertEqual(r.count, 5)
        XCTAssertEqual(r[0].id, ytID)
        XCTAssertTrue(r[0].isClose)
        let diffs = r.compactMap(\.difference).map(abs)
        XCTAssertEqual(diffs, diffs.sorted())
    }
}

// MARK: - Transcodificador

final class AudioTranscoderTests: XCTestCase {
    func testCommandAndFailure() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("audio.wav")
        let runner = ScriptedProcessRunner()
        runner.on("ffmpeg", ScriptedResponse(sideEffect: { _ in try Data("w".utf8).write(to: out) }))
        let t = AudioTranscoder(ffmpeg: URL(fileURLWithPath: "/h/ffmpeg"), runner: runner)
        try await t.convert(input: dir.appendingPathComponent("audio.m4a"), output: out)
        let a = runner.requests[0].arguments
        XCTAssertTrue(a.contains("pcm_s24le"))
        XCTAssertFalse(a.contains("-ar"))

        let bad = ScriptedProcessRunner()
        bad.on("ffmpeg", ScriptedResponse(stderr: "uno\nNo space left on device", status: 1))
        do { try await AudioTranscoder(ffmpeg: URL(fileURLWithPath: "/h/ffmpeg"), runner: bad).convert(input: out, output: out); XCTFail() } catch {
            guard case .ffmpegFailed(let tail) = error as? SourceError else { return XCTFail() }
            XCTAssertTrue(tail.contains("No space left"))
        }
    }
}

// MARK: - HelperLocator y actualizador

final class HelperLocatorTests: XCTestCase {
    private func makeExec(_ dir: URL, _ name: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent(HelperLocator.fileName(name))
        try Data("#!/bin/sh\n".utf8).write(to: u)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
    }
    private func writeInfo(_ dir: URL, _ version: String) throws {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try e.encode(YtDlpInstallInfo(version: version, sha256: "00", installedAt: Date())).write(to: dir.appendingPathComponent("yt-dlp.json"))
    }

    func testPicksNewestVersion() throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("bundle"), support = root.appendingPathComponent("support")
        for n in ["yt-dlp", "deno", "ffmpeg"] { try makeExec(bundle, n) }

        // Sin actualizada: bundle.
        var loc = HelperLocator(bundleDirectory: bundle, supportDirectory: support, bundleYtDlpVersion: "2025.10.22")
        XCTAssertEqual(try loc.ytDlp().origin, .bundle)

        try makeExec(support, "yt-dlp")
        try writeInfo(support, "2025.11.12")
        XCTAssertEqual(try loc.ytDlp().origin, .updated)
        XCTAssertEqual(try loc.ytDlp().version, "2025.11.12")

        loc = HelperLocator(bundleDirectory: bundle, supportDirectory: support, bundleYtDlpVersion: "2025.12.01")
        XCTAssertEqual(try loc.ytDlp().origin, .bundle)
        loc = HelperLocator(bundleDirectory: bundle, supportDirectory: support, bundleYtDlpVersion: "2025.11.12")
        XCTAssertEqual(try loc.ytDlp().origin, .bundle, "empate: gana el bundle")

        try loc.removeUpdate()
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent(HelperLocator.fileName("yt-dlp")).path))
        XCTAssertEqual(try loc.deno().lastPathComponent, HelperLocator.fileName("deno"))
        XCTAssertEqual(try loc.ffmpeg().lastPathComponent, HelperLocator.fileName("ffmpeg"))
    }

    func testVersionCompareAndMissing() throws {
        XCTAssertLessThan(HelperLocator.compare("2025.10.22", "2025.10.22.123456"), 0)
        XCTAssertLessThan(HelperLocator.compare("2025.9.30", "2025.10.1"), 0)
        XCTAssertEqual(HelperLocator.compare("2025.10.22", "2025.10.22"), 0)
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let loc = HelperLocator(bundleDirectory: root, supportDirectory: root.appendingPathComponent("s"))
        XCTAssertThrowsError(try loc.ytDlp()) { XCTAssertEqual($0 as? SourceError, .helperMissing("yt-dlp")) }
        XCTAssertThrowsError(try loc.ffmpeg())
    }
}

final class YtDlpUpdaterTests: XCTestCase {
    private func sha(_ d: Data) -> String {
        // Reutiliza el verificador del propio updater: hash correcto vía una release simulada.
        var out = ""
        for b in d.sha256Bytes { out += String(format: "%02x", b) }
        return out
    }

    func testBadChecksumInstallsNothing() async throws {
        let support = tempDir(); defer { try? FileManager.default.removeItem(at: support) }
        let base = YtDlpUpdater.releaseBase
        let http = StubHTTP(responses: [
            base.appendingPathComponent(YtDlpUpdater.assetName).absoluteString: Data("binario".utf8),
            base.appendingPathComponent("SHA2-256SUMS").absoluteString: Data("\(String(repeating: "0", count: 64))  \(YtDlpUpdater.assetName)\n".utf8)
        ])
        let runner = ScriptedProcessRunner()
        runner.on("--version", ScriptedResponse(stdout: "2025.11.12\n"))
        do { try await YtDlpUpdater(supportDirectory: support, http: http, runner: runner).update(); XCTFail() } catch {
            XCTAssertEqual(error as? SourceError, .checksumMismatch)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent(HelperLocator.fileName("yt-dlp")).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("yt-dlp.json").path))
        XCTAssertTrue(runner.requests.isEmpty)
    }

    func testGoodChecksumInstalls() async throws {
        let support = tempDir(); defer { try? FileManager.default.removeItem(at: support) }
        let base = YtDlpUpdater.releaseBase
        let bin = Data("binario".utf8)
        let http = StubHTTP(responses: [
            base.appendingPathComponent(YtDlpUpdater.assetName).absoluteString: bin,
            base.appendingPathComponent("SHA2-256SUMS").absoluteString: Data("aaaa  otro\n\(sha(bin))  \(YtDlpUpdater.assetName)\n".utf8)
        ])
        let runner = ScriptedProcessRunner()
        runner.on("--version", ScriptedResponse(stdout: "2025.11.12\n"))
        let info = try await YtDlpUpdater(supportDirectory: support, http: http, runner: runner).update()
        XCTAssertEqual(info.version, "2025.11.12")
        XCTAssertTrue(HelperLocator.isRunnable(support.appendingPathComponent(HelperLocator.fileName("yt-dlp")).path))
        XCTAssertEqual(HelperLocator.readInfo(in: support)?.version, "2025.11.12")
        XCTAssertEqual(HelperLocator.readInfo(in: support)?.sha256, sha(bin))
    }
}

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
private extension Data {
    var sha256Bytes: [UInt8] { Array(SHA256.hash(data: self)) }
}

// MARK: - Proceso real (solo /bin/sh y /bin/sleep, sin helpers)

final class SystemProcessRunnerTests: XCTestCase {
    /// Un proceso que dura 30 s.
    static var sleeper: (exe: URL, args: [String]) {
        #if os(Windows)
        (URL(fileURLWithPath: "C:\\Windows\\System32\\PING.EXE"), ["-n", "31", "127.0.0.1"])
        #else
        (URL(fileURLWithPath: "/bin/sleep"), ["30"])
        #endif
    }

    func testCapturesOutputAndStatus() async throws {
        let lines = Seen2()
        #if os(Windows)
        let exe = URL(fileURLWithPath: "C:\\Windows\\System32\\cmd.exe")
        let args = ["/c", "echo uno&echo dos&echo err>&2&exit 3"]
        #else
        let exe = URL(fileURLWithPath: "/bin/sh")
        let args = ["-c", "echo uno; echo dos; echo err >&2; exit 3"]
        #endif
        let r = try await SystemProcessRunner().run(.init(executable: exe, arguments: args)) { lines.add($0) }
        XCTAssertEqual(r.status, 3)
        // cmd.exe termina las líneas con CRLF.
        XCTAssertEqual(lines.values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }, ["uno", "dos"])
        XCTAssertEqual(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines), "err")
    }

    func testCancelKillsProcess() async throws {
        let sleeper = Self.sleeper
        let task = Task {
            try await SystemProcessRunner(terminateGrace: 1).run(.init(executable: sleeper.exe, arguments: sleeper.args))
        }
        try await Task.sleep(for: .milliseconds(300))
        let start = Date()
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertEqual(error as? SourceError, .cancelled) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testTimeout() async {
        do {
            _ = try await SystemProcessRunner(terminateGrace: 1).run(
                .init(executable: Self.sleeper.exe, arguments: Self.sleeper.args, timeout: .total(0.3)))
            XCTFail()
        } catch { XCTAssertEqual(error as? SourceError, .timedOut) }
    }

    func testLaunchFailure() async {
        do { _ = try await SystemProcessRunner().run(.init(executable: URL(fileURLWithPath: "/no/existe"), arguments: [])); XCTFail() }
        catch { guard case .launchFailed = error as? SourceError else { return XCTFail("\(error)") } }
    }
}

private final class Seen2: @unchecked Sendable {
    private let lock = NSLock()
    private var v: [String] = []
    func add(_ x: String) { lock.withLock { v.append(x) } }
    var values: [String] { lock.withLock { v } }
}

// MARK: - SourceImporter

@MainActor
final class SourceImporterTests: XCTestCase {
    private let artURL = "https://image-cdn-fa.spotifycdn.com/image/ab67616d0000b2730e26f0c8d9b01100a89574ec"

    private func makeImporter(runner: ScriptedProcessRunner, http: StubHTTP, root: URL) -> SourceImporter {
        let h = URL(fileURLWithPath: "/h")
        return SourceImporter(
            ytDlp: YtDlpClient(executable: h.appendingPathComponent("yt-dlp"), deno: h.appendingPathComponent("deno"), runner: runner),
            transcoder: AudioTranscoder(ffmpeg: h.appendingPathComponent("ffmpeg"), runner: runner),
            http: http, spotify: SpotifyEmbedClient(http: http), workRoot: root,
            now: { Date(timeIntervalSince1970: 1000) })
    }

    private func script(search: String, ext: String = "webm") throws -> ScriptedProcessRunner {
        let r = ScriptedProcessRunner()
        r.on("--version", ScriptedResponse(stdout: "2025.11.12\n"))
        r.on("ytsearch5:", ScriptedResponse(stdout: search))
        r.on("-f ", ScriptedResponse(progressLines: ["TFPROGRESS 1 2 NA"], sideEffect: { req in
            let i = try XCTUnwrap(req.arguments.firstIndex(of: "-o"))
            let tpl = req.arguments[i + 1].replacingOccurrences(of: "%(ext)s", with: ext)
            try Data("audio".utf8).write(to: URL(fileURLWithPath: tpl))
        }))
        r.on("ffmpeg", ScriptedResponse(sideEffect: { req in
            try Data("wav".utf8).write(to: URL(fileURLWithPath: try XCTUnwrap(req.arguments.last)))
        }))
        return r
    }

    private func spotifyHTTP() throws -> StubHTTP {
        StubHTTP(responses: [
            "https://open.spotify.com/embed/track/\(spotifyID)": try fixture("embed.html"),
            artURL: Data("jpg".utf8)
        ])
    }

    func testFullSpotifyJourney() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let runner = try script(search: String(decoding: try fixture("search_yt.json"), as: UTF8.self))
        let imp = makeImporter(runner: runner, http: try spotifyHTTP(), root: root)
        var states: [ImportState] = []
        imp.onStateChange = { states.append($0) }

        let r = try await imp.resolve("https://open.spotify.com/track/\(spotifyID)")
        XCTAssertEqual(r.title, "La luna me sabe a poco")
        XCTAssertEqual(r.candidates.count, 5)
        XCTAssertFalse(r.noCloseCandidate)
        XCTAssertTrue(runner.requests.contains { $0.arguments.contains("ytsearch5:Marea La luna me sabe a poco") })
        XCTAssertEqual(states.prefix(2), [.resolving(.metadata), .resolving(.searching)])

        let out = try await imp.download(candidate: r.candidates[0].candidate, title: "Tema editado", artist: r.artist)
        XCTAssertEqual(out.title, "Tema editado")
        XCTAssertEqual(out.origin.kind, .spotify)
        XCTAssertEqual(out.origin.spotifyID, spotifyID)
        XCTAssertEqual(out.origin.videoID, ytID)
        XCTAssertEqual(out.origin.codec, "opus")
        XCTAssertEqual(out.origin.ytDlpVersion, "2025.11.12")
        XCTAssertEqual(out.origin.importedAt, Date(timeIntervalSince1970: 1000))
        XCTAssertTrue(out.notices.isEmpty)
        XCTAssertEqual(try String(contentsOf: out.wavURL, encoding: .utf8), "wav")
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(out.artworkURL)), Data("jpg".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.workDirectory.appendingPathComponent("audio.webm").path))
        XCTAssertTrue(states.contains(.downloading(.converting, progress: nil)))
        XCTAssertEqual(imp.state, .finished)
        out.cleanUp()
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.workDirectory.path))
    }

    func testYouTubeJourneyWithM4AFallback() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let runner = try script(search: "", ext: "m4a")
        runner.on("-J", ScriptedResponse(stdout: #"{"id":"\#(ytID)","title":"Tema","channel":"Canal","duration":120}"#))
        let imp = makeImporter(runner: runner, http: StubHTTP(), root: root)
        let r = try await imp.resolve("https://youtu.be/\(ytID)")
        XCTAssertTrue(r.candidates.isEmpty)
        let c = try XCTUnwrap(r.confirmation)
        XCTAssertEqual([c.title, c.channel], ["Tema", "Canal"])
        XCTAssertFalse(runner.requests.contains { $0.arguments.contains { $0.hasPrefix("ytsearch") } })

        let out = try await imp.download(candidate: c, title: r.title, artist: r.artist)
        XCTAssertEqual(out.origin.kind, .youtube)
        XCTAssertEqual(out.origin.codec, "aac")
        XCTAssertEqual(out.notices, [.fellBackToM4A])
        XCTAssertEqual(imp.notices, [.fellBackToM4A])
        XCTAssertTrue(ImportNotice.fellBackToM4A.message.hasPrefix("Sin Opus"))
        out.cleanUp()
    }

    func testNoCloseCandidateWarning() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let far = #"{"entries":[{"id":"aaaaaaaaaaa","title":"Directo","duration":400}]}"#
        let imp = makeImporter(runner: try script(search: far), http: try spotifyHTTP(), root: root)
        let r = try await imp.resolve("spotify:track:\(spotifyID)")
        XCTAssertTrue(r.noCloseCandidate)
        XCTAssertEqual(r.candidates.count, 1)
        let empty = makeImporter(runner: try script(search: #"{"entries":[]}"#), http: try spotifyHTTP(), root: root)
        let e = try await empty.resolve("spotify:track:\(spotifyID)")
        XCTAssertTrue(e.noCloseCandidate)
    }

    func testManualCandidate() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let runner = try script(search: String(decoding: try fixture("search_yt.json"), as: UTF8.self))
        runner.on("-J", ScriptedResponse(stdout: #"{"id":"zzzzzzzzzzz","title":"A mano","channel":"X","duration":267}"#))
        let imp = makeImporter(runner: runner, http: try spotifyHTTP(), root: root)
        try await imp.resolve("spotify:track:\(spotifyID)")
        let c = try await imp.addManualCandidate("https://youtu.be/zzzzzzzzzzz")
        XCTAssertEqual(c.id, "zzzzzzzzzzz")
        guard case .candidates(let r) = imp.state else { return XCTFail() }
        XCTAssertEqual(r.candidates.first?.id, "zzzzzzzzzzz")
        XCTAssertEqual(r.candidates.count, 6)
        do { _ = try await imp.addManualCandidate("https://open.spotify.com/track/\(spotifyID)"); XCTFail() } catch {
            XCTAssertEqual(error as? SourceError, .unsupportedLink)
        }
    }

    func testErrorsArePublished() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let imp = makeImporter(runner: ScriptedProcessRunner(), http: StubHTTP(), root: root)
        do { _ = try await imp.resolve("https://example.com"); XCTFail() } catch { XCTAssertEqual(error as? SourceError, .unsupportedLink) }
        XCTAssertEqual(imp.state, .failed(.unsupportedLink))

        let offline = makeImporter(runner: ScriptedProcessRunner(), http: StubHTTP(error: .offline), root: root)
        do { _ = try await offline.resolve("spotify:track:\(spotifyID)"); XCTFail() } catch { XCTAssertEqual(error as? SourceError, .offline) }
        XCTAssertEqual(offline.state, .failed(.offline))

        // Edad al descargar: error sin más, y la carpeta temporal desaparece.
        let runner = try script(search: String(decoding: try fixture("search_yt.json"), as: UTF8.self))
        let rules = ScriptedProcessRunner()
        rules.on("ytsearch5:", ScriptedResponse(stdout: String(decoding: try fixture("search_yt.json"), as: UTF8.self)))
        rules.on("--version", ScriptedResponse(stdout: "1\n"))
        rules.on("-f ", ScriptedResponse(stderr: "ERROR: Sign in to confirm your age", status: 1))
        _ = runner
        let age = makeImporter(runner: rules, http: try spotifyHTTP(), root: root)
        let r = try await age.resolve("spotify:track:\(spotifyID)")
        do { _ = try await age.download(candidate: r.candidates[0].candidate, title: "t", artist: "a"); XCTFail() } catch {
            XCTAssertEqual(error as? SourceError, .ageRestricted)
        }
        XCTAssertEqual(age.state, .failed(.ageRestricted))
        XCTAssertTrue(SourceError.ageRestricted.returnsToCandidates)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: root.path))?.count, 0)
    }

    func testNoAudioFormat() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let rules = ScriptedProcessRunner()
        rules.on("ytsearch5:", ScriptedResponse(stdout: String(decoding: try fixture("search_yt.json"), as: UTF8.self)))
        rules.on("-f ", ScriptedResponse(stderr: "ERROR: [youtube] x: Requested format is not available. Use --list-formats", status: 1))
        let imp = makeImporter(runner: rules, http: try spotifyHTTP(), root: root)
        let r = try await imp.resolve("spotify:track:\(spotifyID)")
        do { _ = try await imp.download(candidate: r.candidates[0].candidate, title: "t", artist: "a"); XCTFail() } catch {
            XCTAssertEqual(error as? SourceError, .noAudioFormat)
        }
    }

    func testCancellationDuringDownloadCleansUp() async throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let rules = ScriptedProcessRunner()
        rules.on("ytsearch5:", ScriptedResponse(stdout: String(decoding: try fixture("search_yt.json"), as: UTF8.self)))
        rules.on("--version", ScriptedResponse(stdout: "1\n"))
        rules.on("-f ", ScriptedResponse(hangs: true))
        let imp = makeImporter(runner: rules, http: try spotifyHTTP(), root: root)
        let r = try await imp.resolve("spotify:track:\(spotifyID)")
        let cand = r.candidates[0].candidate
        let task = Task { try await imp.download(candidate: cand, title: "t", artist: "a") }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertEqual(error as? SourceError, .cancelled) }
        XCTAssertEqual(imp.state, .idle)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: root.path))?.count, 0)
    }
}
