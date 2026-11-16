import XCTest
@testable import TabKit

/// Tempo escrito entero y sin deriva (mini-spec Fase 5, «Rejilla»): el tempo base de un tramo es el entero más
/// cercano al real; además de la regla del 2 % (contra el tempo real), cuando el inicio escrito de un compás se
/// separa del real más de `TabScore.maxWrittenDrift` (20 ms), ese compás lleva el entero que más reduce la deriva a
/// su final y el siguiente vuelve al tempo base entero.
final class TabTempoDriftTests: XCTestCase {
    /// Inicio escrito de cada compás (y el final) sumando duraciones al tempo escrito desde el inicio del primero.
    static func writtenStarts(_ score: TabScore) -> [Double] {
        var out = [score.bars[0].start]
        for bar in score.bars { out.append(out.last! + 60 * Double(bar.beatCount) / bar.tempo) }
        return out
    }

    /// Inicio real de cada compás y el final de la rejilla.
    static func actualStarts(_ score: TabScore) -> [Double] { score.bars.map(\.start) + [score.endTime] }

    /// Lo que un entero no puede absorber en un compás de `beats` pulsos escrito a `tempo`: el ideal cae entre dos
    /// enteros consecutivos y el mejor deja como mucho media diferencia de duración entre ellos; con el entero
    /// elegido T, la mayor de las dos diferencias posibles es 60·beats/(T(T−1)), y la mitad, 30·beats/(T(T−1)).
    static func integerResidual(beats: Int, tempo: Double) -> Double {
        30 * Double(beats) / (tempo * max(1, tempo - 1))
    }

    /// Compases de 4/4 desde 0,4 s con tempo `bpm · factor^k` en el compás k, pulsos equiespaciados y jitter opcional.
    static func grid(bars: Int, factor: Double, bpm: Double = 120, anacrusis: Int = 0, jitter: Double = 0,
                     seed: UInt64 = 3) -> BeatTimes {
        var rng = TabGridTests.LCG(state: seed)
        var beats: [Double] = []
        var t = 0.4
        for _ in 0..<anacrusis {
            beats.append(t + (rng.next() - 0.5) * 2 * jitter)
            t += 60 / bpm
        }
        for k in 0..<bars {
            let period = 60 / (bpm * pow(factor, Double(k)))
            for _ in 0..<4 {
                beats.append(t + (rng.next() - 0.5) * 2 * jitter)
                t += period
            }
        }
        beats.append(t)
        let downbeats = stride(from: anacrusis, to: anacrusis + bars * 4, by: 4).map { beats[$0] }
        return BeatTimes(beats: beats, downbeats: downbeats, beatsPerBar: 4)
    }

    struct DriftReport {
        var worst: Double
        var changes: Int
        /// Compases que empiezan con |deriva| > 20 ms (llevan el entero de corrección).
        var corrections: Int
    }

