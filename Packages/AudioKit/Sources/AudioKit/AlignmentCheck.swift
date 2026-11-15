import Accelerate
import Foundation

/// Error de un clic de la toma de comprobación.
public struct ClickError: Sendable, Equatable {
    /// Instante del tema del clic (s).
    public var songTime: Double
    /// Dónde cae en la toma alineada menos dónde está en el backing, en muestras (positivo = tarde).
    public var errorSamples: Double
    /// Cuánto destaca la primera llegada sobre el fondo de antes de ella (dB), con los tonos del fondo quitados.
    public var peakToFloorDB: Double

    public init(songTime: Double, errorSamples: Double, peakToFloorDB: Double = .nan) {
        self.songTime = songTime
        self.errorSamples = errorSamples
        self.peakToFloorDB = peakToFloorDB
    }
}

/// Tono estrecho y sostenido en el fondo de la toma: la oscilación de un bucle que realimenta.
public struct BackgroundTone: Sendable, Equatable {
    public var frequencyHz: Double
    /// Pico estimado (dBFS).
    public var peakDBFS: Double
    /// Cuánto sobresale de su vecindad espectral (dB).
    public var prominenceDB: Double

    public init(frequencyHz: Double, peakDBFS: Double, prominenceDB: Double) {
        self.frequencyHz = frequencyHz
        self.peakDBFS = peakDBFS
        self.prominenceDB = prominenceDB
    }

    /// Pico mínimo para contar como oscilación del bucle (dBFS). Casos medidos con la Flex Prime (verify del
    /// 15/11/2026): oscilación real de 2793,8 Hz con pico 0,088 (−21 dBFS) y otra de 2255,4 Hz a −18,0 dBFS;
    /// falso positivo: 999,9 Hz a −120,8 dBFS (artefacto de 1 kHz del USB, suelo de ruido).
    public static let feedbackMinPeakDBFS = -60.0
    /// Prominencia mínima sobre el entorno para contar como oscilación (dB): las reales sobresalían hasta 70 dB
    /// (2255,4 Hz); el artefacto de 1 kHz, solo 12 dB.
    public static let feedbackMinProminenceDB = 30.0

    /// Oscilación del bucle (pico ≥ −60 dBFS y ≥ 30 dB sobre su entorno), no suelo de ruido.
    public var isFeedback: Bool {
        peakDBFS >= Self.feedbackMinPeakDBFS && prominenceDB >= Self.feedbackMinProminenceDB
    }
}

/// Resultado de la toma de comprobación (mini-spec Fase 3, «Demostración con hardware»).
public struct AlignmentReport: Sendable, Equatable {
    public var sampleRate: Double
    public var clicks: [ClickError]
    /// Clics que caían dentro de la toma.
    public var expectedClicks: Int
    public var maxAbsErrorSamples: Double
    /// Pendiente de la recta error/tiempo: la deriva sin corregir (lo que importa con dos dispositivos).
    public var slopeSamplesPerMinute: Double
    /// El tono más fuerte quitado del fondo antes de medir (`nil` = fondo sin tonos).
    public var backgroundTone: BackgroundTone? = nil

    /// El bucle oscila (según `BackgroundTone.isFeedback`): la prueba no es concluyente, ni pasa ni falla.
    public var isInconclusive: Bool { backgroundTone?.isFeedback == true }

    public var maxAbsErrorMs: Double { maxAbsErrorSamples / sampleRate * 1000 }
    public var meanErrorSamples: Double { clicks.isEmpty ? .nan : clicks.map(\.errorSamples).reduce(0, +) / Double(clicks.count) }
    /// Pasa si el error máximo es menor de 1 ms y se midieron (casi) todos los clics.
    public var passes: Bool {
        !clicks.isEmpty && Double(clicks.count) >= AlignmentCheck.minMeasuredFraction * Double(expectedClicks)
            && maxAbsErrorSamples < AlignmentCheck.passThresholdSeconds * sampleRate
    }
}

/// Toma de comprobación: backing de clics, y error de cada clic en la toma alineada. La usan `tf-audio verify`,
/// los tests de la puerta y la app («y lo mismo desde la app»).
///
/// Clic: ráfaga de 2 ms a 3 kHz con ventana de Hann, pico 0,5, uno cada 0,5 s desde 0,25 s. Medida: correlación
/// con la ráfaga en ±50 ms alrededor de su sitio, envolvente para el pico grueso, el lóbulo central de |real|
/// (vale con la polaridad invertida) y submuestra por sinc.
public enum AlignmentCheck {
    /// Condición de paso: error menor de 1 ms (mini-spec Fase 3, «Estimación y condición de paso»).
    public static let passThresholdSeconds = 0.001
    /// Fracción mínima de clics medidos para dar el resultado por bueno (decisión propia).
    public static let minMeasuredFraction = 0.9
    /// Duración de la toma de comprobación (mini-spec Fase 3, «Demostración con hardware»: 60 s).
    public static let verifySeconds = 60.0
    public static let clickPeriodSeconds = 0.5
    public static let firstClickSeconds = 0.25
    public static let burstSeconds = 0.002
    public static let burstHz = 3_000.0
    public static let burstPeak = 0.5
    /// Medio ancho de la búsqueda de cada clic (muy por debajo del periodo: sin ambigüedad).
    public static let searchSeconds = 0.05

