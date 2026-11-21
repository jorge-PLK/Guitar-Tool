#if os(Windows)
import Foundation
import XCTest
@testable import VideoKit

/// `GuitarFramer.analyze` en Windows (plan, «Corte del paso 7», parte 7.11): toma de Media Foundation + MoveNet.
/// El de modelo real solo con `TF_MODEL_TESTS=1` y `<TF_MODELS_DIR o C:\tf-models>\pose\model.onnx`.
final class GuitarFramerWindowsTests: XCTestCase {
    final class Progress: @unchecked Sendable {
        let lock = NSLock()
        var list: [Double] = []
        func add(_ v: Double) { lock.withLock { list.append(v) } }
        var values: [Double] { lock.withLock { list } }
    }

    /// Sin modelo cargable: error de lectura que lo dice (no una caja vacía).
    func testAnalyzeWithUnloadableModelThrowsReadError() async throws {
        let dir = try TestWav.tempDir("GuitarFramerWindowsTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = dir.appendingPathComponent("v.mov")
        _ = try await VideoFileTests.writeVideo(video, start: 1, seconds: 1, color: (0, 0, 255))
        do {
            _ = try await GuitarFramer.analyze(videoURL: video, poseModel: dir.appendingPathComponent("no-existe.onnx"))
            XCTFail("debía fallar sin modelo")
        } catch let GuitarFramerError.read(message) {
            print("7.11 sin modelo: \(message)")
            XCTAssertTrue(message.contains("no-existe.onnx"), message)
        }
    }

    /// Vídeo liso de 2 s desde el tiempo 1 con el modelo real: 8 muestras (cada 0,25 s, como el Mac), tamaño del
    /// fotograma y progreso creciente hasta casi 1.
    func testAnalyzeSyntheticVideoWithRealModel() async throws {
        guard ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1" else {
            throw XCTSkip("tests del modelo real desactivados (TF_MODEL_TESTS != 1)")
        }
        let model = MoveNetPoseTests.poseDirectory().appendingPathComponent("model.onnx")
        guard FileManager.default.fileExists(atPath: model.path) else { throw XCTSkip("no está el modelo en \(model.path)") }
        let dir = try TestWav.tempDir("GuitarFramerWindowsTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let video = dir.appendingPathComponent("v.mov")
        _ = try await VideoFileTests.writeVideo(video, start: 1, seconds: 2, color: (0, 0, 255))
        let progress = Progress()
        let t0 = Date()
        let a = try await GuitarFramer.analyze(video: MontagePartVideo(url: video, videoOffset: 0, take: MontageSpan(start: 1, end: 3)),
                                               poseModel: model, progress: { progress.add($0) })
        let ms = Date().timeIntervalSince(t0) * 1000 / Double(max(1, a.samples))
        print(String(format: "7.11 analyze Windows: %d muestras, %d con pose, %d×%d, %.1f ms/muestra", a.samples, a.detected,
                     a.frameWidth, a.frameHeight, ms))
        XCTAssertEqual(a.samples, 8)
        XCTAssertEqual(a.frameWidth, 320)
        XCTAssertEqual(a.frameHeight, 180)
        let p = progress.values
        XCTAssertEqual(p.count, 8)
        XCTAssertEqual(p, p.sorted())
        XCTAssertEqual(p.last ?? 0, 0.875, accuracy: 0.01)
    }
}
#endif
