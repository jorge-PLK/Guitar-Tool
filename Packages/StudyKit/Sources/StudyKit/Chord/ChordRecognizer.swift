import CoreML
import Foundation

/// Resultado del reconocimiento de acordes: segmentos fusionados y croma por fotograma.
public struct ChordAnalysis: Codable, Sendable, Equatable {
    /// Segmentos consecutivos con la misma etiqueta, en segundos de canción.
    public var segments: [ChordSegment]
    /// Croma de |CQT| plegado a 12 clases (0 = C), `chroma[clase][fotograma]` (mini-spec §1 KeyDetector, paso 1).
    public var chroma: [[Float]]
    /// Duración de un fotograma: 10/108 s.
    public var frameDuration: Double

    public init(segments: [ChordSegment], chroma: [[Float]], frameDuration: Double = 10.0 / 108.0) {
        self.segments = segments
        self.chroma = chroma
        self.frameDuration = frameDuration
    }

    public var frameCount: Int { chroma.first?.count ?? 0 }

    /// Texto `.lab` con el formato de `test.py` de BTC: `"%.3f %.3f %s"`, mayor sin calidad («C#», «F#:7»).
    public var lab: String {
        segments.map { s in
            String(format: "%.3f %.3f %@\n", s.start, s.end, Self.btcName(s.index))
        }.joined()
    }

    /// `idx2voca_chord` de BTC: «C» para C:maj, «C:min»…, «X», «N».
    static func btcName(_ index: Int) -> String {
        guard let l = ChordLabel(index: index) else { return "N" }
        return l.quality == .maj ? l.name : l.labName
    }
}

public enum ChordError: Error, Equatable, Sendable {
    case unreadableAudio(String)
    case model(String)
}

/// Acordes con BTC (vocabulario grande, 170 clases) en Core ML FP16 sobre Neural Engine (ADR-006; mini-spec
/// Fase 2 §1 `ChordRecognizer`; contrato ChordKit de P4).
public actor ChordRecognizer {
    private let modelURL: URL?
    private var predictor: (any ChordWindowPredictor)?

    /// `modelURL`: el `.mlmodelc` de BTC (lo instala ModelKit). Se carga en el primer `analyze`.
    public init(modelURL: URL) {
        self.modelURL = modelURL
    }

    /// Para tests: un predictor simulado en lugar del modelo.
    init(predictor: any ChordWindowPredictor) {
        self.modelURL = nil
        self.predictor = predictor
    }

    /// `stems`: los que se suman (bass + guitar + other + piano), o solo la mezcla. Mismo formato que lea
    /// `AVAudioFile` y misma frecuencia de muestreo entre ellos.
    public func analyze(stems: [URL]) async throws -> ChordAnalysis {
        let wav = try ChordAudio.loadMono(stems)
        try Task.checkCancellation()
        let cqt = LibrosaCQT.shared.chunkedMagnitude(wav)
        try Task.checkCancellation()
        let input = ChordFeatures.normalized(cqt.values)
        let labels = try ChordFeatures.predictLabels(input: input, frames: cqt.frames, with: try loadedPredictor())
        return ChordAnalysis(segments: ChordFeatures.segments(labels),
                             chroma: ChordFeatures.chroma(cqt.values, frames: cqt.frames))
    }

    private func loadedPredictor() throws -> any ChordWindowPredictor {
        if let predictor { return predictor }
        guard let modelURL else { throw ChordError.model("sin modelo") }
        let p = try CoreMLChordPredictor(modelURL: modelURL)
        predictor = p
        return p
    }
}

/// Lo que depende del modelo: una ventana [108 × 144] → logits [108 × 170] (orden C).
protocol ChordWindowPredictor: Sendable {
    func logits(window: UnsafeBufferPointer<Float>) throws -> [Float]
}

/// `BTC_large_voca_fp16`: entrada `cqt` [1, 108, 144] f32, salida `logits` [1, 108, 170].
final class CoreMLChordPredictor: ChordWindowPredictor, @unchecked Sendable {
    private let model: MLModel

