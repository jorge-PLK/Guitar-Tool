#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(CoreVideo)
import CoreVideo
#endif
import Foundation

#if canImport(CoreVideo)
/// Imagen de un fotograma: `CVPixelBuffer` en el Mac. Fuera del Mac, la clase propia de `FramePixelBuffer.swift`.
public typealias FramePixelBuffer = CVPixelBuffer
#endif

/// Un fotograma de la cámara con su marca en el reloj de host (mini-spec Fase 6, «Cámara y sincronía»).
public struct CameraFrame: @unchecked Sendable {
    /// Instante de captura que da la cámara, en segundos de host (`HostClock`).
    public var hostSeconds: Double
    /// Instante de host en que el fotograma llegó a quien lo recibe (diagnóstico: `llegada − marca` es el
    /// retardo de entrega y debe ser positivo y pequeño si la conversión al reloj de host es buena).
    public var arrivalHostSeconds: Double
    /// Número de fotograma de la cámara desde `start` (en la simulada cuenta también los perdidos).
    public var sequence: Int
    /// Imagen (`nil` en los tests que solo miran tiempos).
    public var pixelBuffer: FramePixelBuffer?

    public init(hostSeconds: Double, arrivalHostSeconds: Double, sequence: Int, pixelBuffer: FramePixelBuffer?) {
        self.hostSeconds = hostSeconds
        self.arrivalHostSeconds = arrivalHostSeconds
        self.sequence = sequence
        self.pixelBuffer = pixelBuffer
    }
}

public enum CameraError: Error, Equatable, Sendable {
    case notFound(String)
    case noAccess
    case noFormats(String)
    case configuration(String)
    case alreadyRunning
}

public typealias CameraFrameHandler = @Sendable (CameraFrame) -> Void

/// Captura de una cámara detrás de un protocolo (la real y la simulada).
///
/// Contrato: `start` configura el formato más cercano al pedido, empieza a entregar fotogramas a `onFrame` (en
/// una cola propia, en orden) y devuelve el formato real. `stop` deja de entregarlos antes de volver.
public protocol CameraCapture: AnyObject, Sendable {
    var camera: CameraDevice { get }
    var isRunning: Bool { get }
    /// Fotogramas que la captura dice haber tirado desde `start` (la real: `didDrop`; la simulada: los perdidos).
    var droppedFrames: Int { get }
    func start(_ request: CameraRequest, onFrame: @escaping CameraFrameHandler) throws -> VideoFormat
    func stop()
}

// MARK: - Real

#if canImport(AVFoundation)
/// Captura real con `AVCaptureSession` + `AVCaptureVideoDataOutput`.
///
/// **Marcas.** El `presentationTimeStamp` de cada `CMSampleBuffer` está en el reloj de sincronización de la sesión
/// (`synchronizationClock`); se pasa al reloj de host con `CMSyncConvertTime` y de ahí a segundos con
/// `HostClock.seconds(hostTime:)`, la misma escala que `AudioIOBuffer.hostSeconds`. `arrivalHostSeconds` (la hora
/// de host al entrar en el delegado) permite comprobarlo con hardware: `tf-video sync` da el retardo de entrega.
///
/// **Vista previa.** `session` es para un `AVCaptureVideoPreviewLayer` de la app (sin SwiftUI aquí).
/// `alwaysDiscardsLateVideoFrames = false`: al grabar se prefiere encolar a tirar.
public final class AVCameraCapture: NSObject, CameraCapture, @unchecked Sendable {
    public let camera: CameraDevice
    public let session = AVCaptureSession()
    private let device: AVCaptureDevice
    private let queue = DispatchQueue(label: "ToneForge.AVCameraCapture", qos: .userInteractive)
    private let output = AVCaptureVideoDataOutput()
    private let lock = NSLock()
    private var handler: CameraFrameHandler?
    private var running = false
    private var sequence = 0
    private var dropped = 0

