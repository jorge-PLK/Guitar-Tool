import Foundation
import Store

/// Un trabajo vivo (o su último mensaje) para la página: payload de `jobs.progress` y elemento de `jobs.list`
/// (campos exactos en `Temp/win/step8-contract.md`, «8.3a»).
public struct JobInfo: Codable, Sendable, Equatable {
    /// Id del tema; para `import` (y la futura `download`) una clave opaca `import-N`.
    public var id: String
    public var title: String
    /// `import`, `separation`, `guitars`, `analysis` (`download` reservada para la parte siguiente).
    public var stage: String
    /// `queued`, `running`, `done`, `failed`, `cancelled`.
    public var state: String
    public var fraction: Double?
    public var text: String
    public var error: String?
}

struct JobsListResult: Codable, Sendable { var jobs: [JobInfo] }

/// Núcleo de la cola: envuelve `Store.Library` (que ya trae la cola de uno en uno, el análisis, la Papelera y la
/// recuperación al arrancar), traduce sus eventos a `JobInfo` y lleva el estado en vivo para `library.list`.
/// La cola es una sola para todo: un trabajo de descarga (parte siguiente) llamará a `importFile` al terminar y
/// entrará en la misma cola; su etapa `download` precede a `import` con la misma clave.
final class JobEngine: @unchecked Sendable {
    /// Como mucho 4 mensajes de fracción por segundo y trabajo (encargo 8.3a).
    static let progressInterval: TimeInterval = 0.25

    static let importExtensions: Set<String> = ["wav", "flac", "mp3"]

    let root: ProjectsRoot
    private var relocating = false
    private let profileStore: ProfileStore
    private let indexURL: URL?
    private let services: @Sendable () -> JobServices
    private let now: @Sendable () -> Date

    private let lock = NSLock()
    private var libraryTask: Task<Library, Error>?
    private var pump: Task<Void, Never>?
    private var live: [String: Live] = [:]
    private var order = 0
    private var importCounter = 0
    private var _emitJob: @Sendable (JobInfo) -> Void = { _ in }
    private var _emitChanged: @Sendable () -> Void = {}
    private var hasAnalyzer = false

    private struct Live {
        var info: JobInfo
        var order: Int
        var lastEmit: Date
        /// Tras separar viene el análisis (el analizador existe): no es el final del trabajo.
        var expectsAnalysis: Bool
    }

    init(root: ProjectsRoot, profileStore: ProfileStore, indexURL: URL?,
         services: @escaping @Sendable () -> JobServices, now: @escaping @Sendable () -> Date = { Date() }) {
        self.root = root
        self.profileStore = profileStore
        self.indexURL = indexURL
        self.services = services
        self.now = now
    }

    /// El anfitrión (Bridge) conecta aquí los envíos a la página.
    func setSinks(job: @escaping @Sendable (JobInfo) -> Void, changed: @escaping @Sendable () -> Void) {
        lock.withLock { _emitJob = job; _emitChanged = changed }
    }

    private func emitJob(_ j: JobInfo) { let f = lock.withLock { _emitJob }; f(j) }
    private func emitChanged() { let f = lock.withLock { _emitChanged }; f() }

    // MARK: Library perezosa

    /// Abre la biblioteca la primera vez: temporales huérfanos, índice, recuperación de lo interrumpido.
    func library() async throws -> Library {
        let root = try Bridge.service(root).root
        let task: Task<Library, Error> = lock.withLock {
            if let t = libraryTask { return t }
            let t = Task { [self] in try await self.openLibrary(root: root) }
            libraryTask = t
            return t
        }
        do { return try await task.value } catch {
            lock.withLock { libraryTask = nil }
            throw error
        }
    }

