import Foundation
import ModelKit
import StemKit
import Store
import XCTest
@testable import AppCore

/// B1 (ADR-020): separador de guitarras en las dos plataformas, sin el modelo real. El modelo real se prueba en
/// `StemKit/LeadSeparatorHeavyTests` (Core ML en el Mac, ONNX Runtime en Windows, `TF_MODEL_TESTS=1`).
final class GuitarSplitterTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-guitars-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Descarga que falla como la release `models-win-v1` sin publicar.
    private struct NotPublished: ModelDownloading {
        func download(from: URL, to: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
            throw ModelDownloadError.httpStatus(404)
        }
    }

    private struct HalfLead: LeadGuitarSeparating {
        func separateLead(left: [Float], right: [Float], sampleRate: Double) throws -> (left: [Float], right: [Float]) {
            (left.map { $0 * 0.5 }, right.map { $0 * 0.5 })
        }
    }

    /// `.onnx` falso: contenido fijo y su SHA-256 (`printf 'modelo falso' | shasum -a 256`).
    private static let fakeModel = Data("modelo falso".utf8)
    private static let fakeModelSHA256 = "0df6f1f00cbb01da9115d81efa1b0a179b26511498af89f6f938505592201753"

    /// Catálogo con solo el modelo de solista (mismo id que el real) y el `.onnx` falso.
    private func fakeLeadCatalog() -> [ModelDescriptor] {
        let real = ModelCatalog.leadRhythmMelRoformer
        return [ModelDescriptor(id: real.id, version: real.version, displayName: real.displayName, role: real.role,
                                url: real.url, sha256: real.sha256, archiveBytes: real.archiveBytes,
                                archiveKind: real.archiveKind, packageName: real.packageName, license: real.license,
                                onnxFiles: [OnnxModelFile(fileName: "lead_rhythm.onnx", sha256: Self.fakeModelSHA256,
                                                          bytes: Int64(Self.fakeModel.count))])]
    }

    /// WAV PCM16 estéreo de `seconds` s a 44,1 kHz: L = 0,25, R = −0,5.
    private func stereoWAV(seconds: Double) throws -> URL {
        let rate = 44_100, frames = Int(seconds * Double(rate))
        func le<T: FixedWidthInteger>(_ v: T) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        var d = Data("RIFF".utf8)
        d.append(contentsOf: le(UInt32(36 + frames * 4))); d.append(Data("WAVEfmt ".utf8))
        d.append(contentsOf: le(UInt32(16)) + le(UInt16(1)) + le(UInt16(2)) + le(UInt32(rate)) + le(UInt32(rate * 4))
                 + le(UInt16(4)) + le(UInt16(16)))
        d.append(Data("data".utf8)); d.append(contentsOf: le(UInt32(frames * 4)))
        let l = le(Int16(8192)), r = le(Int16(-16384))
        for _ in 0..<frames { d.append(contentsOf: l + r) }
        let url = dir.appendingPathComponent("guitar.wav")
        try d.write(to: url)
        return url
    }

    /// `production` cablea el separador de guitarras en todas las plataformas (antes `nil` fuera del Mac).
    func testProductionWiresGuitarSplitter() {
        let s = JobServices.production(supportDir: dir, environment: [:])
        XCTAssertNotNil(s.guitarSplitter)
        XCTAssertTrue(s.guitarSplitter is PortableGuitarSplitter)
    }

    /// Carpeta de desarrollo y fichero `.onnx` del modelo de solista (Windows).
    func testLeadModelDevelopmentFolderAndOnnxFile() throws {
        let id = ModelCatalog.leadRhythmMelRoformer.id
        XCTAssertEqual(ModelResolver.developmentFolders(for: id, physicalMemory: 8 << 30), ["lead_rhythm"])
        XCTAssertEqual(ModelResolver.developmentFolders(for: ModelCatalog.separatorBSRoformerSW.id, physicalMemory: 8 << 30),
                       ["bs_roformer"])
        XCTAssertEqual(ModelResolver.developmentFolders(for: "desconocido", physicalMemory: 8 << 30), [])
        let onnx = try XCTUnwrap(ModelCatalog.leadRhythmMelRoformer.onnxFile(physicalMemory: 4 << 30))
        XCTAssertEqual(onnx.fileName, "lead_rhythm.onnx")
        XCTAssertEqual(onnx.bytes, 338_871_118)
        XCTAssertEqual(onnx.sha256, "8a42c4ecf266a8a1cf20641a2cd1756a8b863665877c420bf453dbf425ead51d")

        let folder = dir.appendingPathComponent("lead_rhythm", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appendingPathComponent("model.onnx"))
        let found = ModelResolver.developmentModel(folder: "lead_rhythm", environment: ["TF_MODELS_DIR": dir.path])
        XCTAssertEqual(found?.lastPathComponent, "model.onnx")
        XCTAssertEqual(found?.deletingLastPathComponent().lastPathComponent, "lead_rhythm")
    }

    /// `ModelStore(format: .onnx)`: el separador recibe `<Models>/<id>/lead_rhythm.onnx` instalado por el store.
    func testOnnxStoreResolvesInstalledLeadModel() async throws {
        let source = dir.appendingPathComponent("lead_rhythm.onnx")
        try Self.fakeModel.write(to: source)
        let catalog = fakeLeadCatalog()
        let root = dir.appendingPathComponent("Models", isDirectory: true)
        let store = ModelStore(root: root, catalog: catalog, downloader: NotPublished(), format: .onnx)
        let resolver = ModelResolver(store: store, environment: [:])
        let id = ModelCatalog.leadRhythmMelRoformer.id
        let notYet = await resolver.isInstalled(id)
        XCTAssertFalse(notYet)
        _ = try await store.install(id, fromArchive: source)
        let installed = await resolver.isInstalled(id)
        XCTAssertTrue(installed)
        let url = try await resolver.resolve(id) { _ in }
        XCTAssertEqual(url.lastPathComponent, "lead_rhythm.onnx")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, id)
        XCTAssertEqual(url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path,
                       root.standardizedFileURL.path)
        let sep = try await PortableGuitarSplitter.makeLeadSeparator(models: resolver)
        XCTAssertTrue(sep is RoformerLeadSeparator)
    }

    /// Sin modelo y con tramos de solo: error visible (igual que el Mac sin modelo), nunca pistas a medias.
    func testMissingLeadModelFailsLoudly() async throws {
        let input = try stereoWAV(seconds: 1)
        let out = dir.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let store = ModelStore(root: dir.appendingPathComponent("Models", isDirectory: true), downloader: NotPublished(),
                               format: .onnx)
        let splitter = PortableGuitarSplitter(models: ModelResolver(store: store, environment: [:]))
        let options = GuitarOptions(stereoSplit: false, soloSpans: [Store.GuitarSoloSpan(start: 0.2, end: 0.6)])
        do {
            _ = try await splitter.split(projectFolder: dir, input: input, outputDirectory: out, options: options) { _ in }
            XCTFail("sin modelo debe fallar")
        } catch let e as PortableGuitarSplitter.LeadModelUnavailable {
            XCTAssertTrue(e.localizedDescription.hasPrefix("Modelo de solista no disponible"), e.localizedDescription)
            XCTAssertTrue(e.localizedDescription.contains("404"), e.localizedDescription)
        }
        let left = try FileManager.default.contentsOfDirectory(atPath: out.path).filter { !$0.hasPrefix(".") }
        XCTAssertEqual(left, [])
    }

    /// L/R sin tramos no necesita modelo; con tramos y separador inyectado salen L, R y solista.
    func testStereoAndLeadTracks() async throws {
        let input = try stereoWAV(seconds: 2)
        let out = dir.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let store = ModelStore(root: dir.appendingPathComponent("Models", isDirectory: true), downloader: NotPublished(),
                               format: .onnx)
        let resolver = ModelResolver(store: store, environment: [:])

        let stereoOnly = try await PortableGuitarSplitter(models: resolver)
            .split(projectFolder: dir, input: input, outputDirectory: out, options: GuitarOptions(stereoSplit: true)) { _ in }
        XCTAssertEqual(stereoOnly.tracks.map(\.role), [.left, .right])

        let withLead = try await PortableGuitarSplitter(models: resolver, separatorFactory: { HalfLead() })
            .split(projectFolder: dir, input: input, outputDirectory: out,
                   options: GuitarOptions(stereoSplit: true, soloSpans: [Store.GuitarSoloSpan(start: 0.5, end: 1.5)])) { _ in }
        XCTAssertEqual(withLead.tracks.map(\.role), [.left, .right, .lead])
        for t in withLead.tracks {
            XCTAssertTrue(FileManager.default.fileExists(atPath: out.appendingPathComponent(t.file).path), t.file)
        }
    }
}
