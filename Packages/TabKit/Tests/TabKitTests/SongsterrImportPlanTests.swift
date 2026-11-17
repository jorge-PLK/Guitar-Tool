import Foundation
import XCTest
@testable import TabKit

/// Emparejamiento editable stem → pista de Songsterr (mini-spec Fase 5b, decisiones 3 a 6). Datos sintéticos.
final class SongsterrImportPlanTests: XCTestCase {
    // MARK: - Datos sintéticos

    static func track(_ name: String, _ kind: TabTrackKind, partId: Int, ornaments: Int = 0, unknownDrums: Int = 0)
        -> SongsterrTrack {
        var report = SongsterrImportReport()
        report.notesWithOrnaments = ornaments
        report.unknownDrumNotes = unknownDrums
        return SongsterrTrack(name: name, instrumentId: nil, songId: 10, revisionId: 20, partId: partId, kind: kind,
                              tuningStrings: kind == .drums ? [] : [64, 59, 55, 50, 45, 40], bars: [],
                              tempoChanges: [], notes: [], hits: [], report: report)
    }

    static func scoreTrack(index: Int, kind: TabTrackKind) -> TabTrack {
        TabTrack(id: SongsterrImportPlan.extraID(index), name: "Songsterr \(index)", kind: kind,
                 tuning: kind == .drums ? nil : Tuning.guitar(.standard), source: nil, subdivisions: [.sixteenths])
    }

    static func alignment(tracks: [SongsterrTrack], pairs: [SongsterrStemPair] = [],
                          candidates: [SongsterrPairCandidate] = [],
                          warnings: [SongsterrStructureWarning] = [],
                          placements: [SongsterrTrackPlacement]? = nil) -> SongsterrAlignment {
        let score = TabScore(bars: [], beats: [], endTime: 0,
                             tracks: tracks.indices.map { scoreTrack(index: $0, kind: tracks[$0].kind) })
        return SongsterrAlignment(
            offsetBeats: 0, fineOffset: 0, blocks: [], usesBlocks: !warnings.isEmpty, globalSalience: 0,
            blockSalience: 0, structureWarnings: warnings, score: score,
            placements: placements ?? tracks.indices.map { SongsterrTrackPlacement(id: SongsterrImportPlan.extraID($0)) },
            pairs: pairs, candidates: candidates, extraTracks: [], timedNotes: [])
    }

    static let slots = [
        SongsterrStemSlot(id: "guitar-left", name: "Guitarra izq.", kind: .guitar, role: .guitarLeft),
        SongsterrStemSlot(id: "guitar-right", name: "Guitarra dcha.", kind: .guitar, role: .guitarRight),
        SongsterrStemSlot(id: "bass", name: "Bajo", kind: .bass, role: .bass),
        SongsterrStemSlot(id: "drums", name: "Batería", kind: .drums, role: .drums),
    ]

    /// 0 guitarra, 1 guitarra, 2 voz (guitarra para el conversor), 3 bajo, 4 batería.
    static let tracks = [
        track("Lead", .guitar, partId: 0, ornaments: 4), track("Rhythm", .guitar, partId: 1),
        track("Extra", .guitar, partId: 2, ornaments: 1), track("Bass", .bass, partId: 3),
        track("Drums", .drums, partId: 4, unknownDrums: 2),
    ]

    static func plan(pairs: [SongsterrStemPair], tracks: [SongsterrTrack] = tracks,
                     slots: [SongsterrStemSlot] = slots,
                     warnings: [SongsterrStructureWarning] = []) -> SongsterrImportPlan {
        let candidates = pairs.map { SongsterrPairCandidate(role: $0.role, track: $0.track, similarity: $0.confidence) }
        return SongsterrImportPlan(alignment: alignment(tracks: tracks, pairs: pairs, candidates: candidates,
                                                        warnings: warnings),
                                   tracks: tracks, slots: slots, songId: 10, revisionId: 20)
    }

    static func pair(_ role: SongsterrStemRole, _ track: Int, _ confidence: Double) -> SongsterrStemPair {
        SongsterrStemPair(role: role, track: track, confidence: confidence, margin: nil)
    }

    // MARK: - Propuesta

    func testProposalFollowsAlignerPairs() {
        let plan = Self.plan(pairs: [Self.pair(.guitarLeft, 0, 0.8), Self.pair(.guitarRight, 1, 0.6),
                                     Self.pair(.bass, 3, 0.7), Self.pair(.drums, 4, 0.9)])
        XCTAssertEqual(plan.assignment(for: "guitar-left"), SongsterrAssignment(stemID: "guitar-left", track: 0, confidence: 0.8))
        XCTAssertEqual(plan.assignment(for: "guitar-right")?.track, 1)
        XCTAssertEqual(plan.assignment(for: "bass")?.track, 3)
        XCTAssertEqual(plan.assignment(for: "drums")?.track, 4)
        XCTAssertEqual(plan.automaticStemIDs, [])
        XCTAssertEqual(plan.extraTracks, [2])
    }

