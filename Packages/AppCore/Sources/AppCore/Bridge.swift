import Foundation
import SourceKit
import Store

struct AppInfo: Codable, Sendable {
    struct Launch: Codable, Sendable {
        var screen: String?
        var project: String?
        var snapshot: Bool
    }
    var version: String
    var platform: String
    var mediaBase: String
    var projectsFolder: String?
    var launch: Launch
}

/// Puente entre la página (WebView2) y el núcleo Swift: JSON entrante -> `Router` -> `send`.
public final class Bridge: @unchecked Sendable {
    public static let version = "0.1.0"

    public let router = Router()
    private let options: LaunchOptions
    private let mediaBase: String
    private let projects: URL?
    private let lock = NSLock()
    private var _send: @Sendable (String) -> Void = { _ in }
    /// Cola de trabajos y biblioteca viva (8.3a, `JobQueue.swift`).
    let jobs: JobEngine
    /// Backing: tema abierto y reproductor (8.5, `StudyMethods.swift`).
    let studyService: StudyService
    /// Herramientas externas y descargas por enlace (8.3b, `LinkMethods.swift`); nil = las de producción.
    let link: ExternalSources?
    /// Buscador de Spotify (`link.search`); nil = el real (clave en `.env`).
    let spotify: (any SpotifySearching)?
    /// Tablatura (8.7, `TabService.swift`).
    let tabService: TabService
    private var _host: (any HostServices)?

    /// Diálogos nativos; los pone el anfitrión (8.3a, `ImportMethods.swift`). Sin él, `host.*` da `unsupported`.
    public var host: (any HostServices)? {
        get { lock.lock(); defer { lock.unlock() }; return _host }
        set { lock.lock(); _host = newValue; lock.unlock() }
    }

    /// La pone el anfitrión; se puede llamar desde cualquier hilo.
    public var send: @Sendable (String) -> Void {
        get { lock.lock(); defer { lock.unlock() }; return _send }
        set { lock.lock(); _send = newValue; lock.unlock() }
    }

    /// Carpeta que el anfitrión sirve como `mediaBase` (la de proyectos).
    public var mediaFolder: URL? { projects }

    /// Solo tests: sustituye al explorador.
    private let revealOverride: (@Sendable (URL) throws -> Void)?

    public convenience init(options: LaunchOptions, mediaBase: String) throws {
        try self.init(options: options, mediaBase: mediaBase, reveal: nil)
    }

    init(options: LaunchOptions, mediaBase: String, reveal: (@Sendable (URL) throws -> Void)?,
         services: JobServices? = nil, link: ExternalSources? = nil, tab: TabServices? = nil,
         spotify: (any SpotifySearching)? = nil) throws {
        self.link = link
        self.spotify = spotify
        self.revealOverride = reveal
        self.options = options
        self.mediaBase = mediaBase
        let folder = Bridge.resolveProjectsFolder(options)
        self.projects = folder
        self.jobs = JobEngine.make(options: options, root: folder, services: services)
        // El estudio guarda por la misma `Library` que la cola: un solo escritor de `project.json` (8.3a).
        let queue = self.jobs
        self.studyService = StudyService(options: options, root: folder, storeFactory: { _ in QueueStudyStore(jobs: queue) })
        // 8.5b: análisis y guitarras del tema abierto (`StudyEdits.swift`).
        studyService.attach(jobs: queue)
        let supportDir = options.supportDir
        self.tabService = TabService(studyService: studyService, services: { tab ?? TabServices.production(supportDir: supportDir) },
                                     store: QueueTabStore(jobs: queue))
        registerMethods()
    }

    /// `--projects-folder`; si no, la del perfil (`profile.json` dentro de `--support-dir`, o el sitio por defecto).
    static func resolveProjectsFolder(_ o: LaunchOptions) -> URL? {
        if let f = o.projectsFolder { return f }
        let store = o.supportDir.map { ProfileStore(url: $0.appendingPathComponent("profile.json")) } ?? ProfileStore()
        return (try? store.load())?.projectsFolder
    }

    /// Mensaje JSON de la página. No bloquea: el trabajo va en una Task y la respuesta sale por `send`.
    public func receive(_ json: String) {
        Task { [router] in
            let response = await router.handle(json)
            self.send(response)
        }
    }

    /// Envía un evento a la página.
    public func emit<T: Encodable>(_ event: String, _ payload: T) {
        if let m = Router.eventMessage(event, payload) { send(m) }
    }

    private func registerMethods() {
        let info = AppInfo(
            version: Bridge.version, platform: Bridge.platform, mediaBase: mediaBase,
            projectsFolder: projects?.path,
            launch: .init(screen: options.screen, project: options.project, snapshot: options.snapshot != nil))
        router.register("app.info") { (_: Empty) in info }

        let root = projects
        let jobs = self.jobs
        router.register("library.list") { (_: Empty) -> LibraryListResult in
            jobs.overlay(try Bridge.service(root).list())
        }
        registerImportMethods(root: projects, options: options)
        registerLinkMethods(root: projects, options: options)
        studyService.setSink { [weak self] in self?.send($0) }
        studyService.register(on: router)
        tabService.hostProvider = { [weak self] in self?.host }
        tabService.setSink { [weak self] in self?.send($0) }
        tabService.register(on: router)
        let opener = revealOverride
        router.register("library.reveal") { (p: ProjectIDParams) -> RevealResult in
            guard let id = UUID(uuidString: p.id) else {
                throw RPCError(code: "bad-params", message: "«id» no es un UUID.")
            }
            let folder = try Bridge.service(root).folder(id: id)
            guard FileManager.default.fileExists(atPath: folder.path) else {
                throw RPCError(code: "not-found", message: "La carpeta del tema no existe.")
            }
            try (opener ?? Bridge.openFolder)(folder)
            return RevealResult(revealed: true)
        }
        router.register("library.project") { (p: ProjectIDParams) -> ProjectDetailResult in
            guard let id = UUID(uuidString: p.id) else {
                throw RPCError(code: "bad-params", message: "«id» no es un UUID.")
            }
            return try Bridge.service(root).detail(id: id)
        }
    }

    /// Abre la carpeta en el explorador del sistema. Sustituible en tests.
    static func openFolder(_ url: URL) throws {
        let p = Process()
        #if os(Windows)
        p.executableURL = URL(fileURLWithPath: "C:\\Windows\\explorer.exe")
        #else
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        #endif
        p.arguments = [url.path]
        do { try p.run() } catch {
            throw RPCError(code: "internal", message: "No se pudo abrir la carpeta: \(error)")
        }
    }

    static func service(_ root: URL?) throws -> LibraryService {
        guard let root else {
            throw RPCError(code: "no-projects-folder", message: "No hay carpeta de proyectos configurada.")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw RPCError(code: "no-projects-folder", message: "La carpeta de proyectos no existe: \(root.path)")
        }
        return LibraryService(root: root)
    }

    static var platform: String {
        #if os(Windows)
        "windows"
        #else
        "macos"
        #endif
    }
}
