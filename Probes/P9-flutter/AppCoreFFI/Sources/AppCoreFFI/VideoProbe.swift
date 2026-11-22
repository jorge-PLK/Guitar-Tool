#if canImport(AVFoundation)
import AVFoundation
import CAppCoreFFI
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

// P9.5b prueba 5, candidata nativa: AVPlayer sin audio, esclavo de un reloj `takeview.position`
// {seconds, playing, at, epoch, rate}; pos(t) = seconds + (t - at)*rate si playing. Entrega CVPixelBuffer por el canal de
// textura (tf_frame_copy) y mide dentro de Swift el error A/V con el índice de fotograma incrustado en los vídeos de prueba.

/// Tolerancia: medio fotograma a 30000/1001 fps (arquitectura.md, «Vídeo de tomas»).
private let frameDuration = 1001.0 / 30000.0
private let halfFrame = frameDuration / 2
/// Periodo del temporizador interno (aviso de fotograma nuevo y comprobación de bucle).
private let tickSeconds = 0.008
/// El reloj sintético reemite como `takeview.position`: 30 Hz.
private let clockEmitSeconds = 1.0 / 30.0
/// Margen entre «ahora» y el arranque de la reproducción tras un salto (setRate atHostTime).
private let startLeadSeconds = 0.03
/// Tras resincronizar no se comprueba la deriva durante este tiempo.
private let driftGraceSeconds = 0.4

private func hostNow() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

