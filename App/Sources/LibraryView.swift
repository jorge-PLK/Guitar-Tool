import SwiftUI
import Store

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    /// Vista de la lista, recordada entre arranques (spec 7b, punto 5).
    @AppStorage("libraryGrouping") private var grouping = Grouping.songs.rawValue
    /// Buscador (punto 2): no se recuerda.
    @State private var query = ""
    /// Artista abierto en la vista Artistas (clave plegada, vacía = «Sin artista»). No se recuerda (spec 7b, 6c).
    @State private var openArtist: String?
    /// Tema que se corrige desde su fila (spec 7b, 6b).
    @State private var editing: SongEditTarget?
    @State private var hoveredRow: UUID?

    private let tileColumns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 20, alignment: .top)]
    enum Grouping: String { case songs, artists }

    var body: some View {
        @Bindable var model = model
        Group {
            if let d = model.detail { ProjectDetailView(detail: d) } else { list }
        }
        .sheet(item: $editing) { SongInfoSheet(target: $0) }
        // Cambiar de vista y volver deja la cuadrícula completa (spec 7b, 6c).
        .onChange(of: grouping) { openArtist = nil }
        .onChange(of: model.entries) {
            if let key = openArtist,
               !model.entries.contains(where: { LibraryFilter.fold($0.artist ?? "") == key }) { openArtist = nil }
        }
        .confirmationDialog(model.cleanupRequest?.title ?? "", isPresented: Binding(
            get: { model.cleanupRequest != nil }, set: { if !$0 { model.cleanupRequest = nil } }),
            titleVisibility: .visible, presenting: model.cleanupRequest) { r in
            Button("Limpiar \(Fmt.bytes(r.bytes))", role: .destructive) { model.performCleanup(r) }
            Button("Cancelar", role: .cancel) {}
        } message: { r in
            Text("Se borrarán tomas descartadas y stems por \(Fmt.bytes(r.bytes)). Los stems se pueden volver a generar.")
        }
        .confirmationDialog("¿Eliminar “\(model.trashRequest?.title ?? "")”?", isPresented: Binding(
            get: { model.trashRequest != nil }, set: { if !$0 { model.trashRequest = nil } }),
            titleVisibility: .visible, presenting: model.trashRequest) { r in
            Button("Mover a la Papelera") { model.performTrash(r) }.keyboardShortcut(.defaultAction)
            Button("Eliminar del disco", role: .destructive) { model.performDelete(r) }
            Button("Cancelar", role: .cancel) {}
        } message: { r in
            Text("Se va con el tema: \(r.contents). Si se está separando o está abierto en Backing, se detiene primero.\nEliminar del disco no se puede deshacer. La Papelera conserva la carpeta hasta que la vacíes.")
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            if grouping == Grouping.artists.rawValue && openArtist == nil {
                artistGrid
            } else {
                if grouping == Grouping.artists.rawValue { artistBar }
                ScrollView { table }
            }
        }
        .padding(.horizontal, 40).padding(.vertical, 32)
    }

    private var emptyMessage: some View {
        Text("Ningún tema coincide con «\(query.trimmingCharacters(in: .whitespaces))»")
            .foregroundStyle(TF.muted).frame(maxWidth: .infinity).padding(.vertical, 32)
    }

    /// Cuadrícula de artistas con algún tema que pase el filtro (spec 7b, 6c).
    @ViewBuilder private var artistGrid: some View {
        let groups = LibraryGrouping.byArtist(model.entries, query: query, title: \.title, artist: \.artist)
        if groups.isEmpty {
            if model.entries.isEmpty { Card { emptyLibrary } } else { emptyMessage }
            Spacer(minLength: 0)
        } else {
            ScrollView {
                LazyVGrid(columns: tileColumns, alignment: .leading, spacing: 24) {
                    ForEach(groups) { g in
                        ArtistTile(name: g.name, count: g.count) { openArtist = g.id }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var artistBar: some View {
        let name = model.entries.first { LibraryFilter.fold($0.artist ?? "") == openArtist }?.artist?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(spacing: 14) {
            Button { openArtist = nil } label: { Label("Artistas", systemImage: "chevron.left") }
                .buttonStyle(.plain).foregroundStyle(TF.accent)
            Text((name?.isEmpty ?? true) ? "Sin artista" : name!).font(TF.display(22))
            Spacer()
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 6) {
            Text("Todavía no hay temas").font(TF.body(15, .semibold))
            Text("Importa un wav, flac o mp3, arrástralo a esta ventana o pega un enlace de YouTube o Spotify.").foregroundStyle(TF.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Biblioteca").font(TF.display(32))
                Text("Tus temas y sus guitarras separadas.").foregroundStyle(TF.muted)
            }
            Spacer()
            if let p = model.playlistImport, let text = p.indicator {
                Button { model.openLinkImport() } label: {
                    HStack(spacing: 8) {
                        if p.isLive { ProgressView().controlSize(.small) } else { Image(systemName: "checkmark.circle") }
                        Text(text).font(TF.body(13, .medium))
                    }
                    .foregroundStyle(TF.accent)
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(TF.accentBg, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain).help("Ver la importación de la lista")
                .padding(.trailing, 8)
            }
            searchField.padding(.trailing, 8)
            Picker("Vista", selection: $grouping) {
                Text("Temas").tag(Grouping.songs.rawValue)
                Text("Artistas").tag(Grouping.artists.rawValue)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().padding(.trailing, 8)
            Button("Importar tema") { model.openLinkImport() }.buttonStyle(PrimaryButton())
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(TF.muted)
            TextField("Buscar tema o artista", text: $query).textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(TF.muted).accessibilityLabel("Borrar búsqueda")
            }
        }
        .padding(.horizontal, 12).frame(width: 240, height: 36)
        .background(TF.field, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TF.fieldLine))
    }

    private enum Col {
        static let guitars: CGFloat = 150, takes: CGFloat = 70, state: CGFloat = 150, actions: CGFloat = 170
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
                rows
                if model.entries.isEmpty && model.imports.isEmpty {
                    Divider().overlay(TF.line)
                    emptyLibrary
                }
            }
        }
    }

    @ViewBuilder private var rows: some View {
        let inArtist = grouping == Grouping.artists.rawValue
        let shown: [LibraryEntryInfo] = inArtist
            ? (LibraryGrouping.byArtist(model.entries, query: query, title: \.title, artist: \.artist)
                .first { $0.id == openArtist }?.items ?? [])
            : LibraryGrouping.sortedByTitle(model.entries, query: query, title: \.title, artist: \.artist)
        if !model.entries.isEmpty && shown.isEmpty {
            Divider().overlay(TF.line)
            emptyMessage
        } else {
            ForEach(shown, id: \.id) { e in
                Divider().overlay(TF.line)
                row(e, showArtist: !inArtist)
            }
        }
    }

    private func row(_ e: LibraryEntryInfo, showArtist: Bool = true) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title).font(TF.body(14, .semibold))
                if showArtist, let a = e.artist { Text(a).font(TF.body(13)).foregroundStyle(TF.muted) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(model.isSeparating(e) ? "Separando…" : "—").foregroundStyle(TF.text2)
                .frame(width: Col.guitars, alignment: .leading)
            Text(e.takeCount == 0 ? "—" : "\(e.takeCount)").foregroundStyle(TF.text2).frame(width: Col.takes, alignment: .leading)
            chip(e).frame(width: Col.state, alignment: .leading)
            HStack(spacing: 8) {
                TrashRowButton { model.requestTrash(e) }
                Button { if let f = model.folder(of: e) { model.showInFinder(f) } } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(SecondaryButton(height: 36)).help("Mostrar en Finder").accessibilityLabel("Mostrar en Finder")
                Button { editing = SongEditTarget(id: e.id, title: e.title, artist: e.artist ?? "") } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(SecondaryButton(height: 36)).help("Editar título y artista").accessibilityLabel("Editar título y artista")
            }
            .frame(width: Col.actions, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        // Seleccionada: verde (manda sobre el hover); hover: tinte sutil del acento. Pulsar la fila la selecciona.
        .background(model.backingTarget == e.id ? TF.ok.opacity(0.12)
                    : hoveredRow == e.id ? TF.accent.opacity(0.07) : .clear)
        .overlay(alignment: .leading) {
            if model.backingTarget == e.id { Rectangle().fill(TF.ok).frame(width: 3) }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hoveredRow = e.id } else if hoveredRow == e.id { hoveredRow = nil }
        }
        .onTapGesture { model.select(e.id) }
        .contextMenu {
            Button("Separar de nuevo") { model.separate(e.id) }.disabled(model.isSeparating(e))
            if model.isSeparating(e) { Button("Cancelar separación") { model.cancelSeparation(e.id) } }
            Button("Limpiar…") { model.requestCleanup(id: e.id, title: "Limpiar «\(e.title)»") }
                .disabled(model.isSeparating(e))
            Button("Mostrar en Finder") { if let f = model.folder(of: e) { model.showInFinder(f) } }
            Divider()
            Button("Eliminar…") { model.requestTrash(e) }
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
    @State private var editing = false
    @State private var draftTitle = ""
    @State private var draftArtist = ""
    @FocusState private var titleFocused: Bool

    private func startEditing() {
        draftTitle = detail.project.song.title
        draftArtist = detail.project.song.artist ?? ""
        editing = true
        titleFocused = true
    }

    private func saveEdit() {
        Task { if await model.updateSongInfo(id: detail.id, title: draftTitle, artist: draftArtist) { editing = false } }
    }

    @ViewBuilder private var titleBlock: some View {
        let song = detail.project.song
        if editing {
            VStack(alignment: .leading, spacing: 8) {
                SongInfoFields(title: $draftTitle, artist: $draftArtist, focus: $titleFocused, onSubmit: saveEdit)
                HStack(spacing: 10) {
                    Button("Guardar", action: saveEdit).buttonStyle(PrimaryButton())
                        .disabled(draftTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancelar") { editing = false }.buttonStyle(SecondaryButton(height: 36))
                        .keyboardShortcut(.cancelAction)
                }
            }
            .frame(maxWidth: 480, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(song.title).font(TF.display(32))
                    Button(action: startEditing) { Image(systemName: "pencil") }
                        .buttonStyle(.plain).foregroundStyle(TF.muted)
                        .help("Editar título y artista").accessibilityLabel("Editar título y artista")
                }
                if let a = song.artist { Text(a).foregroundStyle(TF.muted) }
            }
        }
    }

    var body: some View {
        let song = detail.project.song
        ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            Button { model.detail = nil } label: { Label("Biblioteca", systemImage: "chevron.left") }
                .buttonStyle(.plain).foregroundStyle(TF.accent)
            titleBlock
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
                            Text(s.isEmpty ? "vacío" : Fmt.bytes(s.bytes)).foregroundStyle(TF.muted)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 18)
            }
            Card {
                ProjectRecordingsView(detail: detail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 18)
            }
            HStack(spacing: 10) {
                if detail.project.separation.state == .done {
                    Button("Abrir en Backing track") { model.backingTarget = detail.id; model.section = .backing }
                        .buttonStyle(PrimaryButton())
                }
                Button("Mostrar en Finder") { model.showInFinder(detail.folder) }.buttonStyle(SecondaryButton())
                Spacer()
                Button("Eliminar…") {
                    if let e = model.entries.first(where: { $0.id == detail.id }) { model.requestTrash(e) }
                }
                .buttonStyle(.plain).foregroundStyle(TF.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40).padding(.vertical, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        #if DEBUG
        .onAppear { if model.options.detailEdit { startEditing() } }
        #endif
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

/// Botón cuadrado solo con icono, junto a «Abrir»: gris discreto y rojo al pasar el ratón.
private struct TrashRowButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash").font(.system(size: 14))
                .foregroundStyle(hovering ? TF.danger : TF.muted)
                .frame(width: 36, height: 36)
                .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(TF.fieldLine))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Eliminar…")
        .accessibilityLabel("Eliminar")
    }
}
