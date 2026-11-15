import Foundation
import Observation

/// Tema de una lista (de Spotify o de YouTube).
public struct PlaylistTrack: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable { case spotify, youtube }
    public var kind: Kind
    /// Identificador de Spotify o `videoID` de YouTube.
    public var id: String
    public var title: String
    /// Spotify: artistas como texto. YouTube: el canal.
    public var artist: String
    public var durationSeconds: Double?

    public init(kind: Kind, id: String, title: String, artist: String, durationSeconds: Double? = nil) {
        self.kind = kind
        self.id = id
        self.title = title
        self.artist = artist
        self.durationSeconds = durationSeconds
    }

    /// Enlace del tema; queda en `origin.url`.
    var url: URL {
        switch kind {
        case .spotify: URL(string: "https://open.spotify.com/track/\(id)")!
        case .youtube: URL(string: "https://www.youtube.com/watch?v=\(id)")!
        }
    }
}

/// Estado de un tema en la hoja y en la cola (spec, «Listas»).
public enum PlaylistTrackStatus: Sendable, Equatable {
    /// Sin trabajo hecho todavía.
    case pending
    /// Buscando candidatos en YouTube (solo Spotify).
    case searching
    /// Con candidato elegido (propuesto por la búsqueda o escogido a mano), a la espera de la cola.
    case proposed
    /// Sin candidato cercano o el mejor es un directo: sin propuesta; se elige uno a mano o se omite.
    case doubtful
    case downloading(DownloadStage, progress: Double?)
    case imported
    case skipped
    /// Ya estaba en la biblioteca (por id de Spotify o por `videoID`).
    case inLibrary
    case failed(SourceError)

    /// Estados en los que el tema no vuelve a procesarse en esta pasada.
    public var isFinal: Bool {
        switch self {
        case .imported, .skipped, .inLibrary, .failed: true
        default: false
        }
    }
}

public struct PlaylistItem: Sendable, Equatable, Identifiable {
    public var track: PlaylistTrack
    public var id: String { track.id }
    /// Marcado para descargar. Nada viene marcado.
    public var isSelected = false
    public var status: PlaylistTrackStatus = .pending
    /// Spotify: hasta cinco, ordenados por diferencia de duración. YouTube: vacío.
    public var candidates: [RankedCandidate] = []
    /// Lo que descargará la cola. YouTube: el propio vídeo.
    public var chosen: Candidate?
}

public struct PlaylistTotals: Sendable, Equatable {
    public var total = 0
    public var selected = 0
    public var imported = 0
    public var skipped = 0
    public var failed = 0
    public var inLibrary = 0
    /// Marcados que aún no han terminado (importados, omitidos, fallidos o en la biblioteca).
    public var remaining = 0
}

public enum PlaylistPhase: Sendable, Equatable {
    case idle
    case loading
    /// Lista leída: paso 1 (marcar temas).
    case tracks
    case searching(done: Int, total: Int)
    /// Búsqueda terminada: tabla de revisión.
    case review
    case running
    /// Parada por límite de YouTube (`.rateLimited`) o por yt-dlp roto (`.extractorBroken`): se puede reanudar.
    case stopped(SourceError)
    case cancelled
    case finished
    case failed(SourceError)
}

/// Lleva los tres pasos de «Listas» sobre `SourceImporter` (descarga y conversión) y publica el estado de cada tema.
/// No depende de Store: cada tema descargado se entrega a `importHandler` (la app lo importa a la biblioteca y encola
/// su separación). SourceKit llama a `cleanUp()` del `ImportedSource` cuando el cierre termina, con o sin error.
@MainActor @Observable
public final class PlaylistImporter {
    /// Paso en el que está la lista.
    public private(set) var phase: PlaylistPhase = .idle
    public private(set) var name = ""
    public private(set) var items: [PlaylistItem] = []
    /// Spotify devolvió 100 temas: la hoja avisa de que puede haber cortado la lista.
    public private(set) var mayBeTruncated = false
    public private(set) var link: PlaylistLink?

