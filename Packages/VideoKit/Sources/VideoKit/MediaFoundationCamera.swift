#if os(Windows)
import CMediaFoundation
import Foundation
import NativePlatform

// Cámaras en Windows con Media Foundation (plan, «Fase 7c», paso 7, parte 7.2). Misma forma y mismo contrato que
// `AVCameraProvider` y `AVCameraCapture` del Mac: `CameraFrame.hostSeconds` en segundos de `HostClock` (QPC),
// `arrivalHostSeconds` al entrar en la devolución de llamada, fotogramas en orden y `stop` sin entregas tras volver.

/// Cámaras del sistema (`MFEnumDeviceSources`), con aviso al conectar o desconectar (`CM_Register_Notification`).
public final class MediaFoundationCameraProvider: CameraProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var watch: UnsafeMutableRawPointer?

    public init() {}

    deinit { if let watch { tfmf_unwatch_cameras(watch) } }

    public func cameras() -> [CameraDevice] { Self.list() }

    /// Windows no tiene cámara por defecto: la primera que enumera Media Foundation.
    public func defaultCamera() -> CameraDevice? { cameras().first }

    public func camera(id: String) -> CameraDevice? {
        guard let i = Self.identities().first(where: { $0.id == id }) else { return nil }
        return FormatCache.shared.device(id: i.id, name: i.name)
    }

    public func hasCamera(id: String) -> Bool { Self.isPresent(id: id) }

    public func setChangeHandler(_ handler: (@Sendable () -> Void)?) {
        let old = lock.withLock { () -> UnsafeMutableRawPointer? in
            self.handler = handler
            if handler != nil, watch == nil {
                let cb: tfmf_change_callback = { ctx in
                    guard let ctx else { return }
                    Unmanaged<MediaFoundationCameraProvider>.fromOpaque(ctx).takeUnretainedValue().notify()
                }
                watch = tfmf_watch_cameras(cb, Unmanaged.passUnretained(self).toOpaque())
                return nil
            }
            guard handler == nil, let w = watch else { return nil }
            watch = nil
            return w
        }
        // Fuera del cerrojo: `tfmf_unwatch_cameras` espera a una devolución de llamada en curso, que lo toma.
        if let old { tfmf_unwatch_cameras(old) }
    }

    private func notify() { lock.withLock { handler }?() }

    /// Permiso de cámara: falso solo si la privacidad de Windows la niega a las aplicaciones de escritorio (no hay
    /// diálogo que pedir desde una aplicación sin empaquetar).
    public static func ensureAccess() async -> Bool { tfmf_camera_access() != 0 }

    /// Identificador y nombre de cada cámara, sin sus formatos: `MFEnumDeviceSources` solo (barato).
    static func identities() -> [(id: String, name: String)] {
        let n = tfmf_camera_list(nil, 0)
        guard n > 0 else { return [] }
        var infos = [TFMFCameraInfo](repeating: TFMFCameraInfo(), count: Int(n))
        let got = infos.withUnsafeMutableBufferPointer { tfmf_camera_list($0.baseAddress, n) }
        guard got > 0 else { return [] }
        return infos.prefix(Int(min(got, n))).map { (MF.string($0.id), MF.string($0.name)) }
    }

    /// Cámaras con formatos. Describir una abre el dispositivo y recorre sus tipos nativos (~480 ms con una C925e y 122
    /// formatos, medido en el PC, W-2): se hace una vez por cámara y se reutiliza (`FormatCache`). Enumerar sin más cuesta
    /// lo de `identities()`; Grabar lo pide en cada instantánea, en el sondeo y al abrir, todo en el actor principal.
    static func list() -> [CameraDevice] {
        let ids = identities()
        let devices = ids.map { FormatCache.shared.device(id: $0.id, name: $0.name) }
        FormatCache.shared.keep(Set(ids.map(\.id)))
        return devices
    }

    /// ¿Está conectada? Sin describirla.
    static func isPresent(id: String) -> Bool { identities().contains { $0.id == id } }

    /// Descripciones ya hechas por identificador (compartidas por todos los proveedores y capturas del proceso). Una
    /// descripción sin formatos (cámara ocupada o fallo transitorio) no se guarda: se reintenta en la siguiente.
    final class FormatCache: @unchecked Sendable {
        static let shared = FormatCache()
        private let lock = NSLock()
        private var devices: [String: CameraDevice] = [:]

        func device(id: String, name: String) -> CameraDevice {
            if let hit = lock.withLock({ devices[id] }), hit.name == name { return hit }
            let d = MediaFoundationCameraProvider.describe(id: id, name: name)
            if !d.formats.isEmpty { lock.withLock { devices[id] = d } }
            return d
        }

        func keep(_ ids: Set<String>) { lock.withLock { devices = devices.filter { ids.contains($0.key) } } }
    }

    /// Formatos sin repetir (mismo tamaño y rangos de fps): el primero, prefiriendo los sin comprimir (NV12, YUY2) a
    /// MJPG, como el Mac se queda con el primero de `AVCaptureDevice.formats`.
    static func describe(id: String, name: String) -> CameraDevice {
        var raw: [TFMFCameraFormat] = []
        let n = MF.withWide(id) { tfmf_camera_formats($0, nil, 0) }
        if n > 0 {
            raw = [TFMFCameraFormat](repeating: TFMFCameraFormat(), count: Int(n))
            let got = MF.withWide(id) { w in raw.withUnsafeMutableBufferPointer { tfmf_camera_formats(w, $0.baseAddress, n) } }
            raw = got > 0 ? Array(raw.prefix(Int(min(got, n)))) : []
        }
        let compressed: Set<String> = ["MJPG", "H264", "HEVC"]
        let ordered = raw.enumerated().sorted { a, b in
            let ca = compressed.contains(MF.fourCC(a.element.fourCC)), cb = compressed.contains(MF.fourCC(b.element.fourCC))
            return ca != cb ? !ca : a.offset < b.offset
        }.map(\.element)
        var seen = Set<CameraFormat>()
        var formats: [CameraFormat] = []
        for f in ordered {
            let lo = f.fpsMinDen > 0 ? Double(f.fpsMinNum) / Double(f.fpsMinDen) : 0
            let hi = f.fpsMaxDen > 0 ? Double(f.fpsMaxNum) / Double(f.fpsMaxDen) : lo
            let key = CameraFormat(width: Int(f.width), height: Int(f.height), frameRates: [FrameRateRange(min: min(lo, hi), max: max(lo, hi))])
            guard seen.insert(key).inserted else { continue }
            formats.append(CameraFormat(width: key.width, height: key.height, frameRates: key.frameRates, index: Int(f.index)))
        }
        let kind: CameraKind = id.lowercased().contains("usb#") ? .external : .other
        return CameraDevice(id: id, name: name, kind: kind, formats: formats)
    }
}

