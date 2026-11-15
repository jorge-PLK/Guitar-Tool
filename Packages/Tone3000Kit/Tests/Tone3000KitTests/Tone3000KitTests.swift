import XCTest
@testable import Tone3000Kit

final class Tone3000KitTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertEqual(Tone3000Kit.version, "0.1.0")
    }
}