    /// «¿Está ya este id de Spotify en la biblioteca?», antes de buscar.
    @ObservationIgnored public var isSpotifyIDInLibrary: (@MainActor (String) -> Bool)?
    /// «¿Está ya este videoID en la biblioteca?», antes de descargar.
    @ObservationIgnored public var isVideoIDInLibrary: (@MainActor (String) -> Bool)?

    @ObservationIgnored private let ytDlp: YtDlpClient
    @ObservationIgnored private let spotify: SpotifyMetadataFetching
    @ObservationIgnored private let inner: SourceImporter
    @ObservationIgnored private let importHandler: @MainActor (ImportedSource) async throws -> Void
    @ObservationIgnored private var currentTask: Task<Void, Never>?
    @ObservationIgnored private var runningItemID: String?

    public init(ytDlp: YtDlpClient, transcoder: AudioTranscoder, http: HTTPFetching, spotify: SpotifyMetadataFetching,
                workRoot: URL = FileManager.default.temporaryDirectory.appendingPathComponent("ToneForge-source"),
                now: @escaping @Sendable () -> Date = { Date() },
                importHandler: @escaping @MainActor (ImportedSource) async throws -> Void) {
        self.ytDlp = ytDlp
        self.spotify = spotify
        self.importHandler = importHandler
        inner = SourceImporter(ytDlp: ytDlp, transcoder: transcoder, http: http, spotify: spotify, workRoot: workRoot, now: now)
        inner.onStateChange = { [weak self] state in self?.innerStateChanged(state) }
    }

    // MARK: - Estado derivado

    public var totals: PlaylistTotals {
        var t = PlaylistTotals(total: items.count)
        for i in items {
            if i.status == .inLibrary { t.inLibrary += 1 }
            guard i.isSelected else { continue }
            t.selected += 1
            switch i.status {
            case .imported: t.imported += 1
            case .skipped: t.skipped += 1
            case .failed: t.failed += 1
            case .inLibrary: break
            default: t.remaining += 1
            }
        }
        return t
    }

    /// Avance total de la cola, 0...1 (temas terminados más el avance del que se descarga).
    public var queueProgress: Double {
        let selected = items.filter(\.isSelected)
        guard !selected.isEmpty else { return 0 }
        let done = selected.reduce(0.0) { acc, i in
            if i.status.isFinal { return acc + 1 }
            if case .downloading(_, let p) = i.status { return acc + (p ?? 0) }
            return acc
        }
        return done / Double(selected.count)
    }

    // MARK: - Paso 1: temas

    /// Lee la lista. Publica `.tracks` o `.failed` (y relanza el error). Nada viene marcado; los temas que ya están
    /// en la biblioteca quedan como `.inLibrary`.
    public func load(_ text: String) async throws {
        items = []
        name = ""
        mayBeTruncated = false
        link = nil
        phase = .loading
        do {
            let parsed = try PlaylistLink.parse(text)
            var loaded: [PlaylistItem] = []
            switch parsed {
            case .spotify(let id):
                let p = try await spotify.playlist(id: id)
                name = p.name
                mayBeTruncated = p.mayBeTruncated
                loaded = Self.items(from: p)
            case .spotifyAlbum(let id):
                let p = try await spotify.album(id: id)
                name = p.name
                mayBeTruncated = p.mayBeTruncated
                loaded = Self.items(from: p)
            case .youtube:
                let p = try await ytDlp.playlist(url: parsed.canonicalURL)
                name = p.title
                loaded = p.entries.map {
                    var item = PlaylistItem(track: PlaylistTrack(kind: .youtube, id: $0.id, title: $0.title,
                                                                 artist: $0.channel ?? "", durationSeconds: $0.durationSeconds))
                    item.chosen = $0
                    return item
                }
            }
            for i in loaded.indices where isInLibrary(loaded[i]) { loaded[i].status = .inLibrary }
            link = parsed
            items = loaded
            phase = .tracks
        } catch {
            throw failLoading(error)
        }
    }

