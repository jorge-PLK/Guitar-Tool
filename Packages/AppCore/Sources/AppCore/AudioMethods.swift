import AudioKit
import Foundation
import Store

// Métodos y eventos `audio.*` (paso 8, ola 2, W2-C). Contrato en `Temp/win/step8-contract.md`, sección «W2-C audio.*».
// Los textos de estado y error son los de `AudioSettingsView.swift`, `CalibrationSheet.swift` y `AppLogic.swift` (RecordBlock) del Mac.

// MARK: - Tipos del contrato

struct AudioDeviceItem: Codable, Sendable, Equatable {
    var uid: String
    var name: String
    var channels: Int
    /// «nombre · n can.» o «nombre · desconectado» (el elegido que ya no está conectado).
    var label: String
    var connected: Bool
    /// Frecuencia actual del dispositivo (Hz), si se conoce.
    var rate: Double?
}

struct AudioDevicesResult: Codable, Sendable, Equatable {
    var inputs: [AudioDeviceItem]
    var outputs: [AudioDeviceItem]
    /// Salida por defecto del sistema (la de «Salida del sistema»), si hay.
    var systemDefault: AudioDeviceItem?
}

struct AudioRateOption: Codable, Sendable, Equatable {
    var rate: Double
    var label: String
}

struct AudioBackingChoice: Codable, Sendable, Equatable {
    var label: String
    var left: Int
    var right: Int
}

struct AudioGuitarChoice: Codable, Sendable, Equatable {
    var label: String
    /// nil = «Sin asignar».
    var channels: [Int]?
}

struct AudioRateMismatch: Codable, Sendable, Equatable {
    var deviceRate: Double
    var workingRate: Double
    var message: String
    var hint: String
    /// `deviceRate` es una frecuencia de trabajo permitida: se puede ofrecer el botón.
    var canUseDeviceRate: Bool
    var useLabel: String
}

struct AudioCalibrationInfo: Codable, Sendable, Equatable {
    var calibrated: Bool
    /// «Sin calibrar» o «Calibrada · 2,05 ms · 3 feb 2026».
    var label: String
    var latencyMS: Double?
    var date: Date?
}

struct AudioChannelPair: Codable, Sendable, Equatable {
    var left: Int
    var right: Int
}

struct AudioSettingsResult: Codable, Sendable, Equatable {
    var outputDeviceUID: String?
    var inputDeviceUID: String?
    var backingOut: AudioChannelPair
    var guitarIn: [Int]?
    var workingSampleRate: Double
    var allowedSampleRates: [AudioRateOption]
    var backingChoices: [AudioBackingChoice]
    var guitarChoices: [AudioGuitarChoice]
    var rateMismatch: AudioRateMismatch?
    var calibration: AudioCalibrationInfo
    /// Motivo por el que «Calibrar latencia» está desactivado; nil si se puede.
    var calibrateBlock: String?
    /// Textos de la hoja de calibración (`CalibrationSheet`), en orden.
    var calibrateInstructions: [String]
}

struct AudioStateResult: Codable, Sendable, Equatable {
    var sessionOpen: Bool
    var sessionError: String?
    var interruptionNote: String?
    var hostError: String?
    /// El reproductor de estudio suena por la sesión (necesario para grabar).
    var hosting: Bool
    var metersVisible: Bool
    var recording: Bool
    var calibrationRunning: Bool
    var calibrationValid: Bool
    var calibrateBlock: String?
    var recordingNotices: [String]
    var mismatchedRate: Double?
    var workingSampleRate: Double
}

struct AudioCalibrationSuccess: Codable, Sendable, Equatable {
    var latencyMS: Double
    var latencySamples: Double
    var spreadMS: Double
    var spreadSamples: Double
    var rigDelayMS: Double?
    var correctedTakes: Int
    /// Filas de la hoja del Mac, ya con su texto.
    var rows: [AudioCalibrationRow]
}

struct AudioCalibrationRow: Codable, Sendable, Equatable {
    var label: String
    var value: String
}

struct AudioCalibrationFailure: Codable, Sendable, Equatable {
    /// `noSignal` | `saturated` | `unstable`.
    var reason: String
    var spreadMS: Double
    var title: String
    var hint: String
}

