import AudioKit
import SwiftUI

extension Fmt {
    /// Número con coma decimal y `digits` decimales («50,02»).
    static func number(_ v: Double, _ digits: Int) -> String {
        v.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "es")))
    }
}

/// Hoja «Calibrar latencia» de Ajustes · Audio (mini-spec Fase 3, «Calibración de latencia»): instrucciones,
/// progreso y resultado en números, o el motivo del fallo con qué hacer.
struct CalibrationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var audio: AudioController { model.audio }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Calibrar latencia").font(TF.display(22))
            switch audio.calibrationPhase {
            case .idle: instructions
            case .running(let p): running(p)
            case .finished(let outcome): result(outcome)
            }
        }
        .padding(28).frame(width: 540)
        .background(TF.bg)
        .interactiveDismissDisabled(audio.calibrationIsRunning)
        .onDisappear { audio.dismissCalibration() }
    }

    // MARK: Instrucciones

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                Text("Conecta con un cable una salida del dispositivo a su entrada de guitarra.")
                Text("Con una pedalera, carga un rig vacío y baja el volumen de salida: el bucle realimenta (entrada, rig, salida, cable, entrada).")
                Text("La prueba son 10 pitidos agudos en unos 5 segundos. Mide el retardo de ida y vuelta, que es el desfase que tendrá una toma respecto al backing que se oye.")
                    .foregroundStyle(TF.muted)
            }
            .font(TF.body(14)).foregroundStyle(TF.text2).fixedSize(horizontal: false, vertical: true)
            let block = audio.deviceBlock
            if let block {
                Text(block.message).font(TF.body(13)).foregroundStyle(TF.accent).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.buttonStyle(SecondaryButton())
                Button("Empezar") { Task { await audio.calibrate() } }
                    .buttonStyle(PrimaryButton()).disabled(block != nil)
            }
        }
    }

    // MARK: Progreso

    private func running(_ p: Double) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Midiendo… no toques la guitarra ni muevas el cable.")
                .font(TF.body(14)).foregroundStyle(TF.text2)
            AccentBar(value: p, height: 8)
            Text(Fmt.percent(p)).font(TF.body(13)).foregroundStyle(TF.muted).monospacedDigit()
        }
    }

    // MARK: Resultado

    @ViewBuilder private func result(_ outcome: CalibrationOutcome) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            switch outcome {
            case .success(let s): success(s)
            case let .failure(f, spread): failure(f, spreadMS: spread)
            case .error(let msg):
                Text("No se pudo calibrar").font(TF.display(16)).foregroundStyle(TF.danger)
                Text(msg).font(TF.body(14)).foregroundStyle(TF.text2).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                if case .success = outcome {} else {
                    Button("Repetir") { audio.dismissCalibration() }.buttonStyle(SecondaryButton())
                }
                Button("Cerrar") { dismiss() }.buttonStyle(PrimaryButton())
            }
        }
    }

    private func success(_ s: CalibrationSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Chip(text: "Calibrada", kind: .ok)
            VStack(alignment: .leading, spacing: 8) {
                row("Latencia", "\(Fmt.number(s.latencyMS, 2)) ms · \(Fmt.number(s.latencySamples, 1)) muestras")
                row("Dispersión", "\(Fmt.number(s.spreadMS, 3)) ms · \(Fmt.number(s.spreadSamples, 1)) muestras")
                if let rig = s.rigDelayMS {
                    row("Retardo del rig", "\(Fmt.number(rig, 2)) ms · se corregirá en cada toma")
                } else {
                    row("Retardo del rig", "sin canal de referencia: la latencia calibrada vale tal cual")
                }
                if s.correctedTakes > 0 {
                    row("Tomas corregidas", "\(s.correctedTakes) de este tema, hechas sin calibrar")
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(TF.body(13)).foregroundStyle(TF.muted).frame(width: 120, alignment: .leading)
            Text(value).font(TF.body(14, .semibold)).foregroundStyle(TF.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func failure(_ f: LatencyFailure, spreadMS: Double) -> some View {
        let (title, todo): (String, String) = switch f {
        case .noSignal:
            ("No llegó la señal de prueba",
             "Comprueba el cable de una salida del dispositivo a la entrada de guitarra, y que la entrada elegida sea esa. Después repite.")
        case .saturated:
            ("La señal llegó saturada",
             "Baja el volumen de salida del dispositivo (con una pedalera, el del rig o el de la salida) y repite.")
        case .unstable:
            ("Las medidas no coinciden entre sí (dispersión de \(Fmt.number(spreadMS, 2)) ms)",
             "Carga un rig vacío o sin delay ni reverb, cierra otras apps de audio y repite.")
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(TF.display(16)).foregroundStyle(TF.danger).fixedSize(horizontal: false, vertical: true)
            Text(todo).font(TF.body(14)).foregroundStyle(TF.text2).fixedSize(horizontal: false, vertical: true)
        }
    }
}
