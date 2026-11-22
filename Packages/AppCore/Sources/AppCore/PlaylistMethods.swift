import Foundation
import SourceKit
import Store

// W2-J: importación de listas y álbumes (campos exactos en `Temp/win/step8-contract.md`, «W2-J playlist.*»).
// `link.resolve` desvía a lista como la hoja del Mac (`continueTapped`); el resto va por `playlist.*` y el evento
// `playlist.changed` (instantánea completa). La cola es la de `PlaylistImporter` (un tema a la vez, como el Mac); cada tema
// en descarga se refleja además en `jobs.progress` como `playlist-<id>`, y su separación entra en la cola de `Library`.

struct PlaylistErrorInfo: Codable, Sendable, Equatable {
    var code: String
    var title: String
    var detail: String
    /// `extractorBroken`: la página ofrece «Actualizar y reintentar».
    var suggestsUpdate: Bool
    init(_ e: SourceError) {
        let m = SourceMessages.text(for: e)
        code = SourceMessages.code(for: e)
        title = m.title
        detail = m.detail
        suggestsUpdate = e.suggestsYtDlpUpdate
    }
}

struct PlaylistItemInfo: Codable, Sendable {
    var id: String
    var title: String
    var artist: String
    var duration: Double?
    /// `spotify` o `youtube`.
    var kind: String
    var selected: Bool
    /// `pending`, `searching`, `proposed`, `doubtful`, `downloading`, `imported`, `skipped`, `inLibrary`, `failed`.
    var status: String
    /// Solo `downloading`: `download` o `convert`.
    var stage: String?
    /// Solo `downloading` en `download`: 0...1 (nil = indeterminado).
    var progress: Double?
    var error: PlaylistErrorInfo?
    /// El propio tema ya está en la biblioteca («En la biblioteca»).
    var inLibrary: LinkTrackInfo?
    /// «Puede que ya lo tengas» (mismo título y artista, otro identificador).
    var possible: LinkTrackInfo?
    var candidates: [LinkCandidateInfo]
    var chosen: LinkCandidateInfo?
}

struct PlaylistTotalsInfo: Codable, Sendable, Equatable {
    var total: Int
    var selected: Int
    var imported: Int
    var skipped: Int
    var failed: Int
    var inLibrary: Int
    var remaining: Int
    /// Marcados con candidato y sin terminar: lo que cuenta el botón «Descargar y procesar (n)».
    var queued: Int
    /// De `imported`, los que la biblioteca ya tenía (duplicado detectado al importar).
    var duplicates: Int
}

/// Las cuatro cifras del paso 4, ya con los duplicados repartidos como en el Mac.
struct PlaylistSummaryInfo: Codable, Sendable, Equatable {
    var imported: Int
    var skipped: Int
    var inLibrary: Int
    var failed: Int
    var remaining: Int
    var cancelled: Bool
}

struct PlaylistUpdateInfo: Codable, Sendable, Equatable {
    var updating: Bool
    var alreadyLatest: Bool
    var error: String?
}

struct PlaylistSnapshot: Codable, Sendable {
    /// `loading`, `tracks`, `searching`, `review`, `running`, `stopped`, `summary`, `error`.
    var step: String
    var searchDone: Int?
    var searchTotal: Int?
    /// Solo `stopped` y `error`.
    var error: PlaylistErrorInfo?
    var name: String
    /// `spotify` o `youtube`.
    var source: String
    /// `playlist` o `album`.
    var kind: String
    var mayBeTruncated: Bool
    /// Hay trabajo en marcha o parado: la lista se conserva al cerrar la hoja.
    var isLive: Bool
    /// Texto del indicador de la Biblioteca.
    var indicator: String?
    var totals: PlaylistTotalsInfo
    var summary: PlaylistSummaryInfo
    var progress: Double
    var update: PlaylistUpdateInfo
    /// Avisos que no son fallos (p. ej. «No se pudo separar …»).
    var warnings: [String]
    var items: [PlaylistItemInfo]
}

