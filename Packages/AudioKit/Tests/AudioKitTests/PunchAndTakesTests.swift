import XCTest
@testable import AudioKit

/// Punch-in y varias pistas de toma (mini-spec Fase 6, «Punch-in» y «Partes y tomas»).
final class PunchAndTakesTests: XCTestCase {
    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("PunchAndTakesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func noise(_ n: Int, seed: UInt64, scale: Float = 0.5) -> [Float] {
        var g = SeededNoise(seed: seed)
        return (0..<n).map { _ in scale * Float(g.gaussian()) * 0.3 }
    }

    static func sine(_ n: Int, hz: Double, fs: Double, amplitude: Float = 0.5) -> [Float] {
        (0..<n).map { amplitude * Float(sin(2 * Double.pi * hz * Double($0) / fs)) }
    }

    // MARK: Aplanado

    /// Fuera del tramo, la original muestra a muestra (igualdad exacta); dentro, el punch exacto salvo los
    /// fundidos de 10 ms (441 y 480 muestras), que siguen la curva al error de redondeo de float; con dos
    /// punches que se pisan, el último manda en su tramo. A 44,1 y 48 kHz.
    func testFlattenKeepsOriginalOutsideAndCrossfadesTenMilliseconds() {
        for fs in [44_100.0, 48_000.0] {
            let f = PunchFlattener.crossfadeFrames(sampleRate: fs)
            XCTAssertEqual(f, fs == 48_000 ? 480 : 441)
            let baseStart = Int64(3 * fs)                       // la toma empieza a los 3 s
            let n = Int(10 * fs)
            let base = [Self.noise(n, seed: 1), Self.noise(n, seed: 2)]
            // Punch 1: tramo 5–8 s, grabado de 4 a 8,5 s (margen y 0,5 s tras la salida). Mono: va a los dos canales.
            let p1Start = Int64(4 * fs)
            let p1 = PunchAudio(start: Int64(5 * fs), end: Int64(8 * fs), songStartFrame: p1Start,
                                channels: [Self.noise(Int(4.5 * fs), seed: 3)])
            // Punch 2: tramo 7–9,25 s, pisa el final del 1.
            let p2Start = Int64(6.5 * fs)
            let p2 = PunchAudio(start: Int64(7 * fs), end: Int64(9.25 * fs), songStartFrame: p2Start,
                                channels: [Self.noise(Int(3.5 * fs), seed: 4), Self.noise(Int(3.5 * fs), seed: 5)])
            let out = PunchFlattener.flatten(base: base, baseStartFrame: baseStart, punches: [p1, p2], sampleRate: fs)
            XCTAssertEqual(out.map(\.count), [n, n])

            /// Valor del punch `p` (canal `c`) en la muestra del tema `song`; 0 fuera de su fichero.
            func value(_ p: PunchAudio, _ c: Int, _ song: Int64) -> Float {
                let ch = p.channels[min(c, p.channels.count - 1)], k = Int(song - p.songStartFrame)
                return k >= 0 && k < ch.count ? ch[k] : 0
            }
            /// Aplica un punch sobre `prev` en `song` según la regla: fundido de entrada, centro, fundido de salida.
            func apply(_ p: PunchAudio, _ c: Int, _ song: Int64, _ prev: Float) -> (Float, Bool) {
                guard song >= p.start, song < p.end else { return (prev, false) }
                let k = Int(song - p.start), span = Int(p.end - p.start), v = value(p, c, song)
                if k < f { let w = PunchFlattener.weight(k, f); return (prev * (1 - w) + v * w, true) }
                if k >= span - f { let w = PunchFlattener.weight(k - (span - f), f); return (v * (1 - w) + prev * w, true) }
                return (v, false)
            }
            var outsideMismatches = 0, insideMax: Float = 0, fadeMax: Float = 0
            for c in 0..<2 {
                for i in 0..<n {
                    let song = baseStart + Int64(i)
                    let o = out[c][i], b = base[c][i]
                    if song < p1.start || song >= p2.end {
                        if o != b { outsideMismatches += 1 }
                        continue
                    }
                    let (e1, fade1) = apply(p1, c, song, b)
                    let (e2, fade2) = apply(p2, c, song, e1)
                    let inP2 = song >= p2.start
                    // Dentro del tramo del último punch manda él; en sus fundidos importa lo que había antes.
                    if fade2 || (!inP2 && fade1) { fadeMax = max(fadeMax, abs(o - e2)) } else { insideMax = max(insideMax, abs(o - e2)) }
                }
            }
            // Curva: empieza cerca de 0, acaba cerca de 1, monótona.
            let w = (0..<f).map { PunchFlattener.weight($0, f) }
            XCTAssertLessThan(w.first!, 1e-4)
            XCTAssertGreaterThan(w.last!, 1 - 1e-4)
            XCTAssertTrue(zip(w, w.dropFirst()).allSatisfy { $0 < $1 })
            print(String(format: "F6 aplanado a %.0f Hz: fundido %d muestras; %d diferencias fuera; máx |error| dentro %.2e, en fundidos %.2e",
                         fs, f, outsideMismatches, insideMax, fadeMax))
            XCTAssertEqual(outsideMismatches, 0)
            XCTAssertEqual(insideMax, 0)
            XCTAssertLessThanOrEqual(fadeMax, 1e-6)
        }
    }

