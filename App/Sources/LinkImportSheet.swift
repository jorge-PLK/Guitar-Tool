import AppKit
import SourceKit
import Store
import SwiftUI

/// Estado de la hoja «Importar desde enlace» (spec, «Fuentes externas» > Interfaz). Envuelve a `SourceImporter`,
/// que publica el recorrido; aquí viven los campos editables, los errores que se ven y los reintentos.
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
    /// Todos los temas de la biblioteca (índice), para el aviso «posible repetido».
    var tracks: [ExistingTrack] = []

    func withTracks(_ t: [ExistingTrack]) -> LibraryLookup { var c = self; c.tracks = t; return c }

    func possible(title: String, artist: String?) -> ExistingTrack? {
        tracks.first { PossibleDuplicate.matches(title: title, artist: artist, otherTitle: $0.title, otherArtist: $0.artist) }
    }
}

@MainActor @Observable
final class LinkImportSession {
    struct Hooks {
        var makeImporter: () async throws -> SourceImporter
        /// Proyecto que ya tiene ese `videoID` (se comprueba antes de descargar).
        var existingProject: (String) async -> UUID?
        /// Importa el WAV descargado en la biblioteca (no borra la carpeta temporal).
        var store: (ImportedSource, @escaping @Sendable (Double) -> Void) async throws -> Void
        var updateYtDlp: () async throws -> YtDlpInstallInfo
        /// Identificadores que ya tiene la biblioteca (`Library.project(withSpotifyID:)` / `project(withVideoID:)`).
        var lookup: () async -> LibraryLookup
        /// Cierra la hoja y abre ese proyecto en la Biblioteca.
        var open: (UUID) -> Void
        /// Prepara la cola de listas (vive en `AppModel`, no en la hoja).
        var makePlaylist: () async throws -> PlaylistImportSession
        /// Tira la lista abierta (volver al campo vacío).
        var discardPlaylist: () -> Void
        /// Cierra la hoja; con id, avisa de duplicado.
        var close: (UUID?) -> Void
    }

    enum Screen: Equatable {
        case empty
        case resolving(ResolvingStage)
        /// Pasada recién lanzada: aún sin recorrido del importador («Preparando…»).
        case preparing
        case candidates
        case working(String, Double?)
        case error
        case done
        /// Recorrido de listas y álbumes (spec, «Listas»).
        case playlist
        /// El tema del enlace ya está en la biblioteca.
        case repeated
    }

    private enum Op { case resolve, download }

    var text = ""
    var title = ""
    var artist = ""
    var manualText = ""
    var selectedID: String?
    var failure: SourceError?
    var otherError: String?
    var manualError: String?
    /// Tras «Actualizar y reintentar»: ya era la última versión de yt-dlp.
    var alreadyLatest = false
    var updating = false
    var importProgress: Double?
    var isImporting = false
    var finishedNotices: [ImportNotice]?
    private(set) var importer: SourceImporter?
    /// La lista o álbum en curso; la guarda `AppModel`, así que sobrevive al cierre de la hoja.
    var playlist: PlaylistImportSession?
    /// El enlace pegado ya está en la biblioteca: no se busca ni se descarga.
    var existing: ExistingTrack?
    /// `videoID` ya importados: sus candidatos salen «En la biblioteca» y no se pueden elegir.
    var libraryVideos: [String: ExistingTrack] = [:]
    /// Mismo título y artista que un tema de la biblioteca, sin coincidir por identificador: aviso, no bloquea.
    var possibleDuplicate: ExistingTrack?
    #if DEBUG
    /// Capturas: fuerza lo que se ve sin pasar por el recorrido real.
    var forced: Screen?
    #endif

    // MARK: Búsqueda en Spotify (Fase 7b, punto 4)

    enum SearchState: Equatable {
        case idle
        case searching
        case results(query: String, [SpotifyTrackResult])
        case failed(String)
    }
    var searchState = SearchState.idle
    /// Buscador de Spotify; nil = sin búsqueda (el campo solo acepta enlaces).
    var searcher: (any SpotifySearching)?
    /// «Importar fichero…» del popup: cierra la hoja y abre el selector.
    var pickFile: () -> Void = {}
    private var searchTask: Task<Void, Never>?

