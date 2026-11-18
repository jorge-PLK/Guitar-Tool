import Accelerate
import AVFoundation
import XCTest
@testable import TabKit

/// Sonido de los adornos (mini-spec Fase 5c, «Sonido de los adornos»): la altura que sale del sampler con rango de
/// rueda por RPN y canal por cuerda, y los eventos de let ring, slides, ligados, armónicos, notas de adorno y flam.
final class TabSynthAdornmentTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tabsynth-adorn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
    }

    // MARK: Ayudas

    typealias Event = TabSynthRenderer.Event

    /// Frecuencia fundamental de `x[from..<from+n]` por autocorrelación normalizada, buscando el desfase entre
    /// `minHz` y `maxHz`; devuelve también la correlación del máximo (1 = periódica).
    static func fundamental(_ x: [Float], from: Int, n: Int, rate: Double, minHz: Double,
                            maxHz: Double) -> (hz: Double, corr: Float) {
        let minLag = Int(rate / maxHz), maxLag = Int(rate / minHz) + 1
        var best = (lag: minLag, corr: -Float.infinity)
        var corrs: [Float] = []
        x.withUnsafeBufferPointer { p in
            let a = p.baseAddress! + from
            var e0: Float = 0
            vDSP_dotpr(a, 1, a, 1, &e0, vDSP_Length(n))
            for lag in minLag...maxLag {
                var c: Float = 0, e1: Float = 0
                vDSP_dotpr(a, 1, a + lag, 1, &c, vDSP_Length(n))
                vDSP_dotpr(a + lag, 1, a + lag, 1, &e1, vDSP_Length(n))
                let r = c / max(1e-12, (e0 * e1).squareRoot())
                corrs.append(r)
                if r > best.corr { best = (lag, r) }
            }
        }
        // El primer máximo local que llegue al 90 % del mejor (el doble del periodo también correlaciona), con
        // interpolación parabólica.
        if let first = corrs.indices.dropFirst().dropLast().first(where: {
            corrs[$0] >= 0.9 * best.corr && corrs[$0] >= corrs[$0 - 1] && corrs[$0] >= corrs[$0 + 1]
        }) {
            best = (first + minLag, corrs[first])
        }
        let i = best.lag - minLag
        var lag = Double(best.lag)
        if i > 0, i < corrs.count - 1 {
            let (l, c, r) = (Double(corrs[i - 1]), Double(corrs[i]), Double(corrs[i + 1]))
            let d = l - 2 * c + r
            if d != 0 { lag += 0.5 * (l - r) / d }
        }
        return (rate / lag, best.corr)
    }

    static func hz(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

    /// Desvío en semitonos de `measured` respecto a la nota MIDI `midi`.
    static func semitoneError(_ measured: Double, _ midi: Double) -> Double { 12 * log2(measured / hz(midi)) }

    func renderClean(_ events: [Event], frames: Int, rate: Double) throws -> [Float] {
        let url = tmp.appendingPathComponent("probe-\(UUID().uuidString).wav")
        try TabSynthRenderer.renderFile(events: events.sorted { $0.frame < $1.frame }, totalFrames: frames,
                                        sampleRate: rate, soundFontURL: TabSynthTests.soundFont,
                                        program: TabSynthRenderer.GuitarSound.clean.program,
                                        bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), to: url)
        return try TabSynthTests.read(url).channels[0]
    }

    // MARK: Sampler: rango de rueda por RPN y estado por canal

    /// El rango de rueda puesto por RPN se respeta, y la rueda de un canal no mueve las notas de otro (cada canal va a
    /// su sampler en `renderFile`; con un solo sampler la B sonaba 12 semitonos arriba). Altura medida en el WAV,
    /// tolerancia 0,15 semitonos.
    func testSamplerHonoursRPNRangeAndPerChannelBend() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: TabSynthTests.soundFont.path))
        let rate = 48_000.0
        func rpn(_ ch: UInt8, _ semis: UInt8) -> [Event] {
            [Event(frame: 0, status: 0xB0 | ch, data1: 101, data2: 0), Event(frame: 0, status: 0xB0 | ch, data1: 100, data2: 0),
             Event(frame: 0, status: 0xB0 | ch, data1: 6, data2: semis), Event(frame: 0, status: 0xB0 | ch, data1: 38, data2: 0)]
        }
        // A: canal 0 con rango 12 y rueda a fondo (+12) → 52 suena como 64.
        let a = try renderClean(rpn(0, 12) + [Event(frame: 10, status: 0xE0, data1: 127, data2: 127),
                                              Event(frame: 100, status: 0x90, data1: 52, data2: 100)],
                                frames: 48_000, rate: rate)
        let fa = Self.fundamental(a, from: 9_600, n: 4_096, rate: rate, minHz: 120, maxHz: 500)
        // B: rueda a fondo en el canal 1 y nota en el canal 0 → 52 sin mover.
        let b = try renderClean(rpn(1, 12) + [Event(frame: 10, status: 0xE1, data1: 127, data2: 127),
                                              Event(frame: 100, status: 0x90, data1: 52, data2: 100)],
                                frames: 48_000, rate: rate)
        let fb = Self.fundamental(b, from: 9_600, n: 4_096, rate: rate, minHz: 120, maxHz: 500)
        // C: canal 2 con rango 7 y rueda a −1/2 escala → 64 − 3,5.
        let c = try renderClean(rpn(2, 7) + [Event(frame: 10, status: 0xE2, data1: 0, data2: 32),
                                             Event(frame: 100, status: 0x92, data1: 64, data2: 100)],
                                frames: 48_000, rate: rate)
        let fc = Self.fundamental(c, from: 9_600, n: 4_096, rate: rate, minHz: 120, maxHz: 500)
        print("TabSynth RPN: A \(fa) err \(Self.semitoneError(fa.hz, 64)) · B \(fb) err \(Self.semitoneError(fb.hz, 52))"
              + " · C \(fc) err \(Self.semitoneError(fc.hz, 60.5))")
        XCTAssertEqual(Self.semitoneError(fa.hz, 64), 0, accuracy: 0.15)
        XCTAssertEqual(Self.semitoneError(fb.hz, 52), 0, accuracy: 0.15)
        XCTAssertEqual(Self.semitoneError(fc.hz, 60.5), 0, accuracy: 0.15)
    }

    // MARK: Eventos (120 BPM: pulso = 24 000 frames a 48 kHz, tick = 2 000)

    static let rate = 48_000.0

    static func note(_ id: Int, _ pitch: Int, string: Int, beat: Int, tick: Int = 0, ticks: Int = 12,
                     _ edit: (inout TabTechniques) -> Void = { _ in }) -> TabNote {
        var t = TabTechniques()
        edit(&t)
        return TabNote(id: id, pitch: pitch, string: string, start: GridPoint(beat: beat, tick: tick), duration: ticks,
                       amplitude: 0.5, techniques: t)
    }

    static func events(_ notes: [TabNote], bars: Int = 2) throws -> [Event] {
        let score = try TabSynthTests.constantScore(bpm: 120, bars: bars)
        return TabSynthRenderer.events(track: TabSynthTests.pitchedTrack(score, kind: .guitar, notes: notes), in: score,
                                       sampleRate: rate, delayFrames: 0, totalFrames: bars * 4 * 24_000)
    }

    /// Note-on y note-off como "frame:on60v100" / "frame:off60".
    static func noteSummary(_ events: [Event]) -> [String] {
        events.compactMap { e in
            switch e.status & 0xF0 {
            case 0x90: "\(e.frame):on\(e.data1)v\(e.data2)"
            case 0x80: "\(e.frame):off\(e.data1)"
            default: nil
            }
        }
    }

    /// Rango de rueda puesto por RPN en `channel` (nil si no hay).
    static func range(_ events: [Event], channel: UInt8) -> Int? {
        events.first { $0.status == 0xB0 | channel && $0.data1 == 6 }.map { Int($0.data2) }
    }

    /// Puntos de rueda de `channel` en semitonos (con el rango de su RPN; 2 si no hay).
    static func bends(_ events: [Event], channel: UInt8) -> [(frame: Int, semitones: Double)] {
        let r = Double(range(events, channel: channel) ?? 2)
        return events.filter { $0.status == 0xE0 | channel }
            .map { ($0.frame, Double(Int($0.data1) | Int($0.data2) << 7 - 8192) / 8191 * r) }
    }

    static func bend(_ curve: [(frame: Int, semitones: Double)], at frame: Int) -> Double? {
        curve.last { $0.frame <= frame }?.semitones
    }

    // MARK: Let ring

    /// Suena hasta la siguiente nota de su cuerda o el fin del tramo let ring (el final más tardío de los ataques
    /// seguidos con let ring), con tope de 4 s.
    func testLetRingRingsToNextNoteOnStringOrEndOfRun() throws {
        let notes = [
            Self.note(1, 57, string: 3, beat: 0) { $0.letRing = true },
            Self.note(2, 60, string: 2, beat: 1) { $0.letRing = true },
            Self.note(3, 62, string: 2, beat: 2) { $0.letRing = true },
            Self.note(4, 52, string: 4, beat: 3)
        ]
        XCTAssertEqual(Self.noteSummary(try Self.events(notes)),
                       ["0:on57v100", "24000:on60v100", "48000:off60", "48000:on62v100", "72000:off62", "72000:off57",
                        "72000:on52v100", "96000:off52"])
        // Tramo de 6 s: la nota del primer pulso se corta a los 4 s exactos (192 000 frames).
        var long = [Self.note(1, 64, string: 1, beat: 0) { $0.letRing = true }]
        for b in 1..<12 { long.append(Self.note(b + 1, 59 + b % 2, string: 2, beat: b) { $0.letRing = true }) }
        let off = Self.noteSummary(try Self.events(long, bars: 4)).first { $0.hasSuffix(":off64") }
        XCTAssertEqual(off, "192000:off64")
    }

    // MARK: Ligados

    /// La segunda empieza justo al acabar la primera (aunque esta lleve palm mute) y con 0,7 de velocidad; con un
    /// silencio en medio no hay ligado.
    func testHammerPullStartsAtEndOfFirstWithLowerVelocity() throws {
        let notes = [
            Self.note(1, 67, string: 1, beat: 0, ticks: 6) { $0.hammerPull = true },
            Self.note(2, 69, string: 1, beat: 0, tick: 6, ticks: 6),
            Self.note(3, 65, string: 1, beat: 1) { $0.hammerPull = true; $0.palmMute = true },
            Self.note(4, 64, string: 1, beat: 2),
            Self.note(5, 60, string: 1, beat: 3, ticks: 6) { $0.hammerPull = true },
            Self.note(6, 62, string: 1, beat: 3, tick: 9, ticks: 3)
        ]
        let events = try Self.events(notes)
        XCTAssertEqual(Self.noteSummary(events),
                       ["0:on67v100", "12000:off67", "12000:on69v70", "24000:off69", "24000:on65v100", "48000:off65",
                        "48000:on64v70", "72000:off64", "72000:on60v100", "84000:off60", "90000:on62v100", "96000:off62"])
        XCTAssertFalse(events.contains { $0.status & 0xF0 == 0xE0 }, "sin rueda")
    }

    // MARK: Slides

    /// Legato 60 → 65 en la cuerda 2 (canal 1): una sola voz; la rueda (rango 5 por RPN) está en 0 hasta 150 ms antes
    /// de la segunda, sube lineal, vale +5 exactos en el último frame de la primera y se queda en +5 durante la
    /// segunda; vuelve al centro con el note-off.
    func testLegatoSlideGlidesWithoutNewAttack() throws {
        let events = try Self.events([Self.note(1, 60, string: 2, beat: 0) { $0.slideOut = .legato },
                                      Self.note(2, 65, string: 2, beat: 1)])
        XCTAssertEqual(Self.noteSummary(events), ["0:on60v100", "48000:off60"])
        XCTAssertEqual(Self.range(events, channel: 1), 5)
        let curve = Self.bends(events, channel: 1)
        XCTAssertEqual(Self.bend(curve, at: 16_799)!, 0, accuracy: 1e-3)
        let ramp = curve.filter { $0.frame >= 16_800 && $0.frame < 24_000 }
        XCTAssertGreaterThanOrEqual(ramp.count, 12)
        for p in ramp {   // lineal de 0 a +5 entre 16 800 y 23 999 (cuantización de 14 bits: < 1e-3)
            XCTAssertEqual(p.semitones, 5 * Double(p.frame - 16_800) / 7_199, accuracy: 1e-3, "\(p.frame)")
        }
        XCTAssertEqual(curve.first { $0.frame == 23_999 }?.semitones ?? 0, 5, accuracy: 1e-3)
        XCTAssertTrue(curve.filter { $0.frame >= 24_000 && $0.frame < 48_000 }.allSatisfy { abs($0.semitones - 5) < 1e-3 })
        XCTAssertEqual(curve.last!.frame, 48_000)
        XCTAssertEqual(curve.last!.semitones, 0, accuracy: 1e-3)
    }

    /// Shift: mismo glisando y la segunda con ataque; la rueda vuelve al centro antes de su note-on (mismo frame).
    func testShiftSlideGlidesThenAttacks() throws {
        let events = try Self.events([Self.note(1, 60, string: 2, beat: 0) { $0.slideOut = .shift },
                                      Self.note(2, 65, string: 2, beat: 1)])
        XCTAssertEqual(Self.noteSummary(events), ["0:on60v100", "24000:off60", "24000:on65v100", "48000:off65"])
        let curve = Self.bends(events, channel: 1)
        XCTAssertEqual(curve.first { $0.frame == 23_999 }?.semitones ?? 0, 5, accuracy: 1e-3)
        let reset = try XCTUnwrap(events.firstIndex { $0.status == 0xE1 && $0.frame == 24_000 })
        let on = try XCTUnwrap(events.firstIndex { $0.status == 0x91 && $0.data1 == 65 })
        XCTAssertLessThan(reset, on)
        XCTAssertEqual(Int(events[reset].data2), 64)
        // Legato de 14 semitonos (más que el tope de 12): suena como shift, con rango 12 y el glisando hasta +12.
        let far = try Self.events([Self.note(1, 56, string: 3, beat: 0) { $0.slideOut = .legato },
                                   Self.note(2, 70, string: 3, beat: 1)])
        XCTAssertEqual(Self.noteSummary(far), ["0:on56v100", "24000:off56", "24000:on70v100", "48000:off70"])
        XCTAssertEqual(Self.range(far, channel: 2), 12)
        XCTAssertEqual(Self.bends(far, channel: 2).first { $0.frame == 23_999 }?.semitones ?? 0, 12, accuracy: 1e-3)
    }

    /// Entrada desde abajo: −3 en el ataque y 0 a los 100 ms; salida hacia abajo: −3 en el último frame. Un legato
    /// sin nota a la que ir suena como salida.
    func testSlideInAndOutAreShortGlides() throws {
        let events = try Self.events([Self.note(1, 67, string: 1, beat: 1) { $0.slideIn = .intoFromBelow },
                                      Self.note(2, 69, string: 1, beat: 3) { $0.slideOut = .outDown },
                                      Self.note(3, 60, string: 2, beat: 5) { $0.slideOut = .legato }])
        XCTAssertEqual(Self.range(events, channel: 0), 3)
        let s1 = Self.bends(events, channel: 0)
        XCTAssertEqual(s1.first { $0.frame == 24_000 }!.semitones, -3, accuracy: 1e-3)
        // Puntos cada 576 frames (12 ms): 26 304 está al 48 % de la entrada; 29 184, ya pasada.
        XCTAssertEqual(s1.first { $0.frame == 26_304 }!.semitones, -3 * 0.52, accuracy: 1e-3)
        XCTAssertEqual(Self.bend(s1, at: 29_184)!, 0, accuracy: 1e-3)
        XCTAssertEqual(s1.first { $0.frame == 95_999 }!.semitones, -3, accuracy: 1e-3)
        XCTAssertEqual(Self.bend(s1, at: 95_999 - 4_800)!, 0, accuracy: 0.05)
        XCTAssertEqual(Self.bends(events, channel: 1).first { $0.frame == 143_999 }!.semitones, -3, accuracy: 1e-3)
    }

    /// Un bend de un tono sigue llegando a +2 semitonos cuando un slide de 7 amplía el rango a 7, y la nota que suena
    /// a la vez en otra cuerda no recibe rueda (va en su canal). Sin slides el rango sigue siendo 2.
    func testBendsSurviveWiderRangeAndStayOnTheirString() throws {
        let bend = TabBend(points: [.init(position: 0, value: 0), .init(position: 60, value: 4)])
        let events = try Self.events([Self.note(1, 64, string: 1, beat: 0) { $0.bend = bend },
                                      Self.note(2, 60, string: 2, beat: 0),
                                      Self.note(3, 57, string: 3, beat: 2) { $0.slideOut = .legato },
                                      Self.note(4, 64, string: 3, beat: 3)])
        XCTAssertEqual(Self.range(events, channel: 0), 7)
        XCTAssertEqual(Self.range(events, channel: 2), 7)
        XCTAssertNil(Self.range(events, channel: 1))
        XCTAssertTrue(Self.bends(events, channel: 1).isEmpty)
        XCTAssertTrue(events.contains { $0.status == 0x91 && $0.data1 == 60 })
        let b = Self.bends(events, channel: 0).filter { $0.frame < 24_000 }
        XCTAssertEqual(b.first!.semitones, 0, accuracy: 1e-3)
        // Último punto, 23 616: posición 59,04/60 de la curva → 1,968 semitonos.
        XCTAssertEqual(b.last!.semitones, 1.968, accuracy: 1e-3)
        let alone = try Self.events([Self.note(1, 64, string: 1, beat: 0) { $0.bend = bend }])
        XCTAssertEqual(Self.range(alone, channel: 0), 2)
        XCTAssertEqual(Self.bends(alone, channel: 0).filter { $0.frame < 24_000 }.last!.semitones, 1.968, accuracy: 1e-3)
    }

    // MARK: Armónicos

    func testHarmonicSemitonesByFret() {
        let expected: [(Double, Int)] = [(12, 12), (7, 19), (19, 19), (5, 24), (24, 24), (4, 28), (9, 28), (16, 28),
                                         (3.2, 31), (2.7, 34), (2.4, 36), (17, 36), (11, 0), (1, 0), (0, 0)]
        for (fret, semis) in expected {
            XCTAssertEqual(TabSynthRenderer.harmonicSemitones(fret: fret), semis, "traste \(fret)")
        }
    }

    /// Naturales sobre la cuerda al aire (con el traste de la nota si no traen otro); semi y pinch, sobre la pisada.
    func testHarmonicNotesSoundAtTheHarmonicPitch() throws {
        func harm(_ type: TabHarmonicType, _ fret: Double?) -> (inout TabTechniques) -> Void {
            { $0.harmonic = TabHarmonic(type: type, fret: fret) }
        }
        let notes = [
            Self.note(1, 47, string: 6, beat: 0, harm(.natural, 7)),      // E2 al aire + 19 → 59
            Self.note(2, 76, string: 1, beat: 1, harm(.natural, 12)),     // E4 + 12 → 76
            Self.note(3, 69, string: 1, beat: 2, harm(.natural, nil)),    // traste 5 → E4 + 24 → 88
            Self.note(4, 63, string: 2, beat: 3, harm(.natural, 4)),      // B3 + 28 → 87
            Self.note(5, 62, string: 3, beat: 4, harm(.semi, 12)),        // pisada 62 + 12 → 74
            Self.note(6, 59, string: 3, beat: 5, harm(.pinch, 24)),       // pisada 59 + 24 → 83
            Self.note(7, 62, string: 3, beat: 6, harm(.artificial, nil))  // sin distancia: la octava → 74
        ]
        let ons = try Self.events(notes).filter { $0.status & 0xF0 == 0x90 }.map { Int($0.data1) }
        XCTAssertEqual(ons, [59, 76, 88, 87, 74, 83, 74])
    }

    // MARK: Notas de adorno

    /// Antes del pulso: 60 ms (2 880 frames) antes, hasta el ataque de la principal; ligada, la principal con 0,7;
    /// con slide, una sola voz que glisa al final de la de adorno; en el pulso, la principal se retrasa 60 ms.
    func testGraceNotesBeforeAndOnTheBeat() throws {
        func main(_ grace: TabGrace) -> TabNote { Self.note(1, 69, string: 1, beat: 2) { $0.graces = [grace] } }
        XCTAssertEqual(Self.noteSummary(try Self.events([main(TabGrace(fret: 3, type: .beforeBeat))])),
                       ["45120:on67v100", "48000:off67", "48000:on69v100", "72000:off69"])
        XCTAssertEqual(Self.noteSummary(try Self.events([main(TabGrace(fret: 3, type: .beforeBeat, hammerPull: true))])),
                       ["45120:on67v100", "48000:off67", "48000:on69v70", "72000:off69"])
        let slide = try Self.events([main(TabGrace(fret: 3, type: .beforeBeat, slide: true))])
        XCTAssertEqual(Self.noteSummary(slide), ["45120:on67v100", "72000:off67"])
        let curve = Self.bends(slide, channel: 0)
        XCTAssertEqual(Self.bend(curve, at: 46_559)!, 0, accuracy: 1e-3)
        XCTAssertEqual(curve.first { $0.frame == 47_999 }!.semitones, 2, accuracy: 1e-3)
        XCTAssertEqual(Self.bend(curve, at: 71_999)!, 2, accuracy: 1e-3)
        XCTAssertEqual(Self.noteSummary(try Self.events([main(TabGrace(fret: 3, type: .onBeat))])),
                       ["48000:on67v100", "50880:off67", "50880:on69v100", "72000:off69"])
        // Rastrillo en otras cuerdas (pasos 2 y 1): 120 y 60 ms antes, cada una en su cuerda.
        let rake = Self.note(1, 64, string: 1, beat: 2) {
            $0.graces = [TabGrace(fret: 2, type: .beforeBeat, string: 3, step: 2),
                         TabGrace(fret: 0, type: .beforeBeat, string: 2)]
        }
        XCTAssertEqual(Self.noteSummary(try Self.events([rake])),
                       ["42240:on57v100", "45120:off57", "45120:on59v100", "48000:off59", "48000:on64v100", "72000:off64"])
    }

    // MARK: Flam

    /// El golpe de adorno, 30 ms (1 440 frames) antes y con 0,6 de velocidad; el principal en su pulso.
    func testDrumFlamIsAGraceStrokeBefore() throws {
        let score = try TabSynthTests.constantScore(bpm: 120, bars: 1)
        let hits = [TabDrumHit(piece: .snare, at: GridPoint(beat: 1, tick: 0),
                               grace: TabGrace(fret: 38, type: .beforeBeat)),
                    TabDrumHit(piece: .kick, at: GridPoint(beat: 1, tick: 0))]
        let events = TabSynthRenderer.events(track: TabSynthTests.drumTrack(score, hits: hits), in: score,
                                             sampleRate: Self.rate, delayFrames: 0, totalFrames: 96_000)
        XCTAssertEqual(Self.noteSummary(events), ["22560:on38v60", "24000:off38", "24000:on38v100", "24000:on35v100"])
        XCTAssertTrue(events.allSatisfy { $0.status & 0x0F == TabSynthRenderer.drumChannel })
    }
}

