import AVFoundation
import XCTest
@testable import tf_video

/// `tf-video` sin hardware (`--simulated`): `cameras`, `record` y `sync`.
final class TFVideoToolTests: XCTestCase {
    final class Lines: @unchecked Sendable {
        let lock = NSLock()
        var list: [String] = []
        func add(_ s: String) { lock.withLock { list.append(s) } }
        var text: String { lock.withLock { list.joined(separator: "\n") } }
    }

    @MainActor
    func testSimulatedCommands() async throws {
        let dir = try TestWav.tempDir("TFVideoToolTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lines = Lines()
        let env = Env(dir: dir, calibrationURL: dir.appendingPathComponent("none.json"), emit: { lines.add($0) })

        let c = await CLI.run(["cameras", "--simulated", "100"], env: env)
        XCTAssertEqual(c, Exit.ok)
        XCTAssertTrue(lines.text.contains("1920×1080"))

        let r = await CLI.run(["record", "--simulated", "2400.81", "--seconds", "3", "--sim-drift", "50", "--sim-drop", "20",
                               "--width", "640", "--height", "360"], env: env)
        print(lines.text)
        XCTAssertEqual(r, Exit.ok)
        let takes = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("take-") }
        let take = try XCTUnwrap(takes.first)
        for f in ["video.mov", "processed.wav", "frames.csv"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: take.appendingPathComponent(f).path), f)
        }
        XCTAssertTrue(lines.text.contains("Reloj del audio frente al host: 50.00 ppm"))

        let s = await CLI.run(["sync", "--simulated", "2400.81", "--seconds", "2"], env: env)
        XCTAssertEqual(s, Exit.ok)
        XCTAssertTrue(lines.text.contains("Jitter de las marcas"))

        let bad = await CLI.run(["record", "--simulated", "2400.81"], env: env)
        XCTAssertEqual(bad, Exit.error)
    }
}
