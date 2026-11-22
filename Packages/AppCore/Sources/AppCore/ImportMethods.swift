import Foundation
import SourceKit
import Store

/// Diálogos nativos que pone el anfitrión Swift de Windows (otra parte del paso 8); el núcleo no los implementa.
public protocol HostServices: Sendable, HiddenPageLoading {
    /// Selector de fichero; `types` son extensiones sin punto (`["wav","flac","mp3"]`). `nil` si se cancela.
    func pickFile(types: [String]) async -> URL?
    /// Selector de varios ficheros; `[]` si se cancela. Tiene versión por omisión (uno solo) en la extensión.
    func pickFiles(types: [String]) async -> [URL]
    /// Selector de carpeta. `nil` si se cancela.
    func pickFolder() async -> URL?
    /// Selector de carpeta que abre en `initial` (la carpeta de proyectos actual o la propuesta del primer arranque).
    /// Por omisión, sin carpeta inicial.
    func pickFolder(initial: URL?) async -> URL?
    /// Aviso de que la carpeta de proyectos cambió en caliente: el anfitrión vuelve a servirla como `mediaBase`.
    /// `false` si no pudo (la página recarga sus medios con la carpeta vieja).
    func projectsFolderChanged(_ url: URL) async -> Bool
    /// Diálogo de guardar (8.7: exportar a Guitar Pro); `types` son extensiones sin punto. `nil` si se cancela.
    func saveFile(suggestedName: String, types: [String]) async -> URL?
    /// Abre una URL con la aplicación del sistema para su esquema. `false` si nada la abre (p. ej. `spotify:` sin la app).
    func openURL(_ url: URL) async -> Bool
    /// Vista previa visible (W2-H): panel nativo con la página `url` colocado sobre la ventana en `rect` (píxeles CSS de la
    /// página; el anfitrión aplica la escala del monitor). Llamarlo de nuevo cambia la posición y, si `url` cambió, navega.
    /// `false` si el anfitrión no tiene vista previa (por omisión).
    func showPreview(url: URL, rect: PreviewRect) async -> Bool
    /// Oculta el panel y detiene su página. Idempotente; seguro sin vista previa creada.
    func hidePreview() async
}

/// Rectángulo en píxeles CSS de la página (origen arriba a la izquierda del área de la página).
public struct PreviewRect: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public extension HostServices {
    /// Selector de varios ficheros (L-F5: el del Mac permite selección múltiple). Por omisión, uno solo.
    func pickFiles(types: [String]) async -> [URL] { await pickFile(types: types).map { [$0] } ?? [] }
    func pickFolder(initial: URL?) async -> URL? { await pickFolder() }
    func projectsFolderChanged(_ url: URL) async -> Bool { true }
    func saveFile(suggestedName: String, types: [String]) async -> URL? { nil }
    func openURL(_ url: URL) async -> Bool { false }
    func showPreview(url: URL, rect: PreviewRect) async -> Bool { false }
    func hidePreview() async {}
    /// Navegador oculto (W2-G, `TabSongsterr.swift`). Por omisión no hay: la hoja de Songsterr da `unsupported`.
    func load(url: URL, userAgent: String?, readyScript: String?, timeout: TimeInterval) async throws -> HiddenPage {
        throw HiddenPageError.unsupported
    }
}

struct ImportFileParams: Codable, Sendable { var path: String }
struct RenameParams: Codable, Sendable { var id: String; var title: String; var artist: String? }
struct RenameResult: Codable, Sendable {
    var id: String
    var title: String
    var artist: String?
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(artist, forKey: .artist)
    }
}
struct CancelResult: Codable, Sendable { var cancelled: Bool }
struct QueuedResult: Codable, Sendable { var queued: Bool }
struct RemovedResult: Codable, Sendable { var removed: Bool }
struct DeleteTakeParams: Decodable, Sendable { var id: String; var takeId: String }
struct CleanupInfoResult: Codable, Sendable { var bytes: Int64 }
struct CleanupResult: Codable, Sendable { var cleaned: Bool; var bytes: Int64 }
struct PickedFileResult: Codable, Sendable {
    var path: String?
    // `nil` se codifica como ausente; la página lo trata como null.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(path, forKey: .path)
    }
}
struct PickedFilesResult: Codable, Sendable { var paths: [String] }
struct OpenURLParams: Codable, Sendable { var urls: [String] }
struct OpenURLResult: Codable, Sendable { var opened: String? }
struct PreviewShowParams: Decodable, Sendable { var url: String; var x: Double; var y: Double; var width: Double; var height: Double }
struct PreviewShowResult: Codable, Sendable { var shown: Bool }
struct PreviewHideResult: Codable, Sendable { var hidden: Bool }
struct ChosenFolderResult: Codable, Sendable {
    var path: String?
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(path, forKey: .path)
    }
}
struct RelocateParams: Codable, Sendable { var path: String; var mode: String }
struct RelocateProgress: Codable, Sendable { var fraction: Double }
struct RelocateResult: Codable, Sendable { var path: String; var mediaRemapped: Bool }
struct PickedFolderResult: Codable, Sendable {
    var path: String?
    var restartRequired: Bool
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(path, forKey: .path)
        try c.encode(restartRequired, forKey: .restartRequired)
    }
}

