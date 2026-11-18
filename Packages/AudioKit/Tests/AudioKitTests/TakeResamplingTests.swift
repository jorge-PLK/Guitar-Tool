import AVFoundation
import XCTest
@testable import AudioKit

/// Tomas a otra frecuencia que la del proyecto, remuestreadas al cargar (decisión de Jorge, 17/11/2026): un clic
/// cae en el mismo instante del tema (± 1 muestra de destino) en la carga, el reproductor, el punch-in y la
/// corrección de latencia; a la misma frecuencia el camino es el de siempre.
final class TakeResamplingTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws { dir = try SynthWAV.tempDir() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// Tolerancia del encargo: ± 1 muestra de la frecuencia de destino.
    static let toleranceSamples = 1.0
    static let pairs: [(from: Double, to: Double)] = [(48_000, 44_100), (44_100, 48_000)]

    func clickTake(_ name: String, rate: Double, seconds: Double, clickAt: [Int], channels: Int = 1) throws -> URL {
        var x = [Float](repeating: 0, count: Int(seconds * rate))
        for k in clickAt { x[k] = 0.5 }
        let url = dir.appendingPathComponent("\(name).wav")
        try TakeFile.write(Array(repeating: x, count: channels), sampleRate: rate, to: url)
        return url
    }

    /// Posición con decimales del pico más alto en `range` (interpolación parabólica).
    static func peak(_ x: [Float], in range: Range<Int>? = nil) -> Double {
        let r = range ?? 0..<x.count
        var best = r.lowerBound
        for i in r where abs(x[i]) > abs(x[best]) { best = i }
        guard best > 0, best < x.count - 1 else { return Double(best) }
        let a = Double(abs(x[best - 1])), b = Double(abs(x[best])), c = Double(abs(x[best + 1]))
        let d = a - 2 * b + c
        return Double(best) + (d == 0 ? 0 : 0.5 * (a - c) / d)
    }

    func ms(_ samples: Double, _ rate: Double) -> String { String(format: "%.4f ms", samples / rate * 1000) }

    // MARK: Conversión

    func testConvertedTakeKeepsDurationAndClickInstantAndLeavesTheOriginalAlone() throws {
        for (from, to) in Self.pairs {
            let k = Int(0.731 * from)
            let url = try clickTake("t\(Int(from))", rate: from, seconds: 2, clickAt: [k])
            let before = try Data(contentsOf: url)
            let conv = try TakeResampling.readable(url, at: to)
            XCTAssertNotEqual(conv, url)
            XCTAssertEqual(try TakeResampling.sampleRate(of: conv), to)
            let out = try TakeFile.read(conv)
            XCTAssertEqual(out.count, 1, "una toma mono sigue mono")
            let expectedFrames = 2 * to
            let err = Self.peak(out[0]) - Double(k) / from * to
            print("F7 toma \(Int(from))→\(Int(to)): \(out[0].count) muestras (esperadas \(Int(expectedFrames))), clic desfasado \(String(format: "%.3f", err)) muestras (\(ms(err, to)))")
            XCTAssertEqual(Double(out[0].count), expectedFrames, accuracy: Self.toleranceSamples)
            XCTAssertEqual(err, 0, accuracy: Self.toleranceSamples)
            XCTAssertEqual(try Data(contentsOf: url), before, "el original no se toca")
            XCTAssertEqual(try TakeResampling.readable(url, at: to), conv, "la copia se reutiliza")
        }
    }

    func testSameRateIsTheSameFileAndTheSameSamples() throws {
        let url = try clickTake("same", rate: 48_000, seconds: 1, clickAt: [1_000], channels: 2)
        XCTAssertEqual(try TakeResampling.readable(url, at: 48_000), url)
        XCTAssertEqual(try TakeResampling.read(url, at: 48_000), try TakeFile.read(url))
    }

    // MARK: Reproductor

