import XCTest
@testable import TabKit

/// Técnicas (Fase 5b): `TabScore` → JSON del puente de alphaTab y edición que las conserva. El dibujo y la
/// exportación `.gp` de cada técnica se comprueban con `Probes/P5b-guitarra/check-techniques.js`.
final class AlphaTabTechniquesTests: XCTestCase {
    private struct Doc: Decodable {
        struct Bend: Decodable { var type: String; var pts: [[Int]] }
        struct Harm: Decodable { var type: String; var fret: Double? }
        struct Tech: Decodable {
            var pm: Bool?; var lr: Bool?; var hp: Bool?; var dead: Bool?; var ghost: Bool?; var stac: Bool?
            var vib: String?; var bend: Bend?; var sin: String?; var sout: String?; var harm: Harm?; var acc: String?
        }
        struct Note: Decodable { var s: Int; var f: Int; var t: Tech? }
        struct Beat: Decodable {
            var notes: [Note]?; var hits: [Int]?; var ghosts: [Int]?
            var tap: Bool?; var trem: Int?; var whammy: Bend?; var pick: String?; var brush: String?; var grace: String?
        }
        struct Track: Decodable { var kind: String; var bars: [[Beat]] }
        var tracks: [Track]
    }

    private func decode(_ score: TabScore) throws -> Doc {
        let out = try AlphaTabExporter.make(score: score, title: "T", artist: "A")
        return try JSONDecoder().decode(Doc.self, from: Data(out.json.utf8))
    }

    /// Pone `body` en las técnicas de la primera nota de la guitarra y devuelve el beat de alphaTab (no de adorno) donde cae.
    private func scoreWith(_ body: (inout TabTechniques) -> Void) throws -> (TabScore, Doc.Beat) {
        var score = try TabEditorTests.score()
        let g = score.trackIndex(id: "guitar")!
        let start = score.tracks[g].notes[0].start
        // La primera nota del beat en el JSON es la de número de cuerda mayor.
        let target = score.tracks[g].notes.indices.filter { score.tracks[g].notes[$0].start == start }
            .max { score.tracks[g].notes[$0].string < score.tracks[g].notes[$1].string }!
        body(&score.tracks[g].notes[target].techniques)
        let out = try AlphaTabExporter.make(score: score, title: "T", artist: "A")
        let doc = try JSONDecoder().decode(Doc.self, from: Data(out.json.utf8))
        for (bar, refs) in out.beats[g].enumerated() {
            for (i, ref) in refs.enumerated() where ref.start == start && ref.length > 0 {
                return (score, doc.tracks[g].bars[bar][i])
            }
        }
        throw XCTSkip("sin beat")
    }

    func testEveryTechniqueReachesTheJSON() throws {
        let curve = TabBend(type: .bendRelease, points: [.init(position: 0, value: 0), .init(position: 30, value: 4),
                                                        .init(position: 60, value: 0)])
        var all = TabTechniques()
        all.palmMute = true; all.letRing = true; all.hammerPull = true; all.dead = true; all.ghost = true
        all.staccato = true; all.vibrato = .wide; all.bend = curve; all.slideIn = .intoFromBelow
        all.slideOut = .legato; all.harmonic = TabHarmonic(type: .natural, fret: 12); all.accent = .heavy
        all.tapping = true; all.tremoloPicking = .sixteenth; all.whammy = curve; all.pickStroke = .down; all.brush = .up
        let (_, beat) = try scoreWith { $0 = all }
        let t = try XCTUnwrap(beat.notes?.first?.t)
        XCTAssertEqual([t.pm, t.lr, t.hp, t.dead, t.ghost, t.stac], Array(repeating: true, count: 6))
        XCTAssertEqual(t.vib, "wide")
        XCTAssertEqual(t.bend?.type, "bendRelease")
        XCTAssertEqual(t.bend?.pts, [[0, 0], [30, 4], [30, 4], [60, 0]], "cima duplicada: alphaTab lee bendPoints[3]")
        XCTAssertEqual(t.sin, "intoFromBelow")
        XCTAssertEqual(t.sout, "legato")
        XCTAssertEqual(t.harm?.type, "natural")
        XCTAssertEqual(t.harm?.fret, 12)
        XCTAssertEqual(t.acc, "heavy")
        XCTAssertEqual(beat.tap, true)
        XCTAssertEqual(beat.trem, 16)
        XCTAssertEqual(beat.whammy?.type, "bendRelease")
        XCTAssertEqual(beat.pick, "down")
        XCTAssertEqual(beat.brush, "up")
    }

