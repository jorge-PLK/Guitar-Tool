import Foundation
import Observation
import Store
import StudyKit

/// Estado de estudio del proyecto abierto en Backing (mini-spec Fase 2 §1 Store, §2). Sin UI ni reproductor:
/// la pantalla (P7b) lo lee y lo edita; lo del usuario se guarda en `project.json` con rebote.
@MainActor @Observable
final class StudySession {
    /// Rebote del guardado (segundos): se agrupan las ediciones seguidas en una sola escritura.
    static let saveDelay = 0.5
    static let transposeRange = -12...12
    static let fineCentsRange = -50.0...50.0
    static let rateRange = 0.5...2.0

    let projectID: UUID
    let folder: URL
    private(set) var project: Project
    private(set) var analysis: StudyAnalysis?
    private(set) var analysisState: AnalysisState

    /// Lo del usuario. Cualquier cambio programa el guardado.
    var study: StudyState { didSet { if study != oldValue { scheduleSave() } } }
    var sections: [Section] { didSet { if sections != oldValue { scheduleSave() } } }

    @ObservationIgnored private let library: Library
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    var layout: ProjectLayout { ProjectLayout(folder: folder) }

    init(project: Project, folder: URL, library: Library, analysisState: AnalysisState = .missing) {
        self.projectID = project.id
        self.folder = folder
        self.project = project
        self.library = library
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
        if let p = try? ProjectFile.load(folder: folder) { project = p }
        loadAnalysis()
    }

    private func loadAnalysis() {
        analysis = AppStudyAnalyzer.loadCached(project: project, layout: layout)
        if analysis != nil, analysisState != .analyzing { analysisState = .ready }
    }

    func setAnalysisState(_ s: AnalysisState) {
        analysisState = s
        if s == .ready { loadAnalysis() }
    }

    /// Acordes detectados con las correcciones del usuario encima.
    var effectiveChords: [ChordSegment] {
        StudyBridge.effectiveChords(detected: analysis?.chords.segments ?? [],
                                    overrides: study.chordOverrides.map { ($0.start, $0.end, $0.index) })
    }

    /// `keyOverride` si el usuario la corrigió; si no, la detectada («C:maj», «A:min»).
    var effectiveKey: String? { study.keyOverride ?? analysis?.key.key }

    var beats: BeatGrid? { analysis?.beats }

    // MARK: Ediciones

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

    @discardableResult
    func addSection(name: String, start: Double, end: Double, kind: String? = nil) -> UUID? {
        guard end > start else { return nil }
        let s = Section(name: name, start: start, end: end, kind: kind)
        sections.append(s)
        sections.sort { $0.start < $1.start }
        return s.id
    }

    func updateSection(_ id: UUID, _ change: (inout Section) -> Void) {
        guard let i = sections.firstIndex(where: { $0.id == id }) else { return }
        change(&sections[i])
        sections.sort { $0.start < $1.start }
    }

    func removeSection(_ id: UUID) { sections.removeAll { $0.id == id } }

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
    func mix(for kind: StemKind) -> StemMix { study.mixer.first { $0.kind == kind } ?? StemMix(kind: kind) }

    func updateMix(_ kind: StemKind, _ change: (inout StemMix) -> Void) {
        var m = mix(for: kind)
        change(&m)
        if let i = study.mixer.firstIndex(where: { $0.kind == kind }) { study.mixer[i] = m } else { study.mixer.append(m) }
    }

    func updatePlayer(_ change: (inout PlayerSettings) -> Void) {
        var p = study.player
        change(&p)
        p.rate = min(max(p.rate, Self.rateRange.lowerBound), Self.rateRange.upperBound)
        p.transpose = min(max(p.transpose, Self.transposeRange.lowerBound), Self.transposeRange.upperBound)
        p.fineCents = min(max(p.fineCents, Self.fineCentsRange.lowerBound), Self.fineCentsRange.upperBound)
        study.player = p
    }

    // MARK: Tomas (mini-spec Fase 3, «Grabación»)

    /// Último fallo al guardar tomas en `project.json` (nil si fue bien).
    private(set) var takeSaveError: String?

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
        let id = projectID, library = library
        Task { [weak self] in
            do {
                try await library.saveTakes(id: id, takes)
                self?.takeSaveError = nil
            } catch {
                self?.takeSaveError = "No se pudo guardar la toma en el proyecto (\(error))."
            }
        }
    }

    // MARK: Guardado con rebote

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.saveDelay))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// Guarda ya (al cerrar la pantalla o salir de la app).
    func flush() async {
        saveTask?.cancel()
        saveTask = nil
        try? await library.saveStudy(id: projectID, study: study, sections: sections)
    }
}
