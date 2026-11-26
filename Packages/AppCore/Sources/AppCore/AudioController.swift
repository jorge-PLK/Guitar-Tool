import AudioKit
import Foundation
import NativeAudioFile
import Store

// Copia adaptada y portátil de `App/Sources/AudioController.swift`, `AudioBridge.swift` y `AudioDeviceList` (Mac), sin AppKit ni
// Observation: el estado se avisa con cierres (`onStateChange`, `onLevels`, `onCalibration`, `onDevicesChanged`) que cablea
// `AudioMethods.swift`. W2-C del paso 8, ola 2.

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

/// Puente Store <-> AudioKit de la calibración y las tomas: los tipos tienen nombres distintos a propósito y aquí se convierten
/// campo a campo (copia de `AudioBridge` del Mac, con `AudioFileReader` en vez de `AVAudioFile`).
///
/// F2 (paso 8): la clave de Windows lleva modo WASAPI y contenedor (`wasapi`); en el Mac va nil y no cambia nada.
enum PortableAudioBridge {
    static func storeKey(_ k: LatencyCalibrationKey) -> CalibrationKey {
        CalibrationKey(inputUID: k.inputUID, outputUID: k.outputUID, sampleRate: k.sampleRate, bufferFrames: k.bufferFrames,
                       inputChannel: k.inputChannel, outputChannel: k.outputChannel,
                       wasapi: k.wasapi.map { CalibrationKey.WASAPIPath(mode: $0.mode.rawValue, inputEndpoint: $0.inputEndpoint,
                                                                        outputEndpoint: $0.outputEndpoint) })
    }

    /// Un modo desconocido deja la clave sin parte de Windows: no casa con ninguna sesión WASAPI (lo seguro).
    static func kitKey(_ k: CalibrationKey) -> LatencyCalibrationKey {
        LatencyCalibrationKey(inputUID: k.inputUID, outputUID: k.outputUID, sampleRate: k.sampleRate,
                              bufferFrames: k.bufferFrames, inputChannel: k.inputChannel, outputChannel: k.outputChannel,
                              wasapi: k.wasapi.flatMap { w in WASAPIShareMode(rawValue: w.mode).map {
                                  WASAPICalibrationPath(mode: $0, inputEndpoint: w.inputEndpoint, outputEndpoint: w.outputEndpoint)
                              } })
    }

    /// Configuración de la sesión; nil sin dispositivo de entrada. `wasapiMode` solo en Windows.
    static func setup(_ a: AudioSettings, workingRate: Double, wasapiMode: WASAPIShareMode? = nil) -> AudioSetup? {
        guard let input = a.inputDeviceUID else { return nil }
        return AudioSetup(inputDeviceUID: input, outputDeviceUID: a.outputDeviceUID ?? "", sampleRate: workingRate,
                          backingLeft: a.backingOut.left, backingRight: a.backingOut.right, guitarIn: a.guitarIn ?? [],
                          bufferFrames: a.bufferFrames, wasapiMode: wasapiMode)
    }

    /// Lo que se guarda en el perfil tras calibrar con éxito.
    static func calibration(_ r: LatencyCalibrationResult, audio: AudioSettings) -> LatencyCalibration {
        LatencyCalibration(latencySamples: r.latencySamples, spreadSamples: r.spreadSamples, date: r.date,
                           key: storeKey(r.key.inProfileTerms(outputDeviceUID: audio.outputDeviceUID)),
                           referenceIn: r.reference.map { ReferenceChannel(channel: $0.channel, latencySamples: $0.latencySamples) })
    }

    /// La calibración guardada, lista para la sesión, si su clave vale para ella (si no, nil: «Sin calibrar»).
    static func restored(_ saved: LatencyCalibration, audio: AudioSettings, sessionKey: LatencyCalibrationKey,
                         guitarIn: [Int], inputChannels: Int) -> LatencyCalibrationResult? {
        guard storeKey(sessionKey.inProfileTerms(outputDeviceUID: audio.outputDeviceUID)) == saved.key else { return nil }
        return .restored(key: sessionKey, date: saved.date, guitarIn: guitarIn, latencySamples: saved.latencySamples,
                         spreadSamples: saved.spreadSamples, inputChannels: inputChannels,
                         reference: saved.referenceIn.map { ReferenceInput(channel: $0.channel, latencySamples: $0.latencySamples) })
    }