    /// Ráfaga con un número par de muestras; su centro es la muestra `count / 2`.
    public static func burst(sampleRate fs: Double) -> [Float] {
        let n = 2 * Int((burstSeconds * fs / 2).rounded())
        return (0..<n).map { k in
            let w = 0.5 - 0.5 * cos(2 * Double.pi * Double(k) / Double(n))
            return Float(burstPeak * w * sin(2 * Double.pi * burstHz * Double(k - n / 2) / fs))
        }
    }

    public static func clickTimes(songSeconds: Double) -> [Double] {
        stride(from: firstClickSeconds, to: songSeconds - 0.1, by: clickPeriodSeconds).map { $0 }
    }

    /// Backing mono de clics de `songSeconds`.
    public static func backing(songSeconds: Double, sampleRate fs: Double) -> [Float] {
        let b = burst(sampleRate: fs)
        var x = [Float](repeating: 0, count: Int(songSeconds * fs))
        for c in clickTimes(songSeconds: songSeconds) {
            let start = Int((c * fs).rounded()) - b.count / 2
            for k in 0..<b.count where start + k >= 0 && start + k < x.count { x[start + k] += b[k] }
        }
        return x
    }

    // Fondo con tonos (verify con la Flex Prime, 15/11/2026: el bucle del cable oscilaba a 2793,8 Hz, a 0,088
    // de pico, en plena banda de la ráfaga). Decisiones propias; la spec no da números.
    /// Tramo de fondo de cada periodo: los 150 ms que acaban donde empieza la búsqueda del clic (la cola de
    /// ecos del clic anterior, ~150 ms medidos, ya se ha apagado).
    public static let backgroundSeconds = 0.15
    /// Una línea del fondo se quita si sobresale esto de la mediana de su vecindad.
    public static let toneProminenceDB = 10.0
    /// Vecindad espectral de esa mediana (±): mucho más ancha que un tono, más estrecha que el clic.
    public static let toneNeighbourHz = 200.0

    /// Mide cada clic de `take` (un canal de la toma alineada, muestra 0 en `songStart`) frente a su sitio.
    ///
    /// Antes de correlar se quitan del fondo las líneas estrechas y sostenidas (filtro de fase cero estimado
    /// en los tramos sin clic: no mueve el clic). Se toma la primera llegada, no el máximo, con la regla de la
    /// calibración (el pico más temprano que alcanza el 50 % del mayor), para que un eco del bucle no engañe.
    /// El fondo de cada clic se mide antes de su llegada, donde aún no hay ecos.
    public static func measure(take x: [Float], songStart: Double, sampleRate fs: Double, songSeconds: Double) -> AlignmentReport {
        let b = burst(sampleRate: fs)
        let half = b.count / 2
        let w = Int(searchSeconds * fs)
        let carrier = max(1, Int(fs / burstHz / 2))
        let startFrame = Int((songStart * fs).rounded())
        let segLen = 2 * w + b.count
        let n = SignalMath.nextPow2(3 * segLen)
        let centres = clickTimes(songSeconds: songSeconds).map { ($0, Int(($0 * fs).rounded()) - startFrame) }
        let bg = background(x, centres: centres.map(\.1), searchStartOffset: half + w, n: n, sampleRate: fs)
        var out: [ClickError] = []
        var expected = 0
        for (c, e) in centres {
            let segStart = e - half - w
            guard e - half >= 0, e + half <= x.count else { continue }
            expected += 1
            guard segStart >= 0, segStart + segLen <= x.count else { continue }
            let seg = bg.weight.map { filtered(x, from: segStart, count: segLen, weight: $0) }
                ?? Array(x[segStart..<(segStart + segLen)])
            let (real, env) = SignalMath.analyticCorrelation(signal: seg, template: b)
            var top = 0.0
            for i in 0...(2 * w) { top = max(top, env[i]) }
            guard top > 1e-9 else { continue }
            var k = 0
            while k < 2 * w && env[k] < LatencyProbe.firstArrivalFraction * top { k += 1 }
            while k < 2 * w && env[k + 1] >= env[k] { k += 1 }
            var m = k
            for i in max(0, k - carrier)...min(2 * w, k + carrier) where abs(real[i]) > abs(real[m]) { m = i }
            let tau = SignalMath.refinePeak(real, near: m)
            let floorEnd = k - b.count - carrier
            let floor = floorEnd >= b.count ? SignalMath.median(Array(env[0..<floorEnd])) : SignalMath.median(Array(env[0...(2 * w)]))
            let db = 20 * log10(max(env[k], 1e-300) / max(floor, 1e-300))
            out.append(ClickError(songTime: c, errorSamples: tau - Double(w), peakToFloorDB: db))
        }
        return AlignmentReport(sampleRate: fs, clicks: out, expectedClicks: expected,
                               maxAbsErrorSamples: out.map { abs($0.errorSamples) }.max() ?? .nan,
                               slopeSamplesPerMinute: slope(out), backgroundTone: bg.tone)
    }

