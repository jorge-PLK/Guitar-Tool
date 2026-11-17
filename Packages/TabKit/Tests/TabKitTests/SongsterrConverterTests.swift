import Foundation
import XCTest
@testable import TabKit

/// Conversor Songsterr → tiempo musical (mini-spec Fase 5b, «Código», parte 2). Pistas sintéticas hechas a mano.
final class SongsterrConverterTests: XCTestCase {
    static let q = SongsterrTrack.ticksPerQuarter
    static let standard = [64, 59, 55, 50, 45, 40]

    // MARK: - Pistas sintéticas

    static func note(_ string: Int, _ fret: Int, _ extra: [String: Any] = [:]) -> [String: Any] {
        ["string": string, "fret": fret].merging(extra) { $1 }
    }

    static func beat(_ duration: [Int], _ notes: [[String: Any]], _ extra: [String: Any] = [:]) -> [String: Any] {
        ["duration": duration, "notes": notes].merging(extra) { $1 }
    }

    static func rest(_ duration: [Int]) -> [String: Any] {
        ["duration": duration, "rest": true, "notes": [["rest": true]]]
    }

    static func measure(_ beats: [[String: Any]], _ extra: [String: Any] = [:]) -> [String: Any] {
        ["voices": [["beats": beats]]].merging(extra) { $1 }
    }

    /// Compás de 4/4 con una negra (cuerda 0, traste `fret`) y tres de silencio.
    static func marked(_ fret: Int, _ extra: [String: Any] = [:]) -> [String: Any] {
        measure([beat([1, 4], [note(0, fret)]), rest([3, 4])], extra)
    }

    static func track(_ measures: [[String: Any]], tuning: [Int] = standard, instrumentId: Int = 29,
                      instrument: String = "Overdriven Guitar", tempo: [[String: Any]]? = nil) throws -> SongsterrTrack {
        var root: [String: Any] = ["name": "Pista", "instrumentId": instrumentId, "instrument": instrument,
                                   "strings": tuning.count, "tuning": tuning, "measures": measures,
                                   "songId": 1, "partId": 0, "revisionId": 7]
        if let tempo { root["automations"] = ["tempo": tempo] }
        return try SongsterrTrackConverter.convert(try JSONSerialization.data(withJSONObject: root))
    }

    static func tempo(_ measure: Int, _ bpm: Double, position: Int = 0) -> [String: Any] {
        ["measure": measure, "position": position, "type": 4, "bpm": bpm, "linear": false]
    }

    /// La batería no tiene cuerdas ni afinación, aunque la pista venga con un `instrumentId` de guitarra y «Drums» en
    /// el nombre del instrumento.
    func testDrumsHaveNoTuning() throws {
        let hit: [String: Any] = ["duration": [1, 4], "notes": [["string": 0, "fret": 36]]]
        let t = try Self.track([Self.measure([hit])], instrumentId: 30, instrument: "Drums")
        XCTAssertEqual(t.kind, .drums)
        XCTAssertEqual(t.tuningStrings, [])
        XCTAssertNil(t.tuning)
        XCTAssertEqual(t.hits.count, 1)
    }

    // MARK: - Ritmo

