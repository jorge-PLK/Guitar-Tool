import XCTest
import CryptoKit
@testable import ModelKit

private struct Boom: Error, LocalizedError { var errorDescription: String? { "boom" } }

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ v: T) { value = v }
    func mutate(_ f: (inout T) -> Void) { lock.lock(); f(&value); lock.unlock() }
    var get: T { lock.lock(); defer { lock.unlock() }; return value }
}

private final class MockDownloader: ModelDownloading {
    let zip: URL
    let fail: Bool
    let delay: UInt64
    let calls = Box(0)
    init(zip: URL, fail: Bool = false, delay: UInt64 = 0) { self.zip = zip; self.fail = fail; self.delay = delay }
    func download(from: URL, to: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        calls.mutate { $0 += 1 }
        progress(0.25)
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        if fail { throw Boom() }
        progress(0.5)
        try FileManager.default.copyItem(at: zip, to: to)
        progress(1)
    }
}

private struct MockCompiler: ModelCompiling {
    let fail: Bool
    func compile(_ mlpackage: URL) async throws -> URL {
        if fail { throw Boom() }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("mock-\(UUID().uuidString).mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 1000).write(to: out.appendingPathComponent("weights.bin"))
        return out
    }
}

final class ModelStoreTests: XCTestCase {
    var tmp: URL!
    var root: URL!
    var zip: URL!
    var desc: ModelDescriptor!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("modelkit-\(UUID().uuidString)", isDirectory: true)
        root = tmp.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        // .mlpackage falso -> zip con ditto
        let pkg = tmp.appendingPathComponent("src/Fake.mlpackage", isDirectory: true)
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: pkg.appendingPathComponent("Manifest.json"))
        zip = tmp.appendingPathComponent("Fake.mlpackage.zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--keepParent", pkg.path, zip.path]
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        desc = makeDescriptor(version: "v1", sha: try sha256Hex(of: zip))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func makeDescriptor(version: String, sha: String) -> ModelDescriptor {
        ModelDescriptor(id: "fake", version: version, displayName: "Falso", role: .separation,
                        url: URL(string: "https://example.invalid/Fake.zip")!, sha256: sha,
                        archiveBytes: 1, packageName: "Fake.mlpackage", license: "test")
    }

    private func store(_ d: ModelDescriptor? = nil, dl: MockDownloader? = nil, failCompile: Bool = false) -> (ModelStore, MockDownloader) {
        let downloader = dl ?? MockDownloader(zip: zip)
        return (ModelStore(root: root, catalog: [d ?? desc], downloader: downloader,
                           compiler: MockCompiler(fail: failCompile)), downloader)
    }

    private func assertState(_ s: ModelStore, _ e: ModelState, line: UInt = #line) async {
        let v = await s.state("fake")
        XCTAssertEqual(v, e, line: line)
    }

    private func assertUsage(_ s: ModelStore, _ e: Int64, line: UInt = #line) async {
        let v = await s.diskUsage()
        XCTAssertEqual(v, e, line: line)
    }

    private func leftovers() -> [String] {
        let dir = root.appendingPathComponent("fake")
        return (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    }

    func testSuccessfulInstall() async throws {
        let (s, _) = store()
        let updates = await s.updates
        let collector = Task { () -> [ModelState] in
            var out: [ModelState] = []
            for await (_, st) in updates {
                out.append(st)
                if case .installed = st { break }
            }
            return out
        }
        let prog = Box([Double]())
        let url = try await s.ensureInstalled("fake") { p in prog.mutate { $0.append(p) } }
        let seen = await collector.value

        XCTAssertEqual(url.lastPathComponent, "Fake.mlmodelc")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "fake")
        // orden: downloading* -> verifying -> installing -> installed
        var phases: [Int] = []
        for st in seen {
            switch st {
            case .downloading: phases.append(0)
            case .verifying: phases.append(1)
            case .installing: phases.append(2)
            case .installed: phases.append(3)
            default: XCTFail("estado inesperado \(st)")
            }
        }
        XCTAssertEqual(phases, phases.sorted())
        XCTAssertEqual(Set(phases), [0, 1, 2, 3])
        let p = prog.get
        XCTAssertEqual(p, p.sorted())
        XCTAssertEqual(p.last, 1)
        XCTAssertEqual(Set(leftovers()), ["Fake.mlmodelc", "manifest.json"])
        let m = try JSONDecoder.iso.decode(InstalledManifest.self,
                                           from: Data(contentsOf: root.appendingPathComponent("fake/manifest.json")))
        XCTAssertEqual(m.id, "fake"); XCTAssertEqual(m.version, "v1"); XCTAssertEqual(m.sha256, desc.sha256)
        XCTAssertEqual(m.bytes, 1000)
        let st = await s.state("fake")
        XCTAssertEqual(st, .installed(compiledURL: url, bytes: 1000))
    }

