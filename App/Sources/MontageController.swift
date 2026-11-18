import AppKit
import AudioKit
import AVFoundation
import Foundation
import Observation
import Store
import VideoKit

/// Pantalla Montaje (mini-spec Fase 7): puente Store → `MontagePlan` y `MontageMixJob`, análisis de encuadre con
/// caché, vista previa con `AVPlayer` y exportación con progreso.
@MainActor @Observable
final class MontageController {
    enum FramingStatus: Equatable {
        case pending
        case analyzing(Double)
        /// Analizada: muestras totales y con detección.
        case ready(samples: Int, detected: Int)
        case failed(String)
    }

    struct ExportResult: Equatable {
        var url: URL
        var tracksDirectory: URL?
        var finalLUFS: Double?
        var finalTruePeakDB: Double
        var normalized: Bool
        var limitedByPeak: Bool
        var limiterEnabled: Bool = false
        var limiterApplied: Bool = false
        var limiterMaxReductionDB: Double = 0
        var limiterOutOfTolerance: Bool = false
        /// Nombres de los ficheros con muestras recortadas a 24 bits.
        var clippedFiles: [String] = []
    }

    enum ExportPhase: Equatable {
        case idle
        case running(stage: String, progress: Double)
        case done(ExportResult)
        case failed(String)
    }

    /// Reparto del progreso único de la exportación: la mezcla (rápida) y el vídeo (el grueso).
    static let mixProgressShare = 0.15
    /// Retardo antes de rehacer la vista previa tras un cambio (arrastrar la caja emite muchos).
    static let previewDebounce = 0.15
    /// Anticipación al solo (mini-spec «Transiciones»), leída de VideoKit para no duplicarla, como texto («0,5 s»).
    static let anticipationLabel = "\(MontageStyle.anticipation.formatted(.number.precision(.fractionLength(0...2)))) s"
    /// Separación mínima entre dos cortes libres del plano único al arrastrar (s); decisión propia, no sale de la spec.
    static let minCutGap = 0.1
    /// Rebote del guardado, como `StudySession`.
    static let saveDelay = StudySession.saveDelay

    let session: StudySession
    @ObservationIgnored unowned let model: AppModel

    private(set) var state: MontageState
    private(set) var draft: MontageDraft?
    private(set) var analyses: [UUID: FramingAnalysis] = [:]
    private(set) var framingStatus: [UUID: FramingStatus] = [:]
    var framingSheetTakeID: UUID?

    // Vista previa.
    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private var preview: MontagePreview?
    private(set) var previewReady = false
    private(set) var previewError: String?
    private(set) var songTime = 0.0
    private(set) var isPlaying = false
    /// Instante inicial de la vista previa (capturas con `--seek`).
    @ObservationIgnored var initialSongTime: Double?

    // Exportación.
    private(set) var exportPhase: ExportPhase = .idle
    #if DEBUG
    /// Comprobación `--montage-export`: instantes de cada fase (s desde el inicio) y el error tal cual.
    @ObservationIgnored let exportClock = ExportClock()
    @ObservationIgnored private(set) var exportRawError: String?
    #endif

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var durations: [URL: Double] = [:]
    @ObservationIgnored private var closed = false
    @ObservationIgnored private var dirty = false

    init(session: StudySession, model: AppModel) {
        self.session = session
        self.model = model
        state = session.project.montageOrInitial(video: model.profile.video)
        rebuildDraft()
    }

    // MARK: Datos

    var song: Song { session.project.song }
    var sections: [Store.Section] { session.project.sections }
    var lanes: [MontageLane] { draft?.lanes ?? [] }
    var videoLanes: [MontageLane] { lanes.filter { $0.hasVideo && !$0.presence.isEmpty } }
    var isPortrait: Bool { MontagePlanning.isPortrait(state.layout) }
    var canvasLabel: String { isPortrait ? "1080 × 1920" : "1920 × 1080" }
    var span: LaneSpan { draft?.span ?? LaneSpan(start: 0, end: 0) }
    var isAnalyzing: Bool {
        framingStatus.values.contains { if case .analyzing = $0 { return true }; return $0 == .pending }
    }
    var isExporting: Bool { if case .running = exportPhase { return true }; return false }
    var canExport: Bool { draft != nil && !isExporting && !isAnalyzing }
    var singleRhythmCandidates: [MontageLane] { lanes.filter { $0.hasVideo && !$0.isSolo && !$0.presence.isEmpty } }

