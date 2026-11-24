import Foundation
import XCTest
@testable import AppCore

final class ContractFixturesSettingsTests: XCTestCase {
    func testSettingsArea() async throws {
        let rig = try FixtureRig(area: "settings")
        defer { rig.cleanup() }
        // Determinista en cualquier Mac: sin cámaras reales (AJ1 las lee de AVFoundation si no hay proveedor).
        let injected = SettingsEnvironment.cameras
        SettingsEnvironment.cameras = NoCameraProvider()
        defer { SettingsEnvironment.cameras = injected }
        // Solo `settings.get`; `audio.*` y `video.*` son de la ola 3.
        try await rig.run("settings.get")
    }
}
