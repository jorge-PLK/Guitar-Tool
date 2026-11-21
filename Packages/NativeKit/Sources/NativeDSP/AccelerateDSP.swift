#if canImport(Accelerate)
import Accelerate

/// Motor de la fachada DSP en el Mac: cada función llama tal cual a su equivalente de Accelerate (mismo
/// comportamiento que antes del port; plan, «Fase 7c», paso 6, «Regla del Mac»).
public typealias DSP = DSPAccelerate

public enum DSPAccelerate: DSPEngine {
    public typealias RealDFT = AccelerateRealDFT
    public typealias ComplexDFT = AccelerateComplexDFT
    public typealias ComplexDFTD = AccelerateComplexDFTD
    public typealias Biquad = AccelerateBiquad

    @inline(__always) static func split(_ z: UnsafePointer<SplitComplex>) -> DSPSplitComplex {
        DSPSplitComplex(realp: z.pointee.realp, imagp: z.pointee.imagp)
    }

    // MARK: Elemento a elemento

    @inlinable public static func vadd(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                                       _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        vDSP_vadd(a, ia, b, ib, c, ic, n)
    }
    @inlinable public static func vaddD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ b: UnsafePointer<Double>, _ ib: DSPStride,
                                        _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride, _ n: DSPLength) {
        vDSP_vaddD(a, ia, b, ib, c, ic, n)
    }
    @inlinable public static func vsub(_ b: UnsafePointer<Float>, _ ib: DSPStride, _ a: UnsafePointer<Float>, _ ia: DSPStride,
                                       _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        vDSP_vsub(b, ib, a, ia, c, ic, n)
    }
    @inlinable public static func vmul(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                                       _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        vDSP_vmul(a, ia, b, ib, c, ic, n)
    }
    @inlinable public static func vdiv(_ b: UnsafePointer<Float>, _ ib: DSPStride, _ a: UnsafePointer<Float>, _ ia: DSPStride,
                                       _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        vDSP_vdiv(b, ib, a, ia, c, ic, n)
    }
    @inlinable public static func vma(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                                      _ c: UnsafePointer<Float>, _ ic: DSPStride, _ d: UnsafeMutablePointer<Float>, _ id: DSPStride,
                                      _ n: DSPLength) {
        vDSP_vma(a, ia, b, ib, c, ic, d, id, n)
    }
    @inlinable public static func vsma(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>,
                                       _ c: UnsafePointer<Float>, _ ic: DSPStride, _ d: UnsafeMutablePointer<Float>, _ id: DSPStride,
                                       _ n: DSPLength) {
        vDSP_vsma(a, ia, b, c, ic, d, id, n)
    }
    @inlinable public static func vsmsa(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ c: UnsafePointer<Float>,
                                        _ d: UnsafeMutablePointer<Float>, _ id: DSPStride, _ n: DSPLength) {
        vDSP_vsmsa(a, ia, b, c, d, id, n)
    }
    @inlinable public static func vsmul(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>,
                                        _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        vDSP_vsmul(a, ia, b, c, ic, n)
    }
    @inlinable public static func vsmulD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ b: UnsafePointer<Double>,
                                         _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride, _ n: DSPLength) {
        vDSP_vsmulD(a, ia, b, c, ic, n)
    }
    @inlinable public static func vsadd(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>,
                                        _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        vDSP_vsadd(a, ia, b, c, ic, n)
    }
    @inlinable public static func vfill(_ a: UnsafePointer<Float>, _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        vDSP_vfill(a, c, ic, n)
    }
    @inlinable public static func vclr(_ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        vDSP_vclr(c, ic, n)
    }
    @inlinable public static func vrvrs(_ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        vDSP_vrvrs(c, ic, n)
    }
    @inlinable public static func vabs(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride,
                                       _ n: DSPLength) {
        vDSP_vabs(a, ia, c, ic, n)
    }
    @inlinable public static func vabsD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride,
                                        _ n: DSPLength) {
        vDSP_vabsD(a, ia, c, ic, n)
    }
    @inlinable public static func vmax(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                                       _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        vDSP_vmax(a, ia, b, ib, c, ic, n)
    }
    @inlinable public static func vmaxD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ b: UnsafePointer<Double>, _ ib: DSPStride,
                                        _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride, _ n: DSPLength) {
        vDSP_vmaxD(a, ia, b, ib, c, ic, n)
    }
    @inlinable public static func vthres(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>,
                                         _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength) {
        vDSP_vthres(a, ia, b, c, ic, n)
    }
    @inlinable public static func vspdp(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride,
                                        _ n: DSPLength) {
        vDSP_vspdp(a, ia, c, ic, n)
    }

    // MARK: Reducciones

    @inlinable public static func sve(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength) {
        vDSP_sve(a, ia, c, n)
    }
    @inlinable public static func svesq(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength) {
        vDSP_svesq(a, ia, c, n)
    }
    @inlinable public static func meanv(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength) {
        vDSP_meanv(a, ia, c, n)
    }
    @inlinable public static func measqv(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength) {
        vDSP_measqv(a, ia, c, n)
    }
    @inlinable public static func rmsqv(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength) {
        vDSP_rmsqv(a, ia, c, n)
    }
    @inlinable public static func maxmgv(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength) {
        vDSP_maxmgv(a, ia, c, n)
    }
    @inlinable public static func maxvD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Double>, _ n: DSPLength) {
        vDSP_maxvD(a, ia, c, n)
    }
    @inlinable public static func dotpr(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                                        _ c: UnsafeMutablePointer<Float>, _ n: DSPLength) {
        vDSP_dotpr(a, ia, b, ib, c, n)
    }
    @inlinable public static func dotprD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ b: UnsafePointer<Double>, _ ib: DSPStride,
                                         _ c: UnsafeMutablePointer<Double>, _ n: DSPLength) {
        vDSP_dotprD(a, ia, b, ib, c, n)
    }
    @inlinable public static func maximum(_ x: [Float]) -> Float { vDSP.maximum(x) }
    @inlinable public static func maximum(_ x: [Double]) -> Double { vDSP.maximum(x) }

    // MARK: Filtros y matrices

    @inlinable public static func conv(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ f: UnsafePointer<Float>, _ iff: DSPStride,
                                       _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength, _ p: DSPLength) {
        vDSP_conv(a, ia, f, iff, c, ic, n, p)
    }
    @inlinable public static func convD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ f: UnsafePointer<Double>, _ iff: DSPStride,
                                        _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride, _ n: DSPLength, _ p: DSPLength) {
        vDSP_convD(a, ia, f, iff, c, ic, n, p)
    }
    @inlinable public static func desamp(_ a: UnsafePointer<Float>, _ df: DSPStride, _ f: UnsafePointer<Float>,
                                         _ c: UnsafeMutablePointer<Float>, _ n: DSPLength, _ p: DSPLength) {
        vDSP_desamp(a, df, f, c, n, p)
    }
    @inlinable public static func mmul(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                                       _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ m: DSPLength, _ n: DSPLength, _ p: DSPLength) {
        vDSP_mmul(a, ia, b, ib, c, ic, m, n, p)
    }

    // MARK: Complejos

    public static func zvabs(_ a: UnsafePointer<SplitComplex>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>,
                             _ ic: DSPStride, _ n: DSPLength) {
        var za = split(a)
        vDSP_zvabs(&za, ia, c, ic, n)
    }
    public static func zvmul(_ a: UnsafePointer<SplitComplex>, _ ia: DSPStride, _ b: UnsafePointer<SplitComplex>,
                             _ ib: DSPStride, _ c: UnsafePointer<SplitComplex>, _ ic: DSPStride, _ n: DSPLength,
                             _ conjugate: Int32) {
        var za = split(a), zb = split(b), zc = split(c)
        vDSP_zvmul(&za, ia, &zb, ib, &zc, ic, n, conjugate)
    }
    public static func zvmov(_ a: UnsafePointer<SplitComplex>, _ ia: DSPStride, _ c: UnsafePointer<SplitComplex>,
                             _ ic: DSPStride, _ n: DSPLength) {
        var za = split(a), zc = split(c)
        vDSP_zvmov(&za, ia, &zc, ic, n)
    }
    public static func ctoz(_ c: UnsafePointer<InterleavedComplex>, _ ic: DSPStride, _ z: UnsafePointer<SplitComplex>,
                            _ iz: DSPStride, _ n: DSPLength) {
        var zz = split(z)
        UnsafeRawPointer(c).withMemoryRebound(to: DSPComplex.self, capacity: 1) { vDSP_ctoz($0, ic, &zz, iz, n) }
    }
    public static func ztoc(_ z: UnsafePointer<SplitComplex>, _ iz: DSPStride, _ c: UnsafeMutablePointer<InterleavedComplex>,
                            _ ic: DSPStride, _ n: DSPLength) {
        var zz = split(z)
        UnsafeMutableRawPointer(c).withMemoryRebound(to: DSPComplex.self, capacity: 1) { vDSP_ztoc(&zz, iz, $0, ic, n) }
    }

    // MARK: vForce

    @inlinable public static func vvlogf(_ y: UnsafeMutablePointer<Float>, _ x: UnsafePointer<Float>, _ n: UnsafePointer<Int32>) {
        Accelerate.vvlogf(y, x, n)
    }
    @inlinable public static func vvlog1pf(_ y: UnsafeMutablePointer<Float>, _ x: UnsafePointer<Float>, _ n: UnsafePointer<Int32>) {
        Accelerate.vvlog1pf(y, x, n)
    }
    @inlinable public static func vvlog10f(_ y: UnsafeMutablePointer<Float>, _ x: UnsafePointer<Float>, _ n: UnsafePointer<Int32>) {
        Accelerate.vvlog10f(y, x, n)
    }

    // MARK: Conversiones

    @inlinable public static func convertElements(of source: [Float], to destination: inout [Double]) {
        vDSP.convertElements(of: source, to: &destination)
    }
    @inlinable public static func convertElements(of source: [Double], to destination: inout [Float]) {
        vDSP.convertElements(of: source, to: &destination)
    }
    public static func convertPlanar16FtoPlanarF(_ src: UnsafePointer<ImageBuffer>, _ dst: UnsafePointer<ImageBuffer>) -> Int {
        let s = src.pointee, d = dst.pointee
        var vs = vImage_Buffer(data: s.data, height: s.height, width: s.width, rowBytes: s.rowBytes)
        var vd = vImage_Buffer(data: d.data, height: d.height, width: d.width, rowBytes: d.rowBytes)
        return vImageConvert_Planar16FtoPlanarF(&vs, &vd, vImage_Flags(kvImageNoFlags))
    }
}

