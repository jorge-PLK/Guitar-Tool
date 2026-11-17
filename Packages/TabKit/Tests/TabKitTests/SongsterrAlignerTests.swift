import Foundation
import XCTest
@testable import TabKit

/// Tema sintético: pistas de Songsterr hechas a mano y su «grabación» (tonos armónicos con ataque de 2 ms) colocada
/// sobre una rejilla de pulsos con un desfase conocido, ajuste fino conocido y pulsos de más o de menos por bloques.
enum SyntheticSong {
    static let sr = SemitoneSpectrogram.sampleRate
    static let tpq = SongsterrTrack.ticksPerQuarter
    static let guitarTuning = [64, 59, 55, 50, 45, 40]
    static let bassTuning = [43, 38, 33, 28]

    /// Generador congruencial (determinista entre ejecuciones).
    struct LCG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
        mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.count)) }
    }

    /// Pulsos cada `period` s desde `start` con un vaivén determinista de ±4 ms.
    static func beats(count: Int, start: Double = 1.0, period: Double = 0.5) -> [Double] {
        (0..<count).map { start + Double($0) * period + 0.004 * sin(Double($0) * 1.7) }
    }

    static func bars(_ count: Int, beatCount: Int = 4) -> [SongsterrBar] {
        (0..<count).map {
            SongsterrBar(sourceMeasure: $0, start: $0 * beatCount * tpq, beatCount: beatCount, beatUnit: 4, tempo: 120,
                         marker: nil)
        }
    }

    /// Corcheas de altura pseudoaleatoria en `pitches` (un 15 % de silencios), cuerda y traste de `tuning`.
    static func track(name: String, kind: TabTrackKind, bars count: Int, seed: UInt64, pitches: ClosedRange<Int>,
                      step: Int = tpq / 2) -> SongsterrTrack {
        var rng = LCG(state: seed)
        let tuning = kind == .bass ? bassTuning : guitarTuning
        let bars = bars(count)
        var notes: [SongsterrNote] = []
        for (b, bar) in bars.enumerated() {
            for pos in stride(from: 0, to: bar.length, by: step) {
                guard rng.int(0...99) >= 15 else { continue }
                let pitch = rng.int(pitches)
                let s = tuning.indices.first { (0...15).contains(pitch - tuning[$0]) } ?? tuning.count - 1
                notes.append(SongsterrNote(bar: b, position: pos, start: bar.start + pos, duration: step,
                                           string: s + 1, fret: pitch - tuning[s], pitch: pitch))
            }
        }
        return SongsterrTrack(name: name, instrumentId: kind == .bass ? 33 : 30, songId: 1, revisionId: 1, partId: nil,
                              kind: kind, tuningStrings: tuning, bars: bars,
                              tempoChanges: [SongsterrTempoChange(bar: 0, position: 0, bpm: 120)], notes: notes, hits: [],
                              report: SongsterrImportReport())
    }

    static func drums(bars count: Int) -> SongsterrTrack {
        let bars = bars(count)
        var hits: [SongsterrHit] = []
        for (b, bar) in bars.enumerated() {
            for k in 0..<bar.beatCount {
                hits.append(SongsterrHit(bar: b, position: k * tpq, start: bar.start + k * tpq,
                                         piece: k % 2 == 0 ? .kick : .snare))
            }
        }
        return SongsterrTrack(name: "Drums", instrumentId: 1024, songId: 1, revisionId: 1, partId: nil, kind: .drums,
                              tuningStrings: [], bars: bars, tempoChanges: [], notes: [], hits: hits,
                              report: SongsterrImportReport())
    }

    /// La grabación: pulso de la negra q = q + offset + desfase del bloque de su compás; lo que cae en pulsos que un
    /// bloque posterior ya ocupa no suena.
    struct Truth {
        var offset: Int
        var fine: Double
        /// Desfase por bloque de 4 compases.
        var blockShifts: [Int]

        var placement: Placement {
            Placement(offset: offset, fine: fine, shifts: blockShifts,
                      barStartQ: (0..<(blockShifts.count * 4)).map { Double($0 * 4) })
        }

        func onset(_ start: Int, bar: Int, line: BeatLine) -> Double? {
            let q = Double(start) / Double(tpq)
            guard placement.keeps(q: q, bar: bar) else { return nil }
            return line.time(placement.gridBeat(q: q, bar: bar)) + fine
        }
    }

    /// Tonos armónicos (6 parciales a 1/h, caída exponencial de 0,3 s, ataque lineal de 2 ms) hasta el ataque
    /// siguiente.
    static func render(_ events: [(time: Double, pitch: Int)], duration: Double, gain: Float = 0.2) -> [Float] {
        var out = [Float](repeating: 0, count: Int(duration * sr))
        let sorted = events.sorted { $0.time < $1.time }
        for (k, e) in sorted.enumerated() {
            let end = min(e.time + 0.6, k + 1 < sorted.count ? max(sorted[k + 1].time, e.time + 0.05) : e.time + 0.6)
            let i0 = max(0, Int((e.time * sr).rounded())), i1 = min(out.count, Int(end * sr))
            guard i1 > i0 else { continue }
            let f = 440 * pow(2, Double(e.pitch - 69) / 12)
            let t0 = Double(i0) / sr - e.time
            for i in i0..<i1 {
                let t = Double(i - i0) / sr + t0
                let env = min(1, t / 0.002) * exp(-t / 0.3)
                var v = 0.0
                for h in 1...6 where Double(h) * f < sr / 2 { v += sin(2 * .pi * Double(h) * f * t) / Double(h) }
                out[i] += gain * Float(env * v)
            }
        }
        return out
    }

    /// Ráfagas de ruido de 40 ms (batería).
    static func renderHits(_ times: [Double], duration: Double) -> [Float] {
        var out = [Float](repeating: 0, count: Int(duration * sr))
        var rng = LCG(state: 99)
        for t in times {
            let i0 = max(0, Int((t * sr).rounded())), i1 = min(out.count, i0 + Int(0.04 * sr))
            guard i1 > i0 else { continue }
            for i in i0..<i1 {
                let env = exp(-Double(i - i0) / sr / 0.01)
                out[i] += Float(env) * 0.3 * (Float(rng.next() % 2000) / 1000 - 1)
            }
        }
        return out
    }

    static func events(_ track: SongsterrTrack, truth: Truth, line: BeatLine) -> [(time: Double, pitch: Int)] {
        track.notes.compactMap { n in truth.onset(n.start, bar: n.bar, line: line).map { ($0, n.pitch) } }
    }
}