    init(modelURL: URL) throws {
        let config = MLModelConfiguration()
        // FP16 en Neural Engine, como P4 (CPU_AND_NE; ADR-006).
        config.computeUnits = .cpuAndNeuralEngine
        do {
            model = try MLModel(contentsOf: modelURL, configuration: config)
        } catch {
            throw ChordError.model("no se pudo cargar \(modelURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func logits(window: UnsafeBufferPointer<Float>) throws -> [Float] {
        let t = ChordContract.windowFrames, f = ChordContract.nBins, c = ChordContract.nChords
        let input = try MLMultiArray(shape: [1, NSNumber(value: t), NSNumber(value: f)], dataType: .float32)
        input.withUnsafeMutableBytes { raw, strides in
            precondition(strides.last == 1 && strides[1] == f)
            raw.baseAddress!.assumingMemoryBound(to: Float.self).update(from: window.baseAddress!, count: t * f)
        }
        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["cqt": input]))
        guard let m = out.featureValue(for: "logits")?.multiArrayValue else {
            throw ChordError.model("falta la salida logits")
        }
        guard m.count == t * c, m.shape.count == 3 else {
            throw ChordError.model("salida de forma \(m.shape), se esperaba [1, \(t), \(c)]")
        }
        let s1 = m.strides[1].intValue, s2 = m.strides[2].intValue
        var res = [Float](repeating: 0, count: t * c)
        switch m.dataType {
        case .float32:
            m.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: Float.self)
                for i in 0..<t { for j in 0..<c { res[i * c + j] = p[i * s1 + j * s2] } }
            }
        case .float16:
            m.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: Float16.self)
                for i in 0..<t { for j in 0..<c { res[i * c + j] = Float(p[i * s1 + j * s2]) } }
            }
        default:
            for i in 0..<t { for j in 0..<c { res[i * c + j] = m[[0, NSNumber(value: i), NSNumber(value: j)]].floatValue } }
        }
        return res
    }
}

/// Preproceso y postproceso de BTC sin el modelo.
enum ChordFeatures {
    /// (log(|CQT| + 1e-6) − mean) / std, en float32 como numpy. Mismo orden tiempo × bin.
    static func normalized(_ cqt: [Float]) -> [Float] {
        let m = ChordContract.featureMean, s = ChordContract.featureStd, e = ChordContract.logEpsilon
        return cqt.map { (log($0 + e) - m) / s }
    }

    /// Ventanas de 108 sin solape (la última rellena con ceros), argmax por fotograma; solo las tramas válidas.
    static func predictLabels(input: [Float], frames: Int, with predictor: any ChordWindowPredictor) throws -> [Int] {
        let t = ChordContract.windowFrames, f = ChordContract.nBins, c = ChordContract.nChords
        precondition(input.count == frames * f)
        var labels: [Int] = []
        labels.reserveCapacity(frames)
        var window = [Float](repeating: 0, count: t * f)
        var start = 0
        while start < frames {
            try Task.checkCancellation()
            let n = min(t, frames - start)
            window.withUnsafeMutableBufferPointer { w in
                input.withUnsafeBufferPointer { src in
                    w.baseAddress!.update(from: src.baseAddress! + start * f, count: n * f)
                }
                (w.baseAddress! + n * f).update(repeating: 0, count: (t - n) * f)
            }
            let logits = try window.withUnsafeBufferPointer { try predictor.logits(window: $0) }
            guard logits.count == t * c else { throw ChordError.model("logits de \(logits.count) valores") }
            for i in 0..<n { labels.append(argmax(logits, offset: i * c, count: c)) }
            start += t
        }
        return labels
    }

    /// Primer máximo (como `np.argmax`).
    static func argmax(_ x: [Float], offset: Int, count: Int) -> Int {
        var best = 0
        var v = x[offset]
        for j in 1..<count where x[offset + j] > v {
            v = x[offset + j]
            best = j
        }
        return best
    }

    /// Fotogramas consecutivos iguales → un segmento [i·Δ, j·Δ) con Δ = 10/108 s exactos.
    static func segments(_ labels: [Int], frameDuration d: Double = ChordContract.frameDuration) -> [ChordSegment] {
        guard !labels.isEmpty else { return [] }
        var out: [ChordSegment] = []
        var s = 0
        for i in 1...labels.count {
            if i == labels.count || labels[i] != labels[s] {
                out.append(ChordSegment(start: Double(s) * d, end: Double(i) * d, index: labels[s]))
                s = i
            }
        }
        return out
    }

    /// Bin k (fmin C1, 24 por octava) → clase (k div 2) mod 12, 0 = C (mini-spec §1 KeyDetector, paso 1).
    static func chroma(_ cqt: [Float], frames: Int) -> [[Float]] {
        let f = ChordContract.nBins
        var out = [[Float]](repeating: [Float](repeating: 0, count: frames), count: 12)
        for t in 0..<frames {
            for k in 0..<f { out[(k / 2) % 12][t] += cqt[t * f + k] }
        }
        return out
    }
}
