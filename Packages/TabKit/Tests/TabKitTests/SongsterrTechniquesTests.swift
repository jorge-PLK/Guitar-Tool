import Foundation
import XCTest
@testable import TabKit

/// Técnicas de Songsterr → `TabTechniques` (Fase 5b, adornos) con pistas inventadas, Codable aditivo del modelo y,
/// con `TF_P5B_TESTS=1`, el recuento real de El roce:
///   TF_P5B_TESTS=1 Tools/test.sh TabKit SongsterrTechniquesTests
final class SongsterrTechniquesTests: XCTestCase {
    typealias C = SongsterrConverterTests
    static let q = SongsterrTrack.ticksPerQuarter

    /// Una fusa por beat (caben 32 en el compás), una nota por beat (cuerda 2, traste 5): las técnicas de cada nota.
    static func techniques(_ beats: [(note: [String: Any], beat: [String: Any])]) throws -> [TabTechniques] {
        let t = try C.track([C.measure(beats.map { C.beat([1, 32], [C.note(2, 5, $0.note)], $0.beat) })])
        XCTAssertEqual(t.notes.count, beats.count)
        return t.notes.map(\.techniques)
    }

    static func make(_ set: (inout TabTechniques) -> Void) -> TabTechniques {
        var t = TabTechniques()
        set(&t)
        return t
    }

    static func bend(_ points: [(Int, Int)]) -> [String: Any] {
        ["tone": points.map(\.1).max() ?? 0, "points": points.map { ["position": $0.0, "tone": $0.1] }]
    }

    static func points(_ list: [(Int, Int)]) -> [TabBendPoint] { list.map { TabBendPoint(position: $0.0, value: $0.1) } }

    // MARK: - Una técnica por nota

    func testPalmMuteLetRingVibratoAndArticulations() throws {
        let got = try Self.techniques([
            ([:], ["palmMute": true]),
            ([:], ["letRing": true]),
            (["vibrato": true], ["vibrato": true]),
            (["wideVibrato": true], [:]),
            (["leftHandVibrato": "slight"], [:]),
            (["leftHandVibrato": "wide"], [:]),
            ([:], ["vibratoWithTremoloBar": "wide"]),
            (["hp": true], [:]),
            (["dead": true], [:]),
            (["ghost": true], [:]),
            (["accentuated": 1], [:]),
            (["accentuated": 2], [:]),
            (["accentuated": true], [:]),
            (["staccato": true], [:]),
            ([:], ["pickStroke": "down"]),
            ([:], ["pickStroke": "up"]),
            ([:], ["brushStroke": ["direction": "down", "duration": 30, "shift": 100]]),
        ])
        let expected: [TabTechniques] = [
            Self.make { $0.palmMute = true },
            Self.make { $0.letRing = true },
            Self.make { $0.vibrato = .slight },
            Self.make { $0.vibrato = .wide },
            Self.make { $0.vibrato = .slight },
            Self.make { $0.vibrato = .wide },
            Self.make { $0.vibrato = .wide },
            Self.make { $0.hammerPull = true },
            Self.make { $0.dead = true },
            Self.make { $0.ghost = true },
            Self.make { $0.accent = .normal },
            Self.make { $0.accent = .heavy },
            Self.make { $0.accent = .normal },
            Self.make { $0.staccato = true },
            Self.make { $0.pickStroke = .down },
            Self.make { $0.pickStroke = .up },
            Self.make { $0.brush = .down },
        ]
        XCTAssertEqual(got.count, expected.count)
        for (i, (g, e)) in zip(got, expected).enumerated() { XCTAssertEqual(g, e, "nota \(i)") }
    }

    /// Los seis slides de Songsterr (los cuatro que salen en Tornado más los del conversor de referencia).
    func testSlides() throws {
        let values = ["shift", "legato", "below", "into_from_above", "downwards", "out_up"]
        let got = try Self.techniques(values.map { (["slide": $0], [:]) })
        XCTAssertEqual(got.map(\.slideOut), [.shift, .legato, nil, nil, .outDown, .outUp])
        XCTAssertEqual(got.map(\.slideIn), [nil, nil, .intoFromBelow, .intoFromAbove, nil, nil])
    }

