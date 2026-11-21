#if canImport(CoreML)
import CoreML
#endif
import XCTest
@testable import StemKit

/// Lectura de la salida del modelo: FP16 con el último eje rellenado como lo devuelve Core ML con
/// `.cpuAndGPU` (strides medidos `[453033600, 75505600, 36832, 32, 1]`), y con bins rellenados.
/// `MaskTensor.copy` (independiente del motor) se prueba en todas las plataformas; en el Mac, además, la
/// entrada por `MLMultiArray`.
final class MaskCopyTests: XCTestCase {
    private func check(frames: Int, pairStride: Int, binPad: Int, stems: Int = 6) throws {
        let rows = 2 * RoformerContract.bins
        let st2 = frames * pairStride + binPad
        let strides = [stems * rows * st2, rows * st2, st2, pairStride, 1]
        let storage = UnsafeMutablePointer<Float16>.allocate(capacity: strides[0])
        defer { storage.deallocate() }
        storage.initialize(repeating: -1, count: strides[0])
        func value(_ s: Int, _ r: Int, _ t: Int, _ ri: Int) -> Float { Float((s * 7 + r * 3 + t * 5 + ri) % 1000) }
        for s in 0..<stems { for r in 0..<rows { for t in 0..<frames { for ri in 0..<2 {
            storage[s * strides[1] + r * strides[2] + t * strides[3] + ri] = Float16(value(s, r, t, ri))
        } } } }
        func verify(_ out: [Float], _ path: String) {
            var bad = 0
            for s in 0..<stems { for r in 0..<rows { for t in 0..<frames { for ri in 0..<2 {
                if out[((s * rows + r) * frames + t) * 2 + ri] != value(s, r, t, ri) { bad += 1 }
            } } } }
            XCTAssertEqual(bad, 0, "\(path): frames \(frames), stride del par \(pairStride), relleno de bin \(binPad)")
        }

        var raw = [Float](repeating: .nan, count: stems * rows * frames * 2)
        try MaskTensor.copy(UnsafeRawPointer(storage), scalar: .float16, shape: [1, stems, rows, frames, 2],
                            strides: strides, stems: stems, rows: rows, frames: frames, into: &raw)
        verify(raw, "MaskTensor")

        #if canImport(CoreML)
        let m = try MLMultiArray(dataPointer: storage,
                                 shape: [1, NSNumber(value: stems), NSNumber(value: rows), NSNumber(value: frames), 2],
                                 dataType: .float16, strides: strides.map { NSNumber(value: $0) }, deallocator: nil)
        var out = [Float](repeating: .nan, count: stems * rows * frames * 2)
        if stems == 6 {
            try CoreMLMaskModel.copyMask(m, rows: rows, frames: frames, into: &out)   // valor por defecto: BS-RoFormer
        } else {
            try CoreMLMaskModel.copyMask(m, stems: stems, rows: rows, frames: frames, into: &out)
        }
        verify(out, "MLMultiArray")
        #endif
    }

    func testPaddedPairsAsReturnedByCoreML() throws { try check(frames: 5, pairStride: 32, binPad: 0) }
    func testContiguous() throws { try check(frames: 5, pairStride: 2, binPad: 0) }
    func testPaddedBins() throws { try check(frames: 3, pairStride: 4, binPad: 8) }
    /// Modelo de solista: 1 stem (`MaskModelContract.leadRhythm`).
    func testSingleStemPaddedPairs() throws { try check(frames: 5, pairStride: 32, binPad: 0, stems: 1) }
    func testSingleStemPaddedBins() throws { try check(frames: 3, pairStride: 4, binPad: 8, stems: 1) }

    /// Forma o strides que no cuadran con el contrato: error, no lectura fuera del tensor.
    func testRejectsWrongShapeAndStrides() throws {
        var out = [Float](repeating: 0, count: 8)
        let storage = [Float](repeating: 0, count: 64)
        try storage.withUnsafeBytes { p in
            XCTAssertThrowsError(try MaskTensor.copy(p.baseAddress!, scalar: .float32, shape: [1, 1, 2, 3, 2],
                                                     strides: [12, 12, 6, 2, 1], stems: 1, rows: 2, frames: 2, into: &out))
            XCTAssertThrowsError(try MaskTensor.copy(p.baseAddress!, scalar: .float32, shape: [1, 1, 2, 2, 2],
                                                     strides: [8, 8, 3, 2, 1], stems: 1, rows: 2, frames: 2, into: &out))
        }
    }
}
