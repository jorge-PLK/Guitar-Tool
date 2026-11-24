import AudioKit
import Foundation
import Store

// Ediciones del estudio (parte 8.5b): análisis, tonalidad, acordes, secciones y guitarras. Contrato: `Temp/win/step8-contract.md`,
// «8.5b». Mismo comportamiento y reglas que el Mac (`StudySession`, `ChordEditor`, `SectionEditor`); todo se guarda por el
// mismo camino con rebote de `StudySession` y por `Library` (un solo escritor).

// MARK: - Constantes (reglas del Mac)

enum StudyEditConstants {
    /// `ChordEditor.splitBeat`: el pulso de «Partir aquí» debe quedar a más de 50 ms de los dos extremos.
    static let splitMargin = 0.05
    /// Margen al comparar con la duración del tema (decimas de segundo de redondeo del reloj no cuentan como «fuera»).
    static let durationSlack = 0.01
}

// MARK: - Tipos JSON

struct StudyGuitarsInfo: Codable, Sendable {
    var stereoSplit: Bool
    var usesSeparatedGuitars: Bool
    var names: [String: String]
    /// `idle`, `processing` o `failed` (paso de guitarras de la cola).
    var process: String
    var error: String?
    var saveError: String?
}

struct StudyPreviewSections: Codable, Sendable { var sections: [StudySectionInfo] }

struct StudyEditState: Codable, Sendable {
    var analysis: StudyAnalysisInfo
    var chordOverrides: [StudyOverrideInfo]
    var sections: [StudySectionInfo]
    var unappliedSections: Bool
    var loops: [StudySavedLoop]
    var guitars: StudyGuitarsInfo
    var added: String?
    var transport: StudyTransport
}

struct StudyAnalysisEvent: Codable, Sendable {
    var state: String
    var error: String?
}

struct StudySetKeyParams: Decodable, Sendable { var key: String? }
struct StudySetChordParams: Decodable, Sendable { var start: Double; var end: Double; var index: Int?; var label: String? }
struct StudyChordRangeParams: Decodable, Sendable { var start: Double; var end: Double }
struct StudySplitChordParams: Decodable, Sendable { var at: Double }
struct StudyMarkSectionParams: Decodable, Sendable { var start: Double; var end: Double; var solo: Bool?; var snap: String? }
struct StudyDeleteSectionParams: Decodable, Sendable { var id: String }
/// `snap`: `none` (por defecto), `chord` o `bar` (⌥): imán de `SectionEdgeDrag` (mini-spec Fase 7b, punto 7).
struct StudyPreviewSectionEdgeParams: Decodable, Sendable { var id: String; var start: Bool; var to: Double; var snap: String? }
struct StudyNudgeSectionParams: Decodable, Sendable { var id: String; var start: Bool; var forward: Bool; var bar: Bool? }
struct StudyRenameGuitarParams: Decodable, Sendable { var role: String; var name: String }
struct StudyGuitarStereoParams: Decodable, Sendable { var on: Bool }

/// `color` distingue ausente (no cambia) de `null` (automático).
struct StudyUpdateSectionParams: Decodable, Sendable {
    var id: String
    var name: String?
    var start: Double?
    var end: Double?
    var solo: Bool?
    var snap: String?
    var colorGiven = false
    var color: Int?

    private enum Keys: String, CodingKey { case id, name, start, end, solo, snap, color }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        start = try c.decodeIfPresent(Double.self, forKey: .start)
        end = try c.decodeIfPresent(Double.self, forKey: .end)
        solo = try c.decodeIfPresent(Bool.self, forKey: .solo)
        snap = try c.decodeIfPresent(String.self, forKey: .snap)
        colorGiven = c.contains(.color)
        color = colorGiven ? try c.decodeIfPresent(Int.self, forKey: .color) : nil
    }
}

// MARK: - Enlace con la cola

