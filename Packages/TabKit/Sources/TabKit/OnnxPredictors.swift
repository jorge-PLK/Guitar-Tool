#if os(Windows)
import Foundation
import NativeONNX

// Predictores de Windows sobre ONNX Runtime (plan, «Corte del paso 7», parte 7.8), con los contratos de los de
// Core ML. Modelos de la parte 7.3: `basic_pitch.onnx` (`serving_default_input_2:0` (b, 43 844, 1) →
// `StatefulPartitionedCall:1` nota y `:2` onset (b, 172, 88), `:0` contorno) y `adtof.onnx` (`spec` (1, T, 84, 1)
// → `act` (1, T, 5)). Basic Pitch: proveedor elegido por `OnnxModelLoader`; si la GPU no cuadra con CPU, se queda en
// CPU. ADTOF: siempre en CPU (ver `OnnxDrumPredictor.loaderEnvironment`).

/// Basic Pitch: ventana de 43 844 muestras → nota y onset [172][88].
final class OnnxBasicPitchPredictor: BasicPitchWindowPredictor, @unchecked Sendable {
    private let session: OnnxSession
    private let inputName: String
    private let noteName: String
    private let onsetName: String

    init(modelURL: URL) throws {
        do {
            session = try OnnxModelLoader.session(modelURL: modelURL, model: "basic_pitch")
        } catch {
            throw TranscriptionError.model("no se pudo cargar \(modelURL.lastPathComponent): \(error)")
        }
        guard session.inputNames.count == 1, let input = session.inputNames.first else {
            throw TranscriptionError.model("entradas inesperadas: \(session.inputNames)")
        }
        // Sin capturar `self` antes de inicializarlo todo (Swift en Windows lo rechaza).
        let outputs = session.outputNames
        func pick(_ names: [String]) throws -> String {
            guard let n = names.first(where: outputs.contains) else {
                throw TranscriptionError.model("falta la salida \(names.joined(separator: "/")) en \(outputs)")
            }
            return n
        }
        let note = try pick(["StatefulPartitionedCall:1", "note", "Identity_1"])
        let onset = try pick(["StatefulPartitionedCall:2", "onset", "Identity_2"])
        inputName = input
        noteName = note
        onsetName = onset
    }

    func predict(window: UnsafeBufferPointer<Float>) throws -> (note: [Float], onset: [Float]) {
        let n = BasicPitchContract.windowSamples, t = BasicPitchContract.windowFrames, f = BasicPitchContract.nPitches
        precondition(window.count == n)
        var note = [Float](repeating: 0, count: t * f), onset = note
        try note.withUnsafeMutableBufferPointer { np in
            try onset.withUnsafeMutableBufferPointer { op in
                try session.run(inputs: [OnnxBuffer(name: inputName, shape: [1, n, 1],
                                                    pointer: UnsafeMutablePointer(mutating: window.baseAddress!))],
                                outputs: [OnnxBuffer(name: noteName, shape: [1, t, f], pointer: np.baseAddress!),
                                          OnnxBuffer(name: onsetName, shape: [1, t, f], pointer: op.baseAddress!)])
            }
        }
        return (note, onset)
    }
}

/// ADTOF Frame_RNN: espectrograma [T][84] → activaciones [T][5].
final class OnnxDrumPredictor: DrumActivationPredictor, @unchecked Sendable {
    private let session: OnnxSession
    private let inputName: String
    private let outputName: String
    /// Tramas de la entrada fija con que se compara GPU frente a CPU (1 s a 100 fps).
    static let probeFrames = 100

    /// Entorno del cargador para ADTOF: proveedor CPU forzado, diga lo que diga `TF_ONNX_PROVIDER`. En CPU, T = 18 000
    /// tramas (3 min) tarda 0,9 s (Temp/win/estado/modelos-analisis.md, hallazgo 2).
    // Siempre CPU (Jorge, 23/11/2026): en DirectML, con T ≥ ~8000 tramas, ADTOF desborda la pila de DirectML.dll (c00000fd).
    static func loaderEnvironment(_ base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        env[OnnxProviderPlan.environmentKey] = OnnxProvider.cpu.rawValue
        return env
    }

    init(modelURL: URL) throws {
        do {
            session = try OnnxModelLoader.session(modelURL: modelURL, model: "adtof", environment: Self.loaderEnvironment()) {
                OnnxProbe.inputs(for: $0, dynamic: [Self.probeFrames])
            }
        } catch {
            throw TranscriptionError.model("no se pudo cargar \(modelURL.lastPathComponent): \(error)")
        }
        let inputs = session.inputNames, outputs = session.outputNames
        guard let input = inputs.contains("spec") ? "spec" : (inputs.count == 1 ? inputs.first : nil) else {
            throw TranscriptionError.model("entradas inesperadas: \(inputs)")
        }
        guard let output = outputs.contains("act") ? "act" : (outputs.count == 1 ? outputs.first : nil) else {
            throw TranscriptionError.model("salidas inesperadas: \(outputs)")
        }
        inputName = input
        outputName = output
    }

    func predict(spectrogram: UnsafeBufferPointer<Float>, frames t: Int) throws -> [Float] {
        let nb = DrumContract.bands, k = DrumContract.classes
        precondition(spectrogram.count == t * nb)
        var act = [Float](repeating: 0, count: t * k)
        try act.withUnsafeMutableBufferPointer { a in
            try session.run(inputs: [OnnxBuffer(name: inputName, shape: [1, t, nb, 1],
                                                pointer: UnsafeMutablePointer(mutating: spectrogram.baseAddress!))],
                            outputs: [OnnxBuffer(name: outputName, shape: [1, t, k], pointer: a.baseAddress!)])
        }
        return act
    }
}
#endif
