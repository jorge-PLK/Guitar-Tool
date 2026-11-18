import AVFoundation
import XCTest
@testable import VideoKit

/// Puerta del fallo -11841 (`AVErrorInvalidVideoComposition`) con tomas reales (17/11/2026): el último tramo,
/// cuantizado hacia arriba, acaba hasta un fotograma después que la última imagen; un tramo vacío al final de una
/// pista no cuenta en la duración de la composición, así que la composición duraba menos que el plan (proyecto real:
/// 250,1589 s frente a 250,1667 s) y la lectura `[0, plan)` quedaba sin instrucción en la cola.
///
/// Tomas sintéticas como las de la cámara: 29,97 fps (1001/30000 s), primera imagen fuera de la rejilla y lejos de 0.
final class MontageCompositionCoverageTests: XCTestCase {
    static let fps = 30.0
    /// Periodo de la cámara a 29,97 fps (s).
    static let cameraPeriod = 1001.0 / 30_000
    /// Primera imagen de las tomas (s del tema), fuera de la rejilla de 30 fps.
    static let firstImage = 2.0237
    /// Invariante de la exportación: vídeo, audio del fichero y `mezcla.wav` con la misma duración (< medio fotograma).
    static let halfFrame = 0.5 / fps

    struct Variant {
        let name: String
        /// Tramo de la toma (audio) en tiempo del tema.
        let take: MontageSpan
        /// Imágenes escritas desde `firstImage`.
        let frames: Int
    }

    /// A: como el proyecto real, vídeo más largo que la toma y la toma acaba fuera de la rejilla (hueco de 7,8 ms).
    /// B: el vídeo acaba 7,3 ms (una fracción de fotograma) antes del final del tramo.
    /// C: el vídeo acaba 1,4 s antes que la toma, más que el fundido a negro (0,5 s, sobre el último fotograma retenido):
    /// negro hasta el final (`testTakeEndingEarlyFadesToBlack`).
    static let variants = [
        Variant(name: "A", take: MontageSpan(start: 2.0, end: 4.2589), frames: 90),
        Variant(name: "B", take: MontageSpan(start: 2.0, end: 4.4), frames: 71),
        Variant(name: "C", take: MontageSpan(start: 2.0, end: 4.4), frames: 30)
    ]

