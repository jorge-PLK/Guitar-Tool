#if canImport(CoreVideo)
import CoreVideo
#endif
import Foundation
import XCTest
import VideoKit
@testable import AppCore

/// W2-E1: relevo de fotogramas (descarta bajo presión sin bloquear, respeta `maxFPS`, `stop`, forma del evento y
/// `frames.stats`).
///
/// Deterministas (paso 8, relevo 10, parte 3): la cadencia, el descarte y el hueco de `latestWins` se prueban con reloj y
/// temporizador simulados, y el «ocupado» con un codificador retenido por un semáforo, así que no dependen del reloj real
/// ni de la velocidad de la máquina. Que `push` no espera al codificador se prueba sin medir tiempo: con el codificador
/// retenido, un `push` que lo esperase no volvería nunca (`Self.hangLimit`). El coste de `push` en ms es una medición: se
/// imprime siempre y solo se exige `maxPushMs` con `TF_FRAME_PERF=1` (en la VM x64 emulada dio 1,64 ms por
/// expulsiones del hilo, no por el relevo).
final class FrameRelayTests: XCTestCase {
    /// `push` mientras el codificador está ocupado no puede tardar más que esto (decisión propia: el callback de captura
    /// a 60 fps tiene 16,7 ms; pedimos 100 veces menos). Solo con `TF_FRAME_PERF=1`.
    static let maxPushMs = 0.5
    /// Plazo para dar por colgado un `push` con el codificador retenido (decisión propia: holgado para cualquier máquina;
    /// un `push` que esperase al codificador no volvería nunca).
    static let hangLimit = 10.0
    static let strictTiming = ProcessInfo.processInfo.environment["TF_FRAME_PERF"] == "1"

    static func frame(width w: Int = 64, height h: Int = 36) -> FramePixelBuffer {
        #if canImport(CoreVideo)
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, nil, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        memset(CVPixelBufferGetBaseAddress(pb!)!, 0x80, CVPixelBufferGetBytesPerRow(pb!) * h)
        CVPixelBufferUnlockBaseAddress(pb!, [])
        return pb!
        #else
        let pb = FramePixelBuffer(pixelFormat: .bgra, width: w, height: h)
        pb.fill(b: 128, g: 128, r: 128)
        return pb
        #endif
    }