    private func openLibrary(root: URL) async throws -> Library {
        Library.removeOrphanTemporaries(in: root)
        let s = services()
        let index = try LibraryIndex.make(storeURL: indexURL)
        let lib = Library(root: root, profile: profileStore, index: index, importer: s.importer, separator: s.separator,
                          levelMeter: s.levelMeter, analyzer: s.analyzer, guitarSplitter: s.guitarSplitter)
        lock.withLock { hasAnalyzer = s.analyzer != nil }
        await lib.setFileReleaser { [weak self] id, files in await self?.releaseFiles(id, files) }
        let events = lib.events
        let pumpTask = Task { [self] in
            for await e in events { await self.handle(e, library: lib) }
        }
        lock.withLock { pump = pumpTask }
        _ = try await lib.rebuildIndex()
        _ = try await lib.recoverInterrupted()
        return lib
    }

    /// Arranca la biblioteca (y re-encola lo interrumpido) sin esperar a una petición. Sin carpeta, no hace nada.
    func start() async { _ = try? await library() }

    // MARK: Estado vivo

    func list() -> [JobInfo] {
        lock.withLock { live.values.sorted { $0.order < $1.order }.map(\.info) }
    }

    func stage(of id: String) -> String? { lock.withLock { live[id]?.info.stage } }

    /// `library.list` en vivo: `queued`/`running` según la cola si el tema tiene trabajo.
    func overlay(_ r: LibraryListResult) -> LibraryListResult {
        let snapshot = lock.withLock { live }
        guard !snapshot.isEmpty else { return r }
        var out = r
        for i in out.projects.indices {
            guard let j = snapshot[out.projects[i].id.uuidString]?.info else { continue }
            out.projects[i].separationState = j.state == "running" ? "running" : "queued"
            // Los fallos salen de la lista viva al instante (estado final); un tema en cola ya no arrastra el error viejo.
            out.projects[i].separationError = nil        }
        return out
    }

    private static func text(_ stage: String, state: String, fraction: Double?) -> String {
        switch (stage, state) {
        case ("import", _):
            return "Importando… \(Int(((fraction ?? 0) * 100).rounded())) %"
        case ("separation", "queued"): return "En cola"
        case ("separation", _): return "Separando… \(Int(((fraction ?? 0) * 100).rounded())) %"
        case ("guitars", _): return "Separando guitarras"
        case ("analysis", "queued"): return "En cola para análisis"
        case ("analysis", _): return "Analizando…"
        default: return ""
        }
    }

    /// Crea o actualiza un trabajo. Las fracciones sueltas se limitan a `progressInterval`; los cambios de
    /// etapa o estado salen siempre. Los estados finales emiten y sacan el trabajo de la lista viva. `force`: sale aunque
    /// solo cambie el texto (la conversión de vídeo que pasa a «se aplicará cuando el fichero original deje de estar en uso»).
    func update(_ id: String, title: String, stage: String, state: String, fraction: Double? = nil,
                error: String? = nil, expectsAnalysis: Bool? = nil, text: String? = nil, force: Bool = false) {
        let t = now()
        var toEmit: JobInfo?
        lock.withLock {
            var l = live[id] ?? Live(info: JobInfo(id: id, title: title, stage: stage, state: "queued", fraction: nil,
                                                  text: "", error: nil),
                                    order: { order += 1; return order }(), lastEmit: .distantPast, expectsAnalysis: false)
            let isNew = live[id] == nil
            let structural = isNew || force || l.info.stage != stage || l.info.state != state
            l.info.title = title
            l.info.stage = stage
            l.info.state = state
            l.info.fraction = fraction
            l.info.error = error
            l.info.text = text ?? Self.text(stage, state: state, fraction: fraction)
            if let e = expectsAnalysis { l.expectsAnalysis = e }
            let final = ["done", "failed", "cancelled"].contains(state)
            if final {
                live[id] = nil
                toEmit = l.info
            } else {
                if structural || t.timeIntervalSince(l.lastEmit) >= Self.progressInterval {
                    l.lastEmit = t
                    toEmit = l.info
                }
                live[id] = l
            }
        }
        if let toEmit { emitJob(toEmit) }
    }

    // MARK: Eventos de Library

