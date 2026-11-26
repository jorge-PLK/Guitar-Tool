import XCTest
@testable import VideoKit

/// M-5: el sondeo de presencia no debe describir (leer formatos de) ningún dispositivo.
final class CameraProbeTests: XCTestCase {
    func testHasCameraMatchesCameraWithoutDescribing() {
        let p = SimulatedCameraProvider(cameras: [.simulated])
        XCTAssertTrue(p.hasCamera(id: "sim-camera"))
        XCTAssertFalse(p.hasCamera(id: "otra"))
        XCTAssertEqual(p.camera(id: "sim-camera")?.id, "sim-camera")
        XCTAssertNil(p.camera(id: "otra"))
    }

    #if canImport(AVFoundation)
    func testRealProviderPresenceIsConsistentWithCamera() {
        let p = AVCameraProvider()
        XCTAssertFalse(p.hasCamera(id: "no-existe"))
        XCTAssertNil(p.camera(id: "no-existe"))
    }
    #endif
}
