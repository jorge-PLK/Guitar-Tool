import AudioKit
import AVFoundation
import Foundation
import Observation
import Store
import VideoKit

/// Recibe los fotogramas de la cámara (siempre en marcha mientras Grabar está abierta) y los pasa al grabador de la
/// toma en curso; fuera de una toma no hay grabador y se tiran.
final class RecordFrameRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var target: VideoTakeRecorder?
    func set(_ r: VideoTakeRecorder?) { lock.withLock { target = r } }
    func handle(_ f: CameraFrame) { lock.withLock { target }?.handle(f) }
}

/// Pasa el reloj del audio (marcas de host de la sesión y ancla) al `HostTimeMap` de la toma de vídeo; es el
/// `MapFeeder` de `tf-video` (mini-spec Fase 6, «Cámara y sincronía»).
@MainActor
final class RecordMapFeeder {
    let session: AudioSession
    let recorder: VideoTakeRecorder
    private var last = Int64.min

    init(session: AudioSession, recorder: VideoTakeRecorder) {
        self.session = session
        self.recorder = recorder
    }

    /// Añade las marcas nuevas y el ancla actual. Devuelve si ya hay ancla.
    @discardableResult
    func feed() -> Bool {
        let points = session.outputHostClock(after: last)
        let anchor = session.playbackAnchor
        if let p = points.last { last = p.sampleTime }
        recorder.updateMap { m in
            for p in points { m.addClockPoint(outputSample: Double(p.sampleTime), hostSeconds: p.hostSeconds) }
            if let a = anchor {
                m.setAnchor(HostTimeMap.Anchor(songTime: a.songTime, outputSample: a.outputSample, sampleRate: a.sampleRate, rate: a.rate))
            }
        }
        return !recorder.map.anchors.isEmpty
    }
}

/// Lo que se está grabando: una toma nueva o un punch sobre una toma.
struct TakePlan {
    struct Punch { var n: Int; var start: Double; var end: Double }
    var takeID: UUID
    var partID: UUID
    var punch: Punch?
    var playFrom: Double
    /// Se para solo en este instante del tema: en un punch, salida + 0,5 s; en una toma desde una sección, su final + margen.
    var stopAt: Double?
    var audioURL: URL
    var videoURL: URL
}

/// Toma recién grabada a la espera de «Guardar toma» / «Descartar toma».
struct PendingTake {
    var takeID: UUID
    var partID: UUID
    var recorded: RecordedTake
    var format: VideoFormat?
}

/// Hoja «Ajustar desfase» (al parar una toma o desde el menú de toma).
struct OffsetRequest: Identifiable {
    let id = UUID()
    var takeID: UUID
    var isNew: Bool
    var audioURL: URL
    var songStart: Double
    var videoURL: URL
    var punches: [PreviewPunch]
    var fps: Double
    var cameraID: String
    var cameraName: String
    var initialOffset: Double
    /// Giro de la imagen (grados en sentido horario) con que se ve la toma.
    var rotation: Int = 0
}

private struct RecordFailure: Error { let message: String }

/// Pantalla Grabar (mini-spec Fase 6): partes, mezcla propia, cámara, flujo de toma y punch-in.
@MainActor @Observable
final class RecordController {
    enum Phase: Equatable { case idle, counting(Int), recording, finishing, adjusting }
    enum CameraState {
        case idle, none(String), denied, simulated, failed(String)
        case live(AVCaptureSession)
    }
    enum PartStatus { case pending, recording, done }

    /// Mini-spec Fase 6, «Medido con hardware»: los fotogramas llegan con hasta ~254 ms de retraso; al parar se sigue
    /// recibiendo ~0,5 s (o hasta un fotograma con marca posterior al fin, con tope) antes de cerrar el escritor.
    static let videoTailSeconds = 0.5
    static let videoTailMaxSeconds = 1.2
    /// Mini-spec Fase 6, «Punch-in»: se para solo 0,5 s después de la salida.
    static let punchStopAfterSeconds = 0.5
    /// Mini-spec Fase 6, «Interfaz»: el desfase se ajusta en ±500 ms.
    static let offsetRangeMs: ClosedRange<Double> = -500...500
    static let punchBaseTrackID = "take-self"
    /// Frecuencia de la cuenta (Hz del clic: acento y resto).
    static let countAccentHz = 1500.0, countHz = 1000.0

    let session: StudySession
    @ObservationIgnored unowned let model: AppModel
    let player: StudyPlayer

