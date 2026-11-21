import Foundation
import SourceKit
import Store
import XCTest
@testable import AppCore

// 8.3b: importación por enlace y herramientas externas con yt-dlp, ffmpeg y red simulados (sin descargas reales).

private struct LinkFakeImporter: AudioImporting {
    func importAudio(from source: URL, to destination: URL, sampleRate: Double,
                     progress: @escaping @Sendable (Double) -> Void) async throws -> ImportedAudioInfo {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "wav".write(to: destination, atomically: true, encoding: .utf8)
        progress(0.5); progress(1)
        return ImportedAudioInfo(title: nil, artist: nil, duration: 10, sourceFormat: "wav", sourceSampleRate: 44100, sourceChannels: 2)
    }
    func resample(_ file: URL, to destination: URL, sampleRate: Double) async throws {
        try "stem".write(to: destination, atomically: true, encoding: .utf8)
    }
}

private struct LinkFakeSeparator: StemSeparating {
    var modelIdentifier: String? { "fake@1" }
    func separate(input: URL, outputDirectory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for kind in StemKind.allCases {
            try "stem".write(to: outputDirectory.appendingPathComponent("\(kind.rawValue).wav"), atomically: true, encoding: .utf8)
        }
        progress(1)
    }
}

private struct LinkHTTP: HTTPFetching {
    static let spotifyID = "3demoDemoDemoDemoDemox"
    func data(from url: URL, headers: [String: String]) async throws -> Data {
        if url.host == "open.spotify.com" {
            let json = """
            {"props":{"pageProps":{"state":{"data":{"entity":{"id":"\(Self.spotifyID)","title":"La luna me sabe a poco","duration":253000,
            "artists":[{"name":"Marea"}],"visualIdentity":{"image":[{"url":"https://img.test/cover.webp","maxWidth":640}]}}}}}}}
            """
            return Data("<html><script id=\"__NEXT_DATA__\" type=\"application/json\">\(json)</script></html>".utf8)
        }
        // Carátula: un webp de mentira (cabecera RIFF).
        return Data("RIFFxxxxWEBP".utf8)
    }
}

private final class LinkEvents: @unchecked Sendable {
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

private func lkJSON(_ s: String) -> String {
    String(decoding: (try? JSONEncoder().encode(s)) ?? Data(), as: UTF8.self)
}

private let ytID = "4CJwzwOIPAY"
private let ytURL = "https://youtu.be/\(ytID)"
private let spURL = "https://open.spotify.com/track/\(LinkHTTP.spotifyID)"

private struct FakeSpotify: SpotifySearching {
    var result: Result<[SpotifyTrackResult], SpotifySearchError>
    func search(_ query: String) async throws -> [SpotifyTrackResult] { try result.get() }
}

private struct LinkRig {
    let dir: URL
    let projects: URL
    let helpers: URL
    let supportHelpers: URL
    let runner = ScriptedProcessRunner()
    let bridge: Bridge
    let events = LinkEvents()

