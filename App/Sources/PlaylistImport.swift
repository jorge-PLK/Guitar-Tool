import SourceKit
import SwiftUI

/// Recorrido de listas y álbumes (spec, «Fuentes externas» > «Listas»). Envuelve a `PlaylistImporter` y vive en
/// `AppModel`: la hoja se puede cerrar y la búsqueda o la cola siguen. Aquí están los pasos que ve la hoja, la parada
/// por límite o por yt-dlp roto, y el resumen.
@MainActor @Observable
final class PlaylistImportSession {
    struct Hooks {
        var updateYtDlp: () async throws -> YtDlpInstallInfo
        /// Identificadores que ya tiene la biblioteca (se pide antes de leer, buscar y descargar).
        var lookup: () async -> LibraryLookup
        /// Cierra la hoja y abre ese proyecto en la Biblioteca.
        var open: (UUID) -> Void
        /// `videoID` que el cierre de importación encontró ya importados (duplicados: no son fallos).
        var duplicateVideoIDs: () -> Set<String>
    }

    enum Step: Equatable {
        case loading
        /// Paso 1.
        case tracks
        /// Paso 2: buscando.
        case searching(done: Int, total: Int)
        /// Paso 2: revisión.
        case review
        /// Paso 3.
        case running
        case stopped(SourceError)
        /// Paso 4.
        case summary
        case error(SourceError)
    }

    let importer: PlaylistImporter
    private(set) var didRun = false
    var updating = false
    var alreadyLatest = false
    var updateError: String?
    #if DEBUG
    /// Capturas: fuerza el paso que se ve.
    var forcedStep: Step?
    #endif

    private let hooks: Hooks
    /// Lo que ya tiene la biblioteca; sirve a los cierres de SourceKit (síncronos) y a las filas «En la biblioteca».
    private(set) var library = LibraryLookup()
    /// Temas sin coincidencia por identificador pero con el mismo título y artista que uno de la biblioteca.
    private(set) var possible: [String: ExistingTrack] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?

    init(importer: PlaylistImporter, hooks: Hooks) {
        self.importer = importer
        self.hooks = hooks
        importer.isSpotifyIDInLibrary = { [weak self] in self?.library.spotify[$0] != nil }
        importer.isVideoIDInLibrary = { [weak self] in self?.library.video[$0] != nil }
    }

    // MARK: Lo que se ve

    var isYouTube: Bool { if case .youtube? = importer.link { true } else { false } }

    var step: Step {
        #if DEBUG
        if let forcedStep { return forcedStep }
        #endif
        switch importer.phase {
        case .idle, .loading: return .loading
        case .tracks: return .tracks
        case .searching(let d, let t): return .searching(done: d, total: t)
        case .review: return .review
        case .running: return .running
        case .stopped(let e): return .stopped(e)
        case .cancelled:
            if didRun { return .summary }
            return importer.items.contains { $0.chosen != nil || $0.status == .doubtful } ? .review : .tracks
        case .finished: return .summary
        case .failed(let e): return .error(e)
        }
    }

    /// Hay trabajo en marcha o parado a medias: la lista se conserva al cerrar la hoja.
    var isLive: Bool {
        switch importer.phase {
        case .loading, .searching, .running, .stopped: true
        default: false
        }
    }

    /// Texto del indicador de la Biblioteca (nil = nada que mostrar).
    var indicator: String? {
        switch importer.phase {
        case .loading: return "Leyendo la lista…"
        case .searching(let d, let t): return "Buscando \(min(d + 1, max(t, 1))) de \(t)"
        case .running:
            let t = importer.totals
            return "Importando \(min(t.selected - t.remaining + 1, max(t.selected, 1))) de \(t.selected)"
        case .stopped: return "Importación detenida"
        case .finished: return "Importación terminada"
        case .cancelled: return didRun ? "Importación cancelada" : nil
        default: return nil
        }
    }

    var selectedCount: Int { importer.items.filter(\.isSelected).count }

    /// Temas que irán a la cola: marcados, con candidato y sin terminar.
    var queuedCount: Int { importer.items.filter { $0.isSelected && $0.chosen != nil && !$0.status.isFinal }.count }

    var duplicateCount: Int {
        let dups = hooks.duplicateVideoIDs()
        return importer.items.filter { $0.status == .imported && $0.chosen.map { dups.contains($0.id) } == true }.count
    }

    // MARK: Acciones

