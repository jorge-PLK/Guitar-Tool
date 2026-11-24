import Foundation
import SourceKit
import Store
import XCTest
@testable import AppCore

// Parte 1.2b: volcado de `Contract/fixtures/link/` (y base del rig de `tools/`) desde el Router real,
// con yt-dlp, ffmpeg, Spotify y red simulados. Sin red ni hardware.

private struct LFImporter: AudioImporting {
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

private struct LFSeparator: StemSeparating {
    var modelIdentifier: String? { "fake@1" }
    func separate(input: URL, outputDirectory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for kind in StemKind.allCases {
            try "stem".write(to: outputDirectory.appendingPathComponent("\(kind.rawValue).wav"), atomically: true, encoding: .utf8)
        }
        progress(1)
    }
}

let lfSpotifyTrackID = "3demoDemoDemoDemoDemox"
let lfSpotifyURL = "https://open.spotify.com/track/\(lfSpotifyTrackID)"
let lfSpotifyListURL = "https://open.spotify.com/playlist/37i9dQZF1DWUNNEvaozpW5"
let lfYouTubeURL = "https://youtu.be/4CJwzwOIPAY"

/// Página de Spotify (pista) y embed (lista) mínimos; lo demás es una carátula webp de mentira.
private struct LFHTTP: HTTPFetching {
    func data(from url: URL, headers: [String: String]) async throws -> Data {
        guard url.host == "open.spotify.com" else { return Data("RIFFxxxxWEBP".utf8) }
        if url.path.hasPrefix("/embed/playlist") || url.path.hasPrefix("/embed/album") {
            let ids = ["A", "B", "C"].map { "3demoDemoDemoDemoDemo\($0)" }
            let rows = zip(ids, ["Tema A", "Tema B", "Tema C"]).map {
                #"{"uri":"spotify:track:\#($0.0)","title":"\#($0.1)","subtitle":"Marea","duration":252000,"isExplicit":false}"#
            }.joined(separator: ",")
            let json = #"{"props":{"pageProps":{"state":{"data":{"entity":{"name":"Mi lista","id":"x","trackList":[\#(rows)]}}}}}}"#
            return Data(#"<html><script id="__NEXT_DATA__" type="application/json">\#(json)</script></html>"#.utf8)
        }
        let json = """
        {"props":{"pageProps":{"state":{"data":{"entity":{"id":"\(lfSpotifyTrackID)","title":"La luna me sabe a poco","duration":253000,
        "artists":[{"name":"Marea"}],"visualIdentity":{"image":[{"url":"https://img.test/cover.webp","maxWidth":640}]}}}}}}}
        """
        return Data("<html><script id=\"__NEXT_DATA__\" type=\"application/json\">\(json)</script></html>".utf8)
    }
}

struct LFSpotify: SpotifySearching {
    var result: Result<[SpotifyTrackResult], SpotifySearchError> = .success([])
    func search(_ query: String) async throws -> [SpotifyTrackResult] { try result.get() }
}

final class LFEvents: @unchecked Sendable {
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

func lfEventually(_ timeout: TimeInterval = 8, _ cond: () async -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if await cond() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await cond()
}

/// Rig de `link`/`tools`: un `FixtureRig` (volcado y normalización) más un `Bridge` propio con `ExternalSources` simuladas
/// dentro de `base.dir` (para que las rutas se normalicen).
struct LinkFixtureEnv {
    let base: FixtureRig
    let bridge: Bridge
    let runner = ScriptedProcessRunner()
    let events = LFEvents()
    let helpers: URL
    let supportHelpers: URL

