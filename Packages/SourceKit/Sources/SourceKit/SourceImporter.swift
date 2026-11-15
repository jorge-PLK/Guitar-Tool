import Foundation
import Observation

/// Datos de origen del tema importado (la app los traduce a `SongOrigin`).
public struct ImportedOrigin: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable { case youtube, spotify }
    public var kind: Kind
    /// El enlace pegado.
    public var url: String
    public var videoID: String
    public var channel: String?
    public var spotifyID: String?
    public var album: String?
    /// Códec real descargado: `opus` o `aac`.
    public var codec: String
    public var ytDlpVersion: String
    public var importedAt: Date
    /// Solo si el tema viene de una lista (spec, «Listas»): identificador y nombre de la lista.
    public var playlistID: String? = nil
    public var playlistName: String? = nil
}

/// Avisos para la hoja que no son errores.
public enum ImportNotice: Sendable, Equatable {
    /// «Sin Opus: descargado en M4A, agudos hasta ~16 kHz» (spec, «Recorrido» paso 4).
    case fellBackToM4A

    public var message: String {
        switch self {
        case .fellBackToM4A: "Sin Opus: descargado en M4A, agudos hasta ~16 kHz"
        }
    }
}

/// Lo que devuelve `SourceImporter.download`. Vive en `workDirectory` (carpeta temporal): la app lo importa
/// en la biblioteca y luego llama a `cleanUp()`.
public struct ImportedSource: Sendable {
    public var wavURL: URL
    public var title: String
    public var artist: String
    public var origin: ImportedOrigin
    /// Carátula descargada (Spotify: la mayor del embed; YouTube: miniatura). Conserva la extensión del origen.
    public var artworkURL: URL?
    public var notices: [ImportNotice]
    public var workDirectory: URL

    public func cleanUp() { try? FileManager.default.removeItem(at: workDirectory) }
}

/// Lo resuelto a partir del enlace, para la hoja de candidatos.
public struct ResolvedSource: Sendable, Equatable {
    public var link: SourceLink
    /// El texto pegado, tal cual (queda en `origin.url`).
    public var pastedURL: String
    public var title: String
    public var artist: String
    public var album: String?
    public var durationSeconds: Double?
    public var artworkURL: URL?
    /// Solo Spotify: hasta cinco, ordenados por diferencia de duración. Ninguno preseleccionado.
    public var candidates: [RankedCandidate]
    /// Solo YouTube: el vídeo que se pide confirmar.
    public var confirmation: Candidate?
    /// Spotify sin ningún candidato cercano (o búsqueda vacía): aviso y campo para pegar un enlace.
    public var noCloseCandidate: Bool
}

public enum ResolvingStage: Sendable, Equatable { case metadata, searching }
public enum DownloadStage: Sendable, Equatable { case downloading, converting }

public enum ImportState: Sendable, Equatable {
    case idle
    case resolving(ResolvingStage)
    case candidates(ResolvedSource)
    /// `progress`: 0...1 en la descarga; nil si no se conoce.
    case downloading(DownloadStage, progress: Double?)
    case finished
    case failed(SourceError)
}

/// Orquesta el recorrido de «Fuentes externas» y publica el estado para la hoja. No depende de Store.
@MainActor @Observable
public final class SourceImporter {
    public private(set) var state: ImportState = .idle
    public private(set) var resolved: ResolvedSource?
    public private(set) var notices: [ImportNotice] = []
    @ObservationIgnored public var onStateChange: ((ImportState) -> Void)?

    @ObservationIgnored private let ytDlp: YtDlpClient
    @ObservationIgnored private let transcoder: AudioTranscoder
    @ObservationIgnored private let http: HTTPFetching
    @ObservationIgnored private let spotify: SpotifyMetadataFetching
    @ObservationIgnored private let workRoot: URL
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(ytDlp: YtDlpClient, transcoder: AudioTranscoder, http: HTTPFetching, spotify: SpotifyMetadataFetching,
                workRoot: URL = FileManager.default.temporaryDirectory.appendingPathComponent("ToneForge-source"),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.ytDlp = ytDlp
        self.transcoder = transcoder
        self.http = http
        self.spotify = spotify
        self.workRoot = workRoot
        self.now = now
    }

