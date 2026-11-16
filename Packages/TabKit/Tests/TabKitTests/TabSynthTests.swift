import AVFoundation
import XCTest
@testable import TabKit

/// Transcripción sintetizada (mini-spec Fase 5, «Pruebas»: un golpe en el pulso N suena en el tiempo del pulso N del
/// tema, error < 1 ms).
final class TabSynthTests: XCTestCase {
    /// `App/Resources/alphaTab/soundfont/sonivox.sf2` desde este fichero (Packages/TabKit/Tests/TabKitTests/…).
    static let soundFont: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("App/Resources/alphaTab/soundfont/sonivox.sf2")

    var tmp: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.soundFont.path),
                          "falta el soundfont en \(Self.soundFont.path)")
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tabsynth-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
    }

    // MARK: Ayudas

    /// Canales del WAV y su formato.
    static func read(_ url: URL) throws -> (channels: [[Float]], format: AVAudioFormat, fileFormat: AVAudioFormat) {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let n = AVAudioFrameCount(file.length)
        let buf = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: max(n, 1)))
        try file.read(into: buf, frameCount: n)
        let chans = (0..<Int(file.processingFormat.channelCount)).map {
            Array(UnsafeBufferPointer(start: buf.floatChannelData![$0], count: Int(buf.frameLength)))
        }
        return (chans, file.processingFormat, file.fileFormat)
    }

    /// Rejilla a tempo constante de `bars` compases de 4/4 desde 0.
    static func constantScore(bpm: Double, bars: Int) throws -> TabScore {
        let beats = (0..<(bars * 4 + 1)).map { Double($0) * 60 / bpm }
        let down = stride(from: 0, to: bars * 4, by: 4).map { beats[$0] }
        return try TabScore(beatTimes: BeatTimes(beats: beats, downbeats: down, beatsPerBar: 4),
                            duration: beats.last!)
    }

    static func drumTrack(_ score: TabScore, hits: [TabDrumHit]) -> TabTrack {
        TabTrack(id: "drums", name: "Batería", kind: .drums, tuning: nil, source: nil,
                 subdivisions: Array(repeating: .sixteenths, count: score.beats.count), hits: hits)
    }

    static func pitchedTrack(_ score: TabScore, kind: TabTrackKind, notes: [TabNote]) -> TabTrack {
        TabTrack(id: kind.rawValue, name: kind.rawValue, kind: kind,
                 tuning: kind == .bass ? .bass(.standard) : .guitar(.standard), source: nil,
                 subdivisions: Array(repeating: .sixteenths, count: score.beats.count), notes: notes)
    }

    /// Primer frame de `x[from..<to]` con |x| > `threshold`.
    static func firstAbove(_ x: [Float], _ threshold: Float, from: Int, to: Int) -> Int? {
        var i = max(0, from)
        while i < min(to, x.count) {
            if abs(x[i]) > threshold { return i }
            i += 1
        }
        return nil
    }

    /// Error máximo de ataque de la spec (mini-spec Fase 5, «Pruebas»: sintetizado).
    static let maxAttackError = 0.001

    /// Ataque cerca de `expected`: primer frame de [expected − 10 ms, expected + 10 ms] cuya amplitud supera 3 veces
    /// el suelo previo (máximo de |x| en [expected − 30 ms, expected − 10 ms], la cola del golpe anterior) y 1e-4.
    static func onset(_ x: [Float], near expected: Int, rate: Double) -> Int? {
        let ms = Int(rate / 1000)
        let floor = x[max(0, expected - 30 * ms)..<max(0, expected - 10 * ms)].map(abs).max() ?? 0
        return firstAbove(x, max(1e-4, 3 * floor), from: expected - 10 * ms, to: expected + 10 * ms)
    }

    /// 2 pulsos de anacrusa + 24 compases de 4/4 desde 0,7 s; tempo de 90 a 150 BPM en rampa con jitter ±5 ms.
    static func variableGrid() -> BeatTimes {
        var rng = TabGridTests.LCG(state: 11)
        var beats: [Double] = []
        var t = 0.7
        let count = 2 + 24 * 4
        for i in 0..<count {
            beats.append(t + (rng.next() - 0.5) * 0.010)
            t += 60 / (90 + 60 * Double(i) / Double(count - 1))
        }
        return BeatTimes(beats: beats, downbeats: stride(from: 2, to: count, by: 4).map { beats[$0] }, beatsPerBar: 4)
    }

    // MARK: Alineación

    /// Un bombo en cada pulso de una rejilla de tempo variable: el ataque en el WAV cae a < 1 ms de `time(of:)`.
    /// Más una caja en la segunda corchea (tick 6) de cada pulso en otra pasada: la interpolación dentro del pulso.
    func testDrumHitsLandOnBeatTimes() async throws {
        let grid = Self.variableGrid()
        let duration = grid.beats.last! + 0.6
        let score = try TabScore(beatTimes: grid, duration: duration)
        let renderer = TabSynthRenderer(soundFontURL: Self.soundFont)
        for rate in [44_100.0, 48_000.0] {
            for (piece, tick) in [(DrumPiece.kick, 0), (.snare, 6)] {
                let points = score.beats.indices.map { GridPoint(beat: $0, tick: tick) }
                    .filter { score.time(of: $0) >= 0.05 && score.time(of: $0) < duration - 0.05 }
                let track = Self.drumTrack(score, hits: points.map { TabDrumHit(piece: piece, at: $0) })
                let url = tmp.appendingPathComponent("beats-\(piece)-\(Int(rate)).wav")
                try await renderer.render(track: track, in: score, sampleRate: rate, duration: duration, to: url)
                let x = try Self.read(url).channels[0]
                var worst = 0.0, sum = 0.0
                for p in points {
                    let expected = Int((score.time(of: p) * rate).rounded())
                    let found = try XCTUnwrap(Self.onset(x, near: expected, rate: rate), "sin ataque en \(p)")
                    let error = Double(found - expected) / rate
                    worst = max(worst, abs(error))
                    sum += error
                }
                XCTAssertLessThan(worst, Self.maxAttackError, "\(piece) @\(Int(rate))")
                print(String(format: "TabSynth ataque %@ @%d: %d golpes, error máx %.3f ms, medio %+.3f ms",
                             "\(piece)", Int(rate), points.count, worst * 1000, sum / Double(points.count) * 1000))
            }
        }
    }

    // MARK: Formato, duración, determinismo y cancelación

    func testWavHasRequestedDurationToTheSample() async throws {
        let score = try Self.constantScore(bpm: 120, bars: 4)
        let note = TabNote(id: 1, pitch: 52, string: 4, start: GridPoint(beat: 2, tick: 3), duration: 18, amplitude: 0.5)
        let track = Self.pitchedTrack(score, kind: .guitar, notes: [note])
        let renderer = TabSynthRenderer(soundFontURL: Self.soundFont)
        for (rate, duration) in [(44_100.0, 7.123_456), (48_000.0, 5.000_01), (44_100.0, 0.05)] {
            let url = tmp.appendingPathComponent("len-\(Int(rate))-\(duration).wav")
            try await renderer.render(track: track, in: score, sampleRate: rate, duration: duration, to: url)
            let (channels, format, fileFormat) = try Self.read(url)
            XCTAssertEqual(channels.count, 2)
            XCTAssertEqual(channels[0].count, Int((duration * rate).rounded()))
            XCTAssertEqual(format.sampleRate, rate)
            XCTAssertEqual(fileFormat.commonFormat, .pcmFormatFloat32)
            XCTAssertEqual(fileFormat.settings[AVFormatIDKey] as? UInt32, kAudioFormatLinearPCM)
            if duration > 2 {
                // Suena dentro de la nota (con la distorsión por defecto) y no antes.
                let range = score.timeRange(of: note)
                let on = Int((range.lowerBound * rate).rounded())
                XCTAssertEqual(channels[0][..<on].map(abs).max() ?? 0, 0)
                XCTAssertGreaterThan(channels[0][on..<Int(range.upperBound * rate)].map(abs).max() ?? 0, 0.01)
            }
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: tmp.path).filter { $0.hasPrefix(".") }
        XCTAssertEqual(leftovers, [], "temporales sin borrar")
    }

    func testRenderIsDeterministic() async throws {
        let score = try TabScore(beatTimes: Self.variableGrid(), duration: 12)
        var hits: [TabDrumHit] = []
        for b in score.beats.indices {
            hits.append(TabDrumHit(piece: .hiHat, at: GridPoint(beat: b, tick: 0)))
            hits.append(TabDrumHit(piece: .hiHat, at: GridPoint(beat: b, tick: 6)))
            hits.append(TabDrumHit(piece: b % 2 == 0 ? .kick : .snare, at: GridPoint(beat: b, tick: 0)))
        }
        let drums = Self.drumTrack(score, hits: hits)
        let notes = score.beats.indices.map {
            TabNote(id: $0, pitch: 40 + $0 % 12, string: 6, start: GridPoint(beat: $0, tick: 0), duration: 9, amplitude: 0.5)
        }
        let bass = Self.pitchedTrack(score, kind: .bass, notes: notes)
        let renderer = TabSynthRenderer(soundFontURL: Self.soundFont)
        for track in [drums, bass] {
            let a = tmp.appendingPathComponent("det-a-\(track.id).wav")
            let b = tmp.appendingPathComponent("det-b-\(track.id).wav")
            try await renderer.render(track: track, in: score, sampleRate: 48_000, duration: 12, to: a)
            try await renderer.render(track: track, in: score, sampleRate: 48_000, duration: 12, to: b)
            let (ca, cb) = (try Self.read(a).channels, try Self.read(b).channels)
            XCTAssertEqual(ca, cb, track.id)
            XCTAssertGreaterThan(ca[0].map(abs).max() ?? 0, 0.01, track.id)
        }
    }

    func testCancelledRenderThrowsAndLeavesNoFile() async throws {
        let score = try Self.constantScore(bpm: 120, bars: 200)
        let track = Self.drumTrack(score, hits: score.beats.indices.map { TabDrumHit(piece: .kick, at: GridPoint(beat: $0, tick: 0)) })
        let url = tmp.appendingPathComponent("cancel.wav")
        let renderer = TabSynthRenderer(soundFontURL: Self.soundFont)
        let task = Task {
            try await renderer.render(track: track, in: score, sampleRate: 48_000, duration: 400, to: url)
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("debería cancelarse")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tmp.path), [])
    }

    /// Tema de 4 min a 44,1 kHz con batería densa (charles a semicorcheas, bombo y caja) y guitarra a corcheas.
    func testFourMinuteRenderTime() async throws {
        let duration = 240.0
        let score = try Self.constantScore(bpm: 128, bars: Int(duration / (4 * 60 / 128.0)))
        var hits: [TabDrumHit] = []
        var notes: [TabNote] = []
        for b in score.beats.indices {
            for t in stride(from: 0, to: 12, by: 3) { hits.append(TabDrumHit(piece: .hiHat, at: GridPoint(beat: b, tick: t))) }
            hits.append(TabDrumHit(piece: b % 2 == 0 ? .kick : .snare, at: GridPoint(beat: b, tick: 0)))
            for (k, t) in [0, 6].enumerated() {
                for (s, p) in [(6, 40), (5, 47), (4, 52)] {
                    notes.append(TabNote(id: notes.count, pitch: p + (b + k) % 5, string: s,
                                         start: GridPoint(beat: b, tick: t), duration: 6, amplitude: 0.5))
                }
            }
        }
        let renderer = TabSynthRenderer(soundFontURL: Self.soundFont)
        for track in [Self.drumTrack(score, hits: hits), Self.pitchedTrack(score, kind: .guitar, notes: notes)] {
            let url = tmp.appendingPathComponent("long-\(track.id).wav")
            let clock = ContinuousClock()
            let elapsed = try await clock.measure {
                try await renderer.render(track: track, in: score, sampleRate: 44_100, duration: duration, to: url)
            }
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
            print(String(format: "TabSynth 4 min %@: %.2f s (%d eventos)", track.id, seconds,
                         track.kind == .drums ? track.hits.count : track.notes.count * 2))
            XCTAssertLessThan(seconds, 20)
            // Longitud exacta y el último segundo suena (el render llega al final de verdad).
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            XCTAssertEqual(file.length, AVAudioFramePosition(duration * 44_100))
            file.framePosition = file.length - 44_100
            let tail = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 44_100))
            try file.read(into: tail, frameCount: 44_100)
            let peak = UnsafeBufferPointer(start: tail.floatChannelData![0], count: Int(tail.frameLength)).map(abs).max()
            XCTAssertGreaterThan(peak ?? 0, 0.01, track.id)
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Eventos

    func testEventsOrderAndSamePitchOverlap() throws {
        let score = try Self.constantScore(bpm: 120, bars: 2)   // pulsos de 0,5 s
        // Dos notas de la misma altura solapadas (cuerdas distintas) y una que empieza justo cuando acaba otra.
        let notes = [
            TabNote(id: 1, pitch: 64, string: 1, start: GridPoint(beat: 0, tick: 0), duration: 24, amplitude: 0.5),
            TabNote(id: 2, pitch: 64, string: 2, start: GridPoint(beat: 1, tick: 0), duration: 12, amplitude: 0.5),
            TabNote(id: 3, pitch: 60, string: 2, start: GridPoint(beat: 2, tick: 0), duration: 12, amplitude: 0.5),
            TabNote(id: 4, pitch: 60, string: 2, start: GridPoint(beat: 3, tick: 0), duration: 12, amplitude: 0.5)
        ]
        let events = TabSynthRenderer.events(track: Self.pitchedTrack(score, kind: .guitar, notes: notes), in: score,
                                             sampleRate: 48_000, delayFrames: 0, totalFrames: 4 * 48_000)
        let summary = events.map { "\($0.frame):\($0.isNoteOff ? "off" : "on")\($0.data1)" }
        XCTAssertEqual(summary, ["0:on64", "24000:off64", "24000:on64", "48000:off64", "48000:on60",
                                 "72000:off60", "72000:on60", "96000:off60"])
    }
}

