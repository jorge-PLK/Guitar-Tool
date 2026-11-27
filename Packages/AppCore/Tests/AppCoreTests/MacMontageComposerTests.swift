#if canImport(AVFoundation) && !os(Windows)
import AVFoundation
import Foundation
import XCTest
import VideoKit
@testable import AppCore

/// W2-E2: compositor de la vista previa de Montaje en el Mac (`MacMontageComposer`, `AVAssetImageGenerator` sobre la
/// composición de `MontagePreview`), el que usa `tf-webdev`. Punto fino: el fotograma devuelto es el de ese instante,
/// también a 1 ms a cada lado del cambio de fotograma. Toma sintética a 30 fps exactos con un gris distinto por fotograma
/// (30 + 9·i), así que el brillo del centro dice qué fotograma salió.
final class MacMontageComposerTests: XCTestCase {
    static let fps = 30.0
    static let frames = 24
    static let takeStart = 2.0
    /// Distancia al cambio de fotograma que se comprueba (s).
    static let edge = 0.001

    static func level(_ i: Int) -> UInt8 { UInt8(30 + 9 * i) }

    private func writeTake(_ url: URL) async throws {
        let writer = try VideoTakeWriter(url: url, format: VideoFormat(cameraID: "sim", cameraName: "sim", width: 320, height: 180,
                                                                       fps: Self.fps), realTime: false)
        for i in 0..<Self.frames {
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, 320, 180, kCVPixelFormatType_32BGRA, nil, &pb)
            let buffer = try XCTUnwrap(pb)
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(Self.level(i)), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let frame = CameraFrame(hostSeconds: 0, arrivalHostSeconds: 0, sequence: i, pixelBuffer: buffer)
            XCTAssertTrue(writer.append(frame, songTime: Self.takeStart + Double(i) / Self.fps))
        }
        _ = try await writer.finish()
    }

    /// Verde medio de un cuadro 5×5 en el centro.
    private func center(_ pb: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), row = CVPixelBufferGetBytesPerRow(pb)
        let p = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        var sum = 0.0
        for y in (h / 2 - 2)...(h / 2 + 2) { for x in (w / 2 - 2)...(w / 2 + 2) { sum += Double(p[y * row + x * 4 + 1]) } }
        return sum / 25
    }

    /// «Vista previa en negro»: el búfer debe ser IOSurface + Metal para que Flutter lo pase a una textura.
    func testBGRABufferIsIOSurfaceBackedAndKeepsContent() throws {
        let w = 64, h = 48
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        ctx.setFillColor(CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [200 / 255, 100 / 255, 50 / 255, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let image = try XCTUnwrap(ctx.makeImage())
        // Dos veces seguidas (la segunda sale del pool) y con otro tamaño (pool nuevo).
        for _ in 0..<2 {
            let pb = try MacMontageComposer.bgra(image)
            XCTAssertNotNil(CVPixelBufferGetIOSurface(pb))
            XCTAssertEqual(CVPixelBufferGetPixelFormatType(pb), kCVPixelFormatType_32BGRA)
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            let p = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
            let o = (h / 2) * CVPixelBufferGetBytesPerRow(pb) + (w / 2) * 4
            XCTAssertEqual([p[o], p[o + 1], p[o + 2], p[o + 3]], [50, 100, 200, 255])
            CVPixelBufferUnlockBaseAddress(pb, .readOnly)
        }
        let solid = try XCTUnwrap(MontageFrameImage.solid(width: 32, height: 18, b: 1, g: 2, r: 3))
        XCTAssertNotNil(CVPixelBufferGetIOSurface(solid))
    }

    func testFrameAtEachSideOfFrameBoundary() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mac-composer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("take.mov")
        try await writeTake(url)
        let take = MontageSpan(start: Self.takeStart, end: Self.takeStart + Double(Self.frames) / Self.fps)
        let part = MontagePart(id: "a", name: "A", isSolo: false, presence: [take],
                               video: MontagePartVideo(url: url, videoOffset: 0, take: take))
        let plan = MontagePlan(canvas: .landscape, fps: Self.fps, layout: .single, span: take, barDuration: 1, fadeIn: false,
                               fadeOut: false, parts: [part], showPartLabels: false)
        let composer = try await MontageServices.production.makeComposer(plan, MontagePlanning.previewMaxDimension)
        XCTAssertTrue(composer is MacMontageComposer)
        XCTAssertEqual(composer.duration, plan.videoDuration, accuracy: 1e-9)

        // Referencia: brillo a mitad de cada fotograma.
        var ref: [Double] = []
        var millis: [Double] = []
        var size = (0, 0)
        for k in 0..<Self.frames {
            let t0 = Date()
            let pb = try composer.frame(atVideoTime: (Double(k) + 0.5) / Self.fps)
            millis.append(Date().timeIntervalSince(t0) * 1000)
            size = (CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb))
            XCTAssertEqual(CVPixelBufferGetPixelFormatType(pb), kCVPixelFormatType_32BGRA)
            ref.append(center(pb))
        }
        // Los fotogramas centrales se distinguen (sube más de 3 niveles de uno a otro).
        let checked = 3..<(Self.frames - 3)
        for k in checked.dropFirst() { XCTAssertGreaterThan(ref[k] - ref[k - 1], 3, "referencia \(k): \(ref)") }
        func nearest(_ v: Double) -> Int { ref.indices.min { abs(ref[$0] - v) < abs(ref[$1] - v) }! }

        var misses: [String] = []
        for k in checked.dropFirst() {
            let boundary = Double(k) / Self.fps
            let before = nearest(center(try composer.frame(atVideoTime: boundary - Self.edge)))
            let after = nearest(center(try composer.frame(atVideoTime: boundary + Self.edge)))
            if before != k - 1 { misses.append("\(k)-1ms→\(before)") }
            if after != k { misses.append("\(k)+1ms→\(after)") }
        }
        // Instantes fuera del vídeo: se recortan, sin error.
        XCTAssertNoThrow(try composer.frame(atVideoTime: -1))
        XCTAssertNoThrow(try composer.frame(atVideoTime: composer.duration + 1))

        let sorted = millis.sorted()
        print(String(format: "MacMontageComposer: %d×%d, componer p50 %.1f ms, p95 %.1f ms; cambios de fotograma a ±1 ms: %d/%d bien",
                     size.0, size.1, sorted[sorted.count / 2], sorted[Int(Double(sorted.count - 1) * 0.95)],
                     2 * (checked.count - 1) - misses.count, 2 * (checked.count - 1)))
        XCTAssertEqual(max(size.0, size.1), MontagePlanning.previewMaxDimension)
        XCTAssertEqual(misses, [], "fotograma equivocado a 1 ms del cambio")
    }
}
#endif