// MARK: - Audio de los adornos

extension TabSynthAdornmentTests {
    /// RMS de `x[from..<from+n]`.
    static func rms(_ x: [Float], from: Int, n: Int) -> Float {
        var r: Float = 0
        x.withUnsafeBufferPointer { vDSP_rmsqv($0.baseAddress! + from, 1, &r, vDSP_Length(n)) }
        return r
    }

    /// En el WAV (guitarra limpia): un legato 52 → 57 suena 52 y luego 57 (±0,15 semitonos) sin ataque nuevo (el
    /// nivel justo después del cambio no sube sobre el de justo antes), y un shift sí ataca.
    func testLegatoSlideSoundsAtTargetPitchWithoutAttack() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: TabSynthTests.soundFont.path))
        let score = try TabSynthTests.constantScore(bpm: 120, bars: 1)
        let renderer = TabSynthRenderer(soundFontURL: TabSynthTests.soundFont, guitarSound: .clean)
        var report: [String] = []
        for kind in [TabSlideOut.legato, .shift] {
            let notes = [Self.note(1, 52, string: 5, beat: 0) { $0.slideOut = kind }, Self.note(2, 57, string: 5, beat: 1)]
            let url = tmp.appendingPathComponent("slide-\(kind).wav")
            try await renderer.render(track: TabSynthTests.pitchedTrack(score, kind: .guitar, notes: notes), in: score,
                                      sampleRate: Self.rate, duration: 1.5, to: url)
            let x = try TabSynthTests.read(url).channels[0]
            let before = Self.fundamental(x, from: 4_800, n: 4_096, rate: Self.rate, minHz: 80, maxHz: 400)
            let after = Self.fundamental(x, from: 31_200, n: 4_096, rate: Self.rate, minHz: 80, maxHz: 400)
            let jump = Self.rms(x, from: 24_000, n: 960) / Self.rms(x, from: 24_000 - 960 - 7_200, n: 960)
            report.append("\(kind): antes \(before) (\(Self.semitoneError(before.hz, 52))) después \(after) "
                          + "(\(Self.semitoneError(after.hz, 57))) nivel tras/antes del glisando \(jump)")
            XCTAssertEqual(Self.semitoneError(before.hz, 52), 0, accuracy: 0.15, "\(kind)")
            XCTAssertEqual(Self.semitoneError(after.hz, 57), 0, accuracy: 0.15, "\(kind)")
            if kind == .legato { XCTAssertLessThan(jump, 1.2) } else { XCTAssertGreaterThan(jump, 1.5) }
        }
        print("TabSynth slides:\n  " + report.joined(separator: "\n  "))
    }

    /// 4 min a 44,1 kHz de guitarra a corcheas en las seis cuerdas con vibrato en todas (seis samplers): < 20 s.
    func testFourMinuteRenderTimeWithSixSamplers() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: TabSynthTests.soundFont.path))
        let duration = 240.0
        let score = try TabSynthTests.constantScore(bpm: 128, bars: Int(duration / (4 * 60 / 128.0)))
        var notes: [TabNote] = []
        for b in score.beats.indices {
            for t in [0, 6] {
                for (s, p) in [(6, 40), (5, 45), (4, 50), (3, 55), (2, 59), (1, 64)] {
                    notes.append(Self.note(notes.count, p + b % 5, string: s, beat: b, tick: t, ticks: 6) {
                        $0.vibrato = .slight
                    })
                }
            }
        }
        let track = TabSynthTests.pitchedTrack(score, kind: .guitar, notes: notes)
        let events = TabSynthRenderer.events(track: track, in: score, sampleRate: 44_100, delayFrames: 0,
                                             totalFrames: Int(duration * 44_100))
        XCTAssertEqual(Set(events.map { $0.status & 0x0F }).count, 6)
        let url = tmp.appendingPathComponent("long-six.wav")
        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            try await TabSynthRenderer(soundFontURL: TabSynthTests.soundFont)
                .render(track: track, in: score, sampleRate: 44_100, duration: duration, to: url)
        }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        print(String(format: "TabSynth 4 min seis samplers: %.2f s (%d eventos)", seconds, events.count))
        XCTAssertLessThan(seconds, 20)
    }
}