    public func setSelected(_ id: String, _ selected: Bool) {
        guard let i = index(id), items[i].status != .inLibrary else { return }
        items[i].isSelected = selected
    }

    public func selectAll() {
        for i in items.indices where items[i].status != .inLibrary { items[i].isSelected = true }
    }

    public func selectNone() {
        for i in items.indices { items[i].isSelected = false }
    }

    // MARK: - Paso 2: candidatos (solo Spotify)

    /// Busca en YouTube cada tema marcado y sin buscar, uno tras otro. Propone el candidato de menor diferencia solo si
    /// es «cercano» y no «directo»; si no, el tema queda «dudoso». Un límite de YouTube o un extractor roto detienen
    /// la búsqueda (`.stopped`); cancelar deja lo ya buscado.
    public func searchCandidates() async {
        await runCancellable { await self.searchBody() }
    }

    private func searchBody() async {
        let todo = items.filter { $0.isSelected && $0.track.kind == .spotify && $0.status == .pending && $0.chosen == nil }.map(\.id)
        var done = 0
        phase = .searching(done: 0, total: todo.count)
        for id in todo {
            guard let i = index(id) else { continue }
            if Task.isCancelled { phase = .cancelled; return }
            if isInLibrary(items[i]) { items[i].status = .inLibrary; items[i].isSelected = false; continue }
            items[i].status = .searching
            let t = items[i].track
            do {
                let first = t.artist.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? t.artist
                let query = ([first].filter { !$0.isEmpty } + [t.title]).joined(separator: " ")
                let found = try await ytDlp.search(query: query)
                let ranked = CandidateRanker.rank(found, referenceDuration: t.durationSeconds ?? 0, referenceTitle: t.title)
                guard let j = index(id) else { continue }
                items[j].candidates = ranked
                // Estudio salvo que el tema de Spotify sea un directo: entonces solo se propone un directo.
                let wantsLive = CandidateRanker.isLive(title: t.title)
                if let best = ranked.first, best.isClose, best.isLive == wantsLive {
                    items[j].chosen = best.candidate
                    items[j].status = .proposed
                } else {
                    items[j].chosen = nil
                    items[j].status = .doubtful
                }
            } catch {
                guard let j = index(id) else { continue }
                let e = Self.map(error)
                items[j].status = .pending
                if e == .cancelled { phase = .cancelled; return }
                if e == .rateLimited || e.suggestsYtDlpUpdate { phase = .stopped(e); return }
                items[j].status = .failed(e)
            }
            done += 1
            phase = .searching(done: done, total: todo.count)
        }
        phase = .review
    }

    /// Cambia el candidato de un tema (uno de la lista o uno pegado a mano). Vale también para un «dudoso».
    public func choose(_ candidate: Candidate, for id: String) {
        guard let i = index(id), items[i].status != .inLibrary else { return }
        items[i].chosen = candidate
        items[i].status = .proposed
    }

    /// Quita el candidato: el tema queda omitido.
    public func clearCandidate(for id: String) {
        guard let i = index(id), items[i].status != .inLibrary else { return }
        items[i].chosen = nil
        items[i].status = .skipped
    }

    // MARK: - Paso 3: cola

    /// Ejecuta la cola tema a tema. Los marcados sin candidato (dudosos sin resolver) se omiten. Sirve también para
    /// reanudar tras `.stopped` o `.cancelled`: sigue por los que no han terminado.
    public func run() async {
        await runCancellable { await self.runBody() }
    }

    /// Alias de `run()` para el botón «Reanudar».
    public func resume() async { await run() }

