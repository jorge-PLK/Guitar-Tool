import XCTest
@testable import AudioKit

/// Mezcla fuera de línea del montaje (mini-spec Fase 7, «Exportación» y «Pruebas»).
final class MontageMixerTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws { dir = try SynthWAV.tempDir() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func wav(_ name: String, _ left: [Float], _ right: [Float]? = nil, rate: Double = 48_000) throws -> URL {
        let url = dir.appendingPathComponent("\(name).wav")
        try SynthWAV.write(right.map { [left, $0] } ?? [left], rate: rate, to: url)
        return url
    }

    func dc(_ value: Float, seconds: Double, rate: Double = 48_000) -> [Float] {
        [Float](repeating: value, count: Int(seconds * rate))
    }

    func read(_ url: URL) throws -> [[Float]] { try AudioSamples.read(url) }

    func job(_ tracks: [MontageTrack], start: Double = 0, end: Double, rate: Double = 48_000,
             normalization: MontageNormalization = .none, fadeIn: Double? = nil, fadeOut: Double? = nil,
             tracksDir: Bool = false) -> MontageMixJob {
        MontageMixJob(start: start, end: end, sampleRate: rate, tracks: tracks, fadeIn: fadeIn, fadeOut: fadeOut,
                      normalization: normalization, mixURL: dir.appendingPathComponent("out/mezcla.wav"),
                      trackDirectory: tracksDir ? dir.appendingPathComponent("out/pistas") : nil)
    }

