import XCTest
@testable import StemKit

#if os(Windows)
import NativeONNX

/// Separación con el ONNX real (parte 7.8). Solo con `TF_MODEL_TESTS=1`, de uno en uno y con la VM sola (pico de
/// 5,6 GB con T=345). Modelo y referencias en `<TF_MODELS_DIR o C:\tf-models>\bs_roformer` (parte 7.3; T=345):
/// `model.onnx`, `in_real.bin`/`in_imag.bin` y `ref_real.bin`/`ref_imag.bin` (ORT CPU del Mac, un trozo del
/// minuto 1 de T1), `T1_mix_60-85s.wav` y `T1_guitar_60-85s_coreml.wav` (guitarra de la app en el Mac).
final class HeavyModelTests: XCTestCase {
    /// Misma red, otro equipo: SNR ≥ 60 dB; frente a Core ML: SDR ≥ 15 dB (decisiones de Jorge, 19/11/2026).
    static let minSNRvsMacORT = 60.0
    static let minSDRvsCoreML = 15.0
    /// Bordes del fragmento fuera de la comparación: la app separó el tema entero y aquí solo 25 s (otro troceado).
    static let edgeSeconds = 2.0
    static let folder = "bs_roformer"

    private func requireHeavy() throws -> URL {
        guard ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1" else {
            throw XCTSkip("tests del modelo real desactivados (TF_MODEL_TESTS != 1)")
        }
        guard let url = OnnxDevelopmentModels.model(Self.folder) else {
            throw XCTSkip("no está el modelo en \(OnnxDevelopmentModels.directory(Self.folder).path)")
        }
        return url
    }

    /// Un trozo por `OnnxMaskModel` (máscara = out/spec y otra vez por spec) frente a ORT CPU del Mac.
    func test0_ChunkMatchesMacReference() throws {
        let url = try requireHeavy()
        let t0 = Date()
        let model = try OnnxMaskModel(modelURL: url, contract: .bsRoformerSW)
        let load = Date().timeIntervalSince(t0)
        XCTAssertEqual(model.interface, .maskedSpectrum)
        let bins = RoformerContract.bins, frames = model.frames, stems = RoformerContract.stemCount
        print("[7.8] bs_roformer: T=\(frames) del modelo, proveedor \(model.session.provider), carga \(String(format: "%.1f", load)) s")
        let re = try OnnxDevelopmentModels.floats(Self.folder, "in_real.bin")
        let im = try OnnxDevelopmentModels.floats(Self.folder, "in_imag.bin")
        XCTAssertEqual(re.count, 2 * bins * frames, "entrada de la 7.3 con la T del modelo")
        var spec = [Float](repeating: 0, count: 2 * bins * frames * 2)
        for c in 0..<2 { for f in 0..<bins { for t in 0..<frames {
            let p = (c * bins + f) * frames + t, s = ((2 * f + c) * frames + t) * 2
            spec[s] = re[p]; spec[s + 1] = im[p]
        } } }
        var mask = [Float](repeating: .nan, count: stems * 2 * bins * frames * 2)
        let t1 = Date()
        try model.predict(spec: &spec, mask: &mask)
        print("[7.8] bs_roformer: trozo en \(String(format: "%.1f", Date().timeIntervalSince(t1))) s")
        var outRe = [Float](repeating: 0, count: stems * 2 * bins * frames), outIm = outRe
        for st in 0..<stems { for c in 0..<2 { for f in 0..<bins { for t in 0..<frames {
            let s = ((2 * f + c) * frames + t) * 2, m = ((st * 2 * bins + 2 * f + c) * frames + t) * 2
            let o = st * 2 * bins * frames + (c * bins + f) * frames + t
            outRe[o] = mask[m] * spec[s] - mask[m + 1] * spec[s + 1]
            outIm[o] = mask[m] * spec[s + 1] + mask[m + 1] * spec[s]
        } } } }
        let snrRe = snrDB(try OnnxDevelopmentModels.floats(Self.folder, "ref_real.bin"), outRe)
        let snrIm = snrDB(try OnnxDevelopmentModels.floats(Self.folder, "ref_imag.bin"), outIm)
        print("[7.8] bs_roformer: SNR frente a ORT Mac \(String(format: "%.1f", snrRe)) / \(String(format: "%.1f", snrIm)) dB")
        XCTAssertGreaterThanOrEqual(min(snrRe, snrIm), Self.minSNRvsMacORT)
    }

    /// 25 s de T1 por tf-separate y SeparationRunner: guitarra frente a la de la app (Core ML) en el Mac.
    func test1_ExcerptThroughRunner() async throws {
        _ = try requireHeavy()
        let mix = OnnxDevelopmentModels.directory(Self.folder).appendingPathComponent("T1_mix_60-85s.wav")
        try await separateAndCompare(input: mix, label: "44,1 kHz")
    }

    /// El mismo fragmento a 48 kHz (remuestreo r8brain de ida en el test y de vuelta en el helper).
    func test2_Input48kThroughRunner() async throws {
        _ = try requireHeavy()
        let src = try AudioIO.readStereo(OnnxDevelopmentModels.directory(Self.folder).appendingPathComponent("T1_mix_60-85s.wav"))
        let dir = try makeTempDir("heavy48")
        let input = dir.appendingPathComponent("mix48.wav")
        try writeStereo(try AudioIO.resample(src, to: 48_000), to: input)
        try await separateAndCompare(input: input, label: "48 kHz")
    }

    private func separateAndCompare(input: URL, label: String) async throws {
        let model = try requireHeavy()
        let out = try makeTempDir("heavy-out")
        let runner = SeparationRunner(helperURL: builtProduct("tf-separate"))
        var finished: (Double, UInt64)?
        let t0 = Date()
        for try await e in runner.run(model: model, input: input, outputDirectory: out) {
            if case .finished(let s, let p) = e { finished = (s, p) }
        }
        let (seconds, peak) = try XCTUnwrap(finished)
        let source = try AudioIO.readStereo(input)
        let minutes = Double(source.frameCount) / source.sampleRate / 60
        print("[7.8] tf-separate \(label): \(String(format: "%.1f", seconds)) s (\(String(format: "%.0f", seconds / minutes)) s/min, pared \(String(format: "%.1f", Date().timeIntervalSince(t0))) s), pico \(peak >> 20) MB")
        var guitar = try AudioIO.readStereo(out.appendingPathComponent(Stem.guitar.fileName))
        XCTAssertEqual(guitar.frameCount, source.frameCount, "misma longitud que la entrada")
        if guitar.sampleRate != 44_100 { guitar = try AudioIO.resample(guitar, to: 44_100) }
        let app = try AudioIO.readStereo(OnnxDevelopmentModels.directory(Self.folder)
            .appendingPathComponent("T1_guitar_60-85s_coreml.wav"))
        let edge = Int(Self.edgeSeconds * 44_100)
        let n = min(app.frameCount, guitar.frameCount) - edge
        let sdr = (snrDB(Array(app.left[edge..<n]), Array(guitar.left[edge..<n]))
                   + snrDB(Array(app.right[edge..<n]), Array(guitar.right[edge..<n]))) / 2
        print("[7.8] tf-separate \(label): guitarra frente a Core ML de la app \(String(format: "%.1f", sdr)) dB")
        XCTAssertGreaterThanOrEqual(sdr, Self.minSDRvsCoreML)
    }
}
#else
import AVFoundation
import CoreML