    /// Negra, corchea con puntillo + semicorchea, tresillo de corcheas y negra con puntillo + corchea en un 4/4…
    /// más un compás con `type`/`dots`/`tuplet` sin `duration`: cada inicio y duración, exactos en ticks.
    func testDurationsDotsAndTuplets() throws {
        let q = Self.q
        let t = try Self.track([
            Self.measure([
                Self.beat([1, 4], [Self.note(0, 0)]),
                Self.beat([3, 16], [Self.note(0, 1)], ["type": 8, "dots": 1]),
                Self.beat([1, 16], [Self.note(0, 2)]),
                Self.beat([1, 12], [Self.note(0, 3)], ["type": 8, "tuplet": 3]),
                Self.beat([1, 12], [Self.note(0, 4)], ["type": 8, "tuplet": 3]),
                Self.beat([1, 12], [Self.note(0, 5)], ["type": 8, "tuplet": 3]),
                Self.beat([1, 20], [Self.note(0, 6)], ["type": 16, "tuplet": 5]),
                Self.rest([1, 5]),
            ]),
            Self.measure([
                ["type": 4, "dots": 1, "notes": [Self.note(1, 0)]],
                ["type": 8, "notes": [Self.note(1, 1)]],
                ["type": 8, "tuplet": 3, "notes": [Self.note(1, 2)]],
                ["type": 8, "tuplet": 3, "notes": [Self.note(1, 3)]],
                ["type": 8, "tuplet": 3, "notes": [Self.note(1, 4)]],
                ["type": 4, "rest": true, "notes": [["rest": true]]],
            ]),
        ])
        XCTAssertEqual(t.notes.map(\.position), [0, q, q * 7 / 4, 2 * q, 2 * q + q / 3, 2 * q + 2 * q / 3, 3 * q,
                                                 0, 3 * q / 2, 2 * q, 2 * q + q / 3, 2 * q + 2 * q / 3])
        XCTAssertEqual(t.notes.map(\.duration), [q, 3 * q / 4, q / 4, q / 3, q / 3, q / 3, q / 5,
                                                 3 * q / 2, q / 2, q / 3, q / 3, q / 3])
        XCTAssertEqual(t.notes.map(\.bar), [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1])
        XCTAssertEqual(t.notes.map(\.start), t.notes.map { t.bars[$0.bar].start + $0.position })
        XCTAssertEqual(t.bars.map(\.start), [0, 4 * q])
        XCTAssertEqual(t.totalTicks, 8 * q)
        XCTAssertEqual(t.report.inexactDurations, 0)
        XCTAssertEqual(t.report.invalidNotes, 0)
    }

    /// Ligaduras dentro del compás y de un compás al siguiente: una sola nota con la duración sumada. Silencios
    /// (beat, voz entera y compás entero) solo hacen avanzar.
    func testTiesAndRests() throws {
        let q = Self.q
        let t = try Self.track([
            Self.measure([
                Self.rest([1, 4]),
                Self.beat([1, 4], [Self.note(2, 5), Self.note(3, 7)]),
                Self.beat([1, 4], [Self.note(2, 5, ["tie": true])]),
                Self.beat([1, 4], [Self.note(3, 7)]),
            ]),
            Self.measure([
                Self.beat([1, 2], [Self.note(3, 7, ["tie": true])]),
                Self.rest([1, 2]),
            ]),
            ["voices": [["rest": true]]],
            ["rest": true, "voices": [["beats": [Self.beat([1, 1], [Self.note(0, 0)])]]]],
            Self.marked(3),
        ])
        XCTAssertEqual(t.notes.count, 4)
        XCTAssertEqual(t.notes.map(\.start), [q, q, 3 * q, 16 * q])
        XCTAssertEqual(t.notes.map(\.string), [3, 4, 4, 1])
        // 5.º traste de la 3.ª cuerda ligado una negra más; la nota de la 4.ª en el pulso 4 ligada a la blanca.
        XCTAssertEqual(t.notes.map(\.duration), [2 * q, q, 3 * q, q])
        XCTAssertEqual(t.notes.map(\.pitch), [60, 57, 57, 67])
        XCTAssertEqual(t.bars.count, 5)
    }

    /// Dos voces en un compás: cada una empieza en el inicio del compás.
    func testSecondVoiceStartsAtBarStart() throws {
        let q = Self.q
        let m: [String: Any] = ["voices": [
            ["beats": [Self.beat([1, 2], [Self.note(0, 0)]), Self.beat([1, 2], [Self.note(0, 2)])]],
            ["beats": [Self.beat([1, 4], [Self.note(5, 0)]), Self.beat([3, 4], [Self.note(5, 3)])]],
        ]]
        let t = try Self.track([m])
        XCTAssertEqual(t.notes.map(\.start), [0, 0, q, 2 * q])
        XCTAssertEqual(t.notes.map(\.pitch), [64, 40, 43, 66])
    }

    // MARK: - Compases, tempo y repeticiones

