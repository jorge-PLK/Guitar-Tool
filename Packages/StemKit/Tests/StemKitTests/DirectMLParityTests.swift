import XCTest
@testable import StemKit

#if os(Windows)
import NativeONNX

/// DirectML frente a CPU con el mismo `.onnx` y la misma entrada (fixture de la parte 7.3). Caza lo que la
/// comparación de `OnnxModelLoader` no ve con su entrada de prueba pequeña: el GLU con `Split(2)` que DirectML
/// calculaba mal (ONNX originales: −7,5 dB en guitarras; reescritos con dos `Slice`: 116–124 dB; Fase 7c, arreglo A).
/// Solo con `TF_MODEL_TESTS=1`, una ORT con DirectML (`TF_ORT_DLL`) y una GPU por hardware; si no, salta.
final class DirectMLParityTests: XCTestCase {
    /// Misma red y misma entrada en otro proveedor: ≥ 90 dB global y por stem (propuesta de la ronda del GLU, 22/11/2026;
    /// hoy 116 dB en separación y 123 dB en guitarras). Más estricto que los 60 dB de `OnnxComparison.minimumSNR`.
    static let minimumSNR = 90.0
    /// Un stem cuenta por separado solo si su energía pasa de −60 dB respecto a la de su salida: los stems casi en
    /// silencio del fixture (other y piano, −84 y −87 dB) se quedan en el suelo de float32 (~80 dB) aunque cuadren.
    static let minimumStemEnergyDB = -60.0

    private func require(_ folder: String) throws -> (url: URL, adapter: Int) {
        guard ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1" else {
            throw XCTSkip("tests del modelo real desactivados (TF_MODEL_TESTS != 1)")
        }
        guard let url = OnnxDevelopmentModels.model(folder) else {
            throw XCTSkip("no está el modelo en \(OnnxDevelopmentModels.directory(folder).path)")
        }
        let providers = (try? OnnxRuntime.availableProviders) ?? []
        guard providers.contains(OnnxProvider.directML.executionProviderName) else {
            throw XCTSkip("[windows] la onnxruntime.dll cargada no trae DirectML (\(providers)); TF_ORT_DLL debe apuntar a la de DirectML")
        }
        guard let gpu = OnnxProviderPlan.directMLAdapter(OnnxRuntime.gpus, allowSoftware: false) else {
            throw XCTSkip("[windows] sin GPU DirectX 12 por hardware")
        }
        return (url, gpu.adapterIndex)
    }

    /// Ejecuta el modelo con `provider` sobre las entradas del fixture (`files`: entrada → fichero de la carpeta).
    private func run(_ url: URL, folder: String, files: [String: String], provider: OnnxProvider,
                     adapter: Int) throws -> [String: OnnxTensor] {
        // Las mismas opciones que `OnnxMaskModel`.
        let session = try OnnxSession(modelURL: url, provider: provider,
                                      options: OnnxSessionOptions(memoryArena: false, memoryPattern: false, deviceID: adapter))
        XCTAssertEqual(session.provider, provider)
        var inputs: [String: OnnxTensor] = [:]
        for name in session.inputNames {
            let file = try XCTUnwrap(files[name], "entrada \(name) sin fichero")
            let shape = try XCTUnwrap(session.inputShape(name), name)
            XCTAssertFalse(shape.contains { $0 <= 0 }, "\(name): forma fija esperada, \(shape)")
            let data = try OnnxDevelopmentModels.floats(folder, file)
            XCTAssertEqual(data.count, shape.reduce(1, *), "\(file) con la forma \(shape)")
            inputs[name] = OnnxTensor(shape: shape, data: data)
        }
        let t0 = Date()
        let out = try session.run(inputs)
        print(String(format: "[7c] %@ %@: %.2f s", folder, provider.rawValue, Date().timeIntervalSince(t0)))
        return out
    }

    /// SNR de DirectML frente a CPU, global y por stem (primer eje tras el lote), y el peor de los que cuentan.
    private func compare(folder: String, files: [String: String]) throws {
        let (url, adapter) = try require(folder)
        // CPU primero y se suelta antes de crear la de DirectML: una sola sesión grande viva a la vez.
        let cpu = try run(url, folder: folder, files: files, provider: .cpu, adapter: 0)
        let dml: [String: OnnxTensor]
        do {
            dml = try run(url, folder: folder, files: files, provider: .directML, adapter: adapter)
        } catch {
            throw XCTSkip("[windows] DirectML no crea sesión o no ejecuta \(folder): \(error)")
        }
        var worst = Double.infinity
        for name in cpu.keys.sorted() {
            let ref = cpu[name]!, test = try XCTUnwrap(dml[name], name)
            XCTAssertEqual(ref.shape, test.shape, name)
            let global = OnnxComparison.snr(reference: ref.data, test: test.data)
            worst = min(worst, global)
            let stems = ref.shape.count > 1 ? ref.shape[1] : 1, n = ref.data.count / stems
            let total = ref.data.reduce(0) { $0 + Double($1) * Double($1) }
            var perStem: [String] = []
            for s in 0..<stems {
                let r = Array(ref.data[s * n..<(s + 1) * n]), t = Array(test.data[s * n..<(s + 1) * n])
                let energy = 10 * log10(r.reduce(0) { $0 + Double($1) * Double($1) } / total)
                let snr = OnnxComparison.snr(reference: r, test: t)
                let counts = energy > Self.minimumStemEnergyDB
                if counts { worst = min(worst, snr) }
                perStem.append(String(format: "%.1f%@ (%.0f dB)", snr, counts ? "" : "*", energy))
            }
            print(String(format: "[7c] DirectML frente a CPU %@ %@: global %.1f dB; por stem %@ (* no cuenta)",
                         folder, name, global, perStem.joined(separator: ", ")))
        }
        XCTAssertGreaterThanOrEqual(worst, Self.minimumSNR, "\(folder): DirectML no cuadra con CPU")
    }

    /// Guitarras (Mel-Band RoFormer solista/rítmica, 60 GLU): un trozo de 3 s.
    func test1_LeadRhythmDirectMLMatchesCpu() throws {
        try compare(folder: "lead_rhythm", files: ["spec": "in_spec.bin"])
    }

    /// Separación principal (BS-RoFormer, 372 GLU, T=345): un trozo del minuto 1 de T1.
    func test2_BSRoformerDirectMLMatchesCpu() throws {
        try compare(folder: "bs_roformer", files: ["spec_real": "in_real.bin", "spec_imag": "in_imag.bin"])
    }
}
#endif
