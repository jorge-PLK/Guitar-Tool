import Foundation
import ModelKit
import Store
import XCTest
@testable import AppCore

// W2-A: Ajustes no-audio (biblioteca, modelos, cámara y vídeo). Sin hardware ni red.

private struct SImporter: AudioImporting {
    func importAudio(from source: URL, to destination: URL, sampleRate: Double,
                     progress: @escaping @Sendable (Double) -> Void) async throws -> ImportedAudioInfo {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "wav".write(to: destination, atomically: true, encoding: .utf8)
        return ImportedAudioInfo(title: nil, artist: nil, duration: 10, sourceFormat: "wav", sourceSampleRate: 44100, sourceChannels: 2)
    }
    func resample(_ file: URL, to destination: URL, sampleRate: Double) async throws {
        try "stem".write(to: destination, atomically: true, encoding: .utf8)
    }
}

private struct SSeparator: StemSeparating {
    var modelIdentifier: String? { "fake@1" }
    func separate(input: URL, outputDirectory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for kind in StemKind.allCases {
            try "stem".write(to: outputDirectory.appendingPathComponent("\(kind.rawValue).wav"), atomically: true, encoding: .utf8)
        }
        progress(1)
    }
}

private final class SEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [String] = []
    func add(_ s: String) { lock.withLock { all.append(s) } }
    func named(_ n: String) -> [[String: Any]] {
        lock.withLock { all }.compactMap { m in
            guard let o = (try? JSONSerialization.jsonObject(with: Data(m.utf8))) as? [String: Any],
                  o["event"] as? String == n else { return nil }
            return o["payload"] as? [String: Any]
        }
    }
}

private struct SRig {
    let dir: URL
    let projects: URL
    let support: URL
    let router = Router()
    let service: SettingsService
    let events = SEvents()
    let jobs: JobEngine
    let cameras: SimulatedSettingsCameras

    static let webcam = SettingsCamera(id: "cam-a", name: "Webcam USB", kind: "external", formats: [
        SettingsCameraFormat(width: 640, height: 360, frameRates: [SettingsFrameRange(min: 30, max: 30)]),
        SettingsCameraFormat(width: 1280, height: 720, frameRates: [SettingsFrameRange(min: 24, max: 60)]),
        SettingsCameraFormat(width: 1920, height: 1080, frameRates: [SettingsFrameRange(min: 24, max: 30)])])
    static let phone = SettingsCamera(id: "cam-b", name: "Telefono", kind: "continuity", formats: [
        SettingsCameraFormat(width: 1920, height: 1080, frameRates: [SettingsFrameRange(min: 30, max: 60)]),
        SettingsCameraFormat(width: 3840, height: 2160, frameRates: [SettingsFrameRange(min: 24, max: 30)])])

    init(cameras list: [SettingsCamera] = [SRig.webcam, SRig.phone], environment: [String: String] = [:], downloader: (any ModelDownloading)? = nil) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-settings-\(UUID().uuidString)", isDirectory: true)
        projects = dir.appendingPathComponent("Projects", isDirectory: true)
        support = dir.appendingPathComponent("Support", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let options = LaunchOptions(projectsFolder: projects, supportDir: support)
        let services = JobServices(importer: SImporter(), separator: SSeparator(), levelMeter: nil, analyzer: nil, guitarSplitter: nil)
        jobs = JobEngine.make(options: options, root: ProjectsRoot(projects), services: services)
        cameras = SimulatedSettingsCameras(cameras: list)
        service = SettingsService(profile: ProfileStore(url: support.appendingPathComponent("profile.json")), jobs: jobs,
                                  activeFolder: jobs.root, modelsRoot: support.appendingPathComponent("Models"),
                                  environment: environment, cameras: cameras, downloader: downloader)
        let sink = events
        service.setSink { sink.add($0) }
        service.register(on: router)
    }

    func call(_ method: String, _ params: String = "{}") async -> [String: Any] {
        let r = await router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        return (try? JSONSerialization.jsonObject(with: Data(r.utf8))) as? [String: Any] ?? [:]
    }

