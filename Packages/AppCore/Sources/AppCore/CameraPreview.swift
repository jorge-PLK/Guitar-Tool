import Foundation
import Store
import VideoKit

// Vista previa de la cámara en Ajustes · Cámara y vídeo (W2-E2): `video.preview.start` / `video.preview.stop`, sin grabar,
// por el mismo canal que Grabar (`frames.camera`). Como `CameraPreviewModel` del Mac: la cámara efectiva (la elegida o la
// del sistema) con el formato que el selector enseña. Contrato: `Temp/win/step8-contract.md`, «W2-E2».

/// Respuesta de `video.preview.start` (y de `stop`, con `state:"idle"`).
struct CameraPreviewResult: Codable, Sendable, Equatable {
    /// `idle | live | simulated | noCamera | denied | failed`.
    var state: String
    /// Texto del Mac para `noCamera`/`denied`/`failed`; nil si hay imagen.
    var message: String?
    var cameraId: String?
    var cameraName: String?
    var width: Int?
    var height: Int?
    var fps: Double?
    /// Giro guardado de esa cámara (grados horarios; lo aplica la página).
    var rotation: Int
    /// true = Grabar está abierta y ya manda su cámara por `frames.camera`: no se abre otra captura.
    var fromRecord: Bool
}

/// Abre el panel de privacidad de cámara del sistema («Abrir Ajustes del Sistema» de `VideoSettingsView.openCameraPrivacy`).
protocol CameraPrivacyOpening: Sendable {
    func openCameraPrivacy() throws
}

/// Windows: `ms-settings:privacy-webcam`; Mac (`tf-webdev`): Privacidad › Cámara.
struct SystemCameraPrivacy: CameraPrivacyOpening {
    #if os(Windows)
    static let url = "ms-settings:privacy-webcam"
    #else
    static let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
    #endif

    func openCameraPrivacy() throws {
        let p = Process()
        #if os(Windows)
        p.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\cmd.exe")
        p.arguments = ["/c", "start", "", Self.url]
        #else
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = [Self.url]
        #endif
        do { try p.run() } catch {
            throw RPCError(code: "internal", message: "No se pudieron abrir los ajustes del sistema: \(error)")
        }
    }
}

struct CameraPrivacyResult: Codable, Sendable, Equatable { var opened: Bool }

@MainActor
final class CameraPreviewService {
    /// Texto del Mac con el permiso denegado (`VideoSettingsView.previewBox`).
    nonisolated static let deniedMessage = "ToneForge no tiene permiso para usar la cámara."
    /// Sustituible en tests.
    nonisolated(unsafe) var privacy: any CameraPrivacyOpening = SystemCameraPrivacy()
    private let profile: ProfileStore
    private let options: LaunchOptions
    /// Relevo `frames.camera`; lo da el `Bridge` antes de cualquier método.
    nonisolated(unsafe) var makeRelay: (@Sendable () -> FrameRelay?)?
    /// Grabar abierta (comparte la cámara).
    nonisolated(unsafe) var recordController: (@MainActor () -> RecordController?)?
    /// Tests: cámaras a medida; nil = como Grabar (`RecordCameraSource.resolve`).
    var cameras: RecordCameraSource?
    private var capture: (any CameraCapture)?
    private(set) var relay: FrameRelay?
    private var generation = 0

    nonisolated init(options: LaunchOptions) {
        self.options = options
        profile = options.supportDir.map { ProfileStore(url: $0.appendingPathComponent("profile.json")) } ?? ProfileStore()
    }

    nonisolated func register(on router: Router) {
        router.register("video.preview.start") { [self] (_: Empty) -> CameraPreviewResult in await start() }
        router.register("video.preview.stop") { [self] (_: Empty) -> CameraPreviewResult in await stopped() }
        router.register("video.openCameraPrivacy") { [self] (_: Empty) -> CameraPrivacyResult in
            try privacy.openCameraPrivacy()
            return CameraPrivacyResult(opened: true)
        }
    }

