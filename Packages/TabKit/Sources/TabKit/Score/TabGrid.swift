import Foundation

/// Pulsos y primeros pulsos de compás en segundos de canción. TabKit no depende de StudyKit: la app lo rellena
/// desde `BeatGrid` (`beats`, `downbeats`, `beatsPerBar`).
public struct BeatTimes: Sendable, Equatable {
    public var beats: [Double]
    /// Subconjunto de `beats` (si no coincide, cada uno se lleva a su pulso más cercano).
    public var downbeats: [Double]
    /// nil: la moda de pulsos entre downbeats, o 4.
    public var beatsPerBar: Int?

    public init(beats: [Double], downbeats: [Double], beatsPerBar: Int? = nil) {
        self.beats = beats
        self.downbeats = downbeats
        self.beatsPerBar = beatsPerBar
    }
}

public enum TabScoreError: Error, Equatable, Sendable {
    /// Hacen falta al menos dos pulsos para conocer el periodo.
    case notEnoughBeats
}

/// Posición continua en la partitura, para el cursor: compás, pulso dentro del compás y fracción del pulso (0…1).
public struct ScorePosition: Sendable, Equatable {
    public var bar: Int
    public var beatInBar: Int
    public var beatFraction: Double

    public init(bar: Int, beatInBar: Int, beatFraction: Double) {
        self.bar = bar
        self.beatInBar = beatInBar
        self.beatFraction = beatFraction
    }
}

extension TabScore {
    /// Un compás cambia el tempo escrito si su duración se aleja más de esto de la que da el tempo real vigente
    /// (mini-spec Fase 5, «Rejilla»).
    public static let tempoChangeThreshold = 0.02
    /// Deriva máxima entre el inicio escrito de un compás (sumando duraciones al tempo escrito entero desde el
    /// primero) y su inicio real; si se supera, ese compás lleva el entero que más la reduce al final de él
    /// (mini-spec Fase 5, «Rejilla»).
    public static let maxWrittenDrift = 0.020
    /// El tempo real de un tramo es la mediana del de este número de compases desde el que lo abre (o los que
    /// queden) (mini-spec Fase 5, «Rejilla»).
    static let baseTempoBars = 4
    /// Holgura numérica de la comparación con `maxWrittenDrift` (sumas de `Double`).
    static let driftEpsilon = 1e-9
    /// La rejilla se extiende con el periodo local mientras quede antes del primer pulso (o tras el último) más de
    /// esta fracción de periodo: lo que quede dentro se cuantiza igual al pulso extremo (media semicorchea).
    static let extensionSlack = 1.0 / 8
    /// Distancia máxima (en periodos) para dar por bueno el pulso más cercano a un downbeat.
    static let downbeatMatchFraction = 0.5

