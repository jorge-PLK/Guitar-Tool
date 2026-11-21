import AudioKit
import Foundation
import XCTest
@testable import VideoKit

/// Sincronía de vídeo sin piezas del paso 7 (plan, «Fase 7c», paso 6): corre igual en el Mac y en Windows.
///
/// - El reloj de host de VideoKit es el de NativePlatform y, en el Mac, da bit a bit lo mismo que la cuenta con
///   `mach_timebase_info` que había aquí; en las dos plataformas son segundos.
/// - El camino de la puerta de la Fase 6 (`SyncGateTests`, que en Windows salta por `StudyPlayer`) sin el
///   reproductor: marcas del reloj de `AudioSession` + `SimulatedAudioIO`, un ancla puesta a mano, cámara simulada con
///   retardo, jitter de ±2 ms y perdidos, `VideoTakeRecorder` con `HostTimeMap`. Mismas tolerancias que la puerta.
final class SyncPortableTests: XCTestCase {
    static let fs = 48_000.0
    static let fps = 30.0
    /// Retardo y jitter de la cámara simulada (los de `SyncGateTests`, mini-spec Fase 6, «Pruebas»).
    static let cameraDelay = 0.0423
    static let jitter = 0.002
    static let takeSeconds = 60.0
    /// Paso del desfase manual (la hoja va de 1 en 1 ms).
    static let offsetStep = 0.001

    // MARK: Reloj

    func testHostClockIsTheNativePlatformClock() throws {
        #if canImport(Darwin)
        // Regla del Mac (cero cambio): la cuenta de antes, con `mach_timebase_info`, frente a la de ahora.
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let old = Double(tb.numer) / Double(max(1, tb.denom))
        for t: UInt64 in [0, 1, 12_345, mach_absolute_time(), 1 << 52, UInt64.max / 3] {
            XCTAssertEqual(HostClock.seconds(ticks: t), Double(t) * old / 1e9, "ticks \(t)")
        }
        for s in [0, 1.5, 86_400.123, 1e6] {
            XCTAssertEqual(HostClock.ticks(seconds: s), UInt64((s * 1e9 / old).rounded()), "segundos \(s)")
        }
        XCTAssertEqual(HostClock.timebase, old)
        XCTAssertEqual(HostClock.nowSeconds, Double(mach_absolute_time()) * old / 1e9, accuracy: 0.01)
        #endif
        // Las dos plataformas: ida y vuelta y unidad de segundos (50 ms de reposo).
        for s in [0.25, 1234.5, 98_765.125] {
            XCTAssertEqual(HostClock.seconds(ticks: HostClock.ticks(seconds: s)), s, accuracy: HostClock.seconds(ticks: 1) + 1e-9)
        }
        let a = HostClock.nowSeconds
        Thread.sleep(forTimeInterval: 0.050)
        let b = HostClock.nowSeconds
        print(String(format: "6.9 reloj: base %.6f ns/tick, reposo de 50 ms medido %.3f ms", HostClock.timebase, (b - a) * 1000))
        XCTAssertGreaterThan(a, 0)
        XCTAssertGreaterThanOrEqual(b - a, 0.045)
        XCTAssertLessThan(b - a, 0.5)
    }

    /// Rejilla de fotogramas sin CoreMedia: los mismos ticks que `frameTime(fps:)` (el de la composición).
    func testFrameTicksMatchTheCompositionFrame() {
        let rates = [24, 25, 29.97, 30, 59.94, 60, 0.5, 120]
        for fps in rates {
            let f = MontagePlan.frameTicks(fps: fps)
            XCTAssertEqual(f.timescale, 90_000)
            #if canImport(CoreMedia)
            let cm = MontagePlan.frameTime(fps: fps)
            XCTAssertEqual(f.value, cm.value, "\(fps) fps")
            XCTAssertEqual(f.timescale, cm.timescale, "\(fps) fps")
            #endif
        }
        XCTAssertEqual(MontagePlan.frameTicks(fps: 30).value, 3000)
        XCTAssertEqual(MontagePlan.frameTicks(fps: 29.97).value, 3003)
    }

    // MARK: Toma simulada sin reproductor

    struct Take {
        var name: String
        var frames: [(seq: Int, pts: Double, truth: Double)]
        var report: VideoSyncReport
    }

