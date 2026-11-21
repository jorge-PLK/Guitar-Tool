import NativeAudioFile
import XCTest
@testable import TabKit

/// Predictor que imita lo medido en Fase 5b con el Core ML real: con una ventana muda da 0,9 / 0,66 en las 88 notas
/// (el 0/0 de `NormalizedLog`); con audio, una nota real (MIDI 40) donde hay señal ≥ −60 dBFS y, como la normalización
/// por ventana amplifica lo flojo, una nota inventada (MIDI 81) en los tramos flojos de esa misma ventana.
final class SilenceFaultPredictor: BasicPitchWindowPredictor, @unchecked Sendable {
    static let realPitch = 40, ghostPitch = 81
    private let lock = NSLock()
    private var calls = 0, silentCalls = 0
    var callCount: Int { lock.withLock { calls } }
    var silentCallCount: Int { lock.withLock { silentCalls } }

    func predict(window: UnsafeBufferPointer<Float>) throws -> (note: [Float], onset: [Float]) {
        let t = BasicPitchContract.windowFrames, p = BasicPitchContract.nPitches, hop = BasicPitchContract.fftHop
        let silent = window.allSatisfy { $0 == 0 }
        lock.withLock { calls += 1; if silent { silentCalls += 1 } }
        if silent { return ([Float](repeating: 0.9, count: t * p), [Float](repeating: 0.66, count: t * p)) }
        var note = [Float](repeating: 0.05, count: t * p), onset = [Float](repeating: 0.02, count: t * p)
        let real = Self.realPitch - BasicPitchContract.midiOffset, ghost = Self.ghostPitch - BasicPitchContract.midiOffset
        var prevLoud: Bool?
        for f in 0..<t {
            let lo = min(f * hop, window.count), hi = min(lo + hop, window.count)
            var ms: Float = 0
            for i in lo..<hi { ms += window[i] * window[i] }
            let loud = hi > lo && (ms / Float(hi - lo)).squareRoot() >= 1e-3
            let k = loud ? real : ghost
            note[f * p + k] = 0.8
            if prevLoud != loud { onset[f * p + k] = 0.9 }
            prevLoud = loud
        }
        return (note, onset)
    }
}

final class SilenceGateTests: XCTestCase {
    typealias C = BasicPitchContract
    static let sr = C.sampleRate
    /// Un fotograma de Basic Pitch más el desfase de `model_frames_to_time` (≤ 8,6 ms), como en los tests del troceado.
    static let frameTolerance = Double(C.fftHop) / C.sampleRate + 0.0086

    static func sine(_ seconds: Double, dBFS rms: Float, hz: Double = 82.41) -> [Float] {
        let a = powf(10, rms / 20) * 2.0.squareRoot().float
        return (0..<Int(seconds * sr)).map { a * Float(sin(2 * .pi * hz * Double($0) / sr)) }
    }

    static func noise(_ seconds: Double, dBFS rms: Float, seed: UInt64 = 1) -> [Float] {
        var g = SplitMix(seed: seed)
        let a = powf(10, rms / 20) * 3.0.squareRoot().float   // uniforme en ±a: RMS a / √3
        return (0..<Int(seconds * sr)).map { _ in a * (Float(g.next() % 2_000_001) / 1_000_000 - 1) }
    }

    static func zeros(_ seconds: Double) -> [Float] { [Float](repeating: 0, count: Int(seconds * sr)) }

    static func writeWAV(_ x: [Float]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tabkit-gate-\(UUID().uuidString).wav")
        try NativeAudioFile.write(url, channels: [x], sampleRate: sr, format: .float32)
        return url
    }

    // MARK: silencio digital

    /// 20 s de ceros con el predictor que falla como el Core ML en GPU: ninguna ventana llega al modelo, posteriorgramas
    /// a cero y 0 notas, con y sin puerta.
    func testDigitalSilenceGivesNoNotes() async throws {
        let predictor = SilenceFaultPredictor()
        let audio = Self.zeros(20)
        let post = try BasicPitchWindowing.posteriorgram(audio: audio, with: predictor)
        XCTAssertEqual(post.frames, C.outputFrames(forSamples: audio.count))
        XCTAssertEqual(predictor.callCount, 0)
        XCTAssertEqual(post.note.max(), 0)
        XCTAssertEqual(post.onset.max(), 0)
        XCTAssertTrue(BasicPitchNotes.noteEvents(post).isEmpty)

        let url = try Self.writeWAV(audio)
        defer { try? FileManager.default.removeItem(at: url) }
        let notes = try await BasicPitchTranscriber(predictor: predictor).transcribe(url: url)
        XCTAssertEqual(notes.count, 0)
        XCTAssertEqual(predictor.silentCallCount, 0)
    }

