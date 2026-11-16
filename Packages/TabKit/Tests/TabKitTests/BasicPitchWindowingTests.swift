import AVFoundation
import XCTest
@testable import TabKit

/// Predictor simulado que devuelve, en cada fotograma f, la muestra de la ventana en f · 256: con un audio rampa
/// (muestra i = i + 1) cada fotograma desenrollado dice de qué muestra del audio original viene.
final class RampPredictor: BasicPitchWindowPredictor, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    var callCount: Int { lock.withLock { calls } }
    /// Si se da, `note` vale `noteValue(muestra)` y `onset` `onsetValue(muestra)` en lugar de la muestra (± signo).
    let noteValue: ((Int, Int) -> Float)?
    let onsetValue: ((Int, Int) -> Float)?

    init(noteValue: ((Int, Int) -> Float)? = nil, onsetValue: ((Int, Int) -> Float)? = nil) {
        self.noteValue = noteValue
        self.onsetValue = onsetValue
    }

    func predict(window: UnsafeBufferPointer<Float>) throws -> (note: [Float], onset: [Float]) {
        lock.withLock { calls += 1 }
        let t = BasicPitchContract.windowFrames, p = BasicPitchContract.nPitches
        var note = [Float](repeating: 0, count: t * p), onset = note
        for f in 0..<t {
            let i = f * BasicPitchContract.fftHop
            let v = i < window.count ? window[i] : 0
            // muestra original (v − 1) o −1 si es relleno
            let sample = v > 0 ? Int(v) - 1 : -1
            for k in 0..<p {
                note[f * p + k] = noteValue.map { $0(sample, k) } ?? v
                onset[f * p + k] = onsetValue.map { $0(sample, k) } ?? -v
            }
        }
        return (note, onset)
    }
}

final class BasicPitchWindowingTests: XCTestCase {
    typealias C = BasicPitchContract
    static func ramp(_ n: Int) -> [Float] { (0..<n).map { Float($0 + 1) } }

    /// Troceado de `run_inference`: fotograma j del desenrollado ↔ muestra j · 256 − 188 · (j div 142) del original
    /// (36 164 de salto frente a 142 · 256 = 36 352: 188 muestras de corrimiento por ventana), sin huecos ni
    /// repeticiones, note y onset sin cruzar, y floor(n · 86 / 22 050) fotogramas.
    func testUnwrapMapsEveryFrameToItsSample() throws {
        let n = 400_000   // 18,1 s → 11 ventanas
        let predictor = RampPredictor()
        let post = try BasicPitchWindowing.posteriorgram(audio: Self.ramp(n), with: predictor)
        XCTAssertEqual(post.frames, 1560)                       // floor(400 000 · 86 / 22 050)
        XCTAssertEqual(post.frames, C.outputFrames(forSamples: n))
        XCTAssertEqual(predictor.callCount, 11)                  // ceil(1560 / 142)
        var mismatches = 0
        for j in 0..<post.frames {
            let expected = Float(j * C.fftHop - 188 * (j / C.keptFramesPerWindow) + 1)
            if post.note[j * C.nPitches] != expected || post.onset[j * C.nPitches + 87] != -expected { mismatches += 1 }
        }
        XCTAssertEqual(mismatches, 0)
    }

    /// Audio vacío o más corto que un fotograma: sin fotogramas ni notas.
    func testShortAudioGivesNoFrames() throws {
        for n in [0, 1, 256] {
            let post = try BasicPitchWindowing.posteriorgram(audio: Self.ramp(n), with: RampPredictor())
            XCTAssertEqual(post.frames, 0)   // floor(256 · 86 / 22 050) = 0
            XCTAssertTrue(BasicPitchNotes.noteEvents(post).isEmpty)
        }
    }

    /// Una nota sintética (MIDI 40, de 1,00 a 2,50 s) que cruza el borde entre la 1.ª y la 2.ª ventana (1,64 s)
    /// sale como una sola nota, con inicio y fin a menos de un fotograma (11,6 ms) más el desfase propio de
    /// `model_frames_to_time` (≤ 8,6 ms en la primera ventana).
    func testNoteAcrossWindowSeamIsOneNoteAtTheRightTime() throws {
        let sr = C.sampleRate
        let (s, e) = (Int(1.0 * sr), Int(2.5 * sr))
        let bin = 40 - C.midiOffset
        let note: (Int, Int) -> Float = { i, k in k == bin && i >= s && i < e ? 0.8 : 0.05 }
        let onset: (Int, Int) -> Float = { i, k in k == bin && i >= s && i < s + C.fftHop ? 0.9 : 0.02 }
        let post = try BasicPitchWindowing.posteriorgram(audio: Self.ramp(Int(4 * sr)),
                                                         with: RampPredictor(noteValue: note, onsetValue: onset))
        let notes = BasicPitchNotes.noteEvents(post)
        XCTAssertEqual(notes.count, 1)
        let n = try XCTUnwrap(notes.first)
        XCTAssertEqual(n.pitch, 40)
        let frame = Double(C.fftHop) / sr
        print("nota sintética: \(n.start)…\(n.end) s, error \(n.start - 1.0) / \(n.end - 2.5) s")
        XCTAssertEqual(n.start, 1.0, accuracy: frame + 0.0086)
        XCTAssertEqual(n.end, 2.5, accuracy: frame + 0.0086)
        XCTAssertEqual(n.amplitude, 0.8, accuracy: 1e-6)
    }

    /// Desfase de los tiempos de basic-pitch (`model_frames_to_time` resta 0,010 326 s cada 172 fotogramas)
    /// frente a la posición real de cada fotograma (188 muestras cada 142) en 10 minutos: dientes de sierra de
    /// menos de 8,6 ms que no se acumulan. Es de basic-pitch; el port lo reproduce para la paridad.
    func testFrameTimeDriftStaysBelowOneFrame() {
        var worst = 0.0
        for j in 0..<(600 * C.framesPerSecond) {
            let real = Double(j * C.fftHop - 188 * (j / C.keptFramesPerWindow)) / C.sampleRate
            worst = max(worst, abs(C.time(ofFrame: j) - real))
        }
        print("desfase máximo de model_frames_to_time en 10 min: \(worst * 1000) ms")
        XCTAssertLessThan(worst, Double(C.fftHop) / C.sampleRate)
    }

    /// Lectura: estéreo a 44,1 kHz → mono (media de canales) a 22 050 Hz con ceil(n / 2) muestras y un clic a
    /// 0,5 s en su muestra (± 1).
    func testMonoAudioDownmixesAndResamplesWithoutDelay() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tabkit-click-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let n = 44_101
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        buf.floatChannelData![0][22_050] = 0.8   // solo en L: la media da 0,4
        do {
            let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
            try file.write(from: buf)
        }
        let x = try MonoAudio.load(url, sampleRate: C.sampleRate)
        XCTAssertEqual(x.count, 22_051)
        let peak = x.indices.max { abs(x[$0]) < abs(x[$1]) }!
        XCTAssertEqual(peak, 11_025, accuracy: 1)
        XCTAssertEqual(x[peak], 0.4 * 0.5, accuracy: 0.1)
    }
}