    static func take(_ t: RecordedTake, id: UUID, audio: AudioSettings, createdAt: Date = Date()) -> Take {
        Take(id: id, processedFile: ProjectLayout.processedRelativePath(takeId: id), createdAt: createdAt,
             songStart: t.songStart, sampleRate: t.sampleRate, latencySamples: t.latencySamples,
             rigDelaySamples: t.rigDelaySamples, rigDelayReliable: t.rigDelayReliable, latencyCalibrated: t.latencyCalibrated,
             calibrationKey: storeKey(t.calibrationKey.inProfileTerms(outputDeviceUID: audio.outputDeviceUID)),
             clock: ClockMode(rawValue: t.clock.rawValue))
    }

    /// La toma guardada como la ve AudioKit para corregirla al calibrar; nil si no es una toma de esta fase o falta el fichero.
    static func recorded(_ take: Take, folder: URL, resolvedOutputUID: String,
                         resolvedOutputEndpoint: String? = nil) -> (take: RecordedTake, file: URL)? {
        guard let rel = take.processedFile, let songStart = take.songStart, let fs = take.sampleRate,
              let latency = take.latencySamples, let key = take.calibrationKey, let clock = take.clock else { return nil }
        let url = folder.appendingPathComponent(rel)
        guard let file = try? AudioFileReader(url: url) else { return nil }
        let r = RecordedTake(restoring: songStart, sampleRate: fs, frameCount: file.frameCount,
                             channelCount: file.channelCount, latencySamples: latency,
                             rigDelaySamples: take.rigDelaySamples, rigDelayReliable: take.rigDelayReliable,
                             latencyCalibrated: take.latencyCalibrated ?? false,
                             calibrationKey: kitKey(key).resolvingDefaultOutput(to: resolvedOutputUID,
                                                                                endpoint: resolvedOutputEndpoint),
                             clock: AudioIOClock(rawValue: clock.rawValue) ?? .single)
        return (r, url)
    }

    /// La toma de Store con lo que cambió al volver a desplazarla.
    static func applying(_ r: RecordedTake, to take: Take) -> Take {
        var t = take
        t.songStart = r.songStart
        t.latencySamples = r.latencySamples
        t.rigDelaySamples = r.rigDelaySamples
        t.rigDelayReliable = r.rigDelayReliable
        t.latencyCalibrated = r.latencyCalibrated
        return t
    }
}

/// Lista de dispositivos de los selectores; se relee cuando el proveedor avisa de un cambio (en Windows el proveedor sondea).
@MainActor
final class DeviceCatalog {
    private(set) var inputs: [AudioDevice] = []
    private(set) var outputs: [AudioDevice] = []
    private(set) var systemDefault: AudioDevice?
    /// Nombres vistos en esta sesión, para seguir nombrando un dispositivo elegido que ya no está conectado.
    private(set) var names: [String: String] = [:]
    private let provider: AudioDeviceProviding
    /// Lo llama `refresh()` tras cambiar la lista (el controlador de audio rehace la sesión).
    var onChange: (() -> Void)?