/// Cola de trabajos y estado de eventos que el servicio de estudio necesita (la pone `Bridge`; cualquier hilo).
final class StudyEditsLink: @unchecked Sendable {
    private let lock = NSLock()
    private var _jobs: JobEngine?
    private var _lastAnalysis: String?
    private var _process: [UUID: (state: String, error: String?)] = [:]

    var jobs: JobEngine? {
        get { lock.withLock { _jobs } }
        set { lock.withLock { _jobs = newValue } }
    }
    /// Devuelve true si es distinto de lo último emitido (evita repetir `study.analysis`).
    func markAnalysis(_ key: String) -> Bool {
        lock.withLock {
            if _lastAnalysis == key { return false }
            _lastAnalysis = key
            return true
        }
    }
    func process(_ id: UUID) -> (state: String, error: String?) { lock.withLock { _process[id] ?? ("idle", nil) } }
    func setProcess(_ id: UUID, _ state: String, _ error: String? = nil) { lock.withLock { _process[id] = (state, error) } }
}

// MARK: - Servicio

extension StudyService {
    nonisolated func attach(jobs: JobEngine) {
        edits.jobs = jobs
        jobs.setLibraryObserver { [weak self] e in
            Task { @MainActor in self?.libraryEvent(e) }
        }
        jobs.setFileReleaser { [weak self] id, files in await self?.releaseFiles(id, files) }
    }

    nonisolated func registerEdits(on router: Router) {
        router.register("study.snapshot") { [self] (_: Empty) -> StudyOpenResult in try await snapshotCurrent() }
        router.register("study.analyze") { [self] (_: Empty) -> StudyEditState in try await analyze() }
        router.register("study.setKey") { [self] (p: StudySetKeyParams) -> StudyEditState in try await setKey(p) }
        router.register("study.setChord") { [self] (p: StudySetChordParams) -> StudyEditState in try await setChord(p) }
        router.register("study.removeChordOverrides") { [self] (p: StudyChordRangeParams) -> StudyEditState in
            try await edit { s, _ in
                guard p.start.isFinite, p.end.isFinite, p.end >= p.start else {
                    throw RPCError(code: "bad-params", message: "«start» y «end» deben ser tiempos con end >= start.")
                }
                s.removeChordOverrides(in: p.start...p.end)
            }
        }
        router.register("study.clearChordOverrides") { [self] (_: Empty) -> StudyEditState in
            try await edit { s, _ in s.clearChordOverrides() }
        }
        router.register("study.splitChord") { [self] (p: StudySplitChordParams) -> StudyEditState in try await splitChord(p) }
        router.register("study.markSection") { [self] (p: StudyMarkSectionParams) -> StudyEditState in try await markSection(p) }
        router.register("study.updateSection") { [self] (p: StudyUpdateSectionParams) -> StudyEditState in
            try await updateSection(p)
        }
        router.register("study.previewSectionEdge") { [self] (p: StudyPreviewSectionEdgeParams) -> StudyPreviewSections in
            try await previewSectionEdge(p)
        }
        router.register("study.nudgeSectionEdge") { [self] (p: StudyNudgeSectionParams) -> StudyEditState in
            try await edit { s, _ in
                let id = try Self.sectionID(p.id, in: s)
                let b = p.bar == true ? s.downbeats : Self.chordBoundaries(s)
                Self.editSections(s) { $0.nudgeEdge(id, start: p.start, forward: p.forward, boundaries: b) }
            }
        }
        router.register("study.deleteSection") { [self] (p: StudyDeleteSectionParams) -> StudyEditState in
            try await edit { s, _ in
                let id = try Self.sectionID(p.id, in: s)
                Self.editSections(s) { $0.remove(id) }
            }
        }
        router.register("study.applySections") { [self] (_: Empty) -> StudyEditState in
            try await edit(async: { s, _ in
                await s.applySectionsNow()
                if let e = s.guitarOptionsError { throw RPCError(code: "save-failed", message: e) }
            })
        }
        router.register("study.discardSections") { [self] (_: Empty) -> StudyEditState in
            try await edit { s, _ in s.discardSections() }
        }
        router.register("study.renameGuitar") { [self] (p: StudyRenameGuitarParams) -> StudyEditState in
            try await edit { s, _ in
                guard let role = GuitarRole(rawValue: p.role) else {
                    throw RPCError(code: "bad-params", message: "«role» no es una guitarra (rhythm, left, right, lead): \(p.role)")
                }
                let n = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
                s.pendingNames[role] = n.isEmpty ? role.defaultName : n
            }
        }
        router.register("study.setGuitarStereo") { [self] (p: StudyGuitarStereoParams) -> StudyEditState in
            try await edit(async: { s, _ in
                s.guitarOptionsError = nil
                do { _ = try await s.store.saveGuitarStereoSplit(id: s.projectID, p.on) } catch {
                    let m = "No se pudieron guardar las opciones: \(error.localizedDescription)"
                    s.guitarOptionsError = m
                    s.reload()
                    throw RPCError(code: "save-failed", message: m)
                }
                s.reload()
            })
        }
    }

