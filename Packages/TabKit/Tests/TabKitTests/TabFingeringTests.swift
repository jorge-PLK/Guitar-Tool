import XCTest
@testable import TabKit

/// Cuerdas y trastes (mini-spec Fase 5, «Cuerdas y trastes» y «Pruebas»).
final class TabFingeringTests: XCTestCase {
    /// 120 BPM: pulso 0,5 s; 16 compases de 4/4.
    static func score() throws -> TabScore {
        let beats = (0..<64).map { Double($0) * 0.5 }
        return try TabScore(beatTimes: BeatTimes(beats: beats, downbeats: stride(from: 0, to: 32, by: 2).map(Double.init)),
                            duration: 32)
    }

    /// Una nota por pulso.
    static func melody(_ pitches: [Int]) -> [NoteEvent] {
        pitches.enumerated().map { NoteEvent(start: Double($0) * 0.5, end: Double($0) * 0.5 + 0.45, pitch: $1, amplitude: 0.6) }
    }

    /// Un acorde por compás.
    static func chords(_ list: [[Int]]) -> [NoteEvent] {
        list.enumerated().flatMap { i, pitches in
            pitches.map { NoteEvent(start: Double(i) * 2, end: Double(i) * 2 + 1.9, pitch: $0, amplitude: 0.6) }
        }
    }

    static func build(_ events: [NoteEvent], kind: TabTrackKind = .guitar,
                      tuning: Tuning = .guitar(.standard)) throws -> (track: TabTrack, report: TabBuildReport) {
        TabTrackBuilder.pitchedTrack(id: "t", name: "T", kind: kind, tuning: tuning, source: nil,
                                     notes: events, in: try score())
    }

    /// (cuerda, traste) por nota en orden de inicio y, dentro del acorde, de la cuerda grave a la aguda.
    static func shape(_ track: TabTrack) -> [[String]] {
        let groups = Dictionary(grouping: track.notes, by: \.start.absoluteTick)
        return groups.keys.sorted().map { k in
            groups[k]!.sorted { $0.string > $1.string }.map { "\($0.string):\(track.fret(of: $0)!)" }
        }
    }

    func testOpenChordsAndPowerChordsUseUsualShapes() throws {
        let cases: [(String, [Int], [String])] = [
            ("Mi", [40, 47, 52, 56, 59, 64], ["6:0", "5:2", "4:2", "3:1", "2:0", "1:0"]),
            ("La", [45, 52, 57, 61, 64], ["5:0", "4:2", "3:2", "2:2", "1:0"]),
            ("Re", [50, 57, 62, 66], ["4:0", "3:2", "2:3", "1:2"]),
            ("Do", [48, 52, 55, 60, 64], ["5:3", "4:2", "3:0", "2:1", "1:0"]),
            ("E5", [40, 47, 52], ["6:0", "5:2", "4:2"]),
            ("A5", [45, 52, 57], ["5:0", "4:2", "3:2"]),
            ("G5", [43, 50, 55], ["6:3", "5:5", "4:5"]),
            ("C5", [48, 55, 60], ["5:3", "4:5", "3:5"])
        ]
        for (name, pitches, expected) in cases {
            let track = try Self.build(Self.chords([pitches])).track
            XCTAssertEqual(Self.shape(track), [expected], name)
        }
    }

    func testPowerChordRiffStaysInShape() throws {
        // E5 G5 A5 C5 (riff típico): cada uno en su forma de dos cuerdas contiguas + octava.
        let riff = [[40, 47, 52], [43, 50, 55], [45, 52, 57], [48, 55, 60]]
        let track = try Self.build(Self.chords(riff)).track
        XCTAssertEqual(Self.shape(track), [["6:0", "5:2", "4:2"], ["6:3", "5:5", "4:5"],
                                           ["5:0", "4:2", "3:2"], ["5:3", "4:5", "3:5"]])
    }

