import AVFoundation
import XCTest
@testable import AudioKit

/// Retardo del rig, grabación alineada y condición de paso sin hardware (mini-spec Fase 3,
/// «Demostración sin hardware»).
final class TakeAlignmentTests: XCTestCase {
    static let fs = 48_000.0
    static let latency = 2_400.81
    static let declared = 1_200.0

    final class Box: @unchecked Sendable {
        var offset: Double?
        var origin: Int64?
    }

    // MARK: Señales

    /// Notas pulsadas sintéticas: 6 armónicos con caída exponencial, ataque de 2 ms, inicios cada 150–400 ms.
    static func plucks(seconds: Double, seed: UInt64) -> [Float] {
        var rng = SeededNoise(seed: seed)
        let n = Int(seconds * fs)
        var x = [Float](repeating: 0, count: n)
        var t = 0.1
        while t < seconds - 0.5 {
            let f0 = 82 * pow(2, rng.uniform() * 3)
            let amp = 0.15 + 0.15 * rng.uniform()
            let start = Int(t * fs), len = min(n - start, Int(0.8 * fs))
            for i in 0..<len {
                let tt = Double(i) / fs
                let env = min(1, tt / 0.002) * exp(-tt / 0.25)
                var v = 0.0
                for h in 1...6 { v += sin(2 * .pi * f0 * Double(h) * tt) / Double(h) }
                x[start + i] += Float(amp * env * v * 0.5)
            }
            t += 0.15 + 0.25 * rng.uniform()
        }
        return x
    }

    /// Ráfaga de 2 ms a 3 kHz con ventana de Hann (impar respecto a su centro, muestra 48).
    static let burst: [Float] = (0..<96).map { k in
        Float(0.5 * (0.5 - 0.5 * cos(2 * Double.pi * Double(k) / 96)) * sin(2 * Double.pi * 3_000 * Double(k) / fs))
    }

    static let clickPeriod = 0.5
    static let firstClick = 0.25

    static func clickTimes(songSeconds: Double) -> [Double] {
        stride(from: firstClick, to: songSeconds - 0.1, by: clickPeriod).map { $0 }
    }

    static func writeBacking(seconds: Double, to url: URL) throws -> Track {
        var x = [Float](repeating: 0, count: Int(seconds * fs))
        for c in clickTimes(songSeconds: seconds) {
            let center = Int((c * fs).rounded())
            for k in 0..<burst.count { x[center - 48 + k] += burst[k] }
        }
        try TakeFile.write([x, x], sampleRate: fs, to: url)
        return Track(id: "backing", url: url)
    }

    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("TakeAlignmentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Error (muestras) de cada clic de la toma frente a su sitio en el backing: `(tiempo del tema, error)`.
    static func clickErrors(take x: [Float], songStartFrame: Int64, songSeconds: Double, window w: Int = 64) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        for c in clickTimes(songSeconds: songSeconds) {
            let e = Int((c * fs).rounded()) - Int(songStartFrame)
            let segStart = e - 48 - w
            guard segStart >= 0, segStart + 2 * w + 96 <= x.count else { continue }
            let seg = Array(x[segStart..<(segStart + 2 * w + 96)])
            let (corr, _) = SignalMath.analyticCorrelation(signal: seg, template: burst)
            var k = 0
            for i in 0...(2 * w) where corr[i] > corr[k] { k = i }
            let tau = SignalMath.refinePeak(corr, near: k)
            out.append((c, Double(segStart) + tau - Double(e - 48)))
        }
        return out
    }

    // MARK: Sesiones

    /// Graba `signal` (por la salida 1) en una toma de su misma duración, con el ancla en el tema 0.
    static func record(_ signal: [Float], io: SimulatedAudioIO, recorder: TakeRecorder) throws {
        let box = Box()
        try io.start(render: { buf in
            if box.origin == nil { box.origin = buf.sampleTime }
            let rel = Int(buf.sampleTime - box.origin!)
            let out = buf[0]
            for i in 0..<buf.frameCount where rel + i < signal.count { out[i] = signal[rel + i] }
        }, capture: { recorder.capture($0) })
        io.pump()
        recorder.setAnchor(PlaybackAnchor(songTime: 0, outputSample: Double(box.origin!), sampleRate: fs))
        while io.sampleTime - box.origin! < Int64(signal.count) { io.pump() }
        io.stop()
    }

