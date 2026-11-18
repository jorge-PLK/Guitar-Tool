import XCTest
@testable import TabKit

/// Conmutar adornos con el teclado (mini-spec Fase 5c, decisión 6 y tabla de teclas).
final class TabOrnamentsTests: XCTestCase {
    func editor() throws -> TabEditor { TabEditor(score: try TabEditorTests.score()) }

    func guitarNotes(_ e: TabEditor) -> [TabNote] { e.score.tracks[e.score.trackIndex(id: "guitar")!].notes }

    func testBooleanOrnamentsToggleOnAndOff() throws {
        var e = try editor()
        let id = guitarNotes(e)[0].id
        let cases: [(TabOrnament, (TabTechniques) -> Bool)] = [
            (.palmMute, { $0.palmMute }), (.letRing, { $0.letRing }), (.hammerPull, { $0.hammerPull }),
            (.vibrato, { $0.vibrato != nil }), (.whammyVibrato, { $0.whammy != nil }), (.dead, { $0.dead }),
            (.ghost, { $0.ghost }), (.accent, { $0.accent == .normal }), (.heavyAccent, { $0.accent == .heavy }),
            (.staccato, { $0.staccato }), (.naturalHarmonic, { $0.harmonic?.type == .natural }),
            (.artificialHarmonic, { $0.harmonic?.type == .artificial }), (.tapping, { $0.tapping }),
            (.pickDown, { $0.pickStroke == .down }), (.pickUp, { $0.pickStroke == .up }),
        ]
        for (o, isSet) in cases {
            try e.toggle(o, trackID: "guitar", noteIDs: [id])
            XCTAssertTrue(isSet(guitarNotes(e).first { $0.id == id }!.techniques), "\(o) no se puso")
            try e.toggle(o, trackID: "guitar", noteIDs: [id])
            XCTAssertTrue(guitarNotes(e).first { $0.id == id }!.techniques.isEmpty, "\(o) no se quitó")
        }
    }

    func testToggleUndoesToIdenticalScore() throws {
        var e = try editor()
        let original = e.score
        try e.toggle(.palmMute, trackID: "guitar", noteIDs: [guitarNotes(e)[0].id])
        XCTAssertNotEqual(e.score, original)
        XCTAssertTrue(e.undo())
        XCTAssertEqual(e.score, original)
        XCTAssertEqual(try TabEditorTests.json(e.score), try TabEditorTests.json(original))
        XCTAssertTrue(e.redo())
        XCTAssertTrue(e.score.tracks[0].notes.contains { $0.techniques.palmMute } || e.score.tracks.flatMap(\.notes).contains { $0.techniques.palmMute })
    }

    func testSlideCycle() throws {
        var e = try editor()
        let id = guitarNotes(e)[0].id
        var seen: [String] = []
        for _ in 0..<7 {
            try e.toggle(.slide, trackID: "guitar", noteIDs: [id])
            let t = guitarNotes(e).first { $0.id == id }!.techniques
            seen.append("\(t.slideIn?.rawValue ?? "-")/\(t.slideOut?.rawValue ?? "-")")
        }
        XCTAssertEqual(seen, ["-/legato", "-/shift", "intoFromBelow/-", "intoFromAbove/-", "-/outDown", "-/outUp", "-/-"])
    }

    func testBendCycle() throws {
        var e = try editor()
        let id = guitarNotes(e)[0].id
        var seen: [TabBend?] = []
        for _ in 0..<4 {
            try e.toggle(.bend, trackID: "guitar", noteIDs: [id])
            seen.append(guitarNotes(e).first { $0.id == id }!.techniques.bend)
        }
        XCTAssertEqual(seen.count, 4)
        XCTAssertEqual(seen[0]?.points.map(\.value), [0, 4, 4])
        XCTAssertEqual(seen[1]?.points.map(\.value), [0, 2, 2])
        XCTAssertEqual(seen[2]?.type, .bendRelease)
        XCTAssertNil(seen[3])
    }

