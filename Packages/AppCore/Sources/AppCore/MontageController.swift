import AudioKit
import Foundation
import NativeAudioFile
import Store
import VideoKit

// Copia portátil de `App/Sources/MontageController.swift` (W2-M1, paso 8 ola 2): puente Store → `MontagePlan` y
// `MontageMixJob`, análisis de encuadre con caché y exportación con progreso y cancelación, sin AppKit, AVPlayer ni
// Observation (los cambios se avisan con cierres que cablea `MontageMethods.swift`). La vista previa cambia: los
// fotogramas salen por `onPreviewFrame` a ritmo objetivo y el audio es un WAV mezclado con `MontageMixer` (en caché) que
// reproduce el reproductor portátil y que hace de reloj (no hay envolventes en vivo).

@MainActor
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
        /// Códec con que se escribió (en Windows siempre H.264, aunque se pidiera HEVC).
        var codec: String = "h264"
    }

    enum ExportPhase: Equatable {
        case idle
        case running(stage: String, progress: Double)
        case done(ExportResult)
        case failed(String)
        /// El usuario canceló (o salió con la exportación en curso): lo a medias ya está borrado.
        case cancelled
    }

    enum PreviewPhase: String, Equatable {
        /// Sin plan (no hay tomas con vídeo) o aún sin pedir.
        case none
        case preparing
        /// Fase 7c: alguna toma con vídeo se está convirtiendo a H.264 (o espera a que el visor la suelte).
        case converting
        case ready
        case error
    }

    enum AudioPhase: String, Equatable {
        case none
        /// Mezclando el WAV de la vista previa.
        case preparing
        case ready
        /// Montaje sin pistas de audio: la vista previa corre con reloj propio.
        case silent
        case error
    }

    /// Tiempos del controlador; los tests los acortan.
    struct Timing {
        /// Retardo antes de rehacer la vista previa tras un cambio (arrastrar la caja emite muchos).
        var previewDebounce = 0.15
        /// Rebote del guardado (igual que `StudySession.saveDelay`).
        var saveDelay = 0.5
    }

    /// Medidas de la vista previa en marcha (diagnóstico y tests).
    struct PreviewStats: Equatable {
        var delivered = 0
        /// Fotogramas de la rejilla del ritmo objetivo que no se pidieron porque el compositor iba atrasado.
        var skipped = 0
        var lastFrameMillis = 0.0
        var totalFrameMillis = 0.0
        var averageFrameMillis: Double { delivered > 0 ? totalFrameMillis / Double(delivered) : 0 }
        /// Últimas composiciones (ms), para p50/p95 (W2-E2: números de la vista previa).
        var recentMillis: [Double] = []
        static let window = 512

        mutating func record(_ ms: Double) {
            delivered += 1
            lastFrameMillis = ms
            totalFrameMillis += ms
            if recentMillis.count >= Self.window { recentMillis.removeFirst() }
            recentMillis.append(ms)
        }

        func percentile(_ p: Double) -> Double {
            guard !recentMillis.isEmpty else { return 0 }
            let s = recentMillis.sorted()
            return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))]
        }
    }

    /// Reparto del progreso único de la exportación: la mezcla (rápida) y el vídeo (el grueso).
    static let mixProgressShare = 0.15
    /// Anticipación al solo (mini-spec «Transiciones»), leída de VideoKit para no duplicarla, como texto («0,5 s»).
    static let anticipationLabel = "\(MontageStyle.anticipation.formatted(.number.precision(.fractionLength(0...2)))) s"
    /// Separación mínima entre dos cortes libres del plano único al arrastrar (s); decisión propia, no sale de la spec.
    static let minCutGap = 0.1
    /// Ritmo objetivo de la vista previa en fotogramas por segundo (Jorge, 21/11/2026, W2-M1: 15 por omisión).
    static let defaultPreviewFPS = 15.0
    static let previewFPSRange = 1.0...60.0
    /// Resoluciones y fotogramas por segundo ofrecidos en «Exportación» (`MontageView.fpsChoices`, `CameraChoices.presets`).
    static let exportResolutions: [VideoResolution] = [.hd720, .fullHD, .uhd4K]
    static let exportFPSChoices: [Double] = [24, 25, 30, 50, 60]
    /// Subcarpeta de `cache/` con el WAV de la vista previa y las imágenes de la hoja «Encuadre».
    static let cacheFolder = "cache/montage"
    /// Primera ventana en la que un fin de vídeo se da por alcanzado (s antes del final).
    static let endTolerance = 0.1

    let session: StudySession
    private let store: any MontageStoring
    private let services: MontageServices
    private let audio: any MontageAudioPlaying
    private let timing: Timing
    /// Copia local del proyecto (las tomas giradas y el montaje se guardan por `store`, no por `session`).
    private(set) var project: Project

    private(set) var state: MontageState
    private(set) var draft: MontageDraft?
    private(set) var analyses: [UUID: FramingAnalysis] = [:]
    private(set) var framingStatus: [UUID: FramingStatus] = [:]

    // Vista previa.
    private var composer: (any MontageComposing)?
    private var composerPlan: MontagePlan?
    private(set) var previewPhase = PreviewPhase.none
    private(set) var previewError: String?
    private(set) var audioPhase = AudioPhase.none
    private(set) var audioError: String?
    private(set) var audioProgress = 0.0
    /// Clave del WAV cargado y fichero (nil: sin audio).
    private(set) var previewAudioKey: String?
    private(set) var previewAudioURL: URL?
    /// Mezclas hechas desde que se abrió (los tests comprueban la invalidación de la caché).
    private(set) var previewMixCount = 0
    /// Segundos que tardó la última mezcla del WAV de la vista previa, y los de vídeo que cubría.
    private(set) var lastPreviewMixSeconds: Double?
    private(set) var lastPreviewMixVideoSeconds: Double?
    private(set) var isPlaying = false
    private var pausedSongTime = 0.0
    /// Ritmo objetivo de la vista previa.
    var previewFPS = MontageController.defaultPreviewFPS {
        didSet { previewFPS = min(max(previewFPS, Self.previewFPSRange.lowerBound), Self.previewFPSRange.upperBound) }
    }
    private(set) var previewStats = PreviewStats()
    /// Instante inicial de la vista previa (s del tema).
    var initialSongTime: Double?

    /// Fotograma BGRA compuesto y su PTS en ms de vídeo. Lo cablea el anfitrión (`FrameRelay`, canal `frames.montage`).
    var onPreviewFrame: (@Sendable (MontageFramePixels, _ ptsMs: Double) -> Void)?
    /// Algo observable cambió (el servicio emite `montage.state` solo si la instantánea cambia).
    var onChange: (() -> Void)?
    /// Cambió el estado de la exportación (progreso incluido).
    var onExport: (() -> Void)?
    /// Cambió el análisis de encuadre de una toma.
    var onFraming: ((UUID) -> Void)?
    /// Fase 7c: antes de leer el vídeo de una toma (vista previa, encuadre, export) se pregunta aquí; si hay que convertirlo,
    /// el motor lo encola y la toma espera. nil = siempre listo (Mac, tests sin conversión).
    var videoGate: ((_ takeID: UUID, _ files: [URL?]) -> TakeVideoState)?
    /// Tomas cuyo vídeo aún no se puede leer (solo las que no están `ready`).
    private(set) var videoStates: [UUID: TakeVideoState] = [:]

    // Exportación.
    private(set) var exportPhase: ExportPhase = .idle

    private var previewTask: Task<Void, Never>?
    /// Mezcla del WAV de la vista previa en curso (o la última): la siguiente espera a que acabe, aunque esté anulada.
    private var previewMixTask: Task<MontageMixResult, Error>?
    private var frameTask: Task<Void, Never>?
    private var stillTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var durations: [URL: Double] = [:]
    private var closed = true
    private var dirty = false
    private var framingImageVersion = 0
    private var frameFailures = 0
    private var framesFailed = false
    private var loggedFrameFailures = Set<String>()

    init(session: StudySession, video: VideoSettings?, store: any MontageStoring, services: MontageServices = .production,
         audio: any MontageAudioPlaying, timing: Timing = Timing()) {
        self.session = session
        self.store = store
        self.services = services
        self.audio = audio
        self.timing = timing
        project = session.project
        state = session.project.montageOrInitial(video: video)
        rebuildDraft()
    }

    // MARK: Datos

    var song: Song { project.song }
    var sections: [Store.Section] { project.sections }
    var lanes: [MontageLane] { draft?.lanes ?? [] }
    var videoLanes: [MontageLane] { lanes.filter { $0.hasVideo && !$0.presence.isEmpty } }
    var isPortrait: Bool { MontagePlanning.isPortrait(state.layout) }
    var canvasLabel: String { isPortrait ? "1080 × 1920" : "1920 × 1080" }
    var span: LaneSpan { draft?.span ?? LaneSpan(start: 0, end: 0) }
    var isAnalyzing: Bool {
        framingStatus.values.contains { if case .analyzing = $0 { return true }; return $0 == .pending }
    }
    var isExporting: Bool { if case .running = exportPhase { return true }; return false }
    var canExport: Bool { draft != nil && !isExporting && !isAnalyzing && videoStates.isEmpty }
    var singleRhythmCandidates: [MontageLane] { lanes.filter { $0.hasVideo && !$0.isSolo && !$0.presence.isEmpty } }
    var previewReady: Bool { composer != nil }
    /// Duración del vídeo de la vista previa (s), si hay compositor.
    var previewDuration: Double? { composer?.duration }

    func lane(takeID: UUID) -> MontageLane? { lanes.first { $0.takeID == takeID } }

    /// Sección del tema en `t` (para la etiqueta de la vista previa).
    func sectionName(at t: Double) -> String? { sections.first { t >= $0.start && t < $0.end }?.name }
    func isSoloSection(at t: Double) -> Bool { sections.first { t >= $0.start && t < $0.end }?.isSolo ?? false }

    /// Opciones de exportación de este sistema, tal como las da VideoKit (en Windows el único códec es H.264).
    var codecOptions: [VideoCodec] { MontageCodec.supported.map { VideoCodec(rawValue: $0.rawValue) ?? .h264 } }
    var containerOptions: [MontageContainer] { MontageVideoContainer.allCases.map { MontageContainer(rawValue: $0.rawValue) ?? .mov } }
    /// Códec que se usará de verdad: el elegido si el sistema lo admite, si no el preferido.
    var effectiveCodec: VideoCodec { codecOptions.contains(state.export.codec) ? state.export.codec : (codecOptions.first ?? .h264) }

    // MARK: Ciclo de vida

    func open() {
        closed = false
        pausedSongTime = initialSongTime ?? span.start
        startAnalysis()
        schedulePreview(delay: 0)
    }

    func close() {
        closed = true
        previewTask?.cancel()
        frameTask?.cancel()
        stillTask?.cancel()
        analysisTask?.cancel()
        pausedSongTime = songTime
        audio.shutdown()
        isPlaying = false
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
        var order = state.effectiveOrder(of: project.recordingOrInitial().parts.map(\.id))
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
    var existingPartIDs: [UUID] { project.recordingOrInitial().parts.map(\.id) }
    /// Parte que manda en `t` según los cortes (nil = automático); es la que hereda un corte nuevo.
    func singlePart(at t: Double) -> UUID? { state.singlePart(at: t, existingPartIDs: existingPartIDs) }
    /// Lo que de verdad se ve en el plano único (color del carril «Plano»): un corte a una parte sin toma se pinta
    /// con la que elige el automático (decisión de Jorge del 17/11/2026).
    var planeShots: [PlaneShot] { MontagePlanning.planeShots(plan: draft?.plan) }
    /// ¿Tiene toma con imagen la parte elegida en el corte, en su instante? (nil o automático: sí).
    func cutEligiblePartIDs(at t: Double) -> Set<UUID> { MontagePlanning.cutEligibleParts(plan: draft?.plan, at: t) }
    func cutPartCovered(_ cut: MontageSingleCut) -> Bool {
        guard let p = cut.partID else { return true }
        return MontagePlanning.cutEligibleParts(plan: draft?.plan, at: cut.time).contains(p)
    }

    /// `t` ajustado al pulso más cercano (sin pulso, sin ajuste) y dentro del tramo del vídeo.
    func snappedCutTime(_ t: Double) -> Double {
        let snapped = SectionEditor.snap(t, to: session.beats)
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

    /// Corte con parte explícita (nil = automático) y, si `exact`, sin ajuste al pulso.
    @discardableResult
    func addCut(at t: Double, partID: UUID?, exact: Bool) -> UUID {
        let id = UUID()
        state = state.addingSingleCut(at: exact ? min(max(t, span.start), span.end) : snappedCutTime(t), partID: partID, id: id)
        changed()
        return id
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
        let before = state.export
        change(&state.export)
        guard state.export != before else { return }
        rebuildDraft()
        scheduleSave()
        if state.export.fps != before.fps { schedulePreview() }
        notify()
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
        notify()
    }

    private func notify() { onChange?() }

    /// Caja de la guitarra que se dibuja en la hoja «Encuadre»: con el ajuste manual, en el instante `t`.
    func effectiveBox(takeID: UUID, at t: Double) -> NormalizedRect? { effectiveBox(takeID: takeID, at: t, framing: state.framing(for: takeID)) }

    /// Igual que `effectiveBox(takeID:at:)` con un encuadre hipotético `framing` (consulta en vivo durante un arrastre; no guarda nada).
    func effectiveBox(takeID: UUID, at t: Double, framing: TakeFraming) -> NormalizedRect? {
        let f = MontagePlanning.framing(framing, analysis: analyses[takeID])
        return f.box(at: t).map { NormalizedRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
    }

    // MARK: Plan

    private func takeDuration(_ url: URL) -> Double? {
        if let d = durations[url] { return d }
        guard let f = try? AudioFileReader(url: url), f.sampleRate > 0 else { return nil }
        let d = Double(f.frameCount) / f.sampleRate
        durations[url] = d
        return d
    }

    var barDuration: Double { MontagePlan.barDuration(bpm: session.analysis?.bpm, beatsPerBar: session.analysis?.beatsPerBar) }

    private func rebuildDraft() {
        let layout = session.layout
        let fm = FileManager.default
        let stems = session.mixerStems.filter { fm.fileExists(atPath: layout.stemURL($0).path) }
        draft = MontagePlanning.build(project: project, layout: layout, state: state, barDuration: barDuration,
                                      analyses: analyses, stems: stems, guitarRoles: session.guitarTracks.map(\.role),
                                      takeDuration: { [unowned self] in self.takeDuration($0) })
    }

    // MARK: Análisis de encuadre

    private func startAnalysis() {
        analysisTask?.cancel()
        let pending = videoLanes
        for l in pending where framingStatus[l.takeID] == nil { setFraming(l.takeID, .pending) }
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
        setFraming(takeID, .pending)
        let previous = analysisTask
        analysisTask = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await self.analyze(l)
        }
    }

    private func setFraming(_ id: UUID, _ s: FramingStatus?) {
        framingStatus[id] = s
        onFraming?(id)
        notify()
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
        // Fase 7c: sin vídeo legible no se analiza; al acabar la conversión `videoConversionFinished` lo relanza.
        switch videoState(lane) {
        case .ready: break
        case .failed(let m):
            setFraming(id, .failed(VideoConversionEngine.failedMessage(m)))
            return
        default:
            setFraming(id, .pending)
            return
        }
        setFraming(id, .analyzing(0))
        do {
            let a = try await services.analyze(video) { [weak self] p in
                Task { @MainActor in
                    guard let self, case .analyzing = self.framingStatus[id] else { return }
                    self.framingStatus[id] = .analyzing(p)
                    self.onFraming?(id)
                }
            }
            try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(a) { try? data.write(to: cache, options: .atomic) }
            finishAnalysis(id, a)
        } catch is CancellationError {
            setFraming(id, .pending)
        } catch {
            setFraming(id, .failed("\(error)"))
        }
    }

    private func finishAnalysis(_ id: UUID, _ a: FramingAnalysis) {
        guard !closed else { return }
        analyses[id] = a
        framingStatus[id] = .ready(samples: a.samples, detected: a.detected)
        onFraming?(id)
        rebuildDraft()
        schedulePreview()
        notify()
    }

    // MARK: Conversión del vídeo (Fase 7c)

    /// Estado del vídeo de la toma (base y punches) según el motor de conversión; lo apunta en `videoStates`.
    private func videoState(_ lane: MontageLane) -> TakeVideoState {
        guard let gate = videoGate, let v = lane.video else { return .ready }
        let s = gate(lane.takeID, [v.url] + v.punches.map(\.videoURL))
        videoStates[lane.takeID] = s == .ready ? nil : s
        return s
    }

    static let videoWaitMessage = "Hay vídeos de tomas convirtiéndose a H.264 (o con la conversión fallida): espera a que acaben."

    /// Vuelve a preguntar por los vídeos del plan (export).
    func refreshVideoStates() { _ = videosBlocking() }

    /// Pregunta por todas las tomas con vídeo del plan; `nil` si todas están listas, si no el motivo de la espera.
    private func videosBlocking() -> TakeVideoState? {
        // Todas las partes con vídeo del plan, también las de presencia vacía (p. ej. un solo sin sección «Solo»): el
        // compositor abre su fichero igualmente, y un HEVC sin convertir allí rompe la vista previa y el export.
        let lanes = lanes.filter(\.hasVideo)
        let ids = Set(lanes.map(\.takeID))
        videoStates = videoStates.filter { ids.contains($0.key) }
        let states = lanes.map { videoState($0) }
        if let failed = states.first(where: { if case .failed = $0 { return true }; return false }) { return failed }
        return states.first { $0 != .ready }
    }

    /// Fin de una conversión (lo avisa el motor): con el vídeo ya sustituido se reanaliza y se rehace la vista previa.
    func videoConversionFinished(takeId: UUID, state: TakeVideoState) {
        guard !closed, lane(takeID: takeId)?.video != nil else { return }
        switch state {
        case .ready:
            videoStates[takeId] = nil
            analyses[takeId] = nil
            framingStatus[takeId] = nil
            startAnalysis()
            schedulePreview(delay: 0)
        case .failed(let m):
            videoStates[takeId] = state
            setFraming(takeId, .failed(VideoConversionEngine.failedMessage(m)))
            schedulePreview(delay: 0)
        case .converting, .awaitingRelease:
            videoStates[takeId] = state
        }
        notify()
    }

    // MARK: Vista previa

    private func schedulePreview(delay: Double? = nil) {
        previewTask?.cancel()
        let wait = delay ?? timing.previewDebounce
        previewTask = Task { [weak self] in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            await self?.buildPreview()
        }
    }

    /// Reloj de la vista previa en segundos de vídeo.
    var videoPosition: Double { composer == nil ? 0 : audio.currentTime }

    /// Posición en tiempo del tema.
    var songTime: Double {
        guard let c = composer else { return pausedSongTime }
        return c.songTime(videoTime: audio.currentTime)
    }

    private func buildPreview() async {
        guard !closed else { return }
        guard let draft else {
            composer = nil
            composerPlan = nil
            setPreview(.none)
            return
        }
        let plan = draft.plan
        let wasPlaying = isPlaying
        let keep = composer == nil ? (initialSongTime ?? plan.span.start) : songTime
        if wasPlaying { pauseClock() }

        // 0. Fase 7c: ningún vídeo que haya que convertir llega al compositor.
        if let blocking = videosBlocking() {
            composer = nil
            composerPlan = nil
            if case .failed(let m) = blocking {
                previewError = "No se pudo preparar la vista previa: \(VideoConversionEngine.failedMessage(m))"
                setPreview(.error, error: previewError)
            } else {
                setPreview(.converting)
            }
            return
        }

        // 1. Compositor (solo si cambia algo del vídeo: el audio no cuenta).
        var videoPlan = plan
        videoPlan.audio = []
        if composer == nil || composerPlan != videoPlan {
            setPreview(.preparing)
            do {
                let c = try await services.makeComposer(videoPlan, MontagePlanning.previewMaxDimension)
                guard !Task.isCancelled, !closed else { return }
                composer = c
                composerPlan = videoPlan
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, !closed else { return }
                composer = nil
                composerPlan = nil
                previewError = "No se pudo preparar la vista previa (\(error))."
                setPreview(.error, error: previewError)
                return
            }
        }
        guard let composer else { return }

        // 2. Audio: el WAV de la mezcla (en caché mientras no cambie nada que afecte a la mezcla).
        await prepareAudio(draft, duration: composer.duration)
        guard !Task.isCancelled, !closed else { return }

        let t = min(max(keep, plan.span.start), plan.span.end)
        pausedSongTime = t
        audio.seek(to: composer.videoTime(songTime: t))
        setPreview(.ready)
        if wasPlaying {
            do { try audio.play(); isPlaying = true; startFrameLoop() } catch { isPlaying = false; audioError = Self.playError(error) }
        } else {
            requestStill()
        }
        notify()
    }

    private func setPreview(_ p: PreviewPhase, error: String? = nil) {
        previewPhase = p
        if p != .error { previewError = nil } else { previewError = error }
        notify()
    }

    private static func playError(_ error: Error) -> String {
        "No se pudo reproducir: la salida de audio no abre (\((error as? LocalizedError)?.errorDescription ?? "\(error)"))."
    }

    /// Clave de la mezcla de la vista previa: todo lo que cambia el WAV (tramos, pistas con su fichero, volumen y presencia).
    static func audioKey(_ draft: MontageDraft, sampleRate: Double, files: (URL) -> String) -> String {
        func r(_ x: Double) -> String { String(Int((x * 1_000_000).rounded())) }
        var s = "rate=\(sampleRate);bar=\(r(draft.plan.barDuration));"
        s += draft.segments.map { "\(r($0.start))-\(r($0.end))\($0.fadeIn ? "i" : "")\($0.fadeOut ? "o" : "")" }.joined(separator: ",")
        for t in draft.mixTracks {
            s += ";\(t.id)|\(files(t.url))|\(r(t.songStart))|\(r(t.gainDB))|\(t.group)|"
            switch t.presence {
            case .always: s += "always"
            case .silenced(let spans): s += "silenced:" + spans.map { "\(r($0.start))-\(r($0.end))" }.joined(separator: ",")
            case .audible(let spans): s += "audible:" + spans.map { "\(r($0.start))-\(r($0.end))" }.joined(separator: ",")
            }
        }
        // FNV-1a de 64 bits (sin CryptoKit, que no existe en Windows).
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x1_0000_01b3 }
        return String(h, radix: 16)
    }

    private var mixSampleRate: Double { [44_100.0, 48_000.0].contains(project.song.sampleRate) ? project.song.sampleRate : 48_000 }

    private func fileFingerprint(_ url: URL) -> String {
        let a = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (a?[.size] as? NSNumber)?.int64Value ?? -1
        let mtime = (a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(url.path):\(size):\(Int(mtime * 1000))"
    }

    private func prepareAudio(_ draft: MontageDraft, duration: Double) async {
        if draft.mixTracks.isEmpty {
            previewAudioKey = nil
            previewAudioURL = nil
            try? audio.load(url: nil, duration: duration)
            audioPhase = .silent
            audioError = nil
            return
        }
        let key = Self.audioKey(draft, sampleRate: mixSampleRate, files: { [self] in fileFingerprint($0) })
        let dir = session.layout.url(relative: Self.cacheFolder)
        let url = dir.appendingPathComponent("preview-\(key).wav")
        let fm = FileManager.default
        if key == previewAudioKey, previewAudioURL == url, fm.fileExists(atPath: url.path) { return }
        if !fm.fileExists(atPath: url.path) {
            audioPhase = .preparing
            audioProgress = 0
            audioError = nil
            notify()
            // Un cambio que no toca la clave (el análisis de encuadre al acabar) anula esta tarea a mitad de mezcla, y la
            // mezcla anulada sigue hasta su siguiente bloque. Dos reglas para que no se pisen: se espera a que la anterior
            // acabe (en Windows su parcial sigue abierto) y cada intento escribe su propio parcial (la limpieza del anulado
            // borraba por ruta el del siguiente y su `moveItem` fallaba: vista previa en `.error`).
            if let previous = previewMixTask {
                previous.cancel()
                _ = await previous.result
                guard !Task.isCancelled, !closed else { return }
            }
            let partial = dir.appendingPathComponent("preview-\(key).\(UUID().uuidString).partial.wav")
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let job = MontageMixJob(segments: draft.segments.map { MixSegment(start: $0.start, end: $0.end, fadeIn: $0.fadeIn, fadeOut: $0.fadeOut) },
                                    sampleRate: mixSampleRate, tracks: draft.mixTracks, fadeIn: draft.plan.barDuration,
                                    fadeOut: draft.plan.barDuration, normalization: MontageNormalization.none,
                                    mixURL: partial, trackDirectory: nil)
            let started = ProcessInfo.processInfo.systemUptime
            do {
                let mix = services.mix
                let mixing = Task.detached(priority: .userInitiated) {
                    try await mix(job) { [weak self] p in Task { @MainActor in self?.setAudioProgress(p) } }
                }
                previewMixTask = mixing
                _ = try await withTaskCancellationHandler { try await mixing.value } onCancel: { mixing.cancel() }
                try Task.checkCancellation()
                try? fm.removeItem(at: url)
                try fm.moveItem(at: partial, to: url)
                lastPreviewMixSeconds = ProcessInfo.processInfo.systemUptime - started
                lastPreviewMixVideoSeconds = duration
                previewMixCount += 1
            } catch {
                try? fm.removeItem(at: partial)
                if Task.isCancelled || error is CancellationError { return }
                // Sin WAV la vista previa corre con reloj propio y sin sonido; el fallo se dice aparte.
                previewAudioKey = nil
                previewAudioURL = nil
                try? audio.load(url: nil, duration: duration)
                audioPhase = .error
                audioError = "No se pudo mezclar el audio de la vista previa (\(error))."
                return
            }
        }
        do {
            try audio.load(url: url, duration: duration)
            previewAudioKey = key
            previewAudioURL = url
            audioPhase = .ready
            audioError = nil
            removeOldPreviews(keeping: url)
        } catch {
            previewAudioKey = nil
            previewAudioURL = nil
            try? audio.load(url: nil, duration: duration)
            audioPhase = .error
            audioError = "No se pudo abrir el audio de la vista previa (\(error))."
        }
    }

    private func setAudioProgress(_ p: Double) {
        guard audioPhase == .preparing else { return }
        audioProgress = min(max(p, 0), 1)
        notify()
    }

    private func removeOldPreviews(keeping url: URL) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        where f.lastPathComponent.hasPrefix("preview-") && f.lastPathComponent != url.lastPathComponent {
            try? fm.removeItem(at: f)
        }
    }

    // MARK: Transporte de la vista previa

    /// Da a play; sin vista previa lista no hace nada. Si la salida de audio no abre, lanza `audio-unavailable`.
    func play() throws {
        guard composer != nil, !isPlaying else { return }
        if songTime >= span.end - Self.endTolerance { seek(to: span.start) }
        do {
            try audio.play()
        } catch {
            audioError = Self.playError(error)
            notify()
            throw RPCError(code: "audio-unavailable", message: audioError ?? "")
        }
        audioError = nil
        isPlaying = true
        startFrameLoop()
        notify()
    }

    func pause() {
        guard isPlaying else { return }
        pauseClock()
        requestStill()
        notify()
    }

    func togglePlay() throws { if isPlaying { pause() } else { try play() } }

    private func pauseClock() {
        audio.pause()
        isPlaying = false
        frameTask?.cancel()
        frameTask = nil
        pausedSongTime = songTime
    }

    func seek(to t: Double) {
        let t = min(max(t, span.start), span.end)
        pausedSongTime = t
        if let c = composer {
            audio.seek(to: c.videoTime(songTime: t))
            if !isPlaying { requestStill() }
        }
        notify()
    }

    /// Fotograma suelto en la posición actual (al hacer seek en pausa y al terminar de preparar la vista previa).
    func requestStill() {
        stillTask?.cancel()
        guard composer != nil else { return }
        stillTask = Task { [weak self] in
            guard let self, !Task.isCancelled, !self.isPlaying else { return }
            await self.renderAndEmit(videoTime: self.audio.currentTime, isStill: true)
        }
    }

    /// Bucle de la vista previa: pide `MontagePreview.frame(at:)` a `previewFPS` y, si el compositor va atrasado, la
    /// siguiente petición ya es la del reloj de ahora (se saltan los fotogramas intermedios).
    private func startFrameLoop() {
        frameTask?.cancel()
        previewStats = PreviewStats()
        frameTask = Task { [weak self] in
            let clock = ContinuousClock()
            var deadline = clock.now
            var lastVideoTime: Double?
            while !Task.isCancelled {
                guard let self, self.isPlaying, let composer = self.composer else { return }
                let v = self.audio.currentTime
                if v >= composer.duration - 1e-6 || !self.audio.isPlaying {
                    self.reachedEnd(videoTime: v, duration: composer.duration)
                    return
                }
                let fps = self.previewFPS
                if let last = lastVideoTime {
                    // Fotogramas de la rejilla objetivo entre la petición anterior y esta que no se renderizaron.
                    self.previewStats.skipped += max(0, Int(((v - last) * fps).rounded()) - 1)
                }
                lastVideoTime = v
                await self.renderAndEmit(videoTime: v, isStill: false)
                deadline += .seconds(1 / fps)
                if deadline > clock.now { try? await clock.sleep(until: deadline) } else { deadline = clock.now }
            }
        }
    }

    private func reachedEnd(videoTime v: Double, duration: Double) {
        audio.pause()
        isPlaying = false
        frameTask = nil
        pausedSongTime = composer?.songTime(videoTime: min(v, duration)) ?? pausedSongTime
        requestStill()
        notify()
    }

    private func renderAndEmit(videoTime v: Double, isStill: Bool) async {
        guard let composer else { return }
        let t = min(max(0, v), composer.duration)
        let started = ProcessInfo.processInfo.systemUptime
        let outcome: Result<MontageFrameBox, Error> = await Task.detached(priority: .userInitiated) {
            Result { MontageFrameBox(pixels: try composer.frame(atVideoTime: t)) }
        }.value
        guard !Task.isCancelled else { return }
        let result: MontageFrameBox
        switch outcome {
        case .failure(let error):
            noteFrameFailure(error, videoTime: t)
            return
        case .success(let box):
            result = box
            frameFailures = 0
            if framesFailed {
                framesFailed = false
                if previewPhase == .error { setPreview(.ready) }
            }
        }
        if isStill && isPlaying { return }
        let ms = (ProcessInfo.processInfo.systemUptime - started) * 1000
        previewStats.record(ms)
        onPreviewFrame?(result.pixels, t * 1000)
    }

    /// El compositor falló al dar un fotograma: un registro por causa distinta y, si persiste, `preview.error` (la vista
    /// previa no se queda muda sin explicación).
    private func noteFrameFailure(_ error: Error, videoTime t: Double) {
        let text = String(reflecting: error)
        if loggedFrameFailures.insert(text).inserted {
            FileHandle.standardError.write(Data(String(format: "[montage] fotograma de la vista previa en %.3f s: %@\n", t, text).utf8))
        }
        frameFailures += 1
        guard frameFailures >= Self.frameFailureLimit, !framesFailed else { return }
        framesFailed = true
        previewError = "No se pudo componer la vista previa (\(error))."
        setPreview(.error, error: previewError)
    }

    /// Fallos seguidos del compositor a partir de los cuales se avisa en `preview.error`.
    static let frameFailureLimit = 3

    // MARK: Fotograma de la hoja «Encuadre»

    struct FramingFrame: Equatable {
        var url: URL
        /// Ruta relativa a la carpeta del tema (con `/`), para el `mediaBase` de la página.
        var relativePath: String
        var width: Int
        var height: Int
        var time: Double
        var version: Int
    }

    /// Fotograma de la toma en el instante `t` del tema (base o punch, con su desfase), ya girado, escrito como PNG en
    /// `cache/montage/` (equivale a `frameImage` del Mac).
    func framingFrame(takeID: UUID, at t: Double) async throws -> FramingFrame {
        guard let video = lane(takeID: takeID)?.video,
              let rel = project.takes.first(where: { $0.id == takeID })?.processedFile else {
            throw RPCError(code: "not-found", message: "La toma no tiene vídeo.")
        }
        if let l = lane(takeID: takeID), let info = TakeVideoStatusInfo(takeId: takeID, state: videoState(l)) {
            notify()
            throw info.rpcError
        }
        let audioURL = session.layout.url(relative: rel)
        let pixels: MontageFramePixels?
        do { pixels = try await services.takeFrame(video, audioURL, t) } catch {
            throw RPCError(code: "internal", message: "No se pudo leer el fotograma de la toma (\(error)).")
        }
        guard let pixels, let raw = MontageFrameImage.raw(pixels) else {
            throw RPCError(code: "no-frame", message: "La toma no tiene imagen en ese instante.")
        }
        let png = MontageFrameImage.png(raw)
        let relative = "\(Self.cacheFolder)/framing-\(takeID.uuidString).png"
        let url = session.layout.url(relative: relative)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { try png.write(to: url, options: .atomic) } catch {
            throw RPCError(code: "internal", message: "No se pudo guardar el fotograma (\(error)).")
        }
        let k = min(1, Double(MontageFrameImage.framingMaxDimension) / Double(max(raw.width, raw.height)))
        framingImageVersion += 1
        return FramingFrame(url: url, relativePath: relative, width: max(1, Int((Double(raw.width) * k).rounded())),
                            height: max(1, Int((Double(raw.height) * k).rounded())), time: t, version: framingImageVersion)
    }

    // MARK: Giro de la toma («Rotar»)

    /// Giro de la toma (0, 90, 180 o 270).
    func rotation(takeID: UUID) -> Int { project.takes.first { $0.id == takeID }?.rotationDegrees ?? 0 }

    /// «Rotar» en la ficha de la toma: 90° más en sentido horario, guardado en la toma. El encuadre guardado se gira con
    /// la imagen (`TakeFraming.rotatedClockwise`) y el análisis se rehace (su huella incluye el giro).
    func rotateTake(_ takeID: UUID) {
        guard let i = project.takes.firstIndex(where: { $0.id == takeID }) else { return }
        var take = project.takes[i]
        take.videoRotation = VideoSettings.normalizedRotation(take.rotationDegrees + 90)
        project.takes[i] = take
        let id = session.projectID, store = store
        Task { try? await store.saveTakes(id: id, [take]) }
        if state.framing[takeID] != nil { state.framing[takeID] = state.framing(for: takeID).rotatedClockwise(quarterTurns: 1) }
        analyses[takeID] = nil
        framingStatus[takeID] = nil
        changed()
        startAnalysis()
    }

    // MARK: Exportación

    func startExport() {
        refreshVideoStates()   // Fase 7c: export solo con todos los vídeos legibles (y encola los que falten)
        guard canExport, let draft, exportTask == nil else { return }
        if isPlaying { pauseClock() }
        setExport(.running(stage: "Mezclando el audio", progress: 0))
        exportTask = Task { [weak self] in
            await self?.runExport(draft)
        }
    }

    /// Lanza la exportación y espera a que termine.
    func exportAndWait() async {
        startExport()
        await exportTask?.value
    }

    func cancelExport() { exportTask?.cancel() }

    func dismissExportResult() { if !isExporting { setExport(.idle) } }

    private func setExport(_ p: ExportPhase) {
        exportPhase = p
        onExport?()
        notify()
    }

    private func setProgress(_ stage: String, _ p: Double) {
        guard case .running(_, let old) = exportPhase else { return }
        exportPhase = .running(stage: stage, progress: max(old, min(max(p, 0), 1)))
        onExport?()
    }

    private func runExport(_ draft: MontageDraft) async {
        let fm = FileManager.default
        let layout = session.layout
        let kind = state.layout
        let out = state.export
        let codec = effectiveCodec
        let url = layout.montageVideoURL(layout: kind, container: out.container)
        let tracksDir = layout.montageTracksDirectory(layout: kind)
        let temp = fm.temporaryDirectory.appendingPathComponent("tf-montage-export-\(UUID().uuidString)", isDirectory: true)
        let mixURL = (out.trackWAVs ? tracksDir : temp).appendingPathComponent("mezcla.wav")
        let plan = draft.plan
        let job = MontageMixJob(segments: draft.segments.map { MixSegment(start: $0.start, end: $0.end, fadeIn: $0.fadeIn, fadeOut: $0.fadeOut) },
                                sampleRate: mixSampleRate,
                                tracks: draft.mixTracks, fadeIn: plan.barDuration,
                                fadeOut: plan.barDuration,
                                normalization: out.normalize ? (out.limiter ? MontageNormalization.standard : MontageNormalization.standardWithoutLimiter) : MontageNormalization.none,
                                mixURL: mixURL, trackDirectory: out.trackWAVs ? tracksDir : nil)
        let size = MontagePlanning.exportSize(out.resolution, kind: kind)
        let videoContainer: MontageVideoContainer = out.container == .mov ? .mov : .mp4
        let settings = MontageExportSettings(codec: codec == .hevc ? .hevc : .h264, width: size.width, height: size.height, fps: out.fps,
                                             container: videoContainer)
        var mixResult: MontageMixResult?
        let mix = services.mix, export = services.export
        defer {
            try? fm.removeItem(at: temp)
            exportTask = nil
        }
        do {
            try fm.createDirectory(at: layout.videoDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: mixURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let share = Self.mixProgressShare
            let mixing = Task.detached(priority: .userInitiated) {
                try await mix(job) { [weak self] p in Task { @MainActor in self?.setProgress("Mezclando el audio", p * share) } }
            }
            let mixed = try await withTaskCancellationHandler { try await mixing.value } onCancel: { mixing.cancel() }
            mixResult = mixed
            try Task.checkCancellation()
            let exporting = Task.detached(priority: .userInitiated) {
                try await export(plan, mixed.mixURL, settings, url) { [weak self] p in
                    Task { @MainActor in self?.setProgress("Codificando el vídeo", share + p * (1 - share)) }
                }
            }
            let summary = try await withTaskCancellationHandler { try await exporting.value } onCancel: { exporting.cancel() }
            setExport(.done(ExportResult(url: url, tracksDirectory: out.trackWAVs ? tracksDir : nil, finalLUFS: mixed.finalLUFS,
                                         finalTruePeakDB: mixed.finalTruePeakDB, normalized: out.normalize,
                                         limitedByPeak: mixed.limitedByPeak, limiterEnabled: out.normalize && out.limiter,
                                         limiterApplied: mixed.limiterApplied,
                                         limiterMaxReductionDB: mixed.limiterMaxReductionDB,
                                         limiterOutOfTolerance: mixed.limiterOutOfTolerance,
                                         clippedFiles: mixed.clippedFiles.map { $0.url.lastPathComponent },
                                         codec: summary.codec)))
        } catch {
            // Cancelar borra lo a medias: los WAV ya escritos (el vídeo parcial lo borra el exportador).
            if let r = mixResult {
                for f in r.trackFiles { try? fm.removeItem(at: f.url) }
                try? fm.removeItem(at: r.mixURL)
            }
            // La carpeta `-pistas` se crea antes de mezclar: si se cancela durante la mezcla (sin `mixResult`) queda vacía.
            if out.trackWAVs, (try? fm.contentsOfDirectory(atPath: tracksDir.path))?.isEmpty == true { try? fm.removeItem(at: tracksDir) }
            setExport(Task.isCancelled || error is CancellationError ? .cancelled : .failed("\(error)"))
        }
    }

    // MARK: Guardado

    private func scheduleSave() {
        dirty = true
        saveTask?.cancel()
        let delay = timing.saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
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
        guard !project.hasOrphanedTakes else { return }
        try? await store.saveMontage(id: session.projectID, state)
    }
}