    init(area: String, infoID: String = "4CJwzwOIPAY", infoTitle: String = "La luna me sabe a poco",
         infoArtist: String = "Marea", infoStatus: Int32 = 0, infoStderr: String = "",
         hangDownload: Bool = false, spotify: (any SpotifySearching)? = nil) throws {
        base = try FixtureRig(area: area)
        let fm = FileManager.default
        let dir = base.dir
        let projects = dir.appendingPathComponent("LinkProjects", isDirectory: true)
        helpers = dir.appendingPathComponent("Helpers", isDirectory: true)
        supportHelpers = dir.appendingPathComponent("LinkSupport/Helpers", isDirectory: true)
        try fm.createDirectory(at: projects, withIntermediateDirectories: true)
        try fm.createDirectory(at: helpers, withIntermediateDirectories: true)
        for n in ["yt-dlp", "deno", "ffmpeg"] {
            fm.createFile(atPath: helpers.appendingPathComponent(SourceKit.HelperLocator.fileName(n)).path,
                          contents: Data("x".utf8), attributes: [.posixPermissions: 0o755])
        }
        let info = """
        {"id":"\(infoID)","title":"\(infoTitle)","channel":"\(infoArtist)","artist":"\(infoArtist)","duration":253,"thumbnail":"https://img.test/yt.webp"}
        """
        for ext in ["", ".exe"] {
            runner.on("yt-dlp\(ext) --version", ScriptedResponse(stdout: "2026.10.26\n"))
            runner.on("deno\(ext) --version", ScriptedResponse(stdout: "deno 2.1.4 (stable)\n"))
            runner.on("ffmpeg\(ext) -version", ScriptedResponse(stdout: "ffmpeg version 7.1 Copyright\n"))
        }
        runner.on("-J --no-playlist", ScriptedResponse(stdout: info, stderr: infoStderr, status: infoStatus))
        let rows = [("aaaaaaaaaaa", "Marea - La luna me sabe a poco (Audio oficial)", 252.2),
                    ("bbbbbbbbbbb", "Marea - La luna me sabe a poco (Directo)", 301.0)]
        let entries = rows.map {
            "{\"_type\":\"url\",\"id\":\"\($0.0)\",\"url\":\"https://www.youtube.com/watch?v=\($0.0)\",\"title\":\"\($0.1)\",\"channel\":\"Marea\",\"duration\":\($0.2)}"
        }.joined(separator: ",")
        runner.on("ytsearch5:", ScriptedResponse(stdout: "{\"id\":\"q\",\"title\":\"q\",\"_type\":\"playlist\",\"entries\":[\(entries)]}"))
        runner.on("bestaudio", ScriptedResponse(progressLines: ["TFPROGRESS 50 100 NA"], sideEffect: { req in
            guard let i = req.arguments.firstIndex(of: "-o") else { return }
            try Data("audio".utf8).write(to: URL(fileURLWithPath: req.arguments[i + 1].replacingOccurrences(of: "%(ext)s", with: "webm")))
        }, hangs: hangDownload))
        runner.on("pcm_s24le", ScriptedResponse(sideEffect: { req in
            try Data("wav".utf8).write(to: URL(fileURLWithPath: req.arguments.last ?? ""))
        }))
        runner.on("-frames:v", ScriptedResponse(sideEffect: { req in
            try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: URL(fileURLWithPath: req.arguments.last ?? ""))
        }))
        let sources = ExternalSources(bundleDirectory: helpers, supportDirectory: supportHelpers, runner: runner,
                                      http: LFHTTP(), workRoot: dir.appendingPathComponent("work", isDirectory: true))
        let services = JobServices(importer: LFImporter(), separator: LFSeparator(), levelMeter: nil,
                                   analyzer: nil, guitarSplitter: nil)
        bridge = try Bridge(options: LaunchOptions(projectsFolder: projects, supportDir: dir.appendingPathComponent("LinkSupport")),
                            mediaBase: "https://tf.media/", reveal: nil, services: services, link: sources, spotify: spotify)
        let sink = events
        bridge.send = { sink.add($0) }
    }

    func cleanup() { base.cleanup() }

    func quoted(_ s: String) -> String { base.jsonString(s) }

    func raw(_ method: String, _ params: String) async throws -> [String: Any] {
        let r = await bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
    }

    /// Llama al método real y vuelca `<name>.params/.result|.error`.
    @discardableResult
    func run(_ name: String, method: String? = nil, params: String = "{}",
             file: StaticString = #filePath, line: UInt = #line) async throws -> [String: Any] {
        try base.golden(name, .params, params, file: file, line: line)
        let o = try await raw(method ?? name, params)
        if let e = o["error"] {
            try base.golden(name, .error, try FixtureRig.text(e), file: file, line: line)
        } else {
            try base.golden(name, .result, try FixtureRig.text(try XCTUnwrap(o["result"])), file: file, line: line)
        }
        return o
    }

    func event(_ name: String, payload: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws {
        try base.golden(name, .event, try FixtureRig.text(payload), file: file, line: line)
    }

    func finished() -> [[String: Any]] { events.named("link.finished") }
}

final class ContractFixturesLinkTests: XCTestCase {
    func testClassify() async throws {
        let env = try LinkFixtureEnv(area: "link")
        defer { env.cleanup() }
        try await env.run("link.classify.playlist", method: "link.classify", params: "{\"url\":\(env.quoted(lfSpotifyListURL))}")
        try await env.run("link.classify.track", method: "link.classify", params: "{\"url\":\(env.quoted(lfYouTubeURL))}")
        try await env.run("link.classify.unsupported", method: "link.classify", params: "{\"url\":\"https://example.com/x\"}")
    }

