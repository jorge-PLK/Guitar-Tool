import Foundation
import NativePlatform

// Elección del proveedor de ONNX Runtime (plan, Mini-spec del port, «Modelos y aceleración»; parte 7.8).
// Tipos puros: corren también en el Mac con sesiones simuladas.

/// Adaptador gráfico visto por DXGI.
public struct OnnxGPU: Sendable, Equatable, Codable {
    public var name: String
    public var vendorID: UInt32
    public var deviceID: UInt32
    public var dedicatedVideoMemory: UInt64
    /// WARP («Microsoft Basic Render Driver»): DirectML corre en la CPU.
    public var isSoftware: Bool
    /// Índice en `EnumAdapters1`: el `device_id` de DirectML.
    public var adapterIndex: Int

    public static let nvidiaVendorID: UInt32 = 0x10DE

    public init(name: String, vendorID: UInt32, deviceID: UInt32, dedicatedVideoMemory: UInt64, isSoftware: Bool,
                adapterIndex: Int) {
        self.name = name
        self.vendorID = vendorID
        self.deviceID = deviceID
        self.dedicatedVideoMemory = dedicatedVideoMemory
        self.isSoftware = isSoftware
        self.adapterIndex = adapterIndex
    }

    /// Clave estable del adaptador para el recuerdo (si cambia la GPU, se vuelve a comparar).
    public var key: String { String(format: "%04x:%04x:", vendorID, deviceID) + name }
}

/// Un intento de sesión: proveedor y dispositivo.
public struct OnnxCandidate: Sendable, Equatable {
    public var provider: OnnxProvider
    public var deviceID: Int
    /// Adaptador DXGI del intento (nil en CPU y QNN).
    public var gpu: OnnxGPU?

    public init(provider: OnnxProvider, deviceID: Int = 0, gpu: OnnxGPU? = nil) {
        self.provider = provider
        self.deviceID = deviceID
        self.gpu = gpu
    }

    public static let cpu = OnnxCandidate(provider: .cpu)
}

public enum OnnxArchitecture: Sendable, Equatable {
    case arm64, x64

    public static var current: OnnxArchitecture {
        #if arch(arm64)
        .arm64
        #else
        .x64
        #endif
    }
}

/// Orden de intentos: CUDA (GPU NVIDIA) → DirectML (GPU DirectX 12 por hardware) → CPU (Windows x64).
public enum OnnxProviderPlan {
    /// Variable de entorno que fuerza un proveedor (`cpu`, `directml`, `cuda`, `qnn`) para probar en un PC.
    public static let environmentKey = "TF_ONNX_PROVIDER"

    public static func parse(_ text: String) -> OnnxProvider? {
        switch text.lowercased().trimmingCharacters(in: .whitespaces) {
        case "cpu": .cpu
        case "directml", "dml": .directML
        case "cuda": .cuda
        case "qnn", "npu": .qnn
        default: nil
        }
    }

    /// Proveedor forzado por el entorno, si lo hay.
    public static func forced(in environment: [String: String]) -> OnnxProvider? {
        environment[environmentKey].flatMap(parse)
    }

    /// Adaptador para DirectML: el de hardware con más VRAM dedicada; WARP solo si se permite (proveedor forzado).
    public static func directMLAdapter(_ gpus: [OnnxGPU], allowSoftware: Bool) -> OnnxGPU? {
        let hardware = gpus.filter { !$0.isSoftware }
        if let best = hardware.max(by: { $0.dedicatedVideoMemory < $1.dedicatedVideoMemory }) { return best }
        return allowSoftware ? gpus.first(where: \.isSoftware) : nil
    }

    /// Proveedores del orden automático que ni se intentan, con su motivo (para el registro). Con proveedor forzado, ninguno.
    public static func omissions(gpus: [OnnxGPU], available: [String], forced: OnnxProvider?) -> [String] {
        guard forced == nil else { return [] }
        var list: [String] = []
        if !available.contains(OnnxProvider.cuda.executionProviderName) {
            list.append("cuda: no hay EP")
        } else if !gpus.contains(where: { !$0.isSoftware && $0.vendorID == OnnxGPU.nvidiaVendorID }) {
            list.append("cuda: sin GPU NVIDIA")
        }
        if !available.contains(OnnxProvider.directML.executionProviderName) {
            list.append("directML: no hay EP")
        } else if directMLAdapter(gpus, allowSoftware: false) == nil {
            list.append("directML: sin GPU por hardware")
        }
        return list
    }

