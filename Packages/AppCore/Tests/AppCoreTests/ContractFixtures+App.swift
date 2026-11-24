import Foundation
import Store
import XCTest
@testable import AppCore

final class ContractFixturesAppTests: XCTestCase {
    func testAppArea() async throws {
        let rig = try FixtureRig(area: "app")
        defer { rig.cleanup() }
        let o = try await rig.run("app.info")
        XCTAssertNotNil(o["result"])
    }
}
