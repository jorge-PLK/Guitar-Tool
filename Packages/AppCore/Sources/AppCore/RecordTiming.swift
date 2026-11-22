import StudyKit

/// Compases para grabar (mini-spec Fase 6, «Grabar una toma»): los del pulso de la Fase 2; sin pulso, 120 BPM y 4/4.
/// Copia portátil de `App/Sources/RecordTiming.swift` (W2-R1): misma lógica, sin cambios.
struct BarTiming: Equatable {
    /// Mini-spec Fase 6, «Grabar una toma»: sin pulso, 120 BPM y 4/4.
    static let fallbackBPM = 120.0
    static let fallbackBeatsPerBar = 4

    /// Inicios de compás; vacío si no hay pulso (entonces los compases son múltiplos de `barSeconds` desde 0).
    var downbeats: [Double]
    var beatSeconds: Double
    var beatsPerBar: Int
    var barSeconds: Double { beatSeconds * Double(beatsPerBar) }

    init(_ grid: BeatGrid?) {
        downbeats = grid?.downbeats ?? []
        beatSeconds = 60 / (grid?.bpm ?? Self.fallbackBPM)
        beatsPerBar = grid?.beatsPerBar ?? Self.fallbackBeatsPerBar
    }

    /// Lo mismo desde la rejilla de pulsos de `StudySession` (vacía = sin pulso).
    init(beats: [Double], downbeats: [Double]) {
        self.init(beats.count >= 2 ? BeatGrid(beats: beats, downbeats: downbeats) : nil)
    }

    /// Inicio del backing: `bars` compases antes de `start` (con el pulso, en el inicio de compás); nunca antes de 0.
    func preRollStart(for start: Double, bars: Int) -> Double {
        guard bars > 0 else { return max(0, start) }
        if let last = downbeats.lastIndex(where: { $0 <= start + 0.05 }), last - bars >= 0 {
            return downbeats[last - bars]
        }
        return max(0, start - Double(bars) * barSeconds)
    }

    /// Fin de una toma que empieza en una sección (petición de Jorge, 17/11/2026; mini-spec Fase 6, «Grabar una toma»):
    /// el final de la sección más `bars` compases de cola (el mismo «Margen» que la entrada), sin pasar de `duration`.
    /// Con el pulso la cola se cuenta en inicios de compás; sin él, en `barSeconds`.
    func sectionStop(sectionEnd: Double, bars: Int, duration: Double) -> Double {
        var stop = sectionEnd
        if bars > 0 {
            if let last = downbeats.lastIndex(where: { $0 <= sectionEnd + 0.05 }), last + bars < downbeats.count {
                stop = downbeats[last + bars]
            } else {
                stop = sectionEnd + Double(bars) * barSeconds
            }
        }
        return min(stop, duration)
    }

    /// Compás más cercano a `t` (imán del punch-in).
    func nearestBar(_ t: Double) -> Double {
        if let best = downbeats.min(by: { abs($0 - t) < abs($1 - t) }) { return best }
        return (t / barSeconds).rounded() * barSeconds
    }
}
