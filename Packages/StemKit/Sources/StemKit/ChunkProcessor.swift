import Accelerate
import Foundation

/// Un trozo estéreo → `stemCount` stems estéreo en el dominio del tiempo, como `run_chunk` + la vía `coremlpub`
/// de Probes/P4-modelos/bs_roformer_sw/compare.py:
/// STFT → `spec` → máscara del modelo → producto complejo con el espectro → bin 0 a cero → iSTFT.
/// Hop, tramas y número de stems salen del `MaskModelContract` del modelo (6 en BS-RoFormer SW, 1 en la solista).
final class ChunkProcessor {
    let model: MaskModel
    let frames: Int
    let chunk: Int
    let stemCount: Int
    private let pairsPerStem: Int        // 2·bins·frames números complejos
    private let spec: UnsafeMutablePointer<Float>
    private let mask: UnsafeMutablePointer<Float>
    private let analysis: SpectralTransform
    private let synthesis: [SpectralTransform]   // uno por stem: se procesan en paralelo

    init(model: MaskModel) {
        self.model = model
        let frames = model.frames
        let hop = model.contract.hop
        let stems = model.contract.stemCount
        let chunk = (frames - 1) * hop
        self.frames = frames
        self.chunk = chunk
        stemCount = stems
        pairsPerStem = 2 * RoformerContract.bins * frames
        spec = .allocate(capacity: pairsPerStem * 2)
        spec.initialize(repeating: 0, count: pairsPerStem * 2)
        mask = .allocate(capacity: stems * pairsPerStem * 2)
        mask.initialize(repeating: 0, count: stems * pairsPerStem * 2)
        analysis = SpectralTransform(length: chunk, hop: hop)
        synthesis = (0..<stems).map { _ in SpectralTransform(length: chunk, hop: hop) }
        precondition(analysis.frames == frames)
    }

    deinit {
        spec.deallocate()
        mask.deallocate()
    }

    /// - Parameters:
    ///   - input: 2 canales de `chunk` muestras.
    ///   - outputs: `2·stemCount` búferes de `chunk` muestras, índice `2·stem + canal`.
    func process(input: [UnsafePointer<Float>], outputs: [UnsafeMutablePointer<Float>]) throws {
        precondition(input.count == RoformerContract.channels && outputs.count == 2 * stemCount)
        for c in 0..<RoformerContract.channels {
            analysis.forward(input[c], channel: c, into: spec)
        }
        try model.predict(spec: spec, mask: mask)
        let job = PostprocessJob(spec: spec, mask: mask, pairs: pairsPerStem, frames: frames,
                                 synthesis: synthesis, outputs: outputs)
        DispatchQueue.concurrentPerform(iterations: stemCount) { s in
            job.run(stem: s)
        }
    }
}

/// Trabajo de postproceso por stem. Cada iteración toca solo su bloque de la máscara, su
/// SpectralTransform y sus dos búferes de salida; `spec` solo se lee.
private struct PostprocessJob: @unchecked Sendable {
    let spec: UnsafeMutablePointer<Float>
    let mask: UnsafeMutablePointer<Float>
    let pairs: Int
    let frames: Int
    let synthesis: [SpectralTransform]
    let outputs: [UnsafeMutablePointer<Float>]

    func run(stem s: Int) {
        let m = mask + s * pairs * 2
        // Producto complejo intercalado (re, im): stride 2 sobre los mismos punteros.
        var a = DSPSplitComplex(realp: spec, imagp: spec + 1)
        var b = DSPSplitComplex(realp: m, imagp: m + 1)
        vDSP_zvmul(&a, 2, &b, 2, &b, 2, vDSP_Length(pairs), 1)
        // Bin 0 (DC) a cero en los dos canales: filas 2·0 + 0 y 2·0 + 1, `frames · 2` floats cada una.
        m.update(repeating: 0, count: 2 * frames * 2)
        for c in 0..<RoformerContract.channels {
            synthesis[s].inverse(m, channel: c, into: outputs[2 * s + c])
        }
    }
}
