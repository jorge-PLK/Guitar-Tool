import XCTest
@testable import VideoKit

final class VideoKitTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertEqual(VideoKit.version, "0.2.0")
    }
}