extension JobEngine {
    /// Motor con el perfil, el índice y los servicios que toca según `options` (`--support-dir` o los del sistema).
    static func make(options: LaunchOptions, root: ProjectsRoot, services: JobServices?) -> JobEngine {
        let support = options.supportDir
        let profile = support.map { ProfileStore(url: $0.appendingPathComponent("profile.json")) } ?? ProfileStore()
        #if os(Windows)
        let indexName = "Library.json"
        #else
        let indexName = "Library.store"
        #endif
        return JobEngine(root: root, profileStore: profile, indexURL: support?.appendingPathComponent(indexName),
                         services: { services ?? JobServices.production(supportDir: support) })
    }
}

extension Bridge {
    /// Detiene la cola y cancela lo que corre, con tope de 3 s (cierre de la app). Se puede llamar desde cualquier hilo
    /// que no sea el de la interfaz si hay que esperar; mejor usar `shutdownAsync()` desde código async.
    /// Primero cierra la tablatura y el estudio (guarda `project.json` y suelta el reproductor, en el hilo principal) y luego cancela la cola.
    /// Si se llama desde el hilo principal, el cierre del estudio no puede avanzar hasta que la espera acabe: usa `shutdownAsync()`.
    public func shutdown() {
        let box = ShutdownWaiter()
        Task.detached {
            await self.shutdownAsync()
            box.signal()
        }
        box.wait(timeout: JobEngine.shutdownBudget + 0.5)
    }

    /// Cierra y suelta los ficheros de proyecto abiertos (Montaje, visor de tomas, tablatura, estudio y, con él, Grabar).
    func closeProjectFiles() async {
        await closeMontage()
        await closeTakeView()
        await closeTab()
        await closeStudy()
    }

    public func shutdownAsync() async {
        // Primero se corta lo que descarga o lee (yt-dlp, ffmpeg); en Windows los hijos que sigan vivos mueren con el
        // job object «kill on close» de `ChildProcess` al salir el proceso (equivale a `ChildProcesses.terminateAll`).
        for hook in shutdownHooks { await hook() }
        await closeMontage()  // W2-E2: guarda el montaje y para su relevo al cerrar la ventana (los dos anfitriones)
        await closeTakeView()   // W2-V: suelta la salida del visor de tomas
        await closeTab()
        await closeStudy()
        await jobs.shutdown()
    }

    /// Abre la biblioteca y re-encola lo que quedó `queued`/`running` en la sesión anterior. El anfitrión puede llamarlo
    /// al arrancar; si no, se hace con el primer método de trabajo.
    public func start() { Task { [jobs] in await jobs.start() } }