struct PlaylistItemParams: Codable, Sendable { var id: String }
struct PlaylistSelectParams: Codable, Sendable { var id: String; var selected: Bool }
struct PlaylistChooseParams: Codable, Sendable { var id: String; var candidateId: String }
struct PlaylistCloseParams: Codable, Sendable { var force: Bool? }
struct PlaylistCloseResult: Codable, Sendable { var closed: Bool; var live: Bool }

@MainActor
final class PlaylistEngine {
    /// Cada cuánto mira la instantánea para emitir `playlist.changed` y reflejar los trabajos.
    static let pollInterval: Duration = .milliseconds(250)
    static let jobPrefix = "playlist-"

    private let jobs: JobEngine
    private let sources: ExternalSources
    private let root: ProjectsRoot
    private var session: PlaylistImportSession?
    private var duplicates: Set<String> = []
    private var warnings: [String] = []
    private var poll: Task<Void, Never>?
    private var lastSent: Data?
    private var activeJob: (key: String, title: String)?
    private nonisolated let sink = SinkBox()

    private final class SinkBox: @unchecked Sendable {
        private let lock = NSLock()
        private var f: @Sendable (PlaylistSnapshot) -> Void = { _ in }
        func set(_ g: @escaping @Sendable (PlaylistSnapshot) -> Void) { lock.withLock { f = g } }
        func send(_ s: PlaylistSnapshot) { lock.withLock { f }(s) }
    }

    nonisolated init(jobs: JobEngine, sources: ExternalSources, root: ProjectsRoot) {
        self.jobs = jobs
        self.sources = sources
        self.root = root
    }

    nonisolated func setSink(_ f: @escaping @Sendable (PlaylistSnapshot) -> Void) { sink.set(f) }

    // MARK: Abrir

    /// Desvío de `link.resolve`: lee la lista (cancelable con `link.cancel`) y devuelve la instantánea del paso 1.
    func open(_ text: String) async throws -> LinkResolveResult {
        _ = try Bridge.service(root)
        if let old = session { old.importer.cancel(); old.cancelLoading() }
        duplicates = []
        warnings = []
        lastSent = nil
        let s: PlaylistImportSession
        do {
            let importer = try await sources.makePlaylistImporter { [weak self] source in
                try await self?.store(source)
            }
            s = PlaylistImportSession(importer: importer, hooks: hooks())
        } catch { throw SourceMessages.rpc(error) }
        session = s
        kick()
        do { try await s.load(text) } catch {
            if session === s { session = nil }
            throw SourceMessages.rpc(error)
        }
        let snap = snapshot(s)
        remember(snap)
        return LinkResolveResult(link: "playlist", pastedURL: text, title: snap.name, noCloseCandidate: false,
                                 candidates: [], playlist: snap)
    }

    /// `link.cancel` sin `jobId`: corta la lectura de la lista. `true` si había una leyéndose.
    func cancelLoading() -> Bool {
        guard let s = session, s.step == .loading else { return false }
        s.cancelLoading()
        return true
    }

    private func hooks() -> PlaylistImportSession.Hooks {
        let sources = self.sources, root = self.root
        return .init(updateYtDlp: { try await sources.updateYtDlp() },
                     lookup: { await Task.detached { LibraryLookup.scan(root: root.url) }.value },
                     duplicateVideoIDs: { [weak self] in self?.duplicates ?? [] })
    }

