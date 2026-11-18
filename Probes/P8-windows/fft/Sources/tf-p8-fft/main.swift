// Prueba b del paso 4 (Fase 7c): ¿basta pocketfft para sustituir vDSP_DFT con la misma convención?
//
// 1) FFT real de 4096 con la convención empaquetada de vDSP_DFT_zrop (la que usan LogMel, DrumSpectrogram,
//    SemitoneSpectrogram y SpectralTransform), frente a la salida de vDSP en el Mac.
// 2) SignalMath.analyticCorrelation (vDSP_DFT_zop double, n = 65536) reescrita con pocketfft cfft: de esta
//    envolvente sale la latencia de ida y vuelta (spec «Calibración de latencia»: dispersión ≤ 0,1 ms; la
//    medida es de centésimas de muestra), así que se compara la posición del pico en muestras.
// Código 1 si algo pasa de su tolerancia.
import Foundation
import PocketFFTC

#if arch(arm64)
let arch = "arm64"
#elseif arch(x86_64)
let arch = "x86_64"
#else
let arch = "?"
#endif

/// Error relativo máximo admitido en la FFT float frente a vDSP: la referencia es float (≈ 6e-8 relativo
/// por operación, log2(4096) = 12 etapas); 1e-5 del pico deja dos órdenes de margen.
let fftTolerance = 1e-5
/// Diferencia máxima admitida en la posición del pico de correlación, en muestras. La spec pide dispersión
/// ≤ 0,1 ms (4,8 muestras a 48 kHz) y LatencyCalibrator trabaja con centésimas: 1e-6 es despreciable.
let peakTolerance = 1e-6
/// Error relativo máximo de la envolvente (double frente a double).
let envTolerance = 1e-9

nonisolated(unsafe) var failures = 0
func report(_ ok: Bool, _ name: String, _ detail: String) {
    print("\(ok ? "OK" : "FALLO") \(name): \(detail)")
    fflush(stdout)
    if !ok { failures += 1 }
}

/// FFT real hacia delante con la salida de vDSP_DFT_zrop: `re[0] = 2·X[0]`, `im[0] = 2·X[N/2]`,
/// `re[k] + i·im[k] = 2·X[k]`. pocketfft deja el resultado en formato FFTPACK
/// `[r0, r1, i1, r2, i2, …, r(N/2)]`.
final class RealFFT {
    let n: Int
    private let plan: rfft_plan
    private var buf: [Double]
    init(n: Int) {
        self.n = n
        plan = make_rfft_plan(n)!
        buf = [Double](repeating: 0, count: n)
    }
    deinit { destroy_rfft_plan(plan) }

    func forward(_ x: UnsafePointer<Float>, re: inout [Float], im: inout [Float]) {
        for i in 0..<n { buf[i] = Double(x[i]) }
        _ = buf.withUnsafeMutableBufferPointer { rfft_forward(plan, $0.baseAddress!, 1.0) }
        re[0] = Float(2 * buf[0])
        im[0] = Float(2 * buf[n - 1])
        for k in 1..<(n / 2) {
            re[k] = Float(2 * buf[2 * k - 1])
            im[k] = Float(2 * buf[2 * k])
        }
    }
}

/// FFT compleja double con la convención de vDSP_DFT_zop (adelante e^{-i}, inversa sin normalizar).
final class ComplexFFT {
    let n: Int
    private let plan: cfft_plan
    private var buf: [Double]
    init(n: Int) {
        self.n = n
        plan = make_cfft_plan(n)!
        buf = [Double](repeating: 0, count: 2 * n)
    }
    deinit { destroy_cfft_plan(plan) }

    func execute(forward: Bool, _ ir: [Double], _ ii: [Double], _ or: inout [Double], _ oi: inout [Double]) {
        for k in 0..<n { buf[2 * k] = ir[k]; buf[2 * k + 1] = ii[k] }
        _ = buf.withUnsafeMutableBufferPointer {
            forward ? cfft_forward(plan, $0.baseAddress!, 1.0) : cfft_backward(plan, $0.baseAddress!, 1.0)
        }
        for k in 0..<n { or[k] = buf[2 * k]; oi[k] = buf[2 * k + 1] }
    }
}

struct LCG {
    var s: UInt32
    mutating func next() -> Float {
        s = s &* 1_664_525 &+ 1_013_904_223
        return Float(Int32(bitPattern: s)) / 2_147_483_648
    }
}

func nowSeconds() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

print("tf-p8-fft arch=\(arch)")

