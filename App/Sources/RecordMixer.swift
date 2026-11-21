import AudioKit
import Store
import SwiftUI

/// Mezclador de Grabar (mini-spec Fase 6, «Interfaz»): como el de Backing, con su propia mezcla, el medidor de la
/// entrada de guitarra en lugar de «Pistas de audio» y un canal «Tú · parte» por cada mejor toma de las otras partes.
struct RecordMixer: View {
    let ctl: RecordController
    let meters: [String: ChannelMeter]
    /// Nivel de la entrada de guitarra, 0...1.
    let inputLevel: Float
    /// Por defecto compacto (como el plegado de Backing: nombre + M/S); expandido = faders y medidores.
    @Binding var expanded: Bool

    private static let order: [(StemKind, String)] = [
        (.vocals, "Voz"), (.drums, "Batería"), (.bass, "Bajo"), (.guitar, "Guitarra"), (.piano, "Piano"), (.other, "Resto"),
    ]

    var body: some View {
        let session = ctl.session
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text("Mezclador").font(TF.display(18))
                    Spacer()
                    Text("Salida: \(ctl.player.outputDeviceName.isEmpty ? "—" : ctl.player.outputDeviceName)")
                        .font(TF.body(12)).foregroundStyle(TF.muted)
                    Button { expanded.toggle() } label: {
                        Text(expanded ? "Plegar" : "Expandir").font(TF.body(13, .medium)).foregroundStyle(TF.text2)
                            .padding(.horizontal, 12).frame(height: 30)
                            .background(TF.field, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(TF.fieldLine))
                    }
                    .buttonStyle(.plain).accessibilityLabel(expanded ? "Plegar el mezclador" : "Expandir el mezclador")
                }
                if !expanded {
                    compactBody
                } else {
                HStack(alignment: .top, spacing: 10) {
                    RecordMasterChannel(ctl: ctl)
                    GuitarInputChannel(level: inputLevel)
                    Divider().frame(height: 200).padding(.horizontal, 6)
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(Self.order, id: \.0) { kind, name in
                                if kind == .guitar && session.usesSeparatedGuitars {
                                    ForEach(session.guitarTracks, id: \.role) { g in guitarChannel(g) }
                                } else if session.audibleStems.contains(kind), !session.emptyStems.contains(kind) {
                                    stemChannel(kind, name)
                                }
                            }
                            ForEach(ctl.backingTakeChannels, id: \.partID) { bt in takeChannel(bt) }
                        }
                        .padding(.bottom, 10)
                    }
                }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
    }

    // MARK: Compacto

    private var compactBody: some View {
        let session = ctl.session
        let dB = ctl.model.profile.masterGainDB
        let head = HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                Text("Master").font(TF.body(12, .semibold)).fixedSize()
                Slider(value: Binding(get: { dB }, set: { ctl.setMaster(abs($0) < 1.5 ? 0 : $0) }),
                       in: BackingController.faderRange).frame(width: 40).tint(TF.accent)
                Text(Fmt.db(dB)).font(TF.body(12)).foregroundStyle(TF.text2).monospacedDigit().frame(width: 42, alignment: .leading)
            }
            Divider().frame(height: 28)
            HStack(spacing: 6) {
                Text("Tu guitarra").font(TF.body(12, .semibold)).lineLimit(1).fixedSize()
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(TF.bg)
                        RoundedRectangle(cornerRadius: 3).fill(TF.ok).frame(width: g.size.width * CGFloat(min(max(inputLevel, 0), 1)))
                    }
                }
                .frame(width: 22, height: 8)
            }
            .accessibilityElement(children: .ignore).accessibilityLabel("Nivel de la entrada de guitarra")
        }
        let channels = ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 6) {
                Group {
                    ForEach(Self.order, id: \.0) { kind, name in
                        if kind == .guitar && session.usesSeparatedGuitars {
                            ForEach(session.guitarTracks, id: \.role) { g in
                                let id = g.role.trackID
                                compactChannel(ctl.session.guitarName(g.role), forced(id, ctl.mix(forGuitar: g.role)),
                                               mute: { if !ctl.isForcedMuted(id) { ctl.updateMix(guitar: g.role) { $0.muted.toggle() } } },
                                               solo: { if !ctl.isForcedMuted(id) { ctl.updateMix(guitar: g.role) { $0.solo.toggle() } } })
                            }
                        } else if session.audibleStems.contains(kind), !session.emptyStems.contains(kind) {
                            let id = kind.rawValue
                            compactChannel(name, forced(id, ctl.mix(for: kind)),
                                           mute: { if !ctl.isForcedMuted(id) { ctl.updateMix(kind) { $0.muted.toggle() } } },
                                           solo: { if !ctl.isForcedMuted(id) { ctl.updateMix(kind) { $0.solo.toggle() } } })
                        }
                    }
                    ForEach(ctl.backingTakeChannels, id: \.partID) { bt in
                        compactChannel(bt.channelName, ctl.takeMix(bt.partID),
                                       mute: { ctl.updateTakeMix(bt.partID) { $0.muted.toggle() } },
                                       solo: { ctl.updateTakeMix(bt.partID) { $0.solo.toggle() } })
                            .help(bt.channelName)
                    }
                }
            }
        }
        // Adaptación (mínimo de ventana 1100×680): los canales M/S hacen scroll horizontal dentro de la tarjeta; si no
        // caben junto a Master y la entrada, pasan a una segunda línea. Nunca fijan un ancho mínimo a la pantalla.
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) { head; Divider().frame(height: 28); channels.fixedSize(horizontal: true, vertical: false) }
            VStack(alignment: .leading, spacing: 8) { head; channels }
        }
    }

    private func compactChannel(_ name: String, _ m: StemMix, mute: @escaping () -> Void, solo: @escaping () -> Void) -> some View {
        let dim = m.muted || (ctl.anySolo && !m.solo)
        return VStack(spacing: 4) {
            Text(name).font(TF.body(12, .semibold)).lineLimit(1).minimumScaleFactor(0.8).truncationMode(.middle)
                .frame(width: 76)
            HStack(spacing: 6) {
                MixerToggle(text: "M", on: m.muted, label: (m.muted ? "Activar " : "Silenciar ") + name) { mute() }
                MixerToggle(text: "S", on: m.solo, label: "Solo " + name) { solo() }
            }
        }
        .frame(width: 76)
        .opacity(dim ? 0.55 : 1)
    }

    /// La guitarra de la parte que se graba se ve silenciada y no se puede reactivar.
    private func forced(_ id: String, _ m: StemMix) -> StemMix {
        var m = m
        if ctl.isForcedMuted(id) { m.muted = true; m.solo = false }
        return m
    }

    private func stemChannel(_ kind: StemKind, _ name: String) -> some View {
        let id = kind.rawValue
        return MixerChannel(name: name, mix: forced(id, ctl.mix(for: kind)), anySolo: ctl.anySolo, meter: meters[id],
                            setGain: { v in ctl.updateMix(kind) { $0.gainDB = v } },
                            toggleMute: { if !ctl.isForcedMuted(id) { ctl.updateMix(kind) { $0.muted.toggle() } } },
                            toggleSolo: { if !ctl.isForcedMuted(id) { ctl.updateMix(kind) { $0.solo.toggle() } } })
    }

    private func guitarChannel(_ g: Guitar) -> some View {
        let id = g.role.trackID
        return MixerChannel(name: ctl.session.guitarName(g.role), mix: forced(id, ctl.mix(forGuitar: g.role)),
                            anySolo: ctl.anySolo, meter: meters[id],
                            setGain: { v in ctl.updateMix(guitar: g.role) { $0.gainDB = v } },
                            toggleMute: { if !ctl.isForcedMuted(id) { ctl.updateMix(guitar: g.role) { $0.muted.toggle() } } },
                            toggleSolo: { if !ctl.isForcedMuted(id) { ctl.updateMix(guitar: g.role) { $0.solo.toggle() } } })
    }

    private func takeChannel(_ bt: BackingTake) -> some View {
        MixerChannel(name: bt.channelName, mix: ctl.takeMix(bt.partID), anySolo: ctl.anySolo,
                     meter: meters[RecordController.takeTrackID(bt.partID)],
                     setGain: { v in ctl.updateTakeMix(bt.partID) { $0.gainDB = v } },
                     toggleMute: { ctl.updateTakeMix(bt.partID) { $0.muted.toggle() } },
                     toggleSolo: { ctl.updateTakeMix(bt.partID) { $0.solo.toggle() } })
            .help(bt.channelName)
    }
}

