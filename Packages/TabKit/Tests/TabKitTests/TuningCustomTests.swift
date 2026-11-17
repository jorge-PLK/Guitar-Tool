import XCTest
@testable import TabKit

/// Afinación personalizada (mini-spec Fase 5b, decisión 7).
final class TuningCustomTests: XCTestCase {
    /// Do estándar: C G C F A D de grave a agudo (MIDI 36 43 48 53 57 62).
    static let cStandard = [62, 57, 53, 48, 43, 36]

    func testLabelListsNotesFromLowestToHighest() {
        XCTAssertEqual(Tuning.custom(strings: Self.cStandard).customLabel, "Personalizada (C G C F A D)")
    }

    func testCustomRoundTripsWithExactStrings() throws {
        let tuning = Tuning.custom(strings: [64, 59, 55, 50, 45, 40, 35]) // 7 cuerdas
        let data = try JSONEncoder().encode(tuning)
        XCTAssertEqual(try JSONDecoder().decode(Tuning.self, from: data), tuning)
    }

    /// Una afinación escrita antes de existir `custom` se lee igual.
    func testOldJSONStillDecodes() throws {
        let json = #"{"preset":"dropD","strings":[64,59,55,50,45,38]}"#
        let tuning = try JSONDecoder().decode(Tuning.self, from: Data(json.utf8))
        XCTAssertEqual(tuning, .guitar(.dropD))
        XCTAssertFalse(TuningPreset.fixed.contains(.custom))
        XCTAssertEqual(TuningPreset.fixed.count, 4)
    }

    func testRetuningToCustomKeepsPitches() throws {
        var score = try TabFingeringTests.score()
        score.upsert(try TabFingeringTests.build(TabFingeringTests.melody([48, 55, 60, 64])).track)
        var editor = TabEditor(score: score)
        let report = try editor.setTuning(.custom(strings: Self.cStandard), trackID: "t")
        XCTAssertEqual(report.droppedNotes, 0)
        let retuned = editor.score.tracks[0]
        XCTAssertEqual(retuned.tuning, .custom(strings: Self.cStandard))
        XCTAssertEqual(retuned.notes.map(\.pitch), [48, 55, 60, 64])
    }
}