    /// Espectro medio de los tramos de fondo y el peso que quita sus líneas (`nil` si no hay ninguna).
    static func background(_ x: [Float], centres: [Int], searchStartOffset: Int, n: Int,
                           sampleRate fs: Double) -> (weight: [Double]?, tone: BackgroundTone?) {
        let len = Int(backgroundSeconds * fs)
        var p = [Double](repeating: 0, count: n / 2 + 1)
        var count = 0
        for e in centres {
            let to = e - searchStartOffset, from = to - len
            guard from >= 0, to <= x.count else { continue }
            let s = SignalMath.powerSpectrum(x[from..<to], n: n)
            vDSP_vaddD(p, 1, s, 1, &p, 1, vDSP_Length(p.count))
            count += 1
        }
        guard count > 0 else { return (nil, nil) }
        var scale = 1 / Double(count)
        vDSP_vsmulD(p, 1, &scale, &p, 1, vDSP_Length(p.count))
        let prominence = pow(10, toneProminenceDB / 10)
        let (g, med) = SignalMath.lineSuppressionWeight(p, prominence: prominence, neighbourBins: Int(toneNeighbourHz / fs * Double(n)))
        guard g.contains(where: { $0 < 1 }) else { return (nil, nil) }
        // El tono más prominente: frecuencia por parábola en dB y pico por la ganancia de Hann (A·len/4).
        var k = 1
        for i in 1..<(p.count - 1) where p[i] / max(med[i], 1e-300) > p[k] / max(med[k], 1e-300) { k = i }
        let y0 = 10 * log10(max(p[k - 1], 1e-300)), y1 = 10 * log10(max(p[k], 1e-300)), y2 = 10 * log10(max(p[k + 1], 1e-300))
        let d = y0 - 2 * y1 + y2
        let off = d < 0 ? 0.5 * (y0 - y2) / d : 0
        let amp = 4 * p[k].squareRoot() / Double(len)
        let tone = BackgroundTone(frequencyHz: (Double(k) + off) * fs / Double(n), peakDBFS: 20 * log10(max(amp, 1e-15)),
                                  prominenceDB: 10 * log10(p[k] / max(med[k], 1e-300)))
        return (g, tone)
    }

    /// `x[from..<from+count]` filtrado con `weight`, con márgenes a cada lado (hasta `count`, sin salir de `x`)
    /// que se atenúan con media Hann para que el corte no deje transitorios dentro del tramo.
    static func filtered(_ x: [Float], from: Int, count: Int, weight: [Double]) -> [Float] {
        let lo = max(0, from - count), hi = min(x.count, from + 2 * count)
        var ext = Array(x[lo..<hi])
        let pre = from - lo, post = hi - (from + count)
        for i in 0..<pre { ext[i] *= Float(0.5 - 0.5 * cos(Double.pi * Double(i) / Double(pre))) }
        for i in 0..<post { ext[ext.count - 1 - i] *= Float(0.5 - 0.5 * cos(Double.pi * Double(i) / Double(post))) }
        let y = SignalMath.zeroPhaseFilter(ext, weight: weight)
        return Array(y[pre..<(pre + count)])
    }

    /// Recta de mínimos cuadrados del error frente al tiempo, en muestras por minuto.
    static func slope(_ e: [ClickError]) -> Double {
        guard e.count >= 2 else { return 0 }
        let n = Double(e.count)
        let mx = e.map(\.songTime).reduce(0, +) / n, my = e.map(\.errorSamples).reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0
        for p in e {
            sxy += (p.songTime - mx) * (p.errorSamples - my)
            sxx += (p.songTime - mx) * (p.songTime - mx)
        }
        return sxx > 0 ? sxy / sxx * 60 : 0
    }
}
