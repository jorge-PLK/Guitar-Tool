import Foundation

/// Tramo de la partitura seleccionado para el bucle (mini-spec Fase 5c, decisión 3): de `startTick` (incluido) a
/// `endTick` (excluido), en ticks absolutos de la rejilla (`GridPoint.absoluteTick`).
public struct TabSpan: Sendable, Equatable {
    public var startTick: Int
    public var endTick: Int

    public init(startTick: Int, endTick: Int) {
        self.startTick = min(startTick, endTick)
        self.endTick = max(startTick, endTick)
    }

    /// Une dos tramos (el de pulsos pulsado y el de pulsos al que se arrastra o amplía).
    public func union(_ other: TabSpan) -> TabSpan {
        TabSpan(startTick: min(startTick, other.startTick), endTick: max(endTick, other.endTick))
    }
}

/// Posición en un compás: fracción 0…1 de su duración.
public struct TabBarPosition: Sendable, Equatable {
    public var bar: Int
    public var fraction: Double
}

public extension TabScore {
    /// Del inicio del primer pulso al final del último, en segundos de canción; nil si el tramo está vacío o fuera.
    func timeRange(of span: TabSpan) -> ClosedRange<Double>? {
        guard !beats.isEmpty, span.endTick > span.startTick, span.startTick < totalTicks else { return nil }
        let start = time(of: GridPoint(absoluteTick: max(0, span.startTick)))
        let end = time(of: GridPoint(absoluteTick: min(span.endTick, totalTicks)))
        return end > start ? start...end : nil
    }

    /// Compás y fracción de un tick. Con `asEnd`, un tick que cae justo en el inicio de un compás cuenta como el final
    /// del anterior (fracción 1), para pintar el final de un tramo en el compás donde acaba.
    func barPosition(ofTick tick: Int, asEnd: Bool = false) -> TabBarPosition? {
        guard !beats.isEmpty else { return nil }
        let t = min(max(0, tick), totalTicks)
        var b = min(t / Self.ticksPerBeat, beats.count - 1)
        if asEnd, t > 0, t % Self.ticksPerBeat == 0, t / Self.ticksPerBeat < beats.count,
           beats[t / Self.ticksPerBeat].indexInBar == 0 {
            b = t / Self.ticksPerBeat - 1
        }
        let bar = beats[b].bar
        guard bars.indices.contains(bar) else { return nil }
        let first = bars[bar].firstBeat * Self.ticksPerBeat
        let total = bars[bar].beatCount * Self.ticksPerBeat
        return TabBarPosition(bar: bar, fraction: min(1, max(0, Double(t - first) / Double(total))))
    }
}
