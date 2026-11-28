import Foundation
import XCTest
@testable import VideoKit

/// Canalización productor/consumidor de la exportación de Windows (portable: no usa Media Foundation).
final class FramePipelineTests: XCTestCase {
    private struct Boom: Error {}

    func testDeliversEveryIndexInOrder() throws {
        let p = FramePipeline<Int>(count: 500, capacity: 4) { i in
            if i % 7 == 0 { Thread.sleep(forTimeInterval: 0.0005) }
            return i
        }
        p.start()
        defer { p.stop() }
        for i in 0..<500 { XCTAssertEqual(try p.next(), i) }
    }

    func testQueueIsBounded() throws {
        let made = Counter()
        let p = FramePipeline<Int>(count: 100, capacity: 3) { i in made.increment(); return i }
        p.start()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertLessThanOrEqual(made.value, 3)
        XCTAssertEqual(try p.next(), 0)
        p.stop()
    }

    func testStopWhileProducerBlockedOnFullQueueDoesNotHang() throws {
        let p = FramePipeline<Int>(count: 1000, capacity: 2) { $0 }
        p.start()
        _ = try p.next()
        Thread.sleep(forTimeInterval: 0.1)
        p.stop()
        XCTAssertThrowsError(try p.next()) { XCTAssertTrue($0 is CancellationError) }
    }

    func testStopWakesBlockedConsumer() throws {
        let p = FramePipeline<Int>(count: 10, capacity: 2) { i in Thread.sleep(forTimeInterval: 5); return i }
        p.start()
        let done = expectation(description: "consumer returned")
        let box = Counter()
        Thread.detachNewThread {
            do { _ = try p.next() } catch is CancellationError { box.increment() } catch {}
            done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.1)
        let stopper = Thread { p.stop() }
        stopper.start()
        wait(for: [done], timeout: 10)
        XCTAssertEqual(box.value, 1)
    }

    func testProducerErrorIsDeliveredAfterEarlierItems() throws {
        let p = FramePipeline<Int>(count: 20, capacity: 4) { i in if i == 5 { throw Boom() }; return i }
        p.start()
        defer { p.stop() }
        for i in 0..<5 { XCTAssertEqual(try p.next(), i) }
        XCTAssertThrowsError(try p.next()) { XCTAssertTrue($0 is Boom) }
    }

    func testParallelWorkersDeliverInOrder() throws {
        let p = FramePipeline<Int>(count: 400, capacity: 6, workers: 3) { i, _ in
            Thread.sleep(forTimeInterval: Double((i * 7) % 5) * 0.0004)
            return i
        }
        p.start()
        defer { p.stop() }
        for i in 0..<400 { XCTAssertEqual(try p.next(), i) }
    }

    func testParallelWorkersErrorAndStop() throws {
        let p = FramePipeline<Int>(count: 50, capacity: 4, workers: 3) { i, _ in
            if i == 10 { throw Boom() }
            return i
        }
        p.start()
        for i in 0..<10 { XCTAssertEqual(try p.next(), i) }
        XCTAssertThrowsError(try p.next()) { XCTAssertTrue($0 is Boom) }
        p.stop()
        let q = FramePipeline<Int>(count: 1000, capacity: 3, workers: 2) { i, _ in i }
        q.start()
        _ = try q.next()
        q.stop()
    }

    func testSameFrameCountAsSerialLoop() throws {
        let total = 123
        let p = FramePipeline<Int>(count: total, capacity: 5) { $0 }
        p.start()
        defer { p.stop() }
        var got: [Int] = []
        for _ in 0..<total { got.append(try p.next()) }
        XCTAssertEqual(got, Array(0..<total))
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}
