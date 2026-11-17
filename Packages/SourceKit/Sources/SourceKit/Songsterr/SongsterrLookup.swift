import Foundation
import Observation

/// Lo que `SongsterrLookup` necesita del cliente (lo cumple `SongsterrClient`; los tests, un doble).
public protocol SongsterrServing: Sendable {
    func search(artist: String, title: String) async throws -> [SongsterrSearchResult]
    func song(songId: Int) async throws -> SongsterrSong
    func song(link: String) async throws -> SongsterrSong
}

extension SongsterrClient: SongsterrServing {}

/// Qué falló al hablar con Songsterr, con el texto del aviso (spec, «Calidad de la tablatura (Fase 5b)» > Errores).
public enum SongsterrIssue: Equatable, Sendable {
    /// Sin resultados: «No está en Songsterr» y se ofrece la automática.
    case noResults
    /// 429 o bloqueo equivalente: aviso con «Reintentar», sin bucles.
    case rateLimited
    case offline
    /// Página o pista que no se entiende: «Songsterr ha cambiado su formato» y automática.
    case formatChanged
    /// Enlace que no es de Songsterr.
    case invalidLink
    case other(String)

    public init(_ error: Error) {
        switch error as? SongsterrError {
        case .noResults?: self = .noResults
        case .rateLimited?: self = .rateLimited
        case .offline?: self = .offline
        case .unknownFormat?: self = .formatChanged
        case .invalidHost?: self = .invalidLink
        case .httpStatus(let c)?: self = c == 429 ? .rateLimited : .other("Songsterr respondió con el error \(c).")
        default: self = .other(error.localizedDescription)
        }
    }

    public var message: String {
        switch self {
        case .noResults: "No está en Songsterr."
        case .rateLimited: "Songsterr está limitando las peticiones. Espera un poco y vuelve a intentarlo."
        case .offline: "No se pudo conectar con Songsterr. Comprueba la conexión."
        case .formatChanged: "Songsterr ha cambiado su formato."
        case .invalidLink: "Ese enlace no es de Songsterr."
        case .other(let m): m
        }
    }

    /// Se ofrece «Reintentar» (nunca se reintenta solo).
    public var canRetry: Bool {
        switch self {
        case .rateLimited, .offline, .other: true
        default: false
        }
    }

    /// Lo que se hace sin Songsterr es la transcripción automática.
    public var suggestsAutomatic: Bool { self != .invalidLink }
}

/// Estado de la hoja «Tablatura de Songsterr» (mini-spec Fase 5b, «Recorrido» 1 y 2): búsqueda por artista y título,
/// resultado marcado con sus pistas, otros resultados y enlace pegado. Sin UI ni red propia (`SongsterrServing`).
@MainActor @Observable
public final class SongsterrLookup {
    public enum Phase: Equatable, Sendable {
        case idle
        /// «Buscando en Songsterr…»
        case searching
        case results
        case failed(SongsterrIssue)
    }

    private let service: any SongsterrServing

    public private(set) var phase: Phase = .idle
    public private(set) var results: [SongsterrSearchResult] = []
    /// Resultado marcado.
    public private(set) var selectedID: Int?
    /// Temas ya leídos (con sus pistas) por `songId`.
    public private(set) var songs: [Int: SongsterrSong] = [:]
    /// Tema cuyas pistas se están leyendo.
    public private(set) var loadingID: Int?
    /// Fallo al leer las pistas del tema marcado (la lista de resultados sigue ahí).
    public private(set) var detailIssue: SongsterrIssue?
    /// Texto del campo «pegar un enlace».
    public var link = ""
    public private(set) var linkIssue: SongsterrIssue?


    private var lastQuery: (artist: String, title: String)?
    private var task: Task<Void, Never>?

    public init(service: any SongsterrServing) { self.service = service }

    public var selectedSong: SongsterrSong? { selectedID.flatMap { songs[$0] } }
    public var isBusy: Bool { phase == .searching || loadingID != nil }

    /// Busca y marca el primer resultado, leyendo sus pistas.
    public func search(artist: String, title: String) async {
        lastQuery = (artist, title)
        phase = .searching
        results = []
        selectedID = nil
        detailIssue = nil
        do {
            let found = try await service.search(artist: artist, title: title)
            guard !found.isEmpty else { phase = .failed(.noResults); return }
            results = found
            phase = .results
            await select(found[0].songId)
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(SongsterrIssue(error))
        }
    }

    /// Marca un resultado y lee sus pistas si aún no se tienen.
    public func select(_ songId: Int) async {
        selectedID = songId
        detailIssue = nil
        guard songs[songId] == nil else { return }
        loadingID = songId
        defer { if loadingID == songId { loadingID = nil } }
        do {
            let song = try await service.song(songId: songId)
            songs[songId] = song
        } catch is CancellationError {
        } catch {
            if selectedID == songId { detailIssue = SongsterrIssue(error) }
        }
    }

    /// Lee el tema de un enlace pegado y lo marca (se añade arriba de la lista si no estaba).
    public func submitLink() async {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        linkIssue = nil
        loadingID = -1
        defer { loadingID = nil }
        do {
            let song = try await service.song(link: text)
            songs[song.songId] = song
            if !results.contains(where: { $0.songId == song.songId }) {
                results.insert(SongsterrSearchResult(songId: song.songId, artist: song.artist, title: song.title), at: 0)
            }
            phase = .results
            selectedID = song.songId
            detailIssue = nil
        } catch is CancellationError {
        } catch {
            linkIssue = SongsterrIssue(error)
        }
    }

    /// «Reintentar» tras un fallo de la búsqueda o de las pistas del tema marcado. Una sola vez por pulsación.
    public func retry() async {
        if case .failed = phase, let q = lastQuery {
            await search(artist: q.artist, title: q.title)
        } else if let id = selectedID, detailIssue != nil {
            await select(id)
        }
    }
}