    /// Rejilla vacía (sin pistas) que cubre `0…duration` segundos de canción.
    ///
    /// - Los compases empiezan exactamente en los downbeats (mismo `Double`), y cada pulso conserva su tiempo.
    /// - Pulsos antes del primer downbeat: compases de `beatsPerBar` contados hacia atrás y una anacrusa con el resto.
    /// - Antes del primer pulso y tras el último se añaden pulsos con el periodo del extremo; el último compás se
    ///   completa hasta `beatsPerBar`. El primer pulso puede quedar en tiempo negativo.
    public init(beatTimes: BeatTimes, duration: Double) throws {
        var times: [Double] = []
        for t in beatTimes.beats.sorted() where times.last.map({ t - $0 > 1e-6 }) ?? true { times.append(t) }
        guard times.count >= 2 else { throw TabScoreError.notEnoughBeats }

        var down = Self.downbeatIndices(beatTimes.downbeats, in: times)
        let perBar = max(1, beatTimes.beatsPerBar ?? Self.modeBeatsPerBar(down) ?? 4)
        if down.isEmpty { down = [0] }

        let firstPeriod = times[1] - times[0]
        var prepended = 0
        var head: [Double] = []
        var first = times[0]
        while first > firstPeriod * Self.extensionSlack {
            first -= firstPeriod
            head.append(first)
            prepended += 1
        }
        times = head.reversed() + times
        down = down.map { $0 + prepended }

        let lastPeriod = times[times.count - 1] - times[times.count - 2]
        var end = times[times.count - 1] + lastPeriod
        while end < duration - lastPeriod * Self.extensionSlack {
            times.append(end)
            end += lastPeriod
        }

        // Compases como (primer pulso, número de pulsos).
        var ranges: [(first: Int, count: Int)] = []
        let d0 = down[0]
        if d0 > 0 {
            var i = d0 % perBar
            if i > 0 { ranges.append((0, i)) }
            while i < d0 { ranges.append((i, perBar)); i += perBar }
        }
        for (j, d) in down.enumerated() where j + 1 < down.count {
            ranges.append((d, down[j + 1] - d))
        }
        let last = down[down.count - 1]
        let pad = (perBar - (times.count - last) % perBar) % perBar
        for _ in 0..<pad {
            times.append(end)
            end += lastPeriod
        }
        var i = last
        while i < times.count { ranges.append((i, perBar)); i += perBar }

        var beats: [TabBeat] = []
        beats.reserveCapacity(times.count)
        for (barIndex, r) in ranges.enumerated() {
            for k in 0..<r.count { beats.append(TabBeat(time: times[r.first + k], bar: barIndex, indexInBar: k)) }
        }

        // Tempo escrito, siempre entero. `base` es el tempo real vigente: pasa al real del compás si este se aleja
        // > 2 % de él (la comparación es con el real, no con su redondeo, para que el redondeo no dispare cambios);
        // se escribe `base` redondeado. Si además el inicio escrito del compás se ha separado del real más de
        // `maxWrittenDrift`, ese compás lleva el entero que más reduce la deriva a su final y `base` pasa al real del
        // compás; el compás siguiente vuelve a `base` redondeado (si no, la corrección se quedaría como tempo vigente
        // y la deriva oscilaría de signo compás a compás). A tempo real no entero constante esto da correcciones
        // periódicas: el redondeo deriva un poco en cada compás y cada pocos compases un entero lo devuelve.
        // Cada vez que `base` se fija (primer compás, regla del 2 %, corrección) toma la mediana del tempo real de
        // ese compás y los `baseTempoBars − 1` siguientes, para que el jitter de un solo compás no mueva el entero.
        let starts = ranges.map { times[$0.first] }
        let barSeconds = starts.indices.map { ($0 + 1 < starts.count ? starts[$0 + 1] : end) - starts[$0] }
        let actuals = ranges.indices.map { 60 * Double(ranges[$0].count) / barSeconds[$0] }
        func tramoTempo(_ i: Int) -> Double { Self.median(actuals[i..<min(i + Self.baseTempoBars, actuals.count)]) }
        var bars: [TabBar] = []
        var base = 0.0
        var writtenStart = starts[0]
        for (barIndex, r) in ranges.enumerated() {
            let start = starts[barIndex]
            let seconds = barSeconds[barIndex]
            var written: Double
            if barIndex == 0 {
                base = tramoTempo(barIndex)
                written = Self.writtenTempo(base)
            } else {
                let expected = 60 * Double(r.count) / base
                if abs(seconds - expected) / expected > Self.tempoChangeThreshold { base = tramoTempo(barIndex) }
                written = Self.writtenTempo(base)
                let drift = writtenStart - start
                if abs(drift) > Self.maxWrittenDrift + Self.driftEpsilon {
                    base = tramoTempo(barIndex)
                    written = Self.correctionTempo(beats: r.count, seconds: seconds, drift: drift)
                }
            }
            bars.append(TabBar(start: start, firstBeat: r.first, beatCount: r.count, tempo: written))
            writtenStart += 60 * Double(r.count) / written
        }
        self.init(bars: bars, beats: beats, endTime: end)
    }

    /// Mediana (media de los dos centrales si son pares); vacía, 0.
    static func median(_ values: ArraySlice<Double>) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    /// Tempo escrito de un tempo real: el entero más cercano (mínimo 1).
    static func writtenTempo(_ actual: Double) -> Double { max(1, actual.rounded()) }

    /// Entero que deja el final escrito de un compás de `beats` pulsos más cerca de su final real, partiendo de una
    /// deriva `drift` (inicio escrito − inicio real). El ideal es `fin real − inicio escrito`; la deriva cabe en un
    /// compás (≤ 20 ms + lo que derive uno), así que la resta es positiva y el `max` solo protege de rejillas
    /// absurdas. Lo que queda tras el mejor entero es como mucho media diferencia de duración entre dos enteros
    /// consecutivos (≈ 30·beats/T² s: 8,6 ms en 4/4 a 118 BPM).
    static func correctionTempo(beats: Int, seconds: Double, drift: Double) -> Double {
        let ideal = 60 * Double(beats) / max(seconds - drift, seconds / 2)
        func residual(_ tempo: Double) -> Double { abs(drift + 60 * Double(beats) / tempo - seconds) }
        let lo = max(1, ideal.rounded(.down)), hi = max(1, ideal.rounded(.up))
        return residual(hi) < residual(lo) ? hi : lo
    }

    static func downbeatIndices(_ downbeats: [Double], in times: [Double]) -> [Int] {
        var out = Set<Int>()
        for d in downbeats {
            let i = nearestIndex(times, d)
            let period = i + 1 < times.count ? times[i + 1] - times[i] : times[i] - times[i - 1]
            if abs(times[i] - d) <= period * downbeatMatchFraction { out.insert(i) }
        }
        return out.sorted()
    }

    static func modeBeatsPerBar(_ down: [Int]) -> Int? {
        guard down.count >= 2 else { return nil }
        var counts: [Int: Int] = [:]
        for (a, b) in zip(down, down.dropFirst()) { counts[b - a, default: 0] += 1 }
        return counts.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key
    }

    static func nearestIndex(_ sorted: [Double], _ t: Double) -> Int {
        let u = upperBound(sorted, t)
        if u == 0 { return 0 }
        if u == sorted.count { return sorted.count - 1 }
        return t - sorted[u - 1] <= sorted[u] - t ? u - 1 : u
    }

