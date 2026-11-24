import Foundation
import XCTest
@testable import AppCore

final class ContractFixturesSettingsTests: XCTestCase {
    func testSettingsArea() async throws {
        let rig = try FixtureRig(area: "settings")
        defer { rig.cleanup() }
        // Solo `settings.get`; `audio.*` y `video.*` son de la ola 3.
        try await rig.run("settings.get")
    }
}