    func testGuitarWithoutPairGoesAutomatic() {
        let plan = Self.plan(pairs: [Self.pair(.guitarLeft, 0, 0.8)])
        XCTAssertNil(plan.assignment(for: "guitar-right")?.track)
        XCTAssertNil(plan.assignment(for: "guitar-right")?.confidence)
        XCTAssertEqual(plan.automaticStemIDs, ["guitar-right"] + [])
        XCTAssertFalse(plan.extraTracks.contains(0))
    }

    /// Decisión 6: bajo y batería sin pareja medida, con una sola pista de ese tipo, usan la de Songsterr.
    func testSingleBassAndDrumsAreUsedWithoutMeasure() {
        let plan = Self.plan(pairs: [])
        XCTAssertEqual(plan.assignment(for: "bass"), SongsterrAssignment(stemID: "bass", track: 3, confidence: nil))
        XCTAssertEqual(plan.assignment(for: "drums"), SongsterrAssignment(stemID: "drums", track: 4, confidence: nil))
        XCTAssertEqual(plan.automaticStemIDs, ["guitar-left", "guitar-right"])
    }

    func testTwoBassTracksWithoutPairStayAutomatic() {
        let tracks = Self.tracks + [Self.track("Bass 2", .bass, partId: 5)]
        let plan = Self.plan(pairs: [], tracks: tracks)
        XCTAssertNil(plan.assignment(for: "bass")?.track)
        XCTAssertTrue(plan.automaticStemIDs.contains("bass"))
    }

    func testPairOfOtherKindIsIgnored() {
        let plan = Self.plan(pairs: [Self.pair(.bass, 0, 0.9)])  // la pista 0 es guitarra
        XCTAssertEqual(plan.assignment(for: "bass")?.track, 3)
        XCTAssertNil(plan.assignment(for: "bass")?.confidence)
    }

    // MARK: - Edición

    func testChoicesAreSameKindWithSimilarity() {
        let plan = Self.plan(pairs: [Self.pair(.guitarLeft, 0, 0.8)])
        let choices = plan.choices(for: "guitar-left")
        XCTAssertEqual(choices.map(\.track), [0, 1, 2])
        XCTAssertEqual(choices.first?.similarity, 0.8)
        XCTAssertNil(choices.last?.similarity)
        XCTAssertEqual(plan.choices(for: "bass").map(\.track), [3])
        XCTAssertEqual(plan.choices(for: "nope"), [])
    }

    func testAssignEditsAndRejectsInvalid() {
        var plan = Self.plan(pairs: [Self.pair(.guitarLeft, 0, 0.8)])
        XCTAssertTrue(plan.assign(stemID: "guitar-left", track: 2))
        XCTAssertEqual(plan.assignment(for: "guitar-left")?.track, 2)
        XCTAssertNil(plan.assignment(for: "guitar-left")?.confidence)
        XCTAssertEqual(plan.extraTracks, [0, 1])

        XCTAssertFalse(plan.assign(stemID: "guitar-left", track: 3), "un bajo no vale para una guitarra")
        XCTAssertFalse(plan.assign(stemID: "guitar-left", track: 99))
        XCTAssertFalse(plan.assign(stemID: "nope", track: 0))
        XCTAssertEqual(plan.assignment(for: "guitar-left")?.track, 2)

        XCTAssertTrue(plan.assign(stemID: "guitar-left", track: 0))
        XCTAssertEqual(plan.assignment(for: "guitar-left")?.confidence, 0.8)
        XCTAssertTrue(plan.assign(stemID: "guitar-left", track: nil))
        XCTAssertTrue(plan.automaticStemIDs.contains("guitar-left"))
    }

    func testUseAutomaticForAll() {
        var plan = Self.plan(pairs: [Self.pair(.guitarLeft, 0, 0.8), Self.pair(.bass, 3, 0.7)])
        plan.useAutomaticForAll()
        XCTAssertEqual(plan.automaticStemIDs, Self.slots.map(\.id))
        XCTAssertEqual(plan.extraTracks, [0, 1, 2, 3, 4])
    }

    // MARK: - Avisos

