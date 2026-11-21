#if canImport(AVFoundation)
import Foundation
import XCTest
@testable import TabKit

/// TinySoundFont (motor de Windows, paso 7, parte 7.4) frente a `AVAudioUnitSampler` (Mac) con el mismo SoundFont,
/// programa y eventos. El timbre puede diferir; lo que debe coincidir de forma robusta es el ataque de cada nota (en
/// su muestra, < 1 ms como pide la mini-spec de la Fase 5), cuánto suena, la altura fundamental y el nivel.
///
/// Con TF_SYNTH_CHECK_WAV=1 deja los dos renders de cada pasaje en
/// `Temp/win/listen/CHECK_synth_{mac,tsf}_<pasaje>.wav` para escucharlos.
final class TabSynthEngineComparisonTests: XCTestCase {
    /// Diferencia máxima de altura fundamental entre motores y con la nota escrita, en semitonos (la misma tolerancia
    /// que las pruebas de altura de `TabSynthAdornmentTests`).
    static let maxPitchError = 0.15
    /// Diferencia máxima de nivel RMS por nota entre motores, en dB.
    static let maxLevelDifferenceDB = 3.0
    /// Diferencia máxima de duración audible (hasta caer 20 dB bajo el pico de la nota) entre motores, en segundos.
    static let maxDurationDifference = 0.050
    /// Nivel bajo el pico de la nota (dB) que marca el final de la duración audible.
    static let durationFloorDB = -20.0
    /// Paso de la envolvente RMS, en segundos.
    static let envelopeHop = 0.005

    static let rate = 48_000.0

