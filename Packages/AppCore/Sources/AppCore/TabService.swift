import AudioKit
import Foundation
import ModelKit
import Store
import TabKit

// Tablatura (8.7): copia adaptada de `App/Sources/TabController.swift` (Mac) sin AppKit ni alphaTab embebido. La página
// pinta con `tf-bridge.js`; aquí viven pistas, transcripción, edición con deshacer, síntesis y mezcla. Songsterr (hoja,
// buscador, emparejamiento) NO se porta: solo se lee lo ya guardado en el proyecto.

/// Dónde se guarda la fuente de la tablatura elegida (`Library` en producción).
protocol TabSourceStoring: Sendable {
    func saveTabSource(_ choice: TabSourceChoice?, for id: UUID) async throws
}

extension Library: TabSourceStoring {}

struct QueueTabStore: TabSourceStoring {
    let jobs: JobEngine
    func saveTabSource(_ choice: TabSourceChoice?, for id: UUID) async throws {
        try await jobs.library().saveTabSource(choice, for: id)
    }
}

/// Salida de eventos segura entre hilos.
private final class TabOutbox: @unchecked Sendable {
    private let lock = NSLock()
    private var sink: @Sendable (String) -> Void = { _ in }
    func set(_ s: @escaping @Sendable (String) -> Void) { lock.withLock { sink = s } }
    func send(_ m: String) { lock.withLock { sink }(m) }
}

@MainActor
final class TabService {
    /// Rebote del guardado de `tab/score.json` tras editar (Mac: `TabController.saveDebounce`).
    static let saveDebounce = 0.5
    /// Rebote del re-sintetizado tras editar una pista que se oye (mini-spec Fase 5: «con rebote»).
    static let synthDebounce = 1.0
    /// Dos dígitos seguidos en menos de esto forman un traste de dos cifras.
    static let digitChain = 0.8
    /// Nombre del bucle A-B que crea la selección de tramo.
    static let spanLoopName = "Selección"
    /// Cuerda inicial (1 = la más aguda) al añadir una nota sin cuerda elegida: la central.
    nonisolated static func defaultString(of tuning: Tuning) -> Int { max(1, tuning.strings.count / 2) }

    enum Phase: Equatable {
        case waitingAnalysis, empty, working, ready, failed(String), choosingSource
        var name: String {
            switch self {
            case .waitingAnalysis: "waitingAnalysis"
            case .empty: "empty"
            case .working: "working"
            case .ready: "ready"
            case .failed: "failed"
            case .choosingSource: "choosingSource"
            }
        }
    }

    enum SynthState: Equatable { case rendering, ready, failed(String) }
    enum ListenMode: String { case stems, transcription, mixed }

    struct Selection: Equatable {
        var trackID: String
        var point: GridPoint
        var string: Int?
    }

    private let studyService: StudyService
    private let makeServices: @Sendable () -> TabServices
    lazy var services: TabServices = makeServices()
    let tabStore: (any TabSourceStoring)?
    private let outbox = TabOutbox()
    /// La pone `Bridge`: diálogo de guardar del anfitrión.
    nonisolated(unsafe) var hostProvider: @Sendable () -> (any HostServices)? = { nil }

    private(set) var session: StudySession?
    private var ctl: BackingController?
    private(set) var phase: Phase = .working
    private(set) var editor: TabEditor?
    private(set) var sources: [TabSource] = []
    private var vocalSource: TabSource?
    private var alpha: AlphaTabScore?
    private var fingerprints: [String: TrackSourceFingerprint] = [:]
    private var keptTuning: [String: Tuning] = [:]
    private(set) var progress: [String: Double] = [:]
    private(set) var queued: [String] = []
    private var failures: [String: String] = [:]
    private(set) var notices: [String] = []
    private(set) var selectedTrackID: String?
    private(set) var editMode = false
    private(set) var selection: Selection? {
        didSet { if selection != oldValue { graceMode = false }; emitSelectionMarker() }
    }
    /// Modo adorno (tecla G): los dígitos cambian el traste de la nota de adorno de la nota seleccionada.
    private(set) var graceMode = false
    private(set) var listening: Set<String> = []
    private(set) var synth: [String: SynthState] = [:]
    private(set) var extraMuted: Set<String> = []
    private(set) var extraSolo: Set<String> = []
    private(set) var span: TabSpan? { didSet { if span != oldValue { emitRangeMarker() } } }
    private(set) var flash: String?
    private(set) var revision = 0

    private var work: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var flashTask: Task<Void, Never>?
    private var dirty = false
    private var statePending = false
    private var trackRevision: [String: Int] = [:]
    private var synthRevision: [String: Int] = [:]
    private var synthTasks: [String: Task<Void, Never>] = [:]
    private var lastDigit: (value: Int, at: Date)?
    private var lastSpanStart = -1.0
    private var spanAnchor: TabSpan?
    private var spanHead: TabSpan?
    private var customTunings: [String: Tuning] = [:]
    private var transcribed = (shifted: 0, dropped: 0)

    nonisolated init(studyService: StudyService, services: @escaping @Sendable () -> TabServices, store: (any TabSourceStoring)?) {
        self.studyService = studyService
        self.makeServices = services
        self.tabStore = store
    }

    nonisolated func setSink(_ sink: @escaping @Sendable (String) -> Void) { outbox.set(sink) }

    func emit<T: Encodable>(_ event: String, _ payload: T) {
        if let m = Router.eventMessage(event, payload) { outbox.send(m) }
    }

    var score: TabScore? { editor?.score }
    private var layout: ProjectLayout? { session?.layout }
    var selectedTrack: TabTrack? {
        guard let id = selectedTrackID else { return nil }
        return score?.tracks.first { $0.id == id }
    }

    var isOpen: Bool { session != nil }

    /// Hoja de Songsterr (W2-G, `TabSongsterr.swift`).
    lazy var songsterr = SongsterrSheet(owner: self)

    /// Sustituye la partitura (Songsterr: «Aceptar»): descarta lo pendiente y la guarda ya.
    func replaceScore(_ score: TabScore) {
        work?.cancel()
        saveTask?.cancel()
        editor = TabEditor(score: score)
        saveNow()
    }

    func setNotices(_ n: [String]) { notices = n }

    // MARK: Abrir y cerrar

