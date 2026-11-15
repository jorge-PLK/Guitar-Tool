import Accelerate
import Foundation

/// Cálculo interno de la Fase 3: interpolación sinc, correlación por FFT, filtros FIR y ruido.
enum SignalMath {
    // MARK: Interpolación sinc enventanada

    /// Semiancho del núcleo: 64 coeficientes (`−31…32` alrededor de la muestra entera).
    static let sincHalfWidth = 32
    /// Kaiser β = 9: rizado < −90 dB; error de fase despreciable por debajo de 0,4·fs.
    static let kaiserBeta = 9.0
    /// Fases de la tabla del retardo fraccionario: error de posición ≤ 1/(2·4096) muestras.
    static let tablePhases = 4096

    static func sinc(_ x: Double) -> Double { x == 0 ? 1 : sin(.pi * x) / (.pi * x) }

    /// Función de Bessel modificada de orden 0 (serie).
    static func besselI0(_ x: Double) -> Double {
        var sum = 1.0, term = 1.0, k = 1.0
        let q = x * x / 4
        while term > 1e-12 * sum {
            term *= q / (k * k)
            sum += term
            k += 1
        }
        return sum
    }

    private static let i0Beta = besselI0(kaiserBeta)

    /// Núcleo de interpolación en `u` muestras del punto pedido.
    static func kernel(_ u: Double) -> Double {
        let r = u / Double(sincHalfWidth + 1)
        guard abs(r) < 1 else { return 0 }
        return sinc(u) * besselI0(kaiserBeta * (1 - r * r).squareRoot()) / i0Beta
    }

    /// Tabla `[fase][m]` con `kernel(f − m)`, `m = −31…32`, `f = fase / tablePhases`.
    static let sincTable: [Float] = {
        let w = 2 * sincHalfWidth
        var t = [Float](repeating: 0, count: tablePhases * w)
        for p in 0..<tablePhases {
            let f = Double(p) / Double(tablePhases)
            for j in 0..<w {
                let m = j - (sincHalfWidth - 1)
                t[p * w + j] = Float(kernel(f - Double(m)))
            }
        }
        return t
    }()

    /// Valor interpolado de `x` en la posición real `t` (fuera de rango cuenta como 0).
    static func interpolate(_ x: [Double], at t: Double) -> Double {
        let i = Int(t.rounded(.down))
        var s = 0.0
        for j in max(0, i - sincHalfWidth + 1)...min(x.count - 1, i + sincHalfWidth) {
            s += x[j] * kernel(t - Double(j))
        }
        return s
    }

    /// Máximo de |x| interpolado por sinc en `[k − 1, k + 1]`. Rejilla de 0,05 muestras refinada tres
    /// veces ×10: resolución 5·10⁻⁵ muestras.
    static func refinePeak(_ x: [Double], near k: Int) -> Double {
        var best = Double(k), bestV = abs(interpolate(x, at: best))
        var lo = Double(k) - 1, hi = Double(k) + 1, step = 0.05
        for _ in 0..<4 {
            var t = lo
            while t <= hi + 1e-12 {
                let v = abs(interpolate(x, at: t))
                if v > bestV { bestV = v; best = t }
                t += step
            }
            lo = best - step
            hi = best + step
            step /= 10
        }
        return best
    }

    // MARK: Correlación por FFT

    static func nextPow2(_ n: Int) -> Int {
        var p = 1
        while p < n { p <<= 1 }
        return p
    }

    /// Correlación cruzada `c[k] = Σ_m x[m + k]·s[m]` para `k = 0..<x.count` y su envolvente (módulo de
    /// la señal analítica de `c`). Doble precisión.
    static func analyticCorrelation(signal x: [Float], template s: [Float]) -> (real: [Double], envelope: [Double]) {
        let n = nextPow2(x.count + s.count)
        guard let fwd = vDSP_DFT_zop_CreateSetupD(nil, vDSP_Length(n), .FORWARD),
              let inv = vDSP_DFT_zop_CreateSetupD(fwd, vDSP_Length(n), .INVERSE) else {
            return ([Double](repeating: 0, count: x.count), [Double](repeating: 0, count: x.count))
        }
        defer {
            vDSP_DFT_DestroySetupD(inv)
            vDSP_DFT_DestroySetupD(fwd)
        }
        let zeros = [Double](repeating: 0, count: n)
        var xr = zeros, sr = zeros
        vDSP_vspdp(x, 1, &xr, 1, vDSP_Length(x.count))
        vDSP_vspdp(s, 1, &sr, 1, vDSP_Length(s.count))
        var xR = zeros, xI = zeros, sR = zeros, sI = zeros
        vDSP_DFT_ExecuteD(fwd, xr, zeros, &xR, &xI)
        vDSP_DFT_ExecuteD(fwd, sr, zeros, &sR, &sI)
        // X·conj(S), y señal analítica: positivas ×2, negativas a 0 (0 y n/2 intactas).
        var cR = zeros, cI = zeros
        for k in 0...(n / 2) {
            let w: Double = (k == 0 || k == n / 2) ? 1 : 2
            cR[k] = w * (xR[k] * sR[k] + xI[k] * sI[k])
            cI[k] = w * (xI[k] * sR[k] - xR[k] * sI[k])
        }
        var oR = zeros, oI = zeros
        vDSP_DFT_ExecuteD(inv, cR, cI, &oR, &oI)
        let scale = 1 / Double(n)
        var real = [Double](repeating: 0, count: x.count)
        var env = [Double](repeating: 0, count: x.count)
        for k in 0..<x.count {
            real[k] = oR[k] * scale
            env[k] = (oR[k] * oR[k] + oI[k] * oI[k]).squareRoot() * scale
        }
        return (real, env)
    }