    private func prepareOut() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("out"), withIntermediateDirectories: true)
    }

    // MARK: Normalización

    func testNormalizesToMinus14LUFS() async throws {
        try prepareOut()
        let a = SynthWAV.pink(dB: -20, seconds: 6, rate: 48_000, seed: 1)
        let b = SynthWAV.pink(dB: -26, seconds: 6, rate: 48_000, seed: 2)
        let r = try await MontageMixer.mix(job([
            .init(id: "bk", url: try wav("a", a, b), group: .backing),
            .init(id: "g", url: try wav("b", b, a), gainDB: -3, group: .part("Rítmica")),
        ], end: 6, normalization: .standard))
        XCTAssertEqual(r.finalLUFS ?? .nan, -14, accuracy: 0.2)
        XCTAssertFalse(r.limitedByPeak)
        let measured = try LoudnessMeter.measure(url: r.mixURL)
        XCTAssertEqual(measured.integratedLUFS ?? .nan, -14, accuracy: 0.2)
        XCTAssertEqual(measured.truePeakDB, r.finalTruePeakDB, accuracy: 0.1)
        XCTAssertEqual(r.gainDB, -14 - (r.measuredLUFS ?? .nan), accuracy: 1e-9)
    }

    func testPeakCeilingLimitsTheGain() async throws {
        try prepareOut()
        // Ruido flojo con unos impulsos altos: muy poca sonoridad y pico alto.
        var s = SynthWAV.white(dB: -45, seconds: 5, rate: 48_000)
        for i in stride(from: 24_000, to: s.count, by: 48_000) { s[i] = 0.5 }
        let r = try await MontageMixer.mix(job([.init(id: "x", url: try wav("x", s, s), group: .backing)],
                                               end: 5, normalization: .standardWithoutLimiter))
        // Techo efectivo: −1 dBTP menos la holgura del códec (−1,3), igual que con limitador.
        let ceiling = MontageMixer.peakCeilingDB - MontageMixer.codecHeadroomDB
        XCTAssertTrue(r.limitedByPeak)
        XCTAssertEqual(r.finalTruePeakDB, ceiling, accuracy: 1e-6)
        XCTAssertEqual(r.gainDB, ceiling - r.measuredTruePeakDB, accuracy: 1e-9)
        XCTAssertEqual(r.finalLUFS ?? .nan, (r.measuredLUFS ?? .nan) + r.gainDB, accuracy: 1e-9)
        XCTAssertLessThan(r.finalLUFS ?? .nan, -14 - 1)
        let measured = try LoudnessMeter.measure(url: r.mixURL)
        print(String(format: "F7 sin limitador: resultado %.3f LUFS %.3f dBTP; fichero %.3f LUFS %.3f dBTP",
                     r.finalLUFS ?? .nan, r.finalTruePeakDB, measured.integratedLUFS ?? .nan, measured.truePeakDB))
        XCTAssertLessThanOrEqual(measured.truePeakDB, ceiling + 0.001)
        XCTAssertEqual(measured.truePeakDB, ceiling, accuracy: 0.01)
        XCTAssertEqual(measured.integratedLUFS ?? .nan, r.finalLUFS ?? .nan, accuracy: 0.05)
    }

    func testWithoutNormalizationTheGainIsZeroAndTheMixIsTheSum() async throws {
        try prepareOut()
        let a = SynthWAV.sine(440, dB: -12, seconds: 2, rate: 48_000)
        let r = try await MontageMixer.mix(job([
            .init(id: "a", url: try wav("a", a), gainDB: -6, group: .backing),
        ], end: 2))
        XCTAssertEqual(r.gainDB, 0)
        let out = try read(r.mixURL)
        let k = Float(pow(10.0, -6.0 / 20))
        for i in stride(from: 0, to: a.count, by: 997) {
            XCTAssertEqual(out[0][i], a[i] * k, accuracy: 2e-7)
            XCTAssertEqual(out[1][i], a[i] * k, accuracy: 2e-7)   // mono: a los dos lados
        }
    }

    // MARK: Fundidos

    func testSpanEdgesFadeIn80msWithoutClicks() async throws {
        try prepareOut()
        let r = try await MontageMixer.mix(job([
            .init(id: "a", url: try wav("a", dc(0.5, seconds: 4)), group: .backing,
                  presence: .audible([MontageSpan(start: 1, end: 3)])),
        ], end: 4))
        let x = try read(r.mixURL)[0]
        let fs = 48_000
        XCTAssertEqual(x[fs - 10], 0, accuracy: 1e-6)
        XCTAssertEqual(x[fs + 1_920], 0.25, accuracy: 1e-3)          // a medio fundido (40 ms): sin²(π/4) · 0,5
        XCTAssertEqual(x[fs + 3_840], 0.5, accuracy: 1e-3)           // fundido completo (80 ms)
        XCTAssertEqual(x[2 * fs], 0.5, accuracy: 1e-6)
        XCTAssertEqual(x[3 * fs - 1_920], 0.25, accuracy: 1e-3)
        XCTAssertEqual(x[3 * fs + 10], 0, accuracy: 1e-6)
        var worst: Float = 0
        for i in 1..<x.count { worst = max(worst, abs(x[i] - x[i - 1])) }
        XCTAssertLessThan(worst, 0.5 * 0.0006)                       // cuarto de seno de 3 840 muestras: ≤ π/2/3840
        // Duración del fundido: del primer valor > 1 % al primero ≥ 99 %.
        let first = x.firstIndex { $0 > 0.005 }!, full = x.firstIndex { $0 >= 0.495 }!
        XCTAssertEqual(Double(full - first) / 48_000, 0.08, accuracy: 0.015)
    }

    func testSilencedSpansAreTheComplementOfAudibleOnes() async throws {
        try prepareOut()
        let spans = [MontageSpan(start: 1, end: 2), MontageSpan(start: 3, end: 3.5)]
        let u = try wav("u", dc(0.5, seconds: 5))
        let r = try await MontageMixer.mix(job([
            .init(id: "a", url: u, group: .part("P"), presence: .audible(spans)),
            .init(id: "b", url: u, group: .backing, presence: .silenced(spans)),
        ], end: 5))
        let x = try read(r.mixURL)[0]
        for i in stride(from: 0, to: x.count, by: 101) { XCTAssertEqual(x[i], 0.5, accuracy: 2e-7) }
        // Y la sustituida calla dentro del tramo.
        let b = try await MontageMixer.mix(job([.init(id: "b", url: u, group: .backing, presence: .silenced(spans))], end: 5))
        let y = try read(b.mixURL)[0]
        XCTAssertEqual(y[Int(1.5 * 48_000)], 0, accuracy: 1e-6)
        XCTAssertEqual(y[Int(0.5 * 48_000)], 0.5, accuracy: 1e-6)
    }

    func testGlobalFadesOfOneBarAtBothEnds() async throws {
        try prepareOut()
        let bar = 2.0   // 120 BPM, 4/4
        let r = try await MontageMixer.mix(job([.init(id: "a", url: try wav("a", dc(0.5, seconds: 8)), group: .backing)],
                                               end: 8, fadeIn: bar, fadeOut: bar))
        let x = try read(r.mixURL)[0]
        let fs = 48_000
        XCTAssertEqual(x[0], 0, accuracy: 1e-6)
        XCTAssertEqual(x[fs], 0.25, accuracy: 1e-3)                  // mitad del fundido de entrada
        XCTAssertEqual(x[4 * fs], 0.5, accuracy: 1e-6)
        XCTAssertEqual(x[7 * fs], 0.25, accuracy: 1e-3)
        XCTAssertEqual(x[x.count - 1], 0, accuracy: 1e-3)
        XCTAssertEqual(r.frames, 8 * fs)
        var worst: Float = 0
        for i in 1..<x.count { worst = max(worst, abs(x[i] - x[i - 1])) }
        XCTAssertLessThan(worst, 1e-4)
    }

    // MARK: Pistas por separado

    func testPerTrackFilesHaveTheSameLengthAndSumToTheMix() async throws {
        try prepareOut()
        let a = SynthWAV.pink(dB: -18, seconds: 5, rate: 48_000, seed: 1)
        let b = SynthWAV.sine(330, dB: -20, seconds: 5, rate: 48_000)
        let c = SynthWAV.sine(660, dB: -22, seconds: 5, rate: 48_000)
        let spans = [MontageSpan(start: 1.5, end: 3.5)]
        let tracks: [MontageTrack] = [
            .init(id: "drums", url: try wav("d", a, a), group: .backing),
            .init(id: "bass", url: try wav("e", b, b), gainDB: -2, group: .backing, presence: .silenced(spans)),
            .init(id: "rhy", url: try wav("r", b, c), gainDB: 1, group: .part("Rítmica")),
            .init(id: "lead", url: try wav("l", c, b), group: .part("Solista"), presence: .audible(spans)),
        ]
        let r = try await MontageMixer.mix(job(tracks, end: 5, fadeIn: 0.5, fadeOut: 0.5, tracksDir: true))
        XCTAssertEqual(r.trackFiles.map(\.group), [.backing, .part("Rítmica"), .part("Solista")])
        XCTAssertEqual(r.trackFiles.map { $0.url.lastPathComponent }, ["backing.wav", "Rítmica.wav", "Solista.wav"])
        let mix = try read(r.mixURL)
        var sum = [[Float]](repeating: [Float](repeating: 0, count: mix[0].count), count: 2)
        for f in r.trackFiles {
            let file = try WAVHeader(f.url)
            XCTAssertEqual(file.frames, r.frames)
            XCTAssertEqual(file.channels, 2)
            XCTAssertEqual(file.bits, 24)
            XCTAssertEqual(file.sampleRate, 48_000)
            let x = try read(f.url)
            for ch in 0..<2 { for i in 0..<x[ch].count { sum[ch][i] += x[ch][i] } }
        }
        XCTAssertEqual(mix[0].count, r.frames)
        for ch in 0..<2 { for i in stride(from: 0, to: mix[ch].count, by: 13) { XCTAssertEqual(sum[ch][i], mix[ch][i], accuracy: 5e-7) } }
        XCTAssertEqual(try WAVHeader(r.mixURL).bits, 24)
    }

    func testNormalizationGainOnlyAffectsTheMixFile() async throws {
        try prepareOut()
        let a = SynthWAV.pink(dB: -30, seconds: 5, rate: 48_000, seed: 3)
        let u = try wav("a", a, a)
        let plain = try await MontageMixer.mix(job([.init(id: "a", url: u, group: .part("P"))], end: 5, tracksDir: true))
        let normalized = try await MontageMixer.mix(job([.init(id: "a", url: u, group: .part("P"))], end: 5,
                                                        normalization: .standard, tracksDir: true))
        XCTAssertGreaterThan(normalized.gainDB, 5)
        let p = try read(plain.trackFiles[1].url), n = try read(normalized.trackFiles[1].url)
        let mixN = try read(normalized.mixURL)
        let g = Float(pow(10, normalized.gainDB / 20))
        for i in stride(from: 0, to: p[0].count, by: 17) {
            XCTAssertEqual(p[0][i], n[0][i], accuracy: 1e-6)
            XCTAssertEqual(mixN[0][i], n[0][i] * g, accuracy: 1e-5)
        }
    }

    // MARK: Posición y frecuencia

    func testTrackStartingMidRangeIsSilentBeforeItsSampleZero() async throws {
        try prepareOut()
        // Tramo [2, 6]; la muestra 0 de la pista cae en el segundo 4 del tema.
        let r = try await MontageMixer.mix(job([
            .init(id: "a", url: try wav("a", dc(0.5, seconds: 5)), songStart: 4, group: .part("P")),
            .init(id: "b", url: try wav("b", dc(0.25, seconds: 10)), songStart: 0, group: .backing),
        ], start: 2, end: 6))
        XCTAssertEqual(r.frames, 4 * 48_000)
        let x = try read(r.mixURL)[0]
        XCTAssertEqual(x[48_000], 0.25, accuracy: 1e-6)             // t = 3 s: solo la b
        XCTAssertEqual(x[2 * 48_000 - 1], 0.25, accuracy: 1e-6)     // justo antes de t = 4 s
        XCTAssertEqual(x[2 * 48_000], 0.75, accuracy: 1e-6)         // t = 4 s: entra la a
        // Pista que empezó antes del tramo: se lee desde su posición correcta.
        let ramp = (0..<(6 * 48_000)).map { Float($0) / Float(6 * 48_000) * 0.5 }
        let r2 = try await MontageMixer.mix(job([.init(id: "r", url: try wav("r", ramp), songStart: 1, group: .backing)],
                                                start: 2, end: 4))
        let y = try read(r2.mixURL)[0]
        XCTAssertEqual(y[0], ramp[48_000], accuracy: 1e-6)
        XCTAssertEqual(y[48_000], ramp[2 * 48_000], accuracy: 1e-6)
    }

    func testTrackAtAnotherSampleRateIsConverted() async throws {
        try prepareOut()
        let tone = SynthWAV.sine(1000, dB: -20, seconds: 4, rate: 44_100)
        let reference = SynthWAV.sine(1000, dB: -20, seconds: 4, rate: 48_000)
        let r = try await MontageMixer.mix(job([.init(id: "a", url: try wav("a", tone, tone, rate: 44_100), group: .backing)],
                                               end: 3, rate: 48_000))
        XCTAssertEqual(r.frames, 3 * 48_000)
        XCTAssertEqual(try AudioSamples.sampleRate(of: r.mixURL), 48_000)
        let l = LoudnessMeter.measure([reference, reference], sampleRate: 48_000).integratedLUFS ?? .nan
        XCTAssertEqual(r.measuredLUFS ?? .nan, l, accuracy: 0.1)
        // Sin restos temporales de la conversión.
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path))?
            .filter { $0.hasPrefix("tf-montage-") } ?? []
        XCTAssertTrue(leftovers.isEmpty)
    }

    /// Lo mismo con la conversión de Windows (r8brain) forzada en el Mac (parte 7.1).
    func testTrackAtAnotherSampleRateIsConvertedWithThePortableConverter() async throws {
        #if canImport(AVFoundation)
        try await AudioImporter.$forcePortable.withValue(true) { try await testTrackAtAnotherSampleRateIsConverted() }
        #endif
    }

    // MARK: Varios tramos

    func segmentJob(_ tracks: [MontageTrack], _ segs: [MontageSegment], normalization: MontageNormalization = .none,
                    tracksDir: Bool = false) -> MontageMixJob {
        MontageMixJob(segments: segs, sampleRate: 48_000, tracks: tracks, fadeIn: 0.5, fadeOut: 0.5,
                      normalization: normalization, mixURL: dir.appendingPathComponent("out/mezcla.wav"),
                      trackDirectory: tracksDir ? dir.appendingPathComponent("out/pistas") : nil)
    }

    func testTwoSegmentsAreConcatenatedWithFadesAtTheCut() async throws {
        try prepareOut()
        let fs = 48_000
        let ramp = (0..<(10 * fs)).map { Float($0) / Float(fs) / 20 }     // valor = t / 20
        let segs = [MontageSegment(start: 1, end: 3, fadeIn: false, fadeOut: true),
                    MontageSegment(start: 6, end: 8, fadeIn: true, fadeOut: false)]
        let r = try await MontageMixer.mix(segmentJob([.init(id: "r", url: try wav("r", ramp), group: .backing)], segs))
        XCTAssertEqual(r.frames, 4 * fs)
        let x = try read(r.mixURL)[0]
        XCTAssertEqual(x.count, 4 * fs)
        XCTAssertEqual(x[0], 0.05, accuracy: 1e-5)                      // empieza en t = 1 s sin fundido
        XCTAssertEqual(x[fs], ramp[2 * fs] , accuracy: 1e-5)            // t = 2 s, fuera de los fundidos
        XCTAssertEqual(x[2 * fs - fs / 4], 0.5 * 2.75 / 20, accuracy: 2e-4)   // mitad del fundido de salida
        XCTAssertEqual(x[2 * fs - 1], 0, accuracy: 1e-4)
        XCTAssertEqual(x[2 * fs], 0, accuracy: 1e-4)
        XCTAssertEqual(x[2 * fs + fs / 4], 0.5 * 6.25 / 20, accuracy: 2e-4)   // mitad del fundido de entrada del 2.º
        XCTAssertEqual(x[3 * fs], 7.0 / 20, accuracy: 1e-5)             // t = 7 s: contenido del 2.º tramo
        XCTAssertEqual(x[4 * fs - 1], 8.0 / 20, accuracy: 1e-4)         // acaba en t = 8 s sin fundido
        var worst: Float = 0
        for i in 1..<x.count { worst = max(worst, abs(x[i] - x[i - 1])) }
        XCTAssertLessThan(worst, 2e-4)                                   // sin saltos en el corte
    }

    func testShortSegmentHalvesItsFades() async throws {
        try prepareOut()
        let fs = 48_000
        let r = try await MontageMixer.mix(segmentJob([.init(id: "a", url: try wav("a", dc(1, seconds: 3)), group: .backing)],
                                                      [MontageSegment(start: 1, end: 1.6)]))
        let x = try read(r.mixURL)[0]
        XCTAssertEqual(x.count, Int(0.6 * Double(fs)))
        XCTAssertEqual(x[x.count / 2], 1, accuracy: 1e-3)               // cada fundido dura 0,3 s
        XCTAssertEqual(x[Int(0.15 * Double(fs))], 0.5, accuracy: 2e-3)
    }

    func testTwoSegmentsNormalizeOnTheConcatenationAndTracksMatch() async throws {
        try prepareOut()
        let a = SynthWAV.pink(dB: -24, seconds: 12, rate: 48_000, seed: 1)
        let b = SynthWAV.sine(330, dB: -26, seconds: 12, rate: 48_000)
        let segs = [MontageSegment(start: 1, end: 4, fadeIn: false), MontageSegment(start: 7, end: 11, fadeOut: false)]
        let r = try await MontageMixer.mix(segmentJob([
            .init(id: "bk", url: try wav("a", a, a), group: .backing),
            .init(id: "g", url: try wav("b", b, b), group: .part("Rítmica"), presence: .audible([MontageSpan(start: 2, end: 9)])),
        ], segs, normalization: .standard, tracksDir: true))
        XCTAssertEqual(r.frames, 7 * 48_000)
        XCTAssertEqual(r.duration, 7, accuracy: 1e-9)
        XCTAssertEqual(try LoudnessMeter.measure(url: r.mixURL).integratedLUFS ?? .nan, -14, accuracy: 0.2)
        XCTAssertEqual(r.finalLUFS ?? .nan, -14, accuracy: 0.2)
        for f in r.trackFiles { XCTAssertEqual(try WAVHeader(f.url).frames, 7 * 48_000) }
        XCTAssertEqual(try WAVHeader(r.mixURL).frames, 7 * 48_000)
    }

    func testRejectsOverlappingSegments() async throws {
        try prepareOut()
        do {
            _ = try await MontageMixer.mix(segmentJob([], [MontageSegment(start: 0, end: 3), MontageSegment(start: 2, end: 5)]))
            XCTFail("debía fallar")
        } catch let e as MontageMixError { XCTAssertEqual(e, .invalidRange) }
    }

    func testInteriorCutFadesEvenWithoutGlobalFadeInAndOut() async throws {
        try prepareOut()
        let fs = 48_000
        // Sin fundido global (primer tramo sin entrada, último sin salida): solo el corte interior funde.
        let segs = [MontageSegment(start: 0, end: 2, fadeIn: false, fadeOut: true),
                    MontageSegment(start: 4, end: 6, fadeIn: true, fadeOut: false)]
        let r = try await MontageMixer.mix(segmentJob([.init(id: "a", url: try wav("a", dc(1, seconds: 7)), group: .backing)], segs))
        let x = try read(r.mixURL)[0]
        XCTAssertEqual(x[0], 1, accuracy: 1e-4)
        XCTAssertEqual(x[x.count - 1], 1, accuracy: 1e-4)
        XCTAssertEqual(x[2 * fs - fs / 4], 0.5, accuracy: 2e-3)          // mitad de la salida del primero
        XCTAssertEqual(x[2 * fs + fs / 4], 0.5, accuracy: 2e-3)          // mitad de la entrada del segundo
        XCTAssertEqual(x[2 * fs - 1], 0, accuracy: 1e-3)
    }

    func testFadeIsLimitedToHalfTheSegmentEvenWithoutTheOtherFade() async throws {
        try prepareOut()
        let fs = 48_000
        // Tramo de 0,4 s con solo fundido de entrada de 0,5 s: dura 0,2 s (mitad del tramo).
        let segs = [MontageSegment(start: 1, end: 1.4, fadeIn: true, fadeOut: false)]
        let r = try await MontageMixer.mix(segmentJob([.init(id: "a", url: try wav("a", dc(1, seconds: 3)), group: .backing)], segs))
        let x = try read(r.mixURL)[0]
        XCTAssertEqual(x.count, Int(0.4 * Double(fs)))
        XCTAssertEqual(x[Int(0.1 * Double(fs))], 0.5, accuracy: 2e-3)
        XCTAssertEqual(x[Int(0.2 * Double(fs))], 1, accuracy: 2e-3)
        XCTAssertEqual(x[x.count - 1], 1, accuracy: 1e-4)
    }

    func testSilenceWithLimiterStillWritesTheMix() async throws {
        try prepareOut()
        let z = [Float](repeating: 0, count: 2 * 48_000)
        let r = try await MontageMixer.mix(job([.init(id: "z", url: try wav("z", z, z), group: .backing)],
                                               end: 2, normalization: .standard))
        XCTAssertNil(r.finalLUFS)
        XCTAssertEqual(r.gainDB, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.mixURL.path))
        XCTAssertEqual(try WAVHeader(r.mixURL).frames, 2 * 48_000)
        XCTAssertFalse(r.limiterOutOfTolerance)
    }

    func testClippedSamplesAreReportedPerFile() async throws {
        try prepareOut()
        let loud = dc(1.5, seconds: 1)
        let r = try await MontageMixer.mix(job([.init(id: "l", url: try wav("l", loud, loud), group: .backing)],
                                               end: 1, tracksDir: true))
        let names = Set(r.clippedFiles.map { $0.url.lastPathComponent })
        XCTAssertEqual(names, ["backing.wav", "mezcla.wav"])
        XCTAssertTrue(r.clippedFiles.allSatisfy { $0.samples == 2 * 48_000 })
        // Sin pasarse de 0 dBFS no hay aviso.
        let ok = try await MontageMixer.mix(job([.init(id: "l", url: try wav("o", dc(0.5, seconds: 1)), group: .backing)], end: 1))
        XCTAssertTrue(ok.clippedFiles.isEmpty)
    }

    // MARK: Limitador

    /// Ruido rosa flojo con transitorios cortos y altos cada medio segundo.
    func peaky(seconds: Double, seed: UInt64 = 1) -> [Float] {
        var x = SynthWAV.pink(dB: -24, seconds: seconds, rate: 48_000, seed: seed)
        let burst = SynthWAV.white(dB: -9, seconds: 0.003, rate: 48_000, seed: seed + 10)
        for start in stride(from: 24_000, to: x.count - burst.count, by: 24_000) {
            for (i, v) in burst.enumerated() { x[start + i] = v }
        }
        return x
    }

    func testLimiterReachesTargetWhereTheCeilingAloneFallsShort() async throws {
        try prepareOut()
        let x = peaky(seconds: 8)
        let u = try wav("p", x, x)
        func run(_ n: MontageNormalization) async throws -> MontageMixResult {
            try await MontageMixer.mix(job([.init(id: "p", url: u, group: .backing)], end: 8, normalization: n))
        }
        let without = try await run(.standardWithoutLimiter)
        XCTAssertTrue(without.limitedByPeak)
        XCTAssertLessThan(without.finalLUFS ?? .nan, -14.5)
        XCTAssertFalse(without.limiterApplied)
        let with = try await run(.standard)
        let m = try LoudnessMeter.measure(url: with.mixURL)
        print(String(format: "F7 limitador: sin limitador %.2f LUFS / %.2f dBTP; con limitador %.2f LUFS / %.2f dBTP, reducción máx %.2f dB, ganancia de entrada %.2f dB",
                     without.finalLUFS ?? .nan, without.finalTruePeakDB, m.integratedLUFS ?? .nan, m.truePeakDB,
                     with.limiterMaxReductionDB, with.gainDB))
        XCTAssertTrue(with.limiterApplied)
        XCTAssertFalse(with.limitedByPeak)
        XCTAssertGreaterThan(with.limiterMaxReductionDB, 0.5)
        XCTAssertEqual(m.integratedLUFS ?? .nan, -14, accuracy: 0.2)
        XCTAssertLessThanOrEqual(m.truePeakDB, MontageMixer.peakCeilingDB - MontageMixer.codecHeadroomDB)
        XCTAssertEqual(with.finalLUFS ?? .nan, m.integratedLUFS ?? .nan, accuracy: 0.05)
    }

    func testSignalThatNeedsNoLimitingIsIdenticalWithAndWithoutLimiter() async throws {
        try prepareOut()
        let x = SynthWAV.pink(dB: -20, seconds: 5, rate: 48_000, seed: 4)
        let u = try wav("q", x, x)
        func run(_ n: MontageNormalization, _ name: String) async throws -> (MontageMixResult, [[Float]]) {
            var j = job([.init(id: "q", url: u, group: .backing)], end: 5, normalization: n)
            j.mixURL = dir.appendingPathComponent("out/\(name).wav")
            let r = try await MontageMixer.mix(j)
            return (r, try read(r.mixURL))
        }
        let (a, ax) = try await run(.standardWithoutLimiter, "a")
        let (b, bx) = try await run(.standard, "b")
        XCTAssertFalse(b.limiterApplied)
        XCTAssertEqual(b.limiterMaxReductionDB, 0, accuracy: 1e-6)
        XCTAssertEqual(a.gainDB, b.gainDB, accuracy: 0.06)
        for c in 0..<2 { for i in stride(from: 0, to: ax[c].count, by: 7) { XCTAssertEqual(ax[c][i], bx[c][i], accuracy: 1e-3) } }
    }

    func testLimiterGainIsContinuousAndHoldsTheThreshold() {
        let fs = 48_000.0
        var x = SynthWAV.sine(200, dB: -6, seconds: 1, rate: fs)
        for i in 24_000..<24_200 { x[i] *= 4 }                       // transitorio que pide unos 12 dB
        let limiter = PeakLimiter(sampleRate: fs, thresholdDB: -1)
        var (l, _) = limiter.process(x, x)
        l += limiter.flush().0
        XCTAssertEqual(l.count, x.count)
        let ceiling = Float(pow(10.0, -1.0 / 20))
        XCTAssertLessThanOrEqual(l.map(abs).max() ?? 0, ceiling + 1e-6)
        XCTAssertGreaterThan(limiter.maxReductionDB, 6.5)
        // Ganancia aplicada = salida / entrada donde la entrada es apreciable: sin saltos.
        var worst: Float = 0
        var prev: Float?
        for i in 0..<x.count where abs(x[i]) > 0.2 {
            let g = l[i] / x[i]
            if let prev, i > 0, abs(x[i - 1]) > 0.2 { worst = max(worst, abs(g - prev)) }
            prev = g
        }
        XCTAssertLessThan(worst, 0.01)
        // El ataque empieza antes del transitorio (anticipación) y se libera después.
        XCTAssertLessThan(l[23_900] / x[23_900], 0.999)
        XCTAssertGreaterThan(l[47_000] / x[47_000], 0.99)
    }

    func testLimiterWorksAcrossSegments() async throws {
        try prepareOut()
        let x = peaky(seconds: 12, seed: 3)
        let segs = [MontageSegment(start: 1, end: 5, fadeIn: false), MontageSegment(start: 7, end: 11, fadeOut: false)]
        let r = try await MontageMixer.mix(segmentJob([.init(id: "p", url: try wav("p", x, x), group: .backing),
                                                       .init(id: "g", url: try wav("g", x, x), gainDB: -3,
                                                             group: .part("R"))], segs, normalization: .standard, tracksDir: true))
        let m = try LoudnessMeter.measure(url: r.mixURL)
        XCTAssertEqual(m.integratedLUFS ?? .nan, -14, accuracy: 0.2)
        XCTAssertLessThanOrEqual(m.truePeakDB, MontageMixer.peakCeilingDB - MontageMixer.codecHeadroomDB)
        XCTAssertEqual(try WAVHeader(r.mixURL).frames, 8 * 48_000)
        // Las pistas no llevan ni ganancia ni limitador: pico alto.
        let t = try LoudnessMeter.measure(url: r.trackFiles[0].url)
        XCTAssertGreaterThan(t.truePeakDB, -20)
    }

    // MARK: Progreso y cancelación

    func testProgressIsMonotonicAndEndsAtOne() async throws {
        try prepareOut()
        let box = ProgressBox()
        _ = try await MontageMixer.mix(job([.init(id: "a", url: try wav("a", dc(0.1, seconds: 3)), group: .backing)],
                                          end: 3, normalization: .standard), progress: { box.add($0) })
        let values = box.values
        XCTAssertEqual(values.last ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(values, values.sorted())
    }

    func testCancellingDeletesPartialFiles() async throws {
        try prepareOut()
        let u = try wav("a", SynthWAV.pink(dB: -20, seconds: 20, rate: 48_000), SynthWAV.pink(dB: -20, seconds: 20, rate: 48_000, seed: 2))
        let j = job([.init(id: "a", url: u, group: .part("P"))], end: 20, normalization: .standard, tracksDir: true)
        let task = Task { try await MontageMixer.mix(j) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("debía cancelarse")
        } catch is CancellationError {}
        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath: j.mixURL.path))
        XCTAssertFalse(fm.fileExists(atPath: j.trackDirectory!.path))
    }

    func testRejectsAnEmptyRange() async throws {
        try prepareOut()
        do {
            _ = try await MontageMixer.mix(job([], start: 3, end: 3))
            XCTFail("debía fallar")
        } catch let e as MontageMixError { XCTAssertEqual(e, .invalidRange) }
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []
    func add(_ v: Double) { lock.lock(); storage.append(v); lock.unlock() }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return storage }
}

/// Cabecera de un WAV PCM (chunks `fmt ` y `data`), sin AVFoundation: la comprobación vale igual en Windows.
struct WAVHeader {
    var channels = 0, sampleRate = 0.0, bits = 0, frames = 0

    init(_ url: URL) throws {
        let d = [UInt8](try Data(contentsOf: url))
        func u16(_ i: Int) -> Int { Int(d[i]) | Int(d[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        var i = 12
        while i + 8 <= d.count {
            let id = String(decoding: d[i..<i + 4], as: UTF8.self), size = u32(i + 4)
            if id == "fmt " { channels = u16(i + 10); sampleRate = Double(u32(i + 12)); bits = u16(i + 22) }
            if id == "data", channels > 0, bits > 0 { frames = size / (channels * bits / 8) }
            i += 8 + size + (size & 1)
        }
    }
}
