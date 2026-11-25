import Foundation
import Store
import StudyKit
import XCTest
@testable import AppCore

// Ola2.C3 (K7, K8, K12): formas de acorde con capo, nombre y tonalidad transpuestos, en el núcleo. Tema sembrado con
// análisis `C:maj` (acordes 0-2 y 2-4).
@MainActor
final class StudyCoreDeviationsTests: XCTestCase {
    private func open() async throws -> FixtureRig {
        let rig = try FixtureRig(area: "study-core", services: JobServices(importer: EditsImporter(), separator: EditsSeparator(),
                                                                          levelMeter: nil, analyzer: nil, guitarSplitter: nil))
        let p = try FixtureSeed.project(in: rig.projects)
        _ = try await rig.call("study.open", "{\"projectId\":\"\(p.id.uuidString)\"}")
        return rig
    }

    private func result(_ rig: FixtureRig, _ method: String, _ params: String = "{}") async throws -> [String: Any] {
        let r = try await rig.call(method, params)
        return try XCTUnwrap(r["result"] as? [String: Any], "\(method): \(r)")
    }

    private func frets(_ shape: [String: Any]?) -> [Int?] {
        (shape?["frets"] as? [Any] ?? []).map { ($0 as? NSNumber)?.intValue }
    }

    /// K7: la forma que da el puente es la de `ChordShapes.shape(for:capo:)`, con capo 0 y 2 y con transposición.
    func testChordShapeMatchesChordShapesWithCapo() async throws {
        let rig = try await open()
        defer { rig.cleanup() }
        let dMaj = 2 * ChordLabel.qualityCount + 1
        for capo in [0, 2] {
            let r = try await result(rig, "study.chordShape", "{\"index\":\(dMaj),\"capo\":\(capo)}")
            let expected = try XCTUnwrap(ChordShapes.shape(for: ChordLabel(index: dMaj)!, capo: capo))
            let shape = r["shape"] as? [String: Any]
            XCTAssertEqual(frets(shape), expected.frets, "capo \(capo)")
            XCTAssertEqual(shape?["baseFret"] as? Int, expected.baseFret)
            XCTAssertEqual((shape?["barre"] as? [String: Any])?["fret"] as? Int, expected.barre?.fret)
            XCTAssertEqual(r["capo"] as? Int, capo)
        }
        // Sin `capo` usa el del transporte y la transposición actual (D +2 = E).
        _ = try await result(rig, "study.setCapo", "{\"capo\":2}")
        _ = try await result(rig, "study.setTranspose", "{\"semitones\":2}")
        let r = try await result(rig, "study.chordShape", "{\"index\":\(dMaj)}")
        let e = try XCTUnwrap(ChordShapes.shape(for: ChordLabel(index: dMaj)!.transposed(by: 2), capo: 2))
        XCTAssertEqual(frets(r["shape"] as? [String: Any]), e.frets)
        // Sin acorde: sin forma.
        let n = try await result(rig, "study.chordShape", "{\"index\":\(ChordLabel.noChordIndex)}")
        XCTAssertNil(n["shape"])
        XCTAssertEqual(n["display"] as? String, "N")
        // La instantánea ya trae la forma de cada acorde para el capo actual.
        let snap = try await result(rig, "study.snapshot")
        let chords = try XCTUnwrap((snap["analysis"] as? [String: Any])?["chords"] as? [[String: Any]])
        for c in chords {
            let idx = c["index"] as! Int
            let want = ChordShapes.shape(for: ChordLabel(index: idx)!.transposed(by: 2), capo: 2)
            XCTAssertEqual(frets(c["shape"] as? [String: Any]), want?.frets ?? [])
        }
    }

