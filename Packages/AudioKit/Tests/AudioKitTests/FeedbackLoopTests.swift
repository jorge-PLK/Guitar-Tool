import XCTest
@testable import AudioKit

/// El fallo de `tf-audio verify` con la Flex Prime (15/11/2026): el cable de la salida a la entrada de guitarra
/// cierra un bucle a través del rig que oscila (tono sostenido de 2793,8 Hz a 0,088 de pico en el canal 1, en
/// plena banda de la ráfaga de 3 kHz) y hace recircular cada clic cada ~7,3 ms (352 muestras, el primer eco
/// a 0,88). La sincronía estaba bien; la medida no: el máximo de la envolvente caía en cualquier sitio de los
/// ±50 ms (error máximo 2267 muestras). Aquí se reproduce con el simulador y la toma completa por la fachada.
class FeedbackLoopTests: XCTestCase {
    /// Motor del reproductor: el de la plataforma; el portátil en `PortableFeedbackLoopTests` (solo Mac).
    var kind: PlayerKind { .platform }
    static let fs = 48_000.0
    static let rig = 70.74
    static let loopSamples = 352.4
    static let tone = SimulatedTone(frequencyHz: 2_793.84, peak: 0.088)

    /// Como la pasada real: guitarra 1,2 tras el rig con el bucle recirculando y oscilando; canal 3 de referencia.
    static func feedbackIO() -> SimulatedAudioIO {
        let echoes = SimulatedInput.recirculating(loopSamples: loopSamples, loopGain: 0.85)
        let l = SimulatedInput(source: 1, extraDelaySamples: rig, echoes: echoes, gain: 0.3, noiseDBFS: -65, tone: tone)
        let r = SimulatedInput(source: 2, extraDelaySamples: rig, echoes: echoes, gain: 0.2, noiseDBFS: -65,
                               tone: SimulatedTone(frequencyHz: tone.frequencyHz, peak: 0.054))
        let ref = SimulatedInput(source: 1, echoes: echoes, gain: 0.02, noiseDBFS: -65,
                                 tone: SimulatedTone(frequencyHz: tone.frequencyHz, peak: 0.002))
        return SimulatedAudioIO(sampleRate: fs, inputs: [l, r, ref], latencySamples: AudioSessionTests.latency(fs),
                                declaredLatencySamples: AudioSessionTests.declared, initialSampleTime: AudioSessionTests.t0)
    }

    /// La toma de comprobación de 60 s con el bucle oscilando: cada clic a 1 muestra o menos de su sitio, y el
    /// tono del fondo identificado. Antes del arreglo: error máximo ≈ 2400 muestras (el borde de la búsqueda).
    @MainActor
    func testVerifyTakeThroughOscillatingFeedbackLoopWithinOneSample() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FeedbackLoopTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fs = Self.fs
        let io = Self.feedbackIO()
        let s = AudioSessionTests.session(io, guitarIn: [1, 2])
        try s.open()
        defer { s.close() }
        let cal = try await AudioSessionTests.calibrate(s, io)
        let g = cal.channels.first { $0.channel == 1 }
        print(String(format: "F3 bucle: calibración %@, canal 1 %.4f (real %.4f), pico/fondo %.1f dB, referencia %d",
                     cal.isValid ? "válida" : "NO válida", g?.latencySamples ?? .nan, AudioSessionTests.latency(fs) + Self.rig,
                     g?.peakToFloorDB ?? .nan, cal.reference?.channel ?? 0))
        XCTAssertTrue(cal.isValid)
        // El fondo sin la línea del bucle: el ruido (−65 dBFS) queda muy por debajo de los 20 dB.
        XCTAssertGreaterThan(g?.peakToFloorDB ?? 0, 40)
        // El tono sesga la latencia del barrido ~0,05 muestras (la detección de la latencia no se ha tocado);
        // la toma sigue dentro de 1 muestra.
        XCTAssertEqual(g?.latencySamples ?? 0, AudioSessionTests.latency(fs) + Self.rig, accuracy: 0.1)

