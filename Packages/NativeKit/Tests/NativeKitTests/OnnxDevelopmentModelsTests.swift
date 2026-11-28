import Foundation
import NativeONNX
import XCTest

/// Resolución de modelos .onnx: TF_MODELS_DIR, empaquetado junto al .exe (`models\<carpeta>`) y C:\tf-models.
final class OnnxDevelopmentModelsTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tf-models-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func place(_ root: URL, _ subpath: String) throws -> URL {
        let url = root.appendingPathComponent(subpath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: url)
        return url
    }

    func testPackagedModelNextToExecutableWithoutEnvironment() throws {
        let exe = try makeRoot()
        let packaged = try place(exe, "models/pose/model.onnx")
        let found = OnnxDevelopmentModels.resolve("pose", environment: [:], executableDirectory: exe)
        XCTAssertEqual(found?.standardizedFileURL, packaged.standardizedFileURL)
    }

    func testEnvironmentWinsOverPackaged() throws {
        let exe = try makeRoot(), dev = try makeRoot()
        _ = try place(exe, "models/pose/model.onnx")
        let fromEnv = try place(dev, "pose/model.onnx")
        let found = OnnxDevelopmentModels.resolve("pose", environment: [OnnxDevelopmentModels.environmentKey: dev.path],
                                                  executableDirectory: exe)
        XCTAssertEqual(found?.standardizedFileURL, fromEnv.standardizedFileURL)
    }

    func testEnvironmentWithoutFileFallsBackToPackaged() throws {
        let exe = try makeRoot(), dev = try makeRoot()
        let packaged = try place(exe, "models/pose/model.onnx")
        let found = OnnxDevelopmentModels.resolve("pose", environment: [OnnxDevelopmentModels.environmentKey: dev.path],
                                                  executableDirectory: exe)
        XCTAssertEqual(found?.standardizedFileURL, packaged.standardizedFileURL)
    }

    func testCandidatesListEveryTriedPathInOrder() throws {
        let exe = try makeRoot(), dev = try makeRoot()
        let paths = OnnxDevelopmentModels.candidates("pose", environment: [OnnxDevelopmentModels.environmentKey: dev.path],
                                                     executableDirectory: exe).map(\.path)
        XCTAssertEqual(paths.count, 3)
        XCTAssertTrue(paths[0].hasPrefix(dev.path))
        XCTAssertTrue(paths[1].hasPrefix(exe.path) && paths[1].contains("models"))
        XCTAssertTrue(paths[2].contains("tf-models"))
        XCTAssertNil(OnnxDevelopmentModels.resolve("pose", environment: [OnnxDevelopmentModels.environmentKey: dev.path],
                                                   executableDirectory: exe))
    }
}
