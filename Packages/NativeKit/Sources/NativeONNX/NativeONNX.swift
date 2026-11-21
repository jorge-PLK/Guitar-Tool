import Foundation
import NativePlatform
#if os(Windows)
import COnnxRuntime
#endif

/// Proveedor de ejecución de ONNX Runtime.
public enum OnnxProvider: String, Sendable, Codable, CaseIterable {
    case qnn, cuda, directML, cpu

    /// Nombre del proveedor en `OnnxRuntime.availableProviders`.
    public var executionProviderName: String {
        switch self {
        case .qnn: "QNNExecutionProvider"
        case .cuda: "CUDAExecutionProvider"
        case .directML: "DmlExecutionProvider"
        case .cpu: "CPUExecutionProvider"
        }
    }
}

/// Tensor Float32 en orden de filas, con su forma.
public struct OnnxTensor {
    public var shape: [Int]
    public var data: [Float]

    public init(shape: [Int], data: [Float]) {
        self.shape = shape
        self.data = data
    }
}

/// Tensor Float32 sobre memoria del llamante (sin copia): entrada que ORT solo lee, o salida que ORT escribe con
/// esa forma exacta. La memoria debe vivir y tener `shape.reduce(1, *)` floats durante `run`.
public struct OnnxBuffer {
    public var name: String
    public var shape: [Int]
    public var pointer: UnsafeMutablePointer<Float>

    public init(name: String, shape: [Int], pointer: UnsafeMutablePointer<Float>) {
        self.name = name
        self.shape = shape
        self.pointer = pointer
    }
}

/// Error devuelto por ONNX Runtime.
public enum OnnxError: Error, Equatable, Sendable {
    case runtime(String)
}

/// Opciones de sesión.
public struct OnnxSessionOptions: Sendable, Equatable {
    /// Hilos de un operador (`nil`: los de ORT, uno por núcleo físico).
    public var threads: Int?
    /// Reserva de memoria de CPU de ORT. La separación exportada con dynamo la necesita a `false` (si no, pasa de
    /// 10 GB; parte 7.3).
    public var memoryArena: Bool
    /// Patrón de memoria de ORT (con DirectML va siempre a `false`, lo exige el proveedor).
    public var memoryPattern: Bool
    /// Adaptador DXGI (DirectML) u ordinal CUDA.
    public var deviceID: Int

    public init(threads: Int? = nil, memoryArena: Bool = true, memoryPattern: Bool = true, deviceID: Int = 0) {
        self.threads = threads
        self.memoryArena = memoryArena
        self.memoryPattern = memoryPattern
        self.deviceID = deviceID
    }
}

/// Sesión sobre un modelo `.onnx` (solo Windows; en el Mac la inferencia es Core ML y aquí se lanza
/// `PlatformError.unsupported`). `run` admite llamadas concurrentes (ORT lo garantiza).
public final class OnnxSession: @unchecked Sendable {
    public let provider: OnnxProvider
    public let options: OnnxSessionOptions
    public let inputNames: [String]
    public let outputNames: [String]
    #if os(Windows)
    private let handle: OpaquePointer
    #endif

    public convenience init(modelURL: URL, provider: OnnxProvider, threads: Int?) throws {
        try self.init(modelURL: modelURL, provider: provider, options: OnnxSessionOptions(threads: threads))
    }