    /// Reloj manual (s).
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var t = 0.0
        var now: Double { lock.lock(); defer { lock.unlock() }; return t }
        func set(_ v: Double) { lock.lock(); t = v; lock.unlock() }
    }

    /// Temporizador manual: guarda los retardos pedidos y dispara cuando lo diga el test (en el hilo del test).
    final class Timer: @unchecked Sendable {
        private let lock = NSLock()
        private var armed: [@Sendable () -> Void] = []
        private var asked: [Double] = []
        var delays: [Double] { lock.lock(); defer { lock.unlock() }; return asked }
        var pending: Int { lock.lock(); defer { lock.unlock() }; return armed.count }
        func schedule(_ delay: Double, _ fire: @escaping @Sendable () -> Void) {
            lock.lock(); asked.append(delay); armed.append(fire); lock.unlock()
        }
        /// Dispara los armados hasta ahora (los que se armen al disparar quedan para la siguiente vez).
        func fire() {
            lock.lock(); let now = armed; armed = []; lock.unlock()
            now.forEach { $0() }
        }
    }

    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(String, FrameEvent)] = []
        func add(_ n: String, _ e: FrameEvent) { lock.lock(); items.append((n, e)); lock.unlock() }
        var events: [(String, FrameEvent)] { lock.lock(); defer { lock.unlock() }; return items }
    }

    final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ v: T) { value = v }
    }

    static let fakeJPEG = JPEGFrame(data: Data([0xFF, 0xD8, 0xFF, 0xD9]), width: 64, height: 36)

    /// Ejecuta `body` en otro hilo; `false` si no vuelve en `hangLimit` (determinista: no compara tiempos finos).
    private func returns(_ body: @escaping @Sendable () -> Void) -> Bool {
        let done = DispatchSemaphore(value: 0)
        Thread { body(); done.signal() }.start()
        return done.wait(timeout: .now() + Self.hangLimit) == .success
    }

    /// Medición del coste de `push` (ms): siempre se imprime; el umbral solo con `TF_FRAME_PERF=1`.
    private func checkPushCost(_ worst: Double, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        print(String(format: "W2-E1 relevo [medición]: %@, push peor %.4f ms (máx. %.1f%@)", label, worst, Self.maxPushMs,
                     Self.strictTiming ? ", exigido" : ", informativo; TF_FRAME_PERF=1 lo exige"))
        if Self.strictTiming { XCTAssertLessThan(worst, Self.maxPushMs, label, file: file, line: line) }
    }

    private static func ms(since t0: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6 }

    func testDropsWhileBusyWithoutBlocking() {
        let gate = DispatchSemaphore(value: 0), entered = DispatchSemaphore(value: 0)
        let sink = Sink(), clock = Clock()
        let relay = FrameRelay(channel: "t-busy", maxFPS: 1000, maxWidth: 640,
                               encode: { _ in entered.signal(); gate.wait(); return Self.fakeJPEG },
                               emit: sink.add, now: { clock.now })
        let f = Self.frame()
        XCTAssertTrue(relay.push(f, ptsMs: 0))
        entered.wait()
        let worst = Box(0.0), accepted = Box(0), held = Box(f)
        // El codificador sigue retenido en `gate` durante los 50 empujes: si `push` lo esperase, no volvería.
        let ok = returns {
            for i in 1...50 {
                clock.set(Double(i))   // siempre a tiempo: solo cuenta el «ocupado»
                let t0 = DispatchTime.now().uptimeNanoseconds
                if relay.push(held.value, ptsMs: Double(i)) { accepted.value += 1 }
                worst.value = max(worst.value, Self.ms(since: t0))
            }
        }
        gate.signal()
        XCTAssertTrue(ok, "push esperó al codificador ocupado")
        relay.waitIdle()
        let s = relay.stats
        checkPushCost(worst.value, "codificador retenido, 50 empujes")
        XCTAssertEqual(accepted.value, 0)
        XCTAssertEqual(s.sent, 1)
        XCTAssertEqual(s.droppedBusy, 50)
        XCTAssertEqual(s.droppedRate, 0)
        XCTAssertEqual(sink.events.count, 1)
        // Libre otra vez: el siguiente entra.
        clock.set(100)
        XCTAssertTrue(relay.push(f, ptsMs: 100))
        entered.wait(); gate.signal()
        relay.waitIdle()
        XCTAssertEqual(relay.stats.sent, 2)
        XCTAssertEqual(sink.events.map(\.1.seq), [1, 2])
    }

    /// Pronto y ocupado a la vez cuenta como «cadencia» (se comprueba antes); a tiempo y ocupado, como «ocupado».
    func testEarlyAndBusyCountsAsRate() {
        let gate = DispatchSemaphore(value: 0), entered = DispatchSemaphore(value: 0)
        let clock = Clock()
        let relay = FrameRelay(channel: "t-early-busy", maxFPS: 10, maxWidth: 640,
                               encode: { _ in entered.signal(); gate.wait(); return Self.fakeJPEG },
                               emit: { _, _ in }, now: { clock.now })
        let f = Self.frame()
        XCTAssertTrue(relay.push(f, ptsMs: 0))
        entered.wait()
        clock.set(0.01)
        XCTAssertFalse(relay.push(f, ptsMs: 10))
        clock.set(0.1)
        XCTAssertFalse(relay.push(f, ptsMs: 100))
        gate.signal(); relay.waitIdle()
        XCTAssertEqual(relay.stats.droppedRate, 1)
        XCTAssertEqual(relay.stats.droppedBusy, 1)
        XCTAssertEqual(relay.stats.sent, 1)
    }

    /// Presión simulada: cámara de 50 fps durante 2 s, codificador que tarda 110 ms (más que el periodo de 15 fps,
    /// 66,7 ms), todo en tiempo simulado. Cuenta a mano: entra uno de cada 6 fotogramas (0, 120, 240… ms) → 17
    /// enviados. Los plazos alternan: tras los que entran a 0, 240, 480… ms el plazo siguiente es +66,7 ms, así que los
    /// fotogramas a +20 y +40 ms son «pronto» (cuenta antes que «ocupado») → 9 ciclos × 2 = 18 por cadencia; tras los de
    /// 120, 360… el plazo es +13,3 ms y todos los descartes son «ocupado» → 100 − 17 − 18 = 65. Nunca hay cola (el que
    /// sale es siempre el que entró).
    func testSlowEncoderSimulatedPressure() {
        let cameraFPS = 50.0, encodeCost = 0.110, n = 100
        let gate = DispatchSemaphore(value: 0), entered = DispatchSemaphore(value: 0)
        let sink = Sink(), clock = Clock()
        let relay = FrameRelay(channel: "t-sim-pressure", maxFPS: 15, maxWidth: 640,
                               encode: { _ in entered.signal(); gate.wait(); return Self.fakeJPEG },
                               emit: sink.add, now: { clock.now })
        let f = Self.frame()
        var inFlightUntil: Double?
        var accepted: [Int] = []
        for i in 0..<n {
            let t = Double(i) / cameraFPS
            if let end = inFlightUntil, t >= end { gate.signal(); relay.waitIdle(); inFlightUntil = nil }
            clock.set(t)
            if relay.push(f, ptsMs: t * 1000) {
                accepted.append(i)
                entered.wait()
                inFlightUntil = t + encodeCost
            }
        }
        if inFlightUntil != nil { gate.signal(); relay.waitIdle() }
        let s = relay.stats
        print("W2-E1 relevo [simulado]: cámara 50 fps, JPEG 110 ms → \(s.sent) enviados, \(s.droppedBusy) ocupado, \(s.droppedRate) cadencia")
        XCTAssertEqual(accepted, Array(stride(from: 0, to: n, by: 6)))
        XCTAssertEqual(s.sent, 17)
        XCTAssertEqual(s.droppedBusy, 65)
        XCTAssertEqual(s.droppedRate, 18)
        XCTAssertEqual(sink.events.map(\.1.seq), Array(1...17))
        XCTAssertEqual(sink.events.map(\.1.ptsMs), accepted.map { Double($0) / cameraFPS * 1000 })
    }

    /// W2-E2 (Montaje): con `latestWins`, el último fotograma que llega con el codificador ocupado no se pierde: sale al
    /// acabar el actual (el intermedio sí se descarta). Es el de una pausa o un `seek`.
    func testLatestWinsKeepsLastFrameWhileBusy() {
        let gate = DispatchSemaphore(value: 0), entered = DispatchSemaphore(value: 0)
        let sink = Sink(), clock = Clock(), timer = Timer()
        let relay = FrameRelay(channel: "t-latest", maxFPS: 1000, maxWidth: 640, latestWins: true,
                               encode: { _ in entered.signal(); gate.wait(); return Self.fakeJPEG },
                               emit: sink.add, now: { clock.now }, after: timer.schedule)
        let f = Self.frame()
        XCTAssertTrue(relay.push(f, ptsMs: 0))
        entered.wait()
        let worst = Box(0.0), held = Box(f)
        let ok = returns {
            for (i, pts) in [10.0, 20, 30].enumerated() {
                clock.set(Double(i + 1))
                let t0 = DispatchTime.now().uptimeNanoseconds
                relay.push(held.value, ptsMs: pts)
                worst.value = max(worst.value, Self.ms(since: t0))
            }
        }
        XCTAssertTrue(ok, "push esperó al codificador ocupado con el hueco")
        XCTAssertEqual(timer.delays, [], "ocupado: sale al acabar el actual, sin temporizador")
        gate.signal()          // acaba el primero -> sale el del hueco (pts 30)
        entered.wait()
        gate.signal()
        relay.waitIdle()
        checkPushCost(worst.value, "latestWins con codificador retenido")
        XCTAssertEqual(sink.events.map(\.1.ptsMs), [0, 30], "el último gana; 10 y 20 se pierden")
        XCTAssertEqual(sink.events.map(\.1.seq), [1, 2])
        XCTAssertEqual(relay.stats.droppedBusy, 2)
    }

    /// W2-E2: con `latestWins`, uno que llega antes de su plazo sale en el plazo (temporizador), no se pierde. Tiempo
    /// simulado: periodo 50 ms, holgura ¼ → el plazo efectivo del segundo es 37,5 ms.
    func testLatestWinsDelaysEarlyFrameToItsSlot() {
        let sink = Sink(), clock = Clock(), timer = Timer()
        let relay = FrameRelay(channel: "t-latest-rate", maxFPS: 20, maxWidth: 640, latestWins: true,
                               encode: { _ in Self.fakeJPEG }, emit: sink.add, now: { clock.now }, after: timer.schedule)
        let f = Self.frame()
        XCTAssertTrue(relay.push(f, ptsMs: 0))
        relay.waitIdle()
        clock.set(0.001)
        XCTAssertTrue(relay.push(f, ptsMs: 1))   // pronto
        XCTAssertEqual(timer.delays.count, 1)
        XCTAssertEqual(timer.delays[0], 0.0375 - 0.001, accuracy: 1e-9, "retardo hasta el plazo menos la holgura")
        XCTAssertEqual(sink.events.count, 1)
        // Si el temporizador se adelanta (reloj en 20 ms), se rearma con lo que falta y no sale.
        clock.set(0.020)
        timer.fire()
        XCTAssertEqual(sink.events.count, 1)
        XCTAssertEqual(timer.delays.count, 2)
        XCTAssertEqual(timer.delays[1], 0.0375 - 0.020, accuracy: 1e-9)
        // En su plazo sale (en el hilo del disparo).
        clock.set(0.038)
        timer.fire()
        XCTAssertEqual(sink.events.map(\.1.ptsMs), [0, 1])
        XCTAssertEqual(sink.events.map(\.1.seq), [1, 2])
        XCTAssertEqual(relay.stats.droppedRate, 0)
        // Dos prontos seguidos: un solo temporizador; el segundo sustituye al primero (que cuenta como descartado).
        // Plazo siguiente: 50 + 50 = 100 ms (sin reenganche: 38 ms no pasa un periodo del plazo de 50).
        clock.set(0.040)
        XCTAssertTrue(relay.push(f, ptsMs: 40))
        clock.set(0.050)
        XCTAssertTrue(relay.push(f, ptsMs: 50))
        XCTAssertEqual(timer.delays.count, 3, "un solo temporizador para el hueco")
        XCTAssertEqual(timer.delays[2], 0.1 - 0.0125 - 0.040, accuracy: 1e-9)
        XCTAssertEqual(relay.stats.droppedRate, 1)
        clock.set(0.088)
        timer.fire()
        XCTAssertEqual(sink.events.map(\.1.ptsMs), [0, 1, 50])
        XCTAssertEqual(timer.pending, 0)
    }

    /// El temporizador por defecto (`asyncAfter` en la cola del relevo) está cableado: el fotograma pronto llega solo.
    /// Cota inferior exacta por construcción (`asyncAfter` no dispara antes); la superior, holgada.
    func testLatestWinsDefaultTimerFires() {
        let sink = Sink()
        let relay = FrameRelay(channel: "t-latest-default", maxFPS: 20, maxWidth: 640, latestWins: true,
                               encode: { _ in Self.fakeJPEG }, emit: sink.add)
        let f = Self.frame()
        let t0 = DispatchTime.now().uptimeNanoseconds
        XCTAssertTrue(relay.push(f, ptsMs: 0))
        relay.waitIdle()
        XCTAssertTrue(relay.push(f, ptsMs: 1))
        let end = Date().addingTimeInterval(Self.hangLimit)
        while sink.events.count < 2, Date() < end { Thread.sleep(forTimeInterval: 0.002) }
        let ms = Self.ms(since: t0)
        XCTAssertEqual(sink.events.map(\.1.ptsMs), [0, 1])
        XCTAssertGreaterThanOrEqual(ms, 37.5 - 1)
        print(String(format: "W2-E1 relevo [medición]: temporizador real de latestWins, salió a %.1f ms (plazo 37,5)", ms))
    }

    /// Cámaras a 30 y 60 fps (con y sin ±3 ms de vaivén) durante 4 s con `maxFPS` 15: salen 15 fps ± 1 fotograma
    /// en el total, y nunca dos más cerca de medio periodo.
    func testRespectsMaxFPS() {
        for (cameraFPS, jitter) in [(30.0, 0.0), (60.0, 0.0), (30.0, 0.003), (25.0, 0.002)] {
            let sink = Sink(), clock = Clock()
            let relay = FrameRelay(channel: "t-rate-\(cameraFPS)-\(jitter)", maxFPS: 15, maxWidth: 640,
                                   encode: { _ in Self.fakeJPEG }, emit: sink.add, now: { clock.now })
            let f = Self.frame()
            let seconds = 4.0, n = Int(seconds * cameraFPS)
            var accepted: [Double] = []
            var rng: UInt32 = 7
            for i in 0..<n {
                rng = rng &* 1_664_525 &+ 1_013_904_223
                let j = (Double(rng >> 8) / Double(1 << 24) * 2 - 1) * jitter
                let t = Double(i) / cameraFPS + j
                clock.set(t)
                if relay.push(f, ptsMs: t * 1000) { accepted.append(t) }
                relay.waitIdle()
            }
            let gaps = zip(accepted.dropFirst(), accepted).map { $0 - $1 }
            let minGap = gaps.min() ?? 0
            let expected = seconds * 15
            print(String(format: "W2-E1 relevo: cámara %.0f fps ±%.0f ms → %d enviados en %.0f s (esperado %.0f), hueco mín. %.1f ms",
                         cameraFPS, jitter * 1000, accepted.count, seconds, expected, minGap * 1000))
            XCTAssertEqual(Double(accepted.count), expected, accuracy: 1, "\(cameraFPS) fps ±\(jitter)")
            XCTAssertGreaterThanOrEqual(minGap, 0.5 / 15, "\(cameraFPS) fps: dos fotogramas a menos de medio periodo")
            XCTAssertEqual(relay.stats.sent, accepted.count)
            XCTAssertEqual(relay.stats.droppedRate, n - accepted.count)
        }
    }

    /// Tras una pausa larga no hay ráfaga: el primero entra y el siguiente espera un periodo.
    func testNoBurstAfterPause() {
        let clock = Clock()
        let relay = FrameRelay(channel: "t-pause", maxFPS: 10, maxWidth: 640, encode: { _ in Self.fakeJPEG },
                               emit: { _, _ in }, now: { clock.now })
        let f = Self.frame()
        XCTAssertTrue(relay.push(f, ptsMs: 0)); relay.waitIdle()
        clock.set(5)
        XCTAssertTrue(relay.push(f, ptsMs: 0)); relay.waitIdle()
        clock.set(5.05)
        XCTAssertFalse(relay.push(f, ptsMs: 0), "a medio periodo tras reengancharse")
        clock.set(5.1)
        XCTAssertTrue(relay.push(f, ptsMs: 0))
    }

    func testStopRejectsAndSuppressesInFlight() {
        let gate = DispatchSemaphore(value: 0), entered = DispatchSemaphore(value: 0)
        let sink = Sink(), clock = Clock()
        let relay = FrameRelay(channel: "t-stop", maxFPS: 1000, maxWidth: 640,
                               encode: { _ in entered.signal(); gate.wait(); return Self.fakeJPEG },
                               emit: sink.add, now: { clock.now })
        let f = Self.frame()
        XCTAssertTrue(relay.push(f, ptsMs: 0))
        entered.wait()
        relay.stop()
        gate.signal()
        relay.waitIdle()
        XCTAssertEqual(sink.events.count, 0, "el que estaba en curso no se emite tras stop")
        clock.set(1)
        XCTAssertFalse(relay.push(f, ptsMs: 1))
        XCTAssertFalse(relay.stats.running)
        XCTAssertEqual(relay.stats.sent, 0)
    }

    /// `stop` vacía el hueco de `latestWins`: el temporizador armado dispara y no sale nada.
    func testStopDropsLatestWinsPending() {
        let sink = Sink(), clock = Clock(), timer = Timer()
        let relay = FrameRelay(channel: "t-stop-latest", maxFPS: 20, maxWidth: 640, latestWins: true,
                               encode: { _ in Self.fakeJPEG }, emit: sink.add, now: { clock.now }, after: timer.schedule)
        let f = Self.frame()
        XCTAssertTrue(relay.push(f, ptsMs: 0)); relay.waitIdle()
        clock.set(0.001)
        XCTAssertTrue(relay.push(f, ptsMs: 1))
        XCTAssertEqual(timer.pending, 1)
        relay.stop()
        clock.set(0.05)
        timer.fire()
        XCTAssertEqual(sink.events.map(\.1.ptsMs), [0])
        XCTAssertEqual(timer.pending, 0)
    }

    /// Con el codificador real: nombre del evento, tamaño reducido, JPEG en base64 y JSON del puente.
    func testRealEncoderEventShape() throws {
        let sink = Sink()
        let relay = FrameRelay(channel: "camera-test", emit: sink.add)
        XCTAssertTrue(relay.push(Self.frame(width: 1280, height: 720), ptsMs: 1234.5))
        relay.waitIdle()
        let (name, e) = try XCTUnwrap(sink.events.first)
        XCTAssertEqual(name, "frames.camera-test")
        XCTAssertEqual(e.seq, 1); XCTAssertEqual(e.width, 640); XCTAssertEqual(e.height, 360); XCTAssertEqual(e.ptsMs, 1234.5)
        let jpeg = try XCTUnwrap(Data(base64Encoded: e.jpeg))
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xFF, 0xD8])
        let msg = try XCTUnwrap(Router.eventMessage(name, e))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(msg.utf8)) as? [String: Any])
        let payload = try XCTUnwrap(obj["payload"] as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["seq", "width", "height", "ptsMs", "jpeg"])
    }

    /// Bajo presión real con el codificador real (1080p): nada se encola y todo se cuenta. Las comprobaciones son
    /// deterministas (cuentas); el coste de `push` y del JPEG es una medición (`checkPushCost`).
    func testPressureWithRealEncoder() {
        let relay = FrameRelay(channel: "t-pressure", maxFPS: 1_000_000, emit: { _, _ in })   // solo cuenta «ocupado»
        let f = Self.frame(width: 1920, height: 1080)
        var worst = 0.0
        for i in 0..<300 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            relay.push(f, ptsMs: Double(i))
            worst = max(worst, Self.ms(since: t0))
            Thread.sleep(forTimeInterval: 0.0002)
        }
        relay.waitIdle()
        let s = relay.stats
        print(String(format: "W2-E1 relevo bajo presión 1080p [medición]: %d enviados, %d ocupado, %d cadencia; JPEG p50 %.2f ms p95 %.2f; total p50 %.2f ms",
                     s.sent, s.droppedBusy, s.droppedRate, s.encodeP50Ms, s.encodeP95Ms, s.totalP50Ms))
        XCTAssertEqual(s.sent + s.droppedBusy + s.droppedRate, 300)
        XCTAssertGreaterThanOrEqual(s.sent, 1)
        XCTAssertEqual(s.failed, 0, s.lastError ?? "")
        XCTAssertGreaterThan(s.meanBytes, 0)
        checkPushCost(worst, "1080p real, 300 empujes cada 0,2 ms")
    }

    /// Empujes seguidos sin pausa con el codificador real: el segundo llega microsegundos después del primero, cuando
    /// un JPEG de 1080p aún no ha podido acabar → hay descartes por «ocupado» y ninguno por cadencia.
    func testBackToBackRealEncoderDropsBusy() {
        let relay = FrameRelay(channel: "t-back-to-back", maxFPS: 1_000_000, emit: { _, _ in })
        let f = Self.frame(width: 1920, height: 1080)
        for i in 0..<50 { relay.push(f, ptsMs: Double(i)) }
        relay.waitIdle()
        let s = relay.stats
        XCTAssertEqual(s.sent + s.droppedBusy, 50)
        XCTAssertGreaterThan(s.droppedBusy, 0)
        XCTAssertEqual(s.droppedRate, 0)
    }

    func testStatsMethod() async throws {
        let router = Router()
        FrameRelay.register(on: router)
        let relay = FrameRelay(channel: "t-stats", maxFPS: 15, maxWidth: 640, encode: { _ in Self.fakeJPEG }, emit: { _, _ in })
        relay.push(Self.frame(), ptsMs: 0); relay.waitIdle()
        let ok = await router.handle(#"{"id":1,"method":"frames.stats","params":{"channel":"t-stats"}}"#)
        XCTAssertTrue(ok.contains(#""sent":1"#), ok)
        XCTAssertTrue(ok.contains(#""running":true"#), ok)
        let missing = await router.handle(#"{"id":2,"method":"frames.stats","params":{"channel":"no-existe"}}"#)
        XCTAssertTrue(missing.contains(#""code":"not-found""#), missing)
        withExtendedLifetime(relay) {}
    }
}
