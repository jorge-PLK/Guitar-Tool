import Store
import SwiftUI

/// Hoja «Encuadre» de una toma (mini-spec Fase 7, «Encuadre» e «Interfaz»): un fotograma con la caja de la guitarra,
/// el conmutador «Seguir la guitarra» y el ajuste manual (fijo: mover y escalar la caja; seguir: zoom y desplazamiento).
struct MontageFramingSheet: View {
    let ctl: MontageController
    let takeID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var time = 0.0
    @State private var image: CGImage?
    @State private var started = false
    // Estado del arrastre en curso.
    @State private var dragBase: NormalizedRect?
    @State private var dragResizes = false
    @State private var offsetBase: FramingOffset?

    /// Radio (px) de la zona de la esquina que escala la caja.
    private static let handleRadius: CGFloat = 16
    private static let minBoxSide = 0.05
    private static let zoomRange = 0.5...3.0
    private static let offsetRange = -0.5...0.5

    var body: some View {
        let lane = ctl.lane(takeID: takeID)
        let f = ctl.framing(for: takeID)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Encuadre · \(lane?.partName ?? "")").font(TF.display(20))
                Spacer()
                Toggle("Seguir la guitarra", isOn: Binding(get: { f.mode == .follow }, set: { on in
                    ctl.updateFraming(takeID) { $0.mode = on ? .follow : .fixed }
                })).toggleStyle(.switch).tint(TF.accent)
            }
            status
            frameArea
            if let lane {
                HStack(spacing: 10) {
                    Text("Instante").font(TF.body(13)).foregroundStyle(TF.muted)
                    Slider(value: $time, in: lane.take.start...max(lane.take.end, lane.take.start + 0.1)).tint(TF.accent)
                    Text(Fmt.duration(time)).font(TF.body(13)).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            if f.mode == .fixed { fixedControls(f) } else { followControls(f) }
            HStack {
                Button("Restablecer") { ctl.resetFraming(takeID) }.buttonStyle(SecondaryButton())
                Button("Reanalizar") { ctl.reanalyze(takeID) }.buttonStyle(SecondaryButton())
                    .disabled({ if case .analyzing = ctl.framingStatus[takeID] { return true }; return false }())
                Spacer()
                Button("Hecho") { dismiss() }.buttonStyle(PrimaryButton())
            }
        }
        .padding(24).frame(width: 760).background(TF.card).foregroundStyle(TF.text)
        .onAppear {
            guard !started, let lane else { return }
            started = true
            let p = lane.presence.first ?? lane.take
            time = (p.start + p.end) / 2
        }
        .task(id: time) {
            guard started else { return }
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            image = await ctl.frameImage(takeID: takeID, at: time)
        }
    }

    // MARK: Estado del análisis

