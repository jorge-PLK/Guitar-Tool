import XCTest
@testable import Store

final class SectionEditorTests: XCTestCase {
    private func editor(_ list: [Section] = []) -> SectionEditor { SectionEditor(sections: list, duration: 100) }
    private let chords: [Double] = [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20]
    private let bars: [Double] = [0, 8, 16]

    /// Propiedad de la mini-spec Fase 7b, punto 8, comprobada tras cada edición: ordenadas, sin solapes ni anidadas,
    /// cada una de al menos `minLength` y dentro de la canción.
    private func check(_ e: SectionEditor, file: StaticString = #filePath, line: UInt = #line) {
        let s = e.sections.sorted { $0.start < $1.start }
        for x in s {
            XCTAssertGreaterThanOrEqual(x.end - x.start, SectionEditor.minLength - 1e-9, "\(x.name) más corta que el mínimo", file: file, line: line)
            XCTAssertGreaterThanOrEqual(x.start, -1e-9, file: file, line: line)
            XCTAssertLessThanOrEqual(x.end, e.duration + 1e-9, file: file, line: line)
        }
        for (a, b) in zip(s, s.dropFirst()) {
            XCTAssertLessThanOrEqual(a.end, b.start + 1e-9, "\(a.name) [\(a.start), \(a.end)] solapa a \(b.name) [\(b.start), \(b.end)]", file: file, line: line)
        }
    }

    private func spans(_ e: SectionEditor) -> [[Double]] { e.sections.sorted { $0.start < $1.start }.map { [$0.start, $0.end] } }

    // MARK: Crear

    func testMarkCreatesNamedSectionAndSolo() {
        var e = editor()
        let a = e.mark(2...8, solo: false)
        let b = e.mark(10...14, solo: true)
        XCTAssertEqual(e.section(a!)?.name, "Sección 1")
        XCTAssertEqual(e.section(b!)?.name, "Solo")
        XCTAssertTrue(e.section(b!)!.isSolo)
        XCTAssertEqual(e.sections.map(\.start), [2, 10])
        _ = e.mark(16...18, solo: true)
        XCTAssertEqual(e.sections.last?.name, "Solo 2")
        check(e)
    }

    func testMarkTooShortIsIgnored() {
        var e = editor()
        XCTAssertNil(e.mark(2...2.2, solo: false))
        XCTAssertTrue(e.sections.isEmpty)
        check(e)
    }

    func testMarkInGapBetweenSections() {
        var e = editor([Section(name: "A", start: 0, end: 4), Section(name: "B", start: 10, end: 20)])
        let id = e.mark(4...10, solo: false)!   // pegada a las dos, sin tocarlas
        XCTAssertEqual(spans(e), [[0, 4], [4, 10], [10, 20]])
        XCTAssertEqual(e.sections[1].id, id)
        check(e)
    }

    func testMarkStartingInsideCreatesNothing() {
        let before = [Section(name: "Estrofa", start: 0, end: 20)]
        var e = editor(before)
        XCTAssertNil(e.mark(6...10, solo: true))    // dentro del todo: ya no parte
        XCTAssertNil(e.mark(0...10, solo: false))   // empieza en su inicio
        XCTAssertNil(e.mark(6...30, solo: false))   // empieza dentro y sale
        XCTAssertEqual(e.sections, before)
        check(e)
    }

    func testMarkCrossingNeighbourIsTrimmedToItsEdge() {
        var e = editor([Section(name: "A", start: 0, end: 4), Section(name: "B", start: 10, end: 20), Section(name: "C", start: 30, end: 40)])
        let id = e.mark(6...35, solo: false)!   // entra en B (y pasaría por C): se queda en el borde de B
        XCTAssertEqual(e.section(id).map { [$0.start, $0.end] }, [6, 10])
        XCTAssertEqual(spans(e), [[0, 4], [6, 10], [10, 20], [30, 40]])
        check(e)
    }

    func testMarkTrimmedBelowMinimumCreatesNothing() {
        var e = editor([Section(name: "B", start: 10, end: 20)])
        XCTAssertNil(e.mark(9.7...15, solo: false))   // hueco de 0,3 s antes de B
        XCTAssertEqual(e.sections.count, 1)
        check(e)
    }

    func testMarkSameRangeOnlyTogglesSolo() {
        var e = editor([Section(name: "Estrofa", start: 4, end: 10)])
        let id = e.mark(4...10, solo: true)!
        XCTAssertEqual(e.sections.count, 1)
        XCTAssertTrue(e.section(id)!.isSolo)
        XCTAssertEqual(e.section(id)?.name, "Estrofa")
        check(e)
    }