    // MARK: Tonos estrechos del fondo

    /// Espectro de potencia de `x` con ventana de Hann, rellenado con ceros hasta `n` (potencia de 2, ≥ x.count);
    /// bins `0...n/2`.
    static func powerSpectrum(_ x: ArraySlice<Float>, n: Int) -> [Double] {
        guard let fwd = vDSP_DFT_zop_CreateSetupD(nil, vDSP_Length(n), .FORWARD) else { return [] }
        defer { vDSP_DFT_DestroySetupD(fwd) }
        let zeros = [Double](repeating: 0, count: n)
        var re = zeros
        let m = x.count
        for (i, v) in x.enumerated() { re[i] = Double(v) * (0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(m))) }
        var oR = zeros, oI = zeros
        vDSP_DFT_ExecuteD(fwd, re, zeros, &oR, &oI)
        return (0...(n / 2)).map { oR[$0] * oR[$0] + oI[$0] * oI[$0] }
    }

    /// Peso real por bin que solo toca las líneas estrechas: donde la potencia pasa `prominence` veces la
    /// mediana de su vecindad (±`neighbourBins`), la baja hasta ese nivel; en el resto vale 1. Un fondo de
    /// ruido (o el propio clic, que es ancho) no cambia.
    static func lineSuppressionWeight(_ p: [Double], prominence: Double, neighbourBins b: Int) -> (weight: [Double], localMedian: [Double]) {
        var g = [Double](repeating: 1, count: p.count)
        var med = [Double](repeating: 0, count: p.count)
        // La mediana local varía despacio: se calcula cada `step` bins y se interpola.
        let step = max(1, b / 8)
        let last = p.count - 1
        var knots: [(Int, Double)] = []
        var k = 0
        while true {
            knots.append((k, median(Array(p[max(0, k - b)...min(last, k + b)]))))
            if k == last { break }
            k = min(last, k + step)
        }
        for j in 0..<(knots.count - 1) {
            let (k0, m0) = knots[j], (k1, m1) = knots[j + 1]
            for i in k0...k1 { med[i] = k1 == k0 ? m0 : m0 + (m1 - m0) * Double(i - k0) / Double(k1 - k0) }
        }
        if knots.count == 1 { med[0] = knots[0].1 }
        for i in p.indices where p[i] > prominence * med[i] { g[i] = (prominence * med[i] / p[i]).squareRoot() }
        return (g, med)
    }

    /// Filtra `x` (longitud ≤ n) con el peso real `weight` (fase cero, `n = 2·(weight.count − 1)`).
    static func zeroPhaseFilter(_ x: [Float], weight: [Double]) -> [Float] {
        let n = 2 * (weight.count - 1)
        guard n >= x.count,
              let fwd = vDSP_DFT_zop_CreateSetupD(nil, vDSP_Length(n), .FORWARD),
              let inv = vDSP_DFT_zop_CreateSetupD(fwd, vDSP_Length(n), .INVERSE) else { return x }
        defer {
            vDSP_DFT_DestroySetupD(inv)
            vDSP_DFT_DestroySetupD(fwd)
        }
        let zeros = [Double](repeating: 0, count: n)
        var re = zeros
        vDSP_vspdp(x, 1, &re, 1, vDSP_Length(x.count))
        var fR = zeros, fI = zeros
        vDSP_DFT_ExecuteD(fwd, re, zeros, &fR, &fI)
        for k in 0..<n {
            let g = weight[k <= n / 2 ? k : n - k]
            fR[k] *= g
            fI[k] *= g
        }
        var oR = zeros, oI = zeros
        vDSP_DFT_ExecuteD(inv, fR, fI, &oR, &oI)
        let scale = 1 / Double(n)
        return (0..<x.count).map { Float(oR[$0] * scale) }
    }

    // MARK: FIR

    /// Paso bajo de fase lineal (sinc enventanado con Hann), ganancia 1 en continua, `2·half + 1` coeficientes.
    static func lowpass(cutoffHz: Double, sampleRate: Double, half: Int) -> [Float] {
        let fc = cutoffHz / sampleRate
        var h = (-half...half).map { m -> Double in
            let w = 0.5 + 0.5 * cos(Double.pi * Double(m) / Double(half + 1))
            return 2 * fc * sinc(2 * fc * Double(m)) * w
        }
        let sum = h.reduce(0, +)
        h = h.map { $0 / sum }
        return h.map(Float.init)
    }

    /// Filtra con un FIR simétrico; la salida tiene la longitud de la entrada y el retardo del filtro
    /// compensado (ceros fuera).
    static func filterSymmetric(_ x: [Float], _ h: [Float]) -> [Float] {
        let half = h.count / 2
        let padded = [Float](repeating: 0, count: half) + x + [Float](repeating: 0, count: half)
        var y = [Float](repeating: 0, count: x.count)
        vDSP_conv(padded, 1, h, 1, &y, 1, vDSP_Length(x.count), vDSP_Length(h.count))
        return y
    }

    // MARK: Estadística

    static func median(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return .nan }
        let s = v.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}

/// Generador determinista (SplitMix64) con gaussiana por Box-Muller.
struct SeededNoise: Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniforme en (0, 1].
    mutating func uniform() -> Double { (Double(nextUInt64() >> 11) + 1) / 9_007_199_254_740_992.0 }

    mutating func gaussian() -> Double {
        (-2 * log(uniform())).squareRoot() * cos(2 * .pi * uniform())
    }
}