    func testScalesUseFirstPosition() throws {
        // Do mayor en primera posición.
        let cMajor = try Self.build(Self.melody([48, 50, 52, 53, 55, 57, 59, 60])).track
        XCTAssertEqual(Self.shape(cMajor).flatMap { $0 }, ["5:3", "4:0", "4:2", "4:3", "3:0", "3:2", "2:0", "2:1"])
        // Pentatónica de Mi menor abierta, dos octavas.
        let pent = try Self.build(Self.melody([40, 43, 45, 47, 50, 52, 55, 57, 59, 62, 64, 67])).track
        XCTAssertEqual(Self.shape(pent).flatMap { $0 },
                       ["6:0", "6:3", "5:0", "5:2", "4:0", "4:2", "3:0", "3:2", "2:0", "2:3", "1:0", "1:3"])
    }

    func testNoSharedStringsAndFretsInRange() throws {
        var rng = TabGridTests.LCG(state: 11)
        var list: [[Int]] = []
        for _ in 0..<16 {
            let size = 2 + Int(rng.next() * 5)          // 2…6 notas
            var set = Set<Int>()
            while set.count < size { set.insert(40 + Int(rng.next() * 40)) }
            list.append(Array(set))
        }
        let track = try Self.build(Self.chords(list)).track
        for group in Dictionary(grouping: track.notes, by: \.start).values {
            XCTAssertEqual(Set(group.map(\.string)).count, group.count, "cuerda compartida en un acorde")
        }
        for n in track.notes {
            XCTAssertTrue(Tuning.fretRange.contains(track.fret(of: n)!))
        }
    }

    func testTooManyNotesDropsWeakestAndOutOfRangeIsCounted() throws {
        // 7 notas: se quita la de menos amplitud (la 62).
        var events = [40, 47, 52, 56, 59, 64, 62].map { NoteEvent(start: 0, end: 1.9, pitch: $0, amplitude: $0 == 62 ? 0.1 : 0.6) }
        // Fuera de registro: 35 (< E2) sube a 47; 90 (> techo de guitarra 86) se quita (Fase 5b).
        events += [NoteEvent(start: 2, end: 2.4, pitch: 35, amplitude: 0.6), NoteEvent(start: 4, end: 4.4, pitch: 90, amplitude: 0.6)]
        let (track, report) = try Self.build(events)
        XCTAssertEqual(report.shiftedOctave, 1)
        XCTAssertEqual(report.droppedNotes, 2)
        XCTAssertEqual(track.notes.filter { $0.start.beat == 0 }.map(\.pitch).sorted(), [40, 47, 52, 56, 59, 64])
        XCTAssertEqual(track.notes.filter { $0.start.beat > 0 }.map(\.pitch), [47])
    }

    /// Techo de registro (mini-spec Fase 5b, «Respaldo automático»): en guitarra, 86 (traste 22 de la 1.ª) se queda;
    /// 87 y 88, que caben en los trastes 23 y 24, y 95, que antes bajaba una octava, se quitan y se cuentan.
    func testGuitarPitchCeilingDropsAndCounts() throws {
        XCTAssertEqual(TabTrackBuilder.guitarPitchCeiling, 86)
        let (track, report) = try Self.build(Self.melody([76, 86, 87, 88, 95, 84]))
        XCTAssertEqual(track.notes.map(\.pitch), [76, 86, 84])
        XCTAssertEqual(report, TabBuildReport(shiftedOctave: 0, droppedNotes: 3))
        let top = track.notes.first { $0.pitch == 86 }!
        XCTAssertEqual(top.string, 1)
        XCTAssertEqual(track.fret(of: top), 22)
        // Bajo: el techo no se aplica (su registro acaba en 43 + 24 = 67; lo de encima sigue la regla de octava).
        let bass = try Self.build(Self.melody([40, 60, 67]), kind: .bass, tuning: .bass(.standard))
        XCTAssertEqual(bass.track.notes.map(\.pitch), [40, 60, 67])
        XCTAssertEqual(bass.report, TabBuildReport())
    }