/// Tests con el modelo real. Solo con `TF_MODEL_TESTS=1` y siempre bajo el vigilante:
///   TF_MODEL_TESTS=1 Tools/py/.venv/bin/python Probes/P4-modelos/common/guard.py --limit-gb 10 \
///     --log Temp/logs/guard-stemkit.log -- Tools/test.sh StemKit HeavyModelTests
/// El modelo solo se ejecuta dentro de tf-separate, lanzado por SeparationRunner: uno a la vez.
final class HeavyModelTests: XCTestCase {
    /// Criterios del encargo de la Fase 1 (P5), con P4 como referencia (docs/probes/P4-modelos.md).
    static let minSNRvsTorch = 50.0                 // dB; P4: Core ML publicado 57-68 dB frente a PyTorch
    static let maxRealTimeFactor = 0.40             // P4: 0,37×
    static let maxHelperPeakBytes: UInt64 = 6_500_000_000
    static let maxParentGrowthPerTrack: Int64 = 200_000_000

    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let package = repo.appendingPathComponent("Probes/P4-modelos/bs_roformer_sw/out/coreml_pub/BSRoformerSW.mlpackage")
    static let compiled = repo.appendingPathComponent("Temp/models/BSRoformerSW.mlmodelc")
    static let work = repo.appendingPathComponent("Temp/stemkit-heavy")