/// Volumen global (el mismo que el de Backing, guardado en el perfil).
struct RecordMasterChannel: View {
    let ctl: RecordController

    var body: some View {
        let dB = ctl.model.profile.masterGainDB
        VStack(spacing: 6) {
            Text("Master").font(TF.body(12, .semibold)).frame(height: MixerChannel.titleHeight)
            Fader(dB: dB) { ctl.setMaster($0) }
                .frame(width: 28, height: 150)
                .padding(.horizontal, 18).padding(.top, 4)
            Text(Fmt.db(dB)).font(TF.body(12)).foregroundStyle(TF.text2)
            Color.clear.frame(height: 40)
        }
        .padding(.vertical, 12).frame(width: 96, height: MixerChannel.height, alignment: .top)
        .background(TF.accentBg.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TF.accent.opacity(0.6)))
    }
}

/// Medidor de la entrada de guitarra (la señal procesada que se graba).
struct GuitarInputChannel: View {
    let level: Float

    var body: some View {
        VStack(spacing: 6) {
            Text("Tu guitarra").font(TF.body(12, .semibold)).frame(height: MixerChannel.titleHeight)
            GeometryReader { g in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4).fill(TF.bg)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(stops: [.init(color: TF.ok, location: 0.7), .init(color: TF.accent, location: 0.92)],
                                             startPoint: .bottom, endPoint: .top))
                        .frame(height: g.size.height * CGFloat(min(max(level, 0), 1)))
                }
            }
            .frame(width: 12, height: 150).padding(.top, 4)
            Text("Entrada").font(TF.body(12)).foregroundStyle(TF.text2)
            Color.clear.frame(height: 40)
        }
        .padding(.vertical, 12).frame(width: 96, height: MixerChannel.height, alignment: .top)
        .background(TF.field, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TF.fieldLine))
        .accessibilityElement(children: .ignore).accessibilityLabel("Nivel de la entrada de guitarra")
    }
}
