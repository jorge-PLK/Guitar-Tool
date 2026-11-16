import CoreML
import Foundation

public enum TranscriptionError: Error, Equatable, Sendable {
    case unreadableAudio(String)
    case model(String)
}

/// Transcripción a notas con Basic Pitch (Spotify, ICASSP 2022) en Core ML: el troceado con solape de
/// `run_inference` y el paso posteriorgramas → notas de `output_to_notes_polyphonic`, con los umbrales por defecto
/// (mini-spec Fase 4, «Clasificación rítmica o solista»). Lo reutiliza la Fase 5.
public actor BasicPitchTranscriber {
    private let modelURL: URL?
    private let computeUnits: MLComputeUnits
    private var predictor: (any BasicPitchWindowPredictor)?

    /// `modelURL`: el `.mlmodelc` de Basic Pitch (lo instala ModelKit). Se carga en el primer `transcribe`.
    /// Por defecto CPU+GPU, las unidades con las que `tf-ml` validó el modelo frente a Python.
    public init(modelURL: URL, computeUnits: MLComputeUnits = .cpuAndGPU) {
        self.modelURL = modelURL
        self.computeUnits = computeUnits
    }

    /// Para tests: un predictor simulado en lugar del modelo.
    init(predictor: any BasicPitchWindowPredictor) {
        self.modelURL = nil
        self.computeUnits = .cpuOnly
        self.predictor = predictor
    }

    /// Cualquier formato que lea `AVAudioFile`; se pasa a mono (media de canales) y a 22 050 Hz.
    /// Notas ordenadas por inicio y nota.
    public func transcribe(url: URL) async throws -> [NoteEvent] {
        let audio = try MonoAudio.load(url, sampleRate: BasicPitchContract.sampleRate)
        try Task.checkCancellation()
        let post = try posteriorgram(audio: audio)
        try Task.checkCancellation()
        return BasicPitchNotes.noteEvents(post).sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
    }

    /// Posteriorgramas desenrollados de un audio mono a 22 050 Hz.
    func posteriorgram(audio: [Float]) throws -> Posteriorgram {
        try BasicPitchWindowing.posteriorgram(audio: audio, with: try loadedPredictor())
    }

    private func loadedPredictor() throws -> any BasicPitchWindowPredictor {
        if let predictor { return predictor }
        guard let modelURL else { throw TranscriptionError.model("sin modelo") }
        let p = try CoreMLBasicPitchPredictor(modelURL: modelURL, computeUnits: computeUnits)
        predictor = p
        return p
    }
}

/// Salidas `note` y `onset` desenrolladas, [fotograma][88] en orden C, como las de `run_inference`.
struct Posteriorgram: Sendable {
    var frames: Int
    var note: [Float]
    var onset: [Float]
}

/// Lo que depende del modelo: una ventana de 43 844 muestras → `note` y `onset` [172 × 88] (orden C).
protocol BasicPitchWindowPredictor: Sendable {
    func predict(window: UnsafeBufferPointer<Float>) throws -> (note: [Float], onset: [Float])
}

/// Troceado de `get_audio_input` / `window_audio_file` y desenrollado de `unwrap_output`.
enum BasicPitchWindowing {
    typealias C = BasicPitchContract

    /// Audio con 3 840 ceros delante, ventanas de 43 844 cada 36 164 muestras (la última rellena con ceros),
    /// 15 fotogramas fuera por cada lado, concatenadas y recortadas a floor(n · 86 / 22 050).
    static func posteriorgram(audio: [Float], with predictor: any BasicPitchWindowPredictor) throws -> Posteriorgram {
        let p = C.nPitches
        let outFrames = C.outputFrames(forSamples: audio.count)
        let padded = [Float](repeating: 0, count: C.overlapSamples / 2) + audio
        var note = [Float](), onset = [Float]()
        note.reserveCapacity((outFrames + C.keptFramesPerWindow) * p)
        onset.reserveCapacity((outFrames + C.keptFramesPerWindow) * p)
        var window = [Float](repeating: 0, count: C.windowSamples)
        var start = 0
        // `range(0, len(audio_original), hop_size)`; se para antes si ya hay fotogramas de sobra.
        while start < padded.count && note.count < outFrames * p {
            try Task.checkCancellation()
            let n = min(C.windowSamples, padded.count - start)
            window.withUnsafeMutableBufferPointer { w in
                padded.withUnsafeBufferPointer { src in w.baseAddress!.update(from: src.baseAddress! + start, count: n) }
                (w.baseAddress! + n).update(repeating: 0, count: C.windowSamples - n)
            }
            let out = try window.withUnsafeBufferPointer { try predictor.predict(window: $0) }
            guard out.note.count == C.windowFrames * p, out.onset.count == C.windowFrames * p else {
                throw TranscriptionError.model("salida de \(out.note.count)/\(out.onset.count) valores, se esperaban \(C.windowFrames * p)")
            }
            let kept = (C.trimFrames * p)..<((C.windowFrames - C.trimFrames) * p)
            note.append(contentsOf: out.note[kept])
            onset.append(contentsOf: out.onset[kept])
            start += C.hopSamples
        }
        if note.count > outFrames * p {
            note.removeLast(note.count - outFrames * p)
            onset.removeLast(onset.count - outFrames * p)
        }
        return Posteriorgram(frames: note.count / p, note: note, onset: onset)
    }
}