    func registerImportMethods(root: ProjectsRoot, options: LaunchOptions) {
        let jobs = self.jobs
        jobs.setSinks(
            job: { [weak self] j in self?.emit("jobs.progress", j) },
            changed: { [weak self] in self?.emit("library.changed", Empty()) })

        @Sendable func uuid(_ s: String) throws -> UUID {
            guard let id = UUID(uuidString: s) else {
                throw RPCError(code: "bad-params", message: "«id» no es un UUID.")
            }
            return id
        }

        router.register("import.file") { (p: ImportFileParams) in try await jobs.importFile(path: p.path) }
        router.register("jobs.list") { (_: Empty) in JobsListResult(jobs: jobs.list()) }
        router.register("jobs.cancel") { (p: ProjectIDParams) in
            CancelResult(cancelled: try await jobs.cancel(id: try uuid(p.id)))
        }
        router.register("library.separate") { (p: ProjectIDParams) in
            try await jobs.separate(id: try uuid(p.id))
            return QueuedResult(queued: true)
        }
        router.register("library.rename") { (p: RenameParams) in
            let r = try await jobs.rename(id: try uuid(p.id), title: p.title, artist: p.artist)
            return RenameResult(id: p.id, title: r.title, artist: r.artist)
        }
        // `library.cleanupInfo` y `library.cleanup` (con `id` nulo = toda la biblioteca): `SettingsMethods.swift` (W2-A).
        router.register("library.deleteTake") { [weak self] (p: DeleteTakeParams) in
            let id = try uuid(p.id)
            try await jobs.deleteTake(id: id, takeID: try uuid(p.takeId))
            await self?.studyService.reloadIfOpen(id)
            return RemovedResult(removed: true)
        }
        router.register("library.trash") { (p: ProjectIDParams) in
            try await jobs.remove(id: try uuid(p.id), permanently: false)
            return RemovedResult(removed: true)
        }
        router.register("library.delete") { (p: ProjectIDParams) in
            try await jobs.remove(id: try uuid(p.id), permanently: true)
            return RemovedResult(removed: true)
        }

        router.register("host.pickAudioFile") { [weak self] (_: Empty) in
            guard let host = self?.host else { throw Bridge.noHost }
            let url = await host.pickFile(types: Array(JobEngine.importExtensions).sorted())
            return PickedFileResult(path: url?.path)
        }
        router.register("host.pickAudioFiles") { [weak self] (_: Empty) in
            guard let host = self?.host else { throw Bridge.noHost }
            let urls = await host.pickFiles(types: Array(JobEngine.importExtensions).sorted())
            return PickedFilesResult(paths: urls.map(\.path))
        }
        // «Oír en Spotify» (L-F3): como `listen` del Mac, se prueba cada URL en orden (`spotify:track:<id>` y luego la web)
        // y se queda con la primera que abre. Solo esquemas spotify, http y https.
        router.register("host.openURL") { [weak self] (p: OpenURLParams) in
            guard let host = self?.host else { throw Bridge.noHost }
            for text in p.urls {
                guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
                      Bridge.openableSchemes.contains(scheme) else { continue }
                if await host.openURL(url) { return OpenURLResult(opened: text) }
            }
            return OpenURLResult(opened: nil)
        }
        // Vista previa de Songsterr (W2-H): solo https y songsterr.com; sin anfitrión o sin vista previa, `unsupported`.
        router.register("host.preview.show") { [weak self] (p: PreviewShowParams) in
            guard let url = URL(string: p.url), url.scheme == "https", SongsterrReader.isSongsterrHost(url.host) else {
                throw RPCError(code: "bad-params", message: "«url» debe ser una página https de songsterr.com.")
            }
            guard [p.x, p.y, p.width, p.height].allSatisfy(\.isFinite), p.width >= 1, p.height >= 1 else {
                throw RPCError(code: "bad-params", message: "El rectángulo de la vista previa no es válido.")
            }
            guard let host = self?.host else { throw Bridge.noHost }
            let rect = PreviewRect(x: p.x, y: p.y, width: p.width, height: p.height)
            guard await host.showPreview(url: url, rect: rect) else {
                throw RPCError(code: "unsupported", message: "El anfitrión no tiene vista previa.")
            }
            return PreviewShowResult(shown: true)
        }
        router.register("host.preview.hide") { [weak self] (_: Empty) in
            await self?.host?.hidePreview()
            return PreviewHideResult(hidden: true)
        }
        // B2: solo elegir la carpeta (abre en la actual); aplicarla es `library.relocate`.
        router.register("host.chooseFolder") { [weak self] (_: Empty) in
            guard let host = self?.host else { throw Bridge.noHost }
            let picked = await self?.requestFolder(host, initial: root.url)
            return ChosenFolderResult(path: picked?.path)
        }
        // B2: cambiar la carpeta en caliente. `mode`: «move» (copia, verifica y borra el original) o «point» (solo apunta).
        router.register("library.relocate") { [weak self] (p: RelocateParams) in
            guard p.mode == "move" || p.mode == "point" else {
                throw RPCError(code: "bad-params", message: "«mode» debe ser «move» o «point».")
            }
            guard !p.path.isEmpty else { throw RPCError(code: "bad-params", message: "«path» está vacío.") }
            let url = URL(fileURLWithPath: p.path)
            // Con trabajo o grabación en curso se rechaza sin cerrar nada; si no, se sueltan los ficheros del tema abierto
            // (estudio, visor de tomas, Montaje, tablatura) ANTES de mover o reapuntar (decisión de Jorge).
            let recording = await self?.recordService?.isBusy ?? false
            guard jobs.list().isEmpty, !recording else { throw JobEngine.map(LibraryError.workInProgress) }
            await self?.closeProjectFiles()
            do {
                try await jobs.relocate(to: url, move: p.mode == "move") { [weak self] f in
                    self?.emit("library.relocateProgress", RelocateProgress(fraction: f))
                }
            } catch { throw JobEngine.map(error) }
            // La página pide los medios por `mediaBase`: el anfitrión lo remapea a la carpeta nueva.
            let remapped = await self?.host?.projectsFolderChanged(url) ?? true
            self?.emit("library.relocated", RelocateResult(path: url.path, mediaRemapped: remapped))
            return RelocateResult(path: url.path, mediaRemapped: remapped)
        }
        let profile = options.supportDir.map { ProfileStore(url: $0.appendingPathComponent("profile.json")) } ?? ProfileStore()
        router.register("host.pickProjectsFolder") { [weak self] (_: Empty) in
            guard let host = self?.host else { throw Bridge.noHost }
            // Como `chooseFirstRunFolder` del Mac: abre en la propuesta (`~/Music/ToneForge`, creada antes).
            let proposed = self?.proposedFolder
            if let proposed { try? FileManager.default.createDirectory(at: proposed, withIntermediateDirectories: true) }
            guard let url = await self?.requestFolder(host, initial: root.url ?? proposed) else {
                return PickedFolderResult(path: nil, restartRequired: false)
            }
            let firstRun = root.url == nil
            let r = try Bridge.saveProjectsFolder(url, profile: profile)
            guard firstRun else { return r }
            // B3: primer arranque sin reiniciar: la carpeta se adopta, la biblioteca arranca y el anfitrión sirve los medios.
            root.url = url
            await jobs.start()
            _ = await host.projectsFolderChanged(url)
            return PickedFolderResult(path: url.path, restartRequired: false)
        }
    }

