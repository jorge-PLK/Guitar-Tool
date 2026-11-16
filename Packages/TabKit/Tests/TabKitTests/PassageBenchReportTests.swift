import AVFoundation
import XCTest
@testable import TabKit

/// Informativo, sin umbral: tabla de pasajes de un proyecto real de la app para contrastarla de oído. Lee (solo
/// lectura) `<proyecto>/stems/guitar.wav` y los downbeats de `<proyecto>/cache/analysis.json`; si en la carpeta de
/// salida hay `guitar_L.wav`, `guitar_C.wav` o `guitar_R.wav` (de `PanSplitter`), también los clasifica. Escribe en
/// la carpeta de salida `passages_<pista>.txt`, `bars_<pista>.csv` (medidas por compás) y `notes_<pista>.json`
/// (caché de notas: se reutiliza si es más nueva que la pista). Bajo el vigilante:
///   TF_MODEL_TESTS=1 TF_BENCH_PROJECT="<carpeta del proyecto>" TF_BENCH_OUT=Temp/bench/platero/stems \
///     Tools/py/.venv/bin/python Probes/P4-modelos/common/guard.py --limit-gb 10 \
///     --log Temp/logs/guard-tabkit-bench.log -- Tools/test.sh TabKit PassageBenchReportTests
final class PassageBenchReportTests: XCTestCase {
    func testReportProjectPassages() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["TF_MODEL_TESTS"] == "1", let project = env["TF_BENCH_PROJECT"], let outPath = env["TF_BENCH_OUT"] else {
            throw XCTSkip("banco desactivado (hacen falta TF_MODEL_TESTS=1, TF_BENCH_PROJECT y TF_BENCH_OUT)")
        }
        let root = URL(fileURLWithPath: project)
        let out = outPath.hasPrefix("/") ? URL(fileURLWithPath: outPath) : Fixture.repo.appendingPathComponent(outPath)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let analysis = try Fixture.json(root.appendingPathComponent("cache/analysis.json"))
        let beats = try XCTUnwrap((analysis["analysis"] as? [String: Any])?["beats"] as? [String: Any])
        let downbeats = try XCTUnwrap(beats["downbeats"] as? [Double])

        var tracks = [("guitar", root.appendingPathComponent("stems/guitar.wav"))]
        for side in ["L", "C", "R"] {
            let u = out.appendingPathComponent("guitar_\(side).wav")
            if FileManager.default.fileExists(atPath: u.path) { tracks.append(("guitar_\(side)", u)) }
        }
        for (name, url) in tracks {
            let notes = try await Self.cachedNotes(url, cache: out.appendingPathComponent("notes_\(name).json"))
            let text = try Self.report(name: name, url: url, notes: notes, downbeats: downbeats, out: out)
            print(text)
        }
    }

    /// Notas de la pista, de la caché si es más nueva que el audio.
    static func cachedNotes(_ url: URL, cache: URL) async throws -> [NoteEvent] {
        let fm = FileManager.default
        if let c = try? fm.attributesOfItem(atPath: cache.path)[.modificationDate] as? Date,
           let a = try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date, c > a {
            return try JSONDecoder().decode([NoteEvent].self, from: Data(contentsOf: cache))
        }
        let transcriber = BasicPitchTranscriber(modelURL: try BasicPitchHeavyModelTests.compiledModel())
        let notes = try await transcriber.transcribe(url: url)
        try JSONEncoder().encode(notes).write(to: cache)
        return notes
    }

    /// Tabla de pasajes, resumen por papel y CSV por compás; los deja en `out` y devuelve el texto.
    static func report(name: String, url: URL, notes: [NoteEvent], downbeats: [Double], out: URL) throws -> String {
        let f = try AVAudioFile(forReading: url)
        let duration = Double(f.length) / f.processingFormat.sampleRate
        let passages = PassageClassifier.classify(notes: notes, downbeats: downbeats, duration: duration)
        var time: [GuitarRole: Double] = [:]
        for p in passages { time[p.role, default: 0] += p.end - p.start }
        let share = GuitarRole.allCases.map { String(format: "%@ %.0f %%", $0.rawValue, 100 * (time[$0] ?? 0) / duration) }
        var lines = ["\(name).wav: \(notes.count) notas, \(passages.count) pasajes (\(share.joined(separator: ", ")))",
                     "inicio–fin     papel    conf   notas  polifonía"]
        for p in passages {
            let inside = notes.filter { $0.start >= p.start && $0.start < p.end }.count
            let poly = PassageClassifier.features(notes: notes, start: p.start, end: p.end).meanPolyphony
            let role = p.role.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)
            lines.append(String(format: "%@–%@  %@  %.2f  %5d  %.2f", mmss(p.start), mmss(p.end), role, p.confidence, inside, poly))
        }
        let text = lines.joined(separator: "\n") + "\n"
        try text.write(to: out.appendingPathComponent("passages_\(name).txt"), atomically: true, encoding: .utf8)

        var csv = ["start,end,active,poly,three,power,density,register,amplitude,score"]
        for b in PassageClassifier.bars(downbeats: downbeats, duration: duration) {
            let x = PassageClassifier.features(notes: notes, start: b.start, end: b.end)
            csv.append(String(format: "%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.2f,%.3f,%.3f", b.start, b.end, x.activeFraction,
                              x.meanPolyphony, x.threeOrMoreFraction, x.powerChordFraction, x.density, x.register,
                              x.amplitude, PassageClassifier.rhythmScore(x)))
        }
        try (csv.joined(separator: "\n") + "\n").write(to: out.appendingPathComponent("bars_\(name).csv"),
                                                        atomically: true, encoding: .utf8)
        return text
    }

    static func mmss(_ t: Double) -> String {
        let s = Int(t.rounded())
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
