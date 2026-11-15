import XCTest
@testable import TabKit

final class TabKitTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertEqual(TabKit.version, "0.1.0")
    }
}
