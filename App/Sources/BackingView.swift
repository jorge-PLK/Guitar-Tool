import AppKit
import AudioKit
import Store
import StudyKit
import SwiftUI

/// Notas en español para las tonalidades («La menor»); los acordes llevan letra («Am»).
enum SpanishNotes {
    static let names = ["Do", "Do#", "Re", "Re#", "Mi", "Fa", "Fa#", "Sol", "Sol#", "La", "La#", "Si"]
}

/// Pantalla Backing track (boceto `docs/design/Backing.dc.html`, recortado según mini-spec Fase 2 §2).
struct BackingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.backingTarget == nil {
                chooser
            } else if let session = model.study, let ctl = model.backing {
                BackingContent(session: session, ctl: ctl)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: model.backingTarget) {
            if let id = model.backingTarget { await model.openStudy(id) }
        }
        .onDisappear { Task { if model.section != .tab { await model.closeStudy() } } }
    }

    /// Sin tema elegido: lista de los ya separados.
    private var chooser: some View {
        let ready = model.entries.filter { $0.separationState == SeparationStatus.done.rawValue }
        return VStack(alignment: .leading, spacing: 16) {
            Text("Backing track").font(TF.display(30))
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

struct BackingContent: View {
    let session: StudySession
    let ctl: BackingController
    @Environment(AppModel.self) private var model
    /// Rejilla de acordes expandida, recordada por vista (por tema).
    @SceneStorage private var chordsExpanded: Bool
    @State private var chordsEdit = false

    init(session: StudySession, ctl: BackingController) {
        self.session = session
        self.ctl = ctl
        _chordsExpanded = SceneStorage(wrappedValue: false, "backing.chordsExpanded.\(session.projectID)")
    }

    /// Posición y niveles muestreados 20 veces por segundo (el reproductor no los publica como observables).
    @State private var time = 0.0
    @State private var meters: [String: ChannelMeter] = [:]
    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    /// Adaptación (paridad con `WinApp/Web/screens/backing.css`): la pantalla ocupa exactamente el alto disponible; el
    /// mezclador encoge (faders más cortos) hasta su mínimo y solo por debajo hace scroll el contenido.
    static let verticalPadding: CGFloat = 20
    /// Por debajo de este alto de pantalla se usa el mínimo bajo del mezclador (`@media (max-height: 780px)`).
    static let lowHeight: CGFloat = 780

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                FillLastLayout(available: geo.size.height - 2 * Self.verticalPadding, spacing: 14) {
                    header
                    if session.project.separation.state != .done || (session.audibleStems.isEmpty && session.emptyStems.isEmpty) {
                        notSeparated
                    } else {
                        banner
                        BackingTimelineCard(session: session, ctl: ctl, time: time,
                                            expanded: $chordsExpanded, editMode: $chordsEdit)
                        BackingMixer(session: session, ctl: ctl, meters: meters, compact: chordsExpanded,
                                     low: geo.size.height < Self.lowHeight)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 36).padding(.vertical, Self.verticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onReceive(tick) { _ in
            let t = ctl.player.currentTime
            if t != time { time = t }
            if ctl.isPlaying || meters.values.contains(where: { $0.rmsDB > -119 }) { meters = ctl.player.meters }
        }
        #if DEBUG
        .onAppear {
            if model.options.chordsExpanded { chordsExpanded = true }
            else if model.options.selectSection != nil { chordsExpanded = false }
            if model.options.chordsEdit { chordsEdit = true }
        }
        #endif
        .onChange(of: session.metronomeBeats) { ctl.refreshMetronome() }
        .onChange(of: session.audibleStems) { ctl.loadTracks() }
        .onChange(of: session.guitarTracks.map(\.role)) { ctl.loadTracks() }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                let song = session.project.song
                Text([song.artist, song.title].compactMap { $0 }.joined(separator: " · "))
                    .font(TF.body(13)).foregroundStyle(TF.muted)
                Text("Backing track").font(TF.display(26))
            }
            Spacer()
            HStack(spacing: 10) {
            if ctl.hasGuitar {
                Button { ctl.toggleWithoutGuitars() } label: {
                    Text("Sin guitarras")
                        .font(TF.body(13, ctl.guitarsOff ? .semibold : .medium))
                        .foregroundStyle(ctl.guitarsOff ? TF.accent : TF.text)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(ctl.guitarsOff ? TF.accentBg : TF.field, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ctl.guitarsOff ? TF.accent : TF.fieldLine))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(ctl.guitarsOff ? .isSelected : [])
            }
            Button { model.section = .tab } label: {
                Label("Tablatura", systemImage: "music.quarternote.3")
            }
            .buttonStyle(SecondaryButton(height: 34))
            .help("Abrir la tablatura de este tema")
            }
        }
    }

    private var notSeparated: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Este tema aún no está separado").font(TF.display(18))
                Text("Backing track necesita los stems. Sepáralo desde la biblioteca y vuelve.").foregroundStyle(TF.muted)
                Button("Ir a la biblioteca") { model.section = .library }.buttonStyle(SecondaryButton())
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var banner: some View {
        if let e = ctl.loadError {
            bannerBox { Text(e).foregroundStyle(TF.danger) }
        }
        switch session.analysisState {
        case .ready: EmptyView()
        case .analyzing:
            bannerBox {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Analizando acordes y pulso… Puedes reproducir mientras tanto.").foregroundStyle(TF.text2)
                }
            }
        case .missing:
            bannerBox {
                HStack {
                    Text("Sin análisis de acordes ni pulso todavía.").foregroundStyle(TF.text2)
                    Spacer()
                    Button("Analizar") { model.retryAnalysis() }.buttonStyle(SecondaryButton(height: 34))
                }
            }
        case .failed(let msg):
            bannerBox {
                HStack {
                    Text("No se pudo analizar: \(msg)").foregroundStyle(TF.danger).lineLimit(2)
                    Spacer()
                    Button("Reintentar") { model.retryAnalysis() }.buttonStyle(SecondaryButton(height: 34))
                }
            }
        }
    }

    private func bannerBox<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c().font(TF.body(13)).padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(TF.fieldLine))
    }
}

/// Apila sus hijos con `spacing`; el último (el mezclador) recibe el alto que sobra hasta `available`, entre su mínimo
/// (alto propuesto 0) y su ideal (alto propuesto nil). Si ni así cabe, el total supera `available` y lo absorbe el scroll.
struct FillLastLayout: Layout {
    var available: CGFloat
    var spacing: CGFloat

    private func heights(_ subviews: Subviews, width: CGFloat) -> (others: [CGFloat], last: CGFloat) {
        guard let last = subviews.last else { return ([], 0) }
        let others = subviews.dropLast().map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let used = others.filter { $0 > 0.5 }.reduce(0, +) + spacing * CGFloat(others.filter { $0 > 0.5 }.count)
        let minH = last.sizeThatFits(ProposedViewSize(width: width, height: 0)).height
        let idealH = last.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return (others, min(max(available - used, minH), max(minH, idealH)))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 800
        let (others, lastH) = heights(subviews, width: w)
        let visible = others.filter { $0 > 0.5 }
        return CGSize(width: w, height: visible.reduce(0, +) + spacing * CGFloat(visible.count) + lastH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (others, lastH) = heights(subviews, width: bounds.width)
        var y = bounds.minY
        for (i, s) in subviews.dropLast().enumerated() {
            s.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: others[i]))
            if others[i] > 0.5 { y += others[i] + spacing }
        }
        subviews.last?.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: lastH))
    }
}
