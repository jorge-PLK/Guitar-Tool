import Foundation
import XCTest
@testable import TabKit

/// Rejilla del metrónomo con Songsterr sobre temas sintéticos: golpes de batería con ataque de 1 ms en tiempos
/// conocidos y un «modelo de pulso» con los fallos de Beat This! (tramas de 20 ms, retraso, pulsos perdidos,
/// doble o mitad de tempo, downbeats mal puestos).
final class SongsterrBeatGridTests: XCTestCase {
    static let sr = SemitoneSpectrogram.sampleRate
    static let tpq = SongsterrTrack.ticksPerQuarter
    /// Trama de Beat This! (50 fps).
    static let modelFrame = 0.02

    // Tolerancias.
    /// Pulsos colocados con los ataques de batería frente a los tiempos reales (la meta del metrónomo: 1 ms).
    static let anchoredTolerance = 0.001
    /// En los tests de estructura (compás de cuenta sin golpes, pulsos de más o de menos) la recta cruza tramos sin
    /// ataque o con el compás cortado: 2 ms.
    static let structureTolerance = 0.002
    /// Con deriva de tempo la recta local tiene un sesgo de curvatura (≈ 6,7·c con c la mitad de la variación del
    /// periodo por pulso): 120 → 124 BPM en 96 pulsos da ≈ 0,6 ms.
    static let driftTolerance = 0.0015
    /// Sin batería, la recta sobre pulsos redondeados a 20 ms (error uniforme de ±10 ms).
    static let modelOnlyTolerance = 0.006

    // MARK: señales

