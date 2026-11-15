import AppKit
import Foundation
import ModelKit
import Observation
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
            default: break
            }
            i += 1
        }
    }
}
#endif

enum AppSection: Hashable { case library, backing, settings }
enum SettingsTab: String, CaseIterable, Identifiable {
    case audio = "Audio", video = "Cámara y vídeo", device = "Pedalera y TONE3000", library = "Biblioteca y equipo"
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

struct CleanupRequest: Identifiable {
    let id = UUID()
    let projectID: UUID?   // nil = todos
    let title: String
    let bytes: Int64
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
    /// Flex Prime conectada por USB (lista de salidas de CoreAudio).
    let flexPrime = FlexPrimeMonitor()

    // Datos
    var profile = EquipmentProfile()
    var needsFolder = false
    var entries: [LibraryEntryInfo] = []
    var separationProgress: [UUID: Double] = [:]
    var failures: [UUID: String] = [:]
    var imports: [ImportItem] = []
    var modelState: ModelState = .notInstalled
    var usage: DiskUsageReport?
    var modelsBytes: Int64 = 0

    // Diálogos
    var duplicateID: UUID?
    var notice: Notice?
    var cleanupRequest: CleanupRequest?
    var pendingFolder: URL?
    var relocationProgress: Double?

    @ObservationIgnored let supportDir: URL
    @ObservationIgnored let profileStore: ProfileStore
    @ObservationIgnored private var masterSaveTask: Task<Void, Never>?
    @ObservationIgnored let modelStore: ModelStore
    @ObservationIgnored let studyAnalyzer: AppStudyAnalyzer
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
        profileStore = ProfileStore(url: dir.appendingPathComponent("profile.json"))
        modelStore = ModelStore(root: dir.appendingPathComponent("Models", isDirectory: true),
                                bundleResourceDirectory: Bundle.main.resourceURL)
        studyAnalyzer = AppStudyAnalyzer(modelStore: modelStore)
    }

    // MARK: Arranque

    func start() async {
        guard !started else { return }
        started = true
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        do { profile = try profileStore.load() } catch { notify("Perfil ilegible", error) }
        listenToModels()

        #if DEBUG
        for zip in options.installModelFrom {
            let id = zip.lastPathComponent.contains("BeatThis") ? ModelCatalog.beatsBeatThis.id : Self.modelID
            do { _ = try await modelStore.install(id, fromArchive: zip) } catch { notify("No se pudo instalar el modelo", error) }
        }
        if let f = options.projectsFolder {
            profile.projectsFolder = f
            saveProfile()
        }
        #endif

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
                              levelMeter: AppStemLevelMeter(), analyzer: studyAnalyzer)
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
        case "detail-first": if let first = entries.first { await open(first.id) }
        case "backing":
            let match = entries.first { e in options.project.map { e.folderName == $0 || e.title == $0 } ?? true }
            backingTarget = match?.id
            section = .backing
        default: break
        }
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
            guard section == .backing else { return }
            let session = StudySession(project: project, folder: folder, library: library, analysisState: state)
            study = session
            let controller = BackingController(session: session, masterGainDB: profile.masterGainDB)
            controller.onMasterChange = { [weak self] dB in self?.setMasterGain(dB) }
            backing = controller
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

    /// Al salir de la app: guarda lo pendiente de forma síncrona (acotada a 2 s).
    func flushForTermination() {
        backing?.stop()
        if let t = masterSaveTask { t.cancel(); masterSaveTask = nil; saveProfile() }
        guard let library, let s = study else { return }
        let (id, study, sections) = (s.projectID, s.study, s.sections)
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            try? await library.saveStudy(id: id, study: study, sections: sections)
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
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
            if let window = NSApp.windows.first(where: { $0.contentView != nil }), let view = window.contentView {
                window.setContentSize(CGSize(width: 1440, height: 900))
                view.layoutSubtreeIfNeeded()
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                }
            }
            NSApp.terminate(nil)
        }
    }

    /// Estado inicial de Backing para capturas (sin reproducir).
    private func applyLaunchOptions(to session: StudySession) {
        switch options.analysisState {
        case "analyzing"?: session.setAnalysisState(.analyzing)
        case "failed"?: session.setAnalysisState(.failed("Sin red para descargar Beat This!"))
        case "missing"?: session.setAnalysisState(.missing)
        default: break
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
        case .projectNotFound?: return "No se encuentra el proyecto en la carpeta."
        case .duplicate?: return "Ese tema ya está en la biblioteca."
        default: return error.localizedDescription
        }
    }
}