    private func title(of id: UUID, library: Library) async -> String {
        if let t = lock.withLock({ live[id.uuidString]?.info.title }) { return t }
        let entries = (try? await library.entries()) ?? []
        guard let e = entries.first(where: { $0.id == id }) else { return "" }
        return [e.artist, e.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " - ")
    }

    /// Cada evento de `Library` también llega aquí (el estudio abierto refresca análisis y guitarras, 8.5b).
    private var _libraryObserver: (@Sendable (LibraryEvent) -> Void)?
    func setLibraryObserver(_ f: (@Sendable (LibraryEvent) -> Void)?) { lock.withLock { _libraryObserver = f } }
    /// Quien tenga abiertos ficheros de un proyecto los suelta aquí antes de que la biblioteca los sustituya o borre
    /// (`Library.FileReleaser`; NTFS, `MoveFileEx` error 5).
    private var _fileReleaser: Library.FileReleaser?
    func setFileReleaser(_ f: Library.FileReleaser?) { lock.withLock { _fileReleaser = f } }
    var fileReleaser: Library.FileReleaser? { lock.withLock { _fileReleaser } }
    func releaseFiles(_ id: UUID, _ files: [URL]) async {
        if let f = lock.withLock({ _fileReleaser }) { await f(id, files) }
    }

    func handle(_ e: LibraryEvent, library: Library) async {
        func key(_ id: UUID) -> String { id.uuidString }
        if let observer = lock.withLock({ _libraryObserver }) { observer(e) }
        switch e {
        case .separationQueued(let id):
            update(key(id), title: await title(of: id, library: library), stage: "separation", state: "queued")
            emitChanged()
        case .separationStarted(let id):
            update(key(id), title: await title(of: id, library: library), stage: "separation", state: "running", fraction: 0)
            emitChanged()
        case .separationProgress(let id, let p):
            update(key(id), title: await title(of: id, library: library), stage: "separation", state: "running",
                   fraction: min(max(p, 0), 1))
        case .separationFinished(let id):
            let analysis = lock.withLock { hasAnalyzer }
            let t = await title(of: id, library: library)
            if analysis {
                update(key(id), title: t, stage: "analysis", state: "queued", expectsAnalysis: true)
            } else {
                update(key(id), title: t, stage: "separation", state: "done", fraction: 1)
            }
            emitChanged()
        case .separationFailed(let id, let msg):
            update(key(id), title: await title(of: id, library: library), stage: "separation", state: "failed", error: msg)
            emitChanged()
        case .separationCancelled(let id):
            update(key(id), title: await title(of: id, library: library), stage: "separation", state: "cancelled")
            emitChanged()
        case .analysisQueued(let id):
            update(key(id), title: await title(of: id, library: library), stage: "analysis", state: "queued", expectsAnalysis: true)
        case .analysisStarted(let id):
            update(key(id), title: await title(of: id, library: library), stage: "analysis", state: "running")
        case .analysisFinished(let id):
            update(key(id), title: await title(of: id, library: library), stage: "analysis", state: "done", fraction: 1)
            emitChanged()
        case .analysisFailed(let id, let msg):
            update(key(id), title: await title(of: id, library: library), stage: "analysis", state: "failed", error: msg)
            emitChanged()
        case .guitarSplitQueued(let id):
            update(key(id), title: await title(of: id, library: library), stage: "guitars", state: "queued")
        case .guitarSplitStarted(let id):
            update(key(id), title: await title(of: id, library: library), stage: "guitars", state: "running")
        case .guitarSplitFinished(let id), .guitarSplitFailed(let id, _):
            var failure: String?
            if case .guitarSplitFailed(_, let m) = e { failure = m }
            let t = await title(of: id, library: library)
            if lock.withLock({ live[key(id)]?.expectsAnalysis }) == true {
                update(key(id), title: t, stage: "analysis", state: "queued")
            } else {
                update(key(id), title: t, stage: "guitars", state: failure == nil ? "done" : "failed", error: failure)
            }
            emitChanged()
        case .imported, .stemsMeasured, .trashed, .indexChanged, .cleaned, .relocated,
             .rateMigrationStarted, .rateMigrationFinished, .rateMigrationFailed:
            emitChanged()
        }
    }

