#if os(Windows)
import Foundation
import XCTest
@testable import VideoKit

/// `TakeFrameReader` con búsqueda real (`IMFSourceReader::SetCurrentPosition`): el fotograma de un instante es el mismo
/// que leyendo en secuencia desde el principio, vaya el salto hacia delante o hacia atrás. Medida con una toma real:
/// `WINFRAME_VIDEO=<ruta a video.mov>` (si no está, solo corre el caso sintético).
final class TakeFrameSeekWindowsTests: XCTestCase {
    private func seconds(_ body: () throws -> Void) rethrows -> Double {
        let t0 = DispatchTime.now().uptimeNanoseconds
        try body()
        return Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
    }

    /// Toma de 6 s con huecos de fotogramas: con un umbral de salto de 0,2 s los saltos ocurren de verdad y el PTS del
    /// fotograma elegido coincide con el de un lector que recorre desde el principio.
    func testSeekingReaderMatchesSequentialReader() async throws {
        let dir = try TestWav.tempDir("TakeFrameSeekWindowsTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("video.mov")
        let (_, sent) = try await VideoFileTests.writeVideo(url, start: 2.5, seconds: 6, color: (0, 0, 255), drop: [40, 41, 42, 100])
        let file = try XCTUnwrap(TakeVideoFile.open(url))
        let rotation = VideoRotation(degrees: 0)
        let seeking = TakeFrameReader(file: file, rotation: rotation, seekAhead: 0.2)
        let times: [Double] = [8.0, 2.4, 2.5, 5.0, 5.01, 3.0, 4.2, 8.4, 3.3, 7.77, 2.6, 6.123]
        for t in times {
            let sequential = TakeFrameReader(file: file, rotation: rotation, seekAhead: .infinity)
            _ = try sequential.frame(at: t)
            _ = try seeking.frame(at: t)
            XCTAssertEqual(seeking.currentPTS, sequential.currentPTS, "t = \(t)")
            if let p = seeking.currentPTS { XCTAssertLessThanOrEqual(p, t + 1e-6) }
        }
        XCTAssertGreaterThan(seeking.seekCount, 0)
        XCTAssertNotNil(sent.first)
    }

    /// El MP4 exportado sale en H.264 perfil High (avcC, profile_idc 100) y el bitrate de exportación iguala al del Mac.
    func testExportIsH264HighAtMacBitrate() async throws {
        XCTAssertEqual(Double(MediaFoundationMuxer.exportBitrate(width: 1920, height: 1080, fps: 30, codec: .h264)), 14_100_000, accuracy: 1000)
        XCTAssertEqual(Double(MediaFoundationMuxer.exportBitrate(width: 1080, height: 1920, fps: 30, codec: .h264)), 14_100_000, accuracy: 1000)
        let dir = try TestWav.tempDir("TakeFrameSeekWindowsTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("m.mp4")
        _ = try await MontageExporter.write(frames: MediaFoundationExportTests.FlashFrames(frameCount: 15, duration: 0.5, width: 640, height: 360),
                                            mixURL: nil, settings: .init(codec: .h264, width: 640, height: 360, fps: 30, container: .mp4),
                                            to: url, progress: nil)
        let data = try Data(contentsOf: url)
        let box = try XCTUnwrap(data.range(of: Data("avcC".utf8)))
        XCTAssertEqual(data[box.upperBound + 1], 100, "profile_idc de avcC (66 = Baseline, 100 = High)")
    }

    /// Medida en una toma real H.264 1080p (variable de entorno): salto a 5, 125, 240 y de vuelta a 10 s.
    func testMeasureRealTakeSeeks() throws {
        guard let path = ProcessInfo.processInfo.environment["WINFRAME_VIDEO"] else { throw XCTSkip("sin WINFRAME_VIDEO") }
        let url = URL(fileURLWithPath: path)
        var file: TakeVideoFile?
        let open = try seconds { file = try TakeVideoFile.open(url) }
        let f = try XCTUnwrap(file)
        print("WINFRAME open \(String(format: "%.3f", open)) s, \(Int(f.naturalSize.width))x\(Int(f.naturalSize.height)) \(f.frameRate) fps, shift \(f.shift), available \(f.available)")
        // `.infinity` = el lector de antes (secuencial, volver a abrir al retroceder); el otro, con saltos.
        for (name, ahead) in [("secuencial", Double.infinity), ("con saltos", TakeFrameReader.defaultSeekAhead)] {
            let reader = TakeFrameReader(file: f, rotation: VideoRotation(degrees: 0), seekAhead: ahead)
            for t in [5.0, 125.0, 240.0, 10.0, 11.0, 11.4, 200.0, 4.0] {
                var got: FramePixelBuffer?
                let dt = try seconds { got = try reader.frame(at: t) }
                print("WINFRAME \(name) frame(at: \(t)) \(String(format: "%.3f", dt)) s pts \(reader.currentPTS.map { String(format: "%.4f", $0) } ?? "nil")")
                XCTAssertNotNil(got)
            }
        }
    }

    /// Rendimiento de decodificación y conversión (solo medida): fotogramas por segundo del lector y coste de NV12→BGRA.
    func testMeasureDecodeAndConversion() throws {
        guard let path = ProcessInfo.processInfo.environment["WINFRAME_VIDEO"] else { throw XCTSkip("sin WINFRAME_VIDEO") }
        let url = URL(fileURLWithPath: path)
        var n = 0
        var convert = 0.0
        let total = try seconds {
            try MediaFoundationReader.forEachFrame(url) { _, _, pb in
                n += 1
                if n <= 100 { convert += try self.seconds { _ = pb.converted(to: .bgra) } }
                return n < 300
            }
        }
        print("WINFRAME decode \(n) frames en \(String(format: "%.2f", total)) s (\(String(format: "%.1f", Double(n) / total)) fps, con 100 conversiones NV12-BGRA de \(String(format: "%.1f", convert * 10)) ms cada una)")
    }
}
#endif
