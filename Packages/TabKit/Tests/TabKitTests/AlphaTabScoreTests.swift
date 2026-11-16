import XCTest
@testable import TabKit

/// `TabScore` → JSON v1 del puente de alphaTab (mini-spec Fase 5, «Partitura, sonido y exportación»).
final class AlphaTabScoreTests: XCTestCase {
    private struct Doc: Decodable {
        struct Bar: Decodable { var num: Int; var den: Int; var tempo: Double; var start: Double }
        struct Note: Decodable { var s: Int; var f: Int }
        struct Beat: Decodable { var d: Int; var dots: Int?; var tuplet: Int?; var notes: [Note]?; var hits: [Int]? }
        struct Track: Decodable { var name: String; var kind: String; var tuning: [Int]?; var bars: [[Beat]] }
        var version: Int
        var title: String
        var bars: [Bar]
        var tracks: [Track]
    }

    private func make() throws -> (TabScore, AlphaTabScore, Doc) {
        let score = try TabEditorTests.score()
        let out = try AlphaTabExporter.make(score: score, title: "T", artist: "A")
        return (score, out, try JSONDecoder().decode(Doc.self, from: Data(out.json.utf8)))
    }

    func testStructureMatchesScore() throws {
        let (score, out, doc) = try make()
        XCTAssertEqual(doc.version, 1)
        XCTAssertEqual(doc.bars.count, score.bars.count)
        XCTAssertEqual(doc.bars.map(\.start), score.bars.map(\.start))
        XCTAssertEqual(doc.tracks.map(\.name), score.tracks.map(\.name))
        XCTAssertEqual(out.trackIDs, score.tracks.map(\.id))
        for t in doc.tracks { XCTAssertEqual(t.bars.count, doc.bars.count) }
        XCTAssertEqual(doc.tracks[2].kind, "drums")
        XCTAssertNil(doc.tracks[2].tuning)
        // Afinación de grave a aguda (EADGBE).
        XCTAssertEqual(doc.tracks[0].tuning, [40, 45, 50, 55, 59, 64])
    }

    func testEveryBarIsFilledExactlyAndNotesRoundTrip() throws {
        let (score, out, doc) = try make()
        for (ti, track) in score.tracks.enumerated() {
            var found = 0
            for (bi, bar) in score.bars.enumerated() {
                let refs = out.beats[ti][bi]
                XCTAssertEqual(refs.count, doc.tracks[ti].bars[bi].count)
                // Los pulsos de alphaTab cubren el compás sin huecos ni solapes.
                var tick = bar.firstBeat * TabScore.ticksPerBeat
                for r in refs {
                    XCTAssertEqual(r.start.absoluteTick, tick, "track \(track.id) bar \(bi)")
                    tick += r.length
                }
                XCTAssertEqual(tick, (bar.firstBeat + bar.beatCount) * TabScore.ticksPerBeat, "track \(track.id) bar \(bi)")
                for (k, r) in refs.enumerated() {
                    for (s, id) in r.noteIDs {
                        let n = try XCTUnwrap(track.notes.first { $0.id == id })
                        XCTAssertEqual(n.start, r.start)
                        // s = 0 es la cuerda más grave; en TabScore la 1 es la más aguda.
                        XCTAssertEqual(AlphaTabExporter.scoreString(forJSONString: s, stringCount: track.tuning?.strings.count ?? 6), n.string)
                        let jn = try XCTUnwrap(doc.tracks[ti].bars[bi][k].notes?.first { $0.s == s })
                        XCTAssertEqual(jn.f, track.fret(of: n))
                        found += 1
                    }
                    for p in r.pieces {
                        XCTAssertTrue(track.hits.contains(TabDrumHit(piece: p, at: r.start)))
                        XCTAssertTrue(doc.tracks[ti].bars[bi][k].hits?.contains(p.rawValue) == true)
                        found += 1
                    }
                }
            }
            XCTAssertEqual(found, track.kind == .drums ? track.hits.count : track.notes.count, "track \(track.id)")
        }
    }

    func testLowestStringIsIndexZeroAndTriplets() throws {
        let (score, out, doc) = try make()
        let guitar = score.tracks[0]
        let low = try XCTUnwrap(guitar.notes.first { $0.pitch == 40 })
        let ref = try XCTUnwrap(out.beats[0].flatMap { $0 }.first { $0.noteIDs.values.contains(low.id) })
        XCTAssertEqual(ref.noteIDs.first { $0.value == low.id }?.key, 0)
        // El pulso en tresillo (3 notas de tresillo de corchea) sale con tuplet 3.
        let tripletBeats = doc.tracks[0].bars.flatMap { $0 }.filter { $0.tuplet == 3 }
        XCTAssertFalse(tripletBeats.isEmpty)
    }

    func testEditedScoreChangesJSONAndRefsLookUp() throws {
        var score = try TabEditorTests.score()
        var editor = TabEditor(score: score)
        let id = try editor.addNote(trackID: "bass", string: 1, fret: 3, at: GridPoint(beat: 8, tick: 0), duration: 3)
        score = editor.score
        let out = try AlphaTabExporter.make(score: score, title: "T", artist: "A")
        let t = try XCTUnwrap(out.trackIDs.firstIndex(of: "bass"))
        let bar = score.beats[8].bar
        let ref = try XCTUnwrap(out.beats[t][bar].first { $0.noteIDs.values.contains(id) })
        XCTAssertEqual(ref.start, GridPoint(beat: 8, tick: 0))
        XCTAssertNotNil(out.ref(track: t, bar: bar, beat: out.beats[t][bar].firstIndex(of: ref)!))
        XCTAssertNil(out.ref(track: 9, bar: 0, beat: 0))
    }
}
