import XCTest
@testable import AudioKit

/// Retardo del Varispeed por frecuencia, pista de toma y reproductor alojado en una sesión de `AudioIO`
/// (mini-spec Fase 3, «Alineado con el backing» 1 y «A/B dentro de la mezcla»). `kind`: el motor de la plataforma;
/// el portátil en `PortablePlayerHostingTests` (solo Mac). En el portátil el retardo de modelo a velocidad 1 es 0.
class PlayerHostingTests: XCTestCase {
    var kind: PlayerKind { .platform }

    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("PlayerHostingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Retardo del Varispeed (en bypass, velocidad 1) medido con un impulso a 44,1, 48 y 96 kHz: el modelo
    /// del ancla (`TimePitchSetting.varispeedDelayFrames`) debe acertar a la muestra en todas.
    @MainActor
    func testVarispeedDelayIsModelledAtEachSampleRate() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        for fs in [44_100.0, 48_000.0, 96_000.0] {
            var x = [Float](repeating: 0, count: Int(fs))
            let at = Int(0.25 * fs)
            x[at] = 0.5
            let url = dir.appendingPathComponent("imp\(Int(fs)).wav")
            try TakeFile.write([x, x], sampleRate: fs, to: url)
            let p = kind.offline()
            try p.load(tracks: [Track(id: "imp", url: url)])
            try p.play()
            let r = try p.renderOffline(frames: Int(0.5 * fs))
            let out = r.channels[0]
            let peak = out.indices.max { abs(out[$0]) < abs(out[$1]) }!
            let measured = Double(peak) - (p.runStartFrame - Double(r.start)) - Double(at)
            print(String(format: "F3 Varispeed a %.1f kHz: retardo medido %.0f muestras, modelo %.0f, pico %.4f",
                         fs / 1000, measured, p.modelLatencyFrames, out[peak]))
            XCTAssertEqual(measured, p.modelLatencyFrames, accuracy: 0.5, "\(fs)")
            XCTAssertEqual(out[peak], 0.5, accuracy: 1e-4, "\(fs)")
        }
    }

    // MARK: Pista de toma

    /// Posición (muestras, con decimales) de la ráfaga alrededor de `c` en `x`: envolvente de la correlación,
    /// lóbulo central de |real| y sinc. nil si no hay señal.
    static func burstPosition(_ x: [Float], around c: Double, half w: Int, fs: Double) -> (Double, Double)? {
        let b = AlignmentCheck.burst(sampleRate: fs)
        let s = Int(c) - w - b.count / 2
        guard s >= 0, s + 2 * w + b.count <= x.count else { return nil }
        let (real, env) = SignalMath.analyticCorrelation(signal: Array(x[s..<(s + 2 * w + b.count)]), template: b)
        var k = 0
        for i in 0...(2 * w) where env[i] > env[k] { k = i }
        guard env[k] > 1e-6 else { return nil }
        var m = k
        for i in max(0, k - 8)...min(2 * w, k + 8) where abs(real[i]) > abs(real[m]) { m = i }
        return (Double(s) + SignalMath.refinePeak(real, near: m) + Double(b.count / 2), env[k])
    }