    /// Un vídeo importado antes hace que el candidato `aaaaaaaaaaa` de la resolución de Spotify salga con `inLibrary`.
    func testResolveAndImport() async throws {
        let env = try LinkFixtureEnv(area: "link", infoID: "aaaaaaaaaaa", infoTitle: "Versión en directo", infoArtist: "Otro")
        defer { env.cleanup() }
        let yt = "https://youtu.be/aaaaaaaaaaa"
        try await env.run("link.resolve.youtube", method: "link.resolve", params: "{\"url\":\(env.quoted(yt))}")
        let start = try await env.run("link.import", params: "{\"url\":\(env.quoted(yt))}")
        XCTAssertNotNil((start["result"] as? [String: Any])?["jobId"])
        let done = await lfEventually { !env.finished().isEmpty }
        XCTAssertTrue(done)
        let ok = try XCTUnwrap(env.finished().first)
        XCTAssertEqual(ok["duplicate"] as? Bool, false)

        let r = try await env.run("link.resolve", params: "{\"url\":\(env.quoted(lfSpotifyURL))}")
        let cs = try XCTUnwrap((r["result"] as? [String: Any])?["candidates"] as? [[String: Any]])
        XCTAssertNotNil(cs.first { $0["id"] as? String == "aaaaaaaaaaa" }?["inLibrary"] as? [String: Any])

        // Importarlo otra vez: duplicado real.
        _ = try await env.raw("link.import", "{\"url\":\(env.quoted(yt))}")
        let two = await lfEventually { env.finished().count == 2 }
        XCTAssertTrue(two)
        try env.event("link.finished.duplicate", payload: env.finished()[1])
    }

    func testResolvePlaylist() async throws {
        let env = try LinkFixtureEnv(area: "link")
        defer { env.cleanup() }
        let r = try await env.run("link.resolve.playlist", method: "link.resolve", params: "{\"url\":\(env.quoted(lfSpotifyListURL))}")
        XCTAssertNotNil((r["result"] as? [String: Any])?["playlist"])
    }

    func testSearch() async throws {
        let track = SpotifyTrackResult(id: lfSpotifyTrackID, name: "La luna me sabe a poco", artists: ["Marea", "Invitado"],
                                       album: "Besos de Perro", year: 2004, durationMs: 253_000,
                                       imageURL: URL(string: "https://img.test/c.jpg"))
        let env = try LinkFixtureEnv(area: "link", spotify: LFSpotify(result: .success([track])))
        defer { env.cleanup() }
        let r = try await env.run("link.search", params: "{\"query\":\"luna marea\"}")
        XCTAssertNotNil(r["result"])
    }

    func testAddManual() async throws {
        let env = try LinkFixtureEnv(area: "link")
        defer { env.cleanup() }
        _ = try await env.raw("link.resolve", "{\"url\":\(env.quoted(lfSpotifyURL))}")
        let r = try await env.run("link.addManual", params: "{\"url\":\(env.quoted(lfYouTubeURL))}")
        XCTAssertNotNil(r["result"])
    }

    func testCancel() async throws {
        let env = try LinkFixtureEnv(area: "link", hangDownload: true)
        defer { env.cleanup() }
        try await env.run("link.cancel.noJob", method: "link.cancel")
        let start = try await env.raw("link.import", "{\"url\":\(env.quoted(lfYouTubeURL))}")
        let jobID = try XCTUnwrap((start["result"] as? [String: Any])?["jobId"] as? String)
        let started = await lfEventually { env.runner.requests.filter { $0.arguments.contains("-f") }.count == 1 }
        XCTAssertTrue(started)
        let c = try await env.run("link.cancel", params: "{\"jobId\":\(env.quoted(jobID))}")
        XCTAssertEqual((c["result"] as? [String: Any])?["cancelled"] as? Bool, true)
    }

    func testFinishedOkWithNotices() throws {
        let env = try LinkFixtureEnv(area: "link")
        defer { env.cleanup() }
        try env.base.event("link.finished.ok", LinkFinished(
            jobId: "link-1", id: "00000000-0000-0000-0000-000000000001", duplicate: false,
            notices: ["La carátula no se pudo descargar; se usó la miniatura."], error: nil))
    }

    func testFinishedError() async throws {
        let env = try LinkFixtureEnv(area: "link", infoStatus: 1, infoStderr: "Private video")
        defer { env.cleanup() }
        _ = try await env.raw("link.import", "{\"url\":\(env.quoted(lfYouTubeURL))}")
        let done = await lfEventually { !env.finished().isEmpty }
        XCTAssertTrue(done)
        let f = try XCTUnwrap(env.finished().first)
        XCTAssertNotNil(f["error"] as? [String: Any])
        try env.event("link.finished.error", payload: f)
    }
}
