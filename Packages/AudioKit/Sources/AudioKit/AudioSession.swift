import NativeDSP
#if canImport(CoreAudio)
import CoreAudio
#endif
import Foundation
#if canImport(os)
import os
#endif
import Synchronization

// MARK: - Configuración y errores

/// Configuración resuelta de la sesión (mini-spec Fase 3, «Dispositivo y canales» y «Código»): dispositivos,
/// frecuencia de trabajo y canales (desde 1). La app la arma desde `EquipmentProfile.audio`.
public struct AudioSetup: Sendable, Equatable {
    public var inputDeviceUID: String
    /// Vacío = salida por defecto del sistema.
    public var outputDeviceUID: String
    /// Frecuencia de trabajo (la del proyecto).
    public var sampleRate: Double
    public var backingLeft: Int
    public var backingRight: Int
    /// Uno o dos canales; vacío mientras no se asigne (la sesión abre igual, para los medidores).
    public var guitarIn: [Int]
    /// 512 fijo en esta fase (mini-spec Fase 3, «Reglas propias»).
    public var bufferFrames: Int
    /// Modo WASAPI con el que abrir (paso 8, F2); nil = no es WASAPI (CoreAudio lo ignora). Va en la clave de calibración.
    public var wasapiMode: WASAPIShareMode?

    public static let defaultBufferFrames = 512

    public init(inputDeviceUID: String, outputDeviceUID: String, sampleRate: Double, backingLeft: Int = 1,
                backingRight: Int = 2, guitarIn: [Int] = [], bufferFrames: Int = AudioSetup.defaultBufferFrames,
                wasapiMode: WASAPIShareMode? = nil) {
        self.wasapiMode = wasapiMode
        self.inputDeviceUID = inputDeviceUID
        self.outputDeviceUID = outputDeviceUID
        self.sampleRate = sampleRate
        self.backingLeft = backingLeft
        self.backingRight = backingRight
        self.guitarIn = guitarIn
        self.bufferFrames = bufferFrames
    }

    /// Un dispositivo o agregado privado (la toma lo guarda en `clock`).
    public var clock: AudioIOClock {
        outputDeviceUID.isEmpty || outputDeviceUID == inputDeviceUID ? .single : .aggregate
    }
}

public enum AudioSessionError: Error, Equatable, Sendable, LocalizedError {
    case noInputDevice
    case noGuitarInput
    case invalidChannels(String)
    case notConnected(String)
    /// El dispositivo no acepta la frecuencia de trabajo (mini-spec Fase 3, «Frecuencia»).
    case sampleRateMismatch(device: Double, working: Double)
    case notOpen
    /// Calibrando o grabando: una cosa cada vez.
    case busy
    case notRecording
    /// No llegó el ancla del reproductor (no estaba sonando alojado en la sesión).
    case noPlayback
    /// Solo se graba al 100 % (mini-spec Fase 3, «Reglas propias»).
    case unsupportedRate(Double)
    case interrupted(AudioIOInterruption)
    case nothingRecorded
    case device(String)
    case write(String)

    public var errorDescription: String? {
        func khz(_ x: Double) -> String {
            String(format: x.truncatingRemainder(dividingBy: 1000) == 0 ? "%.0f" : "%.1f", x / 1000)
                .replacingOccurrences(of: ".", with: ",")
        }
        switch self {
        case .noInputDevice: return "No hay dispositivo de entrada elegido."
        case .noGuitarInput: return "Falta asignar la entrada de guitarra."
        case .invalidChannels(let s): return "Canales no válidos: \(s)."
        case .notConnected: return "El dispositivo no está conectado."
        case let .sampleRateMismatch(device, working):
            return "El dispositivo está a \(khz(device)) kHz y la frecuencia de trabajo es \(khz(working)) kHz"
        case .notOpen: return "El dispositivo no está abierto."
        case .busy: return "Hay una calibración o una grabación en marcha."
        case .notRecording: return "No se está grabando."
        case .noPlayback: return "El backing no estaba sonando por el dispositivo."
        case .unsupportedRate: return "Solo se graba a velocidad 100 %."
        case .interrupted(.disconnected): return "Se desconectó el dispositivo."
        case .interrupted(.sampleRateChanged(let r)): return "El dispositivo cambió a \(khz(r)) kHz."
        case .nothingRecorded: return "No se grabó nada."
        case .device(let s): return "Error del dispositivo: \(s)."
        case .write(let s): return "No se pudo escribir la toma: \(s)."
        }
    }

