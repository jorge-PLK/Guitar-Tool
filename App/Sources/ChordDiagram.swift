import StudyKit
import SwiftUI

/// Diagrama de acorde de guitarra (6 cuerdas, 5 trastes visibles) dibujado con Canvas (boceto Backing, mini-spec Fase 2 §2).
struct ChordDiagram: View {
    let shape: ChordShape?
    var width: CGFloat = 72
    var height: CGFloat = 84

    private let fretRows = 5
    private let topMargin: CGFloat = 16

    var body: some View {
        Canvas { ctx, size in
            guard let shape else { return }
            // Sin cuerdas al aire y sin traste 1 (p. ej. F# con cejilla en el 2): el diagrama arranca en el traste más bajo.
            let pressed = shape.frets.compactMap { $0 }.filter { $0 > 0 }
            let hasOpen = shape.frets.contains { $0 == 0 }
            let base = (!hasOpen && (pressed.min() ?? 1) > 1) ? pressed.min()! : shape.baseFret
            let left: CGFloat = 22, right = size.width - 6
            let top = topMargin, bottom = size.height - 4
            let stringGap = (right - left) / 5
            let fretGap = (bottom - top) / CGFloat(fretRows)
            let ink = TF.muted.opacity(0.8)
            func x(_ s: Int) -> CGFloat { left + CGFloat(s) * stringGap }       // s = 0 → 6.ª cuerda
            func y(_ row: Int) -> CGFloat { top + CGFloat(row) * fretGap }

            for r in 0...fretRows {
                var p = Path(); p.move(to: CGPoint(x: left, y: y(r))); p.addLine(to: CGPoint(x: right, y: y(r)))
                let nut = r == 0 && base == 1
                ctx.stroke(p, with: .color(nut ? TF.text2 : ink), lineWidth: nut ? 3 : 1)
            }
            for s in 0..<6 {
                var p = Path(); p.move(to: CGPoint(x: x(s), y: top)); p.addLine(to: CGPoint(x: x(s), y: bottom))
                ctx.stroke(p, with: .color(ink), lineWidth: 1)
            }
            if base > 1 {
                ctx.draw(Text("\(base)fr").font(TF.body(10, .semibold)).foregroundStyle(TF.text2),
                         at: CGPoint(x: 10, y: y(0) + fretGap / 2))
            }
            if let b = shape.barre {
                let row = b.fret - base
                // fromString/toString: 6 = Mi grave (índice 0), 1 = Mi agudo (índice 5)
                let a = 6 - max(b.fromString, b.toString), z = 6 - min(b.fromString, b.toString)
                let rect = CGRect(x: x(a) - 4, y: y(row) + fretGap / 2 - 4, width: x(z) - x(a) + 8, height: 8)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(TF.accent))
            }
            for (s, fret) in shape.frets.enumerated() {
                guard let fret else {
                    ctx.draw(Text("×").font(TF.body(11, .bold)).foregroundStyle(TF.muted), at: CGPoint(x: x(s), y: 7))
                    continue
                }
                if fret == 0 {
                    let r = CGRect(x: x(s) - 3.5, y: 3.5, width: 7, height: 7)
                    ctx.stroke(Path(ellipseIn: r), with: .color(TF.text2), lineWidth: 1)
                } else {
                    let row = fret - base
                    guard row >= 0, row < fretRows else { continue }
                    let r = CGRect(x: x(s) - 5, y: y(row) + fretGap / 2 - 5, width: 10, height: 10)
                    ctx.fill(Path(ellipseIn: r), with: .color(TF.accent))
                }
            }
        }
        .frame(width: width, height: height)
        .accessibilityLabel(shape.map { _ in "Diagrama del acorde" } ?? "Sin diagrama")
    }
}
