import AppKit
import Observation
import Store
import StudyKit
import SwiftUI

typealias SongSection = Store.Section

/// Secciones (y solos) como cajas con su nombre sobre los acordes, en la tira compacta (`SectionBoxes`) y en la rejilla
/// expandida (`GridSectionBoxes`). Sin carriles. El borde se ajusta al acorde más cercano solo al dibujar; los datos
/// guardan los tiempos exactos. Solo = naranja con insignia de guitarra; el resto, contorno gris (mini-spec Fase 4,
/// «El solo es una sección más» e «Interfaz»).
///
/// Cómo se edita (la lógica está en `Store.SectionEditor`):
/// - Marcar una sección abre al momento su ventana (`SectionPopover`) con el nombre enfocado.
/// - Clic en la cabecera = seleccionar y abrir esa ventana (nombre, «Solo», inicio y fin con ◀ ▶, bucle, eliminar).
///   Mantener pulsado = bucle de la sección. Clic derecho = atajo (`SectionMenu`).
/// - Una caja seleccionada muestra asas en sus bordes (arrastrables, imán al acorde, ⌥ al compás); Supr la borra.
///
/// Selección compartida por las dos vistas: la ventana y las asas siguen a esta sección.
@MainActor @Observable
final class SectionSelection {
    /// Sección resaltada con asas.
    var selected: UUID?
    /// Sección cuya ventana está abierta.
    var popover: UUID?

    func select(_ id: UUID) { selected = id; popover = id }
    func clear() { selected = nil; popover = nil }
}

/// Una caja (o un trozo de caja, en la rejilla) de sección: contorno, cabecera con el nombre y, si está seleccionada,
/// asas en los bordes reales. El interior deja pasar los gestos de los acordes.
struct SectionBoxPiece: View {
    let session: StudySession
    let ctl: BackingController
    /// La sección con el borde en arrastre ya aplicado.
    let section: SongSection
    let size: CGSize
    let headerHeight: CGFloat
    /// Primer trozo de la caja: lleva el nombre y la ventana. Los demás solo repiten el contorno.
    let isFirst: Bool
    /// Este trozo contiene el borde de inicio / de fin de la sección (donde van las asas).
    let hasStart: Bool
    let hasEnd: Bool
    let selection: SectionSelection
    /// Espacio de coordenadas del anfitrión y aviso de arrastre: (es el inicio, posición, terminado).
    let space: String
    let onEdgeDrag: (Bool, CGPoint, Bool) -> Void

    /// Anchura de la zona que agarra una asa, centrada en el borde.
    static let handleGrab: CGFloat = 16

    private var isSelected: Bool { selection.selected == section.id }

    /// Naranja para los solos; para el resto, su color de paleta (elegido o automático).
    private var tint: Color {
        if section.isSolo { return TF.accent }
        return TF.sectionPalette[(session.sectionPalette[section.id] ?? 0) % TF.sectionPalette.count]
    }

    private var isLoop: Bool {
        guard let l = ctl.loop else { return false }
        return abs(l.lowerBound - section.start) < 0.01 && abs(l.upperBound - section.end) < 0.01
    }