    func result(_ method: String, _ params: String = "{}") async -> [String: Any] {
        (await call(method, params))["result"] as? [String: Any] ?? [:]
    }

    func errorCode(_ method: String, _ params: String = "{}") async -> String? {
        ((await call(method, params))["error"] as? [String: Any])?["code"] as? String
    }

    func cleanup() { try? FileManager.default.removeItem(at: dir) }
}

/// Descarga simulada: avisa del progreso, espera la señal y escribe unos bytes que no son el archivo del catálogo.
private final class FakeDownloader: ModelDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    private var gate: CheckedContinuation<Void, Never>?
    private var opened = false
    var calls: Int { lock.withLock { _calls } }
    func open() { lock.withLock { opened = true; gate?.resume(); gate = nil } }
    func download(from: URL, to: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        lock.withLock { _calls += 1 }
        progress(0.25)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if opened { lock.unlock(); c.resume() } else { gate = c; lock.unlock() }
        }
        progress(0.75)
        try Data("no es el modelo".utf8).write(to: to)
    }
}

private func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

final class SettingsTests: XCTestCase {
    // MARK: settings.get y biblioteca

    func testSettingsGetShowsProfileFolderAndVideo() async throws {
        let rig = try SRig()
        defer { rig.cleanup() }
        var p = EquipmentProfile()
        p.projectsFolder = rig.projects
        try ProfileStore(url: rig.support.appendingPathComponent("profile.json")).save(p)
        let r = await rig.result("settings.get")
        XCTAssertEqual(r["projectsFolder"] as? String, rig.projects.path)
        XCTAssertEqual(r["activeProjectsFolder"] as? String, rig.projects.path)
        XCTAssertEqual((r["video"] as? [String: Any])?["fps"] as? Double, 30)
    }

    func testSettingsGetWithoutProfileGivesNulls() async throws {
        let rig = try SRig()
        defer { rig.cleanup() }
        let r = await rig.result("settings.get")
        XCTAssertTrue(r["projectsFolder"] is NSNull)
    }

    func testUsageAndCleanupWholeLibrary() async throws {
        let rig = try SRig()
        defer { rig.cleanup() }
        let empty = await rig.result("library.usage")
        XCTAssertEqual(num(empty["totalBytes"]), 0)
        XCTAssertEqual((empty["projects"] as? [Any])?.count, 0)

        var ids: [String] = []
        for n in ["a", "b"] {
            let url = rig.dir.appendingPathComponent("\(n).wav")
            try n.write(to: url, atomically: true, encoding: .utf8)
            let r = try await rig.jobs.importFile(path: url.path)
            ids.append(r.id)
        }
        // La separación y el análisis van en la cola: esperar a que los stems existan.
        var usage: [String: Any] = [:]
        var previous = -1.0
        for _ in 0..<400 {
            usage = await rig.result("library.usage")
            let now = num(usage["regenerableBytes"]) ?? 0
            // Estable en dos lecturas seguidas con los dos temas ya separados.
            if now > 0, (usage["projects"] as? [Any])?.count == 2, now == previous { break }
            previous = now
            try await Task.sleep(for: .milliseconds(150))
        }
        let regenerable = try XCTUnwrap(num(usage["regenerableBytes"]))
        XCTAssertGreaterThan(regenerable, 0)
        XCTAssertGreaterThan(try XCTUnwrap(num(usage["totalBytes"])), regenerable)
        XCTAssertEqual((usage["projects"] as? [[String: Any]])?.count, 2)

        // Sin id, id nulo y por tema: los tres caminos.
        let all = await rig.result("library.cleanupInfo")
        XCTAssertEqual(num(all["bytes"]), regenerable)
        let allNull = await rig.result("library.cleanupInfo", "{\"id\":null}")
        XCTAssertEqual(num(allNull["bytes"]), regenerable)
        let one = await rig.result("library.cleanupInfo", "{\"id\":\"\(ids[0])\"}")
        XCTAssertLessThan(try XCTUnwrap(num(one["bytes"])), regenerable)

        let done = await rig.result("library.cleanup", "{\"id\":null}")
        XCTAssertEqual(done["cleaned"] as? Bool, true)
        XCTAssertEqual(num(done["bytes"]), regenerable)
        let after = await rig.result("library.cleanupInfo")
        XCTAssertEqual(num(after["bytes"]), 0)
        let again = await rig.result("library.cleanup")
        XCTAssertEqual(num(again["bytes"]), 0)

        let c1 = await rig.errorCode("library.cleanup", "{\"id\":\"x\"}")
        XCTAssertEqual(c1, "bad-params")
        let c2 = await rig.errorCode("library.cleanup", "{\"id\":\"\(UUID().uuidString)\"}")
        XCTAssertEqual(c2, "not-found")
    }