    public init(modelURL: URL, provider: OnnxProvider, options: OnnxSessionOptions) throws {
        self.provider = provider
        self.options = options
        #if os(Windows)
        var o = tf_ort_options(intra_threads: Int32(options.threads ?? 0), mem_arena: options.memoryArena ? 1 : 0,
                               mem_pattern: options.memoryPattern ? 1 : 0, provider: provider.cCode,
                               device_id: Int32(options.deviceID))
        var raw: OpaquePointer?
        var err = [CChar](repeating: 0, count: 1024)
        let rc = modelURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return tf_ort_session_create(path, &o, &raw, &err, err.count)
        }
        guard rc == 0, let raw else {
            throw OnnxError.runtime(rc == -1 ? "ruta no válida: \(modelURL.path)" : "\(provider.rawValue): \(String(cString: err))")
        }
        handle = raw
        inputNames = (0..<tf_ort_session_input_count(raw)).map { String(cString: tf_ort_session_input_name(raw, $0)) }
        outputNames = (0..<tf_ort_session_output_count(raw)).map { String(cString: tf_ort_session_output_name(raw, $0)) }
        Self.liveLock.withLock { Self.live[ObjectIdentifier(self)] = raw }
        #else
        throw PlatformError.unsupported("onnx solo en Windows")
        #endif
    }

    #if os(Windows)
    deinit {
        _ = Self.liveLock.withLock { Self.live.removeValue(forKey: ObjectIdentifier(self)) }
        tf_ort_session_release(handle)
    }

    /// Sesiones vivas del proceso (para `terminateAll`), protegidas por `liveLock`.
    nonisolated(unsafe) private static var live: [ObjectIdentifier: OpaquePointer] = [:]
    private static let liveLock = NSLock()
    #endif

    /// Corta las ejecuciones en curso (y las siguientes) de todas las sesiones del proceso: `run` lanza error. Para
    /// la parada ordenada de un helper (un trozo de separación tarda decenas de segundos en CPU).
    public static func terminateAll() {
        #if os(Windows)
        liveLock.withLock { for h in live.values { tf_ort_session_terminate(h) } }
        #endif
    }

    /// Forma declarada de una entrada (-1 en los ejes dinámicos).
    public func inputShape(_ name: String) -> [Int]? {
        #if os(Windows)
        guard let i = inputNames.firstIndex(of: name) else { return nil }
        var dims = [Int64](repeating: 0, count: 16)
        let rank = tf_ort_session_input_shape(handle, i, &dims, dims.count)
        return rank == 0 ? nil : dims.prefix(rank).map { Int($0) }
        #else
        return nil
        #endif
    }

    /// Lo que fija `tf_ort_session_create` sin opción (COnnxRuntime.c: `SetSessionGraphOptimizationLevel`,
    /// `SetSessionExecutionMode`; sin `SetInterOpNumThreads`). Solo para informes: cambiarlo aquí no cambia la sesión.
    public static let fixedGraphOptimization = "ORT_ENABLE_ALL"
    public static let fixedExecutionMode = "ORT_SEQUENTIAL"

    /// Configuración de la sesión en una línea ASCII (proveedor, hilos, reserva, patrón, grafo, versión), solo lectura.
    public var configurationSummary: String {
        let threads = options.threads.map { "\($0)" } ?? "auto (0: uno por nucleo fisico)"
        let pattern = provider == .directML ? false : options.memoryPattern   // el C lo apaga con DirectML
        let version = (try? OnnxRuntime.version) ?? "?"
        return "proveedor \(provider.rawValue), device \(options.deviceID), intra_op_threads \(threads), "
            + "inter_op_threads por defecto, cpu_mem_arena \(options.memoryArena ? "on" : "off"), "
            + "mem_pattern \(pattern ? "on" : "off"), graph_opt \(Self.fixedGraphOptimization), "
            + "exec_mode \(Self.fixedExecutionMode), ORT \(version)"
    }

    /// Ejecuta el modelo. Las entradas no se copian (ORT lee los arrays); cada salida se copia una vez a su array.
    /// Para no copiar las salidas grandes, `run(inputs:outputs:)`.
    public func run(_ inputs: [String: OnnxTensor]) throws -> [String: OnnxTensor] {
        try run(inputs, outputs: outputNames)
    }

    /// Como `run(_:)`, pidiendo solo algunas salidas.
    public func run(_ inputs: [String: OnnxTensor], outputs: [String]) throws -> [String: OnnxTensor] {
        for (name, t) in inputs where t.data.count != t.shape.reduce(1, *) {
            throw OnnxError.runtime("entrada \(name): \(t.data.count) valores para la forma \(t.shape)")
        }
        return try Self.pinned(Array(inputs), []) { buffers in try runAllocating(buffers, outputs) }
    }

    /// Ejecuta sin copias: entradas y salidas sobre memoria del llamante (las formas de salida, exactas).
    public func run(inputs: [OnnxBuffer], outputs: [OnnxBuffer]) throws {
        #if os(Windows)
        _ = try runRaw(inputs, outputs.map { $0.name }, outputs)
        #else
        throw PlatformError.unsupported("onnx solo en Windows")
        #endif
    }

    // MARK: - Privado

    /// Fija la memoria de cada array (sin copiarlo) y llama a `body` con sus búferes.
    private static func pinned<R>(_ rest: [(String, OnnxTensor)], _ acc: [OnnxBuffer],
                                  _ body: ([OnnxBuffer]) throws -> R) throws -> R {
        guard let (name, tensor) = rest.first else { return try body(acc) }
        return try tensor.data.withUnsafeBufferPointer { p in
            // ORT recibe `void *` pero no escribe en las entradas.
            let buffer = OnnxBuffer(name: name, shape: tensor.shape, pointer: UnsafeMutablePointer(mutating: p.baseAddress!))
            return try pinned(Array(rest.dropFirst()), acc + [buffer], body)
        }
    }

    private func runAllocating(_ inputs: [OnnxBuffer], _ names: [String]) throws -> [String: OnnxTensor] {
        #if os(Windows)
        let values = try runRaw(inputs, names, nil)
        var result: [String: OnnxTensor] = [:]
        defer { values.forEach { if let v = $0 { tf_ort_value_release(v) } } }
        for (i, name) in names.enumerated() {
            guard let v = values[i], let data = tf_ort_value_data(v) else { throw OnnxError.runtime("salida \(name) vacía") }
            var dims = [Int64](repeating: 0, count: 16)
            let rank = tf_ort_value_shape(v, &dims, dims.count)
            let shape = dims.prefix(rank).map { Int($0) }
            let count = shape.reduce(1, *)
            result[name] = OnnxTensor(shape: shape, data: Array(UnsafeBufferPointer(start: data, count: count)))
        }
        return result
        #else
        throw PlatformError.unsupported("onnx solo en Windows")
        #endif
    }

    #if os(Windows)
    /// Llamada a `tf_ort_session_run`; con `outputs == nil` ORT reserva las salidas y se devuelven sus `OrtValue`.
    private func runRaw(_ inputs: [OnnxBuffer], _ names: [String], _ outputs: [OnnxBuffer]?) throws -> [OpaquePointer?] {
        let inNames = inputs.map { strdup($0.name) }
        let outNames = names.map { strdup($0) }
        defer { (inNames + outNames).forEach { free($0) } }
        let inShapes = inputs.map { $0.shape.map(Int64.init) }
        let outShapes = (outputs ?? []).map { $0.shape.map(Int64.init) }
        let inShapePtrs = inShapes.map { s -> UnsafeMutablePointer<Int64> in
            let p = UnsafeMutablePointer<Int64>.allocate(capacity: max(s.count, 1)); p.initialize(from: s, count: s.count); return p
        }
        let outShapePtrs = outShapes.map { s -> UnsafeMutablePointer<Int64> in
            let p = UnsafeMutablePointer<Int64>.allocate(capacity: max(s.count, 1)); p.initialize(from: s, count: s.count); return p
        }
        defer { (inShapePtrs + outShapePtrs).forEach { $0.deallocate() } }
        let inNamePtrs: [UnsafePointer<CChar>?] = inNames.map { UnsafePointer($0) }
        let outNamePtrs: [UnsafePointer<CChar>?] = outNames.map { UnsafePointer($0) }
        let inData: [UnsafeMutablePointer<Float>?] = inputs.map { $0.pointer }
        let inShapeC: [UnsafePointer<Int64>?] = inShapePtrs.map { UnsafePointer($0) }
        let inRanks = inputs.map { $0.shape.count }
        let outData: [UnsafeMutablePointer<Float>?] = outputs.map { o in o.map { $0.pointer } } ?? Array(repeating: nil, count: names.count)
        let outShapeC: [UnsafePointer<Int64>?] = outputs == nil ? Array(repeating: nil, count: names.count) : outShapePtrs.map { UnsafePointer($0) }
        let outRanks = outputs.map { o in o.map { $0.shape.count } } ?? Array(repeating: 0, count: names.count)
        var values = [OpaquePointer?](repeating: nil, count: names.count)
        var err = [CChar](repeating: 0, count: 1024)
        let rc = tf_ort_session_run(handle, inputs.count, inNamePtrs, inData, inShapeC, inRanks,
                                    names.count, outNamePtrs, outData, outShapeC, outRanks, &values, &err, err.count)
        guard rc == 0 else { throw OnnxError.runtime(String(cString: err)) }
        return values
    }
    #endif
}

