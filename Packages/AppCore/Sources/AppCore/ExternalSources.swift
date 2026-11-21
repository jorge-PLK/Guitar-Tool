import Foundation
import SourceKit
import Store

// Cableado de SourceKit (8.3b): copia adaptada de `App/Sources/ExternalSources.swift` (Mac). Sin ImageIO ni UTType.
// OJO: `AppCore.HelperLocator` (Services.swift, `tf-separate`) y `SourceKit.HelperLocator` (yt-dlp, deno, ffmpeg) se
// llaman igual; aquí el de SourceKit va siempre calificado.

/// Versiones de los helpers para Ajustes («Fuentes externas»).
struct ExternalToolsInfo: Equatable, Sendable {
    var ytDlpVersion: String?
    var ytDlpOrigin: SourceKit.HelperLocator.Origin?
    var denoVersion: String?
    var ffmpegVersion: String?
}

/// Puente entre el núcleo y `SourceKit`: localiza los helpers (carpeta de la app y carpeta `Helpers` de soporte), monta el
/// `SourceImporter` y el `YtDlpUpdater`. La versión del yt-dlp embebido se obtiene ejecutando `yt-dlp --version` una vez.
@MainActor
final class ExternalSources {
    /// Variable de entorno con la carpeta de `yt-dlp`, `deno` y `ffmpeg` (si no, junto al ejecutable). Solo desarrollo y QA.
    nonisolated static let environmentKey = "TF_HELPERS"
    /// Margen de la descarga del binario de yt-dlp (decenas de MB), mayor que el de los metadatos.
    nonisolated static let updateTimeout: TimeInterval = 180

    let bundleDirectory: URL
    let supportDirectory: URL
    private let runner: ProcessRunning
    private let http: HTTPFetching
    private let workRoot: URL
    private var bundleVersion: String??

    nonisolated init(bundleDirectory: URL, supportDirectory: URL, runner: ProcessRunning = SystemProcessRunner(),
                     http: HTTPFetching = URLSessionFetcher(), workRoot: URL = SourceImporter.defaultWorkRoot) {
        self.bundleDirectory = bundleDirectory
        self.supportDirectory = supportDirectory
        self.runner = runner
        self.http = http
        self.workRoot = workRoot
    }

    /// Las de producción: `TF_HELPERS` o la carpeta del ejecutable; el yt-dlp actualizado en `<supportDir>/Helpers`.
    nonisolated static func production(supportDir: URL?, environment: [String: String]) -> ExternalSources {
        let bundle: URL
        if let p = environment[environmentKey], !p.isEmpty {
            bundle = URL(fileURLWithPath: p, isDirectory: true)
        } else {
            bundle = Bundle.main.executableURL?.deletingLastPathComponent()
                ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        }
        let support = supportDir?.appendingPathComponent("Helpers", isDirectory: true)
            ?? SourceKit.HelperLocator.defaultSupportDirectory
        return ExternalSources(bundleDirectory: bundle, supportDirectory: support)
    }

    /// Como `SourceKit.HelperLocator.isRunnable` (interna): Mac, ejecutable; Windows, basta que exista el `.exe`.
    nonisolated static func isRunnable(_ path: String) -> Bool {
        #if os(Windows)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
        #else
        return FileManager.default.isExecutableFile(atPath: path)
        #endif
    }

    func locator() async -> SourceKit.HelperLocator {
        if bundleVersion == nil {
            let exe = bundleDirectory.appendingPathComponent(SourceKit.HelperLocator.fileName("yt-dlp"))
            var v: String?
            if Self.isRunnable(exe.path),
               let r = try? await runner.run(.init(executable: exe, arguments: ["--version"], timeout: .total(30))), r.status == 0 {
                v = String(decoding: r.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            bundleVersion = .some(v)
        }
        return SourceKit.HelperLocator(bundleDirectory: bundleDirectory, supportDirectory: supportDirectory,
                                       bundleYtDlpVersion: bundleVersion ?? nil)
    }

    /// Importador nuevo: lee el `yt-dlp` vigente (embebido o actualizado) al crearlo.
    func makeImporter() async throws -> SourceImporter {
        let loc = await locator()
        let yt = try loc.ytDlp()
        let client = YtDlpClient(executable: yt.url, deno: try loc.deno(), runner: runner)
        let transcoder = AudioTranscoder(ffmpeg: try loc.ffmpeg(), runner: runner)
        return SourceImporter(ytDlp: client, transcoder: transcoder, http: http, spotify: SpotifyEmbedClient(http: http),
                              workRoot: workRoot)
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

    /// Carátula lista para guardar como `source/cover.jpg` (ver `CoverConverter.prepared`).
    func preparedCover(_ art: URL, in directory: URL) async -> URL {
        let ffmpeg = try? await locator().ffmpeg()
        return await CoverConverter.prepared(art, in: directory, ffmpeg: ffmpeg, runner: runner)
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
        let name = r.executable.deletingPathExtension().lastPathComponent
        if name == "yt-dlp", let url = current() { r.executable = url }
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
}

/// Carátula para `source/cover.jpg`. El Mac convierte con ImageIO; aquí: JPEG tal cual (se reconoce por su cabecera, no por
/// la extensión), si no se convierte con el ffmpeg embebido y, si eso falla, se devuelve sin convertir (WebView2 detecta el
/// formato de la imagen al pintarla).
enum CoverConverter {
    static let timeout: TimeInterval = 30

    /// Cabecera JPEG: `FF D8 FF`.
    static func isJPEG(_ file: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? h.close() }
        guard let head = try? h.read(upToCount: 3), head.count == 3 else { return false }
        return Array(head) == [0xFF, 0xD8, 0xFF]
    }

    /// El fichero a guardar como carátula: el mismo si ya es JPEG, el convertido en `directory`, o el original.
    static func prepared(_ source: URL, in directory: URL, ffmpeg: URL?, runner: ProcessRunning) async -> URL {
        if isJPEG(source) { return source }
        guard let ffmpeg else { return source }
        let out = directory.appendingPathComponent("cover-converted.jpg")
        try? FileManager.default.removeItem(at: out)
        let args = ["-y", "-v", "error", "-i", source.path, "-frames:v", "1", "-q:v", "3", out.path]
        guard let r = try? await runner.run(.init(executable: ffmpeg, arguments: args, timeout: .total(timeout))),
              r.status == 0, isJPEG(out) else { return source }
        return out
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