// MARK: - WAV de escucha con los temas reales (TF_5C_CHECK_WAV=1 y TF_P5B_PROJECTS)

extension TabSynthAdornmentTests {
    /// Renderiza las pistas con adornos de los temas de la Fase 5b a `Temp/CHECK_5c_<tema>_<pista>.wav` y resume los
    /// adornos de cada una. Lee la copia aislada de `TF_P5B_PROJECTS`, nunca `~/Music/ToneForge`.
    func testRenderCheckWavsFromProjects() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["TF_5C_CHECK_WAV"] == "1" && !(env["TF_P5B_PROJECTS"] ?? "").isEmpty,
                          "TF_5C_CHECK_WAV=1 y TF_P5B_PROJECTS")
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let outDir = repo.appendingPathComponent("Temp")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let picks: [(project: String, track: String, tag: String)] = [
            ("El roce de tu cuerpo - Platero Y Tu", "Guitarra der.", "roce_guitder"),
            ("Megadeth - Tornado Of Souls", "Guitarra izq.", "tornado_guitizq"),
            ("Megadeth - Tornado Of Souls", "Guitarra der.", "tornado_guitder"),
            ("Megadeth - Tornado Of Souls", "Batería", "tornado_bateria")
        ]
        for pick in picks {
            let url = P5BProjects.project(pick.project).appendingPathComponent("tab/score.json")
            let score = try JSONDecoder().decode(TabScore.self, from: Data(contentsOf: url))
            guard let track = score.tracks.first(where: { $0.name == pick.track }) else {
                XCTFail("\(pick.project): sin pista \(pick.track)"); continue
            }
            let events = TabSynthRenderer.events(track: track, in: score, sampleRate: 44_100, delayFrames: 0,
                                                 totalFrames: Int(score.endTime * 44_100))
            let ons = events.filter { $0.status & 0xF0 == 0x90 }
            let written = track.kind == .drums ? track.hits.count : track.notes.count
            let out = outDir.appendingPathComponent("CHECK_5c_\(pick.tag).wav")
            try await TabSynthRenderer(soundFontURL: TabSynthTests.soundFont)
                .render(track: track, in: score, sampleRate: 44_100, duration: score.endTime, to: out)
            print("TabSynth CHECK \(pick.tag): \(written) notas/golpes escritos, \(ons.count) note-on, "
                  + "\(events.filter { $0.status & 0xF0 == 0xE0 }.count) eventos de rueda, rango "
                  + "\(events.first { $0.status & 0xF0 == 0xB0 && $0.data1 == 6 }.map { Int($0.data2) } ?? 2), "
                  + "\(Set(events.map { $0.status & 0x0F }).count) canales → \(out.path)")
        }
    }
}
