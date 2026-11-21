import XCTest
@testable import StudyKit

final class SongsterrGridFileTests: XCTestCase {
    func testDecodesFileJSON() throws {
        let json = #"{"songId":7,"revisionId":3,"beats":[0.5,1.0,1.5],"downbeats":[0.5],"writtenTempo":120}"#
        let g = try JSONDecoder().decode(SongsterrGridFile.self, from: Data(json.utf8))
        XCTAssertEqual(g, SongsterrGridFile(songId: 7, revisionId: 3, beats: [0.5, 1.0, 1.5], downbeats: [0.5], writtenTempo: 120))
        XCTAssertEqual(g.metronomeGrid(songId: 7, revisionId: 3)?.beats, [0.5, 1.0, 1.5])
        XCTAssertNil(g.metronomeGrid(songId: 7, revisionId: 4))
        XCTAssertNil(g.metronomeGrid(songId: 8, revisionId: 3))
    }
}
