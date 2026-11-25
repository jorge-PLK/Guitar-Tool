#if canImport(AVFoundation)
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import VideoKit

// Reproductor nativo del vídeo de las tomas (ola 3.3.AS; arquitectura.md, «Vídeo de tomas», ADR-021 decisión 9). El audio suena
// en el núcleo y el vídeo va en silencio, esclavo del reloj de `takeview.position {seconds, playing, at, epoch, rate}`.
// Portado de `Probes/P9-flutter/AppCoreFFI/Sources/AppCoreFFI/VideoProbe.swift` (P9 prueba 5): `AVPlayer` con
// `setRate(_:time:atHostTime:)` y `AVPlayerItemVideoOutput` → `CVPixelBuffer` BGRA, que el canal de textura `take` pide con
// `copyFrame()` en cada `tf_frame_copy`.
//
// La imagen sale de `TakePreview.composition(videoOffset:)`: tiempo 0 = inicio de la toma (la edición vacía inicial del
// fichero, los punches y los tramos sin imagen ya vienen resueltos). Los píxeles salen sin girar: el giro lo aplica Dart con
// `videoRotation` (el núcleo lo publica en `takeview.open`), así que aquí no se gira.

/// Mapa reloj → tiempo de vídeo (puro, para tests): `pos(t) = seconds + (t − at)·rate` si suena.
struct TakeVideoClockMap: Equatable, Sendable {
    var seconds = 0.0
    /// Reloj de host (s) en que `seconds` era cierto.
    var at = 0.0
    var rate = 1.0
    var playing = false
    var epoch = 0

    init() {}

    /// `takeview.position`: `rate` 0 con `playing` = esperando la primera muestra (el vídeo espera).
    init(_ e: TakeViewPositionEvent) {
        seconds = e.seconds; at = e.at; rate = e.rate; playing = e.playing; epoch = e.epoch
    }

    var moving: Bool { playing && rate > 0 }

    func position(at t: Double) -> Double { moving ? seconds + (t - at) * rate : seconds }

    /// Cambios que obligan a resincronizar el reproductor (los demás eventos solo refrescan el reloj).
    func needsResync(from old: TakeVideoClockMap?) -> Bool {
        guard let old else { return true }
        return old.moving != moving || old.rate != rate || old.epoch != epoch
    }
}

enum TakeVideoConstants {
    /// Tolerancia: medio fotograma a 30000/1001 fps (arquitectura.md, «Vídeo de tomas»; umbrales P9).
    static let frameDuration = 1001.0 / 30000.0
    static let halfFrame = frameDuration / 2
    /// Periodo del temporizador interno (aviso de fotograma nuevo y vigilante de deriva).
    static let tickSeconds = 0.008
    /// Comprobación de deriva a 30 Hz, como el reloj publicado.
    static let driftCheckSeconds = 1.0 / 30.0
    /// Margen entre «ahora» y el arranque tras un salto (`setRate(atHostTime:)`).
    static let startLeadSeconds = 0.03
    /// Tras resincronizar no se comprueba la deriva durante este tiempo.
    static let driftGraceSeconds = 0.4
    /// Espera máxima a que el item esté listo.
    static let readyTimeoutSeconds = 5.0
    /// El desfase de la hoja cambia en pasos de 1 ms: por debajo de esto es el mismo.
    static let offsetEpsilon = 1e-6
}

private func hostNow() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

