import AudioKit
import AppKit
import Foundation
import ModelKit
import Observation
import SourceKit
import UniformTypeIdentifiers
import Store

#if DEBUG
/// Argumentos de arranque solo en DEBUG (pruebas y capturas).
struct LaunchOptions {
    var supportDir: URL?
    var projectsFolder: URL?
    /// Zips de modelo a instalar sin red (el nombre decide cuál: «BeatThis» = Beat This!, el resto = separador).
    var installModelFrom: [URL] = []
    var importFiles: [URL] = []
    var screen: String?
    // Backing (capturas): proyecto por nombre de carpeta o título, y estado inicial sin reproducir sonido.
    var project: String?
    var seek: Double?
    var loop: ClosedRange<Double>?
    var rate: Double?
    var mute: [String] = []
    var transpose: Int?
    var capo: Int?
    /// «missing», «analyzing» o «failed»: fuerza el estado del análisis y no lanza el real.
    var analysisState: String?
    /// Guarda la ventana en PNG tras `snapshotDelay` s y sale (capturas sin permiso de grabación de pantalla).
    var snapshot: URL?
    var snapshotDelay = 4.0
    /// Backing: rejilla de acordes expandida / modo edición de acordes activo.
    var chordsExpanded = false
    var chordsEdit = false
    /// Escribe en `Temp/p8/grid-hit.txt` el resultado de la comprobación del hit-test de la rejilla y de la tira.
    var gridHitSelftest = false
    /// Abre la hoja «Desde enlace» con datos simulados (sin red): vacio, resolviendo, candidatos, descargando, error o youtube.
    var linkImportDemo: String?
    /// Detalle de Biblioteca con la edición de título y artista activada / diálogo «¿Eliminar…?» del primer tema.
    var detailEdit = false
    var deleteDialog = false
    /// Backing con pistas de guitarra y tramos simulados (solo en memoria): «mono-solo», «stereo», «stereo-solo»,
    /// «dirty» (tramos sin aplicar), «processing» y «failed» (como «mono-solo» con el estado del proceso).
    var guitarsDemo: String?
    /// Con `--guitars-demo`: selecciona la sección N (desde 0) y abre su ventana, para capturas.
    var selectSection: Int?
    /// Tablatura (Fase 5): `--screen tab`, pista N (desde 0) visible, edición activada y «Oír transcripción» en esa pista.
    var tabTrack: Int?
    var tabEdit = false
    var tabListen = false
    /// Con `--screen tab`: exporta el `.gp` a esa ruta sin diálogo, cuando la tablatura está lista.
    var tabExport: URL?

    init(_ args: [String] = CommandLine.arguments) {
        var i = 1
        func path(_ s: String) -> URL { URL(fileURLWithPath: (s as NSString).expandingTildeInPath).standardizedFileURL }
        while i < args.count {
            let a = args[i]
            let next: String? = i + 1 < args.count ? args[i + 1] : nil
            switch (a, next) {
            case ("--support-dir", let v?): supportDir = path(v); i += 1
            case ("--projects-folder", let v?): projectsFolder = path(v); i += 1
            case ("--install-model-from", let v?): installModelFrom.append(path(v)); i += 1
            case ("--project", let v?): project = v; i += 1
            case ("--seek", let v?): seek = Double(v); i += 1
            case ("--loop", let v?):
                let p = v.split(separator: ",").compactMap { Double($0) }
                if p.count == 2, p[1] > p[0] { loop = p[0]...p[1] }
                i += 1
            case ("--rate", let v?): rate = Double(v); i += 1
            case ("--mute", let v?): mute.append(v); i += 1
            case ("--transpose", let v?): transpose = Int(v); i += 1
            case ("--capo", let v?): capo = Int(v); i += 1
            case ("--analysis-state", let v?): analysisState = v; i += 1
            case ("--snapshot", let v?): snapshot = path(v); i += 1
            case ("--snapshot-delay", let v?): snapshotDelay = Double(v) ?? 4; i += 1
            case ("--chords-expanded", _): chordsExpanded = true
            case ("--chords-edit", _): chordsEdit = true
            case ("--grid-hit-selftest", _): gridHitSelftest = true
            case ("--import", let v?): importFiles.append(path(v)); i += 1
            case ("--screen", let v?): screen = v; i += 1
            case ("--link-import-demo", let v?): linkImportDemo = v; i += 1
            case ("--detail-edit", _): detailEdit = true
            case ("--delete-dialog", _): deleteDialog = true
            case ("--guitars-demo", let v?): guitarsDemo = v; i += 1
            case ("--select-section", let v?): selectSection = Int(v); i += 1
            case ("--tab-track", let v?): tabTrack = Int(v); i += 1
            case ("--tab-edit", _): tabEdit = true
            case ("--tab-listen", _): tabListen = true
            case ("--tab-export", let v?): tabExport = path(v); i += 1
            default: break
            }
            i += 1
        }
    }
}
#endif

enum AppSection: Hashable { case library, backing, tab, settings }
enum SettingsTab: String, CaseIterable, Identifiable {
    case audio = "Audio", video = "Cámara y vídeo", library = "Biblioteca y equipo"
    var id: String { rawValue }
}

struct ImportItem: Identifiable {
    let id = UUID()
    let name: String
    var progress: Double
}

struct ProjectDetail: Identifiable {
    var id: UUID { project.id }
    let project: Project
    let folder: URL
    let stems: [(kind: StemKind, bytes: Int64, isEmpty: Bool)]
}

