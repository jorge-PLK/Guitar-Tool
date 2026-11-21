import AppKit
import AudioKit
import Store
import SwiftUI

/// Pantalla Grabar (boceto `docs/design/Record.dc.html`, con los cambios de la mini-spec Fase 6, «Interfaz»).
struct RecordView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.backingTarget == nil {
                chooser
            } else if let session = model.study {
                RecordContent(session: session).id(session.projectID)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: model.backingTarget) {
            if let id = model.backingTarget { await model.openStudy(id) }
        }
        .onDisappear { Task { if model.section != .montage { await model.closeStudy() } } }
    }

    private var chooser: some View {
        let ready = model.entries.filter { $0.separationState == SeparationStatus.done.rawValue }
        return VStack(alignment: .leading, spacing: 16) {
            Text("Grabar").font(TF.display(30))
            if ready.isEmpty {
                Text("Aún no hay temas separados. Importa uno y sepáralo en la biblioteca.").foregroundStyle(TF.muted)
            } else {
                Text("Elige un tema").foregroundStyle(TF.muted)
                ForEach(ready, id: \.id) { e in
                    Button { model.backingTarget = e.id } label: {
                        HStack { Text(e.title); Spacer() }.padding(.horizontal, 12).padding(.vertical, 10)
                            .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 40).padding(.vertical, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RecordContent: View {
    let session: StudySession
    @Environment(AppModel.self) private var model
    @State private var ctl: RecordController?

    var body: some View {
        Group {
            if let ctl, session.project.separation.state == .done {
                RecordBody(ctl: ctl)
            } else if session.project.separation.state != .done {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Este tema aún no está separado").font(TF.display(18))
                        Text("Grabar necesita los stems. Sepáralo desde la biblioteca y vuelve.").foregroundStyle(TF.muted)
                        Button("Ir a la biblioteca") { model.section = .library }.buttonStyle(SecondaryButton())
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(36)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard ctl == nil, session.project.separation.state == .done else { return }
            let c = RecordController(session: session, model: model)
            ctl = c
            c.open()
            #if DEBUG
            if let screen = model.options.screen, screen.hasPrefix("record") { await c.seedDemo(screen) }
            #endif
        }
        .onDisappear {
            ctl?.close()
            ctl = nil
        }
    }
}

private struct RecordBody: View {
    let ctl: RecordController
    @Environment(AppModel.self) private var model

    @State private var time = 0.0
    @State private var meters: [String: ChannelMeter] = [:]
    @State private var inputLevel: Float = 0
    @State private var addingPart = false
    @State private var mixerExpanded = false
    @State private var deleting: UUID?
    @State private var viewing: TakeViewRequest?
    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private let slowTick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var ctl = ctl
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    RecordPreview(ctl: ctl)
                    RecordBar(ctl: ctl, time: time)
                    status
                    if ctl.punchEnabled { PunchTimeline(ctl: ctl, time: time) }
                    RecordMixer(ctl: ctl, meters: meters, inputLevel: inputLevel, expanded: $mixerExpanded)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                ScrollView { partsPanel }.frame(width: 320)
            }
        }
        .padding(.horizontal, 36).padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #if DEBUG
        .onAppear { if model.options.screen == "record-mixer-expanded" { mixerExpanded = true } }
        #endif
        .onReceive(tick) { _ in
            let t = ctl.player.currentTime
            if t != time { time = t }
            if ctl.player.isPlaying || meters.values.contains(where: { $0.rmsDB > -119 }) { meters = ctl.player.meters }
            let guitarIn = model.audio.settings?.guitarIn ?? []
            let levels = model.audio.inputLevels ?? []
            inputLevel = guitarIn.compactMap { $0 - 1 < levels.count && $0 >= 1 ? levels[$0 - 1] : nil }.max() ?? 0
        }
        .onReceive(slowTick) { _ in ctl.pollCamera() }
        .sheet(item: $ctl.offsetRequest) { OffsetSheet(request: $0, ctl: ctl) }
        .sheet(isPresented: $addingPart) { AddPartSheet(ctl: ctl) }
        .sheet(item: $viewing) { req in takeViewer(req) }
        .confirmationDialog("¿Borrar la toma?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar toma", role: .destructive) { if let id = deleting { ctl.deleteTake(id) }; deleting = nil }
            Button("Cancelar", role: .cancel) { deleting = nil }
        } message: {
            Text("Se borra su carpeta (audio y vídeo). No se puede deshacer.")
        }
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                let song = ctl.session.project.song
                Text([song.artist, song.title, "Multitoma"].compactMap { $0 }.joined(separator: " · "))
                    .font(TF.body(13)).foregroundStyle(TF.muted)
                Text("Grabar").font(TF.display(26))
            }
            Spacer()
            Button { model.section = .montage } label: {
                Text("Ir al montaje").font(TF.body(14, .semibold)).foregroundStyle(TF.text2)
                    .padding(.horizontal, 18).frame(height: 44)
                    .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(TF.fieldLine))
            }
            .buttonStyle(.plain)
            .disabled(ctl.isBusy)
            .help("Monta las mejores tomas en un vídeo")
        }
    }

    // MARK: Estado

    private var status: some View {
        let audio = model.audio
        return VStack(alignment: .leading, spacing: 4) {
            if let b = ctl.blockReason { line(b, TF.muted) }
            if ctl.blockReason == nil, ctl.phase == .idle, !audio.calibrationValid { line(RecordStatus.uncalibratedWarning, TF.accent) }
            switch ctl.cameraState {
            case .none(let m): line("\(m) Se grabará solo el audio.", TF.accent)
            case .denied: line("Sin permiso de cámara: se grabará solo el audio. Concédelo en Ajustes del Sistema > Privacidad > Cámara.", TF.accent)
            case .failed(let m): line("\(m) Se grabará solo el audio.", TF.accent)
            default: EmptyView()
            }
            ForEach(ctl.messages, id: \.self) { line($0, TF.accent) }
            ForEach(audio.takeNotices, id: \.self) { line($0, TF.accent) }
            if let e = ctl.loadError { line(e, TF.danger) }
            if let e = ctl.session.takeSaveError { line(e, TF.danger) }
        }
    }

    private func line(_ text: String, _ color: Color) -> some View {
        Text(text).font(TF.body(12)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Partes

    private var partsPanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Partes").font(TF.display(18))
                Text("En cada toma suena el backing sin esa parte y con tus tomas anteriores.")
                    .font(TF.body(13)).foregroundStyle(TF.muted).fixedSize(horizontal: false, vertical: true)
                ForEach(ctl.state.parts) { part in partBox(part) }
                Button { addingPart = true } label: {
                    Text("Añadir parte").font(TF.body(14, .medium)).foregroundStyle(TF.text2)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(TF.muted))
                }
                .buttonStyle(.plain).disabled(ctl.isBusy)
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
        }
    }

    private func partBox(_ part: RecordingPart) -> some View {
        let active = part.id == ctl.activePartID
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(part.name).font(TF.body(14, .semibold)).lineLimit(1)
                Spacer()
                chip(ctl.status(of: part))
            }
            Text(part.replaces.map { "Sustituye: \(ctl.guitarName($0))" } ?? "Parte añadida")
                .font(TF.body(12)).foregroundStyle(TF.muted)
            FlowRow {
                ForEach(Array(ctl.takes(of: part).enumerated()), id: \.element.id) { i, t in takeButton(t, number: i + 1, part: part, best: part.bestTakeID == t.id) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? TF.accentBg : TF.field, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? TF.accent : TF.fieldLine))
        .contentShape(Rectangle())
        .onTapGesture { ctl.selectPart(part.id) }
        .accessibilityElement(children: .contain).accessibilityLabel(part.name)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func chip(_ s: RecordController.PartStatus) -> some View {
        let (text, fg, bg): (String, Color, Color) = switch s {
        case .done: ("Hecha", TF.ok, TF.okBg)
        case .recording: ("Grabando", TF.danger, TF.dangerBg)
        case .pending: ("Pendiente", TF.text2, TF.neutralBg)
        }
        return Text(text).font(TF.body(11, .semibold)).foregroundStyle(fg)
            .padding(.horizontal, 9).padding(.vertical, 3).background(bg, in: Capsule())
    }

    /// Visor de la toma (mini-spec Fase 7b, punto 9): marcar como mejor y eliminar actúan como en la fila.
    @ViewBuilder private func takeViewer(_ req: TakeViewRequest) -> some View {
        TakeViewer(project: ctl.session.project, layout: ctl.session.layout, takeID: req.takeID, title: req.title,
                   isBest: ctl.state.part(containingTake: req.takeID)?.bestTakeID == req.takeID,
                   onMarkBest: { ctl.markBest(req.takeID) },
                   onDelete: { viewing = nil; ctl.deleteTake(req.takeID) },
                   onClose: { viewing = nil })
    }

    private func viewTake(_ t: Take, number: Int, part: RecordingPart) {
        guard ctl.prepareToViewTake() else { return }
        viewing = TakeViewRequest(takeID: t.id, title: "Toma \(number) · \(part.name)")
    }

    private func takeButton(_ t: Take, number: Int, part: RecordingPart, best: Bool) -> some View {
        HStack(spacing: 4) {
            takeMenu(t, number: number, best: best)
            Button { viewTake(t, number: number, part: part) } label: {
                Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(TF.text2)
                    .frame(width: 32, height: 32)
                    .background(TF.sidebar, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(TF.fieldLine))
            }
            .buttonStyle(.plain).disabled(ctl.isBusy || t.processedFile == nil || t.songStart == nil)
            .help("Ver toma").accessibilityLabel("Ver toma \(number)")
        }
    }

    private func takeMenu(_ t: Take, number: Int, best: Bool) -> some View {
        let selected = ctl.selectedTakeID == t.id
        return Menu {
            Button("Marcar como mejor") { ctl.markBest(t.id) }.disabled(best)
            Button("Ajustar desfase…") { ctl.adjustOffset(takeID: t.id) }.disabled(t.videoFile == nil)
            Button("Punch-in") { ctl.startPunch(on: t.id) }
            Divider()
            Button("Borrar…", role: .destructive) { deleting = t.id }
        } label: {
            Text(best ? "Toma \(number) · mejor" : "Toma \(number)")
                .font(TF.body(12, .semibold)).foregroundStyle(best ? TF.ok : TF.text2)
                .padding(.horizontal, 10).frame(height: 32)
                .background(best ? TF.okBg : (selected ? TF.accentBg : TF.sidebar), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? TF.accent : (best ? Color(hex: 0x2F6B45) : TF.fieldLine),
                                                                  lineWidth: selected ? 2 : 1))
        } primaryAction: {
            ctl.selectTake(t.id)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.visible).fixedSize().disabled(ctl.isBusy)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel("Toma \(number)\(best ? ", mejor" : "")")
    }
}

