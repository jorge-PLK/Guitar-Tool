#if os(Windows)
import Foundation
import XCTest
@testable import VideoKit

/// Escritura y mux del exportador con Media Foundation (parte 7.2), con fotogramas sintéticos en lugar del compositor
/// (parte 7.9).
final class MediaFoundationExportTests: XCTestCase {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Gris con un fotograma blanco (`flash`); `delay` por fotograma para poder cancelar a mitad.
    struct FlashFrames: MontageFrameSource {
        var frameCount = 60
        var duration = 2.0
        var width = 640, height = 360
        var flash = 30
        var delay = 0.0
        func frame(_ i: Int) throws -> FramePixelBuffer {
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            let pb = FramePixelBuffer(pixelFormat: .bgra, width: width, height: height)
            let v: UInt8 = i == flash ? 255 : 60
            pb.fill(b: v, g: v, r: v)
            return pb
        }
    }

    /// WAV de 16 bits a mano: seno de 440 Hz a 0,1 con un clic de 1 ms a 0,9 en t = 1,000 s.
    static func clickWav(_ url: URL, sampleRate sr: Int, seconds: Int = 2) throws {
        let n = seconds * sr
        var d = Data()
        func u32(_ v: Int) { d.append(contentsOf: withUnsafeBytes(of: UInt32(v).littleEndian, Array.init)) }
        func u16(_ v: Int) { d.append(contentsOf: withUnsafeBytes(of: UInt16(truncatingIfNeeded: v).littleEndian, Array.init)) }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + n * 4); d.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16); u16(1); u16(2); u32(sr); u32(sr * 4); u16(4); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(n * 4)
        for i in 0..<n {
            let v = i >= sr && i < sr + sr / 1000 ? 0.9 : 0.1 * sin(2 * Double.pi * 440 * Double(i) / Double(sr))
            let s = Int(Int16(v * 32767))
            u16(s); u16(s)
        }
        try d.write(to: url)
    }

    /// Clic y fotograma blanco en el mismo t, sin compensar el AAC (decisión de Jorge del 19/11/2026, ver `AACPriming`):
    /// el lector de Media Foundation los lee juntos, a 48 y a 44,1 kHz, con la tolerancia que tenía la cuenta de las 2112
    /// muestras (2 muestras; la de la puerta es medio fotograma). Ni iTunSMPB ni lista de ediciones de audio. Los
    /// lectores de Apple oirán el clic 2112 muestras antes (`mp4check` en el Mac sobre
    /// `Temp/win/listen/CHECK_mf_sincompensar_*.mp4`).
    func testExportClickAndFlashLandTogetherWithoutPriming() async throws {
        let dir = try TestWav.tempDir("MediaFoundationExportTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let listen = Self.repo.appendingPathComponent("Temp/win/listen")
        try FileManager.default.createDirectory(at: listen, withIntermediateDirectories: true)
        for (sr, name) in [(48_000, "48k"), (44_100, "44k")] {
            let wav = dir.appendingPathComponent("mix\(sr).wav")
            try Self.clickWav(wav, sampleRate: sr)
            let url = dir.appendingPathComponent("m\(sr).mp4")
            let s = try await MontageExporter.write(frames: FlashFrames(), mixURL: wav,
                                                    settings: .init(codec: .h264, width: 640, height: 360, fps: 30, container: .mp4), to: url, progress: nil)
            XCTAssertEqual(s.frames, 60)
            XCTAssertTrue(s.hasAudio)
            let (moov, _) = try MP4EditList.readMoov(url)
            XCTAssertNil(MP4EditList.gaplessInfo(moov: moov), "sin iTunSMPB")
            XCTAssertEqual(try MP4EditList.tracks(in: url).first { $0.handler == "soun" }?.edits, [])
            let au = try MediaFoundationReader.audio(url)
            let click = try XCTUnwrap(au.channels[0].firstIndex { abs($0) > 0.5 })
            var white = -1.0, best = -1
            try MediaFoundationReader.forEachFrame(url) { t, _, f in
                let y = Int(f.baseAddress.load(fromByteOffset: 180 * f.bytesPerRow + 320, as: UInt8.self))
                if y > best { best = y; white = t }
                return true
            }
            let offset = Double(click) / au.sampleRate - white
            print(String(format: "7.9 AAC sin compensar %d Hz: lector MF clic − blanco %+.3f ms (%+.0f muestras); AVFoundation esperado %+.1f ms",
                         sr, offset * 1000, offset * au.sampleRate, -Double(AACPriming.samples) / au.sampleRate * 1000))
            XCTAssertEqual(white, 1.0, accuracy: 1e-3)
            XCTAssertEqual(abs(offset), 0, accuracy: 0.5 / 30, "medio fotograma")
            XCTAssertEqual(offset * au.sampleRate, 0, accuracy: 2)
            let check = listen.appendingPathComponent("CHECK_mf_sincompensar_\(name).mp4")
            try? FileManager.default.removeItem(at: check)
            try FileManager.default.copyItem(at: url, to: check)
        }
    }

    /// Cancelar a mitad borra el parcial y deja el fichero anterior intacto (como en el Mac).
    func testExportCancelRemovesPartialAndKeepsPrevious() async throws {
        let dir = try TestWav.tempDir("MediaFoundationExportTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("m.mov")
        try Data("anterior".utf8).write(to: url)
        let task = Task {
            try await MontageExporter.write(frames: FlashFrames(frameCount: 300, duration: 10, delay: 0.01), mixURL: nil,
                                            settings: .init(codec: .h264, width: 640, height: 360, fps: 30), to: url, progress: nil)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("no se canceló")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(try Data(contentsOf: url), Data("anterior".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("m.partial.mov").path))
    }

    /// MOV y MP4 con el mismo contenido; extensión equivocada → `containerMismatch` antes de escribir; HEVC pedido →
    /// H.264 siempre en Windows (W2-E1; el resumen lo dice).
    func testExportContainersAndCodec() async throws {
        let dir = try TestWav.tempDir("MediaFoundationExportTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        var counts: [Int] = []
        for c in MontageVideoContainer.allCases {
            let url = dir.appendingPathComponent("m.\(c.fileExtension)")
            let s = try await MontageExporter.write(frames: FlashFrames(frameCount: 15, duration: 0.5, width: 320, height: 180), mixURL: nil,
                                                    settings: .init(codec: .hevc, width: 320, height: 180, fps: 30, container: c), to: url, progress: nil)
            XCTAssertEqual(s.settings.codec, .h264)   // W2-E1: en Windows solo H.264
            let info = try MediaFoundationReader.info(url)
            XCTAssertEqual(info.videoCodec, s.settings.codec == .hevc ? "HEVC" : "H264")
            XCTAssertEqual(info.width, 320)
            XCTAssertFalse(info.hasAudio)
            var n = 0
            try MediaFoundationReader.forEachFrame(url) { _, _, _ in n += 1; return true }
            counts.append(n)
        }
        XCTAssertEqual(counts, [15, 15])
        do {
            _ = try await MontageExporter.export(plan: MontagePlan(canvas: .landscape, fps: 30, layout: .single, span: MontageSpan(start: 0, end: 1),
                                                                   barDuration: 1, fadeIn: false, fadeOut: false, parts: []),
                                                 mixURL: nil, settings: .init(codec: .h264, width: 320, height: 180, fps: 30, container: .mp4),
                                                 to: dir.appendingPathComponent("x.mov"))
            XCTFail("sin error")
        } catch {
            XCTAssertEqual(error as? MontageError, .containerMismatch(expected: "mp4", got: "mov"))
        }
    }
}
#endif