    /// Primer índice con `sorted[i] > t`.
    static func upperBound(_ sorted: [Double], _ t: Double) -> Int {
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] <= t { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    // MARK: Tiempo ↔ posición

    /// Inicio del pulso `b`; `beats.count` da `endTime`.
    func beatStart(_ b: Int) -> Double { b < beats.count ? beats[max(0, b)].time : endTime }

    /// Segundos de canción de un punto de la rejilla (interpolación lineal dentro del pulso).
    public func time(of point: GridPoint) -> Double {
        let abs = min(max(0, point.absoluteTick), totalTicks)
        let b = abs / Self.ticksPerBeat
        guard b < beats.count else { return endTime }
        let t0 = beats[b].time
        return t0 + Double(abs % Self.ticksPerBeat) / Double(Self.ticksPerBeat) * (beatStart(b + 1) - t0)
    }

    /// Inicio y fin de una nota en segundos de canción.
    public func timeRange(of note: TabNote) -> Range<Double> { time(of: note.start)..<time(of: note.end) }

    /// Compás, pulso y fracción de pulso de un instante (se satura en los extremos de la rejilla).
    public func position(at time: Double) -> ScorePosition {
        let b = min(max(0, Self.upperBound(beats.map(\.time), time) - 1), beats.count - 1)
        let t0 = beats[b].time, t1 = beatStart(b + 1)
        let fraction = min(max(0, (time - t0) / (t1 - t0)), 1)
        return ScorePosition(bar: beats[b].bar, beatInBar: beats[b].indexInBar, beatFraction: fraction)
    }

    /// Instante de una posición; nil si el compás o el pulso no existen.
    public func time(at position: ScorePosition) -> Double? {
        guard bars.indices.contains(position.bar), (0..<bars[position.bar].beatCount).contains(position.beatInBar)
        else { return nil }
        let b = bars[position.bar].firstBeat + position.beatInBar
        let t0 = beats[b].time
        return t0 + position.beatFraction * (beatStart(b + 1) - t0)
    }

    /// Punto válido más cercano a `time` en la rejilla de la pista (para «añadir en la posición del cursor»).
    public func nearestPoint(to time: Double, in track: TabTrack) -> GridPoint {
        GridPoint(absoluteTick: snapTick(time, subdivisions: track.subdivisions, allowEnd: false))
    }

    // MARK: Cuantización (interna)

    /// Pulso que contiene `time` (saturado a 0…beats.count-1) y fracción del pulso (sin saturar).
    func beatAndFraction(_ time: Double, times: [Double]? = nil) -> (beat: Int, fraction: Double) {
        let b = min(max(0, Self.upperBound(times ?? beats.map(\.time), time) - 1), beats.count - 1)
        let t0 = beats[b].time
        return (b, (time - t0) / (beatStart(b + 1) - t0))
    }

    /// Subdivisión de cada pulso: la de menor error cuadrático con los ataques del pulso; empate, semicorcheas.
    func chooseSubdivisions(onsets: [Double]) -> [Subdivision] {
        var errors = [(six: Double, trip: Double)](repeating: (0, 0), count: beats.count)
        let times = beats.map(\.time)
        for t in onsets {
            let b = min(max(0, Self.upperBound(times, t) - 1), beats.count - 1)
            let fraction = min(max(0, (t - times[b]) / (beatStart(b + 1) - times[b])), 1)
            func err(_ steps: Double) -> Double {
                let x = fraction * steps
                return ((x - x.rounded()) / steps) * ((x - x.rounded()) / steps)
            }
            errors[b].six += err(4)
            errors[b].trip += err(3)
        }
        return errors.map { $0.trip < $0.six - 1e-12 ? .eighthTriplets : .sixteenths }
    }

    /// Tick absoluto del punto más cercano a `time` dentro de su pulso (o el inicio del siguiente).
    /// `allowEnd`: el final de la rejilla (`totalTicks`) es válido (finales de nota), si no se usa el último punto.
    func snapTick(_ time: Double, subdivisions: [Subdivision], allowEnd: Bool, times: [Double]? = nil) -> Int {
        let (b, rawFraction) = beatAndFraction(time, times: times)
        let sub = subdivisions[b]
        let k = Int((min(max(0, rawFraction), 1) * Double(sub.steps)).rounded())
        let tick = b * Self.ticksPerBeat + k * sub.tickStep
        if tick >= totalTicks && !allowEnd { return totalTicks - subdivisions[beats.count - 1].tickStep }
        return tick
    }

    /// Ticks del punto `tick` según la subdivisión de su pulso; el final de la rejilla también es válido.
    func isValidPoint(_ tick: Int, subdivisions: [Subdivision], allowEnd: Bool) -> Bool {
        if tick == totalTicks { return allowEnd }
        guard tick >= 0, tick < totalTicks else { return false }
        return (tick % Self.ticksPerBeat) % subdivisions[tick / Self.ticksPerBeat].tickStep == 0
    }
}
