import Foundation
@testable import NativeDSP

// Casos de la fachada DSP: cada uno ejecuta una operación con un motor y devuelve su salida aplanada a
// Double. En el Mac se comparan los dos motores; en todos los sistemas, el portátil frente a la salida de
// vDSP guardada en `DSPReferenceData.swift`. Entradas deterministas (LCG entero → Float exacto), iguales
// bit a bit en todas las máquinas.

/// Error admitido, relativo al máximo |referencia| de cada caso.
enum DSPTolerance {
    /// Aritmética elemento a elemento y conversiones: 2 ulp de Float (vDSP usa FMA en `vma`/`vsma`; el
    /// portátil no tiene por qué).
    static let elementwise = 2.4e-7
    /// Reducciones Float de 1000 elementos: vDSP suma en Float por carriles (error ~√n·6e-8 ≈ 2e-6 en el
    /// peor caso); el portátil acumula en Double.
    static let floatReduction = 4e-6
    /// Double frente a Double.
    static let double = 1e-13
    /// FIR, diezmado y producto de matrices en Float.
    static let filter = 2e-6
    /// FFT Float: P8 midió 6,6e-8 relativo con n = 4096 frente a una tolerancia de 1e-5; aquí 1e-6.
    static let fft = 1e-6
    /// FFT Double (P8: envolvente de correlación con error 2,7e-17).
    static let fftDouble = 1e-12
    /// vForce frente a libm: ≤ 2 ulp cada uno.
    static let log = 4.8e-7
    /// Cascada de biquads de 4096 muestras (K-weighting, polos del paso alto a 0,995 de z = 1). vDSP calcula
    /// en Float y se aparta 1,0e-3 (relativo al pico) de la forma directa I exacta en Double (medido en el Mac);
    /// el portátil calcula en Double, así que la diferencia entre motores es el error de vDSP. En LUFS, 1e-3
    /// de amplitud es < 0,01 dB. Tolerancia 2e-3.
    static let biquad = 2e-3
    /// Posición subamuestra del pico de correlación analítica (latencia de ida y vuelta, spec «Calibración
    /// de latencia»: dispersión ≤ 0,1 ms = 4,8 muestras a 48 kHz). P8: Δ 0,0 con tolerancia 1e-6.
    static let correlationPeakSamples = 1e-6
}

struct LCG {
    var s: UInt32
    mutating func next() -> Float {
        s = s &* 1_664_525 &+ 1_013_904_223
        return Float(Int32(bitPattern: s)) / 2_147_483_648
    }
}

func noise(_ n: Int, seed: UInt32, scale: Float = 1, offset: Float = 0) -> [Float] {
    var g = LCG(s: seed)
    return (0..<n).map { _ in g.next() * scale + offset }
}

func noiseD(_ n: Int, seed: UInt32) -> [Double] {
    var g = LCG(s: seed)
    return (0..<n).map { _ in Double(g.next()) + Double(g.next()) * 1e-8 }
}

func flat(_ x: [Float]) -> [Double] { x.map(Double.init) }

/// Puntero mutable a un array durante `body` (las llamadas en el sitio no pueden pasar `x` y `&x` a la vez).
func mut<T, R>(_ x: inout [T], _ body: (UnsafeMutablePointer<T>) -> R) -> R {
    x.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
}

/// Coeficientes K-weighting de BS.1770 a 48 kHz (los de `LoudnessMatch` en AudioKit): estante y paso alto.
let kWeighting48k: [Double] = [1.53512485958697, -2.69169618940638, 1.19839281085285, -1.69065929318241, 0.73248077421585,
                               1, -2, 1, -1.99004745483398, 0.99007225036621]

enum DSPCases {
    static let n = 37        // impar y no múltiplo de ningún ancho SIMD
    static let big = 1000    // reducciones

