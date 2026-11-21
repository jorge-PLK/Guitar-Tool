import Foundation
import NativeAudioFile
import XCTest
@testable import TabKit

/// Rejilla del metrónomo con Songsterr en El roce: diagnóstico del `BeatGrid`, rejilla corregida y WAV de escucha
/// (mezcla + clic con acento en el 1) para Jorge. Lee datos sin versionar, como `SongsterrAlignmentRoceTests`:
///   TF_P5B_TESTS=1 Tools/test.sh TabKit SongsterrBeatGridRoceTests
/// Escribe `Temp/p5b/CHECK_roce_metro_actual.wav`, `Temp/p5b/CHECK_roce_metro_songsterr.wav` y
/// `Temp/p5b/roce_metro_grids.json` (las dos rejillas, para medirlas con otro detector de ataques).
final class SongsterrBeatGridRoceTests: XCTestCase {
    static let project = SongsterrAlignmentRoceTests.project
    static let songsterr = SongsterrAlignmentRoceTests.songsterr
    static let p5b = SongsterrAlignmentRoceTests.p5b

    /// Tramo del medio: desde 10 s antes del compás tocado 73 (aviso de estructura de la alineación) hasta 30 s después.
    static let middleBar = 72
    static let middleBefore = 10.0, middleAfter = 30.0
    static let introSeconds = 60.0

    func testRoceMeterGrid() throws {
        guard ProcessInfo.processInfo.environment["TF_P5B_TESTS"] == "1" else {
            throw XCTSkip("puerta de El roce desactivada (TF_P5B_TESTS != 1)")
        }
        let fm = FileManager.default
        try XCTSkipUnless(fm.fileExists(atPath: Self.project.path), "falta \(Self.project.path)")
        try XCTSkipUnless(fm.fileExists(atPath: Self.songsterr.path), "falta \(Self.songsterr.path)")

        let tracks = try (0..<3).map { try SongsterrTrackConverter.convert(Data(contentsOf: Self.songsterr.appendingPathComponent("\($0).json"))) }
        let an = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.project.appendingPathComponent("cache/analysis.json"))) as! [String: Any]
        let b = (an["analysis"] as! [String: Any])["beats"] as! [String: Any]
        let raw = BeatTimes(beats: b["beats"] as! [Double], downbeats: b["downbeats"] as! [Double],
                            beatsPerBar: b["beatsPerBar"] as? Int)
        var stems: [SongsterrStemRole: URL] = [:]
        for r in SongsterrStemRole.allCases { stems[r] = Self.project.appendingPathComponent("stems/\(r.rawValue).wav") }
        let drumsURL = Self.project.appendingPathComponent("stems/drums.wav")

        let written = try XCTUnwrap(SongsterrBeatGrid.writtenTempo(tracks))
        let prepared = SongsterrBeatGrid.prepare(raw, writtenTempo: written)
        print("METRO tempo escrito \(written) detectado (mediana) \(String(format: "%.2f", prepared.detectedTempo)) "
              + "cociente \(String(format: "%.3f", (60 / written) / (60 / prepared.detectedTempo))) fold \(prepared.fold) "
              + "pulsos \(raw.beats.count) → \(prepared.beats.beats.count) (+\(prepared.insertedBeats) −\(prepared.removedBeats))")
        let added = prepared.beats.beats.filter { t in !raw.beats.contains { abs($0 - t) < 1e-6 } }
        print("METRO pulsos añadidos en \(added.map { String(format: "%.2f", $0) })")

        let a = try SongsterrAligner.align(tracks: tracks, beats: prepared.beats, stems: stems,
                                           soloSpans: [SongsterrAlignmentRoceTests.solo])
        var changes: [(Int, Int)] = []
        for blk in a.blocks where changes.last?.1 != blk.shift { changes.append((blk.firstBar, blk.shift)) }
        print("METRO alineación con pulsos preparados: desfase \(a.offsetBeats) fino \(Int((a.fineOffset * 1000).rounded())) ms "
              + "bloques \(changes) avisos \(a.structureWarnings.map { "c\($0.bar + 1) \($0.beats)p" })")

        let grid = try SongsterrBeatGrid.build(prepared: prepared, tracks: tracks, alignment: a, drums: drumsURL)
        print("METRO rejilla: \(grid.beats.count) pulsos, \(grid.downbeats.count) compases, tablatura \(grid.tabBeats) pulsos, "
              + "anclados a batería \(grid.anchoredBeats), intro realineado \(grid.introRealigned)")
        let irregular = grid.bars.enumerated().filter { $0.element.beatCount != 4 || $0.element.playedBar == nil }
        for (i, bar) in irregular {
            print("METRO compás \(i) tocado \(bar.playedBar.map { "\($0 + 1)" } ?? "de más") "
                  + String(format: "%.2f s", bar.start) + " \(bar.beatCount)/\(bar.beatUnit) tempo \(bar.writtenTempo)")
        }
        for bar in grid.bars where (66...74).contains(bar.playedBar ?? 70) {
            print("METRO medio compás tocado \(bar.playedBar.map { "\($0 + 1) (Songsterr \(tracks[0].bars[$0].sourceMeasure + 1))" } ?? "de más") "
                  + String(format: "%.2f s", bar.start) + " \(bar.beatCount) pulsos")
        }
        for bar in grid.bars.prefix(4) {
            print("METRO inicio compás tocado \(bar.playedBar.map { "\($0 + 1)" } ?? "-") " + String(format: "%.3f s", bar.start)
                  + " \(bar.beatCount) pulsos")
        }

        // Rejilla actual tal cual (como `BeatGrid`: downbeats sobre pulsos).
        let current = (beats: SongsterrBeatGrid.dedupe(raw.beats), downbeats: raw.downbeats.sorted())
        stats("actual", current.beats)
        stats("songsterr", grid.beats)

        // Las dos rejillas a JSON para medirlas con otro detector.
        // Ataque de batería que ve `SongsterrBeatGrid` junto a cada pulso corregido (sin la recta), o −1.
        let env = SongsterrBeatGrid.Drums(samples: try MonoAudio.load(drumsURL, sampleRate: SemitoneSpectrogram.sampleRate))
        let raw1 = grid.beats.map { SongsterrBeatGrid.onset(near: $0, period: 60 / written, drums: env) ?? -1 }
        let json: [String: Any] = ["actual": ["beats": current.beats, "downbeats": current.downbeats],
                                   "songsterr": ["beats": grid.beats, "downbeats": grid.downbeats,
                                                 "writtenTempo": grid.writtenTempo, "drumOnsets": raw1]]
        try fm.createDirectory(at: Self.p5b, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
            .write(to: Self.p5b.appendingPathComponent("roce_metro_grids.json"))

        // WAV: 60 primeros segundos + tramo alrededor del compás 73, mismos tramos en los dos.
        let mid = try XCTUnwrap(grid.bars.first { $0.playedBar == Self.middleBar }?.start)
        let spans = [0...Self.introSeconds, (mid - Self.middleBefore)...(mid + Self.middleAfter)]
        print("METRO tramos de escucha \(spans.map { String(format: "%.1f–%.1f s", $0.lowerBound, $0.upperBound) })")
        let song = Self.project.appendingPathComponent("audio/song.wav")
        try ClickMix.write(song: song, beats: current.beats, downbeats: current.downbeats, spans: spans,
                           to: Self.p5b.appendingPathComponent("CHECK_roce_metro_actual.wav"))
        try ClickMix.write(song: song, beats: grid.beats, downbeats: grid.downbeats, spans: spans,
                           to: Self.p5b.appendingPathComponent("CHECK_roce_metro_songsterr.wav"))

        XCTAssertEqual(written, 172)
        XCTAssertEqual(prepared.fold, .same)
        XCTAssertTrue(grid.downbeats.allSatisfy { d in grid.beats.contains(d) })
        XCTAssertEqual(grid.beats, grid.beats.sorted())
    }

    /// Intervalos entre pulsos y salto de un intervalo al siguiente (el escalón de 20 ms del modelo).
    func stats(_ name: String, _ beats: [Double]) {
        let ibi = zip(beats.dropFirst(), beats).map { $0 - $1 }
        let jump = zip(ibi.dropFirst(), ibi).map { abs($0 - $1) }.sorted()
        let sorted = ibi.sorted()
        print("METRO \(name): intervalo mediana \(String(format: "%.1f", 1000 * sorted[sorted.count / 2])) ms "
              + "(\(String(format: "%.2f", 60 / sorted[sorted.count / 2])) BPM), |salto| mediana "
              + "\(String(format: "%.1f", 1000 * jump[jump.count / 2])) ms p90 \(String(format: "%.1f", 1000 * jump[jump.count * 9 / 10])) ms")
    }
}

