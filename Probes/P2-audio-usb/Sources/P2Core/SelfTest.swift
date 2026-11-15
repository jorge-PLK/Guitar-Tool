import Foundation

public struct Check {
    public let name: String
    public let expected: Double
    public let got: Double
    public let tolerance: Double
    public let unit: String
    public var pass: Bool { abs(got - expected) <= tolerance }
}

/// Comprobaciones sobre señales sintéticas con retardo y atenuación conocidos (sin hardware).
public enum SelfTest {
    struct RNG {
        var s: UInt64 = 0x9E37_79B9_7F4A_7C15
        mutating func next() -> Double {
            s ^= s << 13; s ^= s >> 7; s ^= s << 17
            return Double(s >> 11) / Double(1 << 53)
        }
        mutating func gauss() -> Double {
            let u = max(next(), 1e-12), v = next()
            return (-2 * log(u)).squareRoot() * cos(2 * Double.pi * v)
        }
    }

    static func noise(_ n: Int, sigma: Double, rng: inout RNG) -> [Float] {
        (0..<n).map { _ in Float(sigma * rng.gauss()) }
    }

    /// Toma sintética de 3 canales: [procesado (saturado), DI seco (pulsaciones con decaimiento), mudo].
    public static func syntheticTake(fs: Double) -> [[Float]] {
        let n = Int(4 * fs)
        var di = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / fs
            let age = t.truncatingRemainder(dividingBy: 0.5)
            var v = 0.0
            for h in 1...8 { v += sin(2 * Double.pi * 196 * Double(h) * t) / Double(h) }
            di[i] = Float(0.5 * exp(-age / 0.15) * v / 1.8)
        }
        let proc = di.map { Float(tanh(12 * Double($0)) * 0.5) }
        return [proc, di, [Float](repeating: 0, count: n)]
    }

    public static func run() -> [Check] {
        var checks: [Check] = []
        var rng = RNG()
        let fs = 48_000.0

        // 1. Barrido: retardo y nivel en recuperaciones con distintas atenuaciones.
        let sweep = Signals.logSweep(fs: fs, seconds: 2, amplitude: 0.25)
        let cases: [(delay: Int, gainDb: Double, sigma: Double, tone: Float)] = [
            (1234, -23, 1e-3, 0.01), (48_017, -65, 1e-5, 0.0003), (7, -0.5, 1e-4, 0.01), (20_000, -58, 1e-4, 0.0003),
        ]
        for c in cases {
            var rx = noise(sweep.count + 3 * Int(fs), sigma: c.sigma, rng: &rng)
            let g = Float(pow(10, c.gainDb / 20))
            for i in 0..<sweep.count {
                rx[c.delay + i] += sweep[i] * g
                rx[c.delay + i] += c.tone * Float(sin(2 * Double.pi * 220 * Double(c.delay + i) / fs)) // "guitarra" sonando a la vez
            }
            let m = Detectors.measureSweep(sweep: sweep, received: rx)
            checks.append(Check(name: "barrido \(c.gainDb) dB: retardo", expected: Double(c.delay), got: Double(m.lagSamples), tolerance: 1, unit: "muestras"))
            checks.append(Check(name: "barrido \(c.gainDb) dB: nivel", expected: c.gainDb, got: m.levelDb, tolerance: 1, unit: "dB"))
        }
        // Sin barrido (solo ruido y un tono): no debe darse por detectado.
        var rx = noise(sweep.count + 3 * Int(fs), sigma: 1e-4, rng: &rng)
        for i in 0..<rx.count { rx[i] += 0.01 * Float(sin(2 * Double.pi * 220 * Double(i) / fs)) }
        let none = Detectors.measureSweep(sweep: sweep, received: rx)
        checks.append(Check(name: "sin barrido: detectado (0 = no)", expected: 0, got: none.detected ? 1 : 0, tolerance: 0, unit: ""))
        checks.append(Check(name: "sin barrido: nivel por debajo de -60 dB", expected: 1, got: none.levelDb < -60 ? 1 : 0, tolerance: 0, unit: ""))

        // 2. Clics: latencia entera y fraccionaria.
        for latency in [1000.0, 523.37, 311.5] {
            let reps = 10
            let sentAt = (0..<reps).map { 24_000 + $0 * 48_000 }
            var rx = noise(24_000 + reps * 48_000 + 24_000, sigma: 1e-3, rng: &rng)
            for p in sentAt {
                let first = p + Int(latency.rounded(.down))
                for i in 0..<(Signals.Click.length(fs: fs) + 2) {
                    // valor del clic evaluado en (muestra - posición exacta del eco)
                    let n = Double(first + i - p) - latency
                    rx[first + i] += Signals.Click.value(fs: fs, n: n, amplitude: 0.5) * 0.3
                }
            }
            let r = Detectors.measureClicks(fs: fs, sentAt: sentAt, received: rx)
            checks.append(Check(name: "clics \(latency) muestras: media", expected: latency, got: r.mean, tolerance: 1, unit: "muestras"))
            checks.append(Check(name: "clics \(latency) muestras: válidos", expected: Double(reps), got: Double(r.samples.count), tolerance: 0, unit: ""))
        }

        // 3. Análisis: DI seco (pulsaciones con decaimiento) frente a procesado (saturado) y un canal mudo.
        let take = syntheticTake(fs: fs)
        let (proc, di) = (take[0], take[1])
        let rep = Analyzer.analyze(channels: take, fs: fs)
        checks.append(Check(name: "analyze: DI sugerido (índice 0-based)", expected: 1, got: Double(rep.suggestedDI ?? -1), tolerance: 0, unit: ""))
        checks.append(Check(name: "analyze: procesado sugerido", expected: 0, got: Double(rep.suggestedProcessed ?? -1), tolerance: 0, unit: ""))
        checks.append(Check(name: "analyze: canal mudo inactivo (0 = sí)", expected: 0, got: rep.channels[2].active ? 1 : 0, tolerance: 0, unit: ""))
        checks.append(Check(name: "analyze: correlación DI-procesado > 0.8", expected: 1, got: rep.bestCorrelation[0][1] > 0.8 ? 1 : 0, tolerance: 0, unit: ""))

        // Retardo entre canales: copia retrasada 100 muestras y atenuada.
        let delayed = [Float](repeating: 0, count: 100) + di.dropLast(100).map { $0 * 0.5 }
        let rep2 = Analyzer.analyze(channels: [di, delayed], fs: fs)
        checks.append(Check(name: "analyze: retardo entre canales", expected: 100, got: Double(rep2.bestLagSamples[0][1]), tolerance: 1, unit: "muestras"))

        // 4. WAV ida y vuelta.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("p2-selftest-\(getpid()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        if (try? WAV.write(di, sampleRate: fs, to: url)) != nil, let back = try? WAV.read(url) {
            let diff = zip(di, back.channels[0]).map { abs($0 - $1) }.max() ?? 1
            checks.append(Check(name: "WAV ida y vuelta: diferencia máx", expected: 0, got: Double(diff), tolerance: 1e-7, unit: ""))
            checks.append(Check(name: "WAV ida y vuelta: frecuencia", expected: fs, got: back.sampleRate, tolerance: 0, unit: "Hz"))
        } else {
            checks.append(Check(name: "WAV ida y vuelta: lectura", expected: 1, got: 0, tolerance: 0, unit: ""))
        }
        return checks
    }
}
