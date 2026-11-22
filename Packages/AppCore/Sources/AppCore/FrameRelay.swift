import Foundation
import VideoKit

/// Evento `frames.<canal>` (paso 8, W2-E1): un fotograma en JPEG reducido, en base64. `seq` crece de uno en uno por
/// fotograma **enviado** (la página descarta los que lleguen con `seq` menor que el último pintado).
public struct FrameEvent: Codable, Sendable, Equatable {
    public let seq: Int
    public let width: Int
    public let height: Int
    /// Marca que da quien empuja (tiempo de la vista previa o de host), en ms.
    public let ptsMs: Double
    public let jpeg: String
}

/// Contadores de un relevo (`frames.stats {channel}`), para dar números.
public struct FrameRelayStats: Codable, Sendable, Equatable {
    public var channel: String
    public var running: Bool
    public var maxFPS: Double
    public var maxWidth: Int
    public var sent: Int
    /// Descartados porque había uno codificándose.
    public var droppedBusy: Int
    /// Descartados por `maxFPS`.
    public var droppedRate: Int
    public var failed: Int
    /// Coste de la conversión, la reducción y el JPEG (últimos `FrameRelay.statsWindow` fotogramas).
    public var encodeP50Ms: Double
    public var encodeP95Ms: Double
    /// JPEG + base64 + envío al puente.
    public var totalP50Ms: Double
    public var totalP95Ms: Double
    public var meanBytes: Int
    public var lastError: String?
}

/// Relevo de fotogramas hacia la página (paso 8, W2-E1; decisión de Jorge del 21/11/2026: JPEG reducido por el canal
/// de mensajes, sin tocar el shim C++). Para la cámara en vivo de Grabar y la vista previa de Montaje.
///
/// - `push` **no bloquea ni copia**: retiene el búfer y lo pasa a una cola propia. Si hay uno codificándose o es pronto
///   para `maxFPS`, lo descarta y lo cuenta. Nunca hay cola: como mucho un fotograma en curso, así el escritor de la
///   toma, que lee el mismo búfer, no espera.
/// - Cadencia: plazo `1/maxFPS` con holgura de `rateSlack` (un fotograma de una cámara a 30 fps que llega a 66,5 ms en
///   vez de 66,7 no se pierde); de media nunca pasa de `maxFPS`. Tras un hueco largo se reengancha sin ráfaga.
/// - `stop()`: no acepta más y no emite el que esté en curso.
/// - `latestWins` (W2-E2, Montaje): el último fotograma rechazado (ocupado o pronto) se guarda en un hueco único y sale en
///   cuanto se puede; uno nuevo lo sustituye (el sustituido cuenta como descartado). Así el fotograma de una pausa o de un
///   `seek` nunca se pierde. La cámara no lo usa: sus fotogramas caducan solos.
public final class FrameRelay: @unchecked Sendable {
    /// Encargo W2-E1: 15 fps y 640 px de ancho para la cámara.
    public static let defaultMaxFPS = 15.0
    public static let defaultMaxWidth = FrameJPEGEncoder.defaultMaxWidth
    /// Fracción del periodo que un fotograma puede adelantarse al plazo (decisión propia: ¼ de periodo).
    static let rateSlack = 0.25
    /// Muestras para los percentiles (decisión propia: ~34 s a 15 fps).
    static let statsWindow = 512

    public let channel: String
    public let maxFPS: Double
    public let maxWidth: Int
    public let latestWins: Bool

    private let encode: @Sendable (FramePixelBuffer) throws -> JPEGFrame
    private let emit: @Sendable (String, FrameEvent) -> Void
    private let now: @Sendable () -> Double
    /// Temporizador del hueco de `latestWins`: `after(retardo en s, disparo)`. Por defecto, `asyncAfter` en la cola del relevo.
    private let after: @Sendable (Double, @escaping @Sendable () -> Void) -> Void
    private let interval: Double
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var stopped = false
    private var busy = false
    private var nextDue = -Double.infinity
    private var seq = 0
    private var sent = 0, droppedBusy = 0, droppedRate = 0, failed = 0
    private var bytes = 0
    private var encodeMs: [Double] = []
    private var totalMs: [Double] = []
    private var sampleIndex = 0
    private var lastError: String?
    /// Hueco de `latestWins`.
    private var pending: (frame: Held, ptsMs: Double)?
    private var timerArmed = false

    /// `emit(evento, payload)`: normalmente `{ bridge.emit($0, $1) }`. Se llama en la cola del relevo.
    public convenience init(channel: String, maxFPS: Double = defaultMaxFPS, maxWidth: Int = defaultMaxWidth,
                            quality: Double = FrameJPEGEncoder.defaultQuality, latestWins: Bool = false,
                            emit: @escaping @Sendable (String, FrameEvent) -> Void) {
        let encoder = FrameJPEGEncoder(maxWidth: maxWidth, quality: quality)
        self.init(channel: channel, maxFPS: maxFPS, maxWidth: maxWidth, latestWins: latestWins, encode: { try encoder.encode($0) },
                  emit: emit)
    }