/// Captura con `IMFSourceReader` asíncrono, salida NV12.
///
/// **Marcas.** Cada muestra lleva `MFSampleExtension_DeviceTimestamp` (QPC del dispositivo en 100 ns): se pasa a ticks
/// de QPC (`QPCTime.ticks`) y de ahí a segundos con `HostClock.seconds(ticks:)`, la escala de `AudioIOBuffer.hostSeconds`.
/// Si un controlador no la da, la marca del lector más el menor `hora del sistema − marca` visto hasta entonces
/// (`stampSource == .readerPlusArrival`: la marca sale tarde por el retardo de entrega mínimo; `tf-video sync` lo mide).
///
/// **Perdidos.** Media Foundation no avisa: un salto de más de 1,5 periodos entre marcas cuenta los que faltan (y
/// avanza `sequence` como `didDrop` en el Mac).
public final class MediaFoundationCameraCapture: CameraCapture, @unchecked Sendable {
    /// De dónde sale `hostSeconds`.
    public enum StampSource: String, Sendable { case device, readerPlusArrival }

    public let camera: CameraDevice
    private let lock = NSLock()
    private var handle: UnsafeMutableRawPointer?
    private var handler: CameraFrameHandler?
    private var running = false
    private var sequence = 0
    private var dropped = 0
    private var period = 1.0 / 30
    private var lastHost: Double?
    private var readerOffset: Int64?
    private var source: StampSource = .device
    static let frequency = QPCTime.frequency(timebase: HostClock.timebase)

    public init(cameraID: String) throws {
        guard let i = MediaFoundationCameraProvider.identities().first(where: { $0.id == cameraID }) else { throw CameraError.notFound(cameraID) }
        let d = MediaFoundationCameraProvider.FormatCache.shared.device(id: i.id, name: i.name)
        guard !d.formats.isEmpty else { throw CameraError.noFormats(cameraID) }
        camera = d
    }

    deinit { stop() }

