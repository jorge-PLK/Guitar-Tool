import Store
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 240)
            Group {
                switch model.section {
                case .library: LibraryView()
                case .backing: BackingView()
                case .record: RecordView()
                case .montage: MontageView()
                case .tab: TabScreen()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(TF.bg)
        .foregroundStyle(TF.text)
        .font(TF.body())
        .dropDestination(for: URL.self) { urls, _ in
            model.importFiles(urls); return true
        }
        .sheet(isPresented: Binding(get: { model.needsFolder }, set: { _ in })) {
            FirstRunSheet().interactiveDismissDisabled(true)
        }
        .sheet(item: $model.linkImport) { LinkImportSheet(session: $0) }
        .alert(item: $model.notice) { n in
            Alert(title: Text(n.title), message: Text(n.message), dismissButton: .default(Text("Aceptar")))
        }
        .alert("Este tema ya está en la biblioteca", isPresented: Binding(
            get: { model.duplicateID != nil }, set: { if !$0 { model.duplicateID = nil } })) {
            Button("Abrir el existente") {
                if let id = model.duplicateID { Task { await model.open(id) } }
                model.duplicateID = nil
            }
            Button("Cancelar", role: .cancel) { model.duplicateID = nil }
        } message: {
            Text("Ya hay un proyecto con el mismo audio (mismo SHA-256) o con el mismo vídeo de origen. ¿Quieres abrirlo?")
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text("Tone") + Text("Forge").foregroundStyle(TF.accent))
                .font(TF.display(22)).padding(.horizontal, 12).padding(.bottom, 20)
            navRow("Biblioteca", icon: "music.note.list", active: model.section == .library) { model.section = .library; model.detail = nil }
            navRow("Backing track", icon: "slider.vertical.3", active: model.section == .backing) { model.section = .backing }
            navRow("Tablatura", icon: "music.quarternote.3", active: model.section == .tab) { model.section = .tab }
            navRow("Grabar", icon: "record.circle", active: model.section == .record) { model.section = .record }
            navRow("Montaje", icon: "film", active: model.section == .montage) { model.section = .montage }
            Spacer()
            navRow("Ajustes", icon: "gearshape", active: model.section == .settings) { model.section = .settings }
            if let e = model.selectedEntry { selectedCard(e) }
            deviceCard
        }
        .padding(.horizontal, 16).padding(.vertical, 24)
        .frame(maxHeight: .infinity)
        .background(TF.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(TF.line).frame(width: 1) }
    }

    /// Tema seleccionado (Fase 7b, punto 6). Pulsarla abre la página del tema. El desplazamiento de los textos largos
    /// al pasar el ratón lo añade `MarqueeText`.
    private func selectedCard(_ e: LibraryEntryInfo) -> some View {
        let active = model.section == .library && model.detail?.id == e.id
        return Button { Task { await model.open(e.id) } } label: {
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: e.title, font: TF.body(14, .semibold), color: TF.text)
                MarqueeText(text: e.artist ?? "", font: TF.body(12), color: TF.muted)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? TF.accentBg : TF.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? TF.accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.top, 8)
        .help("Abrir la página del tema").accessibilityLabel("Tema seleccionado: \(e.title)")
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(model.audioDevice.chosenUID == nil || model.audioDevice.isConnected ? Color(hex: 0x4CC38A) : TF.muted).frame(width: 8, height: 8)
                Text(model.audioDevice.title).font(TF.body(14, .semibold))
            }
            Text(model.audioDevice.subtitle).font(TF.body(12)).foregroundStyle(TF.muted)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
        .padding(.top, 8)
    }

    private func navRow(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18)
                Text(title)
                Spacer()
            }
            .font(TF.body(14, .medium))
            .foregroundStyle(active ? TF.accent : TF.text2)
            .padding(.horizontal, 12).frame(height: 44)
            .background(active ? TF.accentBg : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct FirstRunSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Elige tu carpeta de proyectos").font(TF.display(24))
            Text("Cada tema vive en su propia carpeta, con sus stems, tomas y vídeo. Puedes cambiarla más tarde en Ajustes.")
                .foregroundStyle(TF.muted).fixedSize(horizontal: false, vertical: true)
            Text("Propuesta: ~/Music/ToneForge").font(TF.body(13)).foregroundStyle(TF.text2)
            HStack { Spacer(); Button("Elegir carpeta…") { model.chooseFirstRunFolder() }.buttonStyle(PrimaryButton()) }
        }
        .padding(28).frame(width: 480)
        .background(TF.card)
        .foregroundStyle(TF.text)
    }
}
