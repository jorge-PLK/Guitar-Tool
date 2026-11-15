import SwiftUI
import Store

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if let d = model.detail { ProjectDetailView(detail: d) } else { list }
        }
        .confirmationDialog(model.cleanupRequest?.title ?? "", isPresented: Binding(
            get: { model.cleanupRequest != nil }, set: { if !$0 { model.cleanupRequest = nil } }),
            titleVisibility: .visible, presenting: model.cleanupRequest) { r in
            Button("Limpiar \(Fmt.bytes(r.bytes))", role: .destructive) { model.performCleanup(r) }
            Button("Cancelar", role: .cancel) {}
        } message: { r in
            Text("Se borrarán tomas descartadas y stems por \(Fmt.bytes(r.bytes)). Los stems se pueden volver a generar.")
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            stats
            table
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40).padding(.vertical, 32)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Biblioteca").font(TF.display(32))
                Text("Tus temas, sus guitarras separadas y los rigs igualados.").foregroundStyle(TF.muted)
            }
            Spacer()
            Button("Importar tema") { model.pickAndImport() }.buttonStyle(PrimaryButton())
        }
    }

    private var stats: some View {
        HStack(spacing: 16) {
            stat("Temas", model.entries.count)
            stat("Rigs igualados", model.matchedRigs)
            stat("Tomas grabadas", model.recordedTakes)
            stat("Vídeos exportados", model.exportedVideos)
        }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(label.uppercased()).font(TF.body(12)).tracking(0.7).foregroundStyle(TF.muted)
                Text("\(value)").font(TF.display(28))
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private enum Col {
        static let guitars: CGFloat = 150, rigs: CGFloat = 70, takes: CGFloat = 70, state: CGFloat = 150, actions: CGFloat = 90
    }

    private func headCell(_ t: String, _ w: CGFloat? = nil) -> some View {
        Text(t.uppercased()).font(TF.body(12, .medium)).tracking(0.7).foregroundStyle(TF.muted)
            .frame(width: w, alignment: .leading).frame(maxWidth: w == nil ? .infinity : nil, alignment: .leading)
    }

    private var table: some View {
        Card {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    headCell("Tema / Artista")
                    headCell("Guitarras", Col.guitars)
                    headCell("Rigs", Col.rigs)
                    headCell("Tomas", Col.takes)
                    headCell("Estado", Col.state)
                    Color.clear.frame(width: Col.actions, height: 1).accessibilityHidden(true)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)

                ForEach(model.imports) { item in
                    Divider().overlay(TF.line)
                    HStack(spacing: 12) {
                        Text(item.name).font(TF.body(14, .semibold))
                        Spacer()
                        ProgressView(value: item.progress).tint(TF.accent).frame(width: 160)
                        Chip(text: "Importando \(Fmt.percent(item.progress))", kind: .working)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                }
                ForEach(model.entries, id: \.id) { e in
                    Divider().overlay(TF.line)
                    row(e)
                }
                if model.entries.isEmpty && model.imports.isEmpty {
                    Divider().overlay(TF.line)
                    VStack(spacing: 6) {
                        Text("Todavía no hay temas").font(TF.body(15, .semibold))
                        Text("Importa un wav, flac o mp3, o arrástralo a esta ventana.").foregroundStyle(TF.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 48)
                }
            }
        }
    }

    private func row(_ e: LibraryEntryInfo) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title).font(TF.body(14, .semibold))
                if let a = e.artist { Text(a).font(TF.body(13)).foregroundStyle(TF.muted) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(model.isSeparating(e) ? "Separando…" : "—").foregroundStyle(TF.text2)
                .frame(width: Col.guitars, alignment: .leading)
            Text(e.rigCount == 0 ? "—" : "\(e.rigCount)").foregroundStyle(TF.text2).frame(width: Col.rigs, alignment: .leading)
            Text(e.takeCount == 0 ? "—" : "\(e.takeCount)").foregroundStyle(TF.text2).frame(width: Col.takes, alignment: .leading)
            chip(e).frame(width: Col.state, alignment: .leading)
            Button("Abrir") { Task { await model.open(e.id) } }
                .buttonStyle(SecondaryButton(height: 36))
                .frame(width: Col.actions, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Separar de nuevo") { model.separate(e.id) }.disabled(model.isSeparating(e))
            if model.isSeparating(e) { Button("Cancelar separación") { model.cancelSeparation(e.id) } }
            Button("Limpiar…") { model.requestCleanup(id: e.id, title: "Limpiar «\(e.title)»") }
                .disabled(model.isSeparating(e))
            Button("Mostrar en Finder") { if let f = model.folder(of: e) { model.showInFinder(f) } }
        }
    }

    @ViewBuilder private func chip(_ e: LibraryEntryInfo) -> some View {
        switch e.separationState {
        case "queued": Chip(text: "En cola", kind: .neutral)
        case "running": Chip(text: "Separando \(Fmt.percent(model.separationProgress[e.id] ?? 0))", kind: .working)
        case "done": Chip(text: "Separado", kind: .ok)
        case "failed": Chip(text: "Error", kind: .error).help(model.failures[e.id] ?? "Error desconocido")
        default: Chip(text: "Importado", kind: .neutral)
        }
    }
}

struct ProjectDetailView: View {
    @Environment(AppModel.self) private var model
    let detail: ProjectDetail

    var body: some View {
        let song = detail.project.song
        VStack(alignment: .leading, spacing: 24) {
            Button { model.detail = nil } label: { Label("Biblioteca", systemImage: "chevron.left") }
                .buttonStyle(.plain).foregroundStyle(TF.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text(song.title).font(TF.display(32))
                if let a = song.artist { Text(a).foregroundStyle(TF.muted) }
            }
            Card {
                VStack(spacing: 0) {
                    info("Frecuencia", Fmt.rate(song.sampleRate))
                    info("Duración", Fmt.duration(song.duration))
                    info("Estado", stateText)
                }
                .padding(.vertical, 6)
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Stems").font(TF.display(18))
                    if detail.stems.isEmpty {
                        Text("Sin stems todavía.").foregroundStyle(TF.muted)
                    }
                    ForEach(detail.stems, id: \.kind) { s in
                        HStack {
                            Text(s.kind.rawValue)
                            Spacer()
                            Text(Fmt.bytes(s.bytes)).foregroundStyle(TF.muted)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 18)
            }
            Button("Mostrar en Finder") { model.showInFinder(detail.folder) }.buttonStyle(SecondaryButton())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40).padding(.vertical, 32)
    }

    private var stateText: String {
        switch detail.project.separation.state {
        case .none: "Importado"
        case .queued: "En cola"
        case .running: "Separando"
        case .done: "Separado"
        case .failed: "Error: \(detail.project.separation.error ?? "desconocido")"
        }
    }

    private func info(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(TF.muted); Spacer(); Text(v).fontWeight(.semibold) }
            .padding(.horizontal, 20).padding(.vertical, 10)
    }
}
