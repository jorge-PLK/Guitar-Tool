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
    /// Backing mono por el canal 1 (`left == right`): lo que se ofrece en una salida de un solo canal.
    public static let mono = ChannelPair(left: 1, right: 1)
    public var isMono: Bool { left == right }
}

/// Clave de una calibración de latencia (mini-spec Fase 3, «Calibración de latencia»): la calibración vale
/// mientras no cambie ningún campo. Los UID vacíos son «salida/entrada por defecto del sistema».
///
/// Windows (paso 8, F2): `inputUID`/`outputUID` son la identidad del APARATO (el contenedor del endpoint WASAPI,
/// `PKEY_Device_ContainerId`; sin contenedor, el id del endpoint), así que la entrada y la salida de la misma pedalera
/// dan el mismo UID, como en el Mac. El camino concreto va en `wasapi`: modo (compartido/exclusivo) y los dos endpoints.
/// En el Mac `wasapi` es nil y no se escribe: la clave codificada es byte a byte la de siempre.
public struct CalibrationKey: Codable, Sendable, Equatable, Hashable {
    public var inputUID: String
    public var outputUID: String
    public var sampleRate: Double
    public var bufferFrames: Int
    /// Canal de entrada medido (el primero de `guitarIn`), desde 1.
    public var inputChannel: Int
    /// Canal de salida por el que salió el barrido (el izquierdo de `backingOut`), desde 1.
    public var outputChannel: Int
    /// Solo Windows: modo y endpoints concretos (nil en el Mac; no se codifica).
    public var wasapi: WASAPIPath?

    /// Lo que la clave de Windows añade a la del Mac. Los endpoints se guardan aunque el UID sea el contenedor: dos
    /// endpoints del mismo aparato pueden ser caminos de señal distintos (otro par de canales, otro flujo USB con su
    /// propio búfer) y nada en WASAPI dice si comparten latencia; así una calibración nunca vale para otro endpoint.
    public struct WASAPIPath: Codable, Sendable, Equatable, Hashable {
        /// `WASAPIShareMode.rawValue` de AudioKit: «shared» o «exclusive».
        public var mode: String
        /// Id del endpoint de captura y de render (vacío = el de defecto del sistema, como los UID).
        public var inputEndpoint: String
        public var outputEndpoint: String

        public init(mode: String, inputEndpoint: String, outputEndpoint: String) {
            self.mode = mode
            self.inputEndpoint = inputEndpoint
            self.outputEndpoint = outputEndpoint
        }
    }

    public init(inputUID: String, outputUID: String, sampleRate: Double, bufferFrames: Int,
                inputChannel: Int, outputChannel: Int, wasapi: WASAPIPath? = nil) {
        self.inputUID = inputUID
        self.outputUID = outputUID
        self.sampleRate = sampleRate
        self.bufferFrames = bufferFrames
        self.inputChannel = inputChannel
        self.outputChannel = outputChannel
        self.wasapi = wasapi
    }

    /// Identidad de aparato de un endpoint en la clave de Windows: su contenedor si lo tiene; si no, el propio endpoint.
    /// Vacío (el de defecto del sistema) sigue vacío.
    public static func deviceIdentity(endpoint: String, container: String?) -> String {
        guard !endpoint.isEmpty, let container, !container.isEmpty else { return endpoint }
        return container
    }
}

/// Lo que la clave de Windows necesita y el perfil no guarda (paso 8, F2): el modo con el que se abre WASAPI y el
/// contenedor de los endpoints elegidos (de la lista de dispositivos). nil en el Mac.
public struct WASAPIKeyContext: Sendable, Equatable {
    /// «shared» o «exclusive» (`WASAPIShareMode.rawValue`).
    public var mode: String
    public var inputContainer: String?
    public var outputContainer: String?

    public init(mode: String, inputContainer: String? = nil, outputContainer: String? = nil) {
        self.mode = mode
        self.inputContainer = inputContainer
        self.outputContainer = outputContainer
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
    /// Canales de backing recordados por UID de salida (clave `systemOutputKey` = salida del sistema). `backingOut` es
    /// el del dispositivo activo; este mapa guarda los de los demás (M-3a: los canales dependen del dispositivo).
    public var backingByDevice: [String: ChannelPair]
    /// Canales de guitarra recordados por UID de entrada. `guitarIn` es el del dispositivo activo.
    public var guitarByDevice: [String: [Int]]

    /// Clave de la salida por defecto del sistema en `backingByDevice` (mismo criterio que los UID vacíos de `CalibrationKey`).
    public static let systemOutputKey = ""

    public init(outputDeviceUID: String? = nil, inputDeviceUID: String? = nil, backingOut: ChannelPair = .default,
                guitarIn: [Int]? = nil, bufferFrames: Int = AudioSettings.defaultBufferFrames,
                latency: LatencyCalibration? = nil, backingByDevice: [String: ChannelPair] = [:],
                guitarByDevice: [String: [Int]] = [:]) {
        self.backingByDevice = backingByDevice
        self.guitarByDevice = guitarByDevice
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
                  latency: try c.decodeIfPresent(LatencyCalibration.self, forKey: .latency),
                  // Perfil anterior a M-3a: sin mapas. Los canales globales de entonces son los del dispositivo
                  // elegido hoy; se guardan en el mapa al cambiar de dispositivo (`chooseOutput`/`chooseInput`).
                  backingByDevice: try c.decodeIfPresent([String: ChannelPair].self, forKey: .backingByDevice) ?? [:],
                  guitarByDevice: try c.decodeIfPresent([String: [Int]].self, forKey: .guitarByDevice) ?? [:])
    }