    init(_ error: AudioIOError, working: Double) {
        switch error {
        case .noInput: self = .noInputDevice
        case .notConnected(let uid): self = .notConnected(uid)
        case let .sampleRateMismatch(device, _): self = .sampleRateMismatch(device: device, working: working)
        case .alreadyRunning: self = .busy
        case .device(let s): self = .device(s)
        }
    }

    init(_ error: TakeRecorderError) {
        switch error {
        case .noAnchor: self = .noPlayback
        case .unsupportedRate(let r): self = .unsupportedRate(r)
        case .nothingCaptured: self = .nothingRecorded
        case .write(let s): self = .write(s)
        }
    }
}

/// Avisos de la sesión, en cualquier hilo (nunca el de E/S).
public enum AudioSessionEvent: Sendable, Equatable {
    /// Toma guardada sin pulsar parar: la sesión se cortó a mitad (se guarda lo grabado) o el reproductor
    /// paró o cambió de pasada. `stopRecording()` la devuelve igual.
    case recordingSaved(RecordedTake)
    case recordingFailed(AudioSessionError)
    /// La sesión se cortó y está cerrada (`recordingSaved` llega antes si se grababa).
    case interrupted(AudioIOInterruption)
}

// MARK: - Sesión

/// Fachada de audio con el dispositivo para la app (mini-spec Fase 3). Sin UI y sin actor: se usa desde
/// cualquier hilo (estado tras cerrojos). Todo inyectable: `makeIO` crea la `AudioIO` (por defecto
/// `CoreAudioIO`; en tests, `SimulatedAudioIO`).
///
/// Mientras está abierta corre la sesión dúplex: medidores de entrada en vivo, el `StudyPlayer` alojado
/// (`StudyPlayer.attach(to:)`) sonando por `backingOut`, calibración y grabación. Una cosa cada vez:
/// calibrar silencia el backing; no se calibra grabando.
///
/// Hilo de E/S → `CaptureRing` (sin cerrojos) → hilo consumidor (cada `consumerIntervalSeconds`) →
/// medidores, `LatencyCalibrator`, `TakeRecorder`. El estímulo de la calibración se escribe directamente en
/// el `render` (sin el cerrojo del calibrador).
public final class AudioSession: @unchecked Sendable {
    public typealias IOFactory = @Sendable (AudioSetup) throws -> any AudioIO