    func testNoTechniquesWritesNoKeys() throws {
        let out = try AlphaTabExporter.make(score: try TabEditorTests.score(), title: "T", artist: "A")
        for key in ["\"t\":", "\"tap\"", "\"trem\"", "\"whammy\"", "\"pick\"", "\"brush\"", "\"ghosts\""] {
            XCTAssertFalse(out.json.contains(key), key)
        }
    }

    func testBeatTechniquesAreLiftedFromAnyChordNote() throws {
        var score = try TabEditorTests.score()
        let g = score.trackIndex(id: "guitar")!
        let chordStart = score.tracks[g].notes[0].start
        let chord = score.tracks[g].notes.indices.filter { score.tracks[g].notes[$0].start == chordStart }
        XCTAssertGreaterThan(chord.count, 1)
        score.tracks[g].notes[chord[1]].techniques.brush = .down
        let doc = try decode(score)
        let beat = doc.tracks[g].bars.flatMap { $0 }.first { ($0.notes ?? []).count == chord.count }!
        XCTAssertEqual(beat.brush, "down")
    }

    func testChainedBendIsReducedToFourPointsKeepingTypeAndEnds() throws {
        let pts = [(0, 0), (10, 4), (20, 4), (30, 8), (40, 8), (50, 4), (60, 0)].map { TabBendPoint(position: $0.0, value: $0.1) }
        let bend = TabBend(type: .custom, points: pts)
        let simple = bend.simplified(maxPoints: 4)
        XCTAssertEqual(simple.points.count, 4)
        XCTAssertEqual(simple.type, .custom)
        XCTAssertEqual(simple.points.first, pts.first)
        XCTAssertEqual(simple.points.last, pts.last)
        XCTAssertEqual(simple.points.map(\.value).max(), 8)
        XCTAssertEqual(simple.points.map(\.position), simple.points.map(\.position).sorted())
        // y por el JSON
        let (_, beat) = try scoreWith { $0.bend = bend }
        XCTAssertEqual(beat.notes?.first?.t?.bend?.pts.count, 4)
        XCTAssertEqual(beat.notes?.first?.t?.bend?.type, "custom")
        // una curva corta no cambia
        let short = TabBend(points: [.init(position: 0, value: 0), .init(position: 60, value: 4)])!
        XCTAssertEqual(short.simplified(maxPoints: 4), short)
    }

    func testGraceNoteIsABeatBeforeTheMainOneAndKeepsRefsAligned() throws {
        var score = try TabEditorTests.score()
        let g = score.trackIndex(id: "guitar")!
        let note = score.tracks[g].notes[0]
        score.tracks[g].notes[0].techniques.graces = [TabGrace(fret: 3, type: .beforeBeat, hammerPull: true)]
        let out = try AlphaTabExporter.make(score: score, title: "T", artist: "A")
        let doc = try JSONDecoder().decode(Doc.self, from: Data(out.json.utf8))
        let bar = note.start.beat / 4
        let beats = doc.tracks[g].bars[bar]
        XCTAssertEqual(beats.count, out.beats[g][bar].count)
        let i = try XCTUnwrap(beats.firstIndex { $0.grace != nil })
        XCTAssertEqual(beats[i].grace, "beforeBeat")
        XCTAssertEqual(beats[i].notes?.first?.f, 3)
        XCTAssertEqual(beats[i].notes?.first?.t?.hp, true)
        XCTAssertNil(beats[i + 1].grace)
        XCTAssertEqual(out.beats[g][bar][i].length, 0)
        XCTAssertEqual(out.beats[g][bar][i].noteIDs.values.first, note.id)
        XCTAssertNil(beats[i + 1].notes?.first?.t)
    }