// MARK: - Retardo del sampler

extension TabSynthTests {
    /// Mide el retardo de ataque: un evento solo en un frame conocido (no múltiplo del bloque) y el primer frame con
    /// señal (|x| > 1e-5) en la salida, sin compensación. Lo que quede tras `samplerAttackDelayFrames` debe ser
    /// < 1 ms en todas las piezas y notas.
    func testSamplerAttackDelay() async throws {
        for rate in [44_100.0, 48_000.0] {
            let renderer = TabSynthRenderer(soundFontURL: Self.soundFont)
            let eventFrame = 10_000 + 1_237
            var report: [String] = []
            var cases: [(String, TabTrackKind, UInt8, UInt8)] = DrumPiece.allCases.map {
                ("\($0)", .drums, $0.rawValue < 128 ? UInt8($0.rawValue) : 0, TabSynthRenderer.drumChannel)
            }
            cases += [("guitar E2", .guitar, 40, 0), ("guitar E4", .guitar, 64, 0), ("bass E1", .bass, 28, 0)]
            for (label, kind, key, channel) in cases {
                let events = [TabSynthRenderer.Event(frame: eventFrame, status: 0x90 | channel, data1: key, data2: 100)]
                let (program, bank) = renderer.instrument(for: kind)
                let url = tmp.appendingPathComponent("delay-\(label)-\(Int(rate)).wav")
                try TabSynthRenderer.renderFile(events: events, totalFrames: 30_000, sampleRate: rate,
                                                soundFontURL: Self.soundFont, program: program, bankMSB: bank, to: url)
                let x = try Self.read(url).channels[0]
                let peak = x.map(abs).max() ?? 0
                let firstAny = Self.firstAbove(x, 1e-5, from: 0, to: x.count) ?? -1
                let first1 = Self.firstAbove(x, peak * 0.01, from: 0, to: x.count) ?? -1
                let first10 = Self.firstAbove(x, peak * 0.1, from: 0, to: x.count) ?? -1
                report.append("\(label): peak \(peak) d(1e-5) \(firstAny - eventFrame) d(1%) \(first1 - eventFrame) "
                              + "d(10%) \(first10 - eventFrame)")
                XCTAssertGreaterThan(peak, 1e-3, "\(label) no suena")
                let residual = Double(firstAny - eventFrame - TabSynthRenderer.samplerAttackDelayFrames) / rate
                XCTAssertGreaterThanOrEqual(residual, 0, "\(label) suena antes del evento")
                XCTAssertLessThan(residual, Self.maxAttackError, "\(label) @\(Int(rate))")
            }
            print("TabSynth retardo @\(Int(rate)):\n  " + report.joined(separator: "\n  "))
        }
    }
}
