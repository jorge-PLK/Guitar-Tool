import Foundation

/// Clic del metrónomo en segundos de canción; `accent` en los downbeats.
public struct Click: Codable, Sendable, Equatable {
    public var time: Double
    public var accent: Bool

    public init(time: Double, accent: Bool) {
        self.time = time
        self.accent = accent
    }
}

/// Rejilla de pulsos y compases (mini-spec Fase 2 §1 StudyKit). Tiempos en segundos de canción, ordenados.
public struct BeatGrid: Codable, Sendable, Equatable {
    public enum SnapUnit: String, Codable, Sendable {
        case beat, bar
    }

    public let beats: [Double]
    /// Subconjunto de `beats` (el postproceso lleva cada downbeat a su pulso más cercano).
    public let downbeats: [Double]
    /// Media de los intervalos entre pulsos dentro de ±20 % de la mediana (ADR-006). nil con menos de 3 pulsos.
    public let bpm: Double?
    /// Moda de pulsos entre downbeats consecutivos (empate: el menor). nil con menos de 2 downbeats.
    public let beatsPerBar: Int?

    /// Margen de ±20 % alrededor de la mediana para el tempo por media (ADR-006).
    static let tempoBand = 0.2
    /// Tolerancia para reconocer un pulso como downbeat (ambos salen de tramas de 20 ms).
    static let sameTime = 1e-6

    public init(beats: [Double], downbeats: [Double]) {
        self.beats = beats.sorted()
        self.downbeats = downbeats.sorted()
        bpm = Self.meanTempo(self.beats)
        beatsPerBar = Self.modeBeatsPerBar(beats: self.beats, downbeats: self.downbeats)
    }

    static func meanTempo(_ beats: [Double]) -> Double? {
        guard beats.count >= 3 else { return nil }
        let d = zip(beats.dropFirst(), beats).map { $0 - $1 }.sorted()
        let median = d.count % 2 == 1 ? d[d.count / 2] : (d[d.count / 2 - 1] + d[d.count / 2]) / 2
        let kept = d.filter { $0 > (1 - tempoBand) * median && $0 < (1 + tempoBand) * median }
        guard !kept.isEmpty else { return nil }
        return 60 / (kept.reduce(0, +) / Double(kept.count))
    }

    static func modeBeatsPerBar(beats: [Double], downbeats: [Double]) -> Int? {
        guard downbeats.count >= 2 else { return nil }
        // searchsorted(beats, downbeats) y diferencias, como `bt_common.bar_histogram`.
        let idx = downbeats.map { lowerBound(beats, $0) }
        var histogram: [Int: Int] = [:]
        for (a, b) in zip(idx, idx.dropFirst()) { histogram[b - a, default: 0] += 1 }
        return histogram.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }

    /// Índice del compás (0 = el que empieza en el primer downbeat) que contiene `time`; nil antes del primero.
    public func bar(at time: Double) -> Int? {
        let i = Self.upperBound(downbeats, time + Self.sameTime)
        return i == 0 ? nil : i - 1
    }

    /// Lleva los dos extremos al pulso (o downbeat) más cercano. Si quedan en el mismo punto, el final pasa al
    /// siguiente (o el inicio al anterior). Sin rejilla, devuelve el tramo tal cual.
    public func snap(_ range: ClosedRange<Double>, to unit: SnapUnit) -> ClosedRange<Double> {
        let grid = unit == .beat ? beats : downbeats
        guard let lo = Self.nearest(grid, range.lowerBound), var hi = Self.nearest(grid, range.upperBound) else {
            return range
        }
        var start = lo
        if hi <= start {
            let next = Self.upperBound(grid, start)
            if next < grid.count {
                hi = grid[next]
            } else {
                let prev = Self.lowerBound(grid, start) - 1
                guard prev >= 0 else { return range }
                start = grid[prev]
                hi = lo
            }
        }
        return start...hi
    }

    /// Clics de los pulsos dentro del tramo; acento en los downbeats.
    public func clicks(in range: ClosedRange<Double>) -> [Click] {
        let from = Self.lowerBound(beats, range.lowerBound), to = Self.upperBound(beats, range.upperBound)
        guard from < to else { return [] }
        return beats[from..<to].map { t in
            let i = Self.lowerBound(downbeats, t - Self.sameTime)
            return Click(time: t, accent: i < downbeats.count && abs(downbeats[i] - t) <= Self.sameTime)
        }
    }

    // MARK: búsqueda en arrays ordenados

    /// Primer índice con a[i] >= x.
    static func lowerBound(_ a: [Double], _ x: Double) -> Int {
        var lo = 0, hi = a.count
        while lo < hi { let m = (lo + hi) / 2; if a[m] < x { lo = m + 1 } else { hi = m } }
        return lo
    }

    /// Primer índice con a[i] > x.
    static func upperBound(_ a: [Double], _ x: Double) -> Int {
        var lo = 0, hi = a.count
        while lo < hi { let m = (lo + hi) / 2; if a[m] <= x { lo = m + 1 } else { hi = m } }
        return lo
    }

    static func nearest(_ a: [Double], _ x: Double) -> Double? {
        guard !a.isEmpty else { return nil }
        let i = lowerBound(a, x)
        if i == 0 { return a[0] }
        if i == a.count { return a[a.count - 1] }
        return x - a[i - 1] <= a[i] - x ? a[i - 1] : a[i]
    }
}