    /// Comprueba, compás a compás, que todos los tempos son enteros y que la deriva al final de cada compás queda
    /// acotada: si el compás corrige (deriva al inicio > 20 ms), por lo que un entero no puede absorber
    /// (`integerResidual`); si no, por 20 ms más lo que deriva ese compás a su tempo escrito.
    @discardableResult
    func assertBoundedDrift(_ score: TabScore, label: String, file: StaticString = #filePath, line: UInt = #line)
        -> DriftReport {
        let written = Self.writtenStarts(score), actual = Self.actualStarts(score)
        var worst = 0.0, worstAllowed = 0.0, corrections = 0
        for (i, bar) in score.bars.enumerated() {
            XCTAssertEqual(bar.tempo, bar.tempo.rounded(), "\(label): tempo no entero en el compás \(i)",
                           file: file, line: line)
            let startDrift = written[i] - actual[i]
            let endDrift = written[i + 1] - actual[i + 1]
            let allowed: Double
            if abs(startDrift) > TabScore.maxWrittenDrift + 1e-9 {
                corrections += 1
                allowed = Self.integerResidual(beats: bar.beatCount, tempo: bar.tempo) + 1e-9
            } else {
                allowed = TabScore.maxWrittenDrift + abs(endDrift - startDrift) + 1e-9
            }
            XCTAssertLessThanOrEqual(abs(endDrift), allowed, "\(label): final del compás \(i)", file: file, line: line)
            if abs(endDrift) > worst { worst = abs(endDrift); worstAllowed = allowed }
        }
        let changes = zip(score.bars, score.bars.dropFirst()).filter { $0.tempo != $1.tempo }.count
        print(String(format: "TabTempoDrift %@: deriva máx %.1f ms (cota en ese compás %.1f ms), %d cambios de tempo "
                     + "(%d correcciones) en %d compases", label, worst * 1000, worstAllowed * 1000, changes,
                     corrections, score.bars.count))
        return DriftReport(worst: worst, changes: changes, corrections: corrections)
    }

    /// Accelerando de 0,5 % por compás durante 64 compases (120 → 164 BPM).
    func testSlowAccelerandoKeepsWrittenTimeOnTrack() throws {
        let beats = Self.grid(bars: 64, factor: 1.005)
        let score = try TabScore(beatTimes: beats, duration: beats.beats.last! - 0.01)
        let report = assertBoundedDrift(score, label: "accelerando 0,5 %")
        // La deriva solo se mira al inicio del compás: uno que empiece con ≤ 20 ms suma la suya entera. Su duración
        // se aleja de la escrita como mucho 3 compases × 0,5 % = 1,5 % (el tempo real vigente se fija en una
        // corrección o al saltar la regla del 2 %, que salta al 4.º: 1,005⁴ > 1,02) más ≤ 0,5 BPM de redondeo
        // (≤ 0,5/120 = 0,42 %), sobre un compás de ≤ 2 s: ≤ 38,3 ms. Cota: 20 ms + 38,3 ms = 58,3 ms.
        XCTAssertLessThan(report.worst, TabScore.maxWrittenDrift + 2.0 * (3 * 0.005 + 0.5 / 120))
        XCTAssertGreaterThan(report.changes, 0)

        // Con la regla anterior (solo 2 %, sin redondear) la deriva crecía: referencia para el informe.
        var writtenTempo = 60 * Double(score.bars[0].beatCount) / (score.bars[1].start - score.bars[0].start)
        var ws = score.bars[0].start, oldWorst = 0.0
        let actual = Self.actualStarts(score)
        for (i, bar) in score.bars.enumerated() {
            let seconds = actual[i + 1] - actual[i]
            let expected = 60 * Double(bar.beatCount) / writtenTempo
            if i > 0, abs(seconds - expected) / expected > TabScore.tempoChangeThreshold {
                writtenTempo = 60 * Double(bar.beatCount) / seconds
            }
            ws += 60 * Double(bar.beatCount) / writtenTempo
            oldWorst = max(oldWorst, abs(ws - actual[i + 1]))
        }
        print(String(format: "TabTempoDrift accelerando con solo la regla del 2 %%: deriva máx %.1f ms", oldWorst * 1000))
        XCTAssertGreaterThan(oldWorst, report.worst)
    }

    func testRitardandoWithJitterStaysBounded() throws {
        let beats = Self.grid(bars: 64, factor: 0.996, jitter: 0.005, seed: 9)
        let score = try TabScore(beatTimes: beats, duration: beats.beats.last! - 0.01)
        let report = assertBoundedDrift(score, label: "ritardando 0,4 % ±5 ms")
        // Un compás sin corregir: ≤ 2 % de regla + ≤ 0,5 BPM de redondeo (a ≥ 92 BPM, ≤ 0,55 %) sobre ≤ 2,6 s, más
        // ±10 ms de jitter entre sus dos downbeats; la deriva al inicio no pasa de 20 ms sin corregirse.
        let barSeconds = 240.0 / (120 * pow(0.996, 63))
        XCTAssertLessThan(report.worst, TabScore.maxWrittenDrift + barSeconds * (0.02 + 0.5 / 92) + 0.010)
    }

    /// 117,3 BPM (no entero) con 2 pulsos de anacrusa y 64 compases: tempo base 117 y correcciones periódicas.
    func testConstantNonIntegerTempoCorrectsPeriodically() throws {
        let real = 117.3, base = 117.0, bars = 64
        let score = try TabScore(beatTimes: Self.grid(bars: bars, factor: 1, bpm: real, anacrusis: 2),
                                 duration: 0.4 + Double(2 + bars * 4) * 60 / real)
        // Anacrusa de 2 + 64 compases + el compás que abre el pulso final (completado hasta 4).
        XCTAssertEqual(score.bars.count, bars + 2)
        XCTAssertEqual(score.bars[0].tempo, base)
        XCTAssertEqual(score.bars[1].tempo, base)
        let report = assertBoundedDrift(score, label: "117,3 BPM constante")

        // Deriva por compás de 4/4 al tempo base: d = 240/117 − 240/117,3 = 5,25 ms. Sin corregir, la deriva al
        // inicio de un compás no pasa de 20 ms, así que al final no pasa de 20 ms + d = 25,25 ms.
        let d = 240 / base - 240 / real
        XCTAssertLessThanOrEqual(report.worst, TabScore.maxWrittenDrift + d + 1e-9)

        // Las correcciones van a 118 o 119; lo que queda tras una es |r| ≤ h = 30·4/(117·116) = 8,84 ms (cota
        // conservadora con T = 117). Entre dos correcciones hay al menos k compases sin corregir con −h + k·d > 20 ms:
        // k ≥ ⌊(20 − h)/d⌋ + 1 = 3, así que una corrección cada ≥ 4 compases: N ≤ ⌈66/4⌉ = 17. Cada una absorbe a lo
        // sumo (20 + d) + h = 34,1 ms, y la deriva total sin corregir (65,5·d = 344 ms) menos lo que puede quedar al
        // final (≤ 20 + d) hay que absorberlo: N ≥ ⌈(344 − 25,25)/34,1⌉ = 10.
        let h = Self.integerResidual(beats: 4, tempo: base)
        let total = score.bars.map { Double($0.beatCount) * (60 / base - 60 / real) }.reduce(0, +)
        let minGap = Int(((TabScore.maxWrittenDrift - h) / d).rounded(.down)) + 2
        let maxN = (score.bars.count + minGap - 1) / minGap
        let minN = Int(((total - (TabScore.maxWrittenDrift + d)) / (TabScore.maxWrittenDrift + d + h)).rounded(.up))
        XCTAssertEqual(minGap, 4)
        XCTAssertEqual(minN, 10)
        XCTAssertEqual(maxN, 17)
        XCTAssertGreaterThanOrEqual(report.corrections, minN)
        XCTAssertLessThanOrEqual(report.corrections, maxN)
        // Cada corrección entra y sale del tempo base (dos cambios), salvo si cae en el último compás.
        XCTAssertTrue([2 * report.corrections, 2 * report.corrections - 1].contains(report.changes))
        let correctionTempos = Set(score.bars.map(\.tempo)).subtracting([base])
        XCTAssertTrue(correctionTempos.isSubset(of: [118, 119]), "\(correctionTempos)")
    }

    /// Tempo real entero constante (120 BPM, anacrusa de 2 y 64 compases): cero cambios y deriva nula.
    func testConstantIntegerTempoEmitsNoChange() throws {
        let score = try TabScore(beatTimes: Self.grid(bars: 64, factor: 1, anacrusis: 2), duration: 0.4 + 258 * 0.5)
        XCTAssertEqual(Set(score.bars.map(\.tempo)), [120])
        let report = assertBoundedDrift(score, label: "120 BPM constante")
        XCTAssertEqual(report.changes, 0)
        XCTAssertLessThan(report.worst, 1e-6)
    }

    /// 120 BPM con ±5 ms de jitter por pulso: un compás suelto llega a ±0,6 BPM (la anacrusa de 2, a ±1,2) y su
    /// redondeo podría dar 119 o 121, pero la mediana de 4 compases queda en 120. Con base 120 la deriva al inicio
    /// de cada compás es su error de downbeat (≤ 5 ms) menos el del primer compás, que empieza en un pulso añadido
    /// hacia atrás con el primer periodo (error 2·j₀ − j₁, ≤ 15 ms): ≤ 20 ms, sin pasar de la cota de corrección.
    /// Cada compás se aleja ≤ 10 ms/2 s = 0,5 %, así que tampoco salta la regla del 2 %. Cero cambios (el final
    /// de la rejilla se extrapola con el último periodo y no cuenta aquí).
    func testConstantIntegerTempoWithJitterEmitsNoChange() throws {
        let score = try TabScore(beatTimes: Self.grid(bars: 64, factor: 1, anacrusis: 2, jitter: 0.005, seed: 5),
                                 duration: 0.4 + 258 * 0.5)
        XCTAssertEqual(Set(score.bars.map(\.tempo)), [120])
        let report = assertBoundedDrift(score, label: "120 BPM ±5 ms")
        XCTAssertEqual(report.changes, 0)
        let written = Self.writtenStarts(score), actual = Self.actualStarts(score)
        let worst = score.bars.indices.map { abs(written[$0] - actual[$0]) }.max() ?? 0
        print(String(format: "TabTempoDrift 120 BPM ±5 ms: deriva máx en inicios de compás %.1f ms", worst * 1000))
        XCTAssertLessThanOrEqual(worst, TabScore.maxWrittenDrift + 1e-9)
    }

    /// Todos los tempos de `TabScore` son enteros, en todas las rejillas de prueba.
    func testAllWrittenTemposAreIntegers() throws {
        let grids: [(String, BeatTimes)] = [
            ("rampa 100→140 ±5 ms", TabGridTests.rampGrid()),
            ("accelerando 0,5 %", Self.grid(bars: 64, factor: 1.005)),
            ("ritardando 0,4 % ±5 ms", Self.grid(bars: 64, factor: 0.996, jitter: 0.005, seed: 9)),
            ("117,3 BPM", Self.grid(bars: 64, factor: 1, bpm: 117.3, anacrusis: 2)),
            ("83,7 BPM ±8 ms", Self.grid(bars: 40, factor: 1, bpm: 83.7, anacrusis: 3, jitter: 0.008, seed: 11)),
        ]
        for (label, grid) in grids {
            let score = try TabScore(beatTimes: grid, duration: grid.beats.last! + 0.2)
            for (i, bar) in score.bars.enumerated() {
                XCTAssertEqual(bar.tempo, bar.tempo.rounded(), "\(label): compás \(i) a \(bar.tempo)")
            }
        }
    }

    func testCorrectionReducesDriftWithBestInteger() throws {
        // 120 BPM; el compás 1 un 1,5 % más largo (no llega al 2 %): al inicio del 2 la deriva es −30 ms. El ideal
        // sería 240/2,03 = 118,23 BPM; 118 deja +3,9 ms y 119 deja −13,2 ms: lleva 118.
        let barSeconds = [2.0, 2.03, 2.0, 2.0, 2.0]
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
        // 5 compases + el que abre el pulso final (completado hasta 4).
        XCTAssertEqual(tempos, [120, 120, 118, 120, 120, 120])
        let written = Self.writtenStarts(score), actual = Self.actualStarts(score)
        XCTAssertEqual(written[2] - actual[2], -0.030, accuracy: 1e-9)
        XCTAssertEqual(written[3] - actual[3], 240.0 / 118 - 2.03, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(abs(written[3] - actual[3]), Self.integerResidual(beats: 4, tempo: 118))
        // El compás siguiente vuelve al tempo base y ya no hay más cambios: la deriva se queda en +3,9 ms.
        for i in 3..<written.count { XCTAssertEqual(written[i] - actual[i], 240.0 / 118 - 2.03, accuracy: 1e-9) }
        assertBoundedDrift(score, label: "corrección de −30 ms")
    }
}
