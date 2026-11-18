import XCTest
@testable import TabKit

/// Tramo seleccionado para el bucle: ticks → segundos y posición en el compás (mini-spec Fase 5c, decisión 3).
final class TabSpanTests: XCTestCase {
    /// 2 compases de 4/4, pulsos cada 0,5 s desde 1 s; el final de la rejilla en 5 s.
    private func score() -> TabScore {
        let beats = (0..<8).map { TabBeat(time: 1 + 0.5 * Double($0), bar: $0 / 4, indexInBar: $0 % 4) }
        let bars = [TabBar(start: 1, firstBeat: 0, beatCount: 4, tempo: 120), TabBar(start: 3, firstBeat: 4, beatCount: 4, tempo: 120)]
        return TabScore(bars: bars, beats: beats, endTime: 5)
    }

    private let tpb = TabScore.ticksPerBeat

    func testRangeGoesFromStartOfFirstBeatToEndOfLast() throws {
        let r = try XCTUnwrap(score().timeRange(of: TabSpan(startTick: 2 * tpb, endTick: 4 * tpb)))
        XCTAssertEqual(r.lowerBound, 2, accuracy: 1e-9)
        XCTAssertEqual(r.upperBound, 3, accuracy: 1e-9)
    }

    func testRangeOfLastBeatEndsAtEndTime() throws {
        let r = try XCTUnwrap(score().timeRange(of: TabSpan(startTick: 7 * tpb, endTick: 8 * tpb)))
        XCTAssertEqual(r.upperBound, 5, accuracy: 1e-9)
    }

    func testEmptyOrOutsideSpanHasNoRange() {
        XCTAssertNil(score().timeRange(of: TabSpan(startTick: 3 * tpb, endTick: 3 * tpb)))
        XCTAssertNil(score().timeRange(of: TabSpan(startTick: 9 * tpb, endTick: 10 * tpb)))
    }

    func testSpanNormalizesAndUnions() {
        let a = TabSpan(startTick: 30, endTick: 10)
        XCTAssertEqual(a, TabSpan(startTick: 10, endTick: 30))
        XCTAssertEqual(a.union(TabSpan(startTick: 40, endTick: 50)), TabSpan(startTick: 10, endTick: 50))
    }

    func testBarPositionStartAndEnd() throws {
        let s = score()
        let start = try XCTUnwrap(s.barPosition(ofTick: 5 * tpb))
        XCTAssertEqual(start.bar, 1)
        XCTAssertEqual(start.fraction, 0.25, accuracy: 1e-9)
        // El final en el límite de compás cuenta como el final del compás anterior.
        let end = try XCTUnwrap(s.barPosition(ofTick: 4 * tpb, asEnd: true))
        XCTAssertEqual(end.bar, 0)
        XCTAssertEqual(end.fraction, 1, accuracy: 1e-9)
        let asStart = try XCTUnwrap(s.barPosition(ofTick: 4 * tpb))
        XCTAssertEqual(asStart.bar, 1)
        XCTAssertEqual(asStart.fraction, 0, accuracy: 1e-9)
        let last = try XCTUnwrap(s.barPosition(ofTick: 8 * tpb, asEnd: true))
        XCTAssertEqual(last.bar, 1)
        XCTAssertEqual(last.fraction, 1, accuracy: 1e-9)
    }
}
