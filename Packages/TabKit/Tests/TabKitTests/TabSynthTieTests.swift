import AVFoundation
import XCTest
@testable import TabKit

/// Ligadura de duración en la transcripción sonora (Fase 5c, tecla L, `TabTechniques.tieDestination`): la nota de
/// origen se prolonga hasta el final de la última ligada, sin note-on nuevo, en cadenas y con let ring, palm mute,
/// vibrato y bends (estos en el canal de su cuerda). 120 BPM a 48 kHz: pulso = 24 000 frames, tick = 2 000.
final class TabSynthTieTests: XCTestCase {
    typealias A = TabSynthAdornmentTests

    static func tied(_ id: Int, _ pitch: Int, string: Int, beat: Int, tick: Int = 0, ticks: Int = 12,
                     _ edit: @escaping (inout TabTechniques) -> Void = { _ in }) -> TabNote {
        A.note(id, pitch, string: string, beat: beat, tick: tick, ticks: ticks) { $0.tieDestination = true; edit(&$0) }
    }

    /// Cadena de tres (pulsos 0, 1 y 2): un note-on en 0 y su note-off en 72 000 (3 pulsos exactos); la continuación
    /// acentuada no ataca. Una nota igual sin ligadura detrás sí ataca, y no hay ligadura si cambia la altura o hay un
    /// hueco. Sin rueda (la ligadura sola no es curva: todo en el canal 0).
    func testTieChainSustainsWithoutNewAttack() throws {
        let events = try A.events([
            A.note(1, 60, string: 2, beat: 0),
            Self.tied(2, 60, string: 2, beat: 1) { $0.accent = .heavy },
            Self.tied(3, 60, string: 2, beat: 2),
            A.note(4, 60, string: 2, beat: 3),
            A.note(5, 64, string: 1, beat: 0, ticks: 48)
        ])
        XCTAssertEqual(A.noteSummary(events), ["0:on64v100", "0:on60v100", "72000:off60", "72000:on60v100",
                                               "96000:off64", "96000:off60"])
        XCTAssertFalse(events.contains { $0.status & 0xF0 == 0xE0 }, "sin rueda")
        XCTAssertTrue(events.allSatisfy { $0.status & 0x0F == 0 }, "sin canal por cuerda")
        // Altura distinta (62) y hueco de medio pulso: vuelven a atacar.
        let broken = try A.events([
            A.note(1, 60, string: 2, beat: 0),
            Self.tied(2, 62, string: 2, beat: 1),
            Self.tied(3, 62, string: 2, beat: 2, tick: 6, ticks: 6)
        ])
        XCTAssertEqual(A.noteSummary(broken), ["0:on60v100", "24000:off60", "24000:on62v100", "48000:off62",
                                               "60000:on62v100", "72000:off62"])
    }

    /// Las técnicas del origen que siguen sonando pasan a la cadena: con let ring, la última ligada suena hasta el fin
    /// del tramo (96 000) y no hasta su fin escrito (48 000); con palm mute, el origen no se acorta y la última dura el
    /// 45 % de su pulso (24 000 + 10 800). El tope de 4 s cuenta desde el ataque del origen: una cadena de 6 pulsos
    /// en un tramo let ring de 10 acaba en 192 000, no en 120 000 + 192 000.
    func testTieChainKeepsLetRingPalmMuteAndCapsFromOriginAttack() throws {
        let ring = try A.events([
            A.note(1, 57, string: 3, beat: 0) { $0.letRing = true },
            Self.tied(2, 57, string: 3, beat: 1),
            A.note(3, 60, string: 2, beat: 1, ticks: 36) { $0.letRing = true }
        ])
        XCTAssertEqual(A.noteSummary(ring), ["0:on57v100", "24000:on60v100", "96000:off60", "96000:off57"])
        let muted = try A.events([A.note(1, 45, string: 5, beat: 0) { $0.palmMute = true },
                                  Self.tied(2, 45, string: 5, beat: 1)])
        XCTAssertEqual(A.noteSummary(muted), ["0:on45v100", "34800:off45"])
        var long = [A.note(1, 64, string: 1, beat: 0) { $0.letRing = true }]
        for b in 1...5 { long.append(Self.tied(b + 1, 64, string: 1, beat: b)) }
        long.append(A.note(7, 59, string: 2, beat: 5, ticks: 60) { $0.letRing = true })
        XCTAssertEqual(A.noteSummary(try A.events(long, bars: 3)),
                       ["0:on64v100", "120000:on59v100", "192000:off64", "240000:off59"])
    }

