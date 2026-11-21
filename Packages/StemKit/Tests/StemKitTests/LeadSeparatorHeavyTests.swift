import XCTest
@testable import StemKit

#if os(Windows)
import NativeONNX

/// Modelo de solista con el ONNX real (parte 7.8). Solo con `TF_MODEL_TESTS=1`, de uno en uno. Modelo y referencias
/// en `<TF_MODELS_DIR o C:\tf-models>\lead_rhythm` (parte 7.3): `in_spec.bin`, `ref_mask.bin` (ORT CPU del Mac) y
/// `coreml_mask.bin` (Core ML de la app).
final class LeadSeparatorHeavyTests: XCTestCase {
    static let minSDRvsTorch = 50.0
    static let maxMaskProbeError = 0.02
    /// Misma red: SNR ≥ 60 dB; frente a Core ML: SDR ≥ 15 dB (decisiones de Jorge, 19/11/2026).
    static let minSNRvsMacORT = 60.0
    static let minSDRvsCoreML = 15.0
    static let folder = "lead_rhythm"

    private func requireHeavy() throws -> URL {
        guard ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1" else {
            throw XCTSkip("tests del modelo real desactivados (TF_MODEL_TESTS != 1)")
        }
        guard let url = OnnxDevelopmentModels.model(Self.folder) else {
            throw XCTSkip("no está el modelo en \(OnnxDevelopmentModels.directory(Self.folder).path)")
        }
        return url
    }

    /// Máscara de un trozo frente al Mac (ORT y Core ML) y, con el fixture de 2 s, sondas y SDR frente a PyTorch.
    func test1_ParityWithTorchFixture() throws {
        let url = try requireHeavy()
        let model = try OnnxMaskModel(modelURL: url, contract: .leadRhythm)
        XCTAssertEqual(model.interface, .mask)
        XCTAssertEqual(model.frames, MaskModelContract.leadRhythm.frames)
        var spec = try OnnxDevelopmentModels.floats(Self.folder, "in_spec.bin")
        var mask = [Float](repeating: .nan, count: spec.count)
        let t0 = Date()
        try model.predict(spec: &spec, mask: &mask)
        let chunk = Date().timeIntervalSince(t0)
        let vsMac = snrDB(try OnnxDevelopmentModels.floats(Self.folder, "ref_mask.bin"), mask)
        let vsCoreML = snrDB(try OnnxDevelopmentModels.floats(Self.folder, "coreml_mask.bin"), mask)
        print(String(format: "[7.8] lead_rhythm (%@): trozo %.1f s (%.0f s/min con num_overlap 2); máscara frente a ORT Mac %.1f dB, frente a Core ML %.1f dB",
                     model.session.provider.rawValue, chunk, chunk * 2 * 60 / 3, vsMac, vsCoreML))
        XCTAssertGreaterThanOrEqual(vsMac, Self.minSNRvsMacORT)
        XCTAssertGreaterThanOrEqual(vsCoreML, Self.minSDRvsCoreML)

        let ref = try LeadSeparatorTests.reference()
        let fixture = try LeadSeparatorTests.fixtureSpec()
        var fspec = fixture.spec
        var fmask = [Float](repeating: 0, count: fixture.stft.specCount)
        try model.predict(spec: &fspec, mask: &fmask)
        var worstMask = 0.0
        for p in ref.mask_probes {
            let i = fixture.stft.specIndex(bin: p.row / 2, channel: p.row % 2, frame: p.frame)
            worstMask = max(worstMask, abs(Double(fmask[i]) - p.re), abs(Double(fmask[i + 1]) - p.im))
        }
        XCTAssertLessThanOrEqual(worstMask, Self.maxMaskProbeError, "sondas de la máscara")
        let input = try AudioIO.readStereo(LeadSeparatorTests.fixtureDir.appendingPathComponent("input_2s_pcm16.wav"))
        let torch = try AudioIO.readStereo(LeadSeparatorTests.fixtureDir.appendingPathComponent("lead_torch_2s_f32.wav"))
        let lead = try CoreMLLeadSeparator(compiledModelURL: url, contract: .leadRhythmMSST)
            .separateLead(left: input.left, right: input.right, sampleRate: 44_100)
        XCTAssertEqual(lead.left.count, torch.frameCount)
        let sdr = snrDB(torch.left + torch.right, lead.left + lead.right)
        print(String(format: "[7.8] lead_rhythm fixture: sondas %.2e, SDR frente a PyTorch %.1f dB", worstMask, sdr))
        XCTAssertGreaterThanOrEqual(sdr, Self.minSDRvsTorch)
    }

    /// Compositor sobre la pista de guitarras de Platero (tramo 157–187 s), si está en `<TF_MODELS_DIR>\platero`:
    /// las pistas suman la entrada en el tramo.
    func test2_PlateroComposer() throws {
        let url = try requireHeavy()
        let platero = OnnxDevelopmentModels.directory("platero").appendingPathComponent("guitar.wav")
        guard FileManager.default.fileExists(atPath: platero.path) else { throw XCTSkip("no está Platero en \(platero.path)") }
        let span = GuitarSoloSpan(start: 157, end: 187)
        let out = try makeTempDir("platero-composer")
        let t0 = Date()
        let tracks = try GuitarStemComposer().compose(input: platero, outputDirectory: out, stereo: false,
                                                      soloSpans: [span], separator: CoreMLLeadSeparator(compiledModelURL: url))
        print(String(format: "[7.8] Platero compositor mono: %.1f s", Date().timeIntervalSince(t0)))
        XCTAssertEqual(tracks.map(\.role), [.rhythm, .lead])
        let src = try AudioIO.readStereo(platero)
        let all = try tracks.map { try AudioIO.readStereo($0.url) }
        let lo = Int((span.start - 2) * src.sampleRate), hi = Int((span.end + 2) * src.sampleRate)
        var sumErr: Float = 0
        for k in lo..<hi {
            sumErr = max(sumErr, abs(all.reduce(0) { $0 + $1.left[k] } - src.left[k]),
                         abs(all.reduce(0) { $0 + $1.right[k] } - src.right[k]))
        }
        XCTAssertLessThanOrEqual(sumErr, 1e-5, "las pistas suman la entrada (mismo umbral que en el Mac)")
    }
}
#else
import AVFoundation
import CoreML