    func open(projectId: String) async throws -> TabState {
        guard let id = UUID(uuidString: projectId) else { throw RPCError(code: "bad-params", message: "«projectId» no es un UUID.") }
        if studyService.current?.session.projectID != id {
            _ = try await studyService.open(StudyOpenParams(projectId: projectId))
        }
        guard let o = studyService.current else { throw RPCError(code: "not-open", message: "No se pudo abrir el tema.") }
        close()
        session = o.session
        ctl = o.controller
        o.controller.onMixChanged = { [weak self] in self?.syncSynthMix(); self?.markChanged() }
        load()
        startQueueIfNeeded()
        return state()
    }

    /// TB10: como `TabController.start()` del Mac, abrir (también tras `tab.songsterr.accept` y `tab.songsterr.automatic`,
    /// que reabren) transcribe solo las pistas pendientes; el cliente ya no llama a `tab.transcribe` para eso.
    private func startQueueIfNeeded() {
        guard phase == .ready, work == nil, !queued.isEmpty else { return }
        work = Task { [weak self] in await self?.runQueue() }
    }

    /// Guarda lo editado, cancela lo pendiente y suelta la síntesis del reproductor (el estudio sigue abierto).
    func close() {
        songsterr.reset()
        work?.cancel()
        work = nil
        saveTask?.cancel()
        flashTask?.cancel()
        synthTasks.values.forEach { $0.cancel() }
        synthTasks = [:]
        if dirty { saveNow() }
        if let ctl {
            ctl.onMixChanged = nil
            let hadSynth = !ctl.extraTracks.isEmpty
            ctl.extraTracks = []
            for s in sources { ctl.setSubstituted(s.playerTrackID, false) }
            if let vocalSource { ctl.setSubstituted(vocalSource.playerTrackID, false) }
            if ctl.loopIsSpan { ctl.setLoop(nil) }
            if hadSynth { let t = ctl.player.currentTime; ctl.loadTracks(); ctl.seek(to: t) }
        }
        session = nil
        ctl = nil
        editor = nil
        alpha = nil
        sources = []
        vocalSource = nil
        fingerprints = [:]
        keptTuning = [:]
        progress = [:]
        queued = []
        failures = [:]
        notices = []
        selectedTrackID = nil
        editMode = false
        selection = nil
        span = nil
        spanAnchor = nil
        spanHead = nil
        listening = []
        synth = [:]
        extraMuted = []
        extraSolo = []
        flash = nil
        dirty = false
        phase = .working
        trackRevision = [:]
        synthRevision = [:]
        customTunings = [:]
        transcribed = (0, 0)
    }

    /// El estudio se cerró o cambió de tema por fuera: esta pantalla ya no es válida.
    func require() throws -> (session: StudySession, ctl: BackingController) {
        guard let s = session, let c = ctl, studyService.current?.session === s else {
            if session != nil { close() }
            throw RPCError(code: "not-open", message: "No hay ninguna tablatura abierta.")
        }
        return (s, c)
    }

