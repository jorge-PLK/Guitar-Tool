import Foundation
import SourceKit
import Store

// Parte sin interfaz de `App/Sources/LinkImportSheet.swift` (Mac), portada para AppCore (8.3b): recorrido enlace -> resolviendo
// -> candidatos -> error, `LibraryLookup`/`ExistingTrack` y la tabla de mensajes. La descarga no vive aquí: es un trabajo de la
// cola (`LinkMethods.swift`). Spec, «Fuentes externas».

/// Tema que ya está en la biblioteca (spec, «Errores» > «Tema repetido»).
struct ExistingTrack: Sendable, Equatable {
    var id: UUID
    var title: String
    var artist: String?
}

/// Lo que ya tiene la biblioteca, por identificador de Spotify y por `videoID`.
struct LibraryLookup: Sendable, Equatable {
    var spotify: [String: ExistingTrack] = [:]
    var video: [String: ExistingTrack] = [:]
    /// Todos los temas de la biblioteca, para el aviso «posible repetido».
    var tracks: [ExistingTrack] = []

    func possible(title: String, artist: String?) -> ExistingTrack? {
        tracks.first { PossibleDuplicate.matches(title: title, artist: artist, otherTitle: $0.title, otherArtist: $0.artist) }
    }

    /// Escaneo de la carpeta de proyectos (como `AppModel.scanLibraryIDs` del Mac).
    static func scan(root: URL?) -> LibraryLookup {
        guard let root else { return LibraryLookup() }
        var found = LibraryLookup()
        for p in ProjectScanner.scan(root: root).found {
            let t = ExistingTrack(id: p.project.id, title: p.project.song.title, artist: p.project.song.artist)
            found.tracks.append(t)
            guard let o = p.project.song.origin else { continue }
            if let s = o.spotifyID { found.spotify[s] = t }
            if let v = o.videoID { found.video[v] = t }
        }
        return found
    }
}

/// Resultado de resolver un enlace.
struct LinkResolution: Sendable {
    var link: SourceLink
    var pastedURL: String
    /// nil si el tema ya está en la biblioteca (`existing`): no se leen metadatos.
    var resolved: ResolvedSource?
    var existing: ExistingTrack?
    var possibleDuplicate: ExistingTrack?
    var libraryVideos: [String: ExistingTrack]
}

@MainActor
final class LinkImportSession {
    struct Hooks {
        /// Importador nuevo (lee el yt-dlp vigente al crearlo).
        var makeImporter: () async throws -> SourceImporter
        /// Identificadores que ya tiene la biblioteca.
        var lookup: () async -> LibraryLookup
    }

    enum Phase: Equatable {
        case empty
        case resolving
        case candidates
        /// El tema del enlace ya está en la biblioteca.
        case repeated
        case error
    }

    private(set) var phase = Phase.empty
    private(set) var failure: SourceError?
    private(set) var last: LinkResolution?

    private let hooks: Hooks
    private var task: Task<LinkResolution, Error>?
    /// Una sola resolución viva: la nueva gana y la anterior responde `cancelled` aunque termine.
    private var generation = 0
    /// Importador de la última resolución: guarda los candidatos a los que `addManual` añade el enlace pegado a mano.
    private var importer: SourceImporter?

    init(hooks: Hooks) { self.hooks = hooks }

    var isResolving: Bool { phase == .resolving }

    func resolve(_ text: String) async throws -> LinkResolution {
        cancel()
        generation += 1
        let mine = generation
        phase = .resolving
        failure = nil
        last = nil
        let t = Task { try await self.resolveOp(text) }
        task = t
        do {
            let r = try await withTaskCancellationHandler { try await t.value } onCancel: { t.cancel() }
            guard mine == generation else { throw SourceError.cancelled }
            task = nil
            last = r
            phase = r.existing != nil ? .repeated : .candidates
            return r
        } catch {
            guard mine == generation else { throw SourceError.cancelled }
            task = nil
            let e: SourceError = (error as? SourceError) ?? (error is CancellationError ? .cancelled : .launchFailed("\(error)"))
            if e == .cancelled { phase = .empty } else { failure = e; phase = .error }
            throw e
        }
    }

    /// «¿Ninguno convence? Pega un enlace de YouTube» (`addManual` del Mac): añade el vídeo al principio de los candidatos de
    /// la última resolución. Devuelve la resolución actualizada y el id añadido. Errores: los de `SourceError`.
    func addManual(_ text: String) async throws -> (resolution: LinkResolution, added: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let importer, var current = last, current.resolved != nil, !isResolving else { throw SourceError.unsupportedLink }
        let c = try await importer.addManualCandidate(t)
        let video = await hooks.lookup().video
        current.resolved = importer.resolved
        current.libraryVideos = video
        last = current
        return (current, c.id)
    }

    /// Cancela la resolución en curso. `true` si había una.
    @discardableResult
    func cancel() -> Bool {
        let was = task != nil
        generation += 1
        task?.cancel()
        task = nil
        if phase == .resolving { phase = .empty }
        return was
    }

