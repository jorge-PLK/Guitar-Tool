#if canImport(AVFoundation)
import AVFoundation
import XCTest
@testable import tf_video
import VideoKit

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

    /// `frame` (sin persona: sin detección, PNG escrito) y `montage` desde un plan en JSON.
    @MainActor
    func testFrameAndMontageCommands() async throws {
        let dir = try TestWav.tempDir("TFVideoToolTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lines = Lines()
        let env = Env(dir: dir, calibrationURL: dir.appendingPathComponent("none.json"), emit: { lines.add($0) })
        let video = dir.appendingPathComponent("v.mov")
        _ = try await VideoFileTests.writeVideo(video, start: 1, seconds: 2, color: (0, 0, 255))
        let png = dir.appendingPathComponent("frame.png")
        let f = await CLI.run(["frame", video.path, "--png", png.path], env: env)
        print(lines.text)
        XCTAssertEqual(f, Exit.ok)
        XCTAssertTrue(lines.text.contains("Muestras: 8, con pose: 0"))
        XCTAssertTrue(lines.text.contains("sin detección"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: png.path))

        let plan = MontagePlan(canvas: .landscape, fps: 30, layout: .side, span: MontageSpan(start: 1, end: 3), barDuration: 0.5, fadeIn: true,
                               fadeOut: true, parts: [
                                   MontagePart(id: "a", name: "Rítmica", isSolo: false, presence: [MontageSpan(start: 1, end: 3)],
                                               video: MontagePartVideo(url: video, videoOffset: 0, take: MontageSpan(start: 1, end: 3)))
                               ])
        let planURL = dir.appendingPathComponent("plan.json")
        try JSONEncoder().encode(plan).write(to: planURL)
        let out = dir.appendingPathComponent("m.mov")
        let m = await CLI.run(["montage", planURL.path, out.path, "--width", "320", "--height", "180", "--codec", "h264"], env: env)
        print(lines.text)
        XCTAssertEqual(m, Exit.ok)
        XCTAssertTrue(lines.text.contains("320×180 h264 a 30.00 fps, 60 fotogramas"))
        let missing = await CLI.run(["montage", planURL.path], env: env)
        XCTAssertEqual(missing, Exit.error)
    }
}
#else
import Foundation
import XCTest

/// Windows: `tf-video` en Windows es de la parte 7.11 (encuadre); `frame` y `montage` necesitan además el detector de
/// pose y el compositor.
final class TFVideoToolTests: XCTestCase {
    func testSimulatedCommands() throws { throw XCTSkip("[paso 7] encuadre") }
    func testFrameAndMontageCommands() throws { throw XCTSkip("[paso 7] encuadre") }
}
#endif // canImport(AVFoundation)