    func testHarmonicsKeepTypeAndFret() throws {
        let got = try Self.techniques([
            (["harmonic": "natural", "harmonicFret": 12], [:]),
            (["harmonic": "artificial", "harmonicFret": 7], [:]),
            (["harmonic": "pinch", "harmonicFret": 24], [:]),
            (["harmonic": "tap"], [:]),
            (["harmonic": "semi", "harmonicFret": 2.4], [:]),
        ])
        XCTAssertEqual(got.map(\.harmonic), [TabHarmonic(type: .natural, fret: 12), TabHarmonic(type: .artificial, fret: 7),
                                             TabHarmonic(type: .pinch, fret: 24), TabHarmonic(type: .tap),
                                             TabHarmonic(type: .semi, fret: 2.4)])
    }

    /// Curvas reales de El roce y Tornado: `tone` 100 = 4 cuartos de tono; el tipo sale de la forma.
    func testBendCurvesAndKinds() throws {
        let shapes: [[(Int, Int)]] = [
            [(0, 0), (60, 100)],                       // bend de un tono
            [(0, 0), (30, 100), (60, 0)],              // bend-release
            [(0, 100), (60, 100)],                     // pre-bend
            [(0, 100), (60, 0)],                       // pre-bend y release
            [(0, 50), (30, 50), (60, 100)],            // pre-bend y bend
            [(0, 0), (30, 150), (60, 0)],              // tono y medio (Tornado)
            [(0, 0), (20, 100), (40, 0), (60, 100)],   // custom
            [(0, 0), (60, 0)],                         // plana: sin bend
        ]
        let got = try Self.techniques(shapes.map { (["bend": Self.bend($0)], [:]) }).map(\.bend)
        XCTAssertEqual(got.map { $0?.type }, [.bend, .bendRelease, .prebend, .prebendRelease, .prebendBend, .bendRelease,
                                              .custom, nil])
        XCTAssertEqual(got[0]?.points, Self.points([(0, 0), (60, 4)]))
        XCTAssertEqual(got[1]?.points, Self.points([(0, 0), (30, 4), (60, 0)]))
        XCTAssertEqual(got[4]?.points, Self.points([(0, 2), (30, 2), (60, 4)]))
        XCTAssertEqual(got[5]?.points, Self.points([(0, 0), (30, 6), (60, 0)]))
        XCTAssertEqual(got[6]?.points, Self.points([(0, 0), (20, 4), (40, 0), (60, 4)]))
    }

    // MARK: - Ligaduras

    /// Negra bend 0→1 tono, ligada a negra quieta y a negra que suelta: una nota de tres negras con la curva
    /// encadenada (cada negra = 20 de 60). La ligada pasa su vibrato, su ligado y su slide; el ghost es del ataque.
    func testTiedNotesChainBendAndKeepSustainedTechniques() throws {
        let q = Self.q
        let t = try C.track([C.measure([
            C.beat([1, 4], [C.note(2, 7, ["bend": Self.bend([(0, 0), (60, 100)]), "ghost": true])]),
            C.beat([1, 4], [C.note(2, 7, ["tie": true, "bend": Self.bend([(0, 100), (60, 100)]), "leftHandVibrato": "wide"])]),
            C.beat([1, 4], [C.note(2, 7, ["tie": true, "bend": Self.bend([(0, 100), (60, 0)]), "hp": true, "slide": "legato",
                                          "dead": true])]),
            C.beat([1, 4], [C.note(2, 5)]),
        ])])
        XCTAssertEqual(t.notes.count, 2)
        let n = t.notes[0]
        XCTAssertEqual(n.duration, 3 * q)
        XCTAssertEqual(n.techniques.bend, TabBend(type: .bendRelease, points: Self.points([(0, 0), (20, 4), (40, 4), (60, 0)])))
        XCTAssertEqual(n.techniques.vibrato, .wide)
        XCTAssertTrue(n.techniques.hammerPull)
        XCTAssertEqual(n.techniques.slideOut, .legato)
        XCTAssertTrue(n.techniques.ghost)
        XCTAssertFalse(n.techniques.dead)
        XCTAssertEqual(t.report.techniques, [.bend: 1, .vibrato: 1, .slide: 1, .hammerPull: 1, .ghost: 1])
        XCTAssertEqual(t.report.notesWithOrnaments, 0)
    }