/// Mezcla estéreo del tema con un clic (acento en el 1) en los tramos pedidos, separados por 1 s de silencio.
enum ClickMix {
    static let accentHz = 1760.0, beatHz = 1175.0
    static let clickLength = 0.03
    static let songGain: Float = 0.6
    static let accentGain: Float = 0.55, beatGain: Float = 0.35
    static let gap = 1.0

    static func write(song: URL, beats: [Double], downbeats: [Double], spans: [ClosedRange<Double>], to url: URL) throws {
        let file = try NativeAudioFile.read(song)
        let sr = file.sampleRate
        let channels = file.channelCount
        let accents = Set(downbeats)
        var out: [[Float]] = Array(repeating: [], count: channels)
        for (s, span) in spans.enumerated() {
            if s > 0 { for c in 0..<channels { out[c] += [Float](repeating: 0, count: Int(gap * sr)) } }
            let start = min(file.frameCount, Int(max(0, span.lowerBound) * sr))
            let n = max(0, Int(min(Double(file.frameCount - start), (span.upperBound - span.lowerBound) * sr)))
            var seg = (0..<channels).map { c in file.channels[c][start..<(start + n)].map { $0 * songGain } }
            for t in beats where t >= span.lowerBound && t < span.upperBound {
                let accent = accents.contains(t)
                let hz = accent ? accentHz : beatHz, gain = accent ? accentGain : beatGain
                let i0 = Int(((t - span.lowerBound) * sr).rounded())
                for k in 0..<Int(clickLength * sr) where i0 + k < n {
                    let x = Double(k) / sr
                    let v = gain * Float(sin(2 * .pi * hz * x) * exp(-x / 0.006))
                    for c in 0..<channels { seg[c][i0 + k] += v }
                }
            }
            for c in 0..<channels { out[c] += seg[c] }
        }
        try? FileManager.default.removeItem(at: url)
        try NativeAudioFile.write(url, channels: out.map { $0.map { max(-1, min(1, $0)) } }, sampleRate: sr, format: .int16)
    }
}
