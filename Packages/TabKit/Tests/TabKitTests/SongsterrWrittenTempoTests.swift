import Foundation
import XCTest
@testable import TabKit

/// Tempo escrito de la tablatura de Songsterr (decisión de Jorge, 17/11/2026): el de Songsterr por tramos, salvo que
/// se aleje más de ±15 % del medido en el tramo; los compases sin compás de Songsterr siguen al anterior.
final class SongsterrWrittenTempoTests: XCTestCase {
    /// 48 pulsos a 0,35 s (171,43 BPM) desde 0,35 s, compases de 4 desde el pulso 0.
    static func score() throws -> (TabScore, [Double]) {
        let beats = (1...48).map { Double($0) * 0.35 }
        let downbeats = stride(from: 0, to: 48, by: 4).map { beats[$0] }
        return (try TabScore(beatTimes: BeatTimes(beats: beats, downbeats: downbeats, beatsPerBar: 4), duration: 17), downbeats)
    }

    static func bars(_ tempos: [Double]) -> [SongsterrBar] {
        tempos.enumerated().map { j, t in
            SongsterrBar(sourceMeasure: j, start: j * 4 * SongsterrTrack.ticksPerQuarter, beatCount: 4, beatUnit: 4,
                         tempo: t, marker: nil)
        }
    }

    func testWrittenTempoByStretchWithTolerance() throws {
        let (score, downbeats) = try Self.score()
        // Compases 0–5 a 172 (cociente 1,003), 6–8 a 130 (0,758: fuera) y 9–11 a 150 (0,875: dentro de ±15 %).
        let tempos: [Double] = [172, 172, 172, 172, 172, 172, 130, 130, 130, 150, 150, 150]
        // El downbeat del compás 3 es de pulsos de más (−1): sin compás de Songsterr, sigue al anterior.
        var map = Array(0..<12)
        map[3] = -1
        let out = SongsterrScorePlacement.writtenTempos(score, downbeats: downbeats, downbeatBars: map, refBars: Self.bars(tempos))
        let first = try XCTUnwrap(out.firstIndex { abs($0.start - downbeats[0]) < 1e-9 })
        let got = out[first..<(first + 12)].map(\.tempo)
        print("SINT tempos escritos \(got)")
        XCTAssertEqual(got, [172, 172, 172, 172, 172, 172, 171, 171, 171, 150, 150, 150])
        // Antes del primer compás de Songsterr, el primer tramo; compases y pulsos, intactos.
        XCTAssertTrue(out[..<first].allSatisfy { $0.tempo == 172 })
        XCTAssertEqual(out.map(\.beatCount), score.bars.map(\.beatCount))
        XCTAssertEqual(out.map(\.start), score.bars.map(\.start))
        // Borde de la tolerancia: 145 (cociente 0,846) ya no vale.
        let edge = SongsterrScorePlacement.writtenTempos(score, downbeats: downbeats, downbeatBars: Array(0..<12),
                                                         refBars: Self.bars([Double](repeating: 145, count: 12)))
        XCTAssertTrue(edge.allSatisfy { $0.tempo == 171 }, "\(Set(edge.map(\.tempo)))")
    }

    /// En el alineador: 2 pulsos de más en la grabación antes del compás 8 dan un compás aparte de 2 pulsos (como el
    /// metrónomo), ningún compás de más de 4 y el tempo escrito de Songsterr (120) en todos.
    func testExtraBeatsMakeTheirOwnBar() throws {
        typealias S = SyntheticSong
        let bars = 16
        let gtr = S.track(name: "Gtr", kind: .guitar, bars: bars, seed: 61, pitches: 45...76)
        let beats = S.beats(count: 80)
        let line = BeatLine(beats)
        let truth = S.Truth(offset: 2, fine: 0, blockShifts: [0, 0, 2, 2])
        let a = try SongsterrAligner.align(tracks: [gtr], beats: BeatTimes(beats: beats, downbeats: []),
                                           audio: [.guitar: S.render(S.events(gtr, truth: truth, line: line), duration: beats.last! + 2)],
                                           soloSpans: [])
        XCTAssertEqual(a.structureWarnings.map(\.beats), [2])
        let inside = a.score.bars.filter { $0.start >= beats[2] - 1e-9 && $0.start < beats[2 + 64 + 2] - 1e-9 }
        XCTAssertEqual(inside.map(\.beatCount), [4, 4, 4, 4, 4, 4, 4, 4, 2, 4, 4, 4, 4, 4, 4, 4, 4])
        XCTAssertTrue(a.score.bars.allSatisfy { $0.tempo == 120 }, "\(Set(a.score.bars.map(\.tempo)))")
    }
}