    public init(cameraID: String) throws {
        guard let d = AVCaptureDevice(uniqueID: cameraID) else { throw CameraError.notFound(cameraID) }
        device = d
        camera = AVCameraProvider.describe(d)
        super.init()
    }

    public var isRunning: Bool { lock.withLock { running } }
    public var droppedFrames: Int { lock.withLock { dropped } }

    public func start(_ request: CameraRequest, onFrame: @escaping CameraFrameHandler) throws -> VideoFormat {
        guard !isRunning else { throw CameraError.alreadyRunning }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { throw CameraError.noAccess }
        guard let (format, fps) = camera.closestFormat(to: request), format.index >= 0,
              format.index < device.formats.count else { throw CameraError.noFormats(camera.id) }
        // La configuración se cierra antes de `startRunning()`: llamarlo entre begin y commit lanza una excepción.
        do {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        let input: AVCaptureDeviceInput
        do { input = try AVCaptureDeviceInput(device: device) } catch { throw CameraError.configuration("\(error)") }
        guard session.canAddInput(input) else { throw CameraError.configuration("no se puede añadir la entrada") }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = false
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CameraError.configuration("no se puede añadir la salida") }
        session.addOutput(output)
        // El formato se fija con la entrada ya en la sesión (si no, el preajuste de la sesión lo pisa).
        do {
            try device.lockForConfiguration()
            device.activeFormat = device.formats[format.index]
            let duration = Self.frameDuration(fps: fps, in: device.activeFormat)
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch { throw CameraError.configuration("\(error)") }
        }
        let realFPS = 1 / CMTimeGetSeconds(device.activeVideoMinFrameDuration)
        lock.withLock {
            handler = onFrame
            sequence = 0
            dropped = 0
            running = true
        }
        session.startRunning()
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        return VideoFormat(cameraID: camera.id, cameraName: camera.name, width: Int(dims.width), height: Int(dims.height),
                           fps: realFPS.isFinite ? realFPS : fps)
    }

    /// Duración de fotograma para `fps`: la exacta del rango que lo contiene si es fijo (evita que 29,97 o 30 se
    /// redondeen mal); si no, 1/fps con escala de µs.
    static func frameDuration(fps: Double, in format: AVCaptureDevice.Format) -> CMTime {
        for r in format.videoSupportedFrameRateRanges where fps >= r.minFrameRate - 1e-6 && fps <= r.maxFrameRate + 1e-6 {
            if abs(r.maxFrameRate - fps) < 1e-3 { return r.minFrameDuration }
            if abs(r.minFrameRate - fps) < 1e-3 { return r.maxFrameDuration }
        }
        return CMTime(seconds: 1 / fps, preferredTimescale: 1_000_000)
    }

    public func stop() {
        guard lock.withLock({ () -> Bool in
            defer { running = false; handler = nil }
            return running
        }) else { return }
        session.stopRunning()
        queue.sync {}
    }

    /// Marca de un `CMSampleBuffer` en segundos de host.
    func hostSeconds(of sample: CMSampleBuffer) -> Double {
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let host = CMClockGetHostTimeClock()
        let converted = session.synchronizationClock.map { CMSyncConvertTime(pts, from: $0, to: host) } ?? pts
        return HostClock.seconds(hostTime: converted)
    }
}

extension AVCameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let arrival = HostClock.nowSeconds
        let (h, seq) = lock.withLock { () -> (CameraFrameHandler?, Int) in
            defer { sequence += 1 }
            return (handler, sequence)
        }
        guard let h else { return }
        h(CameraFrame(hostSeconds: hostSeconds(of: sampleBuffer), arrivalHostSeconds: arrival, sequence: seq,
                      pixelBuffer: CMSampleBufferGetImageBuffer(sampleBuffer)))
    }

    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.withLock {
            dropped += 1
            sequence += 1
        }
    }
}
#endif

// MARK: - Simulada

