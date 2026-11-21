import XCTest
@testable import StudyKit

/// Acordes y tonalidad (mini-spec Fase 2 §4 P3) frente a los fixtures de `Fixtures/README.md`.
final class ChordRecognizerTests: XCTestCase {
    static let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    static func url(_ name: String) -> URL { fixtures.appendingPathComponent(name) }

    static func f32(_ name: String) throws -> [Float] {
        let d = try Data(contentsOf: url(name))
        return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    static func i32(_ name: String) throws -> [Int] {
        let d = try Data(contentsOf: url(name))
        return d.withUnsafeBytes { $0.bindMemory(to: Int32.self).map { Int($0) } }
    }

    struct ChordRef: Decodable {
        let n_frames: Int
        let num_pad: Int
        let segments: [[Double]]
    }

    struct KeyRef: Decodable {
        let chroma: [Double]
        let histogram: [Double]
        let scores: [Double]
        let key: String
        let alternative: String
        let confidence: Double
    }

    static func chordRef() throws -> ChordRef {
        try JSONDecoder().decode(ChordRef.self, from: Data(contentsOf: url("chord_ref.json")))
    }

    static func refSegments() throws -> [ChordSegment] {
        try chordRef().segments.map { ChordSegment(start: $0[0], end: $0[1], index: Int($0[2])) }
    }

    /// Predictor simulado: devuelve los logits del fixture ventana a ventana y guarda lo que recibe.
    final class FixturePredictor: ChordWindowPredictor, @unchecked Sendable {
        let logits: [Float]
        private let lock = NSLock()
        private(set) var windows: [[Float]] = []

        init(logits: [Float]) { self.logits = logits }

        func logits(window: UnsafeBufferPointer<Float>) throws -> [Float] {
            lock.lock()
            defer { lock.unlock() }
            let i = windows.count
            windows.append(Array(window))
            let n = ChordContract.windowFrames * ChordContract.nChords
            return Array(logits[(i * n)..<((i + 1) * n)])
        }
    }

    // MARK: CQT

    /// Punto fino: CQT de Swift frente a `librosa.cqt` sobre la entrada normalizada del modelo.
    func testCQTMatchesLibrosa() throws {
        let wav = try ChordAudio.loadMono([Self.url("harm_22k.wav")])
        XCTAssertEqual(wav.count, 264_600)
        let cqt = LibrosaCQT.shared.chunkedMagnitude(wav)
        XCTAssertEqual(cqt.frames, 130)
        let ref = try Self.f32("chord_input.f32")            // [130, 144]
        XCTAssertEqual(ref.count, cqt.frames * 144)
        let x = ChordFeatures.normalized(cqt.values)
        var sum = 0.0, mx = 0.0, at = 0
        for i in x.indices {
            let e = Double(abs(x[i] - ref[i]))
            sum += e
            if e > mx { mx = e; at = i }
        }
        let mean = sum / Double(x.count)
        // |CQT| crudo, error relativo (informativo).
        let raw = try Self.f32("chord_cqt_abs.f32")          // [144, 130]
        var rel = 0.0
        for t in 0..<130 { for k in 0..<144 {
            let r = Double(raw[k * 130 + t])
            rel = max(rel, abs(Double(cqt.values[t * 144 + k]) - r) / max(r, 1e-6))
        } }
        print(String(format: "CQT frente a librosa (entrada normalizada): medio %.2e, máx %.2e (trama %d, bin %d); |CQT| rel. máx %.2e",
                     mean, mx, at / 144, at % 144, rel))
        XCTAssertLessThan(mean, 1e-3)   // mini-spec §4 P3
        XCTAssertLessThan(mx, 1e-2)
    }

    /// Un seno de 1 kHz cae en su bin: 24·log2(1000 / C1) = 118,4 → 118.
    func testSineLandsInItsBin() {
        let sr = ChordContract.sampleRate
        let wav = (0..<Int(sr * 3)).map { Float(0.5 * sin(2 * Double.pi * 1000 * Double($0) / sr)) }
        let cqt = LibrosaCQT.shared.magnitude(wav)
        for t in 5..<(cqt.frames - 5) {
            let row = Array(cqt.values[(t * 144)..<((t + 1) * 144)])
            let best = row.indices.max { row[$0] < row[$1] }!
            XCTAssertEqual(best, 118, "trama \(t)")
            // Una octava por debajo y por encima, al menos 40 dB menos.
            XCTAssertLessThan(row[94], row[118] * 0.01)
            XCTAssertLessThan(row[142], row[118] * 0.01)
        }
    }

    /// Diezmación: el FIR de media banda tiene ganancia 1 y no desplaza (un impulso sale centrado).
    func testHalfbandIsCenteredAndUnityGain() {
        let cqt = LibrosaCQT.shared
        XCTAssertEqual(cqt.earlyDownsamples, 1)
        XCTAssertEqual(cqt.octaves.map(\.hop), [1024, 512, 256, 128, 64, 32])
        XCTAssertEqual(Double(cqt.halfband.reduce(0, +)), 1, accuracy: 1e-6)
        var x = [Float](repeating: 0, count: 2001)
        x[1000] = 1
        let y = cqt.halve(x)
        XCTAssertEqual(y.count, 1001)
        let peak = y.indices.max { abs(y[$0]) < abs(y[$1]) }!
        XCTAssertEqual(peak, 500)
        // Tono de 0,1·fs dentro de la banda de paso: valor eficaz 1/√2 · √2 (scale=True) = 1, error < 1e-4.
        let tone = (0..<8000).map { Float(sin(2 * Double.pi * 0.1 * Double($0))) }
        let h = cqt.halve(tone)[1000..<3000]
        let rms = (h.reduce(0.0) { $0 + Double($1 * $1) } / Double(h.count)).squareRoot()
        XCTAssertEqual(rms, 1, accuracy: 1e-4)
    }

    // MARK: Remuestreo

    /// 44,1 → 22,05 kHz con el conversor de la plataforma (AVAudioConverter en el Mac, r8brain en Windows) frente
    /// a soxr HQ (`harm_22k.wav`, primeros 2 s): sin retardo y misma CQT.
    func testResampleMatchesSoxrReference() throws {
        _ = try checkResampleAgainstSoxr(label: "plataforma")
    }

    /// Lo mismo con r8brain forzado también en el Mac (parte 7.1: validar el motor de Windows con los fixtures),
    /// y croma y log-mel del tramo frente a soxr, que no deben empeorar respecto a AVAudioConverter.
    func testResampleMatchesSoxrReferenceWithR8brain() throws {
        let r8b = try MonoResampler.$forcePortable.withValue(true) { try checkResampleAgainstSoxr(label: "r8brain") }
        #if canImport(AVFoundation)
        let av = try checkResampleAgainstSoxr(label: "AVAudioConverter")
        // Margen: 10 % del valor de AVAudioConverter (los dos WAV de referencia están cuantizados a 16 bits).
        XCTAssertGreaterThanOrEqual(r8b.snr, av.snr - 1)
        XCTAssertLessThanOrEqual(r8b.chromaRel, av.chromaRel * 1.1 + 1e-5)
        XCTAssertLessThanOrEqual(r8b.logMelMax, av.logMelMax * 1.1 + 1e-4)
        #endif
        _ = r8b
    }

    struct SoxrComparison { var snr, cqtMean, cqtMax, chromaRel, logMelMax: Double }

    func checkResampleAgainstSoxr(label: String, file: StaticString = #filePath, line: UInt = #line) throws -> SoxrComparison {
        let mine = try ChordAudio.loadMono([Self.url("harm_44k_stereo.wav")])
        XCTAssertEqual(mine.count, 44_100)
        let ref = Array(try ChordAudio.loadMono([Self.url("harm_22k.wav")])[0..<44_100])
        // Retardo: máximo de la correlación en ±8 muestras sobre el tramo central.
        var bestLag = 0, best = -Double.infinity
        for lag in -8...8 {
            var s = 0.0
            for i in 2000..<42_000 { s += Double(mine[i + lag]) * Double(ref[i]) }
            if s > best { best = s; bestLag = lag }
        }
        var err = 0.0, pow = 0.0
        for i in 2000..<42_000 {
            err += Double((mine[i] - ref[i]) * (mine[i] - ref[i]))
            pow += Double(ref[i] * ref[i])
        }
        let snr = 10 * log10(pow / err)
        let a = ChordFeatures.normalized(LibrosaCQT.shared.magnitude(mine).values)
        let b = ChordFeatures.normalized(LibrosaCQT.shared.magnitude(ref).values)
        // Tramas 1…19 de 22 (las de los bordes ven el corte del fichero de 2 s).
        var mean = 0.0, mx = 0.0
        for i in (144 * 1)..<(144 * 20) {
            let e = Double(abs(a[i] - b[i]))
            mean += e
            mx = max(mx, e)
        }
        mean /= Double(144 * 19)
        // Croma sumado de las mismas tramas (error relativo máximo por clase) y log-mel de BeatThis (máximo).
        let qa = LibrosaCQT.shared.magnitude(mine), qb = LibrosaCQT.shared.magnitude(ref)
        let ca = ChordFeatures.chroma(qa.values, frames: qa.frames), cb = ChordFeatures.chroma(qb.values, frames: qb.frames)
        var chromaRel = 0.0
        for c in 0..<12 {
            let sa = ca[c][1..<20].reduce(0.0) { $0 + Double($1) }, sb = cb[c][1..<20].reduce(0.0) { $0 + Double($1) }
            chromaRel = max(chromaRel, abs(sa - sb) / max(sb, 1e-9))
        }
        let (ma, fa) = try BeatLogMel.shared.compute(mine), (mb, _) = try BeatLogMel.shared.compute(ref)
        var logMelMax = 0.0
        for i in (128 * 2)..<(128 * (fa - 2)) { logMelMax = max(logMelMax, Double(abs(ma[i] - mb[i]))) }
        print(String(format: "remuestreo (%@) frente a soxr: retardo %d, SNR %.1f dB; CQT normalizada medio %.2e, máx %.2e; croma rel. máx %.2e; log-mel máx %.2e",
                     label, bestLag, snr, mean, mx, chromaRel, logMelMax))
        // Medido: SNR 73,6 dB, medio 1,9e-4, máx 9,1e-3. Ambos WAV están cuantizados a 16 bits por separado
        // (antes y después de remuestrear): en los bins más débiles ese ruido ya da ~1e-2, de ahí el máximo 2e-2.
        XCTAssertEqual(bestLag, 0, label, file: file, line: line)
        XCTAssertGreaterThan(snr, 60, label, file: file, line: line)
        XCTAssertLessThan(mean, 1e-3, label, file: file, line: line)
        XCTAssertLessThan(mx, 2e-2, label, file: file, line: line)
        return SoxrComparison(snr: snr, cqtMean: mean, cqtMax: mx, chromaRel: chromaRel, logMelMax: logMelMax)
    }

    // MARK: Ventanas, argmax, fusión, .lab

    func testArgmaxOfFixtureLogits() throws {
        let logits = try Self.f32("chord_logits.f32")       // [2, 108, 170]
        let ref = try Self.i32("chord_argmax.i32")          // [216]
        let got = (0..<216).map { ChordFeatures.argmax(logits, offset: $0 * 170, count: 170) }
        XCTAssertEqual(got, ref)
    }

    func testPipelineWithFixtureLogits() async throws {
        let predictor = FixturePredictor(logits: try Self.f32("chord_logits.f32"))
        let analysis = try await ChordRecognizer(predictor: predictor).analyze(stems: [Self.url("harm_22k.wav")])

        // Dos ventanas; la segunda con 22 tramas válidas y 86 de ceros.
        XCTAssertEqual(predictor.windows.count, 2)
        let w2 = predictor.windows[1]
        XCTAssertEqual(w2.count, 108 * 144)
        XCTAssertTrue(w2[(22 * 144)...].allSatisfy { $0 == 0 })
        XCTAssertFalse(w2[0..<(22 * 144)].allSatisfy { $0 == 0 })
        XCTAssertEqual(try Self.chordRef().num_pad, 86)

        let ref = try Self.refSegments()
        XCTAssertEqual(analysis.segments.count, ref.count)
        for (a, b) in zip(analysis.segments, ref) {
            XCTAssertEqual(a.index, b.index)
            XCTAssertEqual(a.start, b.start, accuracy: 1e-12)
            XCTAssertEqual(a.end, b.end, accuracy: 1e-12)
        }
        XCTAssertEqual(analysis.lab, try String(contentsOf: Self.url("chord.lab"), encoding: .utf8))

        // Croma por fotograma frente a Python.
        let chroma = try Self.f32("chord_chroma.f32")       // [12, 130]
        XCTAssertEqual(analysis.frameCount, 130)
        var rel = 0.0
        for c in 0..<12 { for t in 0..<130 {
            let r = Double(chroma[c * 130 + t])
            rel = max(rel, abs(Double(analysis.chroma[c][t]) - r) / max(r, 1e-3))
        } }
        print(String(format: "croma por fotograma: error relativo máx %.2e", rel))
        XCTAssertLessThan(rel, 1e-3)
    }

    func testSegmentsMergeAndLab() {
        let d = ChordContract.frameDuration
        let segs = ChordFeatures.segments([1, 1, 2, 2, 2, 169, 13 * 0 + 9])
        XCTAssertEqual(segs, [
            ChordSegment(start: 0, end: 2 * d, index: 1),
            ChordSegment(start: 2 * d, end: 5 * d, index: 2),
            ChordSegment(start: 5 * d, end: 6 * d, index: 169),
            ChordSegment(start: 6 * d, end: 7 * d, index: 9),
        ])
        XCTAssertEqual(ChordFeatures.segments([]), [])
        let lab = ChordAnalysis(segments: segs, chroma: []).lab
        XCTAssertEqual(lab, "0.000 0.185 C\n0.185 0.463 C:dim\n0.463 0.556 N\n0.556 0.648 C:7\n")
    }

    // MARK: Tonalidad

    func testKeyMatchesPythonRecipe() throws {
        let ref = try JSONDecoder().decode(KeyRef.self, from: Data(contentsOf: Self.url("key_fixture.json")))
        let segs = try Self.refSegments()
        let hist = KeyDetector.histogram(segs)
        for i in 0..<12 { XCTAssertEqual(hist[i], ref.histogram[i], accuracy: 1e-9) }

        // Con el croma de Python: puntuaciones idénticas.
        let fixChroma = try Self.f32("chord_chroma.f32")
        let chroma = (0..<12).map { c in Array(fixChroma[(c * 130)..<((c + 1) * 130)]) }
        let e = KeyDetector.detect(chroma: chroma, segments: segs)
        XCTAssertEqual(e.key, "F#:maj")
        XCTAssertEqual(e.alternative, "C#:maj")
        XCTAssertEqual(e.key, ref.key)
        XCTAssertEqual(e.alternative, ref.alternative)
        XCTAssertEqual(e.confidence, ref.confidence, accuracy: 1e-6)

        // Con el croma de la CQT de Swift: croma y puntuaciones a 1e-3 (mini-spec §4 P3).
        let wav = try ChordAudio.loadMono([Self.url("harm_22k.wav")])
        let cqt = LibrosaCQT.shared.chunkedMagnitude(wav)
        let mine = ChordFeatures.chroma(cqt.values, frames: cqt.frames).map { $0.reduce(0.0) { $0 + Double($1) } }
        var chromaRel = 0.0
        for i in 0..<12 { chromaRel = max(chromaRel, abs(mine[i] - ref.chroma[i]) / ref.chroma[i]) }
        let s = KeyDetector.scores(chroma: mine, histogram: hist)
        let ds = zip(s, ref.scores).map { abs($0 - $1) }.max()!
        print(String(format: "tonalidad del tramo: croma rel. máx %.2e, puntuaciones máx %.2e", chromaRel, ds))
        XCTAssertLessThan(chromaRel, 1e-3)
        XCTAssertLessThan(ds, 1e-3)
        let e2 = KeyDetector.detect(chroma: ChordFeatures.chroma(cqt.values, frames: cqt.frames), segments: segs)
        XCTAssertEqual(e2.key, ref.key)
    }

    func testKeyZeroVarianceGivesZeroCorrelation() {
        XCTAssertEqual(KeyDetector.pearson([1, 1, 1], [1, 2, 3]), 0)
        // Solo N y X: histograma nulo → s = ½·r(croma, perfil).
        var chroma = [[Float]](repeating: [0], count: 12)
        for (i, v) in KeyDetector.majorProfile.enumerated() { chroma[(i + 9) % 12] = [Float(v)] }   // A mayor
        let segs = [ChordSegment(start: 0, end: 1, index: 169), ChordSegment(start: 1, end: 2, index: 168)]
        XCTAssertEqual(KeyDetector.histogram(segs), [Double](repeating: 0, count: 12))
        let e = KeyDetector.detect(chroma: chroma, segments: segs)
        XCTAssertEqual(e.key, "A:maj")
        let s = KeyDetector.scores(chroma: chroma.map { Double($0[0]) }, histogram: KeyDetector.histogram(segs))
        XCTAssertEqual(s[9], 0.5, accuracy: 1e-6)
        XCTAssertEqual(KeyDetector.keyNames[21], "A:min")
    }

    func testStudyAnalysisRoundTrip() throws {
        let a = StudyAnalysis(beats: BeatGrid(beats: [0.5, 1, 1.5, 2], downbeats: [0.5]),
                              chords: ChordAnalysis(segments: [ChordSegment(start: 0, end: 1, index: 15)],
                                                    chroma: (0..<12).map { [Float($0)] }),
                              key: KeyEstimate(key: "C#:maj", confidence: 0.1, alternative: "F#:maj"))
        let b = try JSONDecoder().decode(StudyAnalysis.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(a, b)
        let noBeats = StudyAnalysis(beats: nil, chords: a.chords, key: a.key)
        XCTAssertEqual(try JSONDecoder().decode(StudyAnalysis.self, from: JSONEncoder().encode(noBeats)), noBeats)
    }
}