/// Modelo de solista real (Mel-Band RoFormer «Lead_Rhythm_Guitar», FP16, `.cpuAndGPU`). Solo con `TF_MODEL_TESTS=1`
/// y bajo el vigilante, un test cada vez:
///   TF_MODEL_TESTS=1 Tools/py/.venv/bin/python Probes/P4-modelos/common/guard.py --limit-gb 10 \
///     --log Temp/logs/guard-lead.log -- Tools/test.sh StemKit LeadSeparatorHeavyTests/test1_ParityWithTorchFixture
final class LeadSeparatorHeavyTests: XCTestCase {
    /// Umbral de paridad frente a PyTorch (propuesta de tf-ml; Core ML FP16 en Python: 60,5 dB).
    static let minSDRvsTorch = 50.0
    /// Máscara FP16 frente a PyTorch: error absoluto máximo de las sondas.
    static let maxMaskProbeError = 0.02

    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let archive = repo.appendingPathComponent("App/Resources/Models/LeadRhythmMelRoformer_fp16.mlpackage.zip")
    static let compiled = repo.appendingPathComponent("Temp/models/LeadRhythmMelRoformer_fp16.mlmodelc")
    /// Platero, SOLO LECTURA.
    static let platero = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Music/ToneForge/El roce de tu cuerpo - Platero Y Tu/stems/guitar.wav")
    static let bench = repo.appendingPathComponent("Temp/bench/platero/composer")