    /// Toca el backing de clics con el `StudyPlayer` en render offline desde `start`, lo devuelve por `io`
    /// y graba `seconds`. Devuelve la toma y lo escrito.
    @MainActor
    static func playAndRecord(backing: Track, from start: Double, seconds: Double, io: SimulatedAudioIO,
                              calibration: LatencyCalibrationResult?, guitarIn: [Int], url: URL) throws -> (RecordedTake, [[Float]]) {
        let player = StudyPlayer(offlineWith: nil)
        try player.load(tracks: [backing])
        player.seek(to: start)
        try player.play()
        let recorder = TakeRecorder(io: io, backingOutLeft: 1, guitarIn: guitarIn, calibration: calibration)
        let box = Box()
        try io.start(render: { buf in
            let frames = buf.frameCount
            let r = MainActor.assumeIsolated { try! player.renderOffline(frames: frames) }
            if box.offset == nil { box.offset = Double(buf.sampleTime) - Double(r.start) }
            for ch in 0..<2 { _ = buf[ch].update(fromContentsOf: r.channels[ch]) }
        }, capture: { recorder.capture($0) })
        let begin = io.sampleTime
        io.pump()
        let anchor = try XCTUnwrap(player.playbackAnchor).offsettingOutput(by: box.offset!)
        recorder.setAnchor(anchor)
        while io.sampleTime - begin < Int64(seconds * fs) { io.pump() }
        io.stop()
        player.pause()
        let take = try recorder.finish(writingTo: url)
        return (take, try TakeFile.read(url))
    }

    func report(_ name: String, _ errs: [(Double, Double)], file: StaticString = #filePath, line: UInt = #line) {
        let head = errs.prefix(10), tail = errs.suffix(10)
        let maxAbs = errs.map { abs($0.1) }.max() ?? .nan
        let hMax = head.map { abs($0.1) }.max() ?? .nan, tMax = tail.map { abs($0.1) }.max() ?? .nan
        print(String(format: "F3 %@: %d clics, máx |error| %.4f muestras (%.5f ms); primeros 10 %.4f, últimos 10 %.4f; de %.2f s a %.2f s",
                     name, errs.count, maxAbs, maxAbs / Self.fs * 1000, hMax, tMax, errs.first?.0 ?? 0, errs.last?.0 ?? 0))
        XCTAssertGreaterThanOrEqual(errs.count, 110, name, file: file, line: line)
        XCTAssertLessThanOrEqual(maxAbs, 1, name, file: file, line: line)
    }

    // MARK: Retardo del rig

    func testRigDelayPerTakeWithSaturationAndUnreliableWithFullDelay() throws {
        let rigCal = 103.27, rigTake = 223.71
        func guitar(_ rig: Double, echoes: [SimulatedEcho] = []) -> SimulatedInput {
            SimulatedInput(source: 1, extraDelaySamples: rig, echoes: echoes, drive: 4, gain: 0.4, noiseDBFS: -60)
        }
        let io = SimulatedAudioIO(sampleRate: Self.fs, inputs: [guitar(rigCal), SimulatedInput(source: 1, noiseDBFS: -60)],
                                  latencySamples: Self.latency, declaredLatencySamples: Self.declared,
                                  initialSampleTime: LatencyCalibratorTests.t0)
        let cal = try LatencyCalibratorTests.calibrate(io)
        XCTAssertEqual(cal.reference?.channel, 2)
        XCTAssertEqual(cal.rigDelayAtCalibration ?? 0, rigCal, accuracy: 1)

        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let signal = Self.plucks(seconds: 20, seed: 7)

        io.setInput(1, guitar(rigTake))
        let rec = TakeRecorder(io: io, backingOutLeft: 1, guitarIn: [1], calibration: cal)
        try Self.record(signal, io: io, recorder: rec)
        let take = try rec.finish(writingTo: dir.appendingPathComponent("a.wav"))
        let err = (take.rigDelaySamples ?? .nan) - rigTake
        print(String(format: "F3 rig por toma (calibrado %.2f, real %.2f): medido %.4f, error %+.4f muestras (%+.5f ms), fiable %@",
                     rigCal, rigTake, take.rigDelaySamples ?? .nan, err, err / Self.fs * 1000, "\(take.rigDelayReliable ?? false)"))
        XCTAssertEqual(take.rigDelayReliable, true)
        XCTAssertEqual(take.rigDelaySamples ?? 0, rigTake, accuracy: 2)
        XCTAssertEqual(take.latencySamples, cal.reference!.latencySamples)
        XCTAssertTrue(take.latencyCalibrated)

        // Delay al 100 %: repeticiones tan fuertes como la señal. Corto (dentro de la ventana) y largo.
        let short = (1...3).map { SimulatedEcho(delaySamples: Double($0) * 0.012 * Self.fs, gain: pow(0.8, Double($0 - 1))) }
        let long = (1...3).map { SimulatedEcho(delaySamples: Double($0) * 0.350 * Self.fs, gain: pow(0.8, Double($0 - 1))) }
        for (name, echoes) in [("delay 100 % a 12 ms", short), ("delay 100 % a 350 ms", long)] {
            io.setInput(1, guitar(rigTake, echoes: echoes))
            let r = TakeRecorder(io: io, backingOutLeft: 1, guitarIn: [1], calibration: cal, lastReliableRigDelay: take.rigDelaySamples)
            try Self.record(signal, io: io, recorder: r)
            let t = try r.finish(writingTo: dir.appendingPathComponent("b.wav"))
            print("F3 rig con \(name): fiable \(t.rigDelayReliable ?? false), usado \(t.rigDelaySamples ?? .nan)")
            XCTAssertEqual(t.rigDelayReliable, false, name)
            XCTAssertEqual(t.rigDelaySamples, take.rigDelaySamples, name)
        }
    }