    func testSignaturesAndTempoChanges() throws {
        let q = Self.q
        let t = try Self.track([
            Self.marked(0, ["signature": [4, 4]]),
            Self.measure([Self.beat([1, 4], [Self.note(0, 1)]), Self.rest([1, 2])], ["signature": [3, 4]]),
            Self.measure([Self.beat([3, 8], [Self.note(0, 2)]), Self.rest([3, 8])], ["signature": [6, 8]]),
            Self.measure([Self.beat([3, 8], [Self.note(0, 3)]), Self.rest([3, 8])]),
            Self.marked(4, ["signature": [4, 4], "marker": ["text": "Solo", "width": 30]]),
        ], tempo: [Self.tempo(0, 172), Self.tempo(1, 172), Self.tempo(2, 130), Self.tempo(4, 140, position: 2)])
        XCTAssertEqual(t.bars.map(\.beatCount), [4, 3, 6, 6, 4])
        XCTAssertEqual(t.bars.map(\.beatUnit), [4, 4, 8, 8, 4])
        XCTAssertEqual(t.bars.map(\.start), [0, 4 * q, 7 * q, 10 * q, 13 * q])
        XCTAssertEqual(t.bars[2].beatLength, q / 2)
        XCTAssertEqual(t.bars.map(\.tempo), [172, 172, 130, 130, 130])
        XCTAssertEqual(t.bars.map(\.marker), [nil, nil, nil, nil, "Solo"])
        // Cambio a mitad del compás 5: posición 2 de tipo 4 = mitad del compás (regla del conversor de referencia).
        XCTAssertEqual(t.tempoChanges.map(\.bar), [0, 2, 4])
        XCTAssertEqual(t.tempoChanges.map(\.position), [0, 0, 2 * q])
        XCTAssertEqual(t.tempoChanges.map(\.bpm), [172, 130, 140])
        XCTAssertEqual(t.notes.map(\.start), [0, 4 * q, 7 * q, 10 * q, 13 * q])
        // Sin tempo en la pista: 120 desde el principio.
        let plain = try Self.track([Self.marked(0)])
        XCTAssertEqual(plain.tempoChanges, [SongsterrTempoChange(bar: 0, position: 0, bpm: 120)])
        XCTAssertEqual(plain.bars[0].tempo, 120)
    }

    /// Primer compás incompleto = anacrusa (17/11/2026): dos negras de silencio en un 4/4 dan un compás de 2 pulsos y
    /// todo lo demás 2 negras antes. Un primer compás completo de silencios (El roce: negra + blanca con puntillo), uno
    /// que no cuadra en pulsos y uno incompleto que no es el primero no cambian.
    func testIncompleteFirstBarIsAnacrusis() throws {
        let q = Self.q
        let pickup = try Self.track([Self.measure([Self.rest([1, 4]), Self.rest([1, 4])], ["signature": [4, 4]]),
                                     Self.marked(5), Self.marked(7)])
        XCTAssertEqual(pickup.bars.map(\.beatCount), [2, 4, 4])
        XCTAssertEqual(pickup.bars.map(\.start), [0, 2 * q, 6 * q])
        XCTAssertEqual(pickup.notes.map(\.start), [2 * q, 6 * q])
        // Anacrusa con nota: la nota se queda en su sitio dentro del compás corto.
        let withNote = try Self.track([Self.measure([Self.rest([1, 4]), Self.beat([1, 4], [Self.note(0, 3)])]), Self.marked(5)])
        XCTAssertEqual(withNote.bars.map(\.beatCount), [2, 4])
        XCTAssertEqual(withNote.notes.map(\.start), [q, 2 * q])

        let roce = try Self.track([Self.measure([Self.rest([1, 4]), Self.rest([3, 4])], ["signature": [4, 4], "rest": true]),
                                   Self.marked(5)])
        XCTAssertEqual(roce.bars.map(\.beatCount), [4, 4])
        let odd = try Self.track([Self.measure([Self.rest([3, 8])]), Self.marked(5)])
        XCTAssertEqual(odd.bars.map(\.beatCount), [4, 4], "3 corcheas en 4/4 no son pulsos enteros")
        let later = try Self.track([Self.marked(5), Self.measure([Self.rest([1, 4])]), Self.marked(5)])
        XCTAssertEqual(later.bars.map(\.beatCount), [4, 4, 4])
        XCTAssertEqual(SongsterrTrackConverter.version, 3)  // 3: técnicas
    }

