import XCTest
@testable import MatchKit

final class MatchKitTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertEqual(MatchKit.version, "0.1.0")
    }
}
