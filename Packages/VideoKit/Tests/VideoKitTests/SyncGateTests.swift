import AudioKit
import AVFoundation
import XCTest
@testable import VideoKit

/// WAV float32 y lectura del primer canal para los tests.
enum TestWav {
    static func write(_ channels: [[Float]], sampleRate: Double, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels.count,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = channels.first?.count ?? 0
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(65_536))!
        var at = 0
        while at < frames {
            let n = min(65_536, frames - at)
            buf.frameLength = AVAudioFrameCount(n)
            for (c, ch) in channels.enumerated() {
                ch.withUnsafeBufferPointer { buf.floatChannelData![c].update(from: $0.baseAddress! + at, count: n) }
            }
            try file.write(from: buf)
            at += n
        }
    }

    static func readFirst(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        var out: [Float] = []
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65_536)!
        while file.framePosition < file.length {
            try file.read(into: buf)
            if buf.frameLength == 0 { break }
            out.append(contentsOf: UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
        }
        return out
    }

    static func tempDir(_ name: String) throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
}

/// Puerta de la Fase 6 (mini-spec, «Pruebas»): cámara simulada con retardo conocido, jitter de ±2 ms y fotogramas
/// perdidos, sobre el audio simulado de la Fase 3 (`AudioSession` + `SimulatedAudioIO` + `StudyPlayer` alojado).
/// Tres tomas de 60 s (desde el principio, desde mitad de tema y con el audio derivando 50 ppm frente al host) con
/// **el mismo desfase**: cada fotograma cae en su tiempo del tema con error menor de medio fotograma al principio y
/// al final; los perdidos no desplazan a los siguientes; la toma de audio pasa la condición de la Fase 3.
///
/// Verdad: el fotograma `k` se captura de verdad en `trueCaptureHostSeconds(k)`; lo que suena entonces es la
/// muestra de salida de la ley exacta del reloj simulado (`SimulatedAudioIO.outputSample(atHostSeconds:)`) llevada
/// al tema con el ancla del reproductor. El camino que se prueba no conoce esa ley: ajusta el reloj con las marcas
/// de `AudioSession.outputHostClock` y convierte la marca (con retardo y jitter) del fotograma.
final class SyncGateTests: XCTestCase {
    static let fs = 48_000.0
    static let latency = 2_400.81
    static let fps = 30.0
    static let cameraDelay = 0.0423
    static let jitter = 0.002
    static let songSeconds = 130.0
    static let takeSeconds = 60.0

