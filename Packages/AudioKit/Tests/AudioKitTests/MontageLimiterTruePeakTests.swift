import XCTest
@testable import AudioKit

/// Pico real de `mezcla.wav` con el limitador (mini-spec Fase 7, «Exportación»: −14 LUFS, −1 dBTP; «Pruebas»:
/// −14 ± 0,2 LUFS y tope de −1 dBTP), medido con `LoudnessMeter` sobre el fichero escrito.
final class MontageLimiterTruePeakTests: XCTestCase {
    static let fs = 48_000.0
    static let ceiling = MontageMixer.peakCeilingDB
    /// Tolerancia de sonoridad de las pruebas (spec, «Pruebas» de la Fase 7).
    static let lufsTolerance = 0.2

    var dir: URL!
    override func setUpWithError() throws { dir = try SynthWAV.tempDir() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    static func samplePeakDB(_ x: [[Float]]) -> Double {
        20 * log10(Double(x.map { $0.map(abs).max() ?? 0 }.max() ?? 0))
    }

    // MARK: Limitador suelto

    /// Seno a fs/4 con fase de 45°: las muestras valen ±0,707 (−3 dBFS) y el pico real está a 0 dBTP, entre
    /// muestras. Un detector de pico de muestra a −1 dB no lo ve (no reduce nada y sale a 0 dBTP).
    func testLimiterHoldsTheTruePeakBetweenSamples() {
        let x = SynthWAV.sine(Self.fs / 4, dB: 0, seconds: 1, rate: Self.fs, phase: .pi / 4)
        XCTAssertEqual(Self.samplePeakDB([x]), -3.01, accuracy: 0.01)
        // El interpolador de 48 coeficientes tiene +0,09 dB de ganancia a fs/4: el medidor lee +0,09 dBTP.
        let inputTP = LoudnessMeter.measure([x, x], sampleRate: Self.fs).truePeakDB
        XCTAssertEqual(inputTP, 0, accuracy: 0.1)
        let limiter = PeakLimiter(sampleRate: Self.fs, thresholdDB: Self.ceiling)
        var (l, r) = limiter.process(x, x)
        let tail = limiter.flush()
        l += tail.0
        r += tail.1
        XCTAssertEqual(l.count, x.count)
        let tp = LoudnessMeter.measure([l, r], sampleRate: Self.fs).truePeakDB
        print(String(format: "F7 limitador fs/4: pico de muestra %.3f dBFS, pico real de entrada %.3f dBTP → salida %.4f dBTP, reducción %.3f dB",
                     Self.samplePeakDB([x]), inputTP, tp, limiter.maxReductionDB))
        XCTAssertLessThanOrEqual(tp, Self.ceiling + 1e-3)
        XCTAssertEqual(limiter.maxReductionDB, inputTP - Self.ceiling, accuracy: 0.01)
    }

    // MARK: Señal de la puerta de VideoKit

    /// Misma señal que `MontageFrameGridTests.testGateRealMixerDurationsAndAACLoudness` (VideoKit): backing de
    /// ruido + bajo en diente de sierra, rítmica entera, rítmica parcial y solista con dos solos, tramo 59/30–9,0 s
    /// con fundidos de un compás. Con el detector de pico de muestra daba −0,80 dBTP y −14,08 LUFS
    /// (`limiterOutOfTolerance`).
    static let songDuration = 15.0
    static let takeA = MontageSpan(start: 1.987, end: 9.0)
    static let takeB = MontageSpan(start: 1.987, end: 5.3241)
    static let solos = [MontageSpan(start: 4.0129, end: 5.0), MontageSpan(start: 7.5, end: 8.4871)]

    static func noise(_ n: Int, seed: UInt64, amp: Float) -> [Float] {
        var s = seed
        return (0..<n).map { _ in
            s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return amp * (Float(Double(s >> 11) / Double(1 << 53)) * 2 - 1)
        }
    }

    /// Diente de sierra con ataque seco y caída exponencial cada `period` s.
    static func plucks(_ seconds: Double, freq: Double, period: Double, amp: Float) -> [Float] {
        (0..<Int(seconds * fs)).map { i in
            let t = Double(i) / fs
            let local = t.truncatingRemainder(dividingBy: period)
            let phase = (freq * t).truncatingRemainder(dividingBy: 1)
            return amp * Float((2 * phase - 1) * exp(-local / 0.12))
        }
    }

    func gateTracks() throws -> [MontageTrack] {
        let n = Int(Self.songDuration * Self.fs)
        let bass = Self.plucks(Self.songDuration, freq: 82.41, period: 0.5, amp: 0.25)
        let l = zip(Self.noise(n, seed: 1, amp: 0.08), bass).map(+), r = zip(Self.noise(n, seed: 2, amp: 0.08), bass).map(+)
        let backing = dir.appendingPathComponent("backing.wav")
        try SynthWAV.write([l, r], rate: Self.fs, to: backing)
        var tracks = [MontageTrack(id: "backing", url: backing, group: .backing)]
        let parts: [(String, MontageSpan, [MontageSpan], Double)] = [
            ("A", Self.takeA, [Self.takeA], 196), ("B", Self.takeB, [Self.takeB], 247), ("C", Self.takeA, Self.solos, 659)]
        for (id, take, presence, freq) in parts {
            let notes = Self.plucks(take.end - take.start, freq: freq, period: 0.25, amp: 0.5)
            let url = dir.appendingPathComponent("\(id).wav")
            try SynthWAV.write([notes, notes], rate: Self.fs, to: url)
            tracks.append(MontageTrack(id: id, url: url, songStart: take.start, group: .part(id), presence: .audible(presence)))
        }
        return tracks
    }

    func testGateSignalMixStaysUnderMinus1dBTPMeasuredOnTheFile() async throws {
        let job = MontageMixJob(segments: [MontageSegment(start: 59.0 / 30, end: 9.0)], sampleRate: Self.fs,
                                tracks: try gateTracks(), fadeIn: 1, fadeOut: 1, normalization: .standard,
                                mixURL: dir.appendingPathComponent("mezcla.wav"))
        let r = try await MontageMixer.mix(job)
        let x = try AudioSamples.read(r.mixURL)
        let m = LoudnessMeter.measure(x, sampleRate: Self.fs)
        let lufs = m.integratedLUFS ?? .nan
        print(String(format: "F7 pico real puerta: resultado %.3f LUFS %.3f dBTP (fuera de tolerancia: %@, reducción %.2f dB, ganancia %.2f dB); mezcla.wav %.3f LUFS %.3f dBTP, pico de muestra %.3f dBFS",
                     r.finalLUFS ?? .nan, r.finalTruePeakDB, r.limiterOutOfTolerance ? "sí" : "no", r.limiterMaxReductionDB,
                     r.gainDB, lufs, m.truePeakDB, Self.samplePeakDB(x)))
        // La señal tiene picos entre muestras de más de 0,5 dB: un limitador de pico de muestra se pasaría del tope.
        XCTAssertGreaterThan(m.truePeakDB - Self.samplePeakDB(x), 0.5)
        XCTAssertGreaterThan(r.limiterMaxReductionDB, 2)
        // Techo efectivo de `mezcla.wav`: −1 dBTP menos la holgura del códec (el `.mov` AAC sube el pico).
        XCTAssertLessThanOrEqual(m.truePeakDB, Self.ceiling - MontageMixer.codecHeadroomDB)
        XCTAssertGreaterThan(m.truePeakDB, Self.ceiling - MontageMixer.codecHeadroomDB - 0.15)
        XCTAssertEqual(lufs, MontageMixer.targetLUFS, accuracy: Self.lufsTolerance)
        // Lo que dice el resultado es lo que mide el fichero.
        XCTAssertFalse(r.limiterOutOfTolerance)
        XCTAssertEqual(r.finalTruePeakDB, m.truePeakDB, accuracy: 0.01)
        XCTAssertEqual(r.finalLUFS ?? .nan, lufs, accuracy: 0.01)
    }
}