    func testUsageWithoutProjectsFolder() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-settings-nf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let b = try Bridge(options: LaunchOptions(projectsFolder: nil, supportDir: dir), mediaBase: "https://tf.media/")
        let r = await b.router.handle("{\"id\":1,\"method\":\"library.usage\",\"params\":{}}")
        XCTAssertTrue(r.contains("no-projects-folder"), r)
    }

    func testBridgeRegistersSettingsMethods() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-settings-br-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let projects = dir.appendingPathComponent("P")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let b = try Bridge(options: LaunchOptions(projectsFolder: projects, supportDir: dir), mediaBase: "https://tf.media/")
        for m in ["settings.get", "video.cameras", "video.settings", "models.list", "library.usage"] {
            let r = await b.router.handle("{\"id\":1,\"method\":\"\(m)\",\"params\":{}}")
            XCTAssertFalse(r.contains("unknown-method"), "\(m): \(r)")
        }
        // Sin proveedor de cámaras, la lista sale vacía y la página lo enseña como «no hay cámara».
        let cams = await b.router.handle("{\"id\":1,\"method\":\"video.settings\",\"params\":{}}")
        XCTAssertTrue(cams.contains("\"noCamera\":true") || SettingsEnvironment.cameras != nil, cams)
    }

    /// W2-E2: con `--camera simulated`, Ajustes lista la misma cámara que abre la vista previa (antes: lista vacía y
    /// subtítulo «No hay ninguna cámara conectada.» con la imagen simulada al lado).
    func testSimulatedCameraOptionListsTheCameraThePreviewOpens() async throws {
        guard SettingsEnvironment.cameras == nil, RecordEnvironment.cameras == nil else { throw XCTSkip("proveedor inyectado") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-settings-sim-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var options = LaunchOptions(projectsFolder: nil, supportDir: dir)
        options.camera = .simulated
        let b = try Bridge(options: options, mediaBase: "https://tf.media/")
        func result(_ m: String) async -> [String: Any] {
            let r = await b.router.handle("{\"id\":1,\"method\":\"\(m)\",\"params\":{}}")
            return ((try? JSONSerialization.jsonObject(with: Data(r.utf8))) as? [String: Any])?["result"] as? [String: Any] ?? [:]
        }
        let v = await result("video.settings")
        let p = await result("video.preview.start")
        _ = await result("video.preview.stop")
        XCTAssertEqual(p["state"] as? String, "simulated", "\(p)")
        XCTAssertNotNil(v["effectiveCameraId"] as? String, "\(v)")
        XCTAssertEqual(v["effectiveCameraId"] as? String, p["cameraId"] as? String)
        XCTAssertEqual(v["noCamera"] as? Bool, false, "\(v)")
    }

    // MARK: Modelos

    func testModelsListNotInstalledAndDelete() async throws {
        let rig = try SRig()
        defer { rig.cleanup() }
        let r = await rig.result("models.list")
        let m = try XCTUnwrap((r["models"] as? [[String: Any]])?.first)
        XCTAssertEqual(m["id"] as? String, SettingsService.modelID)
        XCTAssertEqual(m["state"] as? String, "notInstalled")
        XCTAssertGreaterThan(num(m["archiveBytes"]) ?? 0, 0)
        XCTAssertEqual(num(r["modelsBytes"]), 0)
        XCTAssertEqual((m["name"] as? String)?.isEmpty, false)

        let del = await rig.result("models.delete")
        XCTAssertEqual(((del["models"] as? [[String: Any]])?.first)?["state"] as? String, "notInstalled")
        let c3 = await rig.errorCode("models.delete", "{\"id\":\"otro\"}")
        XCTAssertEqual(c3, "not-found")
        let c4 = await rig.errorCode("models.download", "{\"id\":\"otro\"}")
        XCTAssertEqual(c4, "not-found")
    }

    func testModelsInstalledFromEnvironmentFolderOnWindows() async throws {
        #if os(Windows)
        let models = FileManager.default.temporaryDirectory.appendingPathComponent("tf-models-\(UUID().uuidString)")
        let folder = models.appendingPathComponent("bs_roformer")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appendingPathComponent("model.onnx"))
        defer { try? FileManager.default.removeItem(at: models) }
        let rig = try SRig(environment: ["TF_MODELS_DIR": models.path])
        defer { rig.cleanup() }
        let list = await rig.result("models.list")
        let m = try XCTUnwrap((list["models"] as? [[String: Any]])?.first)
        XCTAssertEqual(m["state"] as? String, "installed")
        XCTAssertEqual(m["source"] as? String, "folder")
        #endif
    }

    // MARK: video.*

    func testCamerasListAndChoices() async throws {
        let rig = try SRig()
        defer { rig.cleanup() }
        let r = await rig.result("video.cameras")
        XCTAssertEqual(r["defaultId"] as? String, "cam-a")
        let cams = try XCTUnwrap(r["cameras"] as? [[String: Any]])
        XCTAssertEqual(cams.map { $0["id"] as? String }, ["cam-a", "cam-b"])
        XCTAssertEqual(cams[0]["isDefault"] as? Bool, true)
        XCTAssertEqual(cams[1]["kind"] as? String, "continuity")
        // Webcam: de lo conocido solo 720p y 1080p (640x360 no es de los del producto); 1080p llega a 30.
        let res = try XCTUnwrap(cams[0]["resolutions"] as? [[String: Any]])
        XCTAssertEqual(res.map { $0["label"] as? String }, ["720p", "1080p"])
        let fps720 = try XCTUnwrap(res[0]["fps"] as? [[String: Any]])
        XCTAssertEqual(fps720.map { num($0["value"]) }, [24, 25, 30, 50, 60])
        XCTAssertEqual(fps720.first?["label"] as? String, "24 fps")
        let fps1080 = try XCTUnwrap(res[1]["fps"] as? [[String: Any]])
        XCTAssertEqual(fps1080.map { num($0["value"]) }, [24, 25, 30])
        let phone = try XCTUnwrap(cams[1]["resolutions"] as? [[String: Any]])
        XCTAssertEqual(phone.map { $0["label"] as? String }, ["1080p", "4K"])
    }

    func testNoCameras() async throws {
        let rig = try SRig(cameras: [])
        defer { rig.cleanup() }
        let c = await rig.result("video.cameras")
        XCTAssertEqual((c["cameras"] as? [Any])?.count, 0)
        XCTAssertTrue(c["defaultId"] is NSNull)
        let s = await rig.result("video.settings")
        XCTAssertEqual(s["noCamera"] as? Bool, true)
        XCTAssertTrue(s["shown"] is NSNull)
        XCTAssertEqual(s["cameraConnected"] as? Bool, false)
    }

    func testVideoSettingsDefaults() async throws {
        let rig = try SRig()
        defer { rig.cleanup() }
        let s = await rig.result("video.settings")
        XCTAssertTrue(s["cameraUID"] is NSNull)
        XCTAssertEqual(s["effectiveCameraId"] as? String, "cam-a")
        XCTAssertEqual((s["resolution"] as? [String: Any])?["label"] as? String, "1080p")
        XCTAssertEqual(num(s["fps"]), 30)
        XCTAssertEqual(num(s["offsetMs"]), 0)
        XCTAssertEqual(num(s["rotation"]), 0)
        let e = try XCTUnwrap(s["export"] as? [String: Any])
        XCTAssertEqual(e["codec"] as? String, "hevc")
        XCTAssertEqual(num(e["normalizeLUFS"]), -14)
        XCTAssertEqual(e["titleOverlay"] as? Bool, true)
        XCTAssertEqual(e["exportStemWAVs"] as? Bool, true)
        let ch = try XCTUnwrap(s["choices"] as? [String: Any])
        XCTAssertEqual((ch["offsetRangeMs"] as? [String: Any]).flatMap { num($0["min"]) }, -500)
        XCTAssertEqual((ch["exportResolutions"] as? [[String: Any]])?.count, 3)
    }

    func testSetCameraResolutionFpsPersistsAndSystemDefaultResets() async throws {
        let rig = try SRig()
        defer { rig.cleanup() }
        var s = await rig.result("video.setSettings", "{\"cameraUID\":\"cam-b\",\"resolution\":{\"width\":3840,\"height\":2160},\"fps\":24}")
        XCTAssertEqual(s["cameraUID"] as? String, "cam-b")
        XCTAssertEqual((s["resolution"] as? [String: Any])?["label"] as? String, "4K")
        XCTAssertEqual(s["cameraName"] as? String, "Telefono")
        // Se guardó en el perfil de Store (lo que lee el Mac).
        let saved = try ProfileStore(url: rig.support.appendingPathComponent("profile.json")).load().video
        XCTAssertEqual(saved?.cameraUID, "cam-b")
        XCTAssertEqual(saved?.resolution, .uhd4K)
        XCTAssertEqual(saved?.fps, 24)
        s = await rig.result("video.settings")
        XCTAssertEqual(s["cameraUID"] as? String, "cam-b")
        // `cameraUID: null` explícito = «Por defecto del sistema»; sin la clave no se toca.
        s = await rig.result("video.setSettings", "{\"fps\":30}")
        XCTAssertEqual(s["cameraUID"] as? String, "cam-b")
        s = await rig.result("video.setSettings", "{\"cameraUID\":null}")
        XCTAssertTrue(s["cameraUID"] is NSNull)
        XCTAssertNil(try ProfileStore(url: rig.support.appendingPathComponent("profile.json")).load().video?.cameraUID)
    }

    func testShownIsClosestSupportedAndProfileUntouched() async throws {
        let rig = try SRig()
        defer { rig.cleanup() }
        // La webcam no da 4K a 120: se enseña lo más cercano, el perfil conserva lo pedido.
        let s = await rig.result("video.setSettings", "{\"cameraUID\":\"cam-a\",\"resolution\":{\"width\":3840,\"height\":2160},\"fps\":120}")
        let shown = try XCTUnwrap(s["shown"] as? [String: Any])
        XCTAssertEqual((shown["resolution"] as? [String: Any])?["label"] as? String, "1080p")
        XCTAssertEqual(num(shown["fps"]), 30)
        XCTAssertEqual(num(s["fps"]), 120)
    }

    func testModelsDownloadReportsProgressConcurrencyAndFailure() async throws {
        let fake = FakeDownloader()
        let rig = try SRig(downloader: fake)
        defer { rig.cleanup() }
        let first = await rig.result("models.download", "{}")
        XCTAssertEqual(first["started"] as? Bool, true)
        // Una descarga a la vez: la segunda petición no arranca otra.
        let second = await rig.result("models.download", "{}")
        XCTAssertEqual(second["started"] as? Bool, false)
        for _ in 0..<200 where !rig.events.named("models.progress").contains(where: { num($0["fraction"]) == 0.25 }) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(rig.events.named("models.progress").contains { num($0["fraction"]) == 0.25 })
        XCTAssertEqual(fake.calls, 1)
        fake.open()
        // El archivo no coincide con el hash del catálogo: `models.changed` con el error y el modelo en `failed`.
        for _ in 0..<500 where rig.events.named("models.changed").isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        let changed = try XCTUnwrap(rig.events.named("models.changed").last)
        XCTAssertEqual((changed["error"] as? [String: Any])?["code"] as? String, "model-failed", "\(changed)")
        let m = try XCTUnwrap((changed["models"] as? [[String: Any]])?.first)
        XCTAssertEqual(m["state"] as? String, "failed")
        // Tras fallar se puede reintentar.
        let again = await rig.result("models.download", "{}")
        XCTAssertEqual(again["started"] as? Bool, true)
        XCTAssertEqual(rig.events.named("models.changed").count >= 1, true)
    }

    func testDisconnectedChosenCamera() async throws {
        let rig = try SRig()
        defer { rig.cleanup() }
        _ = await rig.result("video.setSettings", "{\"cameraUID\":\"cam-gone\"}")
        let s = await rig.result("video.settings")
        XCTAssertEqual(s["cameraConnected"] as? Bool, false)
        XCTAssertTrue(s["cameraName"] is NSNull)
        XCTAssertEqual(s["effectiveCameraId"] as? String, "cam-gone")
        XCTAssertTrue(s["shown"] is NSNull)
    }

    func testDisconnectedChosenCameraKeepsItsSeenName() async throws {
        let rig = try SRig()
        defer { rig.cleanup() }
        _ = await rig.result("video.setSettings", "{\"cameraUID\":\"cam-b\"}")
        let before = await rig.result("video.settings")
        XCTAssertEqual(before["cameraName"] as? String, "Telefono")
        rig.cameras.setCameras([SRig.webcam])
        let after = await rig.result("video.settings")
        XCTAssertEqual(after["cameraConnected"] as? Bool, false)
        XCTAssertEqual(after["cameraName"] as? String, "Telefono", "\(after)")
    }

    func testOffsetAndRotationPerCamera() async throws {
        let rig = try SRig()
        defer { rig.cleanup() }
        // Sin cameraId: la cámara que se usaría (la del sistema).
        var s = await rig.result("video.setSettings", "{\"offset\":{\"ms\":65.4},\"rotation\":{\"degrees\":90}}")
        XCTAssertEqual(num(s["offsetMs"]), 65)
        XCTAssertEqual(num(s["rotation"]), 90)
        s = await rig.result("video.setSettings", "{\"offset\":{\"cameraId\":\"cam-b\",\"ms\":9999},\"rotation\":{\"cameraId\":\"cam-b\",\"degrees\":-90}}")
        XCTAssertEqual((s["offsetsMs"] as? [String: Any]).flatMap { num($0["cam-b"]) }, 500, "se recorta a ±500 ms")
        XCTAssertEqual((s["rotations"] as? [String: Any]).flatMap { num($0["cam-b"]) }, 270)
        XCTAssertEqual((s["offsetsMs"] as? [String: Any]).flatMap { num($0["cam-a"]) }, 65)
        let v = try XCTUnwrap(try ProfileStore(url: rig.support.appendingPathComponent("profile.json")).load().video)
        XCTAssertEqual(v.defaultOffset(for: "cam-a"), 0.065, accuracy: 1e-9)
        XCTAssertEqual(v.defaultRotation(for: "cam-b"), 270)
        s = await rig.result("video.setSettings", "{\"cameraUID\":\"cam-b\"}")
        XCTAssertEqual(num(s["offsetMs"]), 500)
    }

    func testOffsetWithoutAnyCameraNeedsCameraId() async throws {
        let rig = try SRig(cameras: [])
        defer { rig.cleanup() }
        let c5 = await rig.errorCode("video.setSettings", "{\"offset\":{\"ms\":10}}")
        XCTAssertEqual(c5, "bad-params")
        let s = await rig.result("video.setSettings", "{\"offset\":{\"cameraId\":\"x\",\"ms\":10}}")
        XCTAssertEqual((s["offsetsMs"] as? [String: Any]).flatMap { num($0["x"]) }, 10)
    }

    func testExportDefaults() async throws {
        let rig = try SRig()
        defer { rig.cleanup() }
        let s = await rig.result("video.setSettings", """
        {"export":{"codec":"h264","resolution":{"width":1280,"height":720},"titleOverlay":false,"exportStemWAVs":false}}
        """)
        let e = try XCTUnwrap(s["export"] as? [String: Any])
        XCTAssertEqual(e["codec"] as? String, "h264")
        XCTAssertEqual((e["resolution"] as? [String: Any])?["label"] as? String, "720p")
        XCTAssertEqual(e["titleOverlay"] as? Bool, false)
        XCTAssertEqual(e["exportStemWAVs"] as? Bool, false)
        XCTAssertEqual(num(e["normalizeLUFS"]), -14)
        let saved = try XCTUnwrap(try ProfileStore(url: rig.support.appendingPathComponent("profile.json")).load().video)
        XCTAssertEqual(saved.export.codec, .h264)
        XCTAssertFalse(saved.export.exportStemWAVs)
    }

    func testBadVideoParams() async throws {
        let rig = try SRig()
        defer { rig.cleanup() }
        let bad = ["{\"fps\":0}", "{\"fps\":-3}", "{\"resolution\":{\"width\":0,\"height\":10}}", "{\"export\":{\"codec\":\"av1\"}}",
                   "{\"export\":{\"resolution\":{\"width\":-1,\"height\":1}}}"]
        for p in bad { let code = await rig.errorCode("video.setSettings", p); XCTAssertEqual(code, "bad-params", p) }
        let c6 = await rig.errorCode("video.setSettings", "{\"resolution\":{\"width\":\"a\"}}")
        XCTAssertEqual(c6, "bad-params")
        // Nada se guardó.
        XCTAssertNil(try ProfileStore(url: rig.support.appendingPathComponent("profile.json")).load().video)
    }

    func testCamerasChangedEvent() async throws {
        let rig = try SRig(cameras: [])
        defer { rig.cleanup() }
        rig.cameras.setCameras([SRig.webcam])
        XCTAssertEqual(rig.events.named("video.camerasChanged").count, 1)
        let c = await rig.result("video.cameras")
        XCTAssertEqual((c["cameras"] as? [Any])?.count, 1)
    }

    func testVideoSettingsKeepOtherProfileFields() async throws {
        let rig = try SRig()
        defer { rig.cleanup() }
        let store = ProfileStore(url: rig.support.appendingPathComponent("profile.json"))
        var p = EquipmentProfile(projectsFolder: rig.projects, workingSampleRate: 48000, masterGainDB: -3)
        p.audio = nil
        try store.save(p)
        _ = await rig.result("video.setSettings", "{\"fps\":60}")
        let after = try store.load()
        XCTAssertEqual(after.workingSampleRate, 48000)
        XCTAssertEqual(after.masterGainDB, -3)
        XCTAssertEqual(after.projectsFolder, rig.projects)
        XCTAssertEqual(after.video?.fps, 60)
    }

    /// W2-E2: en Windows solo se ofrece H.264; un `hevc` (p. ej. venido del Mac) se guarda como `h264`. En el Mac no cambia.
    func testCodecNormalizedToOfferedOnes() {
        XCTAssertEqual(SettingsCameraChoices.normalized(.hevc, offered: [.h264]), .h264)
        XCTAssertEqual(SettingsCameraChoices.normalized(.h264, offered: [.h264]), .h264)
        XCTAssertEqual(SettingsCameraChoices.normalized(.hevc, offered: VideoCodec.allCases), .hevc)
        #if os(Windows)
        XCTAssertEqual(SettingsCameraChoices.normalized(.hevc), .h264)
        #else
        XCTAssertEqual(SettingsCameraChoices.normalized(.hevc), .hevc)
        #endif
    }

    func testCameraLaunchOption() {
        XCTAssertNil(LaunchOptions.parse([]).camera)
        XCTAssertEqual(LaunchOptions.parse(["--camera", "real"]).camera, .real)
        XCTAssertEqual(LaunchOptions.parse(["--camera=Simulated", "--audio", "simulated"]).camera, .simulated)
        XCTAssertNil(LaunchOptions.parse(["--camera", "x"]).camera)
    }
}
