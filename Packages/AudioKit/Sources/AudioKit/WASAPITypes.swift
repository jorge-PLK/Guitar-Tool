import Foundation

// Tipos públicos de la E/S WASAPI (plan, «Corte del paso 7», parte 7.10) sin tipos de Windows: el listado de
// dispositivos que pinta `tf-audio`, el cálculo de periodos y qué hacer con cada aviso del shim. Portátiles para
// probarlos en el Mac; los rellena `WASAPIAudioIO` (solo Windows) desde `CWASAPI`.

/// Modo de compartición del flujo (plan, «Fase 7c», «Audio»: IAudioClient3 compartido o exclusivo).
public enum WASAPIShareMode: String, Sendable, Codable, CaseIterable {
    /// `IAudioClient3::InitializeSharedAudioStream` con el periodo del motor más cercano al pedido; si no se puede,
    /// `IAudioClient::Initialize` compartido con el periodo por defecto.
    case shared
    /// `IAudioClient::Initialize` exclusivo con el periodo pedido (o el mínimo del dispositivo).
    case exclusive
}

/// Lo que una sesión WASAPI añade a la clave de calibración (paso 8, F2): el modo con el que quedó abierta y el
/// contenedor (aparato físico) de cada endpoint. `AudioIO.wasapiIdentity`; nil en CoreAudio.
public struct WASAPIIdentity: Sendable, Equatable, Hashable {
    public var mode: WASAPIShareMode
    public var inputContainer: String?
    public var outputContainer: String?

    public init(mode: WASAPIShareMode, inputContainer: String? = nil, outputContainer: String? = nil) {
        self.mode = mode
        self.inputContainer = inputContainer
        self.outputContainer = outputContainer
    }
}

/// Sentido de un endpoint.
public enum WASAPIFlow: String, Sendable, Codable {
    case render
    case capture
}

/// Cómo quedó inicializado cada lado (`WASAPI_PATH_*` de CWASAPI.h, mismos valores).
public enum WASAPIStreamPath: Int32, Sendable, Codable {
    case none = 0
    /// `IAudioClient3::InitializeSharedAudioStream` (periodo del motor).
    case client3Shared = 1
    /// `IAudioClient::Initialize` compartido (periodo por defecto del motor, 10 ms típicos).
    case clientShared = 2
    /// Compartido con AUTOCONVERTPCM: el motor de Windows remuestrea (el endpoint está a otra frecuencia).
    case autoconvert = 3
    case exclusive = 4

    public var label: String {
        switch self {
        case .none: return "ninguno"
        case .client3Shared: return "compartido (IAudioClient3)"
        case .clientShared: return "compartido (IAudioClient)"
        case .autoconvert: return "compartido remuestreado (AUTOCONVERTPCM)"
        case .exclusive: return "exclusivo"
        }
    }
}

/// Formato de un endpoint o de un lado del flujo.
public struct WASAPIFormat: Sendable, Equatable, Codable {
    public var sampleRate: Double
    public var channels: Int
    /// Bits del contenedor y válidos.
    public var bits: Int
    public var validBits: Int
    public var isFloat: Bool

    public init(sampleRate: Double, channels: Int, bits: Int, validBits: Int, isFloat: Bool) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.bits = bits
        self.validBits = validBits
        self.isFloat = isFloat
    }

    /// «48000 Hz · 2 ch · float32» o «48000 Hz · 2 ch · int24/32».
    public var label: String {
        let kind = isFloat ? "float\(bits)" : (validBits == bits ? "int\(bits)" : "int\(validBits)/\(bits)")
        return "\(Int(sampleRate.rounded())) Hz · \(channels) ch · \(kind)"
    }
}

/// Periodos del motor compartido de `IAudioClient3::GetSharedModeEnginePeriod`, en fotogramas.
public struct WASAPIEnginePeriods: Sendable, Equatable, Codable {
    public var defaultFrames: Int
    public var fundamentalFrames: Int
    public var minimumFrames: Int
    public var maximumFrames: Int

