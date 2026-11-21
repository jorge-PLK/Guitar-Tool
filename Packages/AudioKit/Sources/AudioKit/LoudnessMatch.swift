import NativeDSP
import Foundation

/// Igualado de sonoridad de la toma frente al stem (mini-spec Fase 3, «A/B dentro de la mezcla»): RMS con
/// ponderación K (filtro de ITU-R BS.1770) sobre el tramo de la toma, sin contar silencios, tope ±12 dB.
///
/// «Sin contar silencios» se hace con la puerta de BS.1770-4: bloques de 400 ms con salto de 100 ms,
/// puerta absoluta de −70 LKFS y relativa de −10 LU. Una señal mono cuenta como si sonara por los dos
/// canales (así suena la toma en la mezcla).
public enum LoudnessMatch {
    /// Tope de la ganancia (mini-spec Fase 3, «A/B»).
    public static let maxGainDB = 12.0
    // BS.1770-4.
    static let blockSeconds = 0.4
    static let hopSeconds = 0.1
    static let absoluteGateLKFS = -70.0
    static let relativeGateLU = -10.0

    public struct Result: Sendable, Equatable {
        /// Ganancia a aplicar a la toma, con tope.
        public var gainDB: Double
        /// Sin tope (`nil` si alguna de las dos señales es silencio).
        public var unclampedGainDB: Double?
        public var takeLKFS: Double?
        public var stemLKFS: Double?
    }

    /// Ganancia de `take` frente a `stem`, ya recortado al tramo de la toma.
    public static func gain(take: [[Float]], stem: [[Float]], sampleRate: Double) -> Result {
        let lt = loudness(take, sampleRate: sampleRate)
        let ls = loudness(stem, sampleRate: sampleRate)
        guard let lt, let ls else { return Result(gainDB: 0, unclampedGainDB: nil, takeLKFS: lt, stemLKFS: ls) }
        let g = ls - lt
        return Result(gainDB: min(max(g, -maxGainDB), maxGainDB), unclampedGainDB: g, takeLKFS: lt, stemLKFS: ls)
    }

    /// Igual, recortando el stem entero al tramo `[songStart, songStart + duración de la toma)`.
    public static func gain(take: [[Float]], stem: [[Float]], songStart: Double, sampleRate: Double) -> Result {
        let from = max(0, Int((songStart * sampleRate).rounded()))
        let len = take.first?.count ?? 0
        let slice = stem.map { ch -> [Float] in
            let a = min(from, ch.count), b = min(from + len, ch.count)
            return Array(ch[a..<b])
        }
        return gain(take: take, stem: slice, sampleRate: sampleRate)
    }

    /// Sonoridad integrada con puerta (LKFS); `nil` si no pasa ningún bloque.
    public static func loudness(_ channels: [[Float]], sampleRate: Double) -> Double? {
        guard let count = channels.first?.count, count > 0 else { return nil }
        let weighted = channels.map { kWeighted($0, sampleRate: sampleRate) }
        let channelWeight = channels.count == 1 ? 2.0 : 1.0
        let block = min(count, Int((blockSeconds * sampleRate).rounded()))
        let hop = max(1, Int((hopSeconds * sampleRate).rounded()))
        var z: [Double] = []
        var start = 0
        while start + block <= count {
            var sum = 0.0
            for ch in weighted {
                var ms: Float = 0
                ch.withUnsafeBufferPointer { DSP.measqv($0.baseAddress! + start, 1, &ms, DSPLength(block)) }
                sum += Double(ms)
            }
            z.append(channelWeight * sum)
            start += hop
        }
        func lk(_ v: Double) -> Double { -0.691 + 10 * log10(max(v, 1e-30)) }
        let abs = z.filter { lk($0) > absoluteGateLKFS }
        guard !abs.isEmpty else { return nil }
        let gate = lk(abs.reduce(0, +) / Double(abs.count)) + relativeGateLU
        let rel = abs.filter { lk($0) > gate }
        guard !rel.isEmpty else { return nil }
        return lk(rel.reduce(0, +) / Double(rel.count))
    }

    /// Coeficientes `[b0, b1, b2, a1, a2]` de las dos etapas del filtro K (estante alto y paso alto RLB),
    /// calculados para `sampleRate` con los parámetros analógicos de BS.1770 y la transformación bilineal
    /// que usa libebur128 (a 48 kHz dan la tabla de la norma).
    static func kWeightingCoefficients(sampleRate fs: Double) -> [[Double]] {
        // Estante alto.
        let f0 = 1_681.974450955533, g = 3.999843853973347, q = 0.7071752369554196
        let k = tan(Double.pi * f0 / fs)
        let vh = pow(10, g / 20), vb = pow(vh, 0.4996667741545416)
        let a0 = 1 + k / q + k * k
        let shelf = [(vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0,
                     2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]
        // Paso alto (numerador 1, −2, 1 como en la norma).
        let fh = 38.13547087602444, qh = 0.5003270373238773
        let kh = tan(Double.pi * fh / fs)
        let h0 = 1 + kh / qh + kh * kh
        let highpass = [1, -2, 1, 2 * (kh * kh - 1) / h0, (1 - kh / qh + kh * kh) / h0]
        return [shelf, highpass]
    }

    static func kWeighted(_ x: [Float], sampleRate: Double) -> [Float] {
        let coeffs = kWeightingCoefficients(sampleRate: sampleRate).flatMap { $0 }
        guard let setup = DSP.Biquad(coefficients: coeffs, sections: 2) else { return x }
            var delay = [Float](repeating: 0, count: 2 * 2 + 2)
        var y = [Float](repeating: 0, count: x.count)
        setup.execute(&delay, x, 1, &y, 1, DSPLength(x.count))
        return y
    }
}