    static let tolerances: [String: Double] = {
        var t: [String: Double] = [:]
        for k in ["vadd", "vaddD", "vsub", "vmul", "vmul_strided", "vdiv", "vma", "vsma", "vsma_inplace", "vsmsa", "vsmul",
                  "vsmulD", "vsadd", "vfill", "vclr", "vrvrs", "vabs", "vabsD", "vmax", "vmaxD", "vthres", "vspdp",
                  "maxmgv", "maxvD", "maximumF", "maximumD", "zvabs", "zvabs_stride2", "zvmul", "zvmul_conj_inplace",
                  "zvmov", "ctoz", "ztoc", "convertFD", "convertDF", "planar16F"] { t[k] = DSPTolerance.elementwise }
        for k in ["sve", "svesq", "meanv", "measqv", "rmsqv", "dotpr"] { t[k] = DSPTolerance.floatReduction }
        for k in ["dotprD", "convD"] { t[k] = DSPTolerance.double }
        for k in ["conv", "conv_reversed", "desamp", "mmul"] { t[k] = DSPTolerance.filter }
        for k in ["vvlogf", "vvlog1pf", "vvlog10f"] { t[k] = DSPTolerance.log }
        for k in ["realDFT_fwd_512", "realDFT_inv_512", "complexDFT_fwd_192", "complexDFT_inv_128"] { t[k] = DSPTolerance.fft }
        for k in ["complexDFTD_fwd_256", "complexDFTD_inv_256"] { t[k] = DSPTolerance.fftDouble }
        t["biquad_kweight"] = DSPTolerance.biquad
        return t
    }()

