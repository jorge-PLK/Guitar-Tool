#if os(Windows)
import Foundation
import NativeONNX
import XCTest
@testable import TabKit

/// ADTOF siempre en CPU en Windows (Jorge, 23/11/2026): en DirectML, con T ≥ ~8000 tramas, desborda la pila de
/// DirectML.dll y tira el proceso (Temp/win/estado/modelos-analisis.md, hallazgo 2).
final class OnnxDrumProviderTests: XCTestCase {
    /// Un tema de 3 min a 100 fps: por encima del umbral de DirectML (entre 6000 y 8000 tramas).
    static let wholeSongFrames = 18_000

    private let rtx = OnnxGPU(name: "RTX 3060", vendorID: OnnxGPU.nvidiaVendorID, deviceID: 0x2504,
                              dedicatedVideoMemory: 12 << 30, isSoftware: false, adapterIndex: 0)
    private let dmlAndCpu = [OnnxProvider.directML.executionProviderName, OnnxProvider.cpu.executionProviderName]

    /// Sin GPU: con DirectML anunciado y una GPU por hardware, el plan automático probaría DirectML; con el entorno de
    /// ADTOF solo queda CPU, también si el entorno pedía DirectML o CUDA.
    func testAdtofPlanIsCPUOnlyEvenWithDirectMLAvailable() {
        let auto = OnnxProviderPlan.candidates(architecture: .x64, gpus: [rtx], available: dmlAndCpu, forced: nil)
        XCTAssertEqual(auto.map(\.provider), [.directML, .cpu], "sin forzar, DirectML va primero")
        for base in [[:], ["TF_ONNX_PROVIDER": "directml"], ["TF_ONNX_PROVIDER": "cuda"], ["OTRA": "x"]] {
            let env = OnnxDrumPredictor.loaderEnvironment(base)
            let forced = OnnxProviderPlan.forced(in: env)
            XCTAssertEqual(forced, .cpu, "\(base)")
            XCTAssertEqual(OnnxProviderPlan.candidates(architecture: .x64, gpus: [rtx], available: dmlAndCpu, forced: forced),
                           [.cpu], "\(base)")
            XCTAssertEqual(OnnxProviderPlan.omissions(gpus: [rtx], available: dmlAndCpu, forced: forced), [], "\(base)")
            if base["OTRA"] != nil { XCTAssertEqual(env["OTRA"], "x", "el resto del entorno se conserva") }
        }
    }

    /// Con la ORT de DirectML (`TF_ORT_DLL`) y una GPU por hardware: `OnnxDrumPredictor` se abre en CPU, el log lo dice
    /// y un tema entero (T = 18 000) corre en el pool cooperativo (pila de 1 MB, como `DrumTranscriber`) sin caer.
    /// Sin esa ORT, sin GPU, sin `TF_MODEL_TESTS=1` o sin el modelo, salta.
    func testAdtofOpensOnCPUWithDirectMLAndRunsAWholeSong() async throws {
        guard ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1" else {
            throw XCTSkip("tests del modelo real desactivados (TF_MODEL_TESTS != 1)")
        }
        let url = try tabKitDevelopmentModel("adtof")
        let providers = try OnnxRuntime.availableProviders
        guard providers.contains(OnnxProvider.directML.executionProviderName) else {
            throw XCTSkip("la onnxruntime.dll cargada no trae DirectML (\(providers)); TF_ORT_DLL debe apuntar a la de DirectML")
        }
        guard OnnxProviderPlan.directMLAdapter(OnnxRuntime.gpus, allowSoftware: false) != nil else {
            throw XCTSkip("sin GPU por hardware para DirectML")
        }
        let box = AdtofLogBox()
        OnnxModelLoader.setLogHandler { box.add($0) }
        defer { OnnxModelLoader.setLogHandler(nil) }

        let t = Self.wholeSongFrames, nb = DrumContract.bands, k = DrumContract.classes
        let base = try Fixture.f32(DrumTranscriberTests.dir.appendingPathComponent("spec.f32"))
        let spec = (0..<(t * nb)).map { base[$0 % base.count] }
        let (act, seconds) = try await Task.detached { () -> ([Float], Double) in
            let p = try OnnxDrumPredictor(modelURL: url)
            let t0 = Date()
            let act = try spec.withUnsafeBufferPointer { try p.predict(spectrogram: $0, frames: t) }
            return (act, Date().timeIntervalSince(t0))
        }.value

        XCTAssertEqual(OnnxModelLoader.lastSelection(model: "adtof")?.candidate.provider, .cpu)
        let lines = box.lines.filter { $0.hasPrefix("onnx| adtof ") }
        XCTAssertEqual(lines, ["onnx| adtof -> cpu (descartados: ninguno; memoria: no)"])
        XCTAssertEqual(act.count, t * k)
        XCTAssertTrue(act.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }, "activaciones sigmoides finitas")
        print(String(format: "ADTOF T=%d en CPU con ORT %@ (DirectML disponible): %.0f ms; %@",
                     t, (try? OnnxRuntime.version) ?? "?", seconds * 1000, lines.first ?? "-"))
    }
}

private final class AdtofLogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    var lines: [String] { lock.withLock { _lines } }
    func add(_ l: String) { lock.withLock { _lines.append(l) } }
}
#endif
