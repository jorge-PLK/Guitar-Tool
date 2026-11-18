import AVFoundation
import XCTest
@testable import VideoKit

/// `VideoTakeWriter` y `TakePreview` sobre ficheros cortos en un directorio temporal.
final class VideoFileTests: XCTestCase {
    static let format = VideoFormat(cameraID: "sim-camera", cameraName: "Cámara simulada", width: 320, height: 180, fps: 30)

    /// Escribe un vídeo de color liso de `seconds` empezando en el tiempo del tema `start`, sin los fotogramas `drop`.
    static func writeVideo(_ url: URL, start: Double, seconds: Double, color: (b: UInt8, g: UInt8, r: UInt8),
                           drop: Set<Int> = []) async throws -> (VideoTakeSummary, [Double]) {
        let cam = SimulatedCameraCapture(camera: CameraDevice(id: "sim-camera", name: "Cámara simulada", kind: .simulated,
                                                              formats: [CameraFormat(width: 320, height: 180, frameRates: [.init(min: 30, max: 30)])]),
                                         config: .init(delaySeconds: 0, jitterSeconds: 0, dropFrames: drop, pixels: true, color: color),
                                         originHostSeconds: 0)
        let writer = try VideoTakeWriter(url: url, format: format, realTime: false)
        final class Times: @unchecked Sendable { let lock = NSLock(); var list: [Double] = [] }
        let times = Times()
        _ = try cam.start(CameraRequest(width: 320, height: 180, fps: 30)) { f in
            // PTS = tiempo del tema: aquí el reloj de la cámara empieza en `start`.
            let song = start + f.hostSeconds
            if writer.append(f, songTime: song) { times.lock.withLock { times.list.append(song) } }
        }
        cam.advance(toHostSeconds: seconds - 1e-9)
        cam.stop()
        return (try await writer.finish(), times.lock.withLock { times.list })
    }

