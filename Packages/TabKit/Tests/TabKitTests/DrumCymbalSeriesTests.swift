import AVFoundation
import XCTest
@testable import TabKit

/// Platos de ADTOF en serie → charles abierto (Fase 5b, «Platos de ADTOF confundidos con charles»).
final class DrumCymbalSeriesTests: XCTestCase {
    typealias R = DrumCymbalSeries
    static let quarter171 = 60.0 / 171   // El roce de tu cuerpo, 171 BPM

    static func hits(_ notes: [(Double, Int)]) -> [TranscribedDrumHit] {
        notes.map { TranscribedDrumHit(time: $0.0, midi: $0.1) }.sorted { ($0.time, $0.midi) < ($1.time, $1.midi) }
    }

    static func series(from t0: Double, count: Int, ioi: Double) -> [Double] {
        (0..<count).map { t0 + Double($0) * ioi }
    }

    static func notes(of hits: [TranscribedDrumHit], at times: [Double]) -> [Int] {
        times.map { t in hits.first { abs($0.time - t) < 1e-9 && ($0.midi == 49 || $0.midi == 46) }?.midi ?? -1 }
    }

    /// Negras a 171 BPM que empiezan con bombo: crash en la primera, charles abierto en las 15 siguientes.
    func testQuarterSeriesStartingOnKick() {
        let t = Self.series(from: 1.0, count: 16, ioi: Self.quarter171)
        let out = R.refine(Self.hits(t.map { ($0, 49) } + [(1.0, 35), (2.4, 35)]))
        XCTAssertEqual(Self.notes(of: out, at: t), [49] + Array(repeating: 46, count: 15))
        XCTAssertEqual(out.filter { $0.midi == 35 }.count, 2)
    }

    /// Corcheas (175 ms) sin bombo en la primera: todas charles abierto.
    func testEighthSeriesWithoutKick() {
        let t = Self.series(from: 0.5, count: 12, ioi: Self.quarter171 / 2)
        let out = R.refine(Self.hits(t.map { ($0, 49) } + [(0.5, 38)]))
        XCTAssertEqual(Self.notes(of: out, at: t), Array(repeating: 46, count: 12))
    }

    /// Lo que se queda como crash: suelto con bombo, parejas (crash + otro un pulso después) y series de 3.
    func testShortSeriesStayCrash() {
        let single = [2.0]
        let pair = Self.series(from: 5.0, count: 2, ioi: Self.quarter171)
        let three = Self.series(from: 8.0, count: R.minSeriesLength - 1, ioi: Self.quarter171)
        let all = single + pair + three
        let out = R.refine(Self.hits(all.map { ($0, 49) } + [(2.0, 35), (5.0, 35)]))
        XCTAssertEqual(Self.notes(of: out, at: all), Array(repeating: 49, count: all.count))
        // Con un golpe más, la serie de 3 pasa a 4 y cambia (sin bombo: las cuatro).
        let four = Self.series(from: 8.0, count: R.minSeriesLength, ioi: Self.quarter171)
        XCTAssertEqual(Self.notes(of: R.refine(Self.hits(four.map { ($0, 49) })), at: four), [46, 46, 46, 46])
    }

    /// Dos frases de 8 negras separadas por 700 ms (lo medido en El roce entre series), cada una con bombo al
    /// principio: dos crash y 14 charles abiertos.
    func testPhrasesSplitAtGap() {
        let a = Self.series(from: 0, count: 8, ioi: Self.quarter171)
        let b = Self.series(from: a.last! + 0.70, count: 8, ioi: Self.quarter171)
        let out = R.refine(Self.hits((a + b).map { ($0, 49) } + [(a[0], 35), (b[0], 35)]))
        let n = Self.notes(of: out, at: a + b)
        XCTAssertEqual(n.filter { $0 == 49 }.count, 2)
        XCTAssertEqual(n.filter { $0 == 46 }.count, 14)
        XCTAssertEqual(n[0], 49)
        XCTAssertEqual(n[8], 49)
    }