final class SongsterrAlignerTests: XCTestCase {
    typealias S = SyntheticSong

    /// Ajuste fino recuperado en el tema sintético: un paso de la búsqueda (5 ms).
    static let fineTolerance = 0.005
    /// Tiempo alineado de cada nota frente al real: lo que se equivoque el ajuste fino (un paso, 5 ms); el desfase en
    /// pulsos es exacto.
    static let onsetTolerance = 0.005 + 1e-9

    /// El pico de la envolvente de ataques (leída con `OnsetEnvelope.peakAdvance`) cae en el ataque real: tonos
    /// aislados a tiempos que no son múltiplo del hop, pico por interpolación de 0,1 ms.
    func testOnsetEnvelopePeakMatchesAttack() {
        let times: [Double] = (0..<40).map { (k: Int) -> Double in 0.5 + Double(k) * 0.4 + 0.0013 * Double(k % 7) }
        let pitches: [Int] = (0..<40).map { (k: Int) -> Int in 40 + (k * 7) % 36 }
        let audio = S.render(Array(zip(times, pitches)), duration: 17)
        let env = OnsetEnvelope(samples: audio, sampleRate: S.sr)
        var errors: [Double] = []
        for t in times {
            var best = -Double.infinity, at = 0.0
            for k in -400...400 {
                let x = t + Double(k) * 0.0001
                let v = Double(env.value(at: x - OnsetEnvelope.peakAdvance))
                if v > best { best = v; at = x }
            }
            errors.append(at - t)
        }
        let mean = errors.reduce(0, +) / Double(errors.count)
        print("SINT envolvente: error medio del pico \(String(format: "%.2f", mean * 1000)) ms, "
              + "máx |e| \(String(format: "%.2f", errors.map(abs).max()! * 1000)) ms")
        // Media a ±1 ms; cada pico, a ±5 ms (tramas de 5,8 ms: el máximo de la interpolación lineal cae en una).
        XCTAssertEqual(mean, 0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(errors.map(abs).max()!, 0.005)
    }

    func testRecoversGlobalOffsetAndFineToOneStep() throws {
        let bars = 16
        let gtr = S.track(name: "Gtr", kind: .guitar, bars: bars, seed: 1, pitches: 45...76)
        let bass = S.track(name: "Bass", kind: .bass, bars: bars, seed: 2, pitches: 28...50)
        let beats = S.beats(count: 80)
        let line = BeatLine(beats)
        for (offset, fine) in [(3, 0.020), (-2, -0.035), (5, 0.0)] {
            let truth = S.Truth(offset: offset, fine: fine, blockShifts: [Int](repeating: 0, count: bars / 4))
            let duration = beats.last! + 2
            let audio: [SongsterrStemRole: [Float]] = [
                .guitar: S.render(S.events(gtr, truth: truth, line: line), duration: duration),
                .bass: S.render(S.events(bass, truth: truth, line: line), duration: duration),
            ]
            let a = try SongsterrAligner.align(tracks: [gtr, bass], beats: BeatTimes(beats: beats, downbeats: []),
                                               audio: audio, soloSpans: [])
            print("SINT desfase real \(offset) + \(fine) s → \(a.offsetBeats) + \(a.fineOffset) s")
            XCTAssertEqual(a.offsetBeats, offset)
            XCTAssertEqual(a.fineOffset, fine, accuracy: Self.fineTolerance, "desfase \(offset)")
            XCTAssertFalse(a.usesBlocks)
            XCTAssertTrue(a.structureWarnings.isEmpty)
        }
    }

    /// Grabación con 2 pulsos de más antes del compás 8, 3 de menos antes del 16 y un compás de más antes del 24:
    /// bloques, avisos, notas que sobran y tiempo de cada nota.
    func testBlocksFindStructureDifferences() throws {
        let bars = 32
        let gtr = S.track(name: "Gtr", kind: .guitar, bars: bars, seed: 11, pitches: 45...76)
        let bass = S.track(name: "Bass", kind: .bass, bars: bars, seed: 12, pitches: 28...50)
        let beats = S.beats(count: 150)
        let line = BeatLine(beats)
        let truth = S.Truth(offset: 2, fine: 0.015, blockShifts: [0, 0, 2, 2, -1, -1, 3, 3])
        let duration = beats.last! + 2
        let audio: [SongsterrStemRole: [Float]] = [
            .guitar: S.render(S.events(gtr, truth: truth, line: line), duration: duration),
            .bass: S.render(S.events(bass, truth: truth, line: line), duration: duration),
        ]
        let a = try SongsterrAligner.align(tracks: [gtr, bass], beats: BeatTimes(beats: beats, downbeats: []),
                                           audio: audio, soloSpans: [])
        XCTAssertEqual(a.fineOffset, 0.015, accuracy: Self.fineTolerance)
        XCTAssertTrue(a.usesBlocks, "global \(a.globalSalience) bloques \(a.blockSalience)")
        // El global puede quedarse con cualquier tramo; el desfase absoluto de cada bloque es el real.
        XCTAssertEqual(a.blocks.map { a.offsetBeats + $0.shift }, truth.blockShifts.map { truth.offset + $0 })
        XCTAssertEqual(a.structureWarnings.map(\.bar), [8, 16, 24])
        XCTAssertEqual(a.structureWarnings.map(\.beats), [2, -3, 4])
        XCTAssertEqual(a.structureWarnings.map(\.wholeBars), [nil, nil, 1])
        // Compás 16 en la grabación: pulso 2 + 64 − 1 = 65.
        XCTAssertEqual(a.structureWarnings[1].time, beats[65] + a.fineOffset, accuracy: 1e-9)

        // Las notas de los 3 últimos pulsos del compás 15 sobran; las demás, a ≤ 5 ms de su ataque real.
        let extra = gtr.notes.filter { $0.bar == 15 && $0.position >= S.tpq }.count
        XCTAssertGreaterThan(extra, 0)
        XCTAssertEqual(a.placements[0].droppedInExtraBeats, extra)
        let expected = gtr.notes.compactMap { truth.onset($0.start, bar: $0.bar, line: line) }
        XCTAssertEqual(a.timedNotes[0].count, expected.count)
        let worst = zip(a.timedNotes[0].map(\.onset), expected).map { abs($0 - $1) }.max() ?? 1
        print("SINT estructura: peor |Δ ataque| \(String(format: "%.2f", worst * 1000)) ms")
        XCTAssertLessThanOrEqual(worst, Self.onsetTolerance)
    }

    /// Búsqueda del desfase global ampliada por la diferencia de duración (Benito Kamelas, Songsterr 6187196: 848 negras
    /// sobre 789 pulsos, desfase real −56).
    func testGlobalShiftRangeCoversLengthDifference() {
        XCTAssertEqual(SongsterrAligner.globalShifts(tabQuarters: 788, beats: 789), -48...49)
        XCTAssertEqual(SongsterrAligner.globalShifts(tabQuarters: 848, beats: 789), -107...48)
        XCTAssertEqual(SongsterrAligner.globalShifts(tabQuarters: 64, beats: 150), -48...134)
        XCTAssertEqual(SongsterrAligner.globalShifts(tabQuarters: 80, beats: 80), -48...48)
    }

    /// Lo que rompía Benito Kamelas (6187196 y 3490233): la tablatura escribe 14 compases de intro que la grabación no
    /// tiene, más de los ±48 pulsos que probaba el prototipo; el desfase se quedaba en +8 con bloques de ±12 que iban y
    /// volvían y ~1000 notas fuera. Aquí 15 compases de más (−60) delante, y al revés 15 de menos (+60, la grabación
    /// tiene una intro que la tablatura no): desfase exacto, sin bloques ni avisos, y fuera solo las notas que no suenan.
    func testRecoversGlobalOffsetBeyondPrototypeRange() throws {
        for (bars, offset, beatCount) in [(32, -60, 80), (16, 60, 150)] {
            let gtr = S.track(name: "Gtr", kind: .guitar, bars: bars, seed: 31, pitches: 45...76)
            let bass = S.track(name: "Bass", kind: .bass, bars: bars, seed: 32, pitches: 28...50)
            let beats = S.beats(count: beatCount)
            let line = BeatLine(beats)
            let truth = S.Truth(offset: offset, fine: 0.010, blockShifts: [Int](repeating: 0, count: bars / 4))
            let duration = beats.last! + 2
            // Solo suena lo que cae en la grabación (desde el primer pulso).
            func heard(_ t: SongsterrTrack) -> [(time: Double, pitch: Int)] {
                S.events(t, truth: truth, line: line).filter { $0.time >= beats[0] - 0.01 && $0.time < duration - 0.6 }
            }
            let audio: [SongsterrStemRole: [Float]] = [
                .guitar: S.render(heard(gtr), duration: duration),
                .bass: S.render(heard(bass), duration: duration),
            ]
            let a = try SongsterrAligner.align(tracks: [gtr, bass], beats: BeatTimes(beats: beats, downbeats: []),
                                               audio: audio, soloSpans: [])
            let outside = a.placements.map(\.droppedOutsideGrid).reduce(0, +)
            // `TabScore` antepone los pulsos que caben antes del primero (pulsos desde 1 s cada 0,5 s: 2); fuera queda lo
            // de antes.
            let prepended = 2.0
            var missing = 0
            for t in [gtr, bass] {
                for n in t.notes where Double(n.start) / Double(S.tpq) + Double(offset) < -prepended { missing += 1 }
            }
            print("SINT desfase real \(offset) (\(bars) compases sobre \(beatCount) pulsos) → \(a.offsetBeats), "
                  + "fino \(a.fineOffset), avisos \(a.structureWarnings.count), fuera \(outside) (antes del primer pulso \(missing))")
            XCTAssertEqual(a.offsetBeats, offset)
            XCTAssertEqual(a.fineOffset, 0.010, accuracy: Self.fineTolerance)
            XCTAssertFalse(a.usesBlocks)
            XCTAssertTrue(a.structureWarnings.isEmpty)
            XCTAssertEqual(outside, missing)
        }
    }

    /// Las técnicas de Songsterr llegan a la tablatura: una nota con palm mute y bend conserva las dos tras la
    /// colocación (y las demás, ninguna), y un golpe fantasma sigue fantasma.
    func testPlacementKeepsTechniquesAndGhostHits() throws {
        var gtr = S.track(name: "Gtr", kind: .guitar, bars: 4, seed: 21, pitches: 45...76, step: S.tpq)
        var drums = S.drums(bars: 4)
        let marked = 5
        var tech = TabTechniques()
        tech.palmMute = true
        tech.bend = try XCTUnwrap(TabBend(points: [TabBendPoint(position: 0, value: 0), TabBendPoint(position: 30, value: 4),
                                                   TabBendPoint(position: 60, value: 4)]))
        gtr.notes[marked].techniques = tech
        drums.hits[3].ghost = true
        let beats = S.beats(count: 24)
        let placement = Placement(offset: 2, fine: 0, shifts: [], barStartQ: gtr.bars.map { SongsterrAligner.quarters($0.start) })
        let (score, reports) = try SongsterrScorePlacement.build(tracks: [gtr, drums], beats: beats, placement: placement,
                                                                 refBars: gtr.bars, duration: beats.last! + 1)
        XCTAssertEqual(reports.map(\.droppedOutsideGrid), [0, 0])
        let notes = try XCTUnwrap(score.tracks.first { $0.id == SongsterrScorePlacement.trackID(0) }).notes
        XCTAssertEqual(notes.count, gtr.notes.count)
        XCTAssertEqual(notes.filter { !$0.techniques.isEmpty }.count, 1)
        let kept = try XCTUnwrap(notes.first { !$0.techniques.isEmpty })
        XCTAssertEqual(kept.techniques, tech)
        XCTAssertEqual(kept.pitch, gtr.notes[marked].pitch)
        XCTAssertEqual(kept.string, gtr.notes[marked].string)
        let hits = try XCTUnwrap(score.tracks.first { $0.id == SongsterrScorePlacement.trackID(1) }).hits
        XCTAssertEqual(hits.count, drums.hits.count)
        XCTAssertEqual(hits.filter(\.ghost).count, 1)
    }

    /// Riff que se repite cada 2 compases (Tornado Of Souls): dos bloques ganan 0,05 y 0,035 de saliencia a +9 y −7
    /// pulsos del camino y vuelven. Con solo `blockChangePenalty` (3 cambios = 0,06) el camino salta; con el coste por
    /// pulso de salto, no. Un cambio de 4 pulsos (un compás de más) que se mantiene 5 bloques con 0,05 sí se toma.
    func testViterbiIgnoresTwoBarJumpsThatComeBack() {
        let shifts = Array(SongsterrAligner.blockShifts)
        func idx(_ s: Int) -> Int { shifts.firstIndex(of: s)! }
        var score = [[Double]](repeating: [Double](repeating: 0.40, count: shifts.count), count: 12)
        for b in score.indices { score[b][idx(-3)] = 0.55 }
        score[2][idx(6)] = 0.60
        score[3][idx(-10)] = 0.585
        for b in 7..<12 { score[b][idx(1)] = 0.60 }
        let old = SongsterrAligner.viterbi(score, penalty: SongsterrAligner.blockChangePenalty).map { shifts[$0] }
        XCTAssertEqual(Array(old[2...3]), [6, -10])
        let path = SongsterrAligner.viterbi(score, penalty: SongsterrAligner.blockChangePenalty,
                                            perStep: SongsterrAligner.blockChangePenaltyPerBeat).map { shifts[$0] }
        XCTAssertEqual(path, [Int](repeating: -3, count: 7) + [Int](repeating: 1, count: 5))
    }

    /// `TabScore`: rejilla = pulsos + ajuste fino, compases de Songsterr (aquí 3/4), tempo escrito de la Fase 5,
    /// cuerda y traste de Songsterr, tresillos en su subdivisión.
    func testScoreKeepsStringFretAndSongsterrBars() throws {
        let bars = 12
        var gtr = S.track(name: "Gtr", kind: .guitar, bars: bars, seed: 21, pitches: 45...76)
        // Compases de 3/4 y una nota en tresillo (1/3 de negra) en el compás 2, cuerda 3 traste 7.
        gtr.bars = S.bars(bars, beatCount: 3)
        gtr.notes = []
        var rng = S.LCG(state: 5)
        for (b, bar) in gtr.bars.enumerated() {
            for pos in stride(from: 0, to: bar.length, by: S.tpq / 2) {
                let p = rng.int(45...76)
                let s = S.guitarTuning.indices.first { (0...15).contains(p - S.guitarTuning[$0]) }!
                gtr.notes.append(SongsterrNote(bar: b, position: pos, start: bar.start + pos, duration: S.tpq / 2,
                                               string: s + 1, fret: p - S.guitarTuning[s], pitch: p))
            }
        }
        gtr.notes.removeAll { $0.bar == 2 && (S.tpq..<(2 * S.tpq)).contains($0.position) }
        let triplet = SongsterrNote(bar: 2, position: S.tpq + S.tpq / 3, start: gtr.bars[2].start + S.tpq + S.tpq / 3,
                                    duration: S.tpq / 3, string: 3, fret: 7, pitch: 55 + 7)
        gtr.notes.append(triplet)
        gtr.notes.sort { ($0.start, $0.string) < ($1.start, $1.string) }
        let drums = S.drums(bars: bars)
        let beats = S.beats(count: 50)
        let line = BeatLine(beats)
        let truth = S.Truth(offset: 4, fine: 0.010, blockShifts: [0, 0, 0])
        let duration = beats.last! + 1
        let a = try SongsterrAligner.align(
            tracks: [gtr, drums], beats: BeatTimes(beats: beats, downbeats: []),
            audio: [.guitar: S.render(S.events(gtr, truth: truth, line: line), duration: duration)], soloSpans: [])
        XCTAssertEqual(a.offsetBeats, 4)
        let score = a.score
        // Rejilla: los pulsos detectados + ajuste fino, tal cual.
        let first = try XCTUnwrap(score.beats.firstIndex { abs($0.time - (beats[0] + a.fineOffset)) < 1e-9 })
        XCTAssertEqual(zip(score.beats[first..<(first + beats.count)].map(\.time), beats).map { $0 - $1 - a.fineOffset }
                        .map(abs).max()!, 0, accuracy: 1e-9)
        // Compases de 3 pulsos desde el pulso 4 (el compás 0 de Songsterr), tempo escrito 120.
        let barAtStart = try XCTUnwrap(score.bars.firstIndex { $0.firstBeat == first + 4 })
        XCTAssertTrue(score.bars[barAtStart..<(barAtStart + bars)].allSatisfy { $0.beatCount == 3 })
        XCTAssertTrue(score.bars.allSatisfy { $0.tempo == 120 }, "\(Set(score.bars.map(\.tempo)))")
        // Cada nota: pulso 4 + negra de Songsterr, misma cuerda y traste.
        let track = try XCTUnwrap(score.tracks.first { $0.id == "songsterr-0" })
        XCTAssertEqual(track.notes.count, gtr.notes.count)
        for (n, src) in zip(track.notes, gtr.notes) {
            let q = Double(src.start) / Double(S.tpq)
            let beat = first + 4 + Int(q.rounded(.down))
            XCTAssertEqual(n.start.beat, beat)
            XCTAssertEqual(Double(n.start.tick) / Double(TabScore.ticksPerBeat), q - q.rounded(.down), accuracy: 1e-9)
            XCTAssertEqual(n.string, src.string)
            XCTAssertEqual(track.fret(of: n), src.fret)
        }
        let tripletBeat = first + 4 + 3 * 2 + 1
        XCTAssertEqual(track.subdivisions[tripletBeat], .eighthTriplets)
        XCTAssertEqual(track.subdivisions[tripletBeat - 1], .sixteenths)
        // Batería en su pulso, sin pasar por el audio.
        let drumTrack = try XCTUnwrap(score.tracks.first { $0.id == "songsterr-1" })
        XCTAssertEqual(drumTrack.hits.count, drums.hits.count)
        XCTAssertEqual(drumTrack.hits.first?.at, GridPoint(beat: first + 4, tick: 0))
        // La batería no tiene afinación, ni «Personalizada».
        XCTAssertNil(drumTrack.tuning)
        XCTAssertFalse(a.placements[1].customTuning)
    }

    /// Emparejamiento por croma: L y R con su pista, bajo y batería con las suyas, la tercera guitarra (sin stem) extra.
    func testPairsTracksWithStemsByChroma() throws {
        let bars = 16
        let low = S.track(name: "Rítmica grave", kind: .guitar, bars: bars, seed: 31, pitches: 40...55)
        let high = S.track(name: "Rítmica aguda", kind: .guitar, bars: bars, seed: 32, pitches: 60...76)
        let keys = S.track(name: "Teclado", kind: .guitar, bars: bars, seed: 33, pitches: 48...72)
        let bass = S.track(name: "Bajo", kind: .bass, bars: bars, seed: 34, pitches: 28...45)
        let drums = S.drums(bars: bars)
        let beats = S.beats(count: 80)
        let line = BeatLine(beats)
        let truth = S.Truth(offset: 1, fine: 0, blockShifts: [0, 0, 0, 0])
        let duration = beats.last! + 2
        let left = S.render(S.events(high, truth: truth, line: line), duration: duration)
        let right = S.render(S.events(low, truth: truth, line: line), duration: duration)
        let hitTimes = drums.hits.compactMap { truth.onset($0.start, bar: $0.bar, line: line) }
        let audio: [SongsterrStemRole: [Float]] = [
            .guitarLeft: left, .guitarRight: right, .guitar: zip(left, right).map { $0 + $1 },
            .bass: S.render(S.events(bass, truth: truth, line: line), duration: duration),
            .drums: S.renderHits(hitTimes, duration: duration),
        ]
        let a = try SongsterrAligner.align(tracks: [low, high, keys, bass, drums],
                                           beats: BeatTimes(beats: beats, downbeats: []), audio: audio, soloSpans: [])
        let pair = Dictionary(uniqueKeysWithValues: a.pairs.map { ($0.role, $0) })
        for p in a.pairs { print("SINT pareja \(p.role.rawValue) ← \(p.track) \(p.confidence) margen \(p.margin ?? .nan)") }
        XCTAssertEqual(pair[.guitarLeft]?.track, 1)
        XCTAssertEqual(pair[.guitarRight]?.track, 0)
        XCTAssertEqual(pair[.bass]?.track, 3)
        XCTAssertEqual(pair[.drums]?.track, 4)
        XCTAssertNil(pair[.guitarLead])
        XCTAssertEqual(a.extraTracks, [2])
        // Confianza clara frente a la otra guitarra y la batería casi entera sobre ataques.
        XCTAssertGreaterThan(pair[.guitarLeft]!.margin!, 0.1)
        XCTAssertGreaterThan(pair[.guitarRight]!.margin!, 0.1)
        XCTAssertGreaterThan(pair[.drums]!.confidence, 0.9)
        XCTAssertEqual(a.candidates.filter { $0.role == .guitarLeft }.count, 3)
    }

    /// Voz/teclados (programa GM fuera de guitarra) y batería no estiman: misma alineación con y sin ellas (aunque el
    /// stem de guitarra lleve el teclado sonando 5 pulsos más tarde), la heredan nota a nota y el teclado sale extra.
    func testNonGuitarTracksInheritAlignment() throws {
        let bars = 16
        let gtr = S.track(name: "Gtr", kind: .guitar, bars: bars, seed: 41, pitches: 45...76)
        let bass = S.track(name: "Bass", kind: .bass, bars: bars, seed: 42, pitches: 28...50)
        var keys = S.track(name: "Teclado", kind: .guitar, bars: bars, seed: 43, pitches: 48...84, step: S.tpq / 4)
        keys.instrumentId = 0  // piano: el conversor lo deja como .guitar
        let drums = S.drums(bars: bars)
        let beats = S.beats(count: 90)
        let line = BeatLine(beats)
        let truth = S.Truth(offset: 3, fine: 0.010, blockShifts: [0, 0, 0, 0])
        let bleed = S.Truth(offset: 8, fine: 0.010, blockShifts: [0, 0, 0, 0])
        let duration = beats.last! + 2
        let guitarStem = zip(S.render(S.events(gtr, truth: truth, line: line), duration: duration),
                             S.render(S.events(keys, truth: bleed, line: line), duration: duration, gain: 0.1)).map { $0 + $1 }
        let audio: [SongsterrStemRole: [Float]] = [
            .guitar: guitarStem, .guitarLeft: guitarStem,
            .bass: S.render(S.events(bass, truth: truth, line: line), duration: duration),
        ]
        let grid = BeatTimes(beats: beats, downbeats: [])
        let with = try SongsterrAligner.align(tracks: [gtr, bass, keys, drums], beats: grid, audio: audio, soloSpans: [])
        let without = try SongsterrAligner.align(tracks: [gtr, bass], beats: grid, audio: audio, soloSpans: [])
        XCTAssertEqual(with.offsetBeats, 3)
        XCTAssertEqual(with.offsetBeats, without.offsetBeats)
        XCTAssertEqual(with.fineOffset, without.fineOffset)
        XCTAssertEqual(with.globalSalience, without.globalSalience)
        XCTAssertEqual(with.blocks, without.blocks)
        // Herencia: teclado y batería con el desfase y el fino estimados.
        let expectedKeys = keys.notes.map { line.time(Double($0.start) / Double(S.tpq) + 3) + with.fineOffset }
        XCTAssertEqual(zip(with.timedNotes[2].map(\.onset), expectedKeys).map { abs($0 - $1) }.max()!, 0, accuracy: 1e-9)
        let expectedHits = drums.hits.map { line.time(Double($0.start) / Double(S.tpq) + 3) + with.fineOffset }
        XCTAssertEqual(zip(with.timedNotes[3].map(\.onset), expectedHits).map { abs($0 - $1) }.max()!, 0, accuracy: 1e-9)
        XCTAssertEqual(with.score.tracks.first { $0.id == "songsterr-2" }?.notes.isEmpty, false)
        // El teclado no es candidato de ningún stem y sale extra; la batería, sin stem, también.
        XCTAssertFalse(with.candidates.contains { $0.track == 2 })
        XCTAssertEqual(with.pairs.first { $0.role == .guitarLeft }?.track, 0)
        XCTAssertEqual(with.extraTracks, [2, 3])
    }

    func testErrors() {
        let gtr = S.track(name: "Gtr", kind: .guitar, bars: 4, seed: 1, pitches: 45...76)
        XCTAssertThrowsError(try SongsterrAligner.align(tracks: [gtr], beats: BeatTimes(beats: [1], downbeats: []),
                                                        audio: [.guitar: [0]], soloSpans: [])) {
            XCTAssertEqual($0 as? TabScoreError, .notEnoughBeats)
        }
        XCTAssertThrowsError(try SongsterrAligner.align(tracks: [gtr], beats: BeatTimes(beats: [1, 2, 3], downbeats: []),
                                                        audio: [.bass: [Float](repeating: 0, count: 1000)], soloSpans: [])) {
            XCTAssertEqual($0 as? SongsterrAlignmentError, .nothingToAlign)
        }
    }
}
