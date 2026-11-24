import Foundation
import Store
import VideoKit
import XCTest
@testable import AppCore

// Ola 3, parte 3.2: fixtures de `video.*` en `Contract/fixtures/video/`. Convención de variantes como en
// `ContractFixtures+Audio.swift` (`<método>.<variante>.<params|result|error|event>.json`).
// Las cámaras son siempre simuladas y explícitas (las de `VideoDemo` de `VideoSettingsView.swift`), nunca el proveedor del sistema.

private struct FixtureCameraFailure: Error {}

private struct FixturePrivacy: CameraPrivacyOpening {
    func openCameraPrivacy() throws {}
}

final class ContractFixturesVideoTests: XCTestCase {
    static let simCamera = SettingsCamera(id: "sim-camera", name: "Cámara simulada", kind: "simulated", formats: [
        SettingsCameraFormat(width: 1280, height: 720, frameRates: [SettingsFrameRange(min: 24, max: 60)]),
        SettingsCameraFormat(width: 1920, height: 1080, frameRates: [SettingsFrameRange(min: 24, max: 60)])])
    static let iphone = SettingsCamera(id: "sim-iphone", name: "iPhone (Continuity Camera)", kind: "continuity", formats: [
        SettingsCameraFormat(width: 1280, height: 720, frameRates: [SettingsFrameRange(min: 24, max: 60)]),
        SettingsCameraFormat(width: 1920, height: 1080, frameRates: [SettingsFrameRange(min: 24, max: 60)]),
        SettingsCameraFormat(width: 3840, height: 2160, frameRates: [SettingsFrameRange(min: 24, max: 30)])])

    /// Servicio de ajustes con cámaras explícitas y un perfil temporal propio (con vídeo opcional).
    private func settings(_ rig: FixtureRig, cameras list: [SettingsCamera], video: VideoSettings? = nil)
        throws -> (FixtureCalls, SimulatedSettingsCameras) {
        let support = rig.dir.appendingPathComponent("Video-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let store = ProfileStore(url: support.appendingPathComponent("profile.json"))
        if let video {
            var p = EquipmentProfile()
            p.video = video
            try store.save(p)
        }
        let cameras = SimulatedSettingsCameras(cameras: list)
        let service = SettingsService(profile: store, jobs: rig.bridge.jobs, activeFolder: ProjectsRoot(rig.projects),
                                      modelsRoot: support.appendingPathComponent("Models"), environment: [:], cameras: cameras)
        service.setSink { _ in }
        let router = Router()
        service.register(on: router)
        return (FixtureCalls(rig: rig, router: router), cameras)
    }

    private var demoVideo: VideoSettings {
        var v = VideoSettings(cameraUID: "sim-iphone", resolution: .fullHD, fps: 30)
        v.setDefaultOffset(0.065, for: "sim-iphone")
        v.setDefaultRotation(90, for: "sim-iphone")
        return v
    }

    func testVideoSettingsArea() async throws {
        let rig = try FixtureRig(area: "video")
        defer { rig.cleanup() }

        // Normal: dos cámaras, la elegida es el iPhone.
        do {
            let (f, _) = try settings(rig, cameras: [Self.simCamera, Self.iphone], video: demoVideo)
            try await f.call("video.cameras")
            try await f.call("video.settings")
            try rig.event("video.camerasChanged", Empty())
        }

        // Sin ninguna cámara.
        do {
            let (f, _) = try settings(rig, cameras: [])
            try await f.call("video.cameras", variant: "nocamera")
            try await f.call("video.settings", variant: "nocamera")
        }

        // La elegida se desconecta (el nombre se recuerda de la lista vista antes).
        do {
            let (f, cameras) = try settings(rig, cameras: [Self.simCamera, Self.iphone], video: demoVideo)
            _ = await f.router.handle("{\"id\":1,\"method\":\"video.cameras\",\"params\":{}}")
            cameras.setCameras([Self.simCamera])
            try await f.call("video.settings", variant: "disconnected")
            try await f.call("video.cameras", variant: "disconnected")
        }

        // Cambios: tres estados de `cameraUID` (ausente, valor, null) y error.
        do {
            let (f, _) = try settings(rig, cameras: [Self.simCamera, Self.iphone])
            try await f.call("video.setSettings", params: "{\"resolution\":{\"width\":1280,\"height\":720},\"fps\":60}")
            try await f.call("video.setSettings", variant: "camera", params: "{\"cameraUID\":\"sim-iphone\"}")
            try await f.call("video.setSettings", variant: "cameraabsent", params: "{\"rotation\":{\"degrees\":90}}")
            try await f.call("video.setSettings", variant: "cameranull", params: "{\"cameraUID\":null}")
            try await f.call("video.setSettings", variant: "export",
                             params: "{\"export\":{\"codec\":\"h264\",\"titleOverlay\":true},\"offset\":{\"ms\":65}}")
            try await f.call("video.setSettings", variant: "badresolution", params: "{\"resolution\":{\"width\":0,\"height\":0}}")
        }
    }

    @MainActor
    private func preview(_ rig: FixtureRig, source: RecordCameraSource?, relay: Bool = true) throws -> (FixtureCalls, CameraPreviewService) {
        let dir = rig.dir.appendingPathComponent("Preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let s = CameraPreviewService(options: LaunchOptions(projectsFolder: rig.projects, supportDir: dir))
        s.cameras = source
        s.privacy = FixturePrivacy()
        if relay { s.makeRelay = { FrameRelay(channel: "fx-\(UUID().uuidString)", emit: { _, _ in }) } }
        let router = Router()
        s.register(on: router)
        return (FixtureCalls(rig: rig, router: router), s)
    }

    @MainActor
    func testVideoPreviewArea() async throws {
        let rig = try FixtureRig(area: "video")
        defer { rig.cleanup() }

        func live(access: Bool = true, simulated: Bool = false, cameras: [CameraDevice] = [.simulated],
                  make: (@Sendable (CameraDevice) throws -> any CameraCapture)? = nil) -> RecordCameraSource {
            RecordCameraSource(provider: SimulatedCameraProvider(cameras: cameras),
                               makeCapture: make ?? { SimulatedCameraCapture(camera: $0, config: .init(pixels: true), automatic: true) },
                               ensureAccess: { access }, isSimulated: simulated)
        }
        let cases: [(String?, RecordCameraSource, Bool)] = [
            ("simulated", live(simulated: true), true),
            ("live", live(), true),
            ("nocamera", live(cameras: []), true),
            ("denied", live(access: false), true),
            ("failed", live(make: { _ in throw FixtureCameraFailure() }), true),
            ("idle", live(simulated: true), false),
        ]
        for (variant, source, relay) in cases {
            let (f, s) = try preview(rig, source: source, relay: relay)
            try await f.call("video.preview.start", variant: variant)
            s.stop()
        }
        let (f, s) = try preview(rig, source: live(simulated: true))
        try await f.call("video.preview.start", variant: "stopfirst")
        try await f.call("video.preview.stop")
        try await f.call("video.openCameraPrivacy")
        s.stop()
    }
}
