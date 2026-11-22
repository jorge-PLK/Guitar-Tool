import NativeDSP
import XCTest
@testable import AudioKit

/// Pruebas de §4 P6 en render offline con señales sintéticas (48 kHz). Ninguna suena. `kind` elige el motor: el de
/// la plataforma aquí; el portátil en `PortableStudyPlayerTests` (solo Mac; en Windows el de la plataforma ya es ese).
class StudyPlayerTests: XCTestCase {
    var kind: PlayerKind { .platform }
    static let sr = 48_000.0
    var sr: Double { Self.sr }

    // MARK: Señales y medidas

    func zeros(_ seconds: Double) -> [Float] { [Float](repeating: 0, count: Int(seconds * sr)) }

    func sine(_ seconds: Double, _ hz: Double, _ amp: Float) -> [Float] {
        (0..<Int(seconds * sr)).map { amp * Float(sin(2 * Double.pi * hz * Double($0) / Self.sr)) }
    }

    /// Ráfaga de 2 ms a 3 kHz con ventana de Hann, centrada en `t` segundos.
    func addBurst(_ x: inout [Float], at t: Double) {
        let len = 96, c = Int((t * sr).rounded())
        for k in 0..<len {
            let w = 0.5 - 0.5 * cos(2 * Double.pi * Double(k) / Double(len))
            x[c - len / 2 + k] += Float(w * sin(2 * Double.pi * 3_000 * Double(k) / sr))
        }
    }

    /// Centroide de energía en `[c − half, c + half)`.
    func centroid(_ x: [Float], around c: Double, half: Int) -> Double {
        let lo = max(0, Int(c) - half), hi = min(x.count, Int(c) + half)
        var e = 0.0, ex = 0.0
        for j in lo..<hi { let v = Double(x[j]) * Double(x[j]); e += v; ex += v * Double(j) }
        return ex / e
    }

    /// Amplitud de la componente a `hz` en `[from, from + n)` (n con periodos enteros).
    func amplitude(_ x: [Float], hz: Double, from: Int, n: Int) -> Double {
        var re = 0.0, im = 0.0
        for j in 0..<n {
            let ph = 2 * Double.pi * hz * Double(j) / sr
            re += Double(x[from + j]) * cos(ph)
            im += Double(x[from + j]) * sin(ph)
        }
        return 2 * sqrt(re * re + im * im) / Double(n)
    }

    /// Frecuencia por cruces por cero ascendentes interpolados.
    func frequency(_ x: [Float], from: Int, to: Int) -> Double {
        var crossings: [Double] = []
        for j in from..<(to - 1) where x[j] <= 0 && x[j + 1] > 0 {
            crossings.append(Double(j) + Double(-x[j] / (x[j + 1] - x[j])))
        }
        return Double(crossings.count - 1) / ((crossings.last! - crossings.first!) / sr)
    }

    /// RMS en ventanas de 2,5 ms, en dB respecto a la mediana: (mín, máx).
    func envelopeRange(_ x: [Float], from: Int, to: Int) -> (Double, Double) {
        let w = 120
        var rms: [Double] = []
        var j = from
        while j + w <= to {
            var ms: Float = 0
            x.withUnsafeBufferPointer { DSP.measqv($0.baseAddress! + j, 1, &ms, DSPLength(w)) }
            rms.append(Double(sqrt(ms)))
            j += w
        }
        let med = rms.sorted()[rms.count / 2]
        let db = rms.map { 20 * log10(max($0, 1e-9) / med) }
        return (db.min()!, db.max()!)
    }

    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("StudyPlayerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func writeStem(_ name: String, in dir: URL, left: [Float], right: [Float]) throws -> Track {
        let url = dir.appendingPathComponent("\(name).wav")
        try TakeFile.write([left, right], sampleRate: sr, to: url)   // WAV float32, como antes con AVAudioFile
        return Track(id: name, url: url)
    }

    @MainActor
    func makePlayer(_ stems: [(String, [Float], [Float])], devices: (any AudioDeviceProviding)? = nil) throws
        -> (any PlayerUnderTest, URL) {
        let dir = try tempDir()
        let tracks = try stems.map { try writeStem($0.0, in: dir, left: $0.1, right: $0.2) }
        let p = kind.offline(devices: devices)
        try p.load(tracks: tracks)
        return (p, dir)
    }