    /// PTS en tiempo de la película (el del tema): el lector da tiempo de la pista de medios, al que se aplica la
    /// lista de ediciones (un tramo vacío delante y el resto desplazado).
    static func ptsOf(_ url: URL) async throws -> [Double] {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let segs = try await track.load(.segments).filter { !$0.isEmpty }
        XCTAssertEqual(segs.count, 1)
        let shift = CMTimeGetSeconds(segs[0].timeMapping.target.start) - CMTimeGetSeconds(segs[0].timeMapping.source.start)
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(out)
        reader.startReading()
        var pts: [Double] = []
        while let s = out.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(s) > 0 { pts.append(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(s)) + shift) }
        }
        return pts.sorted()
    }

    /// HEVC, solo vídeo, formato real, PTS = tiempo del tema (también empezando a mitad: 12,345 s) con error de la
    /// escala del fichero (1/90 000 s) como mucho, y los fotogramas perdidos dejan hueco sin desplazar los siguientes.
    func testWriterKeepsSongTimePTSAndGapsForDroppedFrames() async throws {
        let dir = try TestWav.tempDir("VideoFileTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("video.mov")
        let (summary, sent) = try await Self.writeVideo(url, start: 12.345, seconds: 1.5, color: (0, 0, 255), drop: [10, 11, 12, 30])
        XCTAssertEqual(summary.framesWritten, 45 - 4)
        XCTAssertEqual(summary.format, Self.format)
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 0)
        let desc = try await videoTracks[0].load(.formatDescriptions).first!
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(desc), kCMVideoCodecType_HEVC)
        let size = try await videoTracks[0].load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 320, height: 180))
        // El escritor no fija `AVAssetWriterInput.transform`: la pista sale con la identidad, y el montaje
        // (`GuitarFramer`, compositor, `tf-video frame`) lee los píxeles tal cual. Si esto cambia, el montaje tiene
        // que aplicar `preferredTransform` en todos esos sitios.
        let transform = try await videoTracks[0].load(.preferredTransform)
        XCTAssertTrue(transform.isIdentity, "preferredTransform \(transform)")

        let read = try await Self.ptsOf(url)
        XCTAssertEqual(read.count, sent.count)
        let worst = zip(read, sent).map { abs($0 - $1) }.max() ?? .nan
        // Tras el hueco de 3 (fotogramas 10–12) el siguiente cae 4 periodos después.
        let gap = read[10] - read[9]
        print(String(format: "F6 escritor: %d fotogramas, primer PTS %.6f s, máx |PTS leído − tema| %.2e s, hueco %.4f s",
                     read.count, read.first ?? .nan, worst, gap))
        XCTAssertLessThanOrEqual(worst, 1.0 / 90_000)
        XCTAssertEqual(read.first!, 12.345, accuracy: 1.0 / 90_000)
        XCTAssertEqual(gap, 4.0 / 30, accuracy: 1.0 / 90_000)
    }

    /// Composición con punch: base fuera del tramo y punch dentro (el último manda), cada uno con su desfase,
    /// comprobado en los tramos y en la imagen; rehacerla al cambiar el desfase es barato.
    func testPreviewUsesPunchInsideItsSpanAndBaseOutside() async throws {
        let dir = try TestWav.tempDir("VideoFileTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let fs = 48_000.0
        let audio = dir.appendingPathComponent("processed.wav")
        try TestWav.write([[Float](repeating: 0.1, count: Int(3 * fs))], sampleRate: fs, to: audio)
        let base = dir.appendingPathComponent("video.mov"), p1 = dir.appendingPathComponent("p1.mov"), p2 = dir.appendingPathComponent("p2.mov")
        // Toma de 10,0 a 13,0 s; vídeo base rojo; punch 1 verde (tramo 10,8–11,8); punch 2 azul (11,5–12,2), pisa al 1.
        _ = try await Self.writeVideo(base, start: 9.9, seconds: 3.4, color: (0, 0, 255))
        _ = try await Self.writeVideo(p1, start: 10.5, seconds: 1.6, color: (0, 255, 0))
        _ = try await Self.writeVideo(p2, start: 11.2, seconds: 1.3, color: (255, 0, 0))
        let preview = try await TakePreview.load(audioURL: audio, songStart: 10, videoURL: base, punches: [
            PreviewPunch(start: 10.8, end: 11.8, videoURL: p1, videoOffset: 0.02),
            PreviewPunch(start: 11.5, end: 12.2, videoURL: p2, videoOffset: -0.01)
        ])
        XCTAssertEqual(preview.duration, 3, accuracy: 1e-6)
        let offset = 0.0333
        let plan = preview.pieces(videoOffset: offset)
        XCTAssertEqual(plan.map(\.source), [.base, .punch(0), .punch(1), .base])
        let expect: [(Double, Double, Double)] = [(0, 0.8, 10 + offset), (0.8, 1.5, 10.8 + 0.02), (1.5, 2.2, 11.5 - 0.01), (2.2, 3.0, 12.2 + offset)]
        for (p, e) in zip(plan, expect) {
            XCTAssertEqual(p.start, e.0, accuracy: 1e-9)
            XCTAssertEqual(p.end, e.1, accuracy: 1e-9)
            XCTAssertEqual(p.sourceStart, e.2, accuracy: 1e-9)
        }
        let comp = try preview.composition(videoOffset: offset)
        let v = comp.tracks(withMediaType: .video).first!
        let a = comp.tracks(withMediaType: .audio).first!
        XCTAssertEqual(CMTimeGetSeconds(a.timeRange.duration), 3, accuracy: 1e-4)
        let segs = v.segments.filter { !$0.isEmpty }
        XCTAssertEqual(segs.count, 4)
        for (s, e) in zip(segs, expect) {
            XCTAssertEqual(CMTimeGetSeconds(s.timeMapping.target.start), e.0, accuracy: 1.0 / 90_000)
            XCTAssertEqual(CMTimeGetSeconds(s.timeMapping.source.start), e.2, accuracy: 1.0 / 90_000)
        }
        // Imagen: rojo, verde, azul, rojo.
        let gen = AVAssetImageGenerator(asset: comp)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        func color(at t: Double) async throws -> (Int, Int, Int) {
            let (img, _) = try await gen.image(at: CMTime(seconds: t, preferredTimescale: 90_000))
            var px = [UInt8](repeating: 0, count: 4)
            let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return (Int(px[0]), Int(px[1]), Int(px[2]))
        }
        func dominant(_ c: (Int, Int, Int)) -> String { c.0 > max(c.1, c.2) ? "rojo" : c.1 > max(c.0, c.2) ? "verde" : "azul" }
        var seen: [String] = []
        for t in [0.4, 1.1, 1.9, 2.6] { seen.append(dominant(try await color(at: t))) }
        XCTAssertEqual(seen, ["rojo", "verde", "azul", "rojo"])

        // Barato: 200 composiciones con desfases distintos.
        let t0 = Date()
        for i in 0..<200 { _ = try preview.composition(videoOffset: Double(i - 100) / 1000) }
        let each = Date().timeIntervalSince(t0) / 200
        print(String(format: "F6 vista previa: tramos %@; imagen %@; rehacer la composición %.3f ms", "\(plan.map(\.source))", "\(seen)", each * 1000))
        XCTAssertLessThan(each, 0.005)
    }
}
