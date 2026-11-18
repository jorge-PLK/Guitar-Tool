import AVFoundation
import XCTest
@testable import AudioKit

/// Señales sintéticas y WAV de prueba (también las usa `MontageMixerTests`).
enum SynthWAV {
    static func sine(_ hz: Double, dB: Double, seconds: Double, rate: Double, phase: Double = 0) -> [Float] {
        let amp = pow(10, dB / 20)
        return (0..<Int(seconds * rate)).map { Float(amp * sin(2 * Double.pi * hz * Double($0) / rate + phase)) }
    }

    /// Ruido blanco con semilla, uniforme, escalado a `dB` de pico.
    static func white(dB: Double, seconds: Double, rate: Double, seed: UInt64 = 1) -> [Float] {
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        let amp = pow(10, dB / 20)
        return (0..<Int(seconds * rate)).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(amp * (Double(state >> 11) / Double(1 << 53) * 2 - 1))
        }
    }

    /// Ruido rosa (filtro de Paul Kellet) a partir del blanco.
    static func pink(dB: Double, seconds: Double, rate: Double, seed: UInt64 = 7) -> [Float] {
        let w = white(dB: 0, seconds: seconds, rate: rate, seed: seed).map(Double.init)
        var b0 = 0.0, b1 = 0.0, b2 = 0.0
        let amp = pow(10, dB / 20)
        return w.map { x in
            b0 = 0.99765 * b0 + x * 0.0990460
            b1 = 0.96300 * b1 + x * 0.2965164
            b2 = 0.57000 * b2 + x * 1.0526913
            return Float(amp * (b0 + b1 + b2 + x * 0.1848) * 0.25)
        }
    }

    static func write(_ channels: [[Float]], rate: Double, to url: URL, float32: Bool = true) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels.count,
            AVLinearPCMBitDepthKey: float32 ? 32 : 24, AVLinearPCMIsFloatKey: float32,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let n = channels[0].count
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        for (c, ch) in channels.enumerated() { buf.floatChannelData![c].update(from: ch, count: n) }
        try file.write(from: buf)
        file.close()   // vuelca la cola ya; si no, depende de cuándo se libere
    }

    static func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("tf-loud-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
}