#if os(Windows)
extension OnnxProvider {
    var cCode: Int32 {
        switch self {
        case .cpu: Int32(TF_ORT_CPU)
        case .directML: Int32(TF_ORT_DIRECTML)
        case .cuda: Int32(TF_ORT_CUDA)
        case .qnn: Int32(TF_ORT_QNN)
        }
    }
}
#endif

/// Datos de la `onnxruntime.dll` cargada.
public enum OnnxRuntime {
    /// Versión de la DLL (p. ej. "1.32.0").
    public static var version: String {
        get throws {
            #if os(Windows)
            guard let p = tf_ort_version() else { throw OnnxError.runtime("no se pudo cargar onnxruntime.dll") }
            return String(cString: p)
            #else
            throw PlatformError.unsupported("onnx solo en Windows")
            #endif
        }
    }

    /// Versión de la API C en uso: la de las cabeceras (1.32) o menor con una DLL más antigua (`TF_ORT_DLL`, p. ej.
    /// la compilación de DirectML, que acaba en 1.24); 0 sin DLL o fuera de Windows.
    public static var apiVersion: Int {
        #if os(Windows)
        Int(tf_ort_api_version())
        #else
        0
        #endif
    }

    /// Nombres de los proveedores compilados en la DLL (siempre incluye `CPUExecutionProvider`).
    public static var availableProviders: [String] {
        get throws {
            #if os(Windows)
            guard let apiPtr = tf_ort_api() else {
                throw OnnxError.runtime("sin onnxruntime.dll, o más antigua que las cabeceras (API \(ORT_API_VERSION))")
            }
            let api = apiPtr.pointee
            var providers: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
            var count: Int32 = 0
            if let status = api.GetAvailableProviders!(&providers, &count) {
                let message = String(cString: api.GetErrorMessage!(status)!)
                api.ReleaseStatus!(status)
                throw OnnxError.runtime("GetAvailableProviders: \(message)")
            }
            let names = (0..<Int(count)).map { String(cString: providers![$0]!) }
            if let status = api.ReleaseAvailableProviders!(providers, count) { api.ReleaseStatus!(status) }
            return names
            #else
            throw PlatformError.unsupported("onnx solo en Windows")
            #endif
        }
    }

    /// Adaptadores gráficos que ve DXGI (en el Mac, ninguno).
    public static var gpus: [OnnxGPU] {
        #if os(Windows)
        var raw = [tf_gpu_info](repeating: tf_gpu_info(), count: 16)
        let n = Int(tf_dxgi_adapters(&raw, Int32(raw.count)))
        guard n > 0 else { return [] }
        return raw.prefix(min(n, raw.count)).map { g in
            var g = g
            let name = withUnsafeBytes(of: &g.name) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            return OnnxGPU(name: name, vendorID: g.vendor_id, deviceID: g.device_id,
                           dedicatedVideoMemory: g.dedicated_video_memory, isSoftware: g.is_software != 0,
                           adapterIndex: Int(g.adapter_index))
        }
        #else
        return []
        #endif
    }
}
