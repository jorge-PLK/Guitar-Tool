import Foundation
import NativeONNX
import NativePlatform
import XCTest

/// Elección de proveedor y recuerdo (tipos puros: corren en el Mac y en Windows) y, en Windows, la sesión real
/// con Basic Pitch frente a las referencias del Mac (parte 7.8).
final class OnnxProviderChoiceTests: XCTestCase {
    let warp = OnnxGPU(name: "Microsoft Basic Render Driver", vendorID: 0x1414, deviceID: 0x8C,
                       dedicatedVideoMemory: 0, isSoftware: true, adapterIndex: 1)
    let rtx = OnnxGPU(name: "NVIDIA RTX", vendorID: 0x10DE, deviceID: 0x2684, dedicatedVideoMemory: 24 << 30,
                      isSoftware: false, adapterIndex: 2)
    let intel = OnnxGPU(name: "Intel Iris Xe", vendorID: 0x8086, deviceID: 0x9A49, dedicatedVideoMemory: 128 << 20,
                        isSoftware: false, adapterIndex: 0)
    let allProviders = ["QNNExecutionProvider", "CUDAExecutionProvider", "DmlExecutionProvider", "CPUExecutionProvider"]

    /// Windows solo x64 (19/11/2026): CUDA → DirectML → CPU; QNN fuera del orden automático (aunque la DLL lo traiga).
    func testOrderCudaDirectMLCpu() {
        let x64 = OnnxProviderPlan.candidates(architecture: .x64, gpus: [intel, rtx, warp], available: allProviders, forced: nil)
        XCTAssertEqual(x64.map(\.provider), [.cuda, .directML, .cpu])
        XCTAssertEqual(x64[1].deviceID, 2, "DirectML sobre el adaptador con más VRAM")
        let arm = OnnxProviderPlan.candidates(architecture: .arm64, gpus: [intel, rtx, warp], available: allProviders, forced: nil)
        XCTAssertEqual(arm.map(\.provider), [.cuda, .directML, .cpu], "sin QNN tampoco en ARM64")
    }

    func testOnlyWhatTheDllAndTheMachineHave() {
        let dmlDll = ["DmlExecutionProvider", "CPUExecutionProvider"]
        XCTAssertEqual(OnnxProviderPlan.candidates(architecture: .arm64, gpus: [intel, rtx], available: dmlDll, forced: nil)
            .map(\.provider), [.directML, .cpu], "sin QNN ni CUDA en la DLL")
        XCTAssertEqual(OnnxProviderPlan.candidates(architecture: .x64, gpus: [intel], available: allProviders, forced: nil)
            .map(\.provider), [.directML, .cpu], "CUDA solo con GPU NVIDIA")
        XCTAssertEqual(OnnxProviderPlan.candidates(architecture: .x64, gpus: [warp], available: allProviders, forced: nil)
            .map(\.provider), [.cpu], "WARP no cuenta como GPU si no se fuerza")
    }

    func testForcedProviderIsTheOnlyAttempt() {
        let forced = OnnxProviderPlan.candidates(architecture: .arm64, gpus: [warp], available: ["CPUExecutionProvider"],
                                                 forced: .directML)
        XCTAssertEqual(forced, [OnnxCandidate(provider: .directML, deviceID: 1, gpu: warp)], "forzado: WARP vale")
        XCTAssertEqual(OnnxProviderPlan.forced(in: ["TF_ONNX_PROVIDER": "DirectML"]), .directML)
        XCTAssertEqual(OnnxProviderPlan.forced(in: ["TF_ONNX_PROVIDER": "cpu"]), .cpu)
        XCTAssertNil(OnnxProviderPlan.forced(in: ["TF_ONNX_PROVIDER": "metal"]))
    }

