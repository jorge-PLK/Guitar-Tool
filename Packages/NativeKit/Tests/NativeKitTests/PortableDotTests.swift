import Foundation
@testable import NativeDSP
import XCTest

/// Reducciones de `DSPPortable` reescritas sin cierre por elemento: deben dar el mismo patrón de bits que la
/// versión anterior (`sum` con cierre, copiada aquí como referencia) para cualquier longitud y paso.
final class PortableDotTests: XCTestCase {
    static let lengths = [0, 1, 2, 3, 4, 5, 63, 64, 65, 951, 4096]
    static let strides = [1, 2, -1, -2]

    // MARK: Referencia (la implementación anterior, con cierre)

    static func refSum(_ n: Int, _ f: (Int) -> Double) -> Double {
        var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0
        var i = 0
        while i + 4 <= n {
            s0 += f(i); s1 += f(i + 1); s2 += f(i + 2); s3 += f(i + 3)
            i += 4
        }
        while i < n { s0 += f(i); i += 1 }
        return (s0 + s1) + (s2 + s3)
    }

    static func refDotpr(_ a: UnsafePointer<Float>, _ ia: Int, _ b: UnsafePointer<Float>, _ ib: Int, _ n: Int) -> Float {
        Float(refSum(n) { Double(a[$0 * ia]) * Double(b[$0 * ib]) })
    }

    static func refDotprD(_ a: UnsafePointer<Double>, _ ia: Int, _ b: UnsafePointer<Double>, _ ib: Int, _ n: Int) -> Double {
        refSum(n) { a[$0 * ia] * b[$0 * ib] }
    }

    // MARK: Datos

    /// Uniforme en [−1, 1) con semilla fija (LCG de Knuth), 52 bits de mantisa.
    static func noiseD(_ count: Int, seed: UInt64) -> [Double] {
        var s = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var out = [Double](repeating: 0, count: count)
        for i in 0..<count {
            s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            out[i] = Double(Int64(bitPattern: s >> 11) - (1 << 52)) / Double(1 << 52)
        }
        return out
    }

    static func noiseF(_ count: Int, seed: UInt64) -> [Float] { noiseD(count, seed: seed).map { Float($0) } }

    /// Elementos que ocupan `n` valores con paso `s` (al menos 1 para tener puntero válido).
    static func span(_ n: Int, _ s: Int) -> Int { max(1, (n - 1) * abs(s) + 1) }

    /// Puntero al primer elemento recorrido: con paso negativo vDSP empieza por el final.
    static func start<T>(_ p: UnsafePointer<T>, _ n: Int, _ s: Int) -> UnsafePointer<T> {
        s < 0 && n > 0 ? p + (n - 1) * abs(s) : p
    }

    // MARK: Bit a bit

    func testDotprBitIdenticalToClosureVersion() {
        var checked = 0
        for n in Self.lengths {
            for ia in Self.strides {
                for ib in Self.strides {
                    let a = Self.noiseF(Self.span(n, ia), seed: UInt64(n * 31 + ia + 5))
                    let b = Self.noiseF(Self.span(n, ib), seed: UInt64(n * 17 + ib + 99))
                    a.withUnsafeBufferPointer { ap in
                        b.withUnsafeBufferPointer { bp in
                            let pa = Self.start(ap.baseAddress!, n, ia), pb = Self.start(bp.baseAddress!, n, ib)
                            var got: Float = .nan
                            DSPPortable.dotpr(pa, ia, pb, ib, &got, DSPLength(n))
                            let ref = Self.refDotpr(pa, ia, pb, ib, n)
                            XCTAssertEqual(got.bitPattern, ref.bitPattern, "dotpr n=\(n) ia=\(ia) ib=\(ib): \(got) vs \(ref)")
                        }
                    }
                    checked += 1
                }
            }
        }
        XCTAssertEqual(checked, Self.lengths.count * Self.strides.count * Self.strides.count)
    }

    func testDotprDBitIdenticalToClosureVersion() {
        for n in Self.lengths {
            for ia in Self.strides {
                for ib in Self.strides {
                    let a = Self.noiseD(Self.span(n, ia), seed: UInt64(n * 13 + ia + 7))
                    let b = Self.noiseD(Self.span(n, ib), seed: UInt64(n * 29 + ib + 3))
                    a.withUnsafeBufferPointer { ap in
                        b.withUnsafeBufferPointer { bp in
                            let pa = Self.start(ap.baseAddress!, n, ia), pb = Self.start(bp.baseAddress!, n, ib)
                            var got: Double = .nan
                            DSPPortable.dotprD(pa, ia, pb, ib, &got, DSPLength(n))
                            let ref = Self.refDotprD(pa, ia, pb, ib, n)
                            XCTAssertEqual(got.bitPattern, ref.bitPattern, "dotprD n=\(n) ia=\(ia) ib=\(ib): \(got) vs \(ref)")
                        }
                    }
                }
            }
        }
    }

