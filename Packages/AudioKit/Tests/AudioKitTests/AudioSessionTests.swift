import AVFoundation
import XCTest
@testable import AudioKit

/// Fachada `AudioSession` con `SimulatedAudioIO` y el `StudyPlayer` alojado (mini-spec Fase 3,
/// «Demostración sin hardware»): calibrar → grabar → toma alineada, sin calibrar → marcada → corregida,
/// desconexión a mitad, niveles y errores.
final class AudioSessionTests: XCTestCase {
    static let declared = 1_200.0
    static let rig = 151.37
    static let t0: Int64 = 987_654

    final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T?
        func set(_ v: T) { lock.withLock { value = v } }
        func get() -> T? { lock.withLock { value } }
    }

    final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [AudioSessionEvent] = []
        func add(_ e: AudioSessionEvent) { lock.withLock { list.append(e) } }
        var all: [AudioSessionEvent] { lock.withLock { list } }
    }

    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("AudioSessionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Latencia con decimales distinta por frecuencia (unos 50 ms, como la Flex Prime).
    static func latency(_ fs: Double) -> Double { fs == 44_100 ? 2_205.37 : 2_400.81 }

    /// Guitarra estéreo con rig saturado y un canal de referencia interno (sin rig).
    static func rigIO(_ fs: Double, driftPPM: Double = 0, bufferFrames: Int = 512) -> SimulatedAudioIO {
        let l = SimulatedInput(source: 1, extraDelaySamples: rig, drive: 2, gain: 0.5, noiseDBFS: -60)
        let r = SimulatedInput(source: 2, extraDelaySamples: rig, drive: 2, gain: 0.5, noiseDBFS: -60)
        return SimulatedAudioIO(sampleRate: fs, inputs: [l, r, SimulatedInput(source: 1, noiseDBFS: -60)],
                                latencySamples: latency(fs), declaredLatencySamples: declared, driftPPM: driftPPM,
                                bufferFrames: bufferFrames, initialSampleTime: t0)
    }

    static func session(_ io: SimulatedAudioIO, guitarIn: [Int]) -> AudioSession {
        AudioSession(setup: AudioSetup(inputDeviceUID: io.inputDeviceUID, outputDeviceUID: io.outputDeviceUID,
                                       sampleRate: io.format.sampleRate, guitarIn: guitarIn),
                     makeIO: { _ in io })
    }

    static func writeBacking(seconds: Double, fs: Double, in dir: URL) throws -> Track {
        let x = AlignmentCheck.backing(songSeconds: seconds, sampleRate: fs)
        let url = dir.appendingPathComponent("backing-\(Int(fs)).wav")
        try TakeFile.write([x, x], sampleRate: fs, to: url)
        return Track(id: "backing", url: url)
    }

    /// Calibra por la fachada conduciendo el simulador a mano desde el actor principal.
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

    /// Toca el backing alojado en la sesión desde `start` y graba `seconds` (o hasta `disconnectAfter`, que
    /// desconecta el simulador). Devuelve la toma y lo escrito.
    @MainActor
    static func playAndRecord(_ s: AudioSession, _ io: SimulatedAudioIO, backing: Track, from start: Double, seconds: Double,
                              url: URL, disconnectAfter: Double? = nil, rate: Double = 1) throws -> (RecordedTake, [[Float]], StudyPlayer) {
        let fs = io.format.sampleRate
        let player = StudyPlayer(offlineWith: nil)
        try player.load(tracks: [backing])
        try player.attach(to: s)
        player.rate = rate
        player.seek(to: start)
        try player.play()
        io.pump()
        s.flushCapture()
        try s.startRecording(to: url)
        let begin = io.sampleTime
        let stopAt = Int64((disconnectAfter ?? seconds) * fs)
        while io.sampleTime - begin < stopAt {
            io.pump()
            s.flushCapture()
        }
        if disconnectAfter != nil { io.disconnect() }
        let take = try s.stopRecording()
        player.pause()
        return (take, try TakeFile.read(url), player)
    }

    func check(_ name: String, _ r: AlignmentReport, minClicks: Int = 110, file: StaticString = #filePath, line: UInt = #line) {
        let head = r.clicks.prefix(10).map { abs($0.errorSamples) }.max() ?? .nan
        let tail = r.clicks.suffix(10).map { abs($0.errorSamples) }.max() ?? .nan
        print(String(format: "F3 %@: %d/%d clics, máx |error| %.4f muestras (%.5f ms), primeros 10 %.4f, últimos 10 %.4f, pendiente %+.4f muestras/min",
                     name, r.clicks.count, r.expectedClicks, r.maxAbsErrorSamples, r.maxAbsErrorMs, head, tail, r.slopeSamplesPerMinute))
        XCTAssertGreaterThanOrEqual(r.clicks.count, minClicks, name, file: file, line: line)
        XCTAssertLessThanOrEqual(r.maxAbsErrorSamples, 1, name, file: file, line: line)
        XCTAssertTrue(r.passes, name, file: file, line: line)
    }

    // MARK: Condición de paso por la fachada, a 44,1 y 48 kHz

    @MainActor
    func testCalibrateRecordAlignedWithinOneSampleAt44_1And48() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        for fs in [44_100.0, 48_000.0] {
            let io = Self.rigIO(fs)
            let s = Self.session(io, guitarIn: [1, 2])
            try s.open()
            defer { s.close() }
            let cal = try await Self.calibrate(s, io)
            print(String(format: "F3 fachada %.1f kHz: calibrada %.4f (real %.4f + rig %.2f), referencia %d con %.4f (error %+.4f muestras)",
                         fs / 1000, cal.latencySamples, Self.latency(fs), Self.rig, cal.reference?.channel ?? 0,
                         cal.reference?.latencySamples ?? .nan, (cal.reference?.latencySamples ?? .nan) - Self.latency(fs)))
            XCTAssertTrue(cal.isValid)
            XCTAssertEqual(cal.reference?.channel, 3)
            XCTAssertTrue(s.isCalibrated)
            XCTAssertEqual(cal.reference?.latencySamples ?? 0, Self.latency(fs), accuracy: 0.05)

            let song = 110.0
            let backing = try Self.writeBacking(seconds: song, fs: fs, in: dir)
            for start in [0.0, 47.31] {
                let url = dir.appendingPathComponent("processed.wav")
                let (take, x, _) = try Self.playAndRecord(s, io, backing: backing, from: start, seconds: 60, url: url)
                XCTAssertTrue(take.latencyCalibrated)
                XCTAssertEqual(take.rigDelayReliable, true)
                XCTAssertEqual(take.rigDelaySamples ?? 0, Self.rig, accuracy: 2)
                XCTAssertEqual(take.sampleRate, fs)
                XCTAssertEqual(take.channelCount, 2)
                XCTAssertEqual(take.songStart, start, accuracy: 0.5 / fs)
                XCTAssertEqual(Double(take.frameCount) / fs, 60, accuracy: 0.1)
                XCTAssertEqual(s.droppedFrames, 0)
                for c in 0..<2 {
                    check(String(format: "fachada %.1f kHz desde %.2f s canal %d", fs / 1000, start, c + 1),
                          AlignmentCheck.measure(take: x[c], songStart: take.songStart, sampleRate: fs, songSeconds: song))
                }
            }
        }
    }

    // MARK: Sin calibrar → marcada → corregida

    @MainActor
    func testUncalibratedTakeIsMarkedAndReshiftedAfterCalibrating() async throws {
        let fs = 48_000.0
        let io = SimulatedAudioIO(sampleRate: fs, inputs: [SimulatedInput(source: 1, drive: 2, gain: 0.5, noiseDBFS: -60)],
                                  latencySamples: Self.latency(fs), declaredLatencySamples: Self.declared, initialSampleTime: Self.t0)
        let other = SimulatedAudioIO(sampleRate: fs, inputs: [SimulatedInput(source: 1, noiseDBFS: -60)],
                                     latencySamples: 3_000.2, declaredLatencySamples: Self.declared, inputDeviceUID: "otra")
        let stale = try LatencyCalibratorTests.calibrate(other)
        XCTAssertTrue(stale.isValid)

        let s = Self.session(io, guitarIn: [1])
        try s.open()
        defer { s.close() }
        s.calibration = stale
        XCTAssertFalse(s.isCalibrated)

        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let song = 80.0
        let backing = try Self.writeBacking(seconds: song, fs: fs, in: dir)
        let url = dir.appendingPathComponent("processed.wav")
        let (take, x, _) = try Self.playAndRecord(s, io, backing: backing, from: 12.5, seconds: 60, url: url)
        XCTAssertFalse(take.latencyCalibrated)
        XCTAssertEqual(take.latencySamples, Self.declared)
        let before = AlignmentCheck.measure(take: x[0], songStart: take.songStart, sampleRate: fs, songSeconds: song)
        print(String(format: "F3 fachada sin calibrar: error medio %.3f muestras (%.3f ms), esperado ≈ %.2f; pasa %@",
                     before.meanErrorSamples, before.meanErrorSamples / fs * 1000, Self.latency(fs) - Self.declared,
                     "\(before.passes)"))
        XCTAssertEqual(before.meanErrorSamples, Self.latency(fs) - Self.declared, accuracy: 1)
        XCTAssertFalse(before.passes)

        let cal = try await Self.calibrate(s, io)
        XCTAssertTrue(s.isCalibrated)
        let fixed = try AudioSession.reshiftUncalibrated([(take, url)], with: cal)
        let t = try XCTUnwrap(fixed.first ?? nil)
        XCTAssertTrue(t.latencyCalibrated)
        XCTAssertNil(try AudioSession.reshiftUncalibrated([(t, url)], with: cal).first ?? nil)
        let y = try TakeFile.read(url)
        check("fachada sin calibrar corregida", AlignmentCheck.measure(take: y[0], songStart: t.songStart, sampleRate: fs, songSeconds: song))
    }

    // MARK: Desconexión a mitad de toma

    @MainActor
    func testDisconnectMidTakeStopsAndSavesWhatWasRecorded() async throws {
        let fs = 48_000.0
        let io = Self.rigIO(fs)
        let s = Self.session(io, guitarIn: [1])
        let events = Events()
        s.setEventHandler { events.add($0) }
        try s.open()
        let cal = try await Self.calibrate(s, io)
        XCTAssertTrue(cal.isValid)

        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let song = 60.0
        let backing = try Self.writeBacking(seconds: song, fs: fs, in: dir)
        let url = dir.appendingPathComponent("processed.wav")
        let (take, x, player) = try Self.playAndRecord(s, io, backing: backing, from: 3, seconds: 60, url: url, disconnectAfter: 20)
        XCTAssertFalse(s.isOpen)
        XCTAssertEqual(s.interruption, .disconnected(io.inputDeviceUID))
        XCTAssertEqual(events.all.first, .recordingSaved(take))
        XCTAssertEqual(events.all.last, .interrupted(.disconnected(io.inputDeviceUID)))
        XCTAssertEqual(Double(take.frameCount) / fs, 20, accuracy: 0.1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        check("toma cortada por desconexión", AlignmentCheck.measure(take: x[0], songStart: take.songStart, sampleRate: fs, songSeconds: song),
              minClicks: 35)
        XCTAssertThrowsError(try s.startRecording(to: url)) {
            XCTAssertEqual($0 as? AudioSessionError, .interrupted(.disconnected(io.inputDeviceUID)))
        }
        // El reproductor vuelve solo a su propia salida.
        for _ in 0..<50 where player.isHosted { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(player.isHosted)
    }

    // MARK: Niveles y errores

    @MainActor
    func testLiveLevelsPerChannelAndGuitarRMSOverThreeSeconds() throws {
        let fs = 48_000.0
        let io = SimulatedAudioIO(sampleRate: fs, inputs: [SimulatedInput(source: nil, noiseDBFS: -30),
                                                           SimulatedInput(source: nil, noiseDBFS: -50)],
                                  latencySamples: 100, declaredLatencySamples: 100)
        let s = Self.session(io, guitarIn: [1])
        try s.open()
        defer { s.close() }
        while io.sampleTime < Int64(4 * fs) {
            io.pump()
            s.flushCapture()
        }
        let meters = s.inputLevels()
        let g = try XCTUnwrap(s.guitarLevelDB())
        print(String(format: "F3 niveles: canal 1 %.2f dB, canal 2 %.2f dB, guitarra 3 s %.3f dB (esperado −30)",
                     meters[0].rmsDB, meters[1].rmsDB, g))
        XCTAssertEqual(meters.count, 2)
        XCTAssertEqual(Double(meters[0].rmsDB), -30, accuracy: 0.5)
        XCTAssertEqual(Double(meters[1].rmsDB), -50, accuracy: 0.5)
        XCTAssertEqual(g, -30, accuracy: 0.1)
    }

    func testClearErrors() throws {
        let fs = 48_000.0
        let io = Self.rigIO(fs)
        // Sin dispositivo de entrada.
        let none = AudioSession(setup: AudioSetup(inputDeviceUID: "", outputDeviceUID: "x", sampleRate: fs), makeIO: { _ in io })
        XCTAssertThrowsError(try none.open()) { XCTAssertEqual($0 as? AudioSessionError, .noInputDevice) }
        // Frecuencia que el dispositivo no acepta.
        let rate = AudioSession(setup: AudioSetup(inputDeviceUID: "a", outputDeviceUID: "a", sampleRate: fs), makeIO: { _ in
            throw AudioIOError.sampleRateMismatch(device: 44_100, requested: 48_000)
        })
        XCTAssertThrowsError(try rate.open()) {
            XCTAssertEqual($0 as? AudioSessionError, .sampleRateMismatch(device: 44_100, working: 48_000))
            XCTAssertEqual(($0 as? AudioSessionError)?.errorDescription,
                           "El dispositivo está a 44,1 kHz y la frecuencia de trabajo es 48 kHz")
        }
        // El simulador a otra frecuencia que la de trabajo.
        let other = AudioSession(setup: AudioSetup(inputDeviceUID: "a", outputDeviceUID: "a", sampleRate: 44_100), makeIO: { _ in io })
        XCTAssertThrowsError(try other.open()) {
            XCTAssertEqual($0 as? AudioSessionError, .sampleRateMismatch(device: 48_000, working: 44_100))
        }
        // Canal de guitarra fuera de rango, y dos papeles en el mismo canal.
        for g in [[5], [1, 1]] {
            let bad = Self.session(io, guitarIn: g)
            XCTAssertThrowsError(try bad.open(), "\(g)") {
                guard case .invalidChannels = $0 as? AudioSessionError else { return XCTFail("\($0)") }
            }
        }
        // Sin guitarra se abre (medidores) pero no se graba ni se calibra.
        let meters = Self.session(io, guitarIn: [])
        try meters.open()
        XCTAssertThrowsError(try meters.startRecording(to: URL(fileURLWithPath: "/dev/null"))) {
            XCTAssertEqual($0 as? AudioSessionError, .noGuitarInput)
        }
        meters.close()
        // Parar sin grabar; grabar con la sesión cerrada.
        let s = Self.session(io, guitarIn: [1])
        XCTAssertThrowsError(try s.stopRecording()) { XCTAssertEqual($0 as? AudioSessionError, .notRecording) }
        XCTAssertThrowsError(try s.startRecording(to: URL(fileURLWithPath: "/dev/null"))) {
            XCTAssertEqual($0 as? AudioSessionError, .notOpen)
        }
        // Grabar sin reproductor ni ancla: falla al parar con un motivo claro.
        try s.open()
        defer { s.close() }
        try s.startRecording(to: FileManager.default.temporaryDirectory.appendingPathComponent("noanchor.wav"))
        for _ in 0..<20 { io.pump() }
        XCTAssertThrowsError(try s.stopRecording()) { XCTAssertEqual($0 as? AudioSessionError, .noPlayback) }
    }
}