    /// Ruido a -60 dB exactos (escala 1e-3 de la señal) → 60,0 dB ± 0,01.
    func testSnr() {
        let ref = (0..<1000).map { Float(sin(Double($0) * 0.1)) }
        let test = ref.map { $0 * (1 + 1e-3) }
        XCTAssertEqual(OnnxComparison.snr(reference: ref, test: test), 60, accuracy: 0.01)
        XCTAssertEqual(OnnxComparison.snr(reference: ref, test: ref), .infinity)
        XCTAssertEqual(OnnxComparison.snr(reference: ref, test: Array(ref.dropLast())), -.infinity)
    }

    // MARK: - Selector con sesiones simuladas

    final class FakeRunner: OnnxRunner {
        let provider: OnnxProvider
        let gain: Float
        init(_ provider: OnnxProvider, gain: Float) { self.provider = provider; self.gain = gain }
        func run(_ inputs: [String: OnnxTensor]) throws -> [String: OnnxTensor] {
            ["y": OnnxTensor(shape: inputs["x"]!.shape, data: inputs["x"]!.data.map { $0 * gain })]
        }
    }

    struct CreateFailed: Error {}

    func tempMemory() -> OnnxProviderMemory {
        OnnxProviderMemory(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("tf-onnx-\(UUID().uuidString).json"))
    }

    func select(_ candidates: [OnnxCandidate], memory: OnnxProviderMemory, gpuGain: Float, failing: Set<OnnxProvider> = [],
                made: inout [OnnxProvider], forced: Bool = false) throws -> (FakeRunner, OnnxSelection) {
        let selector = OnnxProviderSelector(candidates: candidates, forced: forced, memory: memory, runtimeVersion: "1.32.0")
        var log: [OnnxProvider] = []
        defer { made = log }
        return try selector.select(model: "m", probe: { _ in ["x": OnnxProbe.tensor(shape: [1, 256])] }) { c in
            log.append(c.provider)
            if failing.contains(c.provider) { throw CreateFailed() }
            return FakeRunner(c.provider, gain: c.provider == .cpu ? 1 : gpuGain)
        }
    }

    func testFallsThroughWhenSessionCannotBeCreated() throws {
        let memory = tempMemory()
        var made: [OnnxProvider] = []
        let (runner, sel) = try select([OnnxCandidate(provider: .qnn), OnnxCandidate(provider: .directML), .cpu],
                                       memory: memory, gpuGain: 1, failing: [.qnn], made: &made)
        XCTAssertEqual(runner.provider, .directML)
        XCTAssertEqual(made, [.qnn, .directML, .cpu], "QNN falla, DirectML se crea y se compara con CPU")
        XCTAssertEqual(sel.snr, .infinity)
        XCTAssertEqual(sel.skipped.count, 1)
    }

    /// GPU con error relativo 1e-2 (40 dB < 60): el modelo queda en CPU y la segunda vez ni se intenta la GPU.
    func testMismatchLeavesModelOnCpuAndIsRemembered() throws {
        let memory = tempMemory()
        let candidates = [OnnxCandidate(provider: .directML, deviceID: 0, gpu: intel), .cpu]
        var made: [OnnxProvider] = []
        let (first, sel) = try select(candidates, memory: memory, gpuGain: 1.01, made: &made)
        XCTAssertEqual(first.provider, .cpu)
        XCTAssertEqual(made, [.directML, .cpu, .cpu])
        XCTAssertEqual(memory.verdict(model: "m", candidate: candidates[0])?.passed, false)
        XCTAssertEqual(memory.verdict(model: "m", candidate: candidates[0])?.snr ?? 0, 40, accuracy: 0.01)
        XCTAssertTrue(sel.skipped[0].contains("40.0 dB"), sel.skipped[0])
        let (second, _) = try select(candidates, memory: memory, gpuGain: 1, made: &made)
        XCTAssertEqual(second.provider, .cpu)
        XCTAssertEqual(made, [.cpu], "recordado: sin crear la sesión de GPU")
    }