    /// Bordes de las constantes: separación 0,50 s une, 0,51 corta; bombo a 30 ms cuenta, a 40 ms no.
    func testThresholdEdges() {
        let joined = Self.series(from: 0, count: 4, ioi: R.seriesMaxGap)
        XCTAssertEqual(Self.notes(of: R.refine(Self.hits(joined.map { ($0, 49) })), at: joined), [46, 46, 46, 46])
        let split = Self.series(from: 0, count: 4, ioi: R.seriesMaxGap + 0.01)
        XCTAssertEqual(Self.notes(of: R.refine(Self.hits(split.map { ($0, 49) })), at: split), [49, 49, 49, 49])

        let t = Self.series(from: 1.0, count: 6, ioi: Self.quarter171)
        let near = R.refine(Self.hits(t.map { ($0, 49) } + [(1.0 - R.kickWindow, 35)]))
        XCTAssertEqual(Self.notes(of: near, at: t).first, 49)
        let far = R.refine(Self.hits(t.map { ($0, 49) } + [(1.0 + R.kickWindow + 0.01, 35)]))
        XCTAssertEqual(Self.notes(of: far, at: t).first, 46)
    }

    /// Sobre los golpes del fixture de ADTOF (T1, 10 s): mismo número de golpes, mismos tiempos, solo cambia 49 → 46,
    /// orden (tiempo, nota) y el resto de piezas intacto. Las activaciones y los picos no se tocan.
    func testFixtureHitsOnlyCymbalsChange() throws {
        let act = try Fixture.f32(DrumTranscriberTests.dir.appendingPathComponent("act.f32"))
        let raw = DrumPeaks.hits(activations: act, frames: DrumTranscriberTests.frames)
        let out = R.refine(raw)
        XCTAssertEqual(out.count, raw.count)
        XCTAssertEqual(out.map(\.time).sorted(), raw.map(\.time).sorted())
        XCTAssertEqual(out, out.sorted { ($0.time, $0.midi) < ($1.time, $1.midi) })
        for note in [35, 38, 42, 47] {
            XCTAssertEqual(out.filter { $0.midi == note }, raw.filter { $0.midi == note })
        }
        XCTAssertEqual(out.filter { $0.midi == 49 || $0.midi == 46 }.count, raw.filter { $0.midi == 49 }.count)
        print("DrumCymbalSeries fixture T1: platos \(raw.filter { $0.midi == 49 }.count) → crash \(out.filter { $0.midi == 49 }.count), "
              + "charles abierto \(out.filter { $0.midi == 46 }.count)")
    }

    /// La pista de batería, el JSON de alphaTab y el sintetizador reciben la nota 46 como `DrumPiece.openHiHat`.
    func testOpenHiHatPiece() {
        XCTAssertEqual(DrumPiece(rawValue: R.openHiHatMIDI), .openHiHat)
    }
}

// MARK: - El roce de tu cuerpo (modelo real)

/// Recuento antes/después en El roce y WAV de escucha. Solo con `TF_MODEL_TESTS=1`:
///   TF_MODEL_TESTS=1 Tools/test.sh TabKit DrumCymbalSeriesSongTests
/// Escribe en Temp/p5b/drums/ CHECK_roce_drums_5b.wav (izquierda: stem; derecha: golpes con la regla, General MIDI)
/// y CHECK_roce_drums_5b_antes.wav (derecha: golpes de ADTOF sin la regla).
final class DrumCymbalSeriesSongTests: XCTestCase {
    static let song = P5BProjects.project("El roce de tu cuerpo - Platero Y Tu").appendingPathComponent("stems/drums.wav")
    static let out = Fixture.repo.appendingPathComponent("Temp/p5b/drums")
    static let soundFont = Fixture.repo.appendingPathComponent("App/Resources/alphaTab/soundfont/sonivox.sf2")
    /// Picos de Swift frente a los del puerto PyTorch (`diagnose.py`) por clase: el stem va a 48 kHz y cada lado
    /// remuestrea a su manera, así que se admite un 1 % (en T1, a 44,1 kHz, son idénticos).
    static let countTolerance = 0.01

    static func counts(_ hits: [TranscribedDrumHit]) -> [Int: Int] {
        Dictionary(grouping: hits, by: \.midi).mapValues(\.count)
    }