    /// Índice, dentro de lo renderizado, de la muestra de arranque de la pasada.
    @MainActor
    func runIndex(_ p: any PlayerUnderTest, _ start: Int64) -> Double { p.runStartFrame - Double(start) }

    // MARK: Fin por muestras

    /// `endTime` («Ver toma», W2-V): backing de 3 s (0,25) y una toma de 1 s (0,5) desde 0,7 s, como abre el visor
    /// (fin = inicio de la toma + su duración). Desde 0,5 s, lo último que suena es la muestra anterior al fin, ni una
    /// más, con un fin que cae a mitad de trozo; y sin `endTime` vuelve a sonar hasta el final del tema.
    @MainActor
    func testEndTimeStopsAtTheExactSample() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backing = try writeStem("backing", in: dir, left: [Float](repeating: 0.25, count: Int(3 * sr)),
                                    right: [Float](repeating: 0.25, count: Int(3 * sr)))
        let takeURL = dir.appendingPathComponent("take.wav")
        try TakeFile.write([[Float](repeating: 0.5, count: Int(sr))], sampleRate: sr, to: takeURL)
        let takeStart = 0.7, from = 0.5
        let end = takeStart + 1.0
        let endFrame = Int((end * sr).rounded())
        let p = kind.offline()
        try p.load(tracks: [backing])
        p.endTime = end   // antes de `setTake`: debe sobrevivir a la recarga
        try p.setTake(TakeTrack(id: "take", url: takeURL, songStart: takeStart))
        XCTAssertEqual(p.endTime, end)
        p.seek(to: from)
        try p.play()
        let r = try p.renderOffline(frames: Int(1.6 * sr))
        let out = r.channels[0]
        // Índice de la muestra del tema `from` en lo renderizado.
        let i0 = Int((runIndex(p, r.start) + p.modelLatencyFrames).rounded())
        let first = i0 - Int((from * sr).rounded())   // índice que tendría la muestra 0 del tema
        let last = try XCTUnwrap(out.lastIndex { abs($0) > 1e-6 })
        let overshoot = (last + 1) - (first + endFrame)
        print("W2-V fin por muestras (\(kind.rawValue)): última muestra con sonido \(last + 1 - first), fin \(endFrame) → sobrante "
              + "\(overshoot) muestras (\(String(format: "%.3f", Double(overshoot) / sr * 1000)) ms)")
        XCTAssertEqual(overshoot, 0, "ni una muestra de backing tras el fin")
        XCTAssertEqual(out[first + endFrame - 1], 0.75, accuracy: 1e-4, "hasta el fin suenan backing y toma enteros")
        XCTAssertEqual(out[first + endFrame - Int(0.5 * sr)], 0.75, accuracy: 1e-4)
        XCTAssertTrue(out[(first + endFrame)...].allSatisfy { $0 == 0 }, "tras el fin, silencio")

