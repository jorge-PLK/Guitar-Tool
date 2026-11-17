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

/// Metadatos opcionales al importar desde un enlace (mini-spec Fase 2b, «Datos»).
public struct ImportMetadata: Sendable, Equatable {
    public var title: String?
    public var artist: String?
    public var origin: SongOrigin?
    /// Fichero de carátula; se copia a `source/cover.jpg`.
    public var artworkFile: URL?

    public init(title: String? = nil, artist: String? = nil, origin: SongOrigin? = nil, artworkFile: URL? = nil) {
        self.title = title
        self.artist = artist
        self.origin = origin
        self.artworkFile = artworkFile
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
    /// `deleteProject` se negó a borrar: la carpeta no es un proyecto del índice, hijo directo de la carpeta de proyectos.
    case unsafeDeletion(URL)
    /// El título corregido a mano está vacío.
    case emptyTitle
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
    /// El proyecto se movió a la Papelera y salió del índice.
    case trashed(UUID)
    case indexChanged
    case relocated(URL)
    /// Paso de guitarras (Fase 4: L/R y tramos de solo), tras medir y antes del análisis. Si falla, el tema sigue
    /// usable con las pistas que hubiera o el canal «Guitarras» de siempre.
    case guitarSplitQueued(UUID)
    case guitarSplitStarted(UUID)
    case guitarSplitFinished(UUID)
    case guitarSplitFailed(UUID, String)
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
    /// Motivo histórico con el que se marcaban las separaciones que quedaron a medias (ahora se re-encolan).
    public static let interruptedMessage = "interrumpida"
    /// Motivo con el que `recoverInterrupted` marca un tema interrumpido del que no queda ni el audio ni el original.
    public static let missingAudioMessage = "falta el audio"
    /// Prefijos de las carpetas temporales que `removeOrphanTemporaries` borra al arrancar.
    static let importingPrefix = ".importing-"
    static let migratingPrefix = ".migrating-"

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
    private let guitarSplitter: (any GuitarSplitting)?
    /// Pasos de guitarras que fallaron en esta sesión: no se reintentan hasta reabrir la app o cambiar las opciones
    /// (evita bucles al abrir).
    private var guitarSplitFailed: Set<UUID> = []
    /// Estado observable del paso de guitarras (ausente = listo).
    private var guitarStates: [UUID: GuitarSplitState] = [:]
    /// Trabajos de la cola que solo rehacen guitarras (no repiten el análisis).
    private var guitarOnlyJobs: Set<UUID> = []
    /// Las opciones cambiaron con el proyecto en pleno trabajo: hay que repetir el paso con las últimas.
    private var guitarRerun: Set<UUID> = []

    /// Trabajos posteriores (medir stems y analizar). Se sirven antes que la siguiente separación: son cortos.
    private var postQueue: [UUID] = []
    private var currentPostID: UUID?
    /// Borrado de WAV de stems vacíos; interno para que los tests simulen una interrupción tras guardar `project.json`.
    var stemFileRemover: @Sendable (URL) throws -> Void = { url in
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    /// Movimiento a la Papelera; inyectable para que los tests no ensucien la Papelera real.
    var projectTrasher: @Sendable (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
    /// Borrado definitivo de la carpeta de un proyecto; inyectable para simular fallos en tests.
    var projectDeleter: @Sendable (URL) throws -> Void = { url in try FileManager.default.removeItem(at: url) }
    func setProjectDeleter(_ f: @escaping @Sendable (URL) throws -> Void) { projectDeleter = f }
    func setProjectTrasher(_ f: @escaping @Sendable (URL) throws -> Void) { projectTrasher = f }
    func setStemFileRemover(_ f: @escaping @Sendable (URL) throws -> Void) { stemFileRemover = f }

    private var queue: [UUID] = []
    private var worker: Task<Void, Never>?
    private var currentID: UUID?
    private var currentTask: Task<Void, Error>?
    private var cancelRequested: Set<UUID> = []
    private var cancelWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
    private var migrations: [UUID: Task<Void, Never>] = [:]
    /// Cierre de la app en curso: no se encolan más trabajos y la cancelación no toca el estado guardado.
    private var shuttingDown = false

    public init(root: URL, profile: ProfileStore, index: LibraryIndex, importer: any AudioImporting,
                separator: any StemSeparating, autoSeparate: Bool = true,
                levelMeter: (any StemLevelMeasuring)? = nil, analyzer: (any StudyAnalyzing)? = nil,
                guitarSplitter: (any GuitarSplitting)? = nil) {
        self.guitarSplitter = guitarSplitter
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

    private func existingProject(withVideoID videoID: String) -> Project? {
        ProjectScanner.scan(root: root).found.first { $0.project.song.origin?.videoID == videoID }?.project
    }

    /// Proyecto ya importado con ese `videoID` de YouTube (para avisar antes de descargar; mini-spec Fase 2b, «Tema repetido»).
    public func project(withVideoID videoID: String) -> Project? {
        existingProject(withVideoID: videoID)
    }

    /// Proyecto ya importado con ese id de Spotify (para marcar temas de una lista; mini-spec Fase 2b, «Listas»).
    public func project(withSpotifyID spotifyID: String) -> Project? {
        ProjectScanner.scan(root: root).found.first { $0.project.song.origin?.spotifyID == spotifyID }?.project
    }

    public func importSong(from source: URL, metadata: ImportMetadata? = nil,
                           progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> UUID {
        let fm = FileManager.default
        if let vid = metadata?.origin?.videoID, let dup = existingProject(withVideoID: vid) {
            throw LibraryError.duplicate(dup.id)
        }
        let sha = try await Task.detached { try Library.sha256(of: source) }.value
        if let dup = existingProject(withSHA: sha) { throw LibraryError.duplicate(dup) }

        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let rate = workingRate()
        let tmpDir = root.appendingPathComponent("\(Library.importingPrefix)\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { FileOps.removeIfExists(tmpDir) }
        let tmpWav = tmpDir.appendingPathComponent("song.wav")
        let info = try await importer.importAudio(from: source, to: tmpWav, sampleRate: rate, progress: progress)

        // Sin suspensiones desde aquí hasta crear la carpeta: el nombre único no se pisa.
        if let dup = existingProject(withSHA: sha) { throw LibraryError.duplicate(dup) }
        if let vid = metadata?.origin?.videoID, let dup = existingProject(withVideoID: vid) {
            throw LibraryError.duplicate(dup.id)
        }
        // Con metadatos del enlace, título y artista salen de ahí y no del fichero.
        let fileTitle = source.deletingPathExtension().lastPathComponent
        let metaTitle = (metadata?.title?.isEmpty == false) ? metadata?.title : nil
        let metaArtist = (metadata?.artist?.isEmpty == false) ? metadata?.artist : nil
        let title = metaTitle ?? (info.title?.isEmpty == false ? info.title : nil) ?? fileTitle
        let artist = metaArtist ?? ((info.artist?.isEmpty == false) ? info.artist : nil)
        var origin = metadata?.origin
        if metadata?.artworkFile != nil { origin?.artwork = ProjectLayout.coverRelativePath }
        let folderName = FolderNaming.uniqueName(base: FolderNaming.baseName(title: title, artist: artist), in: root)
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        let layout = ProjectLayout(folder: folder)

        let ext = source.pathExtension.lowercased().isEmpty ? "audio" : source.pathExtension.lowercased()
        let sourceRel = "source/original.\(ext)"
        let project = Project(
            song: Song(title: title, artist: artist, source: sourceRel, sourceSHA256: sha,
                       sourceFormat: info.sourceFormat, sourceSampleRate: info.sourceSampleRate,
                       sourceChannels: info.sourceChannels, sampleRate: rate, duration: info.duration, origin: origin))
        do {
            try layout.createSkeleton()
            try fm.copyItem(at: source, to: layout.url(relative: sourceRel))
            if let cover = metadata?.artworkFile { try fm.copyItem(at: cover, to: layout.coverFile) }
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
        guard !shuttingDown, !queue.contains(id), currentID != id else { return }
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

    /// Cierre de la app: vacía las colas y cancela la separación en curso y las reconversiones SIN cambiar el
    /// estado guardado (lo que estaba `queued` o `running` sigue así en disco y `recoverInterrupted` lo
    /// re-encola al arrancar). No espera a que el proceso hijo termine: eso lo vigila quien llama.
    public func stopAllForShutdown() async {
        shuttingDown = true
        queue.removeAll()
        postQueue.removeAll()
        currentTask?.cancel()
        for m in migrations.values { m.cancel() }
        while let w = worker { await w.value }
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
                if guitarRerun.remove(id) != nil, !shuttingDown {
                    guitarOnlyJobs.insert(id)
                    postQueue.append(id)
                }
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
            if !cancelRequested.contains(id) && !shuttingDown {
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
                if cancelRequested.contains(id) || shuttingDown { task.cancel() }
                try await task.value
                if !cancelRequested.contains(id) {
                    let stems = try await promotePartialStems(layout)
                    try await mutate(id) {
                        $0.stems = stems
                        $0.separation = SeparationState(state: .done, model: sep.modelIdentifier, finishedAt: Date())
                    }
                    try deleteEmptyStemFiles(stems, layout: layout)
                    cont.yield(.separationFinished(id))
                    if analyzer != nil || guitarSplitter != nil {
                        postQueue.append(id)
                        if analyzer != nil { cont.yield(.analysisQueued(id)) }
                    }
                }
            }
        } catch {
            if !cancelRequested.contains(id) && !shuttingDown { failure = error.localizedDescription }
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

    /// Al arrancar: borra `stems/.partial` y re-encola la separación de cada tema que quedó `queued` o `running`.
    /// Orden estable: primero el que estaba `running` (era la cabeza de la cola) y después los `queued` por
    /// `updatedAt` (el instante en que se encolaron, que es lo que persiste de la cola en memoria), con
    /// `createdAt` y nombre de carpeta como desempate. Si no queda ni el audio ni el original, ese tema pasa a
    /// `failed` («falta el audio») sin bloquear a los demás; si el modelo falta, falla al separar con su motivo.
    /// Los stems de un tema ya `done` se conservan hasta que termine la nueva separación.
    /// Devuelve los ids afectados (re-encolados o fallidos), en ese orden.
    @discardableResult
    public func recoverInterrupted() async throws -> [UUID] {
        let pending = ProjectScanner.scan(root: root).found.filter {
            ($0.project.separation.state == .queued || $0.project.separation.state == .running) && !isSeparating($0.project.id)
        }.sorted { a, b in
            let (ra, rb) = (a.project.separation.state == .running, b.project.separation.state == .running)
            if ra != rb { return ra }
            if a.project.updatedAt != b.project.updatedAt { return a.project.updatedAt < b.project.updatedAt }
            if a.project.createdAt != b.project.createdAt { return a.project.createdAt < b.project.createdAt }
            return a.folder.lastPathComponent < b.folder.lastPathComponent
        }
        var recovered: [UUID] = []
        for s in pending {
            let layout = ProjectLayout(folder: s.folder)
            FileOps.removeIfExists(layout.stemsPartialDir)
            let fm = FileManager.default
            let hasAudio = fm.fileExists(atPath: layout.audioFile.path)
                || fm.fileExists(atPath: layout.url(relative: s.project.song.source).path)
            if hasAudio {
                try await mutate(s.project.id) { $0.separation = SeparationState(state: .queued) }
                try await separate(id: s.project.id)
            } else {
                try await mutate(s.project.id) {
                    $0.separation = SeparationState(state: .failed, error: Library.missingAudioMessage)
                }
            }
            recovered.append(s.project.id)
        }
        return recovered
    }

    /// Al arrancar, antes de que nada las use: borra `.importing-*` de la carpeta de proyectos y `.migrating-*`
    /// dentro de cada proyecto. Ambas son temporales regenerables: la importación se repite desde el original y
    /// la reconversión se rehace desde `source/` (los swaps son atómicos por fichero y `sampleRate` solo cambia
    /// al final), así que borrarlas no pierde datos, tampoco de una mudanza en modo «Mover».
    /// Solo esos prefijos exactos. Devuelve cuántas carpetas borró.
    @discardableResult
    public nonisolated static func removeOrphanTemporaries(in root: URL) -> Int {
        let fm = FileManager.default
        var removed = 0
        let top = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for url in top {
            let name = url.lastPathComponent
            if name.hasPrefix(importingPrefix) {
                FileOps.removeIfExists(url); removed += 1
                continue
            }
            guard !name.hasPrefix(".") else { continue }
            let inner = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            for u in inner where u.lastPathComponent.hasPrefix(migratingPrefix) {
                FileOps.removeIfExists(u); removed += 1
            }
        }
        return removed
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
    /// Si cambian los tramos de solo (secciones con «Solo»), rehace solo el paso de guitarras en segundo plano;
    /// renombrar o mover secciones que no son solo no reprocesa.
    public func saveStudy(id: UUID, study: StudyState, sections: [Section]) async throws {
        var before: GuitarOptions?
        var after: GuitarOptions?
        try await mutate(id) {
            before = $0.guitarOptions
            $0.study = study
            $0.sections = sections
            after = $0.guitarOptions
        }
        guard before != after else { return }
        guitarSplitFailed.remove(id)
        try await enqueueGuitarStep(id)
    }

    /// Guarda la fuente elegida de la tablatura (nil = sin elegir). Solo toca ese campo.
    public func saveTabSource(_ choice: TabSourceChoice?, for id: UUID) async throws {
        try await mutate(id) { $0.tabSource = choice }
    }

    /// Guarda los nombres de las pistas de guitarra por papel (vacío = el nombre por defecto). No toca pistas ni
    /// opciones, así que es seguro con el paso de guitarras en marcha.
    public func saveGuitarNames(id: UUID, names: [GuitarRole: String]) async throws {
        try await mutate(id) { p in
            for (role, raw) in names {
                let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = n.isEmpty ? role.defaultName : n
                if let i = p.guitars.firstIndex(where: { $0.role == role }) {
                    p.guitars[i].name = name
                } else {
                    p.guitars.append(Guitar(role: role, name: name))
                }
            }
        }
    }

    /// Guarda el interruptor «Guitarras en L y R» y, si cambió, rehace solo el paso de guitarras en segundo
    /// plano (sin repetir el análisis). Con el paso en marcha lo repite después con las últimas opciones.
    /// Devuelve las opciones efectivas (interruptor + tramos de las secciones con «Solo»).
    @discardableResult
    public func saveGuitarStereoSplit(id: UUID, _ on: Bool) async throws -> GuitarOptions {
        var before = false
        let saved = try await mutate(id) { p in
            before = p.guitarSettings.stereoSplit
            p.guitarSettings.stereoSplit = on
        }
        guard before != on else { return saved.guitarOptions }
        guitarSplitFailed.remove(id)
        try await enqueueGuitarStep(id)
        return saved.guitarOptions
    }

    /// Estado del paso de guitarras del proyecto (listo si no hay nada pendiente).
    public func guitarSplitState(id: UUID) -> GuitarSplitState { guitarStates[id] ?? .done }

    private func enqueueGuitarStep(_ id: UUID) async throws {
        guard guitarSplitter != nil, !shuttingDown, let folder = await locate(id) else { return }
        let project = try ProjectFile.load(folder: folder)
        guard project.separation.state == .done, !queue.contains(id), currentID != id, migrations[id] == nil else { return }
        guard guitarSplitNeeded(project, layout: ProjectLayout(folder: folder)) else { return }
        guitarStates[id] = .pending
        continuation.yield(.guitarSplitQueued(id))
        if currentPostID == id { guitarRerun.insert(id); return }
        if !postQueue.contains(id) {
            guitarOnlyJobs.insert(id)
            postQueue.append(id)
        }
        startWorkerIfNeeded()
    }

    /// Añade una toma grabada al proyecto (mini-spec Fase 3, «Grabación»). Solo toca `takes`. Si ya hay una con
    /// ese id, la sustituye.
    public func saveTake(id: UUID, take: Take) async throws {
        try await saveTakes(id: id, [take])
    }

    /// Añade o sustituye (por id) varias tomas de una vez, p. ej. las corregidas al calibrar. Solo toca `takes`.
    public func saveTakes(id: UUID, _ takes: [Take]) async throws {
        try await mutate(id) { p in
            for t in takes {
                if let i = p.takes.firstIndex(where: { $0.id == t.id }) { p.takes[i] = t } else { p.takes.append(t) }
            }
        }
    }

    /// Corrige a mano título y artista (recortados). Título vacío → `emptyTitle` y no se guarda; artista vacío → `nil`.
    /// No renombra la carpeta ni toca `source/`, `audio/`, stems ni `origin`.
    public func updateSongInfo(id: UUID, title: String, artist: String?) async throws {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw LibraryError.emptyTitle }
        let a = artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await mutate(id) {
            $0.song.title = t
            $0.song.artist = (a?.isEmpty ?? true) ? nil : a
        }
        continuation.yield(.indexChanged)
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
        let layout = ProjectLayout(folder: folder)
        let guitarNeeded = guitarSplitNeeded(project, layout: layout)
        if guitarNeeded, guitarStates[id] == nil { guitarStates[id] = .pending; continuation.yield(.guitarSplitQueued(id)) }
        let needsMeasure = needsStemWork(project, layout: layout) || guitarNeeded
        var current = false
        if let analyzer { current = await analyzer.isCurrent(project: project, layout: layout) }
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
        guard let folder = await locate(id) else { return }
        let layout = ProjectLayout(folder: folder)
        var project: Project
        do {
            project = try ProjectFile.load(folder: folder)
            guard project.separation.state == .done else { return }
            if needsStemWork(project, layout: layout) {
                project = try await measureStems(id, folder: folder)
            }
        } catch {
            if analyzer != nil { cont.yield(.analysisFailed(id, error.localizedDescription)) }
            return
        }
        // Orden: niveles → guitarras → análisis.
        let guitarsOnly = guitarOnlyJobs.remove(id) != nil
        if guitarSplitNeeded(project, layout: layout) {
            project = await splitGuitars(id, folder: folder, project: project)
        } else if case .pending? = guitarStates[id] {
            guitarStates[id] = nil
        }
        if let analyzer, !guitarsOnly {
            do {
                cont.yield(.analysisStarted(id))
                if await !analyzer.isCurrent(project: project, layout: layout) {
                    try await analyzer.analyze(project: project, layout: layout)
                }
                cont.yield(.analysisFinished(id))
            } catch {
                cont.yield(.analysisFailed(id, error.localizedDescription))
            }
        }
    }

    // MARK: Guitarras (Fase 4)

    private func guitarInputAvailable(_ project: Project, layout: ProjectLayout) -> Bool {
        project.stems.contains { $0.kind == .guitar && !$0.isEmpty }
            && FileManager.default.fileExists(atPath: layout.stemURL(.guitar).path)
    }

    /// Hay que rehacer las pistas: las opciones piden algo y falta, cambió `stems/guitar.wav`, cambiaron las
    /// opciones o falta algún fichero; o ya no piden nada (o no hay entrada) y quedan pistas que retirar.
    private func guitarSplitNeeded(_ project: Project, layout: ProjectLayout) -> Bool {
        guard guitarSplitter != nil, !guitarSplitFailed.contains(project.id) else { return false }
        let fm = FileManager.default
        let options = project.guitarOptions
        guard options.needsProcessing, guitarInputAvailable(project, layout: layout) else {
            return project.guitarApplied != nil || project.guitars.contains(where: \.isPresent)
        }
        guard let st = project.guitarApplied, st.inputFingerprint == layout.guitarInputFingerprint,
              st.options == options else { return true }
        return project.guitars.contains { g in g.file.map { !fm.fileExists(atPath: layout.url(relative: $0).path) } ?? false }
    }

    /// Rehace las pistas con las opciones guardadas ahora. Si fallan, el proyecto queda como estaba.
    private func splitGuitars(_ id: UUID, folder: URL, project: Project) async -> Project {
        guard let guitarSplitter else { return project }
        let cont = continuation
        let layout = ProjectLayout(folder: folder)
        let fm = FileManager.default
        let options = ((try? ProjectFile.load(folder: folder)) ?? project).guitarOptions
        do {
            guard options.needsProcessing, guitarInputAvailable(project, layout: layout),
                  let fingerprint = layout.guitarInputFingerprint else {
                // Nada que producir: se retiran las pistas (los nombres se conservan).
                let updated = try await mutate(id) { p in
                    p.guitars = p.guitars.map { Guitar(role: $0.role, name: $0.name) }
                    p.guitarApplied = nil
                }
                for role in GuitarRole.allCases { FileOps.removeIfExists(layout.guitarURL(role)) }
                guitarStates[id] = nil
                cont.yield(.guitarSplitFinished(id))
                return updated
            }
            guitarStates[id] = .processing
            cont.yield(.guitarSplitStarted(id))
            let out = layout.guitarsPartialDir
            FileOps.removeIfExists(out)
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
            defer { FileOps.removeIfExists(out) }
            let result = try await guitarSplitter.split(projectFolder: folder, input: layout.stemURL(.guitar),
                                                        outputDirectory: out, options: options) { _ in }
            try Task.checkCancellation()
            // Validar antes de tocar nada: nombre simple y fichero presente.
            for t in result.tracks {
                guard !t.file.isEmpty, !t.file.contains("/"), t.file != "..",
                      fm.fileExists(atPath: out.appendingPathComponent(t.file).path) else {
                    throw LibraryError.sizeMismatch("pista de guitarra \(t.role.rawValue) sin fichero")
                }
            }
            try fm.createDirectory(at: layout.stemsDir, withIntermediateDirectories: true)
            for t in result.tracks {
                try FileOps.atomicReplace(layout.stemsDir.appendingPathComponent(t.file), with: out.appendingPathComponent(t.file))
            }
            let tracks = result.tracks
            let applied = GuitarAppliedState(inputFingerprint: fingerprint, options: options)
            // project.json antes de borrar los WAV de los papeles que ya no salen.
            let updated = try await mutate(id) { p in
                var guitars = p.guitars.map { Guitar(role: $0.role, name: $0.name) }
                for t in tracks {
                    let name = guitars.first { $0.role == t.role }?.name
                    guitars.removeAll { $0.role == t.role }
                    guitars.append(Guitar(role: t.role, name: name, file: "stems/\(t.file)", confidence: t.confidence))
                }
                let order = GuitarRole.allCases
                p.guitars = guitars.sorted { order.firstIndex(of: $0.role)! < order.firstIndex(of: $1.role)! }
                p.guitarApplied = applied
            }
            let kept = Set(tracks.map(\.role))
            for role in GuitarRole.allCases where !kept.contains(role) { FileOps.removeIfExists(layout.guitarURL(role)) }
            guitarStates[id] = nil
            cont.yield(.guitarSplitFinished(id))
            return updated
        } catch {
            guitarSplitFailed.insert(id)
            guitarStates[id] = .failed(error.localizedDescription)
            cont.yield(.guitarSplitFailed(id, error.localizedDescription))
            return project
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

            let tmpDir = folder.appendingPathComponent("\(Library.migratingPrefix)\(UUID().uuidString)", isDirectory: true)
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

    // MARK: Borrado

    /// Mueve la carpeta del proyecto a la Papelera y quita su entrada del índice. Nunca borra de forma definitiva:
    /// si el movimiento falla, lanza el error y no toca nada. Si el tema está en cola o separándose, lo cancela antes.
    public func trashProject(id: UUID) async throws {
        let folder = try await stopWork(forRemoving: id)
        try projectTrasher(folder)
        try await removeFromIndex(id)
        continuation.yield(.trashed(id))
        continuation.yield(.indexChanged)
    }

    /// Borra la carpeta del proyecto de forma DEFINITIVA (no pasa por la Papelera). Mismos pasos previos que
    /// `trashProject`. Salvaguarda: la carpeta tiene que ser la que el índice asigna a ese id, hija directa de la
    /// carpeta de proyectos actual y con su `project.json` dentro; si no, lanza `unsafeDeletion` y no borra nada.
    /// La entrada del índice se quita solo si el borrado salió bien. Emite `.trashed` (sale del índice igual).
    public func deleteProject(id: UUID) async throws {
        let folder = try await stopWork(forRemoving: id)
        guard let name = await index.folderName(for: id), folder.lastPathComponent == name,
              folder.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path,
              !name.isEmpty, !name.hasPrefix("."),
              FileManager.default.fileExists(atPath: ProjectLayout(folder: folder).projectFile.path) else {
            throw LibraryError.unsafeDeletion(folder)
        }
        try projectDeleter(folder)
        try await removeFromIndex(id)
        continuation.yield(.trashed(id))
        continuation.yield(.indexChanged)
    }

    /// Pasos previos comunes a Papelera y borrado: cancela separación (en cola o en marcha), análisis y reconversión.
    private func stopWork(forRemoving id: UUID) async throws -> URL {
        guard let folder = await locate(id) else { throw LibraryError.projectNotFound(id) }
        if queue.contains(id) || currentID == id { try await cancelSeparation(id: id) }
        postQueue.removeAll { $0 == id }
        while currentPostID == id, let w = worker { await w.value }
        if let m = migrations[id] {
            m.cancel()
            await m.value
        }
        return folder
    }

    private func removeFromIndex(_ id: UUID) async throws { try await index.remove(id: id) }

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
