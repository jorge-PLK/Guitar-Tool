#if canImport(AVFoundation) && !os(Windows)
import AVFoundation
import Foundation
import XCTest
import VideoKit
@testable import AppCore

/// M1 (parte 3): fotograma de la toma para la hoja «Encuadre» en el Mac (`MontageServices.production.takeFrame`, el que
/// usa `MontageController.framingFrame`). Punto fino: con desfase y punch, el fotograma devuelto es el de ese instante del
/// tema, también a 1 ms a cada lado de cada cambio de fotograma, de la entrada y salida del punch y del final de la imagen.
/// Base sintética a 30 fps con un gris distinto por fotograma (30 + 9·i); punch azul liso.
final class MacTakeFrameTests: XCTestCase {
    static let fps = 30.0
    static let frames = 24
    static let takeStart = 2.0
    static let take = MontageSpan(start: takeStart, end: takeStart + Double(frames) / fps)
    /// Desfase de la base (positivo: su imagen llega tarde) y del punch.
    static let baseOffset = 0.0123
    static let punchOffset = -0.004
    static let punch = (start: 2.3, end: 2.5)
    /// Distancia al cambio que se comprueba (s).
    static let edge = 0.001

    static func level(_ i: Int) -> UInt8 { UInt8(30 + 9 * i) }

