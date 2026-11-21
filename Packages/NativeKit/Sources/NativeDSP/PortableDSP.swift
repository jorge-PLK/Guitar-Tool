import Foundation

/// Motor portátil de la fachada DSP: Swift puro (y pocketfft para las DFT), compila en todos los sistemas.
/// Mismo contrato que vDSP (argumentos, pasos negativos, operación en el sitio); las reducciones acumulan en
/// `Double`, así que su error es menor que el de vDSP y la diferencia entre motores es el error de vDSP.
/// En Windows es el motor de `DSP`; en el Mac solo lo usan los tests que lo comparan con vDSP.
public enum DSPPortable: DSPEngine {
    public typealias RealDFT = PortableRealDFT
    public typealias ComplexDFT = PortableComplexDFT<Float>
    public typealias ComplexDFTD = PortableComplexDFT<Double>
    public typealias Biquad = PortableBiquad

    // MARK: Elemento a elemento

    public static func vadd(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                            _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        let n = Int(n)
        if ia == 1 && ib == 1 && ic == 1 { for i in 0..<n { c[i] = a[i] + b[i] }; return }
        for i in 0..<n { c[i * ic] = a[i * ia] + b[i * ib] }
    }

    public static func vaddD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ b: UnsafePointer<Double>, _ ib: DSPStride,
                             _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride, _ n: DSPLength) {
        for i in 0..<Int(n) { c[i * ic] = a[i * ia] + b[i * ib] }
    }

    /// `c = a − b` (el primer argumento es el sustraendo, como en vDSP).
    public static func vsub(_ b: UnsafePointer<Float>, _ ib: DSPStride, _ a: UnsafePointer<Float>, _ ia: DSPStride,
                            _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        let n = Int(n)
        if ia == 1 && ib == 1 && ic == 1 { for i in 0..<n { c[i] = a[i] - b[i] }; return }
        for i in 0..<n { c[i * ic] = a[i * ia] - b[i * ib] }
    }

    public static func vmul(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                            _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        let n = Int(n)
        if ia == 1 && ib == 1 && ic == 1 { for i in 0..<n { c[i] = a[i] * b[i] }; return }
        for i in 0..<n { c[i * ic] = a[i * ia] * b[i * ib] }
    }

    /// `c = a / b` (el primer argumento es el divisor, como en vDSP).
    public static func vdiv(_ b: UnsafePointer<Float>, _ ib: DSPStride, _ a: UnsafePointer<Float>, _ ia: DSPStride,
                            _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        for i in 0..<Int(n) { c[i * ic] = a[i * ia] / b[i * ib] }
    }

    /// `d = a·b + c`.
    public static func vma(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                           _ c: UnsafePointer<Float>, _ ic: DSPStride, _ d: UnsafeMutablePointer<Float>, _ id: DSPStride,
                           _ n: DSPLength) {
        let n = Int(n)
        if ia == 1 && ib == 1 && ic == 1 && id == 1 { for i in 0..<n { d[i] = a[i] * b[i] + c[i] }; return }
        for i in 0..<n { d[i * id] = a[i * ia] * b[i * ib] + c[i * ic] }
    }

    /// `d = a·b + c` con `b` escalar.
    public static func vsma(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>,
                            _ c: UnsafePointer<Float>, _ ic: DSPStride, _ d: UnsafeMutablePointer<Float>, _ id: DSPStride,
                            _ n: DSPLength) {
        let n = Int(n), k = b.pointee
        if ia == 1 && ic == 1 && id == 1 { for i in 0..<n { d[i] = a[i] * k + c[i] }; return }
        for i in 0..<n { d[i * id] = a[i * ia] * k + c[i * ic] }
    }

    /// `d = a·b + c` con `b` y `c` escalares.
    public static func vsmsa(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ c: UnsafePointer<Float>,
                             _ d: UnsafeMutablePointer<Float>, _ id: DSPStride, _ n: DSPLength) {
        let k = b.pointee, s = c.pointee
        for i in 0..<Int(n) { d[i * id] = a[i * ia] * k + s }
    }

    public static func vsmul(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>,
                             _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        let n = Int(n), k = b.pointee
        if ia == 1 && ic == 1 { for i in 0..<n { c[i] = a[i] * k }; return }
        for i in 0..<n { c[i * ic] = a[i * ia] * k }
    }

    public static func vsmulD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ b: UnsafePointer<Double>,
                              _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride, _ n: DSPLength) {
        let k = b.pointee
        for i in 0..<Int(n) { c[i * ic] = a[i * ia] * k }
    }

    public static func vsadd(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>,
                             _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        let k = b.pointee
        for i in 0..<Int(n) { c[i * ic] = a[i * ia] + k }
    }

    public static func vfill(_ a: UnsafePointer<Float>, _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        let k = a.pointee
        for i in 0..<Int(n) { c[i * ic] = k }
    }

    public static func vclr(_ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        for i in 0..<Int(n) { c[i * ic] = 0 }
    }

    /// Invierte el orden en el sitio.
    public static func vrvrs(_ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        var lo = 0, hi = Int(n) - 1
        while lo < hi {
            let t = c[lo * ic]
            c[lo * ic] = c[hi * ic]
            c[hi * ic] = t
            lo += 1
            hi -= 1
        }
    }

    public static func vabs(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride,
                            _ n: DSPLength) {
        for i in 0..<Int(n) { c[i * ic] = abs(a[i * ia]) }
    }

    public static func vabsD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride,
                             _ n: DSPLength) {
        for i in 0..<Int(n) { c[i * ic] = abs(a[i * ia]) }
    }

    public static func vmax(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                            _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        for i in 0..<Int(n) { let x = a[i * ia], y = b[i * ib]; c[i * ic] = x >= y ? x : y }
    }

    public static func vmaxD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ b: UnsafePointer<Double>, _ ib: DSPStride,
                             _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride, _ n: DSPLength) {
        for i in 0..<Int(n) { let x = a[i * ia], y = b[i * ib]; c[i * ic] = x >= y ? x : y }
    }

    /// `c = a ≥ b ? a : 0` con `b` escalar.
    public static func vthres(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>,
                              _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        let t = b.pointee
        for i in 0..<Int(n) { let x = a[i * ia]; c[i * ic] = x >= t ? x : 0 }
    }

    /// Float → Double.
    public static func vspdp(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride,
                             _ n: DSPLength) {
        for i in 0..<Int(n) { c[i * ic] = Double(a[i * ia]) }
    }

    // MARK: Reducciones (acumulan en Double)

    @inline(__always)
    static func sum(_ n: Int, _ f: (Int) -> Double) -> Double {
        var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0
        var i = 0
        while i + 4 <= n {
            s0 += f(i); s1 += f(i + 1); s2 += f(i + 2); s3 += f(i + 3)
            i += 4
        }
        while i < n { s0 += f(i); i += 1 }
        return (s0 + s1) + (s2 + s3)
    }

    // Bucles directos con el mismo orden de suma que `sum` (4 acumuladores, resto en s0, `(s0 + s1) + (s2 + s3)`),
    // bit a bit iguales, pero sin cierre: en Debug (-Onone) el cierre no se funde y su llamada por elemento era
    // el coste dominante del audio simulado en Windows. Sin genéricos ni rangos en el bucle interno (en -Onone
    // `for in 0..<n` pasa por el iterador genérico); punteros que avanzan y `Int` locales.

    /// Σ a[i·ia]·b[i·ib], cada factor promocionado a Double antes de multiplicar.
    static func dotSum(_ a: UnsafePointer<Float>, _ ia: Int, _ b: UnsafePointer<Float>, _ ib: Int, _ n: Int) -> Double {
        var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0
        var pa = a, pb = b
        var i = 0
        if ia == 1 && ib == 1 {
            while i + 4 <= n {
                s0 += Double(pa[0]) * Double(pb[0]); s1 += Double(pa[1]) * Double(pb[1])
                s2 += Double(pa[2]) * Double(pb[2]); s3 += Double(pa[3]) * Double(pb[3])
                pa += 4; pb += 4; i += 4
            }
            while i < n { s0 += Double(pa.pointee) * Double(pb.pointee); pa += 1; pb += 1; i += 1 }
            return (s0 + s1) + (s2 + s3)
        }
        while i + 4 <= n {
            s0 += Double(pa.pointee) * Double(pb.pointee); pa += ia; pb += ib
            s1 += Double(pa.pointee) * Double(pb.pointee); pa += ia; pb += ib
            s2 += Double(pa.pointee) * Double(pb.pointee); pa += ia; pb += ib
            s3 += Double(pa.pointee) * Double(pb.pointee); pa += ia; pb += ib
            i += 4
        }
        while i < n { s0 += Double(pa.pointee) * Double(pb.pointee); pa += ia; pb += ib; i += 1 }
        return (s0 + s1) + (s2 + s3)
    }

    /// Σ a[i·ia]·b[i·ib] en Double.
    static func dotSum(_ a: UnsafePointer<Double>, _ ia: Int, _ b: UnsafePointer<Double>, _ ib: Int, _ n: Int) -> Double {
        var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0
        var pa = a, pb = b
        var i = 0
        if ia == 1 && ib == 1 {
            while i + 4 <= n {
                s0 += pa[0] * pb[0]; s1 += pa[1] * pb[1]; s2 += pa[2] * pb[2]; s3 += pa[3] * pb[3]
                pa += 4; pb += 4; i += 4
            }
            while i < n { s0 += pa.pointee * pb.pointee; pa += 1; pb += 1; i += 1 }
            return (s0 + s1) + (s2 + s3)
        }
        while i + 4 <= n {
            s0 += pa.pointee * pb.pointee; pa += ia; pb += ib
            s1 += pa.pointee * pb.pointee; pa += ia; pb += ib
            s2 += pa.pointee * pb.pointee; pa += ia; pb += ib
            s3 += pa.pointee * pb.pointee; pa += ia; pb += ib
            i += 4
        }
        while i < n { s0 += pa.pointee * pb.pointee; pa += ia; pb += ib; i += 1 }
        return (s0 + s1) + (s2 + s3)
    }

    /// Σ a[i·ia] (o Σ a[i·ia]² si `squares`), cada elemento promocionado a Double.
    static func plainSum(_ a: UnsafePointer<Float>, _ ia: Int, _ n: Int, squares: Bool) -> Double {
        var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0
        var pa = a
        var i = 0
        if squares {
            var x = 0.0
            while i + 4 <= n {
                x = Double(pa.pointee); s0 += x * x; pa += ia
                x = Double(pa.pointee); s1 += x * x; pa += ia
                x = Double(pa.pointee); s2 += x * x; pa += ia
                x = Double(pa.pointee); s3 += x * x; pa += ia
                i += 4
            }
            while i < n { x = Double(pa.pointee); s0 += x * x; pa += ia; i += 1 }
        } else {
            while i + 4 <= n {
                s0 += Double(pa.pointee); pa += ia
                s1 += Double(pa.pointee); pa += ia
                s2 += Double(pa.pointee); pa += ia
                s3 += Double(pa.pointee); pa += ia
                i += 4
            }
            while i < n { s0 += Double(pa.pointee); pa += ia; i += 1 }
        }
        return (s0 + s1) + (s2 + s3)
    }

    public static func sve(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength) {
        c.pointee = Float(plainSum(a, ia, Int(n), squares: false))
    }

    public static func svesq(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength) {
        c.pointee = Float(plainSum(a, ia, Int(n), squares: true))
    }

    public static func meanv(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength) {
        c.pointee = Float(plainSum(a, ia, Int(n), squares: false) / Double(n))
    }

    public static func measqv(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength) {
        c.pointee = Float(plainSum(a, ia, Int(n), squares: true) / Double(n))
    }

    public static func rmsqv(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength) {
        c.pointee = Float((plainSum(a, ia, Int(n), squares: true) / Double(n)).squareRoot())
    }

    /// Máximo de |a| (0 si `n` = 0).
    public static func maxmgv(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength) {
        var m: Float = 0
        for i in 0..<Int(n) { m = max(m, abs(a[i * ia])) }
        c.pointee = m
    }

    /// Máximo (−∞ si `n` = 0).
    public static func maxvD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Double>, _ n: DSPLength) {
        var m = -Double.infinity
        for i in 0..<Int(n) { let x = a[i * ia]; if x > m { m = x } }
        c.pointee = m
    }

    public static func dotpr(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                             _ c: UnsafeMutablePointer<Float>, _ n: DSPLength) {
        c.pointee = Float(dotSum(a, ia, b, ib, Int(n)))
    }

    public static func dotprD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ b: UnsafePointer<Double>, _ ib: DSPStride,
                              _ c: UnsafeMutablePointer<Double>, _ n: DSPLength) {
        c.pointee = dotSum(a, ia, b, ib, Int(n))
    }

    /// `vDSP.maximum` (−∞ con el vector vacío).
    public static func maximum(_ x: [Float]) -> Float { x.reduce(-Float.infinity) { $1 > $0 ? $1 : $0 } }
    public static func maximum(_ x: [Double]) -> Double { x.reduce(-Double.infinity) { $1 > $0 ? $1 : $0 } }

    // MARK: Filtros y matrices

    /// Correlación (`iff` > 0) o convolución (`iff` < 0, con `f` apuntando al último coeficiente):
    /// `c[k·ic] = Σ_{j<p} a[(k+j)·ia] · f[j·iff]`. Bucle directo o FFT por bloques según el tamaño
    /// (`PortableConv.swift`).
    public static func conv(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ f: UnsafePointer<Float>, _ iff: DSPStride,
                            _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength, _ p: DSPLength) {
        convPortable(a, ia, f, iff, c, ic, Int(n), Int(p))
    }

    public static func convD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ f: UnsafePointer<Double>, _ iff: DSPStride,
                             _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride, _ n: DSPLength, _ p: DSPLength) {
        let p = Int(p), n = Int(n)
        var k = 0
        while k < n { c[k * ic] = dotSum(a + k * ia, ia, f, iff, p); k += 1 }
    }

    /// Diezmado con FIR: `c[k] = Σ_{j<p} a[k·df + j] · f[j]`.
    public static func desamp(_ a: UnsafePointer<Float>, _ df: DSPStride, _ f: UnsafePointer<Float>,
                              _ c: UnsafeMutablePointer<Float>, _ n: DSPLength, _ p: DSPLength) {
        let p = Int(p), n = Int(n)
        var k = 0
        while k < n { c[k] = Float(dotSum(a + k * df, 1, f, 1, p)); k += 1 }
    }

    /// `C (m×n) = A (m×p) · B (p×n)`, por filas; cada fila de C se acumula en Double.
    public static func mmul(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                            _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ m: DSPLength, _ n: DSPLength, _ p: DSPLength) {
        let m = Int(m), n = Int(n), p = Int(p)
        guard n > 0 else { return }
        withUnsafeTemporaryAllocation(of: Double.self, capacity: n) { row in
            let r = row.baseAddress!
            for i in 0..<m {
                r.update(repeating: 0, count: n)
                for k in 0..<p {
                    let aik = Double(a[(i * p + k) * ia])
                    if aik == 0 { continue }
                    let bk = b + k * n * ib
                    if ib == 1 {
                        for j in 0..<n { r[j] += aik * Double(bk[j]) }
                    } else {
                        for j in 0..<n { r[j] += aik * Double(bk[j * ib]) }
                    }
                }
                for j in 0..<n { c[(i * n + j) * ic] = Float(r[j]) }
            }
        }
    }

    // MARK: Complejos

    public static func zvabs(_ a: UnsafePointer<SplitComplex>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>,
                             _ ic: DSPStride, _ n: DSPLength) {
        let re = a.pointee.realp, im = a.pointee.imagp
        for i in 0..<Int(n) {
            let x = re[i * ia], y = im[i * ia]
            c[i * ic] = (x * x + y * y).squareRoot()
        }
    }

    /// `c = a·b`, o `conj(a)·b` si `conjugate` = −1. Vale en el sitio (`c` igual a `a` o a `b`).
    public static func zvmul(_ a: UnsafePointer<SplitComplex>, _ ia: DSPStride, _ b: UnsafePointer<SplitComplex>,
                             _ ib: DSPStride, _ c: UnsafePointer<SplitComplex>, _ ic: DSPStride, _ n: DSPLength,
                             _ conjugate: Int32) {
        let ar = a.pointee.realp, ai = a.pointee.imagp, br = b.pointee.realp, bi = b.pointee.imagp
        let cr = c.pointee.realp, ci = c.pointee.imagp
        let s: Float = conjugate < 0 ? -1 : 1
        for i in 0..<Int(n) {
            let xr = ar[i * ia], xi = s * ai[i * ia], yr = br[i * ib], yi = bi[i * ib]
            cr[i * ic] = xr * yr - xi * yi
            ci[i * ic] = xr * yi + xi * yr
        }
    }

    public static func zvmov(_ a: UnsafePointer<SplitComplex>, _ ia: DSPStride, _ c: UnsafePointer<SplitComplex>,
                             _ ic: DSPStride, _ n: DSPLength) {
        let ar = a.pointee.realp, ai = a.pointee.imagp, cr = c.pointee.realp, ci = c.pointee.imagp
        for i in 0..<Int(n) {
            cr[i * ic] = ar[i * ia]
            ci[i * ic] = ai[i * ia]
        }
    }

    /// Entrelazado → planos. `ic` cuenta en `Float` (2 = contiguo), como en vDSP.
    public static func ctoz(_ c: UnsafePointer<InterleavedComplex>, _ ic: DSPStride, _ z: UnsafePointer<SplitComplex>,
                            _ iz: DSPStride, _ n: DSPLength) {
        let zr = z.pointee.realp, zi = z.pointee.imagp, step = ic / 2
        for i in 0..<Int(n) {
            let v = c[i * step]
            zr[i * iz] = v.real
            zi[i * iz] = v.imag
        }
    }

    /// Planos → entrelazado. `ic` cuenta en `Float` (2 = contiguo), como en vDSP.
    public static func ztoc(_ z: UnsafePointer<SplitComplex>, _ iz: DSPStride, _ c: UnsafeMutablePointer<InterleavedComplex>,
                            _ ic: DSPStride, _ n: DSPLength) {
        let zr = z.pointee.realp, zi = z.pointee.imagp, step = ic / 2
        for i in 0..<Int(n) { c[i * step] = InterleavedComplex(real: zr[i * iz], imag: zi[i * iz]) }
    }

    // MARK: vForce

    public static func vvlogf(_ y: UnsafeMutablePointer<Float>, _ x: UnsafePointer<Float>, _ n: UnsafePointer<Int32>) {
        for i in 0..<Int(n.pointee) { y[i] = Foundation.log(x[i]) }
    }

    public static func vvlog1pf(_ y: UnsafeMutablePointer<Float>, _ x: UnsafePointer<Float>, _ n: UnsafePointer<Int32>) {
        for i in 0..<Int(n.pointee) { y[i] = Foundation.log1p(x[i]) }
    }

    public static func vvlog10f(_ y: UnsafeMutablePointer<Float>, _ x: UnsafePointer<Float>, _ n: UnsafePointer<Int32>) {
        for i in 0..<Int(n.pointee) { y[i] = Foundation.log10(x[i]) }
    }

    // MARK: Conversiones

    /// `vDSP.convertElements(of:to:)`: `destination` ya tiene la longitud de `source`.
    public static func convertElements(of source: [Float], to destination: inout [Double]) {
        precondition(source.count == destination.count, "convertElements: longitudes distintas")
        for i in source.indices { destination[i] = Double(source[i]) }
    }

    public static func convertElements(of source: [Double], to destination: inout [Float]) {
        precondition(source.count == destination.count, "convertElements: longitudes distintas")
        for i in source.indices { destination[i] = Float(source[i]) }
    }

    /// `vImageConvert_Planar16FtoPlanarF`: IEEE 754 binario16 → Float, exacto (incluidos subnormales, ±∞ y NaN).
    /// Recorre las dimensiones de `dst`; `src` debe ser al menos igual de grande.
    public static func convertPlanar16FtoPlanarF(_ src: UnsafePointer<ImageBuffer>, _ dst: UnsafePointer<ImageBuffer>) -> Int {
        let s = src.pointee, d = dst.pointee
        guard s.height >= d.height, s.width >= d.width, let sp = s.data, let dp = d.data else { return imageBufferSizeMismatch }
        for row in 0..<Int(d.height) {
            let from = (sp + row * s.rowBytes).assumingMemoryBound(to: UInt16.self)
            let to = (dp + row * d.rowBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<Int(d.width) { to[x] = halfToFloat(from[x]) }
        }
        return imageNoError
    }

    @inline(__always)
    static func halfToFloat(_ h: UInt16) -> Float {
        let sign = UInt32(h >> 15) << 31
        let exp = UInt32((h >> 10) & 0x1F)
        let mant = UInt32(h & 0x3FF)
        if exp == 0 {
            let v = Float(mant) * 0x1p-24   // cero o subnormal: mant · 2^-24, exacto en Float
            return sign != 0 ? -v : v
        }
        if exp == 31 { return Float(bitPattern: sign | 0x7F80_0000 | (mant << 13)) }
        return Float(bitPattern: sign | ((exp + 112) << 23) | (mant << 13))
    }
}