    func testSpanAppliesToEveryNoteOfTheSpan() throws {
        var e = try editor()
        let chord = guitarNotes(e).filter { $0.start.beat == 0 }
        XCTAssertGreaterThan(chord.count, 1)
        let ids = e.noteIDs(in: TabSpan(startTick: 0, endTick: TabScore.ticksPerBeat), trackID: "guitar")
        XCTAssertEqual(Set(ids), Set(chord.map(\.id)))
        try e.toggle(.palmMute, trackID: "guitar", noteIDs: ids)
        XCTAssertTrue(guitarNotes(e).filter { ids.contains($0.id) }.allSatisfy { $0.techniques.palmMute })
        XCTAssertTrue(guitarNotes(e).filter { !ids.contains($0.id) }.allSatisfy { !$0.techniques.palmMute })
        // Si solo algunas lo tienen, la tecla lo pone en todas; con todas, lo quita.
        try e.toggle(.palmMute, trackID: "guitar", noteIDs: [ids[0]])
        try e.toggle(.palmMute, trackID: "guitar", noteIDs: ids)
        XCTAssertTrue(guitarNotes(e).filter { ids.contains($0.id) }.allSatisfy { $0.techniques.palmMute })
        try e.toggle(.palmMute, trackID: "guitar", noteIDs: ids)
        XCTAssertTrue(guitarNotes(e).allSatisfy { !$0.techniques.palmMute })
        // Una sola operación de deshacer por conmutación.
        XCTAssertTrue(e.undo())
        XCTAssertTrue(guitarNotes(e).filter { ids.contains($0.id) }.allSatisfy { $0.techniques.palmMute })
    }

