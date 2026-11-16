import XCTest
@testable import TabKit

/// Edición y deshacer (mini-spec Fase 5, «Pruebas»: cada operación y su deshacer devuelve la partitura idéntica).
final class TabEditorTests: XCTestCase {
    /// Guitarra (Mi mayor + Do mayor en primera posición), bajo y batería; el pulso 4 de la guitarra en tresillo.
    static func score() throws -> TabScore {
        var score = try TabFingeringTests.score()
        let guitarEvents = TabFingeringTests.chords([[40, 47, 52, 56, 59, 64]])
            + [0.0, 1.0 / 3, 2.0 / 3].map { NoteEvent(start: 2 + $0 * 0.5, end: 2 + $0 * 0.5 + 0.15, pitch: 60, amplitude: 0.5) }
            + TabFingeringTests.melody([48, 50, 52, 53]).map {
                NoteEvent(start: $0.start + 4, end: $0.end + 4, pitch: $0.pitch, amplitude: $0.amplitude)
            }
        score.upsert(TabTrackBuilder.pitchedTrack(id: "guitar", name: "Guitarra", kind: .guitar, tuning: .guitar(.standard),
                                                  source: nil, notes: guitarEvents, in: score).track)
        score.upsert(TabTrackBuilder.pitchedTrack(id: "bass", name: "Bajo", kind: .bass, tuning: .bass(.standard),
                                                  source: nil, notes: TabFingeringTests.melody([28, 31, 33, 35]), in: score).track)
        score.upsert(TabTrackBuilder.drumTrack(id: "drums", name: "Batería", source: nil,
                                               onsets: [DrumOnset(time: 0, piece: .kick), DrumOnset(time: 0.5, piece: .snare)],
                                               in: score))
        return score
    }

