import XCTest
@testable import StemKit

/// Separador completo (trozos, STFT, postproceso, iSTFT, OLA en streaming, E/S) con un MaskModel simulado.
final class SeparatorTests: XCTestCase {
    /// Trozo corto para que los tests vayan rápido: (101 − 1)·512 = 51 200 muestras.
    let smallFrames = 101

    private func toneAudio(_ n: Int, rate: Double) -> StereoAudio {
        StereoAudio(left: ToneMix.standard(rate: rate, channel: 0).render(n),
                    right: ToneMix.standard(rate: rate, channel: 1).render(n), sampleRate: rate)
    }

    private func separate(_ audio: StereoAudio, model: MaskModel,
                          progress: @escaping (Int, Int) -> Void = { _, _ in },
                          cancel: @escaping () -> Bool = { false }) throws -> (URL, [Stem: StereoAudio]) {
        let dir = try makeTempDir("sep")
        let input = dir.appendingPathComponent("mix.wav")
        try writeStereo(audio, to: input)
        let out = dir.appendingPathComponent("stems")
        try RoformerSeparator(model: model).separate(input: input, outputDirectory: out,
                                                     progress: progress, cancel: cancel)
        var stems: [Stem: StereoAudio] = [:]
        for s in Stem.allCases { stems[s] = try AudioIO.readStereo(out.appendingPathComponent(s.fileName)) }
        return (out, stems)
    }

    /// Máscara 1 + 0i: cada stem reconstruye la entrada (sin continua). Tolerancia: SNR > 60 dB.
    func testIdentityMaskReconstructsInputAbove60dB() throws {
        let n = 3 * 51_200 + 777            // varios trozos, relleno de canción y cola no múltiplo
        let audio = toneAudio(n, rate: 44_100)
        let (_, stems) = try separate(audio, model: ConstantMaskModel(frames: smallFrames))
        for s in Stem.allCases {
            let st = stems[s]!
            XCTAssertEqual(st.frameCount, n)
            XCTAssertEqual(st.sampleRate, 44_100)
            let snr = snrDB(audio, st)
            print("identidad, trozo 51 200, \(s.rawValue): SNR \(String(format: "%.1f", snr)) dB")
            XCTAssertGreaterThan(snr, 60, "\(s.rawValue)")
        }
        // Informativo: sin fundido en los extremos (efecto del bin 0 en el borde reflect, igual en Python).
        let raw = StereoAudio(left: ToneMix.standard(rate: 44_100, channel: 0).render(n, taper: 0),
                              right: ToneMix.standard(rate: 44_100, channel: 1).render(n, taper: 0),
                              sampleRate: 44_100)
        let (_, rawStems) = try separate(raw, model: ConstantMaskModel(frames: smallFrames))
        let edge = 8_192
        let interior = StereoAudio(left: Array(raw.left[edge..<(n - edge)]), right: Array(raw.right[edge..<(n - edge)]),
                                   sampleRate: 44_100)
        let g = rawStems[.guitar]!
        let gInterior = StereoAudio(left: Array(g.left[edge..<(n - edge)]), right: Array(g.right[edge..<(n - edge)]),
                                    sampleRate: 44_100)
        print("identidad sin fundido: SNR global \(String(format: "%.1f", snrDB(raw, g))) dB, "
              + "sin los \(edge) primeros/últimos \(String(format: "%.1f", snrDB(interior, gInterior))) dB")
    }

    /// Lo mismo con el tamaño de trozo del contrato (588 800 muestras, spec [1, 2050, 1151, 2]).
    func testIdentityMaskContractChunkAbove60dB() throws {
        let n = 600_001                      // > 2·borde → relleno reflect; 5 trozos
        let audio = toneAudio(n, rate: 44_100)
        let model = ConstantMaskModel()
        let (_, stems) = try separate(audio, model: model)
        XCTAssertEqual(model.calls, ChunkPlan(inputLength: n).count)
        for s in [Stem.bass, .guitar] {
            let snr = snrDB(audio, stems[s]!)
            print("identidad, trozo 588 800, \(s.rawValue): SNR \(String(format: "%.1f", snr)) dB")
            XCTAssertGreaterThan(snr, 60)
            XCTAssertEqual(stems[s]!.frameCount, n)
        }
    }

