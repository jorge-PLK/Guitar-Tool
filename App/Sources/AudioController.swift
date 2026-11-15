import AudioKit
import Foundation
import Observation
import Store

/// Resultado de una calibración para la hoja de Ajustes · Audio (mini-spec Fase 3, «Calibración de latencia»).
struct CalibrationSummary: Equatable {
    var latencyMS: Double
    var latencySamples: Double
    var spreadMS: Double
    var spreadSamples: Double
    /// Retardo del rig en la calibración, si se encontró canal de referencia interno.
    var rigDelayMS: Double?
    /// Tomas sin calibrar del proyecto abierto que se han vuelto a desplazar.
    var correctedTakes: Int
}

enum CalibrationOutcome: Equatable {
    case success(CalibrationSummary)
    case failure(LatencyFailure, spreadMS: Double)
    case error(String)
}

/// Audio con el dispositivo (mini-spec Fase 3): crea y abre la `AudioSession` según `profile.audio`, aloja el
/// reproductor de Backing mientras está abierta, mide niveles, calibra y graba. La lógica pura (motivos de
/// bloqueo, claves, A/B) está en AudioKit (`RecordingGate`, `MixCompare`, `LatencyCalibrationKey`) y en
/// `AudioBridge`.
@MainActor @Observable
final class AudioController {
    /// Refresco de los medidores de entrada (Hz) (mini-spec Fase 3, «Ajustes · Audio»: ~15 Hz).
    static let meterRefreshHz = 15.0
    /// Suelo del medidor (dBFS): por debajo no se pinta nada.
    static let meterFloorDB = -60.0

    let devices: AudioDeviceList
    @ObservationIgnored private let provider: AudioDeviceProviding
    @ObservationIgnored var makeIO: AudioSession.IOFactory = AudioSession.coreAudio
    /// La app guarda aquí la calibración nueva en el perfil.
    @ObservationIgnored var onCalibrationSaved: ((LatencyCalibration) -> Void)?
    /// Una toma nueva o corregida del proyecto abierto (Backing la recarga).
    @ObservationIgnored var onTakesChanged: ((_ newTake: Bool) -> Void)?

    // Estado legible para la UI.
    private(set) var settings: AudioSettings?
    private(set) var workingRate = EquipmentProfile.defaultSampleRate
    private(set) var session: AudioSession?
    private(set) var sessionError: String?
    private(set) var hostError: String?
    /// Por qué se cerró la sesión la última vez (desconexión, cambio de frecuencia); se limpia al reabrir.
    private(set) var interruptionNote: String?
    /// Nivel 0...1 por canal de entrada (índice 0 = canal 1); nil sin sesión.
    private(set) var inputLevels: [Float]?
    private(set) var calibrationPhase: CalibrationPhase = .idle
    private(set) var isRecording = false
    /// Avisos de la última toma (retardo del rig no fiable, cortada). El de «Sin calibrar» va aparte, antes de grabar.
    private(set) var takeNotices: [String] = []

    enum CalibrationPhase: Equatable {
        case idle
        case running(Double)
        case finished(CalibrationOutcome)
    }

    var metersVisible = false {
        didSet {
            guard metersVisible != oldValue else { return }
            reconcile(force: false)
            restartMeters()
        }
    }

    @ObservationIgnored private var currentSetup: AudioSetup?
    @ObservationIgnored private var requestedRates: Set<String> = []
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private weak var player: StudyPlayer?
    @ObservationIgnored private weak var study: StudySession?
    @ObservationIgnored private var recordingTakeID: UUID?
    @ObservationIgnored private var cutAt: Date?

    init(provider: AudioDeviceProviding, list: AudioDeviceList) {
        self.provider = provider
        devices = list
        list.onChange = { [weak self] in self?.devicesChanged() }
    }

    // MARK: Perfil y dispositivos

    /// Lo llama la app al cambiar el perfil; solo reabre si cambió algo de la sesión.
    func update(profile: EquipmentProfile) {
        let rateChanged = workingRate != profile.workingSampleRate
        let before = settings
        settings = profile.audio
        workingRate = profile.workingSampleRate
        if rateChanged || before?.inputDeviceUID != settings?.inputDeviceUID || before?.outputDeviceUID != settings?.outputDeviceUID {
            requestRates()
        }
        reconcile(force: false)
    }

    private func devicesChanged() {
        requestRates()
        reconcile(force: true)
    }

