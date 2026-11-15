import AVFoundation
import CoreML
import XCTest
@testable import StemKit

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
