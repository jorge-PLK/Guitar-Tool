import AudioKit
import Store
import SwiftUI

/// Mezclador de Backing: un canal por stem (voz, batería, bajo, guitarra, piano, resto). Los stems vacíos
/// o ausentes no se muestran.
struct BackingMixer: View {
    let session: StudySession
    let ctl: BackingController
    let meters: [String: ChannelMeter]
    /// Con la rejilla de acordes expandida: solo master y M/S por stem, sin faders ni medidores de stems.
    var compact = false
    /// Pantalla baja (< `BackingContent.lowHeight`): mínimo del mezclador más justo (236 en vez de 270 en Windows).
    var low = false

    /// Alto mínimo del cuerpo de canales: Windows fija la tarjeta en 270 px (236 en pantalla baja) menos cabecera y márgenes.
    private static let bodyMin: CGFloat = 210
    private static let bodyMinLow: CGFloat = 176
    /// Alto a tamaño completo: canal de 276 + 10 de margen para la barra de scroll horizontal.
    private static let bodyIdeal: CGFloat = MixerChannel.height + 10

    private static let order: [(StemKind, String)] = [
        (.vocals, "Voz"), (.drums, "Batería"), (.bass, "Bajo"), (.guitar, "Guitarra"), (.piano, "Piano"), (.other, "Resto"),
    ]

    @Environment(AppModel.self) private var model