/// Envuelve sus hijos en filas (los botones de toma, las opciones de la barra de grabación y las filas de Backing).
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    /// Reparte los hijos en filas de ancho máximo `width`; cada fila es una lista de (índice, tamaño) y su alto.
    private func rows(_ subviews: Subviews, width: CGFloat) -> [(items: [(Int, CGSize)], height: CGFloat)] {
        var rows: [(items: [(Int, CGSize)], height: CGFloat)] = []
        var cur: [(Int, CGSize)] = [], x: CGFloat = 0, h: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { rows.append((cur, h)); cur = []; x = 0; h = 0 }
            cur.append((i, sz)); x += sz.width + spacing; h = max(h, sz.height)
        }
        if !cur.isEmpty { rows.append((cur, h)) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rs = rows(subviews, width: proposal.width ?? .infinity)
        let w = rs.map { $0.items.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max($0.items.count - 1, 0)) }.max() ?? 0
        return CGSize(width: w, height: rs.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rs.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            for (i, sz) in row.items {
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - sz.height) / 2), proposal: ProposedViewSize(sz))
                x += sz.width + spacing
            }
            y += row.height + spacing
        }
    }
}

/// «Añadir parte»: nombre y guitarra que sustituye (mini-spec Fase 6, «Partes y tomas»).
private struct AddPartSheet: View {
    let ctl: RecordController
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role: GuitarRole?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Añadir parte").font(TF.display(20))
            TextField("Nombre de la parte", text: $name).textFieldStyle(.roundedBorder)
            Picker("Guitarra que sustituye", selection: $role) {
                Text("Ninguna (parte añadida)").tag(GuitarRole?.none)
                ForEach(ctl.guitarRoles, id: \.self) { r in Text(ctl.guitarName(r)).tag(GuitarRole?.some(r)) }
            }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.buttonStyle(SecondaryButton())
                Button("Añadir") { ctl.addPart(name: name, replaces: role); dismiss() }
                    .buttonStyle(PrimaryButton())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(width: 420).background(TF.card).foregroundStyle(TF.text)
    }
}

