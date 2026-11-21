import Foundation
import StudyKit

/// Lo de StudyKit que usan las ediciones del estudio (8.5b): rejilla y etiquetas de acorde. Solo importa StudyKit para no
/// chocar con `Store` (los dos definen `ChordOverride`); igual que `StudyKitBridge`. Copia de `App/Sources/StudyBridge.swift`.
enum StudyEditsBridge {
    /// Pulso más cercano a `t` (o `t` si no hay rejilla).
    static func nearestBeat(_ beats: [Double], to t: Double) -> Double {
        beats.min { abs($0 - t) < abs($1 - t) } ?? t
    }

    /// Compás (downbeat) más cercano a `t` (o el pulso, o `t` si no hay rejilla).
    static func nearestBar(beats: [Double], downbeats: [Double], to t: Double) -> Double {
        guard !downbeats.isEmpty else { return nearestBeat(beats, to: t) }
        return downbeats.min { abs($0 - t) < abs($1 - t) } ?? t
    }

    /// Ajusta un tramo al pulso (`bar` = false) o al compás (`bar` = true); sin rejilla, tal cual.
    static func snap(beats: [Double], downbeats: [Double], _ range: ClosedRange<Double>, bar: Bool) -> ClosedRange<Double> {
        guard beats.count >= 2 else { return range }
        return BeatGrid(beats: beats, downbeats: downbeats).snap(range, to: bar ? .bar : .beat)
    }

    /// El índice es un acorde de StudyKit (0...168 acordes, 168 = «?», 169 = «N»).
    static func isValidChordIndex(_ index: Int) -> Bool { ChordLabel(index: index) != nil }

    /// Índice de una etiqueta «C:min», «F#:7», «C», «N», «X».
    static func chordIndex(label: String) -> Int? { ChordLabel(labName: label)?.index }

    /// Tonalidad mayor o menor normalizada («Db:maj» -> «C#:maj»); nil si no lo es.
    static func normalizedKey(_ text: String) -> String? {
        guard let l = ChordLabel(labName: text), let q = l.quality, q == .maj || q == .min else { return nil }
        // Sin «:» «C» valdría como mayor; la tonalidad se pide completa como la guarda el análisis.
        guard text.contains(":") else { return nil }
        return l.labName
    }
}