    /// Tests: codificador, reloj (s, monótono) y temporizador a medida. Con reloj y temporizador simulados, la cadencia,
    /// el descarte y el hueco de `latestWins` no dependen del reloj real ni de la velocidad de la máquina.
    init(channel: String, maxFPS: Double, maxWidth: Int, latestWins: Bool = false,
         encode: @escaping @Sendable (FramePixelBuffer) throws -> JPEGFrame,
         emit: @escaping @Sendable (String, FrameEvent) -> Void,
         now: @escaping @Sendable () -> Double = { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 },
         after: (@Sendable (Double, @escaping @Sendable () -> Void) -> Void)? = nil) {
        precondition(maxFPS > 0, "FrameRelay: maxFPS ≤ 0")
        self.channel = channel
        self.maxFPS = maxFPS
        self.maxWidth = maxWidth
        self.latestWins = latestWins
        self.encode = encode
        self.emit = emit
        self.now = now
        interval = 1 / maxFPS
        // Por debajo del escritor de la toma (`.userInitiated`): la vista previa cede antes que la grabación.
        let queue = DispatchQueue(label: "ToneForge.FrameRelay.\(channel)", qos: .default)
        self.queue = queue
        self.after = after ?? { delay, fire in queue.asyncAfter(deadline: .now() + max(0, delay), execute: fire) }
        FrameRelayRegistry.shared.add(self)
    }

    deinit { FrameRelayRegistry.shared.retire(channel: channel, last: snapshot(running: false)) }

    /// Nombre del evento del puente.
    public var eventName: String { "frames.\(channel)" }

    /// Ofrece un fotograma; `true` si se acepta para codificar. Llamable desde el callback de captura.
    @discardableResult
    public func push(_ frame: FramePixelBuffer, ptsMs: Double) -> Bool {
        let t = now()
        lock.lock()
        if stopped { lock.unlock(); return false }
        let early = t + Self.rateSlack * interval < nextDue
        if early || busy {
            guard latestWins else {
                if early { droppedRate += 1 } else { droppedBusy += 1 }
                lock.unlock()
                return false
            }
            // Hueco único: el que estaba esperando se pierde; este sale en cuanto acabe el actual o llegue su plazo.
            if pending != nil { if early { droppedRate += 1 } else { droppedBusy += 1 } }
            pending = (Held(frame: frame), ptsMs)
            let delay = busy ? nil : nextDue - Self.rateSlack * interval - t
            lock.unlock()
            if let delay { armTimer(after: delay) }
            return true
        }
        let s = begin(at: t)
        lock.unlock()
        let held = Held(frame: frame)
        queue.async { [self] in run(held.frame, seq: s, ptsMs: ptsMs) }
        return true
    }

    /// Con el cerrojo tomado: plazo siguiente, ocupado y número de secuencia.
    private func begin(at t: Double) -> Int {
        nextDue = t - nextDue > interval ? t + interval : nextDue + interval
        busy = true
        seq += 1
        return seq
    }

    /// `latestWins`: el hueco sale cuando toque (si no hay ya un temporizador).
    private func armTimer(after delay: Double) {
        lock.lock()
        if timerArmed { lock.unlock(); return }
        timerArmed = true
        lock.unlock()
        after(max(0, delay)) { [weak self] in
            guard let self else { return }
            lock.lock()
            timerArmed = false
            lock.unlock()
            drainPending()
        }
    }

    /// `latestWins`: si hay un fotograma esperando y ya se puede, lo codifica (en la cola del relevo); si es pronto, programa.
    private func drainPending() {
        let t = now()
        lock.lock()
        guard latestWins, !stopped, !busy, let p = pending else { lock.unlock(); return }
        if t + Self.rateSlack * interval < nextDue {
            let delay = nextDue - Self.rateSlack * interval - t
            lock.unlock()
            armTimer(after: delay)
            return
        }
        pending = nil
        let s = begin(at: t)
        lock.unlock()
        run(p.frame.frame, seq: s, ptsMs: p.ptsMs)
    }

