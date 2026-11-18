import Foundation
import XCTest
@testable import TabKit

/// Puerta real de la Fase 5c (`TF_P5B_TESTS=1`, datos de `P5BProjects`, solo caché de Songsterr): qué pistas de voz se
/// detectan en los tres temas.
final class TabVocalRealTests: XCTestCase {
    private func revisions(_ project: String, song: Int) throws -> URL {
        let dir = P5BProjects.project(project).appendingPathComponent("cache/songsterr/\(song)")
        let rev = try FileManager.default.contentsOfDirectory(atPath: dir.path).first { !$0.hasPrefix(".") }
        return dir.appendingPathComponent(try XCTUnwrap(rev))
    }

    func testVocalTracksOfTheThreeSongs() throws {
        guard ProcessInfo.processInfo.environment["TF_P5B_TESTS"] == "1" else {
            throw XCTSkip("TF_P5B_TESTS=1 y TF_P5B_PROJECTS con las cachés de Songsterr")
        }
        let cases: [(String, Int, [Int])] = [
            ("El roce de tu cuerpo - Platero Y Tu", 50624, []),
            ("Megadeth - Tornado Of Souls", 12824, [0, 1]),
            ("Benito Kamelas - Aquellas Cosas Que Solíamos Hacer", 3470719, [4]),
        ]
        for (project, song, vocals) in cases {
            let tracks = try P5BProjects.tracks(try revisions(project, song: song))
            let found = tracks.indices.filter { tracks[$0].kind == .vocal }
            print("VOCAL \(project): \(found.map { "\($0) «\(tracks[$0].name)» instrumento \(tracks[$0].instrumentId ?? -1), \(tracks[$0].notes.count) notas" })")
            print("NAMES \(project): \(SongsterrTrack.resolvedNames(tracks))")
            XCTAssertEqual(found, vocals, project)
            for i in found { XCTAssertFalse(tracks[i].notes.isEmpty, "\(project) pista \(i) sin notas") }
        }
    }
}