    /// Ligada sin bend tras un bend: lo mantiene. Bend solo en la ligada: empieza a mitad de la nota.
    func testTiedBendHoldAndLateBend() throws {
        let t = try C.track([C.measure([
            C.beat([1, 4], [C.note(2, 7, ["bend": Self.bend([(0, 0), (60, 100)])])]),
            C.beat([1, 4], [C.note(2, 7, ["tie": true])]),
            C.beat([1, 4], [C.note(1, 8)]),
            C.beat([1, 4], [C.note(1, 8, ["tie": true, "bend": Self.bend([(0, 0), (60, 50)])])]),
        ])])
        XCTAssertEqual(t.notes.map(\.techniques.bend), [
            TabBend(type: .bend, points: Self.points([(0, 0), (30, 4), (60, 4)])),
            TabBend(type: .bend, points: Self.points([(0, 0), (30, 0), (60, 2)])),
        ])
    }

    // MARK: - Notas de adorno, rasgueo y trémolo

    /// La nota de adorno va en la principal de su cuerda (siguiente beat de la voz, también en el compás siguiente),
    /// sin ocupar tiempo: tipo, figura, slide, ligado y muerta. Sin principal en su cuerda, en la de la cuerda más
    /// cercana con su cuerda; varias seguidas, cada una en su beat de adorno (`step`). Sin beat con notas detrás
    /// (silencio, final del tema) se cuenta.
    func testGraceNotesAttachToMainNote() throws {
        let q = Self.q
        let t = try C.track([
            C.measure([
                // Dos de adorno (Tornado: acorde de dos con slide) delante de su acorde.
                C.beat([1, 16], [C.note(3, 4, ["slide": "legato"]), C.note(4, 2, ["slide": "legato"])], ["graceNote": "onBeat"]),
                C.beat([1, 4], [C.note(3, 5), C.note(4, 3)]),
                C.beat([1, 32], [C.note(1, 5, ["hp": true])], ["graceNote": "beforeBeat"]),
                C.beat([1, 4], [C.note(1, 7)]),
                C.beat([1, 64], [C.note(2, 3, ["dead": true]), C.note(5, 0)], ["graceNote": "onBeat"]),  // la 5, a la 2
                C.beat([1, 4], [C.note(2, 5)]),
                C.rest([1, 4]),
                C.beat([1, 32], [C.note(0, 3, ["bend": Self.bend([(0, 0), (60, 100)])])], ["graceNote": "beforeBeat"]),
            ]),
            C.measure([
                C.beat([1, 4], [C.note(0, 5)]),
                C.beat([1, 32], [C.note(1, 1)], ["graceNote": "onBeat"]),
                C.beat([1, 32], [C.note(1, 2)], ["graceNote": "onBeat"]),  // dos seguidas en la misma cuerda
                C.beat([1, 4], [C.note(1, 3)]),
                C.beat([1, 32], [C.note(1, 1)], ["graceNote": "onBeat"]),
                C.rest([1, 4]),                                              // silencio: se pierde
                C.beat([1, 32], [C.note(1, 1)], ["graceNote": "onBeat"]),  // final del tema: se pierde
            ]),
        ])
        XCTAssertEqual(t.notes.map(\.start), [0, 0, q, 2 * q, 4 * q, 5 * q], "las de adorno no ocupan tiempo")
        XCTAssertEqual(t.notes.map(\.techniques.graces), [
            [TabGrace(fret: 4, type: .onBeat, duration: 16, slide: true)],
            [TabGrace(fret: 2, type: .onBeat, duration: 16, slide: true)],
            [TabGrace(fret: 5, type: .beforeBeat, duration: 32, hammerPull: true)],
            [TabGrace(fret: 3, type: .onBeat, duration: 64, dead: true),
             TabGrace(fret: 0, type: .onBeat, duration: 64, string: 6)],
            [TabGrace(fret: 3, type: .bendGrace, duration: 32)],
            [TabGrace(fret: 1, type: .onBeat, duration: 32, step: 2), TabGrace(fret: 2, type: .onBeat, duration: 32)],
        ])
        XCTAssertEqual(t.notes.map(\.string), [4, 5, 2, 3, 1, 2])
        XCTAssertEqual(t.report.techniques, [.grace: 6])
        XCTAssertEqual(t.report.ornaments, [.graceNote: 2])
        XCTAssertEqual(t.report.notesWithOrnaments, 2)
    }