    var tmp: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: TabSynthTests.soundFont.path),
                          "falta el soundfont en \(TabSynthTests.soundFont.path)")
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tabsynth-cmp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
    }

    /// `Temp/win/listen` del repo desde este fichero.
    static let listenDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Temp/win/listen")

    /// Pasaje de guitarra limpia (programa 27): ocho notas sueltas separadas por silencios, de E2 a E5, con duraciones
    /// de corchea a blanca, un acento y una nota fantasma; 120 BPM, 8 s.
    static func guitarPassage() throws -> (TabScore, TabTrack) {
        let score = try TabSynthTests.constantScore(bpm: 120, bars: 4)
        let spec: [(pitch: Int, string: Int, beat: Int, tick: Int, ticks: Int)] = [
            (52, 4, 1, 0, 12), (57, 3, 3, 0, 6), (62, 3, 4, 6, 18), (67, 2, 6, 0, 12),
            (71, 2, 8, 0, 6), (76, 1, 9, 0, 24), (60, 2, 12, 0, 12), (40, 6, 13, 0, 24),
        ]
        var notes = spec.enumerated().map { i, s in
            TabNote(id: i, pitch: s.pitch, string: s.string, start: GridPoint(beat: s.beat, tick: s.tick),
                    duration: s.ticks, amplitude: 0.5)
        }
        notes[3].techniques.accent = .normal
        notes[4].techniques.ghost = true
        return (score, TabSynthTests.pitchedTrack(score, kind: .guitar, notes: notes))
    }

    /// Pasaje de batería: bombo, caja, charles, tom y crash en un compás y medio a 120 BPM.
    static func drumPassage() throws -> (TabScore, TabTrack) {
        let score = try TabSynthTests.constantScore(bpm: 120, bars: 2)
        let pieces: [DrumPiece] = [.kick, .hiHat, .snare, .hiHat, .kick, .tom, .snare, .crash]
        let hits = pieces.enumerated().map { i, p in TabDrumHit(piece: p, at: GridPoint(beat: 1 + i, tick: 0)) }
        return (score, TabSynthTests.drumTrack(score, hits: hits))
    }

    /// Renderiza `track` con un motor; devuelve el canal izquierdo.
    func render(_ track: TabTrack, in score: TabScore, with backend: any TabSynthBackend, label: String,
                duration: Double) throws -> [[Float]] {
        let renderer = TabSynthRenderer(soundFontURL: TabSynthTests.soundFont, guitarSound: .clean)
        let total = Int((duration * Self.rate).rounded())
        let events = TabSynthRenderer.events(track: track, in: score, sampleRate: Self.rate, delayFrames: 0,
                                             totalFrames: total)
        let (program, bank) = renderer.instrument(for: track)
        let url = tmp.appendingPathComponent("\(label).wav")
        try backend.renderFile(events: events, totalFrames: total, sampleRate: Self.rate,
                               soundFontURL: TabSynthTests.soundFont, program: program, bankMSB: bank, to: url)
        if ProcessInfo.processInfo.environment["TF_SYNTH_CHECK_WAV"] == "1" {
            let fm = FileManager.default
            try fm.createDirectory(at: Self.listenDir, withIntermediateDirectories: true)
            let dest = Self.listenDir.appendingPathComponent("CHECK_synth_\(label).wav")
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: url, to: dest)
        }
        let x = try TabSynthTests.read(url)
        XCTAssertEqual(x.channels.count, 2)
        XCTAssertEqual(x.channels[0].count, total)
        return x.channels
    }

    /// Medidas de una nota en un render.
    struct NoteMeasure {
        var onsetError: Int      // frames respecto al esperado
        var audible: Double      // s desde el ataque hasta caer `durationFloorDB` bajo el pico
        var levelDB: Double      // RMS de los primeros 250 ms (o lo que dure la nota)
        var pitchError: Double?  // semitonos respecto a la nota escrita
    }

    /// Mide una nota que empieza en `on` y cuya ventana acaba en `limit` (el siguiente ataque o el final).
    /// Ataque, envolvente y altura sobre la mezcla (L+R)/2; el nivel, con la energía de los dos canales (la ley de
    /// panorama de cada motor reparte distinto entre L y R: el charles de GM va a un lado).
    static func measure(_ stereo: [[Float]], on: Int, off: Int, limit: Int, pitch: Int?) throws -> NoteMeasure {
        let x = zip(stereo[0], stereo[1]).map { ($0 + $1) / 2 }
        let found = try XCTUnwrap(TabSynthTests.onset(x, near: on, rate: rate), "sin ataque cerca de \(on)")
        let hop = Int(envelopeHop * rate)
        var env: [Float] = []
        var i = found
        while i + hop <= limit {
            env.append(TabSynthAdornmentTests.rms(x, from: i, n: hop))
            i += hop
        }
        let peak = env.max() ?? 0
        let floor = peak * Float(pow(10, durationFloorDB / 20))
        let lastAbove = env.lastIndex { $0 >= floor } ?? 0
        let audible = Double((lastAbove + 1) * hop) / rate
        let levelN = min(off - found, Int(0.25 * rate))
        let (l, r) = (TabSynthAdornmentTests.rms(stereo[0], from: found, n: levelN),
                      TabSynthAdornmentTests.rms(stereo[1], from: found, n: levelN))
        let levelDB = 10 * log10(Double(l * l + r * r) / 2)
        var pitchError: Double?
        if let p = pitch {
            let n = 2048
            let (hz, _) = TabSynthAdornmentTests.fundamental(x, from: found + Int(0.04 * rate), n: n, rate: rate,
                                                              minHz: 60, maxHz: 1400)
            pitchError = TabSynthAdornmentTests.semitoneError(hz, Double(p))
        }
        return NoteMeasure(onsetError: found - on, audible: audible, levelDB: levelDB, pitchError: pitchError)
    }

    func compare(passage: String, score: TabScore, track: TabTrack, duration: Double) throws {
        let mac = try render(track, in: score, with: SamplerTabSynth(), label: "mac_\(passage)", duration: duration)
        let tsf = try render(track, in: score, with: TinySoundFontTabSynth(), label: "tsf_\(passage)",
                             duration: duration)
        let total = mac[0].count
        // (ataque, fin escrito, altura) de cada nota o golpe, en orden.
        var items: [(on: Int, off: Int, pitch: Int?)]
        if track.kind == .drums {
            let ons = track.hits.map { Int((score.time(of: $0.at) * Self.rate).rounded()) }
            items = ons.enumerated().map { i, on in (on, i + 1 < ons.count ? ons[i + 1] : total, nil) }
        } else {
            items = track.notes.map { n in
                let r = score.timeRange(of: n)
                return (Int((r.lowerBound * Self.rate).rounded()), Int((r.upperBound * Self.rate).rounded()), n.pitch)
            }
        }
        var lines = ["TabSynth motores, pasaje \(passage) @\(Int(Self.rate)) (mac | tsf):",
                     "  nota  ataque(muestras)  sonido(ms)          nivel(dB)            altura(semitonos)"]
        var worst = (onset: 0, onsetDiff: 0, audible: 0.0, level: 0.0, pitch: 0.0)
        var levelDiffs: [Double] = []
        for (k, item) in items.enumerated() {
            let limit = k + 1 < items.count ? items[k + 1].on - Int(0.01 * Self.rate) : total
            let a = try Self.measure(mac, on: item.on, off: item.off, limit: limit, pitch: item.pitch)
            let b = try Self.measure(tsf, on: item.on, off: item.off, limit: limit, pitch: item.pitch)
            let name = item.pitch.map { "\($0)" } ?? "\(track.hits[k].piece)"
            lines.append(String(format: "  %-6@ %+4d | %+4d       %6.0f | %6.0f      %6.1f | %6.1f (Δ%+5.1f)   %@",
                                name, a.onsetError, b.onsetError, a.audible * 1000, b.audible * 1000,
                                a.levelDB, b.levelDB, b.levelDB - a.levelDB,
                                a.pitchError.map { String(format: "%+.3f | %+.3f", $0, b.pitchError!) } ?? "-"))
            worst.onset = max(worst.onset, abs(a.onsetError), abs(b.onsetError))
            worst.onsetDiff = max(worst.onsetDiff, abs(b.onsetError - a.onsetError))
            worst.audible = max(worst.audible, abs(b.audible - a.audible))
            worst.level = max(worst.level, abs(b.levelDB - a.levelDB))
            levelDiffs.append(b.levelDB - a.levelDB)
            if let pa = a.pitchError, let pb = b.pitchError {
                worst.pitch = max(worst.pitch, abs(pa), abs(pb), abs(pb - pa))
            }
        }
        let meanLevel = levelDiffs.reduce(0, +) / Double(levelDiffs.count)
        lines.append(String(format: "  peor: ataque %d muestras (%.3f ms), Δataque %d, Δsonido %.0f ms, Δnivel %.1f dB "
                            + "(medio %+.1f), altura %.3f st", worst.onset, Double(worst.onset) / Self.rate * 1000,
                            worst.onsetDiff, worst.audible * 1000, worst.level, meanLevel, worst.pitch))
        print(lines.joined(separator: "\n"))

        // El ataque absoluto depende del detector (algunas muestras del SoundFont empiezan flojas: E2 cruza el umbral
        // a 81 muestras en los dos motores); lo que se compara es que tsf ataque donde el sampler. El retardo frente
        // al evento con umbral 1e-5 lo mide `testTinySoundFontAttackDelay`.
        XCTAssertLessThan(Double(worst.onsetDiff) / Self.rate, TabSynthTests.maxAttackError, "\(passage): ataque")
        XCTAssertLessThan(worst.level, Self.maxLevelDifferenceDB, "\(passage): nivel")
        XCTAssertLessThan(worst.pitch, Self.maxPitchError, "\(passage): altura")
        if track.kind != .drums {
            XCTAssertLessThan(worst.audible, Self.maxDurationDifference, "\(passage): duración")
        }
    }

    func testGuitarPassageMatchesSampler() throws {
        let (score, track) = try Self.guitarPassage()
        try compare(passage: "guitarra", score: score, track: track, duration: 8)
    }

    func testDrumPassageMatchesSampler() throws {
        let (score, track) = try Self.drumPassage()
        try compare(passage: "bateria", score: score, track: track, duration: 5)
    }

    /// El retardo de ataque de tsf (como `testSamplerAttackDelay`, con el motor de Windows): el primer frame con señal
    /// (|x| > 1e-5) cae en [0, 1 ms) tras el evento en las seis piezas de batería y en notas de guitarra y bajo.
    func testTinySoundFontAttackDelay() throws {
        for rate in [44_100.0, 48_000.0] {
            let renderer = TabSynthRenderer(soundFontURL: TabSynthTests.soundFont)
            let eventFrame = 10_000 + 1_237
            var report: [String] = []
            var cases: [(String, TabTrackKind, UInt8, UInt8)] = DrumPiece.allCases.map {
                ("\($0)", .drums, UInt8($0.rawValue), TabSynthRenderer.drumChannel)
            }
            cases += [("guitar E2", .guitar, 40, 0), ("guitar E4", .guitar, 64, 0), ("bass E1", .bass, 28, 0)]
            for (label, kind, key, channel) in cases {
                let events = [TabSynthRenderer.Event(frame: eventFrame, status: 0x90 | channel, data1: key, data2: 100)]
                let (program, bank) = renderer.instrument(for: kind)
                let url = tmp.appendingPathComponent("tsf-delay-\(label)-\(Int(rate)).wav")
                try TinySoundFontTabSynth().renderFile(events: events, totalFrames: 30_000, sampleRate: rate,
                                                       soundFontURL: TabSynthTests.soundFont, program: program,
                                                       bankMSB: bank, to: url)
                let x = try TabSynthTests.read(url).channels[0]
                let peak = x.map(abs).max() ?? 0
                let first = TabSynthTests.firstAbove(x, 1e-5, from: 0, to: x.count) ?? -1
                report.append("\(label): pico \(peak) d(1e-5) \(first - eventFrame)")
                XCTAssertGreaterThan(peak, 1e-3, "\(label) no suena")
                let residual = Double(first - eventFrame) / rate
                XCTAssertGreaterThanOrEqual(residual, 0, "\(label) suena antes del evento")
                XCTAssertLessThan(residual, TabSynthTests.maxAttackError, "\(label) @\(Int(rate))")
            }
            print("TabSynth tsf retardo @\(Int(rate)):\n  " + report.joined(separator: "\n  "))
        }
    }

    /// Un fichero que no es SoundFont 2 (aquí un WAV) se rechaza con `TabSynthError.soundFont`, sin dejar fichero.
    func testTinySoundFontRejectsNonSF2() throws {
        let fake = tmp.appendingPathComponent("fake.dls")
        try Data("RIFF\0\0\0\0DLS LIST".utf8).write(to: fake)
        let url = tmp.appendingPathComponent("out.wav")
        XCTAssertThrowsError(try TinySoundFontTabSynth().renderFile(
            events: [], totalFrames: 100, sampleRate: 48_000, soundFontURL: fake, program: 0,
            bankMSB: TabSynthRenderer.melodicBankMSB, to: url)) { error in
            guard case TabSynthError.soundFont = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(TinySoundFontTabSynth.sf2Bank(bankMSB: TabSynthRenderer.percussionBankMSB), 128)
        XCTAssertEqual(TinySoundFontTabSynth.sf2Bank(bankMSB: TabSynthRenderer.melodicBankMSB), 0)
    }
}
#endif
