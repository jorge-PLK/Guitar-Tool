import XCTest
@testable import Store

final class LibraryFilterTests: XCTestCase {
    func testCaseAndAccents() {
        XCTAssertTrue(LibraryFilter.matches(title: "Canción", artist: nil, query: "cancion"))
        XCTAssertTrue(LibraryFilter.matches(title: "One", artist: nil, query: "ONE"))
        XCTAssertTrue(LibraryFilter.matches(title: "x", artist: "Beyoncé", query: "beyonce"))
    }
    func testWordsSplitBetweenTitleAndArtist() {
        XCTAssertTrue(LibraryFilter.matches(title: "One", artist: "Metallica", query: "metallica one"))
        XCTAssertTrue(LibraryFilter.matches(title: "One", artist: "Metallica", query: "one metallica"))
    }
    func testMissingWordExcludes() {
        XCTAssertFalse(LibraryFilter.matches(title: "One", artist: "Metallica", query: "metallica two"))
        XCTAssertFalse(LibraryFilter.matches(title: "One", artist: nil, query: "metallica"))
    }
    func testExtraSpacesAndEmpty() {
        XCTAssertTrue(LibraryFilter.matches(title: "One", artist: "Metallica", query: "  metallica   one  "))
        XCTAssertTrue(LibraryFilter.matches(title: "One", artist: nil, query: ""))
        XCTAssertTrue(LibraryFilter.matches(title: "One", artist: nil, query: "   "))
    }
    func testWordsDoNotSpanTitleAndArtistBoundary() {
        XCTAssertFalse(LibraryFilter.matches(title: "ab", artist: "cd", query: "bc"))
    }
}

final class LibraryGroupingTests: XCTestCase {
    private typealias T = (title: String, artist: String?)
    private func group(_ items: [T], query: String = "") -> [ArtistGroup<T>] {
        LibraryGrouping.byArtist(items, query: query, title: \.title, artist: \.artist)
    }

    func testMergesCaseAndSpaces() {
        let g = group([("B", "Metallica"), ("A", "metallica "), ("C", " METALLICA")])
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].name, "Metallica")
        XCTAssertEqual(g[0].count, 3)
        XCTAssertEqual(g[0].items.map(\.title), ["A", "B", "C"])
    }
    func testAccentOrderAndNoArtistLast() {
        let g = group([("t", nil), ("t", "Zeta"), ("t", "Álamo"), ("t", "Beta"), ("t", "  ")])
        XCTAssertEqual(g.map(\.name), ["Álamo", "Beta", "Zeta", nil])
        XCTAssertEqual(g.last?.count, 2)
    }
    func testFilterAppliedBeforeGrouping() {
        let g = group([("One", "Metallica"), ("Two", "Metallica"), ("One", "Otro")], query: "one")
        XCTAssertEqual(g.map(\.name), ["Metallica", "Otro"])
        XCTAssertEqual(g.map(\.count), [1, 1])
        XCTAssertTrue(group([("One", "M")], query: "zzz").isEmpty)
    }
    func testSortedByTitle() {
        let items: [T] = [("b", nil), ("A", nil), ("c", nil)]
        let r = LibraryGrouping.sortedByTitle(items, title: \.title, artist: \.artist)
        XCTAssertEqual(r.map(\.title), ["A", "b", "c"])
    }
}
