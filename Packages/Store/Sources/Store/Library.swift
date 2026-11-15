import CryptoKit
import Foundation

// MARK: - Protocolos que implementa la app (Store no depende de AudioKit ni StemKit)

public struct ImportedAudioInfo: Sendable, Equatable {
    public var title: String?
    public var artist: String?
    public var duration: Double
    public var sourceFormat: String
    public var sourceSampleRate: Double
    public var sourceChannels: Int

    public init(title: String? = nil, artist: String? = nil, duration: Double, sourceFormat: String,
                sourceSampleRate: Double, sourceChannels: Int) {
        self.title = title
        self.artist = artist
        self.duration = duration
        self.sourceFormat = sourceFormat
        self.sourceSampleRate = sourceSampleRate
        self.sourceChannels = sourceChannels
    }
}

public protocol AudioImporting: Sendable {
    func importAudio(from source: URL, to destination: URL, sampleRate: Double,
                     progress: @escaping @Sendable (Double) -> Void) async throws -> ImportedAudioInfo
    func resample(_ file: URL, to destination: URL, sampleRate: Double) async throws
}

public protocol StemSeparating: Sendable {
    /// Escribe `<kind>.wav` en `outputDirectory` a la frecuencia del input; cancelable con la cancelación de Task.
    func separate(input: URL, outputDirectory: URL, progress: @escaping @Sendable (Double) -> Void) async throws
    /// Identificador del modelo para `separation.model` (p. ej. `bs-roformer-sw@gridshift-fp16`).
    var modelIdentifier: String? { get }
}

public extension StemSeparating {
    var modelIdentifier: String? { nil }
}

/// Mide un stem ya escrito y dice si es silencio (regla de la mini-spec Fase 2, «Stems vacíos»); la implementa la app.
public protocol StemLevelMeasuring: Sendable {
    func isSilent(stem: URL) async throws -> Bool
}

/// Análisis de estudio (pulso, acordes, tonalidad) de un proyecto ya separado; la implementa la app.
/// Escribe `ProjectLayout.analysisCache`. Store no conoce StudyKit.
public protocol StudyAnalyzing: Sendable {
    /// `true` si `cache/analysis.json` existe y su huella coincide con la del proyecto y los modelos actuales.
    func isCurrent(project: Project, layout: ProjectLayout) async -> Bool
    func analyze(project: Project, layout: ProjectLayout) async throws
}

// MARK: - Tipos públicos

/// Estado del análisis de estudio de un proyecto.
public enum AnalysisState: Sendable, Equatable {
    /// Sin análisis (o sin analizador / sin separación terminada).
    case missing
    /// En cola o en marcha.
    case analyzing
    case ready
    case failed(String)
}

public enum LibraryError: Error, Equatable, Sendable {
    /// El original ya existe en otro proyecto (mismo SHA-256); la app decide.
    case duplicate(UUID)
    case projectNotFound(UUID)
    case busy(UUID)
    /// Hay una separación en curso o en cola.
    case workInProgress
    case destinationNotEmpty(URL)
    case sizeMismatch(String)
}

public enum LibraryEvent: Sendable, Equatable {
    case imported(UUID)
    case separationQueued(UUID)
    case separationStarted(UUID)
    case separationProgress(UUID, Double)
    case separationFinished(UUID)
    case separationFailed(UUID, String)
    case separationCancelled(UUID)
    /// Análisis de estudio en la cola posterior a la separación (misma cola de uno en uno).
    case analysisQueued(UUID)
    case analysisStarted(UUID)
    case analysisFinished(UUID)
    case analysisFailed(UUID, String)
    /// Se midió el nivel de los stems (`Stem.isEmpty` y `levelMeasured` actualizados en `project.json`).
    case stemsMeasured(UUID)
    case rateMigrationStarted(UUID)
    case rateMigrationFinished(UUID)
    case rateMigrationFailed(UUID, String)
    case cleaned(UUID)
    case indexChanged
    case relocated(URL)
}

public enum RelocationMode: Sendable {
    /// Solo cambia `profile.projectsFolder` y reconstruye el índice.
    case pointOnly
    /// Copia todo con progreso (0...1), comprueba tamaños y borra el original SOLO al final.
    case move(progress: @Sendable (Double) -> Void)
}