    /// Un tema de la lista: importa y encola su separación, como al separar a mano. Un duplicado no es un fallo.
    private func store(_ source: ImportedSource) async throws {
        let lib = try await jobs.library()
        var cover: URL?
        if let art = source.artworkURL { cover = await sources.preparedCover(art, in: source.workDirectory) }
        let meta = ImportMetadata(title: source.title, artist: source.artist.isEmpty ? nil : source.artist,
                                  origin: SongOrigin(source.origin), artworkFile: cover)
        do {
            let id = try await lib.importSong(from: source.wavURL, metadata: meta) { _ in }
            do { try await lib.separate(id: id) } catch {
                warnings.append("No se pudo separar \(source.title): \(JobEngine.describe(error))")
            }
        } catch LibraryError.duplicate {
            duplicates.insert(source.origin.videoID)
        }
    }

    // MARK: Acciones

    func current() throws -> PlaylistImportSession {
        guard let s = session else { throw RPCError(code: "no-playlist", message: "No hay ninguna lista abierta.") }
        return s
    }

    func state() throws -> PlaylistSnapshot { snapshot(try current()) }

    /// Para `app.info`: la lista que se conserva al cerrar la hoja (cola en marcha o parada), o nil.
    func liveSnapshot() -> PlaylistSnapshot? {
        guard let s = session else { return nil }
        let snap = snapshot(s)
        return snap.isLive ? snap : nil
    }

    /// Responde con la instantánea posterior a la acción y la emite también como evento.
    func act(_ body: @MainActor (PlaylistImportSession) throws -> Void) async throws -> PlaylistSnapshot {
        let s = try current()
        try body(s)
        kick()
        // La acción arranca tareas (búsqueda, cola): se cede un turno para que el paso ya refleje el cambio.
        await Task.yield()
        let snap = snapshot(s)
        remember(snap)
        return snap
    }

    func close(force: Bool) -> PlaylistCloseResult {
        guard let s = session else { return PlaylistCloseResult(closed: false, live: false) }
        let live = s.isLive
        if live && !force { return PlaylistCloseResult(closed: false, live: true) }
        if live { s.importer.cancel() }
        session = nil
        lastSent = nil
        return PlaylistCloseResult(closed: true, live: live)
    }

    // MARK: Instantánea

    private func trackInfo(_ t: ExistingTrack?) -> LinkTrackInfo? { t.map(LinkTrackInfo.init) }

    private func candidateInfo(_ c: Candidate, _ s: PlaylistImportSession, ranked: RankedCandidate?) -> LinkCandidateInfo {
        LinkCandidateInfo(id: c.id, title: c.title, artist: c.channel, duration: c.durationSeconds,
                          thumbnail: LinkEngine.thumbnailURL(videoID: c.id), source: "youtube", url: c.url.absoluteString,
                          isClose: ranked?.isClose ?? false, isLive: ranked?.isLive ?? CandidateRanker.isLive(title: c.title),
                          difference: ranked?.difference, inLibrary: trackInfo(s.library.video[c.id]))
    }

