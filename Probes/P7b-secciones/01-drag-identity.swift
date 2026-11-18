// P7b · punto 7: ¿por qué falla arrastrar el borde de una sección en la rejilla expandida?
//
// Réplica mínima de la estructura de `GridSectionBoxes` (Fase 4/5c): una sección partida en un trozo por fila,
// `ForEach(trozos, id: \.offset)`, el asa de fin dentro del ÚLTIMO trozo y un DragGesture en el asa (más el
// DragGesture(minimumDistance: 0) de la rejilla en el contenedor). Se le mandan eventos de ratón sintéticos
// (bajar, arrastrar, soltar) a la ventana y se mira si el gesto llega a `onEnded` y qué se guarda.
//
//   swift Probes/P7b-secciones/01-drag-identity.swift
//
// Casos: (1) el fin se mueve dentro de su fila; (2) el fin pasa a la fila siguiente (alargar una sección que acaba
// en fin de fila, lo normal con frases de 4 compases); (3) el fin vuelve a la fila anterior (encoger).
// Variante «vieja»: asa dentro del trozo. Variante «nueva»: asas fuera del ForEach, con identidad fija.
import AppKit
import SwiftUI

let cellW: CGFloat = 20, cellsPerRow = 20, rowH: CGFloat = 60, handleW: CGFloat = 16

@MainActor final class Log {
    static let shared = Log()
    var changed = 0, ended = 0, parentEnded = 0
    var committedEnd: Int?
    func reset() { changed = 0; ended = 0; parentEnded = 0; committedEnd = nil }
}

/// Tiempo (en celdas) del límite más cercano a `p`.
func boundary(at p: CGPoint) -> Int {
    let row = max(0, min(1, Int(p.y / rowH)))
    let col = max(0, min(cellsPerRow, Int((p.x / cellW).rounded())))
    return row * cellsPerRow + col
}

struct Piece: Equatable { var row: Int; var lo: Int; var hi: Int }
func pieces(start: Int, end: Int) -> [Piece] {
    (0..<2).compactMap { r in
        let lo = max(start, r * cellsPerRow) - r * cellsPerRow, hi = min(end, (r + 1) * cellsPerRow) - r * cellsPerRow
        return lo < hi ? Piece(row: r, lo: lo, hi: hi) : nil
    }
}

struct Scene: View {
    let newStructure: Bool
    @State var end: Int
    @State private var preview: Int?

    var body: some View {
        let shown = preview ?? end
        let ps = pieces(start: 0, end: shown)
        ZStack(alignment: .topLeading) {
            Color.gray.opacity(0.1).frame(width: CGFloat(cellsPerRow) * cellW + 40, height: 2 * rowH)
            ForEach(Array(ps.enumerated()), id: \.offset) { i, p in
                ZStack(alignment: .topLeading) {
                    Rectangle().stroke(.blue).allowsHitTesting(false)
                    if !newStructure && i == ps.count - 1 { handle.offset(x: CGFloat(p.hi - p.lo) * cellW - handleW / 2) }
                }
                .frame(width: CGFloat(p.hi - p.lo) * cellW, height: rowH)
                .offset(x: CGFloat(p.lo) * cellW, y: CGFloat(p.row) * rowH)
            }
            if newStructure, let last = ps.last {
                handle.offset(x: CGFloat(last.hi) * cellW - handleW / 2, y: CGFloat(last.row) * rowH)
            }
        }
        .frame(width: CGFloat(cellsPerRow) * cellW + 40, height: 2 * rowH, alignment: .topLeading)
        .coordinateSpace(name: "grid")
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("grid")).onEnded { _ in Log.shared.parentEnded += 1 })
    }

    private var handle: some View {
        Color.red.opacity(0.4).frame(width: handleW, height: rowH).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("grid"))
                .onChanged { v in Log.shared.changed += 1; preview = boundary(at: v.location) }
                .onEnded { v in Log.shared.ended += 1; preview = nil; end = boundary(at: v.location); Log.shared.committedEnd = end })
    }
}

@MainActor func run() async {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let size = NSSize(width: CGFloat(cellsPerRow) * cellW + 40, height: 2 * rowH)
    let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 200, y: 200), size: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.orderFrontRegardless()

    func send(_ type: NSEvent.EventType, _ p: CGPoint) {
        let wp = NSPoint(x: p.x, y: size.height - p.y)   // SwiftUI arriba-izquierda → ventana abajo-izquierda
        let e = NSEvent.mouseEvent(with: type, location: wp, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                   pressure: type == .leftMouseUp ? 0 : 1)!
        window.sendEvent(e)
    }
    func pause() async { try? await Task.sleep(for: .milliseconds(40)) }

    var failures = 0
    for newStructure in [false, true] {
        for (name, startEnd, path) in [
            ("dentro de la fila (20→15)", 20, [CGPoint(x: 395, y: 30), CGPoint(x: 360, y: 30), CGPoint(x: 300, y: 30)]),
            ("pasa a la fila siguiente (20→25)", 20, [CGPoint(x: 400, y: 30), CGPoint(x: 395, y: 70), CGPoint(x: 100, y: 90)]),
            ("vuelve a la fila anterior (25→15)", 25, [CGPoint(x: 100, y: 90), CGPoint(x: 300, y: 50), CGPoint(x: 300, y: 30)]),
        ] {
            Log.shared.reset()
            window.contentView = NSHostingView(rootView: Scene(newStructure: newStructure, end: startEnd))
            window.contentView?.layoutSubtreeIfNeeded()
            await pause()
            send(.leftMouseDown, path[0]); await pause()
            for k in 1...20 {   // arrastre en 20 pasos por el camino
                let f = CGFloat(k) / 20, seg = f < 0.5 ? 0 : 1, g = f < 0.5 ? f * 2 : (f - 0.5) * 2
                let a = path[seg], b = path[seg + 1]
                send(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * g, y: a.y + (b.y - a.y) * g)); await pause()
            }
            send(.leftMouseUp, path[2]); await pause()
            let want = boundary(at: path[2])
            let ok = Log.shared.ended == 1 && Log.shared.committedEnd == want
            if !ok && newStructure { failures += 1 }
            print(String(format: "%@ | %-36@ | onChanged %2d · onEnded %d · guardado %@ (esperado %d) · rejilla onEnded %d → %@",
                         newStructure ? "nueva" : "vieja", name as NSString, Log.shared.changed, Log.shared.ended,
                         Log.shared.committedEnd.map { "\($0)" } ?? "nada", want, Log.shared.parentEnded, ok ? "OK" : "FALLA"))
        }
    }
    print(failures == 0 ? "RESULTADO: la estructura nueva no pierde el arrastre" : "RESULTADO: la estructura nueva falla \(failures) casos")
    exit(failures == 0 ? 0 : 1)
}

Task { @MainActor in await run() }
NSApplication.shared.run()