    init(infoStatus: Int32 = 0, infoStderr: String = "", hangInfo: Bool = false, hangDownload: Bool = false,
         spotify: (any SpotifySearching)? = nil) throws {
        let fm = FileManager.default
        dir = fm.temporaryDirectory.appendingPathComponent("appcore-link-\(UUID().uuidString)", isDirectory: true)
        projects = dir.appendingPathComponent("Projects", isDirectory: true)
        helpers = dir.appendingPathComponent("Helpers", isDirectory: true)
        supportHelpers = dir.appendingPathComponent("Support/Helpers", isDirectory: true)
        try fm.createDirectory(at: projects, withIntermediateDirectories: true)
        try fm.createDirectory(at: helpers, withIntermediateDirectories: true)
        for n in ["yt-dlp", "deno", "ffmpeg"] {
            fm.createFile(atPath: helpers.appendingPathComponent(SourceKit.HelperLocator.fileName(n)).path,
                          contents: Data("x".utf8), attributes: [.posixPermissions: 0o755])
        }
        let infoJSON = """
        {"id":"\(ytID)","title":"La luna me sabe a poco","channel":"Marea","artist":"Marea","duration":253,"thumbnail":"https://img.test/yt.webp"}
        """
        // Windows: `lastPathComponent` lleva `.exe` y la clave de ScriptedProcessRunner es "yt-dlp.exe --version".
        for ext in ["", ".exe"] {
            runner.on("yt-dlp\(ext) --version", ScriptedResponse(stdout: "2026.10.26\n"))
            runner.on("deno\(ext) --version", ScriptedResponse(stdout: "deno 2.1.4 (stable)\n"))
            runner.on("ffmpeg\(ext) -version", ScriptedResponse(stdout: "ffmpeg version 7.1 Copyright\n"))
        }
        runner.on("-J --no-playlist", ScriptedResponse(stdout: infoJSON, stderr: infoStderr, status: infoStatus, hangs: hangInfo))
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
                                      http: LinkHTTP(), workRoot: dir.appendingPathComponent("work", isDirectory: true))
        let services = JobServices(importer: LinkFakeImporter(), separator: LinkFakeSeparator(), levelMeter: nil,
                                   analyzer: nil, guitarSplitter: nil)
        bridge = try Bridge(options: LaunchOptions(projectsFolder: projects, supportDir: dir.appendingPathComponent("Support")),
                            mediaBase: "https://tf.media/", reveal: nil, services: services, link: sources, spotify: spotify)
        let sink = events
        bridge.send = { sink.add($0) }
    }

    func raw(_ method: String, _ params: String) async -> String {
        await bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
    }

    func call(_ method: String, _ params: String = "{}") async -> [String: Any] {
        let r = await raw(method, params)
        return (try? JSONSerialization.jsonObject(with: Data(r.utf8))) as? [String: Any] ?? [:]
    }

    func result(_ method: String, _ params: String = "{}") async -> [String: Any] {
        (await call(method, params))["result"] as? [String: Any] ?? [:]
    }

    func errorCode(_ method: String, _ params: String) async -> (code: String, message: String)? {
        guard let e = (await call(method, params))["error"] as? [String: Any] else { return nil }
        return (e["code"] as? String ?? "", e["message"] as? String ?? "")
    }

    func finished() -> [[String: Any]] { events.named("link.finished") }

    func downloadRequests() -> Int { runner.requests.filter { $0.arguments.contains("-f") }.count }

    func cleanup() { try? FileManager.default.removeItem(at: dir) }
}

private func eventually(_ timeout: TimeInterval = 8, _ cond: () async -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if await cond() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await cond()
}

final class LinkTests: XCTestCase {
    func testResolveYouTube() async throws {
        let rig = try LinkRig()
        defer { rig.cleanup() }
        let r = await rig.result("link.resolve", "{\"url\":\(lkJSON(ytURL))}")
        XCTAssertEqual(r["link"] as? String, "youtube")
        XCTAssertEqual(r["title"] as? String, "La luna me sabe a poco")
        XCTAssertEqual(r["artist"] as? String, "Marea")
        XCTAssertEqual(r["thumbnail"] as? String, "https://img.test/yt.webp")
        XCTAssertNil(r["existing"])
        let c = try XCTUnwrap((r["candidates"] as? [[String: Any]])?.first)
        XCTAssertEqual(c["id"] as? String, ytID)
        XCTAssertEqual(c["duration"] as? Double, 253)
        XCTAssertEqual(c["source"] as? String, "youtube")
        XCTAssertEqual(c["artist"] as? String, "Marea")
    }

    func testResolveSpotifyListsCandidates() async throws {
        let rig = try LinkRig()
        defer { rig.cleanup() }
        let r = await rig.result("link.resolve", "{\"url\":\(lkJSON(spURL))}")
        XCTAssertEqual(r["link"] as? String, "spotify")
        XCTAssertEqual(r["duration"] as? Double, 253)
        let cs = try XCTUnwrap(r["candidates"] as? [[String: Any]])
        XCTAssertEqual(cs.count, 2)
        XCTAssertEqual(cs[0]["id"] as? String, "aaaaaaaaaaa")
        XCTAssertEqual(cs[0]["isClose"] as? Bool, true)
        XCTAssertEqual(cs[1]["isLive"] as? Bool, true)
        XCTAssertEqual(cs[0]["thumbnail"] as? String, "https://i.ytimg.com/vi/aaaaaaaaaaa/mqdefault.jpg")
        XCTAssertEqual(r["noCloseCandidate"] as? Bool, false)
    }