    static var names: [String] { tolerances.keys.sorted() }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func run<E: DSPEngine>(_ name: String, _: E.Type) -> [Double] {
        let n = n, ln = DSPLength(n)
        let a = noise(n, seed: 1), b = noise(n, seed: 2), c = noise(n, seed: 3)
        let ad = noiseD(n, seed: 4), bd = noiseD(n, seed: 5)
        var out = [Float](repeating: 0, count: n), outD = [Double](repeating: 0, count: n)
        var k: Float = 0.37, s: Float = -0.21, kd = 0.37
        switch name {
        case "vadd": E.vadd(a, 1, b, 1, &out, 1, ln); return flat(out)
        case "vaddD": E.vaddD(ad, 1, bd, 1, &outD, 1, ln); return outD
        case "vsub": E.vsub(a, 1, b, 1, &out, 1, ln); return flat(out)
        case "vmul": E.vmul(a, 1, b, 1, &out, 1, ln); return flat(out)
        case "vmul_strided":
            // a con paso 2, b recorrido hacia atrás (paso −1 desde el último), salida con paso 3.
            let a2 = noise(2 * n, seed: 6)
            var o3 = [Float](repeating: 0, count: 3 * n)
            b.withUnsafeBufferPointer { bp in E.vmul(a2, 2, bp.baseAddress! + (n - 1), -1, &o3, 3, ln) }
            return flat(o3)
        case "vdiv":
            let d = noise(n, seed: 7, scale: 0.5, offset: 1)   // divisor en [0,5, 1,5)
            E.vdiv(d, 1, a, 1, &out, 1, ln); return flat(out)
        case "vma": E.vma(a, 1, b, 1, c, 1, &out, 1, ln); return flat(out)
        case "vsma": E.vsma(a, 1, &k, b, 1, &out, 1, ln); return flat(out)
        case "vsma_inplace":
            // La mezcla mono de MonoAudio: dst = ch·k + dst, canal a canal.
            var dst = [Float](repeating: 0, count: n)
            var third: Float = 1 / 3
            for ch in [a, b, c] { mut(&dst) { E.vsma(ch, 1, &third, $0, 1, $0, 1, ln) } }
            return flat(dst)
        case "vsmsa": E.vsmsa(a, 1, &k, &s, &out, 1, ln); return flat(out)
        case "vsmul": E.vsmul(a, 1, &k, &out, 1, ln); return flat(out)
        case "vsmulD": E.vsmulD(ad, 1, &kd, &outD, 1, ln); return outD
        case "vsadd": E.vsadd(a, 1, &s, &out, 1, ln); return flat(out)
        case "vfill":
            var o = [Float](repeating: 9, count: 2 * n)
            E.vfill(&k, &o, 2, ln); return flat(o)
        case "vclr":
            var o = a
            E.vclr(&o, 1, DSPLength(n - 5)); return flat(o)
        case "vrvrs":
            var o = a
            E.vrvrs(&o, 1, ln); return flat(o)
        case "vabs": E.vabs(a, 1, &out, 1, ln); return flat(out)
        case "vabsD": E.vabsD(ad, 1, &outD, 1, ln); return outD
        case "vmax": E.vmax(a, 1, b, 1, &out, 1, ln); return flat(out)
        case "vmaxD": E.vmaxD(ad, 1, bd, 1, &outD, 1, ln); return outD
        case "vthres":
            var t: Float = 0.1
            E.vthres(a, 1, &t, &out, 1, ln); return flat(out)
        case "vspdp": E.vspdp(a, 1, &outD, 1, ln); return outD
        case "sve", "svesq", "meanv", "measqv", "rmsqv", "maxmgv", "dotpr":
            let x = noise(big, seed: 8, scale: 1, offset: 0.25), y = noise(big, seed: 9)
            var r: Float = 0
            let lb = DSPLength(big)
            switch name {
            case "sve": E.sve(x, 1, &r, lb)
            case "svesq": E.svesq(x, 1, &r, lb)
            case "meanv": E.meanv(x, 1, &r, lb)
            case "measqv": E.measqv(x, 1, &r, lb)
            case "rmsqv": E.rmsqv(x, 1, &r, lb)
            case "maxmgv": E.maxmgv(x, 1, &r, lb)
            default: E.dotpr(x, 1, y, 1, &r, lb)
            }
            // Con paso 3 sobre el mismo vector (BasicPitchNotes usa meanv con paso).
            var r3: Float = 0
            let l3 = DSPLength(big / 3)
            switch name {
            case "sve": E.sve(x, 3, &r3, l3)
            case "svesq": E.svesq(x, 3, &r3, l3)
            case "meanv": E.meanv(x, 3, &r3, l3)
            case "measqv": E.measqv(x, 3, &r3, l3)
            case "rmsqv": E.rmsqv(x, 3, &r3, l3)
            case "maxmgv": E.maxmgv(x, 3, &r3, l3)
            default: E.dotpr(x, 3, y, 3, &r3, l3)
            }
            return [Double(r), Double(r3)]
        case "maxvD":
            var r = 0.0
            E.maxvD(ad, 1, &r, ln); return [r]
        case "dotprD":
            let x = noiseD(big, seed: 10), y = noiseD(big, seed: 11)
            var r = 0.0
            E.dotprD(x, 1, y, 1, &r, DSPLength(big)); return [r]
        case "maximumF": return [Double(E.maximum(a))]
        case "maximumD": return [E.maximum(ad)]
        case "conv", "conv_reversed":
            let p = 17, x = noise(n + p - 1, seed: 12), h = noise(p, seed: 13)
            if name == "conv" {
                E.conv(x, 1, h, 1, &out, 1, ln, DSPLength(p))
            } else {   // convolución: filtro recorrido desde el último coeficiente
                h.withUnsafeBufferPointer { hp in E.conv(x, 1, hp.baseAddress! + (p - 1), -1, &out, 1, ln, DSPLength(p)) }
            }
            return flat(out)
        case "convD":
            let p = 9, x = noiseD(n + p - 1, seed: 14), h = noiseD(p, seed: 15)
            E.convD(x, 1, h, 1, &outD, 1, ln, DSPLength(p)); return outD
        case "desamp":
            let p = 23, x = noise(2 * n + p, seed: 16), h = noise(p, seed: 17)
            E.desamp(x, 2, h, &out, ln, DSPLength(p)); return flat(out)
        case "mmul":
            let m = 7, nn = 11, p = 13
            let x = noise(m * p, seed: 18), y = noise(p * nn, seed: 19)
            var r = [Float](repeating: 0, count: m * nn)
            E.mmul(x, 1, y, 1, &r, 1, DSPLength(m), DSPLength(nn), DSPLength(p)); return flat(r)
        case "zvabs":
            var re = a, im = b
            return mut(&re) { rp in mut(&im) { ip in
                var z = SplitComplex(realp: rp, imagp: ip)
                E.zvabs(&z, 1, &out, 1, ln)
                return flat(out)
            } }
        case "zvabs_stride2":
            // Complejos entrelazados vistos como planos con paso 2 (PanSplitter, MaskModel).
            var inter = noise(2 * n, seed: 20)
            return mut(&inter) { p in
                var z = SplitComplex(realp: p, imagp: p + 1)
                E.zvabs(&z, 2, &out, 1, ln)
                return flat(out)
            }
        case "zvmul", "zvmul_conj_inplace":
            var ar = a, ai = b, br = c, bi = noise(n, seed: 21), cr = out, ci = out
            return mut(&ar) { arp in mut(&ai) { aip in mut(&br) { brp in mut(&bi) { bip in mut(&cr) { crp in mut(&ci) { cip in
                var za = SplitComplex(realp: arp, imagp: aip), zb = SplitComplex(realp: brp, imagp: bip)
                if name == "zvmul" {
                    var zc = SplitComplex(realp: crp, imagp: cip)
                    E.zvmul(&za, 1, &zb, 1, &zc, 1, ln, 1)
                    return flat(Array(UnsafeBufferPointer(start: crp, count: n)) + Array(UnsafeBufferPointer(start: cip, count: n)))
                }
                E.zvmul(&za, 1, &zb, 1, &zb, 1, ln, -1)   // b = conj(a)·b en el sitio, como ChunkProcessor
                return flat(Array(UnsafeBufferPointer(start: brp, count: n)) + Array(UnsafeBufferPointer(start: bip, count: n)))
            } } } } } }
        case "zvmov":
            var re = a, im = b, inter = [Float](repeating: 0, count: 2 * n)
            return mut(&re) { rp in mut(&im) { ip in mut(&inter) { op in
                var src = SplitComplex(realp: rp, imagp: ip), dst = SplitComplex(realp: op, imagp: op + 1)
                E.zvmov(&src, 1, &dst, 2, ln)
                return flat(Array(UnsafeBufferPointer(start: op, count: 2 * n)))
            } } }
        case "ctoz":
            let x = noise(2 * n, seed: 22)
            var re = out, im = out
            return mut(&re) { rp in mut(&im) { ip in
                var z = SplitComplex(realp: rp, imagp: ip)
                x.withUnsafeBufferPointer { xp in
                    UnsafeRawPointer(xp.baseAddress!).withMemoryRebound(to: InterleavedComplex.self, capacity: n) {
                        E.ctoz($0, 2, &z, 1, ln)
                    }
                }
                return flat(Array(UnsafeBufferPointer(start: rp, count: n)) + Array(UnsafeBufferPointer(start: ip, count: n)))
            } }
        case "ztoc":
            var re = a, im = b, x = [Float](repeating: 0, count: 2 * n)
            return mut(&re) { rp in mut(&im) { ip in mut(&x) { xp in
                var z = SplitComplex(realp: rp, imagp: ip)
                UnsafeMutableRawPointer(xp).withMemoryRebound(to: InterleavedComplex.self, capacity: n) { E.ztoc(&z, 1, $0, 2, ln) }
                return flat(Array(UnsafeBufferPointer(start: xp, count: 2 * n)))
            } } }
        case "vvlogf", "vvlog1pf", "vvlog10f":
            let x = noise(n, seed: 23, scale: 5, offset: 5.01)   // (0, 10]
            var cnt = Int32(n)
            switch name {
            case "vvlogf": E.vvlogf(&out, x, &cnt)
            case "vvlog1pf": E.vvlog1pf(&out, x, &cnt)
            default: E.vvlog10f(&out, x, &cnt)
            }
            return flat(out)
        case "convertFD": E.convertElements(of: a, to: &outD); return outD
        case "convertDF": E.convertElements(of: ad, to: &out); return flat(out)
        case "planar16F": return planar16F(E.self)
        case "realDFT_fwd_512", "realDFT_inv_512": return realDFT(E.self, inverse: name.contains("inv"))
        case "complexDFT_fwd_192", "complexDFT_inv_128":
            let inv = name.contains("inv"), len = inv ? 128 : 192
            let setup = E.ComplexDFT(count: len, direction: inv ? .inverse : .forward)!
            let ir = noise(len, seed: 24), ii = noise(len, seed: 25)
            var or = [Float](repeating: 0, count: len), oi = or
            setup.execute(ir, ii, &or, &oi)
            return flat(or + oi)
        case "complexDFTD_fwd_256", "complexDFTD_inv_256":
            let inv = name.contains("inv"), len = 256
            let setup = E.ComplexDFTD(count: len, direction: inv ? .inverse : .forward)!
            let ir = noiseD(len, seed: 26), ii = noiseD(len, seed: 27)
            var or = [Double](repeating: 0, count: len), oi = or
            setup.execute(ir, ii, &or, &oi)
            return or + oi
        case "biquad_kweight":
            let setup = E.Biquad(coefficients: kWeighting48k, sections: 2)!
            let x = noise(4096, seed: 28, scale: 0.5)
            var y = [Float](repeating: 0, count: 4096)
            var delay = [Float](repeating: 0, count: 6)
            let cut = 1500
            x.withUnsafeBufferPointer { xp in mut(&y) { yp in mut(&delay) { dp in
                setup.execute(dp, xp.baseAddress!, 1, yp, 1, DSPLength(cut))
                setup.execute(dp, xp.baseAddress! + cut, 1, yp + cut, 1, DSPLength(4096 - cut))
            } } }
            return flat(y + delay)
        default:
            fatalError("caso desconocido \(name)")
        }
    }