    #if canImport(CoreAudio)
    /// `CoreAudioIO` sobre los dispositivos del `AudioSetup` (salida vacía = la de defecto del sistema).
    public static let coreAudio: IOFactory = { setup in
        var out = setup.outputDeviceUID
        if out.isEmpty {
            let id = HAL.get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                             as: AudioDeviceID.self) ?? 0
            out = HAL.string(id, kAudioDevicePropertyDeviceUID) ?? ""
        }
        return try CoreAudioIO(inputUID: setup.inputDeviceUID, outputUID: out, sampleRate: setup.sampleRate,
                               bufferFrames: setup.bufferFrames)
    }
    #endif

    #if os(Windows)
    /// `WASAPIAudioIO` sobre los endpoints del `AudioSetup`, en `setup.wasapiMode` (nil = compartido; parte 7.10, F2).
    public static let wasapi: IOFactory = { setup in try WASAPIAudioIO(setup: setup) }
    #endif

    /// E/S del sistema: `coreAudio` en el Mac, `wasapi` en Windows.
    public static var systemIO: IOFactory {
        #if canImport(CoreAudio)
        coreAudio
        #else
        wasapi
        #endif
    }

    /// Modo WASAPI de `systemIO` (paso 8, F2): compartido en Windows (sin selector en la interfaz), nil en el Mac.
    public static var systemWASAPIMode: WASAPIShareMode? {
        #if canImport(CoreAudio)
        nil
        #else
        .shared
        #endif
    }

    /// Capacidad del búfer circular de captura (decisión propia: holgura de sobra para el consumidor).
    public static let ringSeconds = 4.0
    static let consumerIntervalSeconds = 0.005
    /// Ventana de los medidores de entrada (decisión propia).
    public static let meterWindowSeconds = 0.3
    /// RMS de `guitarIn` para la diferencia de nivel en directo (mini-spec Fase 3, «A/B» · B en directo).
    public static let liveLevelSeconds = 3.0
    /// Tope de espera de la calibración (decisión propia; el estímulo dura 5 s).
    public static let calibrationTimeoutSeconds = 15.0

    public let setup: AudioSetup
    private let makeIO: IOFactory
    private let lock = NSLock()
    private var io: (any AudioIO)?
    private var rt: SessionRT?
    private var consumer: Thread?
    private var consumerRunning = false
    private var interruptionValue: AudioIOInterruption?
    private var eventHandler: (@Sendable (AudioSessionEvent) -> Void)?
    private var calibrationValue: LatencyCalibrationResult?
    private var lastReliableRigDelayValue: Double?
    private var playerEnd: (@Sendable () -> Void)?

    /// Solo bajo `consumerLock` (el hilo consumidor y quien vacíe a mano).
    private let consumerLock = NSLock()
    private var levels: LevelHistory?
    private var calibrator: LatencyCalibrator?
    private var calibratorOriginSent = false
    /// `cancelCalibration()` lo pone; la espera de `calibrateLatency` lo lee (bajo `consumerLock`).
    private var calibrationCancelRequested = false
    private var calibrationFrames = 0
    private var recording: Recording?
    private var finishedTake: Result<RecordedTake, AudioSessionError>?

    private final class Recording {
        let recorder: TakeRecorder
        let url: URL
        let fixedAnchor: PlaybackAnchor?
        var anchor: PlaybackAnchor?
        var cut = false
        /// Contadores de E/S al empezar (la línea `audio.take|` da la diferencia).
        /// La E/S se guarda para leer los contadores al final aunque la sesión se haya cortado (`io = nil`).
        let io: any AudioIO
        let ioAtStart: AudioIODiagnostics?
        init(recorder: TakeRecorder, url: URL, anchor: PlaybackAnchor?, io: any AudioIO) {
            self.recorder = recorder
            self.url = url
            fixedAnchor = anchor
            self.io = io
            ioAtStart = io.diagnostics
        }
    }

    public init(setup: AudioSetup, makeIO: @escaping IOFactory = AudioSession.systemIO) {
        self.setup = setup
        self.makeIO = makeIO
    }

    deinit { close() }

    public var sampleRate: Double { setup.sampleRate }

    // MARK: Abrir y cerrar

    /// Abre el dispositivo (le pide la frecuencia de trabajo) y arranca la sesión dúplex.
    public func open() throws {
        try lock.withLock {
            guard io == nil else { return }
            guard !setup.inputDeviceUID.isEmpty else { throw AudioSessionError.noInputDevice }
            let io: any AudioIO
            do { io = try makeIO(setup) } catch let e as AudioIOError {
                throw AudioSessionError(e, working: setup.sampleRate)
            }
            let f = io.format
            guard abs(f.sampleRate - setup.sampleRate) < 0.5 else {
                throw AudioSessionError.sampleRateMismatch(device: f.sampleRate, working: setup.sampleRate)
            }
            try Self.validate(setup, inputs: f.inputChannels, outputs: f.outputChannels)
            let rt = SessionRT(ringFrames: Int(Self.ringSeconds * f.sampleRate), inputs: f.inputChannels,
                               outputs: f.outputChannels, backingLeft: setup.backingLeft - 1,
                               backingRight: setup.backingRight - 1, probe: LatencyProbe(sampleRate: f.sampleRate))
            consumerLock.withLock {
                levels = LevelHistory(channels: f.inputChannels, sampleRate: f.sampleRate)
                finishedTake = nil
            }
            io.setInterruptionHandler { [weak self] reason in self?.interrupted(reason) }
            do {
                try io.start(render: { rt.render($0) }, capture: { rt.capture($0) })
            } catch let e as AudioIOError {
                throw AudioSessionError(e, working: setup.sampleRate)
            }
            self.io = io
            self.rt = rt
            interruptionValue = nil
            consumerRunning = true
            let t = Thread { [weak self] in
                while let s = self, s.lock.withLock({ s.consumerRunning }) {
                    s.drainCapture()
                    Thread.sleep(forTimeInterval: Self.consumerIntervalSeconds)
                }
            }
            t.qualityOfService = .userInitiated
            t.name = "ToneForge.AudioSession.consumer"
            consumer = t
            t.start()
        }
    }

    /// Cierra la sesión (si se grababa, la toma se descarta: usa antes `stopRecording`).
    /// Suelta también el reproductor alojado (plan, «Pendiente tras el paso 7»): al volver la sesión ya no retiene su
    /// render ni, con él, los stems; el reproductor vuelve a su salida con `onEnd`, como antes.
    public func close() {
        let (io, end, rt) = lock.withLock { () -> ((any AudioIO)?, (@Sendable () -> Void)?, SessionRT?) in
            let io = self.io
            self.io = nil
            consumerRunning = false
            consumer = nil
            defer { playerEnd = nil }
            return (io, playerEnd, self.rt)
        }
        io?.setInterruptionHandler(nil)
        io?.stop()
        consumerLock.withLock {
            recording = nil
            calibrator = nil
        }
        rt?.calibrating.store(false, ordering: .sequentiallyConsistent)
        // Tras `stop` el hilo de E/S ya no entra; si un bloque tenía aún el render, lo retiene él hasta acabarlo.
        rt?.player.withLockUnchecked { $0 = nil }
        end?()
    }

    public var isOpen: Bool { lock.withLock { io != nil } }
    /// Por qué se cortó la última sesión (nil si sigue abierta o se cerró a mano).
    public var interruption: AudioIOInterruption? { lock.withLock { interruptionValue } }
    public var clock: AudioIOClock? { lock.withLock { io?.clock } }
    public var format: AudioIOFormat? { lock.withLock { io?.format } }
    /// Muestras de entrada perdidas porque el consumidor no llegó (debe ser 0).
    public var droppedFrames: Int { lock.withLock { rt?.ring.droppedFrames ?? 0 } }
    /// Contadores del ciclo de E/S del dispositivo abierto (`nil` cerrado o si no los da).
    public var ioDiagnostics: AudioIODiagnostics? { lock.withLock { io?.diagnostics } }

    /// Instante de host de la primera muestra de cada ciclo de salida desde que se abrió la sesión, con
    /// `sampleTime` mayor que `after` (mini-spec Fase 6, «Cámara y sincronía»). Junto con `playbackAnchor` es lo
    /// que necesita `HostTimeMap` (VideoKit) para situar en el tema cada fotograma de la cámara. Guarda los
    /// últimos `HostClockLog.capacity` ciclos (unos 11 min a 512 muestras y 48 kHz): quien grabe más debe
    /// pedirlos a medida que llegan. Vacío cerrada o si el dispositivo no da marcas de host.
    public func outputHostClock(after: Int64 = .min) -> [HostClockPoint] {
        guard let rt = lock.withLock({ rt }) else { return [] }
        return rt.clockLog.points(after: after)
    }

    public func setEventHandler(_ handler: (@Sendable (AudioSessionEvent) -> Void)?) {
        lock.withLock { eventHandler = handler }
    }

    /// Latencia de salida estimada (solo para enseñar la posición): la mitad de la declarada de ida y vuelta.
    var outputLatencyFrames: Double { lock.withLock { (io?.declaredLatencySamples ?? 0) / 2 } }

    static func validate(_ s: AudioSetup, inputs: Int, outputs: Int) throws {
        guard s.backingLeft != s.backingRight, (1...max(outputs, 1)).contains(s.backingLeft),
              (1...max(outputs, 1)).contains(s.backingRight), outputs >= 2 else {
            throw AudioSessionError.invalidChannels("backing \(s.backingLeft)-\(s.backingRight) con \(outputs) salidas")
        }
        guard s.guitarIn.count <= 2, Set(s.guitarIn).count == s.guitarIn.count,
              s.guitarIn.allSatisfy({ (1...max(inputs, 1)).contains($0) }) else {
            throw AudioSessionError.invalidChannels("guitarra \(s.guitarIn) con \(inputs) entradas")
        }
    }

    // MARK: Reproductor alojado

    /// Lo llama `StudyPlayer.attach`/`detach`. `onEnd` se llama si la sesión se cierra o se corta.
    func setPlayer(_ renderer: (any HostedPlayback)?, onEnd: (@Sendable () -> Void)?) {
        let rt = lock.withLock { () -> SessionRT? in
            playerEnd = onEnd
            return self.rt
        }
        rt?.player.withLockUnchecked { $0 = renderer }
    }

    /// Ancla del reproductor alojado, en la línea de tiempo de la sesión.
    public var playbackAnchor: PlaybackAnchor? {
        lock.withLock { rt }?.player.withLockUnchecked { $0 }?.anchor
    }

    // MARK: Niveles

    /// Nivel de cada canal de entrada del dispositivo (`[i]` es el canal `i + 1`) en los últimos
    /// `meterWindowSeconds`. Vacío con la sesión cerrada.
    public func inputLevels() -> [ChannelMeter] {
        consumerLock.withLock { levels?.meters(seconds: Self.meterWindowSeconds) ?? [] }
    }

    /// RMS (dBFS) de `guitarIn` en los últimos `seconds` (por defecto 3 s), potencia media de sus canales.
    /// nil sin guitarra asignada o sin datos.
    public func guitarLevelDB(seconds: Double = AudioSession.liveLevelSeconds) -> Double? {
        let ch = setup.guitarIn.map { $0 - 1 }
        guard !ch.isEmpty else { return nil }
        return consumerLock.withLock { levels?.rmsDB(channels: ch, seconds: seconds) }
    }

    // MARK: Calibración

    /// Calibración en uso para grabar (la app la restaura desde Store; se actualiza al calibrar con éxito).
    public var calibration: LatencyCalibrationResult? {
        get { lock.withLock { calibrationValue } }
        set { lock.withLock { calibrationValue = newValue } }
    }

    /// Último retardo del rig fiable (se actualiza con cada toma fiable).
    public var lastReliableRigDelay: Double? {
        get { lock.withLock { lastReliableRigDelayValue } }
        set { lock.withLock { lastReliableRigDelayValue = newValue } }
    }

    /// Clave de calibración de la sesión abierta (nil sin `guitarIn` o cerrada).
    public var calibrationKey: LatencyCalibrationKey? {
        lock.withLock {
            guard let io, !setup.guitarIn.isEmpty else { return nil }
            return LatencyCalibrationKey(io: io, backingOutLeft: setup.backingLeft, guitarIn: setup.guitarIn)
        }
    }

    /// La calibración en uso vale para la sesión abierta.
    public var isCalibrated: Bool {
        guard let key = calibrationKey, let cal = calibration else { return false }
        return cal.applies(to: key)
    }

    /// Calibra la latencia (mini-spec Fase 3, «Calibración de latencia»): el barrido sale por el canal
    /// izquierdo del backing (el reproductor se silencia mientras) y se graban todas las entradas.
    /// `progress` (0…1) se llama en cualquier hilo. Devuelve el resultado aunque no valga (`failure` dice
    /// por qué); si vale, pasa a ser `calibration`. Lanza si la sesión no está abierta, está ocupada o se corta.
    public func calibrateLatency(progress: (@Sendable (Double) -> Void)? = nil) async throws -> LatencyCalibrationResult {
        guard !setup.guitarIn.isEmpty else { throw AudioSessionError.noGuitarInput }
        let (io, rt) = try lock.withLock { () -> (any AudioIO, SessionRT) in
            guard let i = self.io, let r = self.rt else { throw AudioSessionError.notOpen }
            return (i, r)
        }
        let cal = LatencyCalibrator(io: io, backingOutLeft: setup.backingLeft, guitarIn: setup.guitarIn)
        try consumerLock.withLock {
            guard calibrator == nil, recording == nil else { throw AudioSessionError.busy }
            calibrator = cal
            calibratorOriginSent = false
            calibrationFrames = 0
            calibrationCancelRequested = false
        }
        rt.origin.store(Int64.min, ordering: .sequentiallyConsistent)
        rt.calibrating.store(true, ordering: .sequentiallyConsistent)
        defer {
            rt.calibrating.store(false, ordering: .sequentiallyConsistent)
            consumerLock.withLock { if calibrator === cal { calibrator = nil } }
        }
        let needed = Double(cal.probe.captureFrames + cal.probe.maxLatencyFrames)
        let start = Date()
        while true {
            if let reason = interruption { throw AudioSessionError.interrupted(reason) }
            guard isOpen else { throw AudioSessionError.notOpen }
            if consumerLock.withLock({ calibrationCancelRequested }) { throw CancellationError() }
            if cal.isComplete { break }
            if Date().timeIntervalSince(start) > Self.calibrationTimeoutSeconds { break }
            let frames = consumerLock.withLock { calibrationFrames }
            progress?(min(0.99, Double(frames) / needed))
            try? await Task.sleep(for: .milliseconds(20))
        }
        let result = cal.result()
        if result.isValid { calibration = result }
        progress?(1)
        return result
    }

    /// Corta la calibración en marcha: `calibrateLatency` lanza `CancellationError` en el siguiente sondeo (20 ms), suelta el
    /// calibrador y deja la calibración anterior de la sesión. No toca la señal ni el calibrador.
    public func cancelCalibration() {
        consumerLock.withLock { if calibrator != nil { calibrationCancelRequested = true } }
    }

    /// Vuelve a desplazar las tomas sin calibrar hechas con la clave de `calibration` (mini-spec Fase 3,
    /// «Sin calibrar»). Devuelve, en el mismo orden, la toma corregida o nil si no tocaba.
    public static func reshiftUncalibrated(_ takes: [(take: RecordedTake, file: URL)],
                                           with calibration: LatencyCalibrationResult) throws -> [RecordedTake?] {
        try takes.map { try TakeAligner.reshift($0.take, file: $0.file, with: calibration) }
    }

    // MARK: Grabación

    /// Empieza una toma que se escribirá en `url` (`processed.wav`). Con el reproductor alojado sonando, el
    /// ancla sale de él; `anchor` solo para grabar sin reproductor (`tf-audio record`). Sin calibración
    /// válida graba igual con la latencia declarada y la toma queda marcada.
    public func startRecording(to url: URL, anchor: PlaybackAnchor? = nil) throws {
        guard !setup.guitarIn.isEmpty else { throw AudioSessionError.noGuitarInput }
        let io = try lock.withLock { () -> any AudioIO in
            guard let i = self.io else { throw interruptionValue.map { AudioSessionError.interrupted($0) } ?? .notOpen }
            return i
        }
        if let a = anchor ?? playbackAnchor, abs(a.rate - 1) > 1e-9 { throw AudioSessionError.unsupportedRate(a.rate) }
        let rec = TakeRecorder(io: io, backingOutLeft: setup.backingLeft, guitarIn: setup.guitarIn,
                               calibration: calibration, lastReliableRigDelay: lastReliableRigDelay)
        // Lo capturado antes de empezar va a los medidores, no a la toma.
        drainCapture()
        try consumerLock.withLock {
            guard calibrator == nil, recording == nil else { throw AudioSessionError.busy }
            recording = Recording(recorder: rec, url: url, anchor: anchor, io: io)
            finishedTake = nil
        }
    }

    public var isRecording: Bool { consumerLock.withLock { recording != nil } }
    /// La toma en curso se alinea con la latencia calibrada.
    public var recordingIsCalibrated: Bool? { consumerLock.withLock { recording?.recorder.isCalibrated } }

    /// Para, alinea y escribe la toma. Si la sesión se cortó a mitad, devuelve la que se guardó entonces.
    public func stopRecording() throws -> RecordedTake {
        drainCapture()
        let rec = consumerLock.withLock { () -> Recording? in
            defer { recording = nil }
            return recording
        }
        guard let rec else {
            let done = consumerLock.withLock { () -> Result<RecordedTake, AudioSessionError>? in
                defer { finishedTake = nil }
                return finishedTake
            }
            guard let done else { throw AudioSessionError.notRecording }
            return try done.get()
        }
        return try finish(rec).get()
    }

    private func finish(_ rec: Recording) -> Result<RecordedTake, AudioSessionError> {
        let filled = rec.recorder.filledGaps
        AudioKitLog.write(AudioKitLog.takeLine(start: rec.ioAtStart, end: rec.io.diagnostics, filledGaps: filled.count,
                                               filledFrames: filled.frames, sampleRate: rec.recorder.sampleRate))
        do {
            let take = try rec.recorder.finish(writingTo: rec.url)
            if take.rigDelayReliable == true { lastReliableRigDelay = take.rigDelaySamples }
            return .success(take)
        } catch let e as TakeRecorderError {
            return .failure(AudioSessionError(e))
        } catch {
            return .failure(.write("\(error)"))
        }
    }

    // MARK: Consumidor

    /// Vacía ya el búfer circular hacia medidores, calibrador y grabador. Lo hace solo el hilo consumidor;
    /// sirve al conducir un `SimulatedAudioIO` a mano (más rápido que el tiempo real), entre `pump()`.
    public func flushCapture() { drainCapture() }

    func drainCapture() {
        guard let rt = lock.withLock({ rt }) else { return }
        var cutTake: Recording?
        consumerLock.withLock {
            if let cal = calibrator, !calibratorOriginSent {
                let o = rt.origin.load(ordering: .sequentiallyConsistent)
                if o != Int64.min {
                    rt.withEmptyOutput(at: o) { cal.render($0) }
                    calibratorOriginSent = true
                }
            }
            let anchorNow = recording.flatMap { $0.fixedAnchor ?? rt.player.withLockUnchecked { $0 }?.anchor }
            if let rec = recording, !rec.cut {
                if rec.anchor == nil, let a = anchorNow {
                    rec.anchor = a
                    rec.recorder.setAnchor(a)
                } else if rec.anchor != nil, anchorNow != rec.anchor {
                    // El reproductor paró o cambió de pasada: la toma acaba aquí.
                    rec.cut = true
                }
            }
            rt.ring.drain { b in
                levels?.add(b)
                if let cal = calibrator, calibratorOriginSent {
                    cal.capture(b)
                    calibrationFrames += b.frameCount
                }
                if let rec = recording, !rec.cut { rec.recorder.capture(b) }
            }
            if let rec = recording, rec.cut {
                recording = nil
                cutTake = rec
            }
        }
        if let rec = cutTake { saveCut(rec) }
    }

    private func saveCut(_ rec: Recording) {
        let result = finish(rec)
        consumerLock.withLock { finishedTake = result }
        let handler = lock.withLock { eventHandler }
        switch result {
        case .success(let t): handler?(.recordingSaved(t))
        case .failure(let e): handler?(.recordingFailed(e))
        }
    }

    private func interrupted(_ reason: AudioIOInterruption) {
        lock.withLock {
            interruptionValue = reason
            io = nil
            consumerRunning = false
            consumer = nil
        }
        rt?.calibrating.store(false, ordering: .sequentiallyConsistent)
        drainCapture()
        let rec = consumerLock.withLock { () -> Recording? in
            defer { recording = nil }
            return recording
        }
        if let rec { saveCut(rec) }
        let (handler, end) = lock.withLock { () -> ((@Sendable (AudioSessionEvent) -> Void)?, (@Sendable () -> Void)?) in
            defer { playerEnd = nil }
            return (eventHandler, playerEnd)
        }
        rt?.player.withLockUnchecked { $0 = nil }
        end?()
        handler?(.interrupted(reason))
    }
}

