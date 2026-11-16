import AppKit
import AVFoundation
import Store
import SwiftUI

/// Pantalla Montaje (boceto `docs/design/Edit.dc.html`, con los cambios de la mini-spec Fase 7, «Interfaz»).
struct MontageView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.backingTarget == nil {
                chooser
            } else if let session = model.study {
                MontageContent(session: session).id(session.projectID)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: model.backingTarget) {
            if let id = model.backingTarget { await model.openStudy(id) }
        }
        // Grabar ↔ Montaje comparten el estudio abierto: el que llega lo reabre.
        .onDisappear { Task { if model.section != .record { await model.closeStudy() } } }
    }

    private var chooser: some View {
        let withTakes = model.entries.filter { $0.takeCount > 0 }
        return VStack(alignment: .leading, spacing: 16) {
            Text("Montaje").font(TF.display(30))
            if withTakes.isEmpty {
                Text("Aún no hay temas con tomas grabadas. Graba alguna parte con vídeo en Grabar.").foregroundStyle(TF.muted)
                Button("Ir a Grabar") { model.section = .record }.buttonStyle(SecondaryButton())
            } else {
                Text("Elige un tema").foregroundStyle(TF.muted)
                ForEach(withTakes, id: \.id) { e in
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

struct MontageContent: View {
    let session: StudySession
    @Environment(AppModel.self) private var model
    @State private var ctl: MontageController?

    var body: some View {
        Group {
            if let ctl {
                MontageBody(ctl: ctl)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard ctl == nil else { return }
            #if DEBUG
            if let screen = model.options.screen, screen.hasPrefix("montage") { await MontageDemo.seed(session: session, model: model) }
            #endif
            let c = MontageController(session: session, model: model)
            #if DEBUG
            MontageDemo.apply(model.options, to: c)
            #endif
            ctl = c
            c.open()
            #if DEBUG
            if model.options.montageExport { await MontageDemo.runExportCheck(c, options: model.options) }
            #endif
        }
        .onDisappear {
            ctl?.close()
            ctl = nil
        }
    }
}

private struct MontageBody: View {
    let ctl: MontageController
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var ctl = ctl
        VStack(alignment: .leading, spacing: 14) {
            header
            notices
            if ctl.videoLanes.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 16) {
                    LayoutColumn(ctl: ctl).frame(width: 270)
                    PreviewColumn(ctl: ctl).frame(maxWidth: .infinity)
                    SettingsColumn(ctl: ctl).frame(width: 300)
                }
                .frame(maxHeight: .infinity)
                MontageTimelineView(ctl: ctl)
            }
        }
        .padding(.horizontal, 36).padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: Binding(get: { ctl.framingSheetTakeID != nil }, set: { if !$0 { ctl.framingSheetTakeID = nil } })) {
            if let id = ctl.framingSheetTakeID { MontageFramingSheet(ctl: ctl, takeID: id) }
        }
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                let n = ctl.lanes.count
                Text([ctl.song.artist, ctl.song.title, "\(n) \(n == 1 ? "toma" : "tomas")"].compactMap { $0 }.joined(separator: " · "))
                    .font(TF.body(13)).foregroundStyle(TF.muted)
                Text("Montaje").font(TF.display(26))
            }
            Spacer()
            if ctl.isExporting {
                Button("Cancelar exportación") { ctl.cancelExport() }.buttonStyle(SecondaryButton())
            } else {
                Button("Exportar vídeo") { ctl.startExport() }.buttonStyle(PrimaryButton()).disabled(!ctl.canExport)
                    .help(ctl.isAnalyzing ? "Espera a que termine el análisis del encuadre" : "")
            }
        }
    }

    // MARK: Avisos y estado de la exportación

    @ViewBuilder private var notices: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let d = ctl.draft {
                if !d.audioOnlyParts.isEmpty {
                    line("Sin vídeo (solo audio, sin recuadro): \(d.audioOnlyParts.joined(separator: ", ")).", TF.accent)
                }
            }
            if let e = ctl.previewError { line(e, TF.danger) }
            exportStatus
        }
    }

    private func line(_ text: String, _ color: Color) -> some View {
        Text(text).font(TF.body(12)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var exportStatus: some View {
        switch ctl.exportPhase {
        case .idle:
            EmptyView()
        case .running(let stage, let p):
            HStack(spacing: 12) {
                Text("\(stage)…").font(TF.body(13, .medium))
                AccentBar(value: p).frame(maxWidth: 320)
                Text(Fmt.percent(p)).font(TF.body(13)).foregroundStyle(TF.muted).monospacedDigit()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
        case .done(let r):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(TF.ok)
                    Text("Vídeo exportado: \(r.url.path)").font(TF.body(13, .medium)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Mostrar en Finder") { ctl.revealInFinder(r.url) }.buttonStyle(SecondaryButton(height: 32))
                    Button("Cerrar") { ctl.dismissExportResult() }.buttonStyle(SecondaryButton(height: 32))
                }
                if let l = r.finalLUFS {
                    line("Sonoridad final: \(Self.number(l)) LUFS · pico real \(Self.number(r.finalTruePeakDB)) dBTP"
                         + (r.normalized ? "" : " (sin normalizar)"), TF.muted)
                }
                if r.limitedByPeak {
                    line("Se limitó la ganancia para no pasar de −1 dBTP: la mezcla queda por debajo de −14 LUFS.", TF.accent)
                }
                if let d = r.tracksDirectory { line("WAV por pista en \(d.path)", TF.muted) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(TF.okBg, in: RoundedRectangle(cornerRadius: 10))
        case .failed(let m):
            HStack {
                line(m, TF.danger)
                Spacer()
                Button("Cerrar") { ctl.dismissExportResult() }.buttonStyle(SecondaryButton(height: 32))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(TF.dangerBg, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private static func number(_ x: Double) -> String { x.formatted(.number.precision(.fractionLength(1))) }

    // MARK: Estado vacío

    private var emptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Aún no hay tomas con vídeo").font(TF.display(18))
                Text("El montaje usa la mejor toma de cada parte. Graba alguna parte con la cámara y vuelve.")
                    .foregroundStyle(TF.muted).fixedSize(horizontal: false, vertical: true)
                Button("Ir a Grabar") { model.section = .record }.buttonStyle(SecondaryButton())
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Columna Layout

private struct LayoutColumn: View {
    let ctl: MontageController

    private static let layouts: [(kind: Store.MontageLayoutKind, name: String, desc: String)] = [
        (.side, "Lado a lado", "Landscape · 1920 × 1080"),
        (.grid, "Rejilla", "Landscape · 3 o 4 tomas"),
        (.stack, "Apilado", "Portrait · 1080 × 1920"),
        (.single, "Plano único", "Portrait · rítmica y solista"),
    ]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Layout").font(TF.display(18))
                ForEach(Self.layouts, id: \.kind) { l in
                    let on = ctl.state.layout == l.kind
                    Button { ctl.setLayout(l.kind) } label: {
                        HStack(spacing: 10) {
                            LayoutThumb(kind: l.kind)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.name).font(TF.body(14, .semibold)).lineLimit(1)
                                Text(l.desc).font(TF.body(11)).foregroundStyle(TF.muted).lineLimit(1).fixedSize()
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 8).frame(minHeight: 64)
                        .background(on ? TF.accentBg : TF.field, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? TF.accent : TF.fieldLine))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                if ctl.state.layout == .single { rhythmPicker }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Rítmica del plano único (por defecto, la primera con vídeo).
    private var rhythmPicker: some View {
        let options = ctl.singleRhythmCandidates
        return VStack(alignment: .leading, spacing: 4) {
            Text("Rítmica del plano único").font(TF.body(12)).foregroundStyle(TF.muted)
            Picker("Rítmica del plano único", selection: Binding(get: { ctl.state.singleRhythmPartID }, set: { ctl.setSingleRhythm($0) })) {
                Text("Automática (\(options.first?.partName ?? "—"))").tag(UUID?.none)
                ForEach(options) { l in Text(l.partName).tag(UUID?.some(l.id)) }
            }
            .labelsHidden().pickerStyle(.menu)
        }
    }
}

private struct LayoutThumb: View {
    let kind: Store.MontageLayoutKind
    private let tile = RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x5A636C))

    var body: some View {
        Group {
            switch kind {
            case .side:
                HStack(spacing: 3) { tile; tile }.frame(width: 64, height: 36)
            case .grid:
                VStack(spacing: 3) { HStack(spacing: 3) { tile; tile }; HStack(spacing: 3) { tile; tile } }.frame(width: 64, height: 36)
            case .stack:
                VStack(spacing: 3) { tile; tile }.frame(width: 30, height: 52)
            case .single:
                tile.frame(width: 30, height: 52)
            }
        }
        .padding(4).background(TF.bg, in: RoundedRectangle(cornerRadius: 6))
        .frame(width: 70)
    }
}

// MARK: - Vista previa

private struct PreviewColumn: View {
    let ctl: MontageController

    var body: some View {
        Card {
            VStack(spacing: 10) {
                HStack {
                    Text("Vista previa · \(ctl.canvasLabel)")
                    Spacer()
                    Text([Fmt.duration(ctl.songTime), ctl.sectionName(at: ctl.songTime)].compactMap { $0 }.joined(separator: " · "))
                }
                .font(TF.body(13)).foregroundStyle(TF.muted)
                player.frame(maxWidth: .infinity, maxHeight: .infinity)
                controls
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var player: some View {
        MontagePlayerView(player: ctl.player)
            .overlay { if !ctl.previewReady && ctl.previewError == nil { ProgressView().controlSize(.small) } }
            .background(Color(hex: 0x0B0C0E))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(TF.fieldLine))
            .aspectRatio(ctl.isPortrait ? 9.0 / 16.0 : 16.0 / 9.0, contentMode: .fit)
    }

    private var controls: some View {
        let s = ctl.span
        return HStack(spacing: 12) {
            Button { ctl.togglePlay() } label: {
                Image(systemName: ctl.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 16))
                    .foregroundStyle(TF.accentInk).frame(width: 44, height: 44).background(TF.accent, in: Circle())
            }
            .buttonStyle(.plain).disabled(!ctl.previewReady).opacity(ctl.previewReady ? 1 : 0.4)
            .accessibilityLabel(ctl.isPlaying ? "Pausar la vista previa" : "Reproducir la vista previa")
            if s.duration > 0 {
                Slider(value: Binding(get: { min(max(ctl.songTime, s.start), s.end) }, set: { ctl.seek(to: $0) }), in: s.start...s.end)
                    .tint(TF.accent).disabled(!ctl.previewReady)
            } else {
                Spacer()
            }
            (Text(Fmt.duration(ctl.songTime)) + Text(" / \(Fmt.duration(s.end))").foregroundStyle(TF.muted))
                .font(TF.body(13)).monospacedDigit()
        }
    }
}

/// Capa de `AVPlayer` (la vista previa del montaje).
private struct MontagePlayerView: NSViewRepresentable {
    let player: AVPlayer

    final class Host: NSView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }
        override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
        var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
    }

    func makeNSView(context: Context) -> Host {
        let v = Host()
        v.playerLayer?.player = player
        v.playerLayer?.videoGravity = .resizeAspect
        return v
    }

    func updateNSView(_ v: Host, context: Context) {
        if v.playerLayer?.player !== player { v.playerLayer?.player = player }
    }
}

// MARK: - Transiciones y exportación

private struct SettingsColumn: View {
    let ctl: MontageController

    /// Valores informativos de la mini-spec Fase 7, «Transiciones» (no se editan).
    private static let transitions: [(String, String)] = [
        ("Recolocación", "Muelle · 0,5 s"),
        ("Entrada", "Escala 92→100 % + nitidez"),
        ("Anticipación al solo", MontageController.anticipationLabel),
        ("Fundido de audio", "80 ms"),
        ("Fundido de entrada y salida", "1 compás"),
        ("Esquinas", "Redondeadas + sombra"),
    ]
    private static let fpsChoices: [Double] = [24, 25, 30, 50, 60]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Transiciones").font(TF.display(18))
                ForEach(Self.transitions, id: \.0) { k, v in
                    HStack {
                        Text(k).foregroundStyle(TF.text2)
                        Spacer()
                        Text(v).font(TF.body(13, .semibold))
                    }
                    .font(TF.body(13)).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
                }
                Text("Exportación").font(TF.display(18)).padding(.top, 6)
                pickerRow("Formato", selection: Binding(get: { ctl.state.export.codec }, set: { c in ctl.updateExport { $0.codec = c } })) {
                    Text("HEVC").tag(VideoCodec.hevc)
                    Text("H.264").tag(VideoCodec.h264)
                }
                pickerRow("Resolución", selection: Binding(get: { ctl.state.export.resolution }, set: { r in ctl.updateExport { $0.resolution = r } })) {
                    ForEach(CameraChoices.presets, id: \.self) { Text(CameraChoices.label($0)).tag($0) }
                }
                pickerRow("Fotogramas", selection: Binding(get: { ctl.state.export.fps }, set: { f in ctl.updateExport { $0.fps = f } })) {
                    ForEach(fpsOptions, id: \.self) { Text(CameraChoices.label(fps: $0)).tag($0) }
                }
                toggle("Volumen normalizado a -14 LUFS", isOn: Binding(get: { ctl.state.export.normalize }, set: { v in ctl.updateExport { $0.normalize = v } }))
                toggle("Rótulo con título y artista", isOn: Binding(get: { ctl.state.caption }, set: { ctl.setCaption($0) }))
                toggle("Cortar huecos sin tomas", isOn: Binding(get: { ctl.state.cutGaps }, set: { ctl.setCutGaps($0) }))
                toggle("WAV de cada pista", isOn: Binding(get: { ctl.state.export.trackWAVs }, set: { v in ctl.updateExport { $0.trackWAVs = v } }))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var fpsOptions: [Double] {
        Array(Set(Self.fpsChoices + [ctl.state.export.fps])).sorted()
    }

    private func pickerRow<V: Hashable, C: View>(_ title: String, selection: Binding<V>, @ViewBuilder content: () -> C) -> some View {
        HStack {
            Text(title).foregroundStyle(TF.text2)
            Spacer()
            Picker(title, selection: selection, content: content).labelsHidden().pickerStyle(.menu).fixedSize()
        }
        .font(TF.body(13))
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(title).font(TF.body(13)).foregroundStyle(TF.text2) }
            .toggleStyle(.checkbox).tint(TF.accent)
    }
}

// MARK: - Línea de tiempo

private struct MontageTimelineView: View {
    let ctl: MontageController

    /// Margen del eje a cada lado del tramo del vídeo (fracción del tramo).
    private static let axisMarginFraction = 0.10
    private static let labelWidth: CGFloat = 200
    private static let rowSpacing: CGFloat = 6
    private static let laneHeight: CGFloat = 30
    private static let sectionHeight: CGFloat = 24
    private static let bandHeight: CGFloat = 8
    private static let laneColors: [Color] = [0x5BC0EB, 0xF2A33A, 0x6FD99E, 0xC97F9E, 0x5DB5B5].map { Color(hex: $0) }
    private static let soloColor = Color(hex: 0xB79CFF)

    private func color(_ lane: MontageLane, _ index: Int) -> Color {
        lane.isSolo ? Self.soloColor : Self.laneColors[index % Self.laneColors.count]
    }

    var body: some View {
        let lanes = ctl.lanes
        let nonSolo = lanes.filter { !$0.isSolo }
        // Eje: el tramo del vídeo con un margen a cada lado (10 % del tramo, mínimo un compás), sin salirse del tema.
        let songEnd = max(ctl.song.duration, ctl.span.end, 1)
        let margin = max(ctl.span.duration * Self.axisMarginFraction, ctl.draft?.plan.barDuration ?? 0)
        let axisStart = max(0, ctl.span.start - margin), axisEnd = min(songEnd, ctl.span.end + margin)
        let duration = max(axisEnd - axisStart, 1)
        let missing = ctl.draft?.missingParts ?? []
        let rows = lanes.count + missing.count
        let height = Self.bandHeight + Self.sectionHeight + CGFloat(rows) * Self.laneHeight + CGFloat(rows + 1) * Self.rowSpacing
        let segments = ctl.draft?.segments ?? []
        // Huecos cortados («Cortar huecos sin tomas»): lo que queda entre tramos.
        let gaps: [(Double, Double)] = zip(segments, segments.dropFirst()).map { ($0.end, $1.start) }
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: Self.rowSpacing) {
                        Text("Tramo del vídeo").font(TF.body(10)).foregroundStyle(TF.muted).frame(height: Self.bandHeight)
                        Color.clear.frame(height: Self.sectionHeight)
                        ForEach(lanes) { lane in laneLabel(lane) }
                        ForEach(missing, id: \.self) { name in
                            HStack {
                                Text(name).font(TF.body(13, .semibold)).foregroundStyle(TF.text2).lineLimit(1)
                                Spacer(minLength: 0)
                                Text("Sin toma").font(TF.body(11)).foregroundStyle(TF.muted)
                            }.frame(height: Self.laneHeight)
                        }
                    }
                    .frame(width: Self.labelWidth, alignment: .leading)
                    GeometryReader { geo in
                        let w = geo.size.width
                        let x: (Double) -> CGFloat = { CGFloat(($0 - axisStart) / duration) * w }
                        ZStack(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                                band(x: x)
                                sectionsRow(x: x, width: w, axis: (axisStart, axisEnd))
                                ForEach(Array(lanes.enumerated()), id: \.element.id) { i, lane in laneRow(lane, color: color(lane, nonSolo.firstIndex(where: { $0.id == lane.id }) ?? i), x: x) }
                                ForEach(missing, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 6).fill(TF.field).frame(height: Self.laneHeight)
                                }
                            }
                            ForEach(Array([(axisStart, ctl.span.start), (ctl.span.end, axisEnd)].enumerated()), id: \.offset) { _, g in
                                Rectangle().fill(TF.bg.opacity(0.6)).frame(width: max(0, x(g.1) - x(g.0)), height: height)
                                    .offset(x: x(g.0)).allowsHitTesting(false)
                            }
                            ForEach(Array(gaps.enumerated()), id: \.offset) { _, g in
                                Rectangle().fill(TF.bg.opacity(0.7)).overlay(Rectangle().strokeBorder(TF.muted.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 3])))
                                    .frame(width: max(2, x(g.1) - x(g.0)), height: height).offset(x: x(g.0)).allowsHitTesting(false)
                            }
                            Rectangle().fill(TF.text).frame(width: 2, height: height).offset(x: x(ctl.songTime) - 1)
                                .allowsHitTesting(false)
                        }
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                            guard w > 0 else { return }
                            ctl.seek(to: axisStart + Double(min(max(g.location.x / w, 0), 1)) * duration)
                        })
                    }
                    .frame(height: height)
                }
                Text("Barra llena = en pantalla; el contorno discontinuo es lo grabado; lo rayado son huecos cortados. La solista solo aparece en el solo y su entrada empieza \(MontageController.anticipationLabel) antes de la primera nota. Clic para mover la vista previa.")
                    .font(TF.body(12)).foregroundStyle(TF.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
        }
    }

    // MARK: Filas

    private func laneLabel(_ lane: MontageLane) -> some View {
        HStack(spacing: 6) {
            Text(lane.partName).font(TF.body(13, .semibold)).foregroundStyle(TF.text2).lineLimit(1)
            Spacer(minLength: 0)
            if lane.presence.isEmpty {
                Text("Sin solos marcados").font(TF.body(11)).foregroundStyle(TF.muted)
            } else if lane.hasVideo {
                if case .analyzing = ctl.framingStatus[lane.takeID] { ProgressView().controlSize(.mini) }
                Button { ctl.framingSheetTakeID = lane.takeID } label: {
                    Text("Encuadre").font(TF.body(12, .medium)).foregroundStyle(TF.text)
                        .padding(.horizontal, 10).frame(height: Self.laneHeight - 4)
                        .background(TF.field, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TF.fieldLine))
                }
                .buttonStyle(.plain).accessibilityLabel("Encuadre de \(lane.partName)")
            } else {
                Text("Solo audio").font(TF.body(11)).foregroundStyle(TF.muted)
            }
        }
        .frame(height: Self.laneHeight)
    }

    /// El tramo del vídeo con los fundidos de un compás marcados en sus extremos.
    private func band(x: @escaping (Double) -> CGFloat) -> some View {
        let s = ctl.span
        let bar = ctl.draft?.plan.barDuration ?? 0
        let fadeIn = ctl.draft?.plan.fadeIn ?? false
        let fadeOut = ctl.draft?.plan.fadeOut ?? false
        return ZStack(alignment: .topLeading) {
            Color.clear
            RoundedRectangle(cornerRadius: 3).fill(TF.accent.opacity(0.35))
                .frame(width: max(2, x(s.end) - x(s.start)), height: Self.bandHeight).offset(x: x(s.start))
            if fadeIn {
                LinearGradient(colors: [TF.bg, TF.accent], startPoint: .leading, endPoint: .trailing)
                    .frame(width: max(2, x(bar)), height: Self.bandHeight).clipShape(RoundedRectangle(cornerRadius: 3)).offset(x: x(s.start))
            }
            if fadeOut {
                LinearGradient(colors: [TF.accent, TF.bg], startPoint: .leading, endPoint: .trailing)
                    .frame(width: max(2, x(bar)), height: Self.bandHeight).clipShape(RoundedRectangle(cornerRadius: 3)).offset(x: x(s.end - bar))
            }
        }
        .frame(height: Self.bandHeight)
    }

    private func sectionsRow(x: @escaping (Double) -> CGFloat, width: CGFloat, axis: (Double, Double)) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(TF.bg.opacity(0.6)).frame(width: width, height: Self.sectionHeight)
            ForEach(ctl.sections.filter { min($0.end, axis.1) > max($0.start, axis.0) }, id: \.id) { s in
                let a = max(s.start, axis.0), b = min(s.end, axis.1)
                Text(s.name).font(TF.body(11, .semibold)).lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 6)
                    .frame(width: max(2, x(b) - x(a) - 2), height: Self.sectionHeight, alignment: .leading)
                    .foregroundStyle(s.isSolo ? TF.accent : TF.text2)
                    .background(s.isSolo ? TF.accentBg : TF.neutralBg, in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: x(a))
            }
        }
        .frame(height: Self.sectionHeight)
    }

    private func laneRow(_ lane: MontageLane, color: Color, x: @escaping (Double) -> CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(TF.field)
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(color.opacity(0.6))
                .frame(width: max(2, x(lane.take.end) - x(lane.take.start)), height: Self.laneHeight).offset(x: x(lane.take.start))
            ForEach(Array(lane.presence.enumerated()), id: \.offset) { _, p in
                RoundedRectangle(cornerRadius: 6).fill(lane.hasVideo ? color : color.opacity(0.35))
                    .frame(width: max(2, x(p.end) - x(p.start)), height: Self.laneHeight).offset(x: x(p.start))
            }
        }
        .frame(height: Self.laneHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lane.partName): \(lane.presence.count) \(lane.presence.count == 1 ? "tramo" : "tramos") en pantalla")
    }
}