        p.endTime = nil
        p.seek(to: from)
        let s = try p.renderOffline(frames: Int(1.6 * sr))
        let j0 = Int((runIndex(p, s.start) + p.modelLatencyFrames).rounded()) - Int((from * sr).rounded())
        XCTAssertEqual(s.channels[0][j0 + endFrame + Int(0.2 * sr)], 0.25, accuracy: 1e-4, "sin endTime sigue el backing")
    }

    // MARK: Sincronía, mute/solo, ganancia

    @MainActor
    func testImpulsesFromSixStemsComeOutInTheSameSample() throws {
        var x = zeros(1)
        x[12_000] = 0.1
        let (p, dir) = try makePlayer((0..<6).map { ("s\($0)", x, x) })
        defer { try? FileManager.default.removeItem(at: dir) }
        try p.play()
        let r = try p.renderOffline(frames: Int(sr))
        let out = r.channels[0]
        let peak = out.indices.max { abs(out[$0]) < abs(out[$1]) }!
        let lat = Int(p.modelLatencyFrames.rounded())   // retardo del Varispeed a rate 1
        let expected = Int(runIndex(p, r.start)) + lat + 12_000
        let rest = out.enumerated().reduce(0.0) { $0 + ($1.offset == peak ? 0 : Double($1.element * $1.element)) }
        print("P6 impulso: pico en \(peak - Int(runIndex(p, r.start))) (esperado 12000 + \(lat)), valor \(out[peak]), energía fuera \(rest)")
        XCTAssertEqual(peak, expected)
        XCTAssertEqual(out[peak], 0.6, accuracy: 1e-5)
        XCTAssertLessThan(rest, 1e-10)
        for k in 0..<6 {
            for j in 0..<6 { p.setSolo("s\(j)", j == k) }
            p.seek(to: 0)
            let s = try p.renderOffline(frames: 24_000)
            let i = Int(runIndex(p, s.start)) + lat + 12_000
            XCTAssertEqual(s.channels[0][i], 0.1, accuracy: 1e-6, "stem \(k)")
        }
    }

    @MainActor
    func testMuteAndSolo() throws {
        let freqs = [300.0, 500, 700, 900, 1_100, 1_300]
        let (p, dir) = try makePlayer(freqs.enumerated().map { ("s\($0.offset)", sine(5, $0.element, 0.1), sine(5, $0.element, 0.1)) })
        defer { try? FileManager.default.removeItem(at: dir) }
        try p.play()
        func levels() throws -> [Double] {
            _ = try p.renderOffline(frames: 9_600)   // los cambios de mezcla se oyen ~0,1 s después
            let r = try p.renderOffline(frames: 24_000)
            return freqs.map { amplitude(r.channels[0], hz: $0, from: 0, n: 24_000) }
        }
        func check(_ audible: Set<Int>, _ label: String) throws {
            let a = try levels()
            for i in 0..<6 {
                if audible.contains(i) {
                    XCTAssertEqual(a[i], 0.1, accuracy: 1e-3, "\(label): s\(i) debería sonar")
                } else {
                    XCTAssertLessThan(a[i], 1e-5, "\(label): s\(i) debería callar")
                }
            }
        }
        try check(Set(0..<6), "todo")
        p.setMute("s1", true)
        try check([0, 2, 3, 4, 5], "mute s1")
        p.setMute("s1", false)
        p.setSolo("s3", true)
        try check([3], "solo s3")
        p.setSolo("s5", true)
        try check([3, 5], "solo s3+s5")
        p.setMute("s3", true)
        try check([5], "solo s3+s5, mute s3")
        p.setSolo("s5", false)
        try check([], "solo s3 muteado")
    }

    @MainActor
    func testGainWithinAPointOneDB() throws {
        let (p, dir) = try makePlayer([("s0", sine(4, 1_000, 0.25), sine(4, 1_000, 0.25))])
        defer { try? FileManager.default.removeItem(at: dir) }
        try p.play()
        var worst = 0.0
        for g in [6.0, -12.5, -30, 0] {
            p.setGain("s0", dB: g)
            _ = try p.renderOffline(frames: 9_600)
            let r = try p.renderOffline(frames: 24_000)
            let measured = 20 * log10(amplitude(r.channels[0], hz: 1_000, from: 0, n: 24_000) / 0.25)
            worst = max(worst, abs(measured - g))
            XCTAssertEqual(measured, g, accuracy: 0.1, "ganancia \(g) dB")
        }
        print("P6 ganancia: error máximo \(worst) dB")
    }

    @MainActor
    func testMasterGainAffectsStemsAndClickWithinAPointOneDB() throws {
        let (p, dir) = try makePlayer([("s0", sine(4, 1_000, 0.25), sine(4, 1_000, 0.25))])
        defer { try? FileManager.default.removeItem(at: dir) }
        p.metronome = Metronome(clicks: [Click(time: 1.0, accent: true)], isEnabled: true, gainDB: 0)
        func peak(_ x: [Float], _ range: Range<Int>) -> Double { Double(range.map { abs(x[$0]) }.max() ?? 0) }
        // Pasada de referencia: stem solo (primer medio segundo) y clic solo (con el stem silenciado).
        var stemRef = 0.0, clickRef = 0.0
        for master in [0.0, -6, 4.5] {
            p.masterGainDB = master
            p.setMute("s0", false)
            p.seek(to: 0)
            try p.play()
            let a = try p.renderOffline(frames: 24_000)
            p.pause()
            let stem = amplitude(a.channels[0], hz: 1_000, from: 4_800, n: 19_200)
            p.setMute("s0", true)
            p.seek(to: 0.9)
            try p.play()
            let b = try p.renderOffline(frames: 24_000)
            p.pause()
            let click = peak(b.channels[0], 0..<24_000)
            if master == 0 { stemRef = stem; clickRef = click; continue }
            XCTAssertEqual(20 * log10(stem / stemRef), master, accuracy: 0.1, "stem a \(master) dB")
            XCTAssertEqual(20 * log10(click / clickRef), master, accuracy: 0.1, "clic a \(master) dB")
        }
        XCTAssertGreaterThan(clickRef, 0.01)
    }

    @MainActor
    func testMetersFollowTheChannel() async throws {
        let (p, dir) = try makePlayer([("s0", sine(2, 1_000, 0.5), sine(2, 1_000, 0.5)), ("s1", zeros(2), zeros(2))])
        defer { try? FileManager.default.removeItem(at: dir) }
        try p.play()
        _ = try p.renderOffline(frames: 24_000)
        for _ in 0..<50 where p.meters["s0"] == .silent { try await Task.sleep(for: .milliseconds(10)) }
        let m = try XCTUnwrap(p.meters["s0"])
        XCTAssertEqual(m.peakDB, -6.02, accuracy: 0.2)
        XCTAssertEqual(m.rmsDB, -9.03, accuracy: 0.2)
        XCTAssertEqual(p.meters["s1"]?.peakDB ?? -120, -120, accuracy: 1)
    }

    // MARK: Velocidad y tono

    @MainActor
    func testRate70StretchesTenSecondsTo14_286() throws {
        var x = zeros(12)
        addBurst(&x, at: 1)
        addBurst(&x, at: 11)
        let (p, dir) = try makePlayer([("s0", x, x)])
        defer { try? FileManager.default.removeItem(at: dir) }
        p.rate = 0.7
        try p.play()
        let r = try p.renderOffline(frames: Int(17 * sr))
        let i0 = runIndex(p, r.start) + p.modelLatencyFrames
        let c1 = centroid(r.channels[0], around: i0 + 1 * sr / 0.7, half: 4_800)
        let c2 = centroid(r.channels[0], around: i0 + 11 * sr / 0.7, half: 4_800)
        let span = (c2 - c1) / sr
        print("P6 70 %: 10 s → \(span) s (esperado \(10 / 0.7)), error \((span - 10 / 0.7) * 1_000) ms; " +
              "desfase absoluto frente al modelo \((c1 - (i0 + sr / 0.7)) / sr * 1_000) ms")
        XCTAssertEqual(span, 10 / 0.7, accuracy: 0.010)
    }

    @MainActor
    func testPitchPlus200CentsTurns440Into493_9() throws {
        let (p, dir) = try makePlayer([("s0", sine(4, 440, 0.5), sine(4, 440, 0.5))])
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = 440 * pow(2, 200.0 / 1_200)
        p.pitchCents = 200
        try p.play()
        let r = try p.renderOffline(frames: Int(2.5 * sr))
        let f1 = frequency(r.channels[0], from: Int(1 * sr), to: Int(2 * sr))
        p.pause()
        p.rate = 0.7
        p.seek(to: 0)
        try p.play()
        let s = try p.renderOffline(frames: Int(3 * sr))
        let f2 = frequency(s.channels[0], from: Int(1 * sr), to: Int(2.5 * sr))
        print("P6 +200 cents: \(f1) Hz a 100 %, \(f2) Hz a 70 % (esperado \(target))")
        XCTAssertEqual(f1, target, accuracy: 1)
        XCTAssertEqual(f2, target, accuracy: 1)
    }

    func testRateQuantizationIsCorrectedByVarispeed() {
        let s = TimePitchSetting(rate: 0.7)
        XCTAssertEqual(Double(s.timePitchRate), 179.0 / 256)
        XCTAssertEqual(Double(s.timePitchRate) * Double(s.varispeedRate), 0.7, accuracy: 1e-7)
        XCTAssertEqual(TimePitchSetting(rate: 0.75).varispeedRate, 1)
        XCTAssertEqual(TimePitchSetting(rate: 1).varispeedRate, 1)
        XCTAssertEqual(TimePitchSetting(rate: 3).rate, 2)
    }

    // MARK: Bucle

    @MainActor
    func testLoopAt70HasThreeLapsOf2_857WithoutGaps() throws {
        var bursts = zeros(6)
        addBurst(&bursts, at: 3)
        let tone = sine(6, 400, 0.3)   // 400 Hz: periodo de 2,5 ms, continuo en los cortes
        let (p, dir) = try makePlayer([("marks", bursts, bursts), ("tone", tone, tone)])
        defer { try? FileManager.default.removeItem(at: dir) }
        p.rate = 0.7
        p.loop = 2.0...4.0
        p.setMute("tone", true)
        p.seek(to: 1)
        try p.play()
        let a = try p.renderOffline(frames: Int(12.5 * sr))
        let i0 = runIndex(p, a.start) + p.modelLatencyFrames
        let lap = 2 / 0.7
        var hits: [Double] = []
        for n in 0..<4 {
            hits.append(centroid(a.channels[0], around: i0 + (2 / 0.7 + Double(n) * lap) * sr, half: 4_800))
        }
        let laps = zip(hits.dropFirst(), hits).map { ($0 - $1) / sr }
        let lapErr = laps.map { abs($0 - lap) * 1_000 }.max()!
        let timeErr = hits.map { abs(p.songTime(atOutputFrame: Double(a.start) + $0) - 3) * 1_000 }.max()!
        print("P6 bucle 70 %: vueltas \(laps) s (esperado \(lap)), error máx \(lapErr) ms; currentTime en la marca ±\(timeErr) ms")
        for l in laps { XCTAssertEqual(l, lap, accuracy: 0.002) }
        XCTAssertLessThan(timeErr, 5)

        p.setMute("tone", false)
        p.setMute("marks", true)
        p.seek(to: 1)
        let b = try p.renderOffline(frames: Int(12.5 * sr))
        let j0 = Int(runIndex(p, b.start)) + Int(0.3 * sr)
        let (lo, hi) = envelopeRange(b.channels[0], from: j0, to: b.channels[0].count)
        let peak = b.channels[0][j0...].map { abs($0) }.max()!
        print("P6 bucle 70 %: envolvente de 2,5 ms entre \(lo) y \(hi) dB, pico \(peak)")
        XCTAssertGreaterThan(lo, -1)
        XCTAssertLessThan(hi, 1)
        XCTAssertLessThan(peak, 0.3 * 1.12)
    }

    @MainActor
    func testLoopIsSampleExactAtRate1() throws {
        var seed: UInt32 = 12_345
        let noise: [Float] = (0..<Int(3 * sr)).map { _ in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(Int32(bitPattern: seed)) / Float(Int32.max) * 0.5
        }
        let (p, dir) = try makePlayer([("n", noise, noise)])
        defer { try? FileManager.default.removeItem(at: dir) }
        p.loop = 1.0...1.5
        p.seek(to: 0.9)
        try p.play()
        let r = try p.renderOffline(frames: Int(2 * sr))
        let h = Int(p.halfFadeFrames)
        XCTAssertEqual(h, 120)   // 5 ms de fundido cruzado a 48 kHz
        let a = 48_000, b = 72_000
        var expected = Array(noise[43_200..<(b - h)])
        while expected.count < Int(1.9 * sr) {
            for i in 0..<(2 * h) {
                let w = Crossfade.weight(i, 2 * h)   // = StemScheduler.crossfadeWeight
                expected.append(noise[b - h + i] * (1 - w) + noise[a - h + i] * w)
            }
            expected.append(contentsOf: noise[(a + h)..<(b - h)])
        }
        let i0 = Int(runIndex(p, r.start)) + Int(p.modelLatencyFrames.rounded())
        var worst: Float = 0
        // Los primeros ~30 ms tras arrancar los suaviza el TimePitch recién reiniciado; desde ahí, exacto.
        for j in 2_400..<Int(1.9 * sr) { worst = max(worst, abs(r.channels[0][i0 + j] - expected[j])) }
        print("P6 bucle 100 %: error máximo frente a la secuencia esperada \(worst) (vuelta = 24000 muestras)")
        XCTAssertLessThan(worst, 1e-6)
    }

    @MainActor
    func testChangingAndRemovingTheLoopWhilePlayingHasNoCuts() throws {
        let tone = sine(8, 400, 0.3)
        let (p, dir) = try makePlayer([("tone", tone, tone)])
        defer { try? FileManager.default.removeItem(at: dir) }
        p.loop = 1.0...2.0
        p.seek(to: 1)
        try p.play()
        var out = try p.renderOffline(frames: Int(1.5 * sr))
        let start = Int(runIndex(p, out.start)) + 2_400
        XCTAssertEqual(p.currentTime, 1.5, accuracy: 0.002)
        func more(_ seconds: Double) throws -> Double {
            let r = try p.renderOffline(frames: Int(seconds * sr))
            for ch in 0..<2 { out.channels[ch] += r.channels[ch] }
            return p.currentTime
        }
        p.loop = 3.0...3.5      // por delante: se toca hasta él
        let ahead = try more(3)
        p.loop = 1.0...1.5      // por detrás: salta a su inicio
        let behind = try more(1.5)
        p.loop = nil
        let free = try more(1.5)
        let (lo, hi) = envelopeRange(out.channels[0], from: start, to: out.channels[0].count)
        print("P6 cambio de bucle: \(ahead) s en [3, 3,5), \(behind) s en [1, 1,5), \(free) s sin bucle; envolvente \(lo)…\(hi) dB")
        XCTAssertTrue((3.0..<3.5).contains(ahead))
        XCTAssertTrue((1.0..<1.5).contains(behind))
        XCTAssertGreaterThan(free, 1.5)
        XCTAssertGreaterThan(lo, -1)
        XCTAssertLessThan(hi, 1)
    }

    // MARK: Tiempo y metrónomo

    @MainActor
    func testCurrentTimeAt70WithinFiveMs() throws {
        var x = zeros(10)
        let marks = stride(from: 0.5, through: 9.5, by: 0.5).map { $0 }
        for t in marks { addBurst(&x, at: t) }
        let (p, dir) = try makePlayer([("s0", x, x)])
        defer { try? FileManager.default.removeItem(at: dir) }
        p.rate = 0.7
        p.seek(to: 0.3)
        try p.play()
        let r = try p.renderOffline(frames: Int(14 * sr))
        let i0 = runIndex(p, r.start) + p.modelLatencyFrames
        var worst = 0.0
        for t in marks {
            let c = centroid(r.channels[0], around: i0 + (t - 0.3) * sr / 0.7, half: 2_400)
            worst = max(worst, abs(p.songTime(atOutputFrame: Double(r.start) + c) - t) * 1_000)
        }
        let end = Double(r.start) + Double(r.channels[0].count)
        print("P6 currentTime 70 %: error máximo \(worst) ms en \(marks.count) marcas")
        XCTAssertLessThan(worst, 5)
        XCTAssertEqual(p.currentTime, p.songTime(atOutputFrame: end), accuracy: 1e-9)
    }

    /// Busca la plantilla de clic (normal o acento) cerca de `expected`: índice y si es acento.
    func findClick(_ x: [Float], near expected: Double, templates: [[Float]]) -> (Int, Bool) {
        var best = (Int(expected), false, Float.infinity)
        for (ti, t) in templates.enumerated() {
            for o in (Int(expected) - 480)...(Int(expected) + 480) {
                var sse: Float = 0
                for j in 0..<t.count { let d = x[o + j] - t[j]; sse += d * d }
                if sse < best.2 { best = (o, ti == 1, sse) }
            }
        }
        return (best.0, best.1)
    }

    @MainActor
    func testClicksLandAt_BeatMinusStart_Over0_7() throws {
        let beats = (0..<10).map { 1.5 + 0.5 * Double($0) }
        var marks = zeros(8)
        for t in beats { addBurst(&marks, at: t) }
        let (p, dir) = try makePlayer([("marks", marks, marks)])
        defer { try? FileManager.default.removeItem(at: dir) }
        let templates = [ClickSynth.template(accent: false, sampleRate: sr), ClickSynth.template(accent: true, sampleRate: sr)]
        p.metronome = Metronome(clicks: beats.enumerated().map { Click(time: $0.element, accent: $0.offset % 4 == 0) },
                                isEnabled: true, gainDB: 0)
        p.setMute("marks", true)
        p.rate = 0.7
        p.seek(to: 1.3)
        try p.play()
        let r = try p.renderOffline(frames: Int(7.5 * sr))
        let i0 = runIndex(p, r.start) + p.modelLatencyFrames
        var worst = 0.0
        var onsets: [Int] = []
        for (k, t) in beats.enumerated() {
            let e = i0 + (t - 1.3) * sr / 0.7
            let (o, acc) = findClick(r.channels[0], near: e, templates: templates)
            onsets.append(o)
            worst = max(worst, abs(Double(o) - e))
            XCTAssertEqual(acc, k % 4 == 0, "acento del clic \(k)")
        }
        print("P6 clics 70 %: error máximo \(worst) muestras (\(worst / sr * 1_000) ms)")
        XCTAssertLessThan(worst / sr, 0.001)

        // Cuadrado con la música: mismas pasadas, sin metrónomo y con las marcas en los pulsos.
        var m = p.metronome
        m.isEnabled = false
        p.metronome = m
        p.setMute("marks", false)
        p.seek(to: 1.3)
        let s = try p.renderOffline(frames: Int(7.5 * sr))
        let j0 = runIndex(p, s.start) + p.modelLatencyFrames
        var align = 0.0
        for (k, t) in beats.enumerated() {
            let c = centroid(s.channels[0], around: j0 + (t - 1.3) * sr / 0.7, half: 2_400)
            let clickAtSameRun = Double(onsets[k]) - i0 + j0
            align = max(align, abs(c - clickAtSameRun) / sr * 1_000)
        }
        print("P6 clics frente a la música estirada: desfase máximo \(align) ms")
        XCTAssertLessThan(align, 5)
    }

    @MainActor
    func testClicksStaySquareInTheLoop() throws {
        let beats = (0..<10).map { 1.5 + 0.5 * Double($0) }
        let (p, dir) = try makePlayer([("s0", zeros(8), zeros(8))])
        defer { try? FileManager.default.removeItem(at: dir) }
        let templates = [ClickSynth.template(accent: false, sampleRate: sr), ClickSynth.template(accent: true, sampleRate: sr)]
        p.metronome = Metronome(clicks: beats.enumerated().map { Click(time: $0.element, accent: $0.offset % 4 == 0) },
                                isEnabled: true, gainDB: 0)
        p.rate = 0.7
        p.loop = 2.0...4.0
        p.seek(to: 1.3)
        try p.play()
        let r = try p.renderOffline(frames: Int(10 * sr))
        let i0 = runIndex(p, r.start) + p.modelLatencyFrames
        var expected: [(Double, Bool)] = []
        for lap in 0..<3 {
            for (k, t) in beats.enumerated() where t < 4 && (lap == 0 ? t >= 1.3 : t >= 2) {
                expected.append(((t - 1.3 + 2 * Double(lap)) * sr / 0.7, k % 4 == 0))
            }
        }
        var worst = 0.0
        for (e, accent) in expected {
            let (o, acc) = findClick(r.channels[0], near: i0 + e, templates: templates)
            worst = max(worst, abs(Double(o) - (i0 + e)))
            XCTAssertEqual(acc, accent)
        }
        print("P6 clics en bucle 70 %: \(expected.count) clics, error máximo \(worst) muestras")
        XCTAssertLessThan(worst / sr, 0.001)
    }

    // MARK: Salida

    let builtIn = AudioDevice(id: 1, uid: "BuiltIn", name: "Altavoces del MacBook Pro", outputChannels: 2)
    let pedal = AudioDevice(id: 7, uid: "Pedal", name: "Interfaz de prueba", inputChannels: 4, outputChannels: 4)

    @MainActor
    func testPlugAndUnplugChosenDevicePauseAndReroute() async throws {
        let sim = SimulatedDeviceProvider(devices: [builtIn], defaultID: 1)
        let (p, dir) = try makePlayer([("s0", sine(4, 440, 0.1), sine(4, 440, 0.1))], devices: sim)
        defer { try? FileManager.default.removeItem(at: dir) }
        p.setOutput(OutputSelection(deviceUID: "Pedal", left: 3, right: 4))
        XCTAssertEqual(p.outputDeviceName, builtIn.name)
        XCTAssertNil(p.appliedRoute?.channelMap)

        try p.play()
        _ = try p.renderOffline(frames: 9_600)
        sim.plug(pedal)
        for _ in 0..<100 where p.isPlaying { await Task.yield() }
        XCTAssertFalse(p.isPlaying)
        XCTAssertEqual(p.outputDeviceName, pedal.name)
        XCTAssertEqual(p.appliedRoute?.channelMap, [-1, -1, 0, 1])
        XCTAssertEqual(p.currentTime, 0.2, accuracy: 0.001)

        try p.play()
        _ = try p.renderOffline(frames: 9_600)
        sim.unplug(id: 7)
        for _ in 0..<100 where p.isPlaying { await Task.yield() }
        XCTAssertFalse(p.isPlaying)
        XCTAssertEqual(p.outputDeviceName, builtIn.name)
        XCTAssertNil(p.appliedRoute?.channelMap)
    }

    // MARK: Para escuchar (solo con TF_P6_LISTEN=1; usa los stems de P4, no versionados)

    /// T1 sin guitarras al 70 %, en bucle de dos compases con metrónomo → Temp/p6/listen-T1-loop70.wav.
    @MainActor
    func testWriteListeningRender() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TF_P6_LISTEN"] == "1", "TF_P6_LISTEN=1 para generar el WAV")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../..").standardizedFileURL
        let stems = root.appendingPathComponent("Probes/P4-modelos/bs_roformer_sw/out/stems/T1")
        let beatsDir = root.appendingPathComponent("Probes/P4-modelos/beat_this/out/beats/torch")
        func times(_ name: String) throws -> [Double] {
            try String(contentsOf: beatsDir.appendingPathComponent(name), encoding: .utf8)
                .split(whereSeparator: \.isNewline).compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        }
        let beats = try times("T1.beats.txt"), downs = Set(try times("T1.downbeats.txt"))
        let p = kind.offline()
        try p.load(tracks: ["vocals", "drums", "bass", "guitar", "piano", "other"].map {
            Track(id: $0, url: stems.appendingPathComponent("\($0).wav"))
        })
        p.setMute("guitar", true)
        p.metronome = Metronome(clicks: beats.map { Click(time: $0, accent: downs.contains($0)) }, isEnabled: true, gainDB: -6)
        let d = downs.sorted()
        let a = d[8], b = d[10]
        p.loop = a...b
        p.rate = 0.7
        p.seek(to: d[7])
        try p.play()
        let seconds = ((a - d[7]) + 3 * (b - a)) / 0.7 + 1
        let r = try p.renderOffline(frames: Int(seconds * 48_000))
        let out = root.appendingPathComponent(kind == .platform ? "Temp/p6/listen-T1-loop70.wav"
                                                                : "Temp/p6/listen-T1-loop70-portable.wav")
        let left = r.channels[0], right = r.channels[1]
        try TakeFile.write([left, right], sampleRate: 48_000, to: out)
        var ms: Float = 0
        DSP.measqv(left, 1, &ms, DSPLength(left.count))
        print("P6 escucha: \(out.path) bucle \(a)…\(b) s, \(seconds) s, RMS \(20 * log10(sqrt(ms))) dBFS")
        XCTAssertGreaterThan(ms, 1e-6)
    }
}

#if canImport(AVFoundation)
/// Los mismos casos con el motor portátil (el de Windows) en el Mac.
final class PortableStudyPlayerTests: StudyPlayerTests {
    override var kind: PlayerKind { .portable }
}
#endif
