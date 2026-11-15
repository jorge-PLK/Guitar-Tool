import Foundation

public enum Signals {
    /// Barrido logarítmico f0→f1 con fundidos de entrada y salida (Hann, `fade` s).
    public static func logSweep(fs: Double, f0: Double = 20, f1: Double = 20_000,
                                seconds: Double, amplitude: Float, fade: Double = 0.01) -> [Float] {
        let top = min(f1, 0.45 * fs)
        let n = Int((seconds * fs).rounded())
        let l = log(top / f0)
        let k = 2 * Double.pi * f0 * seconds / l
        let nf = max(1, Int(fade * fs))
        var x = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / fs
            var v = sin(k * (exp(t * l / seconds) - 1))
            if i < nf { v *= 0.5 * (1 - cos(Double.pi * Double(i) / Double(nf))) }
            if i >= n - nf { v *= 0.5 * (1 - cos(Double.pi * Double(n - 1 - i) / Double(nf))) }
            x[i] = Float(v) * amplitude
        }
        return x
    }

    /// "Clic" para la medida de latencia: chirp corto (1–15 kHz, 4 ms, Hann).
    /// Un impulso puro se pierde con filtros de DC/paso alto; el chirp se correlaciona con precisión de submuestra.
    public enum Click {
        public static let seconds = 0.004
        public static let f0 = 1_000.0
        public static let f1 = 15_000.0

        public static func length(fs: Double) -> Int { Int((seconds * fs).rounded()) }

        /// Valor en la muestra fraccionaria `n` (0 ≤ n < length).
        public static func value(fs: Double, n: Double, amplitude: Float) -> Float {
            let len = Double(length(fs: fs))
            guard n >= 0, n < len else { return 0 }
            let u = n / len
            let t = n / fs
            let rate = (min(f1, 0.45 * fs) - f0) / seconds
            let w = 0.5 * (1 - cos(2 * Double.pi * u))
            return Float(w * sin(2 * Double.pi * (f0 * t + 0.5 * rate * t * t))) * amplitude
        }

        public static func template(fs: Double, amplitude: Float = 0.5) -> [Float] {
            (0..<length(fs: fs)).map { value(fs: fs, n: Double($0), amplitude: amplitude) }
        }
    }
}
