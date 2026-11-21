import Foundation

/// `.onnx` de desarrollo en Windows (parte 7.8): `<TF_MODELS_DIR o C:\tf-models>\<carpeta>\model.onnx`, la
/// estructura de `Probes/P8-windows/ort-models/out` (parte 7.3). Igual que `OnnxDevelopmentModels` de NativeONNX,
/// que este objetivo de tests no importa.
func studyKitDevelopmentModel(_ folder: String) -> URL {
    let root = ProcessInfo.processInfo.environment["TF_MODELS_DIR"] ?? "C:\\tf-models"
    return URL(fileURLWithPath: root, isDirectory: true)
        .appendingPathComponent(folder, isDirectory: true).appendingPathComponent("model.onnx")
}
