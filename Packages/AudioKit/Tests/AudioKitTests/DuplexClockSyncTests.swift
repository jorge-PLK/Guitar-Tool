import XCTest
@testable import AudioKit

/// `DuplexClockSync`: la línea común de la E/S WASAPI del paso 7 a partir de marcas QPC con temblor. Lo que importa es
/// que el offset de captura salga igual en cada arranque (si no, la calibración de una sesión no vale para la
/// siguiente y el alineado se va): el error debe quedar muy por debajo de 1 ms (`AlignmentCheck.passThresholdSeconds`).
final class DuplexClockSyncTests: XCTestCase {
    static let fs = 48_000.0
    /// `IAudioClock::GetFrequency` típico en modo compartido: posición en unidades de 100 ns.
    static let clockFrequency: UInt64 = 10_000_000
    static let packet = 480

    /// Generador con semilla (LCG de Knuth), uniforme en [-1, 1).
    struct Jitter {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53) * 2 - 1
        }
    }

    /// Una sesión simulada: el render arranca en `t0`, la captura `captureLag` s después (mismo reloj salvo
    /// `capturePPM`). Marcas con temblor uniforme ±`jitter` s. Devuelve el offset fijado y el verdadero (muestras).
    static func session(seed: UInt64, jitter: Double, captureLag: Double = 0.0371, capturePPM: Double = 0,
                        minimumPoints: Int = DuplexClockSync.defaultMinimumPoints, packets: Int = 150)
        -> (offset: Int64?, truth: Double, sync: DuplexClockSync, sampleTimes: [Int64]) {
        var rng = Jitter(state: seed)
        var sync = DuplexClockSync(sampleRate: fs, minimumPoints: minimumPoints)
        let t0 = 86_400.0 + Double(seed)            // segundos de host grandes, como un QPC tras un día encendido
        let captureRate = fs * (1 + capturePPM * 1e-6)
        var times: [Int64] = []
        for k in 0..<packets {
            let t = t0 + Double(k) * Double(packet) / fs + 0.002
            let renderFrames = (t - t0) * fs
            sync.addRenderClock(position: UInt64((renderFrames * Double(clockFrequency) / fs).rounded()),
                                frequency: clockFrequency, hostSeconds: t + jitter * rng.next())
            let tc = t0 + captureLag + Double(k * packet) / captureRate
            if let st = sync.addCapturePacket(devicePosition: UInt64(k * packet), hostSeconds: tc + jitter * rng.next()) {
                times.append(st)
            }
        }
        return (sync.captureOffset, captureLag * fs, sync, times)
    }

    func testOffsetRepeatsWithinAFewSamplesUnderHalfMillisecondJitter() throws {
        var worst = 0.0
        for seed in 1...50 {
            let s = Self.session(seed: UInt64(seed), jitter: 0.0005)
            let offset = try XCTUnwrap(s.offset, "semilla \(seed)")
            worst = max(worst, abs(Double(offset) - s.truth))
        }
        let worstMs = worst / Self.fs * 1000
        print("DuplexClockSync: peor error del offset en 50 arranques con ±0,5 ms de temblor = \(worst) muestras (\(worstMs) ms)")
        // Tolerancia: una quinta parte de la condición de alineado (1 ms). Medido: 4,8 muestras = 0,10 ms.
        XCTAssertLessThan(worstMs, AlignmentCheck.passThresholdSeconds * 1000 / 5)
    }

    func testSinglePacketEstimateWouldNotBeEnough() throws {
        // Con dos puntos (lo que daría mirar un paquete), el temblor entra entero: por eso la recta.
        var worst = 0.0
        for seed in 1...50 {
            let s = Self.session(seed: UInt64(seed), jitter: 0.0005, minimumPoints: 2)
            worst = max(worst, abs(Double(try XCTUnwrap(s.offset)) - s.truth))
        }
        print("DuplexClockSync: con 2 puntos, peor error = \(worst / Self.fs * 1000) ms")
        XCTAssertGreaterThan(worst / Self.fs, AlignmentCheck.passThresholdSeconds / 10)
    }

    func testCaptureBlocksAreConsecutiveAndOnlyAfterWarmUp() {
        let s = Self.session(seed: 7, jitter: 0.0005)
        XCTAssertEqual(s.sampleTimes.count, 150 - (DuplexClockSync.defaultMinimumPoints - 1))
        for (a, b) in zip(s.sampleTimes, s.sampleTimes.dropFirst()) { XCTAssertEqual(b - a, Int64(Self.packet)) }
    }

    func testRenderHostSecondsFollowTheFittedLine() {
        let s = Self.session(seed: 3, jitter: 0.0005)
        let t0 = 86_400.0 + 3
        let r = s.sync.renderBuffer(framesWritten: 48_000)
        XCTAssertEqual(r.sampleTime, 48_000)
        XCTAssertEqual(r.hostSeconds, t0 + 1, accuracy: 0.0001)
        XCTAssertEqual(s.sync.captureHostSeconds(devicePosition: 0), t0 + 0.0371, accuracy: 0.0001)
    }

    func testDriftBetweenTwoClocksIsReported() throws {
        let s = Self.session(seed: 11, jitter: 0.00005, capturePPM: 80, packets: 3000)
        XCTAssertEqual(try XCTUnwrap(s.sync.driftPPM), 80, accuracy: 5)
        XCTAssertEqual(try XCTUnwrap(Self.session(seed: 11, jitter: 0.00005, packets: 3000).sync.driftPPM), 0, accuracy: 5)
    }

    func testResetCaptureEstimatesAgain() {
        var sync = Self.session(seed: 5, jitter: 0.0001).sync
        XCTAssertNotNil(sync.captureOffset)
        sync.resetCapture()
        XCTAssertNil(sync.captureOffset)
        XCTAssertNil(sync.addCapturePacket(devicePosition: 1_000_000, hostSeconds: 90_000))
    }

    func testQPCPositionIsIn100Nanoseconds() {
        XCTAssertEqual(DuplexClockSync.seconds(qpc100ns: 12_345_678_901), 1_234.567_890_1, accuracy: 1e-9)
        XCTAssertEqual(DuplexClockSync.seconds(qpc100ns: 0), 0)
    }
}