    /// Rastrillo de Tornado: dos notas de adorno muertas en las cuerdas 3 y 2, una tras otra, delante de una nota en la
    /// 1 (en un acorde con la 4, la más cercana a la 3 es la 4 y se queda la 2 en la 1). Ninguna se pierde.
    func testRakeGoesToTheNearestMainNoteWithItsStrings() throws {
        let t = try C.track([C.measure([
            C.beat([1, 32], [C.note(2, 0, ["dead": true])], ["graceNote": "beforeBeat"]),
            C.beat([1, 32], [C.note(1, 0, ["dead": true])], ["graceNote": "beforeBeat"]),
            C.beat([1, 2], [C.note(0, 5)]),
            C.beat([1, 32], [C.note(2, 0, ["dead": true])], ["graceNote": "beforeBeat"]),
            C.beat([1, 32], [C.note(1, 0, ["dead": true])], ["graceNote": "beforeBeat"]),
            C.beat([1, 2], [C.note(0, 5), C.note(3, 7)]),
        ])])
        XCTAssertEqual(t.notes.map(\.string), [1, 1, 4])
        XCTAssertEqual(t.notes[0].techniques.graces, [
            TabGrace(fret: 0, type: .beforeBeat, duration: 32, dead: true, string: 3, step: 2),
            TabGrace(fret: 0, type: .beforeBeat, duration: 32, dead: true, string: 2, step: 1),
        ])
        XCTAssertEqual(t.notes[1].techniques.graces,
                       [TabGrace(fret: 0, type: .beforeBeat, duration: 32, dead: true, string: 2, step: 1)])
        XCTAssertEqual(t.notes[2].techniques.graces,
                       [TabGrace(fret: 0, type: .beforeBeat, duration: 32, dead: true, string: 3, step: 2)])
        XCTAssertEqual(t.report.ornaments, [:])
        XCTAssertEqual(t.report.techniques, [.grace: 3])
    }

    /// Flam de batería (Tornado y la referencia: caja de adorno en fusa de 64 delante de la caja): en el golpe de su
    /// misma pieza, con su nota GM. Delante de otra pieza se cuenta.
    func testDrumFlamAttachesToSamePiece() throws {
        let flam: [String: Any] = ["notes": [["fret": 38, "string": 1.5]], "graceNote": "onBeat", "duration": [1, 64]]
        let drums: [String: Any] = ["name": "Drums", "instrumentId": 1024, "measures": [C.measure([
            flam, C.beat([1, 4], [["fret": 38, "string": 1.5, "accentuated": 1]]),
            flam, C.beat([1, 4], [["fret": 36, "string": 0]]),
            C.rest([1, 2]),
        ])]]
        let d = try SongsterrTrackConverter.convert(try JSONSerialization.data(withJSONObject: drums))
        XCTAssertEqual(d.hits.map(\.piece), [.snare, .kick])
        XCTAssertEqual(d.hits.map(\.grace), [TabGrace(fret: 38, type: .onBeat, duration: 64), nil])
        XCTAssertEqual(d.hits.map(\.accent), [.normal, nil])  // el acento de la caja va al golpe
        XCTAssertEqual(d.report.techniques, [.grace: 1, .accent: 1])
        XCTAssertEqual(d.report.ornaments, [.graceNote: 1])
    }

