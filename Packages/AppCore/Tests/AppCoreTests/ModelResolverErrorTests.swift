import Foundation
import ModelKit
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AppCore

/// Mejora 1 (Fase 7c): el error de `ModelResolver.resolve` nombra el modelo y dice qué pasó.
final class ModelResolverErrorTests: XCTestCase {
    private struct Failing: ModelDownloading {
        let error: Error
        func download(from: URL, to: URL, progress: @escaping @Sendable (Double) -> Void) async throws { throw error }
    }

    private func resolver(failing error: Error) -> ModelResolver {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("resolver-err-\(UUID().uuidString)", isDirectory: true)
        let store = ModelStore(root: root, downloader: Failing(error: error), format: .onnx)
        return ModelResolver(store: store, environment: [:])
    }

    func testHTTP404NamesTheModel() async {
        let r = resolver(failing: ModelDownloadError.httpStatus(404))
        for d in [ModelCatalog.beatsBeatThis, ModelCatalog.chordsBTC, ModelCatalog.drumsADTOF] {
            do {
                _ = try await r.resolve(d.id) { _ in }
                XCTFail("debía fallar")
            } catch {
                XCTAssertEqual(error.localizedDescription, "No se pudo descargar el modelo «\(d.displayName)» (HTTP 404).")
            }
        }
        do {
            _ = try await r.resolve(ModelCatalog.beatsBeatThis.id) { _ in }
        } catch {
            XCTAssertEqual(error.localizedDescription, "No se pudo descargar el modelo «Pulso y compás» (HTTP 404).")
        }
    }

    func testOfflineSaysNoConnection() async {
        let r = resolver(failing: URLError(.notConnectedToInternet))
        do {
            _ = try await r.resolve(ModelCatalog.chordsBTC.id) { _ in }
            XCTFail("debía fallar")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Falta el modelo «Acordes» y no hay conexión.")
        }
    }

    func testOtherErrorKeepsDetail() async {
        struct Boom: LocalizedError { var errorDescription: String? { "disco lleno" } }
        let r = resolver(failing: Boom())
        do {
            _ = try await r.resolve(ModelCatalog.separatorBSRoformerSW.id) { _ in }
            XCTFail("debía fallar")
        } catch {
            XCTAssertEqual(error.localizedDescription,
                           "No se pudo preparar el modelo «\(ModelCatalog.separatorBSRoformerSW.displayName)»: disco lleno")
        }
    }
}
