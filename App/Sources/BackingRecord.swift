import AudioKit
import Store
import SwiftUI

/// Botón rojo «Grabar» del transporte de Backing (boceto `Backing.dc.html`; mini-spec Fase 3, «Grabación»).
/// Con el motivo a la vista cuando está desactivado (lo pinta `RecordStatus`).
struct RecordButton: View {
    let ctl: BackingController
    @Environment(AppModel.self) private var model

    private static let red = Color(hex: 0xC8433A)

    var body: some View {
        let audio = model.audio
        let rate = ctl.settings.rate, loop = ctl.loop != nil
        let blocked = !audio.isRecording && audio.recordBlock(playbackRate: rate, loopActive: loop) != nil
        Button {
            if audio.isRecording { audio.stopRecording() } else { audio.startRecording(playbackRate: rate, loopActive: loop) }
        } label: {
            HStack(spacing: 8) {
                if audio.isRecording {
                    RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 10, height: 10)
                } else {
                    Circle().fill(.white).frame(width: 10, height: 10)
                }
                Text(audio.isRecording ? "Parar" : "Grabar")
            }
            .font(TF.body(14, .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 18).frame(height: 44)
            .background(Self.red, in: Capsule())
            .opacity(blocked ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        .accessibilityLabel(audio.isRecording ? "Parar la grabación" : "Grabar")
    }
}

/// Estado de la grabación bajo el transporte: motivo del bloqueo, aviso de «Sin calibrar» y avisos de la toma.
struct RecordStatus: View {
    let session: StudySession
    let ctl: BackingController
    @Environment(AppModel.self) private var model

    /// Aviso de la mini-spec Fase 3, «Reglas propias»: la latencia sin calibrar no bloquea, avisa.
    static let uncalibratedWarning = "Sin calibrar: la toma puede ir desfasada decenas de ms; se corregirá al calibrar."

    var body: some View {
        let audio = model.audio
        let block = audio.isRecording ? nil : audio.recordBlock(playbackRate: ctl.settings.rate, loopActive: ctl.loop != nil)
        VStack(alignment: .leading, spacing: 4) {
            if audio.isRecording {
                line("Grabando desde la posición en que empezaste. Pulsa Parar para guardar la toma.", TF.accent)
            }
            if let block { line(block.message, TF.muted) }
            if block == nil || audio.isRecording, !audio.calibrationValid { line(Self.uncalibratedWarning, TF.accent) }
            ForEach(audio.takeNotices, id: \.self) { line($0, TF.accent) }
            if let e = session.takeSaveError { line(e, TF.danger) }
            if let e = ctl.takeError { line(e, TF.danger) }
        }
    }

    private func line(_ text: String, _ color: Color) -> some View {
        Text(text).font(TF.body(12)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
}

/// Panel «Comparar en la mezcla» (boceto `Backing.dc.html`; mini-spec Fase 3, «A/B dentro de la mezcla»):
/// solo nivel, sobre el stem de guitarra.
struct ComparePanel: View {
    let ctl: BackingController
    @Environment(AppModel.self) private var model

    var body: some View {
        let liveBlock = model.audio.deviceBlock
        let hasTake = ctl.lastTake != nil
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Comparar en la mezcla").font(TF.display(18))
                Text("Escucha tu guitarra dentro de la banda, en lugar de la del disco.")
                    .font(TF.body(13)).foregroundStyle(TF.text2).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 6) {
                    option("A · Original", .original, enabled: true)
                    option("B · Tú en directo", .live, enabled: liveBlock == nil)
                    option("B · Última toma", .lastTake, enabled: hasTake)
                }
                .accessibilityElement(children: .contain).accessibilityLabel("Fuente")
                detail(liveBlock: liveBlock, hasTake: hasTake)
                if ctl.compareMode != .original {
                    Text("Mientras comparas en B, el stem de guitarra queda en silencio; al volver a A recupera tu mute.")
                        .font(TF.body(12)).foregroundStyle(TF.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
        }
        // El tramo del stem se relee ~2 veces por segundo mientras se compara en directo.
        .task(id: ctl.compareMode) {
            while ctl.compareMode == .live, !Task.isCancelled {
                await ctl.refreshLiveDifference()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        .onChange(of: liveBlock != nil) { _, blocked in
            if blocked, ctl.compareMode == .live { ctl.setCompare(.original) }
        }
    }

    private func option(_ title: String, _ mode: CompareMode, enabled: Bool) -> some View {
        let on = ctl.compareMode == mode
        return Button { ctl.setCompare(mode) } label: {
            Text(title)
                .font(TF.body(13, on ? .semibold : .medium))
                .foregroundStyle(on ? TF.accent : TF.text2)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(on ? TF.accentBg : TF.field, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? TF.accent : TF.fieldLine))
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private func detail(liveBlock: RecordBlock?, hasTake: Bool) -> some View {
        switch ctl.compareMode {
        case .original:
            if let liveBlock { hint("B · Tú en directo no disponible: \(liveBlock.message)") }
            if !hasTake { hint("B · Última toma: aún no hay tomas; graba una.") }
        case .live:
            box(title: "Diferencia de nivel en directo") {
                if let d = ctl.liveDifferenceDB {
                    Text(MixCompare.differenceText(d)).font(TF.display(20)).foregroundStyle(TF.text)
                } else {
                    Text("Toca para medirla…").font(TF.body(14)).foregroundStyle(TF.muted)
                }
                Text("Tu procesada (últimos 3 s) frente al stem con su fader. No se compensa: ajusta el volumen en el aparato.")
                    .font(TF.body(12)).foregroundStyle(TF.muted).fixedSize(horizontal: false, vertical: true)
            }
        case .lastTake:
            box(title: "Ganancia aplicada a tu toma") {
                if let g = ctl.takeGainDB {
                    Text(MixCompare.gainText(g)).font(TF.display(28)).foregroundStyle(TF.text)
                    Text("Igualada en sonoridad al stem de guitarra (tope ±\(Int(LoudnessMatch.maxGainDB)) dB).")
                        .font(TF.body(12)).foregroundStyle(TF.muted).fixedSize(horizontal: false, vertical: true)
                } else if ctl.loadedTake != nil {
                    Text("Sin ganancia: no se pudo medir la sonoridad (silencio).").font(TF.body(13)).foregroundStyle(TF.muted)
                } else {
                    Text("Cargando la toma…").font(TF.body(14)).foregroundStyle(TF.muted)
                }
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(TF.body(12)).foregroundStyle(TF.muted).fixedSize(horizontal: false, vertical: true)
    }

    private func box<C: View>(title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(TF.body(12)).foregroundStyle(TF.muted)
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Canal «Tú» del mezclador, cuando hay toma cargada (boceto: caja con borde de acento). Solo suena en «B · Última toma».
struct TakeChannel: View {
    let ctl: BackingController
    let meter: ChannelMeter?

    var body: some View {
        let active = ctl.compareMode == .lastTake
        VStack(spacing: 10) {
            Text("Tú").font(TF.body(13, .semibold))
            HStack(spacing: 10) {
                Fader(dB: ctl.takeFaderDB) { ctl.setTakeGain($0) }.frame(width: 28, height: 150)
                level(active ? meter : nil).frame(width: 8, height: 150)
            }
            Text(Fmt.db(ctl.takeFaderDB)).font(TF.body(12)).foregroundStyle(TF.text2)
            Text(active ? "Sonando" : "En B · Última toma")
                .font(TF.body(11)).foregroundStyle(active ? TF.accent : TF.muted)
                .multilineTextAlignment(.center).frame(height: 36)
        }
        .padding(.vertical, 12).frame(width: 96)
        .background(TF.accentBg.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TF.accent))
        .opacity(active ? 1 : 0.7)
        .accessibilityElement(children: .contain).accessibilityLabel("Canal Tú")
    }

    private func level(_ m: ChannelMeter?) -> some View {
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