// MARK: - Lado de tiempo real

/// Lo que tocan los manejadores de la sesión en el hilo de E/S: sin cerrojos de bloqueo ni reservas.
final class SessionRT: @unchecked Sendable {
    let ring: CaptureRing
    let backingLeft: Int
    let backingRight: Int
    let probe: LatencyProbe
    let player = StateLock<(any HostedPlayback)?>(initialState: nil)
    let calibrating = Atomic<Bool>(false)
    /// Marcas de host de cada ciclo de salida (mini-spec Fase 6).
    let clockLog = HostClockLog()
    /// Muestra de salida del primer barrido (`Int64.min` = aún no).
    let origin = Atomic<Int64>(Int64.min)
    private let dummy: UnsafeMutablePointer<Float>
    private let dummyPointers: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>>

    init(ringFrames: Int, inputs: Int, outputs: Int, backingLeft: Int, backingRight: Int, probe: LatencyProbe) {
        ring = CaptureRing(channels: inputs, capacity: ringFrames)
        self.backingLeft = backingLeft
        self.backingRight = backingRight
        self.probe = probe
        dummy = .allocate(capacity: 1)
        dummy.initialize(to: 0)
        dummyPointers = .allocate(capacity: max(outputs, 1))
        dummyPointers.initialize(repeating: dummy)
    }

