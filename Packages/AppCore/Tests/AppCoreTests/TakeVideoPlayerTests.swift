#if canImport(AVFoundation)
import AVFoundation
import CoreMedia
import Foundation
import VideoKit
import XCTest
@testable import AppCore

/// Reproductor nativo del vídeo de tomas (ola 3.3.AS; arquitectura.md, «Vídeo de tomas»). Mapa reloj → posición, ciclo
/// open/close sobre una toma real de `Temp/flutter/val-projects` y, opt-in (`TF_VIDEO_MEASURE=1`), medida del error A/V.
final class TakeVideoPlayerTests: XCTestCase {
    private func event(_ s: Double, playing: Bool = true, rate: Double = 1, at: Double = 100, epoch: Int = 1) -> TakeViewPositionEvent {
        TakeViewPositionEvent(seconds: s, playing: playing, rate: rate, at: at, epoch: epoch)
    }

    func testPositionMapPlayingPausedAndRate() {
        let m = TakeVideoClockMap(event(10, at: 100))
        XCTAssertEqual(m.position(at: 102), 12, accuracy: 1e-9)
        XCTAssertEqual(TakeVideoClockMap(event(10, rate: 0.7, at: 100)).position(at: 102), 11.4, accuracy: 1e-9)
        // En pausa o esperando la primera muestra (rate 0) la posición no avanza.
        XCTAssertEqual(TakeVideoClockMap(event(10, playing: false, at: 100)).position(at: 105), 10, accuracy: 1e-9)
        let waiting = TakeVideoClockMap(event(10, playing: true, rate: 0, at: 100))
        XCTAssertFalse(waiting.moving)
        XCTAssertEqual(waiting.position(at: 105), 10, accuracy: 1e-9)
    }

    func testNeedsResync() {
        let base = TakeVideoClockMap(event(10, at: 100, epoch: 3))
        XCTAssertTrue(base.needsResync(from: nil))
        // Refresco de reloj (30 Hz): mismos play/rate/epoch, otra posición → no resincroniza.
        XCTAssertFalse(TakeVideoClockMap(event(10.5, at: 100.5, epoch: 3)).needsResync(from: base))
        XCTAssertTrue(TakeVideoClockMap(event(10, at: 100, epoch: 4)).needsResync(from: base))
        XCTAssertTrue(TakeVideoClockMap(event(10, playing: false, at: 100, epoch: 3)).needsResync(from: base))
        XCTAssertTrue(TakeVideoClockMap(event(10, rate: 0.7, at: 100, epoch: 3)).needsResync(from: base))
        XCTAssertTrue(TakeVideoClockMap(event(10, rate: 0, at: 100, epoch: 3)).needsResync(from: base))
    }

    func testCoreMediaHostClockMatchesHostClock() {
        for _ in 0..<5 {
            let a = HostClock.nowSeconds
            let b = CMClockGetTime(CMClockGetHostTimeClock()).seconds
            let c = HostClock.nowSeconds
            XCTAssertGreaterThanOrEqual(b, a - 0.001)
            XCTAssertLessThanOrEqual(b, c + 0.001)
        }
    }

    // MARK: toma real

    private struct Fixture { let video: URL; let audio: URL; let songStart: Double }

    private func fixture() throws -> Fixture {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Temp/flutter/val-projects/Megadeth - Tornado Of Souls/takes")
        let fm = FileManager.default
        guard let ids = try? fm.contentsOfDirectory(atPath: root.path) else { throw XCTSkip("sin val-projects") }
        for id in ids.sorted() {
            let v = root.appendingPathComponent(id).appendingPathComponent("video.mov")
            let a = root.appendingPathComponent(id).appendingPathComponent("processed.wav")
            if fm.fileExists(atPath: v.path), fm.fileExists(atPath: a.path) {
                return Fixture(video: v, audio: a, songStart: Self.songStart(ofTake: id, project: root.deletingLastPathComponent()))
            }
        }
        throw XCTSkip("sin toma con video.mov")
    }

    /// El PTS del vídeo va en tiempo del tema: `songStart` de la toma en `project.json` (0 si no se encuentra).
    private static func songStart(ofTake id: String, project: URL) -> Double {
        guard let data = try? Data(contentsOf: project.appendingPathComponent("project.json")),
              let json = try? JSONSerialization.jsonObject(with: data) else { return 0 }
        func find(_ n: Any) -> Double? {
            if let d = n as? [String: Any] {
                if d["id"] as? String == id, let s = d["songStart"] as? Double { return s }
                for v in d.values { if let r = find(v) { return r } }
            } else if let a = n as? [Any] {
                for v in a { if let r = find(v) { return r } }
            }
            return nil
        }
        return find(json) ?? 0
    }

    private func makePlayer() async throws -> TakeVideoPlayer {
        let f = try fixture()
        let preview = try await TakePreview.load(audioURL: f.audio, songStart: f.songStart, videoURL: f.video, punches: [])
        return try TakeVideoPlayer(preview: preview, offset: 0)
    }