    /// La puerta sola, con las notas fantasma de `guitar_lead` de «El roce» (0 a 157,4 s, amplitud 0,86–0,90) sobre
    /// ceros: quita todas.
    func testGateRemovesEveryNoteOverDigitalSilence() {
        let ghosts = [23, 25, 27, 107].map { NoteEvent(start: 0, end: 157.44, pitch: $0, amplitude: 0.86) }
            + [NoteEvent(start: 0.139, end: 157.44, pitch: 21, amplitude: 0.61),
               NoteEvent(start: 150.0, end: 150.2, pitch: 60, amplitude: 0.9)]
        XCTAssertTrue(SilenceGate.filter(ghosts, audio: Self.zeros(160), sampleRate: Self.sr).isEmpty)
    }

    // MARK: silencio y luego audio

    /// 4 s de ceros y 3 s de seno a −20 dBFS (MIDI 40). Sin puerta salen notas inventadas en la parte muda de la
    /// ventana que cruza el borde; con puerta solo queda la real, con el ataque a un fotograma de 4,000 s.
    func testSilenceThenAudioKeepsOnlyNotesInTheAudio() async throws {
        let audio = Self.zeros(4) + Self.sine(3, dBFS: -20)
        let predictor = SilenceFaultPredictor()
        let transcriber = BasicPitchTranscriber(predictor: predictor)
        let raw = try await transcriber.notes(audio: audio)
        let ghostsRaw = raw.filter { $0.pitch == SilenceFaultPredictor.ghostPitch }
        XCTAssertGreaterThan(ghostsRaw.count, 0, "sin puerta, la ventana del borde inventa notas en lo mudo")
        XCTAssertEqual(predictor.silentCallCount, 0)

        let url = try Self.writeWAV(audio)
        defer { try? FileManager.default.removeItem(at: url) }
        let gated = try await transcriber.transcribe(url: url)
        print("silencio + audio: \(raw.count) notas sin puerta (\(ghostsRaw.count) inventadas) → \(gated.count): "
              + gated.map { "\($0.pitch) \($0.start)…\($0.end)" }.joined(separator: ", "))
        XCTAssertEqual(gated.count, 1)
        let n = try XCTUnwrap(gated.first)
        XCTAssertEqual(n.pitch, SilenceFaultPredictor.realPitch)
        XCTAssertEqual(n.start, 4.0, accuracy: Self.frameTolerance)
        XCTAssertTrue(gated.allSatisfy { $0.start >= 4.0 - Self.frameTolerance })
    }

    /// Borde del ataque: el audio empieza a 4,000 s. Ataques adelantados hasta 50 ms se quedan (Basic Pitch adelanta
    /// hasta dos fotogramas, 23 ms); a 70 ms o más, todo su ataque es silencio y se van. (El tramo de 10 ms que
    /// contiene 4,000 s empieza en 3,991 s: el límite real está en 3,941 s.)
    func testAttackToleranceAtTheStartOfTheAudio() {
        let audio = Self.zeros(4) + Self.sine(2, dBFS: -20)
        func kept(_ start: Double) -> Bool {
            !SilenceGate.filter([NoteEvent(start: start, end: 5.0, pitch: 40, amplitude: 0.8)],
                                audio: audio, sampleRate: Self.sr).isEmpty
        }
        for s in [4.0, 3.988, 3.977, 3.96, 3.951] { XCTAssertTrue(kept(s), "ataque a \(s) s") }
        for s in [3.93, 3.9, 3.5, 0.0] { XCTAssertFalse(kept(s), "ataque a \(s) s") }
    }

    // MARK: ruido de fondo bajo