    /// Repetición con inicio (2 veces), repetición sin inicio (3 veces, vuelve al final de la anterior) y finales
    /// alternativos [1] / [2] (lista y máscara de bits); el tempo sigue al compás tocado.
    func testRepeatsAndAlternateEndingsAreUnrolled() throws {
        let measures: [[String: Any]] = [
            Self.marked(0),                                     // 0
            Self.marked(1, ["repeatStart": true]),              // 1
            Self.marked(2, ["repeat": 2]),                      // 2
            Self.marked(3),                                     // 3
            Self.marked(4, ["repeat": 3]),                      // 4: vuelve al 3
            Self.marked(5, ["repeatStart": true]),              // 5
            Self.marked(6, ["alternateEnding": [1], "repeat": 2]), // 6
            Self.marked(7, ["alternateEnding": 2]),             // 7: máscara 0b10 = final 2
            Self.marked(8),                                     // 8
        ]
        XCTAssertEqual(try SongsterrTrackConverter.playOrder(measures), [0, 1, 2, 1, 2, 3, 4, 3, 4, 3, 4, 5, 6, 5, 7, 8])
        let t = try Self.track(measures, tempo: [Self.tempo(0, 100), Self.tempo(1, 110), Self.tempo(3, 90)])
        XCTAssertEqual(t.bars.map(\.sourceMeasure), [0, 1, 2, 1, 2, 3, 4, 3, 4, 3, 4, 5, 6, 5, 7, 8])
        XCTAssertEqual(t.notes.map(\.fret), [0, 1, 2, 1, 2, 3, 4, 3, 4, 3, 4, 5, 6, 5, 7, 8])
        XCTAssertEqual(t.notes.map(\.start), (0..<16).map { $0 * 4 * Self.q })
        XCTAssertEqual(t.bars.map(\.tempo), [100, 110, 110, 110, 110, 90, 90, 90, 90, 90, 90, 90, 90, 90, 90, 90])
        XCTAssertEqual(t.tempoChanges.map(\.bar), [0, 1, 5])
        // Un final que no suena en ninguna pasada no repite; un «×30000» se corta con error de formato.
        XCTAssertEqual(try SongsterrTrackConverter.playOrder([["repeat": 2, "alternateEnding": [3]], [:]]), [1])
        XCTAssertThrowsError(try SongsterrTrackConverter.playOrder([["repeat": 30_000]]))
    }

    // MARK: - Afinación e instrumento

    func testTuningStringsAndKind() throws {
        let dropD = [64, 59, 55, 50, 45, 38]
        let g = try Self.track([Self.measure([Self.beat([1, 1], [Self.note(5, 0), Self.note(0, 3)])])], tuning: dropD)
        XCTAssertEqual(g.kind, .guitar)
        XCTAssertEqual(g.tuningStrings, dropD)
        XCTAssertEqual(g.tuning, .guitar(.dropD))
        XCTAssertEqual(g.notes.map(\.string), [1, 6])
        XCTAssertEqual(g.notes.map(\.pitch), [67, 38])
        XCTAssertEqual(g.notes.map(\.fret), [3, 0])
        XCTAssertEqual([g.songId, g.revisionId, g.partId], [1, 7, 0])

        let bass = try Self.track([Self.measure([Self.beat([1, 1], [Self.note(3, 5)])])], tuning: [43, 38, 33, 28],
                                  instrumentId: 33, instrument: "Electric Bass (finger)")
        XCTAssertEqual(bass.kind, .bass)
        XCTAssertEqual(bass.tuning, .bass(.standard))
        XCTAssertEqual(bass.notes.first?.pitch, 33)

        // Afinación sin preset (Do estándar), 7 cuerdas y traste > 24: se importan tal cual y se cuenta el traste.
        let c = try Self.track([Self.measure([Self.beat([1, 1], [Self.note(6, 0), Self.note(0, 27)])])],
                               tuning: [62, 57, 53, 48, 43, 38, 33])
        XCTAssertNil(c.tuning)
        XCTAssertEqual(c.notes.map(\.pitch), [89, 33])
        XCTAssertEqual(c.notes.map(\.string), [1, 7])
        XCTAssertEqual(c.report.fretsOutOfRange, 1)

        // Cuerda fuera de la afinación y nota pasado el final del compás: fuera y contadas.
        let bad = try Self.track([Self.measure([Self.beat([1, 1], [Self.note(6, 0)]), Self.beat([1, 4], [Self.note(0, 0)])])])
        XCTAssertTrue(bad.notes.isEmpty)
        XCTAssertEqual(bad.report.invalidNotes, 2)
    }