    /// Clic de una toma a `takeRate` en un tema a `songRate`, en la salida offline: instante del tema del pico.
    @MainActor
    func playedClickError(takeRate: Double, songRate: Double) throws -> Double {
        let backing = dir.appendingPathComponent("backing-\(Int(songRate)).wav")
        try TakeFile.write([[Float](repeating: 0, count: Int(4 * songRate))], sampleRate: songRate, to: backing)
        // `songStart` en la rejilla de la toma y fuera de la del tema (como una toma vieja a 48 kHz).
        let songStart = 24_001 / 48_000.0
        let k = Int(0.9137 * takeRate)
        let take = try clickTake("play-\(Int(takeRate))-\(Int(songRate))", rate: takeRate, seconds: 2, clickAt: [k])
        let p = StudyPlayer(offlineWith: nil)
        try p.load(tracks: [Track(id: "backing", url: backing)])
        try p.setTakes([TakeTrack(id: "Tú", url: take, songStart: songStart)])
        let from = 1.0
        p.seek(to: from)
        try p.play()
        let r = try p.renderOffline(frames: Int(1.0 * songRate))
        let y0 = p.runStartFrame - Double(r.start) + p.modelLatencyFrames
        let expected = songStart + Double(k) / takeRate
        let at = Int((y0 + (expected - from) * songRate).rounded())
        let found = Self.peak(r.channels[0], in: max(0, at - 200)..<min(r.channels[0].count, at + 200))
        return found - (y0 + (expected - from) * songRate)
    }

    @MainActor
    func testPlayerPlacesAClickOfATakeAtAnotherRateAtTheSameInstant() throws {
        for (from, to) in Self.pairs + [(48_000, 48_000), (44_100, 44_100)] {
            let err = try playedClickError(takeRate: from, songRate: to)
            print("F7 reproductor toma \(Int(from)) en tema \(Int(to)): clic desfasado \(String(format: "%.3f", err)) muestras (\(ms(err, to)))")
            XCTAssertEqual(err, 0, accuracy: Self.toleranceSamples)
        }
    }

    // MARK: Punch-in

    func testPunchAtProjectRateOverABaseAtAnotherRate() throws {
        for (baseRate, projectRate) in Self.pairs {
            let baseStart = 24_001 / 48_000.0            // en la rejilla de 48 kHz, no en la de 44,1
            let baseClick = 0.4123, punchClick = 1.6071  // segundos desde el inicio de cada fichero
            let base = try clickTake("base-\(Int(baseRate))", rate: baseRate, seconds: 3,
                                     clickAt: [Int(baseClick * baseRate)])
            let baseBytes = try Data(contentsOf: base)
            let punchStart = 1.0
            let punch = try clickTake("punch-\(Int(projectRate))", rate: projectRate, seconds: 2.5,
                                      clickAt: [Int(punchClick * projectRate)])
            let out = dir.appendingPathComponent("flat-\(Int(projectRate)).wav")
            let span = PunchFile(start: 1.8, end: 2.9, url: punch, songStart: punchStart)
            try PunchFlattener.flattenFiles(base: base, baseSongStart: baseStart, punches: [span], to: out,
                                            sampleRate: projectRate)
            XCTAssertEqual(try TakeResampling.sampleRate(of: out), projectRate)
            XCTAssertEqual(try Data(contentsOf: base), baseBytes, "la original no se toca")
            let x = try TakeFile.read(out)[0]
            let start0 = (baseStart * projectRate).rounded()   // muestra del tema de la muestra 0 del resultado
            func found(_ songTime: Double) -> Double {
                let at = Int(songTime * projectRate - start0)
                return Self.peak(x, in: (at - 200)..<(at + 200)) + start0 - songTime * projectRate
            }
            let e1 = found(baseStart + Double(Int(baseClick * baseRate)) / baseRate)
            let e2 = found(punchStart + Double(Int(punchClick * projectRate)) / projectRate)
            print("F7 punch \(Int(projectRate)) sobre base \(Int(baseRate)): clic de la base \(String(format: "%.3f", e1)) muestras (\(ms(e1, projectRate))), del punch \(String(format: "%.3f", e2)) (\(ms(e2, projectRate)))")
            XCTAssertEqual(e1, 0, accuracy: Self.toleranceSamples)
            XCTAssertEqual(e2, 0, accuracy: Self.toleranceSamples)
            XCTAssertEqual(Double(x.count), 3 * projectRate, accuracy: Self.toleranceSamples, "dura lo que la original")
        }
    }

