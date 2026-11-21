import CPocketFFT

/// `vDSP_conv` portátil: bucle directo para filtros o salidas cortos y FFT por bloques (pocketfft, double)
/// para los largos. Contrato: `c[k·ic] = Σ_{j<p} a[(k+j)·ia] · f[j·iff]`, `k < n`; cualquier paso (también
/// `iff` < 0, la convolución).
///
/// Por qué FFT: `TakeAligner.rigDelay` hace en cada toma una correlación de 951 salidas × 2,65 M de filtro y
/// dos envolventes de 2,65 M × 129; en Windows (Debug, x64 emulado) el bucle directo tardaba 72 s por toma.
extension DSPPortable {
    /// Lado menor (`min(n, p)`) desde el que se usa la FFT; por debajo el bucle directo gana o empata.
    static let fftConvMinSide = 64
    /// Tamaño de la FFT: ≥ 8× el lado menor (bloques largos, poco gasto por bloque) hasta este tope, y nunca
    /// menos de 2× el lado menor (lo que hace falta para que la convolución circular no se solape).
    static let fftConvMinSize = 256
    static let fftConvMaxPreferredSize = 1 << 20

    /// Despacho de `conv`: mismo resultado por las dos rutas dentro del redondeo (la FFT trabaja en double).
    static func convPortable(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ f: UnsafePointer<Float>, _ iff: DSPStride,
                             _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: Int, _ p: Int) {
        guard n > 0 else { return }
        if min(n, p) >= fftConvMinSide {
            convFFT(a, ia, f, iff, c, ic, n, p)
        } else {
            convDirect(a, ia, f, iff, c, ic, n, p)
        }
    }

    /// Bucle directo, acumulando en double con el mismo orden que `sum` (cuatro carriles), sin cierres.
    static func convDirect(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ f: UnsafePointer<Float>, _ iff: DSPStride,
                           _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: Int, _ p: Int) {
        for k in 0..<n {
            let base = a + k * ia
            var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0
            var j = 0
            if ia == 1 && iff == 1 {
                while j + 4 <= p {
                    s0 += Double(base[j]) * Double(f[j])
                    s1 += Double(base[j + 1]) * Double(f[j + 1])
                    s2 += Double(base[j + 2]) * Double(f[j + 2])
                    s3 += Double(base[j + 3]) * Double(f[j + 3])
                    j += 4
                }
                while j < p { s0 += Double(base[j]) * Double(f[j]); j += 1 }
            } else {
                while j + 4 <= p {
                    s0 += Double(base[j * ia]) * Double(f[j * iff])
                    s1 += Double(base[(j + 1) * ia]) * Double(f[(j + 1) * iff])
                    s2 += Double(base[(j + 2) * ia]) * Double(f[(j + 2) * iff])
                    s3 += Double(base[(j + 3) * ia]) * Double(f[(j + 3) * iff])
                    j += 4
                }
                while j < p { s0 += Double(base[j * ia]) * Double(f[j * iff]); j += 1 }
            }
            c[k * ic] = Float((s0 + s1) + (s2 + s3))
        }
    }

    /// Tamaño de FFT para un lado menor `s`.
    static func fftConvSize(_ s: Int) -> Int {
        var size = fftConvMinSize
        while size < 8 * s && size < fftConvMaxPreferredSize { size <<= 1 }
        while size < 2 * s { size <<= 1 }
        return size
    }

