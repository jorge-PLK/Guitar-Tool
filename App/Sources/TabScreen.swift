import AppKit
import AudioKit
import Store
import SwiftUI
import TabKit

/// Pantalla Tablatura (boceto `docs/design/Tab.dc.html`, sin el panel «Entrada» ni «Grabar toma»: son de la Fase 8a).
struct TabScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.backingTarget == nil {
                chooser
            } else if let session = model.study, let ctl = model.backing {
                TabContent(session: session, ctl: ctl).id(ObjectIdentifier(ctl))
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: model.backingTarget) {
            if let id = model.backingTarget { await model.openStudy(id) }
        }
        .onDisappear { Task { if model.section != .backing { await model.closeStudy() } } }
    }

    private var chooser: some View {
        let ready = model.entries.filter { $0.separationState == SeparationStatus.done.rawValue }
        return VStack(alignment: .leading, spacing: 16) {
            Text("Tablatura").font(TF.display(30))
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

struct TabContent: View {
    let session: StudySession
    let ctl: BackingController
    @Environment(AppModel.self) private var model
    @State private var tab: TabController?
    @State private var time = 0.0
    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let tab {
                if !tab.notices.isEmpty { noticeBox(tab) }
                tablature(tab)
                if tab.editMode, tab.phase == .ready { editBar(tab) }
                transport(tab)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 36).padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            guard tab == nil else { return }
            let t = TabController(session: session, ctl: ctl, modelStore: model.modelStore)
            tab = t
            t.installKeyMonitor()
            t.start()
            #if DEBUG
            if let rate = model.options.rate { ctl.setRate(rate) }
            await t.waitUntilSettled()
            t.applyLaunchOptions(trackIndex: model.options.tabTrack, edit: model.options.tabEdit,
                                 listen: model.options.tabListen)
            if let url = model.options.tabExport { await t.exportGuitarPro(to: url) }
            #endif
        }
        .onChange(of: session.beats) { tab?.start() }
        .onReceive(tick) { _ in
            let t = ctl.player.currentTime
            if t != time { time = t }
            tab?.updateCursor(time: t, follow: true)   // solo desplaza si el cursor sale de la vista (seek o reproducción)
        }
        .onDisappear { tab?.close() }
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                let song = session.project.song
                Text([song.artist, song.title].compactMap { $0 }.joined(separator: " · "))
                    .font(TF.body(13)).foregroundStyle(TF.muted)
                Text("Tablatura").font(TF.display(26))
            }
            Spacer()
            if let tab {
                Button { tab.editMode.toggle() } label: {
                    Text("Editar notas")
                        .font(TF.body(13, tab.editMode ? .semibold : .medium))
                        .foregroundStyle(tab.editMode ? TF.accent : TF.text)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(tab.editMode ? TF.accentBg : TF.field, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tab.editMode ? TF.accent : TF.fieldLine))
                }
                .buttonStyle(.plain)
                .disabled(tab.phase != .ready)
                .accessibilityAddTraits(tab.editMode ? .isSelected : [])
                Button("Exportar a Guitar Pro") { tab.exportGuitarPro() }
                    .buttonStyle(SecondaryButton(height: 34))
                    .disabled(tab.phase != .ready || tab.score?.tracks.isEmpty != false)
            }
        }
    }

    private func noticeBox(_ tab: TabController) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(tab.notices.enumerated()), id: \.offset) { _, n in Text(n).foregroundStyle(TF.text2) }
            }
            Spacer()
            Button { tab.dismissNotices() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Cerrar aviso")
        }
        .font(TF.body(13)).padding(.horizontal, 16).padding(.vertical, 12)
        .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(TF.fieldLine))
    }

    // MARK: Pistas y tablatura

    private func tablature(_ tab: TabController) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                trackTabs(tab)
                if let track = tab.selectedTrack { trackControls(tab, track) }
                ZStack {
                    AlphaTabView(host: tab.host)
                        .opacity(tab.phase == .ready || (!tab.entries.isEmpty && tab.phase == .working) ? 1 : 0)
                    overlay(tab)
                }
                .frame(maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
                .background(TF.bg.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                footer(tab)
            }
            .padding(18)
        }
        .frame(maxHeight: .infinity)
    }

    private func trackTabs(_ tab: TabController) -> some View {
        let pending = tab.queued.filter { id in !tab.entries.contains { $0.id == id } }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tab.entries) { e in
                    let active = e.id == tab.selectedTrackID
                    Button { tab.selectedTrackID = e.id } label: {
                        HStack(spacing: 6) {
                            Image(systemName: icon(e.kind)).font(.system(size: 12))
                            Text(e.name)
                            if tab.isListening(e.id) { Image(systemName: "speaker.wave.2.fill").font(.system(size: 11)) }
                        }
                        .font(TF.body(13, active ? .semibold : .medium))
                        .foregroundStyle(active ? TF.accent : TF.text2)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(active ? TF.accentBg : TF.field, in: Capsule())
                        .overlay(Capsule().stroke(active ? TF.accent : TF.fieldLine))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
                ForEach(pending, id: \.self) { id in
                    Text(tab.source(of: id)?.name ?? id)
                        .font(TF.body(13)).foregroundStyle(TF.muted)
                        .padding(.horizontal, 14).frame(height: 34)
                        .overlay(Capsule().stroke(TF.fieldLine, style: StrokeStyle(lineWidth: 1, dash: [3])))
                }
            }
        }
    }

    private func icon(_ k: TabTrackKind) -> String {
        switch k {
        case .guitar: "guitars"
        case .bass: "waveform"
        case .drums: "circle.grid.2x2"
        }
    }

    private func trackControls(_ tab: TabController, _ track: TabTrack) -> some View {
        HStack(spacing: 16) {
            if track.kind != .drums, let tuning = track.tuning {
                HStack(spacing: 8) {
                    Text("Afinación").foregroundStyle(TF.muted)
                    Picker("Afinación", selection: Binding(get: { tuning.preset },
                                                           set: { tab.setTuning($0, trackID: track.id) })) {
                        ForEach(TuningPreset.allCases, id: \.self) { Text(TabController.tuningName($0)).tag($0) }
                    }
                    .labelsHidden().frame(width: 170)
                }
            }
            Toggle("Oír transcripción", isOn: Binding(get: { tab.isListening(track.id) },
                                                      set: { tab.setListening($0, trackID: track.id) }))
                .toggleStyle(.checkbox)
            if tab.synth[track.id] == .rendering {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Sintetizando…").foregroundStyle(TF.muted) }
            }
            Spacer()
            if let summary = tab.headerSummary { Text(summary).foregroundStyle(TF.muted) }
        }
        .font(TF.body(13)).foregroundStyle(TF.text2)
    }

    @ViewBuilder private func overlay(_ tab: TabController) -> some View {
        switch tab.phase {
        case .ready:
            if let e = tab.webError {
                Text("alphaTab: \(e)").foregroundStyle(TF.danger).font(TF.body(13)).padding()
            }
        case .working:
            VStack(alignment: .leading, spacing: 12) {
                Text("Transcribiendo…").font(TF.display(18))
                Text("La primera vez tarda un poco. Lo hecho se guarda pista a pista.").foregroundStyle(TF.muted)
                ForEach(tab.queued, id: \.self) { id in
                    HStack(spacing: 12) {
                        Text(tab.source(of: id)?.name ?? id).frame(width: 150, alignment: .leading)
                        AccentBar(value: tab.progress[id]).frame(width: 220)
                    }
                    .font(TF.body(13))
                }
            }
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(TF.card.opacity(tab.entries.isEmpty ? 1 : 0))
        case .waitingAnalysis:
            message("Esperando el análisis del tema",
                    "La tablatura necesita los compases y pulsos del análisis. Puedes lanzarlo desde Backing track.",
                    action: ("Analizar", { model.retryAnalysis() }))
        case .empty:
            message("No hay pistas que transcribir", "Este tema no tiene stems de guitarra, bajo o batería con audio.", action: nil)
        case .failed(let m):
            message("No se pudo transcribir", m, action: nil)
        }
    }

    private func message(_ title: String, _ body: String, action: (String, () -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(TF.display(18))
            Text(body).foregroundStyle(TF.muted).fixedSize(horizontal: false, vertical: true)
            if let action { Button(action.0, action: action.1).buttonStyle(SecondaryButton(height: 34)) }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TF.card)
    }

    private func footer(_ tab: TabController) -> some View {
        HStack {
            Text(tab.flash ?? tab.selectionSummary ?? "Transcripción automática · revisa y corrige si hace falta")
                .foregroundStyle(tab.flash == nil ? TF.muted : TF.accent)
                .lineLimit(1)
            Spacer()
        }
        .font(TF.body(13)).frame(height: 18)
    }

    // MARK: Edición

    private func editBar(_ tab: TabController) -> some View {
        HStack(spacing: 10) {
            Button { tab.undo() } label: { Label("Deshacer", systemImage: "arrow.uturn.backward") }
                .disabled(!tab.canUndo)
            Button { tab.redo() } label: { Label("Rehacer", systemImage: "arrow.uturn.forward") }
                .disabled(!tab.canRedo)
            if tab.selectedTrack?.kind == .drums {
                ForEach(DrumPiece.allCases, id: \.self) { p in
                    Button(TabController.pieceName(p).capitalized) { tab.toggleHit(p) }.disabled(tab.selection == nil)
                }
                Text("B bombo · C caja · H charles · T tom · P platos").foregroundStyle(TF.muted)
            } else {
                Button { tab.addNoteAtCursor() } label: { Label("Añadir nota", systemImage: "plus") }
                Button { tab.changeDuration(by: -1) } label: { Image(systemName: "minus") }
                    .disabled(tab.selectedNote == nil).accessibilityLabel("Acortar nota")
                Button { tab.changeDuration(by: 1) } label: { Image(systemName: "plus") }
                    .disabled(tab.selectedNote == nil).accessibilityLabel("Alargar nota")
                Button { tab.deleteSelection() } label: { Label("Borrar", systemImage: "trash") }
                    .disabled(tab.selectedNote == nil)
                Text("Dígitos: traste · ↑ ↓: cuerda · ← →: mover · +/−: duración · ⌘Z deshacer")
                    .foregroundStyle(TF.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(SecondaryButton(height: 32))
        .font(TF.body(12))
    }

    // MARK: Transporte

    private func transport(_ tab: TabController) -> some View {
        let settings = ctl.settings
        return HStack(spacing: 14) {
            Button { ctl.seek(to: 0) } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 15)).foregroundStyle(TF.text)
                    .frame(width: 44, height: 44).background(TF.field, in: Circle())
                    .overlay(Circle().stroke(TF.fieldLine))
            }
            .buttonStyle(.plain).accessibilityLabel("Volver al inicio")

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

            loopMenu(tab)
            Spacer(minLength: 0)
        }
    }

    private func loopMenu(_ tab: TabController) -> some View {
        Menu {
            Button("Sin bucle") { ctl.setLoop(nil) }
            if let r = tab.selectedBarRange {
                Button("Compás \(r.bar + 1)") { ctl.setLoop(r.range, name: "compás \(r.bar + 1)") }
            }
            ForEach(session.sections, id: \.id) { s in
                Button(s.name) { ctl.setLoop(s.start...s.end, name: s.name) }
            }
        } label: {
            if let loop = ctl.loop {
                Text("Bucle: \(ctl.loopName ?? "libre") · \(Fmt.clock(loop.lowerBound))–\(Fmt.clock(loop.upperBound))")
            } else {
                Text("Bucle")
            }
        }
        .menuStyle(.borderlessButton).fixedSize()
        .font(TF.body(13, .semibold)).foregroundStyle(ctl.loop == nil ? TF.text2 : TF.accent)
    }
}