struct TrashRequest: Identifiable {
    let id = UUID()
    let projectID: UUID
    let title: String
    let stems: Int
    let takes: Int
    let videos: Int

    /// Lo que se va con el tema, para el diálogo.
    var contents: String {
        var parts = [stems == 0 ? "sus stems" : (stems == 1 ? "1 stem" : "\(stems) stems")]
        if takes > 0 { parts.append(takes == 1 ? "1 toma" : "\(takes) tomas") }
        if videos > 0 { parts.append(videos == 1 ? "1 vídeo" : "\(videos) vídeos") }
        return parts.joined(separator: ", ")
    }
}

struct CleanupRequest: Identifiable {
    let id = UUID()
    let projectID: UUID?   // nil = todos
    let title: String
    let bytes: Int64
}

/// Paso de guitarras en marcha o fallido (eventos `guitarSplit*` de `Library`; no hay progreso por evento).
enum GuitarProcess: Equatable {
    case processing
    case failed(String)
}

struct Notice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor @Observable
final class AppModel {
    // Navegación
    var section: AppSection = .library
    var settingsTab: SettingsTab = .audio
    var detail: ProjectDetail?
    /// Estado de estudio del tema abierto en Backing (P7b); nil si no hay ninguno.
    var study: StudySession?
    /// Reproductor y ajustes de Backing del tema abierto (P7b).
    var backing: BackingController?
    /// Tema sobre el que actúa la pantalla Backing (el último abierto en la biblioteca).
    var backingTarget: UUID?
    /// Dispositivo de salida elegido en el perfil y si está conectado.
    let audioDevice: AudioDeviceMonitor
    /// Proveedor de dispositivos de los selectores de Ajustes · Audio (simulado con `--screen settings-audio` en DEBUG).
    @ObservationIgnored let deviceProvider: AudioDeviceProviding
    /// Audio con el dispositivo (mini-spec Fase 3): sesión, medidores, calibración y grabación.
    let audio: AudioController
    /// Hoja «Calibrar latencia» abierta (Ajustes · Audio).
    var showCalibrationSheet = false

    private static func makeDeviceProvider() -> AudioDeviceProviding {
        #if DEBUG
        if AudioDemo.screens.contains(LaunchOptions().screen ?? "") {
            return SimulatedDeviceProvider(devices: [
                AudioDevice(id: 1, uid: "sim-flex", name: "HeadRush Flex Prime (USB)", inputChannels: 4, outputChannels: 4, sampleRates: [48000]),
                AudioDevice(id: 2, uid: "sim-builtin", name: "Altavoces del MacBook Pro", outputChannels: 2, sampleRates: [44100, 48000]),
                AudioDevice(id: 3, uid: "sim-mic", name: "Micrófono del MacBook Pro", inputChannels: 1, sampleRates: [44100, 48000]),
            ], defaultID: 2)
        }
        #endif
        return CoreAudioDeviceProvider()
    }

    // Datos
    var profile = EquipmentProfile() {
        didSet {
            audioDevice.choose(uid: profile.audio?.outputDeviceUID)
            backing?.player.setOutput(outputSelection)
            audio.update(profile: profile)
        }
    }
    /// Salida del backing según el perfil (dispositivo y par de canales).
    var outputSelection: OutputSelection {
        let a = profile.audio
        return OutputSelection(deviceUID: a?.outputDeviceUID, left: a?.backingOut.left ?? 1, right: a?.backingOut.right ?? 2)
    }
    var needsFolder = false
    var entries: [LibraryEntryInfo] = []
    var separationProgress: [UUID: Double] = [:]
    var failures: [UUID: String] = [:]
    /// Estado del paso de guitarras (L/R y tramos de solo) por tema (Fase 4); sin entrada = nada en marcha.
    var guitarProcess: [UUID: GuitarProcess] = [:]
    var imports: [ImportItem] = []
    var modelState: ModelState = .notInstalled
    var usage: DiskUsageReport?
    var modelsBytes: Int64 = 0

    // Diálogos
    var duplicateID: UUID?
    var notice: Notice?
    var cleanupRequest: CleanupRequest?
    var trashRequest: TrashRequest?
    var pendingFolder: URL?
    var relocationProgress: Double?
    /// Hoja «Importar desde enlace» abierta (nil = cerrada).
    var linkImport: LinkImportSession?
    /// Lista o álbum en importación. Vive aquí, no en la hoja: se puede cerrar la hoja y la cola sigue.
    var playlistImport: PlaylistImportSession?
    /// `videoID` de temas de lista que la biblioteca ya tenía al importarlos (cuentan como «en la biblioteca»).
    @ObservationIgnored private var playlistDuplicates: Set<String> = []

    // Fuentes externas (Ajustes)
    enum YtDlpUpdateStatus: Equatable { case idle, updating, done(String), failed(String) }
    var toolsInfo: ExternalToolsInfo?
    var ytDlpUpdateStatus: YtDlpUpdateStatus = .idle

    @ObservationIgnored let supportDir: URL
    @ObservationIgnored let profileStore: ProfileStore
    @ObservationIgnored private var masterSaveTask: Task<Void, Never>?
    @ObservationIgnored let modelStore: ModelStore
    @ObservationIgnored let studyAnalyzer: AppStudyAnalyzer
    @ObservationIgnored let sources: ExternalSources
    @ObservationIgnored private(set) var library: Library?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    #if DEBUG
    @ObservationIgnored let options = LaunchOptions()
    #endif