    // MARK: Importar

    struct ImportResult: Codable, Sendable { var id: String; var duplicate: Bool }

    func importFile(path: String) async throws -> ImportResult {
        let url = URL(fileURLWithPath: path)
        guard Self.importExtensions.contains(url.pathExtension.lowercased()) else {
            throw RPCError(code: "unsupported", message: "Formato no admitido (wav, flac o mp3): \(url.lastPathComponent)")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RPCError(code: "not-found", message: "No existe el fichero: \(path)")
        }
        let lib = try await library()
        let key: String = lock.withLock { importCounter += 1; return "import-\(importCounter)" }
        let name = url.deletingPathExtension().lastPathComponent
        update(key, title: name, stage: "import", state: "running", fraction: 0)
        do {
            let id = try await lib.importSong(from: url) { [self] p in
                self.update(key, title: name, stage: "import", state: "running", fraction: min(max(p, 0), 1))
            }
            update(key, title: name, stage: "import", state: "done", fraction: 1)
            emitChanged()
            return ImportResult(id: id.uuidString, duplicate: false)
        } catch LibraryError.duplicate(let existing) {
            update(key, title: name, stage: "import", state: "done", fraction: 1)
            return ImportResult(id: existing.uuidString, duplicate: true)
        } catch {
            let rpc = Self.map(error)
            update(key, title: name, stage: "import", state: "failed", error: rpc.message)
            throw rpc
        }
    }

    // MARK: Operaciones sobre un tema

    func separate(id: UUID) async throws {
        let lib = try await library()
        do { try await lib.separate(id: id) } catch { throw Self.map(error) }
    }

    /// `true` si había una separación que cancelar.
    func cancel(id: UUID) async throws -> Bool {
        let lib = try await library()
        guard stage(of: id.uuidString) == "separation" else { return false }
        do { try await lib.cancelSeparation(id: id) } catch { throw Self.map(error) }
        return true
    }

    func rename(id: UUID, title: String, artist: String?) async throws -> (title: String, artist: String?) {
        let lib = try await library()
        do { try await lib.updateSongInfo(id: id, title: title, artist: artist) } catch { throw Self.map(error) }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        emitChanged()
        return (t, (a?.isEmpty ?? true) ? nil : a)
    }

    /// `Library.deleteTake` (carpeta de la toma y su rastro en `project.json`), como `ProjectRecordingsView.delete`.
    func deleteTake(id: UUID, takeID: UUID) async throws {
        let lib = try await library()
        do { try await lib.deleteTake(projectID: id, takeID: takeID) } catch let e as LibraryError {
            if case .takeNotFound = e { throw RPCError(code: "not-found", message: "No hay ninguna toma con id \(takeID.uuidString).") }
            throw Self.map(e)
        } catch { throw Self.map(error) }
        emitChanged()
    }

    /// Guarda el estado de grabación por la `Library` de la cola (`library.markBest`).
    func saveRecording(id: UUID, _ recording: RecordingState) async throws {
        let lib = try await library()
        do { try await lib.saveRecording(id: id, recording) } catch { throw Self.map(error) }
        emitChanged()
    }

    /// Bytes que borraría «Limpiar…» en el tema: `Library.diskUsage` (`regenerableBytes`), como `AppModel.requestCleanup`.
    func cleanupBytes(id: UUID) async throws -> Int64 {
        let lib = try await library()
        return await lib.diskUsage().projects.first { $0.id == id }?.regenerableBytes ?? 0
    }

    /// `Library.cleanup(id:)` (tomas descartadas y stems regenerables), como `AppModel.performCleanup`.
    func cleanup(id: UUID) async throws -> Int64 {
        let lib = try await library()
        do { return try await lib.cleanup(id: id) } catch let e as LibraryError {
            if case .busy = e { throw RPCError(code: "busy", message: "El tema está ocupado (separando o migrando).") }
            throw Self.map(e)
        } catch { throw Self.map(error) }
    }