    private var anySolo: Bool { session.study.mixer.contains { $0.solo } }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text("Mezclador").font(TF.display(18))
                    Spacer()
                    if ctl.hasGuitar || session.usesSeparatedGuitars { GuitarStereoToggle(session: session) }
                    Text("Salida: \(ctl.player.outputDeviceName.isEmpty ? "—" : ctl.player.outputDeviceName)")
                        .font(TF.body(12)).foregroundStyle(TF.muted)
                }
                if compact {
                    compactBody
                } else {
                    // Master fijo a la izquierda; los canales con scroll horizontal propio si no caben. El canal se acorta
                    // con el alto disponible (mínimo `bodyMin`).
                    GeometryReader { g in
                        let ch = min(max(g.size.height - 10, MixerChannel.minHeight), MixerChannel.height)
                        HStack(alignment: .top, spacing: 10) {
                            MasterChannel(ctl: ctl)
                            Divider().frame(height: max(ch - 76, 40)).padding(.horizontal, 6)
                            ScrollView(.horizontal, showsIndicators: true) {
                                HStack(alignment: .top, spacing: 10) {
                                    ForEach(Self.order, id: \.0) { kind, name in
                                        if kind == .guitar && session.usesSeparatedGuitars {
                                            ForEach(session.guitarTracks, id: \.role) { g in guitarChannel(g) }
                                        } else if session.audibleStems.contains(kind), !session.emptyStems.contains(kind) {
                                            stemChannel(kind, name)
                                        }
                                    }
                                }
                                .padding(.bottom, 10)
                            }
                        }
                        .environment(\.mixerChannelHeight, ch)
                    }
                    .frame(minHeight: low ? Self.bodyMinLow : Self.bodyMin, idealHeight: Self.bodyIdeal, maxHeight: Self.bodyIdeal)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
    }

    private func stemChannel(_ kind: StemKind, _ name: String) -> some View {
        MixerChannel(name: name, mix: session.mix(for: kind), anySolo: anySolo, meter: meters[kind.rawValue],
                     setGain: { ctl.setGain(kind, $0) }, toggleMute: { ctl.toggleMute(kind) }, toggleSolo: { ctl.toggleSolo(kind) })
    }

    private func guitarChannel(_ g: Guitar) -> some View {
        MixerChannel(name: session.guitarName(g.role), mix: session.mix(forGuitar: g.role), anySolo: anySolo,
                     meter: meters[g.role.trackID],
                     rename: { session.renameGuitar(g.role, to: $0) },
                     setGain: { ctl.setGain(guitar: g.role, $0) }, toggleMute: { ctl.toggleMute(guitar: g.role) },
                     toggleSolo: { ctl.toggleSolo(guitar: g.role) })
    }

    // MARK: Compacto

    private var compactBody: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 10) {
                Text("Master").font(TF.body(13, .semibold))
                Slider(value: Binding(get: { ctl.masterGainDB }, set: { ctl.setMaster(abs($0) < 1.5 ? 0 : $0) }),
                       in: BackingController.faderRange).frame(width: 150).tint(TF.accent)
                Text(Fmt.db(ctl.masterGainDB)).font(TF.body(12)).foregroundStyle(TF.text2)
                    .monospacedDigit().frame(width: 62, alignment: .leading)
            }
            Divider().frame(height: 28)
            HStack(alignment: .top, spacing: 8) {
                ForEach(Self.order, id: \.0) { kind, name in
                    if kind == .guitar && session.usesSeparatedGuitars {
                        ForEach(session.guitarTracks, id: \.role) { g in
                            let m = session.mix(forGuitar: g.role)
                            let gName = session.guitarName(g.role)
                            compactChannel(gName, m, toggleMute: { ctl.toggleMute(guitar: g.role) },
                                           toggleSolo: { ctl.toggleSolo(guitar: g.role) })
                        }
                    } else if session.audibleStems.contains(kind), !session.emptyStems.contains(kind) {
                        compactChannel(name, session.mix(for: kind), toggleMute: { ctl.toggleMute(kind) },
                                       toggleSolo: { ctl.toggleSolo(kind) })
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func compactChannel(_ name: String, _ m: StemMix, toggleMute: @escaping () -> Void,
                                toggleSolo: @escaping () -> Void) -> some View {
        let dim = m.muted || (anySolo && !m.solo)
        return VStack(spacing: 4) {
            Text(name).font(TF.body(12, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                .truncationMode(.middle).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                MixerToggle(text: "M", on: m.muted, label: (m.muted ? "Activar " : "Silenciar ") + name) { toggleMute() }
                MixerToggle(text: "S", on: m.solo, label: "Solo " + name) { toggleSolo() }
            }
        }
        .frame(minWidth: 78, maxWidth: .infinity)
        .opacity(dim ? 0.55 : 1)
    }
}

private struct MixerChannelHeightKey: EnvironmentKey { static let defaultValue: CGFloat = 276 }
extension EnvironmentValues {
    /// Alto del canal del mezclador (276 a tamaño completo; menor cuando el mezclador encoge).
    var mixerChannelHeight: CGFloat {
        get { self[MixerChannelHeightKey.self] }
        set { self[MixerChannelHeightKey.self] = newValue }
    }
}

/// Canal del mezclador: un stem o (Fase 4) una pista de guitarra. Con `rename` el nombre se edita con doble clic
/// o desde el menú contextual. Sin insignia de confianza: no hay confianza L/R (mini-spec Fase 4).
struct MixerChannel: View {
    let name: String
    let mix: StemMix
    let anySolo: Bool
    let meter: ChannelMeter?
    var rename: ((String) -> Void)?
    let setGain: (Double) -> Void
    let toggleMute: () -> Void
    let toggleSolo: () -> Void

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    private static let baseFaderHeight: CGFloat = 150
    /// Alto de la franja del título y del canal entero: igual para todos (master, stems, vacíos y guitarras) para
    /// que los títulos queden a la misma altura.
    static let titleHeight: CGFloat = 22
    static let height: CGFloat = 276
    /// Alto mínimo del canal (pantalla baja: fader de 40; normal: 74 con cuerpo de 210).
    static let minHeight: CGFloat = 166
    @Environment(\.mixerChannelHeight) private var channelHeight
    private var faderHeight: CGFloat { max(Self.baseFaderHeight - (Self.height - channelHeight), 40) }

    var body: some View {
        let m = mix
        let dim = m.muted || (anySolo && !m.solo)
        VStack(spacing: 6) {
            title
            HStack(spacing: 10) {
                Fader(dB: m.gainDB) { setGain($0) }
                    .frame(width: 28, height: faderHeight)
                levelBar(dim ? nil : meter).frame(width: 8, height: faderHeight)
            }
            .padding(.top, 4)
            Text(m.muted ? "Silenciado" : String(format: "%.1f dB", m.gainDB).replacingOccurrences(of: ".", with: ","))
                .font(TF.body(12)).foregroundStyle(TF.text2)
            HStack(spacing: 6) {
                MixerToggle(text: "M", on: m.muted, label: (m.muted ? "Activar " : "Silenciar ") + name) { toggleMute() }
                MixerToggle(text: "S", on: m.solo, label: "Solo " + name) { toggleSolo() }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 12).frame(width: 96, height: channelHeight, alignment: .top)
        .background(TF.field, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TF.fieldLine))
        .opacity(dim ? 0.55 : 1)
    }

    @ViewBuilder private var title: some View {
        if editing {
            TextField("Nombre", text: $draft)
                .textFieldStyle(.roundedBorder).font(TF.body(12, .semibold)).multilineTextAlignment(.center)
                .frame(width: 84, height: Self.titleHeight).focused($focused)
                .onSubmit { commit() }
                .onChange(of: focused) { _, f in if !f { commit() } }
                .onExitCommand { editing = false }
        } else {
            Text(name).font(TF.body(12, .semibold)).lineLimit(1).minimumScaleFactor(0.9).padding(.horizontal, 4)
                .frame(height: Self.titleHeight)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { if rename != nil { startEditing() } }
                .help(rename == nil ? "" : "Doble clic para cambiar el nombre")
                .contextMenu { if rename != nil { Button("Cambiar nombre…") { startEditing() } } }
        }
    }

    private func startEditing() {
        draft = name
        editing = true
        focused = true
    }

    private func commit() {
        guard editing else { return }
        editing = false
        rename?(draft)
    }

    private func levelBar(_ m: ChannelMeter?) -> some View {
        let floor = BackingController.meterFloorDB
        let f = m.map { min(max((Double($0.rmsDB) - floor) / -floor, 0), 1) } ?? 0
        return GeometryReader { g in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4).fill(TF.bg)
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(stops: [.init(color: TF.ok, location: 0.7), .init(color: TF.accent, location: 0.92)],
                                         startPoint: .bottom, endPoint: .top))
                    .frame(height: g.size.height * f)
            }
        }
    }
}