        let song = 64.0
        let backing = try AudioSessionTests.writeBacking(seconds: song, fs: fs, in: dir)
        let url = dir.appendingPathComponent("verify.wav")
        let (take, x, _) = try AudioSessionTests.playAndRecord(s, io, backing: backing, from: 0, seconds: 60, url: url, kind: kind)
        for c in 0..<2 {
            let r = AlignmentCheck.measure(take: x[c], songStart: take.songStart, sampleRate: fs, songSeconds: song - 2)
            let floors = r.clicks.map(\.peakToFloorDB)
            print(String(format: "F3 bucle canal %d: %d/%d clics, máx |error| %.4f muestras, medio %+.4f, pendiente %+.4f/min, pico/fondo mín %.1f dB, tono %.2f Hz a %.1f dBFS",
                         c + 1, r.clicks.count, r.expectedClicks, r.maxAbsErrorSamples, r.meanErrorSamples, r.slopeSamplesPerMinute,
                         floors.min() ?? .nan, r.backgroundTone?.frequencyHz ?? .nan, r.backgroundTone?.peakDBFS ?? .nan))
            XCTAssertGreaterThanOrEqual(r.clicks.count, 115)
            XCTAssertLessThanOrEqual(r.maxAbsErrorSamples, 1)
            XCTAssertTrue(r.passes)
            let peak = c == 0 ? Self.tone.peak : 0.054
            XCTAssertEqual(r.backgroundTone?.frequencyHz ?? 0, Self.tone.frequencyHz, accuracy: 3)
            XCTAssertEqual(r.backgroundTone?.peakDBFS ?? 0, 20 * log10(peak), accuracy: 1)
        }
    }

    /// Calibración con el tono del bucle: antes, fondo a ~20 dB del pico (como los 19,2–20,8 dB reales); ahora
    /// el fondo es el ruido. Y sin cable, con el mismo tono, sigue saliendo «sin señal».
    func testCalibrationFloorIgnoresLoopToneButStillDetectsMissingCable() {
        let fs = Self.fs
        let probe = LatencyProbe(sampleRate: fs)
        var noise = SeededNoise(seed: 7)
        func recording(withSweep: Bool) -> [Float] {
            (0..<probe.captureFrames).map { i -> Float in
                var v = 0.0
                if withSweep {
                    for (j, gk) in [1.0, 0.85, 0.72, 0.61].enumerated() {
                        v += 0.3 * gk * Double(probe.stimulus(at: i - 1_339 - j * 352))
                    }
                }
                v += Self.tone.peak * sin(2 * Double.pi * Self.tone.frequencyHz * Double(i) / fs)
                return Float(v + pow(10, -65.0 / 20) * noise.gaussian())
            }
        }
        let ok = probe.analyze(recording(withSweep: true), channel: 1)
        print(String(format: "F3 bucle calibración sintética: %.4f muestras, pico/fondo %.1f dB, fallo %@",
                     ok.latencySamples, ok.peakToFloorDB, "\(String(describing: ok.failure))"))
        XCTAssertNil(ok.failure)
        XCTAssertEqual(ok.latencySamples, 1_339, accuracy: 0.1)
        XCTAssertGreaterThan(ok.peakToFloorDB, 40)
        let missing = probe.analyze(recording(withSweep: false), channel: 1)
        print(String(format: "F3 bucle sin cable: pico/fondo %.1f dB, fallo %@", missing.peakToFloorDB, "\(String(describing: missing.failure))"))
        XCTAssertEqual(missing.failure, .noSignal)
    }

    /// Sin bucle ni tono la medida no cambia: ningún tono en el fondo y el mismo error que antes.
    func testCleanTakeReportsNoBackgroundTone() {
        let fs = Self.fs
        let song = 20.0
        let x = AlignmentCheck.backing(songSeconds: song, sampleRate: fs)
        let r = AlignmentCheck.measure(take: x, songStart: 0, sampleRate: fs, songSeconds: song)
        XCTAssertNil(r.backgroundTone)
        XCTAssertEqual(r.clicks.count, r.expectedClicks)
        XCTAssertLessThanOrEqual(r.maxAbsErrorSamples, 0.01)
    }

    /// Toma de clics con un tono de fondo de `peakDBFS` sobre ruido blanco.
    private func take(toneHz: Double, toneDBFS: Double, noiseDBFS: Double) -> AlignmentReport {
        let fs = Self.fs
        let song = 20.0
        var x = AlignmentCheck.backing(songSeconds: song, sampleRate: fs)
        var noise = SeededNoise(seed: 11)
        let a = pow(10, toneDBFS / 20), n = pow(10, noiseDBFS / 20)
        for i in x.indices {
            x[i] += Float(a * sin(2 * Double.pi * toneHz * Double(i) / fs) + n * noise.gaussian())
        }
        return AlignmentCheck.measure(take: x, songStart: 0, sampleRate: fs, songSeconds: song)
    }

    /// El 999,9 Hz a −120 dBFS del USB (12 dB sobre su entorno) es suelo de ruido: ni aviso ni NO CONCLUYENTE.
    func testNoiseFloorToneIsNotFeedbackAndStillPasses() {
        let r = take(toneHz: 999.9, toneDBFS: -120, noiseDBFS: -135)
        print("F3 tono despreciable:", String(describing: r.backgroundTone))
        if let t = r.backgroundTone { XCTAssertFalse(t.isFeedback) }
        XCTAssertFalse(r.isInconclusive)
        XCTAssertTrue(r.passes)
    }

    /// Una oscilación a −20 dBFS es del bucle: no concluyente.
    func testLoudToneIsFeedbackAndInconclusive() {
        let r = take(toneHz: 2_255.4, toneDBFS: -20, noiseDBFS: -80)
        XCTAssertEqual(r.backgroundTone?.isFeedback, true)
        XCTAssertTrue(r.isInconclusive)
    }

    func testFeedbackThresholds() {
        XCTAssertFalse(BackgroundTone(frequencyHz: 1000, peakDBFS: -120.8, prominenceDB: 12).isFeedback)
        XCTAssertFalse(BackgroundTone(frequencyHz: 1000, peakDBFS: -30, prominenceDB: 20).isFeedback)
        XCTAssertFalse(BackgroundTone(frequencyHz: 1000, peakDBFS: -70, prominenceDB: 60).isFeedback)
        XCTAssertTrue(BackgroundTone(frequencyHz: 2793.8, peakDBFS: -21, prominenceDB: 50).isFeedback)
        XCTAssertTrue(BackgroundTone(frequencyHz: 2255.4, peakDBFS: -18, prominenceDB: 70).isFeedback)
    }
}

#if canImport(AVFoundation)
/// Los mismos casos con el motor portátil (el de Windows) en el Mac.
final class PortableFeedbackLoopTests: FeedbackLoopTests {
    override var kind: PlayerKind { .portable }
}
#endif