    // MARK: - Batería

    func testDrumsMapToGMPieces() throws {
        let q = Self.q
        let hits: [[String: Any]] = [36, 35, 38, 42, 46, 49, 51, 57, 45, 56].map { ["string": 0, "fret": $0] }
        let measures: [[String: Any]] = [
            Self.measure([Self.beat([1, 4], hits), Self.beat([1, 4], [["string": 0, "fret": 44]]),
                          Self.beat([1, 4], [["string": 0, "fret": 46, "tie": true]]),
                          Self.beat([1, 4], [["string": 0, "fret": 37, "ghost": true]])]),
        ]
        let root: [String: Any] = ["name": "Drums", "instrumentId": 1024, "instrument": "Drums", "measures": measures]
        let t = try SongsterrTrackConverter.convert(try JSONSerialization.data(withJSONObject: root))
        XCTAssertEqual(t.kind, .drums)
        XCTAssertTrue(t.tuningStrings.isEmpty)
        XCTAssertNil(t.tuning)
        XCTAssertTrue(t.notes.isEmpty)
        // 35 y 36 → un bombo; 49, 51 y 57 → un plato; 56 (cencerro) fuera; el 46 ligado no suena otra vez.
        XCTAssertEqual(t.hits.filter { $0.start == 0 }.map(\.piece), [.kick, .snare, .hiHat, .openHiHat, .tom, .crash])
        XCTAssertEqual(t.hits.filter { $0.start > 0 }.map(\.piece), [.hiHat, .snare])
        XCTAssertEqual(t.hits.filter { $0.start > 0 }.map(\.start), [q, 3 * q])
        XCTAssertEqual(t.report.unknownDrumNotes, 1)
        // El ghost de batería se importa en el golpe.
        XCTAssertEqual(t.hits.map(\.ghost), t.hits.map { $0.start == 3 * q })
        XCTAssertEqual(t.report.techniques, [.ghost: 1])
        XCTAssertEqual(t.report.ornaments, [:])
        XCTAssertEqual(t.report.notesWithOrnaments, 0)

        // Pista sin instrumentId 1024 pero marcada como batería en la página.
        let flagged = try SongsterrTrackConverter.convert(
            try JSONSerialization.data(withJSONObject: ["measures": measures, "instrumentId": 0]), isDrums: true)
        XCTAssertEqual(flagged.kind, .drums)
        XCTAssertEqual(flagged.hits.count, t.hits.count)
    }

    // MARK: - Adornos

