#if DEBUG
import AppKit
import Foundation
import SourceKit

/// `--link-import-demo <vacio|resolviendo|candidatos|descargando|error|youtube|m4a|repetido|posible-repetido|lista-temas|lista-100|lista-revision|lista-cola|lista-resumen>`: abre la hoja con datos simulados
/// (`ScriptedProcessRunner`, HTTP simulado y estados forzados), sin red ni helpers, para capturas.
@MainActor
extension AppModel {
    func openLinkImportDemo(_ state: String) {
        let demo = DemoSources()
        let session = LinkImportSession(hooks: .init(
            makeImporter: { demo.importer() },
            existingProject: { _ in nil },
            store: { _, _ in },
            updateYtDlp: { YtDlpInstallInfo(version: "2026.11.10", sha256: "demo", installedAt: Date()) },
            lookup: { DemoSources.lookup(state) },
            open: { [weak self] _ in self?.linkImport = nil },
            makePlaylist: { throw SourceError.cancelled },
            discardPlaylist: { [weak self] in self?.playlistImport = nil },
            close: { [weak self] _ in self?.linkImport = nil }))
        linkImport = session
        if state.hasPrefix("lista-") {
            Task {
                await demo.playlist(state, hooks: playlistHooks()) { p in
                    self.playlistImport = p
                    session.playlist = p
                }
            }
            return
        }
        let spotify = "https://open.spotify.com/track/3demoDemoDemoDemoDemox"
        let youtube = "https://www.youtube.com/watch?v=4CJwzwOIPAY"
        Task {
            switch state {
            case "vacio": break
            case "resolviendo": session.forced = .resolving(.searching)
            case "preparando": session.forced = .preparing
            case "candidatos": await demo.resolve(session, spotify)
            case "descargando":
                await demo.resolve(session, spotify)
                session.selectedID = session.resolved?.candidates.first?.id
                session.forced = .working("Descargando audio…", 0.42)
            case "m4a":
                await demo.resolve(session, spotify)
                session.forced = .working("Convirtiendo a WAV…", nil)
            case "error":
                await demo.resolve(session, spotify)
                session.selectedID = session.resolved?.candidates.first?.id
                session.failure = .extractorBroken(version: "2026.10.26", detail: "ERROR: [youtube] 4CJwzwOIPAY: Unable to extract nsig function code")
                session.forced = .error
            case "youtube": await demo.resolve(session, youtube)
            case "posible-repetido": await demo.resolve(session, spotify)
            case "repetido":
                // El tema de Spotify del enlace ya está en la biblioteca: no se busca ni se descarga.
                session.text = spotify
                session.continueTapped()
                for _ in 0..<100 where session.existing == nil { try? await Task.sleep(for: .milliseconds(50)) }
            default: break
            }
        }
    }
}

@MainActor
private struct DemoSources {
    let cover: URL
    let http: DemoHTTP
    let runner = ScriptedProcessRunner()