    /// La toma («Tú») es el backing desde `songStart` (7,3 s, fuera de la rejilla de trozos). Se toca dos
    /// veces, una con la toma muda y otra con el backing mudo, y cada clic de la toma debe salir en la muestra
    /// del mismo clic del backing: a 100 % desde 5 s (antes de la toma: relleno de silencio), y a 80 % y 125 %
    /// desde 9,13 s (dentro de la toma). Fuera del 100 % se arranca dentro de la toma porque el TimePitch
    /// (vocoder de fase) arrastra la fase de lo que sonó antes: con historias distintas (silencio frente a
    /// clics) el mismo clic sale desplazado unas muestras (medido: 6,5 a 80 %, 4,2 a 125 %), sin que la
    /// programación tenga nada que ver. También con su ganancia propia.
    @MainActor
    func testTakeTrackClicksLandOnBackingClicksAtAnyRate() throws {
        let fs = 48_000.0
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let song = 40.0, takeStart = 7.3, takeSeconds = 20.0
        let x = AlignmentCheck.backing(songSeconds: song, sampleRate: fs)
        let backing = dir.appendingPathComponent("backing.wav")
        try TakeFile.write([x, x], sampleRate: fs, to: backing)
        let a = Int(takeStart * fs)
        let takeURL = dir.appendingPathComponent("take.wav")
        try TakeFile.write([Array(x[a..<(a + Int(takeSeconds * fs))])], sampleRate: fs, to: takeURL)

        for rate in [1.0, 0.8, 1.25] {
            let from = rate == 1 ? 5.0 : 9.13
            func render(muteBacking: Bool, takeGain: Double = 0) throws -> (out: [Float], run: Double, latency: Double) {
                let p = kind.offline()
                try p.load(tracks: [Track(id: "backing", url: backing)])
                try p.setTake(TakeTrack(id: "Tú", url: takeURL, songStart: takeStart, gainDB: takeGain, muted: !muteBacking))
                XCTAssertEqual(p.tracks.map(\.id), ["backing", "Tú"])
                p.setMute("backing", muteBacking)
                p.rate = rate
                p.seek(to: from)
                try p.play()
                let r = try p.renderOffline(frames: Int((takeStart - from + takeSeconds + 1) * fs / rate))
                return (r.channels[0], p.runStartFrame - Double(r.start), p.modelLatencyFrames)
            }
            let bk = try render(muteBacking: false)
            let tk = try render(muteBacking: true)
            var worst = 0.0, n = 0
            for c in AlignmentCheck.clickTimes(songSeconds: song) where c > takeStart + 0.4 && c < takeStart + takeSeconds - 0.4 {
                let expected = bk.run + bk.latency + (c - from) * fs / rate
                guard let pb = Self.burstPosition(bk.out, around: expected, half: 2_400, fs: fs),
                      let pt = Self.burstPosition(tk.out, around: expected, half: 2_400, fs: fs) else { continue }
                worst = max(worst, abs(pt.0 - pb.0))
                n += 1
            }
            print(String(format: "F3 pista de toma a %.0f %%: %d clics, máx |toma − backing| %.4f muestras", rate * 100, n, worst))
            XCTAssertGreaterThanOrEqual(n, 35, "\(rate)")
            XCTAssertLessThanOrEqual(worst, 1, "\(rate)")
        }

        // Ganancia propia: −6 dB en la toma.
        let p = kind.offline()
        try p.load(tracks: [Track(id: "backing", url: backing)])
        try p.setTake(TakeTrack(id: "Tú", url: takeURL, songStart: takeStart, gainDB: -6))
        p.setMute("backing", true)
        p.seek(to: 10)
        try p.play()
        let r = try p.renderOffline(frames: Int(2 * fs))
        let peak = r.channels[0].map { abs($0) }.max() ?? 0
        print(String(format: "F3 pista de toma a −6 dB: pico %.4f (esperado %.4f)", peak, 0.5 * pow(10, -6.0 / 20)))
        XCTAssertEqual(Double(peak), 0.5 * pow(10, -6.0 / 20), accuracy: 0.01)
        XCTAssertEqual(p.take?.gainDB, -6)
        try p.setTake(nil)
        XCTAssertEqual(p.tracks.map(\.id), ["backing"])
    }

    // MARK: Alojado en tiempo real

    /// Resultado de una pasada alojada en tiempo real.
    struct HostedRun {
        var report: AlignmentReport
        var take: RecordedTake
        var dropped: Int
        var underruns: Int
        var anchorMatches: Bool
    }

    /// Sesión simulada a `fs` con bloques de `bufferFrames` y el `StudyPlayer` en `manualRenderingMode(.realtime)`
    /// alojado en ella (el modo de la app). Un hilo hace de HAL: bombea bloques a `speed` veces el ritmo real.
    /// Calibra, toca desde `from`, graba `seconds` y mide los clics de la toma contra el backing.
    @MainActor
    func hostedRealtimeRun(fs: Double, bufferFrames: Int, song: Double, from: Double, seconds: Double, speed: Double,
                           in dir: URL) async throws -> HostedRun {
        let backing = try AudioSessionTests.writeBacking(seconds: song, fs: fs, in: dir)
        let io = AudioSessionTests.rigIO(fs, bufferFrames: bufferFrames)
        let s = AudioSessionTests.session(io, guitarIn: [1])
        try s.open()
        defer { s.close() }
        let cal = try await AudioSessionTests.calibrate(s, io)
        XCTAssertTrue(cal.isValid)

        let player = kind.realtime(devices: SimulatedDeviceProvider(devices: [], defaultID: nil))
        try player.load(tracks: [backing])
        try player.attach(to: s)
        XCTAssertTrue(player.isHosted)
        // Hilo de E/S simulado.
        let stop = Box<Bool>()
        let pump = Thread {
            let period = Double(io.format.bufferFrames) / fs / speed
            var next = Date()
            while stop.get() != true {
                io.pump()
                next = next.addingTimeInterval(period)
                let wait = next.timeIntervalSinceNow
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            }
        }
        pump.start()
        defer { stop.set(true) }
        player.seek(to: from)
        try player.play()
        var anchor: PlaybackAnchor?
        for _ in 0..<200 where anchor == nil {
            try await Task.sleep(for: .milliseconds(5))
            anchor = s.playbackAnchor
        }
        XCTAssertNotNil(anchor)
        let matches = player.playbackAnchor == anchor
        let url = dir.appendingPathComponent("processed.wav")
        try s.startRecording(to: url)
        try await Task.sleep(for: .seconds(seconds / speed))
        let take = try s.stopRecording()
        stop.set(true)
        player.pause()
        let underruns = player.feedUnderrunFrames
        player.detach()
        XCTAssertFalse(player.isHosted)
        let x = try TakeFile.read(url)
        let r = AlignmentCheck.measure(take: x[0], songStart: take.songStart, sampleRate: fs, songSeconds: song)
        return HostedRun(report: r, take: take, dropped: s.droppedFrames, underruns: underruns, anchorMatches: matches)
    }

