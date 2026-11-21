#if os(Windows)
import Foundation
import NativeONNX

// Predictores de Windows sobre ONNX Runtime (plan, «Corte del paso 7», parte 7.8), con los mismos contratos que los
// de Core ML. Modelos de la parte 7.3: `beat_this.onnx` (`spect` (ventanas, tramas, 128) → `beat`, `downbeat`) y
// `btc.onnx` (`cqt` (n, 108, 144) → `logits` (n, 108, 170)). Proveedor elegido por `OnnxModelLoader`.

/// Beat This!: un trozo [1500 × 128] → logits `beat` y `downbeat` de 1500 tramas.
final class OnnxBeatPredictor: BeatFramePredictor, @unchecked Sendable {
    private let session: OnnxSession

    init(modelURL: URL) throws {
        do {
            session = try OnnxModelLoader.session(modelURL: modelURL, model: "beat_this") {
                OnnxProbe.inputs(for: $0, dynamic: [1, BeatContract.chunk])
            }
        } catch {
            throw BeatError.model("no se pudo cargar \(modelURL.lastPathComponent): \(error)")
        }
    }

    func predict(chunk: UnsafeBufferPointer<Float>) throws -> (beat: [Float], downbeat: [Float]) {
        let n = BeatContract.chunk
        guard chunk.count == n * BeatContract.nMels else {
            throw BeatError.model("trozo de \(chunk.count) valores, se esperaban \(n * BeatContract.nMels)")
        }
        var beat = [Float](repeating: 0, count: n), downbeat = beat
        try beat.withUnsafeMutableBufferPointer { b in
            try downbeat.withUnsafeMutableBufferPointer { d in
                try session.run(inputs: [OnnxBuffer(name: "spect", shape: [1, n, BeatContract.nMels],
                                                    pointer: UnsafeMutablePointer(mutating: chunk.baseAddress!))],
                                outputs: [OnnxBuffer(name: "beat", shape: [1, n], pointer: b.baseAddress!),
                                          OnnxBuffer(name: "downbeat", shape: [1, n], pointer: d.baseAddress!)])
            }
        }
        return (beat, downbeat)
    }
}

/// BTC: una ventana [108 × 144] → logits [108 × 170] (orden C).
final class OnnxChordPredictor: ChordWindowPredictor, @unchecked Sendable {
    private let session: OnnxSession

    init(modelURL: URL) throws {
        do {
            session = try OnnxModelLoader.session(modelURL: modelURL, model: "btc")
        } catch {
            throw ChordError.model("no se pudo cargar \(modelURL.lastPathComponent): \(error)")
        }
    }

    func logits(window: UnsafeBufferPointer<Float>) throws -> [Float] {
        let t = ChordContract.windowFrames, f = ChordContract.nBins, c = ChordContract.nChords
        guard window.count >= t * f else { throw ChordError.model("ventana de \(window.count) valores, se esperaban \(t * f)") }
        var res = [Float](repeating: 0, count: t * c)
        try res.withUnsafeMutableBufferPointer { r in
            try session.run(inputs: [OnnxBuffer(name: "cqt", shape: [1, t, f],
                                                pointer: UnsafeMutablePointer(mutating: window.baseAddress!))],
                            outputs: [OnnxBuffer(name: "logits", shape: [1, t, c], pointer: r.baseAddress!)])
        }
        return res
    }
}
#endif
