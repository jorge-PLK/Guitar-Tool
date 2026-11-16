import Foundation

// No usado desde la revisión del 15/11/2026; ver spec, «Opciones de guitarras y tramos de solo». El tramo del producto
// es `GuitarSoloSpan` (solo inicio y fin), en GuitarStemComposer.swift.

/// Tramo de solo de la puerta del centro (mini-spec Fase 4, «Separación por panorama», viñeta «Centro con
/// puerta», y editor «Aislar solo» en «Interfaz»). Lo marca el usuario en el editor y se guarda tal cual en
/// `project.json` (Codable; los opcionales ausentes se leen como `nil`).
///
/// Dentro de `[start, end]` (más un fundido de `fadeSeconds` por fuera de cada borde, en el dominio de la máscara)
/// la parte de centro se decide con `centerWidth` y `coherenceFloor`. Si hay `frequencyRange` y/o `panRange`, solo
/// los bins dentro de la selección pueden ir a C; el resto del tramo vuelve a L y R por canal. Fuera de los tramos,
/// C = 0 y L, R son los canales exactos.
public struct PanSoloSpan: Sendable, Codable, Equatable {
    /// Intervalo cerrado `[lower, upper]`; si vienen al revés se toman ordenados.
    public struct Bounds: Sendable, Codable, Equatable {
        public var lower: Double
        public var upper: Double

        public init(lower: Double, upper: Double) {
            self.lower = lower
            self.upper = upper
        }

        var low: Double { min(lower, upper) }
        var high: Double { max(lower, upper) }
    }

    /// Anchura del centro dentro del tramo, en |p| (escala de `PanSplitter`: mono 0, extremos ±1).
    /// Mini-spec Fase 4, «Centro con puerta»: 0,30, el mejor del barrido del 15/11/2026.
    public static let defaultCenterWidth = 0.30
    /// Suelo de Re(L·R*)/|canal|² dentro del tramo. Mini-spec Fase 4, «Centro con puerta»: 0,15.
    public static let defaultCoherenceFloor = 0.15
    /// Fundido de la puerta por fuera de cada borde, en segundos. Mini-spec Fase 4, «Centro con puerta»: ~100 ms.
    public static let fadeSeconds = 0.1
    /// Confianza mínima de un pasaje de solo para proponerlo (provisional, sin calibrar: la spec solo dice «alta»).
    /// En Platero, sobre la C de una primera pasada, los «lead» falsos llegan a 0,86 (4–9 s) y el solo real
    /// (157–187 s) queda dentro de un pasaje de 0,64; con 0,9 no se propone nada.
    public static let proposalMinimumConfidence = 0.9

    /// Segundos desde el inicio de `stems/guitar.wav`.
    public var start: Double
    public var end: Double
    /// Franja del solo en Hz (vista de espectrograma o rectángulo del mapa). `nil`: todas las frecuencias.
    public var frequencyRange: Bounds?
    /// Rango de panorama p en [−1, 1] (rectángulo del mapa panorama × frecuencia). `nil`: sin restricción.
    /// Restringe, no sustituye: un bin fuera de `centerWidth` (más la transición) no va a C aunque esté dentro.
    public var panRange: Bounds?
    /// `nil`: `defaultCenterWidth`.
    public var centerWidth: Double?
    /// `nil`: `defaultCoherenceFloor`.
    public var coherenceFloor: Double?

    public init(start: Double, end: Double, frequencyRange: Bounds? = nil, panRange: Bounds? = nil,
                centerWidth: Double? = nil, coherenceFloor: Double? = nil) {
        self.start = start
        self.end = end
        self.frequencyRange = frequencyRange
        self.panRange = panRange
        self.centerWidth = centerWidth
        self.coherenceFloor = coherenceFloor
    }

    public var effectiveCenterWidth: Double { centerWidth ?? Self.defaultCenterWidth }
    public var effectiveCoherenceFloor: Double { coherenceFloor ?? Self.defaultCoherenceFloor }

    /// Propuesta automática (mini-spec Fase 4, «Centro con puerta»: solo con confianza alta). Devuelve, sin
    /// selección de franja ni panorama, los candidatos con `confidence ≥ minimumConfidence`; si no hay, vacío.
    /// No se aplica por defecto: es una sugerencia para el editor «Aislar solo».
    /// Los candidatos los arma quien tenga los pasajes (la app, con los «lead» de `PassageClassifier` sobre la C
    /// de una primera pasada con un tramo que cubra el tema entero); StemKit no depende de TabKit.
    public static func proposals(from candidates: [PanSoloCandidate],
                                 minimumConfidence: Double = proposalMinimumConfidence) -> [PanSoloSpan] {
        candidates
            .filter { $0.confidence >= minimumConfidence && $0.end > $0.start }
            .sorted { $0.start < $1.start }
            .map { PanSoloSpan(start: $0.start, end: $0.end) }
    }
}

/// Pasaje candidato a solo para `PanSoloSpan.proposals`: tramo en segundos y confianza 0…1.
public struct PanSoloCandidate: Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var confidence: Double

    public init(start: Double, end: Double, confidence: Double) {
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

/// Tramo resuelto para el motor: tiempos, bins y parámetros listos.
struct PanGateSpan: Sendable {
    var start: Double
    var end: Double
    var fade: Double
    var centerWidth: Double
    var coherenceFloor: Double
    /// Bins (incluidos) de la franja; todos si no hay franja.
    var binLow: Int
    var binHigh: Int
    var panLow: Double
    var panHigh: Double

    /// `nil` si el tramo no deja nada (vacío o franja fuera del espectro).
    init?(_ s: PanSoloSpan, sampleRate: Double, fade: Double = PanSoloSpan.fadeSeconds) {
        guard s.end > s.start, s.start.isFinite, s.end.isFinite else { return nil }
        start = s.start
        end = s.end
        self.fade = fade
        centerWidth = s.effectiveCenterWidth
        coherenceFloor = min(0.99, max(0, s.effectiveCoherenceFloor))
        let binHz = sampleRate / Double(RoformerContract.nFFT)
        if let f = s.frequencyRange {
            binLow = max(0, Int((f.low / binHz).rounded(.up)))
            binHigh = min(RoformerContract.bins - 1, Int((f.high / binHz).rounded(.down)))
        } else {
            binLow = 0
            binHigh = RoformerContract.bins - 1
        }
        guard binLow <= binHigh else { return nil }
        panLow = s.panRange?.low ?? -.infinity
        panHigh = s.panRange?.high ?? .infinity
    }

    /// Puerta en el instante `t` (s): 0 fuera, coseno alzado de `fade` por fuera de cada borde, 1 dentro.
    func gain(at t: Double) -> Double {
        if t <= start - fade || t >= end + fade { return 0 }
        if t < start { return 0.5 - 0.5 * cos(Double.pi * (t - (start - fade)) / fade) }
        if t > end { return 0.5 + 0.5 * cos(Double.pi * (t - end) / fade) }
        return 1
    }
}