    private func waitReady(_ p: TakeVideoPlayer, timeout: Double = 8) async throws {
        let t0 = HostClock.nowSeconds
        while !p.isReady, HostClock.nowSeconds - t0 < timeout { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(p.isReady)
    }

    func testOpenCloseCycleReleasesPlayer() async throws {
        weak var weakPlayer: TakeVideoPlayer?
        var frames = 0
        do {
            let p = try await makePlayer()
            weakPlayer = p
            try await waitReady(p)
            p.apply(event(0.5, at: HostClock.nowSeconds, epoch: 1))
            let t0 = HostClock.nowSeconds
            while HostClock.nowSeconds - t0 < 1.0 {
                if p.copyFrame() != nil { frames += 1 }
                try await Task.sleep(nanoseconds: 16_000_000)
            }
            p.close()
            p.close()  // idempotente
            XCTAssertNil(p.copyFrame(), "tras close no hay fotograma")
            XCTAssertNil(p.onFrameAvailable)
        }
        XCTAssertGreaterThan(frames, 0)
        // Dejar que se vacíen las tareas pendientes (la del «ready» tiene el reproductor débil).
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(weakPlayer, "TakeVideoPlayer fugado")
    }

    // MARK: fotograma en pausa (ola 3.3.AT)

    private final class Counter: @unchecked Sendable {
        private let l = NSLock(); private var n = 0
        var value: Int { l.lock(); defer { l.unlock() }; return n }
        func bump() { l.lock(); n += 1; l.unlock() }
    }

    private func waitCount(_ c: Counter, above n: Int, timeout: Double = 1.0) async throws {
        let t0 = HostClock.nowSeconds
        while c.value <= n, HostClock.nowSeconds - t0 < timeout { try await Task.sleep(nanoseconds: 5_000_000) }
    }

    /// PTS del buffer entregado: se mide por la imagen no; se comprueba con el contador de entregas y el buffer no nulo.
    func testPausedFramesOnOpenSeekAndOffset() async throws {
        let p = try await makePlayer()
        defer { p.close() }
        let c = Counter()
        p.onFrameAvailable = { c.bump() }
        // (a) Abrir en pausa.
        try await waitCount(c, above: 0)
        XCTAssertGreaterThan(c.value, 0, "sin aviso al abrir en pausa")
        XCTAssertNotNil(p.copyFrame())
        XCTAssertEqual(p.lastDisplaySeconds ?? -1, 0, accuracy: TakeVideoConstants.frameDuration)
        // (b) Seek en pausa a otra posición y de vuelta a 0.
        var epoch = 1
        for target in [2.0, 0.0] {
            epoch += 1
            let n = c.value
            p.apply(event(target, playing: false, at: HostClock.nowSeconds, epoch: epoch))
            try await waitCount(c, above: n, timeout: 2.0)
            XCTAssertGreaterThan(c.value, n, "sin aviso tras seek a \(target)")
            XCTAssertNotNil(p.copyFrame())
            XCTAssertEqual(p.lastDisplaySeconds ?? -1, target, accuracy: TakeVideoConstants.frameDuration, "PTS tras seek a \(target)")
        }
        // (c) setOffset en pausa.
        let n = c.value
        p.setOffset(0.25)
        try await waitCount(c, above: n, timeout: 3.0)
        XCTAssertGreaterThan(c.value, n, "sin aviso tras setOffset")
        XCTAssertNotNil(p.copyFrame())
    }

    // MARK: arrastre del timeline en pausa (ola 3.3.AV)

    /// Primera toma con vídeo y audio de un proyecto de `val-projects` cuyo nombre contiene `name` (según `project.json`).
    private func makePlayer(project name: String) async throws -> TakeVideoPlayer {
        let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Temp/flutter/val-projects")
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: src.path) else { throw XCTSkip("sin val-projects") }
        for n in names.sorted() where n.contains(name) {
            let folder = src.appendingPathComponent(n)
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("project.json")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let takes = json["takes"] as? [[String: Any]] else { continue }
            for t in takes {
                guard let v = t["videoFile"] as? String, let a = t["processedFile"] as? String, let s = t["songStart"] as? Double,
                      fm.fileExists(atPath: folder.appendingPathComponent(v).path),
                      fm.fileExists(atPath: folder.appendingPathComponent(a).path) else { continue }
                let preview = try await TakePreview.load(audioURL: folder.appendingPathComponent(a), songStart: s,
                                                         videoURL: folder.appendingPathComponent(v), punches: [])
                return try TakeVideoPlayer(preview: preview, offset: 0)
            }
        }
        throw XCTSkip("sin toma con vídeo en «\(name)»")
    }