    func testSearchSpotifyByText() async throws {
        let track = SpotifyTrackResult(id: "3demoDemoDemoDemoDemox", name: "La luna me sabe a poco", artists: ["Marea", "Invitado"],
                                       album: "Besos de Perro", year: 2004, durationMs: 253_000, imageURL: URL(string: "https://img.test/c.jpg"))
        let rig = try LinkRig(spotify: FakeSpotify(result: .success([track])))
        defer { rig.cleanup() }
        let r = await rig.result("link.search", "{\"query\":\"  luna marea \"}")
        XCTAssertEqual(r["query"] as? String, "luna marea")
        let t = try XCTUnwrap((r["tracks"] as? [[String: Any]])?.first)
        XCTAssertEqual(t["name"] as? String, "La luna me sabe a poco")
        XCTAssertEqual(t["artists"] as? [String], ["Marea", "Invitado"])
        XCTAssertEqual(t["year"] as? Int, 2004)
        XCTAssertEqual(t["durationText"] as? String, "4:13")
        XCTAssertEqual(t["trackURL"] as? String, spURL)
        XCTAssertEqual(t["appURL"] as? String, "spotify:track:3demoDemoDemoDemoDemox")
        let empty = await rig.errorCode("link.search", "{\"query\":\" \"}")
        XCTAssertEqual(empty?.code, "bad-params")

        // «Elegir»: la página resuelve la URL de la pista como cualquier enlace.
        let res = await rig.result("link.resolve", "{\"url\":\(lkJSON(t["trackURL"] as? String ?? ""))}")
        XCTAssertEqual(res["link"] as? String, "spotify")
    }

    func testSearchSpotifyErrorsUseMacTexts() async throws {
        let missing = try LinkRig(spotify: FakeSpotify(result: .failure(.missingCredentials)))
        defer { missing.cleanup() }
        let m = await missing.errorCode("link.search", "{\"query\":\"marea\"}")
        XCTAssertEqual(m?.code, "spotify-missing-credentials")
        XCTAssertEqual(m?.message, "Búsqueda en Spotify no disponible: falta la clave (.env)")
        let net = try LinkRig(spotify: FakeSpotify(result: .failure(.network)))
        defer { net.cleanup() }
        let n = await net.errorCode("link.search", "{\"query\":\"marea\"}")
        XCTAssertEqual(n?.message, "Sin conexión con Spotify")
        let none = try LinkRig(spotify: FakeSpotify(result: .success([])))
        defer { none.cleanup() }
        let r = await none.result("link.search", "{\"query\":\"zzz\"}")
        XCTAssertEqual((r["tracks"] as? [Any])?.count, 0)
    }

    func testAddManualYouTubeCandidate() async throws {
        let rig = try LinkRig()
        defer { rig.cleanup() }
        // Sin resolución previa no hay a dónde añadir.
        let none = await rig.errorCode("link.addManual", "{\"url\":\(lkJSON(ytURL))}")
        XCTAssertEqual(none?.code, "unsupported-link")
        _ = await rig.result("link.resolve", "{\"url\":\(lkJSON(spURL))}")
        let r = await rig.result("link.addManual", "{\"url\":\(lkJSON(ytURL))}")
        XCTAssertEqual(r["added"] as? String, ytID)
        XCTAssertEqual(r["selectable"] as? Bool, true)
        let cs = try XCTUnwrap((r["resolution"] as? [String: Any])?["candidates"] as? [[String: Any]])
        XCTAssertEqual(cs.count, 3)
        XCTAssertEqual(cs[0]["id"] as? String, ytID)
        XCTAssertEqual(cs[0]["difference"] as? Double, 0)
        XCTAssertEqual(cs[0]["isClose"] as? Bool, true)
        // El candidato añadido se puede importar con `candidateId`.
        let start = await rig.result("link.import", "{\"candidateId\":\(lkJSON(ytID))}")
        XCTAssertNotNil(start["jobId"] as? String)
        let bad = await rig.errorCode("link.addManual", "{\"url\":\"https://example.com/x\"}")
        XCTAssertEqual(bad?.code, "unsupported-link")
    }

