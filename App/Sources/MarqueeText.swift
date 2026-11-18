import SwiftUI

/// Una línea que, si no cabe, se trunca con «…» y, al pasar el ratón, se desplaza hasta verse entera y vuelve al salir
/// (spec Fase 7b, punto 6). El tamaño de la vista no cambia: se mide el texto con una copia oculta.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    /// Velocidad del desplazamiento, pt/s (spec 7b, punto 6).
    static let speed: CGFloat = 30

    @State private var hovering = false
    @State private var fullWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0

    private var overflow: CGFloat { max(0, fullWidth - boxWidth) }

    var body: some View {
        Text(text.isEmpty ? " " : text).font(font).foregroundStyle(color).lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(hovering && overflow > 0 ? 0 : 1)
            .background(GeometryReader { g in Color.clear.onAppear { boxWidth = g.size.width }
                .onChange(of: g.size.width) { _, w in boxWidth = w } })
            .overlay(alignment: .leading) {
                Text(text).font(font).foregroundStyle(color).lineLimit(1).fixedSize()
                    .background(GeometryReader { g in Color.clear.onAppear { fullWidth = g.size.width }
                        .onChange(of: g.size.width) { _, w in fullWidth = w } })
                    .offset(x: hovering ? -overflow : 0)
                    .animation(hovering ? .linear(duration: Double(overflow / Self.speed)) : .easeOut(duration: 0.2),
                               value: hovering)
                    .opacity(hovering && overflow > 0 ? 1 : 0)
            }
            .clipped()
            .onHover { hovering = $0 }
            .onChange(of: text) { _, _ in hovering = false }
    }
}
