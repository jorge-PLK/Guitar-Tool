import CoreGraphics
import XCTest
@testable import Store

/// Cuenta del arrastre de un borde de sección en la tira y en la rejilla (mini-spec Fase 7b, punto 7).
final class SectionEdgeDragTests: XCTestCase {
    typealias Cell = SectionEdgeDrag.Cell

    // Rejilla con las medidas de la app: etiqueta de 84 pt, compases de 4 pulsos de 20 pt con 4 pt de hueco, 4 por fila.
    static let beat = 0.5, perBar = 4, perRow = 4
    static let left: CGFloat = 84, cellW: CGFloat = 20, barGap: CGFloat = 4, rowPitch: CGFloat = 68, band: CGFloat = 64
    static var barW: CGFloat { CGFloat(perBar) * cellW + barGap }

    /// Rejilla de `bars` compases con un acorde por bloque de `beatsPerChord` pulsos (la lista se repite); el acorde
    /// empieza `lead` s después del pulso. Devuelve las celdas, los inicios de acorde y los límites de compás.
    private func grid(bars: Int, beatsPerChord: [Int], lead: Double = 0.05) -> (cells: [Cell], starts: [Double], bars: [Double]) {
        var cells: [Cell] = [], starts: [Double] = []
        var left = 0, k = 0
        for n in 0..<(bars * Self.perBar) {
            let t = Double(n) * Self.beat
            let bar = n / Self.perBar, col = bar % Self.perRow, row = bar / Self.perRow
            var start: Double?
            if left == 0 {
                left = beatsPerChord[k % beatsPerChord.count]; k += 1
                start = t + lead; starts.append(t + lead)
            }
            left -= 1
            let x = Self.left + CGFloat(col) * Self.barW + CGFloat(n % Self.perBar) * Self.cellW
            cells.append(Cell(row: row, frame: CGRect(x: x, y: CGFloat(row) * Self.rowPitch, width: Self.cellW, height: Self.band),
                              time: t, end: t + Self.beat, chordStart: start))
        }
        return (cells, starts, (0...bars).map { Double($0 * Self.perBar) * Self.beat })
    }

    /// Tira: un chip por acorde (`spans` en s), de 60 pt con 6 pt de hueco.
    private func strip(_ spans: [(Double, Double)]) -> [Cell] {
        spans.enumerated().map { i, s in
            Cell(row: 0, frame: CGRect(x: 3 + CGFloat(i) * 66, y: 0, width: 60, height: 65), time: s.0, end: s.1, chordStart: s.0)
        }
    }

    private func drag(_ e: SectionEditor, _ index: Int, isStart: Bool, cells: [Cell], bars: [Double], grab: CGPoint) -> SectionEdgeDrag {
        SectionEdgeDrag(editor: e, id: e.sections[index].id, isStart: isStart, cells: cells, bars: bars, grab: grab)!
    }

    /// Punto donde la vista dibuja el borde (el asa se centra ahí).
    private func drawn(_ t: Double, row: Int, _ cells: [Cell]) -> CGPoint {
        SectionEdgeDrag.point(for: t, near: CGPoint(x: 0, y: CGFloat(row) * Self.rowPitch + 30), in: cells)!
    }

    /// Lo que hacía la rejilla hasta la Fase 7b (`StudyKit.SectionEdgePicker.edgeTime`, sin imán al compás): el límite
    /// del acorde bajo el punto ABSOLUTO del puntero más cercano a la mitad de la celda.
    private func oldGridEdge(at p: CGPoint, _ cells: [Cell]) -> Double {
        func gap(_ lo: CGFloat, _ hi: CGFloat, _ v: CGFloat) -> CGFloat { v < lo ? lo - v : (v > hi ? v - hi : 0) }
        let row = cells.min { gap($0.frame.minY, $0.frame.maxY, p.y) < gap($1.frame.minY, $1.frame.maxY, p.y) }!.row
        let i = cells.indices.filter { cells[$0].row == row }
            .min { gap(cells[$0].frame.minX, cells[$0].frame.maxX, p.x) < gap(cells[$1].frame.minX, cells[$1].frame.maxX, p.x) }!
        let mid = (cells[i].time + cells[i].end) / 2
        var a = i
        while a > 0, cells[a].chordStart == nil { a -= 1 }
        var b = i + 1
        while b < cells.count, cells[b].chordStart == nil { b += 1 }
        let lo = cells[a].chordStart ?? cells[a].time
        let hi = b < cells.count ? (cells[b].chordStart ?? cells[b].time) : cells[cells.count - 1].end
        return mid - lo < hi - mid ? lo : hi
    }

