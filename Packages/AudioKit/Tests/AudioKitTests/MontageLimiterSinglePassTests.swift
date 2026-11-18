import XCTest
@testable import AudioKit

/// `mezcla.wav` sale de la última pasada del limitador, sin repetirla: el fichero entregado tiene que ser idéntico
/// bit a bit al que escribía la pasada final aparte (misma ganancia y umbral sobre la misma mezcla guardada).
final class MontageLimiterSinglePassTests: XCTestCase {
    static let fs = 48_000.0
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("tf-limiter-single-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// Mezcla sin normalizar guardada como en `MontageMixer.mix` (Float32 entrelazado).
    func scratch(_ l: [Float], _ r: [Float]) throws -> URL {
        var data = Data(count: l.count * 8)
        data.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: Float.self)
            for i in 0..<l.count { p[2 * i] = l[i]; p[2 * i + 1] = r[i] }
        }
        let url = dir.appendingPathComponent("mix-\(UUID().uuidString).f32")
        try data.write(to: url)
        return url
    }

    /// Normaliza con `limiterNormalize` y repite aparte la pasada final con su ganancia y umbral (lo que hacía antes
    /// `mix`); devuelve el número de pasadas tras comprobar que los dos ficheros y las medidas coinciden.
    func assertDeliveredEqualsSeparateFinalPass(_ l: [Float], _ r: [Float], file: StaticString = #filePath,
                                                line: UInt = #line) throws -> MontageMixer.LimiterOutcome {
        let src = try scratch(l, r)
        let report = LoudnessMeter.measure([l, r], sampleRate: Self.fs)
        let ceiling = MontageMixer.peakCeilingDB - MontageMixer.codecHeadroomDB
        let delivered = dir.appendingPathComponent("mezcla-\(UUID().uuidString).wav")
        let outcome = try MontageMixer.limiterNormalize(src, frames: l.count, sampleRate: Self.fs, report: report,
                                                        lufs: MontageMixer.targetLUFS, ceiling: ceiling,
                                                        mixURL: delivered, progress: { _ in })
        let reference = dir.appendingPathComponent("ref-\(UUID().uuidString).wav")
        let writer = try PCM24Writer(url: reference, sampleRate: Self.fs)
        let again = try MontageMixer.limiterPass(src, frames: l.count, sampleRate: Self.fs, gainDB: outcome.gainDB,
                                                 thresholdDB: outcome.thresholdDB, writer: writer)
        try writer.finish()
        let a = try Data(contentsOf: delivered), b = try Data(contentsOf: reference)
        XCTAssertEqual(a.count, 44 + l.count * 6, file: file, line: line)
        XCTAssertTrue(a == b, "mezcla.wav difiere de la pasada final aparte", file: file, line: line)
        XCTAssertEqual(outcome.last.lufs, again.lufs, file: file, line: line)
        XCTAssertEqual(outcome.last.truePeakDB, again.truePeakDB, file: file, line: line)
        XCTAssertEqual(outcome.last.reductionDB, again.reductionDB, file: file, line: line)
        XCTAssertEqual(outcome.clippedSamples, writer.clippedSamples, file: file, line: line)
        return outcome
    }

    static func noise(_ n: Int, seed: UInt64, amp: Float) -> [Float] {
        MontageLimiterTruePeakTests.noise(n, seed: seed, amp: amp)
    }

    /// Ataques secos con caída rápida: el limitador recorta mucho y la sonoridad cae, así que hacen falta más pasadas.
    static func plucks(_ seconds: Double, freq: Double, period: Double, decay: Double, amp: Float) -> [Float] {
        (0..<Int(seconds * fs)).map { i in
            let t = Double(i) / fs
            let local = t.truncatingRemainder(dividingBy: period)
            let phase = (freq * t).truncatingRemainder(dividingBy: 1)
            return amp * Float((2 * phase - 1) * exp(-local / decay))
        }
    }

    func testOnePassDeliversTheSameFileAsTheSeparateFinalPass() throws {
        let n = Int(6 * Self.fs)
        let bass = Self.plucks(6, freq: 82.41, period: 0.5, decay: 0.12, amp: 0.25)
        let l = zip(Self.noise(n, seed: 1, amp: 0.08), bass).map(+), r = zip(Self.noise(n, seed: 2, amp: 0.08), bass).map(+)
        let outcome = try assertDeliveredEqualsSeparateFinalPass(l, r)
        XCTAssertEqual(outcome.passes, 1)
        XCTAssertFalse(outcome.outOfTolerance)
    }

    func testSeveralPassesDeliverTheLastOne() throws {
        let n = Int(6 * Self.fs)
        let hits = Self.plucks(6, freq: 110, period: 0.25, decay: 0.01, amp: 0.9)
        let l = zip(Self.noise(n, seed: 3, amp: 0.002), hits).map(+), r = zip(Self.noise(n, seed: 4, amp: 0.002), hits).map(+)
        let outcome = try assertDeliveredEqualsSeparateFinalPass(l, r)
        XCTAssertGreaterThanOrEqual(outcome.passes, 2, "el caso tiene que obligar a corregir entre pasadas")
    }

    func testSilenceWritesOnePassAtZeroGain() throws {
        let zeros = [Float](repeating: 0, count: Int(Self.fs))
        let outcome = try assertDeliveredEqualsSeparateFinalPass(zeros, zeros)
        XCTAssertEqual(outcome.passes, 1)
        XCTAssertEqual(outcome.gainDB, 0)
    }
}