/// Cámara simulada (mini-spec Fase 6, «Pruebas»): fotogramas a `fps` exactos de un reloj de captura verdadero,
/// marcados con un retardo conocido y un jitter uniforme de ±`jitterSeconds`, con fotogramas perdidos.
///
/// El fotograma `k` se captura de verdad en `origin + k/fps` (`trueCaptureHostSeconds`) y se marca en
/// `verdad + delaySeconds + jitter_k`. Un retardo positivo es una imagen que llega tarde: el desfase manual
/// que la corrige es `+delaySeconds` (mismo signo que `videoOffset`).
///
/// Dos modos: manual (`advance(toHostSeconds:)` entrega lo capturado hasta ese instante; con el audio simulado,
/// que corre más rápido que el tiempo real) y automático (`automatic: true`: un temporizador entrega a ritmo real
/// con el reloj de host del Mac, para la app sin cámara).
public final class SimulatedCameraCapture: CameraCapture, @unchecked Sendable {
    public struct Config: Sendable, Equatable {
        /// Retardo de la marca frente al instante verdadero (positivo: la imagen llega tarde).
        public var delaySeconds: Double
        /// Jitter uniforme de la marca, ±.
        public var jitterSeconds: Double
        /// Se pierde uno de cada `dropEvery` fotogramas (`nil`: ninguno).
        public var dropEvery: Int?
        /// Fotogramas concretos perdidos.
        public var dropFrames: Set<Int>
        /// Color de la imagen (BGRA) si `pixels`; sin imagen si `false`.
        public var pixels: Bool
        public var color: (b: UInt8, g: UInt8, r: UInt8)
        public var seed: UInt64

        public init(delaySeconds: Double = 0.040, jitterSeconds: Double = 0.002, dropEvery: Int? = nil,
                    dropFrames: Set<Int> = [], pixels: Bool = false, color: (b: UInt8, g: UInt8, r: UInt8) = (40, 40, 200),
                    seed: UInt64 = 1) {
            self.delaySeconds = delaySeconds
            self.jitterSeconds = jitterSeconds
            self.dropEvery = dropEvery
            self.dropFrames = dropFrames
            self.pixels = pixels
            self.color = color
            self.seed = seed
        }

        public static func == (a: Config, b: Config) -> Bool {
            a.delaySeconds == b.delaySeconds && a.jitterSeconds == b.jitterSeconds && a.dropEvery == b.dropEvery
                && a.dropFrames == b.dropFrames && a.pixels == b.pixels && a.color == b.color && a.seed == b.seed
        }
    }