    func lane(takeID: UUID) -> MontageLane? { lanes.first { $0.takeID == takeID } }

    /// Sección del tema en `t` (para la etiqueta de la vista previa).
    func sectionName(at t: Double) -> String? { sections.first { t >= $0.start && t < $0.end }?.name }
    func isSoloSection(at t: Double) -> Bool { sections.first { t >= $0.start && t < $0.end }?.isSolo ?? false }

    // MARK: Ciclo de vida

    func open() {
        closed = false
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, let p = self.preview, self.player.currentItem != nil else { return }
                self.songTime = p.songTime(itemTime: t)
                self.isPlaying = self.player.rate != 0
            }
        }
        startAnalysis()
        schedulePreview()
    }

    func close() {
        closed = true
        previewTask?.cancel()
        analysisTask?.cancel()
        player.pause()
        isPlaying = false
        player.replaceCurrentItem(with: nil)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        // Salir con una exportación en curso la cancela (borra lo a medias).
        exportTask?.cancel()
        Task { await flush() }
    }

    // MARK: Ajustes del montaje

    func setLayout(_ kind: Store.MontageLayoutKind) {
        guard state.layout != kind else { return }
        state.layout = kind
        changed()
    }

    func setSingleRhythm(_ id: UUID?) {
        state.singleRhythmPartID = id
        changed()
    }

    func setCutGaps(_ on: Bool) {
        state.cutGaps = on
        changed()
    }

    /// Reordena los recuadros: la parte `id` pasa a ocupar el sitio de `target` (las demás se desplazan). Se guarda al soltar.
    func moveLane(_ id: UUID, to target: UUID) {
        var order = state.effectiveOrder(of: session.project.recordingOrInitial().parts.map(\.id))
        guard id != target, let from = order.firstIndex(of: id), let to = order.firstIndex(of: target) else { return }
        order.insert(order.remove(at: from), at: to)
        state.partOrder = order
        changed()
    }

    func setPartOrder(_ ids: [UUID]) {
        state.partOrder = ids
        changed()
    }

    func setCaption(_ on: Bool) {
        state.caption = on
        changed()
    }

    func setShowPartLabels(_ on: Bool) {
        state.showPartLabels = on
        changed()
    }

    func setKeepVideoAspect(_ on: Bool) {
        state.keepVideoAspect = on
        changed()
    }

    /// «Mantener aspect ratio» solo cuenta en apilado y plano único (mini-spec Fase 7, «Interfaz»); en lado a lado y
    /// rejilla el valor guardado se conserva pero no se aplica.
    var keepAspectApplies: Bool { state.layout == .stack || state.layout.isSingleShot }

    // MARK: Cortes libres del plano único

    var isSingleShot: Bool { state.layout.isSingleShot }
    /// Cortes ordenados por tiempo.
    var cuts: [MontageSingleCut] { state.singleCuts.normalizedSingleCuts() }
    /// Partes que se pueden elegir en un corte: las que tienen toma con vídeo.
    var cutCandidates: [MontageLane] { lanes.filter { $0.hasVideo } }
    var existingPartIDs: [UUID] { session.project.recordingOrInitial().parts.map(\.id) }
    /// Parte que manda en `t` según los cortes (nil = automático); es la que hereda un corte nuevo.
    func singlePart(at t: Double) -> UUID? { state.singlePart(at: t, existingPartIDs: existingPartIDs) }
    /// Lo que de verdad se ve en el plano único (color del carril «Plano»): un corte a una parte sin toma se pinta
    /// con la que elige el automático (decisión de Jorge del 17/11/2026).
    var planeShots: [PlaneShot] { MontagePlanning.planeShots(plan: draft?.plan) }
    /// ¿Tiene toma con imagen la parte elegida en el corte, en su instante? (nil o automático: sí).
    func cutPartCovered(_ cut: MontageSingleCut) -> Bool {
        guard let p = cut.partID else { return true }
        return MontagePlanning.cutEligibleParts(plan: draft?.plan, at: cut.time).contains(p)
    }

    /// `t` ajustado al pulso más cercano (sin pulso, sin ajuste) y dentro del tramo del vídeo.
    func snappedCutTime(_ t: Double) -> Double {
        let snapped = SectionEditor.snap(t, to: session.beats?.beats ?? [])
        return min(max(snapped, span.start), span.end)
    }

    /// Posición de un corte arrastrado: ajustada al pulso y sin pasar de los cortes vecinos.
    func draggedCutTime(_ id: UUID, to t: Double) -> Double {
        let all = cuts
        guard let i = all.firstIndex(where: { $0.id == id }) else { return t }
        let lo = i > 0 ? all[i - 1].time + Self.minCutGap : span.start
        let hi = i + 1 < all.count ? all[i + 1].time - Self.minCutGap : span.end
        return min(max(snappedCutTime(t), lo), max(lo, hi))
    }

    /// Crea un corte en `t` (ajustado) que conserva la parte vigente y devuelve su id para abrir el menú.
    @discardableResult
    func addCut(at t: Double) -> UUID {
        let time = snappedCutTime(t)
        let id = UUID()
        state = state.addingSingleCut(at: time, partID: singlePart(at: time), id: id)
        changed()
        return id
    }

    /// Corte con parte explícita (nil = automático) y sin ajuste al pulso (la demo `--montage-cuts`).
    func addCut(at t: Double, partID: UUID?, exact: Bool) {
        state = state.addingSingleCut(at: exact ? min(max(t, span.start), span.end) : snappedCutTime(t), partID: partID)
        changed()
    }

    func moveCut(_ id: UUID, to t: Double) {
        state = state.movingSingleCut(id, to: draggedCutTime(id, to: t))
        changed()
    }

    func setCutPart(_ id: UUID, _ partID: UUID?) {
        state = state.settingSingleCut(id, partID: partID)
        changed()
    }

    func removeCut(_ id: UUID) {
        state = state.removingSingleCut(id)
        changed()
    }

    func clearCuts() {
        state.singleCuts = []
        changed()
    }

    /// Cambios de «Exportación» (no afectan a la vista previa salvo los fps del plan).
    func updateExport(_ change: (inout MontageExport) -> Void) {
        change(&state.export)
        rebuildDraft()
        scheduleSave()
    }

    func framing(for takeID: UUID) -> TakeFraming { state.framing(for: takeID) }

    func updateFraming(_ takeID: UUID, _ change: (inout TakeFraming) -> Void) {
        var f = state.framing(for: takeID)
        change(&f)
        state.framing[takeID] = f
        changed()
    }

    func resetFraming(_ takeID: UUID) { updateFraming(takeID) { $0.reset() } }

    private func changed() {
        rebuildDraft()
        schedulePreview()
        scheduleSave()
    }

    /// Caja de la guitarra que se dibuja en la hoja «Encuadre»: con el ajuste manual, en el instante `t`.
    func effectiveBox(takeID: UUID, at t: Double) -> NormalizedRect? {
        let f = MontagePlanning.framing(state.framing(for: takeID), analysis: analyses[takeID])
        return f.box(at: t).map { NormalizedRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
    }

    // MARK: Plan

    private func takeDuration(_ url: URL) -> Double? {
        if let d = durations[url] { return d }
        guard let f = try? AVAudioFile(forReading: url), f.fileFormat.sampleRate > 0 else { return nil }
        let d = Double(f.length) / f.fileFormat.sampleRate
        durations[url] = d
        return d
    }

    var barDuration: Double {
        let t = BarTiming(session.beats)
        return MontagePlan.barDuration(bpm: 60 / t.beatSeconds, beatsPerBar: t.beatsPerBar)
    }

    private func rebuildDraft() {
        let layout = session.layout
        let fm = FileManager.default
        let stems = session.mixerStems.filter { fm.fileExists(atPath: layout.stemURL($0).path) }
        draft = MontagePlanning.build(project: session.project, layout: layout, state: state, barDuration: barDuration,
                                      analyses: analyses, stems: stems, guitarRoles: session.guitarTracks.map(\.role),
                                      takeDuration: { [unowned self] in self.takeDuration($0) })
    }

    // MARK: Análisis de encuadre

    private func startAnalysis() {
        analysisTask?.cancel()
        let pending = videoLanes
        for l in pending where framingStatus[l.takeID] == nil { framingStatus[l.takeID] = .pending }
        analysisTask = Task { [weak self] in
            for l in pending {
                guard let self, !Task.isCancelled else { return }
                await self.analyze(l)
            }
        }
    }

    /// Reanaliza una toma aunque la caché sea válida (botón de la hoja).
    func reanalyze(_ takeID: UUID) {
        guard let l = lane(takeID: takeID) else { return }
        try? FileManager.default.removeItem(at: session.layout.framingCacheURL(takeId: takeID))
        analyses[takeID] = nil
        framingStatus[takeID] = .pending
        let previous = analysisTask
        analysisTask = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await self.analyze(l)
        }
    }

    private func analyze(_ lane: MontageLane) async {
        guard let video = lane.video else { return }
        let id = lane.takeID
        let cache = session.layout.framingCacheURL(takeId: id)
        let fingerprint = GuitarFramer.fingerprint(video: video)
        if let data = try? Data(contentsOf: cache), let a = try? JSONDecoder().decode(FramingAnalysis.self, from: data),
           a.version == FramingAnalysis.currentVersion, a.fingerprint == fingerprint {
            finishAnalysis(id, a)
            return
        }
        framingStatus[id] = .analyzing(0)
        do {
            let a = try await GuitarFramer.analyze(video: video) { [weak self] p in
                Task { @MainActor in
                    if case .analyzing = self?.framingStatus[id] { self?.framingStatus[id] = .analyzing(p) }
                }
            }
            try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(a) { try? data.write(to: cache, options: .atomic) }
            finishAnalysis(id, a)
        } catch is CancellationError {
            framingStatus[id] = .pending
        } catch {
            framingStatus[id] = .failed("\(error)")
        }
    }

    private func finishAnalysis(_ id: UUID, _ a: FramingAnalysis) {
        guard !closed else { return }
        analyses[id] = a
        framingStatus[id] = .ready(samples: a.samples, detected: a.detected)
        rebuildDraft()
        schedulePreview()
    }

    // MARK: Vista previa

    private func schedulePreview() {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.previewDebounce))
            guard !Task.isCancelled else { return }
            await self?.buildPreview()
        }
    }

    private func buildPreview() async {
        guard !closed else { return }
        guard let plan = draft?.plan else {
            player.replaceCurrentItem(with: nil)
            preview = nil
            previewReady = false
            return
        }
        let wasPlaying = isPlaying
        let keep = preview == nil ? (initialSongTime ?? plan.span.start) : songTime
        do {
            let builder = try await MontageBuilder.load(plan, includeAudio: true)
            guard !Task.isCancelled, !closed else { return }
            let size = MontageBuilder.renderSize(canvas: plan.canvas, maxDimension: MontagePlanning.previewMaxDimension)
            let p = try builder.make(renderSize: size, includeAudio: true)
            preview = p
            player.replaceCurrentItem(with: p.makePlayerItem())
            previewReady = true
            previewError = nil
            let t = min(max(keep, plan.span.start), plan.span.end)
            songTime = t
            await player.seek(to: p.itemTime(songTime: t), toleranceBefore: .zero, toleranceAfter: .zero)
            if wasPlaying { player.play() }
        } catch is CancellationError {
        } catch {
            previewReady = false
            previewError = "No se pudo preparar la vista previa (\(error))."
        }
    }

    func togglePlay() {
        guard previewReady else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if songTime >= span.end - 0.1 { seek(to: span.start) }
            player.play()
            isPlaying = true
        }
    }

    func seek(to t: Double) {
        guard let p = preview else { return }
        let t = min(max(t, span.start), span.end)
        songTime = t
        player.seek(to: p.itemTime(songTime: t), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: Fotograma de la hoja «Encuadre»

    /// Fotograma de la toma en el instante `t` del tema (base o punch, con su desfase).
    func frameImage(takeID: UUID, at t: Double) async -> CGImage? {
        guard let video = lane(takeID: takeID)?.video else { return nil }
        var url = video.url
        var offset = video.videoOffset
        for p in video.punches where p.videoURL != nil && t >= p.start && t < p.end {
            url = p.videoURL
            offset = p.videoOffset
        }
        guard let url else { return nil }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1280, height: 720)
        gen.requestedTimeToleranceBefore = .positiveInfinity
        gen.requestedTimeToleranceAfter = .positiveInfinity
        // Positivo: la imagen del instante T llega al fichero en T + desfase.
        guard let img = try? await gen.image(at: CMTime(seconds: t + offset, preferredTimescale: 90_000)).image else { return nil }
        // La caja del encuadre está en coordenadas de la imagen ya girada.
        return video.rotation.apply(img)
    }

    // MARK: Giro de la toma («Rotar»)

    /// Giro de la toma (0, 90, 180 o 270).
    func rotation(takeID: UUID) -> Int { session.project.takes.first { $0.id == takeID }?.rotationDegrees ?? 0 }

    /// «Rotar» en la ficha de la toma: 90° más en sentido horario, guardado en la toma. El encuadre guardado se gira con
    /// la imagen (`TakeFraming.rotatedClockwise`) y el análisis se rehace (su huella incluye el giro).
    func rotateTake(_ takeID: UUID) {
        guard var take = session.project.takes.first(where: { $0.id == takeID }) else { return }
        take.videoRotation = VideoSettings.normalizedRotation(take.rotationDegrees + 90)
        session.saveTakes([take])
        if state.framing[takeID] != nil { state.framing[takeID] = state.framing(for: takeID).rotatedClockwise(quarterTurns: 1) }
        analyses[takeID] = nil
        framingStatus[takeID] = nil
        changed()
        startAnalysis()
    }

    // MARK: Exportación

    func startExport() {
        guard canExport, let draft, exportTask == nil else { return }
        player.pause()
        isPlaying = false
        exportPhase = .running(stage: "Mezclando el audio", progress: 0)
        exportTask = Task { [weak self] in
            await self?.runExport(draft)
        }
    }

    /// Lanza la exportación y espera a que termine (comprobación `--montage-export`).
    func exportAndWait() async {
        startExport()
        await exportTask?.value
    }

    func cancelExport() { exportTask?.cancel() }

    func dismissExportResult() { if !isExporting { exportPhase = .idle } }

    func revealInFinder(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    private func setProgress(_ stage: String, _ p: Double) {
        if case .running = exportPhase { exportPhase = .running(stage: stage, progress: min(max(p, 0), 1)) }
    }

    private func runExport(_ draft: MontageDraft) async {
        let fm = FileManager.default
        let layout = session.layout
        let kind = state.layout
        let out = state.export
        let url = layout.montageVideoURL(layout: kind, container: out.container)
        let tracksDir = layout.montageTracksDirectory(layout: kind)
        let temp = fm.temporaryDirectory.appendingPathComponent("tf-montage-export-\(UUID().uuidString)", isDirectory: true)
        let mixURL = (out.trackWAVs ? tracksDir : temp).appendingPathComponent("mezcla.wav")
        let plan = draft.plan
        let rate = session.project.song.sampleRate
        let job = MontageMixJob(segments: draft.segments.map { MixSegment(start: $0.start, end: $0.end, fadeIn: $0.fadeIn, fadeOut: $0.fadeOut) },
                                sampleRate: [44_100.0, 48_000.0].contains(rate) ? rate : 48_000,
                                tracks: draft.mixTracks, fadeIn: plan.barDuration,
                                fadeOut: plan.barDuration,
                                normalization: out.normalize ? (out.limiter ? MontageNormalization.standard : MontageNormalization.standardWithoutLimiter) : MontageNormalization.none,
                                mixURL: mixURL, trackDirectory: out.trackWAVs ? tracksDir : nil)
        let size = MontagePlanning.exportSize(out.resolution, kind: kind)
        let videoContainer: MontageVideoContainer
        switch out.container {
        case .mov: videoContainer = .mov
        case .mp4: videoContainer = .mp4
        }
        let settings = MontageExportSettings(codec: out.codec == .hevc ? .hevc : .h264, width: size.width, height: size.height, fps: out.fps,
                                             container: videoContainer)
        var mixResult: MontageMixResult?
        defer {
            try? fm.removeItem(at: temp)
            exportTask = nil
        }
        do {
            try fm.createDirectory(at: layout.videoDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: mixURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let share = Self.mixProgressShare
            #if DEBUG
            let clock = exportClock
            clock.reset()
            #endif
            let mixing = Task.detached(priority: .userInitiated) {
                try await MontageMixer.mix(job) { [weak self] p in
                    #if DEBUG
                    clock.mixProgress(p)
                    #endif
                    Task { @MainActor in self?.setProgress("Mezclando el audio", p * share) }
                }
            }
            let mixed = try await withTaskCancellationHandler { try await mixing.value } onCancel: { mixing.cancel() }
            mixResult = mixed
            #if DEBUG
            clock.mark("mezcla")
            #endif
            try Task.checkCancellation()
            let exporting = Task.detached(priority: .userInitiated) {
                try await MontageExporter.export(plan: plan, mixURL: mixed.mixURL, settings: settings, to: url) { [weak self] p in
                    #if DEBUG
                    clock.markOnce("vídeo: primer fotograma")
                    #endif
                    Task { @MainActor in self?.setProgress("Codificando el vídeo", share + p * (1 - share)) }
                }
            }
            _ = try await withTaskCancellationHandler { try await exporting.value } onCancel: { exporting.cancel() }
            #if DEBUG
            clock.mark("vídeo")
            #endif
            exportPhase = .done(ExportResult(url: url, tracksDirectory: out.trackWAVs ? tracksDir : nil, finalLUFS: mixed.finalLUFS,
                                             finalTruePeakDB: mixed.finalTruePeakDB, normalized: out.normalize,
                                             limitedByPeak: mixed.limitedByPeak, limiterEnabled: out.normalize && out.limiter,
                                             limiterApplied: mixed.limiterApplied,
                                             limiterMaxReductionDB: mixed.limiterMaxReductionDB,
                                             limiterOutOfTolerance: mixed.limiterOutOfTolerance,
                                             clippedFiles: mixed.clippedFiles.map { $0.url.lastPathComponent }))
        } catch {
            #if DEBUG
            exportRawError = "\(error) (cancelada: \(Task.isCancelled))"
            #endif
            // Cancelar borra lo a medias: los WAV ya escritos (el vídeo parcial lo borra el exportador).
            if let r = mixResult {
                for f in r.trackFiles { try? fm.removeItem(at: f.url) }
                try? fm.removeItem(at: r.mixURL)
                if out.trackWAVs, (try? fm.contentsOfDirectory(atPath: tracksDir.path))?.isEmpty == true { try? fm.removeItem(at: tracksDir) }
            }
            exportPhase = Task.isCancelled || error is CancellationError ? .idle : .failed("No se pudo exportar el vídeo (\(error)).")
        }
    }

    // MARK: Guardado

    private func scheduleSave() {
        dirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.saveDelay))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    func flush() async {
        saveTask?.cancel()
        saveTask = nil
        guard dirty else { return }
        dirty = false
        // Proyecto degradado (tomas huérfanas, sin `recording`): no se persiste un montaje por defecto sobre él.
        guard !session.project.hasOrphanedTakes else { return }
        try? await model.library?.saveMontage(id: session.projectID, state)
    }
}
