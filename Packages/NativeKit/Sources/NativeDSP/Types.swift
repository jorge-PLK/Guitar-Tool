// Tipos de la fachada DSP (plan, «Fase 7c», paso 6: NativeDSP). Misma disposición en memoria que los de
// Accelerate, para que sustituir `vDSP_*` por `DSP.*` sea un cambio mecánico (tabla en README.md).

/// Longitud de vector (`vDSP_Length`, entero sin signo de la anchura del puntero).
public typealias DSPLength = UInt
/// Paso entre elementos (`vDSP_Stride`); puede ser negativo.
public typealias DSPStride = Int
/// Recuento de píxeles de `ImageBuffer` (`vImagePixelCount`).
public typealias PixelCount = UInt

/// Vector complejo en dos planos (`DSPSplitComplex`).
public struct SplitComplex {
    public var realp: UnsafeMutablePointer<Float>
    public var imagp: UnsafeMutablePointer<Float>
    public init(realp: UnsafeMutablePointer<Float>, imagp: UnsafeMutablePointer<Float>) {
        self.realp = realp
        self.imagp = imagp
    }
}

/// Complejo entrelazado (`DSPComplex`): dos `Float` seguidos.
public struct InterleavedComplex {
    public var real: Float
    public var imag: Float
    public init(real: Float, imag: Float) {
        self.real = real
        self.imag = imag
    }
}

/// Imagen plana (`vImage_Buffer`): `height` filas de `width` elementos, `rowBytes` bytes entre filas.
public struct ImageBuffer {
    public var data: UnsafeMutableRawPointer?
    public var height: PixelCount
    public var width: PixelCount
    public var rowBytes: Int
    public init(data: UnsafeMutableRawPointer?, height: PixelCount, width: PixelCount, rowBytes: Int) {
        self.data = data
        self.height = height
        self.width = width
        self.rowBytes = rowBytes
    }
}

/// Error de `convertPlanar16FtoPlanarF` (`vImage_Error`): 0 bien.
public let imageNoError = 0
/// Tamaños de búfer incompatibles (`kvImageBufferSizeMismatch`).
public let imageBufferSizeMismatch = -21766

/// Sentido de una DFT (`vDSP_DFT_Direction`).
public enum DFTDirection: Sendable {
    case forward
    case inverse
}

/// DFT real empaquetada (`vDSP_DFT_zrop_*`). Entrada y salida con la convención de vDSP:
/// - adelante: la señal real `x` entra par/impar (`ir[j] = x[2j]`, `ii[j] = x[2j+1]`, lo que deja `vDSP_ctoz`
///   con paso 2) y sale `or[0] = 2·X[0]`, `oi[0] = 2·X[n/2]`, `or[k] + i·oi[k] = 2·X[k]` (k = 1..<n/2);
/// - inversa: la misma disposición al revés, sin normalizar (ida y vuelta = 2n·x).
public protocol RealDFTSetup: AnyObject, Sendable {
    init?(count: Int, direction: DFTDirection)
    func execute(_ ir: UnsafePointer<Float>, _ ii: UnsafePointer<Float>,
                 _ or: UnsafeMutablePointer<Float>, _ oi: UnsafeMutablePointer<Float>)
}

/// DFT compleja (`vDSP_DFT_zop_*`): adelante e^{-i}, inversa e^{+i} sin normalizar.
public protocol ComplexDFTSetup: AnyObject, Sendable {
    associatedtype Scalar
    init?(count: Int, direction: DFTDirection)
    func execute(_ ir: UnsafePointer<Scalar>, _ ii: UnsafePointer<Scalar>,
                 _ or: UnsafeMutablePointer<Scalar>, _ oi: UnsafeMutablePointer<Scalar>)
}

/// Cascada de biquads (`vDSP_biquad_*`). Coeficientes `[b0, b1, b2, a1, a2]` por sección (a0 = 1).
/// `delay` tiene 2·secciones + 2 `Float`, del más antiguo al más reciente: `[x[n-2], x[n-1]]` y después
/// `[y[n-2], y[n-1]]` de cada sección (medido con vDSP).
public protocol BiquadSetup: AnyObject, Sendable {
    init?(coefficients: [Double], sections: Int)
    func execute(_ delay: UnsafeMutablePointer<Float>, _ x: UnsafePointer<Float>, _ ix: DSPStride,
                 _ y: UnsafeMutablePointer<Float>, _ iy: DSPStride, _ n: DSPLength)
}

/// Contrato común de los dos motores (vDSP y portátil): obliga a que tengan las mismas firmas y permite a
/// los tests ejecutar el mismo caso con cada uno.
protocol DSPEngine {
    associatedtype RealDFT: RealDFTSetup
    associatedtype ComplexDFT: ComplexDFTSetup where ComplexDFT.Scalar == Float
    associatedtype ComplexDFTD: ComplexDFTSetup where ComplexDFTD.Scalar == Double
    associatedtype Biquad: BiquadSetup

