#if canImport(CoreVideo)
import CAppCoreFFI
import CoreVideo
import Foundation

// P9 prueba 3: fuente de fotogramas sintética (desvío: no usa la cámara simulada de AppCore; lo que se mide es
// el coste del lado Flutter). CVPixelBuffer 32BGRA con IOSurface, de un pool, generado en un hilo de fondo a fps exactos.

/// Una fuente por canal (0 = camera, 1 = montage; constantes TF_CHANNEL_* de tf_core.h).
final class FrameSource: @unchecked Sendable {
    let channel: Int32
    let width: Int
    let height: Int
    private let fps: Int
    private var pool: CVPixelBufferPool?
    private var timer: DispatchSourceTimer?
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var last: CVPixelBuffer?
    private var lastSeq: Int64 = 0
    private var produced: Int64 = 0
    private var textureCopies: Int64 = 0
    private var distinctCopies: Int64 = 0
    private var lastDelivered: Int64 = 0
    private var bgraCopies: Int64 = 0
    private var costNs: Int64 = 0

    init?(channel: Int32, width: Int, height: Int, fps: Int) {
        guard width >= 16, height >= 2, fps > 0 else { return nil }
        self.channel = channel; self.width = width; self.height = height; self.fps = fps
        queue = DispatchQueue(label: "tf-frames-\(channel)", qos: .userInteractive)
        let poolAttrs: [CFString: Any] = [kCVPixelBufferPoolMinimumBufferCountKey: 4]
        let bufAttrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var p: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(nil, poolAttrs as CFDictionary, bufAttrs as CFDictionary, &p) == kCVReturnSuccess, let p else { return nil }
        pool = p
    }

    func start() {
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        // Temporizador repetitivo con fechas absolutas: sin deriva acumulada.
        t.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / fps), leeway: .nanoseconds(0))
        t.setEventHandler { [self] in produceOne() }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        queue.sync {}  // espera a que termine el fotograma en curso
        lock.lock(); last = nil; lock.unlock()
    }

    private static func tri(_ x: Int) -> UInt32 {  // onda triangular 0...255 con periodo 512
        let v = x & 511
        return UInt32(v < 256 ? v : 511 - v)
    }

    private func produceOne() {
        let t0 = DispatchTime.now().uptimeNanoseconds
        var out: CVPixelBuffer?
        guard let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out) == kCVReturnSuccess, let buf = out else { return }
        let seq = lastSeqUnlocked() + 1
        CVPixelBufferLockBaseAddress(buf, [])
        if let base = CVPixelBufferGetBaseAddress(buf) {
            let stride = CVPixelBufferGetBytesPerRow(buf)
            let s = Int(seq)
            // Fondo de color que rota (relleno de todo el búfer con memset_pattern4).
            let r = Self.tri(s * 3), g = Self.tri(s * 3 + 170), b = Self.tri(s * 3 + 340)
            var bg: UInt32 = b | (g << 8) | (r << 16) | (0xFF << 24)
            memset_pattern4(base, &bg, stride * height)
            // Barra vertical blanca que avanza 1/fps del ancho por fotograma.
            let barW = max(8, width / 64)
            let x = (s * width / fps) % (width - barW)
            var white: UInt32 = 0xFFFF_FFFF
            for row in 0..<height {
                memset_pattern4(base + row * stride + x * 4, &white, barW * 4)
            }
            // Número de secuencia en los 8 primeros píxeles de la fila 0 (un byte por píxel, canal B).
            let row0 = base.assumingMemoryBound(to: UInt8.self)
            for i in 0..<8 {
                row0[i * 4] = UInt8(truncatingIfNeeded: seq >> Int64(8 * i))
                row0[i * 4 + 1] = 0; row0[i * 4 + 2] = 0; row0[i * 4 + 3] = 0xFF
            }
        }
        CVPixelBufferUnlockBaseAddress(buf, [])
        let cost = Int64(DispatchTime.now().uptimeNanoseconds - t0)
        lock.lock()
        last = buf; lastSeq = seq; produced += 1; costNs += cost
        lock.unlock()
        if let id = frameTextures.id(for: channel) { frameTextures.host?.frame_available?(id) }
    }

    private func lastSeqUnlocked() -> Int64 { lock.lock(); defer { lock.unlock() }; return lastSeq }

    /// Camino textura: `CVPixelBufferRef` retenido (+1) del último fotograma.
    func copyForTexture() -> UnsafeMutableRawPointer? {
        lock.lock(); defer { lock.unlock() }
        guard let last else { return nil }
        textureCopies += 1
        if lastSeq != lastDelivered { distinctCopies += 1; lastDelivered = lastSeq }
        return Unmanaged.passRetained(last).toOpaque()
    }

    /// Camino BGRA: -1 no cabe; 0 sin fotograma nuevo; si no, bytes escritos.
    func copyBGRA(dst: UnsafeMutablePointer<UInt8>, capacity: Int, seqInOut: UnsafeMutablePointer<Int64>?) -> Int {
        lock.lock()
        let buf = last; let seq = lastSeq
        lock.unlock()
        guard let buf else { return 0 }
        if let seqInOut, seq <= seqInOut.pointee { return 0 }
        let need = width * height * 4
        if capacity < need { return -1 }
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        if let base = CVPixelBufferGetBaseAddress(buf) {
            let stride = CVPixelBufferGetBytesPerRow(buf)
            for row in 0..<height { memcpy(dst + row * width * 4, base + row * stride, width * 4) }
        }
        CVPixelBufferUnlockBaseAddress(buf, .readOnly)
        lock.lock(); bgraCopies += 1; lock.unlock()
        seqInOut?.pointee = seq
        return need
    }

    func extra() -> [Int64]? { nil }  // P9.7f-B: solo Windows
    func resetWindow() {}

    func stats() -> (Int64, Int64, Int64, Int64, Int64) {
        lock.lock(); defer { lock.unlock() }
        return (produced, textureCopies, distinctCopies, bgraCopies, produced > 0 ? costNs / produced / 1000 : 0)
    }
}

#endif