// MARK: - Vista previa

struct RecordPreview: View {
    let ctl: RecordController

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(RadialGradient(colors: [Color(hex: 0x2A3036), Color(hex: 0x121417)], center: .init(x: 0.5, y: 0.4),
                                     startRadius: 0, endRadius: 520))
            content
            VStack {
                // Una fila si cabe; con la vista previa estrecha (ventana al mínimo), la cámara baja a una segunda fila
                // antes que partir o recortar el nombre de la parte.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) { recPill.fixedSize(); Spacer(minLength: 8); cameraPills }
                    VStack(alignment: .leading, spacing: 8) {
                        recPill
                        HStack { Spacer(minLength: 0); cameraPills }
                    }
                }
                Spacer()
                if case .counting(let n) = ctl.phase {
                    Text("\(n)").font(TF.display(64)).foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 10, y: 4)
                }
            }
            .padding(16)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(TF.line))
        // Ocupa todo el espacio libre (16:9); se encoge cuando el mezclador se expande.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var content: some View {
        switch ctl.cameraState {
        case .live(let s):
            CameraPreviewLayerView(session: s, rotation: ctl.cameraRotation)
        case .simulated:
            placeholder("Vista previa de la cámara · \(ctl.cameraName ?? "simulada") (simulada)")
        case .none, .denied, .failed:
            placeholder("Sin vídeo: se grabará solo el audio")
        case .idle:
            ProgressView().controlSize(.small)
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "video").font(.system(size: 40, weight: .light))
            Text(text)
        }
        .foregroundStyle(TF.muted)
    }

    @ViewBuilder private var cameraPills: some View {
        if let f = ctl.cameraLabel {
            pill(Text(f).foregroundStyle(TF.text2)).fixedSize()
            rotateButton.fixedSize()
        }
    }

    private var recPill: some View {
        let recording = ctl.phase != .idle && ctl.phase != .adjusting
        let part = ctl.activePart?.name ?? ""
        return pill(HStack(spacing: 8) {
            Circle().fill(recording ? Color(hex: 0xE5534B) : TF.muted).frame(width: 10, height: 10)
            Text("\(recording ? "REC · " : "")Toma \(ctl.nextTakeNumber) · \(part)").fontWeight(.semibold)
        })
    }

    /// «Rotar»: 90° más por clic, guardado en la cámara activa (vídeo vertical); lo heredan sus tomas nuevas.
    private var rotateButton: some View {
        let degrees = ctl.cameraRotation
        return Button { ctl.rotateCamera() } label: {
            pill(HStack(spacing: 6) {
                Image(systemName: "rotate.right")
                Text(degrees == 0 ? "Rotar" : "Rotar · \(degrees)°")
            }.foregroundStyle(degrees == 0 ? TF.text2 : TF.accent))
        }
        .buttonStyle(.plain)
        .disabled(ctl.phase != .idle)
        .help("Gira la imagen de esta cámara 90° en sentido horario (no se recodifica; se aplica al ver y montar)")
        .accessibilityLabel("Rotar cámara, ahora \(degrees) grados")
    }

    private func pill<C: View>(_ c: C) -> some View {
        // Una sola línea: la píldora de la toma se recorta con «…» antes que partirse en dos.
        c.font(TF.body(14)).lineLimit(1).padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color(hex: 0x0F1113).opacity(0.75), in: Capsule())
    }
}