    /// Error relativo 1e-4 (80 dB ≥ 60): se queda la GPU; la segunda vez, sin volver a comparar.
    func testMatchIsRememberedAndNotRecompared() throws {
        let memory = tempMemory()
        let candidates = [OnnxCandidate(provider: .directML, deviceID: 0, gpu: intel), .cpu]
        var made: [OnnxProvider] = []
        let (first, sel) = try select(candidates, memory: memory, gpuGain: 1.0001, made: &made)
        XCTAssertEqual(first.provider, .directML)
        XCTAssertEqual(sel.snr ?? 0, 80, accuracy: 0.05)
        let (second, sel2) = try select(candidates, memory: memory, gpuGain: 1.0001, made: &made)
        XCTAssertEqual(second.provider, .directML)
        XCTAssertEqual(made, [.directML], "sin sesión de CPU de referencia")
        XCTAssertTrue(sel2.fromMemory)
        // Otra GPU en el mismo equipo: se compara de nuevo.
        let other = [OnnxCandidate(provider: .directML, deviceID: 2, gpu: rtx), .cpu]
        _ = try select(other, memory: memory, gpuGain: 1.0001, made: &made)
        XCTAssertEqual(made, [.directML, .cpu])
    }

    func testForcedDoesNotFallBackNorCompare() throws {
        var made: [OnnxProvider] = []
        XCTAssertThrowsError(try select([OnnxCandidate(provider: .cuda)], memory: tempMemory(), gpuGain: 1, failing: [.cuda],
                                        made: &made, forced: true))
        let (r, _) = try select([OnnxCandidate(provider: .directML)], memory: tempMemory(), gpuGain: 2, made: &made, forced: true)
        XCTAssertEqual(r.provider, .directML)
        XCTAssertEqual(made, [.directML])
    }

    // MARK: - Línea de registro (Fase 7c, mejora 2)

    func testLogLineNamesDiscardedProviderWithItsReason() throws {
        var made: [OnnxProvider] = []
        let (_, sel) = try select([OnnxCandidate(provider: .cuda, deviceID: 0, gpu: rtx),
                                   OnnxCandidate(provider: .directML, deviceID: 0, gpu: intel), .cpu],
                                  memory: tempMemory(), gpuGain: 1, failing: [.cuda], made: &made)
        let line = sel.logLine(model: "bs_roformer")
        XCTAssertTrue(line.hasPrefix("onnx| bs_roformer -> directML (descartados: cuda: "), line)
        XCTAssertTrue(line.contains("memoria: no"), line)
    }

    func testLogLineWhenSnrFallsBackToCpu() throws {
        var made: [OnnxProvider] = []
        let (_, sel) = try select([OnnxCandidate(provider: .directML, deviceID: 0, gpu: intel), .cpu],
                                  memory: tempMemory(), gpuGain: 1.01, made: &made)
        let line = sel.logLine(model: "btc")
        XCTAssertEqual(line, "onnx| btc -> cpu (descartados: directML: 40.0 dB frente a CPU, < 60 dB; memoria: no)")
    }

    func testLogLineFromMemoryAndOmissions() throws {
        let memory = tempMemory()
        let candidates = [OnnxCandidate(provider: .directML, deviceID: 0, gpu: intel), .cpu]
        var made: [OnnxProvider] = []
        _ = try select(candidates, memory: memory, gpuGain: 1.0001, made: &made)
        let (_, sel) = try select(candidates, memory: memory, gpuGain: 1.0001, made: &made)
        XCTAssertTrue(sel.logLine(model: "m").contains("memoria: sí"), sel.logLine(model: "m"))
        XCTAssertEqual(OnnxProviderPlan.omissions(gpus: [intel], available: ["DmlExecutionProvider", "CPUExecutionProvider"],
                                                  forced: nil), ["cuda: no hay EP"])
        XCTAssertEqual(OnnxProviderPlan.omissions(gpus: [warp], available: ["CPUExecutionProvider"], forced: nil),
                       ["cuda: no hay EP", "directML: no hay EP"])
        XCTAssertEqual(OnnxProviderPlan.omissions(gpus: [], available: allProviders, forced: .cpu), [])
    }

}

#if os(Windows)
final class LineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    var lines: [String] { lock.withLock { _lines } }
    func add(_ l: String) { lock.withLock { _lines.append(l) } }
}

