import Foundation

public func dB(_ linear: Double) -> Double { 20 * log10(max(linear, 1e-12)) }

public struct SweepMeasurement {
    /// Retardo del barrido respecto al inicio de la grabación, en muestras.
    public let lagSamples: Int
    /// Ganancia estimada (proyección por mínimos cuadrados sobre la señal enviada) en dB; 0 dB = mismo nivel que lo enviado.
    public let levelDb: Double
    /// Nivel de la correlación en retardos sin barrido (equivalente en dB), es decir, el suelo de la medida.
    public let floorDb: Double
    public var peakToFloorDb: Double { levelDb - floorDb }
    /// El barrido se distingue del suelo por al menos `Detectors.detectionMarginDb`.
    public var detected: Bool { peakToFloorDb >= Detectors.detectionMarginDb }
}

public struct ClickLatency {
    public let samples: [Double]     // por repetición válida (fraccionario)
    public let invalidReps: Int
    public let sampleRate: Double
    public var mean: Double { samples.isEmpty ? .nan : samples.reduce(0, +) / Double(samples.count) }
    public var std: Double {
        guard samples.count > 1 else { return 0 }
        let m = mean
        return (samples.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(samples.count - 1)).squareRoot()
    }
    public var min: Double { samples.min() ?? .nan }
    public var max: Double { samples.max() ?? .nan }
    public func ms(_ s: Double) -> Double { s / sampleRate * 1000 }
}

public enum Detectors {
    /// Margen mínimo pico/suelo para dar el barrido por detectado.
    public static let detectionMarginDb = 10.0
    /// Muestras alrededor del pico excluidas al estimar el suelo.
    static let floorGuard = 960
    /// Un clic es válido si su pico supera al RMS de la correlación en esta razón.
    public static let clickMinPeakToRms = 6.0
    /// Ventana tras cada clic donde se busca el eco (s).
    public static let clickSearchSeconds = 0.5

    /// Mide el barrido `sweep` dentro de `received` por correlación cruzada con la señal enviada.
    public static func measureSweep(sweep: [Float], received: [Float]) -> SweepMeasurement {
        let c = XCorr(reference: sweep, signal: received)
        let energy = sweep.reduce(0.0) { $0 + Double($1) * Double($1) }
        let maxLag = max(0, received.count - sweep.count)
        var best = 0, bestV = -1.0
        for lag in 0...maxLag {
            let v = abs(c.at(lag))
            if v > bestV { bestV = v; best = lag }
        }
        var acc = 0.0, cnt = 0
        for lag in 0...maxLag where abs(lag - best) > floorGuard {
            let v = c.at(lag)
            acc += v * v; cnt += 1
        }
        let floor = cnt > 0 ? (acc / Double(cnt)).squareRoot() : 0
        return SweepMeasurement(lagSamples: best, levelDb: dB(bestV / energy), floorDb: dB(floor / energy))
    }

    /// Latencia de ida y vuelta: para cada clic enviado en `sentAt[i]` (muestras) busca su eco en `received`.
    public static func measureClicks(fs: Double, sentAt: [Int], received: [Float]) -> ClickLatency {
        let tpl = Signals.Click.template(fs: fs)
        let win = Int(clickSearchSeconds * fs)
        var out: [Double] = []
        var bad = 0
        for p in sentAt {
            guard p < received.count else { bad += 1; continue }
            let seg = Array(received[p..<min(received.count, p + win + tpl.count)])
            guard seg.count > tpl.count else { bad += 1; continue }
            let c = XCorr(reference: tpl, signal: seg)
            let maxLag = seg.count - tpl.count
            var best = 0, bestV = -1.0, acc = 0.0
            for lag in 0...maxLag {
                let v = abs(c.at(lag))
                acc += v * v
                if v > bestV { bestV = v; best = lag }
            }
            let rms = (acc / Double(maxLag + 1)).squareRoot()
            guard bestV / max(rms, 1e-18) >= clickMinPeakToRms else { bad += 1; continue }
            let a = abs(c.at(best - 1)), b = bestV, d = abs(c.at(best + 1))
            let den = a - 2 * b + d
            let delta = den < 0 ? 0.5 * (a - d) / den : 0
            out.append(Double(best) + max(-0.5, min(0.5, delta)))
        }
        return ClickLatency(samples: out, invalidReps: bad, sampleRate: fs)
    }
}