    init(provider: AudioDeviceProviding) {
        self.provider = provider
        refresh(notify: false)
        provider.setChangeHandler { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh(notify: Bool = true) {
        inputs = provider.inputDevices()
        outputs = provider.outputDevices()
        systemDefault = provider.defaultOutputDevice()
        for d in inputs + outputs { names[d.uid] = d.name }
        if notify { onChange?() }
    }
}

/// Opción de canales de un selector: etiqueta y valor.
struct ChannelChoice<Value: Hashable>: Hashable {
    var label: String
    var value: Value
}

extension ChannelPair: @retroactive Hashable {
    public func hash(into h: inout Hasher) { h.combine(left); h.combine(right) }
}

/// Combinaciones de canales ofrecidas (`AudioSettingsView.swift` del Mac); solo las que pasan `AudioSettings.validate()`.
enum ChannelChoices {
    /// Todos los canales caben en un dispositivo de `channels` canales.
    static func fits(_ g: [Int], channels: Int) -> Bool { g.allSatisfy { $0 <= channels } }

    static func backing(channels: Int, current: AudioSettings) -> [ChannelChoice<ChannelPair>] {
        // Salida de un canal: solo «Salida 1 · mono» (M-3d); el núcleo mezcla el backing a mono por ese canal.
        if channels == 1 { return [ChannelChoice(label: monoLabel, value: .mono)] }
        var pairs = stride(from: 1, to: max(channels, 2), by: 2).map { ChannelPair(left: $0, right: $0 + 1) }
        if !pairs.contains(current.backingOut), fits([current.backingOut.left, current.backingOut.right], channels: channels) {
            pairs.append(current.backingOut)
        }
        return pairs.filter { p in var a = current; a.backingOut = p; return a.isValid }
            .map { ChannelChoice(label: $0.isMono ? monoLabel : "Salidas \($0.left) y \($0.right) · estéreo", value: $0) }
    }

    static let monoLabel = "Salida 1 · mono"

    /// Sin «Sin asignar» (M-7): con dispositivo de entrada siempre hay un canal de guitarra asignado.
    static func guitar(channels: Int, current: AudioSettings) -> [ChannelChoice<[Int]>] {
        var options: [[Int]] = (1...max(channels, 1)).map { [$0] }
        options += stride(from: 1, to: channels, by: 2).map { [$0, $0 + 1] }
        if let g = current.guitarIn, !options.contains(g), fits(g, channels: channels) { options.append(g) }
        let valid = options.filter { g in var a = current; a.guitarIn = g; return a.isValid }
        return valid.map { ChannelChoice<[Int]>(label: $0.count == 1 ? "Entrada \($0[0])" : "Entradas \($0[0]) y \($0[1])", value: $0) }
    }

    /// Guitarra efectiva (M-7): con dispositivo de entrada nunca nil. Lo guardado si cabe en `inputChannels` (nil = dispositivo
    /// ausente, no se puede comprobar); si no, la primera opción válida («Entrada 1»). Sin dispositivo de entrada, tal cual.
    static func resolvedGuitar(_ a: AudioSettings, inputChannels: Int?) -> [Int]? {
        guard a.inputDeviceUID != nil else { return a.guitarIn }
        if let g = a.guitarIn, inputChannels.map({ fits(g, channels: $0) }) ?? true { return g }
        guard let n = inputChannels, n > 0 else { return a.guitarIn ?? [1] }
        var base = a
        base.guitarIn = nil
        return guitar(channels: n, current: base).first?.value ?? [1]
    }
}

/// Audio con el dispositivo (mini-spec Fase 3): crea y abre la `AudioSession` según `profile.audio`, aloja el reproductor de
/// estudio mientras está abierta, mide niveles de entrada, calibra y entrega las tomas. Dueño del perfil de audio (lee y guarda
/// `profile.json` por `ProfileStore`; sin almacén, solo en memoria).
@MainActor
final class AudioController {
    /// Refresco máximo de los medidores de entrada (Hz) (contrato `audio.levels`: <= 30 Hz).
    static let meterRefreshHz = 30.0
    /// Suelo del medidor (dBFS): por debajo no se pinta nada (mini-spec Fase 3, «Ajustes · Audio»).
    static let meterFloorDB = -60.0

    let devices: DeviceCatalog
    private let provider: AudioDeviceProviding
    private let store: ProfileStore?
    /// Fábrica de la E/S de la sesión: del sistema (CoreAudio en el Mac, WASAPI en Windows) o la simulada.
    var makeIO: AudioSession.IOFactory
    /// Modo WASAPI de la sesión (F2): compartido en Windows, nil en el Mac. Sin selector en la interfaz; va en `AudioSetup` y
    /// en la clave de calibración. Cambiarlo no reabre la sesión (lo hará el próximo cambio de ajustes).
    var wasapiMode: WASAPIShareMode? = AudioSession.systemWASAPIMode
    /// Se llama tras guardar la calibración nueva en el perfil.
    var onCalibrationSaved: ((LatencyCalibration) -> Void)?
    /// Guarda las tomas del proyecto abierto corregidas al calibrar (la parte de Grabar lo cablea con `StudySession`); sin él,
    /// no se corrige ninguna.
    var saveCorrectedTakes: (([Take]) -> Void)?
    /// Una toma nueva o corregida del proyecto abierto.
    var onTakesChanged: ((_ newTake: Bool) -> Void)?
    /// La toma terminada se entrega aquí (id, toma, cortada); el guardado lo hace Grabar con partes, vídeo y punches.
    var takeSink: ((UUID, RecordedTake, Bool) -> Void)?
    /// Cambió algo de lo que enseña `audio.state` (perfil, sesión, errores, calibración, grabación).
    var onStateChange: (() -> Void)?
    /// Niveles de entrada nuevos (0...1 por canal) y sus dB RMS/pico; nil = sin sesión.
    var onLevels: (([Float]?, [ChannelMeter]) -> Void)?
    /// La lista de dispositivos cambió (tras relevarla).
    var onDevicesChanged: (() -> Void)?
    /// El reproductor dejó de estar alojado en la sesión (el simulado de estudio vuelve a su salida propia).
    var onHostingEnded: (() -> Void)?

    private(set) var profile = EquipmentProfile() { didSet { onStateChange?() } }
    /// Ajustes con la guitarra resuelta (M-7): ajustes antiguos con `guitarIn` nil se resuelven aquí con la opción por omisión.
    var settings: AudioSettings? {
        guard var a = profile.audio else { return nil }
        let channels = a.inputDeviceUID.flatMap { uid in devices.inputs.first { $0.uid == uid }?.inputChannels }
        a.guitarIn = ChannelChoices.resolvedGuitar(a, inputChannels: channels)
        return a
    }
    var workingRate: Double { profile.workingSampleRate }
    private(set) var session: AudioSession?
    private(set) var sessionError: String? { didSet { if sessionError != oldValue { onStateChange?() } } }
    private(set) var hostError: String? { didSet { if hostError != oldValue { onStateChange?() } } }
    /// Por qué se cerró la sesión la última vez (desconexión, cambio de frecuencia); se limpia al reabrir.
    private(set) var interruptionNote: String? { didSet { if interruptionNote != oldValue { onStateChange?() } } }
    /// Nivel 0...1 por canal de entrada (índice 0 = canal 1); nil sin sesión.
    private(set) var inputLevels: [Float]?
    private(set) var calibrationPhase: CalibrationPhase = .idle { didSet { onCalibration?(calibrationPhase); onStateChange?() } }
    private(set) var isRecording = false { didSet { if isRecording != oldValue { onStateChange?() } } }
    /// Avisos de la última toma (retardo del rig no fiable, cortada).
    private(set) var takeNotices: [String] = [] { didSet { if takeNotices != oldValue { onStateChange?() } } }
    /// Progreso y resultado de la calibración (`audio.calibration`).
    var onCalibration: ((CalibrationPhase) -> Void)?

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
            onStateChange?()
        }
    }