    private let hooks: Hooks
    private var lastOp: Op = .resolve
    private var manualLinks: [String] = []
    /// Una sola pasada viva (resolver, descargar, lista, actualizar): una cancelada no escribe estado.
    private let gate = PassGate()
    /// `lookup()` de la última URL resuelta: un reintento de la misma URL no vuelve a escanear la carpeta.
    private var lookupCache: (text: String, value: LibraryLookup)?

    init(hooks: Hooks) { self.hooks = hooks }

    /// Hay una búsqueda o una pasada en curso: «Importar», «Elegir» e «Importar fichero» quedan desactivados.
    var isBusy: Bool { gate.isRunning || searchState == .searching }

    // MARK: Lo que se ve

    var screen: Screen {
        if finishedNotices != nil { return .done }
        #if DEBUG
        if let forced { return forced }
        #endif
        if playlist != nil { return .playlist }
        if existing != nil { return .repeated }
        if updating { return .working("Actualizando yt-dlp…", nil) }
        if isImporting { return .working("Importando en la biblioteca…", importProgress) }
        if otherError != nil { return .error }
        if let f = failure, !(f.returnsToCandidates && importer?.resolved != nil) { return .error }
        guard let importer else { return gate.isRunning ? .preparing : .empty }
        switch importer.state {
        case .resolving(let s): return .resolving(s)
        case .downloading(let s, let p): return .working(s == .downloading ? "Descargando audio…" : "Convirtiendo a WAV…", p)
        case .candidates, .idle, .failed, .finished:
            if importer.resolved != nil { return .candidates }
            return gate.isRunning ? .preparing : .empty
        }
    }

    var resolved: ResolvedSource? { importer?.resolved }
    var notices: [ImportNotice] { importer?.notices ?? [] }
    var canCancel: Bool { !isImporting && !updating }
    var selectedCandidate: Candidate? {
        guard let r = resolved else { return nil }
        if let c = r.confirmation { return c }
        return r.candidates.first { $0.id == selectedID }?.candidate
    }

    // MARK: Acciones

    /// «Importar» del popup: un enlace sigue el recorrido de siempre; lo demás se busca en Spotify.
    func importTapped() {
        guard !isBusy else { return }
        switch ImportQuery.classify(text) {
        case .empty: return
        case .link(let link):
            searchTask?.cancel()
            searchState = .idle
            text = link
            continueTapped()
        case .search(let q): search(q)
        }
    }

    func search(_ query: String) {
        guard let searcher else { searchState = .failed(SpotifySearchError.missingCredentials.localizedDescription); return }
        searchTask?.cancel()
        searchState = .searching
        searchTask = Task {
            do {
                let r = try await searcher.search(query)
                if Task.isCancelled { return }
                searchState = .results(query: query, r)
            } catch {
                if Task.isCancelled || error is CancellationError { return }
                searchState = .failed((error as? SpotifySearchError)?.localizedDescription ?? "Sin conexión con Spotify")
            }
        }
    }

    /// «Elegir»: lanza el flujo de enlace con la pista.
    func choose(_ track: SpotifyTrackResult) {
        guard !isBusy else { return }
        text = track.trackURL.absoluteString
        continueTapped()
    }

    /// ▶ «Oír en Spotify»: la app de Spotify y, si ninguna abre `spotify:`, el navegador.
    func listen(_ track: SpotifyTrackResult) {
        if !NSWorkspace.shared.open(track.appURL) { NSWorkspace.shared.open(track.trackURL) }
    }

    func continueTapped() {
        guard !isBusy, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if case .playlist? = try? SourceInput.parse(text) { startPlaylist(); return }
        lastOp = .resolve
        manualLinks = []
        run { isCurrent in try await self.resolveOp(isCurrent) }
    }

    func importSelected() {
        guard selectedCandidate != nil, !isBusy else { return }
        lastOp = .download
        run { _ in try await self.downloadOp() }
    }