    // MARK: Nombre y solo

    func testRenameTrimsAndEmptyFallsBackToDefault() {
        var e = editor()
        let id = e.mark(2...8, solo: false)!
        e.rename(id, to: "  Intro ")
        XCTAssertEqual(e.section(id)?.name, "Intro")
        e.rename(id, to: "   ")
        XCTAssertEqual(e.section(id)?.name, "Sección 1")
        check(e)
    }

    func testSetSoloFollowsDefaultNamesButKeepsCustomOnes() {
        var e = editor()
        let a = e.mark(2...8, solo: false)!
        e.setSolo(a, true)
        XCTAssertEqual(e.section(a)?.name, "Solo")
        e.setSolo(a, false)
        XCTAssertEqual(e.section(a)?.name, "Sección 1")
        e.rename(a, to: "Puente")
        e.setSolo(a, true)
        XCTAssertEqual(e.section(a)?.name, "Puente")
        XCTAssertTrue(e.section(a)!.isSolo)
        e.setSolo(a, false)
        XCTAssertNil(e.section(a)?.solo)
        check(e)
    }

    func testRemove() {
        var e = editor()
        let a = e.mark(2...8, solo: false)!
        let b = e.mark(10...14, solo: false)!
        e.remove(a)
        XCTAssertEqual(e.sections.map(\.id), [b])
        e.remove(UUID())
        XCTAssertEqual(e.sections.count, 1)
        check(e)
    }

    // MARK: Bordes

    func testSnapEdgeToNearestChordOrBar() {
        var e = editor()
        let id = e.mark(4...12, solo: false)!
        e.snapEdge(id, start: false, to: 15.1, boundaries: chords)
        XCTAssertEqual(e.section(id)?.end, 16)
        e.snapEdge(id, start: true, to: 2.9, boundaries: chords)
        XCTAssertEqual(e.section(id)?.start, 2)
        e.snapEdge(id, start: false, to: 9.0, boundaries: bars)
        XCTAssertEqual(e.section(id)?.end, 8)
        check(e)
    }

    func testEdgeClampedByMinimumAndSongBounds() {
        var e = editor([Section(name: "A", start: 0, end: 10), Section(name: "B", start: 12, end: 20)])
        let a = e.sections[0].id, b = e.sections[1].id
        e.setEdge(a, start: false, to: -3)
        XCTAssertEqual(e.section(a)?.end, 0.5)
        e.setEdge(a, start: true, to: -9)
        XCTAssertEqual(e.section(a)?.start, 0)
        e.setEdge(b, start: false, to: 500)
        XCTAssertEqual(e.section(b)?.end, 100)
        XCTAssertNil(e.clampedEdge(UUID(), start: true, to: 1))
        check(e)
    }

    func testPushingEndShrinksNextNeighbour() {
        var e = editor([Section(name: "A", start: 0, end: 10), Section(name: "B", start: 12, end: 20)])
        let a = e.sections[0].id
        e.setEdge(a, start: false, to: 15)   // atraviesa el hueco y entra en B
        XCTAssertEqual(spans(e), [[0, 15], [15, 20]])
        check(e)
    }

    func testPushingStartShrinksPreviousNeighbour() {
        var e = editor([Section(name: "A", start: 0, end: 10), Section(name: "B", start: 10, end: 20)])
        let b = e.sections[1].id
        e.setEdge(b, start: true, to: 4)
        XCTAssertEqual(spans(e), [[0, 4], [4, 20]])
        check(e)
    }

    func testPushingStopsWhenNeighbourReachesMinimum() {
        var e = editor([Section(name: "A", start: 0, end: 10), Section(name: "B", start: 10, end: 20)])
        let a = e.sections[0].id, b = e.sections[1].id
        e.setEdge(a, start: false, to: 50)
        XCTAssertEqual(spans(e), [[0, 19.5], [19.5, 20]])
        XCTAssertEqual(e.clampedEdge(a, start: false, to: 99), 19.5)
        e.setEdge(b, start: true, to: -5)   // y al revés: B empuja a A hasta su mínimo
        XCTAssertEqual(spans(e), [[0, 0.5], [0.5, 20]])
        check(e)
    }