/// `vDSP_DFT_zrop_CreateSetup` + `vDSP_DFT_Execute`; se destruye en `deinit`.
public final class AccelerateRealDFT: RealDFTSetup, @unchecked Sendable {
    let setup: vDSP_DFT_Setup
    public init?(count: Int, direction: DFTDirection) {
        guard let s = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(count), direction == .forward ? .FORWARD : .INVERSE) else {
            return nil
        }
        setup = s
    }
    deinit { vDSP_DFT_DestroySetup(setup) }
    public func execute(_ ir: UnsafePointer<Float>, _ ii: UnsafePointer<Float>,
                        _ or: UnsafeMutablePointer<Float>, _ oi: UnsafeMutablePointer<Float>) {
        vDSP_DFT_Execute(setup, ir, ii, or, oi)
    }
}

/// `vDSP_DFT_zop_CreateSetup` + `vDSP_DFT_Execute`.
public final class AccelerateComplexDFT: ComplexDFTSetup, @unchecked Sendable {
    let setup: vDSP_DFT_Setup
    public init?(count: Int, direction: DFTDirection) {
        guard let s = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(count), direction == .forward ? .FORWARD : .INVERSE) else {
            return nil
        }
        setup = s
    }
    deinit { vDSP_DFT_DestroySetup(setup) }
    public func execute(_ ir: UnsafePointer<Float>, _ ii: UnsafePointer<Float>,
                        _ or: UnsafeMutablePointer<Float>, _ oi: UnsafeMutablePointer<Float>) {
        vDSP_DFT_Execute(setup, ir, ii, or, oi)
    }
}

