import XCTest
@testable import StemKit

/// El paso de layout del ONNX de separación de Windows (parte 7.8) en todas las plataformas: índices y
/// reconstrucción de la máscara `out / spec` frente al producto que hace `ChunkProcessor`.
final class SeparationSpectrumLayoutTests: XCTestCase {
    let bins = RoformerContract.bins
    let frames = 9
    let stems = 6

    func snr(_ ref: [Float], _ test: [Float]) -> Double {
        var s = 0.0, n = 0.0
        for i in ref.indices { let d = Double(ref[i]) - Double(test[i]); s += Double(ref[i]) * Double(ref[i]); n += d * d }
        return n == 0 ? .infinity : 10 * log10(s / n)
    }

    func testSplitPutsRow2fPlusChannelIntoChannelFrequencyPlane() {
        var spec = [Float](repeating: 0, count: 2 * bins * frames * 2)
        for f in 0..<bins { for c in 0..<2 { for t in 0..<frames {
            let i = ((2 * f + c) * frames + t) * 2
            spec[i] = Float(f * 1000 + c * 100 + t)
            spec[i + 1] = -Float(f * 1000 + c * 100 + t)
        } } }
        var re = [Float](repeating: .nan, count: 2 * bins * frames), im = re
        SeparationSpectrumLayout.split(spec: spec, bins: bins, frames: frames, real: &re, imag: &im)
        var bad = 0
        for c in 0..<2 { for f in 0..<bins { for t in 0..<frames {
            let p = (c * bins + f) * frames + t
            if re[p] != Float(f * 1000 + c * 100 + t) || im[p] != -re[p] { bad += 1 }
        } } }
        XCTAssertEqual(bad, 0)
    }

    /// Modelo simulado como el ONNX: out = máscara·spec en `[stem, canal, frec, trama]`. La máscara reconstruida,
    /// multiplicada otra vez por spec en Float (lo que hace `ChunkProcessor`), devuelve out con SNR ≥ 120 dB, también
    /// con |spec| de 1e-6 a 1e2 y con ceros exactos (máscara 0 allí).
    func testMaskTimesSpecGivesBackTheModelOutput() {
        var rng = SystemRandomNumberGenerator()
        let pairs = 2 * bins * frames
        var spec = [Float](repeating: 0, count: pairs * 2)
        for i in 0..<pairs {
            let mag = Float(pow(10, Double.random(in: -6...2, using: &rng)))
            let ph = Float.random(in: 0..<(2 * .pi), using: &rng)
            spec[2 * i] = mag * cos(ph)
            spec[2 * i + 1] = mag * sin(ph)
        }
        for i in stride(from: 0, to: pairs, by: 97) { spec[2 * i] = 0; spec[2 * i + 1] = 0 }
        var trueMask = [Float](repeating: 0, count: stems * pairs * 2)
        for i in trueMask.indices { trueMask[i] = Float.random(in: -1.5...1.5, using: &rng) }
        // Salida del "ONNX": planos real/imag (stems, 2, bins, T).
        var outRe = [Float](repeating: 0, count: stems * pairs), outIm = outRe
        for s in 0..<stems { for c in 0..<2 { for f in 0..<bins { for t in 0..<frames {
            let si = ((2 * f + c) * frames + t) * 2
            let mi = ((s * 2 * bins + 2 * f + c) * frames + t) * 2
            let o = s * pairs + (c * bins + f) * frames + t
            outRe[o] = trueMask[mi] * spec[si] - trueMask[mi + 1] * spec[si + 1]
            outIm[o] = trueMask[mi] * spec[si + 1] + trueMask[mi + 1] * spec[si]
        } } } }
        var mask = [Float](repeating: .nan, count: stems * pairs * 2)
        SeparationSpectrumLayout.mask(outReal: outRe, outImag: outIm, spec: spec, stems: stems, bins: bins,
                                      frames: frames, into: &mask)
        // Producto Float como ChunkProcessor, devuelto al layout del ONNX para comparar.
        var backRe = [Float](repeating: 0, count: stems * pairs), backIm = backRe
        var zeroMaskAtZeroSpec = true
        for s in 0..<stems { for c in 0..<2 { for f in 0..<bins { for t in 0..<frames {
            let si = ((2 * f + c) * frames + t) * 2
            let mi = ((s * 2 * bins + 2 * f + c) * frames + t) * 2
            let o = s * pairs + (c * bins + f) * frames + t
            backRe[o] = mask[mi] * spec[si] - mask[mi + 1] * spec[si + 1]
            backIm[o] = mask[mi] * spec[si + 1] + mask[mi + 1] * spec[si]
            if spec[si] == 0, spec[si + 1] == 0, mask[mi] != 0 || mask[mi + 1] != 0 { zeroMaskAtZeroSpec = false }
        } } } }
        let snrRe = snr(outRe, backRe), snrIm = snr(outIm, backIm)
        print("[7.8] máscara out/spec · spec frente a out: \(String(format: "%.1f", snrRe)) / \(String(format: "%.1f", snrIm)) dB")
        XCTAssertGreaterThanOrEqual(snrRe, 120)
        XCTAssertGreaterThanOrEqual(snrIm, 120)
        XCTAssertTrue(zeroMaskAtZeroSpec)
        XCTAssertFalse(mask.contains { !$0.isFinite })
    }
}
