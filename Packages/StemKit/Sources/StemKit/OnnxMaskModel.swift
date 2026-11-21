#if os(Windows)
import Foundation
import NativeONNX

/// `MaskModel` de Windows sobre ONNX Runtime (plan, «Corte del paso 7», parte 7.8). Dos interfaces:
/// - separación (`spec_real`/`spec_imag` → `out_spec_real`/`out_spec_imag`, espectro enmascarado): las tramas T
///   salen de la forma declarada del modelo (345 o 575, según el fichero que haya instalado ModelStore) y la máscara
///   se reconstruye con `SeparationSpectrumLayout`;
/// - solista (`spec` → `mask`, el mismo contrato que Core ML): ORT escribe directamente en el búfer de la máscara.
/// Proveedor elegido por `OnnxModelLoader` (QNN → CUDA → DirectML → CPU, comparado con CPU la primera vez).
final class OnnxMaskModel: MaskModel {
    enum Interface { case maskedSpectrum, mask }

    let contract: MaskModelContract
    let frames: Int
    let interface: Interface
    let session: OnnxSession
    /// Clave del recuerdo de proveedor (`OnnxModelLoader`).
    private let modelKey: String
    private var real: [Float] = [], imag: [Float] = [], outReal: [Float] = [], outImag: [Float] = []

    /// `contract` aporta hop, solape y stems; las tramas y los nombres salen del modelo.
    init(modelURL: URL, contract base: MaskModelContract) throws {
        // Sin reserva ni patrón de memoria: el export con dynamo pasa de 10 GB si no (parte 7.3).
        let options = OnnxSessionOptions(memoryArena: false, memoryPattern: false)
        let key = "\(modelURL.deletingPathExtension().lastPathComponent)-\(Self.fileSize(modelURL))"
        modelKey = key
        session = try OnnxModelLoader.session(modelURL: modelURL, model: key, options: options)
        let bins = RoformerContract.bins
        if session.inputNames.contains("spec_real"), session.inputNames.contains("spec_imag") {
            guard let shape = session.inputShape("spec_real"), shape.count == 4, shape[0] == 1, shape[1] == 2,
                  shape[2] == bins, shape[3] > 1 else {
                throw SeparationError.invalidInput("spec_real con forma \(session.inputShape("spec_real") ?? [])")
            }
            interface = .maskedSpectrum
            frames = shape[3]
            contract = MaskModelContract(hop: base.hop, frames: frames, overlaps: base.overlaps,
                                         stemCount: base.stemCount, inputName: "spec_real", outputName: "out_spec_real")
            let plane = 2 * bins * frames
            real = [Float](repeating: 0, count: plane)
            imag = real
            outReal = [Float](repeating: 0, count: base.stemCount * plane)
            outImag = outReal
        } else if session.inputNames.contains(base.inputName) {
            guard let shape = session.inputShape(base.inputName), shape.count == 4, shape[1] == 2 * bins,
                  shape[2] > 1, shape[3] == 2 else {
                throw SeparationError.invalidInput("\(base.inputName) con forma \(session.inputShape(base.inputName) ?? [])")
            }
            interface = .mask
            frames = shape[2]
            let output = session.outputNames.contains(base.outputName) ? base.outputName : (session.outputNames.first ?? "")
            contract = MaskModelContract(hop: base.hop, frames: frames, overlaps: base.overlaps,
                                         stemCount: base.stemCount, inputName: base.inputName, outputName: output)
        } else {
            throw SeparationError.invalidInput("el modelo no tiene spec_real/spec_imag ni \(base.inputName): \(session.inputNames)")
        }
    }

    func predict(spec: UnsafeMutablePointer<Float>, mask: UnsafeMutablePointer<Float>) throws {
        let bins = RoformerContract.bins
        switch interface {
        case .mask:
            // ORT escribe la máscara directamente: no hay etapas de preparar ni de leer salida.
            try SeparationTiming.measureRun {
                try session.run(inputs: [OnnxBuffer(name: contract.inputName, shape: [1, 2 * bins, frames, 2], pointer: spec)],
                                outputs: [OnnxBuffer(name: contract.outputName, shape: [1, contract.stemCount, 2 * bins, frames, 2],
                                                     pointer: mask)])
            }
        case .maskedSpectrum:
            let stems = contract.stemCount, frames = self.frames
            try real.withUnsafeMutableBufferPointer { re in
                try imag.withUnsafeMutableBufferPointer { im in
                    try outReal.withUnsafeMutableBufferPointer { ore in
                        try outImag.withUnsafeMutableBufferPointer { oim in
                            SeparationTiming.measure(.prepareInput) {
                                SeparationSpectrumLayout.split(spec: spec, bins: bins, frames: frames,
                                                               real: re.baseAddress!, imag: im.baseAddress!)
                            }
                            let inShape = [1, 2, bins, frames], outShape = [1, stems, 2, bins, frames]
                            try SeparationTiming.measureRun {
                                try session.run(inputs: [OnnxBuffer(name: "spec_real", shape: inShape, pointer: re.baseAddress!),
                                                         OnnxBuffer(name: "spec_imag", shape: inShape, pointer: im.baseAddress!)],
                                                outputs: [OnnxBuffer(name: "out_spec_real", shape: outShape, pointer: ore.baseAddress!),
                                                          OnnxBuffer(name: "out_spec_imag", shape: outShape, pointer: oim.baseAddress!)])
                            }
                            SeparationTiming.measure(.readOutput) {
                                SeparationSpectrumLayout.mask(outReal: ore.baseAddress!, outImag: oim.baseAddress!, spec: spec,
                                                              stems: stems, bins: bins, frames: frames, into: mask)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Configuración de la sesión tal como se creó (solo lectura) y la elección de proveedor.
    var engineSummary: String {
        var text = "ONNX Runtime, interfaz \(interface == .maskedSpectrum ? "espectro enmascarado" : "mascara"), "
            + "T=\(frames); \(session.configurationSummary)"
        if let sel = OnnxModelLoader.lastSelection(model: modelKey) {
            text += "; seleccion \(sel.candidate.provider.rawValue)\(sel.fromMemory ? " (recordada)" : "")"
            if !sel.skipped.isEmpty { text += ", descartados: \(sel.skipped.joined(separator: " | "))" }
        }
        return text
    }

    private static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
#endif
