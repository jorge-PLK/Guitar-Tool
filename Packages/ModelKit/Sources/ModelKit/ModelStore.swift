#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import NativePlatform

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
    case bundledResourceMissing(String)

    public var errorDescription: String? {
        switch self {
        case .bundledResourceMissing(let n): return "No se encuentra \(n) entre los recursos de la app."
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
        SupportFolder.toneForge.appendingPathComponent("Models", isDirectory: true)
    }

    private enum Source: Sendable {
        case download
        case archive(URL)
        case bundled(URL)
    }

    private let root: URL
    private let bundleResourceDirectory: URL?
    private let descriptors: [String: ModelDescriptor]
    private let downloader: ModelDownloading
    private let compiler: ModelCompiling
    private let hub: StateHub
    private let format: ModelFormat
    private let physicalMemory: UInt64
    private var inflight: [String: (task: Task<URL, Error>, fanout: ProgressFanout)] = [:]

    public init(root: URL = ModelStore.defaultRoot,
                catalog: [ModelDescriptor] = ModelCatalog.all,
                downloader: ModelDownloading = URLSessionDownloader(),
                compiler: ModelCompiling = CoreMLCompiler(),
                bundleResourceDirectory: URL? = nil,
                format: ModelFormat = .native,
                physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) {
        self.root = root
        self.format = format
        self.physicalMemory = physicalMemory
        self.bundleResourceDirectory = bundleResourceDirectory
        self.descriptors = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.downloader = downloader
        self.compiler = compiler
        var initial: [String: ModelState] = [:]
        for d in catalog {
            initial[d.id] = format == .onnx
                ? Self.loadOnnxState(d, file: d.onnxFile(physicalMemory: physicalMemory), root: root)
                : Self.loadState(d, root: root)
        }
        self.hub = StateHub(initial)
    }

    public func state(_ id: String) -> ModelState { hub.get(id) }

    public func states() -> [String: ModelState] { hub.all() }

    public var updates: AsyncStream<(String, ModelState)> { hub.stream() }

    public func ensureInstalled(_ id: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let d = descriptors[id] else { throw ModelError.unknownModel(id) }
        if case .installed(let url, _) = hub.get(id) { progress(1); return url }
        // Windows: el `.onnx` de la release, sin zip ni compilación (parte 7.8).
        if format == .onnx { return try await run(d, source: .download, progress: progress) }
        if d.archiveKind == .bundledZippedMLPackage {
            let name = d.url.lastPathComponent
            guard let dir = bundleResourceDirectory,
                  FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) else {
                throw ModelError.bundledResourceMissing(name)
            }
            return try await run(d, source: .bundled(dir.appendingPathComponent(name)), progress: progress)
        }
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
        let onnx: OnnxModelFile?
        if format == .onnx {
            guard let file = d.onnxFile(physicalMemory: physicalMemory) else {
                throw ModelError.packageNotFound("\(d.id) (.onnx)")
            }
            onnx = file
        } else {
            onnx = nil
        }
        let task = Task {
            do {
                let url: URL
                if let onnx {
                    url = try await Self.onnxPipeline(d, file: onnx, source: source, root: root, hub: hub,
                                                      fanout: fanout, downloader: downloader)
                } else {
                    url = try await Self.pipeline(d, source: source, root: root, hub: hub, fanout: fanout,
                                                  downloader: downloader, compiler: compiler)
                }
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
            case .bundled(let url):
                archive = staging.appendingPathComponent("archive.zip")
                try fm.copyItem(at: url, to: archive)
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

            // El `.mlmodelc` ya viene compilado: no se llama al compilador.
            let compiled = d.archiveKind == .zippedCompiledModel ? package : try await compiler.compile(package)
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

    /// Windows (parte 7.8): descarga (o copia de `install(_:fromArchive:)`) del `.onnx`, verificación SHA-256 y
    /// `<root>/<id>/<fichero>.onnx` con su `manifest.json`. Sin descomprimir ni compilar.
    private static func onnxPipeline(_ d: ModelDescriptor, file: OnnxModelFile, source: Source, root: URL, hub: StateHub,
                                     fanout: ProgressFanout, downloader: ModelDownloading) async throws -> URL {
        let fm = FileManager.default
        let dir = root.appendingPathComponent(d.id, isDirectory: true)
        let staging = dir.appendingPathComponent(".download", isDirectory: true)
        do {
            try? fm.removeItem(at: staging)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            let staged = staging.appendingPathComponent(file.fileName)
            switch source {
            case .download:
                hub.set(d.id, .downloading(0))
                try await downloader.download(from: file.url, to: staged, progress: { fanout.report($0) })
                fanout.report(1)
            case .archive(let url), .bundled(let url):
                try fm.copyItem(at: url, to: staged)
            }
            hub.set(d.id, .verifying)
            let actual = try sha256Hex(of: staged)
            guard actual == file.sha256.lowercased() else {
                throw ModelError.hashMismatch(expected: file.sha256, actual: actual)
            }
            hub.set(d.id, .installing)
            let final = dir.appendingPathComponent(file.fileName)
            try? fm.removeItem(at: final)
            try? fm.removeItem(at: dir.appendingPathComponent("manifest.json"))
            try fm.moveItem(at: staged, to: final)
            let bytes = Int64((try? fm.attributesOfItem(atPath: final.path))?[.size] as? NSNumber ?? 0)
            let manifest = InstalledManifest(id: d.id, version: d.version, sha256: file.sha256,
                                             installedAt: Date(), bytes: bytes)
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            // Sin `.atomic`: en Windows acaba en `replaceItemAt`, que aborta (trampa del paso 6).
            try enc.encode(manifest).write(to: dir.appendingPathComponent("manifest.json"))
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

    private static func loadOnnxState(_ d: ModelDescriptor, file: OnnxModelFile?, root: URL) -> ModelState {
        guard let file else { return .notInstalled }
        let dir = root.appendingPathComponent(d.id, isDirectory: true)
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")) else { return .notInstalled }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let m = try? dec.decode(InstalledManifest.self, from: data),
              m.id == d.id, m.sha256 == file.sha256 else { return .notInstalled }
        let url = dir.appendingPathComponent(file.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return .notInstalled }
        return .installed(compiledURL: url, bytes: m.bytes)
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

/// Descomprime un zip: `ditto` en el Mac; `tar.exe` (bsdtar, incluido en Windows 10/11) en Windows.
private func unzip(_ archive: URL, to destination: URL) async throws {
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    #if os(Windows)
    let tool = "tar.exe"
    let exe = URL(fileURLWithPath: (ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows") + "\\System32\\tar.exe")
    let args = ["-xf", archive.path, "-C", destination.path]
    #else
    let tool = "ditto"
    let exe = URL(fileURLWithPath: "/usr/bin/ditto")
    let args = ["-x", "-k", archive.path, destination.path]
    #endif
    let child = ChildProcess(executableURL: exe, arguments: args)
    let err = Pipe()
    child.process.standardError = err
    child.process.standardOutput = FileHandle.nullDevice
    let status: Int32 = try await withCheckedThrowingContinuation { cont in
        child.terminationHandler = { c in cont.resume(returning: c.terminationStatus) }
        do { try child.run() } catch { child.terminationHandler = nil; cont.resume(throwing: error) }
    }
    guard status == 0 else {
        let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw ModelError.unzipFailed("\(tool) terminó con código \(status). \(msg)")
    }
}