    /// Helper a medir: `TF_SEPARATE_HELPER` (p. ej. el binario release, que es el que irá en la app);
    /// si no, el de debug que compila `swift test`.
    private var helper: URL {
        ProcessInfo.processInfo.environment["TF_SEPARATE_HELPER"].map { URL(fileURLWithPath: $0) }
            ?? builtProduct("tf-separate")
    }

    private func requireHeavy() throws {
        guard ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1" else {
            throw XCTSkip("tests del modelo real desactivados (TF_MODEL_TESTS != 1)")
        }
    }

    /// Compila el .mlpackage una vez a Temp/models y lo reutiliza.
    private func compiledModel() async throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: Self.compiled.path) { return Self.compiled }
        let tmp = try await MLModel.compileModel(at: Self.package)
        try fm.createDirectory(at: Self.compiled.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: Self.compiled.path) { try fm.moveItem(at: tmp, to: Self.compiled) }
        return Self.compiled
    }

    private struct RunResult { let seconds: Double; let wall: Double; let peak: UInt64 }

    private func separate(_ runner: SeparationRunner, model: URL, input: URL, out: URL) async throws -> RunResult {
        let t0 = Date()
        var finished: (Double, UInt64)?
        for try await e in runner.run(model: model, input: input, outputDirectory: out) {
            if case .finished(let s, let p) = e { finished = (s, p) }
        }
        let (s, p) = try XCTUnwrap(finished)
        return RunResult(seconds: s, wall: Date().timeIntervalSince(t0), peak: p)
    }

    private func duration(_ url: URL) throws -> Double {
        let f = try AVAudioFile(forReading: url)
        return Double(f.length) / f.processingFormat.sampleRate
    }

    func test0_EnvironmentReachesTestProcess() throws {
        try requireHeavy()
        print("TF_MODEL_TESTS=1 visible en el proceso de test (pid \(getpid()))")
    }

    /// T1, T2 y T3 seguidos por SeparationRunner: SNR de T1 frente a PyTorch, tiempo, pico del helper
    /// y crecimiento de memoria del proceso padre.
    func test1_ThreeTracksThroughRunner() async throws {
        try requireHeavy()
        let model = try await compiledModel()
        let runner = SeparationRunner(helperURL: helper)
        let tracks = ["T1", "T2", "T3"]
        let inputs = tracks.map { Self.repo.appendingPathComponent("Probes/testaudio/out/\($0)/mix.wav") }
        let durations = try inputs.map(duration)
        let baseline = Int64(MemoryGuard.footprint(pid: getpid()) ?? 0)
        var previous = baseline
        var report: [String] = []
        for (k, name) in tracks.enumerated() {
            let out = Self.work.appendingPathComponent(name)
            let r = try await separate(runner, model: model, input: inputs[k], out: out)
            let now = Int64(MemoryGuard.footprint(pid: getpid()) ?? 0)
            let factor = r.seconds / durations[k]
            report.append(String(format: "%@: %.1f s de audio, separación %.1f s (%.3f×), total %.1f s, pico helper %.2f GB, padre %+.0f MB",
                                 name, durations[k], r.seconds, factor, r.wall, Double(r.peak) / 1e9,
                                 Double(now - previous) / 1e6))
            XCTAssertLessThanOrEqual(factor, Self.maxRealTimeFactor, "\(name): factor de tiempo real")
            XCTAssertLessThanOrEqual(r.peak, Self.maxHelperPeakBytes, "\(name): pico del helper")
            XCTAssertGreaterThan(r.peak, 0, "\(name): MemoryGuard no midió nada")
            XCTAssertLessThanOrEqual(now - previous, Self.maxParentGrowthPerTrack, "\(name): crecimiento del padre")
            for s in Stem.allCases {
                let f = try AVAudioFile(forReading: out.appendingPathComponent(s.fileName))
                XCTAssertEqual(f.length, AVAudioFramePosition((durations[k] * 44_100).rounded()), "\(name) \(s)")
            }
            previous = now
        }
        report.append(String(format: "padre: %+.0f MB en total tras 3 temas", Double(previous - baseline) / 1e6))

        // SNR de T1 frente a la referencia PyTorch de P4, stem a stem.
        let refDir = Self.repo.appendingPathComponent("Probes/P4-modelos/bs_roformer_sw/out/ref_torch/T1")
        for s in Stem.allCases {
            let snr = try autoreleasepool {
                let ref = try AudioIO.readStereo(refDir.appendingPathComponent(s.fileName))
                let est = try AudioIO.readStereo(Self.work.appendingPathComponent("T1").appendingPathComponent(s.fileName))
                return snrDB(ref, est)
            }
            report.append(String(format: "T1 %@: SNR frente a PyTorch %.1f dB", s.rawValue, snr))
            if [.guitar, .bass, .drums, .vocals].contains(s) {
                XCTAssertGreaterThanOrEqual(snr, Self.minSNRvsTorch, "T1 \(s.rawValue)")
            }
        }
        print("PESADO\n" + report.joined(separator: "\n"))
    }

    /// Recorte de 30 s de T1 remuestreado a 48 kHz: stems a 48 kHz con la longitud exacta.
    func test2_Input48kThroughRunner() async throws {
        try requireHeavy()
        let model = try await compiledModel()
        let src = try AVAudioFile(forReading: Self.repo.appendingPathComponent("Probes/testaudio/out/T1/mix.wav"),
                                  commonFormat: .pcmFormatFloat32, interleaved: false)
        let n44 = 30 * 44_100
        src.framePosition = 60 * 44_100
        let buf = AVAudioPCMBuffer(pcmFormat: src.processingFormat, frameCapacity: AVAudioFrameCount(n44))!
        try src.read(into: buf, frameCount: AVAudioFrameCount(n44))
        let clip = StereoAudio(left: Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: n44)),
                               right: Array(UnsafeBufferPointer(start: buf.floatChannelData![1], count: n44)),
                               sampleRate: 44_100)
        let clip48 = try AudioIO.resample(clip, to: 48_000)
        try FileManager.default.createDirectory(at: Self.work, withIntermediateDirectories: true)
        let input = Self.work.appendingPathComponent("T1_30s_48k.wav")
        try writeStereo(clip48, to: input)
        let out = Self.work.appendingPathComponent("T1_30s_48k")
        let r = try await separate(SeparationRunner(helperURL: helper),
                                   model: model, input: input, out: out)
        var sumL = [Float](repeating: 0, count: clip48.frameCount), sumR = sumL
        for s in Stem.allCases {
            let st = try AudioIO.readStereo(out.appendingPathComponent(s.fileName))
            XCTAssertEqual(st.sampleRate, 48_000, s.rawValue)
            XCTAssertEqual(st.frameCount, clip48.frameCount, s.rawValue)
            for k in 0..<min(st.frameCount, sumL.count) { sumL[k] += st.left[k]; sumR[k] += st.right[k] }
        }
        let recon = snrDB(clip48, StereoAudio(left: sumL, right: sumR, sampleRate: 48_000))
        print(String(format: "PESADO 48k: %d muestras a 48 kHz, separación %.1f s, pico helper %.2f GB, "
                     + "suma de stems frente a la mezcla %.1f dB", clip48.frameCount, r.seconds,
                     Double(r.peak) / 1e9, recon))
    }
}
#endif
