import Foundation
import ImageIO
import SourceKit
import Store
import UniformTypeIdentifiers

/// Versiones de los helpers para Ajustes («Fuentes externas»).
struct ExternalToolsInfo: Equatable {
    var ytDlpVersion: String?
    var ytDlpOrigin: HelperLocator.Origin?
    var denoVersion: String?
    var ffmpegVersion: String?
}

/// Puente entre la app y `SourceKit`: localiza los helpers (`Contents/MacOS` y `Application Support/ToneForge/Helpers`),
/// monta el `SourceImporter` y el `YtDlpUpdater`. La versión del yt-dlp embebido se obtiene ejecutando
/// `yt-dlp --version` una vez y se guarda en memoria (más simple que pasarla por Info.plist en tiempo de build).
@MainActor
final class ExternalSources {
    let bundleDirectory: URL
    let supportDirectory: URL
    private let runner: ProcessRunning
    private let http: HTTPFetching
    private var bundleVersion: String??

    /// Margen de la descarga del binario de yt-dlp (decenas de MB), mayor que el de los metadatos.
    static let updateTimeout: TimeInterval = 180

    init(bundleDirectory: URL, supportDirectory: URL, runner: ProcessRunning = SystemProcessRunner(),
         http: HTTPFetching = URLSessionFetcher()) {
        self.bundleDirectory = bundleDirectory
        self.supportDirectory = supportDirectory
        self.runner = runner
        self.http = http
    }

