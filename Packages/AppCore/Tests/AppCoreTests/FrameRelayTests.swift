#if canImport(CoreVideo)
import CoreVideo
#endif
import Foundation
import XCTest
import VideoKit
@testable import AppCore

/// W2-E1: relevo de fotogramas (descarta bajo presión sin bloquear, respeta `maxFPS`, `stop`, forma del evento y
/// `frames.stats`).
final class FrameRelayTests: XCTestCase {
    /// `push` mientras el codificador está ocupado no puede tardar más que esto (decisión propia: el callback de captura
    /// a 60 fps tiene 16,7 ms; pedimos 100 veces menos).
    static let maxPushMs = 0.5

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

    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(String, FrameEvent)] = []
        func add(_ n: String, _ e: FrameEvent) { lock.lock(); items.append((n, e)); lock.unlock() }
        var events: [(String, FrameEvent)] { lock.lock(); defer { lock.unlock() }; return items }
    }

    static let fakeJPEG = JPEGFrame(data: Data([0xFF, 0xD8, 0xFF, 0xD9]), width: 64, height: 36)

    func testDropsWhileBusyWithoutBlocking() {
        let gate = DispatchSemaphore(value: 0), entered = DispatchSemaphore(value: 0)
        let sink = Sink(), clock = Clock()
        let relay = FrameRelay(channel: "t-busy", maxFPS: 1000, maxWidth: 640,
                               encode: { _ in entered.signal(); gate.wait(); return Self.fakeJPEG },
                               emit: sink.add, now: { clock.now })
        let f = Self.frame()
        XCTAssertTrue(relay.push(f, ptsMs: 0))
        entered.wait()
        var worst = 0.0
        for i in 1...50 {
            clock.set(Double(i))   // siempre a tiempo: solo cuenta el «ocupado»
            let t0 = DispatchTime.now().uptimeNanoseconds
            XCTAssertFalse(relay.push(f, ptsMs: Double(i)))
            worst = max(worst, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        }
        gate.signal()
        relay.waitIdle()
        let s = relay.stats
        print(String(format: "W2-E1 relevo: push con codificador ocupado, peor %.4f ms (máx. %.1f)", worst, Self.maxPushMs))
        XCTAssertLessThan(worst, Self.maxPushMs)
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

    /// Cámaras a 30 y 60 fps (con y sin ±3 ms de vaivén) durante 4 s con `maxFPS` 15: salen 15 fps ± 1 fotograma
    /// en el total, y nunca dos más cerca de medio periodo.
    /// W2-E2 (Montaje): con `latestWins`, el último fotograma que llega con el codificador ocupado no se pierde: sale al
    /// acabar el actual (el intermedio sí se descarta). Es el de una pausa o un `seek`.
    func testLatestWinsKeepsLastFrameWhileBusy() {
        let gate = DispatchSemaphore(value: 0), entered = DispatchSemaphore(value: 0)
        let sink = Sink(), clock = Clock()
        let relay = FrameRelay(channel: "t-latest", maxFPS: 1000, maxWidth: 640, latestWins: true,
                               encode: { _ in entered.signal(); gate.wait(); return Self.fakeJPEG },
                               emit: sink.add, now: { clock.now })
        let f = Self.frame()
        XCTAssertTrue(relay.push(f, ptsMs: 0))
        entered.wait()
        var worst = 0.0
        for (i, pts) in [10.0, 20, 30].enumerated() {
            clock.set(Double(i + 1))
            let t0 = DispatchTime.now().uptimeNanoseconds
            relay.push(f, ptsMs: pts)
            worst = max(worst, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        }
        XCTAssertLessThan(worst, Self.maxPushMs, "push sigue sin bloquear con el hueco")
        gate.signal()          // acaba el primero -> sale el del hueco (pts 30)
        entered.wait()
        gate.signal()
        relay.waitIdle()
        XCTAssertEqual(sink.events.map(\.1.ptsMs), [0, 30], "el último gana; 10 y 20 se pierden")
        XCTAssertEqual(sink.events.map(\.1.seq), [1, 2])
        XCTAssertEqual(relay.stats.droppedBusy, 2)
    }

    /// W2-E2: con `latestWins`, uno que llega antes de su plazo sale en el plazo (temporizador), no se pierde.
    func testLatestWinsDelaysEarlyFrameToItsSlot() {
        let sink = Sink()
        let relay = FrameRelay(channel: "t-latest-rate", maxFPS: 20, maxWidth: 640, latestWins: true,
                               encode: { _ in Self.fakeJPEG }, emit: sink.add)
        let f = Self.frame()
        let t0 = DispatchTime.now().uptimeNanoseconds
        XCTAssertTrue(relay.push(f, ptsMs: 0))
        relay.waitIdle()
        XCTAssertTrue(relay.push(f, ptsMs: 1))   // pronto: periodo 50 ms
        let end = Date().addingTimeInterval(1)
        while sink.events.count < 2, Date() < end { Thread.sleep(forTimeInterval: 0.002) }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        XCTAssertEqual(sink.events.map(\.1.ptsMs), [0, 1])
        // Sale en su plazo menos la holgura (¾ de 50 ms = 37,5 ms) y no mucho después.
        XCTAssertGreaterThanOrEqual(ms, 37.5 - 1)
        XCTAssertLessThan(ms, 37.5 + 40)
        XCTAssertEqual(relay.stats.droppedRate, 0)
    }

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
        let sink = Sink()
        let relay = FrameRelay(channel: "t-stop", maxFPS: 1000, maxWidth: 640,
                               encode: { _ in entered.signal(); gate.wait(); return Self.fakeJPEG }, emit: sink.add)
        let f = Self.frame()
        XCTAssertTrue(relay.push(f, ptsMs: 0))
        entered.wait()
        relay.stop()
        gate.signal()
        relay.waitIdle()
        XCTAssertEqual(sink.events.count, 0, "el que estaba en curso no se emite tras stop")
        XCTAssertFalse(relay.push(f, ptsMs: 1))
        XCTAssertFalse(relay.stats.running)
        XCTAssertEqual(relay.stats.sent, 0)
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

    /// Bajo presión real (empujes seguidos sin esperar): nada se encola, todo se cuenta y `push` no bloquea.
    func testPressureWithRealEncoder() {
        let relay = FrameRelay(channel: "t-pressure", maxFPS: 1_000_000, emit: { _, _ in })   // solo cuenta «ocupado»
        let f = Self.frame(width: 1920, height: 1080)
        var worst = 0.0
        for i in 0..<300 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            relay.push(f, ptsMs: Double(i))
            worst = max(worst, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
            Thread.sleep(forTimeInterval: 0.0002)
        }
        relay.waitIdle()
        let s = relay.stats
        print(String(format: "W2-E1 relevo bajo presión 1080p: %d enviados, %d ocupado, %d cadencia; JPEG p50 %.2f ms p95 %.2f; total p50 %.2f ms; push peor %.4f ms",
                     s.sent, s.droppedBusy, s.droppedRate, s.encodeP50Ms, s.encodeP95Ms, s.totalP50Ms, worst))
        XCTAssertEqual(s.sent + s.droppedBusy + s.droppedRate, 300)
        XCTAssertGreaterThan(s.droppedBusy, 0)
        XCTAssertLessThan(worst, Self.maxPushMs)
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