/// Sesión real en la VM: Basic Pitch (0,23 MB, Apache-2.0) frente a ORT CPU del Mac y Core ML de la app (parte 7.3).
final class OnnxSessionTests: XCTestCase {
    let input = "serving_default_input_2:0"
    let outputs = ["StatefulPartitionedCall:0": [1, 172, 264], "StatefulPartitionedCall:1": [1, 172, 88],
                   "StatefulPartitionedCall:2": [1, 172, 88]]
    let thresholds = ["StatefulPartitionedCall:1": Float(0.3), "StatefulPartitionedCall:2": Float(0.5)]

    func fixture(_ name: String) -> URL { Bundle.module.url(forResource: "Fixtures/basic_pitch/" + name, withExtension: nil)! }

    func floats(_ name: String) throws -> [Float] {
        let data = try Data(contentsOf: fixture(name))
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// El cargador manda una línea al gancho del log por cada sesión.
    func testLoaderLogsOneLinePerSession() throws {
        let box = LineBox()
        OnnxModelLoader.setLogHandler { box.add($0) }
        defer { OnnxModelLoader.setLogHandler(nil) }
        _ = try OnnxModelLoader.session(modelURL: fixture("model.onnx"), model: "basic_pitch",
                                        environment: ["TF_ONNX_PROVIDER": "cpu"], memory: nil)
        XCTAssertEqual(box.lines, ["onnx| basic_pitch -> cpu (descartados: ninguno; memoria: no)"])
    }

    func refName(_ prefix: String, _ output: String) -> String {
        prefix + "_StatefulPartitionedCall_" + output.split(separator: ":").last! + ".bin"
    }

    func check(_ result: [String: OnnxTensor], label: String) throws {
        for (name, shape) in outputs {
            let out = try XCTUnwrap(result[name], name)
            XCTAssertEqual(out.shape, shape)
            let snr = OnnxComparison.snr(reference: try floats(refName("ref", name)), test: out.data)
            print("[7.8] \(label) \(name) SNR frente a ORT Mac: \(String(format: "%.1f", snr)) dB")
            XCTAssertGreaterThanOrEqual(snr, OnnxComparison.minimumSNR, name)
            if let thr = thresholds[name] {
                let coreml = try floats(refName("coreml", name))
                let same = zip(coreml, out.data).filter { ($0 >= thr) == ($1 >= thr) }.count
                print("[7.8] \(label) \(name) decisiones iguales a Core ML: \(same)/\(coreml.count)")
                XCTAssertEqual(same, coreml.count, "umbral \(thr): 100 % de decisiones iguales")
            }
        }
    }

    func testBasicPitchOnCpuMatchesMacReference() throws {
        let session = try OnnxSession(modelURL: fixture("model.onnx"), provider: .cpu, options: OnnxSessionOptions(threads: 2))
        XCTAssertEqual(session.inputNames, [input])
        XCTAssertEqual(Set(session.outputNames), Set(outputs.keys))
        XCTAssertEqual(session.inputShape(input), [-1, 43844, 1])
        let x = OnnxTensor(shape: [1, 43844, 1], data: try floats("in_serving_default_input_2_0.bin"))
        let t0 = Date()
        let result = try session.run([input: x])
        print("[7.8] basic_pitch CPU: \(Int(Date().timeIntervalSince(t0) * 1000)) ms por trozo de 2 s")
        try check(result, label: "cpu")
    }

    /// La variante sin copias escribe en los búferes del llamante exactamente lo mismo que la que copia.
    func testZeroCopyRunWritesSameValues() throws {
        let session = try OnnxSession(modelURL: fixture("model.onnx"), provider: .cpu,
                                      options: OnnxSessionOptions(memoryArena: false, memoryPattern: false))
        var x = try floats("in_serving_default_input_2_0.bin")
        let copied = try session.run([input: OnnxTensor(shape: [1, 43844, 1], data: x)])
        var note = [Float](repeating: .nan, count: 172 * 88)
        try x.withUnsafeMutableBufferPointer { xp in
            try note.withUnsafeMutableBufferPointer { np in
                try session.run(inputs: [OnnxBuffer(name: input, shape: [1, 43844, 1], pointer: xp.baseAddress!)],
                                outputs: [OnnxBuffer(name: "StatefulPartitionedCall:1", shape: [1, 172, 88], pointer: np.baseAddress!)])
            }
        }
        XCTAssertEqual(note, copied["StatefulPartitionedCall:1"]!.data)
    }

    func testWrongShapeIsAnError() throws {
        let session = try OnnxSession(modelURL: fixture("model.onnx"), provider: .cpu, threads: 1)
        XCTAssertThrowsError(try session.run([input: OnnxTensor(shape: [1, 43844, 1], data: [0, 1])]))
        XCTAssertThrowsError(try session.run([input: OnnxTensor(shape: [1, 100, 1], data: [Float](repeating: 0, count: 100))]))
    }

    func testDxgiSeesAnAdapter() {
        let gpus = OnnxRuntime.gpus
        print("[7.8] DXGI: " + gpus.map { "\($0.adapterIndex) \($0.name) \(String(format: "%04x", $0.vendorID)) VRAM \($0.dedicatedVideoMemory >> 20) MB sw=\($0.isSoftware)" }.joined(separator: " | "))
        print("[7.8] ORT \((try? OnnxRuntime.version) ?? "?") API \(OnnxRuntime.apiVersion) proveedores: \((try? OnnxRuntime.availableProviders) ?? [])")
        XCTAssertFalse(gpus.isEmpty, "DXGI lista al menos WARP")
    }

    /// DirectML forzado (en la VM, sobre WARP): crea sesión y da lo mismo que CPU (≥ 60 dB) y que el Mac.
    func testDirectMLForcedMatchesCpu() throws {
        let candidates = OnnxProviderPlan.candidates(architecture: .current, gpus: OnnxRuntime.gpus,
                                                     available: try OnnxRuntime.availableProviders, forced: .directML)
        let c = try XCTUnwrap(candidates.first)
        let session: OnnxSession
        do {
            session = try OnnxSession(modelURL: fixture("model.onnx"), provider: .directML, options: OnnxSessionOptions(deviceID: c.deviceID))
        } catch {
            print("[7.8] DirectML no crea sesión en \(c.gpu?.name ?? "?"): \(error)")
            throw XCTSkip("[windows] sin GPU DirectX 12 en la VM")
        }
        let x = OnnxTensor(shape: [1, 43844, 1], data: try floats("in_serving_default_input_2_0.bin"))
        let t0 = Date()
        let result = try session.run([input: x])
        print("[7.8] basic_pitch DirectML en \(c.gpu?.name ?? "?"): \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        try check(result, label: "directml")
    }

    /// El cargador completo: proveedor elegido, recuerdo en un fichero temporal, y la selección forzada a CPU.
    func testLoaderPicksAndRemembers() throws {
        let memory = OnnxProviderMemory(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("tf-onnx-\(UUID().uuidString).json"))
        let probe: (OnnxSession) -> [String: OnnxTensor] = { s in
            let inputs = OnnxProbe.inputs(for: s)
            XCTAssertEqual(inputs["serving_default_input_2:0"]?.shape, [1, 43844, 1], "eje dinámico de lote a 1")
            return inputs
        }
        let auto = try OnnxModelLoader.session(modelURL: fixture("model.onnx"), model: "basic_pitch", environment: [:],
                                               memory: memory, probe: probe)
        let sel = try XCTUnwrap(OnnxModelLoader.lastSelection(model: "basic_pitch"))
        print("[7.8] cargador: \(auto.provider) snr=\(sel.snr.map { String($0) } ?? "-") descartes=\(sel.skipped)")
        let cpu = try OnnxModelLoader.session(modelURL: fixture("model.onnx"), model: "basic_pitch",
                                              environment: ["TF_ONNX_PROVIDER": "cpu"], memory: memory, probe: probe)
        XCTAssertEqual(cpu.provider, .cpu)
    }
}
#endif