    func start(_ text: String) {
        task?.cancel()
        task = Task {
            library = await hooks.lookup()
            try? await importer.load(text)
            var found: [String: ExistingTrack] = [:]
            for i in importer.items where i.status != .inLibrary {
                if let p = library.possible(title: i.track.title, artist: i.track.artist) { found[i.id] = p }
            }
            possible = found
        }
    }

    func openProject(_ id: UUID) { hooks.open(id) }

    /// «Marcar todos»: no marca los «posible repetido» (se marcan a mano).
    func selectAll() {
        importer.selectAll()
        for id in possible.keys { importer.setSelected(id, false) }
    }

    func cancelLoading() { task?.cancel() }

    /// Paso 1 a 2 (Spotify) o 1 a 3 (YouTube, sin candidatos).
    func continueFromTracks() {
        guard selectedCount > 0 else { return }
        if isYouTube { startQueue() } else { search() }
    }

    func search() {
        task = Task {
            library = await hooks.lookup()
            await importer.searchCandidates()
        }
    }

    func startQueue() {
        didRun = true
        task = Task {
            library = await hooks.lookup()
            await importer.run()
        }
    }

    func cancel() { importer.cancel() }

    /// «Reanudar» tras un límite de YouTube: sigue por donde iba (búsqueda o cola).
    func resume() {
        alreadyLatest = false
        if didRun { startQueue() } else { search() }
    }

    /// «Actualizar y reintentar» tras un yt-dlp roto: baja el nuevo y, si trae una versión más nueva, reanuda.
    func updateAndRetry() {
        guard case .stopped(let e) = step, !updating else { return }
        updating = true
        updateError = nil
        alreadyLatest = false
        task = Task {
            defer { updating = false }
            do {
                let info = try await hooks.updateYtDlp()
                if case .extractorBroken(let v?, _) = e, HelperLocator.compare(info.version, v) <= 0 {
                    alreadyLatest = true
                    return
                }
                resume()
            } catch {
                updateError = (error as? SourceError).map { SourceMessages.text(for: $0).detail } ?? error.localizedDescription
            }
        }
    }

    /// Los fallidos vuelven a la cola; los que fallaron buscando, a la búsqueda (y a la revisión).
    func retryFailed() {
        guard importer.retryFailed() > 0 else { return }
        let needsSearch = importer.items.contains { $0.isSelected && $0.status == .pending && $0.chosen == nil && $0.track.kind == .spotify }
        if needsSearch { search() } else { startQueue() }
    }
}

// MARK: - Vista

struct PlaylistImportView: View {
    let playlist: PlaylistImportSession
    let close: () -> Void
    /// Vuelve al campo vacío (descarta la lista).
    let discard: () -> Void

    private var importer: PlaylistImporter { playlist.importer }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch playlist.step {
            case .loading: loadingView
            case .tracks: tracksView
            case .searching(let d, let t): searchingView(d, t)
            case .review: reviewView
            case .running: queueView(stopped: nil)
            case .stopped(let e): queueView(stopped: e)
            case .summary: summaryView
            case .error(let e): errorView(e)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Piezas comunes

    private func listHeader(_ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(importer.name.isEmpty ? "Lista" : importer.name).font(TF.body(16, .semibold)).lineLimit(1)
            Text(subtitle).font(TF.body(13)).foregroundStyle(TF.muted)
        }
    }

