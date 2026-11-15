import CoreML
import Foundation

/// Compila con `MLModel.compileModel(at:)`. No elige `computeUnits` (eso es cosa de StemKit).
public struct CoreMLCompiler: ModelCompiling {
    public init() {}
    public func compile(_ mlpackage: URL) async throws -> URL {
        try await MLModel.compileModel(at: mlpackage)
    }
}
