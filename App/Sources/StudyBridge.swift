import StudyKit

/// `Store` y `StudyKit` definen cada uno su `ChordOverride` (y el enum `StudyKit` tapa el nombre del módulo),
/// así que la conversión vive en un fichero que solo importa StudyKit. Igual con `Click` (StudyKit y AudioKit).
enum StudyBridge {
    static func effectiveChords(detected: [ChordSegment],
                                overrides: [(start: Double, end: Double, index: Int)]) -> [ChordSegment] {
        ChordTimeline.effective(detected: detected,
                                overrides: overrides.map { ChordOverride(start: $0.start, end: $0.end, index: $0.index) })
    }

    /// Clics de la rejilla como pares, para que la app los convierta a `AudioKit.Click`.
    static func clicks(_ grid: BeatGrid, in range: ClosedRange<Double>) -> [(time: Double, accent: Bool)] {
        grid.clicks(in: range).map { ($0.time, $0.accent) }
    }

    /// Pulso de la rejilla más cercano a `t` (o `t` si no hay rejilla).
    static func nearestBeat(_ grid: BeatGrid?, to t: Double) -> Double {
        grid?.beats.min { abs($0 - t) < abs($1 - t) } ?? t
    }

    /// Compás (downbeat) de la rejilla más cercano a `t` (o el pulso, o `t` si no hay rejilla).
    static func nearestBar(_ grid: BeatGrid?, to t: Double) -> Double {
        guard let grid, !grid.downbeats.isEmpty else { return nearestBeat(grid, to: t) }
        return grid.downbeats.min { abs($0 - t) < abs($1 - t) } ?? t
    }

    /// Ajusta un tramo al pulso (`bar` = false) o al compás (`bar` = true).
    static func snap(_ grid: BeatGrid?, _ range: ClosedRange<Double>, bar: Bool) -> ClosedRange<Double> {
        grid?.snap(range, to: bar ? .bar : .beat) ?? range
    }
}
