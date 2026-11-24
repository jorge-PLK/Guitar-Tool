import Foundation
import SourceKit
import Store
import XCTest
@testable import AppCore

// Parte 1.2c: volcado de `Contract/fixtures/playlist/` desde el Router real, con yt-dlp, ffmpeg y red simulados.
// Los `playlist.changed.<paso>.event.json` salen de `playlist.state` en ese paso (mismo `PlaylistSnapshot` que emite el
// sondeo; el sondeo real depende de un temporizador de 250 ms y no es reproducible), salvo `error`, construido a mano.

private struct PFImporter: AudioImporting {
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

private struct PFSeparator: StemSeparating {
    var modelIdentifier: String? { "fake@1" }
    func separate(input: URL, outputDirectory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for kind in StemKind.allCases {
            try "stem".write(to: outputDirectory.appendingPathComponent("\(kind.rawValue).wav"), atomically: true, encoding: .utf8)
        }
        progress(1)
    }
}

private let pfA = "3demoDemoDemoDemoDemoA"
private let pfB = "3demoDemoDemoDemoDemoB"
private let pfC = "3demoDemoDemoDemoDemoC"
private let pfSpotifyList = "https://open.spotify.com/playlist/37i9dQZF1DWUNNEvaozpW5"
private let pfYouTubeList = "https://www.youtube.com/playlist?list=PLabc_123-x"

/// Embed mínimo con tres temas: A (252 s), B (300 s), C (252 s).
private struct PFHTTP: HTTPFetching {
    func data(from url: URL, headers: [String: String]) async throws -> Data {
        guard url.host == "open.spotify.com", url.path.hasPrefix("/embed/") else { return Data("RIFFxxxxWEBP".utf8) }
        let rows = [(pfA, "Tema A", 252_000), (pfB, "Tema B", 300_000), (pfC, "Tema C", 252_000)]
        let list = rows.map {
            #"{"uri":"spotify:track:\#($0.0)","title":"\#($0.1)","subtitle":"Marea","duration":\#($0.2),"isExplicit":false}"#
        }.joined(separator: ",")
        let json = #"{"props":{"pageProps":{"state":{"data":{"entity":{"name":"Mi lista","id":"x","trackList":[\#(list)]}}}}}}"#
        return Data(#"<html><script id="__NEXT_DATA__" type="application/json">\#(json)</script></html>"#.utf8)
    }
}

private struct PFRig {
    let base: FixtureRig
    let bridge: Bridge
    let runner = ScriptedProcessRunner()

    init(hangList: Bool = false, hangSearch: Bool = false, hangDownload: Bool = false,
         downloadStatus: Int32 = 0, downloadStderr: String = "") throws {
        base = try FixtureRig(area: "playlist")
        let fm = FileManager.default
        let dir = base.dir
        let projects = dir.appendingPathComponent("PLProjects", isDirectory: true)
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
        runner.on("--flat-playlist -J https://www.youtube.com/playlist",
                  ScriptedResponse(stdout: "{\"title\":\"Lista YT\",\"entries\":[\(yt)]}", hangs: hangList))
        let runner = self.runner
        func search(_ needle: String, _ rows: [(String, String, Double)]) {
            let entries = rows.map {
                "{\"_type\":\"url\",\"id\":\"\($0.0)\",\"url\":\"https://www.youtube.com/watch?v=\($0.0)\",\"title\":\"\($0.1)\",\"channel\":\"Marea\",\"duration\":\($0.2)}"
            }.joined(separator: ",")
            runner.on("ytsearch5:Marea \(needle)", ScriptedResponse(
                stdout: "{\"id\":\"q\",\"title\":\"q\",\"_type\":\"playlist\",\"entries\":[\(entries)]}", hangs: hangSearch))
        }
        search("Tema A", [("aaaaaaaaaaa", "Marea - Tema A (Audio oficial)", 252.2), ("aaaaaaaaaa2", "Marea - Tema A (Directo)", 301)])
        search("Tema B", [("bbbbbbbbbbb", "Marea - Tema B (Directo)", 301), ("bbbbbbbbbb2", "Marea - Tema B", 200)])
        // C ofrece también el vídeo de A: una vez importado A, elegirlo es «ya en la biblioteca».
        search("Tema C", [("ccccccccccc", "Marea - Tema C (Audio oficial)", 252.4),
                          ("aaaaaaaaaaa", "Marea - Tema A (Audio oficial)", 252.2)])
        runner.on("bestaudio", ScriptedResponse(stderr: downloadStderr, status: downloadStatus,
                                                progressLines: ["TFPROGRESS 50 100 NA"], sideEffect: { req in
            guard let i = req.arguments.firstIndex(of: "-o") else { return }
            try Data("audio".utf8).write(to: URL(fileURLWithPath: req.arguments[i + 1].replacingOccurrences(of: "%(ext)s", with: "webm")))
        }, hangs: hangDownload))
        runner.on("pcm_s24le", ScriptedResponse(sideEffect: { req in
            try Data("wav-\(UUID().uuidString)".utf8).write(to: URL(fileURLWithPath: req.arguments.last ?? ""))
        }))
        let sources = ExternalSources(bundleDirectory: helpers, supportDirectory: dir.appendingPathComponent("PLSupport/Helpers"),
                                      runner: runner, http: PFHTTP(), workRoot: dir.appendingPathComponent("work", isDirectory: true))
        let services = JobServices(importer: PFImporter(), separator: PFSeparator(), levelMeter: nil,
                                   analyzer: nil, guitarSplitter: nil)
        bridge = try Bridge(options: LaunchOptions(projectsFolder: projects, supportDir: dir.appendingPathComponent("PLSupport")),
                            mediaBase: "https://tf.media/", reveal: nil, services: services, link: sources, spotify: nil)
    }

