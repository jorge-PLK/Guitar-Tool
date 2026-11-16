import XCTest
@testable import TabKit

/// Rejilla de `TabScore` desde pulsos y downbeats (mini-spec Fase 5, «Rejilla» y «Pruebas»: los tiempos de compás
/// reproducen los del `BeatGrid` con error < 1 ms).
final class TabGridTests: XCTestCase {
    /// Tolerancia de la spec para tiempos de compás y pulso.
    static let maxTimeError = 0.001

    /// Generador determinista (LCG) para el jitter.
    struct LCG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    /// 2 pulsos de anacrusa + 32 compases de 4/4; tempo de 100 a 140 BPM en rampa, jitter ±5 ms; primer pulso en 1,3 s.
    static func rampGrid() -> BeatTimes {
        var rng = LCG(state: 7)
        var beats: [Double] = []
        var t = 1.3
        let count = 2 + 32 * 4
        for i in 0..<count {
            beats.append(t + (rng.next() - 0.5) * 0.010)
            let bpm = 100 + 40 * Double(i) / Double(count - 1)
            t += 60 / bpm
        }
        let downbeats = stride(from: 2, to: count, by: 4).map { beats[$0] }
        return BeatTimes(beats: beats, downbeats: downbeats, beatsPerBar: 4)
    }

    func testBarStartsReproduceDownbeatsAndBeatTimes() throws {
        let grid = Self.rampGrid()
        let score = try TabScore(beatTimes: grid, duration: grid.beats.last! + 0.2)

        // Cada downbeat es el inicio de un compás, en orden y sin compases intermedios.
        let barStarts = score.bars.map(\.start)
        guard let first = barStarts.firstIndex(where: { abs($0 - grid.downbeats[0]) < 1e-9 }) else {
            return XCTFail("el primer downbeat no abre compás")
        }
        var worstBar = 0.0
        for (j, d) in grid.downbeats.enumerated() {
            worstBar = max(worstBar, abs(barStarts[first + j] - d))
            let viaPosition = try XCTUnwrap(score.time(at: ScorePosition(bar: first + j, beatInBar: 0, beatFraction: 0)))
            worstBar = max(worstBar, abs(viaPosition - d))
        }
        XCTAssertLessThan(worstBar, Self.maxTimeError)

        // Cada pulso del BeatGrid es un pulso de la rejilla con el mismo tiempo (vía GridPoint y vía ScorePosition).
        let offset = try XCTUnwrap(score.beats.firstIndex { abs($0.time - grid.beats[0]) < 1e-9 })
        var worstBeat = 0.0
        for (i, t) in grid.beats.enumerated() {
            let b = score.beats[offset + i]
            worstBeat = max(worstBeat, abs(score.time(of: GridPoint(beat: offset + i, tick: 0)) - t))
            let p = ScorePosition(bar: b.bar, beatInBar: b.indexInBar, beatFraction: 0)
            worstBeat = max(worstBeat, abs(try XCTUnwrap(score.time(at: p)) - t))
        }
        XCTAssertLessThan(worstBeat, Self.maxTimeError)
        print("TabGrid: error máximo compás \(worstBar * 1000) ms, pulso \(worstBeat * 1000) ms")
    }

    func testTimeToPositionRoundTrip() throws {
        let grid = Self.rampGrid()
        let score = try TabScore(beatTimes: grid, duration: grid.beats.last! + 1)
        var worst = 0.0
        for t in stride(from: score.beats[0].time, to: score.endTime, by: 0.0371) {
            let p = score.position(at: t)
            worst = max(worst, abs(try XCTUnwrap(score.time(at: p)) - t))
        }
        XCTAssertLessThan(worst, 1e-9)
    }