struct AudioCalibrationState: Codable, Sendable, Equatable {
    /// `idle` | `running` | `finished`.
    var phase: String
    var progress: Double? = nil
    /// `success` | `failure` | `error` (solo en `finished`).
    var outcome: String? = nil
    var success: AudioCalibrationSuccess? = nil
    var failure: AudioCalibrationFailure? = nil
    var error: String? = nil
}

struct AudioLevelsEvent: Codable, Sendable, Equatable {
    /// 0...1 por canal de entrada (el Mac pinta 28 pt de alto); vacío = sin sesión.
    var levels: [Float]
    var rmsDB: [Float]
    var peakDB: [Float]
}

struct AudioSetSettingsParams: Decodable, Sendable {
    /// Doble opcional: `nil` = ausente (no se toca), `.some(nil)` = `null` (salida del sistema / sin entrada / sin asignar).
    var outputDeviceUID: String??
    var inputDeviceUID: String??
    var backingOut: AudioChannelPair?
    var guitarIn: [Int]??
    var workingSampleRate: Double?

    enum Keys: String, CodingKey { case outputDeviceUID, inputDeviceUID, backingOut, guitarIn, workingSampleRate }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        func optional<T: Decodable>(_ key: Keys, _ type: T.Type) throws -> T?? {
            guard c.contains(key) else { return nil }
            if try c.decodeNil(forKey: key) { return .some(nil) }
            return .some(try c.decode(T.self, forKey: key))
        }
        outputDeviceUID = try optional(.outputDeviceUID, String.self)
        inputDeviceUID = try optional(.inputDeviceUID, String.self)
        guitarIn = try optional(.guitarIn, [Int].self)
        backingOut = try c.decodeIfPresent(AudioChannelPair.self, forKey: .backingOut)
        workingSampleRate = try c.decodeIfPresent(Double.self, forKey: .workingSampleRate)
    }
}

struct AudioMetersParams: Decodable, Sendable { var visible: Bool }

// MARK: - Servicio

/// Dueño del `AudioController` del núcleo y de sus eventos hacia la página. El controlador se crea al primer uso (hilo principal).
@MainActor
final class AudioService {
    /// Textos de la hoja de calibración (`CalibrationSheet.swift`, estado inicial).
    static let calibrateInstructions = [
        "Conecta con un cable una salida del dispositivo a su entrada de guitarra.",
        "Con una pedalera, carga un rig vacío y baja el volumen de salida: el bucle realimenta (entrada, rig, salida, cable, entrada).",
        "La prueba son 10 pitidos agudos en unos 5 segundos. Mide el retardo de ida y vuelta, que es el desfase que tendrá una toma respecto al backing que se oye."
    ]

    private let options: LaunchOptions
    private let emitRaw: @Sendable (String) -> Void
    /// Cómo se crea el controlador la primera vez (los tests lo sustituyen antes de usarlo).
    var factory: (@MainActor (LaunchOptions) -> AudioController) = AudioService.defaultController
    private(set) var created: AudioController?
    private var statePending = false

    nonisolated init(options: LaunchOptions, emit: @escaping @Sendable (String) -> Void) {
        self.options = options
        self.emitRaw = emit
    }

    /// Simulado en `--audio simulated` (sin tocar el perfil real salvo con `--support-dir`); el real, según la plataforma.
    static func defaultController(_ options: LaunchOptions) -> AudioController {
        let store: ProfileStore?
        if let dir = options.supportDir {
            store = ProfileStore(url: dir.appendingPathComponent("profile.json"))
        } else {
            store = options.audio == .simulated ? nil : ProfileStore()
        }
        if options.audio == .simulated {
            let rate = ((try? store?.load()) ?? EquipmentProfile()).workingSampleRate
            return AudioController(provider: AudioController.simulatedProvider(rate: rate), store: store,
                                   makeIO: AudioController.simulatedIO())
        }
        #if os(Windows)
        return AudioController(provider: WASAPIDeviceProvider(), store: store)
        #elseif canImport(CoreAudio)
        return AudioController(provider: CoreAudioDeviceProvider(), store: store)
        #else
        return AudioController(provider: AudioController.simulatedProvider(), store: store)
        #endif
    }