    deinit {
        dummy.deallocate()
        dummyPointers.deallocate()
    }

    func render(_ b: AudioIOBuffer) {
        if b.hostSeconds > 0 { clockLog.append(HostClockPoint(sampleTime: b.sampleTime, hostSeconds: b.hostSeconds)) }
        if calibrating.load(ordering: .sequentiallyConsistent) {
            var o = origin.load(ordering: .relaxed)
            if o == Int64.min {
                o = b.sampleTime
                origin.store(o, ordering: .sequentiallyConsistent)
            }
            guard backingLeft >= 0, backingLeft < b.channelCount else { return }
            let out = b[backingLeft]
            let rel = Int(b.sampleTime - o)
            for i in 0..<b.frameCount { out[i] = probe.stimulus(at: rel + i) }
            return
        }
        if let r = player.withLockUnchecked({ $0 }) { r.render(into: b, left: backingLeft, right: backingRight) }
    }

    func capture(_ b: AudioIOBuffer) { ring.write(b) }

    /// Bloque de salida vacío en `sampleTime` (para fijar el origen del calibrador fuera del hilo de E/S).
    func withEmptyOutput(at sampleTime: Int64, _ body: (AudioIOBuffer) -> Void) {
        body(AudioIOBuffer(sampleTime: sampleTime, frameCount: 0, channels: UnsafeBufferPointer(dummyPointers)))
    }
}