    static let modelID = ModelCatalog.separatorBSRoformerSW.id
    static let defaultSupportDir = URL.applicationSupportDirectory.appendingPathComponent("ToneForge", isDirectory: true)
    static let proposedFolder = URL.musicDirectory.appendingPathComponent("ToneForge", isDirectory: true)

    init() {
        var dir = Self.defaultSupportDir
        #if DEBUG
        if let d = LaunchOptions().supportDir { dir = d }
        #endif
        supportDir = dir
        let provider = Self.makeDeviceProvider()
        deviceProvider = provider
        #if DEBUG
        let simulated = AudioDemo.screens.contains(LaunchOptions().screen ?? "")
        audioDevice = simulated ? AudioDeviceMonitor(provider: provider, observeChanges: false) : AudioDeviceMonitor()
        #else
        audioDevice = AudioDeviceMonitor()
        #endif
        audio = AudioController(provider: provider, list: AudioDeviceList(provider: provider))
        #if DEBUG
        if AudioDemo.screens.contains(LaunchOptions().screen ?? "") { audio.makeIO = AudioDemo.makeIO }
        #endif
        profileStore = ProfileStore(url: dir.appendingPathComponent("profile.json"))
        modelStore = ModelStore(root: dir.appendingPathComponent("Models", isDirectory: true),
                                bundleResourceDirectory: Bundle.main.resourceURL)
        studyAnalyzer = AppStudyAnalyzer(modelStore: modelStore)
        sources = ExternalSources(
            bundleDirectory: Bundle.main.executableURL?.deletingLastPathComponent() ?? Bundle.main.bundleURL,
            supportDirectory: dir.appendingPathComponent("Helpers", isDirectory: true))
        audio.onCalibrationSaved = { [weak self] cal in
            guard let self else { return }
            var a = self.profile.audio ?? AudioSettings()
            a.latency = cal
            self.profile.audio = a
            self.saveProfile()
        }
    }

    // MARK: Arranque

    func start() async {
        guard !started else { return }
        started = true
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        do { profile = try profileStore.load() } catch { notify("Perfil ilegible", error) }
        listenToModels()

        #if DEBUG
        assert(PossibleDuplicate.selfCheck(), "Normalización de «posible repetido»")
        for zip in options.installModelFrom {
            let id = zip.lastPathComponent.contains("BeatThis") ? ModelCatalog.beatsBeatThis.id : Self.modelID
            do { _ = try await modelStore.install(id, fromArchive: zip) } catch { notify("No se pudo instalar el modelo", error) }
        }
        if let f = options.projectsFolder {
            profile.projectsFolder = f
            saveProfile()
        }
        #endif

        // Temporales huérfanos de una ejecución anterior; antes de que nada pueda estar usándolos.
        SourceImporter.removeOrphanedDownloads()
        if let root = profile.projectsFolder { Library.removeOrphanTemporaries(in: root) }

        guard profile.projectsFolder != nil else { needsFolder = true; return }
        await bootstrap()
    }

