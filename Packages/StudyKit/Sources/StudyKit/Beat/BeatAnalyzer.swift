import CoreML
import Foundation

/// Pulso y compás con Beat This! `final0` (mini-spec Fase 2 §1 StudyKit; ADR-006): log-mel, troceado de 1500
/// tramas con borde 6, `mlmodelc` comunitario en CPU+GPU FP32 y postproceso «minimal».
public actor BeatAnalyzer {
    private let modelURL: URL?
    private var predictor: (any BeatFramePredictor)?

    /// `modelURL`: el `.mlmodelc` de Beat This! (lo instala ModelKit). Se carga en el primer `analyze`.
    public init(modelURL: URL) {
        self.modelURL = modelURL
    }

    /// Para tests: un predictor simulado en lugar del modelo.
    init(predictor: any BeatFramePredictor) {
        self.modelURL = nil
        self.predictor = predictor
    }

    /// Analiza la mezcla (cualquier formato que lea `AVAudioFile`). Tiempos en segundos de canción.
    public func analyze(mix: URL) async throws -> BeatGrid {
        let samples = try BeatAudio.loadMono(mix)
        try Task.checkCancellation()
        let spect = try BeatLogMel.shared.compute(samples)
        try Task.checkCancellation()
        let logits = try BeatChunker.predict(spect: spect.values, frames: spect.frames, with: try loadedPredictor())
        let (beats, downbeats) = BeatPostprocessor.minimal(beat: logits.beat, downbeat: logits.downbeat)
        return BeatGrid(beats: beats, downbeats: downbeats)
    }

    private func loadedPredictor() throws -> any BeatFramePredictor {
        if let predictor { return predictor }
        let p = try CoreMLBeatPredictor(modelURL: modelURL!)
        predictor = p
        return p
    }
}

/// Lo que depende del modelo: un trozo de [1500 × 128] → logits `beat` y `downbeat` de 1500 tramas.
protocol BeatFramePredictor: Sendable {
    func predict(chunk: UnsafeBufferPointer<Float>) throws -> (beat: [Float], downbeat: [Float])
}

/// `BeatThis.mlmodelc`: entrada `spect` [1, 1500, 128] f32, salidas `beat` y `downbeat` [1, 1500].
final class CoreMLBeatPredictor: BeatFramePredictor, @unchecked Sendable {
    private let model: MLModel

    init(modelURL: URL) throws {
        let config = MLModelConfiguration()
        // CPU+GPU y FP32: en FP16 la atención da ruido (README del modelo, ADR-006).
        config.computeUnits = .cpuAndGPU
        config.allowLowPrecisionAccumulationOnGPU = false
        do {
            model = try MLModel(contentsOf: modelURL, configuration: config)
        } catch {
            throw BeatError.model("no se pudo cargar \(modelURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func predict(chunk: UnsafeBufferPointer<Float>) throws -> (beat: [Float], downbeat: [Float]) {
        let n = BeatContract.chunk
        let input = try MLMultiArray(shape: [1, NSNumber(value: n), NSNumber(value: BeatContract.nMels)], dataType: .float32)
        input.withUnsafeMutableBytes { raw, strides in
            // Contiguo en C: strides [n·128, 128, 1].
            precondition(strides.last == 1 && strides[1] == BeatContract.nMels)
            raw.baseAddress!.assumingMemoryBound(to: Float.self).update(from: chunk.baseAddress!, count: chunk.count)
        }
        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["spect": input]))
        guard let b = out.featureValue(for: "beat")?.multiArrayValue,
              let d = out.featureValue(for: "downbeat")?.multiArrayValue else {
            throw BeatError.model("faltan las salidas beat/downbeat")
        }
        return (try Self.floats(b, count: n), try Self.floats(d, count: n))
    }

    private static func floats(_ m: MLMultiArray, count: Int) throws -> [Float] {
        guard m.count == count else { throw BeatError.model("salida de \(m.count) tramas, se esperaban \(count)") }
        let stride = m.strides.last?.intValue ?? 1
        switch m.dataType {
        case .float32:
            return m.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: Float.self)
                return (0..<count).map { p[$0 * stride] }
            }
        case .float16:
            return m.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: Float16.self)
                return (0..<count).map { Float(p[$0 * stride]) }
            }
        default:
            return (0..<count).map { m[$0].floatValue }
        }
    }
}