/// Registro circular de las marcas de host de cada ciclo de salida. Un escritor (el hilo de E/S, sin reservar
/// memoria) y lectores fuera de él, como `HostTimeLog`: el lector copia solo lo que el escritor no puede estar
/// pisando.
final class HostClockLog: @unchecked Sendable {
    /// 2^16 ciclos: 11,6 min a 512 muestras y 48 kHz.
    static let capacity = 1 << 16
    static let guardEntries = 64
    private let buf: UnsafeMutablePointer<HostClockPoint>
    private let written = Atomic<Int>(0)

    init() {
        buf = .allocate(capacity: Self.capacity)
        buf.initialize(repeating: HostClockPoint(sampleTime: 0, hostSeconds: 0), count: Self.capacity)
    }

    deinit { buf.deallocate() }

    /// Solo desde el hilo de E/S.
    func append(_ p: HostClockPoint) {
        let n = written.load(ordering: .relaxed)
        buf[n & (Self.capacity - 1)] = p
        written.store(n + 1, ordering: .releasing)
    }

    func points(after: Int64) -> [HostClockPoint] {
        let n = written.load(ordering: .acquiring)
        let keep = min(n, Self.capacity - Self.guardEntries)
        var out: [HostClockPoint] = []
        for i in (n - keep)..<n {
            let p = buf[i & (Self.capacity - 1)]
            if p.sampleTime > after { out.append(p) }
        }
        return out
    }
}

