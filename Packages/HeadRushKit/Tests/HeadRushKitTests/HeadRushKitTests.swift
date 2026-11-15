import XCTest
@testable import HeadRushKit

final class HeadRushKitTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertEqual(HeadRushKit.version, "0.1.0")
    }
}
