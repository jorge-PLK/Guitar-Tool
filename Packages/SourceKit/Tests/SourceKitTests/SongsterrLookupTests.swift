import Foundation
import XCTest
@testable import SourceKit

// Datos SINTÉTICOS; nada de Songsterr real.

private actor FakeSongsterr: SongsterrServing {
    var searchResult: Result<[SongsterrSearchResult], Error> = .success([])
    var songs: [Int: Result<SongsterrSong, Error>] = [:]
    var linkResult: Result<SongsterrSong, Error> = .failure(SongsterrError.invalidHost)
    private(set) var searchCalls = 0
    private(set) var songCalls: [Int] = []

    func set(search r: Result<[SongsterrSearchResult], Error>) { searchResult = r }
    func set(song id: Int, _ r: Result<SongsterrSong, Error>) { songs[id] = r }
    func set(link r: Result<SongsterrSong, Error>) { linkResult = r }

    func search(artist: String, title: String) async throws -> [SongsterrSearchResult] {
        searchCalls += 1
        return try searchResult.get()
    }
    func song(songId: Int) async throws -> SongsterrSong {
        songCalls.append(songId)
        return try (songs[songId] ?? .failure(SongsterrError.noResults)).get()
    }
    func song(link: String) async throws -> SongsterrSong { try linkResult.get() }
}

private func track(_ part: Int, _ name: String) -> SongsterrTrack {
    SongsterrTrack(index: part, partId: part, name: name, instrument: "Guitar", instrumentId: 29,
                   tuning: [64, 59, 55, 50, 45, 40], isDrums: false, isBass: false, isGuitar: true,
                   url: URL(string: "https://example.invalid/\(part)")!)
}

private func song(_ id: Int, _ title: String) -> SongsterrSong {
    SongsterrSong(songId: id, revisionId: id * 10, artist: "Grupo", title: title, tracks: [track(0, "Rítmica"), track(1, "Solo")])
}

private func hit(_ id: Int) -> SongsterrSearchResult { SongsterrSearchResult(songId: id, artist: "Grupo", title: "T\(id)") }

@MainActor
final class SongsterrLookupTests: XCTestCase {
    func testSearchMarksFirstResultAndLoadsItsTracks() async {
        let fake = FakeSongsterr()
        await fake.set(search: .success([hit(1), hit(2)]))
        await fake.set(song: 1, .success(song(1, "T1")))
        let l = SongsterrLookup(service: fake)
        XCTAssertEqual(l.phase, .idle)
        await l.search(artist: "Grupo", title: "T1")
        XCTAssertEqual(l.phase, .results)
        XCTAssertEqual(l.results.map(\.songId), [1, 2])
        XCTAssertEqual(l.selectedID, 1)
        XCTAssertEqual(l.selectedSong?.tracks.map(\.name), ["Rítmica", "Solo"])
        XCTAssertNil(l.detailIssue)
        XCTAssertFalse(l.isBusy)
    }

    func testSelectingAnotherResultLoadsOnceAndCaches() async {
        let fake = FakeSongsterr()
        await fake.set(search: .success([hit(1), hit(2)]))
        await fake.set(song: 1, .success(song(1, "T1")))
        await fake.set(song: 2, .success(song(2, "T2")))
        let l = SongsterrLookup(service: fake)
        await l.search(artist: "a", title: "b")
        await l.select(2)
        await l.select(1)
        await l.select(2)
        XCTAssertEqual(l.selectedID, 2)
        let calls = await fake.songCalls
        XCTAssertEqual(calls, [1, 2])
    }

    func testNoResultsFailsWithOfferToGoAutomatic() async {
        let fake = FakeSongsterr()
        let l = SongsterrLookup(service: fake)
        await l.search(artist: "a", title: "b")
        XCTAssertEqual(l.phase, .failed(.noResults))
        XCTAssertTrue(l.results.isEmpty)
        XCTAssertNil(l.selectedID)
        XCTAssertTrue(SongsterrIssue.noResults.suggestsAutomatic)
        XCTAssertFalse(SongsterrIssue.noResults.canRetry)
        XCTAssertEqual(SongsterrIssue.noResults.message, "No está en Songsterr.")
    }