// MARK: - Barra de grabación

struct RecordBar: View {
    let ctl: RecordController
    let time: Double
    @Environment(AppModel.self) private var model

    private static let red = Color(hex: 0xC8433A)

    var body: some View {
        let blocked = ctl.phase == .idle && ctl.blockReason != nil
        let recording: Bool = { if case .recording = ctl.phase { return true }; if case .counting = ctl.phase { return true }; return false }()
        VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 14) {
            Button {
                if recording { ctl.stopTake() } else { ctl.startTake() }
            } label: {
                HStack(spacing: 8) {
                    if recording { RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 10, height: 10) }
                    else { Circle().fill(.white).frame(width: 10, height: 10) }
                    Text(recording ? "Parar" : "Grabar")
                }
                .font(TF.body(15, .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 22).frame(height: 48)
                .background(Self.red, in: Capsule())
                .opacity(blocked || ctl.phase == .finishing || ctl.phase == .adjusting ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(blocked || ctl.phase == .finishing || ctl.phase == .adjusting)
            .accessibilityLabel(recording ? "Parar la grabación" : "Grabar")

            (Text(Fmt.duration(time)).font(TF.display(20)) + Text(" / \(Fmt.duration(ctl.plannedStop ?? ctl.duration))").font(TF.body(16, .medium)).foregroundStyle(TF.muted))
                .monospacedDigit()
                .help(ctl.plannedStop == nil ? "Duración del tema" : "Para sola al acabar la sección más el margen")

            Spacer(minLength: 0)
            offsetLabel
        }
        // Las opciones envuelven en varias líneas si no caben (ventana mínima 1100×680).
        FlowRow(spacing: 18) {
            Picker("Empezar en", selection: Binding(get: { ctl.startSectionID }, set: { ctl.setStartSection($0) })) {
                Text("Principio").tag(UUID?.none)
                ForEach(ctl.sections, id: \.id) { s in Text(s.name).tag(UUID?.some(s.id)) }
            }
            .pickerStyle(.menu).fixedSize().disabled(ctl.isBusy || ctl.punchEnabled)

            Toggle("Cuenta de 1 compás", isOn: Binding(get: { ctl.state.countIn }, set: { ctl.setCountIn($0) }))
                .toggleStyle(.checkbox).disabled(ctl.isBusy).fixedSize()

            Picker("Margen", selection: Binding(get: { ctl.state.preRollBars }, set: { ctl.setPreRoll($0) })) {
                Text("2 compases").tag(2)
                Text("1 compás").tag(1)
                Text("Sin margen").tag(0)
            }
            .pickerStyle(.menu).fixedSize().disabled(ctl.isBusy)

            Toggle("Punch-in", isOn: Binding(get: { ctl.punchEnabled }, set: { on in
                if on, ctl.selectedTake == nil, let best = ctl.activePart?.bestTakeID { ctl.selectTake(best) }
                ctl.punchEnabled = on
            }))
            .toggleStyle(.checkbox).disabled(ctl.isBusy || (ctl.activePart?.takeIDs.isEmpty ?? true)).fixedSize()
            .help("Vuelve a grabar un tramo de una toma")
        }
        }
        .font(TF.body(14)).foregroundStyle(TF.text2)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(TF.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(TF.line))
    }

    @ViewBuilder private var offsetLabel: some View {
        if let off = ctl.defaultOffset {
            let ms = Int((off * 1000).rounded())
            Text(ms == 0 ? "Desfase de la cámara: sin ajustar" : "Desfase de la cámara: \(ms > 0 ? "+" : "")\(ms) ms")
                .font(TF.body(13, .semibold)).foregroundStyle(ms == 0 ? TF.muted : TF.ok)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
    }
}