    @MainActor
    func recordTake(name: String, from start: Double, hostStart: Double, driftPPM: Double) throws -> Take {
        let fs = Self.fs
        let io = SimulatedAudioIO(sampleRate: fs, inputs: [SimulatedInput(source: 1, noiseDBFS: -60)], latencySamples: 2_400.81,
                                  declaredLatencySamples: 1_200, initialSampleTime: 31_337, hostStartSeconds: hostStart,
                                  hostDriftPPM: driftPPM)
        let s = AudioSession(setup: AudioSetup(inputDeviceUID: io.inputDeviceUID, outputDeviceUID: io.outputDeviceUID,
                                               sampleRate: fs, guitarIn: [1]), makeIO: { _ in io })
        try s.open()
        defer { s.close() }
        let cam = SimulatedCameraCapture(config: .init(delaySeconds: Self.cameraDelay, jitterSeconds: Self.jitter, dropEvery: 37,
                                                       dropFrames: Set(900..<905), seed: UInt64(hostStart)),
                                         originHostSeconds: hostStart + 0.0123)
        let sink = FrameLogSink()
        let rec = VideoTakeRecorder(sink: sink, sampleRate: fs, nominalFPS: Self.fps)
        _ = try cam.start(CameraRequest(width: 1280, height: 720, fps: Self.fps)) { rec.handle($0) }
        var last = Int64.min
        func feed() {
            let points = s.outputHostClock(after: last)
            if let p = points.last { last = p.sampleTime }
            rec.updateMap { m in
                for p in points { m.addClockPoint(outputSample: Double(p.sampleTime), hostSeconds: p.hostSeconds) }
            }
        }
        func step() {
            io.pump()
            s.flushCapture()
            cam.advance(toHostSeconds: io.hostSeconds(atOutputSample: Double(io.sampleTime)))
        }
        for _ in 0..<20 { step() }                           // cámara sin ancla: nada se escribe
        feed()
        // Ancla puesta a mano (lo que haría el reproductor): `start` suena en una muestra de salida algo adelante.
        let anchor = HostTimeMap.Anchor(songTime: start, outputSample: Double(io.sampleTime) + 1_234.5, sampleRate: fs)
        rec.updateMap { $0.setAnchor(anchor) }
        let begin = io.sampleTime
        var blocks = 0
        while io.sampleTime - begin < Int64(Self.takeSeconds * fs) {
            step()
            blocks += 1
            if blocks % 8 == 0 { feed() }
        }
        feed()
        cam.stop()
        // Verdad: la ley exacta del reloj simulado, sin el ajuste que se prueba.
        let frames = sink.entries.map { e in
            (seq: e.sequence, pts: e.songTime,
             truth: anchor.songTime(atOutputSample: io.outputSample(atHostSeconds: cam.trueCaptureHostSeconds(ofFrame: e.sequence))))
        }
        return Take(name: name, frames: frames, report: rec.report())
    }

    @MainActor
    func testTakesWithoutPlayerLandWithinHalfAFrameWithTheSameOffset() throws {
        let takes = [
            try recordTake(name: "desde el principio", from: 0, hostStart: 10_000.25, driftPPM: 0),
            try recordTake(name: "desde mitad de tema", from: 47.31, hostStart: 52_345.5, driftPPM: 0),
            try recordTake(name: "audio a +50 ppm", from: 12.5, hostStart: 98_765.125, driftPPM: 50)
        ]
        let first = takes[0].frames
        let offset = (first.map { $0.pts - $0.truth }.reduce(0, +) / Double(first.count) / Self.offsetStep).rounded() * Self.offsetStep
        XCTAssertEqual(offset, Self.cameraDelay, accuracy: Self.offsetStep)
        let halfFrame = 0.5 / Self.fps
        for t in takes {
            XCTAssertGreaterThan(t.frames.count, Int(Self.takeSeconds * Self.fps * 0.9), t.name)
            guard t.frames.count > 1 else { continue }
            let maxAll = t.frames.map { abs($0.pts - offset - $0.truth) }.max()!
            var gaps = 0, gapWorst = 0.0
            for (a, b) in zip(t.frames, t.frames.dropFirst()) where b.seq - a.seq > 1 {
                gaps += 1
                gapWorst = max(gapWorst, abs((b.pts - a.pts) - Double(b.seq - a.seq) / Self.fps))
            }
            let lost = (t.frames.last!.seq - t.frames.first!.seq + 1) - t.frames.count
            print(String(format: "6.9 sincronía %@: %d fotogramas, desfase %.3f s, máx |error| %.3f ms (%.3f fotogramas), %d huecos (%d perdidos), máx desvío tras hueco %.3f ms, audio %.3f ppm",
                         t.name, t.frames.count, offset, maxAll * 1000, maxAll * Self.fps, gaps, lost, gapWorst * 1000,
                         t.report.audioClockPPM ?? .nan))
            XCTAssertLessThan(maxAll, halfFrame, t.name)
            // Jitter de ±2 ms + redondeo del desfase a 1 ms (como la puerta).
            XCTAssertLessThanOrEqual(maxAll, Self.jitter + Self.offsetStep / 2 + 1e-4, t.name)
            XCTAssertGreaterThanOrEqual(gaps, 40, t.name)
            XCTAssertLessThanOrEqual(gapWorst, 2 * Self.jitter + 1e-4, t.name)
            XCTAssertEqual(t.report.timing?.droppedFromGaps, lost, t.name)
        }
        XCTAssertEqual(takes[2].report.audioClockPPM ?? 0, 50, accuracy: 0.01)
    }
}