    /// Ruido de fondo a −90 dBFS todo el rato (el de la separación está entre −75 y −136), una nota floja a −50 dBFS
    /// (1–2 s) y otra a −25 (3–5 s). Se quedan las dos reales, también con cola de reverberación en el ruido; se van
    /// las inventadas en el ruido y la que tiene el ataque en el audio pero casi toda la duración en el ruido.
    func testLowNoiseFloorDoesNotCutRealNotes() {
        var audio = Self.noise(6, dBFS: -90)
        let quiet = Self.sine(1, dBFS: -50), loud = Self.sine(2, dBFS: -25, hz: 110)
        for i in quiet.indices { audio[Int(1.0 * Self.sr) + i] += quiet[i] }
        for i in loud.indices { audio[Int(3.0 * Self.sr) + i] += loud[i] }
        let real = [NoteEvent(start: 1.0, end: 2.0, pitch: 40, amplitude: 0.4),
                    NoteEvent(start: 0.99, end: 2.01, pitch: 52, amplitude: 0.3),     // armónico, un fotograma antes
                    NoteEvent(start: 3.0, end: 5.0, pitch: 45, amplitude: 0.8),
                    NoteEvent(start: 3.0, end: 5.8, pitch: 57, amplitude: 0.5)]       // 2 s en audio, 0,8 en ruido
        let ghosts = [NoteEvent(start: 0.2, end: 0.8, pitch: 70, amplitude: 0.7),
                      NoteEvent(start: 2.3, end: 2.9, pitch: 81, amplitude: 0.7),
                      NoteEvent(start: 5.2, end: 5.9, pitch: 30, amplitude: 0.6),
                      NoteEvent(start: 4.95, end: 5.9, pitch: 64, amplitude: 0.6)]    // ataque en audio, 90 % en ruido
        let kept = SilenceGate.filter(real + ghosts, audio: audio, sampleRate: Self.sr)
        XCTAssertEqual(kept, real)

        // El umbral, con números: el ruido de fondo queda 30 dB por debajo y la nota floja 10 dB por encima.
        let levels = SilenceGate.Levels(audio: audio, sampleRate: Self.sr)
        let db = { (a: Double, b: Double) in 20 * log10(levels.maxRMS(from: a, to: b)) }
        print("ruido \(db(0.1, 0.9)) dBFS, nota floja \(db(1.1, 1.9)) dBFS, umbral \(SilenceGate.thresholdDBFS)")
        XCTAssertEqual(db(0.1, 0.9), -90, accuracy: 3)
        XCTAssertEqual(db(1.1, 1.9), -50, accuracy: 1)
    }

    /// Ventanas casi mudas: por debajo de −120 dBFS de pico no pasan por el modelo; a −110 dBFS sí.
    func testOnlyNearSilentWindowsSkipTheModel() throws {
        for (db, calls) in [(-130 as Float, 0), (-110, 3)] {
            let predictor = SilenceFaultPredictor()
            let x = Self.noise(4, dBFS: db - 4.8)   // pico ≈ RMS · √3 = RMS + 4,8 dB
            _ = try BasicPitchWindowing.posteriorgram(audio: x, with: predictor)
            XCTAssertEqual(predictor.callCount, calls, "pico \(db) dBFS")
        }
    }
}

