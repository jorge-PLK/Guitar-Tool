import XCTest
@testable import TabKit

/// Cuantización a la rejilla (mini-spec Fase 5, «Rejilla» y «Pruebas»).
final class TabQuantizeTests: XCTestCase {
    static let guitar = Tuning.guitar(.standard)

    func makeScore(_ grid: BeatTimes = TabGridTests.rampGrid()) throws -> TabScore {
        try TabScore(beatTimes: grid, duration: grid.beats.last! + 0.5)
    }

    func note(_ t: Double, _ end: Double, _ pitch: Int = 64, _ amp: Float = 0.6) -> NoteEvent {
        NoteEvent(start: t, end: end, pitch: pitch, amplitude: amp)
    }

    /// Ataques en semicorcheas con jitter ±8 ms sobre una rejilla de tempo variable (100→140 BPM): cada uno cae
    /// en su punto.
    func testSixteenthAttacksOnVariableTempoLandOnTheirPoint() throws {
        let score = try makeScore()
        var rng = TabGridTests.LCG(state: 3)
        var events: [NoteEvent] = []
        var expected: [GridPoint] = []
        for b in 0..<(score.beats.count - 1) where score.beats[b].time >= 1.3 {
            let t0 = score.beats[b].time, period = score.beats[b + 1].time - t0
            let k = b % 4                                   // un ataque por pulso, recorriendo las 4 semicorcheas
            let t = t0 + Double(k) * period / 4 + (rng.next() - 0.5) * 0.016
            events.append(note(t, t + period / 8, 60 + b % 12))
            expected.append(GridPoint(beat: b, tick: k * 3))
        }
        let track = TabTrackBuilder.pitchedTrack(id: "g", name: "G", kind: .guitar, tuning: Self.guitar,
                                                 source: nil, notes: events, in: score).track
        XCTAssertEqual(track.notes.map(\.start), expected)
        XCTAssertTrue(track.subdivisions.allSatisfy { $0 == .sixteenths })
        // Error de tiempo tras cuantizar ≤ el jitter (8 ms).
        let worst = zip(track.notes, events).map { abs(score.time(of: $0.start) - $1.start) }.max()!
        XCTAssertLessThanOrEqual(worst, 0.008 + 1e-9)
        print("TabQuantize: error máximo de ataque \(worst * 1000) ms")
    }

    func testTripletBeatChoosesTriplets() throws {
        let score = try makeScore()
        let b = 20, c = 21
        let t0 = score.beats[b].time, p = score.beats[b + 1].time - t0
        let t1 = score.beats[c].time, q = score.beats[c + 1].time - t1
        let triplets: [NoteEvent] = [0.0, 1.0 / 3, 2.0 / 3].map { (x: Double) -> NoteEvent in
            note(t0 + x * p + 0.004, t0 + x * p + p / 4, 64)
        }
        let eighths: [NoteEvent] = [0.0, 0.5].map { (x: Double) -> NoteEvent in
            note(t1 + x * q - 0.004, t1 + x * q + q / 4, 67)
        }
        let events = triplets + eighths
        let track = TabTrackBuilder.pitchedTrack(id: "g", name: "G", kind: .guitar, tuning: Self.guitar,
                                                 source: nil, notes: events, in: score).track
        XCTAssertEqual(track.subdivisions[b], .eighthTriplets)
        XCTAssertEqual(track.subdivisions[c], .sixteenths)
        XCTAssertEqual(track.notes.map(\.start), [GridPoint(beat: b, tick: 0), GridPoint(beat: b, tick: 4),
                                                  GridPoint(beat: b, tick: 8), GridPoint(beat: c, tick: 0),
                                                  GridPoint(beat: c, tick: 6)])
        // Cada tresillo dura un tresillo (4 ticks); los de c, una semicorchea (3 ticks).
        XCTAssertEqual(track.notes.map(\.duration), [4, 4, 4, 3, 3])
    }