    /// El motor en `manualRenderingMode(.realtime)` (el de la app) alojado en una sesión simulada que avanza a
    /// ritmo de tiempo real desde otro hilo, como el HAL: la toma alineada cae a ≤ 1 muestra a 44,1 y 48 kHz
    /// con bloques de 256, 512 y 1024. Comprueba el arranque de pasada (`activate` + `StemFeed.start`), el
    /// retardo del TimePitch en tiempo real (4096 muestras, sumado al ancla) y el ancla en la línea de la sesión.
    @MainActor
    func testRealtimeHostedPlayerAtRealTimePace() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        for fs in [44_100.0, 48_000.0] {
            for b in [256, 512, 1_024] {
                let run = try await hostedRealtimeRun(fs: fs, bufferFrames: b, song: 30, from: 2.2, seconds: 6, speed: 1, in: dir)
                let r = run.report
                print(String(format: "F3 alojado en tiempo real %.1f kHz, bloque %d: songStart %.4f s, %d/%d clics, máx |error| %.4f muestras (%.5f ms), perdidas %d, vacíos %d",
                             fs / 1000, b, run.take.songStart, r.clicks.count, r.expectedClicks, r.maxAbsErrorSamples,
                             r.maxAbsErrorMs, run.dropped, run.underruns))
                let name = "\(fs) \(b)"
                XCTAssertTrue(run.anchorMatches, name)
                XCTAssertGreaterThanOrEqual(r.clicks.count, 10, name)
                XCTAssertLessThanOrEqual(r.maxAbsErrorSamples, 1, name)
                XCTAssertEqual(run.dropped, 0, name)
                XCTAssertEqual(run.underruns, 0, name)
            }
        }
    }

    /// Condición de paso de la Fase 3 con el reproductor alojado en `manualRenderingMode(.realtime)`: calibrar,
    /// grabar 60 s y que cada clic de la toma caiga a ≤ 1 muestra del backing, desde 0 s y desde mitad de tema,
    /// a 44,1 y 48 kHz. El hilo de E/S va a 5× el ritmo real (el programador rellena cada 20 ms y lleva 0,5 s
    /// de cola: sobra) para que el test no dure 4 minutos; los vacíos de las fuentes se comprueban a 0.
    @MainActor
    func testRealtimeHostedPassConditionFromStartAndMidSong() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Tema más largo que desde-mitad + 60 s + margen: al acabarse el tema la fuente se queda sin búferes y
        // eso contaría como vacío.
        let song = 125.0
        for fs in [44_100.0, 48_000.0] {
            for from in [0.0, 47.31] {
                let run = try await hostedRealtimeRun(fs: fs, bufferFrames: 512, song: song, from: from, seconds: 60, speed: 5,
                                                      in: dir)
                let r = run.report
                let name = String(format: "alojado tiempo real %.1f kHz desde %.2f s", fs / 1000, from)
                print(String(format: "F3 %@: %d/%d clics, máx |error| %.4f muestras (%.5f ms), pendiente %+.4f muestras/min, perdidas %d, vacíos %d",
                             name, r.clicks.count, r.expectedClicks, r.maxAbsErrorSamples, r.maxAbsErrorMs,
                             r.slopeSamplesPerMinute, run.dropped, run.underruns))
                XCTAssertTrue(run.take.latencyCalibrated, name)
                // La grabación empieza al haber ancla (unos milisegundos de reloj, ×5 en tiempo de canción).
                XCTAssertGreaterThanOrEqual(run.take.songStart, from, name)
                XCTAssertLessThan(run.take.songStart, from + 2, name)
                XCTAssertEqual(Double(run.take.frameCount) / fs, 60, accuracy: 2, name)
                XCTAssertTrue(run.anchorMatches, name)
                XCTAssertGreaterThanOrEqual(r.clicks.count, 110, name)
                XCTAssertLessThanOrEqual(r.maxAbsErrorSamples, 1, name)
                XCTAssertTrue(r.passes, name)
                XCTAssertEqual(run.dropped, 0, name)
                XCTAssertEqual(run.underruns, 0, name)
            }
        }
    }

    final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T?
        func set(_ v: T) { lock.withLock { value = v } }
        func get() -> T? { lock.withLock { value } }
    }
}

#if canImport(AVFoundation)
/// Los mismos casos con el motor portátil (el de Windows) en el Mac.
final class PortablePlayerHostingTests: PlayerHostingTests {
    override var kind: PlayerKind { .portable }
}
#endif