    private var inputDevice: AudioDevice? {
        settings?.inputDeviceUID.flatMap { uid in devices.inputs.first { $0.uid == uid } }
    }

    /// Salida elegida, o la de defecto del sistema si no hay ninguna elegida.
    private var outputDevice: AudioDevice? {
        if let uid = settings?.outputDeviceUID { return devices.outputs.first { $0.uid == uid } }
        return devices.systemDefault
    }

    /// Frecuencia ACTUAL de un dispositivo elegido que no está a la de trabajo (mini-spec Fase 3, «Frecuencia»).
    var mismatchedRate: Double? {
        for d in [inputDevice, outputDevice].compactMap({ $0 }) {
            if let n = d.nominalSampleRate, abs(n - workingRate) > 0.5 { return n }
        }
        return nil
    }

    /// Al elegir dispositivo (o cambiar la frecuencia de trabajo) se le pide la frecuencia; si no la acepta se
    /// ve en `mismatchedRate`.
    private func requestRates() {
        var changed = false
        for d in [inputDevice, outputDevice].compactMap({ $0 }) {
            guard let n = d.nominalSampleRate, abs(n - workingRate) > 0.5 else { continue }
            let key = "\(d.uid)@\(Int(workingRate))"
            guard requestedRates.insert(key).inserted else { continue }
            _ = provider.requestSampleRate(workingRate, deviceUID: d.uid)
            changed = true
        }
        if changed { devices.refresh(notify: false) }
    }

    var deviceState: RecordingGate.DeviceState {
        let a = settings
        return RecordingGate.DeviceState(
            hasInputDevice: a?.inputDeviceUID != nil, hasGuitarIn: a?.guitarIn != nil, validChannels: a?.isValid ?? true,
            inputConnected: inputDevice != nil, outputConnected: a?.outputDeviceUID == nil || outputDevice != nil,
            mismatchedRate: mismatchedRate, workingRate: workingRate, sessionError: sessionError)
    }

    /// Motivo para no calibrar (y para no usar el A/B en directo); nil si se puede.
    var deviceBlock: RecordBlock? {
        if calibrationIsRunning || isRecording { return .busy }
        if let b = RecordingGate.deviceBlock(deviceState) { return b }
        if session?.isOpen != true { return .sessionUnavailable(interruptionNote ?? "El dispositivo no está abierto.") }
        return nil
    }

    /// Motivo para no grabar ahora; nil si se puede.
    func recordBlock(playbackRate: Double, loopActive: Bool) -> RecordBlock? {
        var s = deviceState
        if s.sessionError == nil { s.sessionError = hostError }
        if let b = RecordingGate.recordBlock(s, playbackRate: playbackRate, loopActive: loopActive, busy: calibrationIsRunning) {
            return b
        }
        if session?.isOpen != true { return .sessionUnavailable(interruptionNote ?? "El dispositivo no está abierto.") }
        if player?.isHosted != true { return .sessionUnavailable(hostError ?? "El backing no está sonando por el dispositivo.") }
        return nil
    }

    /// Calibración válida guardada para la configuración actual (la clave no cambió).
    var calibrationValid: Bool { settings?.validLatency(sampleRate: workingRate) != nil }

    // MARK: Sesión

    private func desiredSetup() -> AudioSetup? {
        guard let a = settings, a.isValid, let setup = AudioBridge.setup(a, workingRate: workingRate) else { return nil }
        // Sin guitarra asignada la sesión solo sirve para los medidores: solo con Ajustes · Audio a la vista.
        guard !setup.guitarIn.isEmpty || metersVisible else { return nil }
        guard inputDevice != nil, outputDevice != nil || a.outputDeviceUID == nil, mismatchedRate == nil else { return nil }
        return setup
    }

    private func reconcile(force: Bool) {
        let desired = desiredSetup()
        if desired == currentSetup, !force || (session?.isOpen ?? false) == (desired != nil) {
            syncHosting()
            return
        }
        closeSession()
        currentSetup = desired
        if let desired { openSession(desired) }
        syncHosting()
    }

    private func openSession(_ setup: AudioSetup) {
        let s = AudioSession(setup: setup, makeIO: makeIO)
        s.setEventHandler { [weak self] e in Task { @MainActor in self?.handle(e, from: s) } }
        do {
            try s.open()
        } catch {
            sessionError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return
        }
        sessionError = nil
        interruptionNote = nil
        session = s
        if let saved = settings?.latency, let a = settings, let key = s.calibrationKey,
           let r = AudioBridge.restored(saved, audio: a, sessionKey: key, guitarIn: setup.guitarIn,
                                        inputChannels: s.format?.inputChannels ?? 2) {
            s.calibration = r
        }
        restartMeters()
    }