    /// Intentos en orden. Con proveedor forzado, solo ese (sin caer a otro: es para medir).
    public static func candidates(architecture: OnnxArchitecture, gpus: [OnnxGPU], available: [String],
                                  forced: OnnxProvider?) -> [OnnxCandidate] {
        let nvidia = gpus.filter { !$0.isSoftware && $0.vendorID == OnnxGPU.nvidiaVendorID }
        if let forced {
            switch forced {
            case .cpu: return [.cpu]
            case .qnn: return [OnnxCandidate(provider: .qnn)]
            case .cuda: return [OnnxCandidate(provider: .cuda, deviceID: 0, gpu: nvidia.first)]
            case .directML:
                let gpu = directMLAdapter(gpus, allowSoftware: true)
                return [OnnxCandidate(provider: .directML, deviceID: gpu?.adapterIndex ?? 0, gpu: gpu)]
            }
        }
        // QNN fuera del orden automático: Windows es solo x64 (cambio de alcance de Jorge, 19/11/2026). El caso
        // `.qnn` y `architecture` se quedan (API de la 7.0) y QNN solo se usa si se fuerza.
        _ = architecture
        var list: [OnnxCandidate] = []
        if let gpu = nvidia.first, available.contains(OnnxProvider.cuda.executionProviderName) {
            list.append(OnnxCandidate(provider: .cuda, deviceID: 0, gpu: gpu))
        }
        if available.contains(OnnxProvider.directML.executionProviderName),
           let gpu = directMLAdapter(gpus, allowSoftware: false) {
            list.append(OnnxCandidate(provider: .directML, deviceID: gpu.adapterIndex, gpu: gpu))
        }
        list.append(.cpu)
        return list
    }
}

/// Comparación de salidas GPU frente a CPU.
public enum OnnxComparison {
    /// Misma red en otro proveedor: SNR ≥ 60 dB (decisión de Jorge, 19/11/2026; parte 7.3).
    public static let minimumSNR: Double = 60

    /// SNR en dB de `test` frente a `reference` (infinito si son idénticos; -infinito si difieren en tamaño).
    public static func snr(reference: [Float], test: [Float]) -> Double {
        guard reference.count == test.count else { return -.infinity }
        var signal = 0.0, noise = 0.0
        for i in reference.indices {
            let r = Double(reference[i]), d = r - Double(test[i])
            signal += r * r
            noise += d * d
        }
        if noise == 0 { return .infinity }
        if signal == 0 { return -.infinity }
        return 10 * log10(signal / noise)
    }

    /// El peor SNR de todas las salidas de la referencia.
    public static func worstSNR(reference: [String: OnnxTensor], test: [String: OnnxTensor]) -> Double {
        reference.map { name, r in test[name].map { snr(reference: r.data, test: $0.data) } ?? -.infinity }.min() ?? -.infinity
    }
}

/// Entrada fija y determinista para comparar proveedores (valores uniformes en [-1, 1)).
public enum OnnxProbe {
    public static func tensor(shape: [Int], seed: UInt64 = 0x7F4A_7C15) -> OnnxTensor {
        var state = seed
        let count = shape.reduce(1, *)
        var data = [Float](repeating: 0, count: count)
        for i in 0..<count {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            data[i] = Float(Double(state >> 40) / Double(1 << 24) * 2 - 1)
        }
        return OnnxTensor(shape: shape, data: data)
    }

    /// Una entrada fija por cada entrada de la sesión, con su forma declarada; los ejes dinámicos toman, por orden,
    /// los valores de `dynamic` (1 si se acaban).
    public static func inputs(for session: OnnxSession, dynamic: [Int] = []) -> [String: OnnxTensor] {
        var result: [String: OnnxTensor] = [:]
        for (k, name) in session.inputNames.enumerated() {
            var next = dynamic.makeIterator()
            let shape = (session.inputShape(name) ?? [1]).map { $0 > 0 ? $0 : (next.next() ?? 1) }
            result[name] = tensor(shape: shape, seed: 0x7F4A_7C15 &+ UInt64(k))
        }
        return result
    }
}

/// Resultado recordado de una comparación GPU frente a CPU.
public struct OnnxProviderVerdict: Codable, Equatable, Sendable {
    public var passed: Bool
    public var snr: Double?
    public var runtimeVersion: String

    public init(passed: Bool, snr: Double?, runtimeVersion: String) {
        self.passed = passed
        self.snr = snr
        self.runtimeVersion = runtimeVersion
    }
}