    /// alphaTab revienta al dibujar un bend-release de menos de 4 puntos (lee `bendPoints[3]`; El roce). Para curvas
    /// de 2 a 7 puntos de todas las formas, el JSON lleva al menos los puntos que pide su tipo (4 en bend-release, 2 en
    /// los demás) y la misma forma (sin repetidos seguidos, los mismos valores).
    func testBendsCarryThePointsAlphaTabReadsForTheirType() throws {
        let shapes: [[Int]] = [[0, 4], [0, 4, 0], [0, 8, 4], [0, 4, 4, 0], [0, 2, 6, 2, 0], [0, 4, 8, 8, 4, 2, 0],
                               [4, 4], [4, 0], [4, 8], [0, 4, 0, 4], [0, 2, 4, 6, 8, 6, 0], [6, 2, 0]]
        var seen = Set<TabBend.Kind>()
        for v in shapes {
            let pts = v.enumerated().map { TabBendPoint(position: $0.offset * 60 / (v.count - 1), value: $0.element) }
            for bend in [TabBend(points: pts)!, TabBend(type: .bendRelease, points: pts)] {
                let (_, beat) = try scoreWith { $0.bend = bend }
                let j = try XCTUnwrap(beat.notes?.first?.t?.bend)
                let kind = try XCTUnwrap(TabBend.Kind(rawValue: j.type))
                seen.insert(kind)
                XCTAssertGreaterThanOrEqual(j.pts.count, TabBend.alphaTabMinimumPoints(kind), "\(v) \(kind)")
                func squash(_ a: [Int]) -> [Int] { a.enumerated().filter { $0.offset == 0 || a[$0.offset - 1] != $0.element }.map(\.element) }
                XCTAssertEqual(squash(j.pts.map { $0[1] }),
                               squash(bend.simplified(maxPoints: AlphaTabExporter.maxBendPoints).points.map(\.value)), "\(v)")
                XCTAssertEqual(j.pts.map { $0[0] }, j.pts.map { $0[0] }.sorted(), "\(v)")
            }
        }
        XCTAssertTrue(seen.isSuperset(of: [.bend, .bendRelease, .prebend, .prebendBend, .prebendRelease, .custom]))
    }

    /// Rastrillo (Tornado): dos notas de adorno muertas en otras dos cuerdas, una tras otra, delante de la principal.
    /// Salen dos beats de adorno en orden, cada uno con su nota en su cuerda; el mapa de beats tiene un ref por beat
    /// del JSON y, en cada compás, la suma de longitudes es la del compás y cada beat empieza donde acaba el anterior.
    func testRakeIsSeveralGraceBeatsInOrderOnTheirStrings() throws {
        var score = try TabEditorTests.score()
        let g = score.trackIndex(id: "guitar")!
        let note = score.tracks[g].notes[0]
        let count = try XCTUnwrap(score.tracks[g].tuning?.strings.count)
        let far = note.string % count + 1, near = far % count + 1
        XCTAssertFalse([far, near].contains(note.string))
        score.tracks[g].notes[0].techniques.graces = [
            TabGrace(fret: 0, type: .beforeBeat, dead: true, string: far, step: 2),
            TabGrace(fret: 0, type: .beforeBeat, dead: true, string: near, step: 1),
        ]
        let out = try AlphaTabExporter.make(score: score, title: "T", artist: "A")
        let doc = try JSONDecoder().decode(Doc.self, from: Data(out.json.utf8))
        let bar = note.start.beat / 4
        let beats = doc.tracks[g].bars[bar]
        let refs = out.beats[g][bar]
        XCTAssertEqual(beats.count, refs.count)
        let i = try XCTUnwrap(beats.firstIndex { $0.grace != nil })
        XCTAssertEqual(beats[i].grace, "beforeBeat")
        XCTAssertEqual(beats[i + 1].grace, "beforeBeat")
        XCTAssertNil(beats[i + 2].grace)
        let js = { AlphaTabExporter.jsonString(forScoreString: $0, stringCount: count) }
        XCTAssertEqual(beats[i].notes?.map(\.s), [js(far)])
        XCTAssertEqual(beats[i + 1].notes?.map(\.s), [js(near)])
        XCTAssertEqual(beats[i].notes?.first?.t?.dead, true)
        XCTAssertEqual(beats[i + 1].notes?.first?.t?.dead, true)
        XCTAssertEqual(refs[i].noteIDs, [js(far): note.id])
        XCTAssertEqual(refs[i + 1].noteIDs, [js(near): note.id])
        XCTAssertEqual([refs[i].length, refs[i + 1].length], [0, 0])
        XCTAssertEqual(refs[i + 2].start, note.start)
        XCTAssertEqual(refs[i + 2].noteIDs[js(note.string)], note.id)
        // Cursor: en todos los compases de la pista, cada beat empieza donde acaba el anterior (0 ticks de error).
        for (b, bar) in score.bars.enumerated() {
            var tick = bar.firstBeat * TabScore.ticksPerBeat
            for r in out.beats[g][b] {
                XCTAssertEqual(r.start.absoluteTick, tick, "compás \(b)")
                tick += r.length
            }
            XCTAssertEqual(tick, (bar.firstBeat + bar.beatCount) * TabScore.ticksPerBeat, "compás \(b)")
        }
    }

