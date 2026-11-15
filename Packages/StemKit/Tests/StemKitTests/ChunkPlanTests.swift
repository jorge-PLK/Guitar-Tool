import XCTest
@testable import StemKit

final class ChunkPlanTests: XCTestCase {
    let C = 588_800, S = 294_400, F = 58_880

    func testShorterThanOneChunk() {
        let p = ChunkPlan(inputLength: 100_000)
        XCTAssertEqual([p.step, p.fade, p.border], [S, F, S])
        XCTAssertFalse(p.padded)                       // 100 000 ≤ 2·borde → sin relleno de canción
        XCTAssertEqual(p.paddedLength, 100_000)
        XCTAssertEqual(p.starts, [0])
        XCTAssertEqual(p.validCount(0), 100_000)
        XCTAssertEqual(p.tailPad(0), .zeros)           // 100 000 ≤ trozo/2 → ceros
        XCTAssertTrue(p.isLast(0))
        XCTAssertEqual(Set(p.weights(0)), [1])         // primero y último: sin fundidos
    }

    func testExactlyOneChunk() {
        let p = ChunkPlan(inputLength: C)
        XCTAssertFalse(p.padded)                       // C no es > 2·borde (= C)
        XCTAssertEqual(p.starts, [0, S])
        XCTAssertEqual([p.validCount(0), p.validCount(1)], [C, S])
        XCTAssertEqual([p.tailPad(0), p.tailPad(1)], [.none, .zeros])   // S = trozo/2 no es > trozo/2
        XCTAssertEqual([p.isLast(0), p.isLast(1)], [false, true])
        let w0 = p.weights(0), w1 = p.weights(1)
        XCTAssertEqual(w0[0], 1); XCTAssertEqual(w0[F - 1], 1)         // entrada del primero a 1
        XCTAssertEqual(w0[C - F], 1); XCTAssertEqual(w0[C - 1], 0)     // salida: linspace(1, 0)
        XCTAssertEqual(w0[C - F + 1], Float(1 - 1.0 / Double(F - 1)))
        XCTAssertEqual(w1[0], 0); XCTAssertEqual(w1[F - 1], 1)         // entrada: linspace(0, 1)
        XCTAssertEqual(w1[1], Float(1.0 / Double(F - 1)))
        XCTAssertEqual(w1[C - 1], 1)                                   // salida del último a 1
    }

    func testLongNonMultiple() {
        let L0 = 5_000_001
        let p = ChunkPlan(inputLength: L0)
        XCTAssertTrue(p.padded)
        XCTAssertEqual(p.paddedLength, L0 + 2 * S)
        let expectedCount = (p.paddedLength + S - 1) / S                // ceil(5 588 801 / 294 400) = 19
        XCTAssertEqual(p.count, 19)
        XCTAssertEqual(p.count, expectedCount)
        XCTAssertEqual(p.starts, (0..<19).map { $0 * S })
        XCTAssertEqual(p.validCount(16), C)
        XCTAssertEqual(p.validCount(17), 584_001)
        XCTAssertEqual(p.tailPad(17), .reflect)        // 584 001 > trozo/2
        XCTAssertEqual(p.validCount(18), 289_601)
        XCTAssertEqual(p.tailPad(18), .zeros)
        XCTAssertEqual(p.starts.indices.filter { p.isLast($0) }, [18])
    }

    func testTailReflectMatchesNumpy() {
        let p = ChunkPlan(inputLength: 25, chunk: 20, overlaps: 2)   // padded: 25 > 2·10
        // Trozo con n = 15 > 10 → reflect: np.pad(part, (0, 5), "reflect").
        let k = p.starts.indices.first { p.validCount($0) == 15 }!
        XCTAssertEqual(p.tailPad(k), .reflect)
        let src = (0..<p.paddedLength).map(Float.init)
        var part = [Float](repeating: -1, count: 20)
        src.withUnsafeBufferPointer { s in
            part.withUnsafeMutableBufferPointer { d in p.fill(k, from: [s.baseAddress!], into: [d.baseAddress!]) }
        }
        let i = Float(p.starts[k])
        XCTAssertEqual(part, (0..<15).map { i + Float($0) } + [13, 12, 11, 10, 9].map { i + $0 })
    }

    /// Con un "modelo" identidad (salida = trozo de entrada), la suma con solape en streaming devuelve la
    /// entrada: prueba el relleno reflect de la canción, los pesos, la división y el recorte del borde.
    func testStreamingOverlapAddIsIdentity() throws {
        var rng = SeededRandom(3)
        let cases: [(Int, Int)] = [(100_000, C), (C, C), (1_000_003, C), (3_333, 200), (12_345, 1_000), (999, 1_000)]
        for (L0, chunk) in cases {
            let x = (0..<L0).map { _ in rng.unit() }
            let p = ChunkPlan(inputLength: L0, chunk: chunk)
            var src = [Float](repeating: 0, count: p.paddedLength)
            x.withUnsafeBufferPointer { xp in
                src.withUnsafeMutableBufferPointer { sp in
                    if p.padded {
                        reflectPad(xp.baseAddress!, count: L0, left: p.border, right: p.border, into: sp.baseAddress!)
                    } else {
                        sp.baseAddress!.update(from: xp.baseAddress!, count: L0)
                    }
                }
            }
            var out = [Float](repeating: .nan, count: L0)
            var nextStart = 0
            let asm = OverlapAddAssembler(plan: p, channelCount: 1) { start, ch, n in
                XCTAssertEqual(start, nextStart)
                for j in 0..<n { out[start + j] = ch[0][j] }
                nextStart = start + n
            }
            let part = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
            defer { part.deallocate() }
            try src.withUnsafeBufferPointer { sp in
                for k in 0..<p.count {
                    p.fill(k, from: [sp.baseAddress!], into: [part])
                    try asm.add([UnsafePointer(part)])
                }
            }
            XCTAssertEqual(asm.emitted, L0)
            var maxErr: Float = 0
            for k in 0..<L0 { maxErr = max(maxErr, abs(out[k] - x[k])) }
            XCTAssertLessThan(maxErr, 1e-6, "L0 \(L0), trozo \(chunk): error máximo \(maxErr)")
        }
    }
}