    func testPushingAgainstSoloStopsAtItsEdge() {
        var e = editor([Section(name: "A", start: 0, end: 10), Section(name: "Solo", start: 12, end: 20, solo: true),
                        Section(name: "C", start: 20, end: 30)])
        let a = e.sections[0].id, c = e.sections[2].id
        e.setEdge(a, start: false, to: 16)
        XCTAssertEqual(spans(e), [[0, 12], [12, 20], [20, 30]])
        e.setEdge(c, start: true, to: 14)
        XCTAssertEqual(spans(e), [[0, 12], [12, 20], [20, 30]])
        check(e)
    }

    func testSoloPushesAndShrinksNormalSection() {
        var e = editor([Section(name: "Solo", start: 0, end: 10, solo: true), Section(name: "B", start: 10, end: 20)])
        let solo = e.sections[0].id
        e.setEdge(solo, start: false, to: 14)
        XCTAssertEqual(spans(e), [[0, 14], [14, 20]])
        check(e)
    }

    func testNoCascadeToThirdSection() {
        var e = editor([Section(name: "A", start: 0, end: 10), Section(name: "B", start: 10, end: 12),
                        Section(name: "C", start: 12, end: 20)])
        let a = e.sections[0].id
        e.setEdge(a, start: false, to: 18)   // B llega a su mínimo; C no se toca
        XCTAssertEqual(spans(e), [[0, 11.5], [11.5, 12], [12, 20]])
        check(e)
    }

    func testPullingBackLeavesGap() {
        var e = editor([Section(name: "A", start: 0, end: 10), Section(name: "B", start: 10, end: 20)])
        let a = e.sections[0].id, b = e.sections[1].id
        e.setEdge(a, start: false, to: 6)
        XCTAssertEqual(spans(e), [[0, 6], [10, 20]])
        e.setEdge(b, start: true, to: 14)
        XCTAssertEqual(spans(e), [[0, 6], [14, 20]])
        check(e)
    }

    // MARK: Teclas

    func testNudgeMovesOneChordBoundaryAtATime() {
        var e = editor()
        let id = e.mark(4...10, solo: false)!
        e.nudgeEdge(id, start: false, forward: true, boundaries: chords)
        XCTAssertEqual(e.section(id)?.end, 12)
        e.nudgeEdge(id, start: false, forward: false, boundaries: chords)
        e.nudgeEdge(id, start: false, forward: false, boundaries: chords)
        XCTAssertEqual(e.section(id)?.end, 8)
        e.nudgeEdge(id, start: true, forward: false, boundaries: chords)
        XCTAssertEqual(e.section(id)?.start, 2)
        e.nudgeEdge(id, start: true, forward: true, boundaries: chords)
        e.nudgeEdge(id, start: true, forward: true, boundaries: chords)
        XCTAssertEqual(e.section(id)?.start, 6)
        check(e)
    }

    func testNudgeByBarAndStopsAtEnds() {
        var e = editor()
        let id = e.mark(4...10, solo: false)!
        e.nudgeEdge(id, start: false, forward: true, boundaries: bars)
        XCTAssertEqual(e.section(id)?.end, 16)
        e.nudgeEdge(id, start: false, forward: true, boundaries: bars)
        XCTAssertEqual(e.section(id)?.end, 16)
        e.nudgeEdge(id, start: true, forward: false, boundaries: bars)
        XCTAssertEqual(e.section(id)?.start, 0)
        e.nudgeEdge(id, start: true, forward: false, boundaries: bars)
        XCTAssertEqual(e.section(id)?.start, 0)
        check(e)
    }

    func testNudgeFollowsPushRules() {
        var e = editor([Section(name: "A", start: 0, end: 6), Section(name: "B", start: 6, end: 10),
                        Section(name: "Solo", start: 10, end: 14, solo: true), Section(name: "D", start: 14, end: 20)])
        let a = e.sections[0].id, b = e.sections[1].id, d = e.sections[3].id
        e.nudgeEdge(a, start: false, forward: true, boundaries: chords)   // empuja a B
        XCTAssertEqual(spans(e), [[0, 8], [8, 10], [10, 14], [14, 20]])
        e.nudgeEdge(a, start: false, forward: true, boundaries: chords)   // B en su mínimo: para ahí
        XCTAssertEqual(spans(e), [[0, 9.5], [9.5, 10], [10, 14], [14, 20]])
        e.nudgeEdge(b, start: false, forward: true, boundaries: chords)   // contra el solo: no se mueve
        XCTAssertEqual(spans(e), [[0, 9.5], [9.5, 10], [10, 14], [14, 20]])
        e.nudgeEdge(d, start: true, forward: false, boundaries: chords)   // contra el solo: no se mueve
        XCTAssertEqual(spans(e), [[0, 9.5], [9.5, 10], [10, 14], [14, 20]])
        e.nudgeEdge(a, start: false, forward: false, boundaries: chords)  // se retira: B no le sigue
        XCTAssertEqual(spans(e), [[0, 8], [9.5, 10], [10, 14], [14, 20]])
        check(e)
    }

