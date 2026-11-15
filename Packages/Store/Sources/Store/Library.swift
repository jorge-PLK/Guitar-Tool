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

// MARK: - Tipos públicos

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

    private var queue: [UUID] = []
    private var worker: Task<Void, Never>?
    private var currentID: UUID?
    private var currentTask: Task<Void, Error>?
    private var cancelRequested: Set<UUID> = []
    private var cancelWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
    private var migrations: [UUID: Task<Void, Never>] = [:]

    public init(root: URL, profile: ProfileStore, index: LibraryIndex, importer: any AudioImporting,
                separator: any StemSeparating, autoSeparate: Bool = true) {
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
        while !queue.isEmpty {
            let id = queue.removeFirst()
            currentID = id
            await runSeparation(id)
            currentID = nil
            currentTask = nil
        }
        worker = nil
    }

    private func isSeparating(_ id: UUID) -> Bool { queue.contains(id) || currentID == id }

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
                    let stems = try promotePartialStems(layout)
                    try await mutate(id) {
                        $0.stems = stems
                        $0.separation = SeparationState(state: .done, model: sep.modelIdentifier, finishedAt: Date())
                    }
                    cont.yield(.separationFinished(id))
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
    private func promotePartialStems(_ layout: ProjectLayout) throws -> [Stem] {
        let fm = FileManager.default
        try fm.createDirectory(at: layout.stemsDir, withIntermediateDirectories: true)
        var stems: [Stem] = []
        for kind in StemKind.allCases {
            let src = layout.stemsPartialDir.appendingPathComponent("\(kind.rawValue).wav")
            guard fm.fileExists(atPath: src.path) else { continue }
            try FileOps.atomicReplace(layout.stemURL(kind), with: src)
            stems.append(Stem(kind: kind, file: ProjectLayout.stemRelativePath(kind)))
        }
        FileOps.removeIfExists(layout.stemsPartialDir)
        return stems
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
            migrations[id] = Task { await self.migrate(id) }
        }
        return project
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
            for stem in project.stems {
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
        guard queue.isEmpty, currentID == nil, migrations.isEmpty else { throw LibraryError.workInProgress }

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