    /// Correlación por bloques con FFT real de tamaño `N`. El lado menor cabe entero en un bloque, así que
    /// solo se trocea el mayor:
    /// - `n ≤ p` (pocas salidas, filtro largo; `rigDelay`): el filtro va en trozos de `N − n + 1`; los
    ///   productos de espectros se suman en frecuencia y hay una sola inversa al final.
    /// - `n > p` (señal larga, filtro corto; envolventes): espectro del filtro una vez y overlap-save sobre
    ///   las salidas en bloques de `N − p + 1`.
    /// La correlación circular `IFFT(A·conj(F))[k]` no se solapa para `k` < bloque de salidas porque el
    /// segmento de `a` mide `bloque + trozo − 1 ≤ N`.
    static func convFFT(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ f: UnsafePointer<Float>, _ iff: DSPStride,
                        _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: Int, _ p: Int) {
        let size = fftConvSize(min(n, p))
        guard let plan = make_rfft_plan(size) else { return convDirect(a, ia, f, iff, c, ic, n, p) }
        defer { destroy_rfft_plan(plan) }
        let bufA = UnsafeMutablePointer<Double>.allocate(capacity: size)
        let bufF = UnsafeMutablePointer<Double>.allocate(capacity: size)
        defer { bufA.deallocate(); bufF.deallocate() }
        let scale = 1 / Double(size)

        if n <= p {
            let acc = UnsafeMutablePointer<Double>.allocate(capacity: size)
            defer { acc.deallocate() }
            acc.initialize(repeating: 0, count: size)
            let chunk = size - n + 1
            var j0 = 0
            while j0 < p {
                let len = min(chunk, p - j0)
                load(bufA, size, a + j0 * ia, ia, n + len - 1)
                load(bufF, size, f + j0 * iff, iff, len)
                _ = rfft_forward(plan, bufA, 1)
                _ = rfft_forward(plan, bufF, 1)
                multiplyConjugate(bufA, bufF, into: acc, accumulate: true, size)
                j0 += len
            }
            _ = rfft_backward(plan, acc, scale)
            for k in 0..<n { c[k * ic] = Float(acc[k]) }
        } else {
            load(bufF, size, f, iff, p)
            _ = rfft_forward(plan, bufF, 1)
            let block = size - p + 1
            var k0 = 0
            while k0 < n {
                let len = min(block, n - k0)
                load(bufA, size, a + k0 * ia, ia, len + p - 1)
                _ = rfft_forward(plan, bufA, 1)
                multiplyConjugate(bufA, bufF, into: bufA, accumulate: false, size)
                _ = rfft_backward(plan, bufA, scale)
                let out = c + k0 * ic
                if ic == 1 {
                    for k in 0..<len { out[k] = Float(bufA[k]) }
                } else {
                    for k in 0..<len { out[k * ic] = Float(bufA[k]) }
                }
                k0 += len
            }
        }
    }

    /// `dst[0..<count] = src[i·stride]` en double y ceros hasta `size`.
    @inline(__always)
    private static func load(_ dst: UnsafeMutablePointer<Double>, _ size: Int, _ src: UnsafePointer<Float>,
                             _ stride: DSPStride, _ count: Int) {
        if stride == 1 {
            for i in 0..<count { dst[i] = Double(src[i]) }
        } else {
            for i in 0..<count { dst[i] = Double(src[i * stride]) }
        }
        (dst + count).update(repeating: 0, count: size - count)
    }

    /// `out (+)= x · conj(y)` con espectros en formato FFTPACK de pocketfft (`size` par):
    /// `[r0, r1, i1, …, r(size/2−1), i(size/2−1), r(size/2)]`. `out` puede ser `x`.
    @inline(__always)
    private static func multiplyConjugate(_ x: UnsafeMutablePointer<Double>, _ y: UnsafeMutablePointer<Double>,
                                          into out: UnsafeMutablePointer<Double>, accumulate: Bool, _ size: Int) {
        let last = size - 1
        if accumulate {
            out[0] += x[0] * y[0]
            out[last] += x[last] * y[last]
            var i = 1
            while i < last {
                let xr = x[i], xi = x[i + 1], yr = y[i], yi = y[i + 1]
                out[i] += xr * yr + xi * yi
                out[i + 1] += xi * yr - xr * yi
                i += 2
            }
        } else {
            out[0] = x[0] * y[0]
            out[last] = x[last] * y[last]
            var i = 1
            while i < last {
                let xr = x[i], xi = x[i + 1], yr = y[i], yi = y[i + 1]
                out[i] = xr * yr + xi * yi
                out[i + 1] = xi * yr - xr * yi
                i += 2
            }
        }
    }
}