    func cleanup() { base.cleanup() }

    func q(_ s: String) -> String { base.jsonString(s) }

    func raw(_ method: String, _ params: String = "{}") async throws -> [String: Any] {
        let r = await bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
    }

    /// Llama al método real y vuelca `<name>.params/.result|.error`. Devuelve `result` (o `[:]` si hubo error).
    @discardableResult
    func run(_ name: String, method: String? = nil, params: String = "{}", expectError code: String? = nil,
             settle: (() async throws -> [String: Any])? = nil,
             file: StaticString = #filePath, line: UInt = #line) async throws -> [String: Any] {
        try base.golden(name, .params, params, file: file, line: line)
        let o = try await raw(method ?? name, params)
        if let e = o["error"] as? [String: Any] {
            XCTAssertEqual(e["code"] as? String, code, "\(name): error inesperado", file: file, line: line)
            try base.golden(name, .error, try FixtureRig.text(e), file: file, line: line)
            return [:]
        }
        XCTAssertNil(code, "\(name) debía fallar", file: file, line: line)
        var r = try XCTUnwrap(o["result"], file: file, line: line)
        // Acciones que arrancan trabajo asíncrono: la respuesta inmediata depende de la carrera con la tarea, así que se
        // vuelca la instantánea ya asentada (mismo tipo `PlaylistSnapshot`; la respuesta real se comprueba que lo es).
        if let settle {
            XCTAssertNotNil((r as? [String: Any])?["step"], "\(name): la respuesta no es una instantánea", file: file, line: line)
            r = try await settle()
        }
        try base.golden(name, .result, try FixtureRig.text(r), file: file, line: line)
        return r as? [String: Any] ?? [:]
    }

    func state() async throws -> [String: Any] {
        let o = try await raw("playlist.state")
        return o["result"] as? [String: Any] ?? [:]
    }

    /// Espera el paso y devuelve esa instantánea.
    func wait(_ step: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) async throws -> [String: Any] {
        let end = Date().addingTimeInterval(timeout)
        var s = try await state()
        while s["step"] as? String != step, Date() < end {
            try await Task.sleep(for: .milliseconds(20))
            s = try await state()
        }
        XCTAssertEqual(s["step"] as? String, step, file: file, line: line)
        return s
    }

    /// Espera a que termine `playlist.updateAndRetry` (el estado queda con `update.updating == false`).
    func waitUpdated() async throws -> [String: Any] {
        let end = Date().addingTimeInterval(10)
        var s = try await state()
        func updating(_ s: [String: Any]) -> Bool { (s["update"] as? [String: Any])?["updating"] as? Bool != false }
        while updating(s), Date() < end {
            try await Task.sleep(for: .milliseconds(20))
            s = try await state()
        }
        XCTAssertFalse(updating(s))
        return s
    }