    private func requireHeavy() throws {
        guard ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1" else {
            throw XCTSkip("tests del modelo real desactivados (TF_MODEL_TESTS != 1)")
        }
    }

    /// Descomprime el recurso de la app y lo compila una vez a Temp/models (lo mismo que hace ModelStore).
    private func compiledModel() async throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: Self.compiled.path) { return Self.compiled }
        let unzipDir = Self.repo.appendingPathComponent("Temp/models/.lead-unzip-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: unzipDir) }
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", Self.archive.path, unzipDir.path]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0, "ditto")
        let tmp = try await MLModel.compileModel(at: unzipDir.appendingPathComponent("LeadRhythmMelRoformer_fp16.mlpackage"))
        if !fm.fileExists(atPath: Self.compiled.path) { try fm.moveItem(at: tmp, to: Self.compiled) }
        return Self.compiled
    }

    /// Fixture de 2 s: sondas de la máscara Core ML frente a PyTorch y SDR de la solista frente a `lead_torch`.
    func test1_ParityWithTorchFixture() async throws {
        try requireHeavy()
        let url = try await compiledModel()
        let ref = try LeadSeparatorTests.reference()

        // Máscara: misma entrada que PyTorch (sondas de espectro ya verificadas en LeadSeparatorTests).
        let model = try CoreMLMaskModel(compiledModelURL: url, contract: .leadRhythm)
        let fixture = try LeadSeparatorTests.fixtureSpec()
        var spec = fixture.spec
        let stft = fixture.stft
        var mask = [Float](repeating: 0, count: stft.specCount)
        try model.predict(spec: &spec, mask: &mask)
        var worstMask = 0.0
        for p in ref.mask_probes {
            let i = stft.specIndex(bin: p.row / 2, channel: p.row % 2, frame: p.frame)
            worstMask = max(worstMask, abs(Double(mask[i]) - p.re), abs(Double(mask[i + 1]) - p.im))
        }
        XCTAssertLessThanOrEqual(worstMask, Self.maxMaskProbeError, "sondas de la máscara")

        let input = try AudioIO.readStereo(LeadSeparatorTests.fixtureDir.appendingPathComponent("input_2s_pcm16.wav"))
        let torch = try AudioIO.readStereo(LeadSeparatorTests.fixtureDir.appendingPathComponent("lead_torch_2s_f32.wav"))
        // Paridad: el plan de la referencia (num_overlap 1 de MSST), con el mismo código que usa la app.
        let sep = CoreMLLeadSeparator(compiledModelURL: url, contract: .leadRhythmMSST)
        let t0 = Date()
        let lead = try sep.separateLead(left: input.left, right: input.right, sampleRate: 44_100)
        let seconds = Date().timeIntervalSince(t0)
        XCTAssertEqual(lead.left.count, torch.frameCount)
        let sdr = snrDB(torch.left + torch.right, lead.left + lead.right)
        var maxAbs: Float = 0
        for k in 0..<torch.frameCount {
            maxAbs = max(maxAbs, abs(torch.left[k] - lead.left[k]), abs(torch.right[k] - lead.right[k]))
        }
        // Lo que usa la app (num_overlap 2): otro plan de trozos, así que no es paridad sino distancia informativa.
        let app = try CoreMLLeadSeparator(compiledModelURL: url)
            .separateLead(left: input.left, right: input.right, sampleRate: 44_100)
        let sdrApp = snrDB(torch.left + torch.right, app.left + app.right)
        // En [0, 1,5 s) solo pesa el primer trozo, idéntico en los dos planes: ahí num_overlap 2 = num_overlap 1.
        // La diferencia está en [1,5 s, 2 s), que se funde con un segundo trozo de 0,5 s de audio y 2,5 s de ceros.
        let half = MaskModelContract.leadRhythm.chunk / 2
        let sdrFirst = snrDB(Array(lead.left[..<half]) + Array(lead.right[..<half]),
                             Array(app.left[..<half]) + Array(app.right[..<half]))
        print(String(format: "PESADO lead num_overlap 2 frente a 1 en [0, 1,5 s): %.1f dB; frente a PyTorch en "
                     + "[0, 1,5 s): %.1f dB", sdrFirst,
                     snrDB(Array(torch.left[..<half]) + Array(torch.right[..<half]),
                           Array(app.left[..<half]) + Array(app.right[..<half]))))
        XCTAssertGreaterThanOrEqual(sdrFirst, 100)
        print(String(format: "PESADO lead paridad: SDR frente a PyTorch %.1f dB (num_overlap 1; Python FP16 %.1f), "
                     + "error máx %.2e, sondas de máscara %.2e, primera llamada (carga + 1 trozo) %.2f s; "
                     + "con num_overlap 2 (app) %.1f dB",
                     sdr, ref.coreml_fp16_sdr_vs_torch, maxAbs, worstMask, seconds, sdrApp))
        XCTAssertGreaterThanOrEqual(sdr, Self.minSDRvsTorch)
    }

    /// Compositor sobre la pista de guitarras de Platero con el tramo 157–187 s, mono y estéreo. Deja los WAV en
    /// Temp/bench/platero/composer/<modo>/ (luego `Tools/bench-rename.sh`). Mide tiempo y pico de memoria del
    /// proceso (el separador corre aquí, como en la app).
    func test2_PlateroComposer() async throws {
        try requireHeavy()
        guard FileManager.default.fileExists(atPath: Self.platero.path) else { throw XCTSkip("no está Platero") }
        let url = try await compiledModel()
        let span = GuitarSoloSpan(start: 157, end: 187)
        var report: [String] = []
        for (mode, stereo) in [("mono", false), ("estereo", true)] {
            let out = Self.bench.appendingPathComponent(mode)
            try? FileManager.default.removeItem(at: out)
            let baseline = MemoryGuard.footprint(pid: getpid()) ?? 0
            let guardian = MemoryGuard(pid: getpid(), limitBytes: .max, interval: 0.05)
            guardian.start()
            let t0 = Date()
            // Un separador por composición, como AppGuitarSplitter: el tiempo incluye cargar el modelo.
            let tracks = try GuitarStemComposer().compose(input: Self.platero, outputDirectory: out, stereo: stereo,
                                                          soloSpans: [span],
                                                          separator: CoreMLLeadSeparator(compiledModelURL: url))
            let seconds = Date().timeIntervalSince(t0)
            guardian.stop()
            let peak = guardian.peakBytes
            XCTAssertEqual(tracks.map(\.role), stereo ? [.left, .right, .lead] : [.rhythm, .lead])

            // Comprobación en el tramo: pistas suman la entrada; solista 0 fuera de la ventana con fundido.
            let src = try AudioIO.readStereo(Self.platero)
            let leadAudio = try AudioIO.readStereo(out.appendingPathComponent(GuitarStemRole.lead.fileName))
            let rate = src.sampleRate
            let others = try tracks.filter { $0.role != .lead }.map { try AudioIO.readStereo($0.url) }
            var sumErr: Float = 0
            let lo = Int((span.start - 2) * rate), hi = Int((span.end + 2) * rate)
            for k in lo..<hi {
                let l = others.reduce(leadAudio.left[k]) { $0 + $1.left[k] }
                let r = others.reduce(leadAudio.right[k]) { $0 + $1.right[k] }
                sumErr = max(sumErr, abs(l - src.left[k]), abs(r - src.right[k]))
            }
            let fade = GuitarStemComposer.fadeSeconds
            let outside = (0..<leadAudio.frameCount).filter {
                let t = Double($0) / rate
                return (t < span.start - fade || t > span.end + fade) && (leadAudio.left[$0] != 0 || leadAudio.right[$0] != 0)
            }.count
            let s0 = Int(span.start * rate), s1 = Int(span.end * rate)
            func rms(_ x: [Float]) -> Double { sqrt(x[s0..<s1].reduce(0) { $0 + Double($1) * Double($1) } / Double(s1 - s0)) }
            let zerosInSpan = (s0..<s1).filter { leadAudio.left[$0] == 0 && leadAudio.right[$0] == 0 }.count
            // Saltos entre muestras de la solista en el tramo: el mayor de todos y el mayor en ±2 muestras de cada
            // corte de trozo (inicio de ventana + j·paso). Con num_overlap 1 el mayor era 0,262, justo en un corte.
            func step(_ k: Int) -> Float {
                max(abs(leadAudio.left[k] - leadAudio.left[k - 1]), abs(leadAudio.right[k] - leadAudio.right[k - 1]))
            }
            let maxStep = (s0 + 1..<s1).map(step).max() ?? 0
            let windowStart = s0 - GuitarStemComposer.frames(fade + GuitarStemComposer.defaultContextSeconds, rate)
            let stepFrames = MaskModelContract.leadRhythm.chunk / MaskModelContract.leadRhythm.overlaps
            let cuts = stride(from: windowStart + stepFrames, to: s1, by: stepFrames).filter { $0 > s0 + 2 }
            let maxCutStep = cuts.flatMap { c in (c - 2...c + 2).map(step) }.max() ?? 0
            let p99Step: Float = {
                let s = (s0 + 1..<s1).map(step).sorted()
                return s[Int(Double(s.count) * 0.99)]
            }()
            report.append(String(format: "%@: salto máx de la solista en el tramo %.4f, en los %d cortes %.4f, p99 %.4f",
                                 mode, maxStep, cuts.count, maxCutStep, p99Step))
            XCTAssertEqual(zerosInSpan, 0, mode)
            report.append(String(format: "%@: compose %.1f s (carga + 32,2 s de ventana), pico proceso %.2f GB "
                                 + "(base %.2f GB, +%.0f MB), suma de pistas vs entrada máx %.1e, solista ≠ 0 fuera: %d, "
                                 + "RMS solista/entrada en el tramo %.3f/%.3f, muestras 0 en el tramo %d",
                                 mode, seconds, Double(peak) / 1e9, Double(baseline) / 1e9,
                                 (Double(peak) - Double(baseline)) / 1e6, sumErr, outside,
                                 rms(leadAudio.left), rms(src.left), zerosInSpan))
            XCTAssertLessThanOrEqual(sumErr, 1e-5, mode)
            XCTAssertEqual(outside, 0, mode)
        }
        print("PESADO lead Platero\n" + report.joined(separator: "\n"))
    }
}
#endif