/// `vDSP_DFT_zop_CreateSetupD` + `vDSP_DFT_ExecuteD`.
public final class AccelerateComplexDFTD: ComplexDFTSetup, @unchecked Sendable {
    let setup: vDSP_DFT_SetupD
    public init?(count: Int, direction: DFTDirection) {
        guard let s = vDSP_DFT_zop_CreateSetupD(nil, vDSP_Length(count), direction == .forward ? .FORWARD : .INVERSE) else {
            return nil
        }
        setup = s
    }
    deinit { vDSP_DFT_DestroySetupD(setup) }
    public func execute(_ ir: UnsafePointer<Double>, _ ii: UnsafePointer<Double>,
                        _ or: UnsafeMutablePointer<Double>, _ oi: UnsafeMutablePointer<Double>) {
        vDSP_DFT_ExecuteD(setup, ir, ii, or, oi)
    }
}

/// `vDSP_biquad_CreateSetup` + `vDSP_biquad`.
public final class AccelerateBiquad: BiquadSetup, @unchecked Sendable {
    let setup: vDSP_biquad_Setup
    public init?(coefficients: [Double], sections: Int) {
        guard let s = vDSP_biquad_CreateSetup(coefficients, vDSP_Length(sections)) else { return nil }
        setup = s
    }
    deinit { vDSP_biquad_DestroySetup(setup) }
    public func execute(_ delay: UnsafeMutablePointer<Float>, _ x: UnsafePointer<Float>, _ ix: DSPStride,
                        _ y: UnsafeMutablePointer<Float>, _ iy: DSPStride, _ n: DSPLength) {
        vDSP_biquad(setup, delay, x, ix, y, iy, n)
    }
}

#else

/// Motor de la fachada DSP fuera del Mac: el portátil.
public typealias DSP = DSPPortable

#endif
