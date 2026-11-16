import Store
import SwiftUI

// Interfaz de la Fase 4 en Backing (mini-spec «Opciones de guitarras y tramos de solo»): interruptor «Guitarras en L y R»
// con el estado del proceso (en la cabecera del mezclador) y botones «Aplicar»/«Descartar» (en la barra de la tira de
// acordes). Las secciones y los solos se dibujan y se editan sobre la tira (`SectionBoxes.swift`).

/// Interruptor «Guitarras en L y R» y estado del paso de guitarras. Naranja de la paleta, no el azul del sistema.
struct GuitarStereoToggle: View {
    let session: StudySession

    @Environment(AppModel.self) private var model

    private var process: GuitarProcess? { model.guitarProcess[session.projectID] }

    var body: some View {
        HStack(spacing: 12) {
            GuitarStatusView(process: process, error: session.guitarOptionsError)
            Toggle("Guitarras en L y R", isOn: Binding(get: { session.guitarOptions.stereoSplit },
                                                       set: { session.setStereoSplit($0) }))
                .toggleStyle(.switch).controlSize(.small).tint(TF.accent)
                .font(TF.body(13, .medium)).foregroundStyle(TF.text)
                .help("L = canal izquierdo, R = canal derecho de la pista de guitarras")
        }
    }
}

/// «Descartar» y «Aplicar», solo con secciones sin aplicar.
struct SectionApplyButtons: View {
    let session: StudySession

    var body: some View {
        if session.hasUnappliedSections {
            Button("Descartar") { session.discardSections() }
                .buttonStyle(SecondaryButton(height: 28))
                .help("Vuelve a las secciones guardadas")
            Button("Aplicar") { session.applySections() }
                .buttonStyle(ApplyButton())
                .help("Guarda las secciones. Las pistas de guitarra se rehacen, en segundo plano, solo si cambian los solos")
        }
    }
}

private struct ApplyButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TF.body(13, .semibold)).foregroundStyle(TF.accentInk)
            .padding(.horizontal, 16).frame(height: 28)
            .background(TF.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Estado del paso de guitarras: procesando (sin progreso: la cola no lo emite) o error con mensaje.
struct GuitarStatusView: View {
    let process: GuitarProcess?
    var error: String?

    var body: some View {
        switch process {
        case .processing?:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Procesando guitarras…").foregroundStyle(TF.text2)
            }
            .font(TF.body(13))
            .accessibilityElement(children: .combine)
        case .failed(let msg)?:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(msg).lineLimit(1)
            }
            .font(TF.body(13))
            .foregroundStyle(TF.danger)
            .accessibilityElement(children: .combine)
        case nil:
            if let error { Text(error).font(TF.body(13)).foregroundStyle(TF.danger).lineLimit(1) }
        }
    }
}
