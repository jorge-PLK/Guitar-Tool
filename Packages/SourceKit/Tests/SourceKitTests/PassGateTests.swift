import XCTest
@testable import SourceKit

@MainActor
final class PassGateTests: XCTestCase {
    func testRefusesSecondPassWhileRunning() async {
        let gate = PassGate()
        var runs = 0
        XCTAssertTrue(gate.start { _ in runs += 1; try? await Task.sleep(nanoseconds: 100_000_000) })
        XCTAssertTrue(gate.isRunning)
        XCTAssertFalse(gate.start { _ in runs += 100 })
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(gate.isRunning)
        XCTAssertEqual(runs, 1)
    }

    func testCancelledPassIsNotCurrentAndGateReopens() async {
        let gate = PassGate()
        var wrote = false
        var newWrote = false
        gate.start { isCurrent in
            try? await Task.sleep(nanoseconds: 100_000_000)
            if isCurrent() { wrote = true }
        }
        gate.cancel()
        XCTAssertFalse(gate.isRunning)
        XCTAssertTrue(gate.start { isCurrent in if isCurrent() { newWrote = true } })
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(wrote)
        XCTAssertTrue(newWrote)
        XCTAssertFalse(gate.isRunning)
    }
}
