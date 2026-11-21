#if canImport(CoreML)
import CoreML
#endif
import Foundation
import NativeDSP
import NativePlatform

/// El modelo de máscaras, detrás de un protocolo para poder simularlo en los tests.
/// Contrato (docs/probes/P4-modelos.md): entrada `spec` `[1, 2·bins, frames, 2]` float32;
/// salida `[1, stems, 2·bins, frames, 2]`: una máscara compleja por stem con el mismo layout que `spec`
/// (6 stems en BS-RoFormer SW, 1 en el modelo de solista; ver `MaskModelContract`).
///
/// Es la costura con el motor de inferencia: el troceado, el solape (`ChunkPlan`, `OverlapAddAssembler`) y el
/// DSP (`ChunkProcessor`, `SpectralTransform`) solo ven este protocolo. Core ML en el Mac (`CoreMLMaskModel`);
/// en Windows, ONNX Runtime (paso 7) con el mismo contrato, que copiará su tensor de salida con `MaskTensor.copy`.
protocol MaskModel: AnyObject {
    /// Hop, número de stems y nombres del modelo.
    var contract: MaskModelContract { get }
    /// Tramas por trozo; el trozo en muestras es `(frames − 1) · hop`.
    var frames: Int { get }
    /// `spec`: `2·bins·frames·2` floats. `mask`: `stems · 2·bins·frames·2` floats (Float32) a rellenar.
    func predict(spec: UnsafeMutablePointer<Float>, mask: UnsafeMutablePointer<Float>) throws
    /// Motor y opciones, solo para la cabecera de `SeparationTiming` (solo lectura).
    var engineSummary: String { get }
}

/// Carga del modelo de máscaras del sistema a partir del fichero que instala ModelStore.
enum SystemMaskModel {
    static func load(modelURL: URL, contract: MaskModelContract) throws -> MaskModel {
        #if canImport(CoreML)
        return try CoreMLMaskModel(compiledModelURL: modelURL, contract: contract)
        #elseif os(Windows)
        // ONNX Runtime (parte 7.8): `modelURL` es el `.onnx`; las tramas salen del modelo.
        return try OnnxMaskModel(modelURL: modelURL, contract: contract)
        #else
        throw PlatformError.unsupported("sin motor de inferencia en esta plataforma")
        #endif
    }
}

/// Copia de la máscara de salida `[1, stems, rows, frames, 2]` (FP16 o FP32, con strides arbitrarios en
/// elementos) a Float32 contiguo con el layout de `spec`. Independiente del motor: Core ML la llama con el
/// `MLMultiArray`, ONNX Runtime la llamará con el puntero de su tensor.
enum MaskTensor {
    enum Scalar { case float16, float32 }

    static func copy(_ base: UnsafeRawPointer, scalar: Scalar, shape: [Int], strides st: [Int],
                     stems: Int, rows: Int, frames: Int, into mask: UnsafeMutablePointer<Float>) throws {
        guard shape == [1, stems, rows, frames, 2] else {
            throw SeparationError.invalidInput("máscara con forma \(shape), se esperaba [1, \(stems), \(rows), \(frames), 2]")
        }
        guard st.count == 5, st[4] == 1, st[3] >= 2, st[2] >= frames * st[3] else {
            throw SeparationError.invalidInput("máscara con strides no soportados \(st)")
        }
        let rowLen = frames * 2
        switch scalar {
        case .float16:
            // Cada par (re, im) es una "fila" de 2 píxeles con rowBytes = st[3]·2. Si los bins no tienen
            // relleno extra (st[2] = frames·st[3]), un stem entero es una sola imagen.
            let uniform = st[2] == frames * st[3]
            for s in 0..<stems {
                let blocks = uniform ? 1 : rows
                let height = uniform ? rows * frames : frames
                for r in 0..<blocks {
                    var src = ImageBuffer(data: UnsafeMutableRawPointer(mutating: base + (s * st[1] + r * st[2]) * 2),
                                          height: PixelCount(height), width: 2, rowBytes: st[3] * 2)
                    var dst = ImageBuffer(data: mask + (s * rows + r) * rowLen,
                                          height: PixelCount(height), width: 2, rowBytes: 2 * 4)
                    let err = DSP.convertPlanar16FtoPlanarF(&src, &dst)
                    if err != imageNoError { throw SeparationError.invalidInput("FP16→FP32 falló (\(err))") }
                }
            }
        case .float32:
            let f = base.assumingMemoryBound(to: Float.self)
            for s in 0..<stems {
                for r in 0..<rows {
                    let p = UnsafeMutablePointer(mutating: f + s * st[1] + r * st[2])
                    var src = SplitComplex(realp: p, imagp: p + 1)
                    let d = mask + (s * rows + r) * rowLen
                    var dst = SplitComplex(realp: d, imagp: d + 1)
                    DSP.zvmov(&src, DSPStride(st[3]), &dst, 2, DSPLength(frames))
                }
            }
        }
    }
}

#if canImport(CoreML)
/// Un modelo de máscaras RoFormer en Core ML (BS-RoFormer SW, ADR-004, o el de solista), siempre con `.cpuAndGPU`.
final class CoreMLMaskModel: MaskModel {
    let contract: MaskModelContract
    let frames: Int
    private let model: MLModel
    private let outputName: String