    /// `video.mov` a 29,97 fps con PTS = tiempo del tema, escrito con `VideoTakeWriter` (como Grabar).
    static func writeCameraVideo(_ url: URL, frames: Int) async throws -> Double {
        let writer = try VideoTakeWriter(url: url, format: VideoFormat(cameraID: "sim", cameraName: "sim", width: 320, height: 180,
                                                                       fps: 30_000.0 / 1001), realTime: false)
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 320, 180, kCVPixelFormatType_32BGRA, nil, &pb)
        let buffer = try XCTUnwrap(pb)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0x80, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for i in 0..<frames {
            let frame = CameraFrame(hostSeconds: 0, arrivalHostSeconds: 0, sequence: i, pixelBuffer: buffer)
            XCTAssertTrue(writer.append(frame, songTime: firstImage + Double(i) * cameraPeriod))
        }
        _ = try await writer.finish()
        return firstImage + Double(frames) * cameraPeriod
    }

    static func plan(_ parts: [MontagePart], layout: MontageLayoutKind) throws -> MontagePlan {
        let span = try XCTUnwrap(MontagePlan.videoSpan(presences: parts.map(\.presence)))
        return MontagePlan(canvas: .landscape, fps: fps, layout: layout, span: span, barDuration: 1, fadeIn: false, fadeOut: true,
                           parts: parts)
    }

    func testCompositionCoversQuantizedEndWhenTakesEndEarly() async throws {
        let dir = try TestWav.tempDir("MontageCompositionCoverageTests")
        var parts: [MontagePart] = []
        for v in Self.variants {
            let url = dir.appendingPathComponent("\(v.name).mov")
            let videoEnd = try await Self.writeCameraVideo(url, frames: v.frames)
            parts.append(MontagePart(id: v.name, name: v.name, isSolo: false, presence: [v.take],
                                     video: MontagePartVideo(url: url, videoOffset: 0, take: v.take)))
            // Cada toma sola: la composición dura lo que el plan y la lectura `[0, plan)` es válida.
            let plan = try Self.plan([parts.last!], layout: .single)
            let total = VideoTakeWriter.time(plan.videoDuration)
            let preview = try await MontageBuilder.load(plan, includeAudio: false).make(renderSize: CGSize(width: 320, height: 180),
                                                                                       includeAudio: false)
            let gap = plan.span.end - min(videoEnd, v.take.end)
            print(String(format: "Toma %@: imagen hasta %.4f s, tramo hasta %.4f s (hueco %.1f ms), composición %.4f s", v.name,
                         min(videoEnd, v.take.end), plan.span.end, gap * 1000, CMTimeGetSeconds(preview.composition.duration)))
            XCTAssertGreaterThan(gap, 0, "toma \(v.name): debe acabar antes que el tramo cuantizado")
            XCTAssertGreaterThanOrEqual(CMTimeCompare(preview.composition.duration, total), 0,
                                        "toma \(v.name): composición \(CMTimeGetSeconds(preview.composition.duration)) s < plan \(plan.videoDuration) s")
            XCTAssertNoThrow(try MontageExporter.validate(preview, range: CMTimeRange(start: .zero, duration: total)), "toma \(v.name)")
        }

        // Exportación de A y B lado a lado con su `mezcla.wav` de la duración del plan: sin -11841 y con la invariante.
        let plan = try Self.plan(Array(parts.prefix(2)), layout: .side)
        let fs = 48_000.0
        let samples = Int((plan.videoDuration * fs).rounded())
        let tone = (0..<samples).map { Float(0.2 * sin(2 * .pi * 440 * Double($0) / fs)) }
        let mix = dir.appendingPathComponent("mezcla.wav")
        try TestWav.write([tone, tone], sampleRate: fs, to: mix)
        let out = dir.appendingPathComponent("montaje.mov")
        let summary = try await MontageExporter.export(plan: plan, mixURL: mix,
                                                       settings: MontageExportSettings(codec: .h264, width: 640, height: 360, fps: Self.fps),
                                                       to: out)
        let asset = AVURLAsset(url: out)
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let video = try await XCTUnwrap(videoTrack).load(.timeRange).duration.seconds
        let audio = try await XCTUnwrap(audioTrack).load(.timeRange).duration.seconds
        let wav = Double(samples) / fs
        print(String(format: "Exportado: %d fotogramas, vídeo %.4f s, audio %.4f s, mezcla.wav %.4f s", summary.frames, video, audio, wav))
        XCTAssertEqual(summary.frames, Int((plan.videoDuration * Self.fps).rounded()))
        XCTAssertEqual(video, wav, accuracy: Self.halfFrame)
        XCTAssertEqual(audio, wav, accuracy: Self.halfFrame)
    }

    /// Toma C (vídeo gris 0x80 que acaba 1,4 s antes que su audio), sin fundido global: antes se congelaba el último
    /// fotograma hasta el final; ahora funde a negro en 0,5 s desde la última imagen y queda en negro, en plano único,
    /// lado a lado y apilado con «Mantener aspect ratio» (imagen nítida y relleno difuminado). Fotogramas leídos de la
    /// composición con el compositor (lo mismo que ven la vista previa y el exportador).
    func testTakeEndingEarlyFadesToBlack() async throws {
        let dir = try TestWav.tempDir("MontageCompositionCoverageTests-fade")
        let v = Self.variants[2]
        let url = dir.appendingPathComponent("C.mov")
        let videoEnd = try await Self.writeCameraVideo(url, frames: v.frames)
        let part = MontagePart(id: "C", name: "C", isSolo: false, presence: [v.take], video: MontagePartVideo(url: url, videoOffset: 0, take: v.take))
        let cases: [(MontageLayoutKind, Bool)] = [(.single, false), (.side, false), (.stack, true)]
        for (layout, aspect) in cases {
            let plan = MontagePlan(canvas: layout.defaultCanvas, fps: Self.fps, layout: layout, span: v.take, barDuration: 1, fadeIn: false,
                                   fadeOut: false, parts: [part], showPartLabels: false, keepVideoAspect: aspect)
            let size = MontageBuilder.renderSize(canvas: plan.canvas, maxDimension: 320)
            let preview = try await MontageBuilder.load(plan, includeAudio: false).make(renderSize: size, includeAudio: false)
            let tl = preview.timeline
            let imageEnd = try XCTUnwrap(tl.parts.first?.imageEnd)
            XCTAssertEqual(imageEnd, videoEnd, accuracy: 1e-3, "última imagen")
            let gen = MontageGateTests.generator(preview.composition, videoComposition: preview.videoComposition)
            // Instantes en la rejilla de 30 fps (tiempo del vídeo): antes, a mitad del fundido, tras él y último fotograma.
            let start = plan.span.start
            let k0 = Int(((imageEnd - start) * Self.fps).rounded(.down))
            let times = [(k0 - 3, "antes"), (k0 + 8, "mitad"), (k0 + 18, "después"), (Int((plan.videoDuration * Self.fps).rounded()) - 1, "final")]
                .map { (Double($0.0) / Self.fps, $0.1) }
            var line: [String] = []
            var values: [String: (sharp: Double, fill: Double, k: Double)] = [:]
            for (vt, name) in times {
                let f = try await MontageGateTests.frame(gen, at: vt)
                let k = tl.imageBrightness(part: 0, at: start + vt)
                let c = f.rgb(Double(f.width) / 2, Double(f.height) / 2)
                let fl = f.rgb(Double(f.width) / 2, Double(f.height) * 0.15)
                values[name] = (c.0, fl.0, k)
                line.append(String(format: "%@ %.3f s: brillo %.3f, centro %.0f, relleno %.0f", name, start + vt, k, c.0, fl.0))
            }
            print("F7 fin de toma \(layout.rawValue)\(aspect ? " (aspect)" : ""): " + line.joined(separator: "; "))
            let before = try XCTUnwrap(values["antes"]), mid = try XCTUnwrap(values["mitad"])
            let after = try XCTUnwrap(values["después"]), last = try XCTUnwrap(values["final"])
            // Brillo del timeline: 1 antes, lineal a mitad (a ±1e-9 del valor exacto), 0 después.
            XCTAssertEqual(before.k, 1, accuracy: 1e-12)
            XCTAssertEqual(mid.k, 1 - (start + Double(k0 + 8) / Self.fps - imageEnd) / MontageStyle.endFade, accuracy: 1e-9)
            XCTAssertEqual(after.k, 0, accuracy: 1e-12)
            XCTAssertEqual(last.k, 0, accuracy: 1e-12)
            // Píxeles: imagen gris antes; a mitad entre el 25 y el 80 % (la lectura pasa BT.709 → sRGB, no lineal);
            // negro (≤ 4 de 255) tras el fundido y en el último fotograma, donde antes seguía el gris congelado.
            XCTAssertGreaterThan(before.sharp, 100, "\(layout): imagen antes del final")
            XCTAssertGreaterThan(mid.sharp, before.sharp * 0.25, "\(layout): a mitad del fundido")
            XCTAssertLessThan(mid.sharp, before.sharp * 0.8, "\(layout): a mitad del fundido")
            XCTAssertLessThanOrEqual(after.sharp, 4, "\(layout): negro tras el fundido")
            XCTAssertLessThanOrEqual(last.sharp, 4, "\(layout): negro hasta el final")
            if aspect {
                XCTAssertGreaterThan(before.fill, 30, "relleno difuminado antes del final")
                XCTAssertLessThanOrEqual(after.fill, 4, "relleno en negro tras el fundido")
                XCTAssertLessThanOrEqual(last.fill, 4, "relleno en negro hasta el final")
            }
        }
    }
}
