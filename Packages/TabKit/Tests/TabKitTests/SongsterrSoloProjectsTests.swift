import Foundation
import XCTest
@testable import TabKit

/// Informe de la pista de cada sección de solo en los proyectos reales (Tornado Of Souls, Benito Kamelas), como en la
/// app: secciones `solo` de `project.json`, primera revisión de la caché de Songsterr, pulsos preparados y stems. Sin
/// secciones de solo o sin `stems/guitar_lead.wav` el proyecto se salta. El roce tiene su puerta con margen en
/// `SongsterrAlignmentRoceTests`. Apagado por defecto:
///   TF_P5B_TESTS=1 Tools/test.sh TabKit SongsterrSoloProjectsTests
final class SongsterrSoloProjectsTests: XCTestCase {
    static let projects = ["Megadeth - Tornado Of Souls", "Benito Kamelas - Aquellas Cosas Que Solíamos Hacer"]

    func testReportSoloPairs() throws {
        guard ProcessInfo.processInfo.environment["TF_P5B_TESTS"] == "1" else {
            throw XCTSkip("informe de solos desactivado (TF_P5B_TESTS != 1)")
        }
        let fm = FileManager.default
        let root = P5BProjects.root
        for name in Self.projects {
            let dir = root.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("project.json")),
                  let project = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("SOLOS \(name): sin proyecto"); continue
            }
            let sections = (project["sections"] as? [[String: Any]]) ?? []
            let spans = sections.filter { $0["solo"] as? Bool == true }
                .compactMap { s in (s["start"] as? Double).flatMap { a in (s["end"] as? Double).map { a...$0 } } }
            let lead = dir.appendingPathComponent("stems/guitar_lead.wav")
            guard !spans.isEmpty, fm.fileExists(atPath: lead.path) else {
                print("SOLOS \(name): \(spans.count) secciones de solo, guitar_lead.wav \(fm.fileExists(atPath: lead.path) ? "sí" : "no"): nada que emparejar")
                continue
            }
            let cache = dir.appendingPathComponent("cache/songsterr")
            guard let song = try fm.contentsOfDirectory(atPath: cache.path).sorted().first,
                  let rev = try fm.contentsOfDirectory(atPath: cache.appendingPathComponent(song).path).sorted().first else {
                print("SOLOS \(name): sin caché de Songsterr"); continue
            }
            let revDir = cache.appendingPathComponent("\(song)/\(rev)")
            var tracks: [SongsterrTrack] = []
            while let d = try? Data(contentsOf: revDir.appendingPathComponent("\(tracks.count).json")) {
                tracks.append(try SongsterrTrackConverter.convert(d))
            }
            let an = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("cache/analysis.json"))) as! [String: Any]
            let b = (an["analysis"] as! [String: Any])["beats"] as! [String: Any]
            let raw = BeatTimes(beats: b["beats"] as! [Double], downbeats: b["downbeats"] as! [Double],
                                beatsPerBar: b["beatsPerBar"] as? Int)
            let beats = SongsterrBeatGrid.writtenTempo(tracks).map { SongsterrBeatGrid.prepare(raw, writtenTempo: $0).beats } ?? raw
            var stems: [SongsterrStemRole: URL] = [:]
            for r in SongsterrStemRole.allCases {
                let u = dir.appendingPathComponent("stems/\(r.rawValue).wav")
                if fm.fileExists(atPath: u.path) { stems[r] = u }
            }
            let a = try SongsterrAligner.align(tracks: tracks, beats: beats, stems: stems, soloSpans: spans)
            for p in a.soloPairs {
                print("SOLOS \(name) \(p.span) ← \(p.track.map { "\($0) \(tracks[$0].name)" } ?? "-") "
                      + String(format: "confianza %.3f margen %.3f ", p.confidence ?? .nan, p.margin ?? .nan)
                      + p.candidates.map { "\($0.track) \(tracks[$0.track].name) \($0.similarity.map { String(format: "%.3f", $0) } ?? "nil")" }
                        .joined(separator: ", "))
            }
        }
    }
}