    func testRateLimitedRetriesOnlyWhenAskedAndThenRecovers() async {
        let fake = FakeSongsterr()
        await fake.set(search: .failure(SongsterrError.rateLimited))
        let l = SongsterrLookup(service: fake)
        await l.search(artist: "a", title: "b")
        XCTAssertEqual(l.phase, .failed(.rateLimited))
        var calls = await fake.searchCalls
        XCTAssertEqual(calls, 1)   // sin bucle
        await fake.set(search: .success([hit(1)]))
        await fake.set(song: 1, .success(song(1, "T1")))
        await l.retry()
        XCTAssertEqual(l.phase, .results)
        calls = await fake.searchCalls
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(SongsterrIssue.rateLimited.canRetry)
        XCTAssertTrue(SongsterrIssue.rateLimited.suggestsAutomatic)
    }

    func testIssueMapping() {
        XCTAssertEqual(SongsterrIssue(SongsterrError.offline), .offline)
        XCTAssertEqual(SongsterrIssue(SongsterrError.httpStatus(429)), .rateLimited)
        XCTAssertEqual(SongsterrIssue(SongsterrError.unknownFormat("x")), .formatChanged)
        XCTAssertEqual(SongsterrIssue(SongsterrError.invalidHost), .invalidLink)
        if case .other(let m) = SongsterrIssue(SongsterrError.httpStatus(500)) { XCTAssertTrue(m.contains("500")) } else { XCTFail() }
        XCTAssertTrue(SongsterrIssue.offline.canRetry)
        XCTAssertFalse(SongsterrIssue.formatChanged.canRetry)
        XCTAssertTrue(SongsterrIssue.formatChanged.suggestsAutomatic)
        XCTAssertEqual(SongsterrIssue.formatChanged.message, "Songsterr ha cambiado su formato.")
        XCTAssertFalse(SongsterrIssue.invalidLink.suggestsAutomatic)
    }

    func testUnknownFormatOnSearchFailsAsFormatChanged() async {
        let fake = FakeSongsterr()
        await fake.set(search: .failure(SongsterrError.unknownFormat("página")))
        let l = SongsterrLookup(service: fake)
        await l.search(artist: "a", title: "b")
        XCTAssertEqual(l.phase, .failed(.formatChanged))
    }

    func testTrackFailureKeepsResultsAndRetryRereadsOnlyThatSong() async {
        let fake = FakeSongsterr()
        await fake.set(search: .success([hit(1), hit(2)]))
        await fake.set(song: 1, .failure(SongsterrError.unknownFormat("pista")))
        let l = SongsterrLookup(service: fake)
        await l.search(artist: "a", title: "b")
        XCTAssertEqual(l.phase, .results)
        XCTAssertEqual(l.results.count, 2)
        XCTAssertEqual(l.detailIssue, .formatChanged)
        XCTAssertNil(l.selectedSong)
        await fake.set(song: 1, .success(song(1, "T1")))
        await l.retry()
        XCTAssertNil(l.detailIssue)
        XCTAssertNotNil(l.selectedSong)
        let searches = await fake.searchCalls
        XCTAssertEqual(searches, 1)
    }

    func testPastedLinkIsAddedOnTopAndSelected() async {
        let fake = FakeSongsterr()
        await fake.set(search: .success([hit(1)]))
        await fake.set(song: 1, .success(song(1, "T1")))
        await fake.set(link: .success(song(9, "Pegada")))
        let l = SongsterrLookup(service: fake)
        await l.search(artist: "a", title: "b")
        l.link = "  https://example.invalid/s9  "
        await l.submitLink()
        XCTAssertEqual(l.results.map(\.songId), [9, 1])
        XCTAssertEqual(l.selectedID, 9)
        XCTAssertEqual(l.selectedSong?.title, "Pegada")
        XCTAssertNil(l.linkIssue)
        XCTAssertNil(l.loadingID)
    }

    func testPastedLinkWorksAfterNoResultsAndBadLinkReportsInvalid() async {
        let fake = FakeSongsterr()
        let l = SongsterrLookup(service: fake)
        await l.search(artist: "a", title: "b")
        XCTAssertEqual(l.phase, .failed(.noResults))
        l.link = "https://otro.example/x"
        await l.submitLink()
        XCTAssertEqual(l.linkIssue, .invalidLink)
        XCTAssertEqual(l.phase, .failed(.noResults))
        await fake.set(link: .success(song(5, "Ok")))
        l.link = "https://example.invalid/s5"
        await l.submitLink()
        XCTAssertEqual(l.phase, .results)
        XCTAssertEqual(l.selectedID, 5)
        XCTAssertNil(l.linkIssue)
    }

    func testEmptyLinkDoesNothing() async {
        let l = SongsterrLookup(service: FakeSongsterr())
        l.link = "   "
        await l.submitLink()
        XCTAssertNil(l.linkIssue)
        XCTAssertNil(l.selectedID)
    }
}
