import Foundation
#if canImport(CoreML)
import CoreML

/// Compila con `MLModel.compileModel(at:)`. No elige `computeUnits` (eso es cosa de StemKit).
public struct CoreMLCompiler: ModelCompiling {
    public init() {}
    public func compile(_ mlpackage: URL) async throws -> URL {
        try await MLModel.compileModel(at: mlpackage)
    }
}
#else
import NativePlatform

/// Sin Core ML (Windows): los modelos son `.onnx` y no se compilan; `ModelStore` (formato `.onnx`) no llama al
/// compilador (parte 7.8). Si alguien lo llama con un `.mlpackage`, es un error de uso.
public struct CoreMLCompiler: ModelCompiling {
    public init() {}
    public func compile(_ mlpackage: URL) async throws -> URL {
        throw PlatformError.unsupported("Core ML no existe en Windows: los modelos son .onnx y no se compilan")
    }
}
#endif