    func addManual() {
        let t = manualText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let importer, !isBusy else { return }
        manualError = nil
        gate.start { [self] isCurrent in
            do {
                let c = try await importer.addManualCandidate(t)
                guard isCurrent() else { return }
                let video = await hooks.lookup().video
                guard isCurrent() else { return }
                manualLinks.append(t)
                libraryVideos = video
                selectedID = libraryVideos[c.id] == nil ? c.id : nil
                manualText = ""
                failure = nil
            } catch {
                if error is CancellationError || (error as? SourceError) == .cancelled { return }
                manualError = (error as? SourceError).map { SourceMessages.text(for: $0).detail }
                    ?? error.localizedDescription
            }
        }
    }

    func retry() {
        switch lastOp {
        case .resolve: run { isCurrent in try await self.resolveOp(isCurrent) }
        case .download: run { _ in try await self.downloadOp() }
        }
    }

    func updateAndRetry() {
        guard !gate.isRunning else { return }
        let broken = failure
        failure = nil
        otherError = nil
        alreadyLatest = false
        updating = true
        gate.start { [self] isCurrent in
            defer { updating = false }
            do {
                let info = try await hooks.updateYtDlp()
                guard isCurrent() else { return }
                if case .extractorBroken(let v?, _)? = broken, HelperLocator.compare(info.version, v) <= 0 {
                    alreadyLatest = true
                    failure = broken
                    return
                }
                let (savedTitle, savedArtist, savedSel) = (title, artist, selectedID)
                let fresh = try await hooks.makeImporter()
                guard isCurrent() else { return }
                importer = fresh
                try await resolveOp(isCurrent)
                for link in manualLinks { _ = try? await importer?.addManualCandidate(link) }
                guard isCurrent() else { return }
                (title, artist, selectedID) = (savedTitle, savedArtist, savedSel)
                if case .download = lastOp { try await downloadOp() }
            } catch { if isCurrent() { handle(error) } }
        }
    }

    /// Cancela lo que esté en curso: vuelve a los candidatos si ya había, o al campo vacío.
    func cancel() {
        gate.cancel()
        failure = nil
        otherError = nil
        if importer?.resolved == nil { importer?.reset() }
    }

    private func startPlaylist() {
        failure = nil
        otherError = nil
        gate.start { [self] isCurrent in
            do {
                let p = try await hooks.makePlaylist()
                guard isCurrent() else { return }
                playlist = p
                p.start(text)
            } catch { if isCurrent() { handle(error) } }
        }
    }

    func close() {
        searchTask?.cancel()
        // La cola de una lista sigue aunque se cierre la hoja.
        if playlist != nil { hooks.close(nil); return }
        cancel()
        importer?.reset()
        hooks.close(nil)
    }

    func openProject(_ id: UUID) { hooks.open(id) }

    func openExisting() {
        guard let e = existing else { return }
        hooks.open(e.id)
    }

    func backToEmpty() {
        existing = nil
        if playlist != nil { playlist = nil; hooks.discardPlaylist() }
        cancel()
        importer?.reset()
        lookupCache = nil
        failure = nil
        otherError = nil
        alreadyLatest = false
    }

    func backToCandidates() {
        failure = nil
        otherError = nil
    }

    // MARK: Operaciones

    /// Lanza una pasada si no hay otra viva; el estado «Preparando…» se ve en el mismo clic (`gate.isRunning`).
    private func run(_ op: @escaping @MainActor (@MainActor () -> Bool) async throws -> Void) {
        guard !gate.isRunning else { return }
        failure = nil
        otherError = nil
        manualError = nil
        alreadyLatest = false
        gate.start { [self] isCurrent in
            do { try await op(isCurrent) } catch { if isCurrent() { handle(error) } }
        }
    }