    var state: RecordingState
    private(set) var activePartID: UUID?
    var phase: Phase = .idle
    private(set) var loadError: String?
    private(set) var messages: [String] = []
    /// true = proyecto degradado sin índice recuperable: no se guarda `recording` (ni automáticamente ni por edición).
    @ObservationIgnored private var savesBlocked = false
    var selectedTakeID: UUID?
    private(set) var startSectionID: UUID?
    var offsetRequest: OffsetRequest?
    /// Mezcla de los canales (solo en memoria el solo; volumen y silencio también en `state.partMix`) «Tú · parte».
    private(set) var takeMixes: [UUID: StemMix] = [:]

    // Punch-in.
    var punchEnabled = false { didSet { if !punchEnabled { punchIn = nil; punchOut = nil } } }
    var punchIn: Double?
    var punchOut: Double?

    // Cámara.
    private(set) var cameraState: CameraState = .idle
    private(set) var cameraName: String?
    private(set) var videoFormat: VideoFormat?
    @ObservationIgnored private var capture: (any CameraCapture)?
    @ObservationIgnored private let relay = RecordFrameRelay()
    @ObservationIgnored private var cameraGeneration = 0

    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var recorded: (UUID, RecordedTake, Bool)?
    @ObservationIgnored private var pending: PendingTake?
    @ObservationIgnored private var loadedTrackIDs: Set<String> = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var closed = false

    var audio: AudioController { model.audio }

    init(session: StudySession, model: AppModel) {
        self.session = session
        self.model = model
        player = StudyPlayer(devices: CoreAudioDeviceProvider(), output: model.outputSelection)
        player.masterGainDB = model.profile.masterGainDB
        // Proyecto degradado (tomas con vídeo/parte pero sin índice `recording`): nunca se fabrican partes por defecto.
        let orphaned = session.project.hasOrphanedTakes
        let rebuilt = orphaned ? session.project.reconstructedRecording() : nil
        var s = rebuilt ?? session.project.recordingOrInitial()
        if s.parts.isEmpty { s.parts = [RecordingPart(name: "Guitarra", replaces: .rhythm)] }
        state = s
        takeMixes = Dictionary(s.partMix.map { ($0.partID, StemMix(kind: .guitar, gainDB: $0.gainDB, muted: $0.muted)) },
                               uniquingKeysWith: { _, b in b })
        if orphaned && rebuilt == nil {
            savesBlocked = true
            messages = ["Este proyecto tiene tomas en disco sin índice; no se ha modificado. Restaura `project.json` desde la copia `.bak`."]
        } else if orphaned || session.project.recording == nil {
            scheduleSave()
        }
        activePartID = s.parts.first?.id
        startSectionID = defaultStartSection(for: s.parts.first)
    }

    // MARK: Ciclo de vida

    func open() {
        closed = false
        audio.bind(player: player, study: session)
        audio.metersVisible = true
        loadTracks()
        reloadTakeTracks()
        Task { await startCamera() }
    }

    func close() {
        closed = true
        runTask?.cancel()
        stopCamera()
        audio.takeSink = nil
        audio.metersVisible = false
        audio.unbind()
        player.pause()
        Task { await flush() }
    }

    // MARK: Datos del tema

    var timing: BarTiming { BarTiming(session.beats) }
    var duration: Double { player.duration > 0 ? player.duration : session.project.song.duration }
    var sections: [Store.Section] { session.project.sections }
    var activePart: RecordingPart? { activePartID.flatMap { state.part($0) } }
    var guitarRoles: [GuitarRole] {
        let r = session.project.guitars.map(\.role)
        return r.isEmpty ? [.rhythm] : r
    }

    func take(_ id: UUID) -> Take? { session.project.takes.first { $0.id == id } }
    func takes(of part: RecordingPart) -> [Take] { part.takeIDs.compactMap { take($0) } }
    var selectedTake: Take? { selectedTakeID.flatMap { take($0) } }

    /// Número de la toma que se grabaría ahora en la parte activa.
    var nextTakeNumber: Int { (activePart?.takeIDs.count ?? 0) + 1 }

    func status(of p: RecordingPart) -> PartStatus {
        if p.id == activePartID, phase != .idle, phase != .adjusting { return .recording }
        return p.bestTakeID != nil ? .done : .pending
    }

    func guitarName(_ role: GuitarRole) -> String { session.guitarName(role) }

    // MARK: Partes

    func selectPart(_ id: UUID) {
        guard phase == .idle, id != activePartID, state.part(id) != nil else { return }
        activePartID = id
        selectedTakeID = nil
        punchEnabled = false
        startSectionID = defaultStartSection(for: state.part(id))
        applyAllMixes()
        reloadTakeTracks()
    }

