import AppKit
import Store
import StudyKit
import SwiftUI

typealias SongSection = Store.Section

/// Tarjeta «Línea de tiempo» de Backing: secciones, tira de acordes, tonalidad, transposición, barra de
/// progreso con bucle y transporte (mini-spec Fase 2 §2).
struct BackingTimelineCard: View {
    let session: StudySession
    let ctl: BackingController
    let time: Double

    let expanded: Binding<Bool>
    let editMode: Binding<Bool>

    @Environment(AppModel.self) private var model
    @State private var chordEditing: Int?
    @State private var gridEditing: Double?
    @State private var sectionEditing: UUID?
    @State private var stripFrames: [Int: CGRect] = [:]
    @State private var stripDrag: ClosedRange<Int>?

    private var settings: PlayerSettings { ctl.settings }
    private var duration: Double { max(ctl.duration, 0.001) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionsLane(session: session, ctl: ctl, duration: duration, editing: $sectionEditing)
                chordsHeader
                chordsArea
                infoRow
                ProgressBarView(session: session, ctl: ctl, time: time, duration: duration)
                transport
                RecordStatus(session: session, ctl: ctl)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
        }
        .onChange(of: editMode.wrappedValue) { chordEditing = nil; gridEditing = nil }
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
            Text(edit ? "Modo edición: clic en un acorde para cambiarlo o partirlo. No se marcan bucles."
                      : "Clic: saltar al acorde · arrastrar: bucle (⌥ = a compases)")
                .font(TF.body(12)).foregroundStyle(edit ? TF.accent : TF.muted).lineLimit(1)
            Spacer(minLength: 0)
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
                    ChordGridView(session: session, ctl: ctl, time: time, edit: edit, shown: shown, editing: $gridEditing)
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
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(Array(chords.enumerated()), id: \.offset) { i, seg in
                        let inLoop = l.map { ($0.lowerBound...$0.upperBound).contains((seg.start + seg.end) / 2) } ?? false
                        if edit {
                            Button { chordEditing = i } label: { chip(i, seg, current: current, inLoop: inLoop) }
                                .buttonStyle(.plain)
                                .popover(isPresented: Binding(get: { chordEditing == i }, set: { if !$0 { chordEditing = nil } })) {
                                    ChordEditor(session: session, ctl: ctl, segment: seg, time: time)
                                }
                                .id(i)
                        } else {
                            chip(i, seg, current: current, inLoop: inLoop).id(i)
                        }
                    }
                }
                .coordinateSpace(name: "strip")
                .contentShape(Rectangle())
                .gesture(stripGesture(chords), including: edit ? .subviews : .all)
            }
            .onPreferenceChange(StripFrames.self) { stripFrames = $0 }
            .frame(height: 40)
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

    private func chip(_ i: Int, _ seg: ChordSegment, current: Int?, inLoop: Bool) -> some View {
        let on = i == current
        return Text(shown(seg.index).name)
            .font(TF.body(14, .bold))
            .foregroundStyle(on ? TF.accentInk : (current.map { i < $0 } == true ? TF.muted.opacity(0.7) : TF.text))
            .frame(minWidth: 52).frame(height: 36).padding(.horizontal, 6)
            .background(on ? TF.accent : (inLoop ? TF.accent.opacity(0.22) : TF.field), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? .clear : (inLoop ? TF.accent : TF.fieldLine)))
            .background(GeometryReader { g in
                Color.clear.preference(key: StripFrames.self, value: [i: g.frame(in: .named("strip"))])
            })
    }

    private func stripIndex(at x: CGFloat) -> Int? {
        if let hit = stripFrames.first(where: { $0.value.minX <= x && x <= $0.value.maxX }) { return hit.key }
        return stripFrames.min { abs($0.value.midX - x) < abs($1.value.midX - x) }?.key
    }

    /// Clic = saltar al inicio del acorde; arrastre = bucle con imán al pulso (⌥ = al compás).
    private func stripGesture(_ chords: [ChordSegment]) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("strip"))
            .onChanged { v in
                guard abs(v.translation.width) >= ChordGridView.clickSlop,
                      let a = stripIndex(at: v.startLocation.x), let b = stripIndex(at: v.location.x),
                      a < chords.count, b < chords.count else { return }
                stripDrag = min(a, b)...max(a, b)
            }
            .onEnded { v in
                stripDrag = nil
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
        HStack(spacing: 16) {
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
                       in: StudySession.fineCentsRange).frame(width: 90).tint(TF.accent)
                Text("\(Int(settings.fineCents)) cents").frame(width: 62, alignment: .leading)
                    .font(TF.body(13)).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .font(TF.body(13)).foregroundStyle(TF.text2)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) { Text("\(title):"); Text(value).fontWeight(.semibold).foregroundStyle(TF.text) }
    }

    private func labeled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 6) { Text(title).fixedSize(); content() }
    }

    // MARK: Transporte

    private var transport: some View {
        HStack(spacing: 14) {
            Button { ctl.togglePlay() } label: {
                Image(systemName: ctl.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20)).foregroundStyle(TF.accentInk)
                    .frame(width: 52, height: 52).background(TF.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(ctl.isPlaying ? "Pausar" : "Reproducir")

            (Text(Fmt.clock(time)).foregroundStyle(TF.text) + Text(" / \(Fmt.clock(ctl.duration))").foregroundStyle(TF.muted))
                .font(TF.display(20)).monospacedDigit()

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
            Spacer(minLength: 0)
            RecordButton(ctl: ctl)
        }
    }
}

