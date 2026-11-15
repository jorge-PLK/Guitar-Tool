import Accelerate
import CoreML
import Foundation

/// El modelo de máscaras, detrás de un protocolo para poder simularlo en los tests.
/// Contrato (docs/probes/P4-modelos.md): entrada `spec` `[1, 2·bins, frames, 2]` float32;
/// salida `[1, 6, 2·bins, frames, 2]`: una máscara compleja por stem con el mismo layout que `spec`.
protocol MaskModel: AnyObject {
    /// Tramas por trozo; el trozo en muestras es `(frames − 1) · hop`.
    var frames: Int { get }
    /// `spec`: `2·bins·frames·2` floats. `mask`: `6 · 2·bins·frames·2` floats (Float32) a rellenar.
    func predict(spec: UnsafeMutablePointer<Float>, mask: UnsafeMutablePointer<Float>) throws
}

/// El BS-RoFormer SW publicado en Core ML (ADR-004), siempre con `.cpuAndGPU`.
final class CoreMLMaskModel: MaskModel {
    let frames = RoformerContract.frames
    private let model: MLModel
    private let outputName: String

    init(compiledModelURL: URL) throws {
        let config = MLModelConfiguration()
        // ADR-004: Neural Engine prohibido con este modelo (colgó el Mac). Nunca .all ni .cpuAndNeuralEngine.
        config.computeUnits = .cpuAndGPU
        let model = try MLModel(contentsOf: compiledModelURL, configuration: config)
        let desc = model.modelDescription
        let expectedIn: [NSNumber] = [1, NSNumber(value: 2 * RoformerContract.bins), NSNumber(value: frames), 2]
        guard let input = desc.inputDescriptionsByName[RoformerContract.inputName]?.multiArrayConstraint,
              input.shape == expectedIn else {
            throw SeparationError.invalidInput("el modelo no tiene la entrada \(RoformerContract.inputName) \(expectedIn)")
        }
        // Salida del contrato: permute_97; si el modelo la llama distinto y solo hay una, se usa esa.
        if desc.outputDescriptionsByName[RoformerContract.outputName] != nil {
            outputName = RoformerContract.outputName
        } else if desc.outputDescriptionsByName.count == 1, let only = desc.outputDescriptionsByName.keys.first {
            outputName = only
        } else {
            throw SeparationError.invalidInput("el modelo no tiene la salida \(RoformerContract.outputName)")
        }
        self.model = model
    }

    func predict(spec: UnsafeMutablePointer<Float>, mask: UnsafeMutablePointer<Float>) throws {
        let rows = 2 * RoformerContract.bins
        let shape: [NSNumber] = [1, NSNumber(value: rows), NSNumber(value: frames), 2]
        let strides: [NSNumber] = [NSNumber(value: rows * frames * 2), NSNumber(value: frames * 2), 2, 1]
        try autoreleasepool {
            let input = try MLMultiArray(dataPointer: spec, shape: shape, dataType: .float32,
                                         strides: strides, deallocator: nil)
            let provider = try MLDictionaryFeatureProvider(dictionary: [RoformerContract.inputName: input])
            let out = try model.prediction(from: provider)
            guard let m = out.featureValue(for: outputName)?.multiArrayValue else {
                throw SeparationError.invalidInput("el modelo no devolvió \(outputName)")
            }
            try Self.copyMask(m, rows: rows, frames: frames, into: mask)
        }
    }

    /// Copia la máscara `[1, 6, rows, frames, 2]` (FP16 o FP32) a Float32 contiguo.
    /// Core ML con `.cpuAndGPU` la devuelve con el último eje rellenado: strides medidos
    /// `[453033600, 75505600, 36832, 32, 1]`, es decir, cada par (re, im) ocupa 32 FP16 (64 bytes).
    static func copyMask(_ m: MLMultiArray, rows: Int, frames: Int, into mask: UnsafeMutablePointer<Float>) throws {
        let shape = m.shape.map(\.intValue)
        let st = m.strides.map(\.intValue)
        let stems = RoformerContract.stemCount
        guard shape == [1, stems, rows, frames, 2] else {
            throw SeparationError.invalidInput("máscara con forma \(shape), se esperaba [1, \(stems), \(rows), \(frames), 2]")
        }
        guard st[4] == 1, st[3] >= 2, st[2] >= frames * st[3] else {
            throw SeparationError.invalidInput("máscara con strides no soportados \(st)")
        }
        let rowLen = frames * 2
        switch m.dataType {
        case .float16:
            try m.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                // Cada par (re, im) es una "fila" de 2 píxeles con rowBytes = st[3]·2. Si los bins no tienen
                // relleno extra (st[2] = frames·st[3]), un stem entero es una sola imagen.
                let uniform = st[2] == frames * st[3]
                for s in 0..<stems {
                    let blocks = uniform ? 1 : rows
                    let height = uniform ? rows * frames : frames
                    for r in 0..<blocks {
                        var src = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: base + (s * st[1] + r * st[2]) * 2),
                                                height: vImagePixelCount(height), width: 2, rowBytes: st[3] * 2)
                        var dst = vImage_Buffer(data: mask + (s * rows + r) * rowLen,
                                                height: vImagePixelCount(height), width: 2, rowBytes: 2 * 4)
                        let err = vImageConvert_Planar16FtoPlanarF(&src, &dst, vImage_Flags(kvImageNoFlags))
                        if err != kvImageNoError { throw SeparationError.invalidInput("vImage FP16→FP32 falló (\(err))") }
                    }
                }
            }
        case .float32:
            m.withUnsafeBytes { raw in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
                for s in 0..<stems {
                    for r in 0..<rows {
                        var src = DSPSplitComplex(realp: UnsafeMutablePointer(mutating: base + s * st[1] + r * st[2]),
                                                  imagp: UnsafeMutablePointer(mutating: base + s * st[1] + r * st[2] + 1))
                        let d = mask + (s * rows + r) * rowLen
                        var dst = DSPSplitComplex(realp: d, imagp: d + 1)
                        vDSP_zvmov(&src, vDSP_Stride(st[3]), &dst, 2, vDSP_Length(frames))
                    }
                }
            }
        default:
            throw SeparationError.invalidInput("máscara de tipo no soportado \(m.dataType.rawValue)")
        }
    }
}

/// Modelo simulado: una máscara compleja constante por stem (por defecto 1 + 0i en todos).
/// Sirve a los tests y al modo oculto `--simulate` de tf-separate.
final class ConstantMaskModel: MaskModel {
    let frames: Int
    let gains: [(re: Float, im: Float)]
    let delay: TimeInterval
    private(set) var calls = 0

    init(frames: Int = RoformerContract.frames,
         gains: [(re: Float, im: Float)] = Array(repeating: (1, 0), count: RoformerContract.stemCount),
         delay: TimeInterval = 0) {
        precondition(gains.count == RoformerContract.stemCount)
        self.frames = frames
        self.gains = gains
        self.delay = delay
    }

    func predict(spec: UnsafeMutablePointer<Float>, mask: UnsafeMutablePointer<Float>) throws {
        calls += 1
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        let pairs = 2 * RoformerContract.bins * frames
        for (s, g) in gains.enumerated() {
            var re = g.re, im = g.im
            let base = mask + s * pairs * 2
            vDSP_vfill(&re, base, 2, vDSP_Length(pairs))
            vDSP_vfill(&im, base + 1, 2, vDSP_Length(pairs))
        }
    }
}
