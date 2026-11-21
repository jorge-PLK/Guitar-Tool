#if canImport(CoreML)
import CoreML
#endif
import XCTest
@testable import TabKit

/// Basic Pitch con el modelo Core ML real frente a la referencia de Python (mini-spec Fase 4, «Pruebas»). Solo con
/// `TF_MODEL_TESTS=1` y bajo el vigilante, de uno en uno:
///   TF_MODEL_TESTS=1 Tools/py/.venv/bin/python Probes/P4-modelos/common/guard.py --limit-gb 10 \
///     --log Temp/logs/guard-tabkit-basicpitch.log -- Tools/test.sh TabKit BasicPitchHeavyModelTests/testParity
/// Modelo: el que lleva la app, `App/Resources/Models/BasicPitch_nmp.mlpackage.zip`, descomprimido y compilado a
/// un temporal, en CPU+GPU. Referencia: `Fixtures/BasicPitch/` (ONNX Runtime CPU, ver su README). `tf-ml` midió
/// 57/57 notas idénticas desde Python: aquí se exigen (startFrame, endFrame, pitch) exactos y en el mismo orden.
final class BasicPitchHeavyModelTests: XCTestCase {
    /// README del fixture: posteriorgramas a 1e-4 (Core ML desde Python mide 1e-6), notas iguales en
    /// (startFrame, endFrame, pitch) y amplitud a 1e-4.
    static let posteriorgramTolerance: Float = 1e-4
    static let amplitudeTolerance: Float = 1e-4

    nonisolated(unsafe) private static var compiled: URL?

    private func modelURL() throws -> URL {
        guard ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1" else {
            throw XCTSkip("tests del modelo real desactivados (TF_MODEL_TESTS != 1)")
        }
        return try Self.compiledModel()
    }

    static func compiledModel() throws -> URL {
        #if !canImport(CoreML)
        // Windows (parte 7.8): el ONNX de la parte 7.3, sin compilar.
        return try tabKitDevelopmentModel("basic_pitch")
        #else
        if let c = compiled { return c }
        let zip = Fixture.repo.appendingPathComponent("App/Resources/Models/BasicPitch_nmp.mlpackage.zip")
        guard FileManager.default.fileExists(atPath: zip.path) else { throw XCTSkip("no está el modelo en \(zip.path)") }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tabkit-basicpitch-\(UUID().uuidString)")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, tmp.path]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0, "ditto no pudo descomprimir \(zip.lastPathComponent)")
        let pkg = tmp.appendingPathComponent("BasicPitch_nmp.mlpackage")
        let c = try MLModel.compileModel(at: pkg)
        compiled = c
        return c
        #endif
    }

    private static func maxAbsDiff(_ a: [Float], _ b: [Float]) -> Float {
        precondition(a.count == b.count)
        return zip(a, b).reduce(0) { max($0, abs($1.0 - $1.1)) }
    }

    /// Posteriorgramas del Core ML en Swift (troceado incluido) frente a los de Python, y notas frente a `notes.json`.
    func testParity() async throws {
        let model = try modelURL()
        let dir = Fixture.dir.appendingPathComponent("BasicPitch")
        let audioURL = dir.appendingPathComponent("audio.wav")
        let audio = try MonoAudio.load(audioURL, sampleRate: BasicPitchContract.sampleRate)
        XCTAssertEqual(audio.count, 132_300)

        let transcriber = BasicPitchTranscriber(modelURL: model)
        let post = try await transcriber.posteriorgram(audio: audio)
        let refNote = try Fixture.f32(dir.appendingPathComponent("note.f32"))
        let refOnset = try Fixture.f32(dir.appendingPathComponent("onset.f32"))
        XCTAssertEqual(post.frames, 516)
        XCTAssertEqual(post.note.count, refNote.count)
        let dNote = Self.maxAbsDiff(post.note, refNote), dOnset = Self.maxAbsDiff(post.onset, refOnset)
        print("Basic Pitch Core ML (Swift, CPU+GPU) frente a Python: |Δ note| máx \(dNote), |Δ onset| máx \(dOnset)")
        XCTAssertLessThanOrEqual(dNote, Self.posteriorgramTolerance)
        XCTAssertLessThanOrEqual(dOnset, Self.posteriorgramTolerance)

        let notes = BasicPitchNotes.notes(note: post.note, onset: post.onset, frames: post.frames)
        let report = try BasicPitchNotesTests.compare(notes, toReference: dir)
        print("Basic Pitch notas Core ML (Swift) frente a Python: \(report)")
        XCTAssertTrue(report.sameSequence, "mismo orden que Python")
        XCTAssertLessThanOrEqual(report.maxAmplitude, Self.amplitudeTolerance)

        let events = try await transcriber.transcribe(url: audioURL)
        XCTAssertEqual(events.count, report.count)
    }

    /// Informativo (sin umbral): papel por pasaje de cada guitarra suelta de T1, con los pulsos fuertes de
    /// beat_this (`Fixtures/T1/downbeats.json`). Lento (9 pistas de 185 s):
    ///   … -- Tools/test.sh TabKit BasicPitchHeavyModelTests/testReportT1GuitarParts
    func testReportT1GuitarParts() async throws {
        let model = try modelURL()
        let roots = [Fixture.repo, Fixture.repo.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()]
        guard let parts = roots.map({ $0.appendingPathComponent("Probes/testaudio/out/T1/guitar_parts") })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("no están las guitarras sueltas de T1")
        }
        let beats = try Fixture.json(Fixture.dir.appendingPathComponent("T1/downbeats.json"))
        let downbeats = try XCTUnwrap(beats["downbeats"] as? [Double])
        let files = try FileManager.default.contentsOfDirectory(at: parts, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        _ = model
        // Caché de notas y tablas en Temp/bench/t1 (como el banco de proyecto).
        let out = Fixture.repo.appendingPathComponent("Temp/bench/t1")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for f in files {
            let name = f.deletingPathExtension().lastPathComponent
            let notes = try await PassageBenchReportTests.cachedNotes(f, cache: out.appendingPathComponent("notes_\(name).json"))
            print("T1 " + (try PassageBenchReportTests.report(name: name, url: f, notes: notes, downbeats: downbeats, out: out)))
        }
    }
}
