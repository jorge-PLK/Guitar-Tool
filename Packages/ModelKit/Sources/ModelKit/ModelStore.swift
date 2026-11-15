import CryptoKit
import Foundation

public enum ModelState: Sendable, Equatable {
    case notInstalled
    case downloading(Double)
    case verifying
    case installing
    case installed(compiledURL: URL, bytes: Int64)
    case failed(String)
}

public enum ModelError: Error, LocalizedError, Equatable {
    case unknownModel(String)
    case hashMismatch(expected: String, actual: String)
    case unzipFailed(String)
    case packageNotFound(String)
    case busy(String)

    public var errorDescription: String? {
        switch self {
        case .unknownModel(let id): return "Modelo desconocido: \(id)."
        case .hashMismatch(let e, let a): return "La suma SHA-256 no coincide (esperada \(e.prefix(12))…, obtenida \(a.prefix(12))…)."
        case .unzipFailed(let m): return "No se pudo descomprimir el modelo: \(m)"
        case .packageNotFound(let n): return "El archivo descargado no contiene \(n)."
        case .busy(let id): return "El modelo \(id) se está instalando."
        }
    }
}

struct InstalledManifest: Codable, Equatable {
    var id: String
    var version: String
    var sha256: String
    var installedAt: Date
    var bytes: Int64
}

/// Estados + difusión de cambios. Con candado para poder actualizarse en orden desde callbacks de progreso.
private final class StateHub: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [String: ModelState]
    private var continuations: [UUID: AsyncStream<(String, ModelState)>.Continuation] = [:]

    init(_ initial: [String: ModelState]) { states = initial }

    func get(_ id: String) -> ModelState {
        lock.lock(); defer { lock.unlock() }
        return states[id] ?? .notInstalled
    }

    func all() -> [String: ModelState] {
        lock.lock(); defer { lock.unlock() }
        return states
    }

    func set(_ id: String, _ state: ModelState) {
        lock.lock(); defer { lock.unlock() }
        states[id] = state
        for c in continuations.values { c.yield((id, state)) }
    }

    func stream() -> AsyncStream<(String, ModelState)> {
        let (stream, cont) = AsyncStream<(String, ModelState)>.makeStream(bufferingPolicy: .unbounded)
        let key = UUID()
        lock.lock(); continuations[key] = cont; lock.unlock()
        cont.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); self.continuations[key] = nil; self.lock.unlock()
        }
        return stream
    }
}

/// Reparte el progreso (monótono) entre el estado y todos los llamantes que comparten la descarga.
private final class ProgressFanout: @unchecked Sendable {
    private let lock = NSLock()
    private let id: String
    private let hub: StateHub
    private var handlers: [@Sendable (Double) -> Void] = []
    private var last = 0.0

    init(id: String, hub: StateHub) { self.id = id; self.hub = hub }

    func add(_ h: @escaping @Sendable (Double) -> Void) {
        lock.lock(); handlers.append(h); let l = last; lock.unlock()
        h(l)
    }

    func report(_ p: Double) {
        lock.lock()
        let v = min(1, max(p, last))
        let hs = handlers
        last = v
        // El estado se actualiza dentro del candado para conservar el orden.
        hub.set(id, .downloading(v))
        lock.unlock()
        for h in hs { h(v) }
    }
}