/// Con el modelo Core ML real (`TF_MODEL_TESTS=1`, de uno en uno, bajo el vigilante como `BasicPitchHeavyModelTests`).
final class SilenceGateHeavyModelTests: XCTestCase {
    private func model() throws -> URL {
        guard ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1" else {
            throw XCTSkip("tests del modelo real desactivados (TF_MODEL_TESTS != 1)")
        }
        return try BasicPitchHeavyModelTests.compiledModel()
    }

    /// 30 s de ceros con el Core ML real en CPU+GPU: 0 notas (sin la puerta). Informativo: lo que da el modelo con una
    /// ventana de ceros, la causa de las notas fantasma.
    func testRealModelOnDigitalSilence() async throws {
        let url = try model()
        #if canImport(CoreML)
        let raw = try CoreMLBasicPitchPredictor(modelURL: url, computeUnits: .cpuAndGPU)
        #else
        let raw = try OnnxBasicPitchPredictor(modelURL: url)   // Windows (parte 7.8)
        #endif
        let zeros = [Float](repeating: 0, count: BasicPitchContract.windowSamples)
        let out = try zeros.withUnsafeBufferPointer { try raw.predict(window: $0) }
        let mean = out.note.reduce(0, +) / Float(out.note.count)
        print("Core ML CPU+GPU, ventana de ceros: note máx \(out.note.max()!) media \(mean), onset máx \(out.onset.max()!)")
        let notes = try await BasicPitchTranscriber(modelURL: url).notes(audio: [Float](repeating: 0, count: 30 * 22_050))
        XCTAssertEqual(notes.count, 0)
    }

    /// Informativo, con un proyecto de la app: `TF_GATE_PROJECT=<carpeta del proyecto>`. Por pista: notas de la tabla
    /// guardada (antes), con el arreglo de ventanas mudas y con la puerta; notas que quita la puerta y primera nota.
    /// Deja las notas de la solista en `Temp/p5b/roce_lead_gate_notes.json` para el WAV de escucha.
    func testReportProjectStems() async throws {
        let url = try model()
        guard let project = ProcessInfo.processInfo.environment["TF_GATE_PROJECT"] else {
            throw XCTSkip("sin TF_GATE_PROJECT")
        }
        let folder = URL(fileURLWithPath: project)
        let saved = try JSONDecoder().decode(TabScore.self, from: Data(contentsOf: folder.appendingPathComponent("tab/score.json")))
        let times = saved.beats.map(\.time)
        func seconds(_ p: GridPoint) -> Double {
            let b = min(p.beat, times.count - 1)
            let next = b + 1 < times.count ? times[b + 1] : times[b] + 0.5
            return times[b] + (next - times[b]) * Double(p.tick) / Double(TabScore.ticksPerBeat)
        }
        let transcriber = BasicPitchTranscriber(modelURL: url)
        var dump: [String: [NoteEvent]] = [:]
        for (stem, id) in [("guitar_L", "guitar-left"), ("guitar_R", "guitar-right"), ("guitar_lead", "guitar-lead"), ("bass", "bass")] {
            let audio = try MonoAudio.load(folder.appendingPathComponent("stems/\(stem).wav"), sampleRate: BasicPitchContract.sampleRate)
            let raw = try await transcriber.notes(audio: audio)
            let gated = SilenceGate.filter(raw, audio: audio, sampleRate: BasicPitchContract.sampleRate)
            let old = saved.tracks.first { $0.id == id }
            let kind: TabTrackKind = stem == "bass" ? .bass : .guitar
            let tuning = old?.tuning ?? (kind == .bass ? Tuning.bass(.standard) : Tuning.guitar(.standard))
            func built(_ e: [NoteEvent]) -> TabTrack {
                TabTrackBuilder.pitchedTrack(id: id, name: id, kind: kind, tuning: tuning, source: nil, notes: e, in: saved).track
            }
            let (fixed, after) = (built(raw), built(gated))
            let firstOld = old?.notes.map { seconds($0.start) }.min()
            let firstNew = after.notes.map { seconds($0.start) }.min()
            let before158 = { (t: TabTrack?) in t?.notes.filter { seconds($0.start) < 158 }.count ?? -1 }
            print(String(format: "GATE %@: tabla %d → arreglo %d → puerta %d notas | eventos %d → %d (puerta quita %d) | "
                         + "antes de 158 s %d → %d | primera nota tabla %.3f → %.3f s, primer evento %.3f s",
                         stem, old?.notes.count ?? -1, fixed.notes.count, after.notes.count, raw.count, gated.count,
                         raw.count - gated.count, before158(old), before158(after), firstOld ?? -1, firstNew ?? -1,
                         gated.first?.start ?? -1))
            let removed = raw.filter { !gated.contains($0) }
            print("GATE \(stem) quitadas: " + removed.map { String(format: "%d %.3f–%.3f s", $0.pitch, $0.start, $0.end) }
                .joined(separator: ", "))
            if stem == "guitar_lead" { dump = ["raw": raw, "gated": gated] }
        }
        let out = Fixture.repo.appendingPathComponent("Temp/p5b/roce_lead_gate_notes.json")
        try JSONEncoder().encode(dump).write(to: out)
    }
}

/// Generador reproducible para el ruido de los tests.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private extension Double {
    var float: Float { Float(self) }
}