    static func json(_ score: TabScore) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(score)
    }

    func note(_ editor: TabEditor, pitch: Int, beat: Int, track: String = "guitar") -> TabNote {
        editor.score.tracks[editor.score.trackIndex(id: track)!].notes.first { $0.pitch == pitch && $0.start.beat == beat }!
    }

    /// Aplica `op`, comprueba que cambia la partitura, deshace (idéntica, también en JSON) y rehace (igual que tras op).
    func assertRoundTrip(_ name: String, _ op: (inout TabEditor) throws -> Void) throws {
        let original = try Self.score()
        var editor = TabEditor(score: original)
        try op(&editor)
        let edited = editor.score
        XCTAssertNotEqual(edited, original, "\(name): no cambió nada")
        XCTAssertTrue(editor.undo(), name)
        XCTAssertEqual(editor.score, original, name)
        XCTAssertEqual(try Self.json(editor.score), try Self.json(original), name)
        XCTAssertTrue(editor.redo(), name)
        XCTAssertEqual(editor.score, edited, name)
        XCTAssertTrue(editor.undo(), name)
        XCTAssertEqual(editor.score, original, name)
        XCTAssertFalse(editor.canUndo, name)
    }

    func testEachOperationUndoesToIdenticalScore() throws {
        let base = TabEditor(score: try Self.score())
        let e2 = note(base, pitch: 40, beat: 0)
        let c4 = note(base, pitch: 60, beat: 4)
        let bassNote = base.score.tracks[1].notes[0]

        try assertRoundTrip("traste") { try $0.setFret(3, trackID: "guitar", noteID: e2.id) }
        try assertRoundTrip("cuerda") { try $0.moveNote(trackID: "guitar", noteID: c4.id, toString: 3) }
        try assertRoundTrip("borrar") { try $0.deleteNote(trackID: "guitar", noteID: c4.id) }
        try assertRoundTrip("añadir") {
            try $0.addNote(trackID: "guitar", string: 1, fret: 5, at: GridPoint(beat: 12, tick: 3), duration: 6)
        }
        try assertRoundTrip("duración") { try $0.setDuration(3, trackID: "guitar", noteID: e2.id) }
        try assertRoundTrip("afinación") { try $0.setTuning(.guitar(.dropD), trackID: "guitar") }
        try assertRoundTrip("bajo") { try $0.setFret(7, trackID: "bass", noteID: bassNote.id) }
        try assertRoundTrip("poner golpe") { try $0.setHit(.crash, at: GridPoint(beat: 2, tick: 6), present: true, trackID: "drums") }
        try assertRoundTrip("quitar golpe") { try $0.setHit(.snare, at: GridPoint(beat: 1, tick: 0), present: false, trackID: "drums") }
    }

    func testUndoChainAndRedoClearedByNewEdit() throws {
        let original = try Self.score()
        var editor = TabEditor(score: original)
        let e2 = note(editor, pitch: 40, beat: 0)
        try editor.setFret(1, trackID: "guitar", noteID: e2.id)
        let afterOne = editor.score
        try editor.setHit(.tom, at: GridPoint(beat: 3, tick: 9), present: true, trackID: "drums")
        try editor.deleteNote(trackID: "bass", noteID: editor.score.tracks[1].notes[2].id)
        XCTAssertTrue(editor.undo())
        XCTAssertTrue(editor.undo())
        XCTAssertEqual(editor.score, afterOne)
        try editor.setDuration(6, trackID: "guitar", noteID: e2.id)
        XCTAssertFalse(editor.canRedo)
        XCTAssertTrue(editor.undo())
        XCTAssertTrue(editor.undo())
        XCTAssertEqual(editor.score, original)
        XCTAssertFalse(editor.undo())
    }

    func testMoveStringKeepsPitchAndRefusesOutOfRange() throws {
        var editor = TabEditor(score: try Self.score())
        let c4 = note(editor, pitch: 60, beat: 4)               // Do4 en el traste 1 de la 2.ª
        try editor.moveNote(trackID: "guitar", noteID: c4.id, toString: 4)
        let moved = note(editor, pitch: 60, beat: 4)
        XCTAssertEqual(moved.pitch, 60)
        XCTAssertEqual(moved.string, 4)
        XCTAssertEqual(editor.score.tracks[0].fret(of: moved), 10)
        // Do4 en la 1.ª (Mi4) sería traste −4; en la 6.ª (Mi2), 20 (vale).
        let before = editor.score
        XCTAssertThrowsError(try editor.moveNote(trackID: "guitar", noteID: c4.id, toString: 1)) {
            XCTAssertEqual($0 as? TabEditError, .fretOutOfRange)
        }
        XCTAssertEqual(editor.score, before)
        try editor.moveNote(trackID: "guitar", noteID: c4.id, toString: 6)
        XCTAssertEqual(editor.score.tracks[0].fret(of: note(editor, pitch: 60, beat: 4)), 20)
        // Mi2 (40) a la 1.ª: traste −24, se niega; a la 7.ª, no existe.
        let e2 = note(editor, pitch: 40, beat: 0)
        XCTAssertThrowsError(try editor.moveNote(trackID: "guitar", noteID: e2.id, toString: 1))
        XCTAssertThrowsError(try editor.moveNote(trackID: "guitar", noteID: e2.id, toString: 7)) {
            XCTAssertEqual($0 as? TabEditError, .stringOutOfRange)
        }
        // Una cuerda ya ocupada en el mismo acorde: Si3 (59) de la 2.ª a la 3.ª (traste 4), ocupada por Sol#3.
        let b3 = note(editor, pitch: 59, beat: 0)
        XCTAssertThrowsError(try editor.moveNote(trackID: "guitar", noteID: b3.id, toString: 3)) {
            XCTAssertEqual($0 as? TabEditError, .stringOccupied)
        }
    }

    func testInvalidEditsAreRefusedWithoutUndoStep() throws {
        var editor = TabEditor(score: try Self.score())
        let original = editor.score
        let e2 = note(editor, pitch: 40, beat: 0)
        XCTAssertThrowsError(try editor.setFret(25, trackID: "guitar", noteID: e2.id)) {
            XCTAssertEqual($0 as? TabEditError, .fretOutOfRange)
        }
        XCTAssertThrowsError(try editor.setDuration(0, trackID: "guitar", noteID: e2.id)) {
            XCTAssertEqual($0 as? TabEditError, .invalidDuration)
        }
        // El pulso 4 está en tresillo: el tick 3 no es un punto suyo, y una nota del pulso 3 no puede acabar en él.
        XCTAssertEqual(editor.score.tracks[0].subdivisions[4], .eighthTriplets)
        XCTAssertThrowsError(try editor.addNote(trackID: "guitar", string: 1, fret: 0, at: GridPoint(beat: 4, tick: 3), duration: 4)) {
            XCTAssertEqual($0 as? TabEditError, .invalidPosition)
        }
        XCTAssertThrowsError(try editor.addNote(trackID: "guitar", string: 1, fret: 0, at: GridPoint(beat: 3, tick: 0), duration: 15)) {
            XCTAssertEqual($0 as? TabEditError, .invalidDuration)
        }
        XCTAssertThrowsError(try editor.addNote(trackID: "guitar", string: 1, fret: 0, at: GridPoint(beat: 0, tick: 0), duration: 3)) {
            XCTAssertEqual($0 as? TabEditError, .stringOccupied)
        }
        XCTAssertThrowsError(try editor.setHit(.kick, at: GridPoint(beat: 0, tick: 0), present: true, trackID: "guitar")) {
            XCTAssertEqual($0 as? TabEditError, .wrongTrackKind)
        }
        XCTAssertThrowsError(try editor.deleteNote(trackID: "nope", noteID: 1)) {
            XCTAssertEqual($0 as? TabEditError, .unknownTrack)
        }
        XCTAssertThrowsError(try editor.deleteNote(trackID: "guitar", noteID: 999)) {
            XCTAssertEqual($0 as? TabEditError, .unknownNote)
        }
        // Poner un golpe que ya está no cambia nada ni ocupa un paso.
        try editor.setHit(.kick, at: GridPoint(beat: 0, tick: 0), present: true, trackID: "drums")
        XCTAssertEqual(editor.score, original)
        XCTAssertFalse(editor.canUndo)
    }

    func testAddNoteAtCursorAndScoreJSONRoundTrip() throws {
        var editor = TabEditor(score: try Self.score())
        let track = editor.score.tracks[0]
        // Cursor a 6,13 s: pulso 12 (6,0–6,5 s), semicorchea más cercana = tick 3 (6,125 s).
        let point = editor.score.nearestPoint(to: 6.13, in: track)
        XCTAssertEqual(point, GridPoint(beat: 12, tick: 3))
        let id = try editor.addNote(trackID: "guitar", string: 2, fret: 3, at: point, duration: 9)
        let added = editor.score.tracks[0].notes.first { $0.id == id }!
        XCTAssertEqual(added.pitch, 62)
        XCTAssertEqual(editor.score.timeRange(of: added).lowerBound, 6.125, accuracy: 1e-9)
        XCTAssertEqual(editor.score.timeRange(of: added).upperBound, 6.5, accuracy: 1e-9)   // 3 + 9 ticks = pulso 13
        XCTAssertEqual(Set(editor.score.tracks[0].notes.map(\.id)).count, editor.score.tracks[0].notes.count)

        let data = try Self.json(editor.score)
        XCTAssertEqual(try JSONDecoder().decode(TabScore.self, from: data), editor.score)
    }
}