    func testResolveErrorsUseSourceMessages() async throws {
        let rig = try LinkRig()
        defer { rig.cleanup() }
        let badopt = await rig.errorCode("link.resolve", "{\"url\":\"https://example.com/x\"}"); let bad = try XCTUnwrap(badopt)
        XCTAssertEqual(bad.code, "unsupported-link")
        XCTAssertTrue(bad.message.hasPrefix("Enlace no admitido\nSe admiten enlaces"))
        let empty = await rig.errorCode("link.resolve", "{\"url\":\"  \"}")
        XCTAssertEqual(empty?.code, "bad-params")

        let age = try LinkRig(infoStatus: 1, infoStderr: "ERROR: Sign in to confirm your age")
        defer { age.cleanup() }
        let eopt = await age.errorCode("link.resolve", "{\"url\":\(lkJSON(ytURL))}"); let e = try XCTUnwrap(eopt)
        XCTAssertEqual(e.code, "age-restricted")
        XCTAssertEqual(e.message, "Vídeo con restricción de edad\nVídeo con restricción de edad: no se puede descargar sin cuenta.")

        let broken = try LinkRig(infoStatus: 1, infoStderr: "ERROR: unable to extract")
        defer { broken.cleanup() }
        let bopt = await broken.errorCode("link.resolve", "{\"url\":\(lkJSON(ytURL))}"); let b = try XCTUnwrap(bopt)
        XCTAssertEqual(b.code, "extractor-broken")
    }

    func testImportYouTubeDownloadsImportsAndKeepsCover() async throws {
        let rig = try LinkRig()
        defer { rig.cleanup() }
        let start = await rig.result("link.import", "{\"url\":\(lkJSON(ytURL))}")
        let jobID = try XCTUnwrap(start["jobId"] as? String)
        XCTAssertTrue(jobID.hasPrefix("link-"))
        let done = await eventually { !rig.finished().isEmpty }
        XCTAssertTrue(done)
        let f = try XCTUnwrap(rig.finished().first)
        XCTAssertEqual(f["jobId"] as? String, jobID)
        XCTAssertEqual(f["duplicate"] as? Bool, false)
        XCTAssertNil(f["error"])
        let id = try XCTUnwrap(f["id"] as? String)

        // Etapas de la cola: descarga, importación y fin (los cambios de texto dentro de una etapa se limitan a 4 por segundo).
        let mine = rig.events.named("jobs.progress").filter { $0["id"] as? String == jobID }
        XCTAssertEqual(mine.first?["stage"] as? String, "download")
        XCTAssertEqual(mine.last?["stage"] as? String, "import")
        XCTAssertEqual(mine.last?["state"] as? String, "done")

        // El tema: origen, título y carátula en `source/cover.jpg` (el ffmpeg simulado la convirtió a JPEG).
        let list = await rig.result("library.list")
        let p = try XCTUnwrap((list["projects"] as? [[String: Any]])?.first { $0["id"] as? String == id })
        XCTAssertEqual(p["title"] as? String, "La luna me sabe a poco")
        XCTAssertEqual(p["artist"] as? String, "Marea")
        XCTAssertEqual(p["origin"] as? String, "youtube")
        let cover = try XCTUnwrap(p["cover"] as? String)
        XCTAssertTrue(cover.hasSuffix("source/cover.jpg"))
        let bytes = try Data(contentsOf: rig.projects.appendingPathComponent(cover))
        XCTAssertEqual(Array(bytes.prefix(3)), [0xFF, 0xD8, 0xFF])

        // Resolver otra vez el mismo enlace: ya está en la biblioteca.
        let again = await rig.result("link.resolve", "{\"url\":\(lkJSON(ytURL))}")
        XCTAssertEqual((again["existing"] as? [String: Any])?["id"] as? String, id)
        XCTAssertEqual((again["candidates"] as? [Any])?.count, 0)

        // Importarlo otra vez: duplicado, sin descargar de nuevo.
        let before = rig.downloadRequests()
        _ = await rig.result("link.import", "{\"url\":\(lkJSON(ytURL))}")
        let two = await eventually { rig.finished().count == 2 }
        XCTAssertTrue(two)
        XCTAssertEqual(rig.finished()[1]["duplicate"] as? Bool, true)
        XCTAssertEqual(rig.finished()[1]["id"] as? String, id)
        XCTAssertEqual(rig.downloadRequests(), before)
    }

