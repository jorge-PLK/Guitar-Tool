#if canImport(CoreML)
import CoreML
#endif
import XCTest
@testable import StemKit

/// Contrato del modelo de solista sin el modelo: STFT con hop 441 frente a las sondas de PyTorch del fixture,
/// plan de trozos de MSST con num_overlap 1 y la tubería completa con una máscara constante.
final class LeadSeparatorTests: XCTestCase {
    static let fixtureDir = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/LeadRhythm")

    struct Probe: Decodable { let row: Int; let frame: Int; let re: Double; let im: Double }
    struct Reference: Decodable {
        let spec_probes: [Probe]
        let mask_probes: [Probe]
        let lead_first8_L: [Double]
        let coreml_fp16_sdr_vs_torch: Double
    }

    static func reference() throws -> Reference {
        try JSONDecoder().decode(Reference.self, from: Data(contentsOf: fixtureDir.appendingPathComponent("reference.json")))
    }

    /// Espectro `[2050, 301, 2]` del primer (y único) trozo del fixture, como lo arma `demix` de MSST.
    static func fixtureSpec() throws -> (spec: [Float], stft: SpectralTransform) {
        let input = try AudioIO.readStereo(fixtureDir.appendingPathComponent("input_2s_pcm16.wav"))
        let c = MaskModelContract.leadRhythm
        let plan = ChunkPlan(inputLength: input.frameCount, chunk: c.chunk, overlaps: c.overlaps)
        let parts = (0..<2).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: c.chunk) }
        defer { parts.forEach { $0.deallocate() } }
        input.left.withUnsafeBufferPointer { l in
            input.right.withUnsafeBufferPointer { r in
                plan.fill(0, from: [l.baseAddress!, r.baseAddress!], into: parts)
            }
        }
        let stft = SpectralTransform(length: c.chunk, hop: c.hop)
        var spec = [Float](repeating: 0, count: stft.specCount)
        for ch in 0..<2 { stft.forward(parts[ch], channel: ch, into: &spec) }
        return (spec, stft)
    }

    func testContractNumbers() {
        let lead = MaskModelContract.leadRhythm
        XCTAssertEqual(lead.chunk, 132_300)
        XCTAssertEqual(SpectralTransform(length: lead.chunk, hop: lead.hop).frames, lead.frames)
        XCTAssertEqual(lead.stemCount, 1)
        XCTAssertEqual(lead.overlaps, 2)
        // BS-RoFormer SW no cambia.
        let bs = MaskModelContract.bsRoformerSW
        XCTAssertEqual([bs.hop, bs.frames, bs.chunk, bs.overlaps, bs.stemCount], [512, 1151, 588_800, 2, 6])
        XCTAssertEqual(bs.outputName, "permute_97")
        // num_overlap 2: paso de 66 150, relleno reflect de un paso por lado.
        let p = ChunkPlan(inputLength: 7 * 44_100, chunk: lead.chunk, overlaps: lead.overlaps)
        XCTAssertEqual(p.border, 66_150)
        XCTAssertTrue(p.padded)
        XCTAssertEqual(p.starts, stride(from: 0, to: 7 * 44_100 + 2 * 66_150, by: 66_150).map { $0 })
        // Referencia de MSST (num_overlap 1): trozos uno detrás de otro, sin relleno.
        let m = MaskModelContract.leadRhythmMSST
        let q = ChunkPlan(inputLength: 7 * 44_100, chunk: m.chunk, overlaps: m.overlaps)
        XCTAssertEqual(q.border, 0)
        XCTAssertEqual(q.starts, [0, 132_300, 264_600])
    }

    /// Con num_overlap 2, en cada muestra interior del tramo pesa al menos un trozo con peso 1: ningún peso total 0
    /// (lo que con num_overlap 1 dejaba muestras a 0 en los cortes) y ningún corte duro.
    func testOverlapWeightsNeverVanish() {
        let c = MaskModelContract.leadRhythm
        for n in [44_100, 132_301, 7 * 44_100, 32 * 44_100 + 8_820] {
            let p = ChunkPlan(inputLength: n, chunk: c.chunk, overlaps: c.overlaps)
            var total = [Float](repeating: 0, count: p.paddedLength)
            for k in 0..<p.count {
                let w = p.weights(k)
                for j in 0..<p.validCount(k) { total[p.starts[k] + j] += w[j] }
            }
            let off = p.padded ? p.border : 0
            let minW = total[off..<(off + n)].min()!
            XCTAssertGreaterThanOrEqual(minW, 1, "n = \(n): peso mínimo \(minW)")
        }
    }

    /// STFT n_fft 2048, hop 441, center reflect sobre el trozo de 3 s (2 s + relleno reflect de cola) frente a
    /// las sondas de PyTorch: el layout fila 2·f + canal y el hop nuevo, sin el modelo.
    func testSpecProbesMatchTorchAtHop441() throws {
        let ref = try Self.reference()
        let (spec, stft) = try Self.fixtureSpec()
        XCTAssertEqual(stft.frames, 301)
        var worst = 0.0
        for p in ref.spec_probes {
            let i = stft.specIndex(bin: p.row / 2, channel: p.row % 2, frame: p.frame)
            let err = max(abs(Double(spec[i]) - p.re), abs(Double(spec[i + 1]) - p.im))
            let tol = 1e-3 + 1e-5 * hypot(p.re, p.im)
            worst = max(worst, err / tol)
            XCTAssertLessThanOrEqual(err, tol, "fila \(p.row) trama \(p.frame): (\(spec[i]), \(spec[i + 1])) vs (\(p.re), \(p.im))")
        }
        print(String(format: "LEAD spec hop 441: %d sondas, peor error = %.3f × tolerancia", ref.spec_probes.count, worst))
    }

    /// Máscara 1 + 0i: la salida es la entrada con el bin 0 a cero por trama. Con num_overlap 2 no queda ninguna
    /// muestra a 0 en los cortes de trozo (con num_overlap 1 salían a 0 la primera y la última de cada corte).
    func testIdentityMaskThroughSeparator() throws {
        let n = 7 * 44_100
        let left = ToneMix.standard(rate: 44_100, channel: 0).render(n)
        let right = ToneMix.standard(rate: 44_100, channel: 1).render(n)
        let model = ConstantMaskModel(frames: 301, contract: .leadRhythm)
        let sep = RoformerLeadSeparator(loader: { model })
        let out = try sep.separateLead(left: left, right: right, sampleRate: 44_100)
        XCTAssertEqual(out.left.count, n)
        XCTAssertEqual(out.right.count, n)
        let plan = ChunkPlan(inputLength: n, chunk: 132_300, overlaps: 2)
        XCTAssertEqual(model.calls, plan.count)
        // Cortes de trozo en coordenadas de la canción (inicio de cada trozo menos el borde de relleno).
        let cuts = plan.starts.map { $0 - plan.border }.filter { $0 > 0 && $0 < n }
        XCTAssertFalse(cuts.isEmpty)
        var worstCut = 0.0
        for c in cuts {
            for k in max(0, c - 2)...min(n - 1, c + 1) {
                XCTAssertNotEqual(out.left[k], 0, "muestra \(k)")
                worstCut = max(worstCut, Double(abs(out.left[k] - left[k])), Double(abs(out.right[k] - right[k])))
            }
        }
        let snr = snrDB(left + right, out.left + out.right)
        print(String(format: "LEAD identidad 44,1 kHz: SNR %.1f dB, error máx en los cortes %.1e", snr, worstCut))
        XCTAssertGreaterThanOrEqual(snr, 40)
        XCTAssertLessThanOrEqual(worstCut, 1e-3)
    }

    /// A 48 kHz el separador remuestrea a 44,1 kHz y vuelta, y devuelve exactamente la longitud de la entrada.
    func testIdentityMaskAt48kKeepsLength() throws {
        let n = 4 * 48_000 + 17
        let left = ToneMix.standard(rate: 48_000, channel: 0).render(n)
        let right = ToneMix.standard(rate: 48_000, channel: 1).render(n)
        let sep = RoformerLeadSeparator(loader: { ConstantMaskModel(frames: 301, contract: .leadRhythm) })
        let out = try sep.separateLead(left: left, right: right, sampleRate: 48_000)
        XCTAssertEqual(out.left.count, n)
        XCTAssertEqual(out.right.count, n)
        // Fuera de los extremos (relleno del remuestreo) y del corte de trozo a 3 s de 44,1 kHz.
        let lo = 4_800, hi = n - 4_800, cut = 3 * 48_000
        var r: [Float] = [], e: [Float] = []
        for k in lo..<hi where abs(k - cut) > 64 {
            r.append(left[k]); r.append(right[k]); e.append(out.left[k]); e.append(out.right[k])
        }
        let snr = snrDB(r, e)
        print(String(format: "LEAD identidad 48 kHz: SNR %.1f dB", snr))
        XCTAssertGreaterThanOrEqual(snr, 40)
    }

    func testLoaderErrorSurfacesOnFirstCall() {
        struct Boom: Error {}
        let sep = RoformerLeadSeparator(loader: { throw Boom() })
        XCTAssertThrowsError(try sep.separateLead(left: [0, 0], right: [0, 0], sampleRate: 44_100))
        XCTAssertThrowsError(try sep.separateLead(left: [0], right: [0, 0], sampleRate: 44_100))
    }

    /// La salida del modelo de solista es float32: copia con strides rellenados y 1 stem.
    func testFloat32SingleStemMaskCopy() throws {
        let rows = 2 * RoformerContract.bins, frames = 4, pairStride = 4, binPad = 3
        let st2 = frames * pairStride + binPad
        let strides = [rows * st2, rows * st2, st2, pairStride, 1]
        var storage = [Float](repeating: -1, count: strides[0])
        func value(_ r: Int, _ t: Int, _ ri: Int) -> Float { Float(r * 10 + t * 2 + ri) }
        for r in 0..<rows { for t in 0..<frames { for ri in 0..<2 { storage[r * st2 + t * pairStride + ri] = value(r, t, ri) } } }
        var out = [Float](repeating: .nan, count: rows * frames * 2)
        try storage.withUnsafeMutableBufferPointer { p in
            #if canImport(CoreML)
            let m = try MLMultiArray(dataPointer: p.baseAddress!, shape: [1, 1, NSNumber(value: rows), NSNumber(value: frames), 2],
                                     dataType: .float32, strides: strides.map { NSNumber(value: $0) }, deallocator: nil)
            try CoreMLMaskModel.copyMask(m, stems: 1, rows: rows, frames: frames, into: &out)
            #else
            // Lo que hará el modelo ONNX con su tensor (paso 7): la misma copia sin MLMultiArray.
            try MaskTensor.copy(UnsafeRawPointer(p.baseAddress!), scalar: .float32, shape: [1, 1, rows, frames, 2],
                                strides: strides, stems: 1, rows: rows, frames: frames, into: &out)
            #endif
        }
        var bad = 0
        for r in 0..<rows { for t in 0..<frames { for ri in 0..<2 where out[(r * frames + t) * 2 + ri] != value(r, t, ri) { bad += 1 } } }
        XCTAssertEqual(bad, 0)
    }
}