    var body: some View {
        let solo = section.isSolo
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 9)
                .fill(tint.opacity(isSelected ? 0.16 : 0.07))
                .allowsHitTesting(false)
            RoundedRectangle(cornerRadius: 9)
                .stroke(stroke(solo: solo), lineWidth: isSelected || isLoop ? 2 : 1.2)
                .allowsHitTesting(false)
            header(solo: solo)
            if isSelected {
                if hasStart { handle(isStart: true) }
                if hasEnd { handle(isStart: false) }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func stroke(solo: Bool) -> Color {
        if isSelected { return tint }
        if isLoop { return TF.accent }
        return tint.opacity(0.85)
    }

    private func header(solo: Bool) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 9)
            .fill(solo ? TF.accentBg : tint.opacity(0.20))
            .frame(width: size.width, height: headerHeight)
            .overlay(alignment: .leading) {
                if isFirst {
                    // Texto corto o nada si no cabe; el nombre y el rango completos van en el tooltip.
                    ViewThatFits(in: .horizontal) {
                        label(text: true)
                        label(text: false)
                    }
                    .padding(.horizontal, 8).frame(width: size.width, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selection.select(section.id) }
            .onLongPressGesture(minimumDuration: 0.5) {
                if isLoop { ctl.setLoop(nil) } else { ctl.setLoop(section.start...section.end, name: section.name) }
            }
            .contextMenu { SectionMenu(section: section, session: session, selection: selection) }
            .popover(isPresented: Binding(get: { isFirst && selection.popover == section.id },
                                          set: { if !$0, selection.popover == section.id { selection.popover = nil } }),
                     arrowEdge: .bottom) {
                SectionPopover(session: session, ctl: ctl, id: section.id, selection: selection)
            }
            .help("\(section.name)\(solo ? " (solo)" : "") · \(Fmt.clock(section.start))–\(Fmt.clock(section.end)) · clic: editar, mantener: bucle")
            .accessibilityElement()
            .accessibilityLabel("\(solo ? "Solo" : "Sección") \(section.name), \(Fmt.clock(section.start)) a \(Fmt.clock(section.end))")
            .accessibilityHint("Clic para editarla; mantener pulsado para repetirla en bucle")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private func label(text: Bool) -> some View {
        HStack(spacing: 4) {
            if section.isSolo { Image(systemName: "guitars.fill").font(.system(size: 10, weight: .semibold)) }
            if text { Text(section.name).font(TF.body(12, .semibold)).lineLimit(1) }
        }
        .foregroundStyle(section.isSolo ? TF.accent : tint)
        .fixedSize()
    }

    /// Asa de un borde: barra visible centrada en el borde y zona de agarre más ancha, con cursor de redimensionar.
    private func handle(isStart: Bool) -> some View {
        return ZStack {
            Capsule().fill(tint).frame(width: 6, height: min(max(size.height - headerHeight - 10, 16), 30))
                .shadow(color: .black.opacity(0.5), radius: 2)
        }
        .frame(width: Self.handleGrab, height: max(size.height - headerHeight, 0))
        .contentShape(Rectangle())
        .pointerStyle(.columnResize)
        .offset(x: (isStart ? 0 : size.width) - Self.handleGrab / 2, y: headerHeight)
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
            .onChanged { onEdgeDrag(isStart, $0.location, false) }
            .onEnded { onEdgeDrag(isStart, $0.location, true) })
        .accessibilityLabel(isStart ? "Borde de inicio" : "Borde de fin")
    }
}

/// Cajas de la tira compacta, sobre los marcos de los acordes (espacio de coordenadas `SectionBoxes.space`).
struct SectionBoxes: View {
    let session: StudySession
    let ctl: BackingController
    let chords: [ChordSegment]
    /// Marcos de los acordes en el espacio de coordenadas `SectionBoxes.space` de la tira.
    let frames: [Int: CGRect]
    let selection: SectionSelection

    static let space = "strip"
    /// Alto de la franja del nombre, sobre los acordes.
    static let headerHeight: CGFloat = 22
    /// Cuánto sobresale la caja de los acordes de los extremos.
    static let inset: CGFloat = 2