    /// Cada nota se importa con su altura de cuerda y traste y sus técnicas (detalle en `SongsterrTechniquesTests`).
    /// La nota de adorno no ocupa tiempo: la de otra cuerda va en la nota siguiente con su cuerda (rastrillo) y la
    /// siguiente cae en su sitio.
    func testOrnamentsAreImportedAndGraceNotesCounted() throws {
        let q = Self.q
        let bend: [String: Any] = ["tone": 100, "points": [["position": 0, "tone": 0], ["position": 60, "tone": 100]]]
        let t = try Self.track([
            Self.measure([
                Self.beat([1, 8], [Self.note(1, 5, ["bend": bend])]),
                Self.beat([1, 8], [Self.note(1, 7, ["slide": "below"])]),
                Self.beat([1, 8], [Self.note(0, 12, ["harmonic": "natural", "harmonicFret": 12])]),
                Self.beat([1, 8], [Self.note(5, 0), Self.note(4, 2)], ["palmMute": true]),
                Self.beat([1, 32], [Self.note(2, 4)], ["graceNote": "beforeBeat"]),
                Self.beat([1, 8], [Self.note(3, 0, ["dead": true])]),
                Self.beat([1, 8], [Self.note(3, 2, ["ghost": true, "hp": true])]),
                Self.beat([1, 8], [Self.note(2, 4, ["vibrato": true])], ["letRing": true]),
                Self.beat([1, 8], [Self.note(2, 5, ["accentuated": true])]),
            ]),
        ])
        XCTAssertEqual(t.notes.count, 9)
        XCTAssertEqual(t.notes.map(\.start), [0, q / 2, q, 3 * q / 2, 3 * q / 2, 2 * q, 5 * q / 2, 3 * q, 7 * q / 2])
        XCTAssertEqual(t.notes.map(\.pitch), [64, 66, 76, 47, 40, 50, 52, 59, 60])
        XCTAssertEqual(t.report.techniques, [.bend: 1, .slide: 1, .harmonic: 1, .palmMute: 2, .dead: 1, .ghost: 1,
                                             .hammerPull: 1, .vibrato: 1, .letRing: 1, .accent: 1, .grace: 1])
        XCTAssertEqual(t.notes[5].techniques.graces, [TabGrace(fret: 4, type: .beforeBeat, duration: 32, string: 3)])
        XCTAssertEqual(t.report.ornaments, [:])
        XCTAssertEqual(t.report.notesWithOrnaments, 0)
    }

    // MARK: - Formato desconocido

    func testUnknownFormatThrows() throws {
        func convert(_ object: Any) throws -> SongsterrTrack {
            try SongsterrTrackConverter.convert(try JSONSerialization.data(withJSONObject: object))
        }
        XCTAssertThrowsError(try SongsterrTrackConverter.convert(Data("<html>".utf8)))
        XCTAssertThrowsError(try convert([1, 2, 3]))
        XCTAssertThrowsError(try convert(["tuning": Self.standard]))
        XCTAssertThrowsError(try convert(["measures": [Self.marked(0)]]))  // guitarra sin afinación
        XCTAssertThrowsError(try convert(["tuning": Self.standard, "measures": [Self.measure([["notes": [Self.note(0, 0)]]])]]))
    }

    // MARK: - Datos reales (solo en local)

    /// Las tres pistas de El roce en `Temp/p5b/songsterr/50624/` (sin versionar): mismos recuentos de notas que el
    /// prototipo `eval_reference.py` (1311, 1704 y 1035). Se salta si no están.
    func testRealTracksMatchPrototypeCounts() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Temp/p5b/songsterr/50624")
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("0.json").path) else {
            throw XCTSkip("no están las pistas de Songsterr en \(dir.path)")
        }
        let expected = [1311, 1704, 1035]
        for (part, count) in expected.enumerated() {
            let t = try SongsterrTrackConverter.convert(try Data(contentsOf: dir.appendingPathComponent("\(part).json")))
            print("songsterr parte \(part): \(t.kind) \(t.notes.count) notas, \(t.bars.count) compases tocados,",
                  "tempo \(t.tempoChanges.map { "\($0.bar):\($0.bpm)" }), afinación \(String(describing: t.tuning?.preset)),",
                  "técnicas \(t.report.techniques.mapKeys(\.rawValue)),",
                  "sin representar \(t.report.notesWithOrnaments) \(t.report.ornaments.mapKeys(\.rawValue)),",
                  "inválidas \(t.report.invalidNotes), inexactas \(t.report.inexactDurations)")
            XCTAssertEqual(t.notes.count, count, "parte \(part)")
            XCTAssertEqual(t.report.invalidNotes, 0)
            XCTAssertEqual(t.report.inexactDurations, 0)
        }
    }
}

private extension Dictionary {
    func mapKeys<K: Hashable>(_ f: (Key) -> K) -> [K: Value] {
        Dictionary<K, Value>(uniqueKeysWithValues: map { (f($0.key), $0.value) })
    }
}