    /// `frames` fotogramas desde `start` (tiempo del tema); `bgr(i)` es el color del fotograma i.
    private func writeVideo(_ url: URL, start: Double, frames: Int, bgr: (Int) -> (UInt8, UInt8, UInt8)) async throws {
        let writer = try VideoTakeWriter(url: url, format: VideoFormat(cameraID: "sim", cameraName: "sim", width: 320, height: 180,
                                                                       fps: Self.fps), realTime: false)
        for i in 0..<frames {
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, 320, 180, kCVPixelFormatType_32BGRA, nil, &pb)
            let buffer = try XCTUnwrap(pb)
            CVPixelBufferLockBaseAddress(buffer, [])
            let row = CVPixelBufferGetBytesPerRow(buffer)
            let p = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let (b, g, r) = bgr(i)
            for y in 0..<180 { for x in 0..<320 { let o = y * row + x * 4; p[o] = b; p[o + 1] = g; p[o + 2] = r; p[o + 3] = 255 } }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(writer.append(CameraFrame(hostSeconds: 0, arrivalHostSeconds: 0, sequence: i, pixelBuffer: buffer),
                                        songTime: start + Double(i) / Self.fps))
        }
        _ = try await writer.finish()
    }

    /// Verde y azul medios de un cuadro 5×5 en el centro.
    private func center(_ pb: CVPixelBuffer) -> (g: Double, b: Double) {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), row = CVPixelBufferGetBytesPerRow(pb)
        let p = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        var g = 0.0, b = 0.0
        for y in (h / 2 - 2)...(h / 2 + 2) {
            for x in (w / 2 - 2)...(w / 2 + 2) { b += Double(p[y * row + x * 4]); g += Double(p[y * row + x * 4 + 1]) }
        }
        return (g / 25, b / 25)
    }

    func testTakeFrameAtEachSideOfFramePunchAndEndBoundaries() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mac-take-frame-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = dir.appendingPathComponent("processed.wav")
        try await StudyTests.writeSine(audio, frequency: 220, seconds: Self.take.end - Self.take.start)
        let baseURL = dir.appendingPathComponent("video.mov"), punchURL = dir.appendingPathComponent("p1.mov")
        try await writeVideo(baseURL, start: Self.takeStart, frames: Self.frames) { i in (Self.level(i), Self.level(i), Self.level(i)) }
        // Punch: imagen de 2,2 a 2,6 s; manda en 2,3–2,5.
        try await writeVideo(punchURL, start: 2.2, frames: 12) { _ in (220, 30, 30) }

        let take = Self.take
        let plain = MontagePartVideo(url: baseURL, videoOffset: 0, take: take)
        let video = MontagePartVideo(url: baseURL, videoOffset: Self.baseOffset,
                                     punches: [PreviewPunch(start: Self.punch.start, end: Self.punch.end, videoURL: punchURL,
                                                            videoOffset: Self.punchOffset)], take: take)
        let services = MontageServices.production
        var millis: [Double] = []
        func frame(_ v: MontagePartVideo, _ t: Double) async throws -> CVPixelBuffer? {
            let t0 = Date()
            defer { millis.append(Date().timeIntervalSince(t0) * 1000) }
            return try await services.takeFrame(v, audio, t)
        }

        // Referencia: brillo a mitad de cada fotograma, sin desfase ni punch.
        var ref: [Double] = []
        for k in 0..<Self.frames {
            let pb = try await frame(plain, Self.takeStart + (Double(k) + 0.5) / Self.fps)
            let px = try XCTUnwrap(pb, "fotograma \(k)")
            XCTAssertEqual(CVPixelBufferGetPixelFormatType(px), kCVPixelFormatType_32BGRA)
            XCTAssertEqual(CVPixelBufferGetWidth(px), 320)
            XCTAssertEqual(CVPixelBufferGetHeight(px), 180)
            ref.append(center(px).g)
        }
        for k in 1..<Self.frames { XCTAssertGreaterThan(ref[k] - ref[k - 1], 3, "referencia \(k): \(ref)") }
        func nearest(_ pb: CVPixelBuffer?) -> String {
            guard let pb else { return "nil" }
            let c = center(pb)
            if c.b - c.g > 80 { return "punch" }
            return "\(ref.indices.min { abs(ref[$0] - c.g) < abs(ref[$1] - c.g) }!)"
        }

        // Cambios de fotograma de la base con desfase: el fotograma k (PTS 2 + k/30) se ve desde 2 + k/30 − desfase.
        var misses: [String] = [], checks = 0
        for k in Array(2...7) + Array(16...21) {
            let boundary = Self.takeStart + Double(k) / Self.fps - Self.baseOffset
            let before = nearest(try await frame(video, boundary - Self.edge))
            let after = nearest(try await frame(video, boundary + Self.edge))
            if before != "\(k - 1)" { misses.append("\(k)-1ms→\(before)") }
            if after != "\(k)" { misses.append("\(k)+1ms→\(after)") }
            checks += 2
        }
        // Entrada y salida del punch, final de la imagen de la base (2,8 − desfase) y fuera de la toma.
        let lastVisible = Self.take.end - Self.baseOffset
        let expected: [(Double, String)] = [
            // 2,299 s + desfase = PTS 2,3113 → fotograma 9; 2,501 s → PTS 2,5133 → fotograma 15.
            (Self.punch.start - Self.edge, "9"), (Self.punch.start + Self.edge, "punch"),
            (Self.punch.end - Self.edge, "punch"), (Self.punch.end + Self.edge, "15"),
            (lastVisible - Self.edge, "\(Self.frames - 1)"), (lastVisible + Self.edge, "nil"),
            (Self.takeStart - Self.edge, "nil"), (Self.take.end + Self.edge, "nil")
        ]
        for (t, want) in expected {
            let got = nearest(try await frame(video, t))
            if got != want { misses.append(String(format: "%.4f→%@ (quería %@)", t, got, want)) }
            checks += 1
        }

        // Giro: la imagen sale girada (180×320), como en Windows.
        var rotated = video
        rotated.rotation = .clockwise90
        let rotatedFrame = try await frame(rotated, Self.takeStart + 0.1)
        let r = try XCTUnwrap(rotatedFrame)
        XCTAssertEqual(CVPixelBufferGetWidth(r), 180)
        XCTAssertEqual(CVPixelBufferGetHeight(r), 320)

        let sorted = millis.sorted()
        print(String(format: "M1 takeFrame Mac: %d/%d instantes bien a ±1 ms (cambios de fotograma, punch, final); p50 %.1f ms, p95 %.1f ms",
                     checks - misses.count, checks, sorted[sorted.count / 2], sorted[Int(Double(sorted.count - 1) * 0.95)]))
        XCTAssertEqual(misses, [], "fotograma equivocado a 1 ms del cambio")
    }
}
#endif