public final class TakeVideoPlayer: @unchecked Sendable {
    /// Aviso de fotograma nuevo (cualquier hilo): el canal de textura avisa al runner.
    public var onFrameAvailable: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onFrame }
        set { lock.lock(); _onFrame = newValue; lock.unlock() }
    }

    private let preview: TakePreview
    private let player = AVPlayer()
    private let queue = DispatchQueue(label: "tf-take-video", qos: .userInteractive)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var _onFrame: (@Sendable () -> Void)?
    private var item: AVPlayerItem?
    private var output: AVPlayerItemVideoOutput?
    private var offset: Double
    private var ready = false
    private var closed = false
    private var gen = 0
    private var clock = TakeVideoClockMap()
    private var applied: TakeVideoClockMap?
    private var graceUntil = 0.0
    private var lastCheck = 0.0
    private var last: CVPixelBuffer?
    private var notified = false

    // Medidas (bajo lock), para tests y diagnóstico.
    private(set) var deliveries = 0
    private(set) var resyncs = 0
    private(set) var driftResyncs = 0
    private(set) var frameSize: (width: Int, height: Int)?
    /// Error A/V por fotograma entregado en marcha: reloj − PTS del fotograma, menos medio fotograma si `centered` (ms).
    private(set) var errorsMs: [Double] = []
    /// Eventos de resincronización: (host s, «seekDone» u otro motivo).
    private(set) var events: [(t: Double, kind: String)] = []

    /// Abre el vídeo de la toma. Lanza si la composición no se puede armar (sin imagen). No espera al decodificador.
    public init(preview: TakePreview, offset: Double) throws {
        self.preview = preview
        self.offset = offset
        player.automaticallyWaitsToMinimizeStalling = false
        player.isMuted = true
        try install(offset: offset)
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(deadline: .now(), repeating: .nanoseconds(Int(TakeVideoConstants.tickSeconds * 1e9)), leeway: .nanoseconds(0))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    deinit { close() }

    private func install(offset off: Double) throws {
        let comp = try preview.composition(videoOffset: off)
        // El audio suena en el núcleo: sin pista de audio el reproductor no arrastra la latencia del tiempo-tono a rate ≠ 1.
        for a in comp.tracks(withMediaType: .audio) { comp.removeTrack(a) }
        let it = AVPlayerItem(asset: comp)
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: NSDictionary(),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let out = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
        it.add(out)
        lock.lock()
        item = it; output = out; ready = false; applied = nil; gen += 1
        let g = gen
        lock.unlock()
        player.replaceCurrentItem(with: it)
        Task { [weak self] in
            let deadline = Date().addingTimeInterval(TakeVideoConstants.readyTimeoutSeconds)
            while it.status == .unknown, Date() < deadline { try? await Task.sleep(nanoseconds: 10_000_000) }
            guard let self else { return }
            if markReady(generation: g, item: it) { resync(reason: "ready", drift: false) }
        }
    }

    private func markReady(generation g: Int, item it: AVPlayerItem) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let ok = g == gen && !closed && it.status == .readyToPlay
        if ok { ready = true }
        return ok
    }

    public func close() {
        lock.lock()
        if closed { lock.unlock(); return }
        closed = true; gen += 1
        let t = timer; timer = nil
        lock.unlock()
        t?.cancel()
        queue.sync {}
        player.pause()
        player.replaceCurrentItem(with: nil)
        lock.lock(); last = nil; item = nil; output = nil; _onFrame = nil; lock.unlock()
    }

    // MARK: reloj

    /// `takeview.position` (cualquier hilo). Resincroniza solo si cambia sonando/rate/epoch.
    func apply(_ e: TakeViewPositionEvent) {
        lock.lock()
        clock = TakeVideoClockMap(e)
        let need = ready && !closed && clock.needsResync(from: applied)
        lock.unlock()
        if need { resync(reason: "clock", drift: false) }
    }

    /// Desfase de la hoja «Ajustar desfase» (s): rehace la composición (barato) si cambió.
    func setOffset(_ off: Double) {
        lock.lock()
        let changed = abs(off - offset) > TakeVideoConstants.offsetEpsilon && !closed
        if changed { offset = off }
        lock.unlock()
        if changed { try? install(offset: off) }
    }

    private func resync(reason: String, drift: Bool) {
        lock.lock()
        // Cada resincronización invalida la anterior: si llega otra mientras salta, la vieja no arranca.
        gen += 1
        let mine = gen
        resyncs += 1
        if drift { driftResyncs += 1 }
        applied = clock
        let now = hostNow()
        events.append((now, reason))
        let c = clock
        graceUntil = now + TakeVideoConstants.driftGraceSeconds
        lock.unlock()
        let cm: (Double) -> CMTime = { CMTime(seconds: max(0, $0), preferredTimescale: 600_000) }
        guard c.moving else {
            player.pause()
            player.seek(to: cm(c.position(at: now)), toleranceBefore: .zero, toleranceAfter: .zero)
            return
        }
        player.seek(to: cm(c.position(at: now)), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished, let self else { return }
            lock.lock()
            let stale = mine != gen || closed
            let h = hostNow() + TakeVideoConstants.startLeadSeconds
            let p = clock.position(at: h)
            let rate = clock.rate
            if !stale { events.append((hostNow(), "seekDone")) }
            lock.unlock()
            if stale { return }
            player.setRate(Float(rate), time: cm(p), atHostTime: CMTime(seconds: h, preferredTimescale: 1_000_000_000))
        }
    }

    private func tick() {
        let now = hostNow()
        lock.lock()
        let out = output
        let c = clock, grace = graceUntil
        let due = ready && c.moving && now > grace && now - lastCheck >= TakeVideoConstants.driftCheckSeconds
        if due { lastCheck = now }
        let already = notified
        lock.unlock()
        if due {
            let d = player.currentTime().seconds - c.position(at: now)
            if abs(d) > TakeVideoConstants.halfFrame { resync(reason: "drift", drift: true) }
        }
        guard !already, let out else { return }
        let it = out.itemTime(forHostTime: now)
        if out.hasNewPixelBuffer(forItemTime: it) {
            lock.lock(); notified = true; let f = _onFrame; lock.unlock()
            f?()
        }
    }

    // MARK: entrega

    /// `tf_frame_copy`: el fotograma de «ahora»; si no hay nuevo, el último. nil mientras no haya ninguno.
    public func copyFrame() -> CVPixelBuffer? {
        let now = hostNow()
        lock.lock()
        let out = output
        lock.unlock()
        var display = CMTime.invalid
        var fresh: CVPixelBuffer?
        if let out {
            let it = out.itemTime(forHostTime: now)
            if out.hasNewPixelBuffer(forItemTime: it) { fresh = out.copyPixelBuffer(forItemTime: it, itemTimeForDisplay: &display) }
        }
        lock.lock(); defer { lock.unlock() }
        notified = false
        if let fresh {
            last = fresh
            deliveries += 1
            frameSize = (CVPixelBufferGetWidth(fresh), CVPixelBufferGetHeight(fresh))
            if clock.moving, display.isValid, errorsMs.count < 100_000 {
                errorsMs.append((clock.position(at: now) - display.seconds) * 1000)
            }
        }
        return last
    }

    /// Tests: copia coherente de las medidas.
    func measurements() -> (deliveries: Int, resyncs: Int, errorsMs: [Double]) {
        lock.lock(); defer { lock.unlock() }
        return (deliveries, resyncs, errorsMs)
    }

    /// Tests: espera a que el reproductor esté listo.
    var isReady: Bool { lock.lock(); defer { lock.unlock() }; return ready }
}
#endif
