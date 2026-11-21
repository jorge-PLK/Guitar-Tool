import Foundation
@testable import NativeDSP
import XCTest

/// `DSPPortable.conv`: la ruta FFT por bloques frente al bucle directo (y frente a vDSP en el Mac).
final class PortableConvTests: XCTestCase {
    /// Las dos rutas redondean a Float valores double que difieren ~1e-14: como mucho 1 ulp de Float del
    /// mayor valor de salida. Se mide frente a `max |c|` para no penalizar salidas cerca de cero.
    static let maxRelativeToPeak = 2.4e-7

    struct Case { let n: Int, p: Int, ia: Int, iff: Int, ic: Int }

    /// Señal aleatoria uniforme en [−1, 1) con semilla fija (LCG de Knuth).
    static func noise(_ count: Int, seed: UInt64) -> [Float] {
        var s = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return (0..<count).map { _ in
            s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(Int64(bitPattern: s >> 11) - (1 << 52)) / Float(1 << 52)
        }
    }

    /// Ejecuta `conv` (o `convDirect`) con los pasos del caso; `iff` < 0 recorre el filtro desde el final.
    static func run(_ k: Case, direct: Bool, seed: UInt64 = 1,
                    engine: (UnsafePointer<Float>, DSPStride, UnsafePointer<Float>, DSPStride,
                             UnsafeMutablePointer<Float>, DSPStride, DSPLength, DSPLength) -> Void = DSPPortable.conv) -> [Float] {
        let a = noise((k.n + k.p - 1) * k.ia, seed: seed)
        let f = noise(k.p * abs(k.iff), seed: seed + 7)
        var c = [Float](repeating: .nan, count: (k.n - 1) * k.ic + 1)
        a.withUnsafeBufferPointer { ap in
            f.withUnsafeBufferPointer { fp in
                c.withUnsafeMutableBufferPointer { cp in
                    let fStart = k.iff < 0 ? fp.baseAddress! + (k.p - 1) * abs(k.iff) : fp.baseAddress!
                    if direct {
                        DSPPortable.convDirect(ap.baseAddress!, k.ia, fStart, k.iff, cp.baseAddress!, k.ic, k.n, k.p)
                    } else {
                        engine(ap.baseAddress!, k.ia, fStart, k.iff, cp.baseAddress!, k.ic, DSPLength(k.n), DSPLength(k.p))
                    }
                }
            }
        }
        return stride(from: 0, to: c.count, by: k.ic).map { c[$0] }
    }

    static func relativeToPeak(_ got: [Float], _ ref: [Float]) -> Double {
        var peak = 0.0, worst = 0.0
        for i in ref.indices {
            peak = max(peak, abs(Double(ref[i])))
            let d = abs(Double(got[i]) - Double(ref[i]))
            worst = got[i].isNaN ? .infinity : max(worst, d)
        }
        return peak > 0 ? worst / peak : worst
    }

    func testFFTMatchesDirectLoop() {
        let t = DSPPortable.fftConvMinSide   // 64
        let chunk200 = DSPPortable.fftConvSize(200) - 200 + 1   // trozo de filtro con n = 200
        let block129 = DSPPortable.fftConvSize(129) - 129 + 1   // bloque de salidas con p = 129
        let cases: [Case] = [
            // Bordes del umbral (por debajo: directo por las dos vías; desde el umbral: FFT).
            Case(n: t - 1, p: 1_000, ia: 1, iff: 1, ic: 1), Case(n: t, p: 1_000, ia: 1, iff: 1, ic: 1),
            Case(n: 1_000, p: t - 1, ia: 1, iff: 1, ic: 1), Case(n: 1_000, p: t, ia: 1, iff: 1, ic: 1),
            Case(n: t, p: t, ia: 1, iff: 1, ic: 1), Case(n: t + 1, p: t, ia: 1, iff: 1, ic: 1),
            Case(n: 300, p: 300, ia: 1, iff: 1, ic: 1), Case(n: 301, p: 300, ia: 1, iff: 1, ic: 1),
            // Trozos exactos y con resto en las dos ramas.
            Case(n: 200, p: 2 * chunk200, ia: 1, iff: 1, ic: 1), Case(n: 200, p: 2 * chunk200 + 1, ia: 1, iff: 1, ic: 1),
            Case(n: 3 * block129, p: 129, ia: 1, iff: 1, ic: 1), Case(n: 3 * block129 + 1, p: 129, ia: 1, iff: 1, ic: 1),
            // Longitudes no potencia de 2 con las formas de producción (rigDelay y envolventes, reducidas).
            Case(n: 951, p: 30_011, ia: 1, iff: 1, ic: 1), Case(n: 37_123, p: 129, ia: 1, iff: 1, ic: 1),
            // Pasos: entrada salteada, convolución (filtro al revés) y salida salteada.
            Case(n: 777, p: 5_003, ia: 2, iff: -1, ic: 3), Case(n: 5_003, p: 97, ia: 3, iff: -2, ic: 2),
        ]
        var lines: [String] = []
        for (i, k) in cases.enumerated() {
            let ref = Self.run(k, direct: true, seed: UInt64(i + 1))
            let got = Self.run(k, direct: false, seed: UInt64(i + 1))
            let rel = Self.relativeToPeak(got, ref)
            let path = min(k.n, k.p) >= t ? "fft" : "dir"
            lines.append(String(format: "n %6d p %6d ia %d iff %2d ic %d %@  %.2e", k.n, k.p, k.ia, k.iff, k.ic, path as NSString, rel))
            XCTAssertLessThanOrEqual(rel, Self.maxRelativeToPeak, "n \(k.n) p \(k.p): error \(rel) frente al pico")
        }
        print("conv portable FFT vs directo (error max / pico):\n" + lines.joined(separator: "\n"))
    }