    public init(defaultFrames: Int, fundamentalFrames: Int, minimumFrames: Int, maximumFrames: Int) {
        self.defaultFrames = defaultFrames
        self.fundamentalFrames = fundamentalFrames
        self.minimumFrames = minimumFrames
        self.maximumFrames = maximumFrames
    }

    /// Periodo que concede `CWASAPI` (`init_shared`) al pedir `requested` fotogramas (0 = el mínimo): se acota a
    /// [mínimo, máximo] y se sube al siguiente múltiplo del paso contado desde el mínimo, sin pasar del máximo.
    public func granted(requested: Int) -> Int {
        guard requested > 0, fundamentalFrames > 0 else { return minimumFrames }
        let p = min(max(requested, minimumFrames), maximumFrames)
        let up = minimumFrames + (p - minimumFrames + fundamentalFrames - 1) / fundamentalFrames * fundamentalFrames
        return min(up, maximumFrames)
    }
}

/// Conversión entre `REFERENCE_TIME` (100 ns) y fotogramas, redondeando como `CWASAPI` (`hns_to_frames`, `frames_to_hns`).
public enum WASAPIPeriod {
    public static func frames(hundredNanoseconds t: Int64, sampleRate: Double) -> Int {
        Int((Double(t) * sampleRate / 1e7 + 0.5).rounded(.down))
    }

    public static func hundredNanoseconds(frames: Int, sampleRate: Double) -> Int64 {
        guard sampleRate > 0 else { return 0 }
        return Int64((1e7 * Double(frames) / sampleRate + 0.5).rounded(.down))
    }

    public static func milliseconds(frames: Int, sampleRate: Double) -> Double {
        sampleRate > 0 ? Double(frames) / sampleRate * 1000 : 0
    }
}

/// Driver del adaptador de un endpoint (nodo PnP del filtro KS al que está conectado; `wasapi_enumerate`).
public struct WASAPIDriverInfo: Sendable, Equatable, Codable {
    /// Id de instancia PnP del adaptador: «USB\VID_xxxx&PID_yyyy&MI_00\...». Entrada y salida del mismo aparato USB
    /// suelen compartirlo.
    public var adapterInstance: String
    public var adapterName: String
    /// Servicio del driver: «usbaudio2» y «usbaudio» son los genéricos de clase USB Audio de Windows.
    public var service: String
    public var provider: String
    public var version: String
    public var description: String
    /// INF instalado: «usbaudio2.inf», «wdma_usb.inf» (genéricos) u «oemNN.inf» (de un fabricante).
    public var infPath: String
    /// 0, el HRESULT del paso de topología que falló, o 0x80000000 | CONFIGRET de cfgmgr32.
    public var hresult: Int32

    public init(adapterInstance: String = "", adapterName: String = "", service: String = "", provider: String = "",
                version: String = "", description: String = "", infPath: String = "", hresult: Int32 = 0) {
        self.adapterInstance = adapterInstance
        self.adapterName = adapterName
        self.service = service
        self.provider = provider
        self.version = version
        self.description = description
        self.infPath = infPath
        self.hresult = hresult
    }

    /// Qué clase de driver es, para decidir de un vistazo si el aparato va con el suyo o con el genérico.
    public enum Kind: Sendable, Equatable {
        /// Clase USB Audio de Windows (`usbaudio2.sys`, UAC 2.0).
        case usbAudio2Generic
        /// Clase USB Audio 1.0 de Windows (`usbaudio.sys`).
        case usbAudio1Generic
        /// Otro driver de Microsoft (HD Audio, Bluetooth…).
        case microsoft
        /// De un fabricante.
        case vendor
        case unknown
    }

    public var kind: Kind {
        switch service.lowercased() {
        case "usbaudio2": return .usbAudio2Generic
        case "usbaudio": return .usbAudio1Generic
        default: break
        }
        if provider.lowercased().contains("microsoft") { return .microsoft }
        if !provider.isEmpty || !service.isEmpty || !infPath.isEmpty { return .vendor }
        return .unknown
    }
}

