import Foundation
import Store
import StudyKit

/// Guarda lo del usuario en `project.json`. En el Mac y en Windows lo hace `Library` (cola de trabajos de 8.3a, que
/// serializa con el resto de escrituras del proyecto); `FileStudyStore` es la versión directa para tests y para cuando
/// no hay biblioteca.
protocol StudyStoring: Sendable {
    func saveStudy(id: UUID, study: StudyState, sections: [Section]) async throws
    /// Nombres de las pistas de guitarra por papel (vacío = el de por defecto). Parte 8.5b.
    func saveGuitarNames(id: UUID, names: [GuitarRole: String]) async throws
    /// Interruptor «Guitarras en L y R». Parte 8.5b.
    @discardableResult
    func saveGuitarStereoSplit(id: UUID, _ on: Bool) async throws -> GuitarOptions
}

extension Library: StudyStoring {}

/// Escritura de tomas y del estado de grabación por partes (W2-R1, Grabar). Aparte de `StudyStoring` para no obligar a los
/// almacenes que solo guardan el estudio; `StudySession` los usa si el suyo lo cumple (`Library`, `FileStudyStore`, `QueueStudyStore`).
protocol TakeStoring: Sendable {
    /// Añade o sustituye (por id) tomas del proyecto. Solo toca `takes`.
    func saveTakes(id: UUID, _ takes: [Take]) async throws
    /// Solo toca `recording`.
    func saveRecording(id: UUID, _ recording: RecordingState) async throws
}

extension Library: TakeStoring {}

extension QueueStudyStore: TakeStoring {
    func saveTakes(id: UUID, _ takes: [Take]) async throws { try await jobs.library().saveTakes(id: id, takes) }
    func saveRecording(id: UUID, _ recording: RecordingState) async throws {
        try await jobs.library().saveRecording(id: id, recording)
    }
}

/// Escritura directa de `project.json` (carga, cambia `study` y `sections`, guarda). Un cerrojo serializa las escrituras de
/// este proceso; no coordina con una `Library` que escriba el mismo tema a la vez.
final class FileStudyStore: StudyStoring, @unchecked Sendable {
    private let folder: URL
    private let lock = NSLock()
    init(folder: URL) { self.folder = folder }

    func saveStudy(id: UUID, study: StudyState, sections: [Section]) async throws {
        try lock.withLock {
            var p = try ProjectFile.load(folder: folder)
            p.study = study
            p.sections = sections
            p.updatedAt = Date()
            try ProjectFile.save(p, to: folder)
        }
    }

    func saveGuitarNames(id: UUID, names: [GuitarRole: String]) async throws {
        try lock.withLock {
            var p = try ProjectFile.load(folder: folder)
            for (role, raw) in names {
                let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = n.isEmpty ? role.defaultName : n
                if let i = p.guitars.firstIndex(where: { $0.role == role }) { p.guitars[i].name = name } else { p.guitars.append(Guitar(role: role, name: name)) }
            }
            p.updatedAt = Date()
            try ProjectFile.save(p, to: folder)
        }
    }

    func saveGuitarStereoSplit(id: UUID, _ on: Bool) async throws -> GuitarOptions {
        try lock.withLock {
            var p = try ProjectFile.load(folder: folder)
            p.guitarSettings.stereoSplit = on
            p.updatedAt = Date()
            try ProjectFile.save(p, to: folder)
            return p.guitarOptions
        }
    }
}

extension FileStudyStore: TakeStoring {
    func saveTakes(id: UUID, _ takes: [Take]) async throws {
        try lock.withLock {
            var p = try ProjectFile.load(folder: folder)
            for t in takes {
                if let i = p.takes.firstIndex(where: { $0.id == t.id }) { p.takes[i] = t } else { p.takes.append(t) }
            }
            p.updatedAt = Date()
            try ProjectFile.save(p, to: folder)
        }
    }

    func saveRecording(id: UUID, _ recording: RecordingState) async throws {
        try lock.withLock {
            var p = try ProjectFile.load(folder: folder)
            p.recording = recording
            p.updatedAt = Date()
            try ProjectFile.save(p, to: folder)
        }
    }
}

