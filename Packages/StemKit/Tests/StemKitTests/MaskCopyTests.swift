import CoreML
import XCTest
@testable import StemKit

/// Lectura de la salida del modelo: FP16 con el último eje rellenado como lo devuelve Core ML con
/// `.cpuAndGPU` (strides medidos `[453033600, 75505600, 36832, 32, 1]`), y con bins rellenados.
final class MaskCopyTests: XCTestCase {
    private func check(frames: Int, pairStride: Int, binPad: Int) throws {
        let rows = 2 * RoformerContract.bins, stems = 6
        let st2 = frames * pairStride + binPad
        let strides = [stems * rows * st2, rows * st2, st2, pairStride, 1]
        let storage = UnsafeMutablePointer<Float16>.allocate(capacity: strides[0])
        defer { storage.deallocate() }
        storage.initialize(repeating: -1, count: strides[0])
        func value(_ s: Int, _ r: Int, _ t: Int, _ ri: Int) -> Float { Float((s * 7 + r * 3 + t * 5 + ri) % 1000) }
        for s in 0..<stems { for r in 0..<rows { for t in 0..<frames { for ri in 0..<2 {
            storage[s * strides[1] + r * strides[2] + t * strides[3] + ri] = Float16(value(s, r, t, ri))
        } } } }
        let m = try MLMultiArray(dataPointer: storage, shape: [1, 6, NSNumber(value: rows), NSNumber(value: frames), 2],
                                 dataType: .float16, strides: strides.map { NSNumber(value: $0) }, deallocator: nil)
        var out = [Float](repeating: .nan, count: stems * rows * frames * 2)
        try CoreMLMaskModel.copyMask(m, rows: rows, frames: frames, into: &out)
        var bad = 0
        for s in 0..<stems { for r in 0..<rows { for t in 0..<frames { for ri in 0..<2 {
            if out[((s * rows + r) * frames + t) * 2 + ri] != value(s, r, t, ri) { bad += 1 }
        } } } }
        XCTAssertEqual(bad, 0, "frames \(frames), stride del par \(pairStride), relleno de bin \(binPad)")
    }

    func testPaddedPairsAsReturnedByCoreML() throws { try check(frames: 5, pairStride: 32, binPad: 0) }
    func testContiguous() throws { try check(frames: 5, pairStride: 2, binPad: 0) }
    func testPaddedBins() throws { try check(frames: 3, pairStride: 4, binPad: 8) }
}