    private func resolveOp(_ isCurrent: @MainActor () -> Bool) async throws {
        // Tema repetido: se dice en cuanto se reconoce el enlace, antes de leer metadatos y de buscar.
        let lookup: LibraryLookup
        if let c = lookupCache, c.text == text { lookup = c.value } else {
            lookup = await hooks.lookup()
            guard isCurrent() else { throw CancellationError() }
            lookupCache = (text, lookup)
        }
        libraryVideos = lookup.video
        existing = nil
        possibleDuplicate = nil
        switch try? SourceLink.parse(text) {
        case .spotify(let id)?: existing = lookup.spotify[id]
        case .youtube(let id)?: existing = lookup.video[id]
        case nil: break
        }
        if existing != nil { return }
        if importer == nil {
            let made = try await hooks.makeImporter()
            guard isCurrent() else { throw CancellationError() }
            importer = made
        }
        guard let importer else { return }
        let r = try await importer.resolve(text)
        guard isCurrent() else { throw CancellationError() }
        title = r.title
        artist = r.artist
        possibleDuplicate = lookup.possible(title: r.title, artist: r.artist)
        selectedID = r.confirmation?.id
    }

    private func downloadOp() async throws {
        guard let importer, let candidate = selectedCandidate else { return }
        if let dup = await hooks.existingProject(candidate.id) { hooks.close(dup); return }
        let source = try await importer.download(candidate: candidate, title: title, artist: artist)
        defer { source.cleanUp() }
        isImporting = true
        importProgress = 0
        defer { isImporting = false }
        try await hooks.store(source) { [weak self] p in Task { @MainActor in self?.importProgress = p } }
        if source.notices.isEmpty { hooks.close(nil) } else { finishedNotices = source.notices }
    }

    private func handle(_ error: Error) {
        if error is CancellationError { return }
        if let e = error as? SourceError {
            if e == .cancelled { return }
            failure = e
        } else if case LibraryError.duplicate(let id) = error {
            hooks.close(id)
        } else {
            otherError = AppModel.describe(error)
        }
    }
}

/// Textos de la tabla de errores de la spec («Fuentes externas» > Errores), lo que ve el usuario.
enum SourceMessages {
    struct Message {
        var title: String
        var detail: String
    }

    static let supportedLinks = "Se admiten enlaces de un vídeo de YouTube (youtube.com/watch, youtu.be, music.youtube.com) y de una canción de Spotify (open.spotify.com/track o spotify:track), además de listas de YouTube (youtube.com/playlist) y listas o álbumes de Spotify (open.spotify.com/playlist, open.spotify.com/album). Episodios no."

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
}

// MARK: - Vista

struct LinkImportSheet: View {
    @Bindable var session: LinkImportSession

    static let playlistSize = CGSize(width: 880, height: 700)

    var body: some View {
        let wide = session.screen == .playlist
        return VStack(alignment: .leading, spacing: 18) {
            Text(wide ? "Importar lista" : session.screen == .empty ? "Importar tema" : "Importar desde enlace").font(TF.display(22))
            switch session.screen {
            case .empty: emptyView
            case .resolving(let s): resolvingView(s)
            case .preparing: preparingView
            case .candidates: candidatesView
            case .working(let label, let p): workingView(label, p)
            case .error: errorView
            case .done: doneView
            case .repeated: repeatedView
            case .playlist:
                if let p = session.playlist {
                    PlaylistImportView(playlist: p, close: { session.close() },
                                       discard: { session.backToEmpty() })
                }
            }
        }
        // La hoja de una lista necesita más sitio que la de un tema.
        .padding(24).frame(width: wide ? Self.playlistSize.width : session.screen == .empty ? 620 : 560, height: wide ? Self.playlistSize.height : nil)
        .background(TF.card).foregroundStyle(TF.text)
        .interactiveDismissDisabled(!session.canCancel)
    }