    init(compiledModelURL: URL, contract: MaskModelContract = .bsRoformerSW) throws {
        self.contract = contract
        frames = contract.frames
        let config = MLModelConfiguration()
        // ADR-004: Neural Engine prohibido con este modelo (colgó el Mac). Nunca .all ni .cpuAndNeuralEngine.
        // El de solista tampoco se ha probado en el ANE (contrato de tf-ml): misma regla.
        config.computeUnits = .cpuAndGPU
        let model = try MLModel(contentsOf: compiledModelURL, configuration: config)
        let desc = model.modelDescription
        let expectedIn: [NSNumber] = [1, NSNumber(value: 2 * RoformerContract.bins), NSNumber(value: frames), 2]
        guard let input = desc.inputDescriptionsByName[contract.inputName]?.multiArrayConstraint,
              input.shape == expectedIn else {
            throw SeparationError.invalidInput("el modelo no tiene la entrada \(contract.inputName) \(expectedIn)")
        }
        // Salida del contrato; si el modelo la llama distinto y solo hay una, se usa esa.
        if desc.outputDescriptionsByName[contract.outputName] != nil {
            outputName = contract.outputName
        } else if desc.outputDescriptionsByName.count == 1, let only = desc.outputDescriptionsByName.keys.first {
            outputName = only
        } else {
            throw SeparationError.invalidInput("el modelo no tiene la salida \(contract.outputName)")
        }
        self.model = model
    }

    func predict(spec: UnsafeMutablePointer<Float>, mask: UnsafeMutablePointer<Float>) throws {
        let rows = 2 * RoformerContract.bins
        let shape: [NSNumber] = [1, NSNumber(value: rows), NSNumber(value: frames), 2]
        let strides: [NSNumber] = [NSNumber(value: rows * frames * 2), NSNumber(value: frames * 2), 2, 1]
        try autoreleasepool {
            let provider = try SeparationTiming.measure(.prepareInput) {
                let input = try MLMultiArray(dataPointer: spec, shape: shape, dataType: .float32,
                                             strides: strides, deallocator: nil)
                return try MLDictionaryFeatureProvider(dictionary: [contract.inputName: input])
            }
            let out = try SeparationTiming.measureRun { try model.prediction(from: provider) }
            try SeparationTiming.measure(.readOutput) {
                guard let m = out.featureValue(for: outputName)?.multiArrayValue else {
                    throw SeparationError.invalidInput("el modelo no devolvió \(outputName)")
                }
                try Self.copyMask(m, stems: contract.stemCount, rows: rows, frames: frames, into: mask)
            }
        }
    }

    var engineSummary: String { "Core ML, computeUnits .cpuAndGPU (ADR-004), \(frames) tramas" }

    /// Copia la máscara `[1, stems, rows, frames, 2]` (FP16 o FP32) a Float32 contiguo.
    /// Core ML con `.cpuAndGPU` la devuelve con el último eje rellenado: strides medidos en BS-RoFormer
    /// `[453033600, 75505600, 36832, 32, 1]`, es decir, cada par (re, im) ocupa 32 FP16 (64 bytes).
    static func copyMask(_ m: MLMultiArray, stems: Int = RoformerContract.stemCount, rows: Int, frames: Int,
                         into mask: UnsafeMutablePointer<Float>) throws {
        let scalar: MaskTensor.Scalar
        switch m.dataType {
        case .float16: scalar = .float16
        case .float32: scalar = .float32
        default: throw SeparationError.invalidInput("máscara de tipo no soportado \(m.dataType.rawValue)")
        }
        let shape = m.shape.map(\.intValue)
        let st = m.strides.map(\.intValue)
        try m.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            try MaskTensor.copy(base, scalar: scalar, shape: shape, strides: st,
                                stems: stems, rows: rows, frames: frames, into: mask)
        }
    }
}
#endif

/// Modelo simulado: una máscara compleja constante por stem (por defecto 1 + 0i en todos).
/// Sirve a los tests y al modo oculto `--simulate` de tf-separate.
final class ConstantMaskModel: MaskModel {
    let contract: MaskModelContract
    let frames: Int
    let gains: [(re: Float, im: Float)]
    let delay: TimeInterval
    private(set) var calls = 0

    /// `gains` nil: 1 + 0i en los `contract.stemCount` stems.
    init(frames: Int = RoformerContract.frames, contract: MaskModelContract = .bsRoformerSW,
         gains: [(re: Float, im: Float)]? = nil, delay: TimeInterval = 0) {
        let gains = gains ?? Array(repeating: (1, 0), count: contract.stemCount)
        precondition(gains.count == contract.stemCount)
        self.contract = contract
        self.frames = frames
        self.gains = gains
        self.delay = delay
    }

    func predict(spec: UnsafeMutablePointer<Float>, mask: UnsafeMutablePointer<Float>) throws {
        calls += 1
        // El retardo simulado hace de `Run`; rellenar la máscara, de leer la salida.
        SeparationTiming.measureRun { if delay > 0 { Thread.sleep(forTimeInterval: delay) } }
        SeparationTiming.measure(.readOutput) {
            let pairs = 2 * RoformerContract.bins * frames
            for (s, g) in gains.enumerated() {
                var re = g.re, im = g.im
                let base = mask + s * pairs * 2
                DSP.vfill(&re, base, 2, DSPLength(pairs))
                DSP.vfill(&im, base + 1, 2, DSPLength(pairs))
            }
        }
    }

    var engineSummary: String { "simulado (mascara constante), \(frames) tramas, retardo \(Int(delay * 1000)) ms" }
}