    private enum CodingKeys: String, CodingKey {
        case outputDeviceUID, inputDeviceUID, backingOut, guitarIn, bufferFrames, latency, backingByDevice, guitarByDevice
    }

    /// Los mapas por dispositivo solo se escriben si tienen algo: un perfil sin cambiar de dispositivo queda como antes.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(outputDeviceUID, forKey: .outputDeviceUID)
        try c.encodeIfPresent(inputDeviceUID, forKey: .inputDeviceUID)
        try c.encode(backingOut, forKey: .backingOut)
        try c.encodeIfPresent(guitarIn, forKey: .guitarIn)
        try c.encode(bufferFrames, forKey: .bufferFrames)
        try c.encodeIfPresent(latency, forKey: .latency)
        if !backingByDevice.isEmpty { try c.encode(backingByDevice, forKey: .backingByDevice) }
        if !guitarByDevice.isEmpty { try c.encode(guitarByDevice, forKey: .guitarByDevice) }
    }

    /// Un canal no puede tener dos papeles: el par de backing son dos canales de salida distintos (o `left == right`, el
    /// backing mono de una salida de un canal, M-3d); la
    /// guitarra, uno o dos de entrada distintos; y el canal de referencia de la calibración no es de la guitarra.
    public func validate() throws {
        guard backingOut.left >= 1, backingOut.right >= 1 else {
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

    /// Clave con la que se calibraría ahora mismo; nil sin canal de guitarra. `wasapi` solo en Windows (F2): sin él, la
    /// clave del Mac de siempre.
    public func calibrationKey(sampleRate: Double, wasapi: WASAPIKeyContext? = nil) -> CalibrationKey? {
        guard let first = guitarIn?.first else { return nil }
        let input = inputDeviceUID ?? "", output = outputDeviceUID ?? ""
        var key = CalibrationKey(inputUID: input, outputUID: output, sampleRate: sampleRate,
                                 bufferFrames: bufferFrames, inputChannel: first, outputChannel: backingOut.left)
        if let wasapi {
            key.inputUID = CalibrationKey.deviceIdentity(endpoint: input, container: wasapi.inputContainer)
            key.outputUID = CalibrationKey.deviceIdentity(endpoint: output, container: wasapi.outputContainer)
            key.wasapi = CalibrationKey.WASAPIPath(mode: wasapi.mode, inputEndpoint: input, outputEndpoint: output)
        }
        return key
    }

    /// La calibración guardada, si su clave sigue siendo la de la configuración actual.
    public func validLatency(sampleRate: Double, wasapi: WASAPIKeyContext? = nil) -> LatencyCalibration? {
        guard let latency, latency.key == calibrationKey(sampleRate: sampleRate, wasapi: wasapi) else { return nil }
        return latency
    }

    /// Cambia los canales de backing del dispositivo de salida activo y los recuerda para él.
    public mutating func setBacking(_ pair: ChannelPair) {
        backingOut = pair
        backingByDevice[outputDeviceUID ?? Self.systemOutputKey] = pair
    }

    /// Cambia los canales de guitarra del dispositivo de entrada activo y los recuerda para él (nil = sin asignar).
    /// Sin dispositivo de entrada no hay canales que guardar.
    public mutating func setGuitar(_ channels: [Int]?) {
        guitarIn = channels
        guard let uid = inputDeviceUID else { return }
        guitarByDevice[uid] = channels
    }

    /// Al elegir una salida se guardan los canales de la anterior y se restauran los de la nueva, o 1 y 2 si es nueva.
    public mutating func chooseOutput(_ uid: String?) {
        backingByDevice[outputDeviceUID ?? Self.systemOutputKey] = backingOut
        outputDeviceUID = uid
        backingOut = backingByDevice[uid ?? Self.systemOutputKey] ?? .default
    }

    /// Igual para la entrada: se restauran los canales de guitarra de ese dispositivo o queda sin asignar.
    public mutating func chooseInput(_ uid: String?) {
        if let old = inputDeviceUID { guitarByDevice[old] = guitarIn }
        inputDeviceUID = uid
        guitarIn = uid.flatMap { guitarByDevice[$0] }
    }
}

/// Reloj con el que se grabó una toma: un solo dispositivo o el agregado privado con corrección de deriva.
public enum ClockMode: String, Codable, Sendable, Equatable {
    case single, aggregate
}