    /// Único punto donde se pide un selector de carpeta al anfitrión (`host.chooseFolder` y `host.pickProjectsFolder`).
    /// SOLO PARA PRUEBAS: si `TF_TEST_PICK_FOLDER` está definida y no vacía, se devuelve esa ruta como si el usuario la
    /// hubiera elegido, sin abrir el diálogo; el resto del camino es el normal. Sin la variable, todo igual que siempre.
    func requestFolder(_ host: any HostServices, initial: URL?) async -> URL? {
        if let path = environment()[Bridge.testPickFolderVariable], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return await host.pickFolder(initial: initial)
    }

    /// Carpeta que se propone en el primer arranque (`AppModel.proposedFolder` del Mac: `~/Music/ToneForge`).
    static var defaultProposedFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music", isDirectory: true).appendingPathComponent("ToneForge", isDirectory: true)
    }

    /// Esquemas que `host.openURL` deja abrir fuera de la aplicación.
    static let openableSchemes: Set<String> = ["spotify", "http", "https"]

    static var noHost: RPCError {
        RPCError(code: "unsupported", message: "El anfitrión no ofrece diálogos nativos.")
    }

    /// Como el Mac en la primera ejecución: crea la carpeta y la guarda en `profile.json` (el resto del perfil se conserva).
    static func saveProjectsFolder(_ url: URL, profile store: ProfileStore) throws -> PickedFolderResult {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            var profile = (try? store.load()) ?? EquipmentProfile()
            profile.projectsFolder = url
            try store.save(profile)
        } catch {
            throw RPCError(code: "internal", message: "No se pudo guardar la carpeta de proyectos: \(error)")
        }
        return PickedFolderResult(path: url.path, restartRequired: true)
    }
}

/// Espera síncrona acotada a que termine el cierre.
private final class ShutdownWaiter: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    func signal() { semaphore.signal() }
    func wait(timeout: TimeInterval) { _ = semaphore.wait(timeout: .now() + timeout) }
}

/// Guardado del estudio por la `Library` de la cola (la abre si hace falta): se serializa con las escrituras de la cola.
struct QueueStudyStore: StudyStoring {
    let jobs: JobEngine
    func saveStudy(id: UUID, study: StudyState, sections: [Section]) async throws {
        try await jobs.library().saveStudy(id: id, study: study, sections: sections)
    }
    func saveGuitarNames(id: UUID, names: [GuitarRole: String]) async throws {
        try await jobs.library().saveGuitarNames(id: id, names: names)
    }
    func saveGuitarStereoSplit(id: UUID, _ on: Bool) async throws -> GuitarOptions {
        try await jobs.library().saveGuitarStereoSplit(id: id, on)
    }
}
