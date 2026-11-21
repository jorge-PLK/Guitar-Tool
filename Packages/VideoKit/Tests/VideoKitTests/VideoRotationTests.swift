#if canImport(AVFoundation)
import AVFoundation
import XCTest
@testable import VideoKit

/// «Rotar» (decisión de Jorge del 17/11/2026): una toma de 1920 × 1080 con una marca roja en la esquina de arriba a
/// la izquierda, girada 90° en sentido horario, se lee como 1080 × 1920 con la marca arriba a la derecha, sin
/// recodificar la toma: en el montaje (compositor) y en el reproductor de tomas (`TakePreview`).
final class VideoRotationTests: XCTestCase {
    static let size = (w: 1920, h: 1080)
    /// Lado de la marca roja (px del fichero).
    static let mark = 200

    /// `video.mov` de 1 s a 30 fps: gris con la marca roja arriba a la izquierda.
    static func writeMarkedVideo(_ url: URL) async throws {
        let writer = try VideoTakeWriter(url: url, format: VideoFormat(cameraID: "sim", cameraName: "sim", width: size.w, height: size.h, fps: 30),
                                         realTime: false)
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, size.w, size.h, kCVPixelFormatType_32BGRA, nil, &pb)
        let buffer = try XCTUnwrap(pb)
        CVPixelBufferLockBaseAddress(buffer, [])
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<size.h {
            for x in 0..<size.w {
                let o = y * row + x * 4, red = x < mark && y < mark
                base[o] = red ? 0 : 0x80; base[o + 1] = red ? 0 : 0x80; base[o + 2] = red ? 0xFF : 0x80; base[o + 3] = 0xFF
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for i in 0..<30 {
            XCTAssertTrue(writer.append(CameraFrame(hostSeconds: 0, arrivalHostSeconds: 0, sequence: i, pixelBuffer: buffer), songTime: Double(i) / 30))
        }
        _ = try await writer.finish()
    }

    static func isRed(_ c: (Double, Double, Double)) -> Bool { c.0 > 150 && c.1 < 80 && c.2 < 80 }
    static func isGray(_ c: (Double, Double, Double)) -> Bool { abs(c.0 - c.1) < 30 && abs(c.1 - c.2) < 30 && c.0 > 80 }

    /// Las cuatro esquinas (fracción del ancho y del alto): solo la de arriba a la derecha es roja.
    static func checkCorners(_ f: MontageGateTests.Frame, _ label: String) -> String {
        let w = Double(f.width), h = Double(f.height)
        let corners = [("arriba-dcha", 0.95, 0.03), ("arriba-izda", 0.05, 0.03), ("abajo-izda", 0.05, 0.97), ("abajo-dcha", 0.95, 0.97)]
        var line: [String] = []
        for (name, fx, fy) in corners {
            let c = f.rgb(fx * w, fy * h)
            line.append(String(format: "%@ (%.0f, %.0f, %.0f)", name, c.0, c.1, c.2))
            if name == "arriba-dcha" {
                XCTAssertTrue(isRed(c), "\(label): marca roja arriba a la derecha, leído \(c)")
            } else {
                XCTAssertTrue(isGray(c), "\(label): \(name) gris, leído \(c)")
            }
        }
        return line.joined(separator: ", ")
    }

    func testRotated90TakeReadsPortraitWithMarkTopRight() async throws {
        XCTAssertEqual(VideoRotation(degrees: 450), .clockwise90)
        XCTAssertEqual(VideoRotation.clockwise270.next, .none)
        let dir = try TestWav.tempDir("VideoRotationTests")
        let url = dir.appendingPathComponent("video.mov")
        try await Self.writeMarkedVideo(url)
        let take = MontageSpan(start: 0, end: 1)

        // Montaje: plano único portrait, la toma girada llena el lienzo.
        let part = MontagePart(id: "R", name: "R", isSolo: false, presence: [take],
                               video: MontagePartVideo(url: url, videoOffset: 0, take: take, rotation: .clockwise90))
        let plan = MontagePlan(canvas: .portrait, fps: 30, layout: .single, span: take, barDuration: 1, fadeIn: false, fadeOut: false,
                               parts: [part], showPartLabels: false)
        let builder = try await MontageBuilder.load(plan, includeAudio: false)
        XCTAssertEqual(builder.timeline.parts.first?.frameSize, CGSize(width: 1080, height: 1920), "tamaño del fotograma girado")
        let preview = try builder.make(renderSize: CGSize(width: 360, height: 640), includeAudio: false)
        let gen = MontageGateTests.generator(preview.composition, videoComposition: preview.videoComposition)
        let montage = try await MontageGateTests.frame(gen, at: 0.7)
        let m = Self.checkCorners(montage, "montaje")

        // Reproductor de tomas: la pista lleva la transformación, el fichero no se toca.
        let wav = dir.appendingPathComponent("processed.wav")
        try TestWav.write([[Float](repeating: 0, count: 48_000)], sampleRate: 48_000, to: wav)
        let tp = try await TakePreview.load(audioURL: wav, songStart: 0, videoURL: url, punches: [], rotation: .clockwise90)
        let comp = try tp.composition(videoOffset: 0)
        let tgen = MontageGateTests.generator(comp)
        tgen.appliesPreferredTrackTransform = true
        let (img, _) = try await tgen.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
        XCTAssertEqual(img.width, 1080)
        XCTAssertEqual(img.height, 1920)
        let player = try await MontageGateTests.frame(tgen, at: 0.5)
        let p = Self.checkCorners(player, "reproductor")
        // El fichero sigue en 1920 × 1080 (sin recodificar).
        let natural = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first!.load(.naturalSize)
        XCTAssertEqual(natural, CGSize(width: 1920, height: 1080))
        print("F7 rotar 90°: montaje \(montage.width)×\(montage.height): \(m); reproductor \(player.width)×\(player.height): \(p)")
    }
}
#else
import Foundation
import XCTest
@testable import VideoKit

/// Windows (parte 7.9): el giro se aplica al leer cada fotograma (`VideoRotation.apply`), en el compositor y en
/// `TakePreview`; el fichero no se toca.
final class VideoRotationTests: XCTestCase {
    static let size = (w: 1920, h: 1080)
    static let mark = 200

