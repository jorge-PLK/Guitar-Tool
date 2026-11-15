import XCTest
@testable import AnalysisKit

final class AnalysisKitTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertEqual(AnalysisKit.version, "0.1.0")
    }
}
