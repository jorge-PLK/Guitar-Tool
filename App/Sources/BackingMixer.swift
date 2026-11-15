import AudioKit
import Store
import SwiftUI

/// Mezclador de Backing: un canal por stem (voz, batería, bajo, guitarra, piano, resto). Los stems vacíos
/// salen como canal «vacío», sin fader ni medidor (mini-spec Fase 2 «Stems vacíos»).
struct BackingMixer: View {
    let session: StudySession
    let ctl: BackingController
    let meters: [String: ChannelMeter]
    /// Con la rejilla de acordes expandida: solo master y M/S por stem, sin faders ni medidores de stems.
    var compact = false

    private static let order: [(StemKind, String)] = [
        (.vocals, "Voz"), (.drums, "Batería"), (.bass, "Bajo"), (.guitar, "Guitarra"), (.piano, "Piano"), (.other, "Resto"),
    ]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Mezclador").font(TF.display(18))
                    Spacer()
                    Text("Salida: \(ctl.player.outputDeviceName.isEmpty ? "—" : ctl.player.outputDeviceName)")
                        .font(TF.body(12)).foregroundStyle(TF.muted)
                }
                if compact {
                    compactBody
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            MasterChannel(ctl: ctl)
                            Divider().frame(height: 200).padding(.horizontal, 6)
                            ForEach(Self.order, id: \.0) { kind, name in
                                if session.emptyStems.contains(kind) {
                                    emptyChannel(name)
                                } else if session.audibleStems.contains(kind) {
                                    MixerChannel(name: name, kind: kind, session: session, ctl: ctl, meter: meters[kind.rawValue])
                                }
                            }
                            if ctl.loadedTake != nil {
                                TakeChannel(ctl: ctl, meter: meters[BackingController.takeChannelID])
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
        }
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
            ForEach(Self.order, id: \.0) { kind, name in
                if session.emptyStems.contains(kind) {
                    HStack(spacing: 6) {
                        Text(name).font(TF.body(12, .semibold))
                        Text("vacío").font(TF.body(12)).foregroundStyle(TF.muted)
                    }
                    .padding(.horizontal, 10).frame(height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(TF.fieldLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(name), vacío")
                } else if session.audibleStems.contains(kind) {
                    let m = session.mix(for: kind)
                    let dim = m.muted || (session.study.mixer.contains { $0.solo } && !m.solo)
                    HStack(spacing: 6) {
                        Text(name).font(TF.body(12, .semibold)).frame(minWidth: 44, alignment: .leading)
                        MixerToggle(text: "M", on: m.muted, label: (m.muted ? "Activar " : "Silenciar ") + name) { ctl.toggleMute(kind) }
                        MixerToggle(text: "S", on: m.solo, label: "Solo " + name) { ctl.toggleSolo(kind) }
                    }
                    .opacity(dim ? 0.55 : 1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func emptyChannel(_ name: String) -> some View {
        VStack(spacing: 10) {
            Text(name).font(TF.body(13, .semibold))
            Spacer()
            Text("vacío").font(TF.body(12)).foregroundStyle(TF.muted)
            Spacer()
        }
        .padding(.vertical, 12).frame(width: 96, height: 262)
        .background(TF.field.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TF.fieldLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), vacío")
    }
}

struct MixerChannel: View {
    let name: String
    let kind: StemKind
    let session: StudySession
    let ctl: BackingController
    let meter: ChannelMeter?

    private static let faderHeight: CGFloat = 150
    private var mix: StemMix { session.mix(for: kind) }

    var body: some View {
        let m = mix
        let dim = m.muted || (session.study.mixer.contains { $0.solo } && !m.solo)
        VStack(spacing: 10) {
            Text(name).font(TF.body(13, .semibold))
            HStack(spacing: 10) {
                Fader(dB: m.gainDB) { ctl.setGain(kind, $0) }
                    .frame(width: 28, height: Self.faderHeight)
                levelBar(dim ? nil : meter).frame(width: 8, height: Self.faderHeight)
            }
            Text(m.muted ? "Silenciado" : String(format: "%.1f dB", m.gainDB).replacingOccurrences(of: ".", with: ","))
                .font(TF.body(12)).foregroundStyle(TF.text2)
            HStack(spacing: 6) {
                MixerToggle(text: "M", on: m.muted, label: (m.muted ? "Activar " : "Silenciar ") + name) { ctl.toggleMute(kind) }
                MixerToggle(text: "S", on: m.solo, label: "Solo " + name) { ctl.toggleSolo(kind) }
            }
        }
        .padding(.vertical, 12).frame(width: 96)
        .background(TF.field, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TF.fieldLine))
        .opacity(dim ? 0.55 : 1)
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

    var body: some View {
        VStack(spacing: 10) {
            Text("Master").font(TF.body(13, .semibold))
            Fader(dB: ctl.masterGainDB) { ctl.setMaster($0) }
                .frame(width: 28, height: 150)
                .padding(.horizontal, 18)
            Text(Fmt.db(ctl.masterGainDB)).font(TF.body(12)).foregroundStyle(TF.text2)
            Color.clear.frame(height: 36)
        }
        .padding(.vertical, 12).frame(width: 96)
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