    func testTuningChangeKeepsPitches() throws {
        let events = Self.chords([[40, 47, 52, 56, 59, 64], [45, 52, 57], [43, 50, 55], [50, 57, 62, 66]])
            + Self.melody([48, 50, 52, 53, 55, 57, 59, 60]).map {
                NoteEvent(start: $0.start + 8, end: $0.end + 8, pitch: $0.pitch, amplitude: $0.amplitude)
            }
        let original = try Self.build(events).track
        var score = try Self.score()
        score.upsert(original)
        for preset in TuningPreset.fixed {
            var editor = TabEditor(score: score)
            let report = try editor.setTuning(.guitar(preset), trackID: "t")
            let retuned = editor.score.tracks[0]
            XCTAssertEqual(report, TabBuildReport(), "\(preset)")
            XCTAssertEqual(retuned.tuning, .guitar(preset))
            XCTAssertEqual(retuned.notes.map(\.pitch).sorted(), original.notes.map(\.pitch).sorted(), "\(preset)")
            XCTAssertEqual(retuned.notes.map(\.id).sorted(), original.notes.map(\.id).sorted())
            for n in retuned.notes {
                let o = original.notes.first { $0.id == n.id }!
                XCTAssertEqual(n.pitch, o.pitch)
                XCTAssertEqual(n.start, o.start)
                XCTAssertEqual(n.duration, o.duration)
                XCTAssertTrue(Tuning.fretRange.contains(retuned.fret(of: n)!))
            }
            for group in Dictionary(grouping: retuned.notes, by: \.start).values {
                XCTAssertEqual(Set(group.map(\.string)).count, group.count)
            }
        }
        // Drop D: el Mi grave pasa al traste 2 de la 6.ª.
        var editor = TabEditor(score: score)
        try editor.setTuning(.guitar(.dropD), trackID: "t")
        let low = editor.score.tracks[0].notes.first { $0.pitch == 40 }!
        XCTAssertEqual(low.string, 6)
        XCTAssertEqual(editor.score.tracks[0].fret(of: low), 2)
    }

    func testTuningPresets() {
        XCTAssertEqual(Tuning.guitar(.standard).strings, [64, 59, 55, 50, 45, 40])
        XCTAssertEqual(Tuning.guitar(.halfStepDown).strings, [63, 58, 54, 49, 44, 39])
        XCTAssertEqual(Tuning.guitar(.wholeStepDown).strings, [62, 57, 53, 48, 43, 38])
        XCTAssertEqual(Tuning.guitar(.dropD).strings, [64, 59, 55, 50, 45, 38])
        XCTAssertEqual(Tuning.bass(.standard).strings, [43, 38, 33, 28])
        XCTAssertEqual(Tuning.bass(.dropD).strings, [43, 38, 33, 26])
    }

    /// Bajo: entrada polifónica → una nota por ataque, la de más amplitud, en 4 cuerdas.
    func testBassIsMonophonic() throws {
        var events: [NoteEvent] = []
        for i in 0..<16 {
            let t = Double(i) * 0.5 + (i % 2 == 0 ? 0.004 : -0.006)
            events.append(NoteEvent(start: t, end: t + 0.45, pitch: 28 + i % 12, amplitude: 0.8))      // la fundamental
            events.append(NoteEvent(start: t + 0.003, end: t + 0.4, pitch: 40 + i % 12, amplitude: 0.3)) // armónico
            events.append(NoteEvent(start: t - 0.002, end: t + 0.3, pitch: 47 + i % 12, amplitude: 0.2))
        }
        // Una nota larga que se solapa con el ataque siguiente.
        events.append(NoteEvent(start: 8.0, end: 9.4, pitch: 33, amplitude: 0.7))
        events.append(NoteEvent(start: 8.5, end: 8.9, pitch: 35, amplitude: 0.7))
        let track = try Self.build(events, kind: .bass, tuning: .bass(.standard)).track
        XCTAssertEqual(track.notes.count, 18)
        XCTAssertEqual(Set(track.notes.map(\.start)).count, track.notes.count, "más de una nota en un ataque")
        XCTAssertEqual(Array(track.notes.prefix(16).map(\.pitch)), (0..<16).map { 28 + $0 % 12 })
        XCTAssertTrue(track.notes.allSatisfy { (1...4).contains($0.string) })
        // Monofónico también en el tiempo: ninguna nota pasa del siguiente ataque.
        for (a, b) in zip(track.notes, track.notes.dropFirst()) {
            XCTAssertLessThanOrEqual(a.end, b.start)
        }
    }
}