extension Fmt {
    /// m:ss.
    static func clock(_ s: Double) -> String {
        let t = Int(max(s, 0)); return String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Secciones

struct SectionsLane: View {
    let session: StudySession
    let ctl: BackingController
    let duration: Double
    @Binding var editing: UUID?

    @State private var drag: ClosedRange<Double>?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let t: (CGFloat) -> Double = { min(max(Double($0 / max(w, 1)) * duration, 0), duration) }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(TF.bg.opacity(0.5))
                    .overlay(Text(session.sections.isEmpty && drag == nil ? "Arrastra aquí para marcar una sección" : "")
                        .font(TF.body(12)).foregroundStyle(TF.muted))
                ForEach(session.sections, id: \.id) { s in pill(s, width: w) }
                if let d = drag {
                    RoundedRectangle(cornerRadius: 6).fill(TF.accent.opacity(0.25))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(TF.accent))
                        .frame(width: CGFloat((d.upperBound - d.lowerBound) / duration) * w, height: 26)
                        .offset(x: CGFloat(d.lowerBound / duration) * w, y: 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 6)
                .onChanged { v in
                    let a = t(v.startLocation.x), b = t(v.location.x)
                    drag = min(a, b)...max(a, b)
                }
                .onEnded { v in
                    drag = nil
                    let a = t(v.startLocation.x), b = t(v.location.x)
                    // Un arrastre que empieza sobre una sección existente no crea otra.
                    guard !session.sections.contains(where: { $0.start <= a && a < $0.end }) else { return }
                    let r = StudyBridge.snap(session.beats, min(a, b)...max(a, b), bar: true)
                    guard r.upperBound - r.lowerBound > 0.2 else { return }
                    editing = session.addSection(name: "Sección", start: r.lowerBound, end: r.upperBound)
                })
        }
        .frame(height: 30)
    }

    private func pill(_ s: SongSection, width w: CGFloat) -> some View {
        let x0 = CGFloat(s.start / duration) * w
        let x1 = CGFloat(s.end / duration) * w
        let isLoop = isActiveLoop(s)
        return Text(s.name)
            .font(TF.body(12, .semibold)).lineLimit(1)
            .foregroundStyle(isLoop ? TF.accent : TF.text2)
            .padding(.horizontal, 8)
            .frame(width: max(x1 - x0 - 2, 4), height: 26, alignment: .leading)
            .background(isLoop ? TF.accentBg : TF.neutralBg, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isLoop ? TF.accent : .clear))
            .contentShape(Rectangle())
            .onTapGesture {
                if isLoop { ctl.setLoop(nil) } else { ctl.setLoop(s.start...s.end, name: s.name) }
            }
            .contextMenu {
                Button("Editar nombre y tipo…") { editing = s.id }
                Button("Borrar sección", role: .destructive) { session.removeSection(s.id) }
            }
            .popover(isPresented: Binding(get: { editing == s.id }, set: { if !$0 { editing = nil } })) {
                SectionEditor(session: session, id: s.id, editing: $editing)
            }
            .offset(x: x0 + 1, y: 2)
    }

    private func isActiveLoop(_ s: SongSection) -> Bool {
        guard let l = ctl.loop else { return false }
        return abs(l.lowerBound - s.start) < 0.01 && abs(l.upperBound - s.end) < 0.01
    }
}

struct SectionEditor: View {
    let session: StudySession
    let id: UUID
    @Binding var editing: UUID?

    private var section: SongSection? { session.sections.first { $0.id == id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sección").font(TF.display(16))
            TextField("Nombre", text: Binding(get: { section?.name ?? "" },
                                               set: { n in session.updateSection(id) { $0.name = n } }))
                .textFieldStyle(.roundedBorder).frame(width: 220)
            Picker("Tipo", selection: Binding(get: { section?.kind ?? "" }, set: { k in
                session.updateSection(id) { s in
                    let old = SectionKinds.name(s.kind)
                    s.kind = k.isEmpty ? nil : k
                    if s.name == "Sección" || s.name == old, let n = SectionKinds.name(s.kind) { s.name = n }
                }
            })) {
                Text("Sin tipo").tag("")
                ForEach(SectionKinds.all, id: \.id) { Text($0.name).tag($0.id) }
            }
            HStack {
                Button("Borrar", role: .destructive) { editing = nil; session.removeSection(id) }
                Spacer()
                Button("Hecho") { editing = nil }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).frame(width: 260)
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