    func locator() async -> HelperLocator {
        if bundleVersion == nil {
            let exe = bundleDirectory.appendingPathComponent("yt-dlp")
            var v: String?
            if FileManager.default.isExecutableFile(atPath: exe.path),
               let r = try? await runner.run(.init(executable: exe, arguments: ["--version"], timeout: .total(30))), r.status == 0 {
                v = String(decoding: r.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            bundleVersion = .some(v)
        }
        return HelperLocator(bundleDirectory: bundleDirectory, supportDirectory: supportDirectory,
                             bundleYtDlpVersion: bundleVersion ?? nil)
    }

    func makeImporter() async throws -> SourceImporter {
        let loc = await locator()
        let yt = try loc.ytDlp()
        let client = YtDlpClient(executable: yt.url, deno: try loc.deno(), runner: runner)
        let transcoder = AudioTranscoder(ffmpeg: try loc.ffmpeg(), runner: runner)
        return SourceImporter(ytDlp: client, transcoder: transcoder, http: http, spotify: SpotifyEmbedClient(http: http))
    }

    /// Para listas: el `yt-dlp` se busca en cada llamada, así que tras «Actualizar y reintentar» la cola ya usa el nuevo.
    func makePlaylistImporter(importHandler: @escaping @MainActor (ImportedSource) async throws -> Void) async throws -> PlaylistImporter {
        let loc = await locator()
        let yt = try loc.ytDlp()
        let live = LiveYtDlpRunner(base: runner) { try? loc.ytDlp().url }
        let client = YtDlpClient(executable: yt.url, deno: try loc.deno(), runner: live)
        let transcoder = AudioTranscoder(ffmpeg: try loc.ffmpeg(), runner: runner)
        return PlaylistImporter(ytDlp: client, transcoder: transcoder, http: http, spotify: SpotifyEmbedClient(http: http),
                                importHandler: importHandler)
    }

    func updateYtDlp() async throws -> YtDlpInstallInfo {
        let updater = YtDlpUpdater(supportDirectory: supportDirectory, http: URLSessionFetcher(timeout: Self.updateTimeout),
                                   runner: runner)
        return try await updater.update()
    }

    func removeUpdate() async throws { try await locator().removeUpdate() }

    func toolsInfo() async -> ExternalToolsInfo {
        let loc = await locator()
        var info = ExternalToolsInfo()
        if let c = try? loc.ytDlp() { info.ytDlpVersion = c.version; info.ytDlpOrigin = c.origin }
        info.denoVersion = await firstLine(of: try? loc.deno(), args: ["--version"]).flatMap { word($0, 1) }
        info.ffmpegVersion = await firstLine(of: try? loc.ffmpeg(), args: ["-version"]).flatMap { word($0, 2) }
        return info
    }

    private func firstLine(of exe: URL?, args: [String]) async -> String? {
        guard let exe, let r = try? await runner.run(.init(executable: exe, arguments: args, timeout: .total(15))),
              r.status == 0 else { return nil }
        return String(decoding: r.stdout, as: UTF8.self).split(whereSeparator: \.isNewline).first.map(String.init)
    }

    private func word(_ line: String, _ index: Int) -> String? {
        let w = line.split(separator: " ")
        return index < w.count ? String(w[index]) : nil
    }
}

/// Cambia la ruta de `yt-dlp` en cada petición por la que ahora elige `HelperLocator` (embebido o actualizado).
struct LiveYtDlpRunner: ProcessRunning {
    let base: ProcessRunning
    let current: @Sendable () -> URL?

    func run(_ request: ProcessRequest, onLine: (@Sendable (String) -> Void)?) async throws -> ProcessResult {
        var r = request
        if r.executable.lastPathComponent == "yt-dlp", let url = current() { r.executable = url }
        return try await base.run(r, onLine: onLine)
    }
}

/// Aviso suave de «posible repetido» por título y artista (spec, «Errores» > «Posible repetido»): para lo que los
/// identificadores no reconocen (fichero, otro vídeo, otra edición). Solo avisa; nunca bloquea.
enum PossibleDuplicate {
    /// Minúsculas, sin acentos, sin signos y sin espacios repetidos.
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        return folded.split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }

    /// Título igual y artista igual o uno contenido en el otro. Sin artista en alguno de los dos, no hay aviso.
    static func matches(title: String, artist: String?, otherTitle: String, otherArtist: String?) -> Bool {
        guard let artist, let otherArtist else { return false }
        let (a, b) = (normalize(artist), normalize(otherArtist))
        guard !a.isEmpty, !b.isEmpty else { return false }
        let t = normalize(title)
        return !t.isEmpty && t == normalize(otherTitle) && (a == b || a.contains(b) || b.contains(a))
    }

    /// Comprobación en DEBUG de los casos de la spec (el proyecto de la app no tiene target de tests).
    static func selfCheck() -> Bool {
        matches(title: "La Luna me sabe a poco", artist: "Marea", otherTitle: "la luna, me sabe a  poco", otherArtist: "MAREA")
            && matches(title: "Lo que te hace falta", artist: "Leiva, Robe", otherTitle: "Lo que te hace falta", otherArtist: "Leiva")
            && matches(title: "Canción", artist: "Álvaro", otherTitle: "Cancion", otherArtist: "alvaro")
            && !matches(title: "Frontera", artist: "Marea", otherTitle: "Frontera", otherArtist: "Extremoduro")
            && !matches(title: "Frontera", artist: nil, otherTitle: "Frontera", otherArtist: "Marea")
            && !matches(title: "Frontera", artist: "Marea", otherTitle: "Frontera (en directo)", otherArtist: "Marea")
    }
}

/// Convierte la carátula (YouTube suele dar webp) a JPEG con ImageIO: Store la guarda como `source/cover.jpg`.
enum CoverConverter {
    static func jpeg(from source: URL, to destination: URL, quality: Double = 0.9) -> Bool {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let dst = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dst, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dst)
    }
}

extension SongOrigin {
    /// `artwork` queda en nil: Store lo rellena al copiar la carátula.
    init(_ o: ImportedOrigin) {
        self.init(kind: o.kind == .spotify ? .spotify : .youtube, url: o.url, videoID: o.videoID, channel: o.channel,
                  spotifyID: o.spotifyID, album: o.album, artwork: nil, codec: o.codec, ytDlpVersion: o.ytDlpVersion,
                  importedAt: o.importedAt,
                  playlistID: o.playlistID, playlistName: o.playlistName)
    }
}
