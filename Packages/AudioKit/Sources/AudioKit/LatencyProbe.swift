import NativeDSP
import Foundation

/// Por qué no vale una calibración (mini-spec Fase 3, «Calibración de latencia» · Resultado).
public enum LatencyFailure: String, Sendable, Equatable, Codable {
    /// El barrido no destaca 20 dB sobre el fondo: falta el cable.
    case noSignal
    /// La entrada llega al tope del conversor: bajar volumen.
    case saturated
    /// Dispersión de las 9 medidas por encima de 0,1 ms.
    case unstable
}

/// Medida de un canal de entrada.
public struct LatencyChannelMeasurement: Sendable, Equatable {
    /// Canal de entrada, desde 1.
    public var channel: Int
    /// Latencia de cada repetición válida (la primera se descarta), en muestras con decimales.
    public var lagsSamples: [Double]
    /// Mediana de `lagsSamples`.
    public var latencySamples: Double
    /// Máximo menos mínimo de `lagsSamples`.
    public var spreadSamples: Double
    /// Peor (menor) relación primera llegada / fondo de la correlación entre repeticiones, en dB.
    public var peakToFloorDB: Double
    /// Pico de la entrada en las repeticiones medidas (lineal, 1 = fondo de escala).
    public var inputPeak: Float
    public var failure: LatencyFailure?

    public var isValid: Bool { failure == nil }

    /// Público para que `tf-audio` restaure una calibración guardada en `Temp/`.
    public init(channel: Int, lagsSamples: [Double], latencySamples: Double, spreadSamples: Double,
                peakToFloorDB: Double, inputPeak: Float, failure: LatencyFailure?) {
        self.channel = channel
        self.lagsSamples = lagsSamples
        self.latencySamples = latencySamples
        self.spreadSamples = spreadSamples
        self.peakToFloorDB = peakToFloorDB
        self.inputPeak = inputPeak
        self.failure = failure
    }
}

/// Señal de calibración y su análisis (mini-spec Fase 3, «Calibración de latencia»): barrido logarítmico,
/// filtro adaptado, primera llegada, submuestra por sinc, mediana y dispersión. Valor puro.
public struct LatencyProbe: Sendable {
    // Señal (mini-spec Fase 3, «Calibración de latencia» · Señal).
    public static let startHz = 500.0
    public static let endHz = 8_000.0
    public static let sweepSeconds = 0.100
    public static let fadeSeconds = 0.005
    public static let levelDBFS = -12.0
    public static let repetitions = 10
    /// Repeticiones descartadas al principio.
    public static let discarded = 1
    public static let periodSeconds = 0.500

    // Detección y resultado (mini-spec Fase 3, «Calibración de latencia» · Detección y Resultado).
    /// Primera llegada: el pico más temprano que alcance esta fracción del mayor.
    public static let firstArrivalFraction = 0.5
    /// Dispersión máxima para dar la calibración por válida.
    public static let maxSpreadSeconds = 0.000_1
    /// El pico debe destacar esto sobre el fondo.
    public static let minPeakToFloorDB = 20.0
    /// Decisión propia (la spec no da número): la entrada se da por saturada si llega al 99 % del fondo
    /// de escala en las repeticiones medidas. Una saturación suave del rig sin recorte no cuenta.
    public static let clipLevel: Float = 0.99

    /// Muestras de correlación a cada lado de la ventana de búsqueda que necesita la interpolación.
    static let margin = SignalMath.sincHalfWidth + 8
    /// Medio ancho (muestras) de la búsqueda del pico de la portadora alrededor del de la envolvente:
    /// la portadora del filtro adaptado ronda 2,7 kHz (≥ 16 muestras de periodo a 44,1 kHz).
    static let carrierSearch = 4

