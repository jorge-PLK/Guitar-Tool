import XCTest
@testable import Store

final class SectionEditorTests: XCTestCase {
    private func editor(_ list: [Section] = []) -> SectionEditor { SectionEditor(sections: list, duration: 100) }
    private let chords: [Double] = [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20]
    private let bars: [Double] = [0, 8, 16]

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
    }

    func testMarkTooShortIsIgnored() {
        var e = editor()
        XCTAssertNil(e.mark(2...2.2, solo: false))
        XCTAssertTrue(e.sections.isEmpty)
    }

    func testMarkInsideSplitsTheContainer() {
        var e = editor([Section(name: "Estrofa", start: 0, end: 20)])
        let id = e.mark(6...10, solo: true)!
        XCTAssertEqual(e.sections.count, 3)
        XCTAssertEqual(e.sections.map(\.start), [0, 6, 10])
        XCTAssertEqual(e.sections.map(\.end), [6, 10, 20])
        XCTAssertEqual(e.sections[0].name, "Estrofa")
        XCTAssertEqual(e.sections[2].name, "Estrofa")
        XCTAssertNotEqual(e.sections[0].id, e.sections[2].id)
        XCTAssertEqual(e.sections[1].id, id)
        XCTAssertFalse(e.sections[0].isSolo)
    }

    func testMarkOverlapTrimsNeighbours() {
        var e = editor([Section(name: "A", start: 0, end: 10), Section(name: "B", start: 10, end: 20)])
        e.mark(6...14, solo: false)
        XCTAssertEqual(e.sections.map(\.start), [0, 6, 14])
        XCTAssertEqual(e.sections.map(\.end), [6, 14, 20])
        XCTAssertEqual(e.sections.map(\.name), ["A", "Sección 1", "B"])
    }

    func testMarkSameRangeOnlyTogglesSolo() {
        var e = editor([Section(name: "Estrofa", start: 4, end: 10)])
        let id = e.mark(4...10, solo: true)!
        XCTAssertEqual(e.sections.count, 1)
        XCTAssertTrue(e.section(id)!.isSolo)
        XCTAssertEqual(e.section(id)?.name, "Estrofa")
    }

    func testMarkDropsRemnantsShorterThanMinimum() {
        var e = editor([Section(name: "A", start: 0, end: 10)])
        e.mark(0.2...10, solo: false)
        XCTAssertEqual(e.sections.count, 1)
        XCTAssertEqual(e.sections[0].start, 0.2)
    }

    func testRenameTrimsAndEmptyFallsBackToDefault() {
        var e = editor()
        let id = e.mark(2...8, solo: false)!
        e.rename(id, to: "  Intro ")
        XCTAssertEqual(e.section(id)?.name, "Intro")
        e.rename(id, to: "   ")
        XCTAssertEqual(e.section(id)?.name, "Sección 1")
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
    }

    func testRemove() {
        var e = editor()
        let a = e.mark(2...8, solo: false)!
        let b = e.mark(10...14, solo: false)!
        e.remove(a)
        XCTAssertEqual(e.sections.map(\.id), [b])
        e.remove(UUID())
        XCTAssertEqual(e.sections.count, 1)
    }

    func testSnapEdgeToNearestChordOrBar() {
        var e = editor()
        let id = e.mark(4...12, solo: false)!
        e.snapEdge(id, start: false, to: 15.1, boundaries: chords)
        XCTAssertEqual(e.section(id)?.end, 16)
        e.snapEdge(id, start: true, to: 2.9, boundaries: chords)
        XCTAssertEqual(e.section(id)?.start, 2)
        e.snapEdge(id, start: false, to: 9.0, boundaries: bars)
        XCTAssertEqual(e.section(id)?.end, 8)
    }

    func testEdgeClampedByNeighboursMinimumAndSongBounds() {
        var e = editor([Section(name: "A", start: 0, end: 10), Section(name: "B", start: 12, end: 20)])
        let a = e.sections[0].id, b = e.sections[1].id
        e.setEdge(a, start: false, to: 15)
        XCTAssertEqual(e.section(a)?.end, 12)
        e.setEdge(b, start: true, to: 5)
        XCTAssertEqual(e.section(b)?.start, 12)
        e.setEdge(a, start: false, to: -3)
        XCTAssertEqual(e.section(a)?.end, 0.5)
        e.setEdge(a, start: true, to: -9)
        XCTAssertEqual(e.section(a)?.start, 0)
        e.setEdge(b, start: false, to: 500)
        XCTAssertEqual(e.section(b)?.end, 100)
        XCTAssertNil(e.clampedEdge(UUID(), start: true, to: 1))
    }

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
    }

    func testNudgeCannotCrossNeighbourNorShrinkBelowMinimum() {
        var e = editor([Section(name: "A", start: 0, end: 6), Section(name: "B", start: 6, end: 6.8)])
        let a = e.sections[0].id, b = e.sections[1].id
        e.nudgeEdge(a, start: false, forward: true, boundaries: chords)
        XCTAssertEqual(e.section(a)?.end, 6)
        e.nudgeEdge(b, start: false, forward: false, boundaries: chords)
        XCTAssertEqual(e.section(b)?.end, 6.5)
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