    final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T?
        func set(_ v: T) { lock.withLock { value = v } }
        func get() -> T? { lock.withLock { value } }
    }

    static func makeIO(hostStart: Double, hostDriftPPM: Double) -> SimulatedAudioIO {
        SimulatedAudioIO(sampleRate: fs, inputs: [SimulatedInput(source: 1, noiseDBFS: -60)], latencySamples: latency,
                         declaredLatencySamples: 1_200, initialSampleTime: 31_337, hostStartSeconds: hostStart,
                         hostDriftPPM: hostDriftPPM)
    }

    static func session(_ io: SimulatedAudioIO) -> AudioSession {
        AudioSession(setup: AudioSetup(inputDeviceUID: io.inputDeviceUID, outputDeviceUID: io.outputDeviceUID,
                                       sampleRate: fs, guitarIn: [1]), makeIO: { _ in io })
    }

    @MainActor
    static func calibrate(_ s: AudioSession, _ io: SimulatedAudioIO) async throws -> LatencyCalibrationResult {
        let box = Box<Result<LatencyCalibrationResult, any Error>>()
        Task.detached {
            do { box.set(.success(try await s.calibrateLatency())) } catch { box.set(.failure(error)) }
        }
        var n = 0
        while box.get() == nil {
            io.pump()
            s.flushCapture()
            n += 1
            if n % 32 == 0 { try await Task.sleep(for: .milliseconds(1)) }
            if n > 400_000 { XCTFail("la calibración no acaba"); break }
        }
        return try XCTUnwrap(box.get()).get()
    }

    /// Puente AudioKit → VideoKit (el que hará la app): marcas nuevas de la sesión y ancla del reproductor.
    final class Feeder {
        let session: AudioSession
        let recorder: VideoTakeRecorder
        var last = Int64.min
        init(_ s: AudioSession, _ r: VideoTakeRecorder) { session = s; recorder = r }
        func feed() {
            let points = session.outputHostClock(after: last)
            if let p = points.last { last = p.sampleTime }
            let a = session.playbackAnchor
            recorder.updateMap { m in
                for p in points { m.addClockPoint(outputSample: Double(p.sampleTime), hostSeconds: p.hostSeconds) }
                if let a {
                    m.setAnchor(HostTimeMap.Anchor(songTime: a.songTime, outputSample: a.outputSample, sampleRate: a.sampleRate, rate: a.rate))
                }
            }
        }
    }

    struct TakeResult {
        var name: String
        /// (número de fotograma, PTS escrito, verdad).
        var frames: [(seq: Int, pts: Double, truth: Double)]
        var audio: AlignmentReport
        var camera: SimulatedCameraCapture
        var report: VideoSyncReport
        /// Error que daría suponer la frecuencia nominal (sin ajustar la deriva), máximo en valor absoluto, s.
        var nominalClockDrift: Double
    }

    @MainActor
    func recordTake(name: String, from start: Double, hostStart: Double, driftPPM: Double, calibration: LatencyCalibrationResult,
                    backing: URL, dir: URL) throws -> TakeResult {
        let fs = Self.fs
        let io = Self.makeIO(hostStart: hostStart, hostDriftPPM: driftPPM)
        let s = Self.session(io)
        try s.open()
        defer { s.close() }
        s.calibration = calibration
        XCTAssertTrue(s.isCalibrated, name)
        let player = StudyPlayer(offlineWith: nil)
        try player.load(tracks: [Track(id: "backing", url: backing)])
        try player.attach(to: s)

        // La cámara corre desde antes (vista previa); su reloj de captura no está ligado al del audio.
        let cam = SimulatedCameraCapture(config: .init(delaySeconds: Self.cameraDelay, jitterSeconds: Self.jitter, dropEvery: 37,
                                                       dropFrames: Set(900..<905), seed: UInt64(hostStart)),
                                         originHostSeconds: hostStart + 0.0123)
        let sink = FrameLogSink()
        let rec = VideoTakeRecorder(sink: sink, sampleRate: fs, nominalFPS: Self.fps)
        _ = try cam.start(CameraRequest(width: 1280, height: 720, fps: Self.fps)) { rec.handle($0) }
        let feeder = Feeder(s, rec)
        func step() {
            io.pump()
            s.flushCapture()
            cam.advance(toHostSeconds: io.hostSeconds(atOutputSample: Double(io.sampleTime)))
        }
        for _ in 0..<20 { step() }                           // cámara sin reproductor: sin ancla
        player.seek(to: start)
        try player.play()
        step()
        feeder.feed()
        let anchor = try XCTUnwrap(s.playbackAnchor, name)
        let url = dir.appendingPathComponent("\(name).wav")
        try s.startRecording(to: url)
        let begin = io.sampleTime
        var blocks = 0
        while io.sampleTime - begin < Int64(Self.takeSeconds * fs) {
            step()
            blocks += 1
            if blocks % 8 == 0 { feeder.feed() }             // la app consulta cada pocos ms
        }
        feeder.feed()
        let take = try s.stopRecording()
        cam.stop()
        XCTAssertEqual(s.playbackAnchor, anchor, "el ancla no cambió durante la toma")
        player.pause()
        player.detach()

        let truthOf: (Int) -> Double = { k in
            anchor.songFrame(atOutputSample: io.outputSample(atHostSeconds: cam.trueCaptureHostSeconds(ofFrame: k))) / fs
        }
        let frames = sink.entries.map { (seq: $0.sequence, pts: $0.songTime, truth: truthOf($0.sequence)) }
        // Lo mismo con la frecuencia nominal y la primera marca (sin ajuste de deriva), para comparar.
        var nominal = HostTimeMap(sampleRate: fs)
        let firstPoint = try XCTUnwrap(s.outputHostClock().first)
        nominal.addClockPoint(outputSample: Double(firstPoint.sampleTime), hostSeconds: firstPoint.hostSeconds)
        nominal.setAnchor(rec.map.anchors[0])
        let fitted = rec.map
        var drift = 0.0
        for f in frames {
            let h = cam.stampHostSeconds(ofFrame: f.seq)
            drift = max(drift, abs((nominal.songTime(atHostSeconds: h) ?? 0) - (fitted.songTime(atHostSeconds: h) ?? 0)))
        }
        let audio = AlignmentCheck.measure(take: try TestWav.readFirst(url), songStart: take.songStart, sampleRate: fs,
                                           songSeconds: Self.songSeconds)
        return TakeResult(name: name, frames: frames, audio: audio, camera: cam, report: rec.report(), nominalClockDrift: drift)
    }

    @MainActor
    func testThreeTakesLandWithinHalfAFrameWithTheSameOffset() async throws {
        let fs = Self.fs
        let dir = try TestWav.tempDir("SyncGateTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let backing = dir.appendingPathComponent("backing.wav")
        let x = AlignmentCheck.backing(songSeconds: Self.songSeconds, sampleRate: fs)
        try TestWav.write([x, x], sampleRate: fs, to: backing)

        let calIO = Self.makeIO(hostStart: 500, hostDriftPPM: 0)
        let calSession = Self.session(calIO)
        try calSession.open()
        let cal = try await Self.calibrate(calSession, calIO)
        calSession.close()
        XCTAssertTrue(cal.isValid)

        let takes = [
            try recordTake(name: "desde el principio", from: 0, hostStart: 10_000.25, driftPPM: 0, calibration: cal, backing: backing, dir: dir),
            try recordTake(name: "desde mitad de tema", from: 47.31, hostStart: 52_345.5, driftPPM: 0, calibration: cal, backing: backing, dir: dir),
            try recordTake(name: "audio a +50 ppm", from: 12.5, hostStart: 98_765.125, driftPPM: 50, calibration: cal, backing: backing, dir: dir)
        ]
        // Desfase ajustado a mano en la primera toma (la hoja va de 1 en 1 ms), el mismo para las tres.
        let first = takes[0].frames
        let offset = (first.map { $0.pts - $0.truth }.reduce(0, +) / Double(first.count) * 1000).rounded() / 1000
        print(String(format: "F6 puerta: desfase de la toma 1 = %.3f s (retardo simulado de la cámara %.4f s)", offset, Self.cameraDelay))
        XCTAssertEqual(offset, Self.cameraDelay, accuracy: 0.001)

        let halfFrame = 0.5 / Self.fps
        for t in takes {
            let errs = t.frames.map { (song: $0.truth, err: $0.pts - offset - $0.truth) }
            let begin = errs.prefix { $0.song < errs[0].song + 2 }, end = errs.filter { $0.song > errs.last!.song - 2 }
            let maxAll = errs.map { abs($0.err) }.max()!, maxBegin = begin.map { abs($0.err) }.max()!, maxEnd = end.map { abs($0.err) }.max()!
            // Perdidos: el PTS tras un hueco de j fotogramas avanza j periodos (± el jitter de las dos marcas).
            var gaps = 0, gapWorst = 0.0
            for (a, b) in zip(t.frames, t.frames.dropFirst()) where b.seq - a.seq > 1 {
                gaps += 1
                gapWorst = max(gapWorst, abs((b.pts - a.pts) - Double(b.seq - a.seq) / Self.fps))
            }
            let lost = (t.frames.last!.seq - t.frames.first!.seq + 1) - t.frames.count
            print(String(format: "F6 puerta %@: %d fotogramas de %.3f a %.3f s; máx |error| %.3f ms (%.3f fotogramas), principio %.3f ms, final %.3f ms; %d huecos (%d perdidos), máx desvío del PTS tras un hueco %.3f ms; deriva sin ajuste %.3f ms; audio %.3f muestras; jitter medido %.3f ms; audio %.2f ppm",
                         t.name, t.frames.count, t.frames.first!.truth, t.frames.last!.truth, maxAll * 1000, maxAll * Self.fps,
                         maxBegin * 1000, maxEnd * 1000, gaps, lost, gapWorst * 1000, t.nominalClockDrift * 1000,
                         t.audio.maxAbsErrorSamples, (t.report.timing?.jitterMax ?? .nan) * 1000, t.report.audioClockPPM ?? .nan))
            XCTAssertGreaterThan(t.frames.count, Int(Self.takeSeconds * Self.fps * 0.9), t.name)
            XCTAssertLessThan(maxBegin, halfFrame, t.name)
            XCTAssertLessThan(maxEnd, halfFrame, t.name)
            XCTAssertLessThan(maxAll, halfFrame, t.name)
            // Más fino de lo que pide la puerta: jitter de ±2 ms + redondeo del desfase a 1 ms.
            XCTAssertLessThanOrEqual(maxAll, Self.jitter + 0.0005 + 1e-4, t.name)
            XCTAssertGreaterThanOrEqual(gaps, 40, t.name)
            XCTAssertGreaterThanOrEqual(lost, 50, t.name)
            XCTAssertLessThanOrEqual(gapWorst, 2 * Self.jitter + 1e-4, t.name)
            XCTAssertEqual(t.report.timing?.droppedFromGaps, lost, t.name)
            XCTAssertLessThanOrEqual(t.audio.maxAbsErrorSamples, 1, t.name)
            XCTAssertGreaterThanOrEqual(t.audio.clicks.count, 110, t.name)
        }
        XCTAssertEqual(takes[2].report.audioClockPPM ?? 0, 50, accuracy: 0.01)
        XCTAssertGreaterThan(takes[2].nominalClockDrift, 0.0025, "sin ajustar la deriva, 50 ppm en 60 s son ~3 ms")
    }
}
