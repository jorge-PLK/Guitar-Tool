import Foundation
import XCTest
@testable import tf_video
import VideoKit

/// `tf-video` sin hardware (`--simulated`): `cameras`, `record` y `sync`. Mismos casos en el Mac y en Windows (parte
/// 7.11b); `frame` en Windows necesita el modelo de pose (con `TF_MODEL_TESTS=1`; sin él, se prueba el error).
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
        func takeDirs() throws -> [URL] {
            try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("take-") }
        }
        let takes = try takeDirs()
        XCTAssertEqual(takes.count, 1)
        let take = try XCTUnwrap(takes.first)
        for f in ["video.mov", "processed.wav", "frames.csv"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: take.appendingPathComponent(f).path), f)
        }
        XCTAssertTrue(lines.text.contains("Reloj del audio frente al host: 50.00 ppm"))

        let s = await CLI.run(["sync", "--simulated", "2400.81", "--seconds", "2"], env: env)
        print(lines.text)
        XCTAssertEqual(s, Exit.ok)
        XCTAssertTrue(lines.text.contains("Jitter de las marcas"))
        // `sync` va a su propia carpeta (aunque caiga en el mismo segundo) y no toca la toma del `record`.
        let after = try takeDirs()
        XCTAssertEqual(after.count, 2)
        XCTAssertTrue(after.contains { $0.standardizedFileURL == take.standardizedFileURL })
        XCTAssertTrue(FileManager.default.fileExists(atPath: take.appendingPathComponent("video.mov").path))

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
        #if canImport(AVFoundation)
        let f = await CLI.run(["frame", video.path, "--png", png.path], env: env)
        print(lines.text)
        XCTAssertEqual(f, Exit.ok)
        XCTAssertTrue(lines.text.contains("Muestras: 8, con pose: 0"))
        XCTAssertTrue(lines.text.contains("sin detección"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: png.path))
        #else
        let model = MoveNetPoseTests.poseDirectory().appendingPathComponent("model.onnx")
        if ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1", FileManager.default.fileExists(atPath: model.path) {
            let f = await CLI.run(["frame", video.path, "--png", png.path, "--pose-model", model.path], env: env)
            print(lines.text)
            XCTAssertEqual(f, Exit.ok)
            XCTAssertTrue(lines.text.contains("Muestras: 8, con pose: 0"))
            XCTAssertTrue(lines.text.contains("sin detección"))
            let img = try XCTUnwrap(TestPNG.decode(try Data(contentsOf: png)))
            XCTAssertEqual(img.width, 320)
            XCTAssertEqual(img.height, 180)
        } else {
            // Pasada normal (sin modelo): error que dice qué fichero falta y cómo darlo; ni PNG ni caja vacía.
            let missing = dir.appendingPathComponent("no-existe.onnx")
            let f = await CLI.run(["frame", video.path, "--png", png.path, "--pose-model", missing.path], env: env)
            print(lines.text)
            XCTAssertEqual(f, Exit.error)
            XCTAssertTrue(lines.text.contains("no-existe.onnx"), lines.text)
            XCTAssertTrue(lines.text.contains("--pose-model"), lines.text)
            XCTAssertFalse(FileManager.default.fileExists(atPath: png.path))
        }
        #endif

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

/// Carpeta de toma única (parte 7.11b): dos pasadas en el mismo segundo no se pisan (en Windows, `sync` tras `record`
/// no podía reescribir `silence.wav` de la misma carpeta: `unwritable("silence.wav")`).
final class TakeDirectoryTests: XCTestCase {
    func testFreeTakeDirectorySkipsExistingOnes() {
        let base = URL(fileURLWithPath: "/tmp/tf-video", isDirectory: true)
        let name = "take-20261121-093232"
        func pick(_ taken: Set<String>) -> String {
            CLI.freeTakeDirectory(in: base, name: name) { taken.contains($0.lastPathComponent) }.lastPathComponent
        }
        XCTAssertEqual(pick([]), name)
        XCTAssertEqual(pick([name]), name + "-2")
        XCTAssertEqual(pick([name, name + "-2"]), name + "-3")
        // Un hueco: el primero libre empezando por -2.
        XCTAssertEqual(pick([name, name + "-3"]), name + "-2")
        XCTAssertEqual(CLI.freeTakeDirectory(in: base, name: name) { _ in false }.deletingLastPathComponent().path, base.path)
    }
}