    /// Lee `tab/score.json`, lo compara con los ficheros actuales y deja en `queued` lo que hay que (re)transcribir.
    /// A diferencia del Mac, no transcribe solo: lo pide la página con `tab.transcribe`.
    private func load() {
        guard let session, let layout else { return }
        guard session.hasBeatGrid else { phase = .waitingAnalysis; return }
        let times = BeatTimes(beats: session.beats, downbeats: session.downbeats, beatsPerBar: session.analysis?.beatsPerBar)
        let folder = layout.folder
        let exists = { (path: String) in FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path) }
        sources = session.project.tabSources(fileExists: exists)
        vocalSource = session.project.vocalTabSource(fileExists: exists)
        guard !sources.isEmpty else { phase = .empty; return }
        guard let choice = session.project.tabSource else { phase = .choosingSource; return }
        do {
            var score = try TabScore(beatTimes: times, duration: session.project.song.duration)
            let saved = Self.loadSaved(layout.tabScoreFile).flatMap { $0.formatVersion == score.formatVersion ? $0 : nil }
            let importedSaved = saved?.tracks.filter { $0.imported != nil } ?? []
            var autoIDs = sources.map(\.id)
            var kept: [TabTrack] = []
            var redone: [String] = []
            if case .songsterr = choice {
                guard let saved, !importedSaved.isEmpty else { phase = .choosingSource; return }
                autoIDs = autoIDs.filter { !choice.importsSongsterr(forStem: $0) }
                score = saved   // la rejilla es la de Songsterr, ya alineada con el audio
                kept = saved.tracks.filter { $0.imported == nil }
                score.tracks = importedSaved
            } else if let saved {
                if saved.bars == score.bars && saved.beats == score.beats {
                    kept = saved.tracks.filter { $0.imported == nil }
                } else {
                    redone = saved.tracks.filter { t in t.imported == nil && sources.contains { $0.id == t.id } }.map(\.name)
                }
            }
            kept.removeAll { !autoIDs.contains($0.id) }
            fingerprints = [:]
            for s in sources where autoIDs.contains(s.id) {
                fingerprints[s.id] = try TrackSourceFingerprint.of(fileAt: folder.appendingPathComponent(s.relativePath),
                                                                    path: s.relativePath, modelVersion: Self.modelVersion(of: s.kind))
            }
            let needs = autoIDs.filter { id in s(id)?.kind != .vocal && kept.first { $0.id == id }?.source != fingerprints[id] }
            for id in needs { if let t = kept.first(where: { $0.id == id }) { redone.append(t.name) } }
            keptTuning = [:]
            for id in needs { if let tu = kept.first(where: { $0.id == id })?.tuning { keptTuning[id] = tu } }
            kept.removeAll { needs.contains($0.id) }
            score.tracks += kept
            for i in score.tracks.indices {
                if let src = sources.first(where: { $0.id == score.tracks[i].id }) { score.tracks[i].name = src.name }
            }
            editor = TabEditor(score: score)
            queued = needs
            failures = [:]
            if !redone.isEmpty {
                notices.append("Se han rehecho: \(redone.joined(separator: ", ")). Su audio cambió, así que se perdieron las ediciones de esas pistas.")
            }
            phase = .ready
            sortTracks()
            selectedTrackID = editor?.score.tracks.first?.id
            rebuildAlpha()
            listenExtras()
            if let current = editor?.score, !current.tracks.isEmpty, current != saved { saveNow() }
        } catch {
            phase = .failed(BackingController.describe(error))
        }
    }

    private func s(_ id: String) -> TabSource? { sources.first { $0.id == id } }

    nonisolated static func modelVersion(of kind: TabSource.Kind) -> String {
        kind == .drums ? ModelCatalog.drumsADTOF.version : ModelCatalog.transcriptionBasicPitch.version
    }

    nonisolated static func loadSaved(_ url: URL) -> TabScore? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TabScore.self, from: data)
    }

    /// Stem de una pista: el suyo, o el de voz si es una pista `vocal`; nil = pista extra.
    func source(of id: String) -> TabSource? {
        if let src = sources.first(where: { $0.id == id }) { return src }
        guard let vocalSource, score?.tracks.first(where: { $0.id == id })?.kind == .vocal else { return nil }
        return vocalSource
    }

    /// Cierra los avisos actuales (los de apertura: pistas rehechas, transcripción); solo vuelven a salir si hay otros nuevos.
    func dismissNotices() {
        notices = []
        markChanged()
    }

    // MARK: Fuente

    func setSource(_ source: String) async throws -> TabState {
        let (session, _) = try require()
        if source == "songsterr" {
            // Abre la hoja (menú «Fuente» > «Songsterr…»); la fuente se guarda con `tab.songsterr.accept`.
            _ = try await songsterr.open()
            return state()
        }
        guard source == "automatic" else {
            throw RPCError(code: "bad-params", message: "«source» debe ser «automatic» o «songsterr».")
        }
        guard let tabStore else { throw RPCError(code: "unsupported", message: "No hay biblioteca donde guardar la fuente.") }
        do { try await tabStore.saveTabSource(.automatic, for: session.projectID) } catch {
            throw RPCError(code: "internal", message: "No se pudo guardar la fuente: \(error)")
        }
        session.reload()
        let id = session.projectID.uuidString
        return try await open(projectId: id)
    }

    // MARK: Partitura

    private func rebuildAlpha() {
        guard let session, let score = editor?.score, !score.tracks.isEmpty else { alpha = nil; return }
        let song = session.project.song
        do { alpha = try AlphaTabExporter.make(score: score, title: song.title, artist: song.artist ?? "") } catch {
            alpha = nil
            showFlash(error.localizedDescription)
        }
    }

    func scoreJSON(track: String?) throws -> TabScoreResult {
        _ = try require()
        guard let a = alpha else { throw RPCError(code: "not-ready", message: "Aún no hay partitura.") }
        var index = selectedTrackID.flatMap { a.trackIDs.firstIndex(of: $0) } ?? 0
        if let track {
            guard let i = a.trackIDs.firstIndex(of: track) else { throw RPCError(code: "bad-params", message: "Pista desconocida: \(track).") }
            index = i
        }
        return TabScoreResult(json: a.json, trackIndex: index, trackIDs: a.trackIDs, revision: revision)
    }

    func selectTrack(_ id: String) throws -> TabState {
        _ = try require()
        guard score?.tracks.contains(where: { $0.id == id }) == true else { throw RPCError(code: "bad-params", message: "Pista desconocida: \(id).") }
        if selectedTrackID != id {
            selectedTrackID = id
            selection = nil
            clearSpan()
            spanAnchor = nil
        }
        return state()
    }

    private func sortTracks() {
        guard var score = editor?.score else { return }
        let order = sources.map(\.id)
        score.tracks.sort { (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99) }
        if score.tracks != editor?.score.tracks { editor = TabEditor(score: score) }
    }

    /// Compás más frecuente y tempo para la cabecera (Mac: `headerSummary`).
    private var header: TabHeaderSummary? {
        guard let score, !score.bars.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for b in score.bars { counts["\(b.beatCount)/\(b.beatUnit)", default: 0] += 1 }
        let meter = counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? "4/4"
        if usesSongsterr {
            var beats: [Double: Int] = [:]
            for b in score.bars { beats[b.tempo, default: 0] += b.beatCount }
            if let written = beats.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key { return TabHeaderSummary(code: "meterBpm", bar: meter, bpm: Int(written)) }
        }
        guard let bpm = session?.analysis?.bpm else { return TabHeaderSummary(code: "meter", bar: meter) }
        return TabHeaderSummary(code: "meterBpm", bar: meter, bpm: Int(bpm.rounded()))
    }

    private var usesSongsterr: Bool {
        if case .songsterr? = session?.project.tabSource { return true }
        return false
    }

    // MARK: Transcripción

    /// Pone en cola las pistas pedidas (o todas las pendientes) y las transcribe una a una en segundo plano.
    func transcribe(track: String?) throws -> TabQueuedResult {
        _ = try require()
        guard phase == .ready else { throw RPCError(code: "not-ready", message: "La tablatura no está lista para transcribir.") }
        if let track {
            guard let src = s(track), src.kind != .vocal, fingerprints[track] != nil else {
                throw RPCError(code: "bad-params", message: "La pista «\(track)» no se puede transcribir.")
            }
            failures[track] = nil
            if !queued.contains(track) { queued.append(track) }
        } else {
            for id in failures.keys.sorted() where !queued.contains(id) { queued.append(id) }
            failures = [:]
        }
        let ids = track.map { [$0] } ?? queued
        if work == nil, !queued.isEmpty { work = Task { [weak self] in await self?.runQueue() } }
        markChanged()
        return TabQueuedResult(queued: ids)
    }

    func cancel() -> Bool {
        let running = work != nil
        work?.cancel()
        return running
    }

    private func runQueue() async {
        while !Task.isCancelled, let id = queued.first {
            do {
                try await transcribeOne(id)
            } catch is CancellationError {
                break
            } catch {
                let message = BackingController.describe(error)
                progress[id] = nil
                queued.removeAll { $0 == id }
                failures[id] = message
                emit("tab.progress", TabProgressEvent(state: "failed", track: id, fraction: 0, error: message))
                markChanged()
            }
        }
        if Task.isCancelled {
            for id in progress.keys { emit("tab.progress", TabProgressEvent(state: "cancelled", track: id, fraction: progress[id] ?? 0)) }
            progress = [:]
        }
        let t = transcribed
        if t.shifted + t.dropped > 0, !Task.isCancelled {
            var parts: [String] = []
            if t.shifted > 0 { parts.append("\(t.shifted) notas fuera del registro de la afinación se subieron o bajaron una octava") }
            if t.dropped > 0 { parts.append("\(t.dropped) se quitaron por no caber en las cuerdas") }
            notices.append("Transcripción: " + parts.joined(separator: " y ") + ".")
        }
        transcribed = (0, 0)
        work = nil
        listenExtras()
        markChanged()
    }

    private func transcribeOne(_ id: String) async throws {
        guard let src = s(id), let fp = fingerprints[id], let layout else {
            queued.removeAll { $0 == id }
            return
        }
        let url = layout.url(relative: src.relativePath)
        progress[id] = 0
        emit("tab.progress", TabProgressEvent(state: "transcribing", track: id, fraction: 0))
        let report: @Sendable (Double) -> Void = { [weak self] p in
            Task { @MainActor in self?.reportProgress(id, p) }
        }
        var newTrack: TabTrack
        switch src.kind {
        case .drums:
            let hits = try await services.transcriber.drums(url: url, progress: report)
            guard let base = editor?.score else { return }
            let onsets = DrumCymbalSeries.refine(hits).compactMap { h in DrumPiece(rawValue: h.midi).map { DrumOnset(time: h.time, piece: $0) } }
            newTrack = TabTrackBuilder.drumTrack(id: id, name: src.name, source: fp, onsets: onsets, in: base)
        case .vocal:
            queued.removeAll { $0 == id }
            progress[id] = nil
            return
        case .guitar, .bass:
            let events = try await services.transcriber.pitched(url: url, progress: report)
            guard let base = editor?.score else { return }
            let kind: TabTrackKind = src.kind == .bass ? .bass : .guitar
            let tuning = keptTuning[id] ?? (kind == .bass ? Tuning.bass(.standard) : Tuning.guitar(.standard))
            let built = TabTrackBuilder.pitchedTrack(id: id, name: src.name, kind: kind, tuning: tuning, source: fp, notes: events, in: base)
            transcribed.shifted += built.report.shiftedOctave
            transcribed.dropped += built.report.droppedNotes
            newTrack = built.track
        }
        try Task.checkCancellation()
        guard var score = editor?.score else { return }
        score.upsert(newTrack)
        editor = TabEditor(score: score)
        progress[id] = nil
        queued.removeAll { $0 == id }
        trackRevision[id, default: 0] += 1
        sortTracks()
        if selectedTrackID == nil { selectedTrackID = id }
        saveNow()   // cada pista se guarda al terminar: si se cierra a medias, lo hecho no se repite
        revision += 1
        rebuildAlpha()
        if listening.contains(id) { scheduleSynth(id) }
        emit("tab.progress", TabProgressEvent(state: "done", track: id, fraction: 1))
        markChanged()
    }

    private func reportProgress(_ id: String, _ p: Double) {
        guard progress[id] != nil else { return }
        let f = min(max(p, 0), 1)
        guard f - (progress[id] ?? 0) >= 0.01 || f >= 1 else { return }
        progress[id] = f
        emit("tab.progress", TabProgressEvent(state: "transcribing", track: id, fraction: f))
    }

    // MARK: Lienzo (clics de alphaTab)

    private static func span(of ref: AlphaTabBeatRef) -> TabSpan {
        TabSpan(startTick: ref.start.absoluteTick, endTick: ref.start.absoluteTick + max(ref.length, 1))
    }

    func beatClick(track: Int, bar: Int, beat: Int, shift: Bool) throws {
        let (_, ctl) = try require()
        guard let ref = alpha?.ref(track: track, bar: bar, beat: beat), alpha?.trackIDs[track] == selectedTrackID,
              let id = selectedTrackID else { return }
        if shift, spanAnchor != nil { extendSpan(to: ref); return }
        clearSpan()
        spanAnchor = Self.span(of: ref)
        // Mismo pulso ya seleccionado: no se toca la selección (ni su cuerda), pero el clic salta otra vez.
        if selection?.trackID == id, selection?.point == ref.start {
            if let score { ctl.seek(to: min(max(score.time(of: ref.start), 0), ctl.duration)) }
            return
        }
        select(id, ref.start, string: selection?.string)
    }

    func beatDrag(track: Int, bar: Int, beat: Int) throws {
        _ = try require()
        guard spanAnchor != nil, let ref = alpha?.ref(track: track, bar: bar, beat: beat),
              alpha?.trackIDs[track] == selectedTrackID else { return }
        extendSpan(to: ref)
    }

    func noteClick(track: Int, bar: Int, beat: Int, string: Int, shift: Bool) throws {
        _ = try require()
        guard !shift else { return }
        guard let ref = alpha?.ref(track: track, bar: bar, beat: beat), alpha?.trackIDs[track] == selectedTrackID,
              let id = selectedTrackID, let tuning = selectedTrack?.tuning else { return }
        select(id, ref.start, string: AlphaTabExporter.scoreString(forJSONString: string, stringCount: tuning.strings.count))
    }

    private func emitSelectionMarker() {
        guard let sel = selection, let score, score.beats.indices.contains(sel.point.beat) else {
            if session != nil { emit("tab.selection", TabSelectionEvent(bar: -1, fraction: 0)) }
            return
        }
        let bar = score.beats[sel.point.beat].bar
        let b = score.bars[bar]
        let local = sel.point.absoluteTick - b.firstBeat * TabScore.ticksPerBeat
        emit("tab.selection", TabSelectionEvent(bar: bar, fraction: Double(local) / Double(b.beatCount * TabScore.ticksPerBeat)))
    }

    // MARK: Tramo y bucle

    private func extendSpan(to ref: AlphaTabBeatRef) {
        guard let anchor = spanAnchor else { return }
        let head = Self.span(of: ref)
        spanHead = head
        setSpan(anchor.union(head))
    }

    private func setSpan(_ new: TabSpan) {
        guard new != span, let ctl else { return }
        let first = span == nil
        span = new
        guard let score, let range = score.timeRange(of: new) else { return }
        let upper = min(range.upperBound, ctl.duration)
        guard upper > range.lowerBound else { return }
        let startChanged = first || lastSpanStart != range.lowerBound
        lastSpanStart = range.lowerBound
        ctl.setLoop(range.lowerBound...upper, name: Self.spanLoopName, span: true)
        if startChanged { ctl.seek(to: range.lowerBound) }
    }

    /// ⇧← / ⇧→: mueve el extremo móvil del tramo un pulso.
    func extendSpan(forward: Bool) {
        guard let ctl, let id = selectedTrackID, let alpha, let ti = alpha.trackIDs.firstIndex(of: id), let score else { return }
        let refs = alpha.beats[ti].flatMap { $0 }.sorted { $0.start < $1.start }
        if spanAnchor == nil {
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

    /// Quita el tramo y, si el bucle activo era el suyo, también el bucle.
    func clearSpan() {
        spanHead = nil
        span = nil
        if let ctl, ctl.loopIsSpan { ctl.setLoop(nil) }
    }

    /// «Selección» del menú de bucle: vuelve a poner el bucle del tramo y salta a su inicio.
    func applySpanLoop() {
        guard let ctl, let span, let score, let range = score.timeRange(of: span) else { return }
        let upper = min(range.upperBound, ctl.duration)
        guard upper > range.lowerBound else { return }
        ctl.setLoop(range.lowerBound...upper, name: Self.spanLoopName, span: true)
        ctl.seek(to: range.lowerBound)
    }

    func spanAction(_ action: String, keepAnchor: Bool = false) throws -> TabState {
        _ = try require()
        switch action {
        case "clear": clearSpan(); if !keepAnchor { spanAnchor = nil }
        case "apply": applySpanLoop()
        case "extendForward": extendSpan(forward: true)
        case "extendBack": extendSpan(forward: false)
        default: throw RPCError(code: "bad-params", message: "Acción de tramo desconocida: \(action).")
        }
        return state()
    }

    private func emitRangeMarker() {
        guard session != nil else { return }
        guard let span, let score, let a = score.barPosition(ofTick: span.startTick),
              let b = score.barPosition(ofTick: span.endTick, asEnd: true) else {
            emit("tab.range", TabRangeEvent(startBar: -1, startFraction: 0, endBar: -1, endFraction: 0)); return
        }
        emit("tab.range", TabRangeEvent(startBar: a.bar, startFraction: a.fraction, endBar: b.bar, endFraction: b.fraction))
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
        if let score, let ctl { ctl.seek(to: min(max(score.time(of: point), 0), ctl.duration)) }
    }

    func selectPoint(track: String, beat: Int, tick: Int, string: Int?) throws -> TabState {
        _ = try require()
        guard let t = score?.tracks.first(where: { $0.id == track }), t.kind != .vocal else {
            throw RPCError(code: "bad-params", message: "Pista desconocida: \(track).")
        }
        if selectedTrackID != track { _ = try selectTrack(track) }
        guard let score, (0..<score.beats.count).contains(beat), (0..<TabScore.ticksPerBeat).contains(tick) else {
            throw RPCError(code: "bad-params", message: "Esa posición no está en la partitura.")
        }
        select(track, GridPoint(beat: beat, tick: tick), string: string)
        return state()
    }

    var selectedNote: TabNote? {
        guard let sel = selection, let track = selectedTrack, track.id == sel.trackID else { return nil }
        return track.notes.first { $0.start == sel.point && $0.string == sel.string }
    }

    /// Compás del punto seleccionado y su rango en segundos (TabController.selectedBarRange del Mac).
    var selectedBarRange: TabBarRange? {
        guard let sel = selection, let score, let ctl, score.beats.indices.contains(sel.point.beat) else { return nil }
        let bar = score.beats[sel.point.beat].bar
        guard score.bars.indices.contains(bar) else { return nil }
        let start = max(0, score.bars[bar].start)
        let end = bar + 1 < score.bars.count ? score.bars[bar + 1].start : score.endTime
        guard end > start else { return nil }
        return TabBarRange(bar: bar, start: start, end: min(end, max(ctl.duration, start + 0.001)))
    }

    var selectionSummary: TabSelectionSummary? {
        guard let sel = selection, let score, let track = selectedTrack, score.beats.indices.contains(sel.point.beat) else { return nil }
        let bar = score.beats[sel.point.beat].bar + 1
        let beat = score.beats[sel.point.beat].indexInBar + 1
        if track.kind == .drums {
            let pieces = track.hits.filter { $0.at == sel.point }.map { Self.pieceCode($0.piece) }
            return pieces.isEmpty ? TabSelectionSummary(code: "drumsNoHits", bar: bar, beat: beat)
                : TabSelectionSummary(code: "drums", bar: bar, beat: beat, pieces: pieces)
        }
        if let n = selectedNote, let f = track.fret(of: n) { return TabSelectionSummary(code: "note", bar: bar, beat: beat, string: n.string, fret: f) }
        return TabSelectionSummary(code: "noNote", bar: bar, beat: beat, string: sel.string ?? 1)
    }

    /// Código de pieza (ARB `tab_piece*`).
    nonisolated static func pieceCode(_ p: DrumPiece) -> String {
        switch p {
        case .kick: "kick"
        case .snare: "snare"
        case .hiHat: "hiHat"
        case .openHiHat: "openHiHat"
        case .tom: "tom"
        case .crash: "crash"
        }
    }

    // MARK: Edición

    private func step(at point: GridPoint, in track: TabTrack) -> Int {
        track.subdivisions.indices.contains(point.beat) ? track.subdivisions[point.beat].tickStep : 3
    }

    private func edit(_ body: (inout TabEditor) throws -> Void) {
        guard var e = editor else { return }
        let before = e.score.tracks
        do { try body(&e) } catch let err as TabEditError {
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
            trackRevision[new.id, default: 0] += 1
            if listening.contains(new.id) { scheduleSynth(new.id) }
        }
        revision += 1
        scheduleSave()
        rebuildAlpha()
    }

    nonisolated static func message(for e: TabEditError) -> String {
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
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.flash = nil
            self?.markChanged()
        }
        markChanged()
    }

    var canUndo: Bool { editor?.canUndo ?? false }
    var canRedo: Bool { editor?.canRedo ?? false }

    func undo() { stepHistory { $0.undo() } }
    func redo() { stepHistory { $0.redo() } }

    private func stepHistory(_ op: (inout TabEditor) -> Bool) {
        guard var e = editor else { return }
        let before = e.score.tracks
        guard op(&e) else { return }
        if let changed = zip(before, e.score.tracks).first(where: { $0 != $1 })?.1, selectedTrackID != changed.id {
            selectedTrackID = changed.id   // la pista afectada pasa a ser la visible
            selection = nil
        }
        commit(e, before: before)
    }

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

    func changeDuration(by sign: Int) {
        guard let track = selectedTrack, let n = selectedNote else { return }
        let st = step(at: n.start, in: track)
        edit { try $0.setDuration(n.duration + sign * st, trackID: track.id, noteID: n.id) }
    }

    func toggleHit(_ piece: DrumPiece) {
        guard let sel = selection, let track = selectedTrack, track.kind == .drums else { return }
        let present = !track.hits.contains { $0.piece == piece && $0.at == sel.point }
        edit { try $0.setHit(piece, at: sel.point, present: present, trackID: track.id) }
    }

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

    func addNoteAtCursor() {
        guard let score, let ctl, let track = selectedTrack, track.kind != .drums, let tuning = track.tuning else { return }
        let point = score.nearestPoint(to: ctl.player.currentTime, in: track)
        let string = selection?.trackID == track.id ? selection?.string ?? Self.defaultString(of: tuning) : Self.defaultString(of: tuning)
        let dur = step(at: point, in: track)
        edit { _ = try $0.addNote(trackID: track.id, string: string, fret: 0, at: point, duration: dur) }
        selection = Selection(trackID: track.id, point: point, string: string)
    }

    func moveSelection(forward: Bool) {
        guard let track = selectedTrack, let score, let ctl else { return }
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
        let st = track.subdivisions.indices.contains(p.beat) ? track.subdivisions[p.beat].tickStep : 3
        select(track.id, GridPoint(beat: p.beat, tick: (p.tick / st) * st), string: selection?.string)
    }

    /// Afinación personalizada disponible para la pista: la actual si lo es, o la guardada al salir de ella.
    func customTuning(of track: TabTrack) -> Tuning? {
        if let t = track.tuning, t.preset == .custom { return t }
        return customTunings[track.id]
    }

    func setTuning(_ preset: TuningPreset, trackID: String) {
        guard let track = score?.tracks.first(where: { $0.id == trackID }), track.kind != .drums, track.kind != .vocal else { return }
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

    nonisolated static func tuningName(_ p: TuningPreset) -> String {
        switch p {
        case .standard: "Estándar"
        case .halfStepDown: "Medio tono abajo"
        case .wholeStepDown: "Un tono abajo"
        case .dropD: "Drop D"
        case .custom: "Personalizada"
        }
    }

    /// Tabla «Teclas (modo edición)» de la Fase 5c (idéntica a la del Mac).
    nonisolated static func ornament(forKey ch: String, shift: Bool, drums: Bool) -> TabOrnament? {
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

    /// Tecla de la página (`KeyboardEvent.key`): mismas reglas que `handleKey` del Mac. true = se usó.
    func handleKey(_ ch: String, shift: Bool, ctrl: Bool, alt: Bool) -> Bool {
        guard phase == .ready else { return false }
        let plain = !shift && !ctrl && !alt
        let drums = selectedTrack?.kind == .drums
        // Misma tabla que `tab.keyMap` (TabKeyMap.swift): la primera regla que casa decide y da la acción.
        let action = Self.keyEntries.first {
            $0.rule.matches(key: ch, shift: shift, ctrl: ctrl, alt: alt, span: span != nil, edit: editMode, drums: drums)
        }?.action
        if action == .clearSpan { clearSpan(); return true }
        guard editMode else { return false }
        if graceMode, !(ch == "Backspace" || ch == "Delete" || ch.lowercased() == "g" || (plain && Int(ch) != nil)) { graceMode = false }
        guard let action else { return false }
        switch action {
        case .clearSpan: break
        case .undoRedo: if shift { redo() } else { undo() }
        case .artificialHarmonic: toggleOrnament(.artificialHarmonic)
        case .arrowUp: moveString(up: true)
        case .arrowDown: moveString(up: false)
        case .arrowLeft: if shift { extendSpan(forward: false) } else { moveSelection(forward: false) }
        case .arrowRight: if shift { extendSpan(forward: true) } else { moveSelection(forward: true) }
        case .delete: deleteSelection()
        case .deselect: selection = nil
        case .digit: if let d = Int(ch) { typeDigit(d) }
        case .durationUp: changeDuration(by: 1)
        case .durationDown: changeDuration(by: -1)
        case .hit(let piece): toggleHit(piece)
        case .ornament(let o): toggleOrnament(o)
        }
        return true
    }

    func edit(_ p: TabEditParams) throws -> TabState {
        _ = try require()
        guard phase == .ready else { throw RPCError(code: "not-ready", message: "La tablatura no está lista.") }
        var handled: Bool?
        switch p.op {
        case "digit":
            guard let v = p.value, (0...9).contains(v) else { throw RPCError(code: "bad-params", message: "«value» debe ser un dígito.") }
            typeDigit(v)
        case "moveString": moveString(up: p.up ?? true)
        case "delete": deleteSelection()
        case "duration": changeDuration(by: (p.sign ?? 1) < 0 ? -1 : 1)
        case "hit":
            guard let piece = DrumPiece.allCases.first(where: { "\($0)" == p.piece }) else {
                throw RPCError(code: "bad-params", message: "Pieza de batería desconocida: \(p.piece ?? "").")
            }
            toggleHit(piece)
        case "ornament":
            guard let o = TabOrnament.allCases.first(where: { "\($0)" == p.name }) else {
                throw RPCError(code: "bad-params", message: "Adorno desconocido: \(p.name ?? "").")
            }
            toggleOrnament(o)
        case "key": handled = handleKey(p.key ?? "", shift: p.shift ?? false, ctrl: p.ctrl ?? false, alt: p.alt ?? false)
        case "addNote": addNoteAtCursor()
        case "move": moveSelection(forward: p.forward ?? true)
        case "tuning":
            guard let track = p.track, let preset = TuningPreset(rawValue: p.preset ?? "") else {
                throw RPCError(code: "bad-params", message: "Faltan «track» y «preset» válidos.")
            }
            setTuning(preset, trackID: track)
        case "undo": undo()
        case "redo": redo()
        case "editMode":
            editMode = p.on ?? true
            if !editMode { selection = nil }
        case "deselect": selection = nil
        default: throw RPCError(code: "bad-params", message: "Operación de edición desconocida: \(p.op).")
        }
        var st = state()
        st.handled = handled
        return st
    }

    // MARK: Guardado

    private func scheduleSave() {
        dirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.saveDebounce * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.saveNow()
            self?.markChanged()
        }
    }

    func saveNow() {
        guard let score = editor?.score, let layout else { return }
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

    // MARK: Oír transcripción

    nonisolated static func synthPlayerID(_ id: String) -> String { "tab-\(id)" }

    func setListening(_ on: Bool, trackID: String) {
        guard let ctl, score?.tracks.contains(where: { $0.id == trackID }) == true else { return }
        let src = source(of: trackID)   // nil en las pistas extra: solo suena la transcripción
        if on {
            listening.insert(trackID)
            if synthRevision[trackID] == trackRevision[trackID, default: 0], synth[trackID] == .ready {
                activateSynth(trackID, src)
            } else {
                renderSynth(trackID) { [weak self] in self?.activateSynth(trackID, src) }
            }
        } else {
            listening.remove(trackID)
            synthTasks[trackID]?.cancel()
            synth[trackID] = synth[trackID] == .ready ? .ready : nil
            if let src { ctl.setSubstituted(src.playerTrackID, stemStaysSubstituted(src)) }
            syncSynthMix()
        }
        markChanged()
    }

    private func stemStaysSubstituted(_ src: TabSource) -> Bool {
        (score?.tracks ?? []).contains { listening.contains($0.id) && synth[$0.id] == .ready && source(of: $0.id)?.id == src.id }
    }

    private func activateSynth(_ trackID: String, _ src: TabSource?) {
        guard listening.contains(trackID) else { return }
        if let src { ctl?.setSubstituted(src.playerTrackID, true) }
        syncSynthMix()
    }

    // MARK: Mute y solo por pista y selector global

    private func mixState(_ trackID: String) -> (muted: Bool, solo: Bool) {
        if let src = source(of: trackID), let m = ctl?.mix(ofPlayerTrack: src.playerTrackID) { return (m.muted, m.solo) }
        return (extraMuted.contains(trackID), extraSolo.contains(trackID))
    }

    func isMuted(_ trackID: String) -> Bool { mixState(trackID).muted }
    func isSolo(_ trackID: String) -> Bool { mixState(trackID).solo }
    var anySolo: Bool { (ctl?.anyStemSolo ?? false) || !extraSolo.isEmpty }
    func isDimmed(_ trackID: String) -> Bool { isMuted(trackID) || (anySolo && !isSolo(trackID)) }

    func toggleMute(trackID: String) throws {
        let (_, ctl) = try require()
        if let src = source(of: trackID) { ctl.toggleMute(playerTrack: src.playerTrackID); return }
        guard score?.tracks.contains(where: { $0.id == trackID }) == true else { throw RPCError(code: "bad-params", message: "Pista desconocida: \(trackID).") }
        if extraMuted.contains(trackID) { extraMuted.remove(trackID) } else { extraMuted.insert(trackID) }
        syncSynthMix()
    }

    func toggleSolo(trackID: String) throws {
        let (_, ctl) = try require()
        if let src = source(of: trackID) { ctl.toggleSolo(playerTrack: src.playerTrackID); return }
        guard score?.tracks.contains(where: { $0.id == trackID }) == true else { throw RPCError(code: "bad-params", message: "Pista desconocida: \(trackID).") }
        if extraSolo.contains(trackID) { extraSolo.remove(trackID) } else { extraSolo.insert(trackID) }
        syncSynthMix()
    }

    /// La síntesis de cada pista sigue la mezcla de su pista: suena solo con «Oír transcripción», con su mute y su solo.
    func syncSynthMix() {
        guard let ctl else { return }
        for extra in ctl.extraTracks {
            let tid = String(extra.id.dropFirst(4))
            let m = mixState(tid)
            ctl.setExtraMuted(extra.id, !listening.contains(tid) || m.muted)
            ctl.player.setSolo(extra.id, m.solo)
        }
    }

    /// «Stems» = las pistas con stem suenan su stem y las extra su síntesis; «Transcripción» = todas su síntesis.
    var listenMode: ListenMode {
        let entries = score?.tracks ?? []
        let withStem = entries.filter { source(of: $0.id) != nil }
        let extras = entries.filter { source(of: $0.id) == nil }
        let stemsOn = withStem.filter { listening.contains($0.id) }.count
        let extrasOn = extras.allSatisfy { listening.contains($0.id) }
        if entries.isEmpty { return .stems }
        if stemsOn == withStem.count && extrasOn { return .transcription }
        if stemsOn == 0 && extrasOn { return .stems }
        return .mixed
    }

    func setAllListening(_ on: Bool) throws {
        _ = try require()
        for e in score?.tracks ?? [] {
            let target = on || source(of: e.id) == nil
            if target != listening.contains(e.id) { setListening(target, trackID: e.id) }
        }
    }

    /// Estado inicial de «Stems»: las pistas extra (sin stem) suenan siempre con su síntesis.
    private func listenExtras() {
        for e in score?.tracks ?? [] where source(of: e.id) == nil && !listening.contains(e.id) { setListening(true, trackID: e.id) }
    }

    private func scheduleSynth(_ trackID: String) {
        synthTasks[trackID]?.cancel()
        synthTasks[trackID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.synthDebounce * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.renderSynth(trackID) { [weak self] in self?.activateSynth(trackID, self?.source(of: trackID)) }
        }
    }

    /// Renderiza la pista al WAV de `cache/tab/`, lo carga en el reproductor como pista extra y llama a `done`.
    private func renderSynth(_ trackID: String, done: @escaping @MainActor () -> Void) {
        guard let score, let ctl, let layout, let session, let track = score.tracks.first(where: { $0.id == trackID }) else { return }
        synth[trackID] = .rendering
        let rev = trackRevision[trackID, default: 0]
        let url = layout.tabSynthURL(trackID: trackID)
        let rate = session.project.song.sampleRate
        let duration = ctl.duration
        let synthesizer = services.synth
        synthTasks[trackID]?.cancel()
        synthTasks[trackID] = Task { [weak self] in
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try await synthesizer.render(track: track, in: score, sampleRate: rate, duration: duration, to: url)
                guard !Task.isCancelled, let self else { return }
                self.synthRevision[trackID] = rev
                self.synth[trackID] = .ready
                self.attachSynth(trackID, url: url)
                done()
                self.markChanged()
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
        guard let ctl else { return }
        let id = Self.synthPlayerID(trackID)
        if !ctl.extraTracks.contains(where: { $0.id == id }) { ctl.extraTracks.append(Track(id: id, url: url)) }
        let t = ctl.player.currentTime
        let playing = ctl.isPlaying
        ctl.loadTracks()
        ctl.seek(to: t)
        syncSynthMix()
        for tid in listening { if let s = source(of: tid) { ctl.setSubstituted(s.playerTrackID, true) } }
        if playing { try? ctl.play() }
    }

    // MARK: Exportar

    /// Nombre por defecto «Artista - Título.gp».
    nonisolated static func exportFileName(title: String, artist: String?) -> String {
        let bad = CharacterSet(charactersIn: "/:\\")
        func clean(_ s: String) -> String { s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces) }
        let a = artist.map(clean) ?? ""
        return (a.isEmpty ? clean(title) : "\(a) - \(clean(title))") + ".gp"
    }

    func exportName() throws -> TabExportNameResult {
        let (session, _) = try require()
        let song = session.project.song
        return TabExportNameResult(fileName: Self.exportFileName(title: song.title, artist: song.artist))
    }

    /// Guarda los bytes del `.gp` que generó la página (`TF.exportGpBase64`) en `path`, o donde diga el diálogo del anfitrión.
    func export(data base64: String, path: String?) async throws -> TabExportResult {
        _ = try require()
        guard phase == .ready, alpha != nil else { throw RPCError(code: "not-ready", message: "Aún no hay partitura que exportar.") }
        guard let data = Data(base64Encoded: base64), !data.isEmpty else {
            throw RPCError(code: "bad-params", message: "«data» no es base64 válido.")
        }
        var target = path.map { URL(fileURLWithPath: $0) }
        if target == nil {
            let name = try exportName().fileName
            target = await hostProvider()?.saveFile(suggestedName: name, types: ["gp"])
        }
        guard let url = target else { return TabExportResult(saved: false, path: nil) }
        do { try data.write(to: url, options: .atomic) } catch {
            throw RPCError(code: "internal", message: "No se pudo guardar \(url.lastPathComponent): \(error.localizedDescription)")
        }
        showFlash("Guardado \(url.lastPathComponent).")
        return TabExportResult(saved: true, path: url.path)
    }

    // MARK: Estado

    /// Coalesce los cambios de un mismo turno en un solo `tab.state`.
    func markChanged() {
        guard session != nil, !statePending else { return }
        statePending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            statePending = false
            guard session != nil else { return }
            emit("tab.state", state())
        }
    }

    private func tuningInfo(_ t: Tuning?) -> TabTuningInfo? {
        t.map { TabTuningInfo(preset: $0.preset.rawValue, name: Self.tuningName($0.preset), strings: $0.strings) }
    }

    func state() -> TabState {
        let tracks = editor?.score.tracks ?? []
        let names = editor?.score.trackDisplayNames ?? []
        var infos: [TabTrackInfo] = []
        for (i, t) in tracks.enumerated() {
            let origin = t.imported != nil ? "songsterr" : (source(of: t.id) != nil ? "stem" : "extra")
            let tr: String = progress[t.id] != nil ? "transcribing" : queued.contains(t.id) ? "queued" : "ready"
            infos.append(TabTrackInfo(
                id: t.id, name: names.indices.contains(i) ? names[i] : t.name, kind: t.kind.rawValue,
                tuning: tuningInfo(t.tuning), customTuning: tuningInfo(customTuning(of: t)), origin: origin,
                playerTrack: source(of: t.id)?.playerTrackID, transcription: tr, progress: progress[t.id], error: nil,
                fingerprint: t.source, noteCount: t.kind == .drums ? t.hits.count : t.notes.count,
                muted: isMuted(t.id), solo: isSolo(t.id), dimmed: isDimmed(t.id), listening: listening.contains(t.id),
                synth: synth[t.id].map { s in
                    switch s { case .rendering: "rendering"; case .ready: "ready"; case .failed: "failed" }
                }))
        }
        // Stems sin pista todavía: pendientes de transcribir (o fallidos).
        for src in sources where src.kind != .vocal && !tracks.contains(where: { $0.id == src.id }) {
            let tr: String = progress[src.id] != nil ? "transcribing" : queued.contains(src.id) ? "queued"
                : failures[src.id] != nil ? "failed" : "missing"
            let m = ctl?.mix(ofPlayerTrack: src.playerTrackID)
            infos.append(TabTrackInfo(
                id: src.id, name: src.name, kind: src.kind.rawValue, tuning: nil, customTuning: nil, origin: "stem",
                playerTrack: src.playerTrackID, transcription: tr, progress: progress[src.id], error: failures[src.id],
                fingerprint: fingerprints[src.id], noteCount: 0, muted: m?.muted ?? false, solo: m?.solo ?? false,
                dimmed: false, listening: false, synth: nil))
        }
        var err: String?
        if case let .failed(m) = phase { err = m }
        let selInfo = selection.map {
            TabSelectionInfo(track: $0.trackID, beat: $0.point.beat, tick: $0.point.tick, string: $0.string, summary: selectionSummary,
                             barRange: selectedBarRange, hasNote: selectedNote != nil)
        }
        let sourceName: String? = switch session?.project.tabSource {
        case .songsterr?: "songsterr"
        case .automatic?: "automatic"
        case nil: nil
        }
        return TabState(
            projectId: session?.projectID.uuidString ?? "", phase: phase.name, error: err, header: header, source: sourceName,
            tracks: infos, selectedTrack: selectedTrackID, notices: notices, canUndo: canUndo, canRedo: canRedo,
            editMode: editMode, graceMode: graceMode, listenMode: listenMode.rawValue, anySolo: anySolo,
            selection: selInfo, span: span.map { TabSpanInfo(startTick: $0.startTick, endTick: $0.endTick) },
            revision: revision, flash: flash, handled: nil)
    }
}
