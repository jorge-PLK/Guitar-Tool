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
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--keepParent", src.path, zip.path]
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        return zip
    }

    func testCatalogHasThreeUniqueEntries() {
        let ids = ModelCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(Set(ids).count, 3)
        XCTAssertEqual(Set(ModelCatalog.all.map(\.role)), [.separation, .chords, .beats])
        XCTAssertEqual(ModelCatalog.beatsBeatThis.archiveKind, .zippedCompiledModel)
        XCTAssertEqual(ModelCatalog.beatsBeatThis.compiledName, "BeatThis.mlmodelc")
        XCTAssertEqual(ModelCatalog.chordsBTC.archiveKind, .bundledZippedMLPackage)
        XCTAssertEqual(ModelCatalog.chordsBTC.url.lastPathComponent, "BTC_large_voca_fp16.mlpackage.zip")
    }

    func testCompiledZipInstallsWithoutCompiling() async throws {
        let zip = try makeZip(folder: "Fake.mlmodelc", in: tmp.appendingPathComponent("dl"), zipName: "Fake.mlmodelc.zip")
        let d = ModelDescriptor(id: "beats", version: "v1", displayName: "B", role: .beats,
                                url: URL(string: "https://example.invalid/Fake.mlmodelc.zip")!,
                                sha256: try sha256Hex(of: zip), archiveBytes: 1,
                                archiveKind: .zippedCompiledModel, packageName: "Fake.mlmodelc", license: "test")
        let s = ModelStore(root: root, catalog: [d], downloader: NoDownloads(), compiler: CompilerMustNotRun())
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
                           bundleResourceDirectory: res)
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
                           bundleResourceDirectory: res)
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
                           bundleResourceDirectory: tmp.appendingPathComponent("empty", isDirectory: true))
        do {
            _ = try await s.ensureInstalled(d.id) { _ in }
            XCTFail("debía fallar")
        } catch let e as ModelError {
            XCTAssertEqual(e, .bundledResourceMissing("BTC_large_voca_fp16.mlpackage.zip"))
        }
    }
}