/// Estado de estudio del proyecto abierto en Backing (copia portátil de `App/Sources/StudySession.swift`, mini-spec Fase 2
/// §1 Store, §2). Sin UI ni reproductor; lo del usuario se guarda en `project.json` con rebote.
/// Parte 8.5: solo lectura de acordes, tonalidad y secciones desde la página; los métodos de edición están para la parte
/// siguiente y para Tablatura.
@MainActor
final class StudySession {
    /// Rebote del guardado (segundos): se agrupan las ediciones seguidas en una sola escritura (igual que el Mac).
    static let saveDelay = 0.5
    static let transposeRange = -12...12
    static let fineCentsRange = -50.0...50.0
    static let rateRange = 0.5...2.0

    let projectID: UUID
    let folder: URL
    private(set) var project: Project
    private(set) var analysis: StudyKitBridge.Analysis?
    private(set) var analysisState: AnalysisState
    /// Último fallo al guardar (nil si fue bien); lo lee quien quiera avisar.
    var saveError: String?
    /// Se llama tras cada cambio de `study` (el servicio emite `study.state`).
    var onChange: (() -> Void)?

    /// Lo del usuario. Cualquier cambio programa el guardado.
    var study: StudyState { didSet { if study != oldValue { scheduleSave() } } }
    /// Secciones en edición: locales hasta `applySections`. Lo guardado está en `project.sections`.
    var sections: [Section]

    let store: any StudyStoring
    var saveTask: Task<Void, Never>?
    /// Nombres de guitarra editados y aún sin guardar (con rebote; parte 8.5b).
    var pendingNames: [GuitarRole: String] = [:] { didSet { if !pendingNames.isEmpty { scheduleSave() } } }
    /// Error al guardar las opciones o los nombres de guitarra (8.5b).
    var guitarOptionsError: String?
    /// Hay cambios de `study` aún sin escribir (o escribiéndose).
    private(set) var hasPendingSave = false

    var layout: ProjectLayout { ProjectLayout(folder: folder) }

    init(project: Project, folder: URL, store: any StudyStoring, analysisState: AnalysisState = .missing) {
        self.projectID = project.id
        self.folder = folder
        self.project = project
        self.store = store
        self.study = project.study
        self.sections = project.sections
        self.analysisState = analysisState
        loadAnalysis()
    }

    // MARK: Análisis

    /// Stems con fichero (los vacíos no tienen; el mezclador los pinta como «vacío»).
    var audibleStems: [StemKind] { project.stems.filter { !$0.isEmpty }.map(\.kind) }
    var emptyStems: [StemKind] { project.stems.filter(\.isEmpty).map(\.kind) }

    /// Relee `project.json` y la caché tras un evento (`stemsMeasured`, `analysisFinished`).
    func reload() {
        if let p = try? ProjectFile.load(folder: folder) {
            let dirty = hasUnappliedSections
            project = p
            if !dirty { sections = p.sections }
        }
        loadAnalysis()
    }

    private func loadAnalysis() {
        if songsterrGrid == nil { songsterrGrid = SongsterrGridFile.load(layout.tabSongsterrGridFile) }
        let source = StudyKitBridge.Source(separationModel: project.separation.model,
                                           separationFinishedAt: project.separation.finishedAt,
                                           sourceSHA256: project.song.sourceSHA256)
        analysis = StudyKitBridge.loadCached(source, cache: layout.analysisCache)
        if analysis != nil, analysisState != .analyzing { analysisState = .ready }
    }

    func setAnalysisState(_ s: AnalysisState) {
        analysisState = s
        if s == .ready { loadAnalysis() }
    }

    /// Acordes detectados con las correcciones del usuario encima.
    var effectiveChords: [StudyKitBridge.Chord] {
        StudyKitBridge.effectiveChords(detected: analysis?.chords ?? [],
                                       overrides: study.chordOverrides.map { ($0.start, $0.end, $0.index) })
    }

    /// `keyOverride` si el usuario la corrigió; si no, la detectada («C:maj», «A:min»).
    var effectiveKey: String? { study.keyOverride ?? analysis?.key }

    /// Pulsos y compases del análisis (el Mac los llama `BeatGrid`); la rejilla corregida desde Songsterr es de Tablatura.
    var beats: [Double] { analysis?.beats ?? [] }
    var downbeats: [Double] { analysis?.downbeats ?? [] }
    var hasBeatGrid: Bool { beats.count >= 2 }

    /// Rejilla de Songsterr guardada (puede ser de otro tema; `metronomeBeats` lo comprueba). Igual que el Mac: se lee de
    /// disco mientras sea nil, en cada `loadAnalysis`.
    var songsterrGrid: SongsterrGridFile?