    // MARK: Borde inicial

    /// El fallo de agarre: el asa mide 16 pt; agarrada a 6 pt del borde (dentro del acorde de 1 pulso que cierra la
    /// sección), la cuenta vieja tomaba el punto absoluto y el borde saltaba un acorde atrás sin mover el ratón.
    func testGrabbingOffCentreDoesNotJump() {
        let (cells, starts, bars) = grid(bars: 8, beatsPerChord: [3, 1])   // acordes de 3 y 1 pulsos
        let end = starts[2]                                                 // tras el acorde de 1 pulso
        let e = SectionEditor(sections: [Section(name: "A", start: starts[0], end: end)], duration: 100)
        let edge = drawn(end, row: 0, cells)
        for dx in [-7, -6, -3, 0, 3, 6, 7] as [CGFloat] {
            let grab = CGPoint(x: edge.x + dx, y: edge.y)
            let d = drag(e, 0, isStart: false, cells: cells, bars: bars, grab: grab)
            XCTAssertEqual(d.edge(at: grab, bar: false), end, "agarrada a \(dx) pt")
            XCTAssertEqual(d.edge(at: CGPoint(x: grab.x + 1, y: grab.y), bar: false), end, "primer movimiento (1 pt)")
        }
        // Referencia: la cuenta vieja salta con el asa agarrada a 6 pt por la izquierda.
        XCTAssertEqual(oldGridEdge(at: CGPoint(x: edge.x - 6, y: edge.y), cells), starts[1])
        XCTAssertNotEqual(oldGridEdge(at: CGPoint(x: edge.x - 6, y: edge.y), cells), end)
    }

    func testEdgeFollowsPointerByTheSameDistance() {
        let (cells, starts, bars) = grid(bars: 8, beatsPerChord: [4])
        let e = SectionEditor(sections: [Section(name: "A", start: 0, end: starts[2])], duration: 100)
        let edge = drawn(starts[2], row: 0, cells)
        let grab = CGPoint(x: edge.x - 5, y: edge.y + 10)
        let d = drag(e, 0, isStart: false, cells: cells, bars: bars, grab: grab)
        XCTAssertEqual(d.edge(at: CGPoint(x: grab.x + Self.barW, y: grab.y), bar: false), starts[3])      // +1 compás
        XCTAssertEqual(d.edge(at: CGPoint(x: grab.x - Self.barW, y: grab.y), bar: false), starts[1])      // −1 compás
        XCTAssertEqual(d.edge(at: CGPoint(x: grab.x + Self.barW * 0.4, y: grab.y), bar: false), starts[2]) // menos de medio: imán al suyo
    }

    // MARK: Filas (lo que falla en la rejilla expandida)

    /// Alargar una sección que acaba en fin de fila (frases de 4 compases): el borde pasa a la fila siguiente y
    /// vuelve. El punto de partida es el borde dibujado al final de la fila de arriba, no el inicio de la de abajo.
    func testEndEdgeCrossesRowsBothWays() {
        let (cells, _, bars) = grid(bars: 12, beatsPerChord: [4], lead: 0)
        let rowEnd = 8.0   // fin de la fila 0 = inicio de la fila 1
        let e = SectionEditor(sections: [Section(name: "A", start: 0, end: rowEnd)], duration: 100)
        let edge = drawn(rowEnd, row: 0, cells)
        XCTAssertEqual(edge.x, Self.left + 3 * Self.barW + 4 * Self.cellW, accuracy: 1e-9)   // al final de la fila 0
        let grab = CGPoint(x: edge.x + 2, y: edge.y)
        let d = drag(e, 0, isStart: false, cells: cells, bars: bars, grab: grab)
        XCTAssertEqual(d.edge(at: grab, bar: false), rowEnd)
        // Bajar una fila y ir al 2.º compás: 10 s.
        let down = CGPoint(x: Self.left + Self.barW + 12, y: grab.y + Self.rowPitch)
        XCTAssertEqual(d.edge(at: down, bar: false), 10)
        XCTAssertEqual(d.sections(at: down, bar: false).map(\.end), [10])
        // Subir otra vez a la fila 0, 3.er compás: encoge a 4 s.
        XCTAssertEqual(d.edge(at: CGPoint(x: Self.left + 2 * Self.barW + 8, y: grab.y), bar: false), 4)
    }