/// PNG y cajas de `tf-video frame` fuera del Mac (`FramePNG`, parte 7.11b): puro, probado igual en los dos sistemas.
final class FramePNGTests: XCTestCase {
    /// BGRA con relleno de fila → PNG RGB → lector de miniz: mismos bytes. 200 × 120 = 72 120 bytes en bruto, dos
    /// bloques guardados (máx 65 535): cubre el corte entre bloques y el adler32 que comprueba miniz.
    func testEncodeRoundTrip() throws {
        let w = 200, h = 120, stride = w * 4 + 64
        var bgra = [UInt8](repeating: 7, count: stride * h)
        var rgb: [UInt8] = []
        for y in 0..<h {
            for x in 0..<w {
                let o = y * stride + x * 4
                let r = UInt8((x * 3 + y) % 256), g = UInt8((x * 7 + y * 5) % 256), b = UInt8((x + y * 11) % 256)
                bgra[o] = b; bgra[o + 1] = g; bgra[o + 2] = r; bgra[o + 3] = 255
                rgb += [r, g, b]
            }
        }
        let data = bgra.withUnsafeBytes { FramePNG.encode(pixels: $0.baseAddress!, width: w, height: h, bytesPerRow: stride) }
        let img = try XCTUnwrap(TestPNG.decode(data))
        XCTAssertEqual(img.width, w)
        XCTAssertEqual(img.height, h)
        XCTAssertEqual(img.channels, 3)
        XCTAssertEqual(img.pixels, rgb)
    }

    /// Caja (0,25; 0,25; 0,5; 0,5) en 100 × 80 con 2 px: borde de x 24–25 y 74–75, y 19–20 y 59–60 (centrado en la
    /// línea, como `CGContext.stroke`); dentro y fuera, intacto.
    func testStrokeCentersLineOnBoxEdge() {
        let w = 100, h = 80, stride = w * 4
        var bgra = [UInt8](repeating: 0, count: stride * h)
        bgra.withUnsafeMutableBytes {
            FramePNG.stroke(FramingBox(x: 0.25, y: 0.25, width: 0.5, height: 0.5), color: FramePNG.fixedColor, lineWidth: 2,
                            pixels: $0.baseAddress!, width: w, height: h, bytesPerRow: stride)
        }
        func red(_ x: Int, _ y: Int) -> Bool { bgra[y * stride + x * 4 + 2] == 255 && bgra[y * stride + x * 4] == 51 }
        let painted = (0..<h).flatMap { y in (0..<w).filter { red($0, y) } }.count
        // Perímetro de 2 px: 2 × (52 × 2) + 2 × (38 × 2) = 360 px.
        XCTAssertEqual(painted, 360)
        for (x, y) in [(24, 40), (25, 40), (74, 40), (75, 40), (50, 19), (50, 20), (50, 59), (50, 60), (24, 19), (75, 60)] {
            XCTAssertTrue(red(x, y), "(\(x), \(y))")
        }
        for (x, y) in [(23, 40), (26, 40), (73, 40), (76, 40), (50, 18), (50, 21), (50, 40), (0, 0)] {
            XCTAssertFalse(red(x, y), "(\(x), \(y))")
        }
        XCTAssertEqual(FramePNG.lineWidth(imageWidth: 320), 2)
        XCTAssertEqual(FramePNG.lineWidth(imageWidth: 1920), 6)
    }
}