    @State private var preview: SectionEdgePreview?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(session.sections, id: \.id) { s in box(preview.applied(to: s)) }
        }
    }

    /// Índices de acorde que la caja envuelve: el de inicio más cercano al principio y el de fin más cercano al final.
    private func chordSpan(_ s: SongSection) -> ClosedRange<Int>? {
        guard let first = chords.first, let last = chords.last, s.end > first.start, s.start < last.end else { return nil }
        let a = chords.indices.min { abs(chords[$0].start - s.start) < abs(chords[$1].start - s.start) }
        let b = chords.indices.min { abs(chords[$0].end - s.end) < abs(chords[$1].end - s.end) }
        guard let a, let b, a <= b else { return nil }
        return a...b
    }

    @ViewBuilder private func box(_ s: SongSection) -> some View {
        if let span = chordSpan(s), let f0 = frames[span.lowerBound], let f1 = frames[span.upperBound] {
            let x0 = f0.minX - Self.inset, x1 = f1.maxX + Self.inset
            let h = max(f0.maxY, f1.maxY) + Self.inset
            SectionBoxPiece(session: session, ctl: ctl, section: s, size: CGSize(width: max(x1 - x0, 8), height: h),
                            headerHeight: Self.headerHeight, isFirst: true, hasStart: true, hasEnd: true,
                            selection: selection, space: Self.space) { isStart, p, ended in
                drag(s.id, isStart: isStart, x: p.x, ended: ended)
            }
            .offset(x: x0)
        }
    }

    private func drag(_ id: UUID, isStart: Bool, x: CGFloat, ended: Bool) {
        let bar = NSEvent.modifierFlags.contains(.option)
        guard let t = edgeTime(x: x) else { preview = nil; return }
        if ended {
            preview = nil
            session.snapSectionEdge(id, start: isStart, to: t, bar: bar)
        } else if let snapped = session.snappedEdge(id, start: isStart, to: t, bar: bar) {
            preview = SectionEdgePreview(id: id, isStart: isStart, time: snapped)
        }
    }

    /// Límite de acorde bajo la posición `x`: el del lado más cercano del acorde sobre el que está.
    private func edgeTime(x: CGFloat) -> Double? {
        guard !frames.isEmpty else { return nil }
        let i = frames.first { $0.value.minX <= x && x <= $0.value.maxX }?.key
            ?? frames.min { abs($0.value.midX - x) < abs($1.value.midX - x) }!.key
        guard chords.indices.contains(i), let f = frames[i] else { return nil }
        return x < f.midX ? chords[i].start : chords[i].end
    }
}

/// Borde en arrastre: la vista previa mueve la caja antes de soltar.
struct SectionEdgePreview: Equatable {
    var id: UUID
    var isStart: Bool
    var time: Double
}

extension Optional where Wrapped == SectionEdgePreview {
    func applied(to s: SongSection) -> SongSection {
        guard let e = self, e.id == s.id else { return s }
        var r = s
        if e.isStart { r.start = e.time } else { r.end = e.time }
        return r
    }
}

/// Acciones de una sección (clic derecho): renombrar, alternar «Solo», borrar.
struct SectionMenu: View {
    let section: SongSection
    let session: StudySession
    let selection: SectionSelection

    var body: some View {
        Button("Renombrar y ajustar…") { selection.select(section.id) }
        Button(section.isSolo ? "Quitar marca de solo" : "Marcar como solo") { session.setSolo(section.id, !section.isSolo) }
        Divider()
        Button("Eliminar sección", role: .destructive) { selection.clear(); session.removeSection(section.id) }
    }
}

/// Ventana emergente de una sección: nombre (enfocado, con sugerencias), «Solo», inicio y fin con ◀ ▶ por acorde
/// (⌥ = por compás), escuchar en bucle y eliminar. Enter confirma; Esc cierra sin tocar el nombre.
struct SectionPopover: View {
    let session: StudySession
    let ctl: BackingController
    let id: UUID
    let selection: SectionSelection

    static let suggestions = ["Intro", "Estrofa", "Estribillo", "Puente", "Final"]

    @State private var draft = ""
    @State private var cancelled = false
    @FocusState private var nameFocused: Bool

