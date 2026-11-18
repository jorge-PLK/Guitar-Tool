import AppKit
import AudioKit
import Foundation
import ModelKit
import Observation
import SourceKit
import Store
import TabKit
import UniformTypeIdentifiers

/// Orquestación de la pantalla Tablatura (mini-spec Fase 5): pistas del proyecto, transcripción por pista con huella,
/// `tab/score.json`, edición con deshacer, sintetizado («Oír transcripción») y exportación a Guitar Pro.
@MainActor @Observable
final class TabController {
    /// Rebote del guardado de `tab/score.json` tras editar (como `StudySession`).
    static let saveDebounce = 0.5
    /// Rebote del re-sintetizado tras editar una pista que se está oyendo (mini-spec: «con rebote»).
    static let synthDebounce = 1.0
    /// Dos dígitos seguidos en menos de esto forman un traste de dos cifras («1» y «2» → 12).
    static let digitChain = 0.8
    /// Nombre del bucle A-B que crea la selección de tramo (menú de bucle).
    static let spanLoopName = "Selección"
    /// Cuerda inicial (1 = la más aguda) al añadir una nota sin cuerda elegida: la central.
    static func defaultString(of tuning: Tuning) -> Int { max(1, tuning.strings.count / 2) }

    enum Phase: Equatable {
        /// Aún no hay rejilla de compases (análisis del tema en curso, ausente o fallido).
        case waitingAnalysis
        /// Ningún stem de guitarra, bajo o batería con audio.
        case empty
        case working
        case ready
        case failed(String)
        /// `Project.tabSource == nil`: falta elegir entre Songsterr y la transcripción automática (mini-spec Fase 5b).
        case choosingSource
    }

    /// Paso de la hoja «Tablatura de Songsterr».
    enum ImportStage: Equatable {
        /// Resultados de la búsqueda (estado en `lookup`).
        case choosing
        case working(String)
        /// Lista de emparejamiento stem -> pista de Songsterr (estado en `plan`).
        case pairing
        case failed(SongsterrIssue)
    }

    enum SynthState: Equatable { case rendering, ready, failed(String) }

    struct Selection: Equatable {
        var trackID: String
        var point: GridPoint
        /// Cuerda de `TabScore` (1 = la más aguda); nil en batería.
        var string: Int?
    }

    struct Entry: Identifiable, Equatable {
        var id: String
        var name: String
        var kind: TabTrackKind
    }

    let session: StudySession
    let ctl: BackingController
    let host = AlphaTabHost()

    private(set) var phase: Phase = .working
    /// Pistas que se están transcribiendo ahora o esperan turno, en orden, con su progreso 0…1.
    private(set) var progress: [String: Double] = [:]
    private(set) var queued: [String] = []
    /// Avisos de la apertura (pistas rehechas, notas fuera de registro). Se descartan con `dismissNotices()`.
    private(set) var notices: [String] = []
    private(set) var editor: TabEditor?
    private(set) var entries: [Entry] = []
    var selectedTrackID: String? { didSet { if selectedTrackID != oldValue { trackChanged() } } }
    var editMode = false { didSet { if !editMode { selection = nil } } }
    private(set) var selection: Selection? {
        didSet { if selection != oldValue { graceMode = false }; updateSelectionMarker() }
    }
    /// Modo adorno (Fase 5c, tecla G): mientras dura, los dígitos cambian el traste de la nota de adorno de la nota
    /// seleccionada. Acaba al cambiar la selección o con cualquier tecla que no sea dígito, ⌫ o G.
    private(set) var graceMode = false
    private(set) var listening: Set<String> = []
    private(set) var synth: [String: SynthState] = [:]
    /// Mute y solo de las pistas extra (sin stem): solo viven en la sesión. Las pistas con stem usan la mezcla de Backing.
    private(set) var extraMuted: Set<String> = []
    private(set) var extraSolo: Set<String> = []
    /// Tramo de pulsos seleccionado (decisión 3 de la Fase 5c); su bucle A-B se llama `spanLoopName`.
    private(set) var span: TabSpan? { didSet { if span != oldValue { updateRangeMarker() } } }
    /// Mensaje breve del último error de edición o exportación.
    private(set) var flash: String?
    private(set) var webError: String?
    private(set) var rendered = false

    // Fuente de la tablatura (mini-spec Fase 5b, «Recorrido»).
    private(set) var sourceSheetOpen = false
    private(set) var importStage: ImportStage = .choosing
    private(set) var lookup: SongsterrLookup?
    /// Emparejamiento propuesto, editable con `setPairing` mientras `importStage == .pairing`.
    private(set) var plan: SongsterrImportPlan?
    /// Solo DEBUG (`--tab-songsterr`): no abre la hoja ni busca sola cuando falta la fuente.
    var suppressAutoSearch = false

    @ObservationIgnored private let modelStore: ModelStore
    @ObservationIgnored private var sources: [TabSource] = []
    /// Stem de voz del proyecto, al que van vinculadas todas las pistas `vocal` (Fase 5c, decisión 4). Fuera de `sources`:
    /// no se transcribe ni se empareja. nil: las voces son pistas extra.
    @ObservationIgnored private var vocalSource: TabSource?
    @ObservationIgnored private var alpha: AlphaTabScore?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var pairingsToKeep: [TabStemPairing]?
    /// Rejilla del metrónomo de la importación en curso (se guarda al aceptar) y pulsos preparados (para el resumen).
    @ObservationIgnored private var meterGrid: SongsterrMeterGrid?
    @ObservationIgnored private var preparedBeats: SongsterrPreparedBeats?
    @ObservationIgnored private lazy var client = SongsterrClient(loader: SongsterrWebLoader())
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var revision: [String: Int] = [:]
    @ObservationIgnored private var synthRevision: [String: Int] = [:]
    @ObservationIgnored private var synthTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var lastDigit: (value: Int, at: Date)?
    @ObservationIgnored private var lastCursorTime = -1.0
    @ObservationIgnored private var lastSpanStart = -1.0
    /// Pulso pulsado (extremo fijo del tramo) y pulso al que se arrastra o amplía (extremo móvil).
    @ObservationIgnored private var spanAnchor: TabSpan?
    @ObservationIgnored private var spanHead: TabSpan?
    @ObservationIgnored private var keyToken: Any?
    @ObservationIgnored private var terminateToken: NSObjectProtocol?

