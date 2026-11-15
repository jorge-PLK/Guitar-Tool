import AVFoundation
import Accelerate
import Foundation

// Lógica sin vista que usa la app para grabar y comparar (mini-spec Fase 3, «Grabación», «A/B dentro de la
// mezcla» y «Reglas propias»). Vive aquí, y no en App, para tener tests: la app no tiene destino de pruebas.

/// Formato de frecuencia en kHz como en los avisos de la mini-spec («48 kHz», «44,1 kHz»).
func khzText(_ hz: Double) -> String {
    String(format: hz.truncatingRemainder(dividingBy: 1000) == 0 ? "%.0f" : "%.1f", hz / 1000)
        .replacingOccurrences(of: ".", with: ",") + " kHz"
}

// MARK: - Por qué no se puede grabar

/// Motivo por el que calibrar o grabar están desactivados. `message` es lo que se enseña junto al botón.
public enum RecordBlock: Equatable, Sendable {
    case noInputDevice
    case noGuitarInput
    case invalidChannels
    case inputDisconnected
    case outputDisconnected
    /// «El dispositivo está a X kHz y la frecuencia de trabajo es Y kHz» (mini-spec, «Frecuencia»).
    case rateMismatch(device: Double, working: Double)
    /// La sesión no se pudo abrir o el reproductor no pudo alojarse en ella (texto del error).
    case sessionUnavailable(String)
    /// Solo se graba al 100 % (mini-spec, «Reglas propias»).
    case speed(Double)
    /// Solo se graba con el bucle desactivado (mini-spec, «Reglas propias»).
    case loop
    /// Ya hay una calibración o una grabación en marcha.
    case busy

    public var message: String {
        switch self {
        case .noInputDevice: return "Elige un dispositivo de entrada en Ajustes · Audio."
        case .noGuitarInput: return "Asigna la entrada de guitarra en Ajustes · Audio."
        case .invalidChannels: return "Los canales elegidos se repiten: revisa Ajustes · Audio."
        case .inputDisconnected: return "El dispositivo de entrada no está conectado."
        case .outputDisconnected: return "El dispositivo de salida no está conectado."
        case let .rateMismatch(device, working):
            return "El dispositivo está a \(khzText(device)) y la frecuencia de trabajo es \(khzText(working))"
        case .sessionUnavailable(let s): return s
        case .speed: return "Solo se graba a velocidad 100 %: pon el tempo al 100 %."
        case .loop: return "Solo se graba sin bucle: quita el bucle."
        case .busy: return "Hay una calibración o una grabación en marcha."
        }
    }
}

public enum RecordingGate {
    /// Lo que se sabe del dispositivo y de la configuración.
    public struct DeviceState: Equatable, Sendable {
        public var hasInputDevice: Bool
        public var hasGuitarIn: Bool
        public var validChannels: Bool
        public var inputConnected: Bool
        public var outputConnected: Bool
        /// Frecuencia actual de un dispositivo elegido que no está a la de trabajo (nil = todos a ella).
        public var mismatchedRate: Double?
        public var workingRate: Double
        public var sessionError: String?

        public init(hasInputDevice: Bool, hasGuitarIn: Bool, validChannels: Bool = true, inputConnected: Bool = true,
                    outputConnected: Bool = true, mismatchedRate: Double? = nil, workingRate: Double = 48_000,
                    sessionError: String? = nil) {
            self.hasInputDevice = hasInputDevice
            self.hasGuitarIn = hasGuitarIn
            self.validChannels = validChannels
            self.inputConnected = inputConnected
            self.outputConnected = outputConnected
            self.mismatchedRate = mismatchedRate
            self.workingRate = workingRate
            self.sessionError = sessionError
        }
    }

