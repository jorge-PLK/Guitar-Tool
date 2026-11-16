import CoreML
import Foundation

/// Transcripción de batería con ADTOF Frame_RNN en Core ML FP32 (mini-spec Fase 5, «Transcripción», Batería):
/// audio → espectrograma logarítmico → activaciones de 5 piezas a 100 fps → golpes.
public actor DrumTranscriber {
    private let modelURL: URL?
    private let maxFrames: Int
    private let contextFrames: Int
    private var predictor: (any DrumActivationPredictor)?

    /// `modelURL`: el `.mlmodelc` de ADTOF (lo instala ModelKit, `ModelCatalog.drumsADTOF`). Se carga en el primer
    /// `transcribe`, siempre en `.cpuOnly`: la GPU calcula mal la GRU nativa (P4-modelos, «Batería (ADTOF)»).
    public init(modelURL: URL) {
        self.modelURL = modelURL
        self.maxFrames = DrumContract.maxModelFrames
        self.contextFrames = DrumContract.chunkContextFrames
    }

    /// Para tests: un predictor simulado o trozos más cortos que los 60 000 del contrato.
    init(predictor: (any DrumActivationPredictor)?, modelURL: URL? = nil,
         maxFrames: Int = DrumContract.maxModelFrames, contextFrames: Int = DrumContract.chunkContextFrames) {
        self.modelURL = modelURL
        self.predictor = predictor
        self.maxFrames = maxFrames
        self.contextFrames = contextFrames
    }

    /// Cualquier formato que lea `AVAudioFile`; se pasa a mono (media de canales) y, si hace falta, a 44,1 kHz.
    /// Golpes ordenados por (tiempo, nota). `progress` (opcional) va de 0 a 1 y se llama desde este actor.
    public func transcribe(url: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws -> [TranscribedDrumHit] {
        let audio = try MonoAudio.load(url, sampleRate: DrumContract.sampleRate)
        try Task.checkCancellation()
        progress?(0.1)
        let spec = DrumSpectrogram.compute(audio)
        let frames = DrumContract.frames(forSamples: audio.count)
        try Task.checkCancellation()
        progress?(0.2)
        let act = try activations(spectrogram: spec, frames: frames) { progress?(0.2 + 0.75 * $0) }
        try Task.checkCancellation()
        let hits = DrumPeaks.hits(activations: act, frames: frames)
        progress?(1)
        return hits
    }

    /// Activaciones [T][5] de un espectrograma [T][84], por trozos si T supera el máximo del modelo.
    func activations(spectrogram: [Float], frames: Int, progress: (Double) -> Void = { _ in }) throws -> [Float] {
        try DrumChunking.activations(spectrogram: spectrogram, frames: frames, predictor: try loadedPredictor(),
                                     maxFrames: maxFrames, contextFrames: contextFrames, progress: progress)
    }

    private func loadedPredictor() throws -> any DrumActivationPredictor {
        if let predictor { return predictor }
        guard let modelURL else { throw TranscriptionError.model("sin modelo") }
        let p = try CoreMLDrumPredictor(modelURL: modelURL)
        predictor = p
        return p
    }
}

/// Lo que depende del modelo: espectrograma [T][84] → activaciones [T][5] (orden C), T entre 100 y 60 000.
protocol DrumActivationPredictor: Sendable {
    func predict(spectrogram: UnsafeBufferPointer<Float>, frames: Int) throws -> [Float]
}

/// Troceo para temas de más de 60 000 tramas (10 min): cada trozo lleva `context` tramas extra a cada lado (la GRU
/// es bidireccional) y de él solo se queda la parte central; las partes centrales se tocan sin hueco ni solape.
/// Por debajo del máximo hay un único trozo y el resultado es el del modelo entero.
enum DrumChunking {
    struct Chunk: Equatable, Sendable {
        /// Tramas que entran al modelo.
        var input: Range<Int>
        /// Tramas cuya activación se queda (dentro de `input`).
        var keep: Range<Int>
    }

    static func plan(frames: Int, maxFrames: Int, context: Int) -> [Chunk] {
        guard frames > maxFrames else { return [Chunk(input: 0..<frames, keep: 0..<frames)] }
        precondition(maxFrames > 2 * context, "trozos de \(maxFrames) tramas no caben con \(context) de contexto")
        var chunks = [Chunk]()
        var start = 0
        while start < frames {
            // Cada trozo entra con `maxFrames` tramas: contexto delante (salvo al principio del tema), la parte que
            // se queda y contexto detrás; el último se queda hasta el final si cabe entero.
            let lead = min(context, start)
            let end = frames - (start - lead) <= maxFrames ? frames : start + maxFrames - lead - context
            chunks.append(Chunk(input: (start - lead)..<min(frames, end + context), keep: start..<end))
            start = end
        }
        return chunks
    }

    static func activations(spectrogram spec: [Float], frames: Int, predictor: any DrumActivationPredictor,
                            maxFrames: Int, contextFrames: Int, progress: (Double) -> Void = { _ in }) throws -> [Float] {
        let nb = DrumContract.bands, k = DrumContract.classes, minT = DrumContract.minModelFrames
        precondition(spec.count == frames * nb, "espectrograma de \(spec.count) valores, se esperaban \(frames) × \(nb)")
        let chunks = plan(frames: frames, maxFrames: maxFrames, context: contextFrames)
        var act = [Float](repeating: 0, count: frames * k)
        for (i, ch) in chunks.enumerated() {
            try Task.checkCancellation()
            // Menos de 100 tramas (audio de menos de 1 s): se completa con silencio (log10(1 + 0) = 0) y se recorta.
            let n = ch.input.count, padded = max(n, minT)
            var input = [Float](repeating: 0, count: padded * nb)
            input.withUnsafeMutableBufferPointer { dst in
                spec.withUnsafeBufferPointer { src in
                    dst.baseAddress!.update(from: src.baseAddress! + ch.input.lowerBound * nb, count: n * nb)
                }
            }
            let out = try input.withUnsafeBufferPointer { try predictor.predict(spectrogram: $0, frames: padded) }
            guard out.count == padded * k else {
                throw TranscriptionError.model("salida de \(out.count) valores, se esperaban \(padded) × \(k)")
            }
            let offset = ch.keep.lowerBound - ch.input.lowerBound
            act.withUnsafeMutableBufferPointer { dst in
                out.withUnsafeBufferPointer { src in
                    (dst.baseAddress! + ch.keep.lowerBound * k).update(from: src.baseAddress! + offset * k, count: ch.keep.count * k)
                }
            }
            progress(Double(i + 1) / Double(chunks.count))
        }
        return act
    }
}

/// ADTOF Frame_RNN FP32 con GRU nativa: entrada `spec` [1, T, 84, 1] f32, salida `act` [1, T, 5] (sigmoide).
final class CoreMLDrumPredictor: DrumActivationPredictor, @unchecked Sendable {
    private let model: MLModel
    private let inputName: String
    private let outputName: String

    init(modelURL: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        do {
            model = try MLModel(contentsOf: modelURL, configuration: config)
        } catch {
            throw TranscriptionError.model("no se pudo cargar \(modelURL.lastPathComponent): \(error.localizedDescription)")
        }
        let inputs = model.modelDescription.inputDescriptionsByName
        let outputs = model.modelDescription.outputDescriptionsByName
        guard let input = inputs["spec"] != nil ? "spec" : (inputs.count == 1 ? inputs.keys.first : nil) else {
            throw TranscriptionError.model("entradas inesperadas: \(inputs.keys.sorted())")
        }
        guard let output = outputs["act"] != nil ? "act" : (outputs.count == 1 ? outputs.keys.first : nil) else {
            throw TranscriptionError.model("salidas inesperadas: \(outputs.keys.sorted())")
        }
        inputName = input
        outputName = output
    }

    func predict(spectrogram: UnsafeBufferPointer<Float>, frames t: Int) throws -> [Float] {
        let nb = DrumContract.bands, k = DrumContract.classes
        precondition(spectrogram.count == t * nb)
        let input = try MLMultiArray(shape: [1, NSNumber(value: t), NSNumber(value: nb), 1], dataType: .float32)
        input.withUnsafeMutableBytes { raw, strides in
            let dst = raw.baseAddress!.assumingMemoryBound(to: Float.self)
            if strides[1] == nb && strides[2] == 1 {
                dst.update(from: spectrogram.baseAddress!, count: t * nb)
            } else {
                for i in 0..<t { for j in 0..<nb { dst[i * strides[1] + j * strides[2]] = spectrogram[i * nb + j] } }
            }
        }
        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [inputName: input]))
        guard let m = out.featureValue(for: outputName)?.multiArrayValue else {
            throw TranscriptionError.model("falta la salida \(outputName)")
        }
        guard m.shape.count == 3, m.count == t * k else {
            throw TranscriptionError.model("\(outputName) de forma \(m.shape), se esperaba [1, \(t), \(k)]")
        }
        // [1, T, 5] → T · 5 valores en orden C, sea cual sea el tipo y los strides de Core ML.
        let s1 = m.strides[1].intValue, s2 = m.strides[2].intValue
        var res = [Float](repeating: 0, count: t * k)
        switch m.dataType {
        case .float32:
            m.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: Float.self)
                for i in 0..<t { for j in 0..<k { res[i * k + j] = p[i * s1 + j * s2] } }
            }
        case .float16:
            m.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: Float16.self)
                for i in 0..<t { for j in 0..<k { res[i * k + j] = Float(p[i * s1 + j * s2]) } }
            }
        default:
            for i in 0..<t { for j in 0..<k { res[i * k + j] = m[[0, NSNumber(value: i), NSNumber(value: j)]].floatValue } }
        }
        return res
    }
}