    init(session: StudySession, ctl: BackingController, modelStore: ModelStore) {
        self.session = session
        self.ctl = ctl
        self.modelStore = modelStore
        host.onEvent = { [weak self] in self?.handle($0) }
        ctl.onMixChanged = { [weak self] in self?.syncSynthMix() }
        terminateToken = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    var score: TabScore? { editor?.score }
    var layout: ProjectLayout { session.layout }
    var selectedTrack: TabTrack? {
        guard let id = selectedTrackID else { return nil }
        return score?.tracks.first { $0.id == id }
    }

    /// Compás más frecuente de la partitura («4/4») y tempo del tema para la cabecera: con Songsterr, el tempo escrito
    /// que más pulsos ocupa en la partitura; si no, `BeatGrid.bpm` del análisis (entero).
    var headerSummary: String? {
        guard let score, !score.bars.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for b in score.bars { counts["\(b.beatCount)/\(b.beatUnit)", default: 0] += 1 }
        let meter = counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? "4/4"
        if usesSongsterr {
            var beats: [Double: Int] = [:]
            for b in score.bars { beats[b.tempo, default: 0] += b.beatCount }
            if let written = beats.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key {
                return "\(meter) · \(Int(written)) BPM"
            }
        }
        guard let bpm = session.beats?.bpm else { return meter }
        return "\(meter) · \(Int(bpm.rounded())) BPM"
    }

    /// Stem de una pista: el suyo, o el de voz si es una pista `vocal` y el proyecto lo tiene; nil = pista extra.
    func source(of id: String) -> TabSource? {
        if let s = sources.first(where: { $0.id == id }) { return s }
        guard let vocalSource, score?.tracks.first(where: { $0.id == id })?.kind == .vocal else { return nil }
        return vocalSource
    }

    // MARK: Apertura y transcripción

    /// Idempotente: se llama al aparecer la pantalla y cuando llega el análisis.
    func start() {
        guard !started else { return }
        guard session.beats != nil else { phase = .waitingAnalysis; return }
        started = true
        phase = .working
        work = Task { [weak self] in await self?.open() }
    }

    private func open() async {
        guard let g = session.beats else { phase = .waitingAnalysis; started = false; return }
        let times = BeatTimes(beats: g.beats, downbeats: g.downbeats, beatsPerBar: g.beatsPerBar)
        let folder = layout.folder
        let exists = { (path: String) in FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path) }
        sources = session.project.tabSources(fileExists: exists)
        vocalSource = session.project.vocalTabSource(fileExists: exists)
        guard !sources.isEmpty else { phase = .empty; return }
        guard let choice = session.project.tabSource else { askForSource(); return }
        do {
            var score = try TabScore(beatTimes: times, duration: session.project.song.duration)
            let saved = Self.loadSaved(layout.tabScoreFile).flatMap { $0.formatVersion == score.formatVersion ? $0 : nil }
            let importedSaved = saved?.tracks.filter { $0.imported != nil } ?? []
            // Stems que transcribe la automática: todos, o solo los sin pareja si la fuente es Songsterr (decisión 4).
            var autoIDs = sources.map(\.id)
            var kept: [TabTrack] = []
            var redone: [String] = []
            if case .songsterr = choice {
                guard let saved, !importedSaved.isEmpty else { askForSource(); return }
                autoIDs = autoIDs.filter { !choice.importsSongsterr(forStem: $0) }
                // La rejilla es la de Songsterr, ya alineada con el audio: se conserva tal cual.
                score = saved
                kept = saved.tracks.filter { $0.imported == nil }
                score.tracks = importedSaved
            } else if let saved {
                let current = score
                if saved.bars == current.bars && saved.beats == current.beats {
                    kept = saved.tracks.filter { $0.imported == nil }
                } else {
                    // La rejilla cambió (otro análisis) o venía de Songsterr: las posiciones ya no valen, se rehacen todas.
                    redone = saved.tracks.filter { t in t.imported == nil && sources.contains { $0.id == t.id } }.map(\.name)
                }
            }
            kept.removeAll { !autoIDs.contains($0.id) }
            var fingerprints: [(id: String, fingerprint: TrackSourceFingerprint)] = []
            for s in sources where autoIDs.contains(s.id) {
                let fp = try TrackSourceFingerprint.of(fileAt: folder.appendingPathComponent(s.relativePath), path: s.relativePath,
                                                       modelVersion: Self.modelVersion(of: s.kind))
                fingerprints.append((s.id, fp))
            }
            let needs = fingerprints.filter { item in kept.first { $0.id == item.id }?.source != item.fingerprint }.map(\.id)
            for id in needs { if let t = kept.first(where: { $0.id == id }) { redone.append(t.name) } }
            // Una pista desfasada pierde sus ediciones; conserva solo la afinación elegida.
            var keptTuning: [String: Tuning] = [:]
            for id in needs { if let tu = kept.first(where: { $0.id == id })?.tuning { keptTuning[id] = tu } }
            kept.removeAll { needs.contains($0.id) }
            score.tracks += kept
            // Los nombres editados de las guitarras se aplican sin transcribir.
            for i in score.tracks.indices {
                if let s = sources.first(where: { $0.id == score.tracks[i].id }) { score.tracks[i].name = s.name }
            }
            editor = TabEditor(score: score)
            queued = needs
            if !redone.isEmpty {
                notices.append("Se han rehecho: \(redone.joined(separator: ", ")). Su audio cambió, así que se perdieron las ediciones de esas pistas.")
            }
            refreshEntries()
            if selectedTrackID == nil { selectedTrackID = entries.first?.id }
            let fpByID = Dictionary(uniqueKeysWithValues: fingerprints.map { ($0.id, $0.fingerprint) })
            if !queued.isEmpty {
                // Lo que ya estaba al día se ve mientras tanto.
                if !score.tracks.isEmpty { phase = .ready; pushScore() } else { phase = .working }
                try await transcribe(ids: queued, fingerprints: fpByID, keptTuning: keptTuning)
            }
            phase = .ready
            sortTracks()
            pushScore()
            listenExtras()
            saveNow()
        } catch is CancellationError {
            started = false
        } catch {
            phase = .failed(AppModel.describe(error))
        }
    }

    private func transcribe(ids: [String], fingerprints: [String: TrackSourceFingerprint],
                            keptTuning: [String: Tuning]) async throws {
        var pitched: BasicPitchTranscriber?
        var drums: DrumTranscriber?
        var shifted = 0, dropped = 0
        for id in ids {
            try Task.checkCancellation()
            guard let s = sources.first(where: { $0.id == id }), let fp = fingerprints[id] else { continue }
            let url = layout.url(relative: s.relativePath)
            progress[id] = 0
            guard var current = editor else { return }
            switch s.kind {
            case .drums:
                if drums == nil {
                    let m = try await modelStore.ensureInstalled(ModelCatalog.drumsADTOF.id) { _ in }
                    drums = DrumTranscriber(modelURL: m)
                }
                let hits = try await drums!.transcribe(url: url) { [weak self] p in
                    Task { @MainActor in self?.progress[id] = p }
                }
                let onsets = DrumCymbalSeries.refine(hits).compactMap { h in DrumPiece(rawValue: h.midi).map { DrumOnset(time: h.time, piece: $0) } }
                let track = TabTrackBuilder.drumTrack(id: id, name: s.name, source: fp, onsets: onsets, in: current.score)
                current = replace(track, in: current)
            case .vocal:
                continue   // las voces no se transcriben: vienen de Songsterr
            case .guitar, .bass:
                if pitched == nil {
                    let m = try await modelStore.ensureInstalled(ModelCatalog.transcriptionBasicPitch.id) { _ in }
                    pitched = BasicPitchTranscriber(modelURL: m)
                }
                let events = try await pitched!.transcribe(url: url)
                let kind: TabTrackKind = s.kind == .bass ? .bass : .guitar
                let tuning = keptTuning[id] ?? (kind == .bass ? Tuning.bass(.standard) : Tuning.guitar(.standard))
                let built = TabTrackBuilder.pitchedTrack(id: id, name: s.name, kind: kind, tuning: tuning, source: fp,
                                                         notes: events, in: current.score)
                shifted += built.report.shiftedOctave
                dropped += built.report.droppedNotes
                current = replace(built.track, in: current)
            }
            progress[id] = nil
            queued.removeAll { $0 == id }
            editor = current
            refreshEntries()
            if selectedTrackID == nil { selectedTrackID = id }
            // Cada pista se guarda al terminar: si se cierra la pantalla a medias, lo hecho no se repite.
            saveNow()
            if phase != .ready { phase = .ready }
            pushScore()
        }
        if shifted + dropped > 0 {
            var parts: [String] = []
            if shifted > 0 { parts.append("\(shifted) notas fuera del registro de la afinación se subieron o bajaron una octava") }
            if dropped > 0 { parts.append("\(dropped) se quitaron por no caber en las cuerdas") }
            notices.append("Transcripción: " + parts.joined(separator: " y ") + ".")
        }
    }

    private func replace(_ track: TabTrack, in editor: TabEditor) -> TabEditor {
        var score = editor.score
        score.upsert(track)
        return TabEditor(score: score)
    }

    private func sortTracks() {
        guard var score = editor?.score else { return }
        let order = sources.map(\.id)
        score.tracks.sort { (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99) }
        if score.tracks != editor?.score.tracks { editor = TabEditor(score: score) }
        refreshEntries()
    }

    private func refreshEntries() {
        let tracks = editor?.score.tracks ?? []
        let names = editor?.score.trackDisplayNames ?? []   // nombre vacío → instrumento (Fase 5c, decisión 5)
        entries = tracks.enumerated().map { Entry(id: $1.id, name: names[$0], kind: $1.kind) }
    }

    static func modelVersion(of kind: TabSource.Kind) -> String {
        kind == .drums ? ModelCatalog.drumsADTOF.version : ModelCatalog.transcriptionBasicPitch.version
    }