    func snapshot(_ s: PlaylistImportSession) -> PlaylistSnapshot {
        let imp = s.importer
        let step: String
        var done: Int?, total: Int?
        var err: SourceError?
        switch s.step {
        case .loading: step = "loading"
        case .tracks: step = "tracks"
        case .searching(let d, let t): step = "searching"; done = d; total = t
        case .review: step = "review"
        case .running: step = "running"
        case .stopped(let e): step = "stopped"; err = e
        case .summary: step = "summary"
        case .error(let e): step = "error"; err = e
        }
        let t = imp.totals
        let dups = s.duplicateCount
        let items = imp.items.map { item -> PlaylistItemInfo in
            var status = "pending", stage: String?, progress: Double?, error: PlaylistErrorInfo?
            switch item.status {
            case .pending: status = "pending"
            case .searching: status = "searching"
            case .proposed: status = "proposed"
            case .doubtful: status = "doubtful"
            case .downloading(let st, let p):
                status = "downloading"
                stage = st == .downloading ? "download" : "convert"
                progress = st == .downloading ? p : nil
            case .imported: status = "imported"
            case .skipped: status = "skipped"
            case .inLibrary: status = "inLibrary"
            case .failed(let e): status = "failed"; error = PlaylistErrorInfo(e)
            }
            let own: ExistingTrack? = item.track.kind == .spotify ? s.library.spotify[item.track.id] : s.library.video[item.track.id]
            let chosen = item.chosen.map { c in
                candidateInfo(c, s, ranked: item.candidates.first { $0.id == c.id })
            }
            return PlaylistItemInfo(
                id: item.id, title: item.track.title, artist: item.track.artist, duration: item.track.durationSeconds,
                kind: item.track.kind == .spotify ? "spotify" : "youtube", selected: item.isSelected, status: status,
                stage: stage, progress: progress, error: error, inLibrary: trackInfo(own),
                possible: trackInfo(s.possible[item.id]),
                candidates: item.candidates.map { candidateInfo($0.candidate, s, ranked: $0) }, chosen: chosen)
        }
        return PlaylistSnapshot(
            step: step, searchDone: done, searchTotal: total, error: err.map(PlaylistErrorInfo.init), name: imp.name,
            source: s.isYouTube ? "youtube" : "spotify", kind: s.isAlbum ? "album" : "playlist",
            mayBeTruncated: imp.mayBeTruncated, isLive: s.isLive, indicator: s.indicator,
            totals: PlaylistTotalsInfo(total: t.total, selected: t.selected, imported: t.imported, skipped: t.skipped,
                                       failed: t.failed, inLibrary: t.inLibrary, remaining: t.remaining,
                                       queued: s.queuedCount, duplicates: dups),
            summary: PlaylistSummaryInfo(imported: t.imported - dups, skipped: t.skipped, inLibrary: t.inLibrary + dups,
                                         failed: t.failed, remaining: t.remaining, cancelled: imp.phase == .cancelled),
            progress: imp.queueProgress,
            update: PlaylistUpdateInfo(updating: s.updating, alreadyLatest: s.alreadyLatest, error: s.updateError),
            warnings: warnings, items: items)
    }

    private static func encode(_ s: PlaylistSnapshot) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return (try? e.encode(s)) ?? Data()
    }

    private func remember(_ s: PlaylistSnapshot) { lastSent = Self.encode(s) }

    // MARK: Evento y trabajos

    /// Arranca el sondeo si no corre: emite `playlist.changed` cuando la instantánea cambia, refleja el tema en descarga en
    /// `jobs.progress` y se para cuando la lista ya no está viva y no hay cambios.
    func kick() {
        guard poll == nil else { return }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard let self else { return }
                if !self.tick() { self.poll = nil; return }
            }
        }
    }

    /// `false` = parar el sondeo.
    private func tick() -> Bool {
        guard let s = session else { mirrorJob(nil); return false }
        let snap = snapshot(s)
        mirrorJob(snap)
        let data = Self.encode(snap)
        if data != lastSent {
            lastSent = data
            sink.send(snap)
            return true
        }
        return s.isLive || s.updating
    }

    /// Un tema a la vez: el que está descargándose es el trabajo `playlist-<id>`; al dejar de estarlo se cierra según su estado.
    private func mirrorJob(_ snap: PlaylistSnapshot?) {
        let running = snap?.items.first { $0.status == "downloading" }
        if let r = running {
            let title = [r.artist, r.title].filter { !$0.isEmpty }.joined(separator: " - ")
            let key = Self.jobPrefix + r.id
            if let a = activeJob, a.key != key { closeJob(a, snap) }
            activeJob = (key, title)
            if r.stage == "convert" {
                jobs.update(key, title: title, stage: "import", state: "running", fraction: nil, text: "Convirtiendo a WAV…")
            } else {
                let text = r.progress.map { "Descargando audio… \(Int(($0 * 100).rounded())) %" } ?? "Descargando audio…"
                jobs.update(key, title: title, stage: "download", state: "running", fraction: r.progress, text: text)
            }
        } else if let a = activeJob {
            closeJob(a, snap)
            activeJob = nil
        }
    }

    private func closeJob(_ a: (key: String, title: String), _ snap: PlaylistSnapshot?) {
        let id = String(a.key.dropFirst(Self.jobPrefix.count))
        let item = snap?.items.first { $0.id == id }
        switch item?.status {
        case "imported": jobs.update(a.key, title: a.title, stage: "import", state: "done", fraction: 1)
        case "failed":
            jobs.update(a.key, title: a.title, stage: "download", state: "failed", error: item?.error?.title)
        default: jobs.update(a.key, title: a.title, stage: "download", state: "cancelled")
        }
    }

    /// Solo tests: deja que termine la tarea de búsqueda o de cola en marcha y fuerza una pasada del sondeo.
    func settle() async {
        await session?.waitIdle()
        if let s = session { mirrorJob(snapshot(s)) }
    }
}