    func testExtensionBeforeFirstAndAfterLastBeat() throws {
        // 120 BPM, primer pulso en 1,3 s, downbeat en el pulso 2: 2 pulsos de anacrusa.
        let beats = (0..<18).map { 1.3 + Double($0) * 0.5 }
        let grid = BeatTimes(beats: beats, downbeats: [beats[2], beats[6], beats[10], beats[14]], beatsPerBar: 4)
        let score = try TabScore(beatTimes: grid, duration: 12.0)

        // Hacia atrás con el periodo local hasta dejar < 1/8 de periodo antes de 0: 0,8 · 0,3 · −0,2.
        XCTAssertEqual(score.beats[0].time, -0.2, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(score.beats[0].time, 0.5 / 8)
        // 3 pulsos añadidos + 2 de anacrusa = 5 antes del primer downbeat: anacrusa de 1 y un compás de 4.
        XCTAssertEqual(score.bars[0].beatCount, 1)
        XCTAssertEqual(score.bars[1].beatCount, 4)
        XCTAssertEqual(score.bars[2].start, beats[2])
        // Hacia delante hasta cubrir 12 s y completar el último compás.
        XCTAssertGreaterThanOrEqual(score.endTime, 12.0 - 0.5 / 8)
        XCTAssertEqual(score.bars.last!.beatCount, 4)
        XCTAssertEqual(score.beats.count, score.bars.map(\.beatCount).reduce(0, +))
        for (b, beat) in score.beats.enumerated() {
            XCTAssertEqual(score.bars[beat.bar].firstBeat + beat.indexInBar, b)
        }
        // 120 BPM constantes: un solo tempo escrito.
        XCTAssertEqual(Set(score.bars.map { ($0.tempo * 1000).rounded() }), [120_000])
    }

    func testTempoChangesOnlyBeyondTwoPercent() throws {
        // Compases de 2 s (120 BPM); el 3.º un 1 % más largo (sin cambio; deja −20 ms de deriva, justo en el límite),
        // del 5.º al 8.º un 3,4 % más largos, a 116 BPM exactos (cambio, sin deriva añadida por redondeo; 4 compases
        // para que la mediana del tramo, `baseTempoBars`, sea 116), y vuelta a 120.
        let slow = 240.0 / 116
        let barSeconds = [2.0, 2.0, 2.02, 2.0, slow, slow, slow, slow, 2.0, 2.0, 2.0]
        var beats: [Double] = []
        var downbeats: [Double] = []
        var t = 0.0
        for s in barSeconds {
            downbeats.append(t)
            for k in 0..<4 { beats.append(t + Double(k) * s / 4) }
            t += s
        }
        let score = try TabScore(beatTimes: BeatTimes(beats: beats, downbeats: downbeats), duration: t - 0.1)
        let tempos = score.bars.map(\.tempo)
        XCTAssertEqual(tempos[0], 120, accuracy: 1e-9)
        XCTAssertEqual(tempos[1], 120, accuracy: 1e-9)
        XCTAssertEqual(tempos[2], 120, accuracy: 1e-9)          // 1 %: se queda
        XCTAssertEqual(tempos[3], 120, accuracy: 1e-9)
        XCTAssertEqual(Array(tempos[4...7]), [116, 116, 116, 116])  // 3,4 %: cambia
        XCTAssertEqual(Array(tempos[8...10]), [120, 120, 120])      // vuelve: −3,3 %
    }

    func testTwoPercentRuleComparesWithRealTempoNotRounded() throws {
        // Tempo real 117,6 (se escribe 118). El compás 2 a 115,3 BPM se aleja un 1,96 % del real vigente (no cambia
        // de tempo base) aunque se aleja un 2,3 % del 118 escrito: lleva 118. Al inicio del 3 la deriva es −61,5 ms
        // (2 × −6,9 ms de redondeo y −47,6 ms del compás lento), que corrige el compás 3 con un entero; el 4 vuelve
        // a 118.
        let barSeconds = [240 / 117.6, 240 / 117.6, 240 / 115.3, 240 / 117.6, 240 / 117.6]
        var beats: [Double] = [], downbeats: [Double] = []
        var t = 0.0
        for s in barSeconds {
            downbeats.append(t)
            for k in 0..<4 { beats.append(t + Double(k) * s / 4) }
            t += s
        }
        beats.append(t)
        let score = try TabScore(beatTimes: BeatTimes(beats: beats, downbeats: downbeats), duration: t - 0.1)
        let tempos = score.bars.map(\.tempo)
        XCTAssertEqual(Array(tempos[0...2]), [118, 118, 118])
        XCTAssertNotEqual(tempos[3], 118)
        XCTAssertEqual(tempos[4], 118)
    }

    func testBeatsPerBarFromDownbeatsAndErrors() throws {
        let beats = (0..<13).map { Double($0) * 0.4 }
        let score = try TabScore(beatTimes: BeatTimes(beats: beats, downbeats: [0, 1.2, 2.4, 3.6]), duration: 5)
        XCTAssertEqual(score.bars.first!.beatCount, 3)
        XCTAssertThrowsError(try TabScore(beatTimes: BeatTimes(beats: [1], downbeats: []), duration: 5)) {
            XCTAssertEqual($0 as? TabScoreError, .notEnoughBeats)
        }
    }
}