    // MARK: Ayudas

    /// Ejecuta una edición y devuelve el estado ya al día; cualquier cambio emite `study.state`.
    func edit(_ body: @MainActor (StudySession, BackingController) throws -> Void) async throws
        -> StudyEditState {
        guard let o = current else { throw RPCError(code: "not-open", message: "No hay ningún tema abierto en Backing.") }
        defer { stateChanged() }
        try body(o.session, o.controller)
        reloadTracksIfChanged(o)
        return editState(o, added: nil)
    }

    func edit(async body: @MainActor (StudySession, BackingController) async throws -> Void) async throws -> StudyEditState {
        guard let o = current else { throw RPCError(code: "not-open", message: "No hay ningún tema abierto en Backing.") }
        defer { stateChanged() }
        try await body(o.session, o.controller)
        reloadTracksIfChanged(o)
        guard current?.session === o.session else { throw RPCError(code: "not-open", message: "El tema se cerró.") }
        return editState(o, added: nil)
    }

    func guitarsInfo(_ s: StudySession) -> StudyGuitarsInfo {
        var names: [String: String] = [:]
        for r in GuitarRole.allCases { names[r.rawValue] = s.guitarName(r) }
        let p = edits.process(s.projectID)
        return StudyGuitarsInfo(stereoSplit: s.project.guitarSettings.stereoSplit, usesSeparatedGuitars: s.usesSeparatedGuitars,
                                names: names, process: p.state, error: p.error, saveError: s.guitarOptionsError ?? s.saveError)
    }

    func editState(_ o: StudyOpen, added: UUID?) -> StudyEditState {
        let s = o.session
        let guitars = guitarsInfo(s)
        return StudyEditState(
            analysis: analysisInfo(s),
            chordOverrides: s.study.chordOverrides.map { StudyOverrideInfo(start: $0.start, end: $0.end, index: $0.index) },
            sections: sectionInfos(s), unappliedSections: s.hasUnappliedSections,
            loops: s.study.loops.map { StudySavedLoop(id: $0.id.uuidString, name: $0.name, start: $0.start, end: $0.end) },
            guitars: guitars, added: added?.uuidString, transport: transport(s, o.controller))
    }

    func analysisInfo(_ s: StudySession) -> StudyAnalysisInfo {
        let detected = Set((s.analysis?.chords ?? []).map { "\($0.start)|\($0.end)|\($0.index)" })
        let chords = s.effectiveChords.map {
            StudyChord(start: $0.start, end: $0.end, index: $0.index, name: StudyKitBridge.chordName($0.index),
                       overridden: !detected.contains("\($0.start)|\($0.end)|\($0.index)"))
        }
        let (state, error) = Self.analysisLabel(s.analysisState)
        let a = s.analysis
        return StudyAnalysisInfo(
            state: state, error: error, beats: s.beats, downbeats: s.downbeats, bpm: a?.bpm, beatsPerBar: a?.beatsPerBar,
            chords: chords,
            key: StudyKey(detected: a?.key, override: s.study.keyOverride, effective: s.effectiveKey, confidence: a?.keyConfidence))
    }

