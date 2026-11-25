import CoreGraphics
import Foundation
import Store
import XCTest
@testable import AppCore

// 2.C2 (D-2, D-3): imán de bordes de sección y ajuste del bucle por arrastre en el núcleo, comparados con `SectionEdgeDrag`
// (Store) y con `BeatGrid.snap` (la cuenta de SwiftUI). Tema sembrado: acordes 0-2 y 2-4 (el test parte el primero en 1),
// pulsos cada 0,5 desde 0,5, compases en 0,5 y 2,5; secciones «Intro» 0-2 y «Solo» 2-4.
@MainActor
final class StudySnapTests: XCTestCase {
    private struct Setup {
        let rig: FixtureRig
        let intro: Store.Section, solo: Store.Section
        let chords: [(start: Double, end: Double)]
        let bars: [Double]
        let duration: Double
    }

    private func setUp2() async throws -> Setup {
        let rig = try FixtureRig(area: "study-snap", services: JobServices(importer: EditsImporter(), separator: EditsSeparator(),
                                                                          levelMeter: nil, analyzer: nil, guitarSplitter: nil))
        let p = try FixtureSeed.project(in: rig.projects, sections: true)
        let o = try await rig.call("study.open", "{\"projectId\":\"\(p.id.uuidString)\"}")
        XCTAssertNil(o["error"])
        let s = try await rig.call("study.splitChord", "{\"at\":1}")
        let r = try XCTUnwrap(s["result"] as? [String: Any])
        let analysis = try XCTUnwrap(r["analysis"] as? [String: Any])
        let chords = try XCTUnwrap(analysis["chords"] as? [[String: Any]]).map { (($0["start"] as! NSNumber).doubleValue, ($0["end"] as! NSNumber).doubleValue) }
        let bars = try XCTUnwrap(analysis["downbeats"] as? [Double])
        let secs = try XCTUnwrap(r["sections"] as? [[String: Any]]).map {
            Store.Section(id: UUID(uuidString: $0["id"] as! String)!, name: $0["name"] as! String, start: ($0["start"] as! NSNumber).doubleValue,
                          end: ($0["end"] as! NSNumber).doubleValue, solo: ($0["solo"] as? Bool) == true ? true : nil)
        }
        return Setup(rig: rig, intro: secs[0], solo: secs[1], chords: chords, bars: bars, duration: StudyTests.seconds)
    }

    /// Arrastre de SwiftUI: una fila con una celda por acorde (1 s = 100 pt), agarrado en el borde y soltado en `to`.
    private func oracle(_ x: Setup, _ section: Store.Section, start: Bool, to: Double, bar: Bool) throws -> [Store.Section] {
        let cells = x.chords.map {
            SectionEdgeDrag.Cell(row: 0, frame: CGRect(x: $0.start * 100, y: 0, width: ($0.end - $0.start) * 100, height: 10),
                                 time: $0.start, end: $0.end, chordStart: $0.start)
        }
        let editor = SectionEditor(sections: [x.intro, x.solo], duration: x.duration)
        let original = start ? section.start : section.end
        let grab = CGPoint(x: original * 100, y: 5)
        let drag = try XCTUnwrap(SectionEdgeDrag(editor: editor, id: section.id, isStart: start, cells: cells, bars: x.bars, grab: grab))
        return drag.sections(at: CGPoint(x: to * 100, y: 5), bar: bar)
    }

    private func edges(_ list: [[String: Any]]) -> [[Double]] {
        list.map { [($0["start"] as! NSNumber).doubleValue, ($0["end"] as! NSNumber).doubleValue] }
    }

    private func edges(_ list: [Store.Section]) -> [[Double]] { list.map { [$0.start, $0.end] } }