/// Recuerdo por equipo de qué modelo cuadra en qué proveedor (JSON en la carpeta de soporte).
public final class OnnxProviderMemory: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()

    public static var defaultURL: URL {
        SupportFolder.toneForge.appendingPathComponent("onnx-providers.json")
    }

    public init(url: URL = OnnxProviderMemory.defaultURL) {
        self.url = url
    }

    public static func key(model: String, candidate: OnnxCandidate) -> String {
        "\(model)|\(candidate.provider.rawValue)|\(candidate.gpu?.key ?? "-")"
    }

    public func verdict(model: String, candidate: OnnxCandidate) -> OnnxProviderVerdict? {
        lock.withLock { load()[Self.key(model: model, candidate: candidate)] }
    }

    public func record(_ verdict: OnnxProviderVerdict, model: String, candidate: OnnxCandidate) {
        lock.withLock {
            var all = load()
            all[Self.key(model: model, candidate: candidate)] = verdict
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Sin `.atomic`: en Windows acaba en `replaceItemAt`, que aborta (trampa del paso 6).
            if let data = try? JSONEncoder().encode(all) { try? data.write(to: url) }
        }
    }

    private func load() -> [String: OnnxProviderVerdict] {
        guard let data = try? Data(contentsOf: url),
              let all = try? JSONDecoder().decode([String: OnnxProviderVerdict].self, from: data) else { return [:] }
        return all
    }
}

/// Lo que se puede ejecutar con unas entradas (la sesión real o una simulada en los tests).
public protocol OnnxRunner: AnyObject {
    func run(_ inputs: [String: OnnxTensor]) throws -> [String: OnnxTensor]
}

extension OnnxSession: OnnxRunner {}

/// Qué pasó al elegir.
public struct OnnxSelection: Sendable, Equatable {
    public var candidate: OnnxCandidate
    /// Intentos descartados con su motivo.
    public var skipped: [String]
    /// SNR de la comparación hecha ahora o recordada.
    public var snr: Double?
    public var fromMemory: Bool

    /// Línea del log de la app: `onnx| bs_roformer -> directML (descartados: cuda: no hay EP; memoria: no)`.
    /// La memoria es `onnx-providers.json` (veredicto de una comparación anterior); con SNR conocido se añade.
    public func logLine(model: String) -> String {
        var parts = ["descartados: " + (skipped.isEmpty ? "ninguno" : skipped.joined(separator: ", ")),
                     "memoria: " + (fromMemory ? "sí" : "no")]
        if let snr, snr.isFinite { parts.append(String(format: "SNR %.1f dB", snr)) }
        return "onnx| \(model) -> \(candidate.provider.rawValue) (\(parts.joined(separator: "; ")))"
    }
}

/// Recorre los intentos: el primero cuya sesión se crea y, si es GPU/NPU, cuadra con CPU (o ya cuadró antes en este
/// equipo). Si la comparación no cuadra, el modelo queda en CPU y se recuerda.
public struct OnnxProviderSelector {
    public var candidates: [OnnxCandidate]
    /// Proveedor forzado: sin comparar, sin recuerdo y sin caer a otro.
    public var forced: Bool
    public var memory: OnnxProviderMemory?
    public var runtimeVersion: String

    public init(candidates: [OnnxCandidate], forced: Bool, memory: OnnxProviderMemory?, runtimeVersion: String) {
        self.candidates = candidates
        self.forced = forced
        self.memory = memory
        self.runtimeVersion = runtimeVersion
    }

    /// `probe`: entrada fija para la comparación, a partir de la sesión ya creada (para leer sus formas).
    public func select<S: OnnxRunner>(model: String, probe: (S) -> [String: OnnxTensor],
                                      make: (OnnxCandidate) throws -> S) throws -> (S, OnnxSelection) {
        var skipped: [String] = []
        if forced, let only = candidates.first {
            return (try make(only), OnnxSelection(candidate: only, skipped: [], snr: nil, fromMemory: false))
        }
        for candidate in candidates {
            if candidate.provider == .cpu { break }
            let remembered = memory?.verdict(model: model, candidate: candidate)
            if let remembered, remembered.runtimeVersion == runtimeVersion, !remembered.passed {
                skipped.append("\(candidate.provider.rawValue): no cuadró con CPU (\(Self.format(remembered.snr)), recordado)")
                break
            }
            let session: S
            do { session = try make(candidate) } catch {
                skipped.append("\(candidate.provider.rawValue): \(error)")
                continue
            }
            if let remembered, remembered.runtimeVersion == runtimeVersion, remembered.passed {
                return (session, OnnxSelection(candidate: candidate, skipped: skipped, snr: remembered.snr, fromMemory: true))
            }
            let inputs = probe(session)
            let accelerated: [String: OnnxTensor]
            do { accelerated = try session.run(inputs) } catch {
                skipped.append("\(candidate.provider.rawValue): falla al ejecutar: \(error)")
                memory?.record(OnnxProviderVerdict(passed: false, snr: nil, runtimeVersion: runtimeVersion),
                               model: model, candidate: candidate)
                break
            }
            // La sesión de CPU solo vive para la referencia (el pico de memoria es una vez por equipo y modelo).
            let reference = try make(.cpu).run(inputs)
            let snr = OnnxComparison.worstSNR(reference: reference, test: accelerated)
            let passed = snr >= OnnxComparison.minimumSNR
            memory?.record(OnnxProviderVerdict(passed: passed, snr: snr.isFinite ? snr : nil, runtimeVersion: runtimeVersion),
                           model: model, candidate: candidate)
            if passed {
                return (session, OnnxSelection(candidate: candidate, skipped: skipped, snr: snr, fromMemory: false))
            }
            skipped.append("\(candidate.provider.rawValue): \(Self.format(snr)) frente a CPU, < \(Int(OnnxComparison.minimumSNR)) dB")
            break
        }
        return (try make(.cpu), OnnxSelection(candidate: .cpu, skipped: skipped, snr: nil, fromMemory: false))
    }