    public var isRunning: Bool { lock.withLock { running } }
    public var droppedFrames: Int { lock.withLock { dropped } }
    public var stampSource: StampSource { lock.withLock { source } }

    public func start(_ request: CameraRequest, onFrame: @escaping CameraFrameHandler) throws -> VideoFormat {
        guard !isRunning else { throw CameraError.alreadyRunning }
        guard tfmf_camera_access() != 0 else { throw CameraError.noAccess }
        guard let (format, fps) = camera.closestFormat(to: request), format.index >= 0 else { throw CameraError.noFormats(camera.id) }
        let (num, den) = MF.rational(fps)
        lock.withLock {
            handler = onFrame
            sequence = 0
            dropped = 0
            lastHost = nil
            readerOffset = nil
            source = .device
            period = 1 / max(1, fps)
            running = true
        }
        let cb: tfmf_camera_callback = { ctx, frame in
            guard let ctx, let frame else { return }
            Unmanaged<MediaFoundationCameraCapture>.fromOpaque(ctx).takeUnretainedValue().deliver(frame.pointee)
        }
        var h: UnsafeMutableRawPointer?
        var w: Int32 = 0, ht: Int32 = 0, fn: Int32 = 0, fd: Int32 = 0
        let hr = MF.withWide(camera.id) {
            tfmf_capture_start($0, Int32(format.index), num, den, cb, Unmanaged.passUnretained(self).toOpaque(), &h, &w, &ht, &fn, &fd)
        }
        guard hr >= 0, let h else {
            lock.withLock { running = false; handler = nil }
            // E_ACCESSDENIED: la privacidad de Windows o otra aplicación con la cámara.
            if UInt32(bitPattern: hr) == 0x8007_0005 { throw CameraError.noAccess }
            throw CameraError.configuration(MediaFoundationError(hr: hr, step: "iniciar la captura").description)
        }
        let real = fd > 0 ? Double(fn) / Double(fd) : fps
        lock.withLock {
            handle = h
            period = 1 / max(1, real)
        }
        return VideoFormat(cameraID: camera.id, cameraName: camera.name, width: Int(w), height: Int(ht), fps: real)
    }

    public func stop() {
        let h = lock.withLock { () -> UnsafeMutableRawPointer? in
            defer { handle = nil; running = false; handler = nil }
            return handle
        }
        // Al volver, ninguna devolución de llamada en curso ni pendiente (el shim espera con su cerrojo).
        if let h { tfmf_capture_stop(h) }
    }

    /// Segundos de host de una marca de 100 ns de QPC.
    static func hostSeconds(qpcHundredNanoseconds t: Int64) -> Double {
        HostClock.seconds(ticks: QPCTime.ticks(hundredNanoseconds: t, frequency: frequency))
    }

    private func deliver(_ f: TFMFCameraFrame) {
        let arrival = HostClock.nowSeconds
        let pb = FramePixelBuffer(pixelFormat: .nv12, width: Int(f.width), height: Int(f.height))
        if let y = f.y, let uv = f.uv {
            for r in 0..<pb.height { (pb.baseAddress + r * pb.bytesPerRow).copyMemory(from: y + r * Int(f.yStride), byteCount: pb.width) }
            let dst = pb.planeBaseAddress(1)
            for r in 0..<pb.planeHeight(1) {
                (dst + r * pb.bytesPerRow).copyMemory(from: uv + r * Int(f.uvStride), byteCount: 2 * ((pb.width + 1) / 2))
            }
        }
        let step = lock.withLock { () -> (CameraFrameHandler, Int, Double)? in
            guard running, let handler else { return nil }
            let host: Double
            if f.hasDeviceTime != 0 {
                host = Self.hostSeconds(qpcHundredNanoseconds: f.deviceQPC100ns)
            } else {
                source = .readerPlusArrival
                readerOffset = min(readerOffset ?? .max, f.systemTime100ns - f.sampleTime100ns)
                host = Self.hostSeconds(qpcHundredNanoseconds: f.sampleTime100ns + (readerOffset ?? 0))
            }
            if let last = lastHost, host - last > 1.5 * period {
                let missing = Int(((host - last) / period).rounded()) - 1
                dropped += missing
                sequence += missing
            }
            lastHost = host
            defer { sequence += 1 }
            return (handler, sequence, host)
        }
        guard let (handler, seq, host) = step else { return }
        handler(CameraFrame(hostSeconds: host, arrivalHostSeconds: arrival, sequence: seq, pixelBuffer: pb))
    }
}
#endif