    /// Un JSON con la nota de adorno única de antes (`grace`) se lee como `graces` de una; se escribe como `graces`.
    func testLegacySingleGraceDecodes() throws {
        let old = #"{"grace":{"fret":3,"type":"onBeat","dead":true}}"#
        let t = try JSONDecoder().decode(TabTechniques.self, from: Data(old.utf8))
        XCTAssertEqual(t.graces, [TabGrace(fret: 3, type: .onBeat, dead: true)])
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        XCTAssertEqual(String(decoding: try enc.encode(t), as: UTF8.self), #"{"graces":[{"dead":true,"fret":3,"type":"onBeat"}]}"#)
        var rake = TabTechniques()
        rake.graces = [TabGrace(fret: 0, type: .beforeBeat, dead: true, string: 3, step: 2),
                       TabGrace(fret: 0, type: .beforeBeat, dead: true, string: 2)]
        XCTAssertEqual(try JSONDecoder().decode(TabTechniques.self, from: try enc.encode(rake)), rake)
    }

    func testAccentedDrumHitIsMarkedAndLouder() throws {
        var score = try TabEditorTests.score()
        let d = score.trackIndex(id: "drums")!
        score.tracks[d].hits[0].accent = .heavy
        let out = try AlphaTabExporter.make(score: score, title: "T", artist: "A")
        XCTAssertTrue(out.json.contains(#""accents":{"\#(score.tracks[d].hits[0].piece.rawValue)":"heavy"}"#), out.json)
        XCTAssertGreaterThan(TabSynthRenderer.hitVelocity(score.tracks[d].hits[0]), TabSynthRenderer.velocity)
        let plain = try AlphaTabExporter.make(score: try TabEditorTests.score(), title: "T", artist: "A")
        XCTAssertFalse(plain.json.contains("\"accents\""))
    }

    func testSynthEventsApproximateTechniques() throws {
        var t = TabTechniques()
        t.bend = TabBend(points: [.init(position: 0, value: 0), .init(position: 60, value: 4)])
        let ev = TabSynthRenderer.pitchBendEvents(t, on: 0, off: 44100, sampleRate: 44100, delayFrames: 0)
        func value(_ e: TabSynthRenderer.Event) -> Int { Int(e.data1) | Int(e.data2) << 7 }
        XCTAssertEqual(value(ev[0]), 8192)
        XCTAssertGreaterThan(value(ev[ev.count - 2]), 8192 + 8000)   // un tono = fondo de escala
        XCTAssertEqual(value(ev[ev.count - 1]), 8192)                // vuelve al centro
        XCTAssertTrue(TabSynthRenderer.pitchBendEvents(TabTechniques(), on: 0, off: 100, sampleRate: 44100, delayFrames: 0).isEmpty)
        var ghost = TabTechniques(); ghost.ghost = true
        XCTAssertLessThan(TabSynthRenderer.noteVelocity(ghost), TabSynthRenderer.velocity)
    }

    func testDrumFlamIsAGraceBeatBeforeTheHit() throws {
        var score = try TabEditorTests.score()
        let d = score.trackIndex(id: "drums")!
        let hit = score.tracks[d].hits[0]
        score.tracks[d].hits[0].grace = TabGrace(fret: DrumPiece.snare.rawValue, type: .beforeBeat)
        let out = try AlphaTabExporter.make(score: score, title: "T", artist: "A")
        let doc = try JSONDecoder().decode(Doc.self, from: Data(out.json.utf8))
        let bar = hit.at.beat / 4
        let beats = doc.tracks[d].bars[bar]
        XCTAssertEqual(beats.count, out.beats[d][bar].count)
        let i = try XCTUnwrap(beats.firstIndex { $0.grace != nil })
        XCTAssertEqual(beats[i].hits, [DrumPiece.snare.rawValue])
        XCTAssertEqual(out.beats[d][bar][i].length, 0)
        XCTAssertEqual(beats[i + 1].hits?.contains(hit.piece.rawValue), true)
    }

    func testGhostDrumHitIsMarked() throws {
        var score = try TabEditorTests.score()
        let d = score.trackIndex(id: "drums")!
        score.tracks[d].hits[0].ghost = true
        let doc = try decode(score)
        let beats = doc.tracks[d].bars.flatMap { $0 }
        XCTAssertEqual(beats.compactMap(\.ghosts).flatMap { $0 }, [score.tracks[d].hits[0].piece.rawValue])
    }

    // MARK: Edición

    private func techniques() -> TabTechniques {
        var t = TabTechniques()
        t.palmMute = true
        t.vibrato = .slight
        t.bend = TabBend(points: [.init(position: 0, value: 0), .init(position: 60, value: 4)])
        return t
    }

    func testEditingKeepsTechniquesAndDeletingDropsThem() throws {
        var score = try TabEditorTests.score()
        let g = score.trackIndex(id: "guitar")!
        let id = score.tracks[g].notes[0].id
        score.tracks[g].notes[0].techniques = techniques()
        var editor = TabEditor(score: score)
        func current() -> TabNote { editor.score.tracks[g].notes.first { $0.id == id }! }

        let fret = score.tracks[g].fret(of: current())!
        try editor.setFret(fret == 0 ? 1 : fret - 1, trackID: "guitar", noteID: id)
        XCTAssertEqual(current().techniques, techniques())
        try editor.setDuration(current().duration == 3 ? 6 : 3, trackID: "guitar", noteID: id)
        XCTAssertEqual(current().techniques, techniques())
        // mover a otra cuerda (misma altura), si hay una libre y alcanzable
        for string in 1...6 where string != current().string {
            if (try? editor.moveNote(trackID: "guitar", noteID: id, toString: string)) != nil {
                XCTAssertEqual(current().string, string)
                XCTAssertEqual(current().techniques, techniques())
                break
            }
        }
        try editor.deleteNote(trackID: "guitar", noteID: id)
        XCTAssertFalse(editor.score.tracks[g].notes.contains { $0.id == id })
        XCTAssertTrue(editor.undo())
        XCTAssertEqual(current().techniques, techniques())
    }

    func testGhostHitCanBeRemoved() throws {
        var score = try TabEditorTests.score()
        let d = score.trackIndex(id: "drums")!
        let hit = score.tracks[d].hits[0]
        score.tracks[d].hits[0].ghost = true
        var editor = TabEditor(score: score)
        try editor.setHit(hit.piece, at: hit.at, present: false, trackID: "drums")
        XCTAssertFalse(editor.score.tracks[d].hits.contains { $0.isSameHit(as: hit) })
    }
}
