#if canImport(CoreVideo)
import CoreVideo
#endif
#if canImport(AVFoundation) && !os(Windows)
import AVFoundation
#endif
import Foundation
import XCTest
import VideoKit
@testable import AppCore

/// Medición R3 (cámara → JPEG → puente) y M2 (vista previa de Montaje → JPEG → puente), auditoría del paso 8.
/// Solo con `TF_FRAME_PERF=1`; no exige umbrales, imprime números. Fotogramas sintéticos con textura (sin cámara real).
final class FramePathPerfTests: XCTestCase {
    static let seconds = 5.0

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["TF_FRAME_PERF"] == "1" else { throw XCTSkip("medición (TF_FRAME_PERF != 1)") }
    }

    /// CPU del proceso (s); `nil` donde no hay `getrusage`.
    static func cpuSeconds() -> Double? {
        #if canImport(Darwin)
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
        #else
        return nil
        #endif
    }

    static func nowMs() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

    /// NV12 de rango de vídeo (lo que da la cámara del Mac, `CameraCapture`), con degradado y ruido para que el JPEG cueste.
    static func nv12(width w: Int, height h: Int, seed: Int) -> FramePixelBuffer {
        func paint(_ base: UnsafeMutableRawPointer, rowBytes: Int, rows: Int, cols: Int, lo: Int, span: Int) {
            var rng = UInt32(truncatingIfNeeded: seed &* 2_654_435_761 &+ 1)
            for y in 0..<rows {
                let row = (base + y * rowBytes).assumingMemoryBound(to: UInt8.self)
                for x in 0..<cols {
                    rng = rng &* 1_664_525 &+ 1_013_904_223
                    row[x] = UInt8(lo + ((x * 3 + y * 2 + seed * 7) % span + Int(rng >> 28)) % span)
                }
            }
        }
        #if canImport(CoreVideo)
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        paint(CVPixelBufferGetBaseAddressOfPlane(pb!, 0)!, rowBytes: CVPixelBufferGetBytesPerRowOfPlane(pb!, 0), rows: h, cols: w, lo: 16, span: 219)
        paint(CVPixelBufferGetBaseAddressOfPlane(pb!, 1)!, rowBytes: CVPixelBufferGetBytesPerRowOfPlane(pb!, 1), rows: h / 2, cols: w, lo: 96, span: 64)
        CVPixelBufferUnlockBaseAddress(pb!, [])
        return pb!
        #else
        let pb = FramePixelBuffer(pixelFormat: .nv12, width: w, height: h)
        paint(pb.planeBaseAddress(0), rowBytes: pb.bytesPerRow, rows: h, cols: w, lo: 16, span: 219)
        paint(pb.planeBaseAddress(1), rowBytes: pb.bytesPerRow, rows: pb.planeHeight(1), cols: w, lo: 96, span: 64)
        return pb
        #endif
    }

    final class Lat: @unchecked Sendable {
        private let lock = NSLock()
        private var v: [Double] = []
        func add(_ x: Double) { lock.lock(); v.append(x); lock.unlock() }
        func pct(_ p: Double) -> Double {
            lock.lock(); defer { lock.unlock() }
            guard !v.isEmpty else { return 0 }
            let s = v.sorted(); return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))]
        }
    }

    /// Fuente a `fps` en tiempo real durante `seconds` empujando a un relevo real; `produce(i)` da el fotograma (y su coste
    /// cuenta como parte del camino). Devuelve el resumen.
    func run(label: String, fps: Double, relayFPS: Double, latestWins: Bool, produce: (Int) throws -> FramePixelBuffer) rethrows -> String {
        let lat = Lat(), produceMs = Lat()
        let relay = FrameRelay(channel: "perf-\(label)", maxFPS: relayFPS, latestWins: latestWins) { name, e in
            _ = Router.eventMessage(name, e)          // lo que hace `Bridge.emit` antes de mandarlo a la página
            lat.add(Self.nowMs() - e.ptsMs)
        }
        let n = Int(Self.seconds * fps)
        let cpu0 = Self.cpuSeconds(), t0 = Self.nowMs()
        for i in 0..<n {
            let due = t0 + Double(i) * 1000 / fps
            while Self.nowMs() < due { Thread.sleep(forTimeInterval: 0.0005) }
            let p0 = Self.nowMs()
            let f = try produce(i)
            produceMs.add(Self.nowMs() - p0)
            relay.push(f, ptsMs: Self.nowMs())
        }
        relay.waitIdle()
        let wall = (Self.nowMs() - t0) / 1000
        var cpu: Double?
        if let c0 = cpu0, let c1 = Self.cpuSeconds() { cpu = (c1 - c0) / wall * 100 }
        let s = relay.stats
        let cpuText: String = cpu.map { String(format: "%.1f %% de un núcleo", $0) } ?? "n/d"
        let sustained: Double = Double(s.sent) / wall
        let a = String(format: "%@: fuente %.0f fps, relevo máx. %.0f → %.1f fps sostenidos (%d enviados, %d ocupado, %d cadencia)",
                       label, fps, relayFPS, sustained, s.sent, s.droppedBusy, s.droppedRate)
        let b = String(format: "; producir p50 %.2f p95 %.2f ms; JPEG p50 %.2f p95 %.2f ms; JPEG+base64+emit p50 %.2f p95 %.2f ms",
                       produceMs.pct(0.5), produceMs.pct(0.95), s.encodeP50Ms, s.encodeP95Ms, s.totalP50Ms, s.totalP95Ms)
        let c = String(format: "; latencia push→emit p50 %.2f p95 %.2f ms; %d B/fotograma; CPU ", lat.pct(0.5), lat.pct(0.95), s.meanBytes)
        return a + b + c + cpuText
    }

    /// R3: cámara sintética NV12 a 30 fps → relevo de la cámara (15 fps, 640 px), y techo del JPEG solo.
    func testR3CameraPath() {
        for (w, h) in [(1920, 1080), (1280, 720)] {
            let frames = (0..<8).map { Self.nv12(width: w, height: h, seed: $0) }
            let enc = FrameJPEGEncoder()
            _ = try? enc.encode(frames[0])
            let t0 = Self.nowMs()
            for i in 0..<60 { _ = try? enc.encode(frames[i % 8]) }
            let each = (Self.nowMs() - t0) / 60
            print(String(format: "R3 [medición] %d×%d NV12: JPEG seguido %.2f ms/fotograma → techo %.0f fps", w, h, each, 1000 / each))
            print("R3 [medición] " + run(label: "cámara \(w)×\(h)", fps: 30, relayFPS: FrameRelay.defaultMaxFPS, latestWins: false) { frames[$0 % 8] })
        }
    }

    #if canImport(AVFoundation) && !os(Windows)
    /// M2: toma sintética 1280×720 a 30 fps, composición del Mac (`MacMontageComposer`) a 640 px, bucle de la vista previa a
    /// 15 y 30 fps → relevo de Montaje (60 fps, `latestWins`). «producir» = componer el fotograma.
    func testM2MontagePreviewPath() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("m2-perf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("take.mov"), fps = 30.0, count = 150
        let writer = try VideoTakeWriter(url: url, format: VideoFormat(cameraID: "sim", cameraName: "sim", width: 1280, height: 720, fps: fps),
                                         realTime: false)
        for i in 0..<count {
            let frame = CameraFrame(hostSeconds: 0, arrivalHostSeconds: 0, sequence: i, pixelBuffer: Self.nv12(width: 1280, height: 720, seed: i))
            XCTAssertTrue(writer.append(frame, songTime: Double(i) / fps))
        }
        _ = try await writer.finish()
        let take = MontageSpan(start: 0, end: Double(count) / fps)
        for (layout, parts) in [(MontageLayoutKind.single, 1), (.side, 2)] {
            let ps = (0..<parts).map { MontagePart(id: "p\($0)", name: "P\($0)", isSolo: false, presence: [take],
                                                   video: MontagePartVideo(url: url, videoOffset: 0, take: take)) }
            let plan = MontagePlan(canvas: .landscape, fps: fps, layout: layout, span: take, barDuration: 1, fadeIn: false,
                                   fadeOut: false, parts: ps, showPartLabels: false)
            let composer = try await MontageServices.production.makeComposer(plan, MontagePlanning.previewMaxDimension)
            for previewFPS in [15.0, 30.0] {
                let line = try run(label: "montaje \(layout.rawValue) a \(Int(previewFPS)) fps", fps: previewFPS,
                                   relayFPS: Bridge.montageRelayMaxFPS, latestWins: true) { i in
                    try composer.frame(atVideoTime: (Double(i) / previewFPS).truncatingRemainder(dividingBy: composer.duration))
                }
                print("M2 [medición] " + line)
            }
        }
    }
    #endif
}
