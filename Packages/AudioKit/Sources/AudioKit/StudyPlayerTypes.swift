import Foundation

/// Un stem que carga `StudyPlayer`.
public struct Track: Sendable, Equatable, Identifiable {
    public var id: String
    public var url: URL

    public init(id: String, url: URL) {
        self.id = id
        self.url = url
    }
}

/// Clic del metrónomo en tiempo de canción (segundos). StudyKit tiene su propio `Click`; la app convierte.
public struct Click: Sendable, Equatable, Hashable {
    public var time: Double
    public var accent: Bool

    public init(time: Double, accent: Bool) {
        self.time = time
        self.accent = accent
    }
}

/// Metrónomo: clics, activado y volumen.
public struct Metronome: Sendable, Equatable {
    public var clicks: [Click]
    public var isEnabled: Bool
    public var gainDB: Double

    public init(clicks: [Click] = [], isEnabled: Bool = false, gainDB: Double = 0) {
        self.clicks = clicks
        self.isEnabled = isEnabled
        self.gainDB = gainDB
    }
}

/// Nivel de un canal tras ganancia, mute y solo (dBFS, el último bloque medido).
public struct ChannelMeter: Sendable, Equatable {
    public var rmsDB: Float
    public var peakDB: Float

    public static let silent = ChannelMeter(rmsDB: -120, peakDB: -120)

    public init(rmsDB: Float, peakDB: Float) {
        self.rmsDB = rmsDB
        self.peakDB = peakDB
    }
}

public enum StudyPlayerError: Error, Equatable {
    case noTracks
    case unreadable(String)
    /// Todos los stems deben tener la misma frecuencia de muestreo.
    case sampleRateMismatch
    case engine(String)
}

/// Números del reproductor (mini-spec Fase 2 §1 AudioKit, ADR-005).
enum StudyPlayerConstants {
    /// Velocidad 50–200 % (mini-spec §1 AudioKit).
    static let rateRange: ClosedRange<Double> = 0.5...2.0
    /// Transposición −12…+12 semitonos × 100 + fina ±50 cents (mini-spec §1 AudioKit).
    static let pitchCentsRange: ClosedRange<Double> = -1_250...1_250
    /// Overlap del TimePitch (ADR-005).
    static let timePitchOverlap: Float = 8
    /// Fundido en cada corte del bucle (mini-spec §1 AudioKit): fundido cruzado de 5 ms centrado en el corte.
    static let loopCrossfadeSeconds = 0.005
    /// Bucle mínimo aceptado (decisión de P6; por debajo se ignora).
    static let minimumLoopSeconds = 0.05
    /// Trozo que se programa de una vez en cada player y cola por delante de lo renderizado.
    /// Un cambio de bucle se oye, como mucho, tras trozo + cola (≈ 0,75 s de canción).
    static let chunkSeconds = 0.25
    static let queueSeconds = 0.5
    /// Cada cuánto rellena la cola en tiempo real.
    static let refillInterval = 0.02
    /// Historia de tramos que guarda el reloj (para `currentTime` y clics recientes).
    static let historySeconds = 20.0
}
