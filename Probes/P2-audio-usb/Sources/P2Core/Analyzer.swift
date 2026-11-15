import Foundation

public struct ChannelStats {
    public let index: Int            // 0-based
    public let rmsDb: Double
    public let peakDb: Double
    public let crestDb: Double
    public let centroidHz: Double
    public let active: Bool
    /// Puntuación de "limpieza": alta = seco (cresta alta, centroide bajo). nil si el canal está inactivo.
    public let dryScore: Double?
}

public struct AnalysisReport {
    public let sampleRate: Double
    public let channels: [ChannelStats]
    /// Correlación normalizada a retardo 0 (Pearson), [i][j].
    public let correlation: [[Double]]
    /// Máximo |correlación normalizada| dentro de ±maxLagMs, y el retardo (muestras) donde ocurre (j respecto a i).
    public let bestCorrelation: [[Double]]
    public let bestLagSamples: [[Int]]
    public let suggestedDI: Int?
    public let suggestedProcessed: Int?
    public let note: String
}

public enum Analyzer {
    /// Por debajo de este RMS (dBFS) un canal se considera sin señal.
    public static let activeRmsDb = -70.0
    /// Peso del centroide en la puntuación de limpieza: dB de cresta por octava de centroide.
    public static let centroidWeightDbPerOctave = 4.0
    /// Diferencia de puntuación por debajo de la cual DI/procesado se declaran ambiguos.
    public static let ambiguousScoreGap = 3.0
    /// Correlación por encima de la cual dos canales se consideran la misma señal.
    public static let duplicateCorrelation = 0.99
    static let fftSize = 4096
    static let maxCorrSeconds = 10.0
    static let maxLagMs = 10.0

    public static func analyze(channels: [[Float]], fs: Double) -> AnalysisReport {
        var stats: [ChannelStats] = []
        for (i, x) in channels.enumerated() {
            var sum = 0.0, peak = 0.0
            for s in x { let v = Double(s); sum += v * v; peak = max(peak, abs(v)) }
            let rms = x.isEmpty ? 0 : (sum / Double(x.count)).squareRoot()
            let rmsDb = dB(rms), peakDb = dB(peak)
            let active = rmsDb > activeRmsDb
            let cen = active ? centroid(x, fs: fs) : .nan
            let crest = peakDb - rmsDb
            let score = active ? crest - centroidWeightDbPerOctave * log2(max(cen, 50) / 1000) : nil
            stats.append(ChannelStats(index: i, rmsDb: rmsDb, peakDb: peakDb, crestDb: crest,
                                      centroidHz: cen, active: active, dryScore: score))
        }

        // Correlaciones (primeros maxCorrSeconds, centrados).
        let n = channels.count
        let len = min(channels.map { $0.count }.min() ?? 0, Int(maxCorrSeconds * fs))
        let size = FFT.nextPow2(max(2, 2 * len))
        var specs: [Spectrum] = []
        var energy: [Double] = []
        for x in channels {
            var seg = Array(x.prefix(len))
            let mean = seg.isEmpty ? 0 : seg.reduce(0, +) / Float(seg.count)
            for k in 0..<seg.count { seg[k] -= mean }
            energy.append(seg.reduce(0.0) { $0 + Double($1) * Double($1) })
            specs.append(Spectrum(seg, size: size))
        }
        var corr = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        var best = corr
        var lags = [[Int]](repeating: [Int](repeating: 0, count: n), count: n)
        let maxLag = Int(maxLagMs / 1000 * fs)
        for i in 0..<n {
            corr[i][i] = energy[i] > 0 ? 1 : 0
            best[i][i] = corr[i][i]
            for j in (i + 1)..<max(n, i + 1) {
                let norm = (energy[i] * energy[j]).squareRoot()
                guard norm > 0 else { continue }
                let c = XCorr(reference: specs[i], signal: specs[j])
                var bv = 0.0, bl = 0
                for lag in -maxLag...maxLag {
                    let v = c.at(lag) / norm
                    if abs(v) > abs(bv) { bv = v; bl = lag }
                }
                corr[i][j] = c.at(0) / norm; corr[j][i] = corr[i][j]
                best[i][j] = abs(bv); best[j][i] = best[i][j]
                lags[i][j] = bl; lags[j][i] = -bl
            }
        }

        let act = stats.filter { $0.active }
        var di: Int?, proc: Int?
        var note: String
        if act.count < 2 {
            note = act.isEmpty ? "Ningún canal con señal (todos por debajo de \(Int(activeRmsDb)) dBFS)."
                               : "Solo hay un canal con señal (canal \(act[0].index + 1)); no se puede separar seco de procesado."
        } else {
            let sorted = act.sorted { ($0.dryScore ?? 0) > ($1.dryScore ?? 0) }
            let top = sorted.first!, bottom = sorted.last!
            di = top.index; proc = bottom.index
            let gap = (top.dryScore ?? 0) - (bottom.dryScore ?? 0)
            if best[top.index][bottom.index] >= duplicateCorrelation {
                note = "Los canales \(top.index + 1) y \(bottom.index + 1) son prácticamente la misma señal (corr \(String(format: "%.3f", best[top.index][bottom.index]))): probablemente no hay DI separado."
            } else if gap < ambiguousScoreGap {
                note = "Ambiguo: puntuaciones muy parecidas (diferencia \(String(format: "%.1f", gap))). Escucha los canales \(top.index + 1) y \(bottom.index + 1)."
            } else {
                note = "DI seco probable: canal \(top.index + 1) (cresta alta, centroide bajo). Procesado probable: canal \(bottom.index + 1)."
            }
        }
        return AnalysisReport(sampleRate: fs, channels: stats, correlation: corr, bestCorrelation: best,
                              bestLagSamples: lags, suggestedDI: di, suggestedProcessed: proc, note: note)
    }

    /// Centroide espectral (Hz) con espectro de potencia promediado (Welch, Hann 4096, 50 %), sin DC.
    public static func centroid(_ x: [Float], fs: Double) -> Double {
        let n = fftSize, hop = n / 2
        let win = (0..<n).map { 0.5 * (1 - cos(2 * Double.pi * Double($0) / Double(n))) }
        var power = [Double](repeating: 0, count: n / 2 + 1)
        let segs = x.count >= n ? (x.count - n) / hop + 1 : 1
        let stride = max(1, segs / 400)
        var s = 0
        while s < segs {
            var re = [Double](repeating: 0, count: n), im = re
            let start = s * hop
            for i in 0..<n where start + i < x.count { re[i] = Double(x[start + i]) * win[i] }
            FFT.transform(&re, &im)
            for k in 0...(n / 2) { power[k] += re[k] * re[k] + im[k] * im[k] }
            s += stride
        }
        var num = 0.0, den = 0.0
        for k in 1...(n / 2) { num += Double(k) * fs / Double(n) * power[k]; den += power[k] }
        return den > 0 ? num / den : .nan
    }
}