    func sectionInfos(_ s: StudySession) -> [StudySectionInfo] { sectionInfos(s.sections) }

    func sectionInfos(_ sections: [Section]) -> [StudySectionInfo] {
        let palette = SectionEditor.paletteIndices(sections)
        return sections.map {
            StudySectionInfo(id: $0.id.uuidString, name: $0.name, start: $0.start, end: $0.end, solo: $0.isSolo,
                             color: $0.color, paletteIndex: palette[$0.id])
        }
    }

    static func analysisLabel(_ state: AnalysisState) -> (String, String?) {
        switch state {
        case .missing: ("missing", nil)
        case .analyzing: ("analyzing", nil)
        case .ready: ("ready", nil)
        case let .failed(m): ("failed", m)
        }
    }

    static func chordBoundaries(_ s: StudySession) -> [Double] {
        Array(Set(s.effectiveChords.flatMap { [$0.start, $0.end] })).sorted()
    }

    /// Imán del arrastre de un borde, la regla de `SectionEdgeDrag.snappedTime`: los límites de acorde (o los compases con
    /// `bar`, si hay) más el borde original. `none` = sin imán (nil). Probado contra `SectionEdgeDrag` en `StudySnapTests`.
    static func edgeMagnet(_ snap: String, _ s: StudySession, original: Double) -> [Double]? {
        switch snap {
        case "chord": return chordBoundaries(s) + [original]
        case "bar": return (s.downbeats.isEmpty ? chordBoundaries(s) : Array(Set(s.downbeats)).sorted()) + [original]
        default: return nil
        }
    }

    static func sectionID(_ text: String, in s: StudySession) throws -> UUID {
        guard let id = UUID(uuidString: text) else { throw RPCError(code: "bad-params", message: "«id» no es un UUID.") }
        guard s.sections.contains(where: { $0.id == id }) else {
            throw RPCError(code: "not-found", message: "No hay ninguna sección con id \(text).")
        }
        return id
    }

    /// Aplica una edición de `SectionEditor` a las secciones en edición (como `StudySession.edit` del Mac).
    @discardableResult
    static func editSections<R>(_ s: StudySession, _ body: (inout SectionEditor) -> R) -> R {
        var e = SectionEditor(sections: s.sections, duration: s.project.song.duration)
        let r = body(&e)
        if e.sections != s.sections { s.sections = e.sections }
        return r
    }

    /// La biblioteca va a sustituir o borrar `files` del proyecto `id` (aplicar guitarras): si es el tema abierto, el
    /// reproductor los suelta antes de volver (NTFS no deja sustituir un fichero abierto, `MoveFileEx` error 5). Al
    /// llegar `guitarSplitFinished`/`guitarSplitFailed`, `reloadTracksIfChanged` los vuelve a abrir.
    func releaseFiles(_ id: UUID, _ files: [URL]) {
        guard let o = current, o.session.projectID == id else { return }
        let drop = Set(files.map(\.standardizedFileURL.path))
        guard o.controller.player.tracks.contains(where: { drop.contains($0.url.standardizedFileURL.path) }) else { return }
        o.controller.loadTracks(excluding: drop)
    }

    /// Igual que `BackingView`: si cambian los stems o las pistas de guitarra, se recargan en el reproductor.
    func reloadTracksIfChanged(_ o: StudyOpen) {
        let layout = o.session.layout
        let exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
        let wanted = Set(o.session.mixerStems.filter { exists(layout.stemURL($0)) }.map(\.rawValue)
                         + o.session.guitarTracks.filter { exists(layout.guitarURL($0.role)) }.map(\.role.trackID))
        let extra = Set(o.controller.extraTracks.map(\.id))
        let loaded = Set(o.controller.player.tracks.map(\.id)).subtracting(extra)
        if wanted != loaded, !wanted.isEmpty { o.controller.loadTracks() }
    }