public actor ModelStore {
    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ToneForge/Models", isDirectory: true)
    }

    private enum Source: Sendable {
        case download
        case archive(URL)
    }

    private let root: URL
    private let descriptors: [String: ModelDescriptor]
    private let downloader: ModelDownloading
    private let compiler: ModelCompiling
    private let hub: StateHub
    private var inflight: [String: (task: Task<URL, Error>, fanout: ProgressFanout)] = [:]

    public init(root: URL = ModelStore.defaultRoot,
                catalog: [ModelDescriptor] = ModelCatalog.all,
                downloader: ModelDownloading = URLSessionDownloader(),
                compiler: ModelCompiling = CoreMLCompiler()) {
        self.root = root
        self.descriptors = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.downloader = downloader
        self.compiler = compiler
        var initial: [String: ModelState] = [:]
        for d in catalog { initial[d.id] = Self.loadState(d, root: root) }
        self.hub = StateHub(initial)
    }

    public func state(_ id: String) -> ModelState { hub.get(id) }

    public func states() -> [String: ModelState] { hub.all() }

    public var updates: AsyncStream<(String, ModelState)> { hub.stream() }

    public func ensureInstalled(_ id: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let d = descriptors[id] else { throw ModelError.unknownModel(id) }
        if case .installed(let url, _) = hub.get(id) { progress(1); return url }
        return try await run(d, source: .download, progress: progress)
    }

    public func install(_ id: String, fromArchive archive: URL) async throws -> URL {
        guard let d = descriptors[id] else { throw ModelError.unknownModel(id) }
        return try await run(d, source: .archive(archive), progress: { _ in })
    }

    public func delete(_ id: String) throws {
        guard descriptors[id] != nil else { throw ModelError.unknownModel(id) }
        if inflight[id] != nil { throw ModelError.busy(id) }
        let dir = root.appendingPathComponent(id, isDirectory: true)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
        hub.set(id, .notInstalled)
    }

    public func diskUsage() -> Int64 {
        hub.all().values.reduce(0) { sum, s in
            if case .installed(_, let b) = s { return sum + b }
            return sum
        }
    }

    // MARK: - Instalación

    private func run(_ d: ModelDescriptor, source: Source,
                     progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if let existing = inflight[d.id] {
            existing.fanout.add(progress)
            return try await existing.task.value
        }
        let fanout = ProgressFanout(id: d.id, hub: hub)
        fanout.add(progress)
        let root = self.root, hub = self.hub, downloader = self.downloader, compiler = self.compiler
        let task = Task {
            do {
                let url = try await Self.pipeline(d, source: source, root: root, hub: hub, fanout: fanout,
                                                  downloader: downloader, compiler: compiler)
                await self.finish(d.id)
                return url
            } catch {
                await self.finish(d.id)
                throw error
            }
        }
        inflight[d.id] = (task, fanout)
        return try await task.value
    }

    private func finish(_ id: String) { inflight[id] = nil }

    private static func pipeline(_ d: ModelDescriptor, source: Source, root: URL, hub: StateHub,
                                 fanout: ProgressFanout, downloader: ModelDownloading,
                                 compiler: ModelCompiling) async throws -> URL {
        let fm = FileManager.default
        let dir = root.appendingPathComponent(d.id, isDirectory: true)
        let staging = dir.appendingPathComponent(".download", isDirectory: true)
        do {
            try? fm.removeItem(at: staging)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)

            let archive: URL
            switch source {
            case .download:
                hub.set(d.id, .downloading(0))
                archive = staging.appendingPathComponent("archive.zip")
                try await downloader.download(from: d.url, to: archive, progress: { fanout.report($0) })
                fanout.report(1)
            case .archive(let url):
                archive = url
            }

            hub.set(d.id, .verifying)
            let actual = try sha256Hex(of: archive)
            guard actual == d.sha256.lowercased() else {
                throw ModelError.hashMismatch(expected: d.sha256, actual: actual)
            }

            hub.set(d.id, .installing)
            let unzipped = staging.appendingPathComponent("unzipped", isDirectory: true)
            try await unzip(archive, to: unzipped)
            let package = unzipped.appendingPathComponent(d.packageName)
            guard fm.fileExists(atPath: package.path) else { throw ModelError.packageNotFound(d.packageName) }

            let compiled = try await compiler.compile(package)
            let final = dir.appendingPathComponent(d.compiledName, isDirectory: true)
            try? fm.removeItem(at: final)
            try? fm.removeItem(at: dir.appendingPathComponent("manifest.json"))
            try fm.moveItem(at: compiled, to: final)
            let bytes = directorySize(final)

            let manifest = InstalledManifest(id: d.id, version: d.version, sha256: d.sha256,
                                             installedAt: Date(), bytes: bytes)
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(manifest).write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)

            try? fm.removeItem(at: staging)
            hub.set(d.id, .installed(compiledURL: final, bytes: bytes))
            return final
        } catch {
            try? fm.removeItem(at: staging)
            if let left = try? fm.contentsOfDirectory(atPath: dir.path), left.isEmpty {
                try? fm.removeItem(at: dir)
            }
            hub.set(d.id, .failed(error.localizedDescription))
            throw error
        }
    }

    private static func loadState(_ d: ModelDescriptor, root: URL) -> ModelState {
        let dir = root.appendingPathComponent(d.id, isDirectory: true)
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")) else { return .notInstalled }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let m = try? dec.decode(InstalledManifest.self, from: data),
              m.id == d.id, m.version == d.version else { return .notInstalled }
        let compiled = dir.appendingPathComponent(d.compiledName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: compiled.path) else { return .notInstalled }
        return .installed(compiledURL: compiled, bytes: m.bytes)
    }
}

// MARK: - Utilidades

func sha256Hex(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

func directorySize(_ url: URL) -> Int64 {
    guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
    var total: Int64 = 0
    for case let f as URL in e {
        let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        if v?.isRegularFile == true { total += Int64(v?.fileSize ?? 0) }
    }
    return total
}

private func unzip(_ archive: URL, to destination: URL) async throws {
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", archive.path, destination.path]
    let err = Pipe()
    process.standardError = err
    process.standardOutput = FileHandle.nullDevice
    let status: Int32 = try await withCheckedThrowingContinuation { cont in
        process.terminationHandler = { p in cont.resume(returning: p.terminationStatus) }
        do { try process.run() } catch { process.terminationHandler = nil; cont.resume(throwing: error) }
    }
    guard status == 0 else {
        let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw ModelError.unzipFailed("ditto terminó con código \(status). \(msg)")
    }
}
