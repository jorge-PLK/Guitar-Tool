#if canImport(CoreML)
import CoreML
#endif
import XCTest
@testable import ModelKit

private struct CompilerMustNotRun: ModelCompiling {
    func compile(_ mlpackage: URL) async throws -> URL {
        XCTFail("No debe compilarse un .mlmodelc ya compilado")
        throw ModelError.unzipFailed("compilador llamado")
    }
}

private final class NSLock_Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.withLock { n } }
    func increment() { lock.withLock { n += 1 } }
}

private final class CountingCompiler: ModelCompiling, @unchecked Sendable {
    private let n = NSLock_Counter()
    var calls: Int { n.value }
    func compile(_ mlpackage: URL) async throws -> URL {
        n.increment()
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("mock-\(UUID().uuidString).mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: out.appendingPathComponent("weights.bin"))
        return out
    }
}

private struct NoDownloads: ModelDownloading {
    func download(from: URL, to: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        XCTFail("No debe descargarse")
    }
}

#if os(Windows)
/// Windows (parte 7.8): la release `models-win-v1` no está publicada, así que los tests con modelo real no
/// descargan: instalan `<TF_MODELS_DIR>\<carpeta>\model.onnx` (los `.onnx` de desarrollo de la parte 7.3) con
/// `install(_:fromArchive:)`, que verifica el SHA-256 del catálogo. Sin la variable, el test se salta.
func localOnnxModel(_ folder: String) throws -> URL {
    guard let dir = ProcessInfo.processInfo.environment["TF_MODELS_DIR"], !dir.isEmpty else {
        throw XCTSkip("[windows] sin TF_MODELS_DIR: models-win-v1 no está publicada y no hay .onnx local")
    }
    let url = URL(fileURLWithPath: dir).appendingPathComponent(folder).appendingPathComponent("model.onnx")
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw ModelError.packageNotFound("no está \(url.path)")
    }
    return url
}
#endif

final class ModelOriginsTests: XCTestCase {
    var tmp: URL!
    var root: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("modelkit-origins-\(UUID().uuidString)", isDirectory: true)
        root = tmp.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    /// Crea un zip con una carpeta falsa (`.mlmodelc` o `.mlpackage`) dentro de `dir`.
    private func makeZip(folder: String, in dir: URL, zipName: String) throws -> URL {
        let src = tmp.appendingPathComponent("src-\(UUID().uuidString)/\(folder)", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: src.appendingPathComponent("Manifest.json"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let zip = dir.appendingPathComponent(zipName)
        try makeTestZip(folder: src, zip: zip)
        return zip
    }

    func testCatalogHasSixUniqueEntries() {
        let ids = ModelCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, 6)
        XCTAssertEqual(Set(ids).count, 6)
        XCTAssertEqual(Set(ModelCatalog.all.map(\.role)),
                       [.separation, .chords, .beats, .guitarTranscription, .leadGuitarSeparation, .drumTranscription])
        let dr = ModelCatalog.drumsADTOF
        XCTAssertEqual(dr.archiveKind, .bundledZippedMLPackage)
        XCTAssertEqual(dr.url.lastPathComponent, "ADTOF_FrameRNN_fp32.mlpackage.zip")
        XCTAssertEqual(dr.compiledName, "ADTOF_FrameRNN_fp32.mlmodelc")
        XCTAssertTrue(dr.license.contains("CC BY-NC-SA") && dr.license.contains("uso personal"))
        let lr = ModelCatalog.leadRhythmMelRoformer
        XCTAssertEqual(lr.archiveKind, .bundledZippedMLPackage)
        XCTAssertEqual(lr.url.lastPathComponent, "LeadRhythmMelRoformer_fp16.mlpackage.zip")
        XCTAssertEqual(lr.compiledName, "LeadRhythmMelRoformer_fp16.mlmodelc")
        XCTAssertTrue(lr.license.contains("openrail") && lr.license.contains("uso personal"))
        XCTAssertEqual(ModelCatalog.leadRhythmCheckpointSHA256.count, 64)
        let bp = ModelCatalog.transcriptionBasicPitch
        XCTAssertEqual(bp.archiveKind, .bundledZippedMLPackage)
        XCTAssertEqual(bp.url.lastPathComponent, "BasicPitch_nmp.mlpackage.zip")
        XCTAssertEqual(bp.compiledName, "BasicPitch_nmp.mlmodelc")
        XCTAssertEqual(ModelCatalog.beatsBeatThis.archiveKind, .zippedCompiledModel)
        XCTAssertEqual(ModelCatalog.beatsBeatThis.compiledName, "BeatThis.mlmodelc")
        XCTAssertEqual(ModelCatalog.chordsBTC.archiveKind, .bundledZippedMLPackage)
        XCTAssertEqual(ModelCatalog.chordsBTC.url.lastPathComponent, "BTC_large_voca_fp16.mlpackage.zip")
    }

    /// `App/Resources/Models` del repo (los zips embebidos).
    private var appModelsDirectory: URL {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.lastPathComponent != "Packages" { dir.deleteLastPathComponent() }
        return dir.deletingLastPathComponent().appendingPathComponent("App/Resources/Models", isDirectory: true)
    }

    /// Cada modelo embebido del catálogo existe en `App/Resources/Models` con su SHA-256 y su tamaño.
    func testBundledResourcesMatchCatalog() throws {
        #if os(Windows)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: appModelsDirectory.path), "[windows] App/Resources/Models no se sincroniza a la VM")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: appModelsDirectory.appendingPathComponent(ModelCatalog.leadRhythmMelRoformer.url.lastPathComponent).path), "[windows] los zips de App/Resources/Models no se sincronizan a la VM")
        #endif
        let bundled = ModelCatalog.all.filter { $0.archiveKind == .bundledZippedMLPackage }
        XCTAssertEqual(Set(bundled.map(\.id)), ["btc-chords", "basic-pitch", "lead-rhythm-guitar", "adtof-drums"])
        for d in bundled {
            let zip = appModelsDirectory.appendingPathComponent(d.url.lastPathComponent)
            let size = try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? Int64
            XCTAssertEqual(size, d.archiveBytes, d.id)
            XCTAssertEqual(try sha256Hex(of: zip), d.sha256, d.id)
        }
    }

    /// Pesado: copia, verifica y compila de verdad el zip embebido de Basic Pitch. Solo con TF_MODEL_TESTS=1.
    func testRealBasicPitchBundledInstall() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1", "TF_MODEL_TESTS=1 requerido")
        let d = ModelCatalog.transcriptionBasicPitch
        #if os(Windows)
        let s = ModelStore(root: root, catalog: [d])
        let url = try await s.install(d.id, fromArchive: try localOnnxModel("basic_pitch"))
        XCTAssertEqual(url.lastPathComponent, "basic_pitch.onnx")
        #else
        let s = ModelStore(root: root, catalog: [d], bundleResourceDirectory: appModelsDirectory)
        let url = try await s.ensureInstalled(d.id) { _ in }
        XCTAssertEqual(url.lastPathComponent, "BasicPitch_nmp.mlmodelc")
        #endif
        guard case .installed = await s.state(d.id) else { return XCTFail("estado") }
    }