    // MARK: Análisis

    func snapshotCurrent() async throws -> StudyOpenResult {
        guard let o = current else { throw RPCError(code: "not-open", message: "No hay ningún tema abierto en Backing.") }
        return snapshot(o.session, o.controller)
    }

    func emitAnalysis(_ s: StudySession) {
        let (state, error) = Self.analysisLabel(s.analysisState)
        guard edits.markAnalysis("\(s.projectID)|\(state)|\(error ?? "")") else { return }
        emit("study.analysis", StudyAnalysisEvent(state: state, error: error))
    }

    func analyze() async throws -> StudyEditState {
        guard let o = current else { throw RPCError(code: "not-open", message: "No hay ningún tema abierto en Backing.") }
        let s = o.session
        guard let jobs = edits.jobs else { throw RPCError(code: "analysis-unavailable", message: "No hay cola de análisis.") }
        guard let p = try? ProjectFile.load(folder: s.folder), p.separation.state == .done else {
            throw RPCError(code: "not-separated", message: "El tema no tiene la separación terminada: no se puede analizar.")
        }
        let state: AnalysisState
        do { state = try await jobs.library().ensureAnalysis(id: s.projectID) } catch { throw JobEngine.map(error) }
        guard current?.session === s else { throw RPCError(code: "not-open", message: "El tema se cerró.") }
        switch state {
        case .analyzing:
            if s.analysisState != .ready { s.setAnalysisState(.analyzing) }
        case .ready:
            s.reload()
            s.setAnalysisState(.ready)
            o.controller.refreshMetronome()
        case let .failed(m):
            s.setAnalysisState(.failed(m))
        case .missing:
            throw RPCError(code: "analysis-unavailable",
                           message: "No se puede analizar ahora: no hay analizador o el tema aún está en la cola de separación.")
        }
        emitAnalysis(s)
        stateChanged()
        return editState(o, added: nil)
    }

    /// Eventos de la cola que afectan al tema abierto (llegan en cualquier hilo y saltan al principal).
    func libraryEvent(_ e: LibraryEvent) {
        guard let o = current else { return }
        let s = o.session
        switch e {
        case .analysisQueued(let id), .analysisStarted(let id):
            guard id == s.projectID else { return }
            s.setAnalysisState(.analyzing)
            emitAnalysis(s)
        case .analysisFinished(let id):
            guard id == s.projectID else { return }
            // Solo se relee y se recalculan los clics: el reproductor, la posición y el bucle siguen como están.
            s.reload()
            s.setAnalysisState(.ready)
            o.controller.refreshMetronome()
            emitAnalysis(s)
            stateChanged()
        case .analysisFailed(let id, let message):
            guard id == s.projectID else { return }
            s.setAnalysisState(.failed(message))
            emitAnalysis(s)
        case .stemsMeasured(let id):
            guard id == s.projectID else { return }
            s.reload()
            reloadTracksIfChanged(o)
            stateChanged()
        case .guitarSplitQueued(let id), .guitarSplitStarted(let id):
            if id == s.projectID { notifyGuitars(id, "processing") }
        case .guitarSplitFinished(let id):
            guard id == s.projectID else { return }
            edits.setProcess(id, "idle")
            s.reload()
            reloadTracksIfChanged(o)
            emitGuitars("idle", nil)
            stateChanged()
        case .guitarSplitFailed(let id, let message):
            guard id == s.projectID else { return }
            reloadTracksIfChanged(o)   // si falló tras soltar las pistas (`releaseFiles`), se vuelven a abrir
            notifyGuitars(id, "failed", message)
        default:
            break
        }
    }

    /// Trabajo de guitarras: guarda el estado, avisa a la página (`study.guitars`: ella relee el snapshot, como el Mac
    /// refresca la hoja al cambiar `guitarProcess`) y pide `study.state`.
    func notifyGuitars(_ id: UUID, _ state: String, _ error: String? = nil) {
        edits.setProcess(id, state, error)
        emitGuitars(state, error)
        stateChanged()
    }