    private func closeSession() {
        if isRecording { finishRecordingBeforeClosing() }
        player?.detach()
        session?.setEventHandler(nil)
        session?.close()
        session = nil
        inputLevels = nil
        hostError = nil
    }

    /// Aloja el reproductor mientras la sesión está abierta con guitarra asignada; si no, vuelve a su salida normal.
    private func syncHosting() {
        guard let player else { return }
        if let s = session, s.isOpen, !s.setup.guitarIn.isEmpty {
            guard !player.isHosted else { return }
            do {
                try player.attach(to: s)
                hostError = nil
            } catch StudyPlayerError.sampleRateMismatch {
                hostError = "Este tema no está a la frecuencia de trabajo (\(Fmt.rate(workingRate))): no se puede grabar."
            } catch {
                hostError = "No se pudo usar el dispositivo para el backing (\(error))."
            }
        } else {
            if player.isHosted { player.detach() }
            hostError = nil
        }
    }

    private func handle(_ e: AudioSessionEvent, from s: AudioSession) {
        guard s === session else { return }
        switch e {
        case .recordingSaved(let t):
            finalize(t, cut: true)
        case .recordingFailed(let err):
            isRecording = false
            recordingTakeID = nil
            takeNotices = ["No se pudo guardar la toma: \(err.errorDescription ?? "\(err)")"]
        case .interrupted(let reason):
            // La toma, si la había, ya se guardó con `recordingSaved`: se dice por qué se cortó.
            if let at = cutAt, Date().timeIntervalSince(at) < 5 {
                takeNotices = takeNotices.filter { !$0.hasPrefix("La toma se detuvo") }
                    + ["\(AudioSessionError.interrupted(reason).errorDescription ?? "Se cortó el dispositivo") a mitad de la toma: se guardó lo grabado."]
            }
            interruptionNote = AudioSessionError.interrupted(reason).errorDescription
            devices.refresh(notify: false)
            closeSession()
            currentSetup = nil
            reconcile(force: true)
        }
    }

    // MARK: Reproductor y proyecto abierto

    func bind(player: StudyPlayer, study: StudySession) {
        self.player = player
        self.study = study
        takeNotices = []
        syncHosting()
    }

    func unbind() {
        if isRecording { finishRecordingBeforeClosing() }
        player?.detach()
        player = nil
        study = nil
        hostError = nil
        takeNotices = []
    }

    // MARK: Medidores

