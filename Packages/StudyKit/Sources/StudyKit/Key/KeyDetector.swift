import Foundation

/// Tonalidad estimada: nombre «C:maj» / «A:min», segunda opción y margen entre ambas.
public struct KeyEstimate: Codable, Sendable, Equatable {
    public var key: String
    /// s1 − s2 (puntuación de la primera menos la de la segunda).
    public var confidence: Double
    public var alternative: String

    public init(key: String, confidence: Double, alternative: String) {
        self.key = key
        self.confidence = confidence
        self.alternative = alternative
    }
}

/// Tonalidad por perfiles de Temperley sobre croma del CQT + histograma de acordes (mini-spec Fase 2 §1
/// `KeyDetector`; receta idéntica a `make_fase2_fixtures.py`, README de Fixtures «Tonalidad»).
public enum KeyDetector {
    /// Temperley (2007), Kostka-Payne, índice 0 = tónica (README de Fixtures, paso 3).
    static let majorProfile = [0.748, 0.060, 0.488, 0.082, 0.670, 0.460, 0.096, 0.715, 0.104, 0.366, 0.057, 0.400]
    static let minorProfile = [0.712, 0.084, 0.474, 0.618, 0.049, 0.460, 0.105, 0.747, 0.404, 0.067, 0.133, 0.330]
    static let roots = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    /// Orden de las 24 puntuaciones: 0–11 mayores desde C, 12–23 menores desde C.
    static let keyNames = roots.map { "\($0):maj" } + roots.map { "\($0):min" }

    /// `chroma`: 12 × fotogramas (`ChordAnalysis.chroma`); `segments`: los detectados.
    public static func detect(chroma: [[Float]], segments: [ChordSegment]) -> KeyEstimate {
        let c = chroma.map { row in row.reduce(0.0) { $0 + Double($1) } }
        let s = scores(chroma: c, histogram: histogram(segments))
        // np.argsort(scores)[::-1]: descendente; en empate va primero el índice mayor.
        let order = s.indices.sorted { s[$0] != s[$1] ? s[$0] > s[$1] : $0 > $1 }
        return KeyEstimate(key: keyNames[order[0]], confidence: s[order[0]] - s[order[1]],
                           alternative: keyNames[order[1]])
    }

    /// Paso 2: por segmento (sin X ni N) su duración se suma a cada nota del acorde.
    static func histogram(_ segments: [ChordSegment]) -> [Double] {
        var h = [Double](repeating: 0, count: 12)
        for seg in segments {
            guard let l = ChordLabel(index: seg.index), l.isChord else { continue }
            for pc in l.pitchClasses { h[pc] += seg.end - seg.start }
        }
        return h
    }

    /// Paso 3: s = ½·r(croma, p_t) + ½·r(histograma, p_t) con p_t[pc] = p[(pc − t) mod 12].
    static func scores(chroma: [Double], histogram: [Double]) -> [Double] {
        var out: [Double] = []
        for profile in [majorProfile, minorProfile] {
            for t in 0..<12 {
                let p = (0..<12).map { profile[(($0 - t) % 12 + 12) % 12] }
                out.append(0.5 * pearson(chroma, p) + 0.5 * pearson(histogram, p))
            }
        }
        return out
    }

    /// Pearson; 0 si alguna varianza es 0.
    static func pearson(_ x: [Double], _ y: [Double]) -> Double {
        let mx = x.reduce(0, +) / Double(x.count), my = y.reduce(0, +) / Double(y.count)
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for i in x.indices {
            let a = x[i] - mx, b = y[i] - my
            sxy += a * b
            sxx += a * a
            syy += b * b
        }
        let d = (sxx * syy).squareRoot()
        return d > 0 ? sxy / d : 0
    }
}

/// Análisis automático de un tema (se guarda en `cache/analysis.json` con `AnalysisCache`).
public struct StudyAnalysis: Codable, Sendable, Equatable {
    public var beats: BeatGrid?
    public var chords: ChordAnalysis
    public var key: KeyEstimate

    public init(beats: BeatGrid?, chords: ChordAnalysis, key: KeyEstimate) {
        self.beats = beats
        self.chords = chords
        self.key = key
    }
}