    private var started = false
    private var currentSetup: AudioSetup?
    private var requestedRates: Set<String> = []
    private var meterTask: Task<Void, Never>?
    private weak var player: StudyPlayer?
    private weak var study: StudySession?
    private var recordingTakeID: UUID?
    private var cutAt: Date?
    /// Hay una `calibrateLatency` viva (aunque se haya cancelado la espera: la sesión sigue ocupada hasta que acabe).
    private var calibrationInFlight = false
    private var calibrationCancelled = false
    /// El reproductor está alojado en NUESTRA sesión (y no en la simulación propia de `StudyAudio`).
    private var hostedBySession = false

    init(provider: AudioDeviceProviding, store: ProfileStore?, makeIO: @escaping AudioSession.IOFactory = AudioSession.systemIO) {
        self.provider = provider
        self.store = store
        self.makeIO = makeIO
        devices = DeviceCatalog(provider: provider)
        devices.onChange = { [weak self] in self?.devicesChanged() }
    }

    /// Al soltarse el controlador (nadie lo cierra a mano: p. ej. un núcleo descartado) se cierra la sesión, que para la E/S
    /// y con ella el hilo de bombeo simulado (PC7).
    isolated deinit { session?.close() }

    /// Lee el perfil y abre la sesión si toca. Se llama una vez, al primer uso (`audio.*` o abrir un tema); las demás veces no hace nada.
    func start() {
        guard !started else { return }
        started = true
        reloadProfile()
    }

    // MARK: Perfil

    /// Relee `profile.json` (otro componente pudo escribirlo) y reaplica.
    func reloadProfile() {
        if let store, let p = try? store.load() { update(profile: p) } else { update(profile: profile) }
    }

    /// Lo llama quien cambie el perfil; solo reabre si cambió algo de la sesión.
    func update(profile new: EquipmentProfile) {
        let before = settings
        let rateChanged = workingRate != new.workingSampleRate
        profile = new
        if rateChanged || before?.inputDeviceUID != settings?.inputDeviceUID || before?.outputDeviceUID != settings?.outputDeviceUID {
            requestRates()
        }
        reconcile(force: false)
    }

    /// Cambia el perfil sobre lo que haya en disco (el volumen master lo escribe Backing) y lo guarda.
    func modifyProfile(_ change: (inout EquipmentProfile) -> Void) throws {
        // Mismo cerrojo que `video.*` (W2-A): dos escrituras a la vez de `profile.json` no se pisan.
        let p: EquipmentProfile = try {
            SettingsService.profileLock.lock(); defer { SettingsService.profileLock.unlock() }
            var p = (try? store?.load()) ?? profile
            change(&p)
            try store?.save(p)
            return p
        }()
        update(profile: p)
    }