    func testImportSpotifyCandidateWithOverrides() async throws {
        let rig = try LinkRig()
        defer { rig.cleanup() }
        let noID = await rig.errorCode("link.import", "{\"candidateId\":\"aaaaaaaaaaa\"}")
        XCTAssertEqual(noID?.code, "not-found")
        let spotifyOnly = await rig.errorCode("link.import", "{\"url\":\(lkJSON(spURL))}")
        XCTAssertEqual(spotifyOnly?.code, "bad-params")
        let nothing = await rig.errorCode("link.import", "{}")
        XCTAssertEqual(nothing?.code, "bad-params")

        _ = await rig.result("link.resolve", "{\"url\":\(lkJSON(spURL))}")
        let r = await rig.result("link.import", "{\"candidateId\":\"aaaaaaaaaaa\",\"title\":\"Luna\",\"artist\":\"Marea Viva\"}")
        XCTAssertNotNil(r["jobId"])
        let done = await eventually { !rig.finished().isEmpty }
        XCTAssertTrue(done)
        let id = try XCTUnwrap(rig.finished()[0]["id"] as? String)
        let detail = await rig.result("library.project", "{\"id\":\(lkJSON(id))}")
        XCTAssertEqual(detail["title"] as? String, "Luna")
        XCTAssertEqual(detail["artist"] as? String, "Marea Viva")
        XCTAssertEqual(detail["origin"] as? String, "spotify")
        // La separación va a la misma cola con el UUID del tema.
        let separated = await eventually {
            rig.events.named("jobs.progress").contains { $0["id"] as? String == id && $0["stage"] as? String == "separation" }
        }
        XCTAssertTrue(separated)
    }

    func testFailedImportReportsErrorInQueue() async throws {
        let rig = try LinkRig(infoStatus: 1, infoStderr: "Private video")
        defer { rig.cleanup() }
        let r = await rig.result("link.import", "{\"url\":\(lkJSON(ytURL))}")
        let jobID = try XCTUnwrap(r["jobId"] as? String)
        let done = await eventually { !rig.finished().isEmpty }
        XCTAssertTrue(done)
        let f = try XCTUnwrap(rig.finished().first)
        XCTAssertEqual((f["error"] as? [String: Any])?["code"] as? String, "private-video")
        XCTAssertTrue(f["id"] == nil || f["id"] is NSNull)
        let last = rig.events.named("jobs.progress").last { $0["id"] as? String == jobID }
        XCTAssertEqual(last?["state"] as? String, "failed")
        XCTAssertEqual(last?["error"] as? String, "Este vídeo es privado.")
    }

    func testCancelResolve() async throws {
        let rig = try LinkRig(hangInfo: true)
        defer { rig.cleanup() }
        let pending = Task { await rig.raw("link.resolve", "{\"url\":\(lkJSON(ytURL))}") }
        let started = await eventually { !rig.runner.requests.filter { $0.arguments.contains("-J") }.isEmpty }
        XCTAssertTrue(started)
        let c = await rig.result("link.cancel")
        XCTAssertEqual(c["cancelled"] as? Bool, true)
        let r = (try? JSONSerialization.jsonObject(with: Data(await pending.value.utf8))) as? [String: Any] ?? [:]
        XCTAssertEqual((r["error"] as? [String: Any])?["code"] as? String, "cancelled")
        let none = await rig.result("link.cancel")
        XCTAssertEqual(none["cancelled"] as? Bool, false)
    }

