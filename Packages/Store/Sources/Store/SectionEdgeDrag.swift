import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Cuenta del arrastre de un borde de sección, la misma en la tira plegada y en la rejilla expandida (mini-spec
/// Fase 7b, punto 7): posición del puntero → tiempo, borde inicial, imán y límites (`SectionEditor`, punto 8).
/// Sin vistas: la tira y la rejilla solo describen lo que dibujan como celdas y aplican el resultado.
///
/// - Posición → tiempo: la fila cuya franja contiene la y (la más cercana si cae fuera) y, en ella, la celda bajo la
///   x (la más cercana si cae en un hueco); el tiempo se interpola dentro de la celda.
/// - Borde inicial: el puntero se mide desde donde está dibujado el borde, no desde donde se agarró el asa (que tiene
///   16 pt de ancho). Sin moverse, el borde no salta; con el puntero, avanza lo mismo que él.
/// - Imán: el límite más cercano entre los cambios de acorde dibujados (o los compases con ⌥) y el borde inicial.
/// - Límites: `SectionEditor.clampedEdge` (empuja a la vecina hasta `minLength`, se para contra un solo).
public struct SectionEdgeDrag: Sendable, Equatable {
    /// Lo que dibuja la vista: un acorde (tira) o un pulso (rejilla).
    public struct Cell: Sendable, Equatable {
        /// Fila (la tira tiene una sola).
        public var row: Int
        /// Marco de la celda; su franja vertical es la de la fila entera.
        public var frame: CGRect
        public var time: Double
        public var end: Double
        /// Límite de acorde que se dibuja en esta celda (el inicio del acorde que empieza aquí); nil si no cambia.
        public var chordStart: Double?

        public init(row: Int, frame: CGRect, time: Double, end: Double, chordStart: Double?) {
            self.row = row; self.frame = frame; self.time = time; self.end = end; self.chordStart = chordStart
        }
    }

    public let id: UUID
    public let isStart: Bool
    /// Tiempo del borde al empezar el arrastre.
    public let original: Double
    /// Secciones al empezar el arrastre (la vista previa y el resultado se calculan siempre desde aquí).
    public let editor: SectionEditor
    /// Celdas en orden de reproducción.
    public let cells: [Cell]
    let chordMagnet: [Double]
    let barMagnet: [Double]
    /// Punto del borde dibujado y punto donde se agarró el asa.
    let anchor: CGPoint
    let grab: CGPoint

    /// Empieza un arrastre del borde (`isStart`) de la sección `id`, agarrado en `grab`. `bars`: límites de compás
    /// (imán con ⌥). Nil si la sección no existe.
    public init?(editor: SectionEditor, id: UUID, isStart: Bool, cells: [Cell], bars: [Double], grab: CGPoint) {
        guard let s = editor.section(id) else { return nil }
        self.id = id
        self.isStart = isStart
        self.original = isStart ? s.start : s.end
        self.editor = editor
        self.cells = cells
        var chords = cells.compactMap(\.chordStart)
        if let first = cells.first, let last = cells.last { chords += [first.time, last.end] }
        self.chordMagnet = Array(Set(chords)).sorted()
        self.barMagnet = Array(Set(bars)).sorted()
        self.grab = grab
        self.anchor = Self.point(for: original, near: grab, in: cells) ?? grab
    }

    // MARK: Posición ↔ tiempo

    private static func gap(_ lo: CGFloat, _ hi: CGFloat, _ v: CGFloat) -> CGFloat { v < lo ? lo - v : (v > hi ? v - hi : 0) }

    /// Fila más cercana a la y (la que contiene la y, si alguna).
    private static func row(at y: CGFloat, in cells: [Cell]) -> Int? {
        cells.min { gap($0.frame.minY, $0.frame.maxY, y) < gap($1.frame.minY, $1.frame.maxY, y) }?.row
    }

    /// Tiempo bajo `p`, sin imán: interpolado dentro de la celda de la fila más cercana.
    public static func time(at p: CGPoint, in cells: [Cell]) -> Double? {
        guard let r = row(at: p.y, in: cells),
              let c = cells.filter({ $0.row == r }).min(by: { gap($0.frame.minX, $0.frame.maxX, p.x) < gap($1.frame.minX, $1.frame.maxX, p.x) })
        else { return nil }
        let f = c.frame.width > 0 ? min(max((p.x - c.frame.minX) / c.frame.width, 0), 1) : 0
        return c.time + Double(f) * (c.end - c.time)
    }

    /// Punto donde se dibuja `time`: en la fila que lo contiene más cercana a `near` (en un salto de fila, el borde
    /// está al final de una y al principio de la siguiente), con la y de `near` dentro de su franja.
    static func point(for time: Double, near: CGPoint, in cells: [Cell]) -> CGPoint? {
        let rows = Set(cells.map(\.row)).filter { r in
            let rc = cells.filter { $0.row == r }
            return rc.first!.time - SectionEditor.sameTime <= time && time <= rc.last!.end + SectionEditor.sameTime
        }
        let candidates = cells.filter { rows.contains($0.row) }
        guard let r = candidates.min(by: { gap($0.frame.minY, $0.frame.maxY, near.y) < gap($1.frame.minY, $1.frame.maxY, near.y) })?.row
        else { return nil }
        let rc = cells.filter { $0.row == r }
        let c = rc.first { $0.time <= time && time <= $0.end } ?? (time < rc.first!.time ? rc.first! : rc.last!)
        let f = c.end > c.time ? min(max((time - c.time) / (c.end - c.time), 0), 1) : 0
        return CGPoint(x: c.frame.minX + CGFloat(f) * c.frame.width, y: min(max(near.y, c.frame.minY), c.frame.maxY))
    }

    // MARK: Arrastre

    /// Punto efectivo del borde con el puntero en `location`: el borde dibujado más lo que se ha movido el puntero.
    public func edgePoint(at location: CGPoint) -> CGPoint {
        CGPoint(x: anchor.x + location.x - grab.x, y: anchor.y + location.y - grab.y)
    }

    /// Tiempo bajo el puntero con imán (acordes; compases con `bar`, si los hay), sin límites.
    public func snappedTime(at location: CGPoint, bar: Bool) -> Double {
        guard let t = Self.time(at: edgePoint(at: location), in: cells) else { return original }
        let magnet = (bar && !barMagnet.isEmpty ? barMagnet : chordMagnet) + [original]
        return SectionEditor.snap(t, to: magnet)
    }

    /// Dónde queda el borde con el puntero en `location`: con imán y con las reglas de `SectionEditor`.
    public func edge(at location: CGPoint, bar: Bool) -> Double {
        editor.clampedEdge(id, start: isStart, to: snappedTime(at: location, bar: bar)) ?? original
    }

    /// Secciones como quedarían al soltar en `location` (la vista previa; incluye la vecina empujada).
    public func sections(at location: CGPoint, bar: Bool) -> [Section] {
        var e = editor
        e.setEdge(id, start: isStart, to: edge(at: location, bar: bar))
        return e.sections
    }
}
