import Foundation
import SourceKit

// W2-J: parte sin interfaz de `App/Sources/PlaylistImport.swift` (Mac). Mismos pasos, misma comprobación de repetidos y
// mismos literales de indicador. Envuelve a `PlaylistImporter` (que lleva la cola de un tema a la vez); la página recibe su
// estado como instantánea (`PlaylistMethods.swift`). Spec, «Fuentes externas» > «Listas».

@MainActor
final class PlaylistImportSession {
    struct Hooks {
        var updateYtDlp: () async throws -> YtDlpInstallInfo
        /// Identificadores que ya tiene la biblioteca (se pide antes de leer, buscar y descargar).
        var lookup: () async -> LibraryLookup
        /// `videoID` que el cierre de importación encontró ya importados (duplicados: no son fallos).
        var duplicateVideoIDs: () -> Set<String>
    }

    enum Step: Equatable {
        case loading
        /// Paso 1.
        case tracks
        /// Paso 2: buscando.
        case searching(done: Int, total: Int)
        /// Paso 2: revisión.
        case review
        /// Paso 3.
        case running
        case stopped(SourceError)
        /// Paso 4.
        case summary
        case error(SourceError)
    }

    let importer: PlaylistImporter
    private(set) var didRun = false
    private(set) var updating = false
    private(set) var alreadyLatest = false
    private(set) var updateError: String?

    private let hooks: Hooks
    /// Lo que ya tiene la biblioteca; sirve a los cierres de SourceKit (síncronos) y a las filas «En la biblioteca».
    private(set) var library = LibraryLookup()
    /// Temas sin coincidencia por identificador pero con el mismo título y artista que uno de la biblioteca.
    private(set) var possible: [String: ExistingTrack] = [:]
    private var task: Task<Void, Never>?
    private var loadTask: Task<Void, Error>?

    init(importer: PlaylistImporter, hooks: Hooks) {
        self.importer = importer
        self.hooks = hooks
        importer.isSpotifyIDInLibrary = { [weak self] in self?.library.spotify[$0] != nil }
        importer.isVideoIDInLibrary = { [weak self] in self?.library.video[$0] != nil }
    }

    // MARK: Lo que se ve

    var isYouTube: Bool { if case .youtube? = importer.link { true } else { false } }
    var isAlbum: Bool { if case .spotifyAlbum? = importer.link { true } else { false } }

    var step: Step {
        switch importer.phase {
        case .idle, .loading: return .loading
        case .tracks: return .tracks
        case .searching(let d, let t): return .searching(done: d, total: t)
        case .review: return .review
        case .running: return .running
        case .stopped(let e): return .stopped(e)
        case .cancelled:
            if didRun { return .summary }
            return importer.items.contains { $0.chosen != nil || $0.status == .doubtful } ? .review : .tracks
        case .finished: return .summary
        case .failed(let e): return .error(e)
        }
    }

    /// Hay trabajo en marcha o parado a medias: la lista se conserva al cerrar la hoja.
    var isLive: Bool {
        switch importer.phase {
        case .loading, .searching, .running, .stopped: true
        default: false
        }
    }

    /// Texto del indicador de la Biblioteca (nil = nada que mostrar).
    var indicator: String? {
        switch importer.phase {
        case .loading: return "Leyendo la lista…"
        case .searching(let d, let t): return "Buscando \(min(d + 1, max(t, 1))) de \(t)"
        case .running:
            let t = importer.totals
            return "Importando \(min(t.selected - t.remaining + 1, max(t.selected, 1))) de \(t.selected)"
        case .stopped: return "Importación detenida"
        case .finished: return "Importación terminada"
        case .cancelled: return didRun ? "Importación cancelada" : nil
        default: return nil
        }
    }

    var selectedCount: Int { importer.items.filter(\.isSelected).count }

    /// Temas que irán a la cola: marcados, con candidato y sin terminar.
    var queuedCount: Int { importer.items.filter { $0.isSelected && $0.chosen != nil && !$0.status.isFinal }.count }

    var duplicateCount: Int {
        let dups = hooks.duplicateVideoIDs()
        return importer.items.filter { $0.status == .imported && $0.chosen.map { dups.contains($0.id) } == true }.count
    }

    // MARK: Acciones

    /// Lee la lista y vuelve cuando termina (o falla: relanza el error de SourceKit). Cancelable con `cancelLoading()`.
    func load(_ text: String) async throws {
        task?.cancel()
        let t = Task { @MainActor in
            library = await hooks.lookup()
            try await importer.load(text)
            var found: [String: ExistingTrack] = [:]
            for i in importer.items where i.status != .inLibrary {
                if let p = library.possible(title: i.track.title, artist: i.track.artist) { found[i.id] = p }
            }
            possible = found
        }
        loadTask = t
        try await withTaskCancellationHandler { try await t.value } onCancel: { t.cancel() }
    }

    /// «Marcar todos»: no marca los «posible repetido» (se marcan a mano).
    func selectAll() {
        importer.selectAll()
        for id in possible.keys { importer.setSelected(id, false) }
    }

    func cancelLoading() { loadTask?.cancel() }

    /// Paso 1 a 2 (Spotify) o 1 a 3 (YouTube, sin candidatos).
    func continueFromTracks() {
        guard selectedCount > 0 else { return }
        if isYouTube { startQueue() } else { search() }
    }

    func search() {
        task = Task {
            library = await hooks.lookup()
            await importer.searchCandidates()
        }
    }

    func startQueue() {
        didRun = true
        task = Task {
            library = await hooks.lookup()
            await importer.run()
        }
    }

    func cancel() { importer.cancel() }

    /// «Reanudar» tras un límite de YouTube: sigue por donde iba (búsqueda o cola).
    func resume() {
        alreadyLatest = false
        if didRun { startQueue() } else { search() }
    }

    /// «Actualizar y reintentar» tras un yt-dlp roto: baja el nuevo y, si trae una versión más nueva, reanuda.
    func updateAndRetry() {
        guard case .stopped(let e) = step, !updating else { return }
        updating = true
        updateError = nil
        alreadyLatest = false
        task = Task {
            defer { updating = false }
            do {
                let info = try await hooks.updateYtDlp()
                if case .extractorBroken(let v?, _) = e, SourceKit.HelperLocator.compare(info.version, v) <= 0 {
                    alreadyLatest = true
                    return
                }
                resume()
            } catch {
                updateError = (error as? SourceError).map { SourceMessages.text(for: $0).detail } ?? error.localizedDescription
            }
        }
    }

    /// Los fallidos vuelven a la cola; los que fallaron buscando, a la búsqueda (y a la revisión).
    func retryFailed() {
        guard importer.retryFailed() > 0 else { return }
        let needsSearch = importer.items.contains { $0.isSelected && $0.status == .pending && $0.chosen == nil && $0.track.kind == .spotify }
        if needsSearch { search() } else { startQueue() }
    }

    /// Espera a que termine la tarea en marcha (búsqueda o cola). Solo tests.
    func waitIdle() async { await task?.value }
}