    /// Primer arranque: la carpeta es obligatoria.
    func chooseFirstRunFolder() {
        let panel = NSOpenPanel()
        panel.title = "Carpeta de proyectos"
        panel.message = "Elige dónde guardar tus temas. Se propone ~/Music/ToneForge."
        panel.prompt = "Elegir"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        try? FileManager.default.createDirectory(at: Self.proposedFolder, withIntermediateDirectories: true)
        panel.directoryURL = Self.proposedFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        profile.projectsFolder = url
        saveProfile()
        needsFolder = false
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        guard library == nil, let root = profile.projectsFolder else { return }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let index = try LibraryIndex.make(storeURL: supportDir.appendingPathComponent("Library.store"))
            let helper = Bundle.main.url(forAuxiliaryExecutable: "tf-separate")
            let lib = Library(root: root, profile: profileStore, index: index, importer: AppAudioImporter(),
                              separator: AppStemSeparator(modelStore: modelStore, helperURL: helper),
                              levelMeter: AppStemLevelMeter(), analyzer: studyAnalyzer,
                              guitarSplitter: AppGuitarSplitter(modelStore: modelStore))
            library = lib
            eventTask = Task { [weak self] in
                for await e in lib.events { self?.handle(e) }
            }
            _ = try await lib.rebuildIndex()
            _ = try await lib.recoverInterrupted()
        } catch {
            notify("No se pudo abrir la biblioteca", error)
        }
        await refresh()
        #if DEBUG
        if !options.importFiles.isEmpty { importFiles(options.importFiles) }
        switch options.screen {
        case "settings-library": section = .settings; settingsTab = .library
        case "settings": section = .settings
        case "settings-audio":
            // Dispositivos y E/S simulados (ver `makeDeviceProvider`); el perfil se toca solo en memoria, sin guardar.
            section = .settings; settingsTab = .audio
            profile.audio = AudioSettings(outputDeviceUID: "sim-flex", inputDeviceUID: "sim-flex", guitarIn: [1])
        case "calibration-sheet":
            // Igual y, además, calibra de verdad contra la E/S simulada y enseña la hoja con el resultado.
            section = .settings; settingsTab = .audio
            profile.audio = AudioSettings(outputDeviceUID: "sim-flex", inputDeviceUID: "sim-flex", guitarIn: [1])
            showCalibrationSheet = true
            Task { try? await Task.sleep(for: .seconds(1)); await audio.calibrate() }
        case "backing-ab":
            // Backing con E/S simulada: ver `runAudioDemo` (calibra, graba una toma y deja el A/B en «Última toma»).
            profile.audio = AudioSettings(outputDeviceUID: "sim-flex", inputDeviceUID: "sim-flex", guitarIn: [1])
            let match = entries.first { e in options.project.map { e.folderName == $0 || e.title == $0 } ?? true }
            backingTarget = match?.id
            section = .backing
        case "detail-first": if let first = entries.first { await open(first.id) }
        case "tab":
            let match = entries.first { e in options.project.map { e.folderName == $0 || e.title == $0 } ?? true }
            backingTarget = match?.id
            section = .tab
        case "backing":
            let match = entries.first { e in options.project.map { e.folderName == $0 || e.title == $0 } ?? true }
            backingTarget = match?.id
            section = .backing
        default: break
        }
        if let demo = options.linkImportDemo { openLinkImportDemo(demo) }
        if options.deleteDialog, let first = entries.first { requestTrash(first) }
        #endif
    }

    private func listenToModels() {
        Task { [weak self, modelStore] in
            if let s = await modelStore.states()[Self.modelID] { self?.modelState = s }
            let updates = await modelStore.updates
            for await (id, s) in updates where id == Self.modelID {
                self?.modelState = s
                self?.modelsBytes = await modelStore.diskUsage()
            }
        }
        Task { [weak self, modelStore] in self?.modelsBytes = await modelStore.diskUsage() }
    }

    // MARK: Eventos y refresco

    private func handle(_ e: LibraryEvent) {
        switch e {
        case .separationStarted(let id): separationProgress[id] = 0; failures[id] = nil
        case .separationProgress(let id, let p): separationProgress[id] = p
        case .separationFailed(let id, let msg): separationProgress[id] = nil; failures[id] = msg
        case .separationFinished(let id), .separationCancelled(let id): separationProgress[id] = nil; failures[id] = nil
        case .analysisQueued(let id), .analysisStarted(let id): if !analysisPinned, study?.projectID == id { study?.setAnalysisState(.analyzing) }
        case .analysisFinished(let id): if !analysisPinned, study?.projectID == id { study?.reload(); study?.setAnalysisState(.ready) }
        case .analysisFailed(let id, let msg): if !analysisPinned, study?.projectID == id { study?.setAnalysisState(.failed(msg)) }
        case .stemsMeasured(let id): if study?.projectID == id { study?.reload() }
        case .guitarSplitQueued(let id), .guitarSplitStarted(let id): guitarProcess[id] = .processing
        case .guitarSplitFinished(let id): guitarProcess[id] = nil; if study?.projectID == id { study?.reload() }
        case .guitarSplitFailed(let id, let msg): guitarProcess[id] = .failed(msg)
        case .relocated: if let p = try? profileStore.load() { profile = p }
        default: break
        }
        Task { await refresh() }
    }

    func refresh() async {
        guard let library else { return }
        if let list = try? await library.entries() {
            entries = list.sorted { $0.createdAt > $1.createdAt }
            let root = await library.root
            for e in entries where e.separationState == SeparationStatus.failed.rawValue && failures[e.id] == nil {
                let p = try? ProjectFile.load(folder: root.appendingPathComponent(e.folderName))
                failures[e.id] = p?.separation.error ?? "Error desconocido"
            }
        }
        usage = await library.diskUsage()
    }

    // MARK: Biblioteca

    var matchedRigs: Int { entries.reduce(0) { $0 + $1.rigCount } }
    var recordedTakes: Int { entries.reduce(0) { $0 + $1.takeCount } }
    /// Vídeos exportados: aún no hay dato en el índice (llega con el montaje, Fase 7).
    var exportedVideos: Int { 0 }

    func pickAndImport() {
        let panel = NSOpenPanel()
        panel.title = "Importar tema"
        panel.prompt = "Importar"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["wav", "flac", "mp3"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    // MARK: Importar desde enlace

    func openLinkImport() {
        guard library != nil else { return }
        linkImport = LinkImportSession(hooks: .init(
            makeImporter: { [sources] in try await sources.makeImporter() },
            existingProject: { [weak self] videoID in await self?.library?.project(withVideoID: videoID)?.id },
            store: { [weak self] source, progress in _ = try await self?.storeImported(source, progress: progress) },
            updateYtDlp: { [sources] in try await sources.updateYtDlp() },
            lookup: { [weak self] in await self?.scanLibraryIDs() ?? LibraryLookup() },
            open: { [weak self] id in self?.openFromSheet(id) },
            makePlaylist: { [weak self] in
                guard let self else { throw SourceError.cancelled }
                return try await self.makePlaylistSession()
            },
            discardPlaylist: { [weak self] in self?.playlistImport = nil },
            close: { [weak self] dup in self?.closeLinkImport(duplicate: dup) }))
        linkImport?.playlist = playlistImport
    }

    func closeLinkImport(duplicate: UUID? = nil) {
        linkImport = nil
        // Una lista sin cola en marcha (temas, revisión, resumen) no se conserva al cerrar con el botón.
        if let p = playlistImport, !p.isLive { playlistImport = nil }
        if let duplicate { duplicateID = duplicate }
        Task { await refresh() }
    }

    /// Prepara la sesión de lista (`PlaylistImporter` con yt-dlp, ffmpeg y el cierre que importa y separa).
    func makePlaylistSession() async throws -> PlaylistImportSession {
        playlistDuplicates = []
        let importer = try await sources.makePlaylistImporter { [weak self] source in
            try await self?.storePlaylistTrack(source)
        }
        let session = PlaylistImportSession(importer: importer, hooks: playlistHooks())
        playlistImport = session
        return session
    }

    func playlistHooks() -> PlaylistImportSession.Hooks {
        .init(updateYtDlp: { [sources] in try await sources.updateYtDlp() },
              lookup: { [weak self] in await self?.scanLibraryIDs() ?? LibraryLookup() },
              open: { [weak self] id in self?.openFromSheet(id) },
              duplicateVideoIDs: { [weak self] in self?.playlistDuplicates ?? [] })
    }

    /// Identificadores de Spotify y de YouTube que ya tiene la biblioteca, para los cierres de duplicados de SourceKit
    /// (síncronos; el escaneo de `Library.project(withSpotifyID:)` / `project(withVideoID:)` se hace una vez por pasada).
    func scanLibraryIDs() async -> LibraryLookup {
        guard let root = profile.projectsFolder else { return LibraryLookup() }
        return await Task.detached {
            var found = LibraryLookup()
            for p in ProjectScanner.scan(root: root).found {
                guard let o = p.project.song.origin else { continue }
                let t = ExistingTrack(id: p.project.id, title: p.project.song.title, artist: p.project.song.artist)
                if let s = o.spotifyID { found.spotify[s] = t }
                if let v = o.videoID { found.video[v] = t }
            }
            return found
        }.value.withTracks(entries.map { ExistingTrack(id: $0.id, title: $0.title, artist: $0.artist) })
    }

    /// «Abrir» en la hoja: la cierra y abre el proyecto como al pulsar «Abrir» en la Biblioteca.
    func openFromSheet(_ id: UUID) {
        closeLinkImport()
        Task { await open(id) }
    }

    /// Un tema de la lista: importa y encola su separación, como al separar a mano. Un duplicado no es un fallo.
    private func storePlaylistTrack(_ source: ImportedSource) async throws {
        do {
            let id = try await storeImported(source) { _ in }
            do { try await library?.separate(id: id) } catch { notify("No se pudo separar \(source.title)", error) }
        } catch LibraryError.duplicate {
            playlistDuplicates.insert(source.origin.videoID)
        }
        await refresh()
    }

    /// Importa el WAV descargado con título, artista, origen y carátula (convertida a JPEG). La carpeta temporal
    /// la borra quien llama (`ImportedSource.cleanUp`), también si esto falla.
    @discardableResult
    private func storeImported(_ source: ImportedSource, progress: @escaping @Sendable (Double) -> Void) async throws -> UUID {
        guard let library else { throw LibraryError.workInProgress }
        var cover: URL?
        if let art = source.artworkURL {
            let out = source.workDirectory.appendingPathComponent("cover-converted.jpg")
            if CoverConverter.jpeg(from: art, to: out) { cover = out }
        }
        let meta = ImportMetadata(title: source.title, artist: source.artist.isEmpty ? nil : source.artist,
                                  origin: SongOrigin(source.origin), artworkFile: cover)
        return try await library.importSong(from: source.wavURL, metadata: meta, progress: progress)
    }

    // MARK: Fuentes externas (Ajustes)

    func loadToolsInfo() async { toolsInfo = await sources.toolsInfo() }

    func updateYtDlp() {
        guard ytDlpUpdateStatus != .updating else { return }
        ytDlpUpdateStatus = .updating
        Task {
            do {
                let info = try await sources.updateYtDlp()
                await loadToolsInfo()
                ytDlpUpdateStatus = toolsInfo?.ytDlpOrigin == .updated
                    ? .done("yt-dlp actualizado a \(info.version).")
                    : .done("Ya tienes la última versión (\(info.version)).")
            } catch {
                let e = error as? SourceError
                ytDlpUpdateStatus = .failed(e.map { SourceMessages.text(for: $0).title + ": " + SourceMessages.text(for: $0).detail }
                                            ?? error.localizedDescription)
            }
        }
    }

    func revertYtDlp() {
        Task {
            do { try await sources.removeUpdate(); ytDlpUpdateStatus = .idle } catch { notify("No se pudo volver a la embebida", error) }
            await loadToolsInfo()
        }
    }

    func importFiles(_ urls: [URL]) {
        let ok = Set(["wav", "flac", "mp3"])
        let files = urls.filter { ok.contains($0.pathExtension.lowercased()) }
        guard let library, !files.isEmpty else { return }
        Task {
            for url in files {
                let item = ImportItem(name: url.deletingPathExtension().lastPathComponent, progress: 0)
                imports.append(item)
                let itemID = item.id
                do {
                    _ = try await library.importSong(from: url) { [weak self] p in
                        Task { @MainActor in
                            if let i = self?.imports.firstIndex(where: { $0.id == itemID }) { self?.imports[i].progress = p }
                        }
                    }
                } catch LibraryError.duplicate(let existing) {
                    duplicateID = existing
                } catch {
                    notify("No se pudo importar \(url.lastPathComponent)", error)
                }
                imports.removeAll { $0.id == itemID }
            }
            await refresh()
        }
    }

    func open(_ id: UUID) async {
        guard let library, let entry = entries.first(where: { $0.id == id }) else { return }
        do {
            let project = try await library.open(id: id)
            let folder = await library.root.appendingPathComponent(entry.folderName, isDirectory: true)
            let layout = ProjectLayout(folder: folder)
            let stems = project.stems.map { s -> (kind: StemKind, bytes: Int64, isEmpty: Bool) in
                let size = (try? FileManager.default.attributesOfItem(atPath: layout.stemURL(s.kind).path)[.size] as? Int64) ?? 0
                return (s.kind, size, s.isEmpty)
            }
            backingTarget = id
            section = .library
            detail = ProjectDetail(project: project, folder: folder, stems: stems)
        } catch {
            notify("No se pudo abrir el tema", error)
        }
    }

    // MARK: Estudio (Backing)

    /// Abre el tema para estudiar: carga su estado de estudio y pide el análisis si falta o está desfasado.
    func openStudy(_ id: UUID) async {
        guard let library, let entry = entries.first(where: { $0.id == id }) else { return }
        await closeStudy()
        do {
            let project = try await library.open(id: id)
            let folder = await library.root.appendingPathComponent(entry.folderName, isDirectory: true)
            var state = AnalysisState.missing
            if !analysisPinned { state = try await library.ensureAnalysis(id: id) }
            // Si el usuario ya salió de Backing mientras se abría, no se deja nada abierto.
            guard section == .backing || section == .tab else { return }
            let session = StudySession(project: project, folder: folder, library: library, analysisState: state)
            study = session
            let controller = BackingController(session: session, masterGainDB: profile.masterGainDB, output: outputSelection)
            controller.onMasterChange = { [weak self] dB in self?.setMasterGain(dB) }
            backing = controller
            controller.audio = audio
            switch await library.guitarSplitState(id: id) {
            case .processing: guitarProcess[id] = .processing
            case .failed(let msg): guitarProcess[id] = .failed(msg)
            case .pending, .done: break
            }
            #if DEBUG
            applyLaunchOptions(to: session)
            #endif
        } catch {
            notify("No se pudo abrir el tema", error)
        }
    }

    /// Guarda el volumen global en el perfil con rebote (el fader emite muchos valores por segundo).
    func setMasterGain(_ dB: Double) {
        profile.masterGainDB = dB
        masterSaveTask?.cancel()
        masterSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveProfile()
        }
    }

    func closeStudy() async {
        backing?.stop()
        backing = nil
        await study?.flush()
        study = nil
    }

    /// Tope total del cierre (guardado del estudio + cancelar trabajos + esperar a los hijos).
    static let terminationBudget: TimeInterval = 3
    /// Parte del tope tras la que se manda SIGKILL a los hijos que sigan vivos (la gracia de SIGTERM de los runners es 5 s).
    static let terminationKillAfter: TimeInterval = 2

    /// Al salir de la app: guarda lo pendiente, cancela separación, colas e importaciones de enlace y espera
    /// (acotado a `terminationBudget`) a que `tf-separate`, `yt-dlp`, `deno` y `ffmpeg` hayan muerto; los que
    /// sigan vivos reciben SIGKILL.
    func flushForTermination() {
        backing?.stop()
        audio.unbind()
        if let t = masterSaveTask { t.cancel(); masterSaveTask = nil; saveProfile() }
        let start = Date()
        linkImport?.cancel()
        playlistImport?.cancelLoading()
        playlistImport?.cancel()
        if let library {
            let saved = study.map { ($0.projectID, $0.study, $0.project.sections) }
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                if let (id, study, sections) = saved {
                    try? await library.saveStudy(id: id, study: study, sections: sections)
                }
                await library.stopAllForShutdown()
                done.signal()
            }
            _ = done.wait(timeout: .now() + Self.terminationKillAfter)
        }
        ChildProcesses.terminateAll(waiting: max(0.2, Self.terminationBudget - Date().timeIntervalSince(start)),
                                    killAfter: max(0, Self.terminationKillAfter - Date().timeIntervalSince(start)))
    }

    private var analysisPinned: Bool {
        #if DEBUG
        options.analysisState != nil
        #else
        false
        #endif
    }

    /// Reintenta el análisis (tras un fallo, p. ej. sin red para bajar Beat This!).
    func retryAnalysis() {
        guard let library, let id = study?.projectID else { return }
        Task {
            if let state = try? await library.ensureAnalysis(id: id) { study?.setAnalysisState(state) }
        }
    }

    #if DEBUG
    /// `--snapshot`: vuelca el contenido de la ventana a PNG y cierra la app.
    func scheduleSnapshot() {
        guard let url = options.snapshot else { return }
        let delay = options.snapshotDelay
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            if options.screen == "calibration-sheet" {
                // La calibración va a ritmo real: se espera al resultado (máx. 2 min) en vez de fiarse del retardo.
                let deadline = Date().addingTimeInterval(120)
                while Date() < deadline {
                    if case .finished = audio.calibrationPhase { break }
                    try? await Task.sleep(for: .milliseconds(250))
                }
                try? await Task.sleep(for: .milliseconds(800))
            }
            if let window = NSApp.windows.first(where: { $0.contentView != nil }),
               let view = (window.attachedSheet ?? window).contentView {
                // Con una hoja abierta (--link-import-demo) se captura la hoja, que es otra ventana.
                if window.attachedSheet == nil {
                    window.setContentSize(CGSize(width: 1440, height: 900))
                    window.orderFrontRegardless()
                    try? await Task.sleep(for: .milliseconds(600))
                }
                view.layoutSubtreeIfNeeded()
                // Un ScrollView de primer nivel (Ajustes, Backing) sale en blanco con cacheDisplay aunque la vista esté bien
                // (no es un fallo de la app): la ventana propia se captura con el compositor, sin permiso de pantalla.
                if window.attachedSheet == nil, let png = Self.compositedPNG(of: window) {
                    try? png.write(to: url)
                } else if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                }
            }
            // Con una hoja abierta terminate(_:) no sale; en capturas basta salir directamente.
            if NSApp.windows.contains(where: { $0.attachedSheet != nil }) { exit(0) }
            NSApp.terminate(nil)
        }
    }

    /// PNG de la ventana tal como la compone WindowServer (`CGWindowListCreateImage`, que el SDK marca no disponible: se carga por dlsym).
    private static func compositedPNG(of window: NSWindow) -> Data? {
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(sym, to: Fn.self)
        // optionIncludingWindow = 1 << 3; boundsIgnoreFraming = 1 << 0 (sin sombra).
        guard let cg = create(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0)?.takeRetainedValue() else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    /// Estado inicial de Backing para capturas (sin reproducir).
    private func applyLaunchOptions(to session: StudySession) {
        switch options.analysisState {
        case "analyzing"?: session.setAnalysisState(.analyzing)
        case "failed"?: session.setAnalysisState(.failed("Sin red para descargar Beat This!"))
        case "missing"?: session.setAnalysisState(.missing)
        default: break
        }
        if options.screen == "backing-ab" { runAudioDemo() }
        if let demo = options.guitarsDemo {
            session.installGuitarsDemo(demo)
            backing?.loadTracks()
            if demo == "processing" { guitarProcess[session.projectID] = .processing }
            if demo == "failed" { guitarProcess[session.projectID] = .failed("Modelo de solista no disponible") }
        }
        backing?.apply(rate: options.rate, transpose: options.transpose, capo: options.capo,
                       muted: options.mute, loop: options.loop, seek: options.seek)
    }
    #endif

    func separate(_ id: UUID) {
        guard let library else { return }
        Task { do { try await library.separate(id: id) } catch { notify("No se pudo separar", error) } }
    }

    func cancelSeparation(_ id: UUID) {
        guard let library else { return }
        Task { do { try await library.cancelSeparation(id: id) } catch { notify("No se pudo cancelar", error) } }
    }

    func isSeparating(_ e: LibraryEntryInfo) -> Bool {
        e.separationState == SeparationStatus.running.rawValue || e.separationState == SeparationStatus.queued.rawValue
    }

    func showInFinder(_ folder: URL) { NSWorkspace.shared.activateFileViewerSelecting([folder]) }

    func folder(of e: LibraryEntryInfo) -> URL? {
        profile.projectsFolder?.appendingPathComponent(e.folderName, isDirectory: true)
    }

    // MARK: Limpieza

    func requestCleanup(id: UUID?, title: String) {
        guard let library else { return }
        Task {
            let report = await library.diskUsage()
            let bytes = id.map { i in report.projects.first { $0.id == i }?.regenerableBytes ?? 0 } ?? report.regenerableBytes
            cleanupRequest = CleanupRequest(projectID: id, title: title, bytes: bytes)
        }
    }

    func performCleanup(_ r: CleanupRequest) {
        guard let library else { return }
        Task {
            do {
                if let id = r.projectID { try await library.cleanup(id: id) } else { try await library.cleanupAll() }
            } catch { notify("No se pudo limpiar", error) }
            await refresh()
        }
    }

    // MARK: Eliminar tema (Papelera o borrado definitivo)

    /// Prepara la confirmación con lo que se va con el tema: stems, tomas y vídeos (lo que dice su `project.json`).
    func requestTrash(_ e: LibraryEntryInfo) {
        var videos = 0
        if let f = folder(of: e), let p = try? ProjectFile.load(folder: f) { videos = p.videos.count }
        trashRequest = TrashRequest(projectID: e.id, title: e.title, stems: e.stemCount, takes: e.takeCount, videos: videos)
    }

    /// Suelta el tema si está abierto (reproductor, Backing, detalle) y lo mueve a la Papelera. Si falla, no se toca
    /// nada y el aviso dice el motivo y recuerda «Eliminar del disco»; nunca se borra solo.
    func performTrash(_ r: TrashRequest) { remove(r, permanently: false) }

    /// Igual que `performTrash`, pero borra la carpeta del disco (no se puede deshacer).
    func performDelete(_ r: TrashRequest) { remove(r, permanently: true) }

    private func remove(_ r: TrashRequest, permanently: Bool) {
        guard let library else { return }
        Task {
            if study?.projectID == r.projectID { await closeStudy() }
            if backingTarget == r.projectID { backingTarget = nil }
            do {
                if permanently { try await library.deleteProject(id: r.projectID) }
                else { try await library.trashProject(id: r.projectID) }
                if detail?.id == r.projectID { detail = nil }
                separationProgress[r.projectID] = nil
                failures[r.projectID] = nil
            } catch {
                if permanently {
                    notify("No se pudo eliminar del disco", error)
                } else {
                    notice = Notice(title: "No se pudo mover a la Papelera",
                                    message: Self.describe(error) + " No se ha borrado nada; te queda «Eliminar del disco».")
                }
            }
            await refresh()
        }
    }

    /// Corrige título y artista a mano. Refresca la tabla, el detalle abierto y la cabecera de Backing (`study.reload()`
    /// relee `project.json`; no toca el estado de estudio sin guardar). Devuelve `false` si no se pudo guardar.
    @discardableResult
    func updateSongInfo(id: UUID, title: String, artist: String) async -> Bool {
        guard let library else { return false }
        do {
            try await library.updateSongInfo(id: id, title: title, artist: artist)
        } catch LibraryError.emptyTitle {
            notice = Notice(title: "Falta el título", message: "El título no puede quedar vacío.")
            return false
        } catch { notify("No se pudo guardar el título", error); return false }
        if let d = detail, d.id == id, let p = try? ProjectFile.load(folder: d.folder) {
            detail = ProjectDetail(project: p, folder: d.folder, stems: d.stems)
        }
        if study?.projectID == id { study?.reload() }
        await refresh()
        return true
    }

    // MARK: Ajustes

    func saveProfile() {
        do { try profileStore.save(profile) } catch { notify("No se pudo guardar el perfil", error) }
    }

    func setSampleRate(_ hz: Double) {
        profile.workingSampleRate = hz
        saveProfile()
    }

    func pickNewFolder() {
        let panel = NSOpenPanel()
        panel.title = "Carpeta de proyectos"
        panel.prompt = "Elegir"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = profile.projectsFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if url.standardizedFileURL != profile.projectsFolder?.standardizedFileURL { pendingFolder = url }
    }

    func relocate(to url: URL, move: Bool) {
        guard let library else { return }
        Task {
            do {
                if move {
                    relocationProgress = 0
                    try await library.relocate(to: url, mode: .move(progress: { [weak self] p in
                        Task { @MainActor in self?.relocationProgress = p }
                    }))
                } else {
                    try await library.relocate(to: url, mode: .pointOnly)
                }
            } catch LibraryError.workInProgress {
                notice = Notice(title: "Hay trabajo en curso",
                                message: "Espera a que terminen las separaciones y vuelve a cambiar la carpeta.")
            } catch { notify("No se pudo cambiar la carpeta", error) }
            relocationProgress = nil
            if let p = try? profileStore.load() { profile = p }
            await refresh()
        }
    }

    func downloadModel() {
        Task {
            do { _ = try await modelStore.ensureInstalled(Self.modelID) { _ in } } catch { notify("No se pudo descargar el modelo", error) }
        }
    }

    func deleteModel() {
        Task {
            do { try await modelStore.delete(Self.modelID) } catch { notify("No se pudo borrar el modelo", error) }
            modelsBytes = await modelStore.diskUsage()
        }
    }

    func upsertGuitar(_ g: OwnedGuitar) {
        if let i = profile.guitars.firstIndex(where: { $0.id == g.id }) { profile.guitars[i] = g } else { profile.guitars.append(g) }
        if g.isDefault { profile.setDefaultGuitar(g.id) }
        saveProfile()
    }

    func deleteGuitar(_ id: UUID) {
        profile.guitars.removeAll { $0.id == id }
        saveProfile()
    }

    func notify(_ title: String, _ error: Error) {
        notice = Notice(title: title, message: Self.describe(error))
    }

    static func describe(_ error: Error) -> String {
        switch error as? LibraryError {
        case .busy?: return "El tema está ocupado (separándose o reconvirtiéndose)."
        case .workInProgress?: return "Hay una separación en curso o en cola."
        case .unsafeDeletion?: return "La carpeta del tema no es un proyecto válido de la biblioteca; no se ha borrado nada."
        case .projectNotFound?: return "No se encuentra el proyecto en la carpeta."
        case .duplicate?: return "Ese tema ya está en la biblioteca."
        default: return error.localizedDescription
        }
    }
}