    /// Motivo para no calibrar ni grabar (el dispositivo y los canales); nil si se puede.
    public static func deviceBlock(_ s: DeviceState) -> RecordBlock? {
        if !s.hasInputDevice { return .noInputDevice }
        if !s.inputConnected { return .inputDisconnected }
        if !s.outputConnected { return .outputDisconnected }
        if !s.hasGuitarIn { return .noGuitarInput }
        if !s.validChannels { return .invalidChannels }
        if let r = s.mismatchedRate { return .rateMismatch(device: r, working: s.workingRate) }
        if let e = s.sessionError { return .sessionUnavailable(e) }
        return nil
    }

    /// Motivo para no grabar: el del dispositivo y, además, velocidad ≠ 100 % o bucle activo.
    public static func recordBlock(_ s: DeviceState, playbackRate: Double, loopActive: Bool, busy: Bool = false) -> RecordBlock? {
        if let b = deviceBlock(s) { return b }
        if abs(playbackRate - 1) > 1e-9 { return .speed(playbackRate) }
        if loopActive { return .loop }
        if busy { return .busy }
        return nil
    }
}

// MARK: - A/B

/// Fuente del A/B de Backing (mini-spec, «A/B dentro de la mezcla»).
public enum CompareMode: String, Sendable, Equatable, CaseIterable {
    /// El stem de guitarra suena.
    case original
    /// El stem se silencia; te oyes por la monitorización del dispositivo.
    case live
    /// El stem se silencia y suena la última toma, igualada en sonoridad.
    case lastTake
}

public enum MixCompare {
    /// Mute que ve el reproductor para el stem comparado: en A es el del usuario; en B, siempre silenciado.
    /// El del usuario (el del mezclador, guardado en el proyecto) nunca se toca: al volver a A se restaura.
    public static func stemMuted(mode: CompareMode, userMuted: Bool) -> Bool {
        mode == .original ? userMuted : true
    }

    /// Diferencia de nivel en directo: tu procesada menos el stem con su fader (dB). nil si falta una medida.
    public static func liveDifferenceDB(liveDB: Double?, stemRMSDB: Double?, faderDB: Double) -> Double? {
        guard let liveDB, let stemRMSDB, liveDB.isFinite, stemRMSDB.isFinite else { return nil }
        return liveDB - (stemRMSDB + faderDB)
    }

    /// «+2,1 dB respecto al original» (con un signo en cualquier caso).
    public static func differenceText(_ dB: Double) -> String {
        let r = (dB * 10).rounded() / 10
        let sign = r > 0 ? "+" : r < 0 ? "−" : ""
        return sign + String(format: "%.1f", abs(r)).replacingOccurrences(of: ".", with: ",") + " dB respecto al original"
    }

    /// Ganancia de la toma igualada, para enseñarla («+3,2 dB»).
    public static func gainText(_ dB: Double) -> String {
        let r = (dB * 10).rounded() / 10
        let sign = r > 0 ? "+" : r < 0 ? "−" : ""
        return sign + String(format: "%.1f", abs(r)).replacingOccurrences(of: ".", with: ",") + " dB"
    }
}

// MARK: - Muestras de un fichero

/// Lectura de tramos de un WAV (los stems y las tomas), para el A/B.
public enum AudioSamples {
    /// Frecuencia del fichero.
    public static func sampleRate(of url: URL) throws -> Double {
        try AVAudioFile(forReading: url).processingFormat.sampleRate
    }

