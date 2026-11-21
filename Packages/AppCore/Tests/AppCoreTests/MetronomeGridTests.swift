import XCTest
import Store
import StudyKit
@testable import AppCore

/// Rejilla del metrónomo de Backing: la de Songsterr solo si la fuente de la tablatura es ese tema y revisión; si no, el
/// análisis (igual que `StudySession.metronomeBeats` del Mac).
@MainActor
final class MetronomeGridTests: XCTestCase {
    private let analysisBeats = [0.5, 1.0, 1.5, 2.0]
    private let gridBeats = [0.25, 0.75, 1.25, 1.75]

    private func makeSession(source: TabSourceChoice?, grid: SongsterrGridFile?) throws -> StudySession {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("metro-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        var p = Project(song: Song(title: "T", artist: "A", source: "source/original.wav", sourceSHA256: "abc",
                                   sourceFormat: "wav", sourceSampleRate: 44100, sourceChannels: 2,
                                   sampleRate: 44100, duration: 4))
        p.separation = SeparationState(state: .done, model: "m", finishedAt: Date(timeIntervalSince1970: 1_700_000_000))
        p.tabSource = source
        let layout = ProjectLayout(folder: folder)
        try layout.createSkeleton()
        let src = StudyKitBridge.Source(separationModel: "m", separationFinishedAt: p.separation.finishedAt, sourceSHA256: "abc")
        try StudyKitBridge.saveCache(
            StudyKitBridge.Analysis(beats: analysisBeats, downbeats: [0.5], bpm: 120, beatsPerBar: 4, chords: [], key: "C:maj",
                                    keyConfidence: 0), source: src, cache: layout.analysisCache)
        try ProjectFile.save(p, to: folder)
        if let grid { try grid.save(to: layout.tabSongsterrGridFile) }
        return StudySession(project: p, folder: folder, store: FileStudyStore(folder: folder))
    }

    private func grid(song: Int = 7, revision: Int = 3) -> SongsterrGridFile {
        SongsterrGridFile(songId: song, revisionId: revision, beats: gridBeats, downbeats: [0.25], writtenTempo: 120)
    }

    func testSongsterrSourceWithMatchingGridUsesGrid() throws {
        let s = try makeSession(source: .songsterr(songId: 7, revisionId: 3, pairings: []), grid: grid())
        XCTAssertEqual(s.metronomeBeats?.beats, gridBeats)
        XCTAssertEqual(s.metronomeBeats?.downbeats, [0.25])
    }

    func testMismatchedRevisionFallsBackToAnalysis() throws {
        let s = try makeSession(source: .songsterr(songId: 7, revisionId: 4, pairings: []), grid: grid())
        XCTAssertEqual(s.metronomeBeats?.beats, analysisBeats)
    }

    func testNoFileFallsBackToAnalysis() throws {
        let s = try makeSession(source: .songsterr(songId: 7, revisionId: 3, pairings: []), grid: nil)
        XCTAssertEqual(s.metronomeBeats?.beats, analysisBeats)
    }

    func testAutomaticSourceIgnoresGrid() throws {
        let s = try makeSession(source: .automatic, grid: grid())
        XCTAssertEqual(s.metronomeBeats?.beats, analysisBeats)
    }
}