    func testHashMismatch() async throws {
        let (s, _) = store(makeDescriptor(version: "v1", sha: String(repeating: "0", count: 64)))
        do {
            _ = try await s.ensureInstalled("fake") { _ in }
            XCTFail("debía fallar")
        } catch let e as ModelError {
            guard case .hashMismatch = e else { return XCTFail("\(e)") }
        }
        guard case .failed = await s.state("fake") else { return XCTFail("estado") }
        XCTAssertTrue(leftovers().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("fake").path))
    }

    func testDownloadFailure() async throws {
        let (s, _) = store(dl: MockDownloader(zip: zip, fail: true))
        do { _ = try await s.ensureInstalled("fake") { _ in }; XCTFail() } catch {}
        await assertState(s, .failed("boom"))
        XCTAssertTrue(leftovers().isEmpty)
    }

    func testCompileFailure() async throws {
        let (s, _) = store(failCompile: true)
        do { _ = try await s.ensureInstalled("fake") { _ in }; XCTFail() } catch {}
        await assertState(s, .failed("boom"))
        XCTAssertTrue(leftovers().isEmpty)
    }

    func testStateSurvivesRestart() async throws {
        let (s, _) = store()
        let url = try await s.ensureInstalled("fake") { _ in }
        let (s2, dl2) = store()
        await assertState(s2, .installed(compiledURL: url, bytes: 1000))
        let again = try await s2.ensureInstalled("fake") { _ in }
        XCTAssertEqual(again, url)
        XCTAssertEqual(dl2.calls.get, 0)
    }

    func testVersionChangeInvalidates() async throws {
        let (s, _) = store()
        _ = try await s.ensureInstalled("fake") { _ in }
        let (s2, _) = store(makeDescriptor(version: "v2", sha: desc.sha256))
        await assertState(s2, .notInstalled)
    }

    func testConcurrentEnsureSharesDownload() async throws {
        let dl = MockDownloader(zip: zip, delay: 200_000_000)
        let (s, _) = store(dl: dl)
        async let a = s.ensureInstalled("fake") { _ in }
        async let b = s.ensureInstalled("fake") { _ in }
        let (ua, ub) = try await (a, b)
        XCTAssertEqual(ua, ub)
        XCTAssertEqual(dl.calls.get, 1)
    }

    func testDeleteAndDiskUsage() async throws {
        let (s, _) = store()
        await assertUsage(s, 0)
        _ = try await s.ensureInstalled("fake") { _ in }
        await assertUsage(s, 1000)
        try await s.delete("fake")
        await assertUsage(s, 0)
        await assertState(s, .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("fake").path))
    }

    func testInstallFromArchiveKeepsSource() async throws {
        let (s, dl) = store()
        let url = try await s.install("fake", fromArchive: zip)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))
        XCTAssertEqual(dl.calls.get, 0)
    }

    func testURLSessionDownloaderFileURL() async throws {
        let dest = tmp.appendingPathComponent("copy.zip")
        let prog = Box([Double]())
        try await URLSessionDownloader().download(from: zip, to: dest) { p in prog.mutate { $0.append(p) } }
        XCTAssertEqual(try Data(contentsOf: dest), try Data(contentsOf: zip))
        XCTAssertEqual(prog.get.last, 1)
        XCTAssertEqual(prog.get, prog.get.sorted())
    }

    /// Pesado: compilación real del modelo de la Fase 0. Solo con TF_MODEL_TESTS=1.
    func testRealSeparatorInstall() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TF_MODEL_TESTS"] == "1", "TF_MODEL_TESTS=1 requerido")
        var dir = URL(fileURLWithPath: #filePath)
        while !FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path)
                || dir.lastPathComponent != "ModelKit" { dir.deleteLastPathComponent() }
        let repo = dir.deletingLastPathComponent().deletingLastPathComponent()
        let archive = repo.appendingPathComponent("Probes/P4-modelos/bs_roformer_sw/out/coreml_pub/BSRoformerSW.mlpackage.zip")
        let heavyRoot = repo.appendingPathComponent("Temp/modelkit-real-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: heavyRoot) }
        let s = ModelStore(root: heavyRoot)
        let t0 = Date()
        let url = try await s.install("bs-roformer-sw", fromArchive: archive)
        let secs = Date().timeIntervalSince(t0)
        let bytes = directorySize(url)
        print("MODELKIT-REAL compile+install: \(String(format: "%.1f", secs)) s, mlmodelc \(bytes) bytes")
        XCTAssertEqual(url.lastPathComponent, "BSRoformerSW.mlmodelc")
        XCTAssertGreaterThan(bytes, 0)
        guard case .installed = await s.state("bs-roformer-sw") else { return XCTFail("estado") }
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