    private static func format(_ snr: Double?) -> String {
        guard let snr else { return "sin SNR" }
        return snr.isFinite ? String(format: "%.1f dB", snr) : "SNR \(snr)"
    }
}

/// Modelos `.onnx` de desarrollo (parte 7.3): `<TF_MODELS_DIR o C:\tf-models>\<carpeta>\model.onnx`, la misma
/// estructura que `Probes/P8-windows/ort-models/out`. Lo usan los tests y la prueba de Jorge; la app usa ModelStore.
public enum OnnxDevelopmentModels {
    public static let environmentKey = "TF_MODELS_DIR"
    public static let defaultDirectory = "C:\\tf-models"

    public static func directory(_ folder: String,
                                 environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        URL(fileURLWithPath: environment[environmentKey] ?? defaultDirectory, isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
    }

    /// `model.onnx` de la carpeta, si existe.
    public static func model(_ folder: String,
                             environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let url = directory(folder, environment: environment).appendingPathComponent("model.onnx")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Float32 crudos de un fichero de la carpeta (entradas y referencias del Mac).
    public static func floats(_ folder: String, _ file: String,
                              environment: [String: String] = ProcessInfo.processInfo.environment) throws -> [Float] {
        let data = try Data(contentsOf: directory(folder, environment: environment).appendingPathComponent(file))
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

/// Carga de un modelo con el mejor proveedor del equipo (lo que usan StemKit, StudyKit y TabKit en Windows).
public enum OnnxModelLoader {
    nonisolated(unsafe) private static var selections: [String: OnnxSelection] = [:]
    nonisolated(unsafe) private static var logHandler: (@Sendable (String) -> Void)?
    private static let lock = NSLock()

    /// Gancho al que la app conecta su log: recibe una línea por cada sesión creada (o que falla al crearse).
    public static func setLogHandler(_ handler: (@Sendable (String) -> Void)?) {
        lock.withLock { logHandler = handler }
    }

    private static func log(_ line: String) {
        let handler = lock.withLock { logHandler }
        handler?(line)
    }

    /// Selección de la última carga del modelo (para registro y para la prueba de Jorge).
    public static func lastSelection(model: String) -> OnnxSelection? {
        lock.withLock { selections[model] }
    }

    /// `model`: clave estable del modelo para el recuerdo (p. ej. "basic_pitch"). `probe`: entrada fija pequeña
    /// con las formas que acepta el modelo (por defecto `OnnxProbe.inputs(for:)`, con 1 en los ejes dinámicos).
    public static func session(modelURL: URL, model: String, options: OnnxSessionOptions = OnnxSessionOptions(),
                               environment: [String: String] = ProcessInfo.processInfo.environment,
                               memory: OnnxProviderMemory? = OnnxProviderMemory(),
                               probe: (OnnxSession) -> [String: OnnxTensor] = { OnnxProbe.inputs(for: $0) })
        throws -> OnnxSession {
        let forced = OnnxProviderPlan.forced(in: environment)
        let available = (try? OnnxRuntime.availableProviders) ?? []
        let candidates = OnnxProviderPlan.candidates(architecture: .current, gpus: OnnxRuntime.gpus,
                                                     available: available, forced: forced)
        let selector = OnnxProviderSelector(candidates: candidates, forced: forced != nil, memory: memory,
                                            runtimeVersion: (try? OnnxRuntime.version) ?? "?")
        let (session, rawSelection): (OnnxSession, OnnxSelection)
        do {
            (session, rawSelection) = try selector.select(model: model, probe: probe) { candidate in
                var o = options
                o.deviceID = candidate.deviceID
                return try OnnxSession(modelURL: modelURL, provider: candidate.provider, options: o)
            }
        } catch {
            log("onnx| \(model) -> error: \(error)")
            throw error
        }
        var selection = rawSelection
        selection.skipped = OnnxProviderPlan.omissions(gpus: OnnxRuntime.gpus, available: available, forced: forced)
            + selection.skipped
        lock.withLock { selections[model] = selection }
        log(selection.logLine(model: model))
        return session
    }
}
