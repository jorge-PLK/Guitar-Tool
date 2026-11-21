#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation

/// Rango de fotogramas por segundo que admite un formato.
public struct FrameRateRange: Sendable, Equatable, Hashable, Codable {
    public var min: Double
    public var max: Double

    public init(min: Double, max: Double) {
        self.min = min
        self.max = max
    }

    /// `fps` llevado al rango.
    public func clamp(_ fps: Double) -> Double { Swift.min(Swift.max(fps, min), max) }
}

/// Formato de una cámara: resolución y rangos de fps (mini-spec Fase 6, «Cámara y sincronía»).
public struct CameraFormat: Sendable, Equatable, Hashable {
    public var width: Int
    public var height: Int
    public var frameRates: [FrameRateRange]
    /// Posición en `AVCaptureDevice.formats` (-1 en la cámara simulada).
    public var index: Int

    public init(width: Int, height: Int, frameRates: [FrameRateRange], index: Int = -1) {
        self.width = width
        self.height = height
        self.frameRates = frameRates
        self.index = index
    }

    public var maxFrameRate: Double { frameRates.map(\.max).max() ?? 0 }

    /// fps admitido más cercano a `fps`.
    public func closestFrameRate(to fps: Double) -> Double {
        frameRates.map { $0.clamp(fps) }.min { abs($0 - fps) < abs($1 - fps) } ?? fps
    }
}

/// Qué tipo de cámara es (solo para enseñarlo; nada decide por el tipo ni por el nombre).
public enum CameraKind: String, Sendable, Equatable, Codable {
    case builtIn
    case external
    case continuity
    case simulated
    case other
}

/// Una cámara de vídeo del sistema (mini-spec Fase 6: webcam USB, integrada, iPhone por Continuity Camera).
public struct CameraDevice: Sendable, Equatable, Identifiable {
    /// `AVCaptureDevice.uniqueID` (lo que guarda `VideoSettings.cameraUID`).
    public var id: String
    public var name: String
    public var kind: CameraKind
    public var formats: [CameraFormat]

    public init(id: String, name: String, kind: CameraKind, formats: [CameraFormat]) {
        self.id = id
        self.name = name
        self.kind = kind
        self.formats = formats
    }

    /// Cámara simulada de los tests y de `tf-video --simulated`: 1280×720 y 1920×1080 a 24–60 fps y 640×360 a 30.
    public static let simulated = CameraDevice(
        id: "sim-camera", name: "Cámara simulada", kind: .simulated,
        formats: [
            CameraFormat(width: 640, height: 360, frameRates: [FrameRateRange(min: 30, max: 30)]),
            CameraFormat(width: 1280, height: 720, frameRates: [FrameRateRange(min: 24, max: 60)]),
            CameraFormat(width: 1920, height: 1080, frameRates: [FrameRateRange(min: 24, max: 60)])
        ])
}

/// Formato pedido (el de Ajustes: resolución y fps).
public struct CameraRequest: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var fps: Double

    public init(width: Int, height: Int, fps: Double) {
        self.width = width
        self.height = height
        self.fps = fps
    }
}

/// Formato real con que se grabó (lo que guarda `Take.videoFormat`: cámara, ancho, alto y fps).
public struct VideoFormat: Sendable, Equatable, Codable {
    public var cameraID: String
    public var cameraName: String
    public var width: Int
    public var height: Int
    public var fps: Double

    public init(cameraID: String, cameraName: String, width: Int, height: Int, fps: Double) {
        self.cameraID = cameraID
        self.cameraName = cameraName
        self.width = width
        self.height = height
        self.fps = fps
    }
}