    public let camera: CameraDevice
    public let config: Config
    public let automatic: Bool
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "ToneForge.SimulatedCameraCapture", qos: .userInteractive)
    private var handler: CameraFrameHandler?
    private var running = false
    private var origin = 0.0
    private var fps = 30.0
    private var next = 0
    private var dropped = 0
    private var timer: (any DispatchSourceTimer)?
    #if canImport(CoreVideo)
    private var pool: CVPixelBufferPool?
    #else
    private var pixelSize: (Int, Int)?
    #endif

    /// `originHostSeconds`: instante verdadero del fotograma 0 en modo manual (en automático, la hora de `start`).
    public init(camera: CameraDevice = .simulated, config: Config = Config(), automatic: Bool = false,
                originHostSeconds: Double = 0) {
        self.camera = camera
        self.config = config
        self.automatic = automatic
        origin = originHostSeconds
    }

    public var isRunning: Bool { lock.withLock { running } }
    public var droppedFrames: Int { lock.withLock { dropped } }

    /// Instante verdadero de captura del fotograma `k`.
    public func trueCaptureHostSeconds(ofFrame k: Int) -> Double { lock.withLock { origin + Double(k) / fps } }

    /// Marca que lleva el fotograma `k` (verdad + retardo + jitter).
    public func stampHostSeconds(ofFrame k: Int) -> Double {
        trueCaptureHostSeconds(ofFrame: k) + config.delaySeconds + jitter(k)
    }

    /// Si el fotograma `k` se pierde.
    public func isDropped(_ k: Int) -> Bool {
        config.dropFrames.contains(k) || (config.dropEvery.map { $0 > 0 && k % $0 == $0 - 1 } ?? false)
    }

    /// Jitter determinista del fotograma `k`, uniforme en ±`jitterSeconds`.
    func jitter(_ k: Int) -> Double {
        var z = config.seed &+ UInt64(truncatingIfNeeded: k) &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        let u = Double(z >> 11) / Double(1 << 53)
        return (2 * u - 1) * config.jitterSeconds
    }

    public func start(_ request: CameraRequest, onFrame: @escaping CameraFrameHandler) throws -> VideoFormat {
        guard let (format, rate) = camera.closestFormat(to: request) else { throw CameraError.noFormats(camera.id) }
        try lock.withLock {
            guard !running else { throw CameraError.alreadyRunning }
            handler = onFrame
            running = true
            fps = rate
            next = 0
            dropped = 0
            if automatic { origin = HostClock.nowSeconds }
            #if canImport(CoreVideo)
            pool = nil
            #else
            pixelSize = nil
            #endif
        }
        if config.pixels { makePool(width: format.width, height: format.height) }
        if automatic {
            let t = DispatchSource.makeTimerSource(queue: queue)
            let ms = max(1, Int(500 / rate))
            t.schedule(deadline: .now(), repeating: .milliseconds(ms), leeway: .milliseconds(1))
            t.setEventHandler { [weak self] in self?.deliver(upTo: HostClock.nowSeconds, arrival: HostClock.nowSeconds) }
            t.resume()
            lock.withLock { timer = t }
        }
        return VideoFormat(cameraID: camera.id, cameraName: camera.name, width: format.width, height: format.height, fps: rate)
    }

    public func stop() {
        let t = lock.withLock { () -> (any DispatchSourceTimer)? in
            running = false
            handler = nil
            defer { timer = nil }
            return timer
        }
        t?.cancel()
        queue.sync {}
    }

    /// Modo manual: entrega, en el hilo que llama, los fotogramas capturados de verdad hasta `h` (marcados como
    /// llegados en `h`).
    public func advance(toHostSeconds h: Double) {
        precondition(!automatic, "SimulatedCameraCapture: advance solo en modo manual")
        deliver(upTo: h, arrival: h)
    }

    private func deliver(upTo h: Double, arrival: Double) {
        while true {
            let step = lock.withLock { () -> (CameraFrameHandler, Int)? in
                guard running, let handler, origin + Double(next) / fps <= h else { return nil }
                defer { next += 1 }
                return (handler, next)
            }
            guard let (handler, k) = step else { return }
            if isDropped(k) {
                lock.withLock { dropped += 1 }
                continue
            }
            handler(CameraFrame(hostSeconds: stampHostSeconds(ofFrame: k), arrivalHostSeconds: arrival, sequence: k,
                                pixelBuffer: config.pixels ? makePixels() : nil))
        }
    }

    #if canImport(CoreVideo)
    private func makePool(width: Int, height: Int) {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        var p: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &p)
        lock.withLock { pool = p }
    }

    private func makePixels() -> CVPixelBuffer? {
        guard let pool = lock.withLock({ pool }) else { return nil }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return pb }
        let rowBytes = CVPixelBufferGetBytesPerRow(pb), h = CVPixelBufferGetHeight(pb), w = CVPixelBufferGetWidth(pb)
        let c = config.color
        for y in 0..<h {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w {
                row[4 * x] = c.b
                row[4 * x + 1] = c.g
                row[4 * x + 2] = c.r
                row[4 * x + 3] = 255
            }
        }
        return pb
    }
    #else
    // Fuera del Mac: un búfer BGRA nuevo por fotograma, del color de la configuración.
    private func makePool(width: Int, height: Int) { lock.withLock { pixelSize = (width, height) } }

    private func makePixels() -> FramePixelBuffer? {
        guard let (w, h) = lock.withLock({ pixelSize }) else { return nil }
        let pb = FramePixelBuffer(pixelFormat: .bgra, width: w, height: h)
        pb.fill(b: config.color.b, g: config.color.g, r: config.color.r)
        return pb
    }
    #endif
}
