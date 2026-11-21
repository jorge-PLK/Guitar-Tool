import NativeAudioFile
import XCTest
@testable import TabKit

/// Preproceso, picos y troceo de ADTOF frente al fixture de Python (`Fixtures/drums/`, ver su README), sin modelo.
/// Mini-spec Fase 5, «Pruebas», Batería.
final class DrumTranscriberTests: XCTestCase {
    /// Objetivo del encargo para el espectrograma (la spec pide 1e-4 en activaciones; la entrada no puede ir peor).
    static let spectrogramTolerance: Float = 1e-4
    /// Pesos del banco: float32 calculados igual que el original.
    static let filterbankTolerance: Float = 1e-7

    static let dir = Fixture.dir.appendingPathComponent("drums")
    static let frames = 1001

    struct RefHit: Equatable, CustomStringConvertible {
        var frame: Int
        var note: Int
        var description: String { "(\(frame), \(note))" }
    }

    static func referenceHits() throws -> [RefHit] {
        let j = try Fixture.json(dir.appendingPathComponent("hits.json"))
        let hits = try XCTUnwrap(j["hits"] as? [[String: Any]])
        return try hits.map { RefHit(frame: try XCTUnwrap($0["frame"] as? Int), note: try XCTUnwrap($0["note"] as? Int)) }
    }

    static func frameHits(_ hits: [TranscribedDrumHit]) -> [RefHit] {
        hits.map { RefHit(frame: Int(($0.time * Double(DrumContract.framesPerSecond)).rounded()), note: $0.midi) }
    }

    static func maxAbsDiff(_ a: [Float], _ b: [Float]) -> Float {
        precondition(a.count == b.count)
        return zip(a, b).reduce(0) { max($0, abs($1.0 - $1.1)) }
    }

    // MARK: Preproceso

    func testFilterbankMatchesFixture() throws {
        let j = try Fixture.json(Self.dir.appendingPathComponent("filterbank.json"))
        let entries = try XCTUnwrap(j["entries"] as? [[Double]])
        let n = DrumContract.magnitudeBins, nb = DrumContract.bands
        var ref = [Float](repeating: 0, count: nb * n)
        for e in entries { ref[Int(e[0]) * n + Int(e[1])] = Float(e[2]) }
        var got = [Float](repeating: 0, count: nb * n)
        let bands = DrumSpectrogram.filterbank
        XCTAssertEqual(bands.count, nb)
        for (b, band) in bands.enumerated() {
            for (i, w) in band.weights.enumerated() { got[b * n + band.start + i] = w }
        }
        let d = Self.maxAbsDiff(got, ref)
        print("ADTOF banco Swift frente a Python: |Δ| máx \(d), \(entries.count) pesos no nulos")
        XCTAssertLessThanOrEqual(d, Self.filterbankTolerance)
        XCTAssertEqual(got.filter { $0 != 0 }.count, entries.count)
    }

    func testSpectrogramParity() throws {
        let audio = try MonoAudio.load(Self.dir.appendingPathComponent("audio.wav"), sampleRate: DrumContract.sampleRate)
        XCTAssertEqual(audio.count, 441_000)
        let t0 = Date()
        let spec = DrumSpectrogram.compute(audio)
        let dt = Date().timeIntervalSince(t0)
        let ref = try Fixture.f32(Self.dir.appendingPathComponent("spec.f32"))
        XCTAssertEqual(ref.count, Self.frames * DrumContract.bands)
        XCTAssertEqual(spec.count, ref.count)
        let d = Self.maxAbsDiff(spec, ref)
        let mean = zip(spec, ref).reduce(0.0) { $0 + Double(abs($1.0 - $1.1)) } / Double(ref.count)
        print(String(format: "ADTOF espectrograma Swift frente a Python: |Δ| máx %.3g, media %.3g, máx ref %.3f; %.1f ms",
                     d, mean, ref.max() ?? 0, dt * 1000))
        XCTAssertLessThan(d, Self.spectrogramTolerance)
    }

