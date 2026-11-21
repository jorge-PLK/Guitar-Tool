import AppKit
import Store
import StudyKit
import SwiftUI

/// Tarjeta «Línea de tiempo» de Backing: tira de acordes con las secciones y los solos como cajas encima, tonalidad,
/// transposición, barra de progreso con bucle y transporte (mini-spec Fase 2 §2 y Fase 4).
struct BackingTimelineCard: View {
    let session: StudySession
    let ctl: BackingController
    let time: Double

    let expanded: Binding<Bool>
    let editMode: Binding<Bool>

    @Environment(AppModel.self) private var model
    @State private var chordEditing: Int?
    @State private var gridEditing: Double?
    @State private var selection = SectionSelection()
    @State private var keyMonitor = SectionKeyMonitor()
    @State private var spaceMonitor = SpaceKeyMonitor()
    @State private var stripFrames: [Int: CGRect] = [:]
    @State private var stripDrag: ClosedRange<Int>?
    /// Inicio de bucle marcado con «Inicio» a la espera del fin (como en la interfaz de Windows).
    @State private var pendingLoopStart: Double?

    private var settings: PlayerSettings { ctl.settings }
    private var duration: Double { max(ctl.duration, 0.001) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                chordsHeader
                chordsArea
                infoRow
                ProgressBarView(session: session, ctl: ctl, time: time, duration: duration)
                transport
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .onChange(of: editMode.wrappedValue) { chordEditing = nil; gridEditing = nil; selection.clear() }
        .onChange(of: expanded.wrappedValue) { selection.popover = nil }
        .onAppear {
            keyMonitor.install(selection: selection, session: session)
            spaceMonitor.install { [ctl] in ctl.togglePlay() }
            #if DEBUG
            if let n = model.options.selectSection {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    if session.sections.indices.contains(n) { selection.select(session.sections[n].id) }
                }
            }
            #endif
        }
        .onDisappear { keyMonitor.remove(); spaceMonitor.remove() }
    }

    // MARK: Acordes

    private func shown(_ index: Int) -> ChordLabel {
        (ChordLabel(index: index) ?? .unknown).transposed(by: settings.transpose)
    }

    private var chordsHeader: some View {
        let edit = editMode.wrappedValue
        return HStack(spacing: 12) {
            Text("Acordes").font(TF.display(16)).foregroundStyle(TF.text)
            Button { editMode.wrappedValue.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: edit ? "pencil.circle.fill" : "pencil")
                    Text("Editar acordes")
                }
                .font(TF.body(12, edit ? .semibold : .medium))
                .foregroundStyle(edit ? TF.accentInk : TF.text2)
                .padding(.horizontal, 10).frame(height: 28)
                .background(edit ? TF.accent : TF.field, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(edit ? .clear : TF.fieldLine))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(edit ? .isSelected : [])
            // Solo en edición y con correcciones del usuario (como «Quitar todas (n)» de Windows).
            let overrides = session.study.chordOverrides.count
            if edit, overrides > 0 {
                Button { session.clearChordOverrides() } label: {
                    Text("Quitar todas (\(overrides))")
                        .font(TF.body(12, .medium)).foregroundStyle(TF.text2)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(TF.field, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TF.fieldLine))
                }
                .buttonStyle(.plain)
                .help("Quita todas las correcciones de acordes de este tema")
            }
            Text(edit ? "Modo edición: clic en un acorde para cambiarlo o partirlo. No se marcan bucles."
                      : "Clic: saltar · arrastrar: bucle (⌥ = compases)")
                .font(TF.body(12)).foregroundStyle(edit ? TF.accent : TF.muted).lineLimit(1)
                .truncationMode(.tail).layoutPriority(-1)
            Spacer(minLength: 0)
            if !edit, ctl.loop != nil, !currentChordsEmpty {
                markButton("Marcar sección", icon: "rectangle.dashed", solo: false)
                markButton("Marcar como solo", icon: "guitars.fill", solo: true)
            }
            SectionApplyButtons(session: session)
            Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.wrappedValue.toggle() } } label: {
                HStack(spacing: 6) {
                    Text(expanded.wrappedValue ? "Plegar" : "Expandir")
                    Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                }
                .font(TF.body(12, .medium)).foregroundStyle(TF.text2)
                .padding(.horizontal, 10).frame(height: 28)
                .background(TF.field, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(TF.fieldLine))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded.wrappedValue ? "Plegar acordes" : "Expandir acordes")
        }
    }

    private var currentChordsEmpty: Bool { session.effectiveChords.isEmpty }

    /// Marca el bucle activo como sección o como solo (los cambios son locales hasta «Aplicar»).
    private func markButton(_ title: String, icon: String, solo: Bool) -> some View {
        Button { markLoop(solo: solo) } label: {
            HStack(spacing: 6) { Image(systemName: icon); Text(title) }
                .font(TF.body(12, .medium)).foregroundStyle(solo ? TF.accent : TF.text2)
                .padding(.horizontal, 10).frame(height: 28)
                .background(solo ? TF.accentBg : TF.field, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(solo ? TF.accent.opacity(0.6) : TF.fieldLine))
        }
        .buttonStyle(.plain).fixedSize()
        .help(solo ? "Marca el bucle como un solo: sus guitarras se separan al aplicar" : "Marca el bucle como una sección")
    }

    /// Marca el bucle y abre al momento la ventana de la sección nueva (nombre enfocado).
    private func markLoop(solo: Bool) {
        guard let l = ctl.loop, let id = session.markSection(l, solo: solo) else { return }
        selection.select(id)
    }

    private var currentChord: (chords: [ChordSegment], current: Int?, next: ChordSegment?) {
        let chords = session.effectiveChords
        let current = chords.firstIndex { $0.start <= time && time < $0.end }
        let next = current.flatMap { c in
            chords[(c + 1)...].first { $0.index != chords[c].index && ChordLabel(index: $0.index)?.isChord == true }
        }
        return (chords, current, next)
    }

    private var chordsArea: some View {
        let (chords, current, next) = currentChord
        let edit = editMode.wrappedValue
        return VStack(alignment: .leading, spacing: 10) {
            if expanded.wrappedValue {
                HStack(alignment: .top, spacing: 12) {
                    ChordGridView(session: session, ctl: ctl, time: time, edit: edit, shown: shown, editing: $gridEditing, selection: selection)
                    diagramCard(current: current.map { chords[$0] }, next: next)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    if chords.isEmpty {
                        Text(session.analysisState == .ready ? "Sin acordes detectados." : "Los acordes aparecerán al terminar el análisis.")
                            .font(TF.body(13)).foregroundStyle(TF.muted)
                            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 36)
                    } else {
                        chordStrip(chords, current: current)
                    }
                    diagramCard(current: current.map { chords[$0] }, next: next)
                }
            }
        }
        .padding(8)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(edit ? TF.accent : .clear, lineWidth: 1.5))
        .background(edit ? TF.accentBg.opacity(0.4) : .clear, in: RoundedRectangle(cornerRadius: 12))
    }

    private func chordStrip(_ chords: [ChordSegment], current: Int?) -> some View {
        let edit = editMode.wrappedValue
        let l = (stripDrag.map { chords[$0.lowerBound].start...chords[$0.upperBound].end }) ?? ctl.loop
        let bars = Self.barNumbers(chords, downbeats: session.beats?.downbeats ?? [],
                                   tolerance: session.beats?.bpm.map { 30 / $0 } ?? Self.barMatchTolerance)
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    // Hueco para el nombre de las cajas de sección, sobre los acordes.
                    Color.clear.frame(height: SectionBoxes.headerHeight)
                    HStack(spacing: 6) {
                        ForEach(Array(chords.enumerated()), id: \.offset) { i, seg in
                            let inLoop = l.map { ($0.lowerBound...$0.upperBound).contains((seg.start + seg.end) / 2) } ?? false
                            if edit {
                                Button { chordEditing = i } label: { chip(i, seg, current: current, inLoop: inLoop, bar: bars[i]) }
                                    .buttonStyle(.plain)
                                    .popover(isPresented: Binding(get: { chordEditing == i }, set: { if !$0 { chordEditing = nil } })) {
                                        ChordEditor(session: session, ctl: ctl, segment: seg, time: time)
                                    }
                                    .id(i)
                            } else {
                                chip(i, seg, current: current, inLoop: inLoop, bar: bars[i]).id(i)
                                    .contextMenu { chipMenu(seg) }
                            }
                        }
                    }
                    .padding(.horizontal, SectionBoxes.inset + 1).padding(.bottom, SectionBoxes.inset)
                }
                .overlay(alignment: .topLeading) {
                    SectionBoxes(session: session, ctl: ctl, chords: chords, frames: stripFrames, selection: selection)
                }
                .coordinateSpace(name: SectionBoxes.space)
                .contentShape(Rectangle())
                .gesture(stripGesture(chords), including: edit ? .subviews : .all)
            }
            .onPreferenceChange(StripFrames.self) { stripFrames = $0 }
            .frame(height: 40 + SectionBoxes.headerHeight + 3 + SectionBoxes.inset + Self.barNumberRow)
            .onChange(of: current) { _, c in
                if let c { withAnimation { proxy.scrollTo(c, anchor: .center) } }
            }
            .onAppear { if let current { proxy.scrollTo(current, anchor: .center) } }
            #if DEBUG
            .task {
                guard model.options.gridHitSelftest else { return }
                try? await Task.sleep(for: .seconds(2.5))
                var fails: [String] = []
                for (i, f) in stripFrames {
                    for x in [f.midX, f.minX + 0.5, f.maxX - 0.5] where stripIndex(at: x) != i {
                        fails.append("tira: x \(x) esperaba \(i), dio \(String(describing: stripIndex(at: x)))")
                    }
                }
                DebugLog.append("tira: \(stripFrames.count) acordes visibles; fallos: \(fails.count)\n" + fails.prefix(10).joined(separator: "\n"))
            }
            #endif
        }
    }

    /// Clic derecho en un acorde: marcar el bucle activo y acciones de la sección que lo contiene.
    @ViewBuilder private func chipMenu(_ seg: ChordSegment) -> some View {
        let mid = (seg.start + seg.end) / 2
        if ctl.loop != nil {
            Button("Marcar sección") { markLoop(solo: false) }
            Button("Marcar como solo") { markLoop(solo: true) }
        }
        if let s = session.sections.first(where: { $0.start <= mid && mid < $0.end }) {
            if ctl.loop != nil { Divider() }
            SectionMenu(section: s, session: session, selection: selection)
        }
    }

    /// Tolerancia por defecto al emparejar el inicio de un acorde con un primer tiempo (sin BPM). Con BPM se usa medio pulso:
    /// los cambios de acorde detectados no caen exactamente en el primer tiempo (ver `ChordGridLayout.probeFraction`).
    private static let barMatchTolerance = 0.05
    /// Alto reservado bajo los acordes para el número de compás.
    private static let barNumberRow: CGFloat = 12

    /// Número de compás (1 = primer primer-tiempo del análisis) de los acordes que abren un compás. Sin análisis, vacío.
    static func barNumbers(_ chords: [ChordSegment], downbeats: [Double], tolerance: Double) -> [Int: Int] {
        var out: [Int: Int] = [:]
        var d = 0
        for (i, c) in chords.enumerated() {
            while d < downbeats.count, downbeats[d] < c.start - tolerance { d += 1 }
            if d < downbeats.count, abs(downbeats[d] - c.start) <= tolerance { out[i] = d + 1; d += 1 }
        }
        return out
    }

    private func chip(_ i: Int, _ seg: ChordSegment, current: Int?, inLoop: Bool, bar: Int?) -> some View {
        let on = i == current
        return VStack(alignment: .leading, spacing: 0) {
            Text(shown(seg.index).name)
                .font(TF.body(14, .bold))
                .foregroundStyle(on ? TF.accentInk : (current.map { i < $0 } == true ? TF.muted.opacity(0.7) : TF.text))
                .frame(minWidth: 52).frame(height: 36).padding(.horizontal, 6)
                .background(on ? TF.accent : (inLoop ? TF.accent.opacity(0.22) : TF.field), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? .clear : (inLoop ? TF.accent : TF.fieldLine)))
                .background(GeometryReader { g in
                    Color.clear.preference(key: StripFrames.self, value: [i: g.frame(in: .named(SectionBoxes.space))])
                })
            // Número de compás bajo el acorde que abre un compás (hueco fijo para que la tira no cambie de alto).
            Text(bar.map { "\($0)" } ?? " ").font(TF.body(10)).foregroundStyle(TF.muted)
                .padding(.leading, 2).frame(height: Self.barNumberRow, alignment: .center)
        }
    }

    private func stripIndex(at x: CGFloat) -> Int? {
        if let hit = stripFrames.first(where: { $0.value.minX <= x && x <= $0.value.maxX }) { return hit.key }
        return stripFrames.min { abs($0.value.midX - x) < abs($1.value.midX - x) }?.key
    }

    /// Clic = saltar al inicio del acorde; arrastre = bucle con imán al pulso (⌥ = al compás).
    private func stripGesture(_ chords: [ChordSegment]) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(SectionBoxes.space))
            .onChanged { v in
                guard abs(v.translation.width) >= ChordGridView.clickSlop,
                      let a = stripIndex(at: v.startLocation.x), let b = stripIndex(at: v.location.x),
                      a < chords.count, b < chords.count else { return }
                stripDrag = min(a, b)...max(a, b)
            }
            .onEnded { v in
                stripDrag = nil
                selection.clear()
                guard let a = stripIndex(at: v.startLocation.x), let b = stripIndex(at: v.location.x),
                      a < chords.count, b < chords.count else { return }
                if abs(v.translation.width) < ChordGridView.clickSlop {
                    ctl.seek(to: chords[a].start)
                } else {
                    let bar = NSEvent.modifierFlags.contains(.option)
                    let r = chords[min(a, b)].start...chords[max(a, b)].end
                    ctl.setLoop(StudyBridge.snap(session.beats, r, bar: bar), name: bar ? "compases" : "acordes")
                }
            }
    }

    private func diagramCard(current: ChordSegment?, next: ChordSegment?) -> some View {
        let label = current.map { shown($0.index) }
        return HStack(spacing: 12) {
            ChordDiagram(shape: label.flatMap { ChordShapes.shape(for: $0, capo: settings.capo) })
            VStack(alignment: .leading, spacing: 2) {
                Text(label?.name ?? "—").font(TF.display(22))
                Text(next.map { "Siguiente: \(shown($0.index).name)" } ?? " ").font(TF.body(12)).foregroundStyle(TF.muted)
                if settings.capo > 0 { Text("Capo \(settings.capo)").font(TF.body(12)).foregroundStyle(TF.accent) }
            }
            .frame(minWidth: 90, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Tempo, tonalidad, ajustes

    private var keyOptions: [(stored: String, shown: String)] {
        (0..<24).compactMap { n in
            let root = n % 12, minor = n >= 12
            guard let lab = ChordLabel(index: root * ChordLabel.qualityCount + (minor ? 0 : 1)) else { return nil }
            let stored = lab.transposed(by: -settings.transpose).labName
            return (stored, SpanishNotes.names[root] + (minor ? " menor" : " mayor"))
        }
    }

    private func keyName(_ lab: String?) -> String {
        guard let lab, let c = ChordLabel(labName: lab), let q = c.quality else { return "—" }
        let t = c.transposed(by: settings.transpose)
        return SpanishNotes.names[t.root ?? 0] + (q == .min ? " menor" : " mayor")
    }

    private var infoRow: some View {
        // Envuelve en varias líneas si no caben (ventana mínima 1100×680); a 1280 caben en una.
        FlowRow(spacing: 10) {
            stat("Tempo detectado", session.beats?.bpm.map { "\(Int($0.rounded())) BPM" } ?? "—")
            HStack(spacing: 6) {
                Text("Tonalidad:").foregroundStyle(TF.text2).fixedSize()
                Menu {
                    ForEach(keyOptions, id: \.stored) { k in
                        Button(k.shown) { session.setKeyOverride(k.stored) }
                    }
                    if session.study.keyOverride != nil {
                        Divider()
                        Button("Volver a la detectada") { session.setKeyOverride(nil) }
                    }
                } label: {
                    Text(keyName(session.effectiveKey) + (session.study.keyOverride != nil ? " (corregida)" : ""))
                        .font(TF.body(13, .semibold)).foregroundStyle(TF.text)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .disabled(session.analysis == nil)
            }
            labeled("Transponer") {
                Picker("", selection: Binding(get: { settings.transpose }, set: { ctl.setTranspose($0) })) {
                    ForEach(Array(StudySession.transposeRange), id: \.self) { n in
                        Text(n == 0 ? "0 semitonos" : String(format: "%+d", n)).tag(n)
                    }
                }.labelsHidden().frame(width: 112)
            }
            labeled("Capo virtual") {
                Picker("", selection: Binding(get: { settings.capo }, set: { ctl.setCapo($0) })) {
                    Text("Sin capo").tag(0)
                    ForEach(1...12, id: \.self) { Text("Traste \($0)").tag($0) }
                }.labelsHidden().frame(width: 112)
            }
            labeled("Afinación fina") {
                Slider(value: Binding(get: { settings.fineCents }, set: { ctl.setFineCents($0.rounded()) }),
                       in: StudySession.fineCentsRange).frame(width: 70).tint(TF.accent)
                Text("\(Int(settings.fineCents)) cents").frame(width: 56, alignment: .leading)
                    .font(TF.body(13)).monospacedDigit()
            }
        }
        .font(TF.body(13)).foregroundStyle(TF.text2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) { Text("\(title):"); Text(value).fontWeight(.semibold).foregroundStyle(TF.text) }
    }

    private func labeled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 6) { Text(title).fixedSize(); content() }
    }

    // MARK: Transporte

    /// Marca inicio / fin del bucle en la posición actual. «Fin» solo está activo con un inicio pendiente o un bucle.
    private var loopMarks: some View {
        HStack(spacing: 6) {
            Button(pendingLoopStart.map { "Inicio \(Fmt.clock($0))" } ?? "Inicio") { markLoopStart() }
                .buttonStyle(SecondaryButton(height: 30))
                .foregroundStyle(pendingLoopStart == nil ? TF.text : TF.accent)
                .help("Marca el inicio del bucle en la posición actual")
            Button("Fin") { markLoopEnd() }
                .buttonStyle(SecondaryButton(height: 30))
                .disabled(pendingLoopStart == nil && ctl.loop == nil)
                .help("Marca el final del bucle en la posición actual")
        }
        .fixedSize()
    }

    private func markLoopStart() {
        if let loop = ctl.loop, time < loop.upperBound {
            pendingLoopStart = nil
            ctl.setLoop(time...loop.upperBound, name: ctl.loopName)
        } else { pendingLoopStart = time }
    }

    private func markLoopEnd() {
        if let a = pendingLoopStart, time > a {
            ctl.setLoop(a...time, name: nil); pendingLoopStart = nil
        } else if let loop = ctl.loop, time > loop.lowerBound {
            ctl.setLoop(loop.lowerBound...time, name: ctl.loopName)
        }
    }

    private var transport: some View {
        FlowRow(spacing: 14) {
            Button { ctl.togglePlay() } label: {
                Image(systemName: ctl.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20)).foregroundStyle(TF.accentInk)
                    .frame(width: 52, height: 52).background(TF.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ctl.isPlaying ? "Pausar" : "Reproducir")

            (Text(Fmt.clock(time)).foregroundStyle(TF.text) + Text(" / \(Fmt.clock(ctl.duration))").foregroundStyle(TF.muted))
                .font(TF.display(20)).monospacedDigit()

            loopMarks

            if let loop = ctl.loop {
                HStack(spacing: 6) {
                    Text("Bucle: \(ctl.loopName ?? "libre") · \(Fmt.clock(loop.lowerBound))–\(Fmt.clock(loop.upperBound))")
                        .lineLimit(1).fixedSize()
                    Button { ctl.setLoop(nil) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Quitar bucle")
                }
                .font(TF.body(13, .semibold)).foregroundStyle(TF.accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(TF.accentBg, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 10) {
                Text("Tempo").fixedSize()
                Slider(value: Binding(get: { settings.rate * 100 }, set: { ctl.setRate(($0 / 5).rounded() * 0.05) }),
                       in: 50...200).frame(width: 120).tint(TF.accent)
                Text(Fmt.percent(settings.rate)).fontWeight(.semibold).foregroundStyle(TF.text)
                    .frame(width: 54, alignment: .leading).monospacedDigit()
            }
            .font(TF.body(13)).foregroundStyle(TF.text2)

            Toggle("Metrónomo", isOn: Binding(get: { settings.metronomeOn }, set: { ctl.setMetronome($0) }))
                .toggleStyle(.checkbox).font(TF.body(13)).foregroundStyle(TF.text2)
                .disabled(session.beats == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Fmt {
    /// m:ss.
    static func clock(_ s: Double) -> String {
        let t = Int(max(s, 0)); return String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Acordes

struct ChordEditor: View {
    let session: StudySession
    let ctl: BackingController
    let segment: ChordSegment
    let time: Double

    @State private var root: Int?
    @State private var quality: ChordQuality?

    private var transpose: Int { ctl.settings.transpose }

    init(session: StudySession, ctl: BackingController, segment: ChordSegment, time: Double) {
        self.session = session; self.ctl = ctl; self.segment = segment; self.time = time
        let shown = (ChordLabel(index: segment.index) ?? .unknown).transposed(by: ctl.settings.transpose)
        _root = State(initialValue: shown.root)
        _quality = State(initialValue: shown.quality)
    }

    /// Acorde mostrado (transpuesto) → etiqueta guardada (sin transponer).
    private func store(_ shown: ChordLabel) -> Int { shown.transposed(by: -transpose).index }

    private func commit() {
        guard let r = root, let q = quality, let l = ChordLabel(index: r * ChordLabel.qualityCount + q.rawValue) else { return }
        session.setChord(start: segment.start, end: segment.end, index: store(l))
    }

    private var splitBeat: Double? {
        guard time > segment.start, time < segment.end else { return nil }
        let b = StudyBridge.nearestBeat(session.beats, to: time)
        return b > segment.start + 0.05 && b < segment.end - 0.05 ? b : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Acorde").font(TF.display(16))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 6), count: 6), spacing: 6) {
                ForEach(0..<12, id: \.self) { r in
                    let name = ChordLabel(index: r * ChordLabel.qualityCount + 1)?.name ?? ""
                    chip(name, on: root == r) { root = r; commit() }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(60), spacing: 6), count: 4), spacing: 6) {
                ForEach(ChordQuality.allCases, id: \.rawValue) { q in
                    chip(q.suffix.isEmpty ? "mayor" : q.suffix, on: quality == q) { quality = q; commit() }
                }
            }
            HStack {
                chip("N (sin acorde)", on: segment.index == ChordLabel.noChordIndex) {
                    session.setChord(start: segment.start, end: segment.end, index: ChordLabel.noChordIndex)
                }
                Spacer()
            }
            Divider()
            HStack {
                Button("Partir aquí") {
                    if let b = splitBeat {
                        session.setChord(start: segment.start, end: b, index: segment.index)
                        session.setChord(start: b, end: segment.end, index: segment.index)
                    }
                }
                .disabled(splitBeat == nil)
                .help("Parte el tramo en el pulso más cercano al cursor de reproducción")
                Spacer()
                Button("Quitar corrección") { session.removeChordOverrides(in: segment.start...segment.end) }
                    .disabled(!session.study.chordOverrides.contains { $0.start < segment.end && $0.end > segment.start })
            }
        }
        .padding(16)
    }

    private func chip(_ text: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(TF.body(13, .semibold)).frame(minWidth: 36).frame(height: 30).padding(.horizontal, 4)
                .foregroundStyle(on ? TF.accentInk : TF.text)
                .background(on ? TF.accent : TF.field, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }
}

// MARK: - Barra de progreso (slider de posición)

/// Clic en cualquier punto salta; arrastrar mueve el cabezal con seek continuo. Muestra el bucle, no lo marca.
struct ProgressBarView: View {
    let session: StudySession
    let ctl: BackingController
    let time: Double
    let duration: Double

    @State private var scrub: Double?
    @State private var lastSeek = Date.distantPast
    /// Con el reproductor en marcha cada seek reinicia la pasada: se limita la cadencia durante el arrastre.
    static let scrubInterval: TimeInterval = 0.12

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let shownTime = scrub ?? time
            let x: (Double) -> CGFloat = { CGFloat(min(max($0 / duration, 0), 1)) * w }
            let t: (CGFloat) -> Double = { min(max(Double($0 / max(w, 1)) * duration, 0), duration) }
            ZStack(alignment: .leading) {
                Capsule().fill(TF.line).frame(height: 10)
                Capsule().fill(Color(hex: 0x5BC0EB)).frame(width: x(shownTime), height: 10)
                if let l = ctl.loop {
                    RoundedRectangle(cornerRadius: 6).fill(TF.accent.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(TF.accent))
                        .frame(width: max(x(l.upperBound) - x(l.lowerBound), 2), height: 22)
                        .offset(x: x(l.lowerBound))
                }
                Circle().fill(TF.text).frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: x(shownTime) - 7)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let target = t(v.location.x)
                    scrub = target
                    if Date().timeIntervalSince(lastSeek) >= Self.scrubInterval {
                        lastSeek = Date()
                        ctl.seek(to: target)
                    }
                }
                .onEnded { v in
                    ctl.seek(to: t(v.location.x))
                    scrub = nil
                })
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Posición")
        .accessibilityValue("\(Fmt.clock(time)) de \(Fmt.clock(duration))")
        .accessibilityAdjustableAction { dir in ctl.seek(to: time + (dir == .increment ? 5 : -5)) }
    }
}