    private func restartMeters() {
        meterTask?.cancel()
        meterTask = nil
        guard metersVisible, session != nil else { inputLevels = nil; return }
        meterTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.sampleMeters()
                try? await Task.sleep(for: .seconds(1 / Self.meterRefreshHz))
            }
        }
    }

    private func sampleMeters() {
        guard let s = session, s.isOpen else { inputLevels = nil; return }
        inputLevels = s.inputLevels().map { Self.level(db: Double($0.rmsDB)) }
    }

    /// dBFS → 0...1 entre el suelo del medidor y 0 dBFS.
    static func level(db: Double) -> Float {
        Float(min(max((db - meterFloorDB) / -meterFloorDB, 0), 1))
    }

    // MARK: Calibración

    var calibrationIsRunning: Bool {
        if case .running = calibrationPhase { return true }
        return false
    }

    func dismissCalibration() {
        if !calibrationIsRunning { calibrationPhase = .idle }
    }

    /// Calibra (mini-spec Fase 3, «Calibración de latencia»). Devuelve cuando acaba; el estado va en `calibrationPhase`.
    func calibrate() async {
        guard !calibrationIsRunning, let s = session else { return }
        if let block = RecordingGate.deviceBlock(deviceState) {
            calibrationPhase = .finished(.error(block.message))
            return
        }
        player?.pause()
        calibrationPhase = .running(0)
        do {
            let r = try await s.calibrateLatency(progress: { p in
                Task { @MainActor [weak self] in
                    if self?.calibrationIsRunning == true { self?.calibrationPhase = .running(p) }
                }
            })
            calibrationPhase = .finished(await finishCalibration(r, session: s))
        } catch {
            calibrationPhase = .finished(.error((error as? LocalizedError)?.errorDescription ?? "\(error)"))
        }
    }

    private func finishCalibration(_ r: LatencyCalibrationResult, session s: AudioSession) async -> CalibrationOutcome {
        let fs = r.key.sampleRate
        let spreadMS = r.spreadSamples / fs * 1000
        if let failure = r.failure { return .failure(failure, spreadMS: spreadMS) }
        guard let a = settings else { return .error("No hay configuración de audio.") }
        onCalibrationSaved?(AudioBridge.calibration(r, audio: a))
        let corrected = await correctOpenProjectTakes(with: r)
        return .success(CalibrationSummary(latencyMS: r.latencySamples / fs * 1000, latencySamples: r.latencySamples,
                                           spreadMS: spreadMS, spreadSamples: r.spreadSamples,
                                           rigDelayMS: r.rigDelayAtCalibration.map { $0 / fs * 1000 },
                                           correctedTakes: corrected))
    }

    /// Vuelve a desplazar las tomas sin calibrar del proyecto abierto hechas con esta clave (mini-spec Fase 3,
    /// «Sin calibrar»).
    private func correctOpenProjectTakes(with r: LatencyCalibrationResult) async -> Int {
        guard let study else { return 0 }
        let folder = study.folder
        let candidates = study.project.takes.compactMap { t -> (Take, RecordedTake, URL)? in
            guard t.latencyCalibrated == false,
                  let (rec, url) = AudioBridge.recorded(t, folder: folder, resolvedOutputUID: r.key.outputUID) else { return nil }
            return (t, rec, url)
        }
        guard !candidates.isEmpty else { return 0 }
        let pairs = candidates.map { (take: $0.1, file: $0.2) }
        let shifted = await Task.detached { try? AudioSession.reshiftUncalibrated(pairs, with: r) }.value
        guard let shifted else { return 0 }
        let fixed = zip(candidates, shifted).compactMap { c, new in new.map { AudioBridge.applying($0, to: c.0) } }
        guard !fixed.isEmpty else { return 0 }
        study.saveTakes(fixed)
        onTakesChanged?(false)
        return fixed.count
    }

    // MARK: Grabar

    /// Empieza a grabar desde la posición actual con el backing sonando (mini-spec Fase 3, «Grabación»).
    func startRecording(playbackRate: Double, loopActive: Bool) {
        takeNotices = []
        guard !isRecording, let s = session, let player, let study else { return }
        if let b = recordBlock(playbackRate: playbackRate, loopActive: loopActive) {
            takeNotices = [b.message]
            return
        }
        let id = UUID()
        let url = study.layout.processedURL(takeId: id)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !player.isPlaying { try player.play() }
            try s.startRecording(to: url)
        } catch {
            player.pause()
            takeNotices = ["No se pudo empezar a grabar: \((error as? LocalizedError)?.errorDescription ?? "\(error)")"]
            return
        }
        recordingTakeID = id
        isRecording = true
    }

    func stopRecording() {
        guard isRecording, let s = session else { return }
        do {
            let t = try s.stopRecording()
            player?.pause()
            finalize(t, cut: false)
        } catch {
            player?.pause()
            isRecording = false
            recordingTakeID = nil
            takeNotices = ["No se pudo guardar la toma: \((error as? LocalizedError)?.errorDescription ?? "\(error)")"]
        }
    }

    private func finishRecordingBeforeClosing() {
        if let s = session, let t = try? s.stopRecording() {
            finalize(t, cut: true)
        } else {
            isRecording = false
            recordingTakeID = nil
        }
    }

    /// Añade la toma al proyecto (una sola vez por grabación) con todos sus campos.
    private func finalize(_ t: RecordedTake, cut: Bool) {
        guard let id = recordingTakeID, let study, let a = settings else { return }
        recordingTakeID = nil
        isRecording = false
        study.saveTakes([AudioBridge.take(t, id: id, audio: a)])
        var notices: [String] = []
        if cut {
            cutAt = Date()
            notices.append("La toma se detuvo y se guardó lo grabado.")
        }
        if t.rigDelayReliable == false {
            notices.append("No se pudo medir con fiabilidad el retardo del rig en esta toma (mucho delay o reverb): se usó el último valor bueno.")
        }
        takeNotices = notices
        onTakesChanged?(true)
    }

    // MARK: A/B

    /// Nivel en directo de tu guitarra (dBFS, RMS de los últimos 3 s); nil sin sesión o sin guitarra.
    func liveGuitarLevelDB() -> Double? {
        session?.guitarLevelDB(seconds: AudioSession.liveLevelSeconds)
    }
}