    public let sampleRate: Double
    /// Un barrido, a −12 dBFS de pico.
    public let sweep: [Float]
    public let periodFrames: Int

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        sweep = Self.makeSweep(sampleRate: sampleRate)
        periodFrames = Int((Self.periodSeconds * sampleRate).rounded())
    }

    /// Duración del estímulo y de la captura necesaria, desde la salida del primer barrido.
    public var captureFrames: Int { Self.repetitions * periodFrames }

    /// Latencia máxima medible: la llegada debe caber entera dentro de su periodo.
    public var maxLatencyFrames: Int { periodFrames - sweep.count }

    public var maxSpreadSamples: Double { Self.maxSpreadSeconds * sampleRate }

    /// Muestra `i` del estímulo (0 = salida del primer barrido).
    public func stimulus(at i: Int) -> Float {
        guard i >= 0, i < captureFrames else { return 0 }
        let off = i % periodFrames
        return off < sweep.count ? sweep[off] : 0
    }

    static func makeSweep(sampleRate fs: Double) -> [Float] {
        let n = Int((sweepSeconds * fs).rounded())
        let fade = Int((fadeSeconds * fs).rounded())
        let amp = pow(10, levelDBFS / 20)
        let k = sweepSeconds / log(endHz / startHz)
        return (0..<n).map { i in
            let t = Double(i) / fs
            var w = 1.0
            if i < fade { w = 0.5 - 0.5 * cos(Double.pi * Double(i) / Double(fade)) }
            if i >= n - fade { w = 0.5 - 0.5 * cos(Double.pi * Double(n - 1 - i) / Double(fade)) }
            return Float(amp * w * sin(2 * Double.pi * startHz * k * (exp(t / k) - 1)))
        }
    }

    /// Analiza lo grabado por un canal. `recording[0]` es la muestra de entrada marcada en el mismo instante
    /// en que salió el primer barrido.
    public func analyze(_ recording: [Float], channel: Int) -> LatencyChannelMeasurement {
        let m = Self.margin
        var lags: [Double] = []
        var worstDB = Double.infinity
        var peak: Float = 0
        for r in Self.discarded..<Self.repetitions {
            let from = r * periodFrames - m
            let to = (r + 1) * periodFrames
            var seg = [Float](repeating: 0, count: to - from)
            for i in 0..<seg.count where from + i >= 0 && from + i < recording.count { seg[i] = recording[from + i] }
            var p: Float = 0
            DSP.maxmgv(seg, 1, &p, DSPLength(seg.count))
            peak = max(peak, p)
            let rep = measure(seg)
            lags.append(rep.lag)
            worstDB = min(worstDB, rep.peakToFloorDB)
        }
        let median = SignalMath.median(lags)
        let spread = (lags.max() ?? 0) - (lags.min() ?? 0)
        let clipped = peak >= Self.clipLevel
        let failure: LatencyFailure?
        if worstDB < Self.minPeakToFloorDB {
            failure = clipped ? .saturated : .noSignal
        } else if clipped {
            failure = .saturated
        } else if spread > maxSpreadSamples {
            failure = .unstable
        } else {
            failure = nil
        }
        return LatencyChannelMeasurement(channel: channel, lagsSamples: lags, latencySamples: median, spreadSamples: spread,
                                         peakToFloorDB: worstDB, inputPeak: peak, failure: failure)
    }

    /// Una repetición: `seg[margin]` es el instante de salida del barrido.
    func measure(_ seg: [Float]) -> (lag: Double, peakToFloorDB: Double) {
        let m = Self.margin
        let (c, env) = SignalMath.analyticCorrelation(signal: seg, template: sweep)
        let lo = m, hi = m + maxLatencyFrames
        var top = 0.0
        for k in lo...hi { top = max(top, env[k]) }
        let floor = SignalMath.median(Array(env[lo...hi]))
        // Primera llegada: primer punto que alcanza la fracción del mayor, y su máximo local de envolvente.
        var k = lo
        while k < hi && env[k] < Self.firstArrivalFraction * top { k += 1 }
        while k < hi && env[k + 1] >= env[k] { k += 1 }
        var ratioDB = 20 * log10(max(env[k], 1e-300) / max(floor, 1e-300))
        if let clean = lineFreePeakToFloorDB(seg, arrival: k, lo: lo, hi: hi) { ratioDB = clean }
        // Pico de la portadora (con signo: |c|) cerca del de la envolvente, y submuestra por sinc.
        var best = k
        for j in max(0, k - Self.carrierSearch)...min(c.count - 1, k + Self.carrierSearch) where abs(c[j]) > abs(c[best]) {
            best = j
        }
        let t = SignalMath.refinePeak(c, near: best)
        return (t - Double(m), ratioDB)
    }

    /// Pico sobre el fondo sin las líneas estrechas y sostenidas del fondo (la oscilación del bucle: con la
    /// Flex Prime y el rig vacío, un tono de 2793,8 Hz que ponía el fondo a 19–21 dB del pico, cuando el ruido
    /// queda a ~65 dB). Solo cambia la medida del fondo, no la latencia. Las líneas se estiman en lo que queda
    /// de la repetición tras la llegada, el barrido y su cola; `nil` si no queda tramo de fondo o no hay líneas.
    func lineFreePeakToFloorDB(_ seg: [Float], arrival k: Int, lo: Int, hi: Int) -> Double? {
        let len = Int(AlignmentCheck.backgroundSeconds * sampleRate)
        let from = k + sweep.count + len
        guard from + len <= seg.count, k > 2 * Self.carrierSearch else { return nil }
        let n = SignalMath.nextPow2(seg.count)
        let p = SignalMath.powerSpectrum(seg[from..<seg.count], n: n)
        let (g, _) = SignalMath.lineSuppressionWeight(p, prominence: pow(10, AlignmentCheck.toneProminenceDB / 10),
                                                      neighbourBins: Int(AlignmentCheck.toneNeighbourHz / sampleRate * Double(n)))
        guard g.contains(where: { $0 < 1 }) else { return nil }
        // Bordes atenuados (media Hann) antes de la llegada y en el tramo de fondo: el corte no deja transitorios.
        var x = seg
        let taper = len / 4
        let pre = min(k / 2, taper)
        for i in 0..<pre { x[i] *= Float(0.5 - 0.5 * cos(Double.pi * Double(i) / Double(pre))) }
        let post = min(seg.count - from, taper)
        for i in 0..<post { x[seg.count - 1 - i] *= Float(0.5 - 0.5 * cos(Double.pi * Double(i) / Double(post))) }
        let (_, env) = SignalMath.analyticCorrelation(signal: SignalMath.zeroPhaseFilter(x, weight: g), template: sweep)
        var top = 0.0
        for j in max(lo, k - 2 * Self.carrierSearch)...min(hi, k + 2 * Self.carrierSearch) { top = max(top, env[j]) }
        let floor = SignalMath.median(Array(env[lo...hi]))
        return 20 * log10(max(top, 1e-300) / max(floor, 1e-300))
    }
}