    init() {
        cover = FileManager.default.temporaryDirectory.appendingPathComponent("tf-demo-cover.png")
        let size = NSSize(width: 300, height: 300)
        let img = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.95, green: 0.64, blue: 0.23, alpha: 1), NSColor(red: 0.1, green: 0.12, blue: 0.14, alpha: 1)])?
                .draw(in: rect, angle: 45)
            return true
        }
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: cover) }
        http = DemoHTTP(cover: cover)
        let search = Self.searchJSON
        runner.on("ytsearch5:", ScriptedResponse(stdout: search))
        runner.on("-J --no-playlist", ScriptedResponse(stdout: """
            {"id":"4CJwzwOIPAY","title":"La luna me sabe a poco","channel":"Marea","artist":"Marea","duration":253,"thumbnail":"\(cover.absoluteString)"}
            """))
        runner.on("--version", ScriptedResponse(stdout: "2026.10.26\n"))
    }

    func importer() -> SourceImporter {
        SourceImporter(ytDlp: YtDlpClient(executable: URL(fileURLWithPath: "/demo/yt-dlp"), deno: URL(fileURLWithPath: "/demo/deno"), runner: runner),
                       transcoder: AudioTranscoder(ffmpeg: URL(fileURLWithPath: "/demo/ffmpeg"), runner: runner),
                       http: http, spotify: SpotifyEmbedClient(http: http))
    }

    func resolve(_ session: LinkImportSession, _ link: String) async {
        session.text = link
        session.continueTapped()
        // Espera a que el recorrido simulado publique los candidatos.
        for _ in 0..<100 where session.resolved == nil { try? await Task.sleep(for: .milliseconds(50)) }
    }

    // MARK: Listas

    private static let listID = "37i9dQZF1DXdemoDemoDem"

    /// Biblioteca simulada: el tema del enlace de Spotify de la demo, un tema de la lista y el vídeo del tercer candidato.
    /// Con `posible-repetido` el tema solo está por título y artista (importado desde un fichero): sin id de Spotify.
    static func lookup(_ state: String) -> LibraryLookup {
        var l = LibraryLookup(
            spotify: ["3demoDemoDemoDemoDemox": ExistingTrack(id: UUID(), title: "La luna me sabe a poco", artist: "Marea"),
                      inLibraryID: ExistingTrack(id: UUID(), title: "Dulce Condena", artist: "Los Rodríguez")],
            video: ["ccccccccccc": ExistingTrack(id: UUID(), title: "La luna me sabe a poco - Marea", artist: "Rock en español")])
        l.tracks = [ExistingTrack(id: UUID(), title: "Pa' to el año", artist: "Marea"),
                    ExistingTrack(id: UUID(), title: "Frontera", artist: "Extremoduro")]
        // Solo `repetido` reconoce el enlace por su id de Spotify; `posible-repetido` solo por título y artista.
        if state == "posible-repetido" { l.tracks.append(ExistingTrack(id: UUID(), title: "La luna me sabe a poco", artist: "Marea")) }
        if state != "repetido" { l.spotify["3demoDemoDemoDemoDemox"] = nil }
        return l
    }
    /// (id, título, artista, segundos).
    private static let tracks: [(String, String, String, Double)] = [
        ("sp01", "La luna me sabe a poco", "Marea", 253), ("sp02", "Pa to el año", "Marea", 241),
        ("sp03", "Corazón de mimbre", "Marea", 215), ("sp04", "Perro Ciego", "Marea", 262),
        ("sp05", "Mi Madre es una Yonki", "Marea", 198), ("sp06", "El Hombre del Saco", "Marea", 232),
        ("sp07", "Frontera", "Extremoduro", 286), ("sp08", "So Payaso", "Extremoduro", 306),
        ("sp09", "Jesucristo García", "Extremoduro", 317), ("sp10", "Standby", "Extremoduro", 247),
        ("sp11", "Sin Documentos", "Los Rodríguez", 237), ("sp12", "Dulce Condena", "Los Rodríguez", 221)]

    /// Temas que la simulación trata aparte: en la biblioteca, sin candidato cercano, solo con directo cercano,
    /// con fallo al descargar y con descarga en curso.
    private static let inLibraryID = "sp12", doubtfulID = "sp06", liveOnlyID = "sp08", failingID = "sp02", hangingID = "sp03"

    func playlist(_ state: String, hooks: PlaylistImportSession.Hooks, show: (PlaylistImportSession) -> Void) async {
        let many = state == "lista-100"
        var list = Self.tracks
        if many {
            list = (0..<100).map { n -> (String, String, String, Double) in
                (id: "sp\(n + 100)", title: "Tema número \(n + 1)", artist: n % 3 == 0 ? "Marea" : "Extremoduro",
                 secs: 180 + Double(n % 7) * 11)
            }
        }
        let runner = DemoQueueRunner(base: ScriptedProcessRunner(), failing: Self.failingID, hanging: Self.hangingID)
        runner.base.on("--version", ScriptedResponse(stdout: "2026.10.26\n"))
        for t in list {
            let studio = t.3 + (t.0 == Self.doubtfulID ? 25 : t.0 == Self.liveOnlyID ? 22 : 0.6)
            let live = t.3 + (t.0 == Self.liveOnlyID ? -0.4 : 48)
            let rows: [(String, String, String, Double)] = [
                ("v\(t.0)", "\(t.2) - \(t.1) (Audio oficial)", t.2, studio),
                ("w\(t.0)", "\(t.2) - \(t.1) (En directo)", "\(t.2) Oficial", live),
                ("x\(t.0)", "\(t.1) (letra)", "Letras Rock", t.3 + 9)]
            let e = rows.map { "{\"id\":\"\($0.0)\",\"title\":\"\($0.1)\",\"channel\":\"\($0.2)\",\"duration\":\($0.3)}" }.joined(separator: ",")
            runner.base.on("ytsearch5:\(t.2) \(t.1)", ScriptedResponse(stdout: "{\"entries\":[\(e)]}"))
        }
        runner.base.on("-f ", ScriptedResponse(sideEffect: { req in
            guard let i = req.arguments.firstIndex(of: "-o") else { return }
            try Data("a".utf8).write(to: URL(fileURLWithPath: req.arguments[i + 1].replacingOccurrences(of: "%(ext)s", with: "webm")))
        }))
        runner.base.on("ffmpeg", ScriptedResponse(sideEffect: { req in
            if let last = req.arguments.last { try Data("wav".utf8).write(to: URL(fileURLWithPath: last)) }
        }))
        let embedTracks = list.map {
            "{\"uri\":\"spotify:track:\($0.0)\",\"title\":\"\($0.1)\",\"subtitle\":\"\($0.2)\",\"duration\":\(Int($0.3 * 1000)),\"isExplicit\":false}"
        }.joined(separator: ",")
        let json = "{\"props\":{\"pageProps\":{\"state\":{\"data\":{\"entity\":{\"name\":\"Marea y compañía\",\"id\":\"x\",\"trackList\":[\(embedTracks)]}}}}}}"
        let http = DemoHTTP(cover: cover, playlistHTML: "<html><script id=\"__NEXT_DATA__\" type=\"application/json\">\(json)</script></html>")
        let importer = PlaylistImporter(
            ytDlp: YtDlpClient(executable: URL(fileURLWithPath: "/demo/yt-dlp"), deno: URL(fileURLWithPath: "/demo/deno"), runner: runner),
            transcoder: AudioTranscoder(ffmpeg: URL(fileURLWithPath: "/demo/ffmpeg"), runner: runner),
            http: http, spotify: SpotifyEmbedClient(http: http),
            workRoot: FileManager.default.temporaryDirectory.appendingPathComponent("tf-demo-list")) { _ in }
        var h = hooks
        h.lookup = { Self.lookup(state) }
        h.duplicateVideoIDs = { [] }
        let session = PlaylistImportSession(importer: importer, hooks: h)
        show(session)
        session.start("https://open.spotify.com/playlist/\(Self.listID)")
        await waitUntil { importer.phase == .tracks }
        if state == "lista-100" {
            for t in list.prefix(37) { importer.setSelected(t.0, true) }
            return
        }
        let marked = ["sp01", "sp02", "sp03", "sp04", "sp05", "sp06", "sp08"]
        if state == "lista-temas" { for id in ["sp01", "sp04", "sp07"] { importer.setSelected(id, true) }; return }
        for id in marked { importer.setSelected(id, true) }
        session.search()
        await waitUntil { importer.phase == .review }
        // Una elección manual de Jorge: un directo.
        if let item = importer.items.first(where: { $0.id == Self.liveOnlyID }), let live = item.candidates.first(where: { $0.isLive }) {
            importer.choose(live.candidate, for: item.id)
        }
        if state == "lista-revision" { return }
        if state != "lista-cola" { runner.hanging = nil }
        session.startQueue()
        if state == "lista-cola" {
            await waitUntil { importer.items.contains { if case .downloading(_, let p?) = $0.status { p > 0 } else { false } } }
            return
        }
        await waitUntil { importer.phase == .finished }
    }

    private func waitUntil(_ cond: @MainActor () -> Bool) async {
        for _ in 0..<200 where !cond() { try? await Task.sleep(for: .milliseconds(50)) }
    }

    static var searchJSON: String {
        let rows: [(String, String, String, Double)] = [
            ("aaaaaaaaaaa", "Marea - La luna me sabe a poco (Audio oficial)", "Marea", 252.2),
            ("bbbbbbbbbbb", "Marea - La luna me sabe a poco (Directo)", "Marea Oficial", 301),
            ("ccccccccccc", "La luna me sabe a poco - Marea", "Rock en español", 249.4),
            ("ddddddddddd", "Marea - La luna me sabe a poco (letra)", "Letras Rock", 254.1),
            ("eeeeeeeeeee", "La luna me sabe a poco (cover guitarra)", "Guitar Lessons", 233)]
        let e = rows.map { """
            {"_type":"url","ie_key":"Youtube","id":"\($0.0)","url":"https://www.youtube.com/watch?v=\($0.0)","title":"\($0.1)","channel":"\($0.2)","duration":\($0.3)}
            """ }.joined(separator: ",")
        return "{\"id\":\"q\",\"title\":\"q\",\"_type\":\"playlist\",\"entries\":[\(e)]}"
    }
}