    func testCancelDownloadJob() async throws {
        let rig = try LinkRig(hangDownload: true)
        defer { rig.cleanup() }
        let r = await rig.result("link.import", "{\"url\":\(lkJSON(ytURL))}")
        let jobID = try XCTUnwrap(r["jobId"] as? String)
        let started = await eventually { rig.downloadRequests() == 1 }
        XCTAssertTrue(started)
        let c = await rig.result("link.cancel", "{\"jobId\":\(lkJSON(jobID))}")
        XCTAssertEqual(c["cancelled"] as? Bool, true)
        let done = await eventually { !rig.finished().isEmpty }
        XCTAssertTrue(done)
        XCTAssertEqual((rig.finished()[0]["error"] as? [String: Any])?["code"] as? String, "cancelled")
        let last = rig.events.named("jobs.progress").last { $0["id"] as? String == jobID }
        XCTAssertEqual(last?["state"] as? String, "cancelled")
        XCTAssertEqual(last?["stage"] as? String, "download")
        let list = await rig.result("library.list")
        XCTAssertEqual((list["projects"] as? [Any])?.count, 0)
    }

    func testToolsInfoAndRevert() async throws {
        let rig = try LinkRig()
        defer { rig.cleanup() }
        let i = await rig.result("tools.info")
        let seen = "tools.info=\(i) helpers=\(rig.helpers.path) requests=\(rig.runner.requests.map(\.executable.lastPathComponent))"
        XCTAssertEqual(i["ytDlpVersion"] as? String, "2026.10.26", seen)
        XCTAssertEqual(i["ytDlpOrigin"] as? String, "embedded", seen)
        XCTAssertEqual(i["denoVersion"] as? String, "2.1.4", seen)
        XCTAssertEqual(i["ffmpegVersion"] as? String, "7.1", seen)

        // Un yt-dlp actualizado más nuevo en la carpeta de soporte manda; revertir vuelve al embebido.
        let fm = FileManager.default
        try fm.createDirectory(at: rig.supportHelpers, withIntermediateDirectories: true)
        fm.createFile(atPath: rig.supportHelpers.appendingPathComponent(SourceKit.HelperLocator.fileName("yt-dlp")).path,
                      contents: Data("y".utf8), attributes: [.posixPermissions: 0o755])
        let info = YtDlpInstallInfo(version: "2026.11.01", sha256: "00", installedAt: Date())
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try enc.encode(info).write(to: rig.supportHelpers.appendingPathComponent(SourceKit.HelperLocator.infoFileName))
        let updated = await rig.result("tools.info")
        XCTAssertEqual(updated["ytDlpVersion"] as? String, "2026.11.01")
        XCTAssertEqual(updated["ytDlpOrigin"] as? String, "updated")

        let rev = await rig.result("tools.revertYtDlp")
        XCTAssertEqual(rev["reverted"] as? Bool, true)
        let back = await rig.result("tools.info")
        XCTAssertEqual(back["ytDlpOrigin"] as? String, "embedded")
    }

    @MainActor func testHelperNamesAndEnvironment() {
        #if os(Windows)
        let ext = ".exe"
        #else
        let ext = ""
        #endif
        for n in ["yt-dlp", "deno", "ffmpeg"] { XCTAssertEqual(SourceKit.HelperLocator.fileName(n), n + ext) }
        // `TF_HELPERS` llega por el diccionario de entorno (no por setenv).
        let env = [ExternalSources.environmentKey: "C:\\tf-helpers"]
        let s = ExternalSources.production(supportDir: URL(fileURLWithPath: "/s"), environment: env)
        XCTAssertTrue(s.bundleDirectory.path.hasSuffix("tf-helpers"), "bundle=\(s.bundleDirectory.path)")
        XCTAssertEqual(s.supportDirectory.lastPathComponent, "Helpers", "support=\(s.supportDirectory.path)")
    }