final class VideoProbe: @unchecked Sendable {
    let channel: Int32
    private let player = AVPlayer()
    private let item: AVPlayerItem
    private let output: AVPlayerItemVideoOutput
    private let queue = DispatchQueue(label: "tf-video", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()

    // Info del fichero.
    private(set) var infoJSON = "{}"
    private var startPts = 0.0
    private var duration = 0.0

    // Reloj sintético (bajo lock).
    private var cSeconds = 0.0, cAt = 0.0, cRate = 1.0, cPlaying = false, cEpoch = 0
    private var loopStart = 0.0, loopEnd = 0.0, loopOn = false
    private var applied: (playing: Bool, rate: Double, epoch: Int)?
    private var lastEmit = 0.0
    private var graceUntil = 0.0
    private var gen = 0

    // Entrega y medidas (bajo lock).
    private var last: CVPixelBuffer?
    private var notified = false
    private var t0 = hostNow()
    private var samples: [(t: Double, e: Double?, n: Int, item: Double, epoch: Int)] = []
    private var events: [(t: Double, kind: String)] = []
    private var resyncs = 0, driftResyncs = 0, calls = 0, deliveries = 0, unreadable = 0

    /// Apertura asíncrona (el hilo que llama nunca espera): 0 abriendo, 1 listo, 2 fallo. Bajo lock.
    private var openState: Int32 = 0
    private var failReason = ""
    private var stopped = false
    private let asset: AVURLAsset

    var state: Int32 { lock.lock(); defer { lock.unlock() }; return openState }
    /// nil mientras abre; JSON con la info al estar listo; `{"error":...}` si falló.
    var infoOrNil: String? {
        lock.lock(); defer { lock.unlock() }
        switch openState {
        case 1: return infoJSON
        case 2: return "{\"error\":\"" + failReason.replacingOccurrences(of: "\"", with: "'") + "\"}"
        default: return nil
        }
    }

    init(channel: Int32, path: String) {
        self.channel = channel
        asset = AVURLAsset(url: URL(fileURLWithPath: path))
        item = AVPlayerItem(asset: asset)
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
        item.add(output)
        player.replaceCurrentItem(with: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.isMuted = true
        Task { [self] in await openAsync() }
    }

    private func fail(_ why: String) {
        lock.lock(); openState = 2; failReason = why; lock.unlock()
    }

    private func openAsync() async {
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { return fail("sin pista de vídeo") }
            let dur = try await asset.load(.duration).seconds
            let segments = try await track.load(.segments)
            let tr = try await track.load(.preferredTransform)
            let sz = try await track.load(.naturalSize)
            let fps = try await track.load(.nominalFrameRate)
            let fds = try await track.load(.formatDescriptions)
            // El reloj de la toma va de 0 a la duración; el PTS inicial del fichero se suma aquí.
            // La toma real trae una edición vacía inicial (155,547 s) y el item no muestra nada hasta ahí: el desplazamiento
            // es el inicio en la línea de tiempo del item del primer segmento no vacío, menos su inicio en el medio.
            var pts = 0.0
            if let seg = segments.first(where: { !$0.isEmpty }) {
                pts = max(0, seg.timeMapping.target.start.seconds - seg.timeMapping.source.start.seconds)
            }
            var rot = Int((atan2(Double(tr.b), Double(tr.a)) * 180 / .pi).rounded())
            if rot < 0 { rot += 360 }
            let swap = rot == 90 || rot == 270
            var hw = false
            if let fd = fds.first { hw = VTIsHardwareDecodeSupported(CMFormatDescriptionGetMediaSubType(fd)) }
            // setRate(atHostTime:) exige el item listo (sondeo con sleep async: no bloquea ningún hilo).
            let deadline = Date().addingTimeInterval(5)
            while item.status == .unknown, Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
            finishOpen(pts: pts, dur: dur, rot: rot, sz: sz, swap: swap, fps: fps, hw: hw)
        } catch {
            fail("\(error.localizedDescription)")
        }
    }

    private func finishOpen(pts: Double, dur: Double, rot: Int, sz: CGSize, swap: Bool, fps: Float, hw: Bool) {
        guard item.status == .readyToPlay else {
            return fail("item no listo: \(item.error?.localizedDescription ?? "status \(item.status.rawValue)")")
        }
        lock.lock()
        if stopped { lock.unlock(); return }
        startPts = pts
        duration = dur - pts
        infoJSON = String(format: "{\"width\":%d,\"height\":%d,\"displayWidth\":%d,\"displayHeight\":%d,\"rotationDegrees\":%d,\"fps\":%.4f,\"duration\":%.4f,\"startPts\":%.4f,\"hardwareDecode\":%@}",
                          Int(sz.width), Int(sz.height), Int(swap ? sz.height : sz.width), Int(swap ? sz.width : sz.height),
                          rot, Double(fps), duration, pts, hw ? "true" : "false")
        openState = 1
        lock.unlock()
        // setClock/setLoop anteriores quedaron guardados: se aplican aquí.
        resync(reason: "open", drift: false)
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(deadline: .now(), repeating: .nanoseconds(Int(tickSeconds * 1e9)), leeway: .nanoseconds(0))
        t.setEventHandler { [self] in tick() }
        lock.lock(); timer = t; lock.unlock()
        t.resume()
    }

    func stop() {
        lock.lock(); stopped = true; let t = timer; timer = nil; lock.unlock()
        t?.cancel()
        queue.sync {}
        player.pause()
        player.replaceCurrentItem(with: nil)
        lock.lock(); last = nil; lock.unlock()
    }

    // MARK: reloj

    private func pos(_ t: Double) -> Double {  // lock tomado
        cPlaying ? cSeconds + (t - cAt) * cRate : cSeconds
    }

    func setClock(seconds: Double, rate: Double, playing: Bool, jump: Bool) {
        lock.lock()
        cSeconds = seconds; cAt = hostNow(); cRate = rate; cPlaying = playing
        if jump { cEpoch += 1 }
        lastEmit = cAt
        lock.unlock()
        publish()
    }

    func setLoop(start: Double, end: Double, enabled: Bool) {
        lock.lock(); loopStart = start; loopEnd = end; loopOn = enabled; lock.unlock()
    }

    /// Como `takeview.position`: se aplica al reproductor solo si cambia playing/rate/epoch; deriva > medio fotograma también.
    private func publish() {
        lock.lock()
        if openState != 1 { lock.unlock(); return }
        let cur = (playing: cPlaying, rate: cRate, epoch: cEpoch)
        let changed = applied == nil || applied! != cur
        lock.unlock()
        if changed { resync(reason: "clock", drift: false) }
    }

    private func resync(reason: String, drift: Bool) {
        lock.lock()
        gen += 1
        let g = gen
        resyncs += 1
        if drift { driftResyncs += 1 }
        applied = (cPlaying, cRate, cEpoch)
        let now = hostNow()
        events.append((now - t0, reason))
        let playing = cPlaying, rate = cRate
        let target = pos(now)
        graceUntil = now + driftGraceSeconds
        lock.unlock()
        let cm: (Double) -> CMTime = { CMTime(seconds: $0 + self.startPts, preferredTimescale: 600_000) }
        if !playing {
            player.pause()
            player.seek(to: cm(max(0, target)), toleranceBefore: .zero, toleranceAfter: .zero)
            return
        }
        player.seek(to: cm(max(0, target)), toleranceBefore: .zero, toleranceAfter: .zero) { [self] finished in
            guard finished else { return }
            lock.lock(); let stale = g != gen; lock.unlock()
            if stale { return }
            // Arranca en el futuro cercano, en el punto que marque el reloj entonces.
            lock.lock()
            let h = hostNow() + startLeadSeconds
            let p = pos(h)
            events.append((hostNow() - t0, "seekDone"))
            lock.unlock()
            player.setRate(Float(rate), time: cm(max(0, p)), atHostTime: CMTime(seconds: h, preferredTimescale: 1_000_000_000))
        }
    }

    private func tick() {
        let now = hostNow()
        lock.lock()
        // Bucle: el reloj vuelve a start al llegar a end (salto con epoch).
        if loopOn, cPlaying, pos(now) >= loopEnd {
            cSeconds = loopStart; cAt = now; cEpoch += 1; lastEmit = now
            lock.unlock(); publish(); lock.lock()
        } else if now - lastEmit >= clockEmitSeconds {
            lastEmit = now
            let playing = cPlaying, p = pos(now), grace = graceUntil
            lock.unlock()
            publish()
            if playing, now > grace {
                let d = player.currentTime().seconds - startPts - p
                if abs(d) > halfFrame { resync(reason: "drift", drift: true) }
            }
            lock.lock()
        }
        let already = notified
        lock.unlock()
        if !already {
            let it = output.itemTime(forHostTime: now)
            if output.hasNewPixelBuffer(forItemTime: it) {
                lock.lock(); notified = true; lock.unlock()
                if let id = frameTextures.id(for: channel) { frameTextures.host?.frame_available?(id) }
            }
        }
    }

    // MARK: entrega

    /// `tf_frame_copy`: pide el fotograma para «ahora»; si no hay nuevo devuelve el último (+1).
    func copyForTexture() -> UnsafeMutableRawPointer? {
        let now = hostNow()
        let it = output.itemTime(forHostTime: now)
        var display = CMTime.invalid
        let fresh = output.hasNewPixelBuffer(forItemTime: it) ? output.copyPixelBuffer(forItemTime: it, itemTimeForDisplay: &display) : nil
        lock.lock(); defer { lock.unlock() }
        calls += 1
        notified = false
        if let fresh {
            last = fresh
            deliveries += 1
            let n = Self.frameIndex(fresh)
            if n < 0 { unreadable += 1 }
            let e: Double? = n >= 0 ? pos(now) - Double(n) * frameDuration : nil
            samples.append((now - t0, e, n, display.isValid ? display.seconds - startPts : it.seconds - startPts, cEpoch))
        }
        guard let last else { return nil }
        return Unmanaged.passRetained(last).toOpaque()
    }

    /// Índice de fotograma de los vídeos de prueba: 12 bloques de 64x64 arriba a la izquierda; referencias en los bloques 12 (blanco) y 13 (negro).
    private static func frameIndex(_ buf: CVPixelBuffer) -> Int {
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(buf) == kCVPixelFormatType_32BGRA,
              CVPixelBufferGetWidth(buf) >= 896, CVPixelBufferGetHeight(buf) >= 64,
              let base = CVPixelBufferGetBaseAddress(buf) else { return -1 }
        let stride = CVPixelBufferGetBytesPerRow(buf)
        func g(_ k: Int) -> Int { Int(base.load(fromByteOffset: 32 * stride + (64 * k + 32) * 4 + 1, as: UInt8.self)) }
        let w = g(12), b = g(13)
        guard w - b > 100 else { return -1 }
        let thr = (w + b) / 2
        var n = 0
        for k in 0..<12 where g(k) > thr { n |= 1 << k }
        return n
    }

    func statsJSON(reset: Bool) -> String {
        lock.lock(); defer { lock.unlock() }
        var s = "{\"resyncs\":\(resyncs),\"driftResyncs\":\(driftResyncs),\"calls\":\(calls),\"deliveries\":\(deliveries),\"unreadable\":\(unreadable),\"samples\":["
        s += samples.map { x in
            String(format: "[%.2f,%@,%d,%.4f,%d]", x.t * 1000, x.e.map { String(format: "%.2f", $0 * 1000) } ?? "null", x.n, x.item, x.epoch)
        }.joined(separator: ",")
        s += "],\"events\":["
        s += events.map { String(format: "[%.2f,\"%@\"]", $0.t * 1000, $0.kind) }.joined(separator: ",")
        s += "]}"
        if reset {
            samples = []; events = []; resyncs = 0; driftResyncs = 0; calls = 0; deliveries = 0; unreadable = 0
            t0 = hostNow()
        }
        return s
    }
}

final class VideoProbes: @unchecked Sendable {
    private let lock = NSLock()
    private var map: [Int32: VideoProbe] = [:]
    func get(_ ch: Int32) -> VideoProbe? { lock.lock(); defer { lock.unlock() }; return map[ch] }
    func replace(_ ch: Int32, with p: VideoProbe?) -> VideoProbe? {
        lock.lock(); defer { lock.unlock() }
        let old = map[ch]; map[ch] = p; return old
    }
}

let videoProbes = VideoProbes()
#endif