    /// Papelera o borrado definitivo, con los mismos mensajes que el Mac cuando falla.
    func remove(id: UUID, permanently: Bool) async throws {
        let lib = try await library()
        do {
            if permanently { try await lib.deleteProject(id: id) } else { try await lib.trashProject(id: id) }
        } catch let e as LibraryError {
            switch e {
            case .projectNotFound, .unsafeDeletion: throw Self.map(e)
            default: throw Self.removalFailure(e, permanently: permanently)
            }
        } catch { throw Self.removalFailure(error, permanently: permanently) }
        lock.withLock { live[id.uuidString] = nil }
        emitChanged()
    }

    private static func removalFailure(_ e: Error, permanently: Bool) -> RPCError {
        if permanently {
            return RPCError(code: "delete-failed", message: "No se pudo eliminar del disco: \(describe(e))")
        }
        return RPCError(code: "trash-failed", message: "No se pudo mover a la Papelera: \(describe(e)) "
                        + "No se ha borrado nada; te queda «Eliminar del disco».")
    }

    static func describe(_ e: Error) -> String {
        if e is LibraryError { return String(describing: e) }
        return (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
    }

    static func map(_ e: Error) -> RPCError {
        if let r = e as? RPCError { return r }
        if e is CancellationError { return RPCError(code: "cancelled", message: "Cancelado.") }
        if let l = e as? LibraryError {
            switch l {
            case .projectNotFound(let id):
                return RPCError(code: "not-found", message: "No hay ningún tema con id \(id.uuidString).")
            case .emptyTitle: return RPCError(code: "empty-title", message: "El título no puede quedar vacío.")
            case .unsafeDeletion(let u):
                return RPCError(code: "unsafe-deletion", message: "No se borra: no es un tema de la biblioteca (\(u.path)).")
            case .workInProgress:
                return RPCError(code: "work-in-progress",
                                message: "Hay trabajo en curso. Espera a que terminen las separaciones y vuelve a cambiar la carpeta.")
            default: return RPCError(code: "internal", message: String(describing: l))
            }
        }
        return RPCError(code: "internal", message: describe(e))
    }

    // MARK: Carpeta de proyectos en caliente (B2)

    /// Cambia la carpeta de proyectos sin reiniciar (`AppModel.relocate` del Mac): mover los temas o solo apuntar. `Library`
    /// rechaza con `workInProgress` si hay cola; solo una reubicación a la vez. Al acabar, todos los servicios ven la nueva
    /// carpeta (`root`) y el perfil ya la guarda `Library.relocate`.
    func relocate(to url: URL, move: Bool, progress: @escaping @Sendable (Double) -> Void) async throws {
        let free = lock.withLock { () -> Bool in
            if relocating { return false }
            relocating = true
            return true
        }
        guard free else { throw RPCError(code: "busy", message: "Ya se está cambiando la carpeta.") }
        defer { lock.withLock { relocating = false } }
        let lib = try await library()
        try await lib.relocate(to: url, mode: move ? .move(progress: progress) : .pointOnly)
        root.url = url
    }

    // MARK: Cierre

    /// Tope del cierre (encargo 8.3a; como `AppModel.terminationBudget` del Mac).
    static let shutdownBudget: TimeInterval = 3

    /// Cancela la cola y deja de escuchar. En Windows los hijos (`tf-separate`) mueren con la app (job object
    /// «kill on close» de `ChildProcess`); aquí se espera como mucho `shutdownBudget` a que Library pare.
    func shutdown() async {
        let (task, pumpTask) = lock.withLock { (libraryTask, pump) }
        guard let task else { return }
        // Carrera sin estructura: un grupo esperaría igualmente a que Library parase.
        let finished = FinishFlag()
        Task.detached {
            if let lib = try? await task.value { await lib.stopAllForShutdown() }
            finished.set()
        }
        let deadline = Date().addingTimeInterval(Self.shutdownBudget)
        while !finished.isSet, Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
        pumpTask?.cancel()
        lock.withLock { live.removeAll() }
    }
}

private final class FinishFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