extension Bridge {
    /// Se llama desde `registerLinkMethods` (el desvío de `link.resolve` necesita el `LinkEngine`).
    func registerPlaylistMethods(link: LinkEngine, sources: ExternalSources, root: ProjectsRoot) {
        let engine = PlaylistEngine(jobs: jobs, sources: sources, root: root)
        engine.setSink { [weak self] in self?.emit("playlist.changed", $0) }
        liveList = { await engine.liveSnapshot() }
        link.setPlaylistHooks(
            open: { text in try await engine.open(text) },
            cancelLoading: { await engine.cancelLoading() })

        router.register("playlist.state") { (_: Empty) in try await engine.state() }
        router.register("playlist.select") { (p: PlaylistSelectParams) in
            try await engine.act { s in
                guard s.importer.items.contains(where: { $0.id == p.id }) else { throw Self.noTrack(p.id) }
                s.importer.setSelected(p.id, p.selected)
            }
        }
        router.register("playlist.selectAll") { (_: Empty) in try await engine.act { $0.selectAll() } }
        router.register("playlist.selectNone") { (_: Empty) in try await engine.act { $0.importer.selectNone() } }
        router.register("playlist.choose") { (p: PlaylistChooseParams) in
            try await engine.act { s in
                guard let item = s.importer.items.first(where: { $0.id == p.id }) else { throw Self.noTrack(p.id) }
                guard let rc = item.candidates.first(where: { $0.id == p.candidateId }) else {
                    throw RPCError(code: "not-found", message: "Ese candidato no es de este tema.")
                }
                if s.library.video[rc.id] != nil {
                    throw RPCError(code: "in-library", message: "Ese vídeo ya está en la biblioteca.")
                }
                s.importer.choose(rc.candidate, for: p.id)
            }
        }
        router.register("playlist.skip") { (p: PlaylistItemParams) in
            try await engine.act { s in
                guard s.importer.items.contains(where: { $0.id == p.id }) else { throw Self.noTrack(p.id) }
                s.importer.clearCandidate(for: p.id)
            }
        }
        router.register("playlist.continue") { (_: Empty) in try await engine.act { $0.continueFromTracks() } }
        router.register("playlist.search") { (_: Empty) in try await engine.act { $0.search() } }
        router.register("playlist.start") { (_: Empty) in try await engine.act { $0.startQueue() } }
        router.register("playlist.cancel") { (_: Empty) in try await engine.act { $0.cancel() } }
        router.register("playlist.resume") { (_: Empty) in try await engine.act { $0.resume() } }
        router.register("playlist.updateAndRetry") { (_: Empty) in try await engine.act { $0.updateAndRetry() } }
        router.register("playlist.retryFailed") { (_: Empty) in try await engine.act { $0.retryFailed() } }
        router.register("playlist.close") { (p: PlaylistCloseParams) in await engine.close(force: p.force ?? false) }
    }

    static func noTrack(_ id: String) -> RPCError {
        RPCError(code: "not-found", message: "Ese tema no está en la lista (\(id)).")
    }
}
