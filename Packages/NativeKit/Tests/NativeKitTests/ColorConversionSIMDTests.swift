import XCTest
#if os(Windows)
import CMediaFoundation

/// La conversión BGRA/NV12 con AVX2 da los mismos bytes que el bucle escalar (imágenes aleatorias, tamaños con colas).
final class ColorConversionSIMDTests: XCTestCase {
    private struct LCG {
        var s: UInt64
        mutating func next() -> UInt8 { s = s &* 6364136223846793005 &+ 1442695040888963407; return UInt8(truncatingIfNeeded: s >> 33) }
    }

    private static let sizes: [(Int, Int)] = [(1, 1), (2, 2), (7, 5), (8, 8), (9, 3), (15, 4), (16, 16), (17, 9), (31, 7), (33, 6), (63, 11), (64, 4), (100, 51), (1919, 6), (1920, 8)]

    private func withScalar<T>(_ body: () -> T) -> T {
        tfmf_color_force_scalar(1)
        defer { tfmf_color_force_scalar(0) }
        return body()
    }

    func testNV12ToBGRAMatchesScalar() {
        print("AVX2 disponible: \(tfmf_color_simd_available())")
        var rng = LCG(s: 42)
        for (w, h) in Self.sizes {
            let ys = Int32(w + 3), uvs = Int32(2 * ((w + 1) / 2) + 5), bs = Int32(4 * w + 12)
            let y = (0..<Int(ys) * h).map { _ in rng.next() }
            let uv = (0..<Int(uvs) * ((h + 1) / 2)).map { _ in rng.next() }
            var a = [UInt8](repeating: 7, count: Int(bs) * h), b = a
            a.withUnsafeMutableBufferPointer { o in tfmf_nv12_to_bgra(y, ys, uv, uvs, Int32(w), Int32(h), o.baseAddress, bs) }
            withScalar { b.withUnsafeMutableBufferPointer { o in tfmf_nv12_to_bgra(y, ys, uv, uvs, Int32(w), Int32(h), o.baseAddress, bs) } }
            XCTAssertEqual(a, b, "NV12 a BGRA \(w)x\(h)")
        }
    }

    func testBGRAToNV12MatchesScalar() {
        var rng = LCG(s: 7)
        for (w, h) in Self.sizes {
            let bs = Int32(4 * w + 12), ys = Int32(w + 3), uvs = Int32(2 * ((w + 1) / 2) + 5)
            // Extremos incluidos (0 y 255) para ejercitar los recortes.
            let src = (0..<Int(bs) * h).map { i -> UInt8 in let v = rng.next(); return i % 7 == 0 ? (v & 1 == 0 ? 0 : 255) : v }
            var ya = [UInt8](repeating: 9, count: Int(ys) * h), uva = [UInt8](repeating: 9, count: Int(uvs) * ((h + 1) / 2))
            var yb = ya, uvb = uva
            ya.withUnsafeMutableBufferPointer { py in uva.withUnsafeMutableBufferPointer { pu in
                tfmf_bgra_to_nv12(src, bs, Int32(w), Int32(h), py.baseAddress, ys, pu.baseAddress, uvs) } }
            withScalar { yb.withUnsafeMutableBufferPointer { py in uvb.withUnsafeMutableBufferPointer { pu in
                tfmf_bgra_to_nv12(src, bs, Int32(w), Int32(h), py.baseAddress, ys, pu.baseAddress, uvs) } } }
            XCTAssertEqual(ya, yb, "Y \(w)x\(h)")
            XCTAssertEqual(uva, uvb, "UV \(w)x\(h)")
        }
    }
}
#endif