    func testPreviewAndUpdateMatchSectionEdgeDrag() async throws {
        let x = try await setUp2()
        defer { x.rig.cleanup() }
        // (sección, borde inicio?, destino): dentro de un acorde, cerca de compás, borde original, contra la vecina, hasta el final.
        let cases: [(Store.Section, Bool, Double)] = [
            (x.intro, true, 0.4), (x.intro, true, 0.6), (x.intro, true, 0.3), (x.intro, true, 0.2),
            (x.solo, true, 1.2), (x.solo, true, 1.9), (x.solo, true, 2.2), (x.solo, true, 2.4), (x.solo, true, 3.0),
            (x.solo, false, 3.1), (x.solo, false, 3.9), (x.solo, false, 5.0), (x.solo, false, 2.4),
            (x.intro, false, 1.2), (x.intro, false, 1.6),
        ]
        for (section, start, to) in cases {
            for snap in ["chord", "bar"] {
                let bar = snap == "bar"
                let expected = edges(try oracle(x, section, start: start, to: to, bar: bar))
                let params = "{\"id\":\"\(section.id.uuidString)\",\"start\":\(start),\"to\":\(to),\"snap\":\"\(snap)\"}"
                let preview = try await x.rig.call("study.previewSectionEdge", params)
                let got = edges(try XCTUnwrap((preview["result"] as? [String: Any])?["sections"] as? [[String: Any]]))
                XCTAssertEqual(got, expected, "preview \(snap) \(section.name) start=\(start) to=\(to)")

                let key = start ? "start" : "end"
                let upd = try await x.rig.call("study.updateSection",
                                               "{\"id\":\"\(section.id.uuidString)\",\"\(key)\":\(to),\"snap\":\"\(snap)\"}")
                let applied = edges(try XCTUnwrap((upd["result"] as? [String: Any])?["sections"] as? [[String: Any]]))
                XCTAssertEqual(applied, expected, "update \(snap) \(section.name) start=\(start) to=\(to)")
                _ = try await x.rig.call("study.discardSections")
            }
        }
    }

    func testPreviewWithoutSnapIsUnchangedAndBadSnapFails() async throws {
        let x = try await setUp2()
        defer { x.rig.cleanup() }
        let base = "\"id\":\"\(x.intro.id.uuidString)\",\"start\":false,\"to\":1.3"
        let none = try await x.rig.call("study.previewSectionEdge", "{\(base)}")
        let explicit = try await x.rig.call("study.previewSectionEdge", "{\(base),\"snap\":\"none\"}")
        let a = edges(try XCTUnwrap((none["result"] as? [String: Any])?["sections"] as? [[String: Any]]))
        let b = edges(try XCTUnwrap((explicit["result"] as? [String: Any])?["sections"] as? [[String: Any]]))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a[0][1], 1.3)
        let bad = try await x.rig.call("study.previewSectionEdge", "{\(base),\"snap\":\"beat\"}")
        XCTAssertNotNil(bad["error"])
    }

    func testSetLoopSnap() async throws {
        let x = try await setUp2()
        defer { x.rig.cleanup() }
        func loop(_ params: String) async throws -> (Double, Double, String?) {
            let r = try await x.rig.call("study.setLoop", params)
            let l = try XCTUnwrap(((r["result"] as? [String: Any])?["loop"]) as? [String: Any], "\(r)")
            return (try XCTUnwrap(l["start"] as? Double), try XCTUnwrap(l["end"] as? Double), l["name"] as? String)
        }
        // none: tal cual, con el nombre dado.
        var l = try await loop("{\"start\":0.7,\"end\":2.2,\"name\":\"Riff\"}")
        XCTAssertEqual([l.0, l.1], [0.7, 2.2]); XCTAssertEqual(l.2, "Riff")
        l = try await loop("{\"start\":0.7,\"end\":2.2,\"snap\":\"none\"}")
        XCTAssertEqual([l.0, l.1], [0.7, 2.2])
        // chord (SwiftUI sin ⌥): al pulso más cercano de cada extremo.
        l = try await loop("{\"start\":0.7,\"end\":2.2,\"snap\":\"chord\"}")
        XCTAssertEqual([l.0, l.1], [0.5, 2.0]); XCTAssertEqual(l.2, "acordes")
        // bar (⌥): al compás (BeatGrid.snap, que avanza si queda vacío).
        l = try await loop("{\"start\":0.7,\"end\":2.2,\"snap\":\"bar\"}")
        XCTAssertEqual(l.2, "compases")
        let expected = StudyEditsBridge.snap(beats: [0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4], downbeats: x.bars, 0.7...2.2, bar: true)
        XCTAssertEqual([l.0, l.1], [expected.lowerBound, expected.upperBound])
        // El nombre explícito manda.
        l = try await loop("{\"start\":0.7,\"end\":2.2,\"snap\":\"bar\",\"name\":\"Mi bucle\"}")
        XCTAssertEqual(l.2, "Mi bucle")
        let bad = try await x.rig.call("study.setLoop", "{\"start\":1,\"end\":2,\"snap\":\"beat\"}")
        XCTAssertNotNil(bad["error"])
    }
}
