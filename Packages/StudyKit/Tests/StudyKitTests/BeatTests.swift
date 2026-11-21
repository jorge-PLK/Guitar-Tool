import XCTest
@testable import StudyKit

/// Pulso (mini-spec Fase 2 §4 P2) frente a los fixtures de `Fixtures/README.md`.
final class BeatTests: XCTestCase {

    // MARK: fixtures

    static let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!

    static func f32(_ name: String) throws -> [Float] {
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    struct BeatRef: Decodable {
        let frames: Int
        let beats: [Double]
        let downbeats: [Double]
        let bpm_mean: Double
        let chunk_starts: [String: [Int]]
    }

    static func ref() throws -> BeatRef {
        try JSONDecoder().decode(BeatRef.self, from: Data(contentsOf: fixtures.appendingPathComponent("beat_ref.json")))
    }

    // MARK: preproceso

    func testMelBankMatchesFixture() throws {
        let file = try Self.f32("beat_melbank.f32")
        let bank = BeatLogMel.slaneyMelBank()
        XCTAssertEqual(file.count, 513 * 128)
        XCTAssertEqual(bank.count, file.count)
        var maxDiff = 0.0
        for i in 0..<bank.count { maxDiff = max(maxDiff, abs(bank[i] - Double(file[i]))) }
        print("banco mel Swift vs beat_melbank.f32: máx \(maxDiff)")
        XCTAssertLessThan(maxDiff, 5e-5)
    }

    func testLogMelMatchesFixture() throws {
        let ref = try Self.f32("beat_logmel.f32")
        let x = try BeatAudio.loadMono(Self.fixtures.appendingPathComponent("mix_22k.wav"))
        XCTAssertEqual(x.count, 264_600)
        let (mel, frames) = try BeatLogMel.shared.compute(x)
        XCTAssertEqual(frames, 601)
        XCTAssertEqual(mel.count, ref.count)
        var maxDiff: Float = 0, sum: Float = 0
        for i in 0..<min(mel.count, ref.count) {
            let d = abs(mel[i] - ref[i])
            maxDiff = max(maxDiff, d)
            sum += d
        }
        print("log-mel Swift vs beat_logmel.f32: máx \(maxDiff), media \(sum / Float(ref.count)), rango ref \(ref.min()!)…\(ref.max()!)")
        XCTAssertLessThan(maxDiff, 1e-3)
    }

    func testTooShortAudioThrows() {
        XCTAssertThrowsError(try BeatLogMel.shared.compute([Float](repeating: 0, count: 512)))
        XCTAssertNoThrow(try BeatLogMel.shared.compute([Float](repeating: 0, count: 513)))
    }

    /// El remuestreo no puede mover el tiempo: un pulso gaussiano (σ = 0,2 ms, banda < 3 kHz) centrado fuera de
    /// la rejilla de salida (t0 = 1 s + 0,37 muestras de 22 050) debe salir con su centroide en t0.
    /// Tolerancia 0,05 muestras (2,3 µs); un retardo del filtro daría muestras enteras.
    func testResamplerKeepsPulseTime() throws {
        try checkPulseTime(label: "plataforma")
    }

    /// Lo mismo con r8brain (el motor de Windows) forzado también en el Mac (plan, «Corte del paso 7», parte 7.1).
    func testResamplerKeepsPulseTimeWithR8brain() throws {
        try MonoResampler.$forcePortable.withValue(true) { try checkPulseTime(label: "r8brain") }
    }

    func checkPulseTime(label: String) throws {
        let out = 22_050.0
        for rate in [44_100.0, 48_000.0, 96_000.0] {
            let n = Int(rate * 2.5), t0 = 1.0 + 0.37 / out, sigma = 0.0002
            let x = (0..<n).map { i -> Float in
                let t = Double(i) / rate - t0
                return Float(0.8 * exp(-t * t / (2 * sigma * sigma)))
            }
            let y = try BeatAudio.resample(x, from: rate, to: out)
            XCTAssertEqual(y.count, Int((Double(n) * out / rate).rounded()))
            let k = y.indices.max { y[$0] < y[$1] }!
            var num = 0.0, den = 0.0
            for i in (k - 30)...(k + 30) { num += Double(i) * Double(y[i]); den += Double(y[i]) }
            let offset = num / den - t0 * out
            print("remuestreo (\(label)) \(Int(rate)) → 22050: desvío del centroide \(offset) muestras = \(offset / out * 1000) ms, pico \(y[k])")
            XCTAssertEqual(offset, 0, accuracy: 0.05)
            XCTAssertEqual(Double(y.max()!), 0.8, accuracy: 0.8 * 0.02)
        }
    }

    // MARK: troceado

    func testChunkStartsMatchPython() throws {
        let ref = try Self.ref()
        for (frames, starts) in ref.chunk_starts {
            XCTAssertEqual(BeatChunker.starts(frames: Int(frames)!), starts, "T = \(frames)")
        }
        XCTAssertEqual(BeatChunker.starts(frames: 1000), [-6])
        XCTAssertEqual(BeatChunker.starts(frames: 1500), [-6, 6])
        XCTAssertEqual(BeatChunker.starts(frames: 3050), [-6, 1482, 1556])
    }

    /// Predictor que devuelve, por trama de salida, el índice global de la trama de entrada (−1 si es relleno)
    /// y, en `downbeat`, la primera trama real del trozo (identifica qué trozo manda en el solape).
    struct IndexPredictor: BeatFramePredictor {
        func predict(chunk: UnsafeBufferPointer<Float>) throws -> (beat: [Float], downbeat: [Float]) {
            precondition(chunk.count == 1500 * 128)
            let beat = (0..<1500).map { chunk[$0 * 128] - 1 }
            let first = beat.first { $0 >= 0 } ?? -1
            return (beat, [Float](repeating: first, count: 1500))
        }
    }

    func testChunkAggregationAlignsEveryFrame() throws {
        for t in [601, 1000, 1488, 1489, 1500, 3050, 9001] {
            var spect = [Float](repeating: 0, count: t * 128)
            for i in 0..<t { spect[i * 128] = Float(i + 1) }
            let out = try BeatChunker.predict(spect: spect, frames: t, with: IndexPredictor())
            XCTAssertEqual(out.beat, (0..<t).map(Float.init), "T = \(t)")
        }
        // keep_first en 3050: [0, 1488) del trozo −6, [1488, 2976) del 1482, el resto del 1556.
        var spect = [Float](repeating: 0, count: 3050 * 128)
        for i in 0..<3050 { spect[i * 128] = Float(i + 1) }
        let d = try BeatChunker.predict(spect: spect, frames: 3050, with: IndexPredictor()).downbeat
        XCTAssertEqual(d[1487], 0)
        XCTAssertEqual(d[1488], 1482)
        XCTAssertEqual(d[2975], 1482)
        XCTAssertEqual(d[2976], 1556)
        XCTAssertEqual(d[3049], 1556)
    }

    // MARK: postproceso

    func testPostprocessOnFixtureLogitsGivesSameBeats() throws {
        let ref = try Self.ref()
        let (beats, downbeats) = BeatPostprocessor.minimal(beat: try Self.f32("beat_logits_beat.f32"),
                                                           downbeat: try Self.f32("beat_logits_downbeat.f32"))
        XCTAssertEqual(beats.count, 25)
        XCTAssertEqual(downbeats.count, 6)
        assertTimes(beats, ref.beats, accuracy: 1e-9)
        assertTimes(downbeats, ref.downbeats, accuracy: 1e-9)
    }

    func testPeakDeduplicationIsLiteral() {
        var x = [Float](repeating: -5, count: 40)
        x[10] = 2; x[11] = 2; x[12] = 2    // meseta: 10, 11, 12 → 10,5 y 12 (se compara con la media)
        x[30] = 1; x[33] = 0.5              // 33 no es máximo en ±3
        XCTAssertEqual(BeatPostprocessor.peaks(x), [10.5, 12, 30])
        XCTAssertEqual(BeatPostprocessor.peaks([Float](repeating: -1, count: 10)), [])
    }

    func testAnalyzerPipelineWithFixtureLogits() async throws {
        let ref = try Self.ref()
        let b = try Self.f32("beat_logits_beat.f32"), d = try Self.f32("beat_logits_downbeat.f32")
        struct Fixed: BeatFramePredictor {
            let b: [Float], d: [Float]
            func predict(chunk: UnsafeBufferPointer<Float>) throws -> (beat: [Float], downbeat: [Float]) {
                // Un solo trozo con inicio −6: la trama 0 del tramo es la salida 6.
                func place(_ v: [Float]) -> [Float] {
                    var o = [Float](repeating: -1000, count: 1500)
                    for i in v.indices { o[6 + i] = v[i] }
                    return o
                }
                return (place(b), place(d))
            }
        }
        let grid = try await BeatAnalyzer(predictor: Fixed(b: b, d: d))
            .analyze(mix: Self.fixtures.appendingPathComponent("mix_22k.wav"))
        assertTimes(grid.beats, ref.beats, accuracy: 1e-9)
        assertTimes(grid.downbeats, ref.downbeats, accuracy: 1e-9)
        XCTAssertEqual(grid.bpm!, ref.bpm_mean, accuracy: 0.005)
        XCTAssertEqual(grid.beatsPerBar, 4)
    }

    // MARK: rejilla

    /// 110 BPM cuantizado a tramas de 20 ms: intervalos de 27 y 28 tramas (111,1 y 107,1 BPM).
    func testTempoOfQuantized110GridIsMean() {
        let period = 60.0 / 110 * 50
        let beats = (0..<200).map { (Double($0) * period).rounded() / 50 }
        let grid = BeatGrid(beats: beats, downbeats: stride(from: 0, to: 200, by: 4).map { beats[$0] })
        print("tempo rejilla 110 cuantizada: \(grid.bpm!)")
        XCTAssertEqual(grid.bpm!, 110, accuracy: 0.1)
        XCTAssertEqual(grid.beatsPerBar, 4)
        // Un pulso perdido (intervalo doble) queda fuera de ±20 % de la mediana.
        var gappy = beats
        gappy.remove(at: 100)
        XCTAssertEqual(BeatGrid(beats: gappy, downbeats: []).bpm!, 110, accuracy: 0.1)
        XCTAssertNil(BeatGrid(beats: [0, 1], downbeats: []).bpm)
    }

    func testBeatsPerBarIsMode() {
        let beats = (0..<40).map { Double($0) * 0.5 }
        // Compases de 4, 4, 3, 4 pulsos.
        let grid = BeatGrid(beats: beats, downbeats: [0, 2, 4, 5.5, 7.5])
        XCTAssertEqual(grid.beatsPerBar, 4)
        XCTAssertNil(BeatGrid(beats: beats, downbeats: [1]).beatsPerBar)
    }

    /// 120 BPM desde 0,5 s; downbeats cada 4 pulsos desde 1,0 s.
    private func grid120() -> BeatGrid {
        let beats = (1...40).map { Double($0) * 0.5 }
        return BeatGrid(beats: beats, downbeats: stride(from: 1.0, through: 20.0, by: 2.0).map { $0 })
    }

    func testBarAt() {
        let g = grid120()
        XCTAssertNil(g.bar(at: 0.99))
        XCTAssertEqual(g.bar(at: 1.0), 0)
        XCTAssertEqual(g.bar(at: 2.999), 0)
        XCTAssertEqual(g.bar(at: 3.0), 1)
        XCTAssertEqual(g.bar(at: 100), 9)
        XCTAssertNil(BeatGrid(beats: [], downbeats: []).bar(at: 5))
    }

    func testSnap() {
        let g = grid120()
        XCTAssertEqual(g.snap(1.2...2.7, to: .beat), 1.0...2.5)
        XCTAssertEqual(g.snap(1.26...2.74, to: .beat), 1.5...2.5)
        XCTAssertEqual(g.snap(1.2...2.7, to: .bar), 1.0...3.0)
        XCTAssertEqual(g.snap(1.1...1.2, to: .beat), 1.0...1.5)     // no colapsa
        XCTAssertEqual(g.snap(19.9...25, to: .beat), 19.5...20.0)  // al final: el inicio retrocede
        XCTAssertEqual(g.snap(0...0.2, to: .bar), 1.0...3.0)
        XCTAssertEqual(BeatGrid(beats: [], downbeats: []).snap(1.2...2.7, to: .bar), 1.2...2.7)
    }

    func testClicks() throws {
        let g = grid120()
        let c = g.clicks(in: 0.9...3.1)
        XCTAssertEqual(c.map(\.time), [1.0, 1.5, 2.0, 2.5, 3.0])
        XCTAssertEqual(c.map(\.accent), [true, false, false, false, true])
        XCTAssertEqual(g.clicks(in: 1.0...1.0), [Click(time: 1.0, accent: true)])
        XCTAssertEqual(g.clicks(in: 30...40), [])
        let back = try JSONDecoder().decode(BeatGrid.self, from: JSONEncoder().encode(g))
        XCTAssertEqual(back, g)
    }

    // MARK: utilidades

    private func assertTimes(_ got: [Double], _ want: [Double], accuracy: Double,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.count, want.count, "número de instantes", file: file, line: line)
        for (g, w) in zip(got, want) { XCTAssertEqual(g, w, accuracy: accuracy, file: file, line: line) }
    }
}