    final class Captured: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [[String: Any]] = []
        func add(_ s: String) {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] else { return }
            lock.withLock { items.append(o) }
        }
        func clear() { lock.withLock { items.removeAll() } }
        func payloads(_ event: String) -> [[String: Any]] {
            lock.withLock { items.filter { $0["event"] as? String == event }.compactMap { $0["payload"] as? [String: Any] } }
        }
    }

    /// K7/K8: capo, transposición y tonalidad reemiten `study.analysis` con acordes (`display`, `shape`) al día.
    func testTransposeCapoAndKeyReemitAnalysis() async throws {
        let rig = try await open()
        defer { rig.cleanup() }
        let events = Captured()
        rig.bridge.send = { events.add($0) }
        let dMaj = 2 * ChordLabel.qualityCount + 1
        _ = try await result(rig, "study.setChord", "{\"start\":0,\"end\":2,\"index\":\(dMaj)}")
        events.clear()
        _ = try await result(rig, "study.setCapo", "{\"capo\":2}")
        var last = try XCTUnwrap(events.payloads("study.analysis").last)
        var chords = try XCTUnwrap((last["analysis"] as? [String: Any])?["chords"] as? [[String: Any]])
        var first = try XCTUnwrap(chords.first)
        XCTAssertEqual(frets(first["shape"] as? [String: Any]), ChordShapes.shape(for: ChordLabel(index: dMaj)!, capo: 2)?.frets)
        events.clear()
        _ = try await result(rig, "study.setTranspose", "{\"semitones\":2}")
        last = try XCTUnwrap(events.payloads("study.analysis").last)
        chords = try XCTUnwrap((last["analysis"] as? [String: Any])?["chords"] as? [[String: Any]])
        first = try XCTUnwrap(chords.first)
        XCTAssertEqual(first["display"] as? String, "E")
        // Sin cambio de transposición ni capo no se reemite.
        events.clear()
        _ = try await result(rig, "study.setRate", "{\"rate\":0.75}")
        XCTAssertTrue(events.payloads("study.analysis").isEmpty)
        // setKey también.
        events.clear()
        _ = try await result(rig, "study.setKey", "{\"key\":\"A:min\"}")
        XCTAssertEqual(events.payloads("study.analysis").count, 1)
    }

    /// Vocabulario de la hoja «Acorde» (sin tema abierto), `shown` en el análisis y `setChord {shown}` que destranspone.
    func testChordVocabularyAndShownChord() async throws {
        let rig = try FixtureRig(area: "study-core", services: JobServices(importer: EditsImporter(), separator: EditsSeparator(),
                                                                          levelMeter: nil, analyzer: nil, guitarSplitter: nil))
        defer { rig.cleanup() }
        let v = try await result(rig, "study.chordVocabulary")
        let roots = try XCTUnwrap(v["roots"] as? [String])
        let qualities = try XCTUnwrap(v["qualities"] as? [[String: String]])
        XCTAssertEqual(roots.count, 12)
        XCTAssertEqual(roots[1], "C#")
        XCTAssertEqual(qualities.count, 14)
        XCTAssertEqual(qualities[1]["suffix"], "")
        XCTAssertEqual(qualities[0]["suffix"], "m")
        XCTAssertEqual(v["noChordIndex"] as? Int, ChordLabel.noChordIndex)

        let p = try FixtureSeed.project(in: rig.projects)
        _ = try await rig.call("study.open", "{\"projectId\":\"\(p.id.uuidString)\"}")
        _ = try await result(rig, "study.setTranspose", "{\"semitones\":2}")
        // Mostrado D mayor (+2) = C mayor guardado.
        let set = try await result(rig, "study.setChord", "{\"start\":0,\"end\":2,\"shown\":{\"root\":2,\"quality\":1}}")
        let chords = try XCTUnwrap((set["analysis"] as? [String: Any])?["chords"] as? [[String: Any]])
        let first = try XCTUnwrap(chords.first)
        XCTAssertEqual(first["index"] as? Int, ChordLabel(root: 0, quality: .maj).index)
        XCTAssertEqual(first["display"] as? String, "D")
        XCTAssertEqual(first["shown"] as? [String: Int], ["root": 2, "quality": 1])
        let bad = try await rig.call("study.setChord", "{\"start\":0,\"end\":2,\"shown\":{\"root\":12,\"quality\":1}}")
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? String, "bad-params")
    }

    /// K8: «D» con +2 sale «E»; `name` sigue sin transponer.
    func testTransposedChordNameAndKey() async throws {
        let rig = try await open()
        defer { rig.cleanup() }
        let dMaj = 2 * ChordLabel.qualityCount + 1
        _ = try await result(rig, "study.setChord", "{\"start\":0,\"end\":2,\"index\":\(dMaj)}")
        _ = try await result(rig, "study.setTranspose", "{\"semitones\":2}")
        let snap = try await result(rig, "study.snapshot")
        let analysis = try XCTUnwrap(snap["analysis"] as? [String: Any])
        let first = try XCTUnwrap((analysis["chords"] as? [[String: Any]])?.first)
        XCTAssertEqual(first["name"] as? String, "D")
        XCTAssertEqual(first["display"] as? String, "E")
        // Tonalidad C:maj vista +2 = D mayor, sin idioma.
        let key = try XCTUnwrap(analysis["key"] as? [String: Any])
        XCTAssertEqual(key["effective"] as? String, "C:maj")
        XCTAssertEqual(key["display"] as? [String: String], ["tonic": "D", "mode": "maj"])
        // Inverso: la interfaz manda «E menor» (vista +2); se guarda «D:min».
        let set = try await result(rig, "study.setKey", "{\"shown\":{\"tonic\":\"E\",\"mode\":\"min\"}}")
        let k2 = try XCTUnwrap((set["analysis"] as? [String: Any])?["key"] as? [String: Any])
        XCTAssertEqual(k2["override"] as? String, "D:min")
        XCTAssertEqual(k2["display"] as? [String: String], ["tonic": "E", "mode": "min"])
        // Tonalidad no mayor ni menor: error.
        let bad = try await rig.call("study.setKey", "{\"shown\":{\"tonic\":\"E\",\"mode\":\"dim\"}}")
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? String, "bad-params")
    }
}