    /// Ajustes de audio ya cambiados con `change`; valida antes de guardar (`AudioSettingsError` si no valen).
    func updateAudio(workingRate: Double? = nil, _ change: (inout AudioSettings) -> Void) throws {
        var a = settings ?? AudioSettings()
        change(&a)
        // Una guitarra que no cabe en el dispositivo de entrada (p. ej. [1, 2] en uno de 1 canal) o ausente pasa a «Entrada 1» (M-7).
        if a.inputDeviceUID != nil {
            let channels = a.inputDeviceUID.flatMap { uid in devices.inputs.first { $0.uid == uid }?.inputChannels }
            if let g = ChannelChoices.resolvedGuitar(a, inputChannels: channels), g != a.guitarIn { a.setGuitar(g) }
        }
        // Una salida de un canal solo admite el backing mono (M-3d); vale también como valor por defecto de un dispositivo nuevo.
        if let uid = a.outputDeviceUID, let d = devices.outputs.first(where: { $0.uid == uid }), d.outputChannels == 1,
           a.backingOut != .mono {
            a.setBacking(.mono)
        }
        try a.validate()
        try modifyProfile {
            $0.audio = a
            if let workingRate { $0.workingSampleRate = workingRate }
        }
    }

    private func devicesChanged() {
        requestRates()
        reconcile(force: true)
        onDevicesChanged?()
        onStateChange?()
    }

    private var inputDevice: AudioDevice? {
        settings?.inputDeviceUID.flatMap { uid in devices.inputs.first { $0.uid == uid } }
    }

    /// Salida elegida, o la de defecto del sistema si no hay ninguna elegida.
    private var outputDevice: AudioDevice? {
        if let uid = settings?.outputDeviceUID { return devices.outputs.first { $0.uid == uid } }
        return devices.systemDefault
    }

    /// El reproductor de estudio suena por la sesión.
    var isHostingPlayer: Bool { hostedBySession && player?.isHosted == true }
    var chosenInput: AudioDevice? { inputDevice }
    var chosenOutput: AudioDevice? { outputDevice }

    /// Frecuencia ACTUAL de un dispositivo elegido que no está a la de trabajo (mini-spec Fase 3, «Frecuencia»).
    var mismatchedRate: Double? {
        for d in [inputDevice, outputDevice].compactMap({ $0 }) {
            if let n = d.nominalSampleRate, abs(n - workingRate) > 0.5 { return n }
        }
        return nil
    }

    /// Al elegir dispositivo (o cambiar la frecuencia de trabajo) se le pide la frecuencia; si no la acepta se ve en
    /// `mismatchedRate` (en Windows el proveedor nunca la cambia).
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

    var calibrationIsRunning: Bool {
        if case .running = calibrationPhase { return true }
        return calibrationInFlight
    }