/// `nmp` de basic-pitch: entrada `input_2` [1, 43 844, 1] f32; salidas `Identity_1` (note) e `Identity_2` (onset)
/// [1, 172, 88] (`Identity` es contour, que aquí no hace falta). Admite también salidas llamadas `note` y `onset`.
final class CoreMLBasicPitchPredictor: BasicPitchWindowPredictor, @unchecked Sendable {
    private let model: MLModel
    private let inputName: String
    private let noteName: String
    private let onsetName: String

    init(modelURL: URL, computeUnits: MLComputeUnits) throws {
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits
        do {
            model = try MLModel(contentsOf: modelURL, configuration: config)
        } catch {
            throw TranscriptionError.model("no se pudo cargar \(modelURL.lastPathComponent): \(error.localizedDescription)")
        }
        let inputs = model.modelDescription.inputDescriptionsByName
        let outputs = Set(model.modelDescription.outputDescriptionsByName.keys)
        guard let input = inputs["input_2"] != nil ? "input_2" : (inputs.count == 1 ? inputs.keys.first : nil) else {
            throw TranscriptionError.model("entradas inesperadas: \(inputs.keys.sorted())")
        }
        func pick(_ names: [String]) throws -> String {
            guard let n = names.first(where: outputs.contains) else {
                throw TranscriptionError.model("falta la salida \(names.joined(separator: "/")) en \(outputs.sorted())")
            }
            return n
        }
        inputName = input
        noteName = try pick(["note", "Identity_1"])
        onsetName = try pick(["onset", "Identity_2"])
    }

    func predict(window: UnsafeBufferPointer<Float>) throws -> (note: [Float], onset: [Float]) {
        let n = BasicPitchContract.windowSamples
        precondition(window.count == n)
        let input = try MLMultiArray(shape: [1, NSNumber(value: n), 1], dataType: .float32)
        input.withUnsafeMutableBytes { raw, strides in
            precondition(strides[1] == 1)
            raw.baseAddress!.assumingMemoryBound(to: Float.self).update(from: window.baseAddress!, count: n)
        }
        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [inputName: input]))
        return (try Self.matrix(out, noteName), try Self.matrix(out, onsetName))
    }

    /// [1, 172, 88] → 172 · 88 valores en orden C, sea cual sea el tipo y los strides de Core ML.
    private static func matrix(_ out: MLFeatureProvider, _ name: String) throws -> [Float] {
        let t = BasicPitchContract.windowFrames, f = BasicPitchContract.nPitches
        guard let m = out.featureValue(for: name)?.multiArrayValue else { throw TranscriptionError.model("falta la salida \(name)") }
        guard m.count == t * f, m.shape.count == 3 else {
            throw TranscriptionError.model("\(name) de forma \(m.shape), se esperaba [1, \(t), \(f)]")
        }
        let s1 = m.strides[1].intValue, s2 = m.strides[2].intValue
        var res = [Float](repeating: 0, count: t * f)
        switch m.dataType {
        case .float32:
            m.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: Float.self)
                for i in 0..<t { for j in 0..<f { res[i * f + j] = p[i * s1 + j * s2] } }
            }
        case .float16:
            m.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: Float16.self)
                for i in 0..<t { for j in 0..<f { res[i * f + j] = Float(p[i * s1 + j * s2]) } }
            }
        default:
            for i in 0..<t { for j in 0..<f { res[i * f + j] = m[[0, NSNumber(value: i), NSNumber(value: j)]].floatValue } }
        }
        return res
    }
}