    /// Duración: hasta el final de la nota o el siguiente ataque, cuantizada; huecos como silencio; mínimo un punto.
    func testDurationsCutAtNextAttackAndKeepRests() throws {
        let beats = (0..<16).map { Double($0) * 0.5 }   // 120 BPM, semicorchea = 0,125 s
        let score = try TabScore(beatTimes: BeatTimes(beats: beats, downbeats: [0, 2, 4, 6]), duration: 8)
        let events = [
            note(0.0, 0.74, 60),        // 1,5 pulsos → 18 ticks (fin en 0,75)
            note(1.0, 3.0, 62),         // larga, cortada por el ataque en 1,5 → 12 ticks
            note(1.5, 1.52, 64),        // muy corta → un punto (3 ticks)
            note(2.5, 2.99, 65)         // hueco 1,625–2,5 sin notas; dura 1 pulso
        ]
        let track = TabTrackBuilder.pitchedTrack(id: "g", name: "G", kind: .guitar, tuning: Self.guitar,
                                                 source: nil, notes: events, in: score).track
        XCTAssertEqual(track.notes.map(\.start.absoluteTick), [0, 24, 36, 60])
        XCTAssertEqual(track.notes.map(\.duration), [18, 12, 3, 12])
        // El silencio entre la 3.ª y la 4.ª queda como hueco.
        XCTAssertLessThan(track.notes[2].end.absoluteTick, track.notes[3].start.absoluteTick)
    }

    /// Notas antes del primer pulso o tras el último: la rejilla extendida con el periodo local las recoge.
    func testNotesOutsideBeatGridUseExtendedGrid() throws {
        let beats = (0..<8).map { 1.3 + Double($0) * 0.5 }
        let score = try TabScore(beatTimes: BeatTimes(beats: beats, downbeats: [1.3, 3.3]), duration: 7)
        let events = [note(0.175, 0.3, 60), note(6.3, 6.6, 62)]
        let track = TabTrackBuilder.pitchedTrack(id: "g", name: "G", kind: .guitar, tuning: Self.guitar,
                                                 source: nil, notes: events, in: score).track
        XCTAssertEqual(track.notes.count, 2)
        for (n, e) in zip(track.notes, events) {
            XCTAssertEqual(score.time(of: n.start), e.start, accuracy: 1e-9)   // caen justo en semicorchea
        }
    }

    func testDrumOnsetsQuantizedOnePerPiecePerPoint() throws {
        let beats = (0..<16).map { Double($0) * 0.5 }
        let score = try TabScore(beatTimes: BeatTimes(beats: beats, downbeats: [0, 2, 4, 6]), duration: 8)
        let onsets = [DrumOnset(time: 0.003, piece: .kick), DrumOnset(time: 0.0, piece: .crash),
                      DrumOnset(time: 0.01, piece: .kick), DrumOnset(time: 0.505, piece: .snare),
                      DrumOnset(time: 0.62, piece: .hiHat),
                      // Pulso 2 en tresillo de charles.
                      DrumOnset(time: 1.0, piece: .hiHat), DrumOnset(time: 1.0 + 0.5 / 3, piece: .hiHat),
                      DrumOnset(time: 1.0 + 1.0 / 3, piece: .hiHat)]
        let track = TabTrackBuilder.drumTrack(id: "d", name: "D", source: nil, onsets: onsets, in: score)
        XCTAssertEqual(track.hits, [
            TabDrumHit(piece: .kick, at: GridPoint(beat: 0, tick: 0)), TabDrumHit(piece: .crash, at: GridPoint(beat: 0, tick: 0)),
            TabDrumHit(piece: .snare, at: GridPoint(beat: 1, tick: 0)), TabDrumHit(piece: .hiHat, at: GridPoint(beat: 1, tick: 3)),
            TabDrumHit(piece: .hiHat, at: GridPoint(beat: 2, tick: 0)), TabDrumHit(piece: .hiHat, at: GridPoint(beat: 2, tick: 4)),
            TabDrumHit(piece: .hiHat, at: GridPoint(beat: 2, tick: 8))
        ])
        XCTAssertEqual(track.subdivisions[2], .eighthTriplets)
    }
}
