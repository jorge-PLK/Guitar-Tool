import Foundation

/// Par de canales (numerados desde 1) de una salida estéreo.
public struct ChannelPair: Codable, Sendable, Equatable {
    public var left: Int
    public var right: Int

    public init(left: Int = 1, right: Int = 2) {
        self.left = left
        self.right = right
    }

    public static let `default` = ChannelPair(left: 1, right: 2)
}

/// Clave de una calibración de latencia (mini-spec Fase 3, «Calibración de latencia»): la calibración vale
/// mientras no cambie ningún campo. Los UID vacíos son «salida/entrada por defecto del sistema».
public struct CalibrationKey: Codable, Sendable, Equatable, Hashable {
    public var inputUID: String
    public var outputUID: String
    public var sampleRate: Double
    public var bufferFrames: Int
    /// Canal de entrada medido (el primero de `guitarIn`), desde 1.
    public var inputChannel: Int
    /// Canal de salida por el que salió el barrido (el izquierdo de `backingOut`), desde 1.
    public var outputChannel: Int

    public init(inputUID: String, outputUID: String, sampleRate: Double, bufferFrames: Int,
                inputChannel: Int, outputChannel: Int) {
        self.inputUID = inputUID
        self.outputUID = outputUID
        self.sampleRate = sampleRate
        self.bufferFrames = bufferFrames
        self.inputChannel = inputChannel
        self.outputChannel = outputChannel
    }
}

/// Canal de referencia interno: llega antes que `guitarIn` porque no pasa por el rig. Lo encuentra la
/// calibración; no se enseña ni se graba.
public struct ReferenceChannel: Codable, Sendable, Equatable {
    /// Canal de entrada, desde 1.
    public var channel: Int
    /// Latencia de salida a ese canal, en muestras con decimales.
    public var latencySamples: Double

    public init(channel: Int, latencySamples: Double) {
        self.channel = channel
        self.latencySamples = latencySamples
    }
}

/// Última calibración de latencia.
public struct LatencyCalibration: Codable, Sendable, Equatable {
    /// Latencia de ida y vuelta hasta `guitarIn`, en muestras con decimales (mediana).
    public var latencySamples: Double
    /// Dispersión de las medidas (máximo menos mínimo), en muestras.
    public var spreadSamples: Double
    public var date: Date
    public var key: CalibrationKey
    public var referenceIn: ReferenceChannel?

    public init(latencySamples: Double, spreadSamples: Double, date: Date = Date(), key: CalibrationKey,
                referenceIn: ReferenceChannel? = nil) {
        self.latencySamples = latencySamples
        self.spreadSamples = spreadSamples
        self.date = date
        self.key = key
        self.referenceIn = referenceIn
    }
}

public enum AudioSettingsError: Error, Equatable, Sendable {
    /// El par de backing repite canal o tiene un número menor que 1.
    case invalidBackingPair
    /// `guitarIn` no tiene uno o dos canales distintos y válidos.
    case invalidGuitarChannels
    /// El canal de referencia coincide con un canal de `guitarIn`.
    case referenceOverlapsGuitar
}

/// Audio del perfil de equipo (mini-spec Fase 3, «Dispositivo y canales»). Los UID vacíos (nil) son
/// «salida por defecto del sistema» y «sin entrada». Store no depende de AudioKit: son datos.
public struct AudioSettings: Codable, Sendable, Equatable {
    /// Búfer fijo, el probado en el soak de P2; no se enseña.
    public static let defaultBufferFrames = 512

    public var outputDeviceUID: String?
    public var inputDeviceUID: String?
    public var backingOut: ChannelPair
    /// Uno o dos canales de entrada con la guitarra tal como suena (señal procesada); nil = sin asignar.
    public var guitarIn: [Int]?
    public var bufferFrames: Int
    public var latency: LatencyCalibration?

    public init(outputDeviceUID: String? = nil, inputDeviceUID: String? = nil, backingOut: ChannelPair = .default,
                guitarIn: [Int]? = nil, bufferFrames: Int = AudioSettings.defaultBufferFrames,
                latency: LatencyCalibration? = nil) {
        self.outputDeviceUID = outputDeviceUID
        self.inputDeviceUID = inputDeviceUID
        self.backingOut = backingOut
        self.guitarIn = guitarIn
        self.bufferFrames = bufferFrames
        self.latency = latency
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(outputDeviceUID: try c.decodeIfPresent(String.self, forKey: .outputDeviceUID),
                  inputDeviceUID: try c.decodeIfPresent(String.self, forKey: .inputDeviceUID),
                  backingOut: try c.decodeIfPresent(ChannelPair.self, forKey: .backingOut) ?? .default,
                  guitarIn: try c.decodeIfPresent([Int].self, forKey: .guitarIn),
                  bufferFrames: try c.decodeIfPresent(Int.self, forKey: .bufferFrames) ?? Self.defaultBufferFrames,
                  latency: try c.decodeIfPresent(LatencyCalibration.self, forKey: .latency))
    }

    /// Un canal no puede tener dos papeles: el par de backing son dos canales de salida distintos; la
    /// guitarra, uno o dos de entrada distintos; y el canal de referencia de la calibración no es de la guitarra.
    public func validate() throws {
        guard backingOut.left >= 1, backingOut.right >= 1, backingOut.left != backingOut.right else {
            throw AudioSettingsError.invalidBackingPair
        }
        if let g = guitarIn {
            guard (1...2).contains(g.count), g.allSatisfy({ $0 >= 1 }), Set(g).count == g.count else {
                throw AudioSettingsError.invalidGuitarChannels
            }
            if let ref = latency?.referenceIn, g.contains(ref.channel) { throw AudioSettingsError.referenceOverlapsGuitar }
        }
    }

    public var isValid: Bool { (try? validate()) != nil }

    /// Se puede grabar si hay entrada y canal de guitarra (y la configuración es válida).
    public var canRecord: Bool { inputDeviceUID != nil && guitarIn != nil && isValid }

    /// Clave con la que se calibraría ahora mismo; nil sin canal de guitarra.
    public func calibrationKey(sampleRate: Double) -> CalibrationKey? {
        guard let first = guitarIn?.first else { return nil }
        return CalibrationKey(inputUID: inputDeviceUID ?? "", outputUID: outputDeviceUID ?? "", sampleRate: sampleRate,
                              bufferFrames: bufferFrames, inputChannel: first, outputChannel: backingOut.left)
    }

    /// La calibración guardada, si su clave sigue siendo la de la configuración actual.
    public func validLatency(sampleRate: Double) -> LatencyCalibration? {
        guard let latency, latency.key == calibrationKey(sampleRate: sampleRate) else { return nil }
        return latency
    }

    /// Al elegir un dispositivo, el backing queda en 1 y 2 y los demás papeles sin asignar.
    public mutating func chooseOutput(_ uid: String?) {
        outputDeviceUID = uid
        backingOut = .default
    }

    public mutating func chooseInput(_ uid: String?) {
        inputDeviceUID = uid
        guitarIn = nil
    }
}

/// Reloj con el que se grabó una toma: un solo dispositivo o el agregado privado con corrección de deriva.
public enum ClockMode: String, Codable, Sendable, Equatable {
    case single, aggregate
}
