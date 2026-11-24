import Foundation
import XCTest
import VideoKit
@testable import AppCore

/// Hook de píxeles de la cámara (`Bridge.setCameraFrameSink`, 0.S1b): con receptor el relevo entrega sin JPEG ni cola.
final class FrameRelayPixelSinkTests: XCTestCase {
    private final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    private func pixels() -> FramePixelBuffer {
        #if canImport(CoreVideo)
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32BGRA, nil, &pb)
        return pb!
        #else
        return FramePixelBuffer(pixelFormat: .bgra, width: 16, height: 16)
        #endif
    }

    func testPixelSinkReceivesEveryFrameUntilStop() {
        let count = Count()
        let relay = FrameRelay(channel: "camera") { _, _ in count.bump() }
        for i in 0..<10 { XCTAssertTrue(relay.push(pixels(), ptsMs: Double(i))) }
        XCTAssertEqual(count.value, 10)
        relay.stop()
        XCTAssertFalse(relay.push(pixels(), ptsMs: 11))
        XCTAssertEqual(count.value, 10)
    }

    func testBridgeCameraSinkSwitchesRelayToPixels() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tf-pixsink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bridge = try Bridge(options: LaunchOptions(projectsFolder: dir.appendingPathComponent("P"),
                                                       supportDir: dir.appendingPathComponent("S"), audio: .simulated),
                                mediaBase: "https://tf.media/")
        let service = try XCTUnwrap(bridge.recordService)
        XCTAssertNil(service.cameraPixelSink)
        XCTAssertNotNil(service.cameraRelayFactory(bridge))  // JPEG
        let count = Count()
        bridge.setCameraFrameSink { _, _ in count.bump() }
        let relay = try XCTUnwrap(service.cameraRelayFactory(bridge))
        relay.push(pixels(), ptsMs: 0)
        XCTAssertEqual(count.value, 1)
        bridge.setCameraFrameSink(nil)
        XCTAssertNil(service.cameraPixelSink)
    }
}