// 1) FFT real 4096.
do {
    let n = 4096
    let fft = RealFFT(n: n)
    var re = [Float](repeating: 0, count: n / 2), im = re
    fft.forward(tf_ref_x_ptr(), re: &re, im: &im)
    let refRe = Array(UnsafeBufferPointer(start: tf_ref_re_ptr(), count: n / 2))
    let refIm = Array(UnsafeBufferPointer(start: tf_ref_im_ptr(), count: n / 2))
    var peak: Double = 0, maxErr: Double = 0, worstBin = 0
    for k in 0..<(n / 2) {
        peak = max(peak, Double(hypotf(refRe[k], refIm[k])))
        let e = max(abs(Double(re[k] - refRe[k])), abs(Double(im[k] - refIm[k])))
        if e > maxErr { maxErr = e; worstBin = k }
    }
    let rel = maxErr / peak
    report(rel <= fftTolerance, "FFT real 4096 vs vDSP_DFT_zrop",
           String(format: "error máx %.3e (bin %d), pico %.3f, relativo %.3e (tolerancia %.0e)", maxErr, worstBin, peak, rel, fftTolerance))

    // Tiempo por FFT (2000 repeticiones), solo informativo.
    var x = [Float](repeating: 0, count: n)
    var g = LCG(s: 3)
    for i in 0..<n { x[i] = g.next() }
    let reps = 2000
    let t0 = nowSeconds()
    x.withUnsafeBufferPointer { xp in for _ in 0..<reps { fft.forward(xp.baseAddress!, re: &re, im: &im) } }
    print(String(format: "  tiempo FFT real 4096: %.1f µs", (nowSeconds() - t0) / Double(reps) * 1e6))
}

// 2) Correlación analítica (SignalMath.analyticCorrelation con pocketfft).
do {
    let sn = 1024, xn = 40_000, delay = 12_345
    var gs = LCG(s: 7), gx = LCG(s: 99)
    let s = (0..<sn).map { _ in gs.next() }
    var xs = (0..<xn).map { _ in 0.01 * gx.next() }
    for i in 0..<sn { xs[delay + i] += 0.5 * s[i] }

    var m = 1
    while m < xn + sn { m <<= 1 }
    let t0 = nowSeconds()
    let fft = ComplexFFT(n: m)
    let zeros = [Double](repeating: 0, count: m)
    var xr = zeros, sr = zeros
    for i in 0..<xn { xr[i] = Double(xs[i]) }
    for i in 0..<sn { sr[i] = Double(s[i]) }
    var xR = zeros, xI = zeros, sR = zeros, sI = zeros
    fft.execute(forward: true, xr, zeros, &xR, &xI)
    fft.execute(forward: true, sr, zeros, &sR, &sI)
    var cR = zeros, cI = zeros
    for k in 0...(m / 2) {
        let w: Double = (k == 0 || k == m / 2) ? 1 : 2
        cR[k] = w * (xR[k] * sR[k] + xI[k] * sI[k])
        cI[k] = w * (xI[k] * sR[k] - xR[k] * sI[k])
    }
    var oR = zeros, oI = zeros
    fft.execute(forward: false, cR, cI, &oR, &oI)
    let scale = 1 / Double(m)
    var env = [Double](repeating: 0, count: xn)
    for k in 0..<xn { env[k] = (oR[k] * oR[k] + oI[k] * oI[k]).squareRoot() * scale }
    let ms = (nowSeconds() - t0) * 1e3

    let peak = env.indices.max { env[$0] < env[$1] }!
    let (a, b, c) = (env[peak - 1], env[peak], env[peak + 1])
    let pos = Double(peak) + 0.5 * (a - c) / (a - 2 * b + c)
    let refEnv = Array(UnsafeBufferPointer(start: tf_corr_env_ptr(), count: 1000))
    let refPeak = Int(tf_corr_peak_index()), refPos = tf_corr_peak_position(), refVal = tf_corr_peak_value()
    var envErr: Double = 0
    for (j, r) in refEnv.enumerated() { envErr = max(envErr, abs(env[j * 40] - r)) }
    envErr = max(envErr, abs(b - refVal)) / refVal
    let dPos = abs(pos - refPos)
    report(peak == refPeak && dPos <= peakTolerance, "pico de correlación vs vDSP_DFT_zopD",
           String(format: "pico %d (ref %d), posición %.9f (ref %.9f), diferencia %.2e muestras (tolerancia %.0e)",
                  peak, refPeak, pos, refPos, dPos, peakTolerance))
    report(envErr <= envTolerance, "envolvente de correlación vs vDSP",
           String(format: "error relativo máx %.2e en 1001 puntos (tolerancia %.0e); n = %d en %.1f ms", envErr, envTolerance, m, ms))
}

print("fallos \(failures)")
exit(failures == 0 ? 0 : 1)