    /// Carpeta de trabajo por defecto de las descargas (`<tmp>/ToneForge-source/<UUID>`).
    public nonisolated static var defaultWorkRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ToneForge-source", isDirectory: true)
    }

    /// Al arrancar, antes de que ninguna descarga la use: borra la carpeta de trabajo entera (descargas huérfanas
    /// de una ejecución anterior). Devuelve `true` si existía.
    @discardableResult
    public nonisolated static func removeOrphanedDownloads(workRoot: URL = SourceImporter.defaultWorkRoot) -> Bool {
        guard FileManager.default.fileExists(atPath: workRoot.path) else { return false }
        return (try? FileManager.default.removeItem(at: workRoot)) != nil
    }

    /// Pasos 1 a 3 del recorrido. Publica `.candidates` o `.failed` (y relanza el error).
    @discardableResult
    public func resolve(_ text: String) async throws -> ResolvedSource {
        try await resolve(text, search: true)
    }

    /// Como `resolve`, pero con Spotify no busca candidatos (para descargar un vídeo ya conocido).
    @discardableResult
    public func resolveWithoutSearch(_ text: String) async throws -> ResolvedSource {
        try await resolve(text, search: false)
    }

    private func resolve(_ text: String, search: Bool) async throws -> ResolvedSource {
        notices = []
        resolved = nil
        do {
            let link = try SourceLink.parse(text)
            set(.resolving(.metadata))
            let pasted = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let result: ResolvedSource
            switch link {
            case .youtube:
                let v = try await ytDlp.info(url: link.canonicalURL)
                result = ResolvedSource(
                    link: link, pastedURL: pasted, title: v.title, artist: v.artist, album: v.album,
                    durationSeconds: v.durationSeconds, artworkURL: v.thumbnailURL, candidates: [],
                    confirmation: Candidate(id: v.id, url: link.canonicalURL, title: v.title, channel: v.channel,
                                            durationSeconds: v.durationSeconds),
                    noCloseCandidate: false)
            case .spotify(let id):
                let t = try await spotify.track(id: id)
                if search { set(.resolving(.searching)) }
                // Consulta «<artista> <título>» con el primer artista (la spec no fija cuál).
                let query = ([t.artists.first].compactMap { $0 } + [t.title]).joined(separator: " ")
                let found = search ? try await ytDlp.search(query: query) : []
                let ranked = CandidateRanker.rank(found, referenceDuration: t.durationSeconds, referenceTitle: t.title)
                result = ResolvedSource(
                    link: link, pastedURL: pasted, title: t.title, artist: t.artists.joined(separator: ", "), album: nil,
                    durationSeconds: t.durationSeconds, artworkURL: t.artworkURL, candidates: ranked, confirmation: nil,
                    noCloseCandidate: search && !ranked.contains { $0.isClose })
            }
            resolved = result
            set(.candidates(result))
            return result
        } catch { throw fail(error) }
    }

    /// Enlace de YouTube pegado a mano cuando ningún candidato convence: se añade al principio de la lista.
    @discardableResult
    public func addManualCandidate(_ text: String) async throws -> Candidate {
        guard var current = resolved else { throw SourceError.unsupportedLink }
        do {
            guard case .youtube = try SourceLink.parse(text) else { throw SourceError.unsupportedLink }
            let link = try SourceLink.parse(text)
            let v = try await ytDlp.info(url: link.canonicalURL)
            let c = Candidate(id: v.id, url: link.canonicalURL, title: v.title, channel: v.channel,
                              durationSeconds: v.durationSeconds)
            let diff = (c.durationSeconds != nil && current.durationSeconds != nil) ? c.durationSeconds! - current.durationSeconds! : nil
            current.candidates.removeAll { $0.id == c.id }
            current.candidates.insert(
                RankedCandidate(candidate: c, difference: diff, isClose: diff.map { abs($0) <= CandidateRanker.closeThreshold } ?? false,
                                isLive: CandidateRanker.isLive(title: c.title)),
                at: 0)
            resolved = current
            set(.candidates(current))
            return c
        } catch { throw fail(error) }
    }

    /// Pasos 4 y 5. `title` y `artist` son los (posiblemente corregidos) de la hoja. Al fallar o cancelar borra la
    /// carpeta temporal; al terminar la deja a la app (`ImportedSource.cleanUp`).
    public func download(candidate: Candidate, title: String, artist: String) async throws -> ImportedSource {
        guard let resolved else { throw SourceError.unsupportedLink }
        return try await download(candidate: candidate, title: title, artist: artist, resolved: resolved)
    }

    /// Lo mismo con el origen dado (lo usa `PlaylistImporter`, que no pasa por `resolve`).
    func download(candidate: Candidate, title: String, artist: String, resolved: ResolvedSource) async throws -> ImportedSource {
        let work = workRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            set(.downloading(.downloading, progress: nil))
            let version = (try? await ytDlp.version()) ?? "desconocida"
            let audio = try await ytDlp.download(url: candidate.url, into: work) { [weak self] f in
                Task { @MainActor in self?.applyProgress(f) }
            }
            var notices: [ImportNotice] = []
            if audio.fellBackToM4A { notices.append(.fellBackToM4A) }
            self.notices = notices

            var artwork: URL?
            if let url = resolved.artworkURL, let data = try? await http.data(from: url, headers: [:]) {
                let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                let file = work.appendingPathComponent("cover.\(ext)")
                if (try? data.write(to: file)) != nil { artwork = file }
            }
            try Task.checkCancellation()

            set(.downloading(.converting, progress: nil))
            let wav = work.appendingPathComponent("audio.wav")
            try await transcoder.convert(input: audio.url, output: wav)
            try? FileManager.default.removeItem(at: audio.url)

            let origin = ImportedOrigin(
                kind: { if case .spotify = resolved.link { .spotify } else { .youtube } }(),
                url: resolved.pastedURL, videoID: candidate.id, channel: candidate.channel,
                spotifyID: { if case .spotify(let id) = resolved.link { id } else { nil } }(),
                album: resolved.album, codec: audio.codec, ytDlpVersion: version, importedAt: now())
            set(.finished)
            return ImportedSource(wavURL: wav, title: title, artist: artist, origin: origin, artworkURL: artwork,
                                  notices: notices, workDirectory: work)
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw fail(error)
        }
    }

    public func reset() {
        resolved = nil
        notices = []
        set(.idle)
    }

    // MARK: -

    private func applyProgress(_ f: Double) {
        if case .downloading(.downloading, _) = state { set(.downloading(.downloading, progress: f)) }
    }

    /// Cancelar vuelve a `.idle` (no es un error para la hoja); el resto se publica como `.failed`.
    private func fail(_ error: Error) -> Error {
        if error is CancellationError || (error as? SourceError) == .cancelled {
            set(.idle)
            return SourceError.cancelled
        }
        let e = (error as? SourceError) ?? SourceError.launchFailed(error.localizedDescription)
        // Tras un error de vídeo la hoja vuelve a los candidatos: se conserva `resolved`.
        set(.failed(e))
        return e
    }

    private func set(_ new: ImportState) {
        state = new
        onStateChange?(new)
    }
}