    /// Señal de prueba realista: tres resonadores (senoidales por recurrencia, sin libm, para que la entrada
    /// sea idéntica bit a bit en todas las máquinas) y ruido.
    static func tones(_ len: Int) -> [Float] {
        let r = noise(len, seed: 29, scale: 0.05)
        let coefs: [Float] = [1.9975, 1.4300, -1.9500]   // 2·cos(ω) de tres frecuencias
        let amps: [Float] = [0.6, 0.3, 0.1]
        var out = r
        for (c, amp) in zip(coefs, amps) {
            var y1: Float = 0, y2: Float = amp * 0.05
            for i in 0..<len {
                let y = c * y1 - y2
                y2 = y1
                y1 = y
                out[i] += y
            }
        }
        return out
    }

    /// `vDSP_DFT_zrop` de 512 como lo usan LogMel/DrumSpectrogram (ctoz con paso 2 → Execute) y su inversa
    /// (SpectralTransform).
    static func realDFT<E: DSPEngine>(_: E.Type, inverse: Bool) -> [Double] {
        let len = 512, half = len / 2
        let fwd = E.RealDFT(count: len, direction: .forward)!
        let x = tones(len)
        var ir = [Float](repeating: 0, count: half), ii = ir, or = ir, oi = ir
        mut(&ir) { rp in mut(&ii) { ip in
            var z = SplitComplex(realp: rp, imagp: ip)
            x.withUnsafeBufferPointer { xp in
                UnsafeRawPointer(xp.baseAddress!).withMemoryRebound(to: InterleavedComplex.self, capacity: half) {
                    E.ctoz($0, 2, &z, 1, DSPLength(half))
                }
            }
        } }
        fwd.execute(ir, ii, &or, &oi)
        guard inverse else { return flat(or + oi) }
        let inv = E.RealDFT(count: len, direction: .inverse)!
        var br = ir, bi = ii
        inv.execute(or, oi, &br, &bi)
        return flat(br + bi)
    }