    private func run(_ frame: FramePixelBuffer, seq s: Int, ptsMs: Double) {
        let t0 = DispatchTime.now().uptimeNanoseconds
        do {
            let jpeg = try encode(frame)
            let t1 = DispatchTime.now().uptimeNanoseconds
            let event = FrameEvent(seq: s, width: jpeg.width, height: jpeg.height, ptsMs: ptsMs, jpeg: jpeg.data.base64EncodedString())
            if isStopped { finish(); return }
            emit(eventName, event)
            let t2 = DispatchTime.now().uptimeNanoseconds
            finish(encodeMs: Double(t1 - t0) / 1e6, totalMs: Double(t2 - t0) / 1e6, bytes: jpeg.data.count)
        } catch {
            lock.lock(); failed += 1; lastError = "\(error)"; busy = false; lock.unlock()
        }
        if latestWins { drainPending() }
    }

    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    private func finish(encodeMs e: Double? = nil, totalMs t: Double = 0, bytes b: Int = 0) {
        lock.lock()
        defer { lock.unlock() }
        busy = false
        guard let e else { return }
        sent += 1
        bytes += b
        if encodeMs.count < Self.statsWindow {
            encodeMs.append(e); totalMs.append(t)
        } else {
            encodeMs[sampleIndex] = e; totalMs[sampleIndex] = t
            sampleIndex = (sampleIndex + 1) % Self.statsWindow
        }
    }

    /// Deja de aceptar fotogramas; el que esté en curso no se emite. Los contadores siguen consultables.
    public func stop() {
        lock.lock(); stopped = true; pending = nil; lock.unlock()
    }

    public var stats: FrameRelayStats { snapshot(running: !isStopped) }

    private func snapshot(running: Bool) -> FrameRelayStats {
        lock.lock()
        defer { lock.unlock() }
        func pct(_ v: [Double], _ p: Double) -> Double {
            guard !v.isEmpty else { return 0 }
            let s = v.sorted()
            return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))]
        }
        return FrameRelayStats(channel: channel, running: running, maxFPS: maxFPS, maxWidth: maxWidth, sent: sent,
                               droppedBusy: droppedBusy, droppedRate: droppedRate, failed: failed,
                               encodeP50Ms: pct(encodeMs, 0.5), encodeP95Ms: pct(encodeMs, 0.95),
                               totalP50Ms: pct(totalMs, 0.5), totalP95Ms: pct(totalMs, 0.95),
                               meanBytes: sent > 0 ? bytes / sent : 0, lastError: lastError)
    }

    /// Tests: espera a que termine el fotograma en curso.
    func waitIdle() { queue.sync {} }

    /// `frames.stats {channel}`: contadores del relevo vivo o, si ya no existe, los últimos que dejó.
    static func register(on router: Router) {
        router.register("frames.stats") { (p: FrameStatsParams) -> FrameRelayStats in
            guard let s = FrameRelayRegistry.shared.stats(channel: p.channel) else {
                throw RPCError(code: "not-found", message: "No hay relevo de fotogramas «\(p.channel)».")
            }
            return s
        }
    }
}

extension Bridge {
    /// Relevo que emite por este puente (`frames.<channel>`). Lo guarda quien lo crea. El núcleo ya cablea `camera` (Grabar y
    /// `video.preview.*`) y `montage` (W2-E2); un anfitrión solo lo necesita para canales propios.
    public func makeFrameRelay(channel: String, maxFPS: Double = FrameRelay.defaultMaxFPS,
                               maxWidth: Int = FrameRelay.defaultMaxWidth,
                               quality: Double = FrameJPEGEncoder.defaultQuality, latestWins: Bool = false) -> FrameRelay {
        FrameRelay(channel: channel, maxFPS: maxFPS, maxWidth: maxWidth, quality: quality, latestWins: latestWins) { [weak self] in
            self?.emit($0, $1)
        }
    }
}

struct FrameStatsParams: Codable, Sendable {
    let channel: String
}

/// El búfer viaja a la cola del relevo sin copiarse (en el Mac es un `CVPixelBuffer`, que Swift no marca `Sendable`;
/// nadie lo escribe mientras tanto: la captura entrega uno nuevo por fotograma).
private struct Held: @unchecked Sendable {
    let frame: FramePixelBuffer
}

/// Relevos por canal para `frames.stats` (débiles: el dueño es quien los crea).
final class FrameRelayRegistry: @unchecked Sendable {
    static let shared = FrameRelayRegistry()

    private struct Weak { weak var relay: FrameRelay? }
    private let lock = NSLock()
    private var live: [String: Weak] = [:]
    private var last: [String: FrameRelayStats] = [:]

    func add(_ r: FrameRelay) {
        lock.lock(); live[r.channel] = Weak(relay: r); lock.unlock()
    }

    func retire(channel: String, last s: FrameRelayStats) {
        lock.lock()
        if live[channel]?.relay == nil { live[channel] = nil }
        last[channel] = s
        lock.unlock()
    }

    func stats(channel: String) -> FrameRelayStats? {
        lock.lock()
        let r = live[channel]?.relay
        let l = last[channel]
        lock.unlock()
        return r?.stats ?? l
    }
}