    func testStructureWarningsNameBars() {
        let w = [
            SongsterrStructureWarning(bar: 8, sourceMeasure: 8, time: 65, beats: 4, wholeBars: 1),
            SongsterrStructureWarning(bar: 20, sourceMeasure: 19, time: 150, beats: -8, wholeBars: -2),
            SongsterrStructureWarning(bar: 30, sourceMeasure: 28, time: 200, beats: 1, wholeBars: nil),
        ]
        let out = Self.plan(pairs: [], warnings: w).warnings
        XCTAssertTrue(out[0].contains("Compás 9 (1:05)") && out[0].contains("1 compás de más"), out[0])
        XCTAssertTrue(out[1].contains("Compás 21 (2:30)") && out[1].contains("faltan 2 compases"), out[1])
        XCTAssertTrue(out[2].contains("Compás 31 (3:20)") && out[2].contains("1 pulso de más"), out[2])
    }

    func testOrnamentAndDrumWarningsCountOnlyUsedTracks() {
        // Guitarra 0 (4 adornos), extra 2 (1) y batería 4 (2 golpes sin pieza); la guitarra 1 no tiene.
        let plan = Self.plan(pairs: [Self.pair(.guitarLeft, 0, 0.8), Self.pair(.drums, 4, 0.9)])
        let out = plan.warnings
        XCTAssertTrue(out.contains { $0.hasPrefix("5 notas con adornos") }, "\(out)")
        XCTAssertTrue(out.contains { $0.hasPrefix("2 golpes de percusión") }, "\(out)")

        var auto = plan
        auto.useAutomaticForAll()  // siguen contando: todas las pistas pasan a extra
        XCTAssertTrue(auto.warnings.contains { $0.hasPrefix("5 notas con adornos") })
    }

    func testNoWarningsWhenClean() {
        let clean = [Self.track("G", .guitar, partId: 0)]
        let plan = Self.plan(pairs: [Self.pair(.guitarLeft, 0, 0.8)], tracks: clean, slots: [Self.slots[0]])
        XCTAssertEqual(plan.warnings, [])
    }

    func testDroppedNotesWarning() {
        var p0 = SongsterrTrackPlacement(id: "songsterr-0")
        p0.droppedOutsideGrid = 3
        p0.droppedInExtraBeats = 2
        let tracks = [Self.track("G", .guitar, partId: 0)]
        let alignment = Self.alignment(tracks: tracks, pairs: [Self.pair(.guitarLeft, 0, 0.8)], placements: [p0])
        let plan = SongsterrImportPlan(alignment: alignment, tracks: tracks, slots: [Self.slots[0]], songId: 10,
                                       revisionId: 20)
        XCTAssertTrue(plan.warnings.contains { $0.hasPrefix("5 notas quedaron fuera") }, "\(plan.warnings)")
    }

    // MARK: - Resultado

    func testBuildRenamesPairedTracksAndKeepsExtras() {
        let plan = Self.plan(pairs: [Self.pair(.guitarLeft, 0, 0.8), Self.pair(.bass, 3, 0.7)])
        let r = plan.build()
        XCTAssertEqual(r.score.tracks.map(\.id), ["guitar-left", "bass", "drums", "songsterr-1", "songsterr-2"])
        XCTAssertEqual(r.score.tracks.first?.name, "Guitarra izq.")
        XCTAssertEqual(r.extraTrackIDs, ["songsterr-1", "songsterr-2"])
        XCTAssertEqual(r.automaticStemIDs, ["guitar-right"])
        for t in r.score.tracks {
            XCTAssertNil(t.source)
            XCTAssertEqual(t.imported?.songId, 10)
            XCTAssertEqual(t.imported?.revisionId, 20)
            XCTAssertEqual(t.imported?.converterVersion, SongsterrTrackConverter.version)
        }
        XCTAssertEqual(r.score.tracks.first?.imported?.partId, 0)
        XCTAssertEqual(r.score.tracks.last?.imported?.partId, 2)
        XCTAssertNil(r.score.tracks.first { $0.kind == .drums }?.tuning)
    }

    func testBuildAllAutomaticKeepsAllAsExtras() {
        var plan = Self.plan(pairs: [])
        plan.useAutomaticForAll()
        let r = plan.build()
        XCTAssertEqual(r.score.tracks.count, 5)
        XCTAssertEqual(r.extraTrackIDs.count, 5)
    }

    // MARK: - TabTrack.imported

    func testImportedStampIsAdditiveInJSON() throws {
        var t = Self.scoreTrack(index: 0, kind: .guitar)
        let old = try JSONEncoder().encode(t)
        XCTAssertNil(try JSONDecoder().decode(TabTrack.self, from: old).imported)

        t.imported = ImportedTrackStamp(songId: 1, revisionId: 2, converterVersion: 3, partId: nil)
        let back = try JSONDecoder().decode(TabTrack.self, from: try JSONEncoder().encode(t))
        XCTAssertEqual(back.imported, t.imported)
    }
}