    /// FP16 → FP32 con filas de paso mayor que el ancho (MaskModel lee pares re/im de un tensor con paso).
    static func planar16F<E: DSPEngine>(_: E.Type) -> [Double] {
        let patterns: [UInt16] = [0x0000, 0x8000, 0x0001, 0x8001, 0x03FF, 0x0400, 0x3C00, 0xBC00, 0x3555, 0x7BFF, 0xFBFF,
                                  0x2E66, 0xC948, 0x1234, 0x5678, 0x0200]
        let rows = 8, width = 2, srcStride = 5   // 5 halfs por fila, se leen 2
        var src = [UInt16](repeating: 0x7E00, count: rows * srcStride)   // relleno NaN: no debe leerse
        for r in 0..<rows { for x in 0..<width { src[r * srcStride + x] = patterns[(r * width + x) % patterns.count] } }
        var dst = [Float](repeating: 0, count: rows * width)
        let err = mut(&src) { sp in mut(&dst) { dp in
            var s = ImageBuffer(data: UnsafeMutableRawPointer(sp), height: PixelCount(rows), width: PixelCount(width),
                                rowBytes: srcStride * 2)
            var d = ImageBuffer(data: UnsafeMutableRawPointer(dp), height: PixelCount(rows), width: PixelCount(width),
                                rowBytes: width * 4)
            return E.convertPlanar16FtoPlanarF(&s, &d)
        } }
        return [Double(err)] + flat(dst)
    }