    /// Rejilla del metrónomo de Backing (igual que `StudySession.metronomeBeats` del Mac): la corregida desde Songsterr si
    /// la fuente de la tablatura es ese mismo tema y revisión (y trae al menos 2 pulsos); si no, la del análisis.
    var metronomeBeats: (beats: [Double], downbeats: [Double])? {
        if case let .songsterr(songId, revisionId, _)? = project.tabSource,
           let grid = songsterrGrid?.metronomeGrid(songId: songId, revisionId: revisionId) {
            return (grid.beats, grid.downbeats)
        }
        return hasBeatGrid ? (beats, downbeats) : nil
    }

    // MARK: Guitarras (Fase 4)

    /// Pistas de guitarra con fichero en disco, en el orden de `GuitarRole.allCases`.
    var guitarTracks: [Guitar] {
        project.guitarTracks.filter { g in
            g.file.map { FileManager.default.fileExists(atPath: layout.url(relative: $0).path) } == true
        }
    }

    /// Hay pistas separadas: sustituyen al canal «Guitarras» del mezclador (no se suman dos veces).
    var usesSeparatedGuitars: Bool { !guitarTracks.isEmpty }

    /// Stems con canal propio en el mezclador (sin `guitar` si se muestran las pistas separadas).
    var mixerStems: [StemKind] { usesSeparatedGuitars ? audibleStems.filter { $0 != .guitar } : audibleStems }

    func guitarName(_ role: GuitarRole) -> String { pendingNames[role] ?? project.guitarName(role) }

    // MARK: Ediciones (lo que la página lee ya y editará la parte siguiente)

    /// Pone `index` en `[start, end]`: los tramos del usuario mandan; solapes, gana el último (lo da `ChordTimeline`).
    func setChord(start: Double, end: Double, index: Int) {
        guard end > start else { return }
        study.chordOverrides.append(ChordOverride(start: start, end: end, index: index))
    }

    func removeChordOverrides(in range: ClosedRange<Double>) {
        study.chordOverrides.removeAll { $0.start < range.upperBound && $0.end > range.lowerBound }
    }

    func clearChordOverrides() { study.chordOverrides = [] }

    func setKeyOverride(_ key: String?) { study.keyOverride = key }

    /// Hay secciones editadas sin aplicar.
    var hasUnappliedSections: Bool { sections != project.sections }

    func discardSections() { sections = project.sections }

    /// Guarda las secciones en edición (con `Library`, también rehace las pistas de guitarra si cambian los solos).
    func applySections() {
        let applied = sections
        project.sections = applied
        saveTask?.cancel()
        let (store, id, study) = (self.store, projectID, self.study)
        Task { [weak self] in
            do { try await store.saveStudy(id: id, study: study, sections: applied) } catch {
                self?.saveError = "No se pudieron guardar las secciones: \(error.localizedDescription)"
            }
            self?.reload()
        }
    }

    /// Como `applySections` pero espera a que termine el guardado (8.5b: `study.applySections` responde con lo ya escrito).
    func applySectionsNow() async {
        let applied = sections
        guitarOptionsError = nil
        project.sections = applied
        saveTask?.cancel()
        saveTask = nil
        let written = study
        do {
            try await store.saveStudy(id: projectID, study: written, sections: applied)
            if study == written { hasPendingSave = false }
        } catch {
            guitarOptionsError = "No se pudieron guardar las secciones: \(error.localizedDescription)"
        }
        reload()
    }

    @discardableResult
    func addLoop(name: String, start: Double, end: Double) -> UUID? {
        guard end > start else { return nil }
        let l = Loop(name: name, start: start, end: end)
        study.loops.append(l)
        return l.id
    }

    func updateLoop(_ id: UUID, _ change: (inout Loop) -> Void) {
        guard let i = study.loops.firstIndex(where: { $0.id == id }) else { return }
        change(&study.loops[i])
    }

    func removeLoop(_ id: UUID) { study.loops.removeAll { $0.id == id } }

    /// Mezcla guardada del stem (valores por defecto si aún no se tocó).
    func mix(for kind: StemKind) -> StemMix {
        study.mixer.first { $0.kind == kind && $0.guitarRole == nil } ?? StemMix(kind: kind)
    }

    func updateMix(_ kind: StemKind, _ change: (inout StemMix) -> Void) {
        updateMix(where: { $0.kind == kind && $0.guitarRole == nil }, default: StemMix(kind: kind), change)
    }

