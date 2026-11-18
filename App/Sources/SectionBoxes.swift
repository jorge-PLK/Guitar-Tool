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

/// Una caja (o un trozo de caja, en la rejilla) de sección: contorno y cabecera con el nombre. El interior deja pasar
/// los gestos de los acordes. Las asas de los bordes NO van aquí: las dibuja el anfitrión aparte (`SectionEdgeHandle`),
/// con identidad fija, para que el arrastre no muera cuando el trozo que tenía el borde desaparece (punto 7, Fase 7b).
struct SectionBoxPiece: View {
    let session: StudySession
    let ctl: BackingController
    /// La sección con el borde en arrastre ya aplicado.
    let section: SongSection
    let size: CGSize
    let headerHeight: CGFloat
    /// Primer trozo de la caja: lleva el nombre y la ventana. Los demás solo repiten el contorno.
    let isFirst: Bool
    let selection: SectionSelection

    private var isSelected: Bool { selection.selected == section.id }

    /// Naranja para los solos; para el resto, su color de paleta (elegido o automático).
    static func tint(_ section: SongSection, _ session: StudySession) -> Color {
        if section.isSolo { return TF.accent }
        return TF.sectionPalette[(session.sectionPalette[section.id] ?? 0) % TF.sectionPalette.count]
    }

    private var tint: Color { Self.tint(section, session) }

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

}

/// Asa de un borde de la sección seleccionada: barra visible centrada en `x` y zona de agarre más ancha, con cursor de
/// redimensionar. La coloca el anfitrión fuera de los trozos de caja, con identidad fija durante todo el arrastre.
/// Si el sistema cancela el gesto (sin `onEnded`), `onCancel` deja limpia la vista previa.
struct SectionEdgeHandle: View {
    let isStart: Bool
    let tint: Color
    /// Borde (x) y franja vertical del asa, en el espacio de coordenadas `space`.
    let x: CGFloat
    let top: CGFloat
    let height: CGFloat
    let space: String
    let onDrag: (DragGesture.Value, _ ended: Bool) -> Void
    let onCancel: () -> Void

    /// Anchura de la zona que agarra una asa, centrada en el borde.
    static let grab: CGFloat = 16

    @GestureState private var active = false

    var body: some View {
        ZStack {
            Capsule().fill(tint).frame(width: 6, height: min(max(height - 10, 16), 30))
                .shadow(color: .black.opacity(0.5), radius: 2)
        }
        .frame(width: Self.grab, height: max(height, 0))
        .contentShape(Rectangle())
        .pointerStyle(.columnResize)
        .offset(x: x - Self.grab / 2, y: top)
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
            .updating($active) { _, s, _ in s = true }
            .onChanged { onDrag($0, false) }
            .onEnded { onDrag($0, true) })
        .onChange(of: active) { _, on in if !on { onCancel() } }
        .accessibilityLabel(isStart ? "Borde de inicio" : "Borde de fin")
    }
}

/// Arrastre de un borde en curso, igual en la tira y en la rejilla: la cuenta la hace `Store.SectionEdgeDrag`
/// (posición → tiempo, borde inicial, imán, reglas del punto 8) y aquí solo se guarda la vista previa y se aplica al soltar.
struct SectionEdgeDragState {
    private var drag: SectionEdgeDrag?
    private var grab: CGPoint?
    /// Secciones como quedarían al soltar (con la vecina empujada); nil sin arrastre.
    private(set) var preview: [SongSection]?

    /// Un evento del asa. El primero fija la cuenta con las secciones y el borde de ese momento; al soltar, guarda.
    @MainActor mutating func update(_ v: DragGesture.Value, id: UUID, isStart: Bool, ended: Bool, session: StudySession,
                                    cells: () -> [SectionEdgeDrag.Cell], bars: () -> [Double]) {
        let bar = NSEvent.modifierFlags.contains(.option)
        if drag?.id != id || drag?.isStart != isStart || grab != v.startLocation {
            drag = SectionEdgeDrag(editor: session.sectionEditor, id: id, isStart: isStart, cells: cells(), bars: bars(),
                                   grab: v.startLocation)
            grab = v.startLocation
        }
        guard let d = drag else { cancel(); return }
        if ended {
            session.setSectionEdge(id, start: isStart, to: d.edge(at: v.location, bar: bar))
            cancel()
        } else {
            preview = d.sections(at: v.location, bar: bar)
        }
    }

    mutating func cancel() { drag = nil; grab = nil; preview = nil }
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

    @State private var edge = SectionEdgeDragState()

    var body: some View {
        let shown = edge.preview ?? session.sections
        ZStack(alignment: .topLeading) {
            ForEach(shown, id: \.id) { s in box(s) }
            if let id = selection.selected, let s = shown.first(where: { $0.id == id }), let r = rect(s) {
                handle(s, isStart: true, x: r.minX, height: r.height)
                handle(s, isStart: false, x: r.maxX, height: r.height)
            }
        }
    }

    private func handle(_ s: SongSection, isStart: Bool, x: CGFloat, height: CGFloat) -> some View {
        SectionEdgeHandle(isStart: isStart, tint: SectionBoxPiece.tint(s, session), x: x, top: Self.headerHeight,
                          height: height - Self.headerHeight, space: Self.space,
                          onDrag: { v, ended in
                              edge.update(v, id: s.id, isStart: isStart, ended: ended, session: session,
                                          cells: { cells }, bars: { session.barBoundaries })
                          },
                          onCancel: { edge.cancel() })
    }

    /// Un chip por acorde, con la franja entera de la tira en vertical (`SectionEdgeDrag` en una sola fila).
    private var cells: [SectionEdgeDrag.Cell] {
        frames.sorted { $0.key < $1.key }.compactMap { i, f in
            guard chords.indices.contains(i) else { return nil }
            return .init(row: 0, frame: CGRect(x: f.minX, y: 0, width: f.width, height: max(f.maxY, 1)),
                         time: chords[i].start, end: chords[i].end, chordStart: chords[i].start)
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

    /// Caja de la sección en la tira (x desde el primer chip hasta el último, alto hasta el pie de los chips).
    private func rect(_ s: SongSection) -> CGRect? {
        guard let span = chordSpan(s), let f0 = frames[span.lowerBound], let f1 = frames[span.upperBound] else { return nil }
        let x0 = f0.minX - Self.inset, x1 = f1.maxX + Self.inset
        return CGRect(x: x0, y: 0, width: max(x1 - x0, 8), height: max(f0.maxY, f1.maxY) + Self.inset)
    }

    @ViewBuilder private func box(_ s: SongSection) -> some View {
        if let r = rect(s) {
            SectionBoxPiece(session: session, ctl: ctl, section: s, size: r.size, headerHeight: Self.headerHeight,
                            isFirst: true, selection: selection)
                .offset(x: r.minX)
        }
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