    private func resolveOp(_ text: String) async throws -> LinkResolution {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Enlace no reconocido: se dice antes de buscar los helpers.
        let link = try SourceLink.parse(trimmed)
        let lookup = await hooks.lookup()
        try Task.checkCancellation()
        var existing: ExistingTrack?
        switch link {
        case .spotify(let id): existing = lookup.spotify[id]
        case .youtube(let id): existing = lookup.video[id]
        }
        if let existing {
            return LinkResolution(link: link, pastedURL: trimmed, resolved: nil, existing: existing,
                                  possibleDuplicate: nil, libraryVideos: lookup.video)
        }
        let importer = try await hooks.makeImporter()
        try Task.checkCancellation()
        let r = try await importer.resolve(trimmed)
        try Task.checkCancellation()
        self.importer = importer
        return LinkResolution(link: link, pastedURL: trimmed, resolved: r, existing: nil,
                              possibleDuplicate: lookup.possible(title: r.title, artist: r.artist),
                              libraryVideos: lookup.video)
    }
}

/// Textos de la tabla de errores de la spec («Fuentes externas» > Errores), lo que ve el usuario. Literal del Mac.
enum SourceMessages {
    struct Message {
        var title: String
        var detail: String
    }

    static let supportedLinks = "Se admiten enlaces de un vídeo de YouTube (youtube.com/watch, youtu.be, music.youtube.com) y de una canción de Spotify (open.spotify.com/track o spotify:track). Listas, álbumes y episodios no."  // listas y álbumes: ola 2; entonces vuelve el literal del Mac

    static func text(for e: SourceError) -> Message {
        switch e {
        case .offline: Message(title: "Sin conexión", detail: "No se ha podido conectar. Comprueba la red y reintenta.")
        case .unsupportedLink: Message(title: "Enlace no admitido", detail: supportedLinks)
        case .spotifyMetadataUnreadable:
            Message(title: "No se han podido leer los datos de Spotify",
                 detail: "Pega un enlace de YouTube del tema en su lugar.")
        case .ageRestricted:
            Message(title: "Vídeo con restricción de edad",
                 detail: "Vídeo con restricción de edad: no se puede descargar sin cuenta.")
        case .unavailable(.region): Message(title: "No disponible en tu región", detail: "Este vídeo no está disponible en tu país.")
        case .unavailable(.privateVideo): Message(title: "Vídeo privado", detail: "Este vídeo es privado.")
        case .unavailable(.removed): Message(title: "Vídeo no disponible", detail: "Este vídeo se ha retirado o ya no está disponible.")
        case .noAudioFormat: Message(title: "Sin audio descargable", detail: "Este vídeo no ofrece audio descargable.")
        case .extractorBroken(let v, let d):
            Message(title: "yt-dlp puede estar desactualizado" + (v.map { " (versión \($0))" } ?? ""),
                 detail: d.isEmpty ? "YouTube ha cambiado algo y yt-dlp no sabe leerlo." : d)
        case .ffmpegFailed(let m): Message(title: "Falló la conversión", detail: lastLines(m))
        case .helperMissing(let n):
            Message(title: "Falta un componente", detail: "No se encuentra «\(n)» dentro de la app. Reinstala ToneForge.")
        case .launchFailed(let m): Message(title: "No se pudo lanzar el proceso", detail: lastLines(m))
        case .httpStatus(let c): Message(title: "Respuesta inesperada", detail: "El servidor respondió con el código \(c).")
        case .timedOut: Message(title: "Tiempo agotado", detail: "El servidor tarda demasiado en responder. Reintenta.")
        case .cancelled: Message(title: "Cancelado", detail: "")
        case .checksumMismatch:
            Message(title: "Actualización rechazada", detail: "La suma SHA-256 del yt-dlp descargado no coincide. No se ha instalado nada.")
        case .updateFailed(let m): Message(title: "No se pudo actualizar yt-dlp", detail: lastLines(m))
        case .rateLimited:
            Message(title: "YouTube ha limitado las peticiones",
                    detail: "YouTube ha limitado las peticiones; espera unos minutos y reintenta.")
        case .noAudioProduced: Message(title: "Sin audio", detail: "yt-dlp terminó pero no dejó ningún fichero de audio.")
        }
    }

    static func lastLines(_ s: String, _ n: Int = 4) -> String {
        s.split(whereSeparator: \.isNewline).suffix(n).joined(separator: "\n")
    }

    /// Código del contrato (8.3b) de cada error.
    static func code(for e: SourceError) -> String {
        switch e {
        case .offline: "offline"
        case .unsupportedLink: "unsupported-link"
        case .spotifyMetadataUnreadable: "spotify-unreadable"
        case .ageRestricted: "age-restricted"
        case .unavailable(.region): "region"
        case .unavailable(.privateVideo): "private-video"
        case .unavailable(.removed): "removed"
        case .noAudioFormat: "no-audio-format"
        case .extractorBroken: "extractor-broken"
        case .ffmpegFailed: "ffmpeg-failed"
        case .helperMissing: "helper-missing"
        case .launchFailed: "launch-failed"
        case .httpStatus: "http-status"
        case .timedOut: "timed-out"
        case .cancelled: "cancelled"
        case .checksumMismatch: "checksum-mismatch"
        case .updateFailed: "update-failed"
        case .rateLimited: "rate-limited"
        case .noAudioProduced: "no-audio-produced"
        }
    }

    /// `"<título>\n<detalle>"` (sin detalle, solo el título).
    static func rpc(_ e: SourceError) -> RPCError {
        let m = text(for: e)
        return RPCError(code: code(for: e), message: m.detail.isEmpty ? m.title : m.title + "\n" + m.detail)
    }

    /// Cualquier error del recorrido como `RPCError` (los ajenos a SourceKit, vía `JobEngine.map`).
    static func rpc(_ e: Error) -> RPCError {
        if let s = e as? SourceError { return rpc(s) }
        return JobEngine.map(e)
    }
}