    /// sve, svesq, meanv, measqv y rmsqv, que también dejaron el cierre.
    func testSumReductionsBitIdenticalToClosureVersion() {
        for n in Self.lengths where n > 0 {
            for ia in Self.strides {
                let a = Self.noiseF(Self.span(n, ia), seed: UInt64(n * 7 + ia + 11))
                a.withUnsafeBufferPointer { ap in
                    let pa = Self.start(ap.baseAddress!, n, ia)
                    let s = Self.refSum(n) { Double(pa[$0 * ia]) }
                    let sq = Self.refSum(n) { let x = Double(pa[$0 * ia]); return x * x }
                    let refs: [(String, Float, (UnsafeMutablePointer<Float>) -> Void)] = [
                        ("sve", Float(s), { DSPPortable.sve(pa, ia, $0, DSPLength(n)) }),
                        ("svesq", Float(sq), { DSPPortable.svesq(pa, ia, $0, DSPLength(n)) }),
                        ("meanv", Float(s / Double(n)), { DSPPortable.meanv(pa, ia, $0, DSPLength(n)) }),
                        ("measqv", Float(sq / Double(n)), { DSPPortable.measqv(pa, ia, $0, DSPLength(n)) }),
                        ("rmsqv", Float((sq / Double(n)).squareRoot()), { DSPPortable.rmsqv(pa, ia, $0, DSPLength(n)) }),
                    ]
                    for (name, ref, run) in refs {
                        var got: Float = .nan
                        run(&got)
                        XCTAssertEqual(got.bitPattern, ref.bitPattern, "\(name) n=\(n) ia=\(ia): \(got) vs \(ref)")
                    }
                }
            }
        }
    }

    /// convD y desamp, que hacen un producto escalar por salida.
    func testConvDAndDesampBitIdenticalToClosureVersion() {
        for p in [1, 3, 4, 5, 64, 65] {
            for ia in [1, 2] {
                for iff in [1, 2, -1] {
                    let n = 37
                    let a = Self.noiseD((n + p - 1) * ia, seed: UInt64(p * 3 + ia))
                    let f = Self.noiseD(Self.span(p, iff), seed: UInt64(p * 5 + iff + 50))
                    var got = [Double](repeating: .nan, count: n)
                    a.withUnsafeBufferPointer { ap in
                        f.withUnsafeBufferPointer { fp in
                            let pa = ap.baseAddress!, pf = Self.start(fp.baseAddress!, p, iff)
                            got.withUnsafeMutableBufferPointer { DSPPortable.convD(pa, ia, pf, iff, $0.baseAddress!, 1, DSPLength(n), DSPLength(p)) }
                            for k in 0..<n {
                                let base = pa + k * ia
                                let ref = Self.refSum(p) { base[$0 * ia] * pf[$0 * iff] }
                                XCTAssertEqual(got[k].bitPattern, ref.bitPattern, "convD p=\(p) ia=\(ia) iff=\(iff) k=\(k)")
                            }
                        }
                    }
                }
            }
            for df in [1, 2, 3] {
                let n = 41
                let a = Self.noiseF((n - 1) * df + p, seed: UInt64(p * 11 + df))
                let f = Self.noiseF(p, seed: UInt64(p * 19 + df + 1))
                var got = [Float](repeating: .nan, count: n)
                a.withUnsafeBufferPointer { ap in
                    f.withUnsafeBufferPointer { fp in
                        let pa = ap.baseAddress!, pf = fp.baseAddress!
                        got.withUnsafeMutableBufferPointer { DSPPortable.desamp(pa, df, pf, $0.baseAddress!, DSPLength(n), DSPLength(p)) }
                        for k in 0..<n {
                            let base = pa + k * df
                            let ref = Float(Self.refSum(p) { Double(base[$0]) * Double(pf[$0]) })
                            XCTAssertEqual(got[k].bitPattern, ref.bitPattern, "desamp p=\(p) df=\(df) k=\(k)")
                        }
                    }
                }
            }
        }
    }

    // MARK: Tiempo

    /// 1 M de `dotpr` de n = 64 (lo que hace `SimulatedAudioIO.synthesize` por muestra y por tap), con la
    /// referencia con cierre y con la versión nueva. Solo imprime; el resultado debe coincidir.
    func testDotprTimingPrint() {
        let n = 64, calls = 1_000_000
        let a = Self.noiseF(n, seed: 1), b = Self.noiseF(n, seed: 2)
        var accRef = 0.0, accNew = 0.0
        var tRef = 0.0, tNew = 0.0
        a.withUnsafeBufferPointer { ap in
            b.withUnsafeBufferPointer { bp in
                let pa = ap.baseAddress!, pb = bp.baseAddress!
                var t0 = Date()
                var i = 0
                while i < calls { accRef += Double(Self.refDotpr(pa, 1, pb, 1, n)); i += 1 }
                tRef = Date().timeIntervalSince(t0)
                var r: Float = 0
                t0 = Date()
                i = 0
                while i < calls { DSPPortable.dotpr(pa, 1, pb, 1, &r, DSPLength(n)); accNew += Double(r); i += 1 }
                tNew = Date().timeIntervalSince(t0)
            }
        }
        XCTAssertEqual(accRef.bitPattern, accNew.bitPattern)
        print(String(format: "PortableDot timing: 1M dotpr n=64  closure %.3f s  direct %.3f s  speedup x%.1f",
                     tRef, tNew, tRef / max(tNew, 1e-9)))
    }
}
