import Foundation
import XCTest
@testable import TabKit

/// Voces de Songsterr y nombres de pista (mini-spec Fase 5c, decisiones 4 y 5). Datos sintéticos.
final class TabVocalTests: XCTestCase {
    // MARK: Detección

    private func converted(name: String, instrumentId: Int, instrument: String) throws -> SongsterrTrack {
        let measure = SongsterrConverterTests.measure([
            SongsterrConverterTests.beat([1, 4], [SongsterrConverterTests.note(0, 3)]), SongsterrConverterTests.rest([3, 4]),
        ])
        var root: [String: Any] = ["name": name, "instrumentId": instrumentId, "instrument": instrument,
                                   "strings": 6, "tuning": SongsterrConverterTests.standard, "measures": [measure]]
        root["songId"] = 1
        return try SongsterrTrackConverter.convert(try JSONSerialization.data(withJSONObject: root))
    }

    /// Los tres temas de la 5b traen las voces como saxos (66, 67) con «Vocals» en el nombre: se reconocen por nombre;
    /// el instrumento 52–54 vale sin nombre.
    func testVocalDetectionByInstrumentAndName() throws {
        XCTAssertEqual(try converted(name: "Vocals", instrumentId: 66, instrument: "Tenor Sax").kind, .vocal)
        XCTAssertEqual(try converted(name: "Dave Mustaine | Lead Vocals", instrumentId: 67, instrument: "Baritone Sax").kind, .vocal)
        XCTAssertEqual(try converted(name: "Dave Mustaine & David Ellefson | Backing Vocals", instrumentId: 67,
                                     instrument: "Baritone Sax").kind, .vocal)
        XCTAssertEqual(try converted(name: "", instrumentId: 53, instrument: "Voice Oohs").kind, .vocal)
        XCTAssertEqual(try converted(name: "Coro", instrumentId: 30, instrument: "Distortion Guitar").kind, .vocal)
        // Lo que no es voz sigue como estaba.
        XCTAssertEqual(try converted(name: "Lead Guitar", instrumentId: 30, instrument: "Distortion Guitar").kind, .guitar)
        XCTAssertEqual(try converted(name: "", instrumentId: 33, instrument: "Electric Bass (finger)").kind, .bass)
        XCTAssertEqual(try converted(name: "Fito", instrumentId: 30, instrument: "Distortion Guitar").kind, .guitar)
    }

    /// La voz conserva la altura MIDI de la nota (con la afinación ficticia de Songsterr) y no tiene afinación.
    func testVocalKeepsPitchAndHasNoTuning() throws {
        let t = try converted(name: "Vocals", instrumentId: 66, instrument: "Tenor Sax")
        XCTAssertNil(t.tuning)
        XCTAssertEqual(t.notes.map(\.pitch), [67])   // cuerda 0 = 64, traste 3
        XCTAssertEqual(t.instrumentId, 66)
    }

    /// Una voz no se empareja con ningún stem: sale como pista extra.
    func testVocalIsNeverPairedWithAStemAndIsExtra() {
        let tracks = [
            SongsterrImportPlanTests.track("Lead", .guitar, partId: 0), SongsterrImportPlanTests.track("Vocals", .vocal, partId: 1),
            SongsterrImportPlanTests.track("Bass", .bass, partId: 2), SongsterrImportPlanTests.track("Drums", .drums, partId: 3),
        ]
        let plan = SongsterrImportPlanTests.plan(pairs: [], tracks: tracks)
        for slot in SongsterrImportPlanTests.slots {
            XCTAssertFalse(plan.choices(for: slot.id).contains { $0.track == 1 }, slot.id)
        }
        XCTAssertTrue(plan.extraTracks.contains(1))
        XCTAssertFalse(plan.assignments.contains { $0.track == 1 })
        var edited = plan
        XCTAssertFalse(edited.assign(stemID: "bass", track: 1))
        let built = plan.build()
        XCTAssertTrue(built.extraTrackIDs.contains(SongsterrImportPlan.extraID(1)))
    }

    // MARK: Nombres

    func testEmptyNamesTakeTheInstrumentNameWithNumbers() {
        let names = TabTrackNames.resolve([
            ("Lead Guitar", .guitar), ("", .guitar), ("", .guitar), ("", .bass), ("   ", .drums), ("", .vocal), ("", .vocal),
        ])
        XCTAssertEqual(names, ["Lead Guitar", "Guitarra", "Guitarra 2", "Bajo", "Batería", "Voz", "Voz 2"])
    }

    func testPlanChoicesUseResolvedNames() {
        let tracks = [
            SongsterrImportPlanTests.track("", .guitar, partId: 0), SongsterrImportPlanTests.track("", .guitar, partId: 1),
            SongsterrImportPlanTests.track("", .bass, partId: 2),
        ]
        let plan = SongsterrImportPlanTests.plan(pairs: [], tracks: tracks)
        XCTAssertEqual(plan.trackNames, ["Guitarra", "Guitarra 2", "Bajo"])
        XCTAssertEqual(plan.choices(for: "guitar-left").map(\.name), ["Guitarra", "Guitarra 2"])
        XCTAssertEqual(plan.choices(for: "bass").map(\.name), ["Bajo"])
    }

    // MARK: Partitura y puente