    /// Golpe de batería: ruido con ataque lineal de 1 ms y caída de 40 ms más un golpe grave de 70 Hz; contratiempos
    /// (charles) a un tercio de amplitud.
    static func drums(hits: [Double], offbeats: [Double] = [], length: Double) -> [Float] {
        var x = [Float](repeating: 0, count: Int(length * sr))
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func noise() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int64(bitPattern: state >> 1) % 2001 - 1000) / 1000
        }
        func add(_ t: Double, gain: Float) {
            let i0 = Int((t * sr).rounded())
            for k in 0..<Int(0.15 * sr) where i0 + k >= 0 && i0 + k < x.count {
                let s = Double(k) / sr
                let attack = Float(min(1, s / 0.001))
                let env = attack * Float(exp(-s / 0.04))
                x[i0 + k] += gain * env * (0.6 * noise() + 0.8 * Float(sin(2 * .pi * 70 * s)))
            }
        }
        for t in hits { add(t, gain: 0.8) }
        for t in offbeats { add(t, gain: 0.27) }
        return x
    }

    static func envelope(_ x: [Float]) -> SongsterrBeatGrid.Drums { SongsterrBeatGrid.Drums(samples: x, sampleRate: sr) }

    /// Compases de Songsterr seguidos con el compás y tempo dados.
    static func bars(_ signatures: [(Int, Int)], tempo: Double) -> [SongsterrBar] {
        var start = 0
        return signatures.enumerated().map { j, s in
            let bar = SongsterrBar(sourceMeasure: j, start: start, beatCount: s.0, beatUnit: s.1, tempo: tempo, marker: nil)
            start += bar.length
            return bar
        }
    }

    /// Tiempos con tempo que pasa linealmente de `from` a `to` BPM a lo largo de `count` pulsos.
    static func drifting(count: Int, start: Double, from: Double, to: Double) -> [Double] {
        var t = start, out: [Double] = []
        for k in 0..<count {
            out.append(t)
            t += 60 / (from + (to - from) * Double(k) / Double(max(1, count - 1)))
        }
        return out
    }

    /// Lo que daría el modelo: `late` s tarde y redondeado a tramas de 20 ms.
    static func model(_ truth: [Double], late: Double) -> [Double] {
        truth.map { (($0 + late) / modelFrame).rounded() * modelFrame }
    }

    static func maxError(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).map { abs($0 - $1) }.max() ?? .infinity
    }

    // MARK: 1. doble y mitad de tempo

    func testHalfTempoModelIsDoubled() {
        let truth = (0..<64).map { 1.0 + Double($0) * 60 / 172 }
        let half = stride(from: 0, to: truth.count, by: 2).map { truth[$0] }
        let p = SongsterrBeatGrid.prepare(BeatTimes(beats: half, downbeats: stride(from: 0, to: half.count, by: 2).map { half[$0] }),
                                          writtenTempo: 172)
        XCTAssertEqual(p.fold, .doubled)
        XCTAssertEqual(p.detectedTempo, 86, accuracy: 0.01)
        XCTAssertEqual(p.beats.beats.count, truth.count - 1)
        XCTAssertLessThan(Self.maxError(p.beats.beats, truth), 1e-9)
    }

    func testDoubleTempoModelIsHalvedOnDownbeatParity() {
        // Corcheas que empiezan media negra antes de la primera negra: las negras son los índices impares.
        let truth = (0..<48).map { 2.0 + Double($0) * 60 / 120 }
        let eighths = (0..<97).map { 2.0 - 0.25 + Double($0) * 0.25 }
        let downbeats = stride(from: 0, to: truth.count, by: 4).map { truth[$0] }
        let p = SongsterrBeatGrid.prepare(BeatTimes(beats: eighths, downbeats: downbeats), writtenTempo: 120)
        XCTAssertEqual(p.fold, .halved)
        XCTAssertEqual(p.beats.beats.count, truth.count)
        XCTAssertLessThan(Self.maxError(p.beats.beats, truth), 1e-9)
        XCTAssertEqual(p.beats.downbeats, downbeats)
    }

    func testSameTempoAndMissingBeatFilled() {
        let truth = (0..<40).map { 1.0 + Double($0) * 0.5 }
        var model = truth
        model.remove(at: 17)
        let p = SongsterrBeatGrid.prepare(BeatTimes(beats: model, downbeats: []), writtenTempo: 120)
        XCTAssertEqual(p.fold, .same)
        XCTAssertEqual(p.insertedBeats, 1)
        XCTAssertLessThan(Self.maxError(p.beats.beats, truth), 1e-9)
        // Un hueco de 3 pulsos (calderón, corte) no se rellena.
        var gap = truth
        gap.removeSubrange(20...22)
        XCTAssertEqual(SongsterrBeatGrid.prepare(BeatTimes(beats: gap, downbeats: []), writtenTempo: 120).insertedBeats, 0)
    }

    /// Tornado Of Souls: el modelo marca negras a 200 BPM salvo un estribillo entero a mitad de tempo (cada 2 pulsos)
    /// y un tramo a corcheas. La mediana local de esos tramos también está doblada o partida; los arregla el periodo
    /// del tema. Los pulsos salen exactos (≤ 1e-9 s) y uno por negra.
    func testHalfAndDoubleTempoStretchesAreFolded() {
        let period = 0.3
        let truth = (0..<200).map { 1.0 + Double($0) * period }
        var model = Array(truth[0..<40])
        model += stride(from: 40, to: 80, by: 2).map { truth[$0] }               // estribillo a mitad de tempo
        model += Array(truth[80..<120])
        for k in 120..<150 { model += [truth[k], truth[k] + period / 2] }        // corcheas
        model += Array(truth[150...])
        let p = SongsterrBeatGrid.prepare(BeatTimes(beats: model, downbeats: []), writtenTempo: 196)
        XCTAssertEqual(p.fold, .same)
        XCTAssertEqual(p.beats.beats.count, truth.count)
        XCTAssertLessThan(Self.maxError(p.beats.beats, truth), 1e-9)
        // 20 pulsos de menos en el estribillo y 30 de más en las corcheas (en el borde se quita y se repone uno).
        XCTAssertEqual(p.insertedBeats - p.removedBeats, 20 - 30)
    }

    /// Un pulso movido a 0,4 del intervalo (0,4 + 1,6) o dos de más en un intervalo (0,3 + 0,3 + 0,4) entre pulsos
    /// regulares: el tramo dura un número entero de periodos y se reparte. Medio pulso de desfase que sigue (0,5 y
    /// luego regular) no se toca.
    func testIrregularStretchIsEvenedOut() {
        let period = 0.3
        let truth = (0..<60).map { 1.0 + Double($0) * period }
        var model = truth
        model[20] = truth[19] + 0.4 * period
        // Tramo a contratiempo: 1,5, siete regulares y 0,5 (Tornado Of Souls, 238–240 s).
        for k in 30...37 { model[k] = truth[k] + 0.5 * period }
        model.insert(contentsOf: [truth[40] + 0.3 * period, truth[40] + 0.6 * period], at: 41)
        let p = SongsterrBeatGrid.prepare(BeatTimes(beats: model, downbeats: []), writtenTempo: 200)
        XCTAssertEqual(p.beats.beats.count, truth.count)
        XCTAssertLessThan(Self.maxError(p.beats.beats, truth), 1e-9)

        // Desfase de medio pulso que se queda: 0,5 y después intervalos regulares desde la nueva fase.
        var shifted = Array(truth[0..<30])
        shifted += truth[29...].dropLast().map { $0 + 0.5 * period }
        let q = SongsterrBeatGrid.regularize(shifted)
        XCTAssertEqual(q.net, 0)
        XCTAssertEqual(q.beats, shifted)
    }

    // MARK: 2. fase y precisión con batería

    /// Modelo 15 ms tarde, en tramas de 20 ms, con un pulso perdido y downbeats cada 3 pulsos (mal): la rejilla cae
    /// sobre los ataques reales a ≤ 1 ms y sus compases son los de Songsterr.
    func testPhaseAndQuantizationFixedByDrums() {
        let truth = (0..<96).map { 1.0 + Double($0) * 60 / 126 }
        let off = truth.map { $0 + 30 / 126 }
        let env = Self.envelope(Self.drums(hits: truth, offbeats: off, length: truth.last! + 1))
        var model = Self.model(truth, late: 0.015)
        model.remove(at: 40)
        let wrongDownbeats = stride(from: 0, to: model.count, by: 3).map { model[$0] }
        let p = SongsterrBeatGrid.prepare(BeatTimes(beats: model, downbeats: wrongDownbeats), writtenTempo: 126)
        XCTAssertEqual(p.insertedBeats, 1)
        let g = SongsterrBeatGrid.build(prepared: p, refBars: Self.bars(Array(repeating: (4, 4), count: 24), tempo: 126),
                                        offset: 0, shifts: [], drums: env)
        let before = Self.maxError(p.beats.beats, truth)
        let after = Self.maxError(g.beats, truth)
        let signed = zip(g.beats, truth).map { 1000 * ($0 - $1) }
        let raw = truth.map { 1000 * ((SongsterrBeatGrid.onset(near: $0, period: 60 / 126, drums: env) ?? .nan) - $0) }
        print("PRECISIÓN fase: modelo máx \(String(format: "%.1f", before * 1000)) ms → rejilla máx "
              + "\(String(format: "%.2f", after * 1000)) ms; anclados \(g.anchoredBeats)/\(g.tabBeats); con signo "
              + "min \(String(format: "%.2f", signed.min()!)) máx \(String(format: "%.2f", signed.max()!)); ataque crudo "
              + "min \(String(format: "%.2f", raw.min()!)) máx \(String(format: "%.2f", raw.max()!)) primeros \(raw.prefix(8).map { String(format: "%.2f", $0) })")
        XCTAssertEqual(g.beats.count, truth.count)
        XCTAssertEqual(g.anchoredBeats, truth.count)
        XCTAssertGreaterThan(before, 0.020)
        XCTAssertLessThanOrEqual(after, Self.anchoredTolerance)
        XCTAssertEqual(g.downbeats, stride(from: 0, to: truth.count, by: 4).map { g.beats[$0] })
        XCTAssertEqual(g.bars.map(\.beatCount), Array(repeating: 4, count: 24))
        XCTAssertEqual(g.writtenTempo, 126)
    }

    /// Tempo que sube de 120 a 124 BPM sin clic: los pulsos siguen al audio, no a un BPM fijo.
    func testDriftFollowsAudio() {
        let truth = Self.drifting(count: 96, start: 1.5, from: 120, to: 124)
        let env = Self.envelope(Self.drums(hits: truth, length: truth.last! + 1))
        let p = SongsterrBeatGrid.prepare(BeatTimes(beats: Self.model(truth, late: -0.008), downbeats: []), writtenTempo: 122)
        let g = SongsterrBeatGrid.build(prepared: p, refBars: Self.bars(Array(repeating: (4, 4), count: 24), tempo: 122),
                                        offset: 0, shifts: [], drums: env)
        let fixed = (0..<truth.count).map { truth[0] + Double($0) * 60 / 122 }
        let after = Self.maxError(g.beats, truth)
        print("PRECISIÓN deriva: BPM fijo máx \(String(format: "%.1f", Self.maxError(fixed, truth) * 1000)) ms, modelo máx "
              + "\(String(format: "%.1f", Self.maxError(p.beats.beats, truth) * 1000)) ms → rejilla máx \(String(format: "%.2f", after * 1000)) ms")
        XCTAssertEqual(g.beats.count, truth.count)
        XCTAssertLessThanOrEqual(after, Self.driftTolerance)
    }

    /// Sin batería la rejilla es la recta local por los pulsos del modelo: quita buena parte del escalón de 20 ms.
    func testWithoutDrumsSmoothsModelFrames() {
        let truth = (0..<96).map { 1.013 + Double($0) * 60 / 126 }
        let p = SongsterrBeatGrid.prepare(BeatTimes(beats: Self.model(truth, late: 0), downbeats: []), writtenTempo: 126)
        let g = SongsterrBeatGrid.build(prepared: p, refBars: Self.bars(Array(repeating: (4, 4), count: 24), tempo: 126),
                                        offset: 0, shifts: [], drums: nil)
        let before = Self.maxError(p.beats.beats, truth), after = Self.maxError(g.beats, truth)
        print("PRECISIÓN sin batería: modelo máx \(String(format: "%.1f", before * 1000)) ms → rejilla máx \(String(format: "%.2f", after * 1000)) ms")
        XCTAssertEqual(g.anchoredBeats, 0)
        XCTAssertLessThan(after, before)
        XCTAssertLessThanOrEqual(after, Self.modelOnlyTolerance)
    }

    // MARK: 3. anacrusa y compases irregulares

    /// Songsterr empieza con un compás de 2/4 (anacrusa) y luego 3/4 y 4/4; el modelo pone compases de 4 desde el
    /// primer pulso. Los primeros tiempos salen de Songsterr.
    func testPickupAndOddMetersFromSongsterr() {
        let sigs = [(2, 4), (4, 4), (4, 4), (3, 4)] + Array(repeating: (4, 4), count: 8)
        let n = sigs.reduce(0) { $0 + $1.0 }
        let truth = (0..<n).map { 2.0 + Double($0) * 0.5 }
        let env = Self.envelope(Self.drums(hits: truth, length: truth.last! + 1))
        let modelDownbeats = stride(from: 0, to: n, by: 4).map { truth[$0] }
        let p = SongsterrBeatGrid.prepare(BeatTimes(beats: Self.model(truth, late: 0.01), downbeats: modelDownbeats),
                                          writtenTempo: 120)
        let g = SongsterrBeatGrid.build(prepared: p, refBars: Self.bars(sigs, tempo: 120), offset: 0, shifts: [], drums: env)
        var starts: [Double] = [], k = 0
        for s in sigs { starts.append(truth[k]); k += s.0 }
        XCTAssertEqual(g.bars.map(\.beatCount), sigs.map(\.0))
        XCTAssertLessThanOrEqual(Self.maxError(g.downbeats, starts), Self.anchoredTolerance)
        XCTAssertEqual(g.downbeats.count, starts.count)
    }

    /// Songsterr escribe un compás de cuenta de 4/4 entero y la grabación solo tiene 2 golpes de cuenta. La
    /// alineación acierta desde el bloque 2 (desfase −2) y falla el primero (0); los downbeats del modelo están bien.
    /// El intro toma el desfase del bloque siguiente.
    func testCountInBarRealignedFromNextBlock() {
        let barsCount = 12
        let truth = (0..<(barsCount * 4 - 2)).map { 1.0 + Double($0) * 0.5 }
        let env = Self.envelope(Self.drums(hits: truth, length: truth.last! + 1))
        // Primer compás de la canción en el pulso 2.
        let modelDownbeats = stride(from: 2, to: truth.count, by: 4).map { truth[$0] }
        let p = SongsterrBeatGrid.prepare(BeatTimes(beats: Self.model(truth, late: 0), downbeats: modelDownbeats),
                                          writtenTempo: 120)
        let g = SongsterrBeatGrid.build(prepared: p, refBars: Self.bars(Array(repeating: (4, 4), count: barsCount), tempo: 120),
                                        offset: -2, shifts: [2, 0, 0], drums: env)
        XCTAssertTrue(g.introRealigned)
        // El compás de cuenta empieza 2 pulsos antes del primer golpe (fuera del audio, pero dentro del tramo).
        let expected = [truth[0] - 1.0] + stride(from: 2, to: truth.count, by: 4).map { truth[$0] }
        XCTAssertEqual(g.downbeats.count, expected.count)
        XCTAssertLessThanOrEqual(Self.maxError(g.downbeats.dropFirst().map { $0 }, expected.dropFirst().map { $0 }),
                                 Self.structureTolerance)
        XCTAssertEqual(g.downbeats[0], expected[0], accuracy: 0.01)
        XCTAssertEqual(g.bars.map(\.beatCount), Array(repeating: 4, count: barsCount))

        // Sin downbeats del modelo que lo apoyen, se respeta la alineación.
        let q = SongsterrBeatGrid.prepare(BeatTimes(beats: Self.model(truth, late: 0), downbeats: []), writtenTempo: 120)
        let h = SongsterrBeatGrid.build(prepared: q, refBars: Self.bars(Array(repeating: (4, 4), count: barsCount), tempo: 120),
                                        offset: -2, shifts: [2, 0, 0], drums: env)
        XCTAssertFalse(h.introRealigned)
    }

    // MARK: 4. estructura

    /// Dos pulsos de más en la grabación antes del bloque 2: entra un compás de 2 pulsos sin compás de Songsterr. Uno de
    /// menos antes del bloque 3: el compás anterior se queda en 3.
    func testExtraAndMissingBeatsInRecording() {
        let count = 12 * 4 + 2 - 1
        let truth: [Double] = (0..<count).map { 1.0 + Double($0) * 0.5 }
        let env = Self.envelope(Self.drums(hits: truth, length: truth.last! + 1))
        let p = SongsterrBeatGrid.prepare(BeatTimes(beats: Self.model(truth, late: 0), downbeats: []), writtenTempo: 120)
        let g = SongsterrBeatGrid.build(prepared: p, refBars: Self.bars(Array(repeating: (4, 4), count: 12), tempo: 120),
                                        offset: 0, shifts: [0, 2, 1], drums: env)
        let counts: [Int] = g.bars.map { $0.beatCount }
        let played: [Int?] = g.bars.map { $0.playedBar }
        XCTAssertEqual(counts, [4, 4, 4, 4, 2, 4, 4, 4, 3, 4, 4, 4, 4])
        XCTAssertEqual(played, [0, 1, 2, 3, nil, 4, 5, 6, 7, 8, 9, 10, 11])
        XCTAssertEqual(g.beats.count, truth.count)
        XCTAssertLessThanOrEqual(Self.maxError(g.beats, truth), Self.structureTolerance)
        XCTAssertFalse(g.introRealigned)
    }

    func testWrittenTempoIsTheLongest() {
        var bars = Self.bars(Array(repeating: (4, 4), count: 10), tempo: 172)
        for j in 7..<10 { bars[j].tempo = 130 }
        let t = SongsterrTrack(name: "g", instrumentId: 30, songId: 1, revisionId: 1, partId: nil, kind: .guitar,
                               tuningStrings: [64, 59, 55, 50, 45, 40], bars: bars, tempoChanges: [], notes: [], hits: [],
                               report: SongsterrImportReport())
        XCTAssertEqual(SongsterrBeatGrid.writtenTempo([t]), 172)
    }
}