/// Canal master: volumen global (stems + metrónomo), guardado en el perfil de equipo.
struct MasterChannel: View {
    let ctl: BackingController
    @Environment(\.mixerChannelHeight) private var channelHeight

    var body: some View {
        VStack(spacing: 6) {
            Text("Master").font(TF.body(12, .semibold)).frame(height: MixerChannel.titleHeight)
            Fader(dB: ctl.masterGainDB) { ctl.setMaster($0) }
                .frame(width: 28, height: max(150 - (MixerChannel.height - channelHeight), 40))
                .padding(.horizontal, 18).padding(.top, 4)
            Text(Fmt.db(ctl.masterGainDB)).font(TF.body(12)).foregroundStyle(TF.text2)
            Color.clear.frame(height: 40)
        }
        .padding(.vertical, 12).frame(width: 96, height: channelHeight, alignment: .top)
        .background(TF.accentBg.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TF.accent.opacity(0.6)))
    }
}

struct MixerToggle: View {
    let text: String
    let on: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text).font(TF.body(12, .bold))
                .foregroundStyle(on ? TF.accentInk : TF.text2)
                .frame(width: 36, height: 36)
                .background(on ? TF.accent : TF.field, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? .clear : TF.fieldLine))
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }
}

extension Fmt {
    /// «−6,0 dB».
    static func db(_ v: Double) -> String { String(format: "%.1f dB", v).replacingOccurrences(of: ".", with: ",") }
}

/// Fader vertical de −60 a +6 dB; doble clic = 0 dB; imán a 0 dB.
struct Fader: View {
    let dB: Double
    let set: (Double) -> Void

    private static let snapDB = 1.5

    var body: some View {
        GeometryReader { g in
            let h = g.size.height, r = BackingController.faderRange
            let frac = (dB - r.lowerBound) / (r.upperBound - r.lowerBound)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 3).fill(TF.bg).frame(width: 6).frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: 4).fill(TF.text2).frame(width: 28, height: 18)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                    .offset(y: h * (1 - frac) - 9)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { set(0) }
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let f = 1 - min(max(v.location.y / h, 0), 1)
                var d = r.lowerBound + f * (r.upperBound - r.lowerBound)
                if abs(d) < Self.snapDB { d = 0 }
                set(d)
            })
        }
        .accessibilityElement()
        .accessibilityLabel("Volumen")
        .accessibilityValue(String(format: "%.1f dB", dB))
        .accessibilityAdjustableAction { dir in set(dB + (dir == .increment ? 1 : -1)) }
    }
}