    /// Muchas ediciones al azar (crear, arrastrar, teclas, con solos): nunca solapes ni anidadas.
    func testRandomEditsNeverOverlap() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            var e = editor()
            for _ in 0..<40 {
                let ids = e.sections.map(\.id)
                switch Int.random(in: 0..<4, using: &rng) {
                case 0:
                    let a = Double.random(in: 0...98, using: &rng)
                    e.mark(a...min(100, a + Double.random(in: 0...30, using: &rng)), solo: Bool.random(using: &rng))
                case 1 where !ids.isEmpty:
                    e.setEdge(ids.randomElement(using: &rng)!, start: Bool.random(using: &rng), to: Double.random(in: -10...110, using: &rng))
                case 2 where !ids.isEmpty:
                    e.nudgeEdge(ids.randomElement(using: &rng)!, start: Bool.random(using: &rng), forward: Bool.random(using: &rng),
                                boundaries: chords + bars.map { $0 + 0.3 })
                case 3 where !ids.isEmpty:
                    e.setSolo(ids.randomElement(using: &rng)!, Bool.random(using: &rng))
                default:
                    break
                }
                check(e)
            }
        }
    }

    // MARK: Color

    func testSameNameSameColorAndNewNamesTakeNextFree() {
        let list = [Section(name: "Intro", start: 0, end: 4), Section(name: "Estribillo", start: 4, end: 8),
                    Section(name: "Estrofa", start: 8, end: 12), Section(name: "Estribillo", start: 12, end: 16)]
        let c = SectionEditor.paletteIndices(list)
        XCTAssertEqual([c[list[0].id], c[list[1].id], c[list[2].id], c[list[3].id]], [0, 1, 2, 1])
    }

    func testChosenColorWinsAndIsNotOfferedToOthers() {
        let list = [Section(name: "A", start: 0, end: 4), Section(name: "B", start: 4, end: 8, color: 0)]
        let c = SectionEditor.paletteIndices(list)
        XCTAssertEqual(c[list[1].id], 0)
        XCTAssertEqual(c[list[0].id], 1)
    }

    func testSoloHasNoPaletteColorAndKeepsChoice() {
        var e = editor([Section(name: "Puente", start: 0, end: 4, color: 3)])
        let id = e.sections[0].id
        e.setSolo(id, true)
        XCTAssertNil(SectionEditor.paletteIndices(e.sections)[id])
        e.setSolo(id, false)
        XCTAssertEqual(SectionEditor.paletteIndices(e.sections)[id], 3)
    }

    func testSetColorValidatesAndResets() {
        var e = editor([Section(name: "A", start: 0, end: 4)])
        let id = e.sections[0].id
        e.setColor(id, 4); XCTAssertEqual(e.section(id)?.color, 4)
        e.setColor(id, 99); XCTAssertEqual(e.section(id)?.color, 4)
        e.setColor(id, nil); XCTAssertNil(e.section(id)?.color)
    }

    func testPaletteExhaustedReuses() {
        let list = (0..<9).map { Section(name: "S\($0)", start: Double($0) * 2, end: Double($0) * 2 + 2) }
        let c = SectionEditor.paletteIndices(list)
        XCTAssertEqual(c.count, 9)
        XCTAssertTrue(c.values.allSatisfy { (0..<SectionEditor.paletteCount).contains($0) })
    }

    func testColorRoundTripAndOldFilesWithoutIt() throws {
        let dir = try makeTempDir("section-color")
        var p = makeFullProject()
        p.sections = [Section(name: "Estrofa", start: 10, end: 40, color: 5), Section(name: "Solo", start: 50, end: 60, solo: true)]
        try ProjectFile.save(p, to: dir)
        let r = try ProjectFile.load(folder: dir)
        XCTAssertEqual(r.sections, p.sections)
        XCTAssertEqual(r.sections[0].color, 5)
        XCTAssertNil(r.sections[1].color)
        let old = try JSONDecoder().decode(Section.self, from: Data(#"{"id":"\#(UUID().uuidString)","name":"A","start":1,"end":2}"#.utf8))
        XCTAssertNil(old.color)
    }
}