    /// Mezcla guardada de una pista de guitarra (por papel, mini-spec Fase 4 «Datos»).
    func mix(forGuitar role: GuitarRole) -> StemMix {
        study.mixer.first { $0.guitarRole == role } ?? StemMix(kind: .guitar, guitarRole: role)
    }

    func updateMix(guitar role: GuitarRole, _ change: (inout StemMix) -> Void) {
        updateMix(where: { $0.guitarRole == role }, default: StemMix(kind: .guitar, guitarRole: role), change)
    }

    private func updateMix(where match: (StemMix) -> Bool, default base: StemMix, _ change: (inout StemMix) -> Void) {
        var m = study.mixer.first(where: match) ?? base
        change(&m)
        if let i = study.mixer.firstIndex(where: match) { study.mixer[i] = m } else { study.mixer.append(m) }
    }

    func updatePlayer(_ change: (inout PlayerSettings) -> Void) {
        var p = study.player
        change(&p)
        p.rate = min(max(p.rate, Self.rateRange.lowerBound), Self.rateRange.upperBound)
        p.transpose = min(max(p.transpose, Self.transposeRange.lowerBound), Self.transposeRange.upperBound)
        p.fineCents = min(max(p.fineCents, Self.fineCentsRange.lowerBound), Self.fineCentsRange.upperBound)
        study.player = p
    }

    // MARK: Guardado con rebote

    private func scheduleSave() {
        hasPendingSave = true
        onChange?()
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.saveDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    // MARK: Tomas (mini-spec Fase 3, «Grabación»; W2-R1, copia de `App/Sources/StudySession.swift`)

    /// Último fallo al guardar tomas en `project.json` (nil si fue bien).
    private(set) var takeSaveError: String?
    private var takeSaves: [Task<Void, Never>] = []

    /// Tomas con fichero alineado que se pueden oír, de la más antigua a la más reciente.
    var playableTakes: [Take] {
        project.takes.filter { !$0.discarded && $0.processedFile != nil && $0.songStart != nil && $0.sampleRate != nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Añade o sustituye (por id) tomas del proyecto y las guarda ya (solo toca `takes`).
    func saveTakes(_ takes: [Take]) {
        for t in takes {
            if let i = project.takes.firstIndex(where: { $0.id == t.id }) { project.takes[i] = t } else { project.takes.append(t) }
        }
        guard let writer = store as? any TakeStoring else {
            takeSaveError = "No se pudo guardar la toma en el proyecto (este almacén no guarda tomas)."
            return
        }
        let id = projectID
        takeSaves.append(Task { [weak self] in
            do {
                try await writer.saveTakes(id: id, takes)
                self?.takeSaveError = nil
            } catch {
                self?.takeSaveError = "No se pudo guardar la toma en el proyecto (\(error))."
            }
            self?.onChange?()
        })
    }

    /// Espera a que terminen los guardados de tomas lanzados. Los quita de la lista solo al acabar: con dos esperas a la vez
    /// (Grabar al guardar y `takeview.open`), la segunda también espera en vez de ver la lista vacía.
    func awaitTakeSaves() async {
        let pending = takeSaves
        for t in pending { await t.value }
        takeSaves.removeAll { pending.contains($0) }
    }

    /// Guarda el estado de grabación por partes (solo toca `recording`) y lo deja también en el proyecto en memoria.
    func saveRecording(_ state: RecordingState) async throws {
        project.recording = state
        if let writer = store as? any TakeStoring { try await writer.saveRecording(id: projectID, state) }
    }

    /// Guarda ya (al cerrar la pantalla o salir de la app).
    func flush() async {
        saveTask?.cancel()
        saveTask = nil
        let written = study
        let before = saveError
        do {
            try await store.saveStudy(id: projectID, study: written, sections: project.sections)
            if study == written { hasPendingSave = false }
            saveError = nil
        } catch {
            saveError = "No se pudo guardar el estudio: \(error.localizedDescription)"
        }
        // El aviso sale (o se retira) sin esperar a otra edición: la interfaz lo lee de `guitarsInfo.saveError`.
        if saveError != before { onChange?() }
        if !pendingNames.isEmpty {
            let names = pendingNames
            pendingNames = [:]
            do { try await store.saveGuitarNames(id: projectID, names: names) } catch {
                guitarOptionsError = "No se pudieron guardar los nombres: \(error.localizedDescription)"
            }
            reload()
        }
    }
}

extension GuitarRole {
    /// Id de su pista en el reproductor (`guitar_L`, igual que el nombre del fichero sin extensión).
    var trackID: String { String(fileName.dropLast(4)) }
}
