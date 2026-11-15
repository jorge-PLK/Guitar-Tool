import XCTest
@testable import StudyKit

final class StudyKitTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertEqual(StudyKit.version, "0.1.0")
    }
}