    /// Un seno de 1 kHz llegado a 48 kHz y remuestreado da casi el mismo espectrograma que generado a 44,1 kHz.
    func testResampledInputMatchesNative() throws {
        let seconds = 2.0, f0 = 1000.0, amp: Float = 0.5
        func sine(_ rate: Double) -> [Float] {
            (0..<Int(seconds * rate)).map { amp * Float(sin(2 * Double.pi * f0 * Double($0) / rate)) }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tabkit-drums-48k-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let x = sine(48_000)
        try NativeAudioFile.write(url, channels: [x, x], sampleRate: 48_000, format: .float32)
        let loaded = try MonoAudio.load(url, sampleRate: DrumContract.sampleRate)
        XCTAssertEqual(loaded.count, 88_200)
        let a = DrumSpectrogram.compute(loaded), b = DrumSpectrogram.compute(sine(44_100))
        XCTAssertEqual(a.count, b.count)
        // Tramas interiores (fuera de los bordes del remuestreador y del relleno): 10..190.
        let nb = DrumContract.bands
        let d = Self.maxAbsDiff(Array(a[(10 * nb)..<(190 * nb)]), Array(b[(10 * nb)..<(190 * nb)]))
        let peak = b[(100 * nb)..<(101 * nb)].max() ?? 0
        print("ADTOF 48 kHz remuestreado frente a 44,1 kHz nativo: |Δ| máx \(d) (pico de la trama \(peak))")
        XCTAssertLessThan(d, 1e-4)   // medido: 8e-7
    }

    // MARK: Picos

    /// `act.f32` de Python → exactamente los 53 golpes de `hits.json`, con el margen de cada decisión.
    func testPeaksReproduceFixtureHits() throws {
        let act = try Fixture.f32(Self.dir.appendingPathComponent("act.f32"))
        XCTAssertEqual(act.count, Self.frames * DrumContract.classes)
        let got = Self.frameHits(DrumPeaks.hits(activations: act, frames: Self.frames))
        let ref = try Self.referenceHits()
        XCTAssertEqual(ref.count, 53)
        XCTAssertEqual(got, ref)

        // Margen: lo cerca que queda `p` de su umbral y, en los máximos locales, de su vecino más alto distinto.
        // Si es mucho mayor que la diferencia de activación admitida (1e-4), el resultado no depende del redondeo.
        var thrMargin = Float.infinity, maxMargin = Float.infinity
        let k = DrumContract.classes
        for c in 0..<k {
            let p = DrumPeaks.processed((0..<Self.frames).map { act[$0 * k + c] })
            let thr = DrumContract.thresholds[c]
            for t in p.indices {
                thrMargin = min(thrMargin, abs(p[t] - thr))
                guard p[t] >= thr else { continue }
                for j in max(0, t - 2)...min(p.count - 1, t + 1) where j != t {
                    maxMargin = min(maxMargin, abs(p[t] - p[j]))
                }
            }
        }
        print("ADTOF picos: \(got.count)/\(ref.count) golpes iguales; margen mínimo a umbral \(thrMargin), entre vecinos \(maxMargin)")
    }

    func testPeakPickingRules() {
        // Pico aislado sobre fondo cero: un golpe; por debajo del umbral (0,22 en `p`, no en la activación): nada.
        var a = [Float](repeating: 0, count: 40)
        a[20] = 0.5
        XCTAssertEqual(DrumPeaks.peakFrames(a, threshold: 0.22), [20])
        // Activación 0,23 ≥ 0,22, pero p = 0,23 − 0,23/12 ≈ 0,211 < 0,22: no hay golpe.
        a[20] = 0.23
        XCTAssertEqual(DrumPeaks.peakFrames(a, threshold: 0.22), [])
        // Dos picos a 2 tramas se combinan (queda el mayor); a 3 tramas, no.
        var b = [Float](repeating: 0, count: 40)
        b[10] = 0.6; b[12] = 0.9
        XCTAssertEqual(DrumPeaks.peakFrames(b, threshold: 0.22), [12])
        var c = [Float](repeating: 0, count: 40)
        c[10] = 0.9; c[13] = 0.9
        XCTAssertEqual(DrumPeaks.peakFrames(c, threshold: 0.22), [10, 13])
        // Meseta de dos tramas iguales: ambas son máximos locales y el grupo se queda con la primera.
        var d = [Float](repeating: 0, count: 40)
        d[20] = 0.8; d[21] = 0.8
        let p = DrumPeaks.processed(d)
        XCTAssertEqual(p[20], p[21], "las dos medias móviles abarcan las dos tramas: mismo p")
        XCTAssertEqual(DrumPeaks.peakFrames(d, threshold: 0.22), [20])
    }

    // MARK: Troceo

    func testChunkPlanCoversEveryFrameOnce() {
        for (frames, maxF, ctx) in [(1001, 60_000, 1000), (60_000, 60_000, 1000), (60_001, 60_000, 1000),
                                    (150_000, 60_000, 1000), (18_502, 4000, 1000), (2101, 300, 100)] {
            let plan = DrumChunking.plan(frames: frames, maxFrames: maxF, context: ctx)
            XCTAssertEqual(plan.first?.keep.lowerBound, 0)
            XCTAssertEqual(plan.last?.keep.upperBound, frames)
            for (a, b) in zip(plan, plan.dropFirst()) { XCTAssertEqual(a.keep.upperBound, b.keep.lowerBound) }
            for ch in plan {
                XCTAssertLessThanOrEqual(ch.input.count, maxF)
                XCTAssertTrue(ch.input.contains(ch.keep.lowerBound) && ch.input.contains(ch.keep.upperBound - 1))
                if plan.count > 1 {
                    // Contexto completo salvo en los extremos del tema.
                    XCTAssertEqual(ch.keep.lowerBound - ch.input.lowerBound, min(ctx, ch.keep.lowerBound))
                    XCTAssertEqual(ch.input.upperBound - ch.keep.upperBound, min(ctx, frames - ch.keep.upperBound))
                }
            }
            if frames <= maxF { XCTAssertEqual(plan.count, 1) }
        }
    }

    /// Un predictor local (cada salida depende de ±r tramas de entrada, r < contexto) troceado da exactamente lo
    /// mismo que de una vez: la unión no pierde, repite ni desplaza tramas.
    func testChunkedActivationsEqualSinglePass() throws {
        let frames = 2345, nb = DrumContract.bands
        let spec = (0..<(frames * nb)).map { Float(($0 * 7919) % 1009) / 1009 }
        let local = LocalPredictor(radius: 40)
        let whole = try DrumChunking.activations(spectrogram: spec, frames: frames, predictor: local,
                                                 maxFrames: 60_000, contextFrames: 1000)
        let recorder = LocalPredictor(radius: 40)
        let chunked = try DrumChunking.activations(spectrogram: spec, frames: frames, predictor: recorder,
                                                   maxFrames: 400, contextFrames: 50)
        XCTAssertEqual(recorder.calls.count, DrumChunking.plan(frames: frames, maxFrames: 400, context: 50).count)
        XCTAssertGreaterThan(recorder.calls.count, 5)
        XCTAssertTrue(recorder.calls.allSatisfy { $0 >= DrumContract.minModelFrames && $0 <= 400 })
        XCTAssertEqual(chunked, whole)
    }

    /// Menos de 100 tramas: entra rellenado a 100 y sale recortado a T.
    func testShortInputIsPaddedToModelMinimum() throws {
        let frames = 37, nb = DrumContract.bands
        let spec = (0..<(frames * nb)).map { Float($0 % 13) }
        let rec = LocalPredictor(radius: 0)
        let act = try DrumChunking.activations(spectrogram: spec, frames: frames, predictor: rec,
                                               maxFrames: 60_000, contextFrames: 1000)
        XCTAssertEqual(rec.calls, [DrumContract.minModelFrames])
        XCTAssertEqual(act.count, frames * DrumContract.classes)
    }

    /// `transcribe(url:)` con un predictor que devuelve `act.f32`: tramas, picos y orden como `hits.json`.
    func testTranscribeWiringWithFixtureActivations() async throws {
        let act = try Fixture.f32(Self.dir.appendingPathComponent("act.f32"))
        let t = DrumTranscriber(predictor: FixedPredictor(frames: Self.frames, act: act))
        let progress = ProgressLog()
        let hits = try await t.transcribe(url: Self.dir.appendingPathComponent("audio.wav")) { progress.add($0) }
        XCTAssertEqual(Self.frameHits(hits), try Self.referenceHits())
        XCTAssertEqual(progress.values.last, 1)
        XCTAssertEqual(progress.values, progress.values.sorted())
    }
}

/// Salida [T][5]: media de la entrada en las tramas [i − r, i + r] ∩ [0, T) del trozo, por columna (5 bandas).
/// Lleva la cuenta de las T con que se llama.
final class LocalPredictor: DrumActivationPredictor, @unchecked Sendable {
    let radius: Int
    private(set) var calls = [Int]()
    init(radius: Int) { self.radius = radius }

    func predict(spectrogram: UnsafeBufferPointer<Float>, frames t: Int) throws -> [Float] {
        calls.append(t)
        let nb = DrumContract.bands, k = DrumContract.classes
        var out = [Float](repeating: 0, count: t * k)
        for i in 0..<t {
            for c in 0..<k {
                var s: Float = 0
                for j in max(0, i - radius)...min(t - 1, i + radius) { s += spectrogram[j * nb + c * 7] }
                out[i * k + c] = s
            }
        }
        return out
    }
}

struct FixedPredictor: DrumActivationPredictor {
    let frames: Int
    let act: [Float]
    func predict(spectrogram: UnsafeBufferPointer<Float>, frames t: Int) throws -> [Float] {
        guard t == frames else { throw TranscriptionError.model("T = \(t), se esperaba \(frames)") }
        return act
    }
}

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var v = [Double]()
    func add(_ x: Double) { lock.lock(); v.append(x); lock.unlock() }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return v }
}