    private var section: SongSection? { session.sections.first { $0.id == id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section?.isSolo == true ? "Solo" : "Sección").font(TF.display(16))
            TextField("Nombre", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit { done() }
                .onExitCommand { cancel() }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Self.suggestions, id: \.self) { name in
                    Button { draft = name } label: {
                        Text(name).font(TF.body(12, .medium)).foregroundStyle(draft == name ? TF.text : TF.muted)
                            .frame(maxWidth: .infinity).frame(height: 24)
                            .background(draft == name ? TF.line : TF.field, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            swatches
            Toggle("Solo", isOn: Binding(get: { section?.isSolo ?? false }, set: { on in
                let untouched = draft == section?.name
                session.setSolo(id, on)
                if untouched { draft = section?.name ?? draft }   // el nombre por defecto sigue a la marca
            }))
            .toggleStyle(.switch).controlSize(.small).tint(TF.accent)
            Divider()
            edgeRow("Inicio", isStart: true)
            edgeRow("Fin", isStart: false)
            Text("◀ ▶ mueven por acorde · ⌥ por compás").font(TF.body(11)).foregroundStyle(TF.muted)
            HStack {
                Button { listen() } label: { Label("Escuchar en bucle", systemImage: "repeat") }
                Spacer()
                Button("Eliminar", role: .destructive) { selection.clear(); session.removeSection(id) }
            }
            HStack {
                Spacer()
                Button("Hecho") { done() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).frame(width: 300)
        .onAppear {
            draft = section?.name ?? ""
            DispatchQueue.main.async { nameFocused = true }
        }
        .onDisappear { if !cancelled { session.renameSection(id, to: draft) } }
    }

    /// Muestras de la paleta; el naranja no se ofrece (es de los solos). Clic en la elegida = volver al automático.
    private var swatches: some View {
        let solo = section?.isSolo == true
        let current = session.sectionPalette[id]
        return HStack(spacing: 8) {
            Text("Color").font(TF.body(13)).foregroundStyle(TF.text2).frame(width: 46, alignment: .leading)
            if solo {
                Circle().fill(TF.accent).frame(width: 20, height: 20)
                Text("Los solos van en naranja").font(TF.body(12)).foregroundStyle(TF.muted)
            } else {
                ForEach(TF.sectionPalette.indices, id: \.self) { i in
                    Button { session.setSectionColor(id, section?.color == i ? nil : i) } label: {
                        Circle().fill(TF.sectionPalette[i]).frame(width: 20, height: 20)
                            .overlay(Circle().stroke(TF.text, lineWidth: current == i ? 2 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(i + 1)")
                    .accessibilityAddTraits(current == i ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 24)
    }

    private func edgeRow(_ title: String, isStart: Bool) -> some View {
        let t = (isStart ? section?.start : section?.end) ?? 0
        return HStack(spacing: 8) {
            Text(title).font(TF.body(13)).foregroundStyle(TF.text2).frame(width: 46, alignment: .leading)
            nudge("chevron.left", isStart: isStart, forward: false)
            Text(Self.precise(t)).font(TF.body(14, .semibold)).monospacedDigit().frame(minWidth: 64)
            nudge("chevron.right", isStart: isStart, forward: true)
            Spacer(minLength: 0)
        }
    }

    private func nudge(_ icon: String, isStart: Bool, forward: Bool) -> some View {
        Button {
            session.nudgeSectionEdge(id, start: isStart, forward: forward, bar: NSEvent.modifierFlags.contains(.option))
        } label: {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(TF.text)
                .frame(width: 30, height: 24).background(TF.field, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(TF.fieldLine))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isStart ? "Inicio" : "Fin") \(forward ? "después" : "antes")")
    }

    /// m:ss.d
    static func precise(_ s: Double) -> String {
        let t = max(s, 0)
        return String(format: "%d:%04.1f", Int(t) / 60, t - Double(Int(t) / 60 * 60))
    }

    private func listen() {
        guard let s = section else { return }
        ctl.setLoop(s.start...s.end, name: s.name)
        ctl.seek(to: s.start)
        if !ctl.isPlaying { ctl.togglePlay() }
    }

    private func done() {
        session.renameSection(id, to: draft)
        cancelled = true
        selection.popover = nil
    }

    private func cancel() {
        cancelled = true
        selection.popover = nil
    }
}