    /// Sobre ficheros: el resultado escrito es el de la función pura, y la original puede sobrescribirse.
    func testFlattenFilesMatchesPureFunction() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fs = 48_000.0
        let base = [Self.noise(Int(4 * fs), seed: 7)]
        let punch = [Self.noise(Int(2 * fs), seed: 8)]
        let baseURL = dir.appendingPathComponent("processed.wav"), punchURL = dir.appendingPathComponent("punch.wav")
        try TakeFile.write(base, sampleRate: fs, to: baseURL)
        try TakeFile.write(punch, sampleRate: fs, to: punchURL)
        let expected = PunchFlattener.flatten(
            base: base, baseStartFrame: Int64(10 * fs),
            punches: [PunchAudio(start: Int64(11 * fs), end: Int64(12.5 * fs), songStartFrame: Int64(10.75 * fs), channels: punch)],
            sampleRate: fs)
        try PunchFlattener.flattenFiles(base: baseURL, baseSongStart: 10,
                                        punches: [PunchFile(start: 11, end: 12.5, url: punchURL, songStart: 10.75)], to: baseURL)
        XCTAssertEqual(try TakeFile.read(baseURL), expected)
    }

    // MARK: Reproductor

    /// Ventana de un periodo de 1 kHz (48 muestras a 48 kHz) centrada en `at`.
    static func rms(_ x: [Float], at: Int, window: Int = 48) -> Double {
        let a = max(0, at - window / 2), b = min(x.count, a + window)
        guard b > a else { return 0 }
        return sqrt(x[a..<b].reduce(0) { $0 + Double($1) * Double($1) } / Double(b - a))
    }

    /// Punch-in al reproducir: la toma vieja suena entera hasta la entrada, se funde en 10 ms y queda en
    /// silencio. Medido en la salida offline con la toma sola (seno de 1 kHz a 0,5).
    @MainActor
    func testPunchInSilencesOldTakeWithTenMillisecondFade() throws {
        let fs = 48_000.0
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backing = dir.appendingPathComponent("backing.wav")
        try TakeFile.write([[Float](repeating: 0, count: Int(10 * fs))], sampleRate: fs, to: backing)
        let takeURL = dir.appendingPathComponent("take.wav")
        try TakeFile.write([Self.sine(Int(6 * fs), hz: 1_000, fs: fs)], sampleRate: fs, to: takeURL)
        let entry = 3.0, from = 2.0

        let p = StudyPlayer(offlineWith: nil)
        try p.load(tracks: [Track(id: "backing", url: backing)])
        try p.setTakes([TakeTrack(id: "Tú", url: takeURL, songStart: 1, silencedFrom: entry)])
        p.seek(to: from)
        try p.play()
        let r = try p.renderOffline(frames: Int(2 * fs))
        let y0 = p.runStartFrame - Double(r.start) + p.modelLatencyFrames
        func index(_ t: Double) -> Int { Int((y0 + (t - from) * fs).rounded()) }
        let x = r.channels[0]
        let full = 0.5 / 2.0.squareRoot()
        var before = Double.infinity, after = 0.0
        for t in stride(from: from + 0.1, through: entry - 0.001, by: 0.0005) { before = min(before, Self.rms(x, at: index(t))) }
        for t in stride(from: entry + 0.011 + 0.0005, through: from + 1.9, by: 0.0005) { after = max(after, Self.rms(x, at: index(t))) }
        let mid = Self.rms(x, at: index(entry + 0.005))
        print(String(format: "F6 punch-in al reproducir: RMS mín antes %.4f (lleno %.4f), a mitad del fundido %.4f, máx después %.2e",
                     before, full, mid, after))
        XCTAssertEqual(before, full, accuracy: 0.02 * full)
        XCTAssertEqual(mid, full * 0.5, accuracy: 0.1 * full)
        XCTAssertLessThan(after, 1e-4)
    }

    /// Varias pistas de toma: cada una con su canal (id, ganancia, mute, solo) en `tracks` y `meters`; los ids
    /// repetidos se rechazan; `setTake` sigue funcionando como antes.
    @MainActor
    func testSeveralTakeTracksWithGainMuteAndSolo() throws {
        let fs = 48_000.0
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backing = dir.appendingPathComponent("backing.wav")
        try TakeFile.write([[Float](repeating: 0, count: Int(6 * fs))], sampleRate: fs, to: backing)
        let a = dir.appendingPathComponent("a.wav"), b = dir.appendingPathComponent("b.wav")
        try TakeFile.write([Self.sine(Int(5 * fs), hz: 1_000, fs: fs)], sampleRate: fs, to: a)
        try TakeFile.write([Self.sine(Int(5 * fs), hz: 1_500, fs: fs)], sampleRate: fs, to: b)

        let p = StudyPlayer(offlineWith: nil)
        try p.load(tracks: [Track(id: "backing", url: backing)])
        XCTAssertThrowsError(try p.setTakes([TakeTrack(id: "backing", url: a, songStart: 0)]))
        XCTAssertThrowsError(try p.setTakes([TakeTrack(id: "x", url: a, songStart: 0), TakeTrack(id: "x", url: b, songStart: 0)]))
        try p.setTakes([TakeTrack(id: "Tú · Rítmica", url: a, songStart: 0.5), TakeTrack(id: "Tú · Solista", url: b, songStart: 0.5)])
        XCTAssertEqual(p.tracks.map(\.id), ["backing", "Tú · Rítmica", "Tú · Solista"])
        XCTAssertEqual(p.take?.id, "Tú · Rítmica")

        func level() throws -> Double {
            p.seek(to: 1)
            try p.play()
            let r = try p.renderOffline(frames: Int(1.5 * fs))
            p.pause()
            let x = r.channels[0][Int(0.6 * fs)..<Int(1.4 * fs)]
            return sqrt(x.reduce(0) { $0 + Double($1) * Double($1) } / Double(x.count))
        }
        let one = 0.5 / 2.0.squareRoot()
        let both = try level()
        p.setSolo("Tú · Rítmica", true)
        let soloA = try level()
        XCTAssertEqual(p.takes[0].solo, true)
        p.setSolo("Tú · Rítmica", false)
        p.setMute("Tú · Rítmica", true)
        let onlyB = try level()
        XCTAssertEqual(p.takes[0].muted, true)
        p.setMute("Tú · Rítmica", false)
        p.setGain("Tú · Solista", dB: -6)
        XCTAssertEqual(p.takes[1].gainDB, -6)
        let bQuiet = try level()
        print(String(format: "F6 dos tomas: RMS ambas %.4f, solo A %.4f, mute A %.4f, B a −6 dB %.4f", both, soloA, onlyB, bQuiet))
        XCTAssertEqual(both, (2 * one * one).squareRoot(), accuracy: 0.02)
        XCTAssertEqual(soloA, one, accuracy: 0.01)
        XCTAssertEqual(onlyB, one, accuracy: 0.01)
        let half = one * pow(10, -6.0 / 20)
        XCTAssertEqual(bQuiet, (one * one + half * half).squareRoot(), accuracy: 0.02)
        XCTAssertNotNil(p.meters["Tú · Solista"])

        try p.setTake(TakeTrack(id: "Tú", url: a, songStart: 0))
        XCTAssertEqual(p.tracks.map(\.id), ["backing", "Tú"])
        XCTAssertEqual(p.takes.count, 1)
    }
}