    // Elemento a elemento.
    static func vadd(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                     _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength)
    static func vaddD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ b: UnsafePointer<Double>, _ ib: DSPStride,
                      _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride, _ n: DSPLength)
    static func vsub(_ b: UnsafePointer<Float>, _ ib: DSPStride, _ a: UnsafePointer<Float>, _ ia: DSPStride,
                     _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength)
    static func vmul(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                     _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength)
    static func vdiv(_ b: UnsafePointer<Float>, _ ib: DSPStride, _ a: UnsafePointer<Float>, _ ia: DSPStride,
                     _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength)
    static func vma(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                    _ c: UnsafePointer<Float>, _ ic: DSPStride, _ d: UnsafeMutablePointer<Float>, _ id: DSPStride,
                    _ n: DSPLength)
    static func vsma(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>,
                     _ c: UnsafePointer<Float>, _ ic: DSPStride, _ d: UnsafeMutablePointer<Float>, _ id: DSPStride,
                     _ n: DSPLength)
    static func vsmsa(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ c: UnsafePointer<Float>,
                      _ d: UnsafeMutablePointer<Float>, _ id: DSPStride, _ n: DSPLength)
    static func vsmul(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>,
                      _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength)
    static func vsmulD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ b: UnsafePointer<Double>,
                       _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride, _ n: DSPLength)
    static func vsadd(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>,
                      _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength)
    static func vfill(_ a: UnsafePointer<Float>, _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength)
    static func vclr(_ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength)
    static func vrvrs(_ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength)
    static func vabs(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride,
                     _ n: DSPLength)
    static func vabsD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride,
                      _ n: DSPLength)
    static func vmax(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                     _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength)
    static func vmaxD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ b: UnsafePointer<Double>, _ ib: DSPStride,
                      _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride, _ n: DSPLength)
    static func vthres(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>,
                       _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength)
    static func vspdp(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride,
                      _ n: DSPLength)

    // Reducciones.
    static func sve(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength)
    static func svesq(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength)
    static func meanv(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength)
    static func measqv(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength)
    static func rmsqv(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength)
    static func maxmgv(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>, _ n: DSPLength)
    static func maxvD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Double>, _ n: DSPLength)
    static func dotpr(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                      _ c: UnsafeMutablePointer<Float>, _ n: DSPLength)
    static func dotprD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ b: UnsafePointer<Double>, _ ib: DSPStride,
                       _ c: UnsafeMutablePointer<Double>, _ n: DSPLength)
    static func maximum(_ x: [Float]) -> Float
    static func maximum(_ x: [Double]) -> Double

    // Filtros y matrices.
    static func conv(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ f: UnsafePointer<Float>, _ iff: DSPStride,
                     _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ n: DSPLength, _ p: DSPLength)
    static func convD(_ a: UnsafePointer<Double>, _ ia: DSPStride, _ f: UnsafePointer<Double>, _ iff: DSPStride,
                      _ c: UnsafeMutablePointer<Double>, _ ic: DSPStride, _ n: DSPLength, _ p: DSPLength)
    static func desamp(_ a: UnsafePointer<Float>, _ df: DSPStride, _ f: UnsafePointer<Float>,
                       _ c: UnsafeMutablePointer<Float>, _ n: DSPLength, _ p: DSPLength)
    static func mmul(_ a: UnsafePointer<Float>, _ ia: DSPStride, _ b: UnsafePointer<Float>, _ ib: DSPStride,
                     _ c: UnsafeMutablePointer<Float>, _ ic: DSPStride, _ m: DSPLength, _ n: DSPLength, _ p: DSPLength)

    // Complejos.
    static func zvabs(_ a: UnsafePointer<SplitComplex>, _ ia: DSPStride, _ c: UnsafeMutablePointer<Float>,
                      _ ic: DSPStride, _ n: DSPLength)
    static func zvmul(_ a: UnsafePointer<SplitComplex>, _ ia: DSPStride, _ b: UnsafePointer<SplitComplex>,
                      _ ib: DSPStride, _ c: UnsafePointer<SplitComplex>, _ ic: DSPStride, _ n: DSPLength,
                      _ conjugate: Int32)
    static func zvmov(_ a: UnsafePointer<SplitComplex>, _ ia: DSPStride, _ c: UnsafePointer<SplitComplex>,
                      _ ic: DSPStride, _ n: DSPLength)
    static func ctoz(_ c: UnsafePointer<InterleavedComplex>, _ ic: DSPStride, _ z: UnsafePointer<SplitComplex>,
                     _ iz: DSPStride, _ n: DSPLength)
    static func ztoc(_ z: UnsafePointer<SplitComplex>, _ iz: DSPStride, _ c: UnsafeMutablePointer<InterleavedComplex>,
                     _ ic: DSPStride, _ n: DSPLength)

    // vForce.
    static func vvlogf(_ y: UnsafeMutablePointer<Float>, _ x: UnsafePointer<Float>, _ n: UnsafePointer<Int32>)
    static func vvlog1pf(_ y: UnsafeMutablePointer<Float>, _ x: UnsafePointer<Float>, _ n: UnsafePointer<Int32>)
    static func vvlog10f(_ y: UnsafeMutablePointer<Float>, _ x: UnsafePointer<Float>, _ n: UnsafePointer<Int32>)

    // Conversiones.
    static func convertElements(of source: [Float], to destination: inout [Double])
    static func convertElements(of source: [Double], to destination: inout [Float])
    static func convertPlanar16FtoPlanarF(_ src: UnsafePointer<ImageBuffer>, _ dst: UnsafePointer<ImageBuffer>) -> Int
}
