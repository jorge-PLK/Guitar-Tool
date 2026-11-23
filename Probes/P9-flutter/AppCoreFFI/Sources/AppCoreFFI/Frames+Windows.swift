#if os(Windows)
import CAppCoreFFI
import Foundation

// P9.7f-A: fuente de fotogramas sintética en Windows (mismo generador que Frames.swift, sin CoreVideo).
// Último fotograma = bytes BGRA compactos + secuencia. Camino `gpu`: el productor sube cada fotograma a la textura
// D3D11 compartida (tf_d3d.c) solo después de que el runner haya pedido `tf_frame_copy` al menos una vez (el camino
// `pixel` no llama a tf_frame_copy, así que no paga D3D).
//
// TF_P9_SOLID=1: fotograma rojo puro opaco (B=0,G=0,R=255,A=255) con un cuadrado azul puro de 200x200 arriba a la
// izquierda, para comprobar el orden de canales. Sin barra ni número de secuencia.

private let solidSquare = 200

// P9.7f-B: umbrales de la atribución de descartes (intervalos en µs).
private let shortIntervalUs: Int64 = 8_000    // dos fotogramas casi seguidos (cadencia del generador)
private let longIntervalUs: Int64 = 50_000    // hueco largo
private let lateFetchUs: Int64 = 40_000       // petición tardía del motor (>1,2 periodos a 30 fps)

/// Intervalos entre eventos sucesivos, en µs.
private struct Intervals {
    var v: [Int64] = []
    var lastNs: Int64 = 0
    mutating func tick(_ nowNs: Int64) -> Int64 {
        defer { lastNs = nowNs }
        guard lastNs != 0 else { return 0 }
        let d = (nowNs - lastNs) / 1000
        v.append(d)
        return d
    }
    mutating func reset() { v.removeAll(keepingCapacity: true) }
    /// [cuenta, min, p50, p99, max, <8 ms, >50 ms]
    func summary() -> [Int64] {
        guard !v.isEmpty else { return [0, 0, 0, 0, 0, 0, 0] }
        let s = v.sorted()
        func q(_ p: Double) -> Int64 { s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))] }
        return [Int64(s.count), s[0], q(0.5), q(0.99), s[s.count - 1],
                Int64(s.filter { $0 < shortIntervalUs }.count), Int64(s.filter { $0 > longIntervalUs }.count)]
    }
}

final class FrameSource: @unchecked Sendable {
    let channel: Int32
    let width: Int
    let height: Int
    private let fps: Int
    private let solid: Bool
    private var timer: DispatchSourceTimer?
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var work: UnsafeMutablePointer<UInt32>  // lo escribe el hilo productor; se intercambia con `last` bajo lock
    private var last: UnsafeMutablePointer<UInt32>  // bajo lock
    private var haveLast = false
    private var lastSeq: Int64 = 0
    private var produced: Int64 = 0
    private var textureCopies: Int64 = 0
    private var distinctCopies: Int64 = 0
    private var lastDelivered: Int64 = 0
    private var bgraCopies: Int64 = 0
    private var costNs: Int64 = 0
    private var wantGPU = false
    private var uploadedSeq: Int64 = 0
    // P9.7f-B
    private let precise: Bool  // TF_P9_PRECISE=1: hilo propio con temporizador de espera de alta resolución
    private var running = false
    private let exited = DispatchSemaphore(value: 0)
    private var prodIv = Intervals()
    private var fetchIv = Intervals()
    private var bgraDistinct: Int64 = 0
    private var bgraLastDelivered: Int64 = 0
    private var fetches: Int64 = 0, repeatFetches: Int64 = 0, gapFetches: Int64 = 0
    private var skippedSeqs: Int64 = 0, lateGapFetches: Int64 = 0

    init?(channel: Int32, width: Int, height: Int, fps: Int) {
        guard width >= 16, height >= 2, fps > 0 else { return nil }
        self.channel = channel; self.width = width; self.height = height; self.fps = fps
        solid = getenv("TF_P9_SOLID").map { String(cString: $0) == "1" } ?? false
        precise = getenv("TF_P9_PRECISE").map { String(cString: $0) == "1" } ?? false
        queue = DispatchQueue(label: "tf-frames-\(channel)", qos: .userInteractive)
        work = .allocate(capacity: width * height)
        last = .allocate(capacity: width * height)
        work.initialize(repeating: 0, count: width * height)
        last.initialize(repeating: 0, count: width * height)
    }

    deinit {
        work.deallocate()
        last.deallocate()
    }

