import Foundation
import XCTest
@testable import TabKit

/// Ficheros de prueba (`Fixtures/`, recurso del target; `Fixtures/BasicPitch/` lo genera `tf-ml`).
enum Fixture {
    static let dir = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    /// Raíz del repo (o del worktree), para los modelos y audios de `Probes/` y `App/`.
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func f32(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        return data.withUnsafeBytes { raw in
            (0..<(data.count / 4)).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
        }
    }

    static func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}

/// Paso posteriorgramas → notas frente al original de Python, sin modelo.
final class BasicPitchNotesTests: XCTestCase {
    /// Tolerancias: fotogramas y notas exactos; amplitud (np.mean en float32 frente a vDSP) y tiempos.
    static let amplitudeTolerance: Float = 1e-6
    static let timeTolerance = 1e-9

    func testDefaultsMatchBasicPitchPredict() {
        XCTAssertEqual(BasicPitchContract.minimumNoteFrames, 11)          // round(127.70 ms · 86,13 fps)
        XCTAssertEqual(BasicPitchContract.hopSamples, 36_164)
        XCTAssertEqual(BasicPitchContract.keptFramesPerWindow, 142)
        XCTAssertEqual(BasicPitchContract.windowTimeOffset, 0.010326077097505669, accuracy: 1e-15)
    }

    /// `make_reference.py`: `output_to_notes_polyphonic` de basic-pitch 0.4.0 sobre posteriorgramas sintéticos con
    /// huecos bajo el umbral, onsets débiles (los recoge melodia), silencio (0/0 → NaN en Python) y empate en el
    /// argmax. Notas en el mismo orden que Python, fotogramas exactos.
    func testPortMatchesPythonOnSyntheticPosteriorgrams() throws {
        let dir = Fixture.dir.appendingPathComponent("NoteCreation")
        let ref = try Fixture.json(dir.appendingPathComponent("reference.json"))
        let cases = try XCTUnwrap(ref["cases"] as? [String: [String: Any]])
        XCTAssertEqual(Set(cases.keys), ["random_a", "random_b", "silence", "constant"])
        var total = 0, worstAmp: Float = 0, worstTime = 0.0
        for (name, c) in cases.sorted(by: { $0.key < $1.key }) {
            let frames = try XCTUnwrap(c["frames"] as? Int)
            let expected = try XCTUnwrap(c["notes"] as? [[Double]])
            let note = try Fixture.f32(dir.appendingPathComponent("\(name)_note.f32"))
            let onset = try Fixture.f32(dir.appendingPathComponent("\(name)_onset.f32"))
            let got = BasicPitchNotes.notes(note: note, onset: onset, frames: frames)
            XCTAssertEqual(got.count, expected.count, name)
            for (g, e) in zip(got, expected) {
                XCTAssertEqual([g.start, g.end, g.pitch], [Int(e[0]), Int(e[1]), Int(e[2])], name)
                worstAmp = max(worstAmp, abs(g.amplitude - Float(e[3])))
                worstTime = max(worstTime, abs(BasicPitchContract.time(ofFrame: g.start) - e[4]),
                                abs(BasicPitchContract.time(ofFrame: g.end) - e[5]))
            }
            total += expected.count
        }
        print("BasicPitchNotes sintético: \(total) notas, |Δ amplitud| máx \(worstAmp), |Δ tiempo| máx \(worstTime) s")
        XCTAssertEqual(total, 111)
        XCTAssertLessThanOrEqual(worstAmp, Self.amplitudeTolerance)
        XCTAssertLessThanOrEqual(worstTime, Self.timeTolerance)
    }

    /// Fixture de `tf-ml` (6 s de la guitarra de T1): los posteriorgramas de Python (ONNX) por el port dan las
    /// notas de `notes.json` de Python. Comparadas ordenadas por (startFrame, pitch), como pide su README.
    func testPortMatchesPythonOnT1Posteriorgrams() throws {
        let dir = Fixture.dir.appendingPathComponent("BasicPitch")
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("notes.json").path) else {
            throw XCTSkip("falta Fixtures/BasicPitch (lo genera tf-ml)")
        }
        let note = try Fixture.f32(dir.appendingPathComponent("note.f32"))
        let onset = try Fixture.f32(dir.appendingPathComponent("onset.f32"))
        let got = BasicPitchNotes.notes(note: note, onset: onset, frames: note.count / BasicPitchContract.nPitches)
        let report = try Self.compare(got, toReference: dir)
        print("BasicPitchNotes T1 (posteriorgramas de Python): \(report)")
        XCTAssertTrue(report.sameSequence, "mismo orden que Python")
        XCTAssertLessThanOrEqual(report.maxAmplitude, Self.amplitudeTolerance)
        XCTAssertLessThanOrEqual(report.maxTime, Self.timeTolerance)
    }

    struct Report: CustomStringConvertible {
        var count = 0
        var sameSequence = false
        var maxAmplitude: Float = 0
        var maxTime = 0.0
        var description: String {
            "\(count) notas, mismo orden \(sameSequence), |Δ amplitud| máx \(maxAmplitude), |Δ tiempo| máx \(maxTime) s"
        }
    }

    /// Falla si (startFrame, endFrame, pitch) no coinciden como conjunto ordenado; mide amplitud y tiempos.
    static func compare(_ got: [BasicPitchNotes.FrameNote], toReference dir: URL,
                        file: StaticString = #filePath, line: UInt = #line) throws -> Report {
        let ref = try Fixture.json(dir.appendingPathComponent("notes.json"))
        let notes = try XCTUnwrap(ref["notes"] as? [[String: Any]])
        let expected: [(BasicPitchNotes.FrameNote, Double, Double)] = try notes.map {
            (BasicPitchNotes.FrameNote(start: try XCTUnwrap($0["startFrame"] as? Int), end: try XCTUnwrap($0["endFrame"] as? Int),
                                       pitch: try XCTUnwrap($0["pitch"] as? Int),
                                       amplitude: Float(try XCTUnwrap($0["amplitude"] as? Double))),
             try XCTUnwrap($0["startTime"] as? Double), try XCTUnwrap($0["endTime"] as? Double))
        }
        var r = Report(count: expected.count)
        r.sameSequence = got.map { [$0.start, $0.end, $0.pitch] } == expected.map { [$0.0.start, $0.0.end, $0.0.pitch] }
        let order: ((BasicPitchNotes.FrameNote, Double, Double), (BasicPitchNotes.FrameNote, Double, Double)) -> Bool = {
            ($0.0.start, $0.0.pitch, $0.0.end) < ($1.0.start, $1.0.pitch, $1.0.end)
        }
        let g = got.map { ($0, 0.0, 0.0) }.sorted(by: order)
        let e = expected.sorted(by: order)
        XCTAssertEqual(g.map { [$0.0.start, $0.0.end, $0.0.pitch] }, e.map { [$0.0.start, $0.0.end, $0.0.pitch] },
                       file: file, line: line)
        for (a, b) in zip(g, e) {
            r.maxAmplitude = max(r.maxAmplitude, abs(a.0.amplitude - b.0.amplitude))
            r.maxTime = max(r.maxTime, abs(BasicPitchContract.time(ofFrame: a.0.start) - b.1),
                            abs(BasicPitchContract.time(ofFrame: a.0.end) - b.2))
        }
        return r
    }
}
