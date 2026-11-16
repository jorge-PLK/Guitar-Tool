import CoreGraphics
import Foundation

/// Puntero → límite de acorde (o de compás) en la rejilla expandida, para arrastrar los bordes de sección
/// (mini-spec Fase 4, «Opciones de guitarras y tramos de solo»: el borde se engancha al límite bajo el puntero, ⌥ = compás).
///
/// Trabaja sobre lo que la rejilla DIBUJA (celdas de pulso con su marco), no sobre los segmentos de acorde crudos:
/// los límites son los cambios de acorde visibles. Así el borde avanza de uno en uno siguiendo al puntero.
public struct SectionEdgePicker: Sendable {
    public struct Cell: Sendable {
        /// Fila de la rejilla.
        public var row: Int
        /// Marco de la celda; su franja vertical (minY...maxY) es la de la fila entera.
        public var frame: CGRect
        public var time: Double
        public var end: Double
        /// Inicio del segmento de acorde que suena en la celda (nil si no hay).
        public var chordStart: Double?
        /// El acorde mostrado cambia respecto a la celda anterior.
        public var isChange: Bool
        public var barStart: Double
        public var barEnd: Double

        public init(row: Int, frame: CGRect, time: Double, end: Double, chordStart: Double?, isChange: Bool,
                    barStart: Double, barEnd: Double) {
            self.row = row; self.frame = frame; self.time = time; self.end = end
            self.chordStart = chordStart; self.isChange = isChange; self.barStart = barStart; self.barEnd = barEnd
        }
    }

    /// Celdas en orden de reproducción (fila a fila, de izquierda a derecha).
    public let cells: [Cell]

    public init(cells: [Cell]) { self.cells = cells }

    /// Índice de la celda bajo `p`: la fila cuya franja contiene la y (la más cercana si cae entre filas) y, dentro
    /// de ella, la celda con x más próxima.
    public func cellIndex(at p: CGPoint) -> Int? {
        guard !cells.isEmpty else { return nil }
        func gap(_ lo: CGFloat, _ hi: CGFloat, _ v: CGFloat) -> CGFloat { v < lo ? lo - v : (v > hi ? v - hi : 0) }
        guard let row = cells.min(by: {
            gap($0.frame.minY, $0.frame.maxY, p.y) < gap($1.frame.minY, $1.frame.maxY, p.y)
        })?.row else { return nil }
        return cells.indices.filter { cells[$0].row == row }
            .min { gap(cells[$0].frame.minX, cells[$0].frame.maxX, p.x) < gap(cells[$1].frame.minX, cells[$1].frame.maxX, p.x) }
    }

    /// Tiempo del límite de acorde (o de compás con `bar`) más cercano al punto dentro del acorde (compás) bajo `p`.
    public func edgeTime(at p: CGPoint, bar: Bool) -> Double? {
        guard let i = cellIndex(at: p) else { return nil }
        let c = cells[i]
        let mid = (c.time + c.end) / 2
        let lo: Double, hi: Double
        if bar {
            lo = c.barStart; hi = c.barEnd
        } else {
            var a = i
            while a > 0, !cells[a].isChange { a -= 1 }
            var b = i + 1
            while b < cells.count, !cells[b].isChange { b += 1 }
            lo = cells[a].chordStart ?? cells[a].time
            hi = b < cells.count ? (cells[b].chordStart ?? cells[b].time) : cells[cells.count - 1].end
        }
        return mid - lo < hi - mid ? lo : hi
    }
}