    func testStartEdgeCrossesRowUp() {
        let (cells, _, bars) = grid(bars: 12, beatsPerChord: [4], lead: 0)
        let e = SectionEditor(sections: [Section(name: "A", start: 8, end: 16)], duration: 100)
        let edge = drawn(8, row: 1, cells)
        XCTAssertEqual(edge.x, Self.left, accuracy: 1e-9)   // al principio de la fila 1
        let d = drag(e, 0, isStart: true, cells: cells, bars: bars, grab: edge)
        XCTAssertEqual(d.edge(at: CGPoint(x: Self.left + 2 * Self.barW + 10, y: edge.y - Self.rowPitch), bar: false), 4)
    }

    func testRowChangeFollowsPointerVertically() {
        let (cells, _, bars) = grid(bars: 12, beatsPerChord: [4])
        XCTAssertEqual(SectionEdgeDrag.time(at: CGPoint(x: Self.left + 10, y: 25), in: cells), 0.25)
        XCTAssertEqual(SectionEdgeDrag.time(at: CGPoint(x: Self.left + 10, y: Self.rowPitch + 25), in: cells), 8.25)
        XCTAssertEqual(SectionEdgeDrag.time(at: CGPoint(x: Self.left + 10, y: Self.rowPitch - 1), in: cells), 8.25)   // hueco entre filas, más cerca de la 1
        XCTAssertEqual(SectionEdgeDrag.time(at: CGPoint(x: Self.left + 10, y: 9999), in: cells), 16.25)              // bajo la última fila
        XCTAssertEqual(SectionEdgeDrag.time(at: CGPoint(x: 0, y: 25), in: cells), 0)                                  // sobre la etiqueta
        XCTAssertEqual(SectionEdgeDrag.time(at: CGPoint(x: 9999, y: 25), in: cells), 8)                               // pasado el fin de fila
        _ = bars
    }

    // MARK: Imán

    private func sweep(_ d: SectionEdgeDrag, row: Int, bar: Bool) -> [Double] {
        var out: [Double] = []
        for x in stride(from: Self.left - 10, through: Self.left + CGFloat(Self.perRow) * Self.barW + 10, by: 1) {
            let t = d.snappedTime(at: CGPoint(x: x, y: CGFloat(row) * Self.rowPitch + 25), bar: bar)
            if out.last != t { out.append(t) }
        }
        return out
    }

    func testChordMagnetAdvancesOneVisibleChordAtATime() {
        let (cells, starts, bars) = grid(bars: 12, beatsPerChord: [4, 2, 2, 4, 2, 2])
        let all = Array(Set([0] + starts + [24])).sorted()
        let e = SectionEditor(sections: [Section(name: "A", start: 0, end: starts[1])], duration: 100)
        let edge = drawn(starts[1], row: 0, cells)
        let d = drag(e, 0, isStart: false, cells: cells, bars: bars, grab: edge)
        for row in 0..<3 {
            let seq = sweep(d, row: row, bar: false)
            XCTAssertEqual(seq, seq.sorted())
            XCTAssertGreaterThanOrEqual(seq.count, 4)
            for t in seq { XCTAssertTrue(all.contains(t), "fila \(row): \(t) no es un cambio de acorde dibujado") }
            for (a, b) in zip(seq, seq.dropFirst()) {
                XCTAssertEqual(all.firstIndex(of: b)! - all.firstIndex(of: a)!, 1, "fila \(row): salta de \(a) a \(b)")
            }
        }
    }

    func testBarMagnetAdvancesOneBarAtATime() {
        let (cells, _, bars) = grid(bars: 12, beatsPerChord: [2])
        let e = SectionEditor(sections: [Section(name: "A", start: 0, end: 8)], duration: 100)
        let d = drag(e, 0, isStart: false, cells: cells, bars: bars, grab: drawn(8, row: 0, cells))
        for row in 0..<3 {
            let seq = sweep(d, row: row, bar: true)
            XCTAssertGreaterThanOrEqual(seq.count, 4)
            for (a, b) in zip(seq, seq.dropFirst()) { XCTAssertEqual(b - a, 2.0, accuracy: 1e-9) }
        }
    }

    func testBarMagnetFallsBackToChordsWithoutBars() {
        let (cells, starts, _) = grid(bars: 4, beatsPerChord: [2])
        let e = SectionEditor(sections: [Section(name: "A", start: 0, end: starts[2])], duration: 100)
        let edge = drawn(starts[2], row: 0, cells)
        let d = drag(e, 0, isStart: false, cells: cells, bars: [], grab: edge)
        XCTAssertEqual(d.edge(at: CGPoint(x: edge.x + 2 * Self.cellW, y: edge.y), bar: true), starts[3])
    }

