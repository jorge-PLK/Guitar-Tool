import ModelKit
import SwiftUI
import Store

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ajustes").font(TF.display(30))
                    Text("Se configura una vez y lo usan todas las pantallas. Se guarda en tu perfil de equipo.")
                        .foregroundStyle(TF.muted)
                }
                HStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        let on = tab == model.settingsTab
                        Button { model.settingsTab = tab } label: {
                            Text(tab.rawValue).font(TF.body(14, on ? .semibold : .medium))
                                .foregroundStyle(on ? TF.accent : TF.text2)
                                .padding(.horizontal, 18).frame(height: 44)
                                .background(on ? TF.accentBg : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(TF.fieldLine))

                switch model.settingsTab {
                case .audio: AudioSettingsView()
                case .video: VideoSettingsView()
                case .library: LibrarySettings()
                }
            }
            .padding(.horizontal, 36).padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private func phase(_ text: String) -> some View {
    Text(text).foregroundStyle(TF.accent).font(TF.body(13, .semibold))
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let note: String
    @ViewBuilder var content: Content
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(TF.display(18, .medium))
                    Text(note).font(TF.body(13)).foregroundStyle(TF.muted).fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct InfoRow<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 12) {
            Text(label)
            Spacer()
            trailing
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct LibrarySettings: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDeleteModel = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 20) { library; models; externalSources }.frame(maxWidth: .infinity)
        .task { await model.refresh(); await model.loadToolsInfo() }
        .confirmationDialog("Carpeta de proyectos", isPresented: Binding(
            get: { model.pendingFolder != nil }, set: { if !$0 { model.pendingFolder = nil } }),
            titleVisibility: .visible, presenting: model.pendingFolder) { url in
            Button("Mover los temas aquí") { model.relocate(to: url, move: true) }
            Button("Solo apuntar a esta carpeta") { model.relocate(to: url, move: false) }
            Button("Cancelar", role: .cancel) {}
        } message: { url in
            Text("«\(url.path)»: ¿mover los temas existentes a la carpeta nueva o solo apuntar a ella?")
        }
        .confirmationDialog("Borrar el modelo", isPresented: $confirmDeleteModel, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) { model.deleteModel() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se volverá a descargar la próxima vez que separes un tema.")
        }
    }

    private var library: some View {
        SettingsGroup(title: "Biblioteca", note: "Una carpeta por tema, con sus stems, tomas y vídeo.") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Carpeta de proyectos").font(TF.body(13)).foregroundStyle(TF.muted)
                Text(model.profile.projectsFolder?.path ?? "—")
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(TF.field, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(TF.fieldLine))
            }
            InfoRow(label: "Espacio usado") {
                Text(model.usage.map { Fmt.bytes($0.totalBytes) } ?? "—").fontWeight(.semibold).foregroundStyle(TF.text2)
            }
            if let p = model.relocationProgress {
                HStack(spacing: 12) {
                    ProgressView(value: p).tint(TF.accent)
                    Text("Moviendo \(Fmt.percent(p))").font(TF.body(13)).foregroundStyle(TF.muted)
                }
            }
            HStack(spacing: 8) {
                Button("Cambiar carpeta") { model.pickNewFolder() }.buttonStyle(SecondaryButton())
                    .disabled(model.relocationProgress != nil)
                Button("Limpiar tomas descartadas y stems") {
                    model.requestCleanup(id: nil, title: "Limpiar toda la biblioteca")
                }.buttonStyle(SecondaryButton())
            }
        }
    }

    private var models: some View {
        let d = ModelCatalog.separatorBSRoformerSW
        return SettingsGroup(title: "Modelos", note: "Se descargan la primera vez que se usan.") {
            InfoRow(label: d.displayName) { modelStatus(d) }
            if case .downloading(let p) = model.modelState {
                ProgressView(value: p).tint(TF.accent)
            }
            HStack(spacing: 8) {
                switch model.modelState {
                case .installed:
                    Button("Borrar") { confirmDeleteModel = true }.buttonStyle(SecondaryButton())
                case .notInstalled, .failed:
                    Button("Descargar") { model.downloadModel() }.buttonStyle(PrimaryButton())
                default: EmptyView()
                }
            }
        }
    }

    private var externalSources: some View {
        let info = model.toolsInfo
        let updated = info?.ytDlpOrigin == .updated
        return SettingsGroup(title: "Fuentes externas",
                             note: "Importar desde enlace usa yt-dlp, Deno y ffmpeg, que van dentro de la app. Si YouTube cambia y las descargas fallan, actualiza yt-dlp.") {
            InfoRow(label: "yt-dlp") {
                Text(info == nil ? "comprobando…" : (info?.ytDlpVersion ?? "no disponible")).fontWeight(.semibold).foregroundStyle(TF.text2)
                if let o = info?.ytDlpOrigin { Chip(text: o == .updated ? "actualizada" : "embebida", kind: o == .updated ? .ok : .neutral) }
            }
            InfoRow(label: "Deno") { Text(info == nil ? "comprobando…" : (info?.denoVersion ?? "no disponible")).fontWeight(.semibold).foregroundStyle(TF.text2) }
            InfoRow(label: "ffmpeg") { Text(info == nil ? "comprobando…" : (info?.ffmpegVersion ?? "no disponible")).fontWeight(.semibold).foregroundStyle(TF.text2) }
            switch model.ytDlpUpdateStatus {
            case .idle: EmptyView()
            case .updating: ProgressView().progressViewStyle(.linear).tint(TF.accent)
            case .done(let m): Text(m).font(TF.body(13)).foregroundStyle(TF.ok)
            case .failed(let m): Text(m).font(TF.body(13)).foregroundStyle(TF.danger).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("Actualizar yt-dlp") { model.updateYtDlp() }.buttonStyle(PrimaryButton())
                    .disabled(model.ytDlpUpdateStatus == .updating)
                Button("Volver a la embebida") { model.revertYtDlp() }.buttonStyle(SecondaryButton())
                    .disabled(!updated || model.ytDlpUpdateStatus == .updating)
            }
        }
    }

    @ViewBuilder private func modelStatus(_ d: ModelDescriptor) -> some View {
        switch model.modelState {
        case .notInstalled:
            Text("Pendiente · \(Fmt.bytes(d.archiveBytes))").foregroundStyle(TF.accent).fontWeight(.semibold)
        case .downloading(let p): Text("Descargando \(Fmt.percent(p))").foregroundStyle(TF.accent).fontWeight(.semibold)
        case .verifying: Text("Verificando…").foregroundStyle(TF.accent).fontWeight(.semibold)
        case .installing: Text("Instalando…").foregroundStyle(TF.accent).fontWeight(.semibold)
        case .installed(_, let bytes): Text("Descargado · \(Fmt.bytes(bytes))").foregroundStyle(TF.ok).fontWeight(.semibold)
        case .failed(let m): Text("Error").foregroundStyle(TF.danger).fontWeight(.semibold).help(m)
        }
    }
}