    /// Pesado: copia, verifica y compila de verdad el zip embebido del modelo de solista y comprueba el contrato
    /// de entrada y salida. Solo con TF_MODEL_TESTS=1.
    #if canImport(CoreML)
    func testRealLeadRhythmBundledInstall() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1", "TF_MODEL_TESTS=1 requerido")
        let d = ModelCatalog.leadRhythmMelRoformer
        let s = ModelStore(root: root, catalog: [d], bundleResourceDirectory: appModelsDirectory)
        let url = try await s.ensureInstalled(d.id) { _ in }
        XCTAssertEqual(url.lastPathComponent, "LeadRhythmMelRoformer_fp16.mlmodelc")
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        let model = try MLModel(contentsOf: url, configuration: config)
        let desc = model.modelDescription
        XCTAssertEqual(desc.inputDescriptionsByName["spec"]?.multiArrayConstraint?.shape, [1, 2050, 301, 2])
        XCTAssertEqual(desc.inputDescriptionsByName["spec"]?.multiArrayConstraint?.dataType, .float32)
        XCTAssertEqual(desc.outputDescriptionsByName["mask"]?.multiArrayConstraint?.shape, [1, 1, 2050, 301, 2])
    }

    /// Pesado: copia, verifica y compila de verdad el zip embebido de ADTOF y lo ejecuta en `.cpuOnly` con T = 100
    /// tramas (longitud flexible). Solo con TF_MODEL_TESTS=1.
    func testRealADTOFBundledInstall() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1", "TF_MODEL_TESTS=1 requerido")
        let d = ModelCatalog.drumsADTOF
        let s = ModelStore(root: root, catalog: [d], bundleResourceDirectory: appModelsDirectory)
        let url = try await s.ensureInstalled(d.id) { _ in }
        XCTAssertEqual(url.lastPathComponent, "ADTOF_FrameRNN_fp32.mlmodelc")
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: url, configuration: config)
        XCTAssertEqual(model.modelDescription.inputDescriptionsByName["spec"]?.multiArrayConstraint?.dataType, .float32)
        let spec = try MLMultiArray(shape: [1, 100, 84, 1], dataType: .float32)
        for i in 0..<spec.count { spec[i] = 0 }
        let out = try await model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["spec": spec]))
        XCTAssertEqual(out.featureValue(for: "act")?.multiArrayValue?.shape, [1, 100, 5])
    }

    #elseif os(Windows)
    /// Windows: instala el `.onnx` local del modelo de solista con el descriptor del catálogo (SHA-256 y tamaño).
    func testRealLeadRhythmBundledInstall() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1", "TF_MODEL_TESTS=1 requerido")
        let d = ModelCatalog.leadRhythmMelRoformer
        let s = ModelStore(root: root, catalog: [d])
        let url = try await s.install(d.id, fromArchive: try localOnnxModel("lead_rhythm"))
        XCTAssertEqual(url.lastPathComponent, "lead_rhythm.onnx")
        guard case .installed(_, let bytes) = await s.state(d.id) else { return XCTFail("estado") }
        XCTAssertEqual(bytes, d.onnxFiles.first?.bytes)
    }

    /// Windows: instala el `.onnx` local de ADTOF con el descriptor del catálogo (SHA-256 y tamaño).
    func testRealADTOFBundledInstall() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1", "TF_MODEL_TESTS=1 requerido")
        let d = ModelCatalog.drumsADTOF
        let s = ModelStore(root: root, catalog: [d])
        let url = try await s.install(d.id, fromArchive: try localOnnxModel("adtof"))
        XCTAssertEqual(url.lastPathComponent, "adtof.onnx")
        guard case .installed(_, let bytes) = await s.state(d.id) else { return XCTFail("estado") }
        XCTAssertEqual(bytes, d.onnxFiles.first?.bytes)
    }
    #endif

    func testCompiledZipInstallsWithoutCompiling() async throws {
        let zip = try makeZip(folder: "Fake.mlmodelc", in: tmp.appendingPathComponent("dl"), zipName: "Fake.mlmodelc.zip")
        let d = ModelDescriptor(id: "beats", version: "v1", displayName: "B", role: .beats,
                                url: URL(string: "https://example.invalid/Fake.mlmodelc.zip")!,
                                sha256: try sha256Hex(of: zip), archiveBytes: 1,
                                archiveKind: .zippedCompiledModel, packageName: "Fake.mlmodelc", license: "test")
        let s = ModelStore(root: root, catalog: [d], downloader: NoDownloads(), compiler: CompilerMustNotRun(), format: .coreML)
        let url = try await s.install("beats", fromArchive: zip)
        XCTAssertEqual(url.lastPathComponent, "Fake.mlmodelc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathComponent("Manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("beats/manifest.json").path))
        let st = await s.state("beats")
        guard case .installed(let u, _) = st else { return XCTFail("estado \(st)") }
        XCTAssertEqual(u, url)
    }

    func testBundledZipIsCopiedVerifiedAndCompiled() async throws {
        let res = tmp.appendingPathComponent("resources", isDirectory: true)
        let zip = try makeZip(folder: "Fake.mlpackage", in: res, zipName: "Fake.mlpackage.zip")
        let d = ModelDescriptor(id: "chords", version: "v1", displayName: "C", role: .chords,
                                url: URL(string: "bundle:///Fake.mlpackage.zip")!,
                                sha256: try sha256Hex(of: zip), archiveBytes: 1,
                                archiveKind: .bundledZippedMLPackage, packageName: "Fake.mlpackage", license: "test")
        let compiler = CountingCompiler()
        let s = ModelStore(root: root, catalog: [d], downloader: NoDownloads(), compiler: compiler,
                           bundleResourceDirectory: res, format: .coreML)
        let url = try await s.ensureInstalled("chords") { _ in }
        XCTAssertEqual(compiler.calls, 1)
        XCTAssertEqual(url.lastPathComponent, "Fake.mlmodelc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path), "el recurso del bundle no se toca")
        // Segunda llamada: ya instalado, sin recompilar.
        _ = try await s.ensureInstalled("chords") { _ in }
        XCTAssertEqual(compiler.calls, 1)
    }

    func testBundledZipWithWrongSHAFails() async throws {
        let res = tmp.appendingPathComponent("resources", isDirectory: true)
        _ = try makeZip(folder: "Fake.mlpackage", in: res, zipName: "Fake.mlpackage.zip")
        let d = ModelDescriptor(id: "chords", version: "v1", displayName: "C", role: .chords,
                                url: URL(string: "bundle:///Fake.mlpackage.zip")!,
                                sha256: String(repeating: "0", count: 64), archiveBytes: 1,
                                archiveKind: .bundledZippedMLPackage, packageName: "Fake.mlpackage", license: "test")
        let compiler = CountingCompiler()
        let s = ModelStore(root: root, catalog: [d], downloader: NoDownloads(), compiler: compiler,
                           bundleResourceDirectory: res, format: .coreML)
        do {
            _ = try await s.ensureInstalled("chords") { _ in }
            XCTFail("debía fallar")
        } catch let e as ModelError {
            guard case .hashMismatch = e else { return XCTFail("error \(e)") }
        }
        XCTAssertEqual(compiler.calls, 0)
        let st = await s.state("chords")
        guard case .failed = st else { return XCTFail("estado \(st)") }
    }

    func testBundledZipMissingResource() async throws {
        let d = ModelCatalog.chordsBTC
        let s = ModelStore(root: root, catalog: [d], downloader: NoDownloads(), compiler: CountingCompiler(),
                           bundleResourceDirectory: tmp.appendingPathComponent("empty", isDirectory: true),
                           format: .coreML)
        do {
            _ = try await s.ensureInstalled(d.id) { _ in }
            XCTFail("debía fallar")
        } catch let e as ModelError {
            XCTAssertEqual(e, .bundledResourceMissing("BTC_large_voca_fp16.mlpackage.zip"))
        }
    }
}
