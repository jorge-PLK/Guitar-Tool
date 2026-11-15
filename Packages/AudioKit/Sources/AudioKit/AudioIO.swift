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
public struct AudioIOBuffer {
    public let sampleTime: Int64
    public let frameCount: Int
    private let pointers: UnsafeBufferPointer<UnsafeMutablePointer<Float>>

    public init(sampleTime: Int64, frameCount: Int, channels: UnsafeBufferPointer<UnsafeMutablePointer<Float>>) {
        self.sampleTime = sampleTime
        self.frameCount = frameCount
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

public enum AudioIOError: Error, Equatable, Sendable {
    case alreadyRunning
    case noInput
    case device(String)
    /// Dispositivo no encontrado o no conectado (UID).
    case notConnected(String)
    /// El dispositivo no aceptó la frecuencia de trabajo (mini-spec Fase 3, «Frecuencia»).
    case sampleRateMismatch(device: Double, requested: Double)
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
}

public extension AudioIO {
    var diagnostics: AudioIODiagnostics? { nil }
}