/// Procesos descendientes de la app (los que lanzaron los runners). Solo toca los nuestros: `proc_listpids` por padre.
enum ChildProcesses {
    /// Pids vivos (sin zombis) que descienden de `root`.
    static func descendants(of root: pid_t = getpid()) -> [pid_t] {
        var result: [pid_t] = []
        var frontier = [root]
        while let parent = frontier.popLast() {
            var buf = [pid_t](repeating: 0, count: 256)
            let bytes = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(parent), &buf, Int32(buf.count * MemoryLayout<pid_t>.size))
            guard bytes > 0 else { continue }
            for pid in buf.prefix(Int(bytes) / MemoryLayout<pid_t>.size) where pid > 0 {
                var info = proc_bsdshortinfo()
                let n = proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdshortinfo>.size))
                if n > 0, info.pbsi_status == UInt32(SZOMB) { continue }
                result.append(pid)
                frontier.append(pid)
            }
        }
        return result
    }

    /// Espera hasta `waiting` s a que no quede ningún descendiente; pasados `killAfter` s manda SIGKILL a los que queden.
    static func terminateAll(waiting: TimeInterval, killAfter: TimeInterval) {
        let start = Date()
        var killed = false
        while Date().timeIntervalSince(start) < waiting {
            let alive = descendants()
            if alive.isEmpty { return }
            if !killed, Date().timeIntervalSince(start) >= killAfter {
                for pid in alive { kill(pid, SIGKILL) }
                killed = true
            }
            usleep(50_000)
        }
        for pid in descendants() { kill(pid, SIGKILL) }
    }
}