/// Troceado y agregado oficiales (`split_piece(avoid_short_end=True)` + `aggregate_prediction("keep_first")`).
enum BeatChunker {
    /// Inicios de trozo (pueden ser negativos: relleno a la izquierda).
    static func starts(frames t: Int, chunk: Int = BeatContract.chunk, border: Int = BeatContract.border) -> [Int] {
        let step = chunk - 2 * border
        var s = Array(stride(from: -border, to: t - border, by: step))
        if s.isEmpty { s = [-border] }
        if t > step { s[s.count - 1] = t - (chunk - border) }
        return s
    }

    /// Ejecuta el predictor sobre cada trozo y devuelve logits por trama (T). Cada trozo es
    /// spect[max(s,0) ..< min(s+1500, T)] con max(0, −s) ceros a la izquierda y max(0, min(6, s+1500−T)) a la
    /// derecha; el modelo tiene entrada fija, así que se completa con ceros hasta 1500 y la salida se recorta.
    static func predict(spect: [Float], frames t: Int, with predictor: any BeatFramePredictor)
        throws -> (beat: [Float], downbeat: [Float]) {
        let chunk = BeatContract.chunk, border = BeatContract.border, nMels = BeatContract.nMels
        precondition(spect.count == t * nMels)
        var beat = [Float](repeating: -1000, count: t)
        var downbeat = [Float](repeating: -1000, count: t)
        var buffer = [Float](repeating: 0, count: chunk * nMels)
        // keep_first: en orden inverso, para que los trozos anteriores sobrescriban el solape.
        for s in starts(frames: t).reversed() {
            let lo = max(s, 0), hi = min(s + chunk, t)
            let left = max(0, -s), right = max(0, min(border, s + chunk - t))
            let length = left + (hi - lo) + right
            buffer.withUnsafeMutableBufferPointer { b in
                b.update(repeating: 0)
                spect.withUnsafeBufferPointer { src in
                    (b.baseAddress! + left * nMels).update(from: src.baseAddress! + lo * nMels, count: (hi - lo) * nMels)
                }
            }
            let out = try buffer.withUnsafeBufferPointer { try predictor.predict(chunk: $0) }
            // Se quita el borde de 6 a cada lado del trozo de `length` tramas.
            let dst = s + border
            let n = min(length - 2 * border, t - dst)
            for i in 0..<max(n, 0) {
                beat[dst + i] = out.beat[border + i]
                downbeat[dst + i] = out.downbeat[border + i]
            }
            try Task.checkCancellation()
        }
        return (beat, downbeat)
    }
}

/// Postproceso «minimal» de `beat_this` (`Postprocessor.postp_minimal`).
enum BeatPostprocessor {
    static func minimal(beat: [Float], downbeat: [Float]) -> (beats: [Double], downbeats: [Double]) {
        let beats = peaks(beat).map { $0 / BeatContract.fps }
        var downs = peaks(downbeat).map { $0 / BeatContract.fps }
        // Cada downbeat al pulso más cercano (el primero en caso de empate, como argmin); luego sin repetidos.
        if !beats.isEmpty {
            downs = downs.map { d in
                var best = 0
                for i in 1..<beats.count where abs(beats[i] - d) < abs(beats[best] - d) { best = i }
                return beats[best]
            }
        }
        return (beats, Array(Set(downs)).sorted())
    }

    /// Máximos locales en ventana de 7 (±3 tramas, fuera del borde cuenta como −∞) con logit > 0;
    /// los picos adyacentes (separados ≤ 1 trama) se funden en su media. Devuelve tramas (pueden ser x,5).
    static func peaks(_ x: [Float]) -> [Double] {
        let n = x.count, half = 3
        var frames = [Int]()
        for i in 0..<n where x[i] > 0 {
            var m = x[i]
            for j in max(0, i - half)...min(n - 1, i + half) { m = max(m, x[j]) }
            if x[i] == m { frames.append(i) }
        }
        // deduplicate_peaks(width=1): media incremental del grupo; se compara con la media, no con el último
        // (literal del oficial: 10, 11, 12 → 10,5 y 12).
        var result = [Double]()
        guard var p = frames.first.map(Double.init) else { return result }
        var c = 1.0
        for f in frames.dropFirst() {
            if Double(f) - p <= 1 {
                c += 1
                p += (Double(f) - p) / c
            } else {
                result.append(p)
                p = Double(f)
                c = 1
            }
        }
        result.append(p)
        return result
    }
}