/// Endpoint de audio activo, tal como lo da `wasapi_enumerate` (el listado de `tf-audio`).
public struct WASAPIDeviceInfo: Sendable, Equatable, Codable, Identifiable {
    /// Id del endpoint: estable entre arranques; es el UID de `AudioSetup` y de la clave de calibración.
    public var id: String
    /// Nombre amigable de Windows: «Altavoces (High Definition Audio Device)»; entre paréntesis, el adaptador.
    public var name: String
    public var flow: WASAPIFlow
    /// Es el de consola por defecto de su sentido.
    public var isDefault: Bool
    /// Formato de mezcla del motor (el del modo compartido).
    public var mix: WASAPIFormat
    /// `IAudioClient::GetDevicePeriod`: por defecto (compartido) y mínimo (exclusivo), en 100 ns.
    public var defaultPeriod100ns: Int64
    public var minimumPeriod100ns: Int64
    /// `nil` = el endpoint no da `IAudioClient3` (compartido a periodo por defecto).
    public var engine: WASAPIEnginePeriods?
    /// `IsFormatSupported(EXCLUSIVE)` con float32 al formato de mezcla (si no, el shim prueba enteros).
    public var exclusiveFloat: Bool
    /// 0 o el primer HRESULT de error al consultar el endpoint.
    public var hresult: Int32
    /// Driver del adaptador (parte 7.10b); vacío si el endpoint no tiene adaptador físico o la consulta falló.
    public var driver: WASAPIDriverInfo
    /// `PKEY_Device_ContainerId` del endpoint, «{XXXXXXXX-…}» (paso 8, F2): todos los endpoints del mismo aparato físico
    /// comparten contenedor. nil si Windows no lo da. Los integrados en el PC comparten el contenedor del propio equipo.
    public var containerID: String?

    public init(id: String, name: String, flow: WASAPIFlow, isDefault: Bool, mix: WASAPIFormat,
                defaultPeriod100ns: Int64, minimumPeriod100ns: Int64, engine: WASAPIEnginePeriods?,
                exclusiveFloat: Bool, hresult: Int32 = 0, driver: WASAPIDriverInfo = WASAPIDriverInfo(),
                containerID: String? = nil) {
        self.driver = driver
        self.containerID = containerID
        self.id = id
        self.name = name
        self.flow = flow
        self.isDefault = isDefault
        self.mix = mix
        self.defaultPeriod100ns = defaultPeriod100ns
        self.minimumPeriod100ns = minimumPeriod100ns
        self.engine = engine
        self.exclusiveFloat = exclusiveFloat
        self.hresult = hresult
    }

    /// Camino por el que abriría el modo compartido a la frecuencia de mezcla.
    public var sharedPath: WASAPIStreamPath { engine != nil ? .client3Shared : .clientShared }

    /// Periodo mínimo en compartido, en fotogramas a la frecuencia de mezcla: el mínimo del motor con IAudioClient3; sin
    /// él, el periodo por defecto (IAudioClient compartido no baja de ahí).
    public var minimumSharedPeriodFrames: Int {
        engine?.minimumFrames ?? WASAPIPeriod.frames(hundredNanoseconds: defaultPeriod100ns, sampleRate: mix.sampleRate)
    }

    /// Periodo mínimo en exclusivo, en fotogramas a la frecuencia de mezcla.
    public var minimumExclusivePeriodFrames: Int {
        WASAPIPeriod.frames(hundredNanoseconds: minimumPeriod100ns, sampleRate: mix.sampleRate)
    }

    /// Periodo que concedería el modo compartido a la frecuencia de mezcla al pedir `requested` (0 = el mínimo).
    public func sharedPeriodFrames(requested: Int) -> Int {
        engine?.granted(requested: requested)
            ?? WASAPIPeriod.frames(hundredNanoseconds: defaultPeriod100ns, sampleRate: mix.sampleRate)
    }
}