    /// ~20 seeks en pausa cada 50 ms recorriendo la toma: llegan fotogramas intermedios distintos y el último es el del último destino.
    private func scrubBurst(project: String) async throws {
        let p = try await makePlayer(project: project)
        defer { p.close() }
        let c = Counter()
        p.onFrameAvailable = { c.bump() }
        try await waitReady(p)
        try await waitCount(c, above: 0, timeout: 3)
        let base = p.pausedDeliveredSeconds.count
        var epoch = 1
        let targets = (1...20).map { 0.4 * Double($0) }
        for target in targets {
            epoch += 1
            p.apply(event(target, playing: false, at: HostClock.nowSeconds, epoch: epoch))
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let burst = Array(p.pausedDeliveredSeconds.dropFirst(base))
        let intermediates = Set(burst.map { ($0 * 1000).rounded() }).count
        let t0 = HostClock.nowSeconds
        while (p.lastDisplaySeconds ?? -1) < targets.last! - TakeVideoConstants.frameDuration, HostClock.nowSeconds - t0 < 5 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let all = Array(p.pausedDeliveredSeconds.dropFirst(base))
        print("TF_SCRUB \(project) durante la ráfaga=\(burst.count) distintos=\(intermediates) total=\(all.count) pts=\(all.map { String(format: "%.2f", $0) })")
        XCTAssertGreaterThanOrEqual(intermediates, 3, "fotogramas intermedios durante la ráfaga: \(burst)")
        XCTAssertEqual(p.lastDisplaySeconds ?? -1, targets.last!, accuracy: TakeVideoConstants.frameDuration, "último fotograma")
    }

    func testScrubBurstInPause1920() async throws { try await scrubBurst(project: "El roce") }
    func testScrubBurstInPause640() async throws { try await scrubBurst(project: "Megadeth") }

    // MARK: medida opt-in (P9: |mediana| y |p95| ≤ medio fotograma; seek < 300 ms)

    private func median(_ v: [Double]) -> Double { let s = v.sorted(); return s.isEmpty ? .nan : s[s.count / 2] }
    private func p95(_ v: [Double]) -> Double { let s = v.sorted(); return s.isEmpty ? .nan : s[min(s.count - 1, Int(Double(s.count) * 0.95))] }

    /// Llama copyFrame() a ~60 Hz durante `seconds`.
    private func pump(_ p: TakeVideoPlayer, seconds: Double) async throws {
        let t0 = HostClock.nowSeconds
        var next = t0
        while HostClock.nowSeconds - t0 < seconds {
            _ = p.copyFrame()
            next += 1.0 / 60
            let wait = next - HostClock.nowSeconds
            if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
        }
    }

    func testMeasureAVSync() async throws {
        guard ProcessInfo.processInfo.environment["TF_VIDEO_MEASURE"] == "1" else { throw XCTSkip("TF_VIDEO_MEASURE=1 para medir") }
        let p = try await makePlayer()
        defer { p.close() }
        try await waitReady(p)
        var epoch = 1
        let half = TakeVideoConstants.halfFrame * 1000
        var report = "TF_VIDEO_MEASURE frame=\(TakeVideoConstants.frameDuration * 1000) ms\n"
        for rate in [1.0, 0.7] {
            epoch += 1
            let start = p.measureMark()
            p.apply(event(1.0, rate: rate, at: HostClock.nowSeconds, epoch: epoch))
            try await pump(p, seconds: 1.0)  // asentamiento
            let settled = p.measureMark()
            try await pump(p, seconds: 6.0)
            let e = Array(p.measuredErrors(since: settled))
            let delivered = p.measureMark().deliveries - start.deliveries
            let med = median(e), q = p95(e.map { abs($0) })
            // El PTS del fotograma mostrado va siempre por detrás del reloj (0…1 fotograma): se da también centrado.
            report += "rate \(rate): n=\(e.count) entregados=\(delivered) mediana=\(med) p95abs=\(q) | centrado: mediana=\(med - half) p95abs=\(p95(e.map { abs($0 - half) })) resyncs=\(p.measureMark().resyncs)\n"
            XCTAssertGreaterThan(e.count, 10, report)
        }
        // Recuperación tras seek: desde apply hasta el primer fotograma entregado con error < 1 fotograma.
        epoch += 1
        let before = p.measureMark()
        let t0 = HostClock.nowSeconds
        p.apply(event(4.0, rate: 1.0, at: t0, epoch: epoch))
        var seekMs = Double.nan
        while HostClock.nowSeconds - t0 < 3 {
            _ = p.copyFrame()
            let errs = p.measuredErrors(since: before)
            if let i = errs.firstIndex(where: { abs($0) < TakeVideoConstants.frameDuration * 1000 }) { _ = i; seekMs = (HostClock.nowSeconds - t0) * 1000; break }
            try await Task.sleep(nanoseconds: 4_000_000)
        }
        report += "seek: \(seekMs) ms"
        print(report)
        try? report.write(toFile: "/tmp/tf-video-measure.txt", atomically: true, encoding: .utf8)
    }
}

extension TakeVideoPlayer {
    struct MeasureMark { let deliveries: Int; let resyncs: Int; let errorCount: Int }
    func measureMark() -> MeasureMark { let m = measurements(); return MeasureMark(deliveries: m.deliveries, resyncs: m.resyncs, errorCount: m.errorsMs.count) }
    func measuredErrors(since m: MeasureMark) -> ArraySlice<Double> { measurements().errorsMs.dropFirst(m.errorCount) }
}
#endif