/// Descargas simuladas: un tema falla por privado y otro se queda descargando a medias.
private final class DemoQueueRunner: ProcessRunning, @unchecked Sendable {
    let base: ScriptedProcessRunner
    private let lock = NSLock()
    private let failing: String
    private var _hanging: String?
    var hanging: String? {
        get { lock.withLock { _hanging } }
        set { lock.withLock { _hanging = newValue } }
    }

    init(base: ScriptedProcessRunner, failing: String, hanging: String) {
        self.base = base
        self.failing = failing
        _hanging = hanging
    }

    func run(_ request: ProcessRequest, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        let key = request.arguments.joined(separator: " ")
        if request.executable.lastPathComponent == "yt-dlp", key.contains("-f ") {
            if key.contains("v=v\(failing)") || key.contains("v=w\(failing)") || key.contains("v=x\(failing)") {
                return ProcessResult(status: 1, stderr: "ERROR: [youtube] Private video. Sign in if you've been granted access to this video")
            }
            if let h = hanging, key.contains("v=v\(h)") || key.contains("v=w\(h)") {
                onLine?("TFPROGRESS 4200000 10000000 0")
                do { while true { try await Task.sleep(for: .milliseconds(10)) } } catch { throw SourceError.cancelled }
            }
        }
        return try await base.run(request, onLine: onLine)
    }
}

private struct DemoHTTP: HTTPFetching {
    let cover: URL
    var playlistHTML: String?

    func data(from url: URL, headers: [String: String]) async throws -> Data {
        if url.path.contains("/embed/playlist/"), let html = playlistHTML { return Data(html.utf8) }
        if url.host == "open.spotify.com" {
            let json = """
            {"props":{"pageProps":{"state":{"data":{"entity":{"id":"3demo","title":"La luna me sabe a poco","duration":253000,
            "artists":[{"name":"Marea"}],"visualIdentity":{"image":[{"url":"\(cover.absoluteString)","maxWidth":640}]}}}}}}}
            """
            return Data("<html><script id=\"__NEXT_DATA__\" type=\"application/json\">\(json)</script></html>".utf8)
        }
        return (try? Data(contentsOf: cover)) ?? Data()
    }
}
#endif