    /// El controlador (se crea y cablea la primera vez) y ya iniciado.
    func controller() -> AudioController {
        if let created { return created }
        let c = factory(options)
        created = c
        c.onStateChange = { [weak self] in self?.stateChanged() }
        c.onLevels = { [weak self] levels, meters in
            let e = AudioLevelsEvent(levels: levels ?? [], rmsDB: meters.map(\.rmsDB), peakDB: meters.map(\.peakDB))
            self?.emit("audio.levels", e)
        }
        c.onCalibration = { [weak self] _ in
            guard let self, let c = self.created else { return }
            self.emit("audio.calibration", Self.calibrationState(c.calibrationPhase))
        }
        c.onDevicesChanged = { [weak self] in
            guard let self, let c = self.created else { return }
            self.emit("audio.devicesChanged", Self.devicesResult(c))
        }
        c.start()
        return c
    }

    private func emit<T: Encodable>(_ event: String, _ payload: T) {
        if let m = Router.eventMessage(event, payload) { emitRaw(m) }
    }

    /// Coalesce los cambios de un mismo turno en un solo `audio.state`.
    private func stateChanged() {
        guard !statePending else { return }
        statePending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            statePending = false
            if let c = created { emit("audio.state", Self.stateResult(c)) }
        }
    }

    // MARK: Métodos

    nonisolated func register(on router: Router) {
        router.register("audio.devices") { [self] (_: Empty) -> AudioDevicesResult in
            await MainActor.run { Self.devicesResult(self.controller()) }
        }
        router.register("audio.settings") { [self] (_: Empty) -> AudioSettingsResult in
            await MainActor.run { Self.settingsResult(self.controller()) }
        }
        router.register("audio.setSettings") { [self] (p: AudioSetSettingsParams) -> AudioSettingsResult in
            try await setSettings(p)
        }
        router.register("audio.state") { [self] (_: Empty) -> AudioStateResult in
            await MainActor.run { Self.stateResult(self.controller()) }
        }
        router.register("audio.setMeters") { [self] (p: AudioMetersParams) -> AudioStateResult in
            await MainActor.run {
                let c = self.controller()
                c.metersVisible = p.visible
                return Self.stateResult(c)
            }
        }
        router.register("audio.calibrate") { [self] (_: Empty) -> AudioCalibrationState in
            let c = await MainActor.run { self.controller() }
            await c.calibrate()
            return await MainActor.run { Self.calibrationState(c.calibrationPhase) }
        }
        router.register("audio.cancelCalibration") { [self] (_: Empty) -> AudioCalibrationState in
            await MainActor.run {
                let c = self.controller()
                c.cancelCalibration()
                return Self.calibrationState(c.calibrationPhase)
            }
        }
        router.register("audio.dismissCalibration") { [self] (_: Empty) -> AudioCalibrationState in
            await MainActor.run {
                let c = self.controller()
                c.dismissCalibration()
                return Self.calibrationState(c.calibrationPhase)
            }
        }
    }

    private func setSettings(_ p: AudioSetSettingsParams) async throws -> AudioSettingsResult {
        let c = controller()
        if let r = p.workingSampleRate, !EquipmentProfile.allowedSampleRates.contains(r) {
            throw RPCError(code: "bad-params", message: "«workingSampleRate» debe ser 44100 o 48000.")
        }
        if let b = p.backingOut, b.left < 1 || b.right < 1 {
            throw RPCError(code: "bad-params", message: "«backingOut» numera los canales desde 1.")
        }
        do {
            try c.updateAudio(workingRate: p.workingSampleRate) { a in
                if let o = p.outputDeviceUID { a.chooseOutput(o) }
                if let i = p.inputDeviceUID { a.chooseInput(i) }
                if let b = p.backingOut { a.backingOut = ChannelPair(left: b.left, right: b.right) }
                if let g = p.guitarIn { a.guitarIn = g }
            }
        } catch is AudioSettingsError {
            throw RPCError(code: "bad-params", message: RecordBlock.invalidChannels.message)
        } catch {
            throw RPCError(code: "internal", message: "No se pudo guardar el perfil: \(error)")
        }
        return Self.settingsResult(c)
    }

    // MARK: Construcción de resultados

    static func item(_ d: AudioDevice, channels: Int) -> AudioDeviceItem {
        AudioDeviceItem(uid: d.uid, name: d.name, channels: channels, label: "\(d.name) · \(channels) can.", connected: true,
                        rate: d.nominalSampleRate)
    }

    /// Dispositivos conectados con su nº de canales; el elegido que no esté conectado se mantiene como «desconectado»
    /// (`options` de `AudioSettingsView`).
    static func options(_ connected: [AudioDevice], chosen: String?, names: [String: String],
                        channels: (AudioDevice) -> Int) -> [AudioDeviceItem] {
        var result = connected.map { item($0, channels: channels($0)) }
        if let chosen, !connected.contains(where: { $0.uid == chosen }) {
            let name = names[chosen] ?? "Dispositivo elegido"
            result.append(AudioDeviceItem(uid: chosen, name: name, channels: 0, label: "\(name) · desconectado", connected: false,
                                          rate: nil))
        }
        return result
    }

    static func devicesResult(_ c: AudioController) -> AudioDevicesResult {
        let d = c.devices
        return AudioDevicesResult(
            inputs: options(d.inputs, chosen: c.settings?.inputDeviceUID, names: d.names, channels: \.inputChannels),
            outputs: options(d.outputs, chosen: c.settings?.outputDeviceUID, names: d.names, channels: \.outputChannels),
            systemDefault: d.systemDefault.map { item($0, channels: $0.outputChannels) })
    }

    static func number(_ v: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", v).replacingOccurrences(of: ".", with: ",")
    }

    static func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    static func settingsResult(_ c: AudioController) -> AudioSettingsResult {
        let a = c.settings ?? AudioSettings()
        let rate = c.workingRate
        let outChannels = c.chosenOutput?.outputChannels ?? 2
        let inChannels = c.chosenInput?.inputChannels ?? 2
        let calibration: AudioCalibrationInfo
        if let l = c.validCalibration {
            let ms = l.latencySamples / rate * 1000
            calibration = AudioCalibrationInfo(calibrated: true, label: "Calibrada · \(number(ms, 2)) ms · \(dateText(l.date))",
                                               latencyMS: ms, date: l.date)
        } else {
            calibration = AudioCalibrationInfo(calibrated: false, label: "Sin calibrar", latencyMS: nil, date: nil)
        }
        var mismatch: AudioRateMismatch?
        if let m = c.mismatchedRate {
            mismatch = AudioRateMismatch(
                deviceRate: m, workingRate: rate,
                message: "El dispositivo está a \(AudioController.rateText(m)) y la frecuencia de trabajo es \(AudioController.rateText(rate))",
                hint: "Grabar y calibrar quedan bloqueados; el backing suena igual.",
                canUseDeviceRate: EquipmentProfile.allowedSampleRates.contains(m),
                useLabel: "Usar \(AudioController.rateText(m)) como frecuencia de trabajo")
        }
        return AudioSettingsResult(
            outputDeviceUID: a.outputDeviceUID, inputDeviceUID: a.inputDeviceUID,
            backingOut: AudioChannelPair(left: a.backingOut.left, right: a.backingOut.right), guitarIn: a.guitarIn,
            workingSampleRate: rate,
            allowedSampleRates: EquipmentProfile.allowedSampleRates.map { AudioRateOption(rate: $0, label: AudioController.rateText($0)) },
            backingChoices: ChannelChoices.backing(channels: outChannels, current: a).map {
                AudioBackingChoice(label: $0.label, left: $0.value.left, right: $0.value.right)
            },
            guitarChoices: ChannelChoices.guitar(channels: inChannels, current: a).map {
                AudioGuitarChoice(label: $0.label, channels: $0.value)
            },
            rateMismatch: mismatch, calibration: calibration, calibrateBlock: c.deviceBlock?.message,
            calibrateInstructions: calibrateInstructions)
    }

    static func stateResult(_ c: AudioController) -> AudioStateResult {
        AudioStateResult(
            sessionOpen: c.session?.isOpen == true, sessionError: c.sessionError, interruptionNote: c.interruptionNote,
            hostError: c.hostError, hosting: c.session?.isOpen == true && c.isHostingPlayer, metersVisible: c.metersVisible,
            recording: c.isRecording, calibrationRunning: c.calibrationIsRunning, calibrationValid: c.calibrationValid,
            calibrateBlock: c.deviceBlock?.message, recordingNotices: c.takeNotices, mismatchedRate: c.mismatchedRate,
            workingSampleRate: c.workingRate)
    }

    /// Título y qué hacer ante cada fallo (`CalibrationSheet.failure`).
    static func failureTexts(_ f: LatencyFailure, spreadMS: Double) -> (title: String, hint: String) {
        switch f {
        case .noSignal:
            ("No llegó la señal de prueba",
             "Comprueba el cable de una salida del dispositivo a la entrada de guitarra, y que la entrada elegida sea esa. Después repite.")
        case .saturated:
            ("La señal llegó saturada",
             "Baja el volumen de salida del dispositivo (con una pedalera, el del rig o el de la salida) y repite.")
        case .unstable:
            ("Las medidas no coinciden entre sí (dispersión de \(number(spreadMS, 2)) ms)",
             "Carga un rig vacío o sin delay ni reverb, cierra otras apps de audio y repite.")
        }
    }

    static func calibrationState(_ phase: AudioController.CalibrationPhase) -> AudioCalibrationState {
        switch phase {
        case .idle:
            return AudioCalibrationState(phase: "idle")
        case .running(let p):
            return AudioCalibrationState(phase: "running", progress: p)
        case .finished(.error(let message)):
            return AudioCalibrationState(phase: "finished", outcome: "error", error: message)
        case .finished(.failure(let f, let spread)):
            let t = failureTexts(f, spreadMS: spread)
            return AudioCalibrationState(phase: "finished", outcome: "failure",
                                         failure: AudioCalibrationFailure(reason: f.rawValue, spreadMS: spread, title: t.title, hint: t.hint))
        case .finished(.success(let s)):
            var rows = [AudioCalibrationRow(label: "Latencia", value: "\(number(s.latencyMS, 2)) ms · \(number(s.latencySamples, 1)) muestras"),
                        AudioCalibrationRow(label: "Dispersión", value: "\(number(s.spreadMS, 3)) ms · \(number(s.spreadSamples, 1)) muestras")]
            if let rig = s.rigDelayMS {
                rows.append(AudioCalibrationRow(label: "Retardo del rig", value: "\(number(rig, 2)) ms · se corregirá en cada toma"))
            } else {
                rows.append(AudioCalibrationRow(label: "Retardo del rig",
                                                value: "sin canal de referencia: la latencia calibrada vale tal cual"))
            }
            if s.correctedTakes > 0 {
                rows.append(AudioCalibrationRow(label: "Tomas corregidas", value: "\(s.correctedTakes) de este tema, hechas sin calibrar"))
            }
            return AudioCalibrationState(
                phase: "finished", outcome: "success",
                success: AudioCalibrationSuccess(latencyMS: s.latencyMS, latencySamples: s.latencySamples, spreadMS: s.spreadMS,
                                                 spreadSamples: s.spreadSamples, rigDelayMS: s.rigDelayMS,
                                                 correctedTakes: s.correctedTakes, rows: rows))
        }
    }
}

// MARK: - Bridge

extension Bridge {
    /// Registra `audio.*` y engancha el servicio al reproductor de estudio.
    func registerAudioMethods(options: LaunchOptions) {
        let service = AudioService(options: options, emit: { [weak self] in self?.send($0) })
        service.register(on: router)
        studyService.audioService = service
        // B6: al cerrar, corta grabación y calibración en curso (Mac y Windows).
        addShutdownHook { [weak service] in
            guard let s = service else { return }
            await MainActor.run {
                guard let c = s.created else { return }
                if c.isRecording { c.stopRecording() }
                if c.calibrationIsRunning { c.cancelCalibration() }
            }
        }
        // W2-E2: las cámaras de Ajustes las pone `SettingsService.resolvedCameras` (Media Foundation en Windows salvo
        // `--camera simulated`/`--audio simulated`), no aquí.
    }
}