public extension CameraDevice {
    /// Formato más cercano al pedido (mini-spec Fase 6: «si la cámara no da el formato pedido, el más cercano»)
    /// y los fps que se usarán con él. Regla propia: primero la resolución (menor diferencia de área en escala
    /// logarítmica y, a igualdad, de proporción) y luego los fps (el admitido más cercano). `nil` sin formatos.
    func closestFormat(to request: CameraRequest) -> (format: CameraFormat, fps: Double)? {
        func resolutionDistance(_ f: CameraFormat) -> (Double, Double) {
            let area = log(Double(f.width * f.height) / Double(max(1, request.width * request.height)))
            let aspect = log((Double(f.width) / Double(max(1, f.height))) / (Double(request.width) / Double(max(1, request.height))))
            // Redondeo para que formatos iguales con otro píxel no se desempaten por ruido de coma flotante.
            return ((abs(area) * 1e6).rounded(), (abs(aspect) * 1e6).rounded())
        }
        let best = formats.enumerated().min { a, b in
            let ra = resolutionDistance(a.element), rb = resolutionDistance(b.element)
            if ra != rb { return ra < rb }
            let fa = abs(a.element.closestFrameRate(to: request.fps) - request.fps)
            let fb = abs(b.element.closestFrameRate(to: request.fps) - request.fps)
            if fa != fb { return fa < fb }
            return a.offset < b.offset
        }
        return best.map { ($0.element, $0.element.closestFrameRate(to: request.fps)) }
    }
}

/// Cámaras del sistema detrás de un protocolo (la real y la simulada).
public protocol CameraProviding: AnyObject, Sendable {
    func cameras() -> [CameraDevice]
    /// Cámara por defecto del sistema (`nil` si no hay ninguna).
    func defaultCamera() -> CameraDevice?
    /// Aviso al conectar o desconectar una cámara (en cualquier hilo).
    func setChangeHandler(_ handler: (@Sendable () -> Void)?)
}

public extension CameraProviding {
    func camera(id: String) -> CameraDevice? { cameras().first { $0.id == id } }
}

#if canImport(AVFoundation)
/// Cámaras reales con `AVCaptureDevice.DiscoverySession`: integradas, externas (USB) y Continuity Camera.
public final class AVCameraProvider: CameraProviding, @unchecked Sendable {
    static let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera]

    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var observers: [any NSObjectProtocol] = []

    public init() {
        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.lock.withLock { self?.handler }?()
            })
        }
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    public func setChangeHandler(_ handler: (@Sendable () -> Void)?) { lock.withLock { self.handler = handler } }

    static func discovery() -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .unspecified)
    }

    public func cameras() -> [CameraDevice] { Self.discovery().devices.map(Self.describe) }

    public func defaultCamera() -> CameraDevice? { AVCaptureDevice.default(for: .video).map(Self.describe) }

    static func kind(_ d: AVCaptureDevice) -> CameraKind {
        switch d.deviceType {
        case .builtInWideAngleCamera: return .builtIn
        case .external: return .external
        case .continuityCamera: return .continuity
        default: return .other
        }
    }

    /// Formatos sin repetir (mismo tamaño y rangos; p. ej. el mismo con otro formato de píxel): el primero.
    static func describe(_ d: AVCaptureDevice) -> CameraDevice {
        var seen = Set<CameraFormat>()
        var formats: [CameraFormat] = []
        for (i, f) in d.formats.enumerated() {
            let dims = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            let ranges = f.videoSupportedFrameRateRanges.map { FrameRateRange(min: $0.minFrameRate, max: $0.maxFrameRate) }
            let key = CameraFormat(width: Int(dims.width), height: Int(dims.height), frameRates: ranges, index: -1)
            guard seen.insert(key).inserted else { continue }
            formats.append(CameraFormat(width: key.width, height: key.height, frameRates: ranges, index: i))
        }
        return CameraDevice(id: d.uniqueID, name: d.localizedName, kind: kind(d), formats: formats)
    }

    /// Permiso de cámara (pide si no está decidido).
    public static func ensureAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}
#endif

/// Cámaras simuladas (tests, `tf-video --simulated` y capturas de la app sin cámara).
public final class SimulatedCameraProvider: CameraProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var list: [CameraDevice]
    private var handler: (@Sendable () -> Void)?

    public init(cameras: [CameraDevice] = [.simulated]) { list = cameras }

    public func cameras() -> [CameraDevice] { lock.withLock { list } }
    public func defaultCamera() -> CameraDevice? { lock.withLock { list.first } }
    public func setChangeHandler(_ handler: (@Sendable () -> Void)?) { lock.withLock { self.handler = handler } }

    /// Cambia la lista (conectar o desconectar) y avisa.
    public func setCameras(_ cameras: [CameraDevice]) {
        let h = lock.withLock { () -> (@Sendable () -> Void)? in
            list = cameras
            return handler
        }
        h?()
    }
}