    /// Margen de los umbrales de fiabilidad: los casos claros quedan muy por encima y los turbios muy por debajo.
    func testRigEstimatorSeparatesClearFromUnclearPeaks() {
        let x = Self.plucks(seconds: 10, seed: 3)
        func delayed(_ d: Int, drive: Double, echoes: [(Int, Float)] = []) -> [Float] {
            var y = [Float](repeating: 0, count: x.count)
            for i in d..<x.count { y[i] = x[i - d] }
            for (e, g) in echoes { for i in (d + e)..<x.count { y[i] += g * x[i - d - e] } }
            return drive > 0 ? y.map { Float(tanh(drive * Double($0))) } : y
        }
        for (name, y, clear) in [("limpio 200", delayed(200, drive: 0), true), ("tanh4 200", delayed(200, drive: 4), true),
                                 ("eco 12 ms", delayed(200, drive: 4, echoes: [(576, 1), (1152, 0.8)]), false),
                                 ("eco 350 ms", delayed(200, drive: 4, echoes: [(16_800, 1), (33_600, 0.8), (50_400, 0.64)]), false),
                                 ("sin relación", Self.plucks(seconds: 10, seed: 99), false)] {
            let e = TakeAligner.rigDelay(guitar: y, reference: x, sampleRate: Self.fs, lastReliable: -1)
            print(String(format: "F3 estimador %@: medido %.4f corr %.3f secundario %.3f fiable %@",
                         name, e.measuredSamples, e.correlation, e.secondaryRatio, "\(e.reliable)"))
            XCTAssertEqual(e.reliable, clear, name)
            if clear {
                XCTAssertEqual(e.samples, 200, accuracy: 0.05, name)
            } else {
                XCTAssertEqual(e.samples, -1, name)
            }
        }
    }

    // MARK: Condición de paso

    @MainActor
    func testPassConditionClicksWithinOneSampleFromStartAndMidSong() throws {
        let rig = 151.37
        let guitarL = SimulatedInput(source: 1, extraDelaySamples: rig, drive: 2, gain: 0.5, noiseDBFS: -60)
        let guitarR = SimulatedInput(source: 2, extraDelaySamples: rig, drive: 2, gain: 0.5, noiseDBFS: -60)
        let io = SimulatedAudioIO(sampleRate: Self.fs, inputs: [guitarL, guitarR, SimulatedInput(source: 1, noiseDBFS: -60)],
                                  latencySamples: Self.latency, declaredLatencySamples: Self.declared,
                                  initialSampleTime: LatencyCalibratorTests.t0)
        let cal = try LatencyCalibratorTests.calibrate(io, guitarIn: [1, 2])
        XCTAssertEqual(cal.reference?.channel, 3)

        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let song = 110.0
        let backing = try Self.writeBacking(seconds: song, to: dir.appendingPathComponent("backing.wav"))
        for start in [0.0, 47.31] {
            let (take, x) = try Self.playAndRecord(backing: backing, from: start, seconds: 60, io: io, calibration: cal,
                                                   guitarIn: [1, 2], url: dir.appendingPathComponent("processed.wav"))
            print(String(format: "F3 toma desde %.2f s: songStart %.6f s, latencia %.4f, rig %.4f (fiable %@), desplazamiento %d, %d canales, %d muestras",
                         start, take.songStart, take.latencySamples, take.rigDelaySamples ?? .nan,
                         "\(take.rigDelayReliable ?? false)", take.shiftSamples, take.channelCount, take.frameCount))
            XCTAssertEqual(take.channelCount, 2)
            XCTAssertEqual(x.count, 2)
            XCTAssertEqual(x[0].count, take.frameCount)
            XCTAssertTrue(take.latencyCalibrated)
            XCTAssertEqual(take.rigDelayReliable, true)
            XCTAssertEqual(take.songStart, start, accuracy: 0.5 / Self.fs)
            XCTAssertEqual(Double(take.frameCount) / Self.fs, 60, accuracy: 0.1)
            for c in 0..<2 {
                report("condición de paso desde \(start) s, canal \(c + 1)",
                       Self.clickErrors(take: x[c], songStartFrame: take.songStartFrame, songSeconds: song))
            }
        }
    }