    func start() {
        if precise {
            running = true
            let period = Int64(1_000_000_000 / fps)
            let th = Thread { [self] in
                var next = Int64(DispatchTime.now().uptimeNanoseconds)
                while true {
                    lock.lock(); let go = running; lock.unlock()
                    if !go { break }
                    produceOne()
                    next += period
                    let now = Int64(DispatchTime.now().uptimeNanoseconds)
                    if next <= now { next = now }  // atrasado: sin ráfaga de recuperación
                    _ = tf_hr_sleep_ns(next - now)
                }
                exited.signal()
            }
            th.qualityOfService = .userInteractive
            th.start()
            return
        }
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / fps), leeway: .nanoseconds(0))
        t.setEventHandler { [self] in produceOne() }
        timer = t
        t.resume()
    }

    func stop() {
        if precise {
            lock.lock(); let was = running; running = false; lock.unlock()
            if was { exited.wait() }
            lock.lock(); haveLast = false; lock.unlock()
            return
        }
        timer?.cancel()
        timer = nil
        queue.sync {}  // espera a que termine el fotograma en curso
        lock.lock(); haveLast = false; lock.unlock()
    }

    private static func tri(_ x: Int) -> UInt32 {  // onda triangular 0...255 con periodo 512
        let v = x & 511
        return UInt32(v < 256 ? v : 511 - v)
    }

    private func fill(seq: Int64) {
        // Píxel BGRA en memoria little-endian = UInt32 0xAARRGGBB.
        if solid {
            let red: UInt32 = 0xFFFF_0000, blue: UInt32 = 0xFF00_00FF
            work.update(repeating: red, count: width * height)
            for row in 0..<min(solidSquare, height) {
                (work + row * width).update(repeating: blue, count: min(solidSquare, width))
            }
            return
        }
        let s = Int(seq)
        let r = Self.tri(s * 3), g = Self.tri(s * 3 + 170), b = Self.tri(s * 3 + 340)
        let bg: UInt32 = b | (g << 8) | (r << 16) | (0xFF << 24)
        work.update(repeating: bg, count: width)
        for row in 1..<height { memcpy(work + row * width, work, width * 4) }
        // Barra vertical blanca que avanza 1/fps del ancho por fotograma.
        let barW = max(8, width / 64)
        let x = (s * width / fps) % (width - barW)
        for row in 0..<height { (work + row * width + x).update(repeating: 0xFFFF_FFFF, count: barW) }
        // Número de secuencia en los 8 primeros píxeles de la fila 0 (un byte por píxel, canal B).
        for i in 0..<8 {
            let byte = UInt32(UInt8(truncatingIfNeeded: seq >> Int64(8 * i)))
            work[i] = byte | (0xFF << 24)
        }
    }

    private func produceOne() {
        let t0 = DispatchTime.now().uptimeNanoseconds
        lock.lock(); let seq = lastSeq + 1; let gpu = wantGPU; lock.unlock()
        fill(seq: seq)
        let cost = Int64(DispatchTime.now().uptimeNanoseconds - t0)
        var uploaded = false
        if gpu {
            work.withMemoryRebound(to: UInt8.self, capacity: width * height * 4) { p in
                uploaded = tf_d3d_upload(channel, p, Int32(width), Int32(height)) == 0
            }
        }
        lock.lock()
        swap(&work, &last)  // doble búfer: `last` pasa a ser el recién generado
        haveLast = true; lastSeq = seq; produced += 1; costNs += cost
        _ = prodIv.tick(Int64(t0))
        if uploaded { uploadedSeq = seq }
        lock.unlock()
        if let id = frameTextures.id(for: channel) { frameTextures.host?.frame_available?(id) }
    }

    /// Camino textura (gpu): HANDLE compartido D3D11 del último fotograma subido, o nil si aún no hay.
    /// La primera llamada activa la subida (el camino pixel nunca la llama).
    func copyForTexture() -> UnsafeMutableRawPointer? {
        lock.lock(); defer { lock.unlock() }
        wantGPU = true
        noteFetch(delivered: uploadedSeq, previous: lastDelivered)
        guard uploadedSeq > 0, let h = tf_d3d_handle(channel) else { return nil }
        textureCopies += 1
        if uploadedSeq != lastDelivered { distinctCopies += 1; lastDelivered = uploadedSeq }
        return h
    }

    /// Camino BGRA: -1 no cabe; 0 sin fotograma nuevo; si no, bytes escritos.
    func copyBGRA(dst: UnsafeMutablePointer<UInt8>, capacity: Int, seqInOut: UnsafeMutablePointer<Int64>?) -> Int {
        lock.lock(); defer { lock.unlock() }
        guard haveLast else { return 0 }
        noteFetch(delivered: lastSeq, previous: bgraLastDelivered)
        if let seqInOut, lastSeq <= seqInOut.pointee { return 0 }
        let need = width * height * 4
        if capacity < need { return -1 }
        memcpy(dst, last, need)
        bgraCopies += 1
        if lastSeq > bgraLastDelivered { bgraDistinct += 1; bgraLastDelivered = lastSeq }
        seqInOut?.pointee = lastSeq
        return need
    }

    /// Bajo lock. Una petición del motor (o de Dart en bgra): ¿sirvió una secuencia nueva, repetida o con huecos?
    private func noteFetch(delivered: Int64, previous: Int64) {
        let iv = fetchIv.tick(Int64(DispatchTime.now().uptimeNanoseconds))
        fetches += 1
        if delivered == previous { repeatFetches += 1; return }
        let gap = previous > 0 ? delivered - previous - 1 : 0
        if gap > 0 {
            gapFetches += 1; skippedSeqs += gap
            if iv > lateFetchUs { lateGapFetches += 1 }
        }
    }

    func resetWindow() {
        lock.lock(); defer { lock.unlock() }
        prodIv.reset(); fetchIv.reset()
        fetches = 0; repeatFetches = 0; gapFetches = 0; skippedSeqs = 0; lateGapFetches = 0
    }

    func extra() -> [Int64]? {
        lock.lock(); defer { lock.unlock() }
        return [bgraDistinct, fetches, repeatFetches, gapFetches, skippedSeqs, lateGapFetches]
            + prodIv.summary() + fetchIv.summary()
    }

    func stats() -> (Int64, Int64, Int64, Int64, Int64) {
        lock.lock(); defer { lock.unlock() }
        return (produced, textureCopies, distinctCopies, bgraCopies, produced > 0 ? costNs / produced / 1000 : 0)
    }
}
#endif