/// Medidor de sonoridad y pico real (mini-spec Fase 7, «Pruebas»).
final class LoudnessMeterTests: XCTestCase {
    /// El ffmpeg embebido (`Vendor/helpers`) es una compilación mínima sin el filtro `ebur128`; si es así se
    /// prueba con uno de Homebrew. Sin ninguno con el filtro, el test se salta.
    static let ffmpeg: URL? = {
        let embedded = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Vendor/helpers/ffmpeg")
        let candidates = [embedded, URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"), URL(fileURLWithPath: "/usr/local/bin/ffmpeg")]
        for url in candidates where FileManager.default.isExecutableFile(atPath: url.path) {
            let p = Process()
            p.executableURL = url
            p.arguments = ["-hide_banner", "-filters"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { continue }
            let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            if text.contains(" ebur128 ") { return url }
        }
        return nil
    }()

    /// Sonoridad integrada y pico real que da `ebur128` de ffmpeg.
    func ffmpegMeasure(_ url: URL) throws -> (lufs: Double, peak: Double) {
        let p = Process()
        p.executableURL = Self.ffmpeg!
        p.arguments = ["-hide_banner", "-nostats", "-i", url.path, "-filter_complex", "ebur128=peak=true", "-f", "null", "-"]
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        func last(_ pattern: String) -> Double? {
            let re = try! NSRegularExpression(pattern: pattern)
            let ns = text as NSString
            guard let m = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).last else { return nil }
            return Double(ns.substring(with: m.range(at: 1)))
        }
        guard let i = last(#"\n\s*I:\s+(-?[\d.]+) LUFS"#), let pk = last(#"Peak:\s+(-?[\d.]+) dBFS"#) else {
            throw NSError(domain: "ffmpeg", code: 1, userInfo: [NSLocalizedDescriptionKey: "sin resumen ebur128"])
        }
        return (i, pk)
    }

    // MARK: Valores de referencia fijos

    func testSine997HzAtMinus23dBFSStereoIsMinus23LUFS() {
        for fs in [44_100.0, 48_000.0] {
            let s = SynthWAV.sine(997, dB: -23, seconds: 6, rate: fs)
            let r = LoudnessMeter.measure([s, s], sampleRate: fs)
            XCTAssertEqual(r.integratedLUFS ?? .nan, -23.0, accuracy: 0.05, "a \(fs) Hz")
            XCTAssertEqual(r.truePeakDB, -23.0, accuracy: 0.1)
        }
    }

    func testMonoIsThreeDecibelsBelowTheSameAudioOnBothChannels() {
        let s = SynthWAV.sine(997, dB: -23, seconds: 5, rate: 48_000)
        let mono = LoudnessMeter.measure([s], sampleRate: 48_000).integratedLUFS ?? .nan
        let stereo = LoudnessMeter.measure([s, s], sampleRate: 48_000).integratedLUFS ?? .nan
        XCTAssertEqual(stereo - mono, 3.01, accuracy: 0.02)
    }

    func testTruePeakSeesTheInterSamplePeak() {
        // Seno a fs/4 con fase 45°: las muestras valen ±0,707 y el pico real es 1,0 (0 dBTP).
        let s = SynthWAV.sine(11_025, dB: 0, seconds: 1, rate: 44_100, phase: Double.pi / 4)
        let r = LoudnessMeter.measure([s, s], sampleRate: 44_100)
        XCTAssertEqual(r.truePeakDB, 0, accuracy: 0.2)
        XCTAssertGreaterThan(r.truePeakDB, -3.0 + 2.5)
    }

    func testSilenceAndShortSignalsHaveNoLoudness() {
        let z = [Float](repeating: 0, count: 48_000 * 2)
        let r = LoudnessMeter.measure([z, z], sampleRate: 48_000)
        XCTAssertNil(r.integratedLUFS)
        XCTAssertEqual(r.truePeakDB, -.infinity)
        let short = SynthWAV.sine(1000, dB: -20, seconds: 0.3, rate: 48_000)
        XCTAssertNil(LoudnessMeter.measure([short, short], sampleRate: 48_000).integratedLUFS)
    }

    func testChunkedProcessingGivesTheSameResultAsOneShot() {
        let a = SynthWAV.pink(dB: -12, seconds: 4, rate: 44_100)
        let b = SynthWAV.white(dB: -15, seconds: 4, rate: 44_100)
        let whole = LoudnessMeter.measure([a, b], sampleRate: 44_100)
        var meter = LoudnessMeter(sampleRate: 44_100, channels: 2)
        var i = 0
        for size in [1, 777, 4410, 5000, 12345].cycled() {
            if i >= a.count { break }
            let j = min(a.count, i + size)
            meter.process([Array(a[i..<j]), Array(b[i..<j])])
            i = j
        }
        XCTAssertEqual(meter.report.integratedLUFS ?? .nan, whole.integratedLUFS ?? .nan, accuracy: 1e-6)
        XCTAssertEqual(meter.report.truePeakDB, whole.truePeakDB, accuracy: 1e-6)
    }

    func testFileMeasurementMatchesInMemoryAndReportsProgress() throws {
        let dir = try SynthWAV.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = SynthWAV.pink(dB: -10, seconds: 3, rate: 48_000)
        let url = dir.appendingPathComponent("a.wav")
        try SynthWAV.write([a, a], rate: 48_000, to: url)
        var last = 0.0
        let r = try LoudnessMeter.measure(url: url, progress: { last = $0 })
        XCTAssertEqual(last, 1, accuracy: 1e-9)
        XCTAssertEqual(r.integratedLUFS ?? .nan, LoudnessMeter.measure([a, a], sampleRate: 48_000).integratedLUFS ?? .nan, accuracy: 1e-6)
        XCTAssertThrowsError(try LoudnessMeter.measure(url: url, isCancelled: { true }))
    }

    // MARK: Puertas (valores teóricos, sin ffmpeg)

    /// Seno de 997 Hz estéreo a `dB` dBFS: su sonoridad es `dB` LUFS (ver el primer test).
    private func tone(_ dB: Double, _ seconds: Double, fs: Double = 48_000) -> [Float] {
        SynthWAV.sine(997, dB: dB, seconds: seconds, rate: fs)
    }

    func testRelativeGateExcludesASectionTwentyDecibelsLower() {
        // Sin puerta relativa saldría ≈ −26 LUFS (media de energía de −23 y −43); con ella, −23: el umbral
        // relativo queda en ≈ −36 LUFS (−10 LU bajo la media) y los bloques de −43 se descartan.
        let x = tone(-23, 10) + tone(-43, 10)
        let r = LoudnessMeter.measure([x, x], sampleRate: 48_000)
        XCTAssertEqual(r.integratedLUFS ?? .nan, -23.0, accuracy: 0.1)
    }

    func testAbsoluteGateExcludesDigitalSilence() {
        let silence = [Float](repeating: 0, count: 48_000 * 30)
        let x = tone(-23, 20) + silence
        let r = LoudnessMeter.measure([x, x], sampleRate: 48_000)
        XCTAssertEqual(r.integratedLUFS ?? .nan, -23.0, accuracy: 0.1)
    }

    func testAbsoluteGateAt70LUFSDecidesWhatTheRelativeGateSees() {
        // 20 s a −60 y 80 s a −75 (bajo −70 LUFS). Con la puerta absoluta los −75 no cuentan y sale −60; sin ella
        // la media de energía daría ≈ −66,5 y el umbral relativo (−76,5) los dejaría pasar.
        let x = tone(-60, 20) + tone(-75, 80)
        XCTAssertEqual(LoudnessMeter.measure([x, x], sampleRate: 48_000).integratedLUFS ?? .nan, -60.0, accuracy: 0.1)
        // Todo bajo la absoluta: sin medida.
        let quiet = tone(-75, 6)
        XCTAssertNil(LoudnessMeter.measure([quiet, quiet], sampleRate: 48_000).integratedLUFS)
    }

    // MARK: Contra ebur128 de ffmpeg

    func testMatchesFFmpegEBUR128() throws {
        guard Self.ffmpeg != nil else {
            throw XCTSkip("Ningún ffmpeg con el filtro ebur128 (el embebido no lo trae): no se compara")
        }
        let dir = try SynthWAV.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        func burst(_ db: Double, _ seconds: Double, _ fs: Double) -> [Float] { SynthWAV.sine(1000, dB: db, seconds: seconds, rate: fs) }
        func silence(_ seconds: Double, _ fs: Double) -> [Float] { [Float](repeating: 0, count: Int(seconds * fs)) }
        var worst = 0.0
        for fs in [44_100.0, 48_000.0] {
            // Para las puertas: parte fuerte, parte bajo la relativa (−45 dBFS), parte bajo la absoluta (−85 dBFS) y silencio.
            let gated = burst(-20, 3, fs) + silence(1, fs) + burst(-45, 3, fs) + burst(-85, 2, fs) + burst(-18, 2, fs)
            let cases: [(String, [[Float]])] = [
                ("tono", [burst(-20, 5, fs), burst(-20, 5, fs)]),
                ("blanco", [SynthWAV.white(dB: -6, seconds: 6, rate: fs, seed: 3), SynthWAV.white(dB: -9, seconds: 6, rate: fs, seed: 4)]),
                ("rosa", [SynthWAV.pink(dB: -8, seconds: 6, rate: fs, seed: 5), SynthWAV.pink(dB: -8, seconds: 6, rate: fs, seed: 6)]),
                ("puertas", [gated, gated.map { $0 * 0.7 }]),
                ("mono", [SynthWAV.pink(dB: -10, seconds: 5, rate: fs, seed: 9)]),
            ]
            for (name, channels) in cases {
                let url = dir.appendingPathComponent("\(name)-\(Int(fs)).wav")
                try SynthWAV.write(channels, rate: fs, to: url)
                let ref = try ffmpegMeasure(url)
                let mine = LoudnessMeter.measure(channels, sampleRate: fs)
                let diff = abs((mine.integratedLUFS ?? .nan) - ref.lufs)
                worst = max(worst, diff)
                print(String(format: "F7 sonoridad %@ %.0f Hz: propio %.3f LUFS / %.2f dBTP, ffmpeg %.1f LUFS / %.1f dBFS (dif %.3f LU)",
                             name, fs, mine.integratedLUFS ?? .nan, mine.truePeakDB, ref.lufs, ref.peak, diff))
                XCTAssertLessThan(diff, 0.1, "\(name) a \(fs) Hz")
                XCTAssertEqual(mine.truePeakDB, ref.peak, accuracy: 0.5, "pico real de \(name) a \(fs) Hz")
            }
        }
        print(String(format: "F7 sonoridad: peor diferencia con ffmpeg %.3f LU", worst))
    }
}

private extension Array {
    func cycled() -> AnySequence<Element> {
        AnySequence(sequence(state: 0) { i -> Element? in defer { i += 1 }; return self[i % self.count] })
    }
}