    // MARK: Vacío

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .trailing) {
                field("Pega un enlace o busca en Spotify", text: $session.text) { session.importTapped() }
                if session.searchState == .searching {
                    ProgressView().controlSize(.small).padding(.trailing, 12)
                }
            }
            searchArea
            actions {
                Button("Importar fichero…") { session.pickFile() }.buttonStyle(SecondaryButton())
                    .disabled(session.isBusy)
                Spacer().frame(width: 8)
                Button("Cancelar") { session.close() }.buttonStyle(SecondaryButton())
                    .keyboardShortcut(.cancelAction)
                Button("Importar") { session.importTapped() }.buttonStyle(PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(session.isBusy || ImportQuery.classify(session.text) == .empty)
            }
        }
    }

    @ViewBuilder private var searchArea: some View {
        switch session.searchState {
        case .idle, .searching:
            Text(SourceMessages.supportedLinks).font(TF.body(12)).foregroundStyle(TF.muted)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            banner(message, error: true)
            Text(SourceMessages.supportedLinks).font(TF.body(12)).foregroundStyle(TF.muted)
                .fixedSize(horizontal: false, vertical: true)
        case .results(let query, let tracks):
            if tracks.isEmpty {
                Text("Spotify no ha encontrado nada para «\(query)»").font(TF.body(13)).foregroundStyle(TF.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(tracks) { t in
                        if t.id != tracks.first?.id { Divider().overlay(TF.line) }
                        trackRow(t)
                    }
                }
                .background(TF.field, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func trackRow(_ t: SpotifyTrackResult) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: t.imageURL) { image in image.resizable().scaledToFill() } placeholder: {
                Image(systemName: "music.note").foregroundStyle(TF.muted)
            }
            .frame(width: 36, height: 36).background(TF.card).clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 1) {
                Text(t.name).font(TF.body(13, .semibold)).lineLimit(1)
                Text(t.artistsText).font(TF.body(12)).foregroundStyle(TF.text2).lineLimit(1)
                Text(t.year.map { "\(t.album) · \($0)" } ?? t.album).font(TF.body(11)).foregroundStyle(TF.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(t.durationText).font(TF.body(12)).foregroundStyle(TF.muted).monospacedDigit()
            Button { session.listen(t) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.plain).foregroundStyle(TF.accent)
                .help("Oír en Spotify").accessibilityLabel("Oír en Spotify")
            Button("Elegir") { session.choose(t) }.buttonStyle(SecondaryButton(height: 30))
                .disabled(session.isBusy)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    // MARK: Repetido

    private var repeatedView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Ya está en la biblioteca", systemImage: "checkmark.circle.fill")
                .foregroundStyle(TF.ok).font(TF.body(15, .semibold))
            if let e = session.existing {
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.title).font(TF.body(15, .semibold)).lineLimit(2)
                    if let a = e.artist, !a.isEmpty { Text(a).font(TF.body(13)).foregroundStyle(TF.muted) }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
            }
            Text("No se busca ni se descarga nada.").font(TF.body(12)).foregroundStyle(TF.muted)
            actions {
                Button("Cerrar") { session.close() }.buttonStyle(SecondaryButton())
                Button("Abrir") { session.openExisting() }.buttonStyle(PrimaryButton())
            }
        }
    }

    // MARK: Preparando

    private var preparingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Preparando…")
            }
            actions { Button("Cancelar") { session.cancel() }.buttonStyle(SecondaryButton()) }
        }
    }

    // MARK: Resolviendo

    private func resolvingView(_ stage: ResolvingStage) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(stage == .metadata ? "Leyendo metadatos…" : "Buscando en YouTube…")
            }
            if stage == .searching { Text("Suele tardar unos 9 s.").font(TF.body(12)).foregroundStyle(TF.muted) }
            actions { Button("Cancelar") { session.cancel() }.buttonStyle(SecondaryButton()) }
        }
    }

    // MARK: Candidatos

    @ViewBuilder private var candidatesView: some View {
        if let r = session.resolved {
            VStack(alignment: .leading, spacing: 14) {
                header(r)
                if let p = session.possibleDuplicate { possibleBand(p) }
                if let f = session.failure, f.returnsToCandidates { banner(SourceMessages.text(for: f).detail, error: true) }
                if let c = r.confirmation { confirmation(c) } else { candidateList(r) }
                if !session.notices.isEmpty { ForEach(session.notices, id: \.message) { banner($0.message, error: false) } }
                actions {
                    Button("Cancelar") { session.close() }.buttonStyle(SecondaryButton())
                    Button("Importar") { session.importSelected() }.buttonStyle(PrimaryButton())
                        .disabled(session.selectedCandidate == nil || session.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func possibleBand(_ p: ExistingTrack) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(TF.muted)
            Text("Puede que ya lo tengas: " + [p.title, p.artist].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(TF.body(13)).foregroundStyle(TF.text2).lineLimit(2)
            Spacer(minLength: 8)
            Button("Abrir") { session.openProject(p.id) }.buttonStyle(SecondaryButton(height: 28))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(TF.neutralBg, in: RoundedRectangle(cornerRadius: 8))
    }

    private func header(_ r: ResolvedSource) -> some View {
        HStack(alignment: .top, spacing: 16) {
            cover(r.artworkURL)
            VStack(alignment: .leading, spacing: 10) {
                labeled("Título") { field("Título", text: $session.title) {} }
                labeled("Artista") { field("Artista", text: $session.artist) {} }
            }
        }
    }

    private func cover(_ url: URL?) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            default: ZStack { TF.field; Image(systemName: "music.note").foregroundStyle(TF.muted) }
            }
        }
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(TF.fieldLine))
    }

    private func confirmation(_ c: Candidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VÍDEO A IMPORTAR").font(TF.body(12, .medium)).tracking(0.7).foregroundStyle(TF.muted)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(TF.body(14, .semibold)).lineLimit(2)
                    Text([c.channel, c.durationSeconds.map(Fmt.duration)].compactMap { $0 }.joined(separator: " · "))
                        .font(TF.body(13)).foregroundStyle(TF.muted)
                }
                Spacer()
                openLink(c.url)
            }
            .padding(12).background(TF.field, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func candidateList(_ r: ResolvedSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CANDIDATOS EN YOUTUBE").font(TF.body(12, .medium)).tracking(0.7).foregroundStyle(TF.muted)
                Spacer()
                if let d = r.durationSeconds {
                    Text("Spotify: \(Fmt.duration(d))").font(TF.body(12)).foregroundStyle(TF.muted)
                }
            }
            if r.noCloseCandidate {
                banner(r.candidates.isEmpty
                       ? "La búsqueda no ha dado resultados. Pega a mano un enlace de YouTube."
                       : "Ningún candidato queda a \(Int(CandidateRanker.closeThreshold)) s o menos de la duración de Spotify. Elige con cuidado o pega a mano un enlace de YouTube.",
                       error: false)
            }
            ScrollView {
                VStack(spacing: 6) { ForEach(r.candidates) { row($0) } }
            }
            .frame(maxHeight: 280)
            labeled("¿Ninguno convence? Pega un enlace de YouTube") {
                HStack(spacing: 8) {
                    field("https://www.youtube.com/watch?v=…", text: $session.manualText) { session.addManual() }
                    Button("Añadir") { session.addManual() }.buttonStyle(SecondaryButton())
                        .disabled(session.manualText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let m = session.manualError { Text(m).font(TF.body(12)).foregroundStyle(TF.danger) }
        }
    }

    private func row(_ rc: RankedCandidate) -> some View {
        let inLib = session.libraryVideos[rc.id]
        let on = session.selectedID == rc.id && inLib == nil
        return HStack(spacing: 12) {
            Image(systemName: on ? "largecircle.fill.circle" : "circle").foregroundStyle(on ? TF.accent : TF.muted)
                .opacity(inLib == nil ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text(rc.candidate.title).font(TF.body(14, .semibold)).lineLimit(1)
                Text([rc.candidate.channel, rc.candidate.durationSeconds.map(Fmt.duration)].compactMap { $0 }.joined(separator: " · "))
                    .font(TF.body(12)).foregroundStyle(TF.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let d = rc.difference { Text(Self.signed(d)).font(TF.body(12, .medium)).foregroundStyle(TF.text2) }
            if rc.isClose { Chip(text: "cercano", kind: .ok) }
            if rc.isLive { Chip(text: "directo", kind: .neutral) }
            if let e = inLib {
                Chip(text: "En la biblioteca", kind: .neutral)
                Button("Abrir") { session.openProject(e.id) }.buttonStyle(SecondaryButton(height: 28))
            } else {
                openLink(rc.candidate.url)
            }
        }
        .opacity(inLib == nil ? 1 : 0.7)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(on ? TF.accentBg : TF.field, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? TF.accent : TF.fieldLine))
        .contentShape(Rectangle())
        .onTapGesture { if inLib == nil { session.selectedID = rc.id } }
    }

    private func openLink(_ url: URL) -> some View {
        Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.right.square") }
            .buttonStyle(.plain).foregroundStyle(TF.accent).help("Abrir en el navegador")
    }

    static func signed(_ seconds: Double) -> String {
        String(format: "%+.1f s", seconds).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: Trabajando

    private func workingView(_ label: String, _ progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !session.title.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title).font(TF.body(15, .semibold)).lineLimit(2)
                    if !session.artist.isEmpty { Text(session.artist).font(TF.body(13)).foregroundStyle(TF.muted) }
                }
            }
            HStack {
                Text(label)
                Spacer()
                if let p = progress { Text(Fmt.percent(p)).foregroundStyle(TF.muted) }
            }
            AccentBar(value: progress)
            ForEach(session.notices, id: \.message) { banner($0.message, error: false) }
            actions {
                Button("Cancelar") { session.cancel() }.buttonStyle(SecondaryButton()).disabled(!session.canCancel)
            }
        }
    }

    // MARK: Error

    private var errorView: some View {
        let e = session.failure
        let t = e.map(SourceMessages.text(for:)) ?? SourceMessages.Message(title: "No se pudo importar", detail: session.otherError ?? "")
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(TF.danger)
                VStack(alignment: .leading, spacing: 6) {
                    Text(t.title).font(TF.body(15, .semibold))
                    Text(t.detail).font(TF.body(13)).foregroundStyle(TF.muted).fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            if session.alreadyLatest {
                banner("yt-dlp ya es la última versión: YouTube ha cambiado algo y hay que esperar a que se corrija. Mientras, importa el fichero a mano (Importar tema > Desde fichero…).", error: false)
            }
            actions {
                Button("Cerrar") { session.close() }.buttonStyle(SecondaryButton())
                if e?.suggestsYtDlpUpdate == true && !session.alreadyLatest {
                    Button("Actualizar y reintentar") { session.updateAndRetry() }.buttonStyle(PrimaryButton())
                } else if e == .unsupportedLink || e == .spotifyMetadataUnreadable {
                    Button(e == .unsupportedLink ? "Probar con otro enlace" : "Pegar un enlace de YouTube") {
                        session.text = ""; session.backToEmpty()
                    }.buttonStyle(PrimaryButton())
                } else if !session.alreadyLatest {
                    Button("Reintentar") { session.retry() }.buttonStyle(PrimaryButton())
                }
            }
        }
    }

    // MARK: Hecho

    private var doneView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Tema importado", systemImage: "checkmark.circle.fill").foregroundStyle(TF.ok).font(TF.body(15, .semibold))
            ForEach(session.finishedNotices ?? [], id: \.message) { banner($0.message, error: false) }
            actions { Button("Cerrar") { session.close() }.buttonStyle(PrimaryButton()) }
        }
    }

    // MARK: Piezas

    private func actions<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) { Spacer(); content() }
    }

    private func labeled<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(TF.body(13)).foregroundStyle(TF.muted)
            content()
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, onSubmit: @escaping () -> Void) -> some View {
        TextField(placeholder, text: text).textFieldStyle(.plain)
            .padding(.horizontal, 12).frame(height: 40)
            .background(TF.field, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(TF.fieldLine))
            .onSubmit(onSubmit)
    }

    private func banner(_ text: String, error: Bool) -> some View {
        Text(text).font(TF.body(13)).foregroundStyle(error ? TF.danger : TF.accent)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
            .background(error ? TF.dangerBg : TF.accentBg, in: RoundedRectangle(cornerRadius: 8))
    }
}

extension LinkImportSession: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