    /// Espera a que el tema esté `downloading` (con su progreso ya fijado) en la cola.
    func waitDownloading(file: StaticString = #filePath, line: UInt = #line) async throws -> [String: Any] {
        let end = Date().addingTimeInterval(10)
        var s = try await state()
        func downloading(_ s: [String: Any]) -> Bool {
            (s["items"] as? [[String: Any]])?.contains { $0["status"] as? String == "downloading" } == true
        }
        while !downloading(s), Date() < end {
            try await Task.sleep(for: .milliseconds(20))
            s = try await state()
        }
        XCTAssertTrue(downloading(s), file: file, line: line)
        return s
    }

    /// `playlist.changed.<paso>` desde una instantánea ya leída.
    func event(_ step: String, _ snapshot: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(snapshot["step"] as? String, step, file: file, line: line)
        try base.golden("playlist.changed.\(step)", .event, try FixtureRig.text(snapshot), file: file, line: line)
    }

    func open(_ url: String) async throws {
        let o = try await raw("link.resolve", "{\"url\":\(q(url))}")
        XCTAssertNotNil((o["result"] as? [String: Any])?["playlist"], "\(o)")
    }
}

final class ContractFixturesPlaylistTests: XCTestCase {
    private func ids(_ s: [String: Any]) -> [String] { (s["items"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String } }

    /// Sin lista abierta.
    func testNoPlaylist() async throws {
        let rig = try PFRig()
        defer { rig.cleanup() }
        try await rig.run("playlist.start.noPlaylist", method: "playlist.start", expectError: "no-playlist")
        try await rig.run("playlist.state.noPlaylist", method: "playlist.state", expectError: "no-playlist")
        let c = try await rig.run("playlist.close.none", method: "playlist.close", params: "{\"force\":false}")
        XCTAssertEqual(c["closed"] as? Bool, false)
        XCTAssertEqual(c["live"] as? Bool, false)
    }

    func testLoading() async throws {
        let rig = try PFRig(hangList: true)
        defer { rig.cleanup() }
        let task = Task { _ = try await rig.raw("link.resolve", "{\"url\":\(rig.q(pfYouTubeList))}") }
        let s = try await rig.wait("loading")
        try rig.event("loading", s)
        _ = try await rig.raw("link.cancel")
        try await task.value
    }

    /// Spotify: pista a pista hasta la revisión, elecciones y cola completa hasta el resumen.
    func testSpotifyFlow() async throws {
        let rig = try PFRig()
        defer { rig.cleanup() }
        try await rig.open(pfSpotifyList)
        let tracks = try await rig.run("playlist.state")
        XCTAssertEqual(tracks["step"] as? String, "tracks")
        try rig.event("tracks", tracks)

        try await rig.run("playlist.select", params: "{\"id\":\(rig.q(pfA)),\"selected\":true}")
        try await rig.run("playlist.selectAll")
        try await rig.run("playlist.selectNone")
        try await rig.run("playlist.select.b", method: "playlist.select", params: "{\"id\":\(rig.q(pfB)),\"selected\":true}")
        try await rig.run("playlist.select.a", method: "playlist.select", params: "{\"id\":\(rig.q(pfA)),\"selected\":true}")
        try await rig.run("playlist.continue", settle: { try await rig.wait("review") })
        let review = try await rig.wait("review")
        try rig.event("review", review)

        try await rig.run("playlist.skip.error", method: "playlist.skip", params: "{\"id\":\"nope\"}", expectError: "not-found")
        try await rig.run("playlist.skip", params: "{\"id\":\(rig.q(pfB))}")
        try await rig.run("playlist.choose", params: "{\"id\":\(rig.q(pfB)),\"candidateId\":\"bbbbbbbbbbb\"}")
        // `search` no vuelve a buscar los temas que ya tienen candidato elegido: el estado asentado es el mismo `review`.
        try await rig.run("playlist.search", settle: { try await rig.wait("review") })
        try await rig.run("playlist.choose.b", method: "playlist.choose", params: "{\"id\":\(rig.q(pfB)),\"candidateId\":\"bbbbbbbbbbb\"}")
        try await rig.run("playlist.start", settle: { try await rig.wait("summary") })
        let summary = try await rig.wait("summary")
        try rig.event("summary", summary)
        XCTAssertEqual((summary["summary"] as? [String: Any])?["imported"] as? Int, 2)

        // A ya está en la biblioteca: C ofrece el vídeo de A y elegirlo falla.
        try await rig.open(pfSpotifyList)
        _ = try await rig.raw("playlist.select", "{\"id\":\(rig.q(pfC)),\"selected\":true}")
        _ = try await rig.raw("playlist.continue")
        _ = try await rig.wait("review")
        try await rig.run("playlist.choose.error", method: "playlist.choose",
                          params: "{\"id\":\(rig.q(pfC)),\"candidateId\":\"aaaaaaaaaaa\"}", expectError: "in-library")
    }

    /// Búsqueda detenida a medias, cierre con trabajo vivo y forzado.
    func testSearchingAndClose() async throws {
        let rig = try PFRig(hangSearch: true)
        defer { rig.cleanup() }
        try await rig.open(pfSpotifyList)
        _ = try await rig.raw("playlist.selectAll")
        _ = try await rig.raw("playlist.continue")
        let s = try await rig.wait("searching")
        try rig.event("searching", s)
        let c = try await rig.run("playlist.close.live", method: "playlist.close", params: "{\"force\":false}")
        XCTAssertEqual(c["closed"] as? Bool, false)
        XCTAssertEqual(c["live"] as? Bool, true)
        let f = try await rig.run("playlist.close.force", method: "playlist.close", params: "{\"force\":true}")
        XCTAssertEqual(f["closed"] as? Bool, true)
    }

    /// Cola en marcha, cancelada y reanudada.
    func testRunningCancelResume() async throws {
        let rig = try PFRig(hangDownload: true)
        defer { rig.cleanup() }
        try await rig.open(pfYouTubeList)
        _ = try await rig.raw("playlist.selectAll")
        _ = try await rig.raw("playlist.continue")
        let running = try await rig.waitDownloading()
        try rig.event("running", running)
        let cancelled = try await rig.run("playlist.cancel", settle: { try await rig.wait("summary") })
        XCTAssertEqual((cancelled["summary"] as? [String: Any])?["cancelled"] as? Bool, true)
        try await rig.run("playlist.resume", settle: { try await rig.waitDownloading() })
        _ = try await rig.raw("playlist.close", "{\"force\":true}")
    }

    /// yt-dlp roto: la cola se detiene y se ofrece actualizar.
    func testStoppedAndUpdateAndRetry() async throws {
        let rig = try PFRig(downloadStatus: 1, downloadStderr: "ERROR: unable to extract")
        defer { rig.cleanup() }
        try await rig.open(pfYouTubeList)
        _ = try await rig.raw("playlist.selectAll")
        _ = try await rig.raw("playlist.continue")
        let stopped = try await rig.wait("stopped")
        try rig.event("stopped", stopped)
        try await rig.run("playlist.updateAndRetry", settle: { try await rig.waitUpdated() })
    }

    /// Fallos de tema suelto (no detienen la cola) y reintento.
    func testRetryFailed() async throws {
        let rig = try PFRig(downloadStatus: 1, downloadStderr: "ERROR: Private video")
        defer { rig.cleanup() }
        try await rig.open(pfYouTubeList)
        _ = try await rig.raw("playlist.selectAll")
        _ = try await rig.raw("playlist.continue")
        let s = try await rig.wait("summary")
        XCTAssertEqual((s["summary"] as? [String: Any])?["failed"] as? Int, 2)
        try await rig.run("playlist.retryFailed", settle: {
            let end = Date().addingTimeInterval(10)
            var s = try await rig.state()
            func failed(_ s: [String: Any]) -> Bool {
                s["step"] as? String == "summary" && (s["summary"] as? [String: Any])?["failed"] as? Int == 2
            }
            while !failed(s), Date() < end { try await Task.sleep(for: .milliseconds(20)); s = try await rig.state() }
            return s
        })
    }

    /// `error` no se alcanza con los simulados (una lectura fallida es un error RPC y cierra la sesión): instantánea real a mano.
    func testErrorEvent() throws {
        let rig = try PFRig()
        defer { rig.cleanup() }
        let snap = PlaylistSnapshot(
            step: "error", searchDone: nil, searchTotal: nil, error: PlaylistErrorInfo(.offline), name: "Mi lista",
            source: "spotify", kind: "playlist", mayBeTruncated: false, isLive: false, indicator: nil,
            totals: PlaylistTotalsInfo(total: 0, selected: 0, imported: 0, skipped: 0, failed: 0, inLibrary: 0,
                                       remaining: 0, queued: 0, duplicates: 0),
            summary: PlaylistSummaryInfo(imported: 0, skipped: 0, inLibrary: 0, failed: 0, remaining: 0, cancelled: false),
            progress: 0, update: PlaylistUpdateInfo(updating: false, alreadyLatest: false, error: nil), warnings: [], items: [])
        try rig.base.event("playlist.changed.error", snap)
    }
}