    /// Motivo para no calibrar; nil si se puede.
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
        if !isHostingPlayer { return .sessionUnavailable(hostError ?? "El backing no está sonando por el dispositivo.") }
        return nil
    }

    /// Calibración válida guardada para la configuración actual (la clave no cambió).
    var calibrationValid: Bool { validCalibration != nil }

    /// La calibración guardada si su clave es la de ahora (mini-spec Fase 3, «Caducidad»). Con la sesión abierta se compara
    /// con la clave REAL de la sesión, la misma que se guardó al calibrar y la que usa la grabación: con WASAPI el búfer de
    /// la clave es el periodo concedido (480 en compartido a 48 kHz), no los 512 pedidos del perfil, y comparar con el
    /// perfil daba «Sin calibrar» justo después de calibrar. Sin sesión, la clave del perfil (en el Mac son la misma).
    var validCalibration: LatencyCalibration? {
        guard let a = settings, let saved = a.latency else { return nil }
        if let s = session, let key = s.calibrationKey {
            return PortableAudioBridge.storeKey(key.inProfileTerms(outputDeviceUID: a.outputDeviceUID)) == saved.key ? saved : nil
        }
        return a.validLatency(sampleRate: workingRate, wasapi: wasapiKeyContext)
    }

    /// Lo que la clave de Windows añade al perfil (F2): el modo y el contenedor de los dispositivos elegidos (la salida por
    /// defecto va vacía en la clave, sin contenedor). nil en el Mac.
    var wasapiKeyContext: WASAPIKeyContext? {
        guard let wasapiMode else { return nil }
        return WASAPIKeyContext(mode: wasapiMode.rawValue, inputContainer: inputDevice?.containerID,
                                outputContainer: settings?.outputDeviceUID == nil ? nil : outputDevice?.containerID)
    }

    // MARK: Sesión

    /// ¿Se alojaría ahora el reproductor de estudio en la sesión? (sesión pedida con guitarra asignada y dispositivos listos).
    var wouldHostPlayer: Bool {
        guard let setup = desiredSetup() else { return false }
        return !setup.guitarIn.isEmpty
    }

    private func desiredSetup() -> AudioSetup? {
        guard started, let a = settings, a.isValid, let setup = PortableAudioBridge.setup(a, workingRate: workingRate,
                                                                                                  wasapiMode: wasapiMode) else { return nil }
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
        onStateChange?()
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
           let r = PortableAudioBridge.restored(saved, audio: a, sessionKey: key, guitarIn: setup.guitarIn,
                                                inputChannels: s.format?.inputChannels ?? 2) {
            s.calibration = r
        }
        restartMeters()
    }

    private func closeSession() {
        if isRecording { finishRecordingBeforeClosing() }
        let wasHosted = hostedBySession && player?.isHosted == true
        if hostedBySession { player?.detach() }
        hostedBySession = false
        session?.setEventHandler(nil)
        session?.close()
        session = nil
        inputLevels = nil
        hostError = nil
        if wasHosted { onHostingEnded?() }
    }

    /// Aloja el reproductor mientras la sesión está abierta con guitarra asignada; si no, vuelve a su salida normal.
    private func syncHosting() {
        guard let player else { return }
        if let s = session, s.isOpen, !s.setup.guitarIn.isEmpty {
            guard !(hostedBySession && player.isHosted) else { return }
            do {
                try player.attach(to: s)
                hostedBySession = true
                hostError = nil
            } catch StudyPlayerError.sampleRateMismatch {
                hostError = "Este tema no está a la frecuencia de trabajo (\(Self.rateText(workingRate))): no se puede grabar."
            } catch StudyPlayerError.noTracks {
                // Sin pistas cargadas (aún o de verdad): no es un fallo del dispositivo. Al cargar se reintenta.
                hostError = "Este tema no tiene stems para sonar de fondo: no se puede grabar."
            } catch {
                hostError = "No se pudo usar el dispositivo para el backing (\(error))."
            }
        } else {
            if hostedBySession, player.isHosted {
                player.detach()
                onHostingEnded?()
            }
            hostedBySession = false
            hostError = nil
        }
    }

    /// «44,1 kHz» / «48 kHz» (`Fmt.rate` del Mac).
    static func rateText(_ hz: Double) -> String {
        hz == 44100 ? "44,1 kHz" : hz == 48000 ? "48 kHz" : "\(Int(hz)) Hz"
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

    /// Reintenta alojar el reproductor en el dispositivo (p. ej. tras cargar las pistas, que `bind` pudo adelantarse a ellas).
    func refreshHosting() { syncHosting() }

    /// Backing abrió un tema: su reproductor se engancha a la sesión si hay una abierta con guitarra.
    func bind(player: StudyPlayer, study: StudySession) {
        start()
        self.player = player
        self.study = study
        takeNotices = []
        syncHosting()
    }

    /// Backing cerró el tema: el reproductor vuelve a su salida propia.
    func unbind() {
        if isRecording { finishRecordingBeforeClosing() }
        if hostedBySession { player?.detach() }
        hostedBySession = false
        player = nil
        study = nil
        hostError = nil
        takeNotices = []
    }

    // MARK: Medidores

    private func restartMeters() {
        meterTask?.cancel()
        meterTask = nil
        guard metersVisible, session != nil else {
            if inputLevels != nil { inputLevels = nil; onLevels?(nil, []) }
            return
        }
        meterTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.sampleMeters()
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 / Self.meterRefreshHz))
            }
        }
    }

    /// Una lectura de los medidores (la hace el bucle a `meterRefreshHz`; los tests la llaman a mano).
    func sampleMeters() {
        guard let s = session, s.isOpen else {
            if inputLevels != nil { inputLevels = nil; onLevels?(nil, []) }
            return
        }
        let meters = s.inputLevels()
        let levels = meters.map { Self.level(db: Double($0.rmsDB)) }
        inputLevels = levels
        onLevels?(levels, meters)
    }

    /// dBFS -> 0...1 entre el suelo del medidor y 0 dBFS.
    static func level(db: Double) -> Float {
        Float(min(max((db - meterFloorDB) / -meterFloorDB, 0), 1))
    }

    // MARK: Calibración

    /// Cierra el resultado de la calibración (como cerrar la hoja del Mac); no hace nada si está en marcha.
    func dismissCalibration() {
        if !calibrationIsRunning { calibrationPhase = .idle }
    }

    /// Deja de esperar la calibración en marcha: el resultado se descarta (la medida acaba sola en unos segundos y la sesión sigue
    /// ocupada hasta entonces).
    func cancelCalibration() {
        guard case .running = calibrationPhase else { return }
        calibrationCancelled = true
        calibrationPhase = .idle
        session?.cancelCalibration()   // corta la medida de verdad (si no, seguiría ~5 s)
    }

    /// Calibra (mini-spec Fase 3, «Calibración de latencia»). Devuelve cuando acaba; el estado va en `calibrationPhase`.
    func calibrate() async {
        guard !calibrationIsRunning, let s = session else { return }
        if let block = RecordingGate.deviceBlock(deviceState) {
            calibrationPhase = .finished(.error(block.message))
            return
        }
        player?.pause()
        calibrationCancelled = false
        calibrationInFlight = true
        calibrationPhase = .running(0)
        defer { calibrationInFlight = false }
        do {
            let r = try await s.calibrateLatency(progress: { p in
                Task { @MainActor [weak self] in
                    if case .running = self?.calibrationPhase { self?.calibrationPhase = .running(p) }
                }
            })
            if calibrationCancelled {
                discardCalibration(of: s)
                return
            }
            calibrationPhase = .finished(await finishCalibration(r, session: s))
        } catch {
            if calibrationCancelled { return }
            calibrationPhase = .finished(.error((error as? LocalizedError)?.errorDescription ?? "\(error)"))
        }
    }

    /// La sesión da por buena una calibración válida al acabar; si se canceló, vuelve a la guardada en el perfil (o a ninguna).
    private func discardCalibration(of s: AudioSession) {
        guard s === session else { return }
        if let saved = settings?.latency, let a = settings, let key = s.calibrationKey,
           let r = PortableAudioBridge.restored(saved, audio: a, sessionKey: key, guitarIn: s.setup.guitarIn,
                                                inputChannels: s.format?.inputChannels ?? 2) {
            s.calibration = r
        } else {
            s.calibration = nil
        }
    }

    private func finishCalibration(_ r: LatencyCalibrationResult, session s: AudioSession) async -> CalibrationOutcome {
        let fs = r.key.sampleRate
        let spreadMS = r.spreadSamples / fs * 1000
        if let failure = r.failure { return .failure(failure, spreadMS: spreadMS) }
        guard let a = settings else { return .error("No hay configuración de audio.") }
        let saved = PortableAudioBridge.calibration(r, audio: a)
        do {
            try modifyProfile { $0.audio?.latency = saved }
        } catch {
            return .error("No se pudo guardar la calibración: \(error)")
        }
        onCalibrationSaved?(saved)
        let corrected = await correctOpenProjectTakes(with: r)
        return .success(CalibrationSummary(latencyMS: r.latencySamples / fs * 1000, latencySamples: r.latencySamples,
                                           spreadMS: spreadMS, spreadSamples: r.spreadSamples,
                                           rigDelayMS: r.rigDelayAtCalibration.map { $0 / fs * 1000 },
                                           correctedTakes: corrected))
    }

    /// Vuelve a desplazar las tomas sin calibrar del proyecto abierto hechas con esta clave (mini-spec Fase 3, «Sin calibrar»).
    private func correctOpenProjectTakes(with r: LatencyCalibrationResult) async -> Int {
        guard let study, let save = saveCorrectedTakes else { return 0 }
        let folder = study.folder
        let candidates = study.project.takes.compactMap { t -> (Take, RecordedTake, URL)? in
            guard t.latencyCalibrated == false,
                  let (rec, url) = PortableAudioBridge.recorded(t, folder: folder, resolvedOutputUID: r.key.outputUID,
                                                                resolvedOutputEndpoint: r.key.wasapi?.outputEndpoint) else { return nil }
            return (t, rec, url)
        }
        guard !candidates.isEmpty else { return 0 }
        let pairs = candidates.map { (take: $0.1, file: $0.2) }
        let shifted = await Task.detached { try? AudioSession.reshiftUncalibrated(pairs, with: r) }.value
        guard let shifted else { return 0 }
        let fixed = zip(candidates, shifted).compactMap { c, new in new.map { PortableAudioBridge.applying($0, to: c.0) } }
        guard !fixed.isEmpty else { return 0 }
        save(fixed)
        onTakesChanged?(false)
        return fixed.count
    }

    // MARK: Grabar

    /// Empieza a grabar desde la posición actual con el backing sonando (mini-spec Fase 3, «Grabación»).
    func startRecording(playbackRate: Double, loopActive: Bool, takeID: UUID = UUID(), url target: URL? = nil) {
        takeNotices = []
        guard !isRecording, let s = session, let player, let study else { return }
        if let b = recordBlock(playbackRate: playbackRate, loopActive: loopActive) {
            takeNotices = [b.message]
            return
        }
        let id = takeID
        let url = target ?? study.layout.processedURL(takeId: id)
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

    /// Entrega la toma (una sola vez por grabación) a `takeSink`; sin él, la toma no se guarda y se avisa.
    private func finalize(_ t: RecordedTake, cut: Bool) {
        guard let id = recordingTakeID else { return }
        recordingTakeID = nil
        isRecording = false
        var notices: [String] = []
        if cut {
            cutAt = Date()
            notices.append("La toma se detuvo y se guardó lo grabado.")
        }
        if t.rigDelayReliable == false {
            notices.append("No se pudo medir con fiabilidad el retardo del rig en esta toma (mucho delay o reverb): se usó el último valor bueno.")
        }
        guard let takeSink else {
            takeNotices = notices + ["No hay dónde guardar la toma."]
            return
        }
        takeNotices = notices
        takeSink(id, t, cut)
    }

    // MARK: A/B

    /// Nivel en directo de tu guitarra (dBFS, RMS de los últimos 3 s); nil sin sesión o sin guitarra.
    func liveGuitarLevelDB() -> Double? {
        session?.guitarLevelDB(seconds: AudioSession.liveLevelSeconds)
    }

    // MARK: E/S simulada (`--audio simulated` y tests)

    /// Dispositivos simulados: una entrada y una salida de 2 canales, a `rate` (aceptan 44,1 y 48 kHz).
    static func simulatedProvider(rate: Double = EquipmentProfile.defaultSampleRate) -> SimulatedDeviceProvider {
        SimulatedDeviceProvider(
            devices: [
                AudioDevice(id: 1, uid: simulatedInputUID, name: "Entrada simulada", inputChannels: 2,
                            sampleRates: EquipmentProfile.allowedSampleRates, nominalSampleRate: rate),
                AudioDevice(id: 2, uid: simulatedOutputUID, name: "Salida simulada", outputChannels: 2,
                            sampleRates: EquipmentProfile.allowedSampleRates, nominalSampleRate: rate)
            ], defaultID: 2)
    }

    nonisolated static let simulatedInputUID = "sim-in"
    nonisolated static let simulatedOutputUID = "sim-out"
    /// Latencia de ida y vuelta de la E/S simulada, en muestras (con decimales, como un aparato real) y la declarada.
    nonisolated static let simulatedLatencySamples = 2_205.37
    nonisolated static let simulatedDeclaredLatencySamples = 1_100.0

    /// E/S simulada con el cable de prueba (entradas 1 y 2 oyen las salidas 1 y 2) y reloj real: un hilo da cuerda al simulador.
    /// `automatic` = lo más rápido que pueda (tests de calibración, sin esperar los 5 s).
    static func simulatedIO(automatic: Bool = false) -> AudioSession.IOFactory {
        { setup in
            let inputs = [SimulatedInput(source: 1, drive: 2, gain: 0.5, noiseDBFS: -60),
                          SimulatedInput(source: 2, drive: 2, gain: 0.5, noiseDBFS: -60)]
            let io = SimulatedAudioIO(sampleRate: setup.sampleRate, inputs: inputs, latencySamples: simulatedLatencySamples,
                                      declaredLatencySamples: simulatedDeclaredLatencySamples,
                                      bufferFrames: setup.bufferFrames, inputDeviceUID: simulatedInputUID,
                                      outputDeviceUID: simulatedOutputUID, automatic: automatic,
                                      wasapiIdentity: setup.wasapiMode.map { WASAPIIdentity(mode: $0) })
            if !automatic { RealtimePump(io: io, sampleRate: setup.sampleRate, block: setup.bufferFrames).start() }
            return io
        }
    }
}