    @MainActor
    func testUncalibratedTakeIsMarkedAndCorrectedAfterCalibrating() throws {
        let io = SimulatedAudioIO(sampleRate: Self.fs, inputs: [SimulatedInput(source: 1, drive: 2, gain: 0.5, noiseDBFS: -60)],
                                  latencySamples: Self.latency, declaredLatencySamples: Self.declared,
                                  initialSampleTime: LatencyCalibratorTests.t0)
        // Calibración de otra clave (otra entrada).
        let other = SimulatedAudioIO(sampleRate: Self.fs, inputs: [SimulatedInput(source: 1, noiseDBFS: -60)],
                                     latencySamples: 3_000.2, declaredLatencySamples: Self.declared, inputDeviceUID: "otra")
        let stale = try LatencyCalibratorTests.calibrate(other)
        XCTAssertTrue(stale.isValid)

        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let song = 80.0
        let backing = try Self.writeBacking(seconds: song, to: dir.appendingPathComponent("backing.wav"))
        let url = dir.appendingPathComponent("processed.wav")
        let (take, x) = try Self.playAndRecord(backing: backing, from: 12.5, seconds: 60, io: io, calibration: stale,
                                               guitarIn: [1], url: url)
        XCTAssertFalse(take.latencyCalibrated)
        XCTAssertEqual(take.latencySamples, Self.declared)
        XCTAssertNil(take.rigDelaySamples)
        let before = Self.clickErrors(take: x[0], songStartFrame: take.songStartFrame, songSeconds: song, window: 2_000)
        let meanBefore = before.map(\.1).reduce(0, +) / Double(before.count)
        print(String(format: "F3 sin calibrar: error medio %.3f muestras (%.3f ms), esperado ≈ %.2f",
                     meanBefore, meanBefore / Self.fs * 1000, Self.latency - Self.declared))
        XCTAssertEqual(meanBefore, Self.latency - Self.declared, accuracy: 1)

        let cal = try LatencyCalibratorTests.calibrate(io)
        XCTAssertNil(try TakeAligner.reshift(take, file: url, with: stale))
        let fixed = try XCTUnwrap(try TakeAligner.reshift(take, file: url, with: cal))
        XCTAssertTrue(fixed.latencyCalibrated)
        XCTAssertEqual(fixed.latencySamples, cal.latencySamples)
        let y = try TakeFile.read(url)
        XCTAssertEqual(y[0].count, fixed.frameCount)
        print(String(format: "F3 re-desplazada: songStart %.6f → %.6f s", take.songStart, fixed.songStart))
        report("toma sin calibrar corregida", Self.clickErrors(take: y[0], songStartFrame: fixed.songStartFrame, songSeconds: song))
    }

    func testReshiftTrimsWhenTheNewStartFallsBeforeTheSong() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("processed.wav")
        let x = (0..<10_000).map { Float($0) / 10_000 }
        try TakeFile.write([x], sampleRate: Self.fs, to: url)
        let key = LatencyCalibrationKey(inputUID: "sim-in", outputUID: "sim-out", sampleRate: Self.fs, bufferFrames: 512,
                                        inputChannel: 1, outputChannel: 1)
        let take = RecordedTake(songStart: 0, sampleRate: Self.fs, frameCount: x.count, channelCount: 1, latencySamples: 1_200,
                                rigDelaySamples: nil, rigDelayReliable: nil, latencyCalibrated: false, calibrationKey: key, clock: .single)
        let m = LatencyChannelMeasurement(channel: 1, lagsSamples: [2_400.81], latencySamples: 2_400.81, spreadSamples: 0,
                                          peakToFloorDB: 80, inputPeak: 0.25, failure: nil)
        let cal = LatencyCalibrationResult(key: key, date: Date(), guitarIn: [1], channels: [m], reference: nil)
        let fixed = try XCTUnwrap(try TakeAligner.reshift(take, file: url, with: cal))
        let y = try TakeFile.read(url)[0]
        // 2401 − 1200 = 1201 muestras de más al principio: se recortan.
        XCTAssertEqual(fixed.songStart, 0)
        XCTAssertEqual(y.count, x.count - 1_201)
        XCTAssertEqual(y[0], x[1_201])
    }
}
