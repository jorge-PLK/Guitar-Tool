import CoreGraphics
import XCTest
@testable import StudyKit

final class SectionEdgePickerTests: XCTestCase {
    static let beat = 0.5, perBar = 4, perRow = 4, cellW: CGFloat = 20, rowPitch: CGFloat = 60

    /// Rejilla de `bars` compases con un acorde por bloque de `beatsPerChord` pulsos (la lista se repite).
    /// Devuelve el picker y los inicios de acorde visibles.
    private func make(bars: Int, beatsPerChord: [Int]) -> (SectionEdgePicker, [Double]) {
        var cells: [SectionEdgePicker.Cell] = []
        var starts: [Double] = []
        var chordLen = 0, k = 0
        var chordStart = 0.0
        for n in 0..<(bars * Self.perBar) {
            let t = Double(n) * Self.beat
            let bar = n / Self.perBar, col = bar % Self.perRow, row = bar / Self.perRow
            var change = false
            if chordLen == 0 {
                chordLen = beatsPerChord[k % beatsPerChord.count]; k += 1
                chordStart = t + 0.05; change = true; starts.append(chordStart)
            }
            chordLen -= 1
            let x = CGFloat(col * Self.perBar + n % Self.perBar) * Self.cellW
            cells.append(.init(row: row, frame: CGRect(x: x, y: CGFloat(row) * Self.rowPitch, width: Self.cellW, height: 50),
                               time: t, end: t + Self.beat, chordStart: chordStart, isChange: change,
                               barStart: Double(bar * Self.perBar) * Self.beat, barEnd: Double((bar + 1) * Self.perBar) * Self.beat))
        }
        return (SectionEdgePicker(cells: cells), starts)
    }

    private func sweep(_ p: SectionEdgePicker, row: Int, bar: Bool) -> [Double] {
        stride(from: CGFloat(0), to: CGFloat(Self.perRow * Self.perBar) * Self.cellW, by: 1).compactMap {
            p.edgeTime(at: CGPoint(x: $0, y: CGFloat(row) * Self.rowPitch + 25), bar: bar)
        }
    }

    func testChordEdgeAdvancesOneChordAtATime() {
        // 1 y 2 acordes por compás, varias filas.
        let (p, starts) = make(bars: 12, beatsPerChord: [4, 2, 2, 4, 2, 2])
        let all = starts + [12 * 4 * 0.5]
        for row in 0..<3 {
            let seq = sweep(p, row: row, bar: false)
            XCTAssertEqual(seq, seq.sorted())
            var distinct: [Double] = []
            for t in seq where distinct.last != t { distinct.append(t) }
            XCTAssertGreaterThanOrEqual(distinct.count, 4)
            for (a, b) in zip(distinct, distinct.dropFirst()) {
                let ia = all.firstIndex(of: a)!, ib = all.firstIndex(of: b)!
                XCTAssertEqual(ib - ia, 1, "fila \(row): salta de \(a) a \(b)")
            }
        }
    }

    func testBarEdgeAdvancesOneBarAtATime() {
        let (p, _) = make(bars: 12, beatsPerChord: [2])
        for row in 0..<3 {
            var distinct: [Double] = []
            for t in sweep(p, row: row, bar: true) where distinct.last != t { distinct.append(t) }
            for (a, b) in zip(distinct, distinct.dropFirst()) { XCTAssertEqual(b - a, 2.0, accuracy: 1e-9) }
            XCTAssertGreaterThanOrEqual(distinct.count, 4)
        }
    }

    func testRowChangeFollowsPointerVertically() {
        let (p, _) = make(bars: 12, beatsPerChord: [4])
        XCTAssertEqual(p.edgeTime(at: CGPoint(x: 10, y: 25), bar: true), 0)
        XCTAssertEqual(p.edgeTime(at: CGPoint(x: 10, y: Self.rowPitch + 25), bar: true), 8)
        XCTAssertEqual(p.edgeTime(at: CGPoint(x: 10, y: Self.rowPitch - 3), bar: true), 8)   // hueco entre filas 0 y 1
        XCTAssertEqual(p.edgeTime(at: CGPoint(x: 10, y: 9999), bar: true), 16)               // bajo la última fila: su inicio
    }

    func testReturnedTimeIsAlwaysAnExactBoundary() {
        // El tope con el otro borde lo pone SectionEditor.clampedEdge; aquí, que nunca es un punto intermedio.
        let (p, starts) = make(bars: 4, beatsPerChord: [1, 3, 2, 2])
        let all = Set(starts + [8.0])
        for t in sweep(p, row: 0, bar: false) { XCTAssertTrue(all.contains(t), "\(t)") }
    }

    /// El método anterior (tiempo del borde de celda + imán al segmento de acorde crudo más cercano) acababa en
    /// segmentos más cortos que un pulso que la rejilla no dibuja; el nuevo, solo en cambios de acorde visibles.
    func testOldRawSnapLandedOnHiddenChords() {
        let (p, starts) = make(bars: 4, beatsPerChord: [4])
        let raw = (starts + (0..<16).map { Double($0) * 0.5 + 0.2 }).sorted()
        func old(_ x: CGFloat) -> Double {
            let c = p.cells[p.cellIndex(at: CGPoint(x: x, y: 25))!]
            let t = x < c.frame.midX ? c.time : c.end
            return raw.min { abs($0 - t) < abs($1 - t) }!
        }
        XCTAssertFalse(starts.contains(old(10)))
        XCTAssertEqual(p.edgeTime(at: CGPoint(x: 10, y: 25), bar: false), starts[0])
        XCTAssertEqual(p.edgeTime(at: CGPoint(x: 70, y: 25), bar: false), starts[1])
    }
}
