#if canImport(CoreML)
import CoreML
#endif
import XCTest
@testable import StudyKit

/// Acordes y tonalidad con el modelo real (mini-spec Fase 2 §4 P3). Solo con `TF_MODEL_TESTS=1` y siempre bajo
/// el vigilante:
///   TF_MODEL_TESTS=1 Tools/py/.venv/bin/python Probes/P4-modelos/common/guard.py --limit-gb 10 \
///     --log Temp/logs/guard-studykit-chord.log -- Tools/test.sh StudyKit ChordHeavyModelTests
/// Modelo: `Probes/P4-modelos/btc/out/coreml/BTC_large_voca_fp16.mlpackage`, compilado en el test a un temporal.
/// Sin él (o sin los stems de P4), se salta.
final class ChordHeavyModelTests: XCTestCase {
    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let p4 = repo.appendingPathComponent("Probes/P4-modelos")

    /// Criterios de §4 P3.
    static let minMatchPercent = 99.0
    static let maxSecondsPerSong = 15.0
    static let harmonicStems = ["bass", "guitar", "other", "piano"]

    nonisolated(unsafe) private static var compiled: URL?

    private func modelURL() throws -> URL {
        #if canImport(CoreML)
        guard ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1" else {
            throw XCTSkip("tests del modelo real desactivados (TF_MODEL_TESTS != 1)")
        }
        if let c = Self.compiled { return c }
        let pkg = Self.p4.appendingPathComponent("btc/out/coreml/BTC_large_voca_fp16.mlpackage")
        guard FileManager.default.fileExists(atPath: pkg.path) else { throw XCTSkip("no está el modelo en \(pkg.path)") }
        let c = try MLModel.compileModel(at: pkg)
        Self.compiled = c
        return c
        #else
        // Windows (parte 7.8): ONNX de la parte 7.3 en `<TF_MODELS_DIR o C:\tf-models>\btc\model.onnx`.
        guard ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1" else {
            throw XCTSkip("tests del modelo real desactivados (TF_MODEL_TESTS != 1)")
        }
        let url = studyKitDevelopmentModel("btc")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("no está el modelo en \(url.path)") }
        return url
        #endif
    }

    /// Etiqueta por fotograma de un `.lab` (fotograma i ↦ el segmento que contiene (i + ½)·Δ).
    static func frames(lab: String, count: Int) -> [Int] {
        let d = ChordContract.frameDuration
        let segs: [(Double, Double, Int)] = lab.split(separator: "\n").compactMap { line in
            let p = line.split(separator: " ")
            guard p.count == 3, let s = Double(p[0]), let e = Double(p[1]),
                  let l = ChordLabel(labName: String(p[2])) else { return nil }
            return (s, e, l.index)
        }
        var out = [Int](repeating: -1, count: count)
        var j = 0
        for i in 0..<count {
            let t = (Double(i) + 0.5) * d
            while j < segs.count - 1 && t >= segs[j].1 { j += 1 }
            if j < segs.count && t >= segs[j].0 && t < segs[j].1 { out[i] = segs[j].2 }
        }
        return out
    }

    static func frames(_ segments: [ChordSegment]) -> [Int] {
        let d = ChordContract.frameDuration
        var out: [Int] = []
        for s in segments {
            let n = Int(((s.end - s.start) / d).rounded())
            out.append(contentsOf: repeatElement(s.index, count: n))
        }
        return out
    }

    struct KeySong: Decodable {
        let key: String
        let alternative: String
        let confidence: Double
        let scores: [Double]
        let n_frames: Int
    }

    /// El modelo sobre las ventanas del fixture: logits frente a los de Python (Core ML ANE en coremltools).
    func testFixtureWindowsMatchPythonLogits() throws {
        let predictor = try makeChordPredictor(modelURL: try modelURL())
        let input = try ChordRecognizerTests.f32("chord_input.f32")
        let ref = try ChordRecognizerTests.f32("chord_logits.f32")
        let labels = try ChordFeatures.predictLabels(input: input, frames: 130, with: predictor)
        let refArgmax = Array(try ChordRecognizerTests.i32("chord_argmax.i32")[0..<130])
        let same = zip(labels, refArgmax).filter { $0 == $1 }.count
        // Logits de la primera ventana (sin relleno).
        let l0 = try input.withUnsafeBufferPointer { try predictor.logits(window: UnsafeBufferPointer(rebasing: $0[0..<(108 * 144)])) }
        let maxDiff = zip(l0, ref[0..<(108 * 170)]).map { abs($0 - $1) }.max()!
        print(String(format: "fixture: argmax igual en %d/130, logits ventana 1 máx dif %.3e", same, maxDiff))
        XCTAssertGreaterThanOrEqual(Double(same) / 130 * 100, Self.minMatchPercent)
    }

    /// T1–T3 desde los stems de P4 frente a los `.lab` de P4 (Core ML ANE y PyTorch) y tonalidad frente a
    /// `key_songs.json`.
    func testSongsMatchP4() async throws {
        let model = try modelURL()
        let keyRef = try JSONDecoder().decode([String: KeySong].self,
                                              from: Data(contentsOf: ChordRecognizerTests.url("key_songs.json")))
        let recognizer = ChordRecognizer(modelURL: model)
        for tema in ["T1", "T2", "T3"] {
            let dir = Self.p4.appendingPathComponent("bs_roformer_sw/out/conv/coremlpub_cpu_gpu/\(tema)")
            let stems = Self.harmonicStems.map { dir.appendingPathComponent("\($0).wav") }
            guard stems.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
                throw XCTSkip("faltan stems en \(dir.path)")
            }
            let t0 = Date()
            let analysis = try await recognizer.analyze(stems: stems)
            let secs = Date().timeIntervalSince(t0)
            let mine = Self.frames(analysis.segments)
            XCTAssertEqual(mine.count, analysis.frameCount)

            var line = String(format: "%@: %d fotogramas, %.2f s", tema, mine.count, secs)
            for ref in ["coreml_ane_fp16", "torch"] {
                let labURL = Self.p4.appendingPathComponent("btc/out/lab/\(ref)/\(tema)_stems.lab")
                let lab = try String(contentsOf: labURL, encoding: .utf8)
                let theirs = Self.frames(lab: lab, count: mine.count)
                let same = zip(mine, theirs).filter { $0 == $1 }.count
                let pct = Double(same) / Double(mine.count) * 100
                line += String(format: " · %@ %.2f %%", ref, pct)
                XCTAssertGreaterThanOrEqual(pct, Self.minMatchPercent, "\(tema) frente a \(ref)")
            }

            let key = KeyDetector.detect(chroma: analysis.chroma, segments: analysis.segments)
            let r = try XCTUnwrap(keyRef[tema])
            let chroma = analysis.chroma.map { $0.reduce(0.0) { $0 + Double($1) } }
            let scores = KeyDetector.scores(chroma: chroma, histogram: KeyDetector.histogram(analysis.segments))
            let ds = zip(scores, r.scores).map { abs($0 - $1) }.max()!
            line += String(format: " · tonalidad %@ (alt %@, conf %.4f) ref %@ (%.4f), dif. puntuaciones máx %.2e",
                           key.key, key.alternative, key.confidence, r.key, r.confidence, ds)
            print(line)
            XCTAssertEqual(analysis.frameCount, r.n_frames, tema)
            XCTAssertEqual(key.key, r.key, tema)
            XCTAssertLessThanOrEqual(secs, Self.maxSecondsPerSong, tema)
        }
    }
}