    // MARK: Límites (reglas del punto 8 en la vista previa)

    func testDragPushesNeighbourAndStopsAtMinimumOrSolo() {
        let (cells, _, bars) = grid(bars: 8, beatsPerChord: [4], lead: 0)
        let e = SectionEditor(sections: [Section(name: "A", start: 0, end: 4), Section(name: "B", start: 4, end: 12)], duration: 100)
        let edge = drawn(4, row: 0, cells)
        let d = drag(e, 0, isStart: false, cells: cells, bars: bars, grab: edge)
        let twoBars = CGPoint(x: edge.x + 2 * Self.barW, y: edge.y)
        XCTAssertEqual(d.sections(at: twoBars, bar: false).map { [$0.start, $0.end] }, [[0, 8], [8, 12]])
        XCTAssertEqual(d.sections(at: CGPoint(x: edge.x + 9 * Self.barW, y: edge.y + Self.rowPitch), bar: false).map { [$0.start, $0.end] },
                       [[0, 11.5], [11.5, 12]])
        var solo = e; solo.setSolo(e.sections[1].id, true)
        let s = drag(solo, 0, isStart: false, cells: cells, bars: bars, grab: edge)
        XCTAssertEqual(s.sections(at: twoBars, bar: false).map { [$0.start, $0.end] }, [[0, 4], [4, 12]])
        // La vista previa no cambia el editor de partida: cada posición se calcula desde el borde inicial.
        XCTAssertEqual(d.editor, e)
    }

    // MARK: Tira

    func testStripPointerToChordBoundary() {
        let cells = strip([(0, 2), (2, 4), (4, 7), (7, 8), (8, 12)])
        let e = SectionEditor(sections: [Section(name: "A", start: 0, end: 4)], duration: 100)
        let edge = drawn(4, row: 0, cells)
        XCTAssertEqual(edge.x, 3 + 66 + 60, accuracy: 1e-9)   // fin del 2.º chip
        let grab = CGPoint(x: edge.x + 5, y: 40)              // en el hueco entre chips
        let d = drag(e, 0, isStart: false, cells: cells, bars: [0, 4, 8, 12], grab: grab)
        // El borde efectivo es el dibujado (129) más lo que se mueve el puntero.
        func at(_ x: CGFloat) -> CGPoint { CGPoint(x: grab.x + x - edge.x, y: 40) }
        XCTAssertEqual(d.edge(at: grab, bar: false), 4)
        XCTAssertEqual(d.edge(at: at(135 + 15), bar: false), 4)   // primer cuarto del acorde 4–7
        XCTAssertEqual(d.edge(at: at(135 + 40), bar: false), 7)   // pasados dos tercios
        XCTAssertEqual(d.edge(at: at(201 + 30), bar: true), 8)    // mitad del 7–8, imán al compás
        XCTAssertEqual(d.edge(at: at(-50), bar: false), 0.5)      // no baja del mínimo
    }

    /// Las dos vistas, sobre la misma canción, llevan el borde al mismo tiempo cuando el puntero está en el mismo
    /// sitio musical.
    func testStripAndGridAgree() {
        let (gcells, starts, bars) = grid(bars: 8, beatsPerChord: [4], lead: 0)
        let scells = strip(starts.map { ($0, $0 + 2) })
        let e = SectionEditor(sections: [Section(name: "A", start: 0, end: 4)], duration: 100)
        let g = drag(e, 0, isStart: false, cells: gcells, bars: bars, grab: drawn(4, row: 0, gcells))
        let s = drag(e, 0, isStart: false, cells: scells, bars: bars, grab: drawn(4, row: 0, scells))
        for bar in 0..<8 {
            for frac in [0.1, 0.3, 0.7, 0.9] {
                let gp = CGPoint(x: Self.left + CGFloat(bar % 4) * Self.barW + CGFloat(frac) * 4 * Self.cellW,
                                 y: CGFloat(bar / 4) * Self.rowPitch + 30)
                let sp = CGPoint(x: 3 + CGFloat(bar) * 66 + CGFloat(frac) * 60, y: 30)
                XCTAssertEqual(g.edge(at: gp, bar: false), s.edge(at: sp, bar: false), "compás \(bar), \(frac)")
            }
        }
    }
}
