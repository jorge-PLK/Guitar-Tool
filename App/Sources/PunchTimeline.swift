import AppKit
import Store
import SwiftUI

/// Línea de tiempo del punch-in (mini-spec Fase 6, «Punch-in»): secciones del tema y marcas de entrada y salida con
/// imán al compás; con ⌥ pulsado el movimiento es libre.
struct PunchTimeline: View {
    let ctl: RecordController
    let time: Double

    @State private var active: Handle?
    private enum Handle { case entry, exit }

    private static let height: CGFloat = 54

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Punch-in").font(TF.display(16))
                    Spacer()
                    Text(summary).font(TF.body(12)).foregroundStyle(TF.muted).monospacedDigit()
                }
                GeometryReader { g in
                    let w = g.size.width, d = max(ctl.duration, 0.001)
                    let x: (Double) -> CGFloat = { CGFloat($0 / d) * w }
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8).fill(TF.bg)
                        ForEach(ctl.sections, id: \.id) { s in
                            let c = TF.sectionPalette[(ctl.session.sectionPalette[s.id] ?? 0) % TF.sectionPalette.count]
                            RoundedRectangle(cornerRadius: 4).fill(c.opacity(0.30))
                                .overlay(Text(s.name).font(TF.body(10, .medium)).foregroundStyle(c).lineLimit(1).padding(.horizontal, 4),
                                         alignment: .topLeading)
                                .frame(width: max(x(s.end) - x(s.start), 2), height: Self.height - 14)
                                .offset(x: x(s.start), y: 7)
                        }
                        if let a = ctl.punchIn {
                            let b = ctl.punchOut ?? a
                            Rectangle().fill(TF.accent.opacity(0.28))
                                .frame(width: max(x(b) - x(a), 2), height: Self.height).offset(x: x(a))
                            handle(.entry).offset(x: x(a) - 3)
                        }
                        if let b = ctl.punchOut { handle(.exit).offset(x: x(b) - 3) }
                        if ctl.phase != .idle || time > 0 {
                            Rectangle().fill(.white.opacity(0.8)).frame(width: 1, height: Self.height).offset(x: x(time))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in drag(to: Double(v.location.x / max(w, 1)) * d) }
                        .onEnded { _ in active = nil })
                }
                .frame(height: Self.height)
                Text("Haz clic para marcar la entrada y después la salida; arrastra las marcas para moverlas (⌥ = libre, sin imán al compás).")
                    .font(TF.body(12)).foregroundStyle(TF.muted)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .disabled(ctl.isBusy)
    }

    private func handle(_ h: Handle) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(TF.accent).frame(width: 6, height: Self.height)
            .accessibilityLabel(h == .entry ? "Entrada del punch-in" : "Salida del punch-in")
    }

    private var summary: String {
        func f(_ t: Double?) -> String { t.map { String(format: "%d:%04.1f", Int($0) / 60, $0.truncatingRemainder(dividingBy: 60)).replacingOccurrences(of: ".", with: ",") } ?? "—" }
        return "Entrada \(f(ctl.punchIn)) · Salida \(f(ctl.punchOut))"
    }

    private func drag(to raw: Double) {
        var t = min(max(raw, 0), ctl.duration)
        if !NSEvent.modifierFlags.contains(.option) { t = min(max(ctl.timing.nearestBar(t), 0), ctl.duration) }
        if active == nil {
            if ctl.punchIn == nil { active = .entry }
            else if ctl.punchOut == nil { active = .exit }
            else if let a = ctl.punchIn, let b = ctl.punchOut { active = abs(t - a) <= abs(t - b) ? .entry : .exit }
        }
        switch active {
        case .entry?:
            ctl.punchIn = t
            if let o = ctl.punchOut, t >= o { ctl.punchOut = nil }
        case .exit?:
            if let i = ctl.punchIn, t <= i { ctl.punchOut = i; ctl.punchIn = t; active = .entry } else { ctl.punchOut = t }
        case nil: break
        }
    }
}
