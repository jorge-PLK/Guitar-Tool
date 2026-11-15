import Foundation

/// Tramo de acorde en segundos de canción. `index` = `ChordLabel.index`.
public struct ChordSegment: Codable, Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var index: Int

    public init(start: Double, end: Double, index: Int) {
        self.start = start
        self.end = end
        self.index = index
    }
}

/// Corrección del usuario (equivalente local del `ChordOverride` de Store; la app los convierte).
public struct ChordOverride: Codable, Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var index: Int

    public init(start: Double, end: Double, index: Int) {
        self.start = start
        self.end = end
        self.index = index
    }
}

public enum ChordTimeline {
    /// Tolerancia (s) para descartar tramos vacíos y considerar adyacentes dos tramos.
    static let epsilon = 1e-6

    /// Acordes efectivos: los tramos del usuario mandan y parten los detectados que pisan;
    /// entre overrides solapados gana el último de la lista. Fusiona adyacentes con el mismo índice.
    public static func effective(detected: [ChordSegment], overrides: [ChordOverride]) -> [ChordSegment] {
        // 1. Resolver solapes entre overrides: cada uno nuevo recorta a los anteriores.
        var resolved: [ChordSegment] = []
        for o in overrides where o.end - o.start > epsilon {
            resolved = resolved.flatMap { subtract($0, from: o.start, to: o.end) }
            resolved.append(ChordSegment(start: o.start, end: o.end, index: o.index))
        }
        // 2. Quitar de lo detectado todo lo que pisan.
        var base = detected.filter { $0.end - $0.start > epsilon }
        for o in resolved {
            base = base.flatMap { subtract($0, from: o.start, to: o.end) }
        }
        // 3. Ordenar y fusionar.
        let all = (base + resolved).sorted { $0.start < $1.start }
        var merged: [ChordSegment] = []
        for s in all {
            if var last = merged.last, last.index == s.index, abs(s.start - last.end) <= epsilon {
                last.end = max(last.end, s.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(s)
            }
        }
        return merged
    }

    /// `segment` menos el intervalo [from, to]; devuelve 0, 1 o 2 trozos.
    private static func subtract(_ segment: ChordSegment, from: Double, to: Double) -> [ChordSegment] {
        guard from < segment.end, to > segment.start else { return [segment] }
        var out: [ChordSegment] = []
        if from - segment.start > epsilon {
            out.append(ChordSegment(start: segment.start, end: from, index: segment.index))
        }
        if segment.end - to > epsilon {
            out.append(ChordSegment(start: to, end: segment.end, index: segment.index))
        }
        return out
    }
}