    /// Canales de `[from, from + seconds)` (s) del fichero; `seconds` nil = hasta el final. Recorta a lo que haya.
    public static func read(_ url: URL, from: Double = 0, seconds: Double? = nil) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let fs = file.processingFormat.sampleRate
        let channels = Int(file.processingFormat.channelCount)
        let start = min(max(0, Int((from * fs).rounded())), Int(file.length))
        let end = seconds.map { min(Int(file.length), start + Int(($0 * fs).rounded())) } ?? Int(file.length)
        var out = Array(repeating: [Float](), count: channels)
        guard end > start else { return out }
        for c in 0..<channels { out[c].reserveCapacity(end - start) }
        file.framePosition = AVAudioFramePosition(start)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65_536)!
        var left = end - start
        while left > 0 {
            buf.frameLength = 0
            try file.read(into: buf, frameCount: AVAudioFrameCount(min(65_536, left)))
            let n = Int(buf.frameLength)
            if n == 0 { break }
            for c in 0..<channels { out[c].append(contentsOf: UnsafeBufferPointer(start: buf.floatChannelData![c], count: n)) }
            left -= n
        }
        return out
    }

    /// RMS en dBFS: potencia media de los canales (como `AudioSession.guitarLevelDB`). nil si es silencio o está vacío.
    public static func rmsDB(_ channels: [[Float]]) -> Double? {
        let n = channels.reduce(0) { $0 + $1.count }
        guard n > 0 else { return nil }
        var sum = 0.0
        for ch in channels {
            var ms: Float = 0
            vDSP_measqv(ch, 1, &ms, vDSP_Length(ch.count))
            sum += Double(ms) * Double(ch.count)
        }
        let p = sum / Double(n)
        guard p > 1e-12 else { return nil }
        return 10 * log10(p)
    }
}

// MARK: - Tomas

extension RecordedTake {
    /// Para que la app reconstruya una toma guardada y la corrija al calibrar (`AudioSession.reshiftUncalibrated`).
    public init(restoring songStart: Double, sampleRate: Double, frameCount: Int, channelCount: Int,
                latencySamples: Double, rigDelaySamples: Double?, rigDelayReliable: Bool?, latencyCalibrated: Bool,
                calibrationKey: LatencyCalibrationKey, clock: AudioIOClock) {
        self.songStart = songStart
        self.sampleRate = sampleRate
        self.frameCount = frameCount
        self.channelCount = channelCount
        self.latencySamples = latencySamples
        self.rigDelaySamples = rigDelaySamples
        self.rigDelayReliable = rigDelayReliable
        self.latencyCalibrated = latencyCalibrated
        self.calibrationKey = calibrationKey
        self.clock = clock
    }
}

// MARK: - Calibración guardada

extension LatencyCalibrationKey {
    /// La clave en los términos del perfil de equipo: sin salida elegida (nil) el UID va vacío, aunque la sesión
    /// la abriera en la de defecto del sistema (cuyo UID real sí lleva la clave de la sesión).
    public func inProfileTerms(outputDeviceUID: String?) -> LatencyCalibrationKey {
        var k = self
        k.outputUID = outputDeviceUID ?? ""
        return k
    }

    /// Lo contrario: con el UID vacío del perfil, el de la salida por defecto con la que abrió la sesión.
    public func resolvingDefaultOutput(to uid: String) -> LatencyCalibrationKey {
        var k = self
        if k.outputUID.isEmpty { k.outputUID = uid }
        return k
    }
}

extension LatencyCalibrationResult {
    /// Calibración válida reconstruida desde lo guardado (solo hay datos de `guitarIn`; el resto de canales no importa).
    public static func restored(key: LatencyCalibrationKey, date: Date, guitarIn: [Int], latencySamples: Double,
                                spreadSamples: Double, inputChannels: Int, reference: ReferenceInput?) -> LatencyCalibrationResult {
        let count = max(inputChannels, guitarIn.max() ?? 1, reference?.channel ?? 1)
        let channels = (1...count).map { ch -> LatencyChannelMeasurement in
            let isGuitar = ch == guitarIn.first
            return LatencyChannelMeasurement(channel: ch, lagsSamples: isGuitar ? [latencySamples] : [],
                                             latencySamples: isGuitar ? latencySamples : 0,
                                             spreadSamples: isGuitar ? spreadSamples : 0, peakToFloorDB: 0, inputPeak: 0,
                                             failure: nil)
        }
        return LatencyCalibrationResult(key: key, date: date, guitarIn: guitarIn, channels: channels, reference: reference)
    }
}