    private func runBody() async {
        phase = .running
        for i in items.indices where items[i].isSelected && !items[i].status.isFinal && items[i].chosen == nil {
            items[i].status = .skipped
        }
        let todo = items.filter { $0.isSelected && !$0.status.isFinal && $0.chosen != nil && $0.status != .searching }.map(\.id)
        for id in todo {
            guard let i = index(id) else { continue }
            if Task.isCancelled { phase = .cancelled; return }
            guard let chosen = items[i].chosen else { continue }
            if isVideoIDInLibrary?(chosen.id) == true { items[i].status = .inLibrary; continue }
            let restore = items[i].status
            items[i].status = .downloading(.downloading, progress: nil)
            runningItemID = id
            do {
                try await download(index: i, id: id, chosen: chosen)
                if let j = index(id) { items[j].status = .imported }
            } catch {
                runningItemID = nil
                guard let j = index(id) else { continue }
                let e = Self.map(error)
                if e == .cancelled { items[j].status = restore; phase = .cancelled; return }
                if e == .rateLimited || e.suggestsYtDlpUpdate { items[j].status = restore; phase = .stopped(e); return }
                items[j].status = .failed(e)
            }
            runningItemID = nil
        }
        phase = .finished
    }

    private func download(index i: Int, id: String, chosen: Candidate) async throws {
        let t = items[i].track
        let source = ResolvedSource(
            link: t.kind == .spotify ? .spotify(trackID: t.id) : .youtube(videoID: t.id), pastedURL: t.url.absoluteString,
            title: t.title, artist: t.artist, album: nil, durationSeconds: t.durationSeconds, artworkURL: nil,
            candidates: [], confirmation: nil, noCloseCandidate: false)
        var imported = try await inner.download(candidate: chosen, title: t.title, artist: t.artist, resolved: source)
        imported.origin.playlistID = link.map { l in
            switch l { case .spotify(let id): id; case .spotifyAlbum(let id): id; case .youtube(let id): id }
        }
        imported.origin.playlistName = name
        defer { imported.cleanUp() }
        if let j = index(id) { items[j].status = .downloading(.converting, progress: nil) }
        try await importHandler(imported)
    }

    /// Detiene la búsqueda o la cola en curso y conserva lo hecho (lo importado queda importado).
    public func cancel() { currentTask?.cancel() }

    /// Los fallidos vuelven a estar listos: con candidato, como «propuesto»; sin él, como «pendiente» (Spotify: a
    /// buscar de nuevo con `searchCandidates()`). Después hay que llamar a `run()`. Devuelve cuántos se reactivaron.
    @discardableResult
    public func retryFailed() -> Int {
        var n = 0
        for i in items.indices where items[i].status.isFailed {
            items[i].status = items[i].chosen == nil ? .pending : .proposed
            n += 1
        }
        return n
    }

    // MARK: -

    private func runCancellable(_ body: @escaping @MainActor () async -> Void) async {
        let task = Task { await body() }
        currentTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        currentTask = nil
    }

    private func innerStateChanged(_ state: ImportState) {
        guard let id = runningItemID, let i = index(id) else { return }
        if case .downloading(let stage, let p) = state { items[i].status = .downloading(stage, progress: p) }
    }

    private func isInLibrary(_ item: PlaylistItem) -> Bool {
        switch item.track.kind {
        case .spotify: isSpotifyIDInLibrary?(item.track.id) == true
        case .youtube: isVideoIDInLibrary?(item.track.id) == true
        }
    }

    private func index(_ id: String) -> Int? { items.firstIndex { $0.id == id } }

    private static func items(from p: SpotifyPlaylist) -> [PlaylistItem] {
        p.tracks.map {
            PlaylistItem(track: PlaylistTrack(kind: .spotify, id: $0.id, title: $0.title, artist: $0.artists.joined(separator: ", "),
                                              durationSeconds: $0.durationSeconds))
        }
    }

    private static func map(_ error: Error) -> SourceError {
        if error is CancellationError { return .cancelled }
        return (error as? SourceError) ?? .launchFailed(error.localizedDescription)
    }

    private func failLoading(_ error: Error) -> Error {
        let e = Self.map(error)
        phase = e == .cancelled ? .idle : .failed(e)
        return e
    }
}

private extension PlaylistTrackStatus {
    var isFailed: Bool { if case .failed = self { true } else { false } }
}