    @ViewBuilder private var status: some View {
        let text: (String, Color) = switch ctl.framingStatus[takeID] {
        case nil, .pending?: ("En cola para analizar la guitarra…", TF.muted)
        case .analyzing(let p)?: ("Analizando la guitarra… \(Fmt.percent(p))", TF.accent)
        case .ready(let samples, let detected)?:
            detected == 0
                ? ("Sin detección: se usa el fotograma entero, centrado. Puedes colocar la caja a mano.", TF.accent)
                : ("Guitarra detectada en \(detected) de \(samples) muestras.", TF.muted)
        case .failed(let m)?: ("No se pudo analizar la toma (\(m)).", TF.danger)
        }
        Text(text.0).font(TF.body(12)).foregroundStyle(text.1).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Fotograma con la caja

    private var frameArea: some View {
        let aspect = image.map { CGFloat($0.width) / CGFloat($0.height) } ?? 16.0 / 9.0
        return Color.black
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        if let image {
                            Image(decorative: image, scale: 1).resizable().frame(width: geo.size.width, height: geo.size.height)
                        } else {
                            Text("Sin imagen en este instante").font(TF.body(13)).foregroundStyle(TF.muted)
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                        boxOverlay(size: geo.size, aspect: aspect)
                    }
                    .contentShape(Rectangle())
                    .gesture(drag(size: geo.size, aspect: aspect))
                }
            }
            .frame(maxHeight: 400)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(TF.fieldLine))
    }

    private func currentBox() -> NormalizedRect {
        ctl.effectiveBox(takeID: takeID, at: time) ?? NormalizedRect(x: 0, y: 0, width: 1, height: 1)
    }

    private func rect(_ b: NormalizedRect, _ size: CGSize) -> CGRect {
        CGRect(x: b.x * size.width, y: b.y * size.height, width: b.width * size.width, height: b.height * size.height)
    }

    private func boxOverlay(size: CGSize, aspect: CGFloat) -> some View {
        let r = rect(currentBox(), size)
        return ZStack(alignment: .topLeading) {
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                p.addRect(r)
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
            Rectangle().stroke(TF.accent, lineWidth: 2).frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
            if ctl.framing(for: takeID).mode == .fixed {
                Circle().fill(TF.accent).frame(width: 14, height: 14).offset(x: r.maxX - 7, y: r.maxY - 7)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Arrastre

    private func drag(size: CGSize, aspect: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard size.width > 0, size.height > 0 else { return }
                let dx = Double(g.translation.width / size.width), dy = Double(g.translation.height / size.height)
                if ctl.framing(for: takeID).mode == .fixed {
                    if dragBase == nil {
                        let b = currentBox()
                        let corner = CGPoint(x: (b.x + b.width) * size.width, y: (b.y + b.height) * size.height)
                        dragResizes = hypot(g.startLocation.x - corner.x, g.startLocation.y - corner.y) <= Self.handleRadius
                        dragBase = b
                    }
                    guard let base = dragBase else { return }
                    let box = dragResizes ? Self.resized(base, dx: dx, aspect: Double(aspect)) : Self.moved(base, dx: dx, dy: dy)
                    ctl.updateFraming(takeID) { $0.manualBox = box }
                } else {
                    if offsetBase == nil { offsetBase = ctl.framing(for: takeID).followOffset }
                    guard let base = offsetBase else { return }
                    ctl.updateFraming(takeID) { $0.followOffset = FramingOffset(x: Self.clamp(base.x + dx, Self.offsetRange), y: Self.clamp(base.y + dy, Self.offsetRange)) }
                }
            }
            .onEnded { _ in
                dragBase = nil
                dragResizes = false
                offsetBase = nil
            }
    }

    static func clamp(_ v: Double, _ r: ClosedRange<Double>) -> Double { min(max(v, r.lowerBound), r.upperBound) }

    /// Mueve la caja sin salirse del fotograma.
    static func moved(_ b: NormalizedRect, dx: Double, dy: Double) -> NormalizedRect {
        NormalizedRect(x: clamp(b.x + dx, 0...(1 - b.width)), y: clamp(b.y + dy, 0...(1 - b.height)), width: b.width, height: b.height)
    }

    /// Escala la caja desde su esquina superior izquierda conservando su proporción en píxeles (`aspect` = ancho/alto del fotograma).
    static func resized(_ b: NormalizedRect, dx: Double, aspect: Double) -> NormalizedRect {
        let boxAspect = (b.width * aspect) / max(b.height, 1e-6)
        let maxW = min(1 - b.x, (1 - b.y) * boxAspect / aspect)
        let w = clamp(b.width + dx, minBoxSide...max(minBoxSide, maxW))
        return NormalizedRect(x: b.x, y: b.y, width: w, height: w * aspect / boxAspect)
    }

    // MARK: Controles

    private func fixedControls(_ f: TakeFraming) -> some View {
        HStack(spacing: 10) {
            Text(f.manualBox == nil ? "Caja automática: arrástrala para moverla; el punto de la esquina la escala."
                                    : "Ajuste manual: arrastra la caja para moverla; el punto de la esquina la escala.")
                .font(TF.body(12)).foregroundStyle(TF.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func followControls(_ f: TakeFraming) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            slider("Zoom", value: f.followZoom, range: Self.zoomRange, format: { String(format: "×%.2f", $0) }) { v in
                ctl.updateFraming(takeID) { $0.followZoom = v }
            }
            slider("Desplazamiento X", value: f.followOffset.x, range: Self.offsetRange, format: { String(format: "%+.2f", $0) }) { v in
                ctl.updateFraming(takeID) { $0.followOffset.x = v }
            }
            slider("Desplazamiento Y", value: f.followOffset.y, range: Self.offsetRange, format: { String(format: "%+.2f", $0) }) { v in
                ctl.updateFraming(takeID) { $0.followOffset.y = v }
            }
            Text("El recorte sigue la trayectoria de la guitarra; arrastra sobre el fotograma para desplazarlo.")
                .font(TF.body(12)).foregroundStyle(TF.muted)
        }
    }

    private func slider(_ title: String, value: Double, range: ClosedRange<Double>, format: (Double) -> String,
                        set: @escaping @Sendable (Double) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title).font(TF.body(13)).foregroundStyle(TF.text2).frame(width: 130, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: range).tint(TF.accent)
            Text(format(value)).font(TF.body(13)).monospacedDigit().frame(width: 56, alignment: .trailing)
        }
    }
}
