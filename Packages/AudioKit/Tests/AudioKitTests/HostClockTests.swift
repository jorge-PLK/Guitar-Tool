import XCTest
@testable import AudioKit

/// Instante de host de las muestras (mini-spec Fase 6, «Cámara y sincronía»).
final class HostClockTests: XCTestCase {
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var out: [(Int64, Int, Double)] = []
        private var inp: [(Int64, Int, Double)] = []
        func addOut(_ b: AudioIOBuffer) { lock.withLock { out.append((b.sampleTime, b.frameCount, b.hostSeconds)) } }
        func addIn(_ b: AudioIOBuffer) { lock.withLock { inp.append((b.sampleTime, b.frameCount, b.hostSeconds)) } }
        var outputs: [(Int64, Int, Double)] { lock.withLock { out } }
        var inputs: [(Int64, Int, Double)] { lock.withLock { inp } }
    }

    /// `SimulatedAudioIO` marca cada bloque con la hora de host de su reloj simulado, con la deriva del dispositivo
    /// frente al host (50 ppm) y la de la entrada frente a la salida (20 ppm). Error ≤ 1 ns frente a la ley exacta.
    func testSimulatedHostTimesFollowTheClockLawWithDrift() throws {
        for fs in [44_100.0, 48_000.0] {
            let io = SimulatedAudioIO(sampleRate: fs, inputs: [SimulatedInput(source: 1)], latencySamples: 2_000.3,
                                      declaredLatencySamples: 1_000, driftPPM: 20, initialSampleTime: 7_777,
                                      hostStartSeconds: 123_456.789, hostDriftPPM: 50)
            let log = Log()
            try io.start(render: { log.addOut($0) }, capture: { log.addIn($0) })
            for _ in 0..<(Int(60 * fs) / 512) { io.pump() }
            io.stop()
            let rate = fs * (1 + 50e-6)
            var worstOut = 0.0, worstIn = 0.0
            for (t, _, h) in log.outputs {
                worstOut = max(worstOut, abs(h - (123_456.789 + Double(t - 7_777) / rate)))
            }
            for (t, _, h) in log.inputs {
                let y = 7_777 + Double(t - 7_777) / (1 + 20e-6)
                worstIn = max(worstIn, abs(h - (123_456.789 + (y - 7_777) / rate)))
            }
            // 60 s de bloques: el reloj de salida avanza 60 s·(1 − 50 ppm) de host por cada 60 s nominales.
            let first = log.outputs.first!, last = log.outputs.last!
            let hostSpan = last.2 - first.2, nominal = Double(last.0 - first.0) / fs
            let ppm = (nominal / hostSpan - 1) * 1e6
            print(String(format: "F6 reloj simulado a %.0f Hz: máx |error| salida %.2e s, entrada %.2e s; deriva medida %.3f ppm",
                         fs, worstOut, worstIn, ppm))
            XCTAssertLessThanOrEqual(worstOut, 1e-9)
            XCTAssertLessThanOrEqual(worstIn, 1e-9)
            XCTAssertEqual(ppm, 50, accuracy: 0.01)
            XCTAssertEqual(io.outputSample(atHostSeconds: io.hostSeconds(atOutputSample: 1_234_567.25)), 1_234_567.25, accuracy: 1e-6)
        }
    }

    /// La sesión publica la hora de host de cada ciclo de salida (`outputHostClock`) y la de entrada llega a
    /// quien vacía el búfer circular.
    func testSessionPublishesOutputHostClock() throws {
        let fs = 48_000.0
        let io = SimulatedAudioIO(sampleRate: fs, inputs: [SimulatedInput(source: 1), SimulatedInput(source: 2)],
                                  latencySamples: 2_400, declaredLatencySamples: 1_200, initialSampleTime: 500,
                                  hostStartSeconds: 5_000, hostDriftPPM: -30)
        let s = AudioSession(setup: AudioSetup(inputDeviceUID: io.inputDeviceUID, outputDeviceUID: io.outputDeviceUID,
                                               sampleRate: fs, guitarIn: [1]),
                             makeIO: { _ in io })
        try s.open()
        defer { s.close() }
        for _ in 0..<100 { io.pump() }
        let all = s.outputHostClock()
        XCTAssertEqual(all.count, 100)
        for p in all {
            XCTAssertEqual(p.hostSeconds, io.hostSeconds(atOutputSample: Double(p.sampleTime)), accuracy: 1e-9)
        }
        let later = s.outputHostClock(after: all[49].sampleTime)
        XCTAssertEqual(later.count, 50)
        XCTAssertEqual(later.first, all[50])

        let ring = CaptureRing(channels: 1, capacity: 4_096)
        let p = UnsafeMutablePointer<Float>.allocate(capacity: 16)
        defer { p.deallocate() }
        var ptrs = [p]
        ptrs.withUnsafeMutableBufferPointer { b in
            ring.write(AudioIOBuffer(sampleTime: 10, frameCount: 16, channels: UnsafeBufferPointer(b), hostSeconds: 77.5))
        }
        var got = 0.0
        ring.drain { got = $0.hostSeconds }
        XCTAssertEqual(got, 77.5)
    }
}