/// Lo que quedó abierto de un `WASAPIAudioIO` (copia de `wasapi_stream_info`).
public struct WASAPIStreamInfo: Sendable, Equatable {
    public var mode: WASAPIShareMode
    public var renderPath: WASAPIStreamPath
    public var capturePath: WASAPIStreamPath
    /// Formato del dispositivo de cada lado (las muestras pasan como float32; la conversión la hace el shim).
    public var renderFormat: WASAPIFormat?
    public var captureFormat: WASAPIFormat?
    /// `GetBufferSize` y periodo concedido, en fotogramas.
    public var renderBufferFrames: Int
    public var captureBufferFrames: Int
    public var renderPeriodFrames: Int
    public var capturePeriodFrames: Int
    /// `GetStreamLatency` en 100 ns.
    public var renderLatency100ns: Int64
    public var captureLatency100ns: Int64
    /// Frecuencia del endpoint de captura (≠ la del flujo con AUTOCONVERTPCM).
    public var captureDeviceRate: Double
    public var renderName: String
    public var captureName: String

    public init(mode: WASAPIShareMode, renderPath: WASAPIStreamPath, capturePath: WASAPIStreamPath,
                renderFormat: WASAPIFormat?, captureFormat: WASAPIFormat?, renderBufferFrames: Int, captureBufferFrames: Int,
                renderPeriodFrames: Int, capturePeriodFrames: Int, renderLatency100ns: Int64, captureLatency100ns: Int64,
                captureDeviceRate: Double, renderName: String, captureName: String) {
        self.mode = mode
        self.renderPath = renderPath
        self.capturePath = capturePath
        self.renderFormat = renderFormat
        self.captureFormat = captureFormat
        self.renderBufferFrames = renderBufferFrames
        self.captureBufferFrames = captureBufferFrames
        self.renderPeriodFrames = renderPeriodFrames
        self.capturePeriodFrames = capturePeriodFrames
        self.renderLatency100ns = renderLatency100ns
        self.captureLatency100ns = captureLatency100ns
        self.captureDeviceRate = captureDeviceRate
        self.renderName = renderName
        self.captureName = captureName
    }

    /// Latencia de flujo declarada de ida y vuelta en muestras a `sampleRate` (como en el HAL, solo vale sin calibración).
    public func declaredLatencySamples(sampleRate: Double) -> Double {
        Double(renderLatency100ns + captureLatency100ns) * sampleRate / 1e7
    }
}

/// Contadores del hilo de audio del shim tras parar (copia de `wasapi_stream_status`).
public struct WASAPIStreamStatus: Sendable, Equatable {
    public var mmcss: Bool
    public var lastHResult: Int32
    /// 0 = parada pedida, o el `WASAPIEvent` que la paró.
    public var stopReason: Int32
    public var renderBuffers: Int
    public var renderStarved: Int
    public var capturePackets: Int
    public var wakeups: Int
    public var clockFailures: Int
    /// Fotogramas de captura descartados mientras se fijaba el offset de `DuplexClockSync`.
    public var droppedCaptureFrames: Int
    /// Discontinuidades de captura tras el primer paquete.
    public var captureResets: Int
    /// Deriva captura-salida (`DuplexClockSync.driftPPM`) y offset fijado (muestras), si los hubo.
    public var driftPPM: Double?
    public var captureOffset: Int64?

    public init(mmcss: Bool = false, lastHResult: Int32 = 0, stopReason: Int32 = 0, renderBuffers: Int = 0,
                renderStarved: Int = 0, capturePackets: Int = 0, wakeups: Int = 0, clockFailures: Int = 0,
                droppedCaptureFrames: Int = 0, captureResets: Int = 0, driftPPM: Double? = nil, captureOffset: Int64? = nil) {
        self.mmcss = mmcss
        self.lastHResult = lastHResult
        self.stopReason = stopReason
        self.renderBuffers = renderBuffers
        self.renderStarved = renderStarved
        self.capturePackets = capturePackets
        self.wakeups = wakeups
        self.clockFailures = clockFailures
        self.droppedCaptureFrames = droppedCaptureFrames
        self.captureResets = captureResets
        self.driftPPM = driftPPM
        self.captureOffset = captureOffset
    }
}