    private func scoreWithVocal(name: String = "", program: Int? = 66) throws -> TabScore {
        var score = try TabSynthTests.constantScore(bpm: 120, bars: 2)
        let subs = Array(repeating: Subdivision.sixteenths, count: score.beats.count)
        let notes = [
            TabNote(id: 1, pitch: 64, string: 1, start: GridPoint(beat: 0, tick: 0), duration: 12, amplitude: 1),
            TabNote(id: 2, pitch: 67, string: 1, start: GridPoint(beat: 1, tick: 0), duration: 24, amplitude: 1),
        ]
        score.upsert(TabTrack(id: "songsterr-4", name: name, kind: .vocal, tuning: nil, source: nil, subdivisions: subs,
                              notes: notes, program: program))
        score.upsert(TabTrack(id: "songsterr-0", name: "", kind: .guitar, tuning: .guitar(.standard), source: nil,
                              subdivisions: subs, notes: [TabSynthAdornmentTests.note(1, 45, string: 5, beat: 0)]))
        return score
    }

    private struct Doc: Decodable {
        struct Note: Decodable { var s: Int; var f: Int; var p: Int? }
        struct Beat: Decodable { var d: Int; var notes: [Note]? }
        struct Track: Decodable { var name: String; var kind: String; var tuning: [Int]?; var program: Int?; var bars: [[Beat]] }
        var tracks: [Track]
    }

    /// La voz va al JSON sin afinación, con la altura de cada nota y su programa; el nombre vacío pasa a «Voz».
    func testAlphaTabScoreVocalHasNoTabAndKeepsPitch() throws {
        let out = try AlphaTabExporter.make(score: try scoreWithVocal(), title: "T", artist: "A")
        let doc = try JSONDecoder().decode(Doc.self, from: Data(out.json.utf8))
        let vocal = try XCTUnwrap(doc.tracks.first { $0.kind == "vocal" })
        XCTAssertEqual(vocal.name, "Voz")
        XCTAssertNil(vocal.tuning)
        XCTAssertEqual(vocal.program, 66)
        let notes = vocal.bars.flatMap { $0 }.flatMap { $0.notes ?? [] }
        XCTAssertEqual(notes.compactMap(\.p), [64, 67])
        XCTAssertTrue(notes.allSatisfy { $0.s == 0 && $0.f == 0 })
        // La guitarra sin nombre pasa a «Guitarra» y lleva afinación.
        let guitar = try XCTUnwrap(doc.tracks.first { $0.kind == "guitar" })
        XCTAssertEqual(guitar.name, "Guitarra")
        XCTAssertEqual(guitar.tuning?.count, 6)
        XCTAssertNil(guitar.program)
        // Cada nota de la voz se puede volver a su `TabNote` desde el mapa de pulsos.
        let ti = try XCTUnwrap(out.trackIDs.firstIndex(of: "songsterr-4"))
        let ids = out.beats[ti].flatMap { $0 }.flatMap { $0.noteIDs.values }.sorted()
        XCTAssertEqual(ids, [1, 2])
    }

    /// El `.gp` y el puente de alphaTab se comprueban con `Probes/P5c-voces/check-vocal.js` (node, sin hardware); aquí,
    /// que el JSON lleva lo que ese script alimenta (`kind` y `program`) y nada de cuerdas.
    func testVocalRoundTripsThroughScoreJSONAndOldFilesDecode() throws {
        let score = try scoreWithVocal()
        let data = try JSONEncoder().encode(score)
        let back = try JSONDecoder().decode(TabScore.self, from: data)
        XCTAssertEqual(back.tracks, score.tracks)
        XCTAssertEqual(back.tracks.first { $0.kind == .vocal }?.program, 66)

        // Un score.json de antes de la 5c: sin `program` ni pistas de voz.
        var old = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var tracks = old["tracks"] as! [[String: Any]]
        tracks.removeAll { ($0["kind"] as? String) == "vocal" }
        for i in tracks.indices { tracks[i].removeValue(forKey: "program") }
        old["tracks"] = tracks
        let oldData = try JSONSerialization.data(withJSONObject: old)
        XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("\"program\""))
        let decoded = try JSONDecoder().decode(TabScore.self, from: oldData)
        XCTAssertEqual(decoded.tracks.map(\.kind), [.guitar])
        XCTAssertNil(decoded.tracks[0].program)
        // Y una pista sin `program` no lo escribe.
        let plain = try JSONEncoder().encode(decoded.tracks[0])
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("program"))
    }

    // MARK: Sintetizador

    /// La voz suena con su programa GM (o la voz «Oohs» si no trae ninguno) y por un solo canal, sin cuerdas.
    func testSynthUsesTrackProgramAndNoStringChannels() throws {
        let renderer = TabSynthRenderer(soundFontURL: URL(fileURLWithPath: "/dev/null"))
        XCTAssertEqual(renderer.instrument(for: try scoreWithVocal(program: 66).tracks[0]).program, 66)
        XCTAssertEqual(renderer.instrument(for: try scoreWithVocal(program: nil).tracks[0]).program, TabSynthRenderer.vocalProgram)
        XCTAssertEqual(renderer.instrument(for: .vocal).program, TabSynthRenderer.vocalProgram)

        let score = try scoreWithVocal()
        let vocal = try XCTUnwrap(score.tracks.first { $0.kind == .vocal })
        let events = TabSynthRenderer.events(track: vocal, in: score, sampleRate: 48_000, delayFrames: 0,
                                             totalFrames: 8 * 24_000)
        let ons = events.filter { $0.status & 0xF0 == 0x90 }
        XCTAssertEqual(ons.map(\.data1), [64, 67])
        XCTAssertTrue(events.allSatisfy { $0.status & 0x0F == 0 })
    }

    /// Una voz no admite cambio de afinación.
    func testVocalRejectsRetuning() throws {
        var editor = TabEditor(score: try scoreWithVocal())
        XCTAssertThrowsError(try editor.setTuning(.guitar(.standard), trackID: "songsterr-4"))
    }
}