    /// Con curvas cada cuerda va a su canal. Vibrato en el origen (cuerda 2, canal 1): la ligada lo hereda y su fase
    /// sigue contando desde el ataque del origen (cada punto de 0 a 48 000 es 0,25·sin(2π·5,5·(t − 0,2)), ±1e-3
    /// semitonos), sin volver a esperar los 0,2 s. Bend de un tono en el origen (cuerda 3, canal 2): la ligada sin bend
    /// lo mantiene en +2 y la siguiente con release baja de +2 a 0. Un note-on por cuerda; la cuerda 1 sin rueda.
    func testTieChainCarriesVibratoAndBendOnItsStringChannel() throws {
        let full = TabBend(points: [.init(position: 0, value: 0), .init(position: 60, value: 4)])
        let release = TabBend(points: [.init(position: 0, value: 4), .init(position: 60, value: 0)])
        let events = try A.events([
            A.note(1, 64, string: 1, beat: 0, ticks: 48),
            A.note(2, 60, string: 2, beat: 0) { $0.vibrato = .slight },
            Self.tied(3, 60, string: 2, beat: 1),
            A.note(4, 55, string: 3, beat: 0) { $0.bend = full },
            Self.tied(5, 55, string: 3, beat: 1),
            Self.tied(6, 55, string: 3, beat: 2) { $0.bend = release }
        ])
        let ons = events.filter { $0.status & 0xF0 == 0x90 }.map { "\($0.status & 0x0F):\($0.data1)@\($0.frame)" }
        XCTAssertEqual(ons, ["0:64@0", "1:60@0", "2:55@0"])
        XCTAssertEqual(events.first { $0.status == 0x81 }?.frame, 48_000)
        XCTAssertEqual(events.first { $0.status == 0x82 }?.frame, 72_000)
        XCTAssertTrue(A.bends(events, channel: 0).isEmpty)

        let vib = A.bends(events, channel: 1).filter { $0.frame < 48_000 }
        XCTAssertGreaterThan(vib.filter { $0.frame >= 24_000 }.count, 30)
        var worst = 0.0
        for p in vib {
            let t = Double(p.frame) / A.rate
            let want = t > 0.2 ? 0.25 * sin(2 * .pi * 5.5 * (t - 0.2)) : 0
            worst = max(worst, abs(p.semitones - want))
        }
        XCTAssertLessThan(worst, 1e-3, "vibrato continuo a través de la ligadura")
        let afterTie = try XCTUnwrap(vib.first { $0.frame >= 24_000 })
        XCTAssertGreaterThan(abs(afterTie.semitones), 0.1, "sin retraso nuevo en la ligada")

        let bend = A.bends(events, channel: 2)
        // Puntos cada 576 frames: el último del origen (23 616) va por el 98,4 % de la subida.
        XCTAssertEqual(try XCTUnwrap(bend.first { $0.frame == 23_616 }).semitones, 2 * 23_616 / 24_000, accuracy: 1e-3)
        let held = bend.filter { $0.frame >= 24_000 && $0.frame < 48_000 }
        XCTAssertGreaterThan(held.count, 30)
        XCTAssertTrue(held.allSatisfy { abs($0.semitones - 2) < 1e-3 }, "bend mantenido en la ligada")
        XCTAssertEqual(try XCTUnwrap(bend.first { $0.frame == 48_000 }).semitones, 2, accuracy: 1e-3)
        XCTAssertEqual(try XCTUnwrap(bend.first { $0.frame == 71_616 }).semitones, 2 * (1 - 23_616.0 / 24_000),
                       accuracy: 1e-3)
        XCTAssertEqual(bend.last?.frame, 72_000)
        XCTAssertEqual(bend.last?.semitones ?? 1, 0, accuracy: 1e-3)
    }

    /// En el WAV (guitarra limpia, cuerda 5, nota 52): cadena ligada en los pulsos 0–2 y las mismas notas sin
    /// ligadura en los pulsos 4–6. En la cadena el nivel justo después de cada unión no sube sobre el de justo antes
    /// (< 1,2); sin ligadura sí (> 1,5). Con TF_5C_CHECK_WAV=1 deja el WAV en `Temp/CHECK_5c_tie_chain.wav`.
    func testTieChainSoundsWithoutAttackInWav() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: TabSynthTests.soundFont.path))
        let score = try TabSynthTests.constantScore(bpm: 120, bars: 2)
        let notes = [A.note(1, 52, string: 5, beat: 0), Self.tied(2, 52, string: 5, beat: 1),
                     Self.tied(3, 52, string: 5, beat: 2),
                     A.note(4, 52, string: 5, beat: 4), A.note(5, 52, string: 5, beat: 5),
                     A.note(6, 52, string: 5, beat: 6)]
        let track = TabSynthTests.pitchedTrack(score, kind: .guitar, notes: notes)
        let events = TabSynthRenderer.events(track: track, in: score, sampleRate: A.rate, delayFrames: 0,
                                             totalFrames: 192_000)
        XCTAssertEqual(A.noteSummary(events), ["0:on52v100", "72000:off52", "96000:on52v100", "120000:off52",
                                               "120000:on52v100", "144000:off52", "144000:on52v100", "168000:off52"])
        let env = ProcessInfo.processInfo.environment
        let dir: URL
        if env["TF_5C_CHECK_WAV"] == "1" {
            dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Temp")
        } else {
            dir = FileManager.default.temporaryDirectory.appendingPathComponent("tabsynth-tie-\(UUID().uuidString)")
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("CHECK_5c_tie_chain.wav")
        defer { if env["TF_5C_CHECK_WAV"] != "1" { try? FileManager.default.removeItem(at: dir) } }
        try await TabSynthRenderer(soundFontURL: TabSynthTests.soundFont, guitarSound: .clean)
            .render(track: track, in: score, sampleRate: A.rate, duration: 4, to: url)
        let x = try TabSynthTests.read(url).channels[0]
        func jump(at f: Int) -> Float { A.rms(x, from: f, n: 960) / A.rms(x, from: f - 960, n: 960) }
        let tied = [jump(at: 24_000), jump(at: 48_000)], attacked = [jump(at: 120_000), jump(at: 144_000)]
        print("TabSynth ligadura: nivel tras/antes en las uniones ligadas \(tied), sin ligadura \(attacked) → \(url.path)")
        for j in tied { XCTAssertLessThan(j, 1.2) }
        for j in attacked { XCTAssertGreaterThan(j, 1.5) }
    }
}
