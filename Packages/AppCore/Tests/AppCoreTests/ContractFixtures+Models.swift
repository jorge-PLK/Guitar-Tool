import Foundation
import ModelKit
import Store
import XCTest
@testable import AppCore

/// Descarga simulada: avisa 0.25, espera la señal y escribe bytes que no son el archivo del catálogo (acaba en `failed`).
private final class FixtureModelDownloader: ModelDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var gate: CheckedContinuation<Void, Never>?
    private var opened = false
    func open() { lock.withLock { opened = true; gate?.resume(); gate = nil } }
    func download(from: URL, to: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0.25)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if opened { lock.unlock(); c.resume() } else { gate = c; lock.unlock() }
        }
        try Data("no es el modelo".utf8).write(to: to)
    }
}

private final class FixtureModelEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [[String: Any]] = []
    func add(_ s: String) {
        if let o = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] { lock.withLock { all.append(o) } }
    }
    func named(_ n: String) -> [[String: Any]] { lock.withLock { all }.filter { $0["event"] as? String == n } }
}

final class ContractFixturesModelsTests: XCTestCase {
    func testModelsArea() async throws {
        let rig = try FixtureRig(area: "models")
        defer { rig.cleanup() }
        let support = rig.dir.appendingPathComponent("Support", isDirectory: true)
        let options = LaunchOptions(projectsFolder: rig.projects, supportDir: support)
        let jobs = JobEngine.make(options: options, root: ProjectsRoot(rig.projects),
                                  services: JobServices(importer: FixtureImporter(), separator: FixtureSeparator(gate: FixtureGate()),
                                                        levelMeter: nil, analyzer: nil, guitarSplitter: nil))
        let downloader = FixtureModelDownloader()
        let service = SettingsService(profile: ProfileStore(url: support.appendingPathComponent("profile.json")), jobs: jobs,
                                      activeFolder: jobs.root, modelsRoot: support.appendingPathComponent("Models"),
                                      cameras: SimulatedSettingsCameras(cameras: []), downloader: downloader)
        let events = FixtureModelEvents()
        service.setSink { events.add($0) }
        let router = Router()
        service.register(on: router)

        func call(_ method: String, _ params: String = "{}", name: String? = nil) async throws {
            let n = name ?? method
            try rig.golden(n, .params, params)
            let r = await router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
            let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
            if let e = o["error"] { try rig.golden(n, .error, try FixtureRig.text(e)) }
            else { try rig.golden(n, .result, try FixtureRig.text(try XCTUnwrap(o["result"]))) }
        }
        func waitEvent(_ name: String, where ok: ([String: Any]) -> Bool = { _ in true }) async throws -> [String: Any] {
            for _ in 0..<500 {
                if let e = events.named(name).last(where: { ($0["payload"] as? [String: Any]).map(ok) ?? false }) {
                    return try XCTUnwrap(e["payload"] as? [String: Any])
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTFail("sin evento \(name)")
            return [:]
        }

        // notInstalled
        try await call("models.list", name: "models.list")
        try await call("models.delete", "{\"id\":\"otro\"}")

        // downloading (fraction 0.25 fijada por el doble), busy al borrar, luego failed.
        try await call("models.download")
        let progress = try await waitEvent("models.progress") { ($0["fraction"] as? Double) == 0.25 }
        try rig.golden("models.progress", .event, try FixtureRig.text(progress))
        try await call("models.list", name: "models.list.downloading")
        try await call("models.delete", name: "models.delete.busy")
        downloader.open()
        let changed = try await waitEvent("models.changed")
        try rig.golden("models.changed", .event, try FixtureRig.text(changed))
        try await call("models.list", name: "models.list.failed")
    }

    /// Modelo ya instalado en disco (manifest + paquete compilado con tamaño fijo en el manifest): `installed` con `bytes`,
    /// y `models.download` sobre él cierra enseguida con `models.changed` sin `error`.
    func testModelsInstalled() async throws {
        let rig = try FixtureRig(area: "models")
        defer { rig.cleanup() }
        let support = rig.dir.appendingPathComponent("Support", isDirectory: true)
        let d = ModelCatalog.separatorBSRoformerSW
        let modelDir = support.appendingPathComponent("Models/\(d.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir.appendingPathComponent(d.compiledName, isDirectory: true),
                                                withIntermediateDirectories: true)
        let manifest = "{\"id\":\"\(d.id)\",\"version\":\"\(d.version)\",\"sha256\":\"00\",\"installedAt\":\"2026-01-01T00:00:00Z\",\"bytes\":123456789}"
        try Data(manifest.utf8).write(to: modelDir.appendingPathComponent("manifest.json"))

        let options = LaunchOptions(projectsFolder: rig.projects, supportDir: support)
        let jobs = JobEngine.make(options: options, root: ProjectsRoot(rig.projects),
                                  services: JobServices(importer: FixtureImporter(), separator: FixtureSeparator(gate: FixtureGate()),
                                                        levelMeter: nil, analyzer: nil, guitarSplitter: nil))
        let service = SettingsService(profile: ProfileStore(url: support.appendingPathComponent("profile.json")), jobs: jobs,
                                      activeFolder: jobs.root, modelsRoot: support.appendingPathComponent("Models"),
                                      cameras: SimulatedSettingsCameras(cameras: []), downloader: FixtureModelDownloader())
        let events = FixtureModelEvents()
        service.setSink { events.add($0) }
        let router = Router()
        service.register(on: router)

        try rig.golden("models.list.installed", .params, "{}")
        let r = await router.handle("{\"id\":1,\"method\":\"models.list\",\"params\":{}}")
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
        try rig.golden("models.list.installed", .result, try FixtureRig.text(try XCTUnwrap(o["result"])))

        _ = await router.handle("{\"id\":2,\"method\":\"models.download\",\"params\":{}}")
        var changed: [String: Any]?
        for _ in 0..<500 where changed == nil {
            changed = events.named("models.changed").last?["payload"] as? [String: Any]
            if changed == nil { try await Task.sleep(for: .milliseconds(10)) }
        }
        let payload = try XCTUnwrap(changed, "sin evento models.changed")
        XCTAssertTrue(payload["error"] is NSNull, "\(payload)")
        try rig.golden("models.changed.ok", .event, try FixtureRig.text(payload))
    }
}