    /// `SignalMath.analyticCorrelation` (AudioKit) con el motor dado: envolvente de la correlación de x con s
    /// por FFT compleja double; de su pico sale la latencia de ida y vuelta. Devuelve (índice, posición
    /// subamuestra parabólica, valor).
    static func correlationPeak<E: DSPEngine>(_: E.Type) -> (index: Int, position: Double, value: Double) {
        let sn = 1024, xn = 40_000, delay = 12_345
        let s = noise(sn, seed: 7)
        var xs = noise(xn, seed: 99, scale: 0.01)
        for i in 0..<sn { xs[delay + i] += 0.5 * s[i] }
        var m = 1
        while m < xn + sn { m <<= 1 }
        let fwd = E.ComplexDFTD(count: m, direction: .forward)!, inv = E.ComplexDFTD(count: m, direction: .inverse)!
        let zeros = [Double](repeating: 0, count: m)
        var xr = zeros, sr = zeros
        mut(&xr) { E.vspdp(xs, 1, $0, 1, DSPLength(xn)) }
        mut(&sr) { E.vspdp(s, 1, $0, 1, DSPLength(sn)) }
        var xR = zeros, xI = zeros, sR = zeros, sI = zeros
        fwd.execute(xr, zeros, &xR, &xI)
        fwd.execute(sr, zeros, &sR, &sI)
        var cR = zeros, cI = zeros
        for k in 0...(m / 2) {
            let w: Double = (k == 0 || k == m / 2) ? 1 : 2
            cR[k] = w * (xR[k] * sR[k] + xI[k] * sI[k])
            cI[k] = w * (xI[k] * sR[k] - xR[k] * sI[k])
        }
        var oR = zeros, oI = zeros
        inv.execute(cR, cI, &oR, &oI)
        let scale = 1 / Double(m)
        let env = (0..<xn).map { (oR[$0] * oR[$0] + oI[$0] * oI[$0]).squareRoot() * scale }
        let peak = env.indices.max { env[$0] < env[$1] }!
        let (p0, p1, p2) = (env[peak - 1], env[peak], env[peak + 1])
        return (peak, Double(peak) + 0.5 * (p0 - p2) / (p0 - 2 * p1 + p2), p1)
    }
}

/// Error máximo relativo al máximo |referencia| (y el índice del peor elemento).
func relativeError(_ got: [Double], _ ref: [Double]) -> (rel: Double, worst: Int) {
    guard got.count == ref.count, !ref.isEmpty else { return (.infinity, -1) }
    let peak = max(ref.map { abs($0) }.max()!, 1e-30)
    var err = 0.0, worst = 0
    for i in ref.indices {
        let e = abs(got[i] - ref[i])
        if e > err || e.isNaN { err = e; worst = i }
    }
    return (err / peak, worst)
}
