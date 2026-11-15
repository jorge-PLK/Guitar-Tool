import Darwin
import XCTest
@testable import StudyKit

/// Pulso con el modelo real (mini-spec Fase 2 §4 P2). Solo con `TF_MODEL_TESTS=1` y siempre bajo el vigilante:
///   TF_MODEL_TESTS=1 Tools/py/.venv/bin/python Probes/P4-modelos/common/guard.py --limit-gb 10 \
///     --log Temp/logs/guard-studykit-beat.log -- Tools/test.sh StudyKit BeatHeavyModelTests
/// Modelo: `TF_BEAT_MODEL` o `Probes/P4-modelos/beat_this/out/hf_supracut/BeatThis.mlmodelc`. Sin él, se salta.
final class BeatHeavyModelTests: XCTestCase {
    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// Criterios de §4 P2.
    static let matchTolerance = 0.020      // ±20 ms
    static let minMatchPercent = 99.0
    static let tempoTolerance = 0.05
    static let maxSecondsPerSong = 10.0
    /// Tempo de P4 (media a ±20 % de la mediana, ADR-006).
    static let p4Tempo = ["T1": 124.99, "T2": 74.00, "T3": 110.02]

    private func modelURL() throws -> URL {
        guard ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1" else {
            throw XCTSkip("tests del modelo real desactivados (TF_MODEL_TESTS != 1)")
        }
        let url = ProcessInfo.processInfo.environment["TF_BEAT_MODEL"].map { URL(fileURLWithPath: $0) }
            ?? Self.repo.appendingPathComponent("Probes/P4-modelos/beat_this/out/hf_supracut/BeatThis.mlmodelc")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("no está el modelo en \(url.path)") }
        return url
    }

    /// Swift (log-mel + Core ML) sobre el tramo del fixture: mismos pulsos que Python; diferencia de logits informativa.
    func test1_FixtureWithRealModel() throws {
        let model = try modelURL()
        let x = try BeatAudio.loadMono(BeatTests.fixtures.appendingPathComponent("mix_22k.wav"))
        let spect = try BeatLogMel.shared.compute(x)
        let logits = try BeatChunker.predict(spect: spect.values, frames: spect.frames,
                                             with: try CoreMLBeatPredictor(modelURL: model))
        let refB = try BeatTests.f32("beat_logits_beat.f32"), refD = try BeatTests.f32("beat_logits_downbeat.f32")
        let db = zip(logits.beat, refB).map { abs($0 - $1) }.max()!
        let dd = zip(logits.downbeat, refD).map { abs($0 - $1) }.max()!
        print("fixture: logits Swift vs Python máx beat \(db), downbeat \(dd)")
        let (beats, downbeats) = BeatPostprocessor.minimal(beat: logits.beat, downbeat: logits.downbeat)
        let ref = try BeatTests.ref()
        XCTAssertEqual(beats, ref.beats)
        XCTAssertEqual(downbeats, ref.downbeats)
    }

    /// T1–T3 completos frente a los pulsos Core ML de P4.
    func test2_SongsMatchP4() async throws {
        let model = try modelURL()
        let analyzer = BeatAnalyzer(modelURL: model)
        for song in ["T1", "T2", "T3"] {
            let mix = Self.repo.appendingPathComponent("Probes/testaudio/out/\(song)/mix.wav")
            let refDir = Self.repo.appendingPathComponent("Probes/P4-modelos/beat_this/out/beats/coreml_comm")
            guard FileManager.default.fileExists(atPath: mix.path) else { throw XCTSkip("falta \(mix.path)") }
            let refBeats = try Self.times(refDir.appendingPathComponent("\(song).beats.txt"))
            let refDowns = try Self.times(refDir.appendingPathComponent("\(song).downbeats.txt"))

            let t0 = Date()
            let grid = try await analyzer.analyze(mix: mix)
            let secs = Date().timeIntervalSince(t0)

            let pb = Self.matchPercent(ref: refBeats, est: grid.beats)
            let pd = Self.matchPercent(ref: refDowns, est: grid.downbeats)
            let pbBack = Self.matchPercent(ref: grid.beats, est: refBeats)
            print(String(format: "%@: %.2f s · pulsos %d/%d %.2f %% (inverso %.2f %%) · downbeats %d/%d %.2f %% · bpm %.3f · compás %d · footprint %.2f GB",
                         song, secs, grid.beats.count, refBeats.count, pb, pbBack, grid.downbeats.count, refDowns.count,
                         pd, grid.bpm ?? .nan, grid.beatsPerBar ?? 0, Double(Self.footprint()) / 1e9))
            XCTAssertGreaterThanOrEqual(pb, Self.minMatchPercent, song)
            XCTAssertGreaterThanOrEqual(pbBack, Self.minMatchPercent, song)
            XCTAssertGreaterThanOrEqual(pd, Self.minMatchPercent, song)
            XCTAssertEqual(grid.bpm ?? 0, Self.p4Tempo[song]!, accuracy: Self.tempoTolerance, song)
            XCTAssertLessThanOrEqual(secs, Self.maxSecondsPerSong, song)
        }
    }

    // MARK: utilidades

    static func times(_ url: URL) throws -> [Double] {
        try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).compactMap { Double($0) }
    }

    /// % de instantes de `ref` con uno de `est` a ±20 ms (`bt_common.match_pct`).
    static func matchPercent(ref: [Double], est: [Double], tol: Double = matchTolerance) -> Double {
        guard !ref.isEmpty else { return est.isEmpty ? 100 : 0 }
        guard !est.isEmpty else { return 0 }
        let hits = ref.filter { r in
            let x = BeatGrid.nearest(est, r)!
            return abs(x - r) <= tol + 1e-9
        }.count
        return 100 * Double(hits) / Double(ref.count)
    }

    /// `phys_footprint` del proceso de test (incluye memoria Metal atribuida).
    static func footprint() -> UInt64 {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
        }
        return rc == 0 ? info.ri_phys_footprint : 0
    }
}
