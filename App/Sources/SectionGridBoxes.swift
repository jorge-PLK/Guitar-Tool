import AppKit
import Store
import StudyKit
import SwiftUI

/// Cajas de sección sobre la rejilla expandida (mismo aspecto y gestos que la tira, `SectionBoxes.swift`). Una sección
/// que cruza filas se parte en un trozo de caja por fila; el nombre y la ventana van en el primero y las asas, en los
/// bordes reales. Todo en el espacio de coordenadas "grid" (el contenido del ScrollView de la rejilla).
struct GridSectionBoxes: View {
    let session: StudySession
    let ctl: BackingController
    let rows: [[ChordGridLayout.Bar]]
    let geometry: ChordGridGeometry
    let selection: SectionSelection

    static let space = "grid"
    /// Cuánto sobresale la caja de las celdas, a los lados y por debajo.
    static let inset: CGFloat = 2

    /// Un trozo de caja: fila, marco en el espacio de la rejilla, y si es el primero / el último de la sección.
    struct Piece: Equatable {
        var row: Int
        var rect: CGRect
        var isFirst: Bool
        var isLast: Bool
    }

    @State private var preview: SectionEdgePreview?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(session.sections, id: \.id) { s in
                let shown = preview.applied(to: s)
                ForEach(Array(Self.pieces(of: shown, rows: rows, geometry: geometry).enumerated()), id: \.offset) { _, p in
                    SectionBoxPiece(session: session, ctl: ctl, section: shown, size: p.rect.size,
                                    headerHeight: ChordGridView.sectionGutter, isFirst: p.isFirst,
                                    hasStart: p.isFirst, hasEnd: p.isLast, selection: selection, space: Self.space) { isStart, pt, ended in
                        drag(s.id, isStart: isStart, point: pt, ended: ended)
                    }
                    .offset(x: p.rect.minX, y: p.rect.minY)
                }
            }
        }
    }

    /// Trozos de la caja de `s`: por cada fila, de la primera a la última celda cuyo punto medio cae dentro de la sección.
    static func pieces(of s: SongSection, rows: [[ChordGridLayout.Bar]], geometry g: ChordGridGeometry) -> [Piece] {
        var out: [Piece] = []
        for (r, bars) in rows.enumerated() {
            var lo = CGFloat.greatestFiniteMagnitude, hi = -CGFloat.greatestFiniteMagnitude
            for (c, bar) in bars.enumerated() {
                for (k, cell) in bar.cells.enumerated() where s.start <= (cell.time + cell.end) / 2 && (cell.time + cell.end) / 2 < s.end {
                    let f = g.cellFrame(row: r, col: c, beat: k, beatCount: bar.cells.count)
                    lo = min(lo, f.minX); hi = max(hi, f.maxX)
                }
            }
            guard lo <= hi else { continue }
            let y = CGFloat(r) * g.rowPitch
            out.append(Piece(row: r, rect: CGRect(x: lo - inset, y: y, width: hi - lo + 2 * inset,
                                                  height: ChordGridView.sectionGutter + ChordGridView.rowHeight + inset),
                             isFirst: out.isEmpty, isLast: false))
        }
        if !out.isEmpty { out[out.count - 1].isLast = true }
        return out
    }

    private func drag(_ id: UUID, isStart: Bool, point p: CGPoint, ended: Bool) {
        let bar = NSEvent.modifierFlags.contains(.option)
        let picker = Self.picker(rows: rows, geometry: geometry, chords: session.effectiveChords)
        guard let t = picker.edgeTime(at: p, bar: bar) else { preview = nil; return }
        if ended {
            preview = nil
            session.setSectionEdge(id, start: isStart, to: t)
        } else if let clamped = session.clampedEdge(id, start: isStart, to: t) {
            preview = SectionEdgePreview(id: id, isStart: isStart, time: clamped)
        }
    }

    /// Celdas de la rejilla con su marco (franja de la fila entera en vertical) para `SectionEdgePicker`.
    static func picker(rows: [[ChordGridLayout.Bar]], geometry g: ChordGridGeometry, chords: [ChordSegment]) -> SectionEdgePicker {
        var cells: [SectionEdgePicker.Cell] = []
        for (r, bars) in rows.enumerated() {
            for (c, bar) in bars.enumerated() {
                for (k, cell) in bar.cells.enumerated() {
                    let f = g.cellFrame(row: r, col: c, beat: k, beatCount: bar.cells.count)
                    let band = CGRect(x: f.minX, y: CGFloat(r) * g.rowPitch, width: f.width, height: g.rowPitch - ChordGridView.rowSpacing)
                    cells.append(.init(row: r, frame: band, time: cell.time, end: cell.end,
                                       chordStart: cell.chord.map { chords[$0].start }, isChange: cell.isChange,
                                       barStart: bar.start, barEnd: bar.end))
                }
            }
        }
        return SectionEdgePicker(cells: cells)
    }
}

/// Barra espaciadora = reproducir/pausar en Backing track y Tablatura. Se atiende en el monitor de eventos (antes que
/// el botón enfocado o la vista web, que harían su propia acción) y el evento se consume: sin doble conmutación.
/// No actúa si se está escribiendo (el editor de campo es un `NSText`) ni con modificadores ni si hay otra ventana/hoja.
@MainActor
final class SpaceKeyMonitor {
    private var token: Any?

    func install(toggle: @escaping @MainActor () -> Void) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let window = NSApp.keyWindow, window.sheetParent == nil, window.attachedSheet == nil,
                      event.window === window, !(window.firstResponder is NSText) else { return false }
                if !event.isARepeat { toggle() }
                return true
            }
            return handled ? nil : event
        }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

/// Supr / Retroceso borran la sección seleccionada y Esc la deselecciona, salvo que se esté escribiendo en un campo
/// (el nombre de la ventana de la sección). Vale para la tira y la rejilla: la selección es compartida.
@MainActor
final class SectionKeyMonitor {
    private var token: Any?

    func install(selection: SectionSelection, session: StudySession) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = event.keyCode, mods = event.modifierFlags.intersection([.command, .control, .option])
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let id = selection.selected, mods.isEmpty, !(NSApp.keyWindow?.firstResponder is NSText) else { return false }
                switch code {
                case 51, 117:   // retroceso, suprimir
                    selection.clear()
                    session.removeSection(id)
                    return true
                case 53 where selection.popover == nil:   // Esc
                    selection.clear()
                    return true
                default:
                    return false
                }
            }
            return handled ? nil : event
        }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}