    func testGraceIsTwoFretsBelowAndTied() throws {
        var e = try editor()
        let n = guitarNotes(e).first { e.score.tracks[0].fret(of: $0).map { $0 >= 2 } ?? false }!
        let fret = e.score.tracks[0].fret(of: n)!
        try e.toggle(.grace, trackID: "guitar", noteIDs: [n.id])
        let g = guitarNotes(e).first { $0.id == n.id }!.techniques.graces
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].fret, fret - 2)
        XCTAssertEqual(g[0].type, .beforeBeat)
        XCTAssertTrue(g[0].hammerPull)
        try e.toggle(.grace, trackID: "guitar", noteIDs: [n.id])
        XCTAssertTrue(guitarNotes(e).first { $0.id == n.id }!.techniques.graces.isEmpty)
        // Cuerda al aire: no hay traste por debajo.
        let open = guitarNotes(e).first { e.score.tracks[0].fret(of: $0) == 0 }!
        XCTAssertThrowsError(try e.toggle(.grace, trackID: "guitar", noteIDs: [open.id])) {
            XCTAssertEqual($0 as? TabEditError, .fretOutOfRange)
        }
    }

    func testGraceFretChangesWithUndo() throws {
        var e = try editor()
        let n = guitarNotes(e).first { e.score.tracks[0].fret(of: $0).map { $0 >= 2 } ?? false }!
        XCTAssertThrowsError(try e.setGraceFret(3, trackID: "guitar", noteID: n.id))
        try e.toggle(.grace, trackID: "guitar", noteIDs: [n.id])
        let withGrace = e.score
        try e.setGraceFret(7, trackID: "guitar", noteID: n.id)
        let after = guitarNotes(e).first { $0.id == n.id }!
        XCTAssertEqual(after.techniques.graces[0].fret, 7)
        XCTAssertEqual(after.pitch, n.pitch)
        XCTAssertThrowsError(try e.setGraceFret(25, trackID: "guitar", noteID: n.id)) {
            XCTAssertEqual($0 as? TabEditError, .fretOutOfRange)
        }
        XCTAssertTrue(e.undo())
        XCTAssertEqual(e.score, withGrace)
    }

    func testTieNeedsPreviousNoteOfSameStringAndPitch() throws {
        var e = try editor()
        let beat = e.score.beats.count - 4
        let a = try e.addNote(trackID: "guitar", string: 1, fret: 5, at: GridPoint(beat: beat, tick: 0), duration: 12)
        let b = try e.addNote(trackID: "guitar", string: 1, fret: 5, at: GridPoint(beat: beat + 1, tick: 0), duration: 12)
        XCTAssertThrowsError(try e.toggle(.tie, trackID: "guitar", noteIDs: [a])) {
            XCTAssertEqual($0 as? TabEditError, .noTieOrigin)
        }
        try e.toggle(.tie, trackID: "guitar", noteIDs: [b])
        XCTAssertTrue(guitarNotes(e).first { $0.id == b }!.techniques.tieDestination)
        try e.toggle(.tie, trackID: "guitar", noteIDs: [b])
        XCTAssertFalse(guitarNotes(e).first { $0.id == b }!.techniques.tieDestination)
    }

    func testTieRoundTripsThroughJSONAndOldScoresStillLoad() throws {
        var t = TabTechniques()
        t.tieDestination = true
        let data = try JSONEncoder().encode(t)
        XCTAssertEqual(try JSONDecoder().decode(TabTechniques.self, from: data), t)
        XCTAssertEqual(try JSONDecoder().decode(TabTechniques.self, from: Data("{}".utf8)), TabTechniques())
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(TabTechniques()), as: UTF8.self), "{}")
    }

    func testDrumOrnaments() throws {
        var e = try editor()
        let drums = e.score.tracks[e.score.trackIndex(id: "drums")!]
        let points = Array(Set(drums.hits.map(\.at))).sorted()
        let first = [points[0]]
        try e.toggle(.flam, trackID: "drums", hitPoints: first)
        var hits = e.score.tracks[e.score.trackIndex(id: "drums")!].hits.filter { $0.at == points[0] }
        XCTAssertTrue(hits.allSatisfy { $0.grace?.fret == $0.piece.rawValue && $0.grace?.type == .beforeBeat })
        try e.toggle(.flam, trackID: "drums", hitPoints: first)
        try e.toggle(.ghost, trackID: "drums", hitPoints: first)
        try e.toggle(.accent, trackID: "drums", hitPoints: first)
        try e.toggle(.heavyAccent, trackID: "drums", hitPoints: first)
        hits = e.score.tracks[e.score.trackIndex(id: "drums")!].hits.filter { $0.at == points[0] }
        XCTAssertTrue(hits.allSatisfy { $0.ghost && $0.grace == nil && $0.accent == .heavy })
        try e.toggle(.heavyAccent, trackID: "drums", hitPoints: first)
        try e.toggle(.ghost, trackID: "drums", hitPoints: first)
        XCTAssertEqual(e.score.tracks[e.score.trackIndex(id: "drums")!].hits, drums.hits)
        let ids = e.noteIDs(in: TabSpan(startTick: 0, endTick: 1000), trackID: "drums")
        XCTAssertTrue(ids.isEmpty)
        XCTAssertFalse(e.hitPoints(in: TabSpan(startTick: 0, endTick: 1000), trackID: "drums").isEmpty)
    }

    func testWrongTrackKindsAreRefused() throws {
        var e = try editor()
        let note = guitarNotes(e)[0].id
        let before = e.score
        XCTAssertThrowsError(try e.toggle(.palmMute, trackID: "drums", noteIDs: [1])) {
            XCTAssertEqual($0 as? TabEditError, .wrongTrackKind)
        }
        XCTAssertThrowsError(try e.toggle(.flam, trackID: "guitar", noteIDs: [note]))
        XCTAssertThrowsError(try e.toggle(.palmMute, trackID: "guitar", noteIDs: [9999])) {
            XCTAssertEqual($0 as? TabEditError, .unknownNote)
        }
        XCTAssertThrowsError(try e.toggle(.palmMute, trackID: "guitar", noteIDs: []))
        XCTAssertThrowsError(try e.toggle(.palmMute, trackID: "nope", noteIDs: [1])) {
            XCTAssertEqual($0 as? TabEditError, .unknownTrack)
        }
        XCTAssertThrowsError(try e.toggle(.palmMute, trackID: "guitar", hitPoints: [GridPoint(beat: 0, tick: 0)]))
        XCTAssertThrowsError(try e.toggle(.slide, trackID: "drums", hitPoints: [GridPoint(beat: 0, tick: 0)]))
        XCTAssertEqual(e.score, before)
        XCTAssertFalse(e.canUndo)
    }
}
