import CoreML
import XCTest
@testable import TabKit

/// ADTOF con el modelo Core ML real (`.cpuOnly`) frente a Python (mini-spec Fase 5, «Pruebas», Batería). Solo con
/// `TF_MODEL_TESTS=1` y bajo el vigilante, de uno en uno:
///   TF_MODEL_TESTS=1 Tools/py/.venv/bin/python Probes/P4-modelos/common/guard.py --limit-gb 10 \
///     --log Temp/logs/guard-tabkit-drums.log -- Tools/test.sh TabKit DrumHeavyModelTests/testFixtureParity
/// Modelo: el que lleva la app, `App/Resources/Models/ADTOF_FrameRNN_fp32.mlpackage.zip`, descomprimido y compilado
/// a un temporal. Referencias: `Fixtures/drums/` y, para el tema entero, `Probes/P4-modelos/adtof/out/{act,hits}/torch/T1`.
final class DrumHeavyModelTests: XCTestCase {
    /// Spec: diferencia de activación < 1e-4 y golpes a ±10 ms.
    static let activationTolerance: Float = 1e-4
    static let hitTolerance = 0.010

    nonisolated(unsafe) private static var compiled: URL?

    private func modelURL() throws -> URL {
        guard ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1" else {
            throw XCTSkip("tests del modelo real desactivados (TF_MODEL_TESTS != 1)")
        }
        return try Self.compiledModel()
    }

    static func compiledModel() throws -> URL {
        if let c = compiled { return c }
        let zip = Fixture.repo.appendingPathComponent("App/Resources/Models/ADTOF_FrameRNN_fp32.mlpackage.zip")
        guard FileManager.default.fileExists(atPath: zip.path) else { throw XCTSkip("no está el modelo en \(zip.path)") }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tabkit-adtof-\(UUID().uuidString)")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, tmp.path]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0, "ditto no pudo descomprimir \(zip.lastPathComponent)")
        let c = try MLModel.compileModel(at: tmp.appendingPathComponent("ADTOF_FrameRNN_fp32.mlpackage"))
        compiled = c
        return c
    }

    /// Golpes por nota emparejados en orden: mismo número y |Δt| máximo.
    struct HitReport: CustomStringConvertible {
        var counts: [Int: (got: Int, ref: Int)]
        var maxDelta: Double
        var sameCounts: Bool { counts.values.allSatisfy { $0.got == $0.ref } }
        var description: String {
            let c = DrumContract.midiNotes.map { "\($0): \(counts[$0]?.got ?? 0)/\(counts[$0]?.ref ?? 0)" }
            return "golpes \(c.joined(separator: " · ")), |Δt| máx \(String(format: "%.4f", maxDelta)) s"
        }
    }

    static func compare(_ got: [TranscribedDrumHit], _ ref: [Int: [Double]]) -> HitReport {
        var counts = [Int: (Int, Int)](), maxDelta = 0.0
        for note in DrumContract.midiNotes {
            let g = got.filter { $0.midi == note }.map(\.time).sorted(), r = (ref[note] ?? []).sorted()
            counts[note] = (g.count, r.count)
            if g.count == r.count { for (a, b) in zip(g, r) { maxDelta = max(maxDelta, abs(a - b)) } } else { maxDelta = .infinity }
        }
        return HitReport(counts: counts, maxDelta: maxDelta)
    }

    // MARK: Fixture

    func testFixtureParity() async throws {
        let model = try modelURL()
        let dir = DrumTranscriberTests.dir
        let audioURL = dir.appendingPathComponent("audio.wav")
        let audio = try MonoAudio.load(audioURL, sampleRate: DrumContract.sampleRate)
        let frames = DrumContract.frames(forSamples: audio.count)
        XCTAssertEqual(frames, DrumTranscriberTests.frames)

        var t0 = Date()
        let transcriber = DrumTranscriber(modelURL: model)
        let spec = DrumSpectrogram.compute(audio)
        let tSpec = Date().timeIntervalSince(t0)
        t0 = Date()
        let act = try await transcriber.activations(spectrogram: spec, frames: frames)   // carga + 1.ª inferencia
        let tFirst = Date().timeIntervalSince(t0)
        t0 = Date()
        _ = try await transcriber.activations(spectrogram: spec, frames: frames)
        let tSecond = Date().timeIntervalSince(t0)

        let ref = try Fixture.f32(dir.appendingPathComponent("act.f32"))
        XCTAssertEqual(act.count, ref.count)
        let d = DrumTranscriberTests.maxAbsDiff(act, ref)
        print(String(format: "ADTOF Core ML (Swift, cpuOnly) frente a PyTorch: |Δ act| máx %.3g; espectro %.1f ms, carga+inferencia %.0f ms, inferencia %.0f ms",
                     d, tSpec * 1000, tFirst * 1000, tSecond * 1000))
        XCTAssertLessThan(d, Self.activationTolerance)

        t0 = Date()
        let hits = try await transcriber.transcribe(url: audioURL)
        let tAll = Date().timeIntervalSince(t0)
        var refByNote = [Int: [Double]]()
        for h in try DrumTranscriberTests.referenceHits() {
            refByNote[h.note, default: []].append(Double(h.frame) / Double(DrumContract.framesPerSecond))
        }
        let report = Self.compare(hits, refByNote)
        print("ADTOF fixture (Swift de extremo a extremo frente a hits.json): \(report); transcribe \(String(format: "%.0f", tAll * 1000)) ms")
        XCTAssertTrue(report.sameCounts)
        XCTAssertLessThanOrEqual(report.maxDelta, Self.hitTolerance + 1e-9)
        XCTAssertEqual(DrumTranscriberTests.frameHits(hits), try DrumTranscriberTests.referenceHits(), "mismas tramas exactas")
    }

    // MARK: Tema entero (T1, 185 s)

    private struct T1 {
        var drums: URL
        var torchAct: URL
        var torchHits: URL
    }

    private func t1() throws -> T1 {
        let roots = [Fixture.repo, Fixture.repo.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()]
        for r in roots {
            let p4 = r.appendingPathComponent("Probes/P4-modelos")
            let t = T1(drums: p4.appendingPathComponent("bs_roformer_sw/out/conv/coremlpub_cpu_gpu/T1/drums.wav"),
                       torchAct: p4.appendingPathComponent("adtof/out/act/torch/T1.npy"),
                       torchHits: p4.appendingPathComponent("adtof/out/hits/torch/T1"))
            if [t.drums, t.torchAct, t.torchHits].allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) { return t }
        }
        throw XCTSkip("no están el stem de batería de T1 ni las salidas de PyTorch de P4")
    }

    /// `.npy` v1/v2 de float32 little-endian en orden C.
    static func npyF32(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let major = data[6]
        let headerLen = major == 1 ? Int(data[8]) | Int(data[9]) << 8
            : Int(data[8]) | Int(data[9]) << 8 | Int(data[10]) << 16 | Int(data[11]) << 24
        let start = (major == 1 ? 10 : 12) + headerLen
        let header = String(decoding: data[(major == 1 ? 10 : 12)..<start], as: UTF8.self)
        XCTAssertTrue(header.contains("'<f4'") && header.contains("'fortran_order': False"), header)
        return data.withUnsafeBytes { raw in
            (0..<((data.count - start) / 4)).map {
                Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: start + $0 * 4, as: UInt32.self)))
            }
        }
    }

    static func torchHits(_ dir: URL) throws -> [Int: [Double]] {
        let names = ["kick": 35, "snare": 38, "tom": 47, "hihat": 42, "cymbal": 49]
        var res = [Int: [Double]]()
        for (name, note) in names {
            let text = try String(contentsOf: dir.appendingPathComponent("\(name).txt"), encoding: .utf8)
            res[note] = text.split(whereSeparator: \.isNewline).compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        }
        return res
    }

    /// T1 entero: activaciones frente a PyTorch y golpes a ±10 ms frente a sus golpes; tiempos de cada paso.
    func testFullSongT1() async throws {
        let model = try modelURL()
        let t = try t1()
        var t0 = Date()
        let audio = try MonoAudio.load(t.drums, sampleRate: DrumContract.sampleRate)
        let tLoad = Date().timeIntervalSince(t0)
        t0 = Date()
        let spec = DrumSpectrogram.compute(audio)
        let tSpec = Date().timeIntervalSince(t0)
        let frames = DrumContract.frames(forSamples: audio.count)
        let transcriber = DrumTranscriber(modelURL: model)
        t0 = Date()
        let act = try await transcriber.activations(spectrogram: spec, frames: frames)
        let tModel = Date().timeIntervalSince(t0)
        let ref = try Self.npyF32(t.torchAct)
        XCTAssertEqual(act.count, ref.count, "T = \(frames)")
        let d = DrumTranscriberTests.maxAbsDiff(act, ref)
        let hits = DrumPeaks.hits(activations: act, frames: frames)
        let report = Self.compare(hits, try Self.torchHits(t.torchHits))
        print(String(format: "ADTOF T1 (%d tramas) Swift frente a PyTorch: |Δ act| máx %.3g; ", frames, d) + "\(report)")
        print(String(format: "ADTOF T1 tiempos: lectura %.2f s, espectro %.2f s, carga+modelo %.2f s", tLoad, tSpec, tModel))
        XCTAssertLessThan(d, Self.activationTolerance)
        XCTAssertTrue(report.sameCounts)
        XCTAssertLessThanOrEqual(report.maxDelta, Self.hitTolerance + 1e-9)
    }

    /// Tema de 11 min (T1 repetido, 66 000 tramas) con los trozos del contrato: 2 trozos, el primero de 60 000
    /// tramas, el máximo del modelo. Informativo: tiempo y que el modelo acepta T = 60 000.
    func testLongSongWithContractChunks() async throws {
        let model = try modelURL()
        let t = try t1()
        let audio = try MonoAudio.load(t.drums, sampleRate: DrumContract.sampleRate)
        let one = DrumSpectrogram.compute(audio)
        let frames = 66_000, nb = DrumContract.bands
        var spec = [Float]()
        spec.reserveCapacity(frames * nb)
        while spec.count < frames * nb { spec.append(contentsOf: one.prefix(frames * nb - spec.count)) }
        let plan = DrumChunking.plan(frames: frames, maxFrames: DrumContract.maxModelFrames, context: DrumContract.chunkContextFrames)
        XCTAssertEqual(plan.map(\.input.count), [DrumContract.maxModelFrames, frames - 57_000 + DrumContract.chunkContextFrames])
        let t0 = Date()
        let act = try await DrumTranscriber(modelURL: model).activations(spectrogram: spec, frames: frames)
        let dt = Date().timeIntervalSince(t0)
        let hits = DrumPeaks.hits(activations: act, frames: frames)
        let sizes = plan.map { "\($0.input.count)" }.joined(separator: "+")
        print("ADTOF 11 min (\(frames) tramas, trozos \(sizes)): carga+modelo " + String(format: "%.2f s", dt) + ", \(hits.count) golpes")
        XCTAssertEqual(act.count, frames * DrumContract.classes)
    }

    /// Troceo con el modelo real: T1 en trozos de 10 000 tramas frente a una pasada. Con el contexto del contrato
    /// (`chunkContextFrames`) la unión queda por debajo de la tolerancia de activación y los golpes no cambian.
    func testChunkSeams() async throws {
        let model = try modelURL()
        let t = try t1()
        let audio = try MonoAudio.load(t.drums, sampleRate: DrumContract.sampleRate)
        let spec = DrumSpectrogram.compute(audio)
        let frames = DrumContract.frames(forSamples: audio.count)
        let whole = try await DrumTranscriber(modelURL: model).activations(spectrogram: spec, frames: frames)
        let wholeHits = DrumPeaks.hits(activations: whole, frames: frames)
        let maxF = 10_000
        for ctx in [1000, 2000, DrumContract.chunkContextFrames] {
            let chunker = DrumTranscriber(predictor: nil, modelURL: model, maxFrames: maxF, contextFrames: ctx)
            let act = try await chunker.activations(spectrogram: spec, frames: frames)
            let d = DrumTranscriberTests.maxAbsDiff(act, whole)
            let hits = DrumPeaks.hits(activations: act, frames: frames)
            let n = DrumChunking.plan(frames: frames, maxFrames: maxF, context: ctx).count
            print(String(format: "ADTOF troceo T1 (%d tramas, contexto %d, %d trozos): |Δ act| máx %.3g frente a una pasada; ", maxF, ctx, n, d)
                  + "golpes " + (hits == wholeHits ? "iguales" : "DISTINTOS (\(hits.count) / \(wholeHits.count))"))
            if ctx == DrumContract.chunkContextFrames {
                XCTAssertLessThan(d, Self.activationTolerance)
                XCTAssertEqual(hits, wholeHits)
            }
        }
    }
}
