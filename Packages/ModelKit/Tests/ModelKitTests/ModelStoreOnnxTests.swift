import Foundation
import XCTest
@testable import ModelKit

/// Modelos `.onnx` de Windows (parte 7.8): elección de variante por RAM, instalación sin compilar y, en Windows, el
/// `.onnx` real de `<TF_MODELS_DIR o C:\tf-models>\basic_pitch` frente al SHA-256 del catálogo. El camino ONNX se
/// fuerza con `format: .onnx`, así que corre también en el Mac (donde el formato por defecto sigue siendo Core ML).
final class ModelStoreOnnxTests: XCTestCase {
    private final class CopyDownloader: ModelDownloading, @unchecked Sendable {
        let source: URL
        private let lock = NSLock()
        private var _requested: [URL] = []
        var requested: [URL] { lock.withLock { _requested } }
        init(source: URL) { self.source = source }
        func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
            lock.withLock { _requested.append(url) }
            try FileManager.default.copyItem(at: source, to: destination)
            progress(1)
        }
    }

    private struct NoCompiler: ModelCompiling {
        func compile(_ mlpackage: URL) async throws -> URL { XCTFail("ONNX no se compila"); return mlpackage }
    }

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("modelkit-onnx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testSeparationVariantByPhysicalMemory() {
        let d = ModelCatalog.separatorBSRoformerSW
        XCTAssertEqual(d.onnxFile(physicalMemory: 8 << 30)?.frames, 345, "8 GB: T=345")
        XCTAssertEqual(d.onnxFile(physicalMemory: 12 << 30)?.frames, 345, "12 GB: T=345")
        // T575 desactivado (GLU en Split roto en DirectML): con cualquier RAM sale T345.
        XCTAssertEqual(d.onnxFile(physicalMemory: 16_960_000_000)?.frames, 345, "16 GB: T=345")
        XCTAssertEqual(d.onnxFile(physicalMemory: 32 << 30)?.fileName, "bs_roformer.onnx", "32 GB: T=345")
        XCTAssertEqual(d.onnxFile(physicalMemory: 64 << 30)?.fileName, "bs_roformer.onnx")
        XCTAssertEqual(ModelCatalog.chordsBTC.onnxFile(physicalMemory: 8 << 30)?.fileName, "btc.onnx")
        XCTAssertEqual(ModelCatalog.all.filter { $0.onnxFiles.isEmpty }.map(\.id), [], "los seis modelos tienen .onnx")
    }

    func testDownloadVerifyInstallWithoutCompiling() async throws {
        let dir = try tempDir()
        let payload = dir.appendingPathComponent("payload.onnx")
        try Data((0..<4096).map { UInt8($0 % 251) }).write(to: payload)
        let sha = try sha256Hex(of: payload)
        let d = ModelDescriptor(id: "m", version: "v1", displayName: "M", role: .chords,
                                url: URL(string: "https://example.invalid/m.zip")!, sha256: "x", archiveBytes: 1,
                                packageName: "M.mlpackage", license: "test",
                                onnxFiles: [OnnxModelFile(fileName: "m.onnx", sha256: sha, bytes: 4096)])
        let root = dir.appendingPathComponent("root")
        let downloader = CopyDownloader(source: payload)
        let store = ModelStore(root: root, catalog: [d], downloader: downloader, compiler: NoCompiler(),
                               format: .onnx, physicalMemory: 8 << 30)
        let url = try await store.ensureInstalled("m", progress: { _ in })
        XCTAssertEqual(url.lastPathComponent, "m.onnx")
        XCTAssertEqual(try sha256Hex(of: url), sha)
        XCTAssertEqual(downloader.requested, [ModelCatalog.onnxReleaseBase.appendingPathComponent("m.onnx")])
        guard case .installed(let u, let bytes) = await store.state("m") else { return XCTFail("no instalado") }
        XCTAssertEqual(u, url)
        XCTAssertEqual(bytes, 4096)
        // Otra instancia lo ve instalado sin descargar.
        let again = ModelStore(root: root, catalog: [d], downloader: downloader, compiler: NoCompiler(),
                               format: .onnx, physicalMemory: 8 << 30)
        guard case .installed = await again.state("m") else { return XCTFail("no se recuerda") }
        XCTAssertEqual(downloader.requested.count, 1)
    }

    func testHashMismatchLeavesNothing() async throws {
        let dir = try tempDir()
        let payload = dir.appendingPathComponent("payload.onnx")
        try Data([1, 2, 3]).write(to: payload)
        let d = ModelDescriptor(id: "m", version: "v1", displayName: "M", role: .chords,
                                url: URL(string: "https://example.invalid/m.zip")!, sha256: "x", archiveBytes: 1,
                                packageName: "M.mlpackage", license: "test",
                                onnxFiles: [OnnxModelFile(fileName: "m.onnx", sha256: String(repeating: "0", count: 64), bytes: 3)])
        let root = dir.appendingPathComponent("root")
        let store = ModelStore(root: root, catalog: [d], downloader: CopyDownloader(source: payload), compiler: NoCompiler(),
                               format: .onnx)
        do {
            _ = try await store.install("m", fromArchive: payload)
            XCTFail("debía fallar")
        } catch let e as ModelError {
            guard case .hashMismatch = e else { return XCTFail("\(e)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("m").path))
    }

    /// Windows: el `.onnx` real de la parte 7.3 se instala con el descriptor del catálogo (su SHA-256 cuadra).
    func testRealBasicPitchFromDevelopmentFolder() async throws {
        #if os(Windows)
        let fallback = "C:\\tf-models"
        #else
        // En el Mac, la salida de la parte 7.3 en el repo.
        let fallback = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Probes/P8-windows/ort-models/out").path
        #endif
        let models = ProcessInfo.processInfo.environment["TF_MODELS_DIR"] ?? fallback
        let src = URL(fileURLWithPath: models).appendingPathComponent("basic_pitch").appendingPathComponent("model.onnx")
        guard FileManager.default.fileExists(atPath: src.path) else { throw XCTSkip("no está \(src.path)") }
        let root = try tempDir()
        let store = ModelStore(root: root, catalog: ModelCatalog.all, compiler: NoCompiler(), format: .onnx)
        let url = try await store.install(ModelCatalog.transcriptionBasicPitch.id, fromArchive: src)
        XCTAssertEqual(url.lastPathComponent, "basic_pitch.onnx")
    }
}