    private func actions<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) { content() }.frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func table<C: View>(@ViewBuilder _ rows: () -> C) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) { rows() }
        }
        .frame(maxHeight: .infinity)
        .background(TF.bg.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(TF.fieldLine))
    }

    private func banner(_ text: String, error: Bool = false) -> some View {
        Text(text).font(TF.body(13)).foregroundStyle(error ? TF.danger : TF.accent)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
            .background(error ? TF.dangerBg : TF.accentBg, in: RoundedRectangle(cornerRadius: 8))
    }

    private func duration(_ s: Double?) -> String { s.map(Fmt.duration) ?? "—" }

    private func titleBlock(_ t: PlaylistTrack) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t.title).font(TF.body(14, .semibold)).lineLimit(1)
            Text(t.artist).font(TF.body(12)).foregroundStyle(TF.muted).lineLimit(1)
        }
    }

    private func rowBackground<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) {
            content().padding(.horizontal, 14).padding(.vertical, 8)
            Divider().overlay(TF.line)
        }
    }

    // MARK: Cargando

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) { ProgressView().controlSize(.small); Text("Leyendo la lista…") }
            Spacer()
            actions { Button("Cancelar") { playlist.cancelLoading(); discard() }.buttonStyle(SecondaryButton()) }
        }
    }

    // MARK: Paso 1: temas

    private var tracksView: some View {
        let t = importer.totals
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                listHeader("\(t.total) temas · \(t.selected) marcados" + (t.inLibrary > 0 ? " · \(t.inLibrary) ya en la biblioteca" : ""))
                Spacer()
                Button("Marcar todos") { playlist.selectAll() }.buttonStyle(SecondaryButton(height: 34))
                Button("Ninguno") { importer.selectNone() }.buttonStyle(SecondaryButton(height: 34))
            }
            if importer.mayBeTruncated {
                banner("Spotify devuelve como máximo 100 temas por lista: puede haber cortado esta. Si faltan temas, impórtalos desde su enlace.")
            }
            table {
                ForEach(importer.items) { trackRow($0) }
            }
            actions {
                Button("Cerrar") { close() }.buttonStyle(SecondaryButton())
                if playlist.isYouTube {
                    Button("Descargar y procesar (\(t.selected))") { playlist.continueFromTracks() }
                        .buttonStyle(PrimaryButton()).disabled(t.selected == 0)
                } else {
                    Button("Buscar en YouTube (\(t.selected))") { playlist.continueFromTracks() }
                        .buttonStyle(PrimaryButton()).disabled(t.selected == 0)
                }
            }
        }
    }

    private func trackRow(_ item: PlaylistItem) -> some View {
        let inLib = item.status == .inLibrary
        return rowBackground {
            HStack(spacing: 12) {
                if inLib {
                    Color.clear.frame(width: 20, height: 20)
                } else {
                    Button { importer.setSelected(item.id, !item.isSelected) } label: {
                        Image(systemName: item.isSelected ? "checkmark.square.fill" : "square").font(.system(size: 18))
                            .foregroundStyle(item.isSelected ? TF.accent : TF.muted)
                    }
                    .buttonStyle(.plain)
                }
                titleBlock(item.track).opacity(inLib ? 0.55 : 1)
                Spacer(minLength: 8)
                if inLib { Chip(text: "En la biblioteca", kind: .neutral) }
                if let p = playlist.possible[item.id] {
                    Chip(text: "Puede que ya lo tengas", kind: .working).help("Parecido a: \(p.title)")
                }
                Text(duration(item.track.durationSeconds)).font(TF.body(13)).foregroundStyle(TF.muted).frame(width: 48, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .onTapGesture { if !inLib { importer.setSelected(item.id, !item.isSelected) } }
        }
    }

    // MARK: Paso 2: búsqueda y revisión

    private func searchingView(_ done: Int, _ total: Int) -> some View {
        let current = importer.items.first { $0.status == .searching }?.track
        return VStack(alignment: .leading, spacing: 14) {
            listHeader("Buscando cada tema en YouTube")
            HStack {
                Text("Buscando \(min(done + 1, max(total, 1))) de \(total)")
                Spacer()
                Text(Fmt.percent(total == 0 ? 0 : Double(done) / Double(total))).foregroundStyle(TF.muted)
            }
            AccentBar(value: total == 0 ? 0 : Double(done) / Double(total))
            if let current { titleBlock(current) }
            Text("Nada se descarga todavía: después podrás revisar los candidatos.").font(TF.body(12)).foregroundStyle(TF.muted)
            Spacer()
            actions { Button("Cancelar") { playlist.cancel() }.buttonStyle(SecondaryButton()) }
        }
    }

    private var reviewItems: [PlaylistItem] { importer.items.filter { $0.isSelected && $0.status != .imported && $0.status != .inLibrary } }

    private var reviewView: some View {
        let items = reviewItems
        let proposed = items.filter { $0.status == .proposed }.count
        let doubtful = items.filter { $0.status == .doubtful }.count
        let skipped = items.filter { $0.status == .skipped }.count
        let unsearched = items.contains { $0.status == .pending && $0.chosen == nil && $0.track.kind == .spotify }
        return VStack(alignment: .leading, spacing: 14) {
            listHeader("\(proposed) con candidato · \(doubtful) dudosos · \(skipped) omitidos")
            banner("Revisa lo propuesto: nada se descarga hasta que pulses «Descargar y procesar». Los «dudosos» no tienen propuesta: elige uno o se omiten.")
            table {
                ForEach(items) { reviewRow($0) }
            }
            actions {
                Button("Cerrar") { close() }.buttonStyle(SecondaryButton())
                if unsearched { Button("Seguir buscando") { playlist.search() }.buttonStyle(SecondaryButton()) }
                Button("Descargar y procesar (\(playlist.queuedCount))") { playlist.startQueue() }
                    .buttonStyle(PrimaryButton()).disabled(playlist.queuedCount == 0)
            }
        }
    }

    private func reviewRow(_ item: PlaylistItem) -> some View {
        let doubtful = item.status == .doubtful
        return rowBackground {
            HStack(spacing: 12) {
                titleBlock(item.track).frame(width: 250, alignment: .leading)
                Text(duration(item.track.durationSeconds)).font(TF.body(12)).foregroundStyle(TF.muted).frame(width: 40, alignment: .trailing)
                candidateMenu(item)
                if doubtful { Chip(text: "dudoso", kind: .error) }
            }
            .padding(.vertical, doubtful ? 4 : 0)
            .background(doubtful ? TF.dangerBg.opacity(0.35) : .clear)
        }
    }

    private func candidateMenu(_ item: PlaylistItem) -> some View {
        let chosen = item.chosen.flatMap { c in item.candidates.first { $0.id == c.id } }
        return Menu {
            ForEach(item.candidates) { rc in
                if let e = playlist.library.video[rc.id] {
                    Button { } label: { Text(menuLabel(rc) + " · En la biblioteca") }.disabled(true)
                    Button { playlist.openProject(e.id) } label: { Text("Abrir «\(e.title)» en la biblioteca") }
                } else {
                    Button { importer.choose(rc.candidate, for: item.id) } label: {
                        Text(menuLabel(rc))
                    }
                }
            }
            if !item.candidates.isEmpty { Divider() }
            Button("Omitir este tema") { importer.clearCandidate(for: item.id) }
        } label: {
            HStack(spacing: 8) {
                if let c = item.chosen {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.title).font(TF.body(13, .medium)).lineLimit(1)
                        Text([c.channel, c.durationSeconds.map(Fmt.duration)].compactMap { $0 }.joined(separator: " · "))
                            .font(TF.body(11)).foregroundStyle(TF.muted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let d = chosen?.difference { Text(LinkImportSheet.signed(d)).font(TF.body(12, .medium)).foregroundStyle(TF.text2) }
                    if chosen?.isClose == true { Chip(text: "cercano", kind: .ok) }
                    if chosen?.isLive == true { Chip(text: "directo", kind: .neutral) }
                    if playlist.library.video[c.id] != nil { Chip(text: "En la biblioteca", kind: .neutral) }
                } else {
                    Text(placeholder(item)).font(TF.body(13)).foregroundStyle(item.status == .skipped ? TF.muted : TF.text2)
                    Spacer(minLength: 4)
                }
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(TF.muted)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TF.field, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(TF.fieldLine))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
    }

    private func placeholder(_ item: PlaylistItem) -> String {
        switch item.status {
        case .skipped: "Omitido"
        case .failed(let e): "Falló la búsqueda: " + SourceMessages.text(for: e).title
        case .pending: "Sin buscar"
        default: item.candidates.isEmpty ? "Sin resultados: omitir" : "Elige un candidato…"
        }
    }

    private func menuLabel(_ rc: RankedCandidate) -> String {
        var parts = [rc.candidate.title]
        if let ch = rc.candidate.channel { parts.append(ch) }
        if let d = rc.candidate.durationSeconds { parts.append(Fmt.duration(d)) }
        if let d = rc.difference { parts.append(LinkImportSheet.signed(d)) }
        if rc.isClose { parts.append("cercano") }
        if rc.isLive { parts.append("directo") }
        return parts.joined(separator: " · ")
    }

    // MARK: Paso 3: cola

    private func queueView(stopped: SourceError?) -> some View {
        let t = importer.totals
        let done = t.selected - t.remaining
        let rows = importer.items.filter(\.isSelected)
        return VStack(alignment: .leading, spacing: 14) {
            listHeader(stopped == nil ? "Descargando, importando y separando" : "Cola detenida")
            HStack {
                Text("\(done) de \(t.selected) temas")
                Spacer()
                Text(Fmt.percent(importer.queueProgress)).foregroundStyle(TF.muted)
            }
            AccentBar(value: importer.queueProgress)
            if let e = stopped {
                let m = SourceMessages.text(for: e)
                banner(m.title + ". " + (e == .rateLimited ? "No se reintenta sola: reanuda cuando quieras." : m.detail), error: true)
                if playlist.alreadyLatest {
                    banner("yt-dlp ya es la última versión: YouTube ha cambiado algo y hay que esperar a que se corrija. Lo ya importado se conserva.")
                }
                if let u = playlist.updateError { banner(u, error: true) }
            }
            table { ForEach(rows) { queueRow($0) } }
            actions {
                Button("Cerrar") { close() }.buttonStyle(SecondaryButton()).help("La cola sigue en segundo plano")
                if let e = stopped {
                    if e.suggestsYtDlpUpdate && !playlist.alreadyLatest {
                        Button(playlist.updating ? "Actualizando…" : "Actualizar y reintentar") { playlist.updateAndRetry() }
                            .buttonStyle(PrimaryButton()).disabled(playlist.updating)
                    } else if !e.suggestsYtDlpUpdate {
                        Button("Reanudar") { playlist.resume() }.buttonStyle(PrimaryButton())
                    }
                } else {
                    Button("Cancelar") { playlist.cancel() }.buttonStyle(SecondaryButton())
                }
            }
        }
    }

    private func queueRow(_ item: PlaylistItem) -> some View {
        rowBackground {
            HStack(spacing: 12) {
                titleBlock(item.track)
                Spacer(minLength: 8)
                switch item.status {
                case .downloading(let stage, let p):
                    Text(stage == .downloading ? "Descargando" + (p.map { " " + Fmt.percent($0) } ?? "…") : "Convirtiendo…")
                        .font(TF.body(12)).foregroundStyle(TF.accent)
                    AccentBar(value: stage == .downloading ? p : nil, height: 5).frame(width: 140)
                case .imported: Chip(text: "Importado", kind: .ok)
                case .skipped: Chip(text: "Omitido", kind: .neutral)
                case .inLibrary: Chip(text: "En la biblioteca", kind: .neutral)
                case .failed(let e): Chip(text: SourceMessages.text(for: e).title, kind: .error)
                default: Text("En cola").font(TF.body(12)).foregroundStyle(TF.muted)
                }
            }
        }
    }

    // MARK: Paso 4: resumen

    private var summaryView: some View {
        let t = importer.totals
        let dups = playlist.duplicateCount
        let failed = importer.items.filter { if case .failed = $0.status { true } else { false } }
        let cancelled = importer.phase == .cancelled
        return VStack(alignment: .leading, spacing: 14) {
            listHeader(cancelled ? "Cola cancelada: lo ya importado se conserva" : "Importación terminada")
            HStack(spacing: 12) {
                stat("Importados", t.imported - dups, TF.ok)
                stat("Omitidos", t.skipped, TF.text2)
                stat("Ya en la biblioteca", t.inLibrary + dups, TF.text2)
                stat("Fallidos", t.failed, t.failed > 0 ? TF.danger : TF.text2)
            }
            if t.imported - dups > 0 {
                Text("Los temas importados se están separando en stems; verás el avance en la Biblioteca.")
                    .font(TF.body(12)).foregroundStyle(TF.muted)
            }
            if failed.isEmpty {
                Spacer()
            } else {
                Text("FALLIDOS").font(TF.body(12, .medium)).tracking(0.7).foregroundStyle(TF.muted)
                table { ForEach(failed) { failedRow($0) } }
            }
            actions {
                Button("Cerrar") { close() }.buttonStyle(PrimaryButton())
                if cancelled && t.remaining > 0 {
                    Button("Reanudar (\(t.remaining))") { playlist.resume() }.buttonStyle(SecondaryButton())
                }
                if !failed.isEmpty {
                    Button("Reintentar fallidos (\(failed.count))") { playlist.retryFailed() }.buttonStyle(SecondaryButton())
                }
            }
        }
    }

    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(TF.body(11)).tracking(0.7).foregroundStyle(TF.muted)
            Text("\(value)").font(TF.display(26)).foregroundStyle(color)
        }
        .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
        .background(TF.field, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(TF.fieldLine))
    }

    private func failedRow(_ item: PlaylistItem) -> some View {
        rowBackground {
            HStack(alignment: .top, spacing: 12) {
                titleBlock(item.track).frame(width: 280, alignment: .leading)
                if case .failed(let e) = item.status {
                    let m = SourceMessages.text(for: e)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title).font(TF.body(13, .semibold)).foregroundStyle(TF.danger)
                        if !m.detail.isEmpty {
                            Text(m.detail).font(TF.body(12)).foregroundStyle(TF.muted).lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Error

    private func errorView(_ e: SourceError) -> some View {
        let m = SourceMessages.text(for: e)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(TF.danger)
                VStack(alignment: .leading, spacing: 6) {
                    Text(m.title).font(TF.body(15, .semibold))
                    Text(m.detail).font(TF.body(13)).foregroundStyle(TF.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            actions {
                Button("Cerrar") { close() }.buttonStyle(SecondaryButton())
                Button("Probar con otro enlace") { discard() }.buttonStyle(PrimaryButton())
            }
        }
    }
}