    static func writeMarkedVideo(_ url: URL) async throws {
        let writer = try VideoTakeWriter(url: url, format: VideoFormat(cameraID: "sim", cameraName: "sim", width: size.w, height: size.h, fps: 30),
                                         realTime: false)
        let pb = RenderSupport.buffer(width: size.w, height: size.h) { x, y in x < mark && y < mark ? (0xFF, 0, 0) : (0x80, 0x80, 0x80) }
        for i in 0..<30 {
            XCTAssertTrue(writer.append(CameraFrame(hostSeconds: 0, arrivalHostSeconds: 0, sequence: i, pixelBuffer: pb), songTime: Double(i) / 30))
        }
        _ = try await writer.finish()
    }

    static func isRed(_ c: (Double, Double, Double)) -> Bool { c.0 > 150 && c.1 < 80 && c.2 < 80 }
    static func isGray(_ c: (Double, Double, Double)) -> Bool { abs(c.0 - c.1) < 30 && abs(c.1 - c.2) < 30 && c.0 > 80 }

    static func checkCorners(_ f: MontageGateTests.Frame, _ label: String) -> String {
        let w = Double(f.width), h = Double(f.height)
        var line: [String] = []
        for (name, fx, fy) in [("arriba-dcha", 0.95, 0.03), ("arriba-izda", 0.05, 0.03), ("abajo-izda", 0.05, 0.97), ("abajo-dcha", 0.95, 0.97)] {
            let c = f.rgb(fx * w, fy * h)
            line.append(String(format: "%@ (%.0f, %.0f, %.0f)", name, c.0, c.1, c.2))
            if name == "arriba-dcha" {
                XCTAssertTrue(isRed(c), "\(label): marca roja arriba a la derecha, leído \(c)")
            } else {
                XCTAssertTrue(isGray(c), "\(label): \(name) gris, leído \(c)")
            }
        }
        return line.joined(separator: ", ")
    }

    func testRotated90TakeReadsPortraitWithMarkTopRight() async throws {
        XCTAssertEqual(VideoRotation(degrees: 450), .clockwise90)
        XCTAssertEqual(VideoRotation.clockwise270.next, .none)
        let dir = try TestWav.tempDir("VideoRotationTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("video.mov")
        try await Self.writeMarkedVideo(url)
        let take = MontageSpan(start: 0, end: 1)
        let part = MontagePart(id: "R", name: "R", isSolo: false, presence: [take],
                               video: MontagePartVideo(url: url, videoOffset: 0, take: take, rotation: .clockwise90))
        let plan = MontagePlan(canvas: .portrait, fps: 30, layout: .single, span: take, barDuration: 1, fadeIn: false, fadeOut: false,
                               parts: [part], showPartLabels: false)
        let builder = try await MontageBuilder.load(plan, includeAudio: false)
        XCTAssertEqual(builder.timeline.parts.first?.frameSize, CGSize(width: 1080, height: 1920), "tamaño del fotograma girado")
        let preview = try builder.make(renderSize: CGSize(width: 360, height: 640), includeAudio: false)
        let montage = MontageGateTests.Frame(try preview.frame(at: 0.7))
        let m = Self.checkCorners(montage, "montaje")
        let wav = dir.appendingPathComponent("processed.wav")
        try TestWav.write([[Float](repeating: 0, count: 48_000)], sampleRate: 48_000, to: wav)
        let tp = try await TakePreview.load(audioURL: wav, songStart: 0, videoURL: url, punches: [], rotation: .clockwise90)
        let img = try XCTUnwrap(try tp.frame(at: 0.5, videoOffset: 0))
        XCTAssertEqual([img.width, img.height], [1080, 1920])
        let p = Self.checkCorners(MontageGateTests.Frame(img), "reproductor")
        let info = try MediaFoundationReader.info(url)
        XCTAssertEqual([info.width, info.height], [1920, 1080])
        print("7.9 rotar 90°: montaje \(montage.width)×\(montage.height): \(m); reproductor \(img.width)×\(img.height): \(p)")
    }
}
#endif // canImport(AVFoundation)