// MARK: - Niveles

/// Historial de niveles por bloque de cada canal de entrada: suma de cuadrados, pico y muestras.
struct LevelHistory {
    static let capacity = 4_096
    let channels: Int
    let sampleRate: Double
    private var sumSq: [[Double]]
    private var peak: [[Float]]
    private var frames: [Int]
    private var head = 0
    private var count = 0

    init(channels: Int, sampleRate: Double) {
        self.channels = channels
        self.sampleRate = sampleRate
        sumSq = Array(repeating: [Double](repeating: 0, count: Self.capacity), count: channels)
        peak = Array(repeating: [Float](repeating: 0, count: Self.capacity), count: channels)
        frames = [Int](repeating: 0, count: Self.capacity)
    }

    mutating func add(_ b: AudioIOBuffer) {
        let n = b.frameCount
        guard n > 0 else { return }
        for c in 0..<min(channels, b.channelCount) {
            var ms: Float = 0, p: Float = 0
            DSP.measqv(b[c].baseAddress!, 1, &ms, DSPLength(n))
            DSP.maxmgv(b[c].baseAddress!, 1, &p, DSPLength(n))
            sumSq[c][head] = Double(ms) * Double(n)
            peak[c][head] = p
        }
        frames[head] = n
        head = (head + 1) % Self.capacity
        count = min(count + 1, Self.capacity)
    }