    nonisolated static let idle = CameraPreviewResult(state: "idle", rotation: 0, fromRecord: false)

    /// Arranca (o rehace, si ya estaba) la vista previa. Con Grabar abierta, devuelve su estado sin abrir otra captura.
    func start() async -> CameraPreviewResult {
        stop()
        generation += 1
        let mine = generation
        let video = (try? profile.load())?.video ?? VideoSettings()
        if let rc = recordController?() {
            let name = rc.cameraState.name == "none" ? "noCamera" : rc.cameraState.name
            return CameraPreviewResult(state: name, message: rc.cameraMessage, cameraId: rc.activeCameraID,
                                       cameraName: rc.cameraName, width: rc.videoFormat?.width, height: rc.videoFormat?.height,
                                       fps: rc.videoFormat?.fps, rotation: rc.cameraRotation, fromRecord: true)
        }
        guard let source = cameras ?? RecordCameraSource.resolve(options) else { return Self.noCamera(video) }
        // Como `CameraList.effective` del Mac: la elegida si está conectada (si no, `noCamera`, sin caer a la del sistema);
        // sin elección, la del sistema.
        let device = video.cameraUID.map { source.provider.camera(id: $0) } ?? source.provider.defaultCamera()
        guard let device else { return Self.noCamera(video) }
        var result = CameraPreviewResult(state: "live", cameraId: device.id, cameraName: device.name,
                                         rotation: video.defaultRotation(for: device.id), fromRecord: false)
        // El formato que enseña el selector (el del perfil si la cámara lo admite; si no, el más cercano).
        var request = CameraRequest(width: video.resolution.width, height: video.resolution.height, fps: video.fps)
        if let m = SettingsCameraChoices.closest(VideoKitCameraAdapter.convert(device), width: request.width, height: request.height,
                                                 fps: request.fps) {
            request = CameraRequest(width: m.format.width, height: m.format.height, fps: m.fps)
        }
        if !source.isSimulated {
            guard await source.ensureAccess() else {
                result.state = "denied"
                result.message = Self.deniedMessage
                return result
            }
            guard mine == generation else { return Self.idle }
        }
        guard let relay = makeRelay?() else { return Self.idle }
        let hook = RecordService.previewHook(relay)
        let make = source.makeCapture
        let opened = await Task.detached { () -> Result<(any CameraCapture, VideoFormat), Error> in
            do {
                let c = try make(device)
                let f = try c.start(request) { hook($0) }
                return .success((c, f))
            } catch { return .failure(error) }
        }.value
        switch opened {
        case .success(let (c, f)):
            guard mine == generation else {
                relay.stop()
                Task.detached { c.stop() }
                return Self.idle
            }
            capture = c
            self.relay = relay
            result.state = source.isSimulated ? "simulated" : "live"
            result.width = f.width
            result.height = f.height
            result.fps = f.fps
        case .failure(let e):
            relay.stop()
            if let ce = e as? CameraError, ce == .noAccess {
                result.state = "denied"
                result.message = Self.deniedMessage
            } else {
                result.state = "failed"
                result.message = "No se pudo abrir la cámara (\(e))."
            }
        }
        return result
    }

    func stopped() -> CameraPreviewResult { stop(); return Self.idle }

    /// Para la captura propia (si la hay). Con Grabar abierta no la toca.
    func stop() {
        generation += 1
        relay?.stop()
        relay = nil
        if let c = capture { Task.detached { c.stop() } }
        capture = nil
    }

    static func noCamera(_ v: VideoSettings) -> CameraPreviewResult {
        CameraPreviewResult(state: "noCamera",
                            message: v.cameraUID == nil ? "No hay ninguna cámara conectada." : "La cámara elegida está desconectada.",
                            cameraId: v.cameraUID, rotation: v.cameraUID.map { v.defaultRotation(for: $0) } ?? 0, fromRecord: false)
    }
}
