import XCTest
@testable import AudioKit

/// Calibración de latencia sin hardware (mini-spec Fase 3, «Demostración sin hardware»).
final class LatencyCalibratorTests: XCTestCase {
    /// Línea de tiempo que no empieza en 0, para que nada lo dé por hecho.
    static let t0: Int64 = 987_654

    static func calibrate(_ io: SimulatedAudioIO, guitarIn: [Int] = [1]) throws -> LatencyCalibrationResult {
        let cal = LatencyCalibrator(io: io, backingOutLeft: 1, guitarIn: guitarIn)
        try io.start(render: { cal.render($0) }, capture: { cal.capture($0) })
        while !cal.isComplete { io.pump() }
        io.stop()
        return cal.result()
    }

    func describe(_ m: LatencyChannelMeasurement, _ fs: Double) -> String {
        String(format: "lat %.4f (%.4f ms) disp %.4f muestras, pico/fondo %.1f dB, pico %.3f, fallo %@",
               m.latencySamples, m.latencySamples / fs * 1000, m.spreadSamples, m.peakToFloorDB, m.inputPeak,
               m.failure?.rawValue ?? "ninguno")
    }

    func testRecoversFractionalLatencyWithNoiseAndStrongerLaterEcho() throws {
        let cases: [(Double, Double)] = [(44_100, 2_205.37), (48_000, 2_400.81), (48_000, 1_234.56)]
        for (fs, latency) in cases {
            let echo = SimulatedEcho(delaySamples: 0.012 * fs + 0.3, gain: 1.8)
            let io = SimulatedAudioIO(sampleRate: fs, inputs: [SimulatedInput(source: 1, echoes: [echo], noiseDBFS: -60)],
                                      latencySamples: latency, declaredLatencySamples: 1_000, initialSampleTime: Self.t0)
            let r = try Self.calibrate(io)
            let err = r.latencySamples - latency
            print(String(format: "F3 calibración %.0f Hz, L %.2f: error %+.4f muestras (%+.5f ms); ", fs, latency, err, err / fs * 1000)
                  + describe(r.guitar, fs))
            XCTAssertTrue(r.isValid, "\(fs) \(latency)")
            XCTAssertEqual(r.latencySamples, latency, accuracy: 0.05, "\(fs) \(latency)")
            XCTAssertNil(r.reference)
        }
    }

    func testFailsWithTheRightReason() throws {
        let fs = 48_000.0, latency = 2_400.81
        let noSignal = SimulatedAudioIO(sampleRate: fs, inputs: [SimulatedInput(source: nil, noiseDBFS: -60)],
                                        latencySamples: latency, declaredLatencySamples: 1_000)
        let clipped = SimulatedAudioIO(sampleRate: fs, inputs: [SimulatedInput(source: 1, gain: 8, noiseDBFS: -60)],
                                       latencySamples: latency, declaredLatencySamples: 1_000)
        let drifting = SimulatedAudioIO(sampleRate: fs, inputs: [SimulatedInput(source: 1, noiseDBFS: -60)],
                                        latencySamples: latency, declaredLatencySamples: 1_000, driftPPM: 50)
        for (name, io, expected) in [("sin señal", noSignal, LatencyFailure.noSignal), ("saturada", clipped, .saturated),
                                     ("deriva 50 ppm", drifting, .unstable)] {
            let r = try Self.calibrate(io)
            print("F3 fallo \(name): " + describe(r.guitar, fs))
            XCTAssertFalse(r.isValid, name)
            XCTAssertEqual(r.failure, expected, name)
        }
    }

    func testSaturatedLoopWithinOneSample() throws {
        for (fs, latency) in [(44_100.0, 2_205.37), (48_000.0, 2_400.81)] {
            let io = SimulatedAudioIO(sampleRate: fs, inputs: [SimulatedInput(source: 1, drive: 8, gain: 0.6, noiseDBFS: -60)],
                                      latencySamples: latency, declaredLatencySamples: 1_000, initialSampleTime: Self.t0)
            let r = try Self.calibrate(io)
            let err = r.latencySamples - latency
            print(String(format: "F3 vuelta saturada %.0f Hz: error %+.4f muestras (%+.5f ms); ", fs, err, err / fs * 1000)
                  + describe(r.guitar, fs))
            XCTAssertTrue(r.isValid)
            XCTAssertEqual(r.latencySamples, latency, accuracy: 1)
        }
    }

    func testPicksTheChannelThatArrivesBeforeGuitarInAsReference() throws {
        let fs = 48_000.0, latency = 2_400.81, rig = 151.37
        let guitar = SimulatedInput(source: 1, extraDelaySamples: rig, drive: 3, gain: 0.5, noiseDBFS: -60)
        let io = SimulatedAudioIO(sampleRate: fs, inputs: [guitar, guitar, SimulatedInput(source: 1, noiseDBFS: -60),
                                                           SimulatedInput(source: nil, noiseDBFS: -60)],
                                  latencySamples: latency, declaredLatencySamples: 1_000, initialSampleTime: Self.t0)
        let r = try Self.calibrate(io, guitarIn: [1, 2])
        let refErr = (r.reference?.latencySamples ?? .nan) - latency
        print(String(format: "F3 referencia: canal %d, error %+.4f muestras; guitarIn error %+.4f; rig en calibración %.4f",
                     r.reference?.channel ?? 0, refErr, r.latencySamples - latency - rig, r.rigDelayAtCalibration ?? .nan))
        XCTAssertTrue(r.isValid)
        XCTAssertEqual(r.reference?.channel, 3)
        XCTAssertEqual(refErr, 0, accuracy: 0.05)
        XCTAssertEqual(r.latencySamples, latency + rig, accuracy: 1)
        XCTAssertEqual(r.channels[3].failure, .noSignal)

        // Sin canal que llegue antes (uno llega a la vez que guitarIn, otro sin señal): ninguna referencia.
        let flat = SimulatedAudioIO(sampleRate: fs, inputs: [SimulatedInput(source: 1, noiseDBFS: -60),
                                                             SimulatedInput(source: 1, noiseDBFS: -60),
                                                             SimulatedInput(source: nil, noiseDBFS: -60)],
                                    latencySamples: latency, declaredLatencySamples: 1_000)
        let s = try Self.calibrate(flat)
        XCTAssertTrue(s.isValid)
        XCTAssertNil(s.reference)
    }

    func testCalibrateOnAFreeRunningSession() async throws {
        let fs = 48_000.0, latency = 2_400.81
        let io = SimulatedAudioIO(sampleRate: fs, inputs: [SimulatedInput(source: 1, noiseDBFS: -60)], latencySamples: latency,
                                  declaredLatencySamples: 1_000, initialSampleTime: Self.t0, automatic: true)
        let cal = LatencyCalibrator(io: io, backingOutLeft: 1, guitarIn: [1])
        let r = try await cal.calibrate(on: io)
        XCTAssertFalse(io.isRunning)
        XCTAssertTrue(r.isValid)
        XCTAssertEqual(r.latencySamples, latency, accuracy: 0.05)
        XCTAssertEqual(r.key, LatencyCalibrationKey(inputUID: "sim-in", outputUID: "sim-out", sampleRate: fs, bufferFrames: 512,
                                                    inputChannel: 1, outputChannel: 1))
    }
}
