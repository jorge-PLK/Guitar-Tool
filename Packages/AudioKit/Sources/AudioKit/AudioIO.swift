import Foundation

// MARK: - Sesión dúplex detrás de la que queda el hardware (mini-spec Fase 3, «Código»)

/// Formato de una sesión de `AudioIO`.
public struct AudioIOFormat: Sendable, Equatable {
    public var sampleRate: Double
    public var inputChannels: Int
    public var outputChannels: Int
    /// Tamaño de bloque pedido al dispositivo (512 fijo en esta fase). Los bloques entregados pueden ser
    /// de otro tamaño: nadie debe suponer `frameCount == bufferFrames`.
    public var bufferFrames: Int

    public init(sampleRate: Double, inputChannels: Int, outputChannels: Int, bufferFrames: Int = 512) {
        self.sampleRate = sampleRate
        self.inputChannels = inputChannels
        self.outputChannels = outputChannels
        self.bufferFrames = bufferFrames
    }
}

/// Con qué reloj se abrió la sesión (mini-spec Fase 3, «Dispositivo y canales»): un solo dispositivo o un
/// agregado privado con la salida como maestro y corrección de deriva en la entrada.
public enum AudioIOClock: String, Sendable, Equatable, Codable {
    case single
    case aggregate
}

/// Bloque no entrelazado de una sesión. Los punteros solo valen durante la llamada al manejador.
///
/// `sampleTime` es la posición de la primera muestra en la **línea de tiempo común** de la sesión (el
/// reloj maestro, en muestras). Salida y entrada se marcan en esa misma línea: si una señal sale en la
/// muestra `y` y vuelve por la entrada en la muestra `n`, la latencia de ida y vuelta es `n − y`. Es lo
/// que mide `LatencyCalibrator` y lo que estima `AudioIO.declaredLatencySamples`.
///
/// `hostSeconds` es el instante de host de esa primera muestra (mini-spec Fase 6, «Cámara y sincronía»), en
/// segundos de `HostClock` (`mach_absolute_time` en el Mac, la escala de `CoreAudioIO.hostNowSeconds` y del reloj de
/// host de CoreMedia; QPC en Windows): en `CoreAudioIO`, el `mHostTime` del HAL; en `WASAPIAudioIO` (paso 7), el
/// QPC de `DuplexClockSync`; en `SimulatedAudioIO`, el de su reloj simulado. 0 = el
/// dispositivo no dio marca válida. El de la muestra `sampleTime + i` es `hostSeconds + i / frecuencia` salvo
/// la deriva del reloj del dispositivo frente al de host (de ahí que `HostTimeMap` ajuste una recta).
public struct AudioIOBuffer {
    public let sampleTime: Int64
    public let frameCount: Int
    public let hostSeconds: Double
    private let pointers: UnsafeBufferPointer<UnsafeMutablePointer<Float>>

    public init(sampleTime: Int64, frameCount: Int, channels: UnsafeBufferPointer<UnsafeMutablePointer<Float>>,
                hostSeconds: Double = 0) {
        self.sampleTime = sampleTime
        self.frameCount = frameCount
        self.hostSeconds = hostSeconds
        pointers = channels
    }

    public var channelCount: Int { pointers.count }

    /// Canal `index` (desde 0, índice del dispositivo).
    public subscript(index: Int) -> UnsafeMutableBufferPointer<Float> {
        UnsafeMutableBufferPointer(start: pointers[index], count: frameCount)
    }
}

/// Rellena un bloque de salida. Llega a cero; lo que no se escriba sale en silencio.
public typealias AudioIORenderHandler = @Sendable (AudioIOBuffer) -> Void
/// Recibe un bloque de entrada (todos los canales del dispositivo de entrada).
public typealias AudioIOCaptureHandler = @Sendable (AudioIOBuffer) -> Void

public enum AudioIOError: Error, Equatable, Sendable, LocalizedError {
    case alreadyRunning
    case noInput
    case device(String)
    /// Dispositivo no encontrado o no conectado (UID).
    case notConnected(String)
    /// El dispositivo no aceptó la frecuencia de trabajo (mini-spec Fase 3, «Frecuencia»).
    case sampleRateMismatch(device: Double, requested: Double)

