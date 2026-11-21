import CPocketFFT

/// `vDSP_DFT_zrop` sobre pocketfft (`rfft`, double). pocketfft deja el espectro en formato FFTPACK
/// `[r0, r1, i1, r2, i2, …, r(n/2)]`; aquí se reempaqueta con la convención de vDSP (ver `RealDFTSetup`).
/// El plan es de solo lectura y la memoria de trabajo es de cada llamada: se puede ejecutar desde varios hilos.
public final class PortableRealDFT: RealDFTSetup, @unchecked Sendable {
    let n: Int
    let direction: DFTDirection
    private let plan: rfft_plan

    public init?(count: Int, direction: DFTDirection) {
        guard count >= 2, count % 2 == 0, let p = make_rfft_plan(count) else { return nil }
        n = count
        self.direction = direction
        plan = p
    }

    deinit { destroy_rfft_plan(plan) }

    public func execute(_ ir: UnsafePointer<Float>, _ ii: UnsafePointer<Float>,
                        _ or: UnsafeMutablePointer<Float>, _ oi: UnsafeMutablePointer<Float>) {
        let n = n, half = n / 2, plan = plan, forward = direction == .forward
        withUnsafeTemporaryAllocation(of: Double.self, capacity: n) { tmp in
            let buf = tmp.baseAddress!
            if forward {
                for j in 0..<half {
                    buf[2 * j] = Double(ir[j])
                    buf[2 * j + 1] = Double(ii[j])
                }
                _ = rfft_forward(plan, buf, 1)
                // Antes de escribir: `or`/`oi` pueden ser las mismas zonas que `ir`/`ii`.
                or[0] = Float(2 * buf[0])
                oi[0] = Float(2 * buf[n - 1])
                for k in 1..<max(half, 1) {
                    or[k] = Float(2 * buf[2 * k - 1])
                    oi[k] = Float(2 * buf[2 * k])
                }
            } else {
                buf[0] = Double(ir[0])
                buf[n - 1] = Double(ii[0])
                for k in 1..<max(half, 1) {
                    buf[2 * k - 1] = Double(ir[k])
                    buf[2 * k] = Double(ii[k])
                }
                _ = rfft_backward(plan, buf, 1)
                for j in 0..<half {
                    or[j] = Float(buf[2 * j])
                    oi[j] = Float(buf[2 * j + 1])
                }
            }
        }
    }
}

/// Escalares de `PortableComplexDFT`: Float (`vDSP_DFT_zop`) y Double (`vDSP_DFT_zopD`).
public protocol PortableDFTScalar: BinaryFloatingPoint {
    init(_ value: Double)
    var asDouble: Double { get }
}
extension Float: PortableDFTScalar { public var asDouble: Double { Double(self) } }
extension Double: PortableDFTScalar { public var asDouble: Double { self } }

/// `vDSP_DFT_zop[D]` sobre pocketfft (`cfft`, double): adelante e^{-i}, inversa e^{+i}, sin normalizar.
public final class PortableComplexDFT<Scalar: PortableDFTScalar>: ComplexDFTSetup, @unchecked Sendable {
    let n: Int
    let direction: DFTDirection
    private let plan: cfft_plan

    public init?(count: Int, direction: DFTDirection) {
        guard count >= 1, let p = make_cfft_plan(count) else { return nil }
        n = count
        self.direction = direction
        plan = p
    }

    deinit { destroy_cfft_plan(plan) }

    public func execute(_ ir: UnsafePointer<Scalar>, _ ii: UnsafePointer<Scalar>,
                        _ or: UnsafeMutablePointer<Scalar>, _ oi: UnsafeMutablePointer<Scalar>) {
        let n = n, plan = plan, forward = direction == .forward
        withUnsafeTemporaryAllocation(of: Double.self, capacity: 2 * n) { tmp in
            let buf = tmp.baseAddress!
            for k in 0..<n {
                buf[2 * k] = ir[k].asDouble
                buf[2 * k + 1] = ii[k].asDouble
            }
            _ = forward ? cfft_forward(plan, buf, 1) : cfft_backward(plan, buf, 1)
            for k in 0..<n {
                or[k] = Scalar(buf[2 * k])
                oi[k] = Scalar(buf[2 * k + 1])
            }
        }
    }
}

/// `vDSP_biquad`: cascada en forma directa I, calculada en Double; el estado vuelve a `delay` (Float) al acabar,
/// con la disposición de vDSP: `[x[n-2], x[n-1], y1[n-2], y1[n-1], y2[n-2], …]`.
public final class PortableBiquad: BiquadSetup, @unchecked Sendable {
    let sections: Int
    private let coeffs: [Double]

    public init?(coefficients: [Double], sections: Int) {
        guard sections >= 1, coefficients.count >= 5 * sections else { return nil }
        self.sections = sections
        coeffs = Array(coefficients.prefix(5 * sections))
    }

    public func execute(_ delay: UnsafeMutablePointer<Float>, _ x: UnsafePointer<Float>, _ ix: DSPStride,
                        _ y: UnsafeMutablePointer<Float>, _ iy: DSPStride, _ n: DSPLength) {
        let m = sections
        withUnsafeTemporaryAllocation(of: Double.self, capacity: 2 * m + 2) { st in
            let s = st.baseAddress!
            for i in 0..<(2 * m + 2) { s[i] = Double(delay[i]) }
            coeffs.withUnsafeBufferPointer { cp in
                let c = cp.baseAddress!
                for t in 0..<Int(n) {
                    var v = Double(x[t * ix])
                    for k in 0..<m {
                        let b0 = c[5 * k], b1 = c[5 * k + 1], b2 = c[5 * k + 2], a1 = c[5 * k + 3], a2 = c[5 * k + 4]
                        let xi = s + 2 * k, yo = s + 2 * k + 2   // entradas y salidas de la sección k
                        let out = b0 * v + b1 * xi[1] + b2 * xi[0] - a1 * yo[1] - a2 * yo[0]
                        xi[0] = xi[1]
                        xi[1] = v
                        v = out
                    }
                    let last = s + 2 * m
                    last[0] = last[1]
                    last[1] = v
                    y[t * iy] = Float(v)
                }
            }
            for i in 0..<(2 * m + 2) { delay[i] = Float(s[i]) }
        }
    }
}
