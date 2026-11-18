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
    /// Secciones en edición (los solos son secciones con la marca «Solo»): locales hasta «Aplicar» (mini-spec Fase 4,
    /// «Opciones de guitarras y tramos de solo»). Lo guardado está en `project.sections`.
    var sections: [Section]
    /// Nombres de guitarra editados y aún sin guardar (con rebote, `Library.saveGuitarNames`).
    private var pendingNames: [GuitarRole: String] = [:] { didSet { if !pendingNames.isEmpty { scheduleSave() } } }
    /// Error al guardar las opciones o los nombres (se muestra junto al interruptor).
    private(set) var guitarOptionsError: String?

    @ObservationIgnored private var simulated = false
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
        if let p = try? ProjectFile.load(folder: folder) {
            let dirty = hasUnappliedSections
            project = p
            if !simulated, !dirty { sections = p.sections }
        }
        loadAnalysis()
    }

    /// Guarda la fuente elegida de la tablatura (Fase 5b; nil = sin elegir). Solo toca ese campo de `project.json`.
    /// `grid`: rejilla del metrónomo corregida desde Songsterr (se guarda en `tab/songsterr-grid.json`).
    func saveTabSource(_ choice: TabSourceChoice?, grid: SongsterrGridFile? = nil) async {
        project.tabSource = choice
        if let grid {
            songsterrGrid = grid
            if !simulated { try? grid.save(to: layout.tabSongsterrGridFile) }
        }
        guard !simulated else { return }
        try? await library.saveTabSource(choice, for: projectID)
    }

    /// Rejilla de Songsterr guardada (puede ser de otro tema; `metronomeBeats` lo comprueba).
    private(set) var songsterrGrid: SongsterrGridFile?

    /// Rejilla del metrónomo (Backing y Tablatura): la corregida desde Songsterr si la fuente de la tablatura es ese
    /// mismo tema y revisión; si no (automática, sin elegir), la del análisis.
    var metronomeBeats: BeatGrid? {
        if case let .songsterr(songId, revisionId, _)? = project.tabSource, let g = songsterrGrid,
           g.songId == songId, g.revisionId == revisionId, g.beats.count >= 2 {
            return BeatGrid(beats: g.beats, downbeats: g.downbeats)
        }
        return beats
    }

    // MARK: Guitarras (Fase 4)

    /// Pistas de guitarra con fichero en disco, en el orden de `GuitarRole.allCases`.
    var guitarTracks: [Guitar] {
        project.guitarTracks.filter { g in
            simulated || g.file.map { FileManager.default.fileExists(atPath: layout.url(relative: $0).path) } == true
        }
    }

    /// Hay pistas separadas: sustituyen al canal «Guitarras» del mezclador (no se suman dos veces).
    var usesSeparatedGuitars: Bool { !guitarTracks.isEmpty }

    /// Stems con canal propio en el mezclador (sin `guitar` si se muestran las pistas separadas).
    var mixerStems: [StemKind] { usesSeparatedGuitars ? audibleStems.filter { $0 != .guitar } : audibleStems }

    var guitarOptions: GuitarOptions { project.guitarOptions }

    func guitarName(_ role: GuitarRole) -> String { pendingNames[role] ?? project.guitarName(role) }

    func renameGuitar(_ role: GuitarRole, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingNames[role] = n.isEmpty ? role.defaultName : n
    }

    /// Interruptor «Guitarras en L y R»: se guarda ya (las secciones en edición no se tocan).
    func setStereoSplit(_ on: Bool) {
        guitarOptionsError = nil
        guard !simulated else {
            project.guitarSettings.stereoSplit = on
            return
        }
        Task { [library, projectID] in
            do {
                try await library.saveGuitarStereoSplit(id: projectID, on)
            } catch {
                guitarOptionsError = "No se pudieron guardar las opciones: \(error.localizedDescription)"
            }
            reload()
        }
    }

    private func loadAnalysis() {
        if songsterrGrid == nil { songsterrGrid = SongsterrGridFile.load(layout.tabSongsterrGridFile) }
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

    // MARK: Secciones (el solo es una sección más)

    /// Hay secciones editadas sin aplicar.
    var hasUnappliedSections: Bool { sections != project.sections }

    func discardSections() { sections = project.sections }

    /// Guarda las secciones en edición; la biblioteca rehace las pistas de guitarra en segundo plano solo si cambian
    /// los tramos de solo (renombrar o mover secciones que no son solo no reprocesa).
    func applySections() {
        let applied = sections
        guitarOptionsError = nil
        project.sections = applied
        guard !simulated else { return }
        saveTask?.cancel()
        Task { [library, projectID, study] in
            do {
                try await library.saveStudy(id: projectID, study: study, sections: applied)
            } catch {
                guitarOptionsError = "No se pudieron guardar las secciones: \(error.localizedDescription)"
            }
            reload()
        }
    }

    /// Las secciones en edición, en un `SectionEditor` (lógica y tests en Store).
    var sectionEditor: SectionEditor { SectionEditor(sections: sections, duration: project.song.duration) }

    /// Aplica una edición de `SectionEditor` a las secciones en edición.
    private func edit<R>(_ body: (inout SectionEditor) -> R) -> R {
        var e = sectionEditor
        let r = body(&e)
        if e.sections != sections { sections = e.sections }
        return r
    }

    /// Marca una sección (o un solo) en `r`, solo en hueco libre: empezando dentro de otra no se crea; si entra en la
    /// siguiente, se queda en su borde (`SectionEditor.mark`, mini-spec Fase 7b, punto 8).
    @discardableResult
    func markSection(_ r: ClosedRange<Double>, solo: Bool) -> UUID? { edit { $0.mark(r, solo: solo) } }

    func renameSection(_ id: UUID, to name: String) { edit { $0.rename(id, to: name) } }

    /// Alterna «Solo»; un nombre por defecto sigue a la marca («Sección 2» y «Solo»).
    func setSolo(_ id: UUID, _ on: Bool) { edit { $0.setSolo(id, on) } }

    /// Mueve un borde a `time` (lo da `SectionEdgeDrag` al soltar, ya con imán) con las reglas de `SectionEditor`:
    /// empuja a la vecina hasta su mínimo, se para contra un solo.
    func setSectionEdge(_ id: UUID, start moveStart: Bool, to time: Double) {
        edit { $0.setEdge(id, start: moveStart, to: time) }
    }

    /// Mueve un borde al acorde siguiente o anterior (al compás con `bar`), con las mismas reglas que el arrastre.
    func nudgeSectionEdge(_ id: UUID, start moveStart: Bool, forward: Bool, bar: Bool) {
        let b = bar ? barBoundaries : chordBoundaries
        edit { $0.nudgeEdge(id, start: moveStart, forward: forward, boundaries: b) }
    }

    func removeSection(_ id: UUID) { edit { $0.remove(id) } }

    /// Elige el color de paleta de una sección (nil = automático).
    func setSectionColor(_ id: UUID, _ index: Int?) { edit { $0.setColor(id, index) } }

    /// Color de paleta de cada sección que no es solo (`SectionEditor.paletteIndices`).
    var sectionPalette: [UUID: Int] { SectionEditor.paletteIndices(sections) }

    /// Límites de acorde (inicios y finales, ordenados): el imán de los bordes de sección.
    var chordBoundaries: [Double] {
        Array(Set(effectiveChords.flatMap { [$0.start, $0.end] })).sorted()
    }

    /// Inicios de compás (downbeats).
    var barBoundaries: [Double] { beats?.downbeats ?? [] }

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
        try? await library.saveStudy(id: projectID, study: study, sections: project.sections)
        if !simulated, !pendingNames.isEmpty {
            let names = pendingNames
            pendingNames = [:]
            do { try await library.saveGuitarNames(id: projectID, names: names) } catch {
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

#if DEBUG
extension StudySession {
    /// `--guitars-demo`: pistas, secciones y solos simulados, solo en memoria (no se guardan ni hay pistas en disco).
    /// Modos: «mono-solo», «stereo», «stereo-solo», «dirty» (secciones sin aplicar), «processing», «failed» y
    /// «narrow» (solos estrechos). Los modos sin solo llevan solo secciones normales.
    func installGuitarsDemo(_ demo: String) {
        let d = max(project.song.duration, 60)
        let downbeats = beats?.downbeats ?? []
        let bars = downbeats.count >= 8 ? downbeats : Array(stride(from: 0.0, to: d, by: 4))
        func at(_ f: Double) -> Double {
            let target = d * f
            return bars.min { abs($0 - target) < abs($1 - target) } ?? target
        }
        let stereo = demo.hasPrefix("stereo")
        let solo = demo.hasSuffix("solo") || ["dirty", "processing", "failed", "narrow"].contains(demo)
        var roles: [GuitarRole] = stereo ? [.left, .right] : [.rhythm]
        if solo { roles.append(.lead) }
        simulated = true
        // Con acordes analizados, las secciones caen sobre los primeros acordes (así se ven sin desplazar la tira).
        let chords = effectiveChords
        var list: [Section]
        if chords.count >= 16 {
            func c(_ i: Int) -> Double { chords[i].start }
            list = [Section(name: "Intro", start: c(0), end: c(3)),
                    Section(name: "Estrofa", start: c(3), end: c(6))]
            if solo {
                list.append(Section(name: "Solo", start: c(6), end: c(9), solo: true))
                list.append(Section(name: "Estribillo", start: c(9), end: c(12)))
                list.append(Section(name: "Solo 3", start: c(13), end: c(14), solo: true))
                list.append(Section(name: "Puente del tema", start: c(14), end: c(16)))
            } else {
                list.append(Section(name: "Estribillo", start: c(6), end: c(10)))
                list.append(Section(name: "Puente", start: c(10), end: c(14)))
            }
        } else {
            list = [Section(name: "Intro", start: 0, end: at(0.12)),
                    Section(name: "Estrofa", start: at(0.12), end: at(0.30)),
                    Section(name: "Estribillo", start: at(0.30), end: at(0.42))]
            if solo {
                list.append(Section(name: "Solo", start: at(0.42), end: at(0.52), solo: true))
                list.append(Section(name: "Solo 2", start: at(0.78), end: at(0.84), solo: true))
            } else {
                list.append(Section(name: "Puente", start: at(0.42), end: at(0.60)))
            }
        }
        project.sections = list
        sections = list
        project.guitarSettings = GuitarSettings(stereoSplit: stereo)
        project.guitars = roles.map { Guitar(role: $0, name: $0 == .left ? "Robe" : ($0 == .right ? "Uoho" : nil), file: $0.relativePath) }
        if demo == "dirty" {
            if chords.count >= 18 { _ = markSection(chords[16].start...chords[18].start, solo: true) }
            if let i = sections.firstIndex(where: { $0.name == "Estrofa" }) { sections[i].name = "Estrofa 1" }
        }
    }
}
#endif

/// Rejilla del metrónomo corregida desde Songsterr (`SongsterrBeatGrid.build`), en `tab/songsterr-grid.json`. Va con
/// el tema y la revisión de los que salió: solo vale mientras `Project.tabSource` sea ese mismo.
struct SongsterrGridFile: Codable, Equatable {
    var songId: Int
    var revisionId: Int
    var beats: [Double]
    var downbeats: [Double]
    /// Tempo escrito principal de Songsterr (BPM de negra).
    var writtenTempo: Double

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    static func load(_ url: URL) -> SongsterrGridFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SongsterrGridFile.self, from: data)
    }
}