    func addPart(name: String, replaces: GuitarRole?) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        let p = RecordingPart(name: n, replaces: replaces)
        state.parts.append(p)
        scheduleSave()
        selectPart(p.id)
    }

    /// Mini-spec Fase 6, «Grabar una toma»: por defecto el principio; en una parte solista, el primer solo.
    private func defaultStartSection(for part: RecordingPart?) -> UUID? {
        if let id = state.startSectionID, sections.contains(where: { $0.id == id }) { return id }
        guard part?.isLead == true else { return nil }
        return sections.first(where: \.isSolo)?.id
    }

    func setStartSection(_ id: UUID?) {
        startSectionID = id
        state.startSectionID = id
        scheduleSave()
    }

    var startTime: Double { sections.first { $0.id == startSectionID }?.start ?? 0 }

    /// Instante del tema (s) en que para sola una toma nueva: con una sección en «Empezar en», su final más el margen
    /// (tope: el final del tema). nil con «Principio» (sigue hasta el final del tema o hasta que se pare) y en el
    /// punch-in, que tiene su propia regla (salida + 0,5 s).
    var plannedStop: Double? {
        guard !punchEnabled, let s = sections.first(where: { $0.id == startSectionID }) else { return nil }
        return timing.sectionStop(sectionEnd: s.end, bars: state.preRollBars, duration: duration)
    }

    func setCountIn(_ on: Bool) { state.countIn = on; scheduleSave() }
    func setPreRoll(_ bars: Int) { state.preRollBars = bars; scheduleSave() }

    // MARK: Mezclador de Grabar

    func mix(for kind: StemKind) -> StemMix {
        state.mix.first { $0.kind == kind && $0.guitarRole == nil } ?? StemMix(kind: kind)
    }

    func mix(forGuitar role: GuitarRole) -> StemMix {
        state.mix.first { $0.guitarRole == role } ?? StemMix(kind: .guitar, guitarRole: role)
    }

    private func update(where match: (StemMix) -> Bool, default base: StemMix, _ change: (inout StemMix) -> Void) {
        var m = state.mix.first(where: match) ?? base
        change(&m)
        m.gainDB = min(max(m.gainDB, BackingController.faderRange.lowerBound), BackingController.faderRange.upperBound)
        if let i = state.mix.firstIndex(where: match) { state.mix[i] = m } else { state.mix.append(m) }
        scheduleSave()
    }

    func updateMix(_ kind: StemKind, _ change: (inout StemMix) -> Void) {
        update(where: { $0.kind == kind && $0.guitarRole == nil }, default: StemMix(kind: kind), change)
        apply(mix(for: kind), to: kind.rawValue)
    }

    func updateMix(guitar role: GuitarRole, _ change: (inout StemMix) -> Void) {
        update(where: { $0.guitarRole == role }, default: StemMix(kind: .guitar, guitarRole: role), change)
        apply(mix(forGuitar: role), to: role.trackID)
    }

    func setMaster(_ dB: Double) {
        let g = min(max(dB, BackingController.faderRange.lowerBound), BackingController.faderRange.upperBound)
        player.masterGainDB = g
        model.setMasterGain(g)
    }

    /// Pista del backing que se silencia (y fuerza) al grabar la parte activa: la guitarra que sustituye.
    var forcedMutedTrackID: String? {
        guard let id = activePartID, let role = state.mutedGuitar(whileRecording: id) else { return nil }
        if session.usesSeparatedGuitars { return session.guitarTracks.contains { $0.role == role } ? role.trackID : nil }
        return session.audibleStems.contains(.guitar) ? StemKind.guitar.rawValue : nil
    }

    var anySolo: Bool { state.mix.contains { $0.solo } }

    func isForcedMuted(_ id: String) -> Bool { id == forcedMutedTrackID }

    private func apply(_ m: StemMix, to id: String) {
        guard loadedTrackIDs.contains(id) else { return }
        let forced = isForcedMuted(id)
        player.setGain(id, dB: m.gainDB)
        player.setMute(id, forced || m.muted)
        player.setSolo(id, forced ? false : m.solo)
    }

    private func applyAllMixes() {
        for kind in session.mixerStems { apply(mix(for: kind), to: kind.rawValue) }
        for g in session.guitarTracks { apply(mix(forGuitar: g.role), to: g.role.trackID) }
    }

    /// Carga los stems y pistas de guitarra como Backing (con pistas separadas no se suma `guitar.wav`).
    func loadTracks() {
        let layout = session.layout
        let guitarTracks = session.guitarTracks.map { Track(id: $0.role.trackID, url: layout.guitarURL($0.role)) }
        let tracks = (session.mixerStems.map { Track(id: $0.rawValue, url: layout.stemURL($0)) } + guitarTracks)
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
        guard !tracks.isEmpty else { loadError = nil; return }
        do {
            try player.load(tracks: tracks)
            loadedTrackIDs = Set(tracks.map(\.id))
            loadError = nil
        } catch {
            loadError = "No se pudieron cargar los stems (\(error))."
            return
        }
        audio.refreshHosting()
        applyAllMixes()
        player.rate = 1
        player.pitchCents = 0
        player.loop = nil
        player.metronome = Metronome(clicks: [], isEnabled: false, gainDB: 0)
    }

    // MARK: Tus tomas anteriores

    static func takeTrackID(_ partID: UUID) -> String { "take-\(partID.uuidString)" }

    /// Canales «Tú · parte» de la mezcla: la mejor toma de cada otra parte.
    var backingTakeChannels: [BackingTake] {
        guard let id = activePartID else { return [] }
        return state.backingTakes(whileRecording: id).filter { bt in
            take(bt.takeID).map { $0.processedFile != nil && $0.songStart != nil } ?? false
        }
    }

    func takeMix(_ partID: UUID) -> StemMix { takeMixes[partID] ?? StemMix(kind: .guitar) }

    func updateTakeMix(_ partID: UUID, _ change: (inout StemMix) -> Void) {
        var m = takeMix(partID)
        change(&m)
        m.gainDB = min(max(m.gainDB, BackingController.faderRange.lowerBound), BackingController.faderRange.upperBound)
        takeMixes[partID] = m
        let stored = PartMix(partID: partID, gainDB: m.gainDB, muted: m.muted)
        if let i = state.partMix.firstIndex(where: { $0.partID == partID }) { state.partMix[i] = stored } else { state.partMix.append(stored) }
        scheduleSave()
        let id = Self.takeTrackID(partID)
        player.setGain(id, dB: m.gainDB)
        player.setMute(id, m.muted)
        player.setSolo(id, m.solo)
    }

    /// Carga en el reproductor las mejores tomas de las otras partes (y, en un punch, la toma vieja con
    /// `silencedFrom` en la entrada).
    func reloadTakeTracks(punch: (take: Take, from: Double)? = nil) {
        var tracks: [TakeTrack] = []
        for bt in backingTakeChannels {
            guard let t = take(bt.takeID), let rel = t.processedFile, let start = t.songStart else { continue }
            let m = takeMix(bt.partID)
            tracks.append(TakeTrack(id: Self.takeTrackID(bt.partID), url: session.layout.url(relative: rel), songStart: start,
                                    gainDB: m.gainDB, muted: m.muted, solo: m.solo))
        }
        if let (t, from) = punch, let rel = t.processedFile, let start = t.songStart {
            tracks.append(TakeTrack(id: Self.punchBaseTrackID, url: session.layout.url(relative: rel), songStart: start,
                                    silencedFrom: from))
        }
        do { try player.setTakes(tracks) } catch { loadError = "No se pudieron cargar tus tomas anteriores (\(error))." }
    }

    // MARK: Cámara

    var cameraLabel: String? {
        guard let f = videoFormat else { return nil }
        return "\(CameraChoices.label(VideoResolution(width: f.width, height: f.height))) · \(CameraChoices.label(fps: f.fps))"
    }

    /// Desfase por defecto de la cámara en uso (s); nil sin cámara.
    var defaultOffset: Double? {
        guard let id = videoFormat?.cameraID ?? cameraID else { return nil }
        return (model.profile.video ?? VideoSettings()).defaultOffset(for: id)
    }

    @ObservationIgnored private var cameraID: String?

    /// Giro de la cámara en uso (grados en sentido horario; 0 sin cámara). Observable a través de `model.profile`.
    var cameraRotation: Int {
        guard let id = videoFormat?.cameraID ?? cameraID else { return 0 }
        return (model.profile.video ?? VideoSettings()).defaultRotation(for: id)
    }

    /// «Rotar» en Grabar: 90° más en sentido horario, guardado en la cámara activa (lo heredan sus tomas nuevas).
    func rotateCamera() {
        guard let id = videoFormat?.cameraID ?? cameraID else { return }
        var v = model.profile.video ?? VideoSettings()
        v.setDefaultRotation(v.defaultRotation(for: id) + 90, for: id)
        model.profile.video = v
        model.saveProfile()
    }

    func startCamera() async {
        stopCamera()
        cameraGeneration += 1
        let mine = cameraGeneration
        let video = model.profile.video ?? VideoSettings()
        let provider = model.cameraProvider
        let device: CameraDevice?
        if let uid = video.cameraUID { device = provider.camera(id: uid) } else { device = provider.defaultCamera() }
        guard let device else {
            cameraState = .none(video.cameraUID == nil ? "No hay ninguna cámara conectada." : "La cámara elegida en Ajustes no está conectada.")
            return
        }
        cameraName = device.name
        cameraID = device.id
        let request = CameraRequest(width: video.resolution.width, height: video.resolution.height, fps: video.fps)
        let relay = relay
        if provider is SimulatedCameraProvider {
            let cam = SimulatedCameraCapture(camera: device, config: .init(pixels: true), automatic: true)
            do {
                videoFormat = try cam.start(request) { relay.handle($0) }
                capture = cam
                cameraState = .simulated
            } catch { cameraState = .failed("No se pudo abrir la cámara (\(error)).") }
            return
        }
        guard await AVCameraProvider.ensureAccess() else {
            if mine == cameraGeneration { cameraState = .denied }
            return
        }
        guard mine == cameraGeneration else { return }
        let result = await Task.detached { () -> Result<(AVCameraCapture, VideoFormat), Error> in
            do {
                let c = try AVCameraCapture(cameraID: device.id)
                let f = try c.start(request) { relay.handle($0) }
                return .success((c, f))
            } catch { return .failure(error) }
        }.value
        switch result {
        case .success(let (c, f)):
            if mine == cameraGeneration, !closed {
                capture = c
                videoFormat = f
                cameraState = .live(c.session)
            } else {
                Task.detached { c.stop() }
            }
        case .failure(let e):
            if mine == cameraGeneration { cameraState = .failed("No se pudo abrir la cámara (\(e)).") }
        }
    }

    func stopCamera() {
        cameraGeneration += 1
        let c = capture
        capture = nil
        relay.set(nil)
        if let c { Task.detached { c.stop() } }
        cameraState = .idle
        videoFormat = nil
    }

    /// Cada pocos segundos (sin tomas en curso): si la cámara se desconecta o aparece la elegida, se reacopla.
    func pollCamera() {
        guard phase == .idle, !closed else { return }
        let video = model.profile.video ?? VideoSettings()
        let provider = model.cameraProvider
        let present: Bool
        if let uid = video.cameraUID { present = provider.camera(id: uid) != nil } else { present = provider.defaultCamera() != nil }
        switch cameraState {
        case .idle, .denied: break
        case .none: if present { Task { await startCamera() } }
        default: if !present { stopCamera(); cameraState = .none("Se desconectó la cámara: se grabará solo el audio.") }
        }
    }

    // MARK: Grabar

    /// Motivo por el que no se puede grabar ahora (reglas de la Fase 3), o nil.
    var blockReason: String? {
        guard phase == .idle else { return nil }
        if let b = audio.recordBlock(playbackRate: 1, loopActive: false) { return b.message }
        if activePart == nil { return "Elige una parte." }
        if punchEnabled {
            if selectedTake == nil { return "Elige la toma sobre la que hacer el punch-in." }
            if punchPlan() == nil { return "Marca la entrada y la salida del punch-in en la línea de tiempo." }
        }
        return nil
    }

    var isBusy: Bool { phase != .idle }

    func startTake() {
        guard phase == .idle, blockReason == nil, let part = activePart else { return }
        let layout = session.layout
        let plan: TakePlan
        if punchEnabled {
            guard let p = punchPlan() else { return }
            plan = p
        } else {
            let id = UUID()
            plan = TakePlan(takeID: id, partID: part.id, punch: nil,
                            playFrom: timing.preRollStart(for: startTime, bars: state.preRollBars), stopAt: plannedStop,
                            audioURL: layout.processedURL(takeId: id), videoURL: layout.videoURL(takeId: id))
        }
        stopRequested = false
        messages = []
        phase = state.countIn ? .counting(1) : .recording
        runTask = Task { await run(plan) }
    }

    /// Parar (o cancelar la cuenta).
    func stopTake() {
        switch phase {
        case .counting: runTask?.cancel()
        case .recording: stopRequested = true
        default: break
        }
    }

    func punchPlan() -> TakePlan? {
        guard punchEnabled, let t = selectedTake, t.processedFile != nil, t.songStart != nil,
              let pin = punchIn, let pout = punchOut, pout > pin, let partID = t.partID ?? activePartID else { return nil }
        let n = (t.punches?.count ?? 0) + 1
        let dir = session.layout.punchDirectory(takeId: t.id, n: n)
        return TakePlan(takeID: t.id, partID: partID, punch: .init(n: n, start: pin, end: pout),
                        playFrom: timing.preRollStart(for: pin, bars: state.preRollBars),
                        stopAt: pout + Self.punchStopAfterSeconds,
                        audioURL: dir.appendingPathComponent("processed.wav"), videoURL: dir.appendingPathComponent("video.mov"))
    }

    private func run(_ plan: TakePlan) async {
        var writer: VideoTakeWriter?
        var recorder: VideoTakeRecorder?
        let fm = FileManager.default
        let newTake = plan.punch == nil
        do {
            guard let audioSession = audio.session else { throw RecordFailure(message: "El dispositivo no está abierto.") }
            try fm.createDirectory(at: plan.audioURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            player.pause()
            if let p = plan.punch, let t = take(plan.takeID) { reloadTakeTracks(punch: (t, p.start)) } else { reloadTakeTracks() }
            player.seek(to: plan.playFrom)
            if state.countIn { try await countIn() }
            if capture != nil, let fmt = videoFormat {
                let w = try VideoTakeWriter(url: plan.videoURL, format: fmt, realTime: true)
                writer = w
                recorder = VideoTakeRecorder(sink: w, sampleRate: audioSession.sampleRate, nominalFPS: fmt.fps)
            }
            let feeder = recorder.map { RecordMapFeeder(session: audioSession, recorder: $0) }
            recorded = nil
            audio.takeSink = { [weak self] id, t, cut in self?.recorded = (id, t, cut) }
            try player.play()
            if let feeder {
                // El ancla aparece unos ms después de `play`: hasta entonces los fotogramas se descartan.
                for _ in 0..<400 {
                    if feeder.feed() { break }
                    try await Task.sleep(for: .milliseconds(5))
                }
            }
            relay.set(recorder)
            phase = .recording
            audio.startRecording(playbackRate: 1, loopActive: false, takeID: plan.takeID, url: plan.audioURL)
            guard audio.isRecording else {
                throw RecordFailure(message: audio.takeNotices.first ?? "No se pudo empezar a grabar.")
            }
            while audio.isRecording {
                feeder?.feed()
                try await Task.sleep(for: .milliseconds(20))
                if stopRequested { break }
                let now = player.currentTime
                if !player.isPlaying || now >= player.duration - 0.03 { break }
                if let stopAt = plan.stopAt, now >= stopAt { break }
            }
            phase = .finishing
            if audio.isRecording { audio.stopRecording() }
            guard let (_, rec, cut) = recorded else {
                throw RecordFailure(message: audio.takeNotices.first ?? "No se pudo guardar la toma.")
            }
            if cut { messages.append("La toma se detuvo y se guardó lo grabado.") }
            // Cola de vídeo: los fotogramas llegan con retraso; se sigue ~0,5 s o hasta uno posterior al fin.
            let endSong = rec.songStart + Double(rec.frameCount) / rec.sampleRate
            let t0 = ContinuousClock.now
            while true {
                feeder?.feed()
                let elapsed = (ContinuousClock.now - t0) / .seconds(1)
                let last = recorder?.frames.last?.songTime ?? .infinity
                if elapsed >= Self.videoTailMaxSeconds || (elapsed >= Self.videoTailSeconds && last >= endSong) { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            relay.set(nil)
            let summary = try await writer?.finish()
            var format: VideoFormat?
            if let s = summary, s.framesWritten > 0 { format = s.format } else if writer != nil {
                try? fm.removeItem(at: plan.videoURL)
                messages.append("No llegaron fotogramas de la cámara: la toma es solo de audio.")
            }
            audio.takeSink = nil
            if let p = plan.punch {
                try await commitPunch(plan, p, rec, format)
                phase = .idle
            } else {
                finishNewTake(plan, rec, format)
            }
        } catch {
            relay.set(nil)
            writer?.cancel()
            audio.takeSink = nil
            if audio.isRecording { audio.stopRecording() }
            player.pause()
            if newTake { try? fm.removeItem(at: session.layout.takeDirectory(takeId: plan.takeID)) }
            else if let p = plan.punch { try? fm.removeItem(at: session.layout.punchDirectory(takeId: plan.takeID, n: p.n)) }
            if !(error is CancellationError) {
                messages.append((error as? RecordFailure)?.message ?? "No se pudo grabar la toma (\(error)).")
            }
            phase = .idle
        }
    }

    /// Cuenta de 1 compás con clics del metrónomo (mini-spec Fase 6, «Grabar una toma»): un reproductor aparte con
    /// los clics generados, sin tocar el backing.
    private func countIn() async throws {
        let t = timing
        let file = try Self.makeCountInFile(beats: t.beatsPerBar, beatSeconds: t.beatSeconds)
        defer { try? FileManager.default.removeItem(at: file) }
        let p = StudyPlayer(devices: CoreAudioDeviceProvider(), output: model.outputSelection)
        try p.load(tracks: [Track(id: "countin", url: file)])
        try p.play()
        defer { p.pause() }
        let t0 = ContinuousClock.now
        for k in 0..<t.beatsPerBar {
            phase = .counting(k + 1)
            try await Task.sleep(until: t0 + .seconds(Double(k + 1) * t.beatSeconds), clock: .continuous)
        }
    }

    static func makeCountInFile(beats: Int, beatSeconds: Double, sampleRate: Double = 48_000) throws -> URL {
        let frames = Int((Double(beats) * beatSeconds + 0.1) * sampleRate)
        var x = [Float](repeating: 0, count: frames)
        let n = Int(0.04 * sampleRate)
        for k in 0..<beats {
            let at = Int(Double(k) * beatSeconds * sampleRate)
            let hz = k == 0 ? countAccentHz : countHz
            for i in 0..<n where at + i < frames {
                let env = Float(exp(-Double(i) / (0.008 * sampleRate)))
                x[at + i] = 0.6 * env * Float(sin(2 * Double.pi * hz * Double(i) / sampleRate))
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("toneforge-countin-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames))!
        buf.frameLength = AVAudioFrameCount(frames)
        for c in 0..<2 { x.withUnsafeBufferPointer { buf.floatChannelData![c].update(from: $0.baseAddress!, count: frames) } }
        try file.write(from: buf)
        return url
    }

    // MARK: Toma nueva: ajustar desfase y guardar

    private func finishNewTake(_ plan: TakePlan, _ rec: RecordedTake, _ format: VideoFormat?) {
        pending = PendingTake(takeID: plan.takeID, partID: plan.partID, recorded: rec, format: format)
        guard let format else {
            savePending(offset: 0, makeDefault: false)
            return
        }
        phase = .adjusting
        let offset = (model.profile.video ?? VideoSettings()).defaultOffset(for: format.cameraID)
        offsetRequest = OffsetRequest(takeID: plan.takeID, isNew: true, audioURL: plan.audioURL, songStart: rec.songStart,
                                      videoURL: plan.videoURL, punches: [], fps: format.fps, cameraID: format.cameraID,
                                      cameraName: format.cameraName, initialOffset: offset,
                                      rotation: (model.profile.video ?? VideoSettings()).defaultRotation(for: format.cameraID))
    }

    /// «Guardar toma» / «Guardar» de la hoja de desfase.
    func finishOffset(save: Bool, offset: Double, makeDefault: Bool) {
        guard let req = offsetRequest else { return }
        offsetRequest = nil
        if req.isNew {
            if save { savePending(offset: offset, makeDefault: makeDefault) } else { discardPending() }
        } else if save {
            setOffset(takeID: req.takeID, offset: offset, camera: (req.cameraID, makeDefault))
        }
    }

    private func savePending(offset: Double, makeDefault: Bool) {
        guard let p = pending, let audioSettings = model.profile.audio else { discardPending(); return }
        pending = nil
        var t = AudioBridge.take(p.recorded, id: p.takeID, audio: audioSettings)
        t.partID = p.partID
        if let f = p.format {
            t.videoFile = ProjectLayout.videoRelativePath(takeId: p.takeID)
            t.videoOffset = offset
            t.videoFormat = TakeVideoFormat(cameraUID: f.cameraID, cameraName: f.cameraName, width: f.width, height: f.height, fps: f.fps)
            // La toma nueva hereda el giro de su cámara (nil = 0°: no se escribe sin giro).
            let rotation = (model.profile.video ?? VideoSettings()).defaultRotation(for: f.cameraID)
            t.videoRotation = rotation == 0 ? nil : rotation
            if makeDefault { setDefaultOffset(offset, camera: f.cameraID) }
        }
        session.saveTakes([t])
        if let i = state.parts.firstIndex(where: { $0.id == p.partID }) { state.parts[i].addTake(p.takeID) }
        selectedTakeID = p.takeID
        scheduleSave()
        reloadTakeTracks()
        phase = .idle
    }

    private func discardPending() {
        if let p = pending { try? FileManager.default.removeItem(at: session.layout.takeDirectory(takeId: p.takeID)) }
        pending = nil
        phase = .idle
    }

    private func setDefaultOffset(_ seconds: Double, camera: String) {
        var v = model.profile.video ?? VideoSettings()
        v.setDefaultOffset(seconds, for: camera)
        model.profile.video = v
        model.saveProfile()
    }

    /// Cambia el desfase de una toma ya guardada (y, si se pide, el de su cámara por defecto).
    func setOffset(takeID: UUID, offset: Double, camera: (id: String, makeDefault: Bool)?) {
        guard var t = take(takeID) else { return }
        t.videoOffset = offset
        session.saveTakes([t])
        if let camera, camera.makeDefault { setDefaultOffset(offset, camera: camera.id) }
    }

    /// «Ajustar desfase» desde el menú de toma.
    func adjustOffset(takeID: UUID) {
        guard phase == .idle, let t = take(takeID), let rel = t.videoFile, let f = t.videoFormat, let start = t.songStart,
              let audioRel = t.processedFile else { return }
        let layout = session.layout
        let punches = (t.punches ?? []).map {
            PreviewPunch(start: $0.start, end: $0.end, videoURL: $0.videoFile.map { layout.url(relative: $0) },
                         videoOffset: $0.videoOffset ?? t.videoOffset ?? 0)
        }
        offsetRequest = OffsetRequest(takeID: takeID, isNew: false, audioURL: layout.url(relative: audioRel), songStart: start,
                                      videoURL: layout.url(relative: rel), punches: punches, fps: f.fps, cameraID: f.cameraUID,
                                      cameraName: f.cameraName, initialOffset: t.videoOffset ?? 0, rotation: t.rotationDegrees)
    }

    // MARK: Mejor toma, borrar, seleccionar

    func selectTake(_ id: UUID) {
        guard phase == .idle else { return }
        if let part = state.part(containingTake: id), part.id != activePartID { selectPart(part.id) }
        selectedTakeID = id
    }

    /// Mini-spec Fase 7b, punto 9: el visor de tomas no se abre grabando y, al abrirlo, se para el transporte de Grabar.
    func prepareToViewTake() -> Bool {
        guard phase == .idle else { return false }
        player.pause()
        return true
    }

    func markBest(_ takeID: UUID) {
        guard let i = state.parts.firstIndex(where: { $0.takeIDs.contains(takeID) }) else { return }
        state.parts[i].setBest(takeID)
        scheduleSave()
        reloadTakeTracks()
    }

    func startPunch(on takeID: UUID) {
        guard phase == .idle else { return }
        selectTake(takeID)
        punchEnabled = true
    }

    func deleteTake(_ takeID: UUID) {
        guard phase == .idle else { return }
        Task {
            await flush()
            guard let library = model.library else { return }
            do {
                try await library.deleteTake(projectID: session.projectID, takeID: takeID)
            } catch {
                messages = ["No se pudo borrar la toma (\(error))."]
                return
            }
            session.reload()
            state.removeTake(takeID)
            if selectedTakeID == takeID { selectedTakeID = nil; punchEnabled = false }
            reloadTakeTracks()
        }
    }

    // MARK: Punch-in

    private func commitPunch(_ plan: TakePlan, _ p: TakePlan.Punch, _ rec: RecordedTake, _ format: VideoFormat?) async throws {
        guard var t = take(plan.takeID), let start = t.songStart else { throw RecordFailure(message: "No se encontró la toma del punch.") }
        let layout = session.layout, fm = FileManager.default
        let processed = layout.processedURL(takeId: t.id)
        // La primera vez, la original se guarda en `base/processed.wav`.
        if t.baseProcessedFile == nil {
            let base = layout.baseProcessedURL(takeId: t.id)
            try fm.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: base)
            try fm.copyItem(at: processed, to: base)
            t.baseProcessedFile = ProjectLayout.baseProcessedRelativePath(takeId: t.id)
        }
        // Aplanado: la toma actual (con los punches anteriores ya dentro) más este; el último manda en su tramo.
        // Se aplana a la frecuencia del punch (la de la sesión, que es la del proyecto). Una original grabada a
        // otra frecuencia se remuestrea al leerla (su copia en `base/` queda intacta) y la toma pasa a esa
        // frecuencia; `songStart` va en segundos y las latencias en muestras de `calibrationKey`, no cambian.
        let file = PunchFile(start: p.start, end: p.end, url: plan.audioURL, songStart: rec.songStart)
        let rate = rec.sampleRate
        try await Task.detached {
            try PunchFlattener.flattenFiles(base: processed, baseSongStart: start, punches: [file], to: processed,
                                            sampleRate: rate)
        }.value
        t.sampleRate = rate
        let rel = ProjectLayout.punchRelativeDirectory(takeId: t.id, n: p.n)
        let offset = format.map { (model.profile.video ?? VideoSettings()).defaultOffset(for: $0.cameraID) }
        var punches = t.punches ?? []
        punches.append(TakePunch(start: p.start, end: p.end, processedFile: rel + "/processed.wav",
                                 videoFile: format == nil ? nil : rel + "/video.mov", videoOffset: offset))
        t.punches = punches
        session.saveTakes([t])
        punchIn = nil
        punchOut = nil
        reloadTakeTracks()
    }

    // MARK: Guardado

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(StudySession.saveDelay))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    func flush() async {
        saveTask?.cancel()
        saveTask = nil
        guard !savesBlocked else { return }
        try? await model.library?.saveRecording(id: session.projectID, state)
    }
}