    /// Máscara compleja distinta por stem: comprueba el producto complejo (no conjugado), el orden de los
    /// stems y el bin 0. Para x = Σ A cos(ωn+φ), la máscara a + bi da a·x − b·Σ A sin(ωn+φ).
    func testComplexMaskPerStemAbove60dB() throws {
        let gains: [(re: Float, im: Float)] = [(1, 0), (0.5, 0), (0, 1), (0, -1), (2, 0), (-0.7, 0.7)]
        let n = 2 * 51_200 + 3_001
        let audio = toneAudio(n, rate: 44_100)
        let quad = StereoAudio(left: ToneMix.standard(rate: 44_100, channel: 0).render(n, quadrature: true),
                               right: ToneMix.standard(rate: 44_100, channel: 1).render(n, quadrature: true),
                               sampleRate: 44_100)
        let (_, stems) = try separate(audio, model: ConstantMaskModel(frames: smallFrames, gains: gains))
        for (s, g) in zip(Stem.allCases, gains) {
            let expected = StereoAudio(
                left: zip(audio.left, quad.left).map { g.re * $0 - g.im * $1 },
                right: zip(audio.right, quad.right).map { g.re * $0 - g.im * $1 }, sampleRate: 44_100)
            let snr = snrDB(expected, stems[s]!)
            print("máscara \(g) en \(s.rawValue): SNR \(String(format: "%.1f", snr)) dB")
            XCTAssertGreaterThan(snr, 60, "\(s.rawValue) con máscara \(g)")
        }
    }

    /// Entrada a 48 kHz → stems a 48 kHz con la misma longitud exacta; con máscara identidad la ida
    /// 48 → 44,1 → 48 kHz conserva la señal alineada (tolerancia: SNR > 50 dB).
    func testInput48kGives48kStemsSameLength() throws {
        let n = 3 * 48_000 + 123
        let audio = toneAudio(n, rate: 48_000)
        let (_, stems) = try separate(audio, model: ConstantMaskModel(frames: smallFrames))
        for s in Stem.allCases {
            XCTAssertEqual(stems[s]!.sampleRate, 48_000)
            XCTAssertEqual(stems[s]!.frameCount, n, "\(s.rawValue)")
        }
        let snr = snrDB(audio, stems[.guitar]!)
        print("48 kHz ida y vuelta con identidad: SNR \(String(format: "%.1f", snr)) dB")
        XCTAssertGreaterThan(snr, 50)
    }

    func testProgressIsMonotonicAndEndsAtOne() throws {
        let n = 4 * 51_200 + 10
        var events: [(Int, Int)] = []
        _ = try separate(toneAudio(n, rate: 44_100), model: ConstantMaskModel(frames: smallFrames),
                         progress: { events.append(($0, $1)) })
        let total = ChunkPlan(inputLength: n, chunk: 51_200).count
        XCTAssertEqual(events.map(\.0), Array(0...total))
        XCTAssertTrue(events.allSatisfy { $0.1 == total })
        let fractions = events.map { Double($0.0) / Double($0.1) }
        XCTAssertEqual(fractions.last, 1)
        XCTAssertEqual(fractions, fractions.sorted())
    }

    func testCancelLeavesNoFiles() throws {
        let dir = try makeTempDir("cancel")
        let input = dir.appendingPathComponent("mix.wav")
        try writeStereo(toneAudio(5 * 51_200, rate: 44_100), to: input)
        let out = dir.appendingPathComponent("stems")
        var done = 0
        XCTAssertThrowsError(try RoformerSeparator(model: ConstantMaskModel(frames: smallFrames))
            .separate(input: input, outputDirectory: out, progress: { k, _ in done = k }, cancel: { done >= 2 })) {
            XCTAssertEqual($0 as? SeparationError, .cancelled)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path), [])
    }

    func testRejectsMonoAndUnsupportedRate() throws {
        let dir = try makeTempDir("bad")
        let sep = RoformerSeparator(model: ConstantMaskModel(frames: smallFrames))
        let rate = dir.appendingPathComponent("22k.wav")
        try writeStereo(StereoAudio(left: [0, 0.1], right: [0, 0.1], sampleRate: 22_050), to: rate)
        XCTAssertThrowsError(try sep.separate(input: rate, outputDirectory: dir)) {
            guard case SeparationError.invalidInput = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try sep.separate(input: dir.appendingPathComponent("nada.wav"), outputDirectory: dir)) {
            guard case SeparationError.invalidInput = $0 else { return XCTFail("\($0)") }
        }
    }
}