public struct ProjectDiskUsage: Sendable, Equatable {
    public let id: UUID
    public let folderName: String
    public let bytes: Int64
    /// Lo que `cleanup` liberaría.
    public let regenerableBytes: Int64
}

public struct DiskUsageReport: Sendable, Equatable {
    public let totalBytes: Int64
    public let projects: [ProjectDiskUsage]
    public var regenerableBytes: Int64 { projects.reduce(0) { $0 + $1.regenerableBytes } }
}

// MARK: - Library

public actor Library {
    /// Motivo con el que `recoverInterrupted` marca las separaciones que quedaron a medias.
    public static let interruptedMessage = "interrumpida"

    public nonisolated let events: AsyncStream<LibraryEvent>
    private nonisolated let continuation: AsyncStream<LibraryEvent>.Continuation

    public private(set) var root: URL
    private let profile: ProfileStore
    private let index: LibraryIndex
    private let importer: any AudioImporting
    private let separator: any StemSeparating
    private let autoSeparate: Bool
    private let levelMeter: (any StemLevelMeasuring)?
    private let analyzer: (any StudyAnalyzing)?

    /// Trabajos posteriores (medir stems y analizar). Se sirven antes que la siguiente separación: son cortos.
    private var postQueue: [UUID] = []
    private var currentPostID: UUID?
    /// Borrado de WAV de stems vacíos; interno para que los tests simulen una interrupción tras guardar `project.json`.
    var stemFileRemover: @Sendable (URL) throws -> Void = { url in
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    func setStemFileRemover(_ f: @escaping @Sendable (URL) throws -> Void) { stemFileRemover = f }

    private var queue: [UUID] = []
    private var worker: Task<Void, Never>?
    private var currentID: UUID?
    private var currentTask: Task<Void, Error>?
    private var cancelRequested: Set<UUID> = []
    private var cancelWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
    private var migrations: [UUID: Task<Void, Never>] = [:]

    public init(root: URL, profile: ProfileStore, index: LibraryIndex, importer: any AudioImporting,
                separator: any StemSeparating, autoSeparate: Bool = true,
                levelMeter: (any StemLevelMeasuring)? = nil, analyzer: (any StudyAnalyzing)? = nil) {
        self.levelMeter = levelMeter
        self.analyzer = analyzer
        let (stream, cont) = AsyncStream.makeStream(of: LibraryEvent.self)
        self.events = stream
        self.continuation = cont
        self.root = root
        self.profile = profile
        self.index = index
        self.importer = importer
        self.separator = separator
        self.autoSeparate = autoSeparate
    }

    private func workingRate() -> Double {
        (try? profile.load().workingSampleRate) ?? EquipmentProfile.defaultSampleRate
    }

    // MARK: Localización

    private func locate(_ id: UUID) async -> URL? {
        if let name = await index.folderName(for: id) {
            let f = root.appendingPathComponent(name, isDirectory: true)
            if FileManager.default.fileExists(atPath: ProjectLayout(folder: f).projectFile.path) { return f }
        }
        return ProjectScanner.scan(root: root).found.first { $0.project.id == id }?.folder
    }

    @discardableResult
    private func mutate(_ id: UUID, _ change: (inout Project) -> Void) async throws -> Project {
        guard let folder = await locate(id) else { throw LibraryError.projectNotFound(id) }
        var p = try ProjectFile.load(folder: folder)
        change(&p)
        p.updatedAt = Date()
        try ProjectFile.save(p, to: folder)
        try await index.upsert(project: p, folder: folder)
        return p
    }

    // MARK: Importación

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func existingProject(withSHA sha: String) -> UUID? {
        ProjectScanner.scan(root: root).found.first { $0.project.song.sourceSHA256 == sha }?.project.id
    }

    public func importSong(from source: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> UUID {
        let fm = FileManager.default
        let sha = try await Task.detached { try Library.sha256(of: source) }.value
        if let dup = existingProject(withSHA: sha) { throw LibraryError.duplicate(dup) }

        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let rate = workingRate()
        let tmpDir = root.appendingPathComponent(".importing-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { FileOps.removeIfExists(tmpDir) }
        let tmpWav = tmpDir.appendingPathComponent("song.wav")
        let info = try await importer.importAudio(from: source, to: tmpWav, sampleRate: rate, progress: progress)

        // Sin suspensiones desde aquí hasta crear la carpeta: el nombre único no se pisa.
        if let dup = existingProject(withSHA: sha) { throw LibraryError.duplicate(dup) }
        let fileTitle = source.deletingPathExtension().lastPathComponent
        let title = (info.title?.isEmpty == false ? info.title : nil) ?? fileTitle
        let artist = (info.artist?.isEmpty == false) ? info.artist : nil
        let folderName = FolderNaming.uniqueName(base: FolderNaming.baseName(title: title, artist: artist), in: root)
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        let layout = ProjectLayout(folder: folder)

        let ext = source.pathExtension.lowercased().isEmpty ? "audio" : source.pathExtension.lowercased()
        let sourceRel = "source/original.\(ext)"
        let project = Project(
            song: Song(title: title, artist: artist, source: sourceRel, sourceSHA256: sha,
                       sourceFormat: info.sourceFormat, sourceSampleRate: info.sourceSampleRate,
                       sourceChannels: info.sourceChannels, sampleRate: rate, duration: info.duration))
        do {
            try layout.createSkeleton()
            try fm.copyItem(at: source, to: layout.url(relative: sourceRel))
            try fm.moveItem(at: tmpWav, to: layout.audioFile)
            try ProjectFile.save(project, to: folder)
        } catch {
            FileOps.removeIfExists(folder)
            throw error
        }
        try await index.upsert(project: project, folder: folder)
        continuation.yield(.imported(project.id))
        continuation.yield(.indexChanged)
        if autoSeparate { try await separate(id: project.id) }
        return project.id
    }

    // MARK: Cola de separación

    /// Encola la separación (o la relanza si falló / terminó). Si ya está en cola o en marcha no hace nada.
    public func separate(id: UUID) async throws {
        guard let folder = await locate(id) else { throw LibraryError.projectNotFound(id) }
        guard FileManager.default.fileExists(atPath: ProjectLayout(folder: folder).projectFile.path) else {
            throw LibraryError.projectNotFound(id)
        }
        guard !queue.contains(id), currentID != id else { return }
        postQueue.removeAll { $0 == id }
        try await mutate(id) { $0.separation = SeparationState(state: .queued) }
        queue.append(id)
        continuation.yield(.separationQueued(id))
        startWorkerIfNeeded()
    }

    /// Cancela una separación en cola o en marcha: vuelve a `none` y se borra `.partial`.
    public func cancelSeparation(id: UUID) async throws {
        if let i = queue.firstIndex(of: id) {
            queue.remove(at: i)
            try await mutate(id) { $0.separation = SeparationState(state: .none) }
            if let f = await locate(id) { FileOps.removeIfExists(ProjectLayout(folder: f).stemsPartialDir) }
            continuation.yield(.separationCancelled(id))
        } else if currentID == id {
            cancelRequested.insert(id)
            currentTask?.cancel()
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                cancelWaiters[id, default: []].append(c)
            }
        }
    }

    /// Para tests y cierre ordenado: espera a que la cola de separación quede vacía.
    public func waitForSeparations() async {
        while let w = worker { await w.value }
    }

    /// Espera a las reconversiones de frecuencia en curso.
    public func waitForMigrations() async {
        while let t = migrations.values.first { await t.value }
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        worker = Task { await self.runQueue() }
    }

    private func runQueue() async {
        while !queue.isEmpty || !postQueue.isEmpty {
            if !postQueue.isEmpty {
                let id = postQueue.removeFirst()
                currentPostID = id
                await runPostProcessing(id)
                currentPostID = nil
                continue
            }
            let id = queue.removeFirst()
            currentID = id
            await runSeparation(id)
            currentID = nil
            currentTask = nil
        }
        worker = nil
    }

    /// Separándose o con trabajo posterior (medida / análisis) pendiente o en marcha.
    private func isSeparating(_ id: UUID) -> Bool {
        queue.contains(id) || currentID == id || postQueue.contains(id) || currentPostID == id
    }

    private func runSeparation(_ id: UUID) async {
        let cont = continuation
        var failure: String?
        var folder: URL?
        do {
            if let m = migrations[id] { await m.value }
            guard let f = await locate(id) else { throw LibraryError.projectNotFound(id) }
            folder = f
            let layout = ProjectLayout(folder: f)
            if !cancelRequested.contains(id) {
                let project = try await mutate(id) { $0.separation = SeparationState(state: .running) }
                cont.yield(.separationStarted(id))
                let fm = FileManager.default
                FileOps.removeIfExists(layout.stemsPartialDir)
                try fm.createDirectory(at: layout.stemsPartialDir, withIntermediateDirectories: true)
                if !fm.fileExists(atPath: layout.audioFile.path) {
                    try fm.createDirectory(at: layout.audioDir, withIntermediateDirectories: true)
                    _ = try await importer.importAudio(from: layout.url(relative: project.song.source),
                                                       to: layout.audioFile, sampleRate: project.song.sampleRate,
                                                       progress: { _ in })
                }
                let sep = separator
                let input = layout.audioFile
                let out = layout.stemsPartialDir
                let task = Task { try await sep.separate(input: input, outputDirectory: out) { cont.yield(.separationProgress(id, $0)) } }
                currentTask = task
                if cancelRequested.contains(id) { task.cancel() }
                try await task.value
                if !cancelRequested.contains(id) {
                    let stems = try await promotePartialStems(layout)
                    try await mutate(id) {
                        $0.stems = stems
                        $0.separation = SeparationState(state: .done, model: sep.modelIdentifier, finishedAt: Date())
                    }
                    try deleteEmptyStemFiles(stems, layout: layout)
                    cont.yield(.separationFinished(id))
                    if analyzer != nil {
                        postQueue.append(id)
                        cont.yield(.analysisQueued(id))
                    }
                }
            }
        } catch {
            if !cancelRequested.contains(id) { failure = error.localizedDescription }
        }

        if cancelRequested.remove(id) != nil {
            if let f = folder { FileOps.removeIfExists(ProjectLayout(folder: f).stemsPartialDir) }
            _ = try? await mutate(id) { $0.separation = SeparationState(state: .none) }
            cont.yield(.separationCancelled(id))
        } else if let failure {
            if let f = folder { FileOps.removeIfExists(ProjectLayout(folder: f).stemsPartialDir) }
            _ = try? await mutate(id) { $0.separation = SeparationState(state: .failed, error: failure) }
            cont.yield(.separationFailed(id, failure))
        }
        for w in cancelWaiters.removeValue(forKey: id) ?? [] { w.resume() }
    }

    /// Mueve `.partial/<kind>.wav` → `stems/<kind>.wav` (atómico por fichero) y devuelve la lista de stems.
    /// Los silenciosos (regla de «Stems vacíos») no se promueven: se descartan y se borra el WAV anterior, si lo había.
    /// Orden seguro ante interrupciones: aquí no se borra nada de los vacíos; `runSeparation` guarda `project.json`
    /// y solo entonces llama a `deleteEmptyStemFiles` (y limpia `.partial`).
    private func promotePartialStems(_ layout: ProjectLayout) async throws -> [Stem] {
        let fm = FileManager.default
        try fm.createDirectory(at: layout.stemsDir, withIntermediateDirectories: true)
        var stems: [Stem] = []
        for kind in StemKind.allCases {
            let src = layout.stemsPartialDir.appendingPathComponent("\(kind.rawValue).wav")
            guard fm.fileExists(atPath: src.path) else { continue }
            let rel = ProjectLayout.stemRelativePath(kind)
            var measured = false
            if let levelMeter {
                do {
                    if try await levelMeter.isSilent(stem: src) {
                        stems.append(Stem(kind: kind, file: rel, isEmpty: true, levelMeasured: true))
                        continue
                    }
                    measured = true
                } catch {
                    // No se pudo medir: se conserva y se reintenta al abrir.
                }
            }
            try FileOps.atomicReplace(layout.stemURL(kind), with: src)
            stems.append(Stem(kind: kind, file: rel, levelMeasured: measured))
        }
        return stems
    }

    /// Borra los WAV de los stems `isEmpty` (de `stems/` y de `.partial`) y quita `.partial`. Idempotente.
    private func deleteEmptyStemFiles(_ stems: [Stem], layout: ProjectLayout) throws {
        for s in stems where s.isEmpty {
            try stemFileRemover(layout.stemURL(s.kind))
            try stemFileRemover(layout.stemsPartialDir.appendingPathComponent("\(s.kind.rawValue).wav"))
        }
        FileOps.removeIfExists(layout.stemsPartialDir)
    }

    /// Al arrancar: `queued|running` → `failed` («interrumpida»). Devuelve los ids afectados.
    @discardableResult
    public func recoverInterrupted() async throws -> [UUID] {
        var recovered: [UUID] = []
        for s in ProjectScanner.scan(root: root).found {
            let st = s.project.separation.state
            guard st == .queued || st == .running, !isSeparating(s.project.id) else { continue }
            FileOps.removeIfExists(ProjectLayout(folder: s.folder).stemsPartialDir)
            try await mutate(s.project.id) {
                $0.separation = SeparationState(state: .failed, error: Library.interruptedMessage)
            }
            recovered.append(s.project.id)
        }
        return recovered
    }

    // MARK: Abrir y reconversión de frecuencia

    /// Devuelve el proyecto; si su frecuencia no es la del perfil lanza la reconversión en segundo plano.
    public func open(id: UUID) async throws -> Project {
        guard let folder = await locate(id) else { throw LibraryError.projectNotFound(id) }
        let project = try ProjectFile.load(folder: folder)
        if project.song.sampleRate != workingRate(), migrations[id] == nil {
            migrations[id] = Task {
                await self.migrate(id)
                _ = try? await self.ensureAnalysis(id: id)
            }
        }
        _ = try? await ensureAnalysis(id: id)
        return project
    }

    /// Guarda lo del usuario en la herramienta de estudio (`project.json`): correcciones, bucles, mezcla, ajustes y secciones.
    /// Solo toca esos campos, así que es seguro mientras hay una separación o un análisis en marcha.
    public func saveStudy(id: UUID, study: StudyState, sections: [Section]) async throws {
        try await mutate(id) {
            $0.study = study
            $0.sections = sections
        }
    }

    // MARK: Medida de stems y análisis de estudio

    /// Estado del análisis; si falta o está desfasado (o quedan stems por medir) lo encola en la misma cola
    /// de uno en uno. Idempotente. Sin analizador, solo programa la medida de stems pendientes.
    @discardableResult
    public func ensureAnalysis(id: UUID) async throws -> AnalysisState {
        guard let folder = await locate(id) else { throw LibraryError.projectNotFound(id) }
        let project = try ProjectFile.load(folder: folder)
        guard project.separation.state == .done, !queue.contains(id), currentID != id else { return .missing }
        if postQueue.contains(id) || currentPostID == id { return analyzer == nil ? .missing : .analyzing }
        // Durante la reconversión no se toca: al terminar `open` vuelve a pedirlo.
        guard migrations[id] == nil else { return .missing }
        let needsMeasure = needsStemWork(project, layout: ProjectLayout(folder: folder))
        var current = false
        if let analyzer { current = await analyzer.isCurrent(project: project, layout: ProjectLayout(folder: folder)) }
        if !needsMeasure && (analyzer == nil || current) { return current ? .ready : .missing }
        postQueue.append(id)
        if analyzer != nil { continuation.yield(.analysisQueued(id)) }
        startWorkerIfNeeded()
        return analyzer != nil ? .analyzing : .missing
    }

    /// Hay que medir (con medidor) o completar un borrado interrumpido (stem `isEmpty` con fichero presente).
    private func needsStemWork(_ project: Project, layout: ProjectLayout) -> Bool {
        project.stems.contains { s in
            (levelMeter != nil && !s.levelMeasured && !s.isEmpty)
                || (s.isEmpty && FileManager.default.fileExists(atPath: layout.stemURL(s.kind).path))
        }
    }

    /// Un stem no vacío sin fichero (proyecto dañado) significa que hay que reseparar el tema.
    public func needsReseparation(id: UUID) async throws -> Bool {
        guard let folder = await locate(id) else { throw LibraryError.projectNotFound(id) }
        let project = try ProjectFile.load(folder: folder)
        let layout = ProjectLayout(folder: folder)
        guard project.separation.state == .done else { return false }
        return project.stems.contains { !$0.isEmpty && !FileManager.default.fileExists(atPath: layout.stemURL($0.kind).path) }
    }

    /// Mide los stems sin medir y guarda `project.json` ANTES de borrar ningún WAV; luego borra los vacíos
    /// (incluidos los que quedaron de un borrado interrumpido).
    private func measureStems(_ id: UUID, folder: URL) async throws -> Project {
        let layout = ProjectLayout(folder: folder)
        var project = try ProjectFile.load(folder: folder)
        if let levelMeter, project.stems.contains(where: { !$0.levelMeasured && !$0.isEmpty }) {
            var stems = project.stems
            for i in stems.indices where !stems[i].levelMeasured && !stems[i].isEmpty {
                let url = layout.stemURL(stems[i].kind)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }   // dañado: no se mide
                guard let silent = try? await levelMeter.isSilent(stem: url) else { continue }
                if silent { stems[i].isEmpty = true }
                stems[i].levelMeasured = true
            }
            project = try await mutate(id) { $0.stems = stems }
        }
        try deleteEmptyStemFiles(project.stems, layout: layout)
        continuation.yield(.stemsMeasured(id))
        return project
    }

    private func runPostProcessing(_ id: UUID) async {
        let cont = continuation
        do {
            guard let folder = await locate(id) else { return }
            var project = try ProjectFile.load(folder: folder)
            guard project.separation.state == .done else { return }
            if needsStemWork(project, layout: ProjectLayout(folder: folder)) {
                project = try await measureStems(id, folder: folder)
            }
            guard let analyzer else { return }
            let layout = ProjectLayout(folder: folder)
            cont.yield(.analysisStarted(id))
            if await !analyzer.isCurrent(project: project, layout: layout) {
                try await analyzer.analyze(project: project, layout: layout)
            }
            cont.yield(.analysisFinished(id))
        } catch {
            if analyzer != nil { cont.yield(.analysisFailed(id, error.localizedDescription)) }
        }
    }

    private func migrate(_ id: UUID) async {
        defer { migrations[id] = nil }
        do {
            while isSeparating(id), let w = worker { await w.value }
            guard let folder = await locate(id) else { return }
            let layout = ProjectLayout(folder: folder)
            let project = try ProjectFile.load(folder: folder)
            let target = workingRate()
            guard project.song.sampleRate != target else { return }
            continuation.yield(.rateMigrationStarted(id))

            let tmpDir = folder.appendingPathComponent(".migrating-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { FileOps.removeIfExists(tmpDir) }

            var swaps: [(dest: URL, tmp: URL)] = []
            let newSong = tmpDir.appendingPathComponent("song.wav")
            _ = try await importer.importAudio(from: layout.url(relative: project.song.source), to: newSong,
                                               sampleRate: target, progress: { _ in })
            swaps.append((layout.audioFile, newSong))
            for stem in project.stems where !stem.isEmpty && FileManager.default.fileExists(atPath: layout.stemURL(stem.kind).path) {
                let tmp = tmpDir.appendingPathComponent("\(stem.kind.rawValue).wav")
                try await importer.resample(layout.stemURL(stem.kind), to: tmp, sampleRate: target)
                swaps.append((layout.stemURL(stem.kind), tmp))
            }
            try Task.checkCancellation()

            for s in swaps { try FileOps.atomicReplace(s.dest, with: s.tmp) }
            try await mutate(id) { $0.song.sampleRate = target }
            continuation.yield(.rateMigrationFinished(id))
        } catch {
            continuation.yield(.rateMigrationFailed(id, error.localizedDescription))
        }
    }

    // MARK: Limpieza y espacio

    @discardableResult
    public func cleanup(id: UUID) async throws -> Int64 {
        guard let folder = await locate(id) else { throw LibraryError.projectNotFound(id) }
        guard !isSeparating(id), migrations[id] == nil else { throw LibraryError.busy(id) }
        let plan = ProjectCleaner.plan(folder: folder, project: try ProjectFile.load(folder: folder))
        try ProjectCleaner.execute(plan)
        try await index.upsert(project: plan.resultingProject, folder: folder)
        continuation.yield(.cleaned(id))
        return plan.bytes
    }

    /// Limpia todos los proyectos que no estén ocupados. Devuelve los bytes planificados.
    @discardableResult
    public func cleanupAll() async throws -> Int64 {
        var total: Int64 = 0
        for s in ProjectScanner.scan(root: root).found where !isSeparating(s.project.id) && migrations[s.project.id] == nil {
            total += try await cleanup(id: s.project.id)
        }
        return total
    }

    public func diskUsage() -> DiskUsageReport {
        let rows = ProjectScanner.scan(root: root).found.map { s in
            ProjectDiskUsage(id: s.project.id, folderName: s.folder.lastPathComponent,
                             bytes: DiskSize.allocatedBytes(of: s.folder),
                             regenerableBytes: ProjectCleaner.plan(folder: s.folder, project: s.project).bytes)
        }
        return DiskUsageReport(totalBytes: rows.reduce(0) { $0 + $1.bytes }, projects: rows)
    }

    public func entries() async throws -> [LibraryEntryInfo] { try await index.entries() }

    @discardableResult
    public func rebuildIndex() async throws -> RebuildReport {
        let r = try await index.rebuild(root: root)
        continuation.yield(.indexChanged)
        return r
    }

    // MARK: Reubicar

    public func relocate(to newRoot: URL, mode: RelocationMode) async throws {
        let oldRoot = root
        guard newRoot.standardizedFileURL != oldRoot.standardizedFileURL else { return }
        guard queue.isEmpty, currentID == nil, postQueue.isEmpty, currentPostID == nil, migrations.isEmpty else { throw LibraryError.workInProgress }

        var copied: [String] = []
        switch mode {
        case .pointOnly:
            try FileManager.default.createDirectory(at: newRoot, withIntermediateDirectories: true)
        case .move(let progress):
            copied = try await Task.detached { try Library.copyTree(from: oldRoot, to: newRoot, progress: progress) }.value
        }

        do {
            var p = try profile.load()
            p.projectsFolder = newRoot
            try profile.save(p)
            root = newRoot
            _ = try await index.rebuild(root: newRoot)
        } catch {
            root = oldRoot
            if case .move = mode { Library.discardCopy(names: copied, in: newRoot) }
            throw error
        }
        // El original se borra SOLO al final.
        for name in copied { FileOps.removeIfExists(oldRoot.appendingPathComponent(name)) }
        continuation.yield(.relocated(newRoot))
        continuation.yield(.indexChanged)
    }

    /// Copia todo el contenido de `old` a `new` con progreso y verifica tamaños. Si falla, borra lo copiado.
    /// Devuelve los nombres de primer nivel copiados.
    nonisolated static func copyTree(from old: URL, to new: URL, progress: @Sendable (Double) -> Void) throws -> [String] {
        let fm = FileManager.default
        let existed = fm.fileExists(atPath: new.path)
        if existed, !((try? fm.contentsOfDirectory(atPath: new.path)) ?? []).isEmpty {
            throw LibraryError.destinationNotEmpty(new)
        }
        let top = try fm.contentsOfDirectory(atPath: old.path).sorted()
        let subpaths = try fm.subpathsOfDirectory(atPath: old.path).sorted()
        func isDir(_ u: URL) -> Bool { (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let total = max(1, subpaths.reduce(Int64(0)) {
            let u = old.appendingPathComponent($1)
            return $0 + (isDir(u) ? 0 : DiskSize.logicalBytes(of: u))
        })
        do {
            try fm.createDirectory(at: new, withIntermediateDirectories: true)
            var done: Int64 = 0
            for rel in subpaths {
                let src = old.appendingPathComponent(rel)
                let dst = new.appendingPathComponent(rel)
                if isDir(src) {
                    try fm.createDirectory(at: dst, withIntermediateDirectories: true)
                } else {
                    try fm.copyItem(at: src, to: dst)
                    done += DiskSize.logicalBytes(of: src)
                    progress(min(1, Double(done) / Double(total)))
                }
            }
            for rel in subpaths where !isDir(old.appendingPathComponent(rel)) {
                if DiskSize.logicalBytes(of: old.appendingPathComponent(rel)) != DiskSize.logicalBytes(of: new.appendingPathComponent(rel)) {
                    throw LibraryError.sizeMismatch(rel)
                }
            }
        } catch {
            if existed { discardCopy(names: top, in: new) } else { FileOps.removeIfExists(new) }
            throw error
        }
        return top
    }

    nonisolated static func discardCopy(names: [String], in dir: URL) {
        for n in names { FileOps.removeIfExists(dir.appendingPathComponent(n)) }
    }
}