/// Avisos del shim (`WASAPI_EVENT_*` de CWASAPI.h, mismos valores).
enum WASAPIEvent: Int32, Sendable {
    case defaultChanged = 1
    case deviceRemoved = 2
    case deviceInvalidated = 3
    case streamError = 4
    case stalled = 5
    case formatChanged = 6

    /// Qué hace la sesión con un aviso.
    enum Action: Sendable, Equatable {
        case ignore
        case interrupt(AudioIOInterruption)
        /// Releer la frecuencia de mezcla del endpoint `uid` y cortar si ya no es la de trabajo.
        case checkRate(uid: String, flow: WASAPIFlow)
    }

    /// Regla (contrato de `AudioIO`, como `CoreAudioIO`): desconexión de un endpoint de la sesión o flujo muerto →
    /// `.disconnected`; cambio de formato de uno de los dos → mirar la frecuencia; cambio de dispositivo por defecto
    /// → nada (la sesión sigue con los endpoints que resolvió al abrir, como el HAL). `AudioIOInterruption` solo tiene
    /// desconexión y frecuencia: un flujo colgado o con error se da por desconectado.
    static func action(kind: Int32, flow: Int32, deviceID: String?, inputUID: String, outputUID: String) -> Action {
        guard let event = WASAPIEvent(rawValue: kind) else { return .ignore }
        let side: String = flow == 1 && !inputUID.isEmpty ? inputUID : (outputUID.isEmpty ? inputUID : outputUID)
        switch event {
        case .defaultChanged:
            return .ignore
        case .deviceRemoved:
            guard let id = deviceID else { return .ignore }
            if id == outputUID, !id.isEmpty { return .interrupt(.disconnected(outputUID)) }
            if id == inputUID, !id.isEmpty { return .interrupt(.disconnected(inputUID)) }
            return .ignore
        case .deviceInvalidated, .streamError, .stalled:
            return .interrupt(.disconnected(side))
        case .formatChanged:
            guard let id = deviceID else { return .ignore }
            if id == outputUID, !id.isEmpty { return .checkRate(uid: id, flow: .render) }
            if id == inputUID, !id.isEmpty { return .checkRate(uid: id, flow: .capture) }
            return .ignore
        }
    }
}

/// Regla de frecuencia al abrir en compartido (mini-spec Fase 3, «Frecuencia»: el dispositivo trabaja a la frecuencia
/// del proyecto o se avisa). En compartido no se puede cambiar la frecuencia de mezcla desde la app (solo desde el panel
/// de sonido de Windows): la salida, que es el reloj maestro de la línea común, tiene que estar ya a la frecuencia de
/// trabajo. La entrada también (decisión por defecto del hilo principal, parte 7.10b; Jorge puede revertirla): con
/// AUTOCONVERTPCM el remuestreo de Windows mete un retardo que no se mide. Solo para tests y diagnóstico,
/// `WASAPIAudioIO.Options.allowInputResampling` la admite a otra frecuencia (el shim y P8 lo cubren: `stream_position`).
enum WASAPIRateRule {
    /// `nil` = vale; si no, la frecuencia del dispositivo para `AudioIOError.sampleRateMismatch`.
    static func mismatch(mode: WASAPIShareMode, renderMixRate: Double?, working: Double) -> Double? {
        guard mode == .shared, let r = renderMixRate, abs(r - working) >= 0.5 else { return nil }
        return r
    }

    /// Lo mismo para la entrada: en compartido tiene que estar a la frecuencia de trabajo salvo `allowResampling`.
    static func inputMismatch(mode: WASAPIShareMode, captureMixRate: Double?, working: Double,
                              allowResampling: Bool) -> Double? {
        allowResampling ? nil : mismatch(mode: mode, renderMixRate: captureMixRate, working: working)
    }
}