    /// Recorre hacia atrás los bloques que cubren `seconds`.
    private func walk(seconds: Double, _ body: (Int) -> Void) -> Int {
        let want = Int(seconds * sampleRate)
        var got = 0, k = 0
        while k < count, got < want {
            let i = (head - 1 - k + Self.capacity) % Self.capacity
            body(i)
            got += frames[i]
            k += 1
        }
        return got
    }

    func meters(seconds: Double) -> [ChannelMeter] {
        func db(_ x: Double) -> Float { x > 1e-6 ? Float(20 * log10(x)) : -120 }
        return (0..<channels).map { c in
            var s = 0.0, p: Float = 0
            let n = walk(seconds: seconds) { s += sumSq[c][$0]; p = max(p, peak[c][$0]) }
            guard n > 0 else { return .silent }
            return ChannelMeter(rmsDB: db(sqrt(s / Double(n))), peakDB: db(Double(p)))
        }
    }

    func rmsDB(channels list: [Int], seconds: Double) -> Double? {
        var s = 0.0
        let n = walk(seconds: seconds) { i in for c in list where c < channels { s += sumSq[c][i] } }
        guard n > 0 else { return nil }
        let ms = s / Double(n * list.count)
        return ms > 1e-12 ? 10 * log10(ms) : -120
    }
}