    func testMissingHelperIsReported() async throws {
        let rig = try LinkRig()
        defer { rig.cleanup() }
        try FileManager.default.removeItem(at: rig.helpers.appendingPathComponent(SourceKit.HelperLocator.fileName("ffmpeg")))
        let eopt = await rig.errorCode("link.resolve", "{\"url\":\(lkJSON(ytURL))}"); let e = try XCTUnwrap(eopt)
        XCTAssertEqual(e.code, "helper-missing")
        XCTAssertTrue(e.message.contains("«ffmpeg»"))
        let t = await rig.result("tools.info")
        XCTAssertNil(t["ffmpegVersion"] as? String)
    }

    func testPossibleDuplicateAndLookup() {
        XCTAssertTrue(PossibleDuplicate.matches(title: "La Luna me sabe a poco", artist: "Marea",
                                                otherTitle: "la luna, me sabe a  poco", otherArtist: "MAREA"))
        XCTAssertTrue(PossibleDuplicate.matches(title: "Lo que te hace falta", artist: "Leiva, Robe",
                                                otherTitle: "Lo que te hace falta", otherArtist: "Leiva"))
        XCTAssertTrue(PossibleDuplicate.matches(title: "Canción", artist: "Álvaro", otherTitle: "Cancion", otherArtist: "alvaro"))
        XCTAssertFalse(PossibleDuplicate.matches(title: "Frontera", artist: "Marea", otherTitle: "Frontera", otherArtist: "Extremoduro"))
        XCTAssertFalse(PossibleDuplicate.matches(title: "Frontera", artist: nil, otherTitle: "Frontera", otherArtist: "Marea"))
        XCTAssertFalse(PossibleDuplicate.matches(title: "Frontera", artist: "Marea", otherTitle: "Frontera (en directo)", otherArtist: "Marea"))
        var l = LibraryLookup()
        l.tracks = [ExistingTrack(id: UUID(), title: "Frontera", artist: "Extremoduro")]
        XCTAssertNotNil(l.possible(title: "frontera", artist: "extremoduro"))
        XCTAssertNil(l.possible(title: "Frontera", artist: "Marea"))
    }

    func testCoverPreparation() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-cover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let jpg = dir.appendingPathComponent("a.bin"), webp = dir.appendingPathComponent("b.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xDB]).write(to: jpg)
        try Data("RIFFxxxxWEBP".utf8).write(to: webp)
        let runner = ScriptedProcessRunner()
        runner.on("-frames:v", ScriptedResponse(sideEffect: { req in
            try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: URL(fileURLWithPath: req.arguments.last ?? ""))
        }))
        let ffmpeg = URL(fileURLWithPath: "/h/ffmpeg")
        // JPEG (por cabecera, sea cual sea la extensión): tal cual, sin lanzar ffmpeg.
        let same = await CoverConverter.prepared(jpg, in: dir, ffmpeg: ffmpeg, runner: runner)
        XCTAssertEqual(same, jpg)
        XCTAssertTrue(runner.requests.isEmpty)
        // Webp: convertido con ffmpeg.
        let conv = await CoverConverter.prepared(webp, in: dir, ffmpeg: ffmpeg, runner: runner)
        XCTAssertEqual(conv.lastPathComponent, "cover-converted.jpg")
        XCTAssertTrue(CoverConverter.isJPEG(conv))
        // Sin ffmpeg, o si falla: se devuelve sin convertir.
        let none = await CoverConverter.prepared(webp, in: dir, ffmpeg: nil, runner: runner)
        XCTAssertEqual(none, webp)
        let failing = ScriptedProcessRunner()
        failing.on("-frames:v", ScriptedResponse(stderr: "boom", status: 1))
        let failed = await CoverConverter.prepared(webp, in: dir, ffmpeg: ffmpeg, runner: failing)
        XCTAssertEqual(failed, webp)
    }
}
