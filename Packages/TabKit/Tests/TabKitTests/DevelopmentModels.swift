import Foundation
import XCTest

/// `.onnx` de desarrollo en Windows (parte 7.8): `<TF_MODELS_DIR o C:\tf-models>\<carpeta>\model.onnx`, la
/// estructura de `Probes/P8-windows/ort-models/out` (parte 7.3). Sin él, el test se salta por entorno.
func tabKitDevelopmentModel(_ folder: String) throws -> URL {
    let root = ProcessInfo.processInfo.environment["TF_MODELS_DIR"] ?? "C:\\tf-models"
    let url = URL(fileURLWithPath: root, isDirectory: true)
        .appendingPathComponent(folder, isDirectory: true).appendingPathComponent("model.onnx")
    guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("no está el modelo en \(url.path)") }
    return url
}