    func emitGuitars(_ state: String, _ error: String?) {
        emit("study.guitars", StudyAnalysisEvent(state: state, error: error))
    }

    // MARK: Tonalidad y acordes

    func setKey(_ p: StudySetKeyParams) async throws -> StudyEditState {
        try await edit { s, _ in
            guard let text = p.key else { s.setKeyOverride(nil); return }
            guard let key = StudyEditsBridge.normalizedKey(text) else {
                throw RPCError(code: "bad-params", message: "«key» no es una tonalidad mayor o menor («C:maj», «A:min»): \(text)")
            }
            guard s.analysis != nil else {
                throw RPCError(code: "no-analysis", message: "Aún no hay análisis: la tonalidad no se puede corregir.")
            }
            s.setKeyOverride(key)
        }
    }

    func setChord(_ p: StudySetChordParams) async throws -> StudyEditState {
        try await edit { s, _ in
            guard p.start.isFinite, p.end.isFinite, p.start >= 0, p.end > p.start else {
                throw RPCError(code: "bad-params", message: "«start» y «end» deben ser tiempos con 0 <= start < end.")
            }
            let index: Int
            switch (p.index, p.label) {
            case let (i?, nil):
                guard StudyEditsBridge.isValidChordIndex(i) else {
                    throw RPCError(code: "bad-params", message: "«index» fuera de 0...169: \(i)")
                }
                index = i
            case let (nil, l?):
                guard let i = StudyEditsBridge.chordIndex(label: l) else {
                    throw RPCError(code: "bad-params", message: "«label» no se reconoce como acorde («C:min», «F#:7», «N»): \(l)")
                }
                index = i
            default:
                throw RPCError(code: "bad-params", message: "Indica «index» o «label» (solo uno).")
            }
            s.setChord(start: p.start, end: p.end, index: index)
        }
    }

    func splitChord(_ p: StudySplitChordParams) async throws -> StudyEditState {
        try await edit { s, _ in
            guard p.at.isFinite else { throw RPCError(code: "bad-params", message: "«at» no es un tiempo.") }
            // `ChordEditor.splitBeat`: el acorde que contiene el cursor y el pulso más cercano, con margen de 50 ms.
            guard let seg = s.effectiveChords.first(where: { $0.start < p.at && p.at < $0.end }) else {
                throw RPCError(code: "cannot-split", message: "No hay ningún acorde en ese instante.")
            }
            let b = StudyEditsBridge.nearestBeat(s.beats, to: p.at)
            guard b > seg.start + StudyEditConstants.splitMargin, b < seg.end - StudyEditConstants.splitMargin else {
                throw RPCError(code: "cannot-split", message: "El pulso más cercano cae fuera del acorde (a menos de 50 ms de un extremo).")
            }
            s.setChord(start: seg.start, end: b, index: seg.index)
            s.setChord(start: b, end: seg.end, index: seg.index)
        }
    }

    // MARK: Secciones

    func markSection(_ p: StudyMarkSectionParams) async throws -> StudyEditState {
        guard let o = current else { throw RPCError(code: "not-open", message: "No hay ningún tema abierto en Backing.") }
        defer { stateChanged() }
        let s = o.session
        let duration = s.project.song.duration
        guard p.start.isFinite, p.end.isFinite, p.start >= 0, p.end > p.start,
              p.end <= max(duration, o.controller.duration) + StudyEditConstants.durationSlack else {
            throw RPCError(code: "bad-params", message: "«start» y «end» deben ser tiempos con 0 <= start < end <= duración.")
        }
        var range = p.start...p.end
        switch p.snap ?? "none" {
        case "none": break
        case "beat": range = StudyEditsBridge.snap(beats: s.beats, downbeats: s.downbeats, range, bar: false)
        case "bar": range = StudyEditsBridge.snap(beats: s.beats, downbeats: s.downbeats, range, bar: true)
        default: throw RPCError(code: "bad-params", message: "«snap» debe ser none, beat o bar.")
        }
        guard let id = Self.editSections(s, { $0.mark(range, solo: p.solo == true) }) else {
            throw RPCError(code: "section-not-created",
                           message: "No se crea: empieza dentro de otra sección o queda más corta de \(SectionEditor.minLength) s.")
        }
        return editState(o, added: id)
    }