    static func loadSaved(_ url: URL) -> TabScore? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TabScore.self, from: data)
    }

    func dismissNotices() { notices = [] }

    /// Cierra la pantalla: cancela lo pendiente y guarda lo editado.
    func close() {
        work?.cancel()
        saveTask?.cancel()
        synthTasks.values.forEach { $0.cancel() }
        removeKeyMonitor()
        if let terminateToken { NotificationCenter.default.removeObserver(terminateToken) }
        terminateToken = nil
        if dirty { saveNow() }
    }

    // MARK: Fuente de la tablatura (mini-spec Fase 5b)

    /// Texto del menú «Fuente».
    var sourceLabel: String {
        switch session.project.tabSource {
        case .songsterr?: "Songsterr"
        case .automatic?: "Transcripción automática"
        case nil: "Sin elegir"
        }
    }

    var usesSongsterr: Bool {
        if case .songsterr? = session.project.tabSource { return true }
        return false
    }

    private func askForSource() {
        phase = .choosingSource
        if !suppressAutoSearch { openSourceSheet() }
    }

    /// Abre la hoja con la búsqueda por artista y título del proyecto (la lanza si aún no se hizo).
    func openSourceSheet() {
        if lookup == nil { lookup = SongsterrLookup(service: client) }
        importTask?.cancel()
        plan = nil
        importStage = .choosing
        sourceSheetOpen = true
        if lookup?.phase == .idle { search() }
    }

    func search() {
        let song = session.project.song
        Task { [weak self] in await self?.lookup?.search(artist: song.artist ?? "", title: song.title) }
    }

    func retrySearch() { Task { [weak self] in await self?.lookup?.retry() } }
    func select(songId: Int) { Task { [weak self] in await self?.lookup?.select(songId) } }
    func submitLink() { Task { [weak self] in await self?.lookup?.submitLink() } }

    func closeSourceSheet() {
        importTask?.cancel()
        sourceSheetOpen = false
        plan = nil
        importStage = .choosing
    }

    /// «Usar esta»: descarga las pistas del resultado marcado, las alinea y propone el emparejamiento.
    func useSelectedSong() {
        guard let song = lookup?.selectedSong else { return }
        beginImport(songId: song.songId, song: song, keeping: nil)
    }

    /// Menú «Fuente» > «Cambiar emparejamiento…»: lee otra vez el tema elegido y vuelve a proponer con lo ya elegido.
    func reviewPairing() {
        guard case let .songsterr(songId, _, pairings)? = session.project.tabSource else { return }
        beginImport(songId: songId, song: nil, keeping: pairings)
    }

    func retryImport() {
        guard let r = lastImport else { return }
        beginImport(songId: r.songId, song: r.song, keeping: r.keeping)
    }

    func backToResults() {
        importTask?.cancel()
        plan = nil
        importStage = .choosing
    }

    @ObservationIgnored private var lastImport: (songId: Int, song: SongsterrSong?, keeping: [TabStemPairing]?)?

    func beginImport(songId: Int, song: SongsterrSong?, keeping: [TabStemPairing]?) {
        importTask?.cancel()
        lastImport = (songId, song, keeping)
        plan = nil
        sourceSheetOpen = true
        importStage = .working(song == nil ? "Leyendo Songsterr…" : "Descargando pistas de Songsterr…")
        importTask = Task { [weak self] in await self?.runImport() }
    }

    /// Roles de stem con los que el alineador mide cada fuente (`TabSource.id` -> `SongsterrStemRole`).
    static func role(of source: TabSource) -> SongsterrStemRole {
        switch source.id {
        case "guitar-left": .guitarLeft
        case "guitar-right": .guitarRight
        case "guitar-lead": .guitarLead
        case "bass": .bass
        case "drums": .drums
        default: .guitar   // «guitar» y «guitar-rhythm»
        }
    }

    static func slotKind(_ k: TabSource.Kind) -> TabTrackKind {
        switch k {
        case .guitar: .guitar
        case .bass: .bass
        case .drums: .drums
        case .vocal: .vocal
        }
    }

    static func issue(for error: Error) -> SongsterrIssue {
        if error is SongsterrFormatError { return .formatChanged }
        if let a = error as? SongsterrAlignmentError, a == .nothingToAlign {
            return .other("Ninguna pista de guitarra o bajo de Songsterr se pudo medir con el audio del tema.")
        }
        return SongsterrIssue(error)
    }

    private func runImport() async {
        guard let req = lastImport, let g = session.beats else { return }
        do {
            let song: SongsterrSong
            if let s = req.song { song = s } else { song = try await client.song(songId: req.songId) }
            importStage = .working("Descargando pistas de Songsterr…")
            let dir = layout.songsterrCacheDir(songId: song.songId, revisionId: song.revisionId)
            let files = try await client.downloadTracks(song.tracks, to: dir)
            importStage = .working("Alineando con el audio…")
            // (Sin nombrar el tipo: `SongsterrTrack` existe en SourceKit y en TabKit.)
            let tracks = try song.tracks.map { t in
                guard let f = files[t.partId] else { throw SongsterrError.unknownFormat("pista \(t.partId)") }
                var c = try SongsterrTrackConverter.convert(try Data(contentsOf: f), isDrums: t.isDrums)
                c.songId = song.songId
                c.revisionId = song.revisionId
                c.partId = t.partId
                if !t.name.isEmpty { c.name = t.name }
                return c
            }
            let raw = BeatTimes(beats: g.beats, downbeats: g.downbeats, beatsPerBar: g.beatsPerBar)
            // Pulsos llevados a negras de Songsterr (pliegue de doble o mitad de tempo, pulsos perdidos o sobrantes)
            // ANTES de alinear; la rejilla del metrónomo sale de ellos.
            let prepared = SongsterrBeatGrid.writtenTempo(tracks).map { SongsterrBeatGrid.prepare(raw, writtenTempo: $0) }
            let times = prepared?.beats ?? raw
            var stems: [SongsterrStemRole: URL] = [:]
            for s in sources { stems[Self.role(of: s)] = layout.url(relative: s.relativePath) }
            if stems[.guitar] == nil,
               let full = session.project.stems.first(where: { $0.kind == .guitar && !$0.isEmpty }) {
                stems[.guitar] = layout.url(relative: full.file)
            }
            let stemURLs = stems
            let spans = session.sections.filter(\.isSolo).map { $0.start...$0.end }
            let (alignment, grid) = try await Task.detached(priority: .userInitiated) {
                let a = try SongsterrAligner.align(tracks: tracks, beats: times, stems: stemURLs, soloSpans: spans)
                let grid = try prepared.map {
                    try SongsterrBeatGrid.build(prepared: $0, tracks: tracks, alignment: a, drums: stemURLs[.drums])
                }
                return (a, grid)
            }.value
            try Task.checkCancellation()
            meterGrid = grid
            preparedBeats = prepared
            let slots = sources.map { SongsterrStemSlot(id: $0.id, name: $0.name, kind: Self.slotKind($0.kind), role: Self.role(of: $0)) }
            var proposal = SongsterrImportPlan(alignment: alignment, tracks: tracks, slots: slots,
                                               songId: song.songId, revisionId: song.revisionId)
            for p in req.keeping ?? [] {
                // Secciones de solo: cada una con la guardada que empiece a menos de 1 s.
                if let saved = p.solos, let current = proposal.assignment(for: p.stemID)?.solos {
                    for (k, s) in current.enumerated() {
                        guard let old = saved.first(where: { abs($0.start - s.span.lowerBound) < 1 }) else { continue }
                        let track = old.partId.flatMap { id in tracks.firstIndex { $0.partId == id } }
                        proposal.assign(stemID: p.stemID, solo: k, track: track)
                    }
                    continue
                }
                if let id = p.partId {
                    if let i = tracks.firstIndex(where: { $0.partId == id }) { proposal.assign(stemID: p.stemID, track: i) }
                } else {
                    proposal.assign(stemID: p.stemID, track: nil)
                }
            }
            plan = proposal
            importStage = .pairing
        } catch is CancellationError {
        } catch {
            importStage = .failed(Self.issue(for: error))
        }
    }

    /// Elige la pista de Songsterr de un stem (nil = transcripción automática).
    func setPairing(stemID: String, track: Int?) { plan?.assign(stemID: stemID, track: track) }

    /// Elige la pista de Songsterr de una sección de solo del stem solista (nil = sin notas de Songsterr en ella).
    func setSoloPairing(stemID: String, solo: Int, track: Int?) { plan?.assign(stemID: stemID, solo: solo, track: track) }

    func setAllAutomatic() { plan?.useAutomaticForAll() }

    /// «Aceptar»: crea la tablatura con lo emparejado, guarda la fuente y transcribe lo que quede sin pareja.
    func acceptPairing() {
        guard let plan else { return }
        let result = plan.build()
        let pairings = plan.assignments.map { a in
            TabStemPairing(stemID: a.stemID, partId: a.track.flatMap { plan.tracks[$0].partId },
                           solos: a.solos.isEmpty ? nil : a.solos.map { s in
                               TabSoloPairing(start: s.span.lowerBound, end: s.span.upperBound,
                                              partId: s.track.flatMap { plan.tracks[$0].partId }, confidence: s.confidence)
                           })
        }
        let choice = TabSourceChoice.songsterr(songId: plan.songId, revisionId: plan.revisionId, pairings: pairings)
        importTask?.cancel()
        work?.cancel()
        notices = plan.warnings
        editor = TabEditor(score: result.score)
        saveNow()
        closeSourceSheet()
        let grid = meterGrid.map {
            SongsterrGridFile(songId: plan.songId, revisionId: plan.revisionId, beats: $0.beats, downbeats: $0.downbeats,
                              writtenTempo: $0.writtenTempo)
        }
        Task { [weak self] in
            await self?.session.saveTabSource(choice, grid: grid)
            self?.ctl.refreshMetronome()
            self?.restart()
        }
    }

    /// «Transcribir automáticamente» (hoja) o menú «Fuente» > «Transcripción automática».
    func chooseAutomatic() {
        closeSourceSheet()
        work?.cancel()
        Task { [weak self] in
            await self?.session.saveTabSource(.automatic)
            self?.ctl.refreshMetronome()   // vuelve la rejilla del análisis
            self?.restart()
        }
    }

    private func restart() {
        work?.cancel()
        for id in Array(listening) { setListening(false, trackID: id) }
        started = false
        progress = [:]
        queued = []
        selection = nil
        selectedTrackID = nil
        phase = .working
        start()
    }

    // MARK: Guardado

    private func scheduleSave() {
        dirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.saveDebounce))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard let score = editor?.score else { return }
        saveTask?.cancel()
        do {
            try FileManager.default.createDirectory(at: layout.tabDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(score).write(to: layout.tabScoreFile, options: .atomic)
            dirty = false
        } catch {
            showFlash("No se pudo guardar la tablatura: \(error.localizedDescription)")
        }
    }

    // MARK: alphaTab

    private func handle(_ e: AlphaTabHost.Event) {
        switch e {
        case .ready: pushScore()
        case .rendered:
            rendered = true
            lastCursorTime = -1   // tras cada pintado el cursor se vuelve a colocar (y a mostrar)
            webError = nil
            updateSelectionMarker()
            updateRangeMarker()
        case .error(let m): webError = m
        case .beatClick(let track, let bar, let beat, let shift):
            guard let ref = alpha?.ref(track: track, bar: bar, beat: beat), alpha?.trackIDs[track] == selectedTrackID,
                  let id = selectedTrackID else { return }
            // ⇧clic con un pulso ya pulsado: amplía el tramo hasta aquí.
            if shift, spanAnchor != nil { extendSpan(to: ref); return }
            clearSpan()
            spanAnchor = Self.span(of: ref)
            // Mismo pulso ya seleccionado: no se toca la selección (ni su cuerda), pero el clic salta otra vez.
            if selection?.trackID == id, selection?.point == ref.start {
                if let score { ctl.seek(to: min(max(score.time(of: ref.start), 0), ctl.duration)) }
                return
            }
            select(id, ref.start, string: selection?.string)
        case .beatDrag(let track, let bar, let beat):
            guard spanAnchor != nil, let ref = alpha?.ref(track: track, bar: bar, beat: beat),
                  alpha?.trackIDs[track] == selectedTrackID else { return }
            extendSpan(to: ref)
        case .noteClick(let track, let bar, let beat, let s, _, let shift):
            guard !shift else { return }   // el ⇧clic sobre una nota ya lo trata `beatClick`
            guard let ref = alpha?.ref(track: track, bar: bar, beat: beat), alpha?.trackIDs[track] == selectedTrackID,
                  let id = selectedTrackID, let tuning = selectedTrack?.tuning else { return }
            select(id, ref.start, string: AlphaTabExporter.scoreString(forJSONString: s, stringCount: tuning.strings.count))
        }
    }

    /// Reconstruye el JSON de alphaTab con la partitura actual y la pinta (mantiene la pista y el desplazamiento).
    func pushScore() {
        guard let score = editor?.score, !score.tracks.isEmpty else { return }
        let song = session.project.song
        do {
            let a = try AlphaTabExporter.make(score: score, title: song.title, artist: song.artist ?? "")
            alpha = a
            let index = selectedTrackID.flatMap { a.trackIDs.firstIndex(of: $0) } ?? 0
            host.load(json: a.json, track: index)
        } catch {
            webError = error.localizedDescription
        }
    }

    private func trackChanged() {
        selection = nil
        clearSpan()
        spanAnchor = nil
        guard let id = selectedTrackID, let a = alpha, let i = a.trackIDs.firstIndex(of: id) else { return }
        host.load(json: a.json, track: i)
    }

    /// Mueve el cursor de alphaTab a `time` (20 veces por segundo desde la vista; solo si cambió).
    func updateCursor(time: Double, follow: Bool) {
        guard rendered, abs(time - lastCursorTime) > 0.001 else { return }
        lastCursorTime = time
        host.setCursorTime(time, follow: follow)
    }

    private func updateSelectionMarker() {
        guard rendered, let sel = selection, let score else { host.setSelection(bar: -1, fraction: 0); return }
        guard score.beats.indices.contains(sel.point.beat) else { return }
        let bar = score.beats[sel.point.beat].bar
        let b = score.bars[bar]
        let local = sel.point.absoluteTick - b.firstBeat * TabScore.ticksPerBeat
        host.setSelection(bar: bar, fraction: Double(local) / Double(b.beatCount * TabScore.ticksPerBeat))
    }

    // MARK: Tramo y bucle (decisión 3)

    private static func span(of ref: AlphaTabBeatRef) -> TabSpan {
        TabSpan(startTick: ref.start.absoluteTick, endTick: ref.start.absoluteTick + max(ref.length, 1))
    }

    /// Amplía el tramo desde el pulso pulsado hasta `ref` y lo pone como bucle.
    private func extendSpan(to ref: AlphaTabBeatRef) {
        guard let anchor = spanAnchor else { return }
        let head = Self.span(of: ref)
        spanHead = head
        setSpan(anchor.union(head))
    }

    private func setSpan(_ new: TabSpan) {
        guard new != span else { return }
        let first = span == nil
        span = new
        guard let score, let range = score.timeRange(of: new) else { return }
        let upper = min(range.upperBound, ctl.duration)
        guard upper > range.lowerBound else { return }
        let startChanged = first || lastSpanStart != range.lowerBound
        lastSpanStart = range.lowerBound
        ctl.setLoop(range.lowerBound...upper, name: Self.spanLoopName)
        if startChanged { ctl.seek(to: range.lowerBound) }
    }

    /// ⇧← / ⇧→: mueve el extremo móvil del tramo un pulso (en edición también).
    func extendSpan(forward: Bool) {
        guard let id = selectedTrackID, let alpha, let ti = alpha.trackIDs.firstIndex(of: id), let score else { return }
        let refs = alpha.beats[ti].flatMap { $0 }.sorted { $0.start < $1.start }
        if spanAnchor == nil {
            // Sin pulso pulsado: parte del punto seleccionado (o del cursor de reproducción).
            let point = selection?.trackID == id ? selection?.point
                                                 : score.tracks.first { $0.id == id }.map { score.nearestPoint(to: ctl.player.currentTime, in: $0) }
            guard let p = point?.absoluteTick,
                  let ref = refs.last(where: { $0.start.absoluteTick <= p }) ?? refs.first else { return }
            spanAnchor = Self.span(of: ref)
        }
        guard let anchor = spanAnchor else { return }
        let head = spanHead ?? anchor
        let next = forward ? refs.first { $0.start.absoluteTick >= head.endTick }
                           : refs.last { $0.start.absoluteTick < head.startTick }
        guard let next else { return }
        extendSpan(to: next)
    }

    /// Quita el tramo y, si el bucle activo era el suyo, también el bucle (Esc, «Sin bucle», cambio de pista).
    func clearSpan() {
        spanHead = nil
        span = nil
        if ctl.loopName == Self.spanLoopName { ctl.setLoop(nil) }
    }

    /// El bucle activo ya no es el del tramo (se eligió otro o ninguno): se quita solo el resaltado.
    func loopChanged() {
        guard span != nil, ctl.loopName != Self.spanLoopName else { return }
        spanHead = nil
        spanAnchor = nil
        span = nil
    }

    /// «Selección» en el menú de bucle: vuelve a poner el bucle del tramo y salta a su inicio.
    func applySpanLoop() {
        guard let span, let score, let range = score.timeRange(of: span) else { return }
        let upper = min(range.upperBound, ctl.duration)
        guard upper > range.lowerBound else { return }
        ctl.setLoop(range.lowerBound...upper, name: Self.spanLoopName)
        ctl.seek(to: range.lowerBound)
    }

    private func updateRangeMarker() {
        guard let span, let score, let a = score.barPosition(ofTick: span.startTick),
              let b = score.barPosition(ofTick: span.endTick, asEnd: true) else {
            host.setRange(startBar: -1, startFraction: 0, endBar: -1, endFraction: 0); return
        }
        host.setRange(startBar: a.bar, startFraction: a.fraction, endBar: b.bar, endFraction: b.fraction)
    }

    // MARK: Selección

    func select(_ trackID: String, _ point: GridPoint, string: Int?) {
        let track = score?.tracks.first { $0.id == trackID }
        var s = string
        if track?.kind == .drums { s = nil }
        else if s == nil, let tu = track?.tuning { s = Self.defaultString(of: tu) }
        // Con una nota en ese punto, la cuerda sigue a la nota si la cuerda elegida está vacía.
        if let track, track.kind != .drums {
            let notes = track.notes.filter { $0.start == point }
            if !notes.isEmpty, !notes.contains(where: { $0.string == s }) { s = notes.first?.string }
        }
        selection = Selection(trackID: trackID, point: point, string: s)
        if let score { ctl.seek(to: min(max(score.time(of: point), 0), ctl.duration)) }
    }

    var selectedNote: TabNote? {
        guard let sel = selection, let track = selectedTrack, track.id == sel.trackID else { return nil }
        return track.notes.first { $0.start == sel.point && $0.string == sel.string }
    }

    /// Texto de estado bajo la tablatura.
    var selectionSummary: String? {
        guard let sel = selection, let score, let track = selectedTrack, score.beats.indices.contains(sel.point.beat) else { return nil }
        let bar = score.beats[sel.point.beat].bar + 1
        let beat = score.beats[sel.point.beat].indexInBar + 1
        let place = "Compás \(bar), pulso \(beat)"
        if track.kind == .drums {
            let pieces = track.hits.filter { $0.at == sel.point }.map { Self.pieceName($0.piece) }
            return "\(place) · " + (pieces.isEmpty ? "sin golpes" : pieces.joined(separator: ", "))
        }
        if let n = selectedNote, let f = track.fret(of: n) {
            return "\(place) · cuerda \(n.string), traste \(f)"
        }
        return "\(place) · cuerda \(sel.string ?? 1), sin nota"
    }

    static func pieceName(_ p: DrumPiece) -> String {
        switch p {
        case .kick: "bombo"
        case .snare: "caja"
        case .hiHat: "charles"
        case .openHiHat: "charles abierto"
        case .tom: "tom"
        case .crash: "platos"
        }
    }

    // MARK: Edición

    private func step(at point: GridPoint, in track: TabTrack) -> Int {
        track.subdivisions.indices.contains(point.beat) ? track.subdivisions[point.beat].tickStep : 3
    }

    /// Aplica `body` al editor; un fallo se muestra como aviso breve y no cambia nada.
    private func edit(_ body: (inout TabEditor) throws -> Void) {
        guard var e = editor else { return }
        let before = e.score.tracks
        do {
            try body(&e)
        } catch let err as TabEditError {
            showFlash(Self.message(for: err)); return
        } catch {
            showFlash(error.localizedDescription); return
        }
        commit(e, before: before)
    }

    private func commit(_ e: TabEditor, before: [TabTrack]) {
        guard e.score.tracks != before else { return }
        editor = e
        for (old, new) in zip(before, e.score.tracks) where old != new {
            revision[new.id, default: 0] += 1
            if listening.contains(new.id) { scheduleSynth(new.id) }
        }
        scheduleSave()
        pushScore()
    }

    static func message(for e: TabEditError) -> String {
        switch e {
        case .unknownTrack, .unknownNote: "No hay nada seleccionado."
        case .wrongTrackKind: "Esa edición no vale para esta pista."
        case .stringOutOfRange: "No hay otra cuerda en esa dirección."
        case .fretOutOfRange: "El traste saldría de 0–24."
        case .stringOccupied: "Ya hay una nota en esa cuerda en ese punto."
        case .invalidPosition: "Esa posición no está en la rejilla de la pista."
        case .invalidDuration: "Esa duración no cabe."
        case .noTieOrigin: "No hay una nota anterior igual en esa cuerda a la que ligarla."
        }
    }

    func showFlash(_ text: String) {
        flash = text
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.flash = nil
        }
    }

    var canUndo: Bool { editor?.canUndo ?? false }
    var canRedo: Bool { editor?.canRedo ?? false }

    func undo() { stepHistory { $0.undo() } }
    func redo() { stepHistory { $0.redo() } }

    private func stepHistory(_ op: (inout TabEditor) -> Bool) {
        guard var e = editor else { return }
        let before = e.score.tracks
        guard op(&e) else { return }
        if let changed = zip(before, e.score.tracks).first(where: { $0 != $1 })?.1 {
            // La pista afectada pasa a ser la visible y su punto, el seleccionado.
            if selectedTrackID != changed.id { selectedTrackID = changed.id }
        }
        commit(e, before: before)
    }

    /// Dígito (0–9) con una nota seleccionada: cambia el traste; sin nota: la añade en el punto seleccionado.
    func typeDigit(_ d: Int) {
        guard let sel = selection, let track = selectedTrack, track.kind != .drums, let string = sel.string else { return }
        var fret = d
        if let last = lastDigit, Date().timeIntervalSince(last.at) < Self.digitChain, last.value * 10 + d <= Tuning.fretRange.upperBound {
            fret = last.value * 10 + d
        }
        lastDigit = (d, Date())
        if graceMode, let n = selectedNote, !n.techniques.graces.isEmpty {
            edit { try $0.setGraceFret(fret, trackID: track.id, noteID: n.id) }
        } else if let n = selectedNote {
            edit { try $0.setFret(fret, trackID: track.id, noteID: n.id) }
        } else {
            let dur = step(at: sel.point, in: track)
            edit { _ = try $0.addNote(trackID: track.id, string: string, fret: fret, at: sel.point, duration: dur) }
        }
    }

    /// ↑ / ↓: pasa la nota a la cuerda de arriba (más aguda) o de abajo conservando la altura; sin nota solo mueve la cuerda.
    func moveString(up: Bool) {
        guard let sel = selection, let track = selectedTrack, let tuning = track.tuning, let string = sel.string else { return }
        let target = up ? string - 1 : string + 1
        guard (1...tuning.strings.count).contains(target) else { showFlash(Self.message(for: .stringOutOfRange)); return }
        if let n = selectedNote {
            edit { try $0.moveNote(trackID: track.id, noteID: n.id, toString: target) }
            if editor?.score.tracks.first(where: { $0.id == track.id })?.notes.contains(where: { $0.id == n.id && $0.string == target }) == true {
                selection?.string = target
            }
        } else {
            selection?.string = target
        }
    }

    func deleteSelection() {
        guard let sel = selection, let track = selectedTrack else { return }
        if track.kind == .drums {
            let pieces = track.hits.filter { $0.at == sel.point }.map(\.piece)
            guard !pieces.isEmpty else { return }
            edit { e in for p in pieces { try e.setHit(p, at: sel.point, present: false, trackID: track.id) } }
        } else if let n = selectedNote {
            edit { try $0.deleteNote(trackID: track.id, noteID: n.id) }
        }
    }

    /// +/−: alarga o acorta la nota seleccionada un paso de la subdivisión de su pulso.
    func changeDuration(by sign: Int) {
        guard let track = selectedTrack, let n = selectedNote else { return }
        let st = step(at: n.start, in: track)
        edit { try $0.setDuration(n.duration + sign * st, trackID: track.id, noteID: n.id) }
    }

    /// Batería: pone o quita el golpe de `piece` en el punto seleccionado.
    func toggleHit(_ piece: DrumPiece) {
        guard let sel = selection, let track = selectedTrack, track.kind == .drums else { return }
        let present = !track.hits.contains { $0.piece == piece && $0.at == sel.point }   // también el golpe fantasma
        edit { try $0.setHit(piece, at: sel.point, present: present, trackID: track.id) }
    }

    /// Teclas de adornos (decisión 6 de la Fase 5c): conmuta `ornament` en todas las notas (o golpes de batería) del
    /// tramo seleccionado o, sin tramo, en la nota (o los golpes) del punto seleccionado. Se guarda, se redibuja y
    /// vuelve a sintetizar la pista si se oye (`commit`). Las pistas de voz no tienen cuerdas: no hacen nada.
    func toggleOrnament(_ ornament: TabOrnament) {
        guard let track = selectedTrack, track.kind != .vocal, let e = editor else { return }
        if track.kind == .drums {
            let points = span.map { e.hitPoints(in: $0, trackID: track.id) } ?? selection.map { [$0.point] } ?? []
            guard !points.isEmpty else { showFlash("No hay golpes seleccionados."); return }
            edit { try $0.toggle(ornament, trackID: track.id, hitPoints: points) }
        } else {
            let ids = span.map { e.noteIDs(in: $0, trackID: track.id) } ?? selectedNote.map { [$0.id] } ?? []
            guard !ids.isEmpty else { showFlash("No hay ninguna nota seleccionada."); return }
            edit { try $0.toggle(ornament, trackID: track.id, noteIDs: ids) }
            graceMode = ornament == .grace && selectedNote?.techniques.graces.isEmpty == false
        }
    }

    /// «Añadir nota»: en el punto de la rejilla más cercano al cursor de reproducción, traste 0 en la cuerda elegida.
    func addNoteAtCursor() {
        guard let score, let track = selectedTrack, track.kind != .drums, let tuning = track.tuning else { return }
        let point = score.nearestPoint(to: ctl.player.currentTime, in: track)
        let string = selection?.trackID == track.id ? selection?.string ?? Self.defaultString(of: tuning) : Self.defaultString(of: tuning)
        let dur = step(at: point, in: track)
        edit { _ = try $0.addNote(trackID: track.id, string: string, fret: 0, at: point, duration: dur) }
        selection = Selection(trackID: track.id, point: point, string: string)
    }

    /// ← / →: siguiente o anterior punto de la rejilla de la pista.
    func moveSelection(forward: Bool) {
        guard let track = selectedTrack, let score else { return }
        let current = selection?.point ?? score.nearestPoint(to: ctl.player.currentTime, in: track)
        var tick = current.absoluteTick
        if forward {
            tick += step(at: current, in: track)
        } else {
            tick -= 1
            let b = max(0, tick / TabScore.ticksPerBeat)
            let st = track.subdivisions.indices.contains(b) ? track.subdivisions[b].tickStep : 3
            tick -= (tick % TabScore.ticksPerBeat) % st
        }
        tick = min(max(0, tick), score.totalTicks - 1)
        let p = GridPoint(absoluteTick: tick)
        let b = p.beat
        let st = track.subdivisions.indices.contains(b) ? track.subdivisions[b].tickStep : 3
        let snapped = GridPoint(beat: b, tick: (p.tick / st) * st)
        select(track.id, snapped, string: selection?.string)
        host.setCursorTime(score.time(of: snapped), follow: true)
    }

    /// Última afinación personalizada de cada pista, para poder volver a ella desde el selector tras elegir un preset.
    private var customTunings: [String: Tuning] = [:]

    /// Afinación personalizada disponible para la pista: la actual si lo es, o la guardada al salir de ella.
    func customTuning(of track: TabTrack) -> Tuning? {
        if let t = track.tuning, t.preset == .custom { return t }
        return customTunings[track.id]
    }

    func setTuning(_ preset: TuningPreset, trackID: String) {
        guard let track = score?.tracks.first(where: { $0.id == trackID }), track.kind != .drums else { return }
        if let current = track.tuning, current.preset == .custom { customTunings[trackID] = current }
        let tuning: Tuning
        if preset == .custom {
            guard let saved = customTunings[trackID] else { return }
            tuning = saved
        } else {
            tuning = track.kind == .bass ? Tuning.bass(preset) : Tuning.guitar(preset)
        }
        guard tuning != track.tuning else { return }
        var report = TabBuildReport()
        edit { report = try $0.setTuning(tuning, trackID: trackID) }
        if report.shiftedOctave + report.droppedNotes > 0 {
            showFlash("\(report.shiftedOctave) notas se movieron una octava y \(report.droppedNotes) se quitaron por no caber en la afinación.")
        }
        selection = nil
    }

    static func tuningName(_ p: TuningPreset) -> String {
        switch p {
        case .standard: "Estándar"
        case .halfStepDown: "Medio tono abajo"
        case .wholeStepDown: "Un tono abajo"
        case .dropD: "Drop D"
        case .custom: "Personalizada"
        }
    }

    // MARK: Teclado de edición

    func installKeyMonitor() {
        guard keyToken == nil else { return }
        keyToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }
    }

    func removeKeyMonitor() {
        if let keyToken { NSEvent.removeMonitor(keyToken) }
        keyToken = nil
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        guard phase == .ready, !(NSApp.keyWindow?.firstResponder is NSText) else { return false }
        let mods = e.modifierFlags.intersection([.command, .control, .option, .shift])
        let ch = e.charactersIgnoringModifiers ?? ""
        // Esc quita el tramo seleccionado y su bucle, en lectura y en edición.
        if e.keyCode == 53, mods.isEmpty, span != nil { clearSpan(); return true }
        guard editMode else { return false }
        if graceMode, !(e.keyCode == 51 || e.keyCode == 117 || ch.lowercased() == "g" || (mods.isEmpty && Int(ch) != nil)) {
            graceMode = false
        }
        if mods == .command, ch == "z" { undo(); return true }
        if mods == [.command, .shift], ch == "z" { redo(); return true }
        if mods == .option, ch.lowercased() == "y", selectedTrack?.kind != .drums {
            toggleOrnament(.artificialHarmonic); return true
        }
        guard mods.isEmpty || mods == .shift else { return false }
        switch e.keyCode {
        case 126: moveString(up: true); return true
        case 125: moveString(up: false); return true
        case 123: if mods == .shift { extendSpan(forward: false) } else { moveSelection(forward: false) }; return true
        case 124: if mods == .shift { extendSpan(forward: true) } else { moveSelection(forward: true) }; return true
        case 51, 117: deleteSelection(); return true
        case 53: selection = nil; return true
        default: break
        }
        if mods.isEmpty, let d = Int(ch), ch.count == 1 { typeDigit(d); return true }
        switch ch {
        case "+", "=": changeDuration(by: 1); return true
        case "-": changeDuration(by: -1); return true
        default: break
        }
        if mods.isEmpty, selectedTrack?.kind == .drums {
            switch ch.lowercased() {
            case "b": toggleHit(.kick); return true
            case "c": toggleHit(.snare); return true
            case "h": toggleHit(.hiHat); return true
            case "t": toggleHit(.tom); return true
            case "p": toggleHit(.crash); return true
            default: break
            }
        }
        if let o = Self.ornament(forKey: ch, shift: mods == .shift, drums: selectedTrack?.kind == .drums) {
            toggleOrnament(o); return true
        }
        return false
    }

    /// Tabla «Teclas (modo edición)» de la Fase 5c. En batería solo valen F, O, `;` y `:` (B C H T P son golpes y se
    /// tratan antes); en pistas de guitarra y bajo, el resto. Las letras van sin ⇧, salvo ⇧D y ⇧U; los signos valen con
    /// o sin ⇧ (según el teclado).
    static func ornament(forKey ch: String, shift: Bool, drums: Bool) -> TabOrnament? {
        switch ch {
        case ";": return .accent
        case ":": return .heavyAccent
        case "o": return shift ? nil : .ghost
        default: break
        }
        if drums { return ch == "f" && !shift ? .flam : nil }
        switch ch {
        case "!": return .staccato
        case ")": return .tapping
        case "D": return .pickDown
        case "U": return .pickUp
        default: break
        }
        if shift { return nil }
        switch ch {
        case "p": return .palmMute
        case "i": return .letRing
        case "h": return .hammerPull
        case "s": return .slide
        case "b": return .bend
        case "v": return .vibrato
        case "w": return .whammyVibrato
        case "x": return .dead
        case "y": return .naturalHarmonic
        case "g": return .grace
        case "l": return .tie
        default: return nil
        }
    }

    // MARK: Oír transcripción

    func isListening(_ id: String) -> Bool { listening.contains(id) }

    static func synthPlayerID(_ id: String) -> String { "tab-\(id)" }

    func setListening(_ on: Bool, trackID: String) {
        guard score?.tracks.contains(where: { $0.id == trackID }) == true else { return }
        let src = source(of: trackID)   // nil en las pistas extra de Songsterr: solo suena la transcripción
        if on {
            listening.insert(trackID)
            if synthRevision[trackID] == revision[trackID, default: 0], synth[trackID] == .ready {
                activateSynth(trackID, src)
            } else {
                renderSynth(trackID) { [weak self] in self?.activateSynth(trackID, src) }
            }
        } else {
            listening.remove(trackID)
            synthTasks[trackID]?.cancel()
            // Con varias pistas de voz sobre el mismo stem, este solo vuelve a sonar cuando ninguna está en transcripción.
            if let src { ctl.setSubstituted(src.playerTrackID, stemStaysSubstituted(src)) }
            syncSynthMix()
        }
    }

    private func stemStaysSubstituted(_ src: TabSource) -> Bool {
        entries.contains { listening.contains($0.id) && synth[$0.id] == .ready && source(of: $0.id)?.id == src.id }
    }

    private func activateSynth(_ trackID: String, _ src: TabSource?) {
        guard listening.contains(trackID) else { return }
        if let src { ctl.setSubstituted(src.playerTrackID, true) }
        syncSynthMix()
    }

    // MARK: Mute y solo por pista (decisión 2) y selector global (decisión 2b)

    private func mixState(_ trackID: String) -> (muted: Bool, solo: Bool) {
        if let src = source(of: trackID), let m = ctl.mix(ofPlayerTrack: src.playerTrackID) { return (m.muted, m.solo) }
        return (extraMuted.contains(trackID), extraSolo.contains(trackID))
    }

    func isMuted(_ trackID: String) -> Bool { mixState(trackID).muted }
    func isSolo(_ trackID: String) -> Bool { mixState(trackID).solo }
    var anySolo: Bool { ctl.anyStemSolo || !extraSolo.isEmpty }
    /// Misma regla de atenuación que el mezclador de Backing.
    func isDimmed(_ trackID: String) -> Bool { isMuted(trackID) || (anySolo && !isSolo(trackID)) }

    func toggleMute(trackID: String) {
        if let src = source(of: trackID) { ctl.toggleMute(playerTrack: src.playerTrackID); return }
        if extraMuted.contains(trackID) { extraMuted.remove(trackID) } else { extraMuted.insert(trackID) }
        syncSynthMix()
    }

    func toggleSolo(trackID: String) {
        if let src = source(of: trackID) { ctl.toggleSolo(playerTrack: src.playerTrackID); return }
        if extraSolo.contains(trackID) { extraSolo.remove(trackID) } else { extraSolo.insert(trackID) }
        syncSynthMix()
    }

    /// La síntesis de cada pista sigue la mezcla de su pista: suena solo con «Oír transcripción», con su mute y su solo.
    /// (El stem sustituido lo mantiene silenciado `BackingController`.)
    func syncSynthMix() {
        for extra in ctl.extraTracks {
            let tid = String(extra.id.dropFirst(4))
            let m = mixState(tid)
            ctl.setExtraMuted(extra.id, !listening.contains(tid) || m.muted)
            ctl.player.setSolo(extra.id, m.solo)
        }
    }

    enum ListenMode: Equatable { case stems, transcription, mixed }

    /// Estado del selector «Stems / Transcripción» (decisión 2b): «Stems» = las pistas con stem suenan su stem y las extra
    /// su síntesis; «Transcripción» = todas su síntesis; cualquier otra combinación es mixta.
    var listenMode: ListenMode {
        let withStem = entries.filter { source(of: $0.id) != nil }
        let extras = entries.filter { source(of: $0.id) == nil }
        let stemsOn = withStem.filter { listening.contains($0.id) }.count
        let extrasOn = extras.allSatisfy { listening.contains($0.id) }
        if entries.isEmpty { return .stems }
        if stemsOn == withStem.count && extrasOn { return .transcription }
        if stemsOn == 0 && extrasOn { return .stems }
        return .mixed
    }

    /// «Transcripción»: todas las pistas a su síntesis. «Stems»: las pistas con stem a su stem y las extra (que no
    /// tienen stem) a su síntesis; para callar una extra basta su M. Las síntesis que faltan se pintan en segundo plano
    /// (`synthProgress`).
    func setAllListening(_ on: Bool) {
        for e in entries {
            let target = on || source(of: e.id) == nil
            if target != listening.contains(e.id) { setListening(target, trackID: e.id) }
        }
    }

    /// Estado inicial de «Stems» (decisión 2b): las pistas extra (sin stem) suenan siempre con su síntesis. Se aplica al
    /// quedar lista la partitura; `restart()` (cambio de fuente o de emparejamiento) vacía `listening` y vuelve a pasar
    /// por aquí, así una pista que gana stem vuelve a su stem y una que lo pierde pasa a su síntesis.
    private func listenExtras() {
        for e in entries where source(of: e.id) == nil && !listening.contains(e.id) { setListening(true, trackID: e.id) }
    }

    /// Pistas oídas con su síntesis lista y total de las oídas, mientras alguna se está pintando.
    var synthProgress: (done: Int, total: Int)? {
        let heard = entries.map(\.id).filter { listening.contains($0) }
        guard heard.contains(where: { synth[$0] == .rendering }) else { return nil }
        return (heard.filter { synth[$0] == .ready }.count, heard.count)
    }

    private func scheduleSynth(_ trackID: String) {
        synthTasks[trackID]?.cancel()
        synthTasks[trackID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.synthDebounce))
            guard !Task.isCancelled, let self else { return }
            self.renderSynth(trackID) { [weak self] in self?.activateSynth(trackID, self?.source(of: trackID)) }
        }
    }

    /// Renderiza la pista al WAV de `cache/tab/`, lo carga en el reproductor como pista extra y llama a `done`.
    private func renderSynth(_ trackID: String, done: @escaping @MainActor () -> Void) {
        guard let score, let track = score.tracks.first(where: { $0.id == trackID }) else { return }
        guard let sf = Bundle.main.url(forResource: "sonivox", withExtension: "sf2", subdirectory: "alphaTab/soundfont") else {
            synth[trackID] = .failed("Falta el soundfont en la app"); showFlash("Falta el soundfont de alphaTab en la app."); return
        }
        synth[trackID] = .rendering
        let rev = revision[trackID, default: 0]
        let url = layout.tabSynthURL(trackID: trackID)
        let rate = session.project.song.sampleRate
        let duration = ctl.duration
        let renderer = TabSynthRenderer(soundFontURL: sf)
        synthTasks[trackID]?.cancel()
        synthTasks[trackID] = Task { [weak self] in
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try await renderer.render(track: track, in: score, sampleRate: rate, duration: duration, to: url)
                guard !Task.isCancelled, let self else { return }
                self.synthRevision[trackID] = rev
                self.synth[trackID] = .ready
                self.attachSynth(trackID, url: url)
                done()
            } catch is CancellationError {
            } catch {
                self?.synth[trackID] = .failed(error.localizedDescription)
                self?.listening.remove(trackID)
                self?.showFlash("No se pudo sintetizar la pista: \(error.localizedDescription)")
            }
        }
    }

    /// Añade (o recarga) el WAV sintetizado como pista del reproductor, conservando posición y reproducción.
    private func attachSynth(_ trackID: String, url: URL) {
        let id = Self.synthPlayerID(trackID)
        if !ctl.extraTracks.contains(where: { $0.id == id }) { ctl.extraTracks.append(Track(id: id, url: url)) }
        let t = ctl.player.currentTime
        let playing = ctl.isPlaying
        ctl.loadTracks()
        ctl.seek(to: t)
        // Las demás pistas extra que no se oyen quedan silenciadas; mute y solo de cada una se reaplican.
        syncSynthMix()
        for tid in listening { if let s = source(of: tid) { ctl.setSubstituted(s.playerTrackID, true) } }
        if playing { ctl.togglePlay() }
    }

    // MARK: Exportar

    /// Nombre por defecto «Artista - Título.gp».
    static func exportFileName(title: String, artist: String?) -> String {
        let bad = CharacterSet(charactersIn: "/:\\")
        func clean(_ s: String) -> String { s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces) }
        let a = artist.map(clean) ?? ""
        return (a.isEmpty ? clean(title) : "\(a) - \(clean(title))") + ".gp"
    }

    func exportGuitarPro() {
        guard phase == .ready, alpha != nil else { return }
        let song = session.project.song
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gp") ?? .data]
        panel.nameFieldStringValue = Self.exportFileName(title: song.title, artist: song.artist)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await exportGuitarPro(to: url) }
    }

    func exportGuitarPro(to url: URL) async {
        do {
            // Sin parche de la batería: alphaTab 1.9.0 ya la exporta de forma que suena con RSE en Guitar Pro 8.
            let data = try await host.exportGP()
            try data.write(to: url, options: .atomic)
            showFlash("Guardado \(url.lastPathComponent).")
        } catch {
            showFlash("No se pudo exportar: \(error.localizedDescription)")
        }
    }

    /// Compás del punto seleccionado y su rango en segundos (para el bucle «Compás N»).
    var selectedBarRange: (bar: Int, range: ClosedRange<Double>)? {
        guard let sel = selection, let score, score.beats.indices.contains(sel.point.beat) else { return nil }
        let bar = score.beats[sel.point.beat].bar
        let start = max(0, score.bars[bar].start)
        let end = bar + 1 < score.bars.count ? score.bars[bar + 1].start : score.endTime
        guard end > start else { return nil }
        return (bar, start...min(end, max(ctl.duration, start + 0.001)))
    }

    #if DEBUG
    /// Capturas: espera a que acabe la transcripción y se pinte la partitura (máx. 10 min).
    func waitUntilSettled() async {
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            switch phase {
            case .ready where queued.isEmpty && rendered: return
            case .failed, .empty, .waitingAnalysis: return
            default: break
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// `--tab-songsterr <songId>`: búsqueda, página, descarga, alineación y plan con la propuesta tal cual, partitura,
    /// transcripción de lo que quede sin pareja y resumen en `summary`. Antes hay que vaciar `tabSource` y poner
    /// `suppressAutoSearch` (lo hace `TabContent`).
    func runSongsterrHeadless(songId: Int, summary: URL?) async {
        var lines: [String] = []
        func log(_ s: String) { lines.append(s); print("[tab-songsterr] \(s)") }
        func finish() { if let summary { try? lines.joined(separator: "\n").write(to: summary, atomically: true, encoding: .utf8) } }
        let t0 = Date()
        func lap() -> String { String(format: "%.1f s", Date().timeIntervalSince(t0)) }
        func wait(timeout: Double, until done: () -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if done() { return true }
                try? await Task.sleep(for: .milliseconds(200))
            }
            return false
        }
        guard await wait(timeout: 120, until: { phase == .choosingSource || phase == .empty || phase == .waitingAnalysis }),
              phase == .choosingSource else {
            log("ERROR: la pantalla no llegó a pedir fuente (fase \(phase))")
            finish(); return
        }
        let song = session.project.song
        do {
            let found = try await client.search(artist: song.artist ?? "", title: song.title)
            log("búsqueda «\(song.artist ?? "") - \(song.title)»: \(found.count) resultados (\(lap())); primero: \(found.first.map { "\($0.artist) - \($0.title) #\($0.songId)" } ?? "-"); \(found.contains { $0.songId == songId } ? "incluye" : "NO incluye") #\(songId)")
        } catch {
            log("búsqueda: ERROR \(Self.issue(for: error).message)")
        }
        beginImport(songId: songId, song: nil, keeping: nil)
        _ = await wait(timeout: 900) { if case .working = importStage { return false } else { return true } }
        guard importStage == .pairing, let plan else {
            if case .failed(let i) = importStage { log("importación: ERROR \(i.message)") } else { log("importación: sin resultado") }
            finish(); return
        }
        let al = plan.alignment
        if let p = preparedBeats {
            log("pulsos: tempo escrito \(Int(p.writtenTempo)), detectado \(String(format: "%.2f", p.detectedTempo)), pliegue \(p.fold.rawValue), +\(p.insertedBeats) −\(p.removedBeats) pulsos")
        } else {
            log("pulsos: sin tempo escrito en Songsterr, pulsos del análisis tal cual")
        }
        if let g = meterGrid {
            log("rejilla del metrónomo: \(g.beats.count) pulsos, \(g.downbeats.count) compases, \(g.anchoredBeats)/\(g.tabBeats) anclados a la batería")
        }
        log("alineación (\(lap())): desfase \(al.offsetBeats) pulsos, fino \(String(format: "%.3f", al.fineOffset)) s, bloques \(al.usesBlocks ? "sí" : "no"), \(al.structureWarnings.count) diferencias de estructura")
        log("tema: \(plan.tracks.count) pistas")
        for slot in plan.slots {
            let a = plan.assignment(for: slot.id)
            let conf = a?.confidence.map { String(format: "%.2f", $0) } ?? "-"
            if let i = a?.track { log("  \(slot.name) [\(slot.id)] -> «\(plan.tracks[i].name)» (pista \(i), confianza \(conf))") }
            else if let solos = a?.solos, !solos.isEmpty {
                log("  \(slot.name) [\(slot.id)] -> solo por secciones de solo:")
                for (k, s) in solos.enumerated() {
                    let pair = al.soloPairs.indices.contains(k) ? al.soloPairs[k] : nil
                    let others = (pair?.candidates ?? []).map { c in "\(plan.tracks[c.track].name) \(c.similarity.map { String(format: "%.3f", $0) } ?? "-")" }
                    log("    Solo \(k + 1) (\(SongsterrImportPlan.clockText(s.span.lowerBound))) <- \(s.track.map { "«\(plan.tracks[$0].name)»" } ?? "nada") (confianza \(s.confidence.map { String(format: "%.3f", $0) } ?? "-"), margen \(pair?.margin.map { String(format: "%.3f", $0) } ?? "-"); \(others.joined(separator: ", ")))")
                }
            }
            else { log("  \(slot.name) [\(slot.id)] -> transcripción automática") }
        }
        for i in plan.extraTracks { log("  extra: «\(plan.tracks[i].name)» (\(plan.tracks[i].kind))") }
        for w in plan.warnings { log("  aviso: \(w)") }
        acceptPairing()
        await waitUntilSettled()
        log("partitura (\(lap())): fase \(phase)")
        for t in score?.tracks ?? [] {
            log("  \(t.id) «\(t.name)» \(t.kind) \(t.notes.count) notas, \(t.hits.count) golpes, \(t.imported != nil ? "Songsterr" : "automática")")
        }
        for n in notices { log("  aviso: \(n)") }
        log("OK")
        finish()
    }

    /// `--tab-songsterr-sheet <songId>`: hoja de Songsterr en el paso de emparejamiento, para capturas.
    func openPairingForCapture(songId: Int) async {
        guard await waitForPhase({ $0 != .working && $0 != .waitingAnalysis }) else { return }
        beginImport(songId: songId, song: nil, keeping: nil)
        for _ in 0..<3000 {
            if case .working = importStage { try? await Task.sleep(for: .milliseconds(200)) } else { break }
        }
    }

    private func waitForPhase(_ ok: (Phase) -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if ok(phase) { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    /// Capturas: abre la pista `index`, activa la edición y selecciona el primer pulso con nota.
    func applyLaunchOptions(trackIndex: Int?, edit: Bool, listen: Bool) {
        if let i = trackIndex, entries.indices.contains(i) { selectedTrackID = entries[i].id }
        if listen, let id = selectedTrackID { setListening(true, trackID: id) }
        if edit {
            editMode = true
            if let t = selectedTrack {
                let p: GridPoint? = t.kind == .drums ? t.hits.first?.at : t.notes.first?.start
                if let p { select(t.id, p, string: t.notes.first?.string) }
            }
        }
    }
    #endif
}