    /// Por debajo del umbral el resultado es bit a bit el del bucle con `sum` de antes (mismo orden de suma).
    func testDirectPathKeepsSummationOrder() {
        let k = Case(n: 37, p: 50, ia: 1, iff: 1, ic: 1)
        let a = Self.noise(k.n + k.p - 1, seed: 3), f = Self.noise(k.p, seed: 3 + 7)
        let got = Self.run(k, direct: false, seed: 3)
        for i in 0..<k.n {
            let old = Float(DSPPortable.sum(k.p) { Double(a[i + $0]) * Double(f[$0]) })
            XCTAssertEqual(got[i].bitPattern, old.bitPattern, "salida \(i)")
        }
    }

    /// Comprueba que el despacho toma la ruta FFT desde el umbral (y documenta su única diferencia de
    /// comportamiento): un NaN en la entrada se extiende a todo el bloque, no solo a las salidas que lo tocan.
    func testDispatchUsesFFTFromThreshold() {
        for (n, p, fft) in [(DSPPortable.fftConvMinSide - 1, 200, false), (DSPPortable.fftConvMinSide, 200, true)] {
            var a = [Float](repeating: 0.5, count: n + p - 1), f = [Float](repeating: 0.25, count: p)
            a[0] = .nan
            var c = [Float](repeating: 0, count: n)
            DSPPortable.conv(a, 1, &f, 1, &c, 1, DSPLength(n), DSPLength(p))
            XCTAssertTrue(c[0].isNaN)
            XCTAssertEqual(c[n - 1].isNaN, fft, "n \(n): la última salida no lee a[0]")
        }
    }

    #if canImport(Accelerate)
    /// En el Mac, con las formas grandes: la ruta FFT queda tan cerca de vDSP como el bucle directo de antes
    /// (la diferencia con vDSP es el error de vDSP, que acumula en Float).
    func testFFTMatchesVDSP() {
        for k in [Case(n: 951, p: 60_000, ia: 1, iff: 1, ic: 1), Case(n: 100_003, p: 129, ia: 1, iff: 1, ic: 1)] {
            let v = Self.run(k, direct: false, engine: DSPAccelerate.conv)
            let fft = Self.relativeToPeak(Self.run(k, direct: false), v)
            let direct = Self.relativeToPeak(Self.run(k, direct: true), v)
            print(String(format: "conv vs vDSP n %d p %d: FFT %.2e, directo %.2e", k.n, k.p, fft, direct))
            XCTAssertLessThanOrEqual(fft, direct + Self.maxRelativeToPeak)
        }
    }
    #endif

    /// Tiempo de la ruta FFT con las formas reales de `rigDelay` (toma de 60 s a 44,1 kHz). Sin aserto de
    /// tiempo (depende de la máquina); se imprime para el informe.
    func testFFTTimingAtRigDelayShapes() {
        let n = 2_646_000
        for k in [Case(n: 951, p: n - 950, ia: 1, iff: 1, ic: 1), Case(n: n, p: 129, ia: 1, iff: 1, ic: 1)] {
            let start = DispatchTime.now().uptimeNanoseconds
            let c = Self.run(k, direct: false)
            let s = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
            XCTAssertFalse(c.contains { !$0.isFinite })
            print(String(format: "conv FFT n %d p %d: %.3f s (con generar la entrada)", k.n, k.p, s))
        }
    }
}