    func testRoceCountsAndListeningFiles() async throws {
        guard ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1" else {
            throw XCTSkip("tests del modelo real desactivados (TF_MODEL_TESTS != 1)")
        }
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.song.path), "falta \(Self.song.path)")
        let model = try DrumHeavyModelTests.compiledModel()
        let raw = try await DrumTranscriber(modelURL: model).transcribe(url: Self.song)
        let refined = DrumCymbalSeries.refine(raw)
        let before = Self.counts(raw), after = Self.counts(refined)
        print("El roce antes: \(before.sorted { $0.key < $1.key })")
        print("El roce después: \(after.sorted { $0.key < $1.key })")
        XCTAssertEqual(raw.count, refined.count)
        XCTAssertEqual((before[49] ?? 0), (after[49] ?? 0) + (after[46] ?? 0))

        // Misma regla sobre los golpes de Python (si está la salida de diagnose.py): 51 crash y 376 charles abiertos.
        let pyURL = Self.out.appendingPathComponent("roce_hits.json")
        if let data = try? Data(contentsOf: pyURL),
           let py = try JSONSerialization.jsonObject(with: data) as? [String: [Double]] {
            let names = ["kick": 35, "snare": 38, "tom": 47, "hihat": 42, "cymbal": 49]
            var pyHits = [TranscribedDrumHit]()
            for (name, midi) in names { pyHits += (py[name] ?? []).map { TranscribedDrumHit(time: $0, midi: midi) } }
            pyHits.sort { ($0.time, $0.midi) < ($1.time, $1.midi) }
            let pyAfter = Self.counts(DrumCymbalSeries.refine(pyHits))
            print("El roce, regla sobre los golpes de Python: \(pyAfter.sorted { $0.key < $1.key })")
            XCTAssertEqual(pyAfter[49], 51)
            XCTAssertEqual(pyAfter[46], 376)
            for (note, n) in Self.counts(pyHits) {
                let d = abs(Double((before[note] ?? 0) - n)) / Double(max(n, 1))
                XCTAssertLessThanOrEqual(d, Self.countTolerance, "nota \(note): Swift \(before[note] ?? 0), Python \(n)")
            }
        }

        guard FileManager.default.fileExists(atPath: Self.soundFont.path) else { return }
        try FileManager.default.createDirectory(at: Self.out, withIntermediateDirectories: true)
        let stem = try MonoAudio.load(Self.song, sampleRate: DrumContract.sampleRate)
        try Self.writeCheck(stem: stem, hits: refined, to: Self.out.appendingPathComponent("CHECK_roce_drums_5b.wav"))
        try Self.writeCheck(stem: stem, hits: raw, to: Self.out.appendingPathComponent("CHECK_roce_drums_5b_antes.wav"))
    }

    /// Estéreo a 44,1 kHz: izquierda el stem, derecha los golpes por el sampler de la app (cada uno suena hasta el
    /// siguiente de la misma nota), ambos normalizados a −1 dBFS de pico.
    static func writeCheck(stem: [Float], hits: [TranscribedDrumHit], to url: URL) throws {
        let rate = DrumContract.sampleRate, n = stem.count
        var events = [TabSynthRenderer.Event]()
        var open = Set<Int>()
        for h in hits {
            let f = Int((h.time * rate).rounded()), key = UInt8(h.midi)
            if open.contains(h.midi) { events.append(.init(frame: f, status: 0x80 | TabSynthRenderer.drumChannel, data1: key, data2: 0)) }
            events.append(.init(frame: f, status: 0x90 | TabSynthRenderer.drumChannel, data1: key, data2: TabSynthRenderer.velocity))
            open.insert(h.midi)
        }
        events.sort { ($0.frame, $0.isNoteOff ? 0 : 1) < ($1.frame, $1.isNoteOff ? 0 : 1) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("roce-check-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let renderer = TabSynthRenderer(soundFontURL: soundFont)
        let (program, bank) = renderer.instrument(for: .drums)
        try TabSynthRenderer.renderFile(events: events, totalFrames: n, sampleRate: rate, soundFontURL: soundFont,
                                        program: program, bankMSB: bank, to: tmp)
        let synth = try TabSynthTests.read(tmp).channels[0]
        func normalized(_ x: [Float]) -> [Float] {
            let peak = x.map(abs).max() ?? 0
            let g = peak > 0 ? Float(0.891) / peak : 0
            return x.map { $0 * g }
        }
        let l = normalized(stem), r = normalized(Array(synth.prefix(n)) + [Float](repeating: 0, count: max(0, n - synth.count)))
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: false)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        l.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: n) }
        r.withUnsafeBufferPointer { buf.floatChannelData![1].update(from: $0.baseAddress!, count: n) }
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buf)
        print("CHECK escrito: \(url.path)")
    }
}