    /// `upStroke`/`downStroke` son la flecha del rasgueo de Guitar Pro: en los datos de referencia van siempre con
    /// `brushStroke` hacia abajo (437 de 437) y hacia arriba (216 de 216). Solos, dan el mismo rasgueo.
    func testStrokesAndTremoloPicking() throws {
        let got = try Self.techniques([
            ([:], ["upStroke": 1, "brushStroke": ["direction": "down", "duration": 30, "shift": 100]]),
            ([:], ["downStroke": 1, "brushStroke": ["direction": "up", "duration": 30, "shift": 100]]),
            ([:], ["upStroke": 1]),
            ([:], ["downStroke": 1]),
            ([:], ["tremolo": [1, 32]]),
            ([:], ["tremolo": [1, 16]]),
            ([:], ["tremolo": [1, 8]]),
        ])
        XCTAssertEqual(got.map(\.brush), [.down, .up, .down, .up, nil, nil, nil])
        XCTAssertEqual(got.map(\.tremoloPicking), [nil, nil, nil, nil, .thirtySecond, .sixteenth, .eighth])

        let odd = try C.track([C.measure([C.beat([1, 4], [C.note(0, 0)], ["tremolo": [1, 12]])])])
        XCTAssertNil(odd.notes[0].techniques.tremoloPicking)
        XCTAssertEqual(odd.report.ornaments, [.unknownTremolo: 1])
    }

    // MARK: - Lo que sigue sin representarse

    /// Valores desconocidos de slide y armónico, claves desconocidas (por nombre y por nota) y técnicas de guitarra
    /// en batería: van al aviso. Ritmo, vigas y dinámica no.
    func testUnrepresentedAreCountedByKind() throws {
        let t = try C.track([C.measure([
            C.beat([1, 8], [C.note(2, 5, ["slide": "sideways"])]),
            C.beat([1, 8], [C.note(2, 5, ["harmonic": "whistle"])]),
            C.beat([1, 8], [C.note(0, 0), C.note(1, 1)], ["fooBeat": 1, "beamStart": true, "velocity": "mf",
                                                          "chord": ["text": "Am", "width": 21]]),
            C.beat([1, 8], [C.note(2, 5, ["fooBar": 3, "slide": "shift"])]),
            C.beat([1, 32], [C.note(2, 4)], ["graceNote": "onBeat"]),
        ])])
        XCTAssertEqual(t.report.ornaments, [.unknownSlide: 1, .unknownHarmonic: 1, .unknownKey: 3, .graceNote: 1])
        XCTAssertEqual(t.report.unknownKeys, ["beat.fooBeat": 2, "note.fooBar": 1])
        XCTAssertEqual(t.report.notesWithOrnaments, 6)
        XCTAssertEqual(t.report.techniques, [.slide: 1])

        let drums: [String: Any] = ["name": "Drums", "instrumentId": 1024, "measures": [C.measure([
            C.beat([1, 4], [["string": 0, "fret": 38, "ghost": true], ["string": 0, "fret": 40]]),  // misma caja
            C.beat([1, 4], [["string": 0, "fret": 42, "accentuated": 2]]),
            C.beat([1, 4], [["string": 0, "fret": 36, "ghost": true]]),
            C.beat([1, 4], [["string": 0, "fret": 49, "staccato": true]]),
        ])]]
        let d = try SongsterrTrackConverter.convert(try JSONSerialization.data(withJSONObject: drums))
        XCTAssertEqual(d.hits.map(\.piece), [.snare, .hiHat, .kick, .crash])
        XCTAssertEqual(d.hits.map(\.ghost), [false, false, true, false])  // la caja con uno normal no es fantasma
        XCTAssertEqual(d.hits.map(\.accent), [nil, .heavy, nil, nil])
        XCTAssertEqual(d.report.ornaments, [.drumTechnique: 1])  // el staccato del plato: sin sitio
        XCTAssertEqual(d.report.techniques, [.ghost: 1, .accent: 1])
    }

    /// Cada tipo sin representar tiene su nombre en el aviso.
    func testOrnamentLabelsAreDistinct() throws {
        let label = SongsterrOrnament.allCases.map(SongsterrImportPlan.label)
        XCTAssertEqual(Set(label).count, SongsterrOrnament.allCases.count)
    }

    // MARK: - Codable aditivo