    // MARK: Corrección de latencia

    func key(_ rate: Double) -> LatencyCalibrationKey {
        LatencyCalibrationKey(inputUID: "in", outputUID: "out", sampleRate: rate, bufferFrames: 512, inputChannel: 1,
                              outputChannel: 1)
    }

    func uncalibrated(songStart: Double, fileRate: Double, frames: Int, keyRate: Double) -> RecordedTake {
        RecordedTake(restoring: songStart, sampleRate: fileRate, frameCount: frames, channelCount: 1,
                     latencySamples: 1_200, rigDelaySamples: nil, rigDelayReliable: nil, latencyCalibrated: false,
                     calibrationKey: key(keyRate), clock: .single)
    }

    func calibration(keyRate: Double) -> LatencyCalibrationResult {
        .restored(key: key(keyRate), date: Date(), guitarIn: [1], latencySamples: 2_400.37, spreadSamples: 0,
                  inputChannels: 2, reference: nil)
    }

    /// Fichero a la frecuencia de la clave: misma cuenta entera que antes del cambio.
    func testReshiftWithMatchingRatesIsTheOldIntegerArithmetic() throws {
        let rate = 48_000.0
        let url = try clickTake("rs-same", rate: rate, seconds: 2, clickAt: [30_000])
        let take = uncalibrated(songStart: 120_000 / rate, fileRate: rate, frames: Int(2 * rate), keyRate: rate)
        let out = try XCTUnwrap(TakeAligner.reshift(take, file: url, with: calibration(keyRate: rate)))
        let oldDelta = TakeAligner.shiftSamples(latency: 2_400.37, rigDelay: nil) - take.shiftSamples
        XCTAssertEqual(out.songStartFrame, take.songStartFrame - Int64(oldDelta))
        XCTAssertEqual(out.songStart, Double(take.songStartFrame - Int64(oldDelta)) / rate)
    }

    /// Fichero a otra frecuencia que la clave (una toma a 48 kHz aplanada con un punch a 44,1, o al revés): el
    /// cambio de latencia se aplica en segundos. Con un inicio cerca de 0 también se recorta el fichero.
    func testReshiftWithFileAtAnotherRateThanTheKeyMovesTheClickByTheLatencyInSeconds() throws {
        for (keyRate, fileRate) in Self.pairs {
            for songStartSeconds in [2.5, 0.01] {
                let k = Int(0.8 * fileRate)
                let url = try clickTake("rs-\(Int(keyRate))-\(Int(fileRate))-\(songStartSeconds)", rate: fileRate,
                                        seconds: 2, clickAt: [k])
                let songStart = (songStartSeconds * fileRate).rounded() / fileRate
                let take = uncalibrated(songStart: songStart, fileRate: fileRate, frames: Int(2 * fileRate), keyRate: keyRate)
                let cal = calibration(keyRate: keyRate)
                let out = try XCTUnwrap(TakeAligner.reshift(take, file: url, with: cal))
                let delta = Double(TakeAligner.shiftSamples(latency: 2_400.37, rigDelay: nil) - take.shiftSamples) / keyRate
                let expected = songStart + Double(k) / fileRate - delta
                let x = try TakeFile.read(url)[0]
                XCTAssertEqual(try TakeResampling.sampleRate(of: url), fileRate, "no se remuestrea")
                let got = out.songStart + Self.peak(x) / fileRate
                let err = (got - expected) * fileRate
                print("F7 recalibrar clave \(Int(keyRate)) fichero \(Int(fileRate)) inicio \(songStartSeconds) s: clic desfasado \(String(format: "%.3f", err)) muestras (\(ms(err, fileRate)))")
                XCTAssertEqual(err, 0, accuracy: 0.5 + 1e-6)
                XCTAssertGreaterThanOrEqual(out.songStart, 0)
                XCTAssertEqual(out.frameCount, x.count)
                XCTAssertEqual(out.songStart * fileRate, (out.songStart * fileRate).rounded(), accuracy: 1e-6,
                               "songStart sigue en la rejilla del fichero")
            }
        }
    }
}