    /// Vista previa del arrastre de un borde: mismas reglas que `updateSection` sin ajuste (`setEdge` con `clampedEdge`)
    /// sobre una copia. No cambia estado, no emite `study.state`, no guarda.
    func previewSectionEdge(_ p: StudyPreviewSectionEdgeParams) throws -> StudyPreviewSections {
        guard let o = current else { throw RPCError(code: "not-open", message: "No hay ningún tema abierto en Backing.") }
        let s = o.session
        let id = try Self.sectionID(p.id, in: s)
        guard p.to.isFinite else { throw RPCError(code: "bad-params", message: "«to» debe ser un tiempo.") }
        let snap = p.snap ?? "none"
        guard ["none", "chord", "bar"].contains(snap) else {
            throw RPCError(code: "bad-params", message: "«snap» debe ser none, chord o bar.")
        }
        var e = SectionEditor(sections: s.sections, duration: s.project.song.duration)
        var to = p.to
        if let original = e.section(id).map({ p.start ? $0.start : $0.end }), let m = Self.edgeMagnet(snap, s, original: original) {
            to = SectionEditor.snap(to, to: m)
        }
        e.setEdge(id, start: p.start, to: to)
        return StudyPreviewSections(sections: sectionInfos(e.sections))
    }

    func updateSection(_ p: StudyUpdateSectionParams) async throws -> StudyEditState {
        try await edit { s, _ in
            let id = try Self.sectionID(p.id, in: s)
            for t in [p.start, p.end].compactMap({ $0 }) where !t.isFinite {
                throw RPCError(code: "bad-params", message: "«start» y «end» deben ser tiempos.")
            }
            if p.colorGiven, let c = p.color, !(0..<SectionEditor.paletteCount).contains(c) {
                throw RPCError(code: "bad-params", message: "«color» fuera de la paleta (0...\(SectionEditor.paletteCount - 1)).")
            }
            let snap = p.snap ?? "none"
            guard ["none", "beat", "bar", "chord"].contains(snap) else {
                throw RPCError(code: "bad-params", message: "«snap» debe ser none, beat, bar o chord.")
            }
            let beats = s.beats
            // El nombre explícito va después de «solo»: así manda sobre el nombre por defecto que sigue a la marca.
            if let solo = p.solo { Self.editSections(s) { $0.setSolo(id, solo) } }
            if let name = p.name { Self.editSections(s) { $0.rename(id, to: name) } }
            if p.colorGiven { Self.editSections(s) { $0.setColor(id, p.color) } }
            @MainActor func move(_ time: Double, start: Bool) {
                Self.editSections(s) { e in
                    switch snap {
                    case "beat": e.setEdge(id, start: start, to: StudyEditsBridge.nearestBeat(beats, to: time))
                    case "bar", "chord":
                        // Imán de `SectionEdgeDrag`: incluye el borde original (`edgeMagnet`).
                        let original = e.section(id).map { start ? $0.start : $0.end } ?? time
                        let m = Self.edgeMagnet(snap, s, original: original) ?? []
                        e.setEdge(id, start: start, to: SectionEditor.snap(time, to: m))
                    default: e.setEdge(id, start: start, to: time)
                    }
                }
            }
            let current = s.sections.first { $0.id == id }
            // Hacia la derecha, primero el final: si no, el inicio toparía con el final antiguo.
            if let a = p.start, let b = p.end, let cur = current, a > cur.start {
                move(b, start: false); move(a, start: true)
            } else {
                if let a = p.start { move(a, start: true) }
                if let b = p.end { move(b, start: false) }
            }
        }
    }
}