    /// Un JSON de antes de las técnicas se lee sin ellas; uno sin técnicas se escribe como antes (sin la clave); con
    /// técnicas, ida y vuelta idéntica.
    func testOldJSONDecodesWithoutTechniques() throws {
        let old = #"{"id":3,"pitch":64,"string":1,"start":{"beat":2,"tick":6},"duration":12,"amplitude":0.5}"#
        let note = try JSONDecoder().decode(TabNote.self, from: Data(old.utf8))
        XCTAssertEqual(note, TabNote(id: 3, pitch: 64, string: 1, start: GridPoint(beat: 2, tick: 6), duration: 12, amplitude: 0.5))
        XCTAssertTrue(note.techniques.isEmpty)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        XCTAssertFalse(String(decoding: try enc.encode(note), as: UTF8.self).contains("techniques"))

        let oldHit = #"{"piece":38,"at":{"beat":1,"tick":0}}"#
        let hit = try JSONDecoder().decode(TabDrumHit.self, from: Data(oldHit.utf8))
        XCTAssertFalse(hit.ghost)
        XCTAssertEqual(String(decoding: try enc.encode(hit), as: UTF8.self), #"{"at":{"beat":1,"tick":0},"piece":38}"#)

        let partial = try JSONDecoder().decode(TabTechniques.self, from: Data(#"{"palmMute":true}"#.utf8))
        XCTAssertEqual(partial, Self.make { $0.palmMute = true })

        var full = note
        full.techniques = Self.make {
            $0.palmMute = true; $0.letRing = true; $0.vibrato = .wide
            $0.bend = TabBend(type: .bendRelease, points: Self.points([(0, 0), (30, 4), (60, 0)]))
            $0.slideIn = .intoFromBelow; $0.slideOut = .legato; $0.hammerPull = true
            $0.harmonic = TabHarmonic(type: .natural, fret: 12); $0.dead = true; $0.ghost = true; $0.accent = .heavy
            $0.staccato = true; $0.tapping = true; $0.tremoloPicking = .sixteenth
            $0.whammy = TabBend(type: .custom, points: Self.points([(0, 0), (60, -8)]))
            $0.pickStroke = .up; $0.brush = .down
            $0.graces = [TabGrace(fret: 0, type: .beforeBeat, dead: true, string: 4, step: 2),
                         TabGrace(fret: 3, type: .beforeBeat, duration: 32, slide: true, hammerPull: true, dead: true)]
        }
        XCTAssertEqual(full.techniques.kinds, TabTechniqueKind.allCases)
        XCTAssertEqual(try JSONDecoder().decode(TabNote.self, from: try enc.encode(full)), full)
        let ghostHit = TabDrumHit(piece: .snare, at: GridPoint(beat: 1, tick: 0), ghost: true,
                                  grace: TabGrace(fret: 38, type: .onBeat, duration: 64), accent: .heavy)
        XCTAssertEqual(try JSONDecoder().decode(TabDrumHit.self, from: try enc.encode(ghostHit)), ghostHit)
    }

    /// Un golpe fantasma es el mismo golpe para la edición: ponerlo no lo duplica y quitarlo lo quita.
    func testEditorTreatsGhostHitAsSameHit() throws {
        var score = try TabEditorTests.score()
        let drums = score.trackIndex(id: "drums")!
        let snare = score.tracks[drums].hits.firstIndex { $0.piece == .snare }!
        score.tracks[drums].hits[snare].ghost = true
        let at = score.tracks[drums].hits[snare].at
        var editor = TabEditor(score: score)
        try editor.setHit(.snare, at: at, present: true, trackID: "drums")
        XCTAssertEqual(editor.score.tracks[drums].hits.filter { $0.piece == .snare }.map(\.ghost), [true])
        try editor.setHit(.snare, at: at, present: false, trackID: "drums")
        XCTAssertTrue(editor.score.tracks[drums].hits.filter { $0.piece == .snare }.isEmpty)
    }

    // MARK: - El roce (solo en local)

    /// Recuento real de las pistas de El roce en caché: técnicas importadas por tipo y lo que queda sin representar.
    func testRoceTechniqueCounts() throws {
        guard ProcessInfo.processInfo.environment["TF_P5B_TESTS"] == "1" else {
            throw XCTSkip("recuento de El roce desactivado (TF_P5B_TESTS != 1)")
        }
        let dir = SongsterrAlignmentRoceTests.project.appendingPathComponent("cache/songsterr/50624/6707291")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: dir.path), "falta \(dir.path)")
        var imported: [TabTechniqueKind: Int] = [:]
        var missing: [SongsterrOrnament: Int] = [:]
        var keys: [String: Int] = [:]
        var notes = 0, withMissing = 0
        for part in 0..<4 {
            let url = dir.appendingPathComponent("\(part).json")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let t = try SongsterrTrackConverter.convert(try Data(contentsOf: url))
            let r = t.report
            print("ROCE técnicas «\(t.name)» \(t.kind): \(t.notes.count + t.hits.count) notas;",
                  "importadas \(TabTechniqueKind.allCases.compactMap { k in r.techniques[k].map { "\(k.rawValue) \($0)" } });",
                  "sin representar \(r.notesWithOrnaments) \(r.ornaments) \(r.unknownKeys)")
            imported.merge(r.techniques, uniquingKeysWith: +)
            missing.merge(r.ornaments, uniquingKeysWith: +)
            keys.merge(r.unknownKeys, uniquingKeysWith: +)
            notes += t.notes.count + t.hits.count
            withMissing += r.notesWithOrnaments
        }
        print("ROCE total: \(notes) notas; importadas",
              TabTechniqueKind.allCases.compactMap { k in imported[k].map { "\(k.rawValue) \($0)" } }.joined(separator: ", "),
              "| sin representar \(withMissing) notas: \(missing) \(keys)")
        // Antes se perdían palm mute 777, ghost 412, let ring 215, bend 54, slide 9 y vibrato 4, contados por nota de
        // Songsterr. Ahora se cuentan por nota importada: las ligadas van dentro de su nota (2 let ring y 4 bends) y
        // 46 ghost de plato caen en el mismo punto que un plato normal (un golpe por pieza y punto, no fantasma).
        XCTAssertEqual(imported, [.palmMute: 777, .letRing: 213, .vibrato: 4, .bend: 50, .slide: 9, .ghost: 366, .brush: 9])
        // `upStroke` (2 rasgueos de 6 y 3 notas) es la flecha del mismo `brushStroke` hacia abajo: nada sin representar.
        XCTAssertEqual(missing, [:])
        XCTAssertEqual(keys, [:])
        XCTAssertEqual(withMissing, 0)

        // Tornado Of Souls, solo informativo (su alineación la revisa otra prueba).
        let tornado = P5BProjects.project("Megadeth - Tornado Of Souls").appendingPathComponent("cache/songsterr/12824/10230610")
        var tImported: [TabTechniqueKind: Int] = [:], tMissing: [SongsterrOrnament: Int] = [:], tKeys: [String: Int] = [:]
        var tWith = 0
        for part in 0..<12 {
            let url = tornado.appendingPathComponent("\(part).json")
            guard let data = try? Data(contentsOf: url) else { continue }
            let r = try SongsterrTrackConverter.convert(data).report
            tImported.merge(r.techniques, uniquingKeysWith: +)
            tMissing.merge(r.ornaments, uniquingKeysWith: +)
            tKeys.merge(r.unknownKeys, uniquingKeysWith: +)
            tWith += r.notesWithOrnaments
        }
        print("TORNADO total: importadas",
              TabTechniqueKind.allCases.compactMap { k in tImported[k].map { "\(k.rawValue) \($0)" } }.joined(separator: ", "),
              "| sin representar \(tWith) notas: \(tMissing) \(tKeys)")
        guard !tImported.isEmpty else { return }
        // 74 notas de guitarra con adornos + 14 flams de caja. El rastrillo (dos notas de adorno muertas en las cuerdas
        // 3 y 2, una tras otra, delante de una nota en la 1) va en la nota de la 1 con sus cuerdas: nada sin representar.
        XCTAssertEqual(tImported[.grace], 88)
        XCTAssertEqual(tMissing, [:])
        XCTAssertEqual(tWith, 0)
        XCTAssertEqual(tKeys, [:])
    }
}