    /// Texto para el usuario: nunca lleva el UID ni el nombre del caso.
    public var errorDescription: String? {
        func khz(_ x: Double) -> String {
            String(format: x.truncatingRemainder(dividingBy: 1000) == 0 ? "%.0f" : "%.1f", x / 1000)
                .replacingOccurrences(of: ".", with: ",")
        }
        switch self {
        case .alreadyRunning: return "El dispositivo ya está en uso."
        case .noInput: return "No hay dispositivo de entrada elegido."
        case .device(let s): return "Error del dispositivo: \(s)."
        case .notConnected: return "El dispositivo no está conectado."
        case let .sampleRateMismatch(device, requested):
            return "El dispositivo está a \(khz(device)) kHz y la frecuencia de trabajo es \(khz(requested)) kHz."
        }
    }
}

/// Por qué se cortó una sesión en marcha. Se avisa en cualquier hilo (nunca en el de E/S); la sesión ya
/// no llama a los manejadores después de avisar.
public enum AudioIOInterruption: Sendable, Equatable {
    /// Se desconectó un dispositivo de la sesión (UID).
    case disconnected(String)
    /// Alguien cambió la frecuencia del dispositivo (p. ej. desde su menú).
    case sampleRateChanged(Double)
}

/// Sesión dúplex sobre uno o dos dispositivos (mini-spec Fase 3, «Código»). La versión real
/// (`CoreAudioIO`, parte 2) incluye el agregado privado; `SimulatedAudioIO` devuelve la salida por la entrada.
///
/// Contrato:
/// - `start` abre la sesión y empieza a llamar a los manejadores en el hilo de E/S (tiempo real en la
///   versión real; no deben bloquear ni reservar memoria). `render` se llama con bloques consecutivos de
///   salida y `capture` con bloques consecutivos de entrada, ambos con `sampleTime` en la línea común.
///   El orden relativo de las dos llamadas dentro de un ciclo no está garantizado.
/// - `stop` deja de llamar a los manejadores antes de volver (salvo si se llama desde uno de ellos).
/// - La línea de tiempo es monótona durante la vida del objeto; entre `stop` y `start` puede saltar.
public protocol AudioIO: AnyObject, Sendable {
    var format: AudioIOFormat { get }
    /// UID del dispositivo de entrada y de salida (para la clave de calibración). Nada mira el nombre.
    var inputDeviceUID: String { get }
    var outputDeviceUID: String { get }
    var clock: AudioIOClock { get }
    /// Latencia de ida y vuelta que declara el dispositivo, en muestras: lo que se usa sin calibración
    /// válida (poco fiable: en P2 declaraba 25 ms y eran 50).
    var declaredLatencySamples: Double { get }
    var isRunning: Bool { get }

    func start(render: @escaping AudioIORenderHandler, capture: @escaping AudioIOCaptureHandler) throws
    func stop()
    /// Aviso de corte (desconexión, cambio de frecuencia). Al avisar, la sesión ya está parada.
    func setInterruptionHandler(_ handler: (@Sendable (AudioIOInterruption) -> Void)?)
    /// Contadores del ciclo de E/S para diagnóstico (`nil` si el dispositivo no los da).
    var diagnostics: AudioIODiagnostics? { get }
    /// Solo WASAPI (paso 8, F2): modo y contenedores para la clave de calibración. nil (CoreAudio) = clave del Mac.
    var wasapiIdentity: WASAPIIdentity? { get }
}

public extension AudioIO {
    var diagnostics: AudioIODiagnostics? { nil }
    var wasapiIdentity: WASAPIIdentity? { nil }
}

/// Instante de host de una muestra de salida de la línea común (mini-spec Fase 6, «Cámara y sincronía»): lo
/// que `AudioSession.outputHostClock` publica de cada ciclo y lo que necesita `HostTimeMap` (VideoKit) para
/// pasar del reloj de host al tiempo del tema junto con el `PlaybackAnchor`.
public struct HostClockPoint: Sendable, Equatable {
    /// Muestra de salida en la línea común de la sesión.
    public var sampleTime: Int64
    /// Segundos de host (`HostClock`) de esa muestra.
    public var hostSeconds: Double

    public init(sampleTime: Int64, hostSeconds: Double) {
        self.sampleTime = sampleTime
        self.hostSeconds = hostSeconds
    }
}
