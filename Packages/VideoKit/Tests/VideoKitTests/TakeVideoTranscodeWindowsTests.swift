#if os(Windows)
import Foundation
import XCTest
@testable import VideoKit

/// Conversión HEVC → H.264 con el ffmpeg embebido de verdad (mini-spec «Tomas HEVC en Windows», punto 7): la toma HEVC
/// del Mac sale en H.264 con los mismos PTS del tema y Media Foundation la abre. Se salta sin ffmpeg (`TF_HELPERS` o
/// `Vendor/helpers-win/<arch>/ffmpeg.exe`).
final class TakeVideoTranscodeWindowsTests: XCTestCase {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func ffmpeg() -> URL? {
        var candidates: [URL] = []
        if let h = ProcessInfo.processInfo.environment["TF_HELPERS"], !h.isEmpty {
            candidates.append(URL(fileURLWithPath: h, isDirectory: true).appendingPathComponent("ffmpeg.exe"))
        }
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x64"
        #endif
        candidates.append(repo.appendingPathComponent("Vendor/helpers-win/\(arch)/ffmpeg.exe"))
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Lanza ffmpeg y devuelve (código, líneas de stdout, stderr).
    static func run(_ exe: URL, _ args: [String]) throws -> (Int32, [String], String) {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init),
                String(decoding: e, as: UTF8.self))
    }

    /// El punto fino: tras convertir y recolocar, el primer fotograma de la toma cae en el mismo PTS del tema que en el
    /// original (20,0 s) con error ≤ 1 ms, los 61 fotogramas siguen en su sitio (rejilla de 1/30 s, error ≤ 1 ms leídos
    /// con Media Foundation) y la duración coincide con ±1 fotograma. Después `TakeVideoFile.open` ve el mismo tramo.
    func testConvertsMacHEVCTakeKeepingSongTimePTS() throws {
        guard let exe = Self.ffmpeg() else { throw XCTSkip("sin ffmpeg (TF_HELPERS o Vendor/helpers-win)") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TakeVideoTranscode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("video.mov")
        try FileManager.default.copyItem(at: TakeVideoProbeTests.hevcFixture, to: input)
        let original = try XCTUnwrap(TakeVideoProbe.read(input))
        XCTAssertEqual(original.codec, .hevc)

        // Media Foundation sobre el original: o lo abre (hay decodificador HEVC) o da el error con tipo, no 0xC00D36B3.
        do {
            let info = try MediaFoundationReader.info(input)
            print("HEVC original: Media Foundation lo abre (\(info.videoCodec)): este equipo tiene decodificador HEVC")
        } catch let e as MediaFoundationReader.UndecodableVideo {
            print("HEVC original: \(e)")
            XCTAssertNotEqual(UInt32(bitPattern: e.hr), 0xC00D_36B3)
            XCTAssertTrue(["HEVC", "hvc1"].contains(e.codec), e.codec)
        }

        let output = dir.appendingPathComponent(".converting-video.mov")
        var used: String?
        var progress = 0
        var failures: [String] = []
        for encoder in TakeVideoTranscode.encoders {
            try? FileManager.default.removeItem(at: output)
            let args = TakeVideoTranscode.ffmpegArguments(input: input, output: output, encoder: encoder,
                                                          bitrate: TakeVideoTranscode.bitrate(for: original), gop: TakeVideoTranscode.gop(for: original))
            let (status, lines, stderr) = try Self.run(exe, args)
            if status == 0, FileManager.default.fileExists(atPath: output.path) {
                used = encoder
                progress = lines.compactMap(TakeVideoTranscode.progressMicroseconds).count
                break
            }
            failures.append("\(encoder): \(status) \(stderr.suffix(300))")
        }
        let encoder = try XCTUnwrap(used, "ningún codificador: \(failures)")
        XCTAssertGreaterThan(progress, 0, "ffmpeg no dio progreso por stdout")

        let raw = try XCTUnwrap(TakeVideoProbe.read(output))
        try TakeVideoTranscode.alignStart(output, firstFrameTime: original.firstFrameTime)
        let converted = try XCTUnwrap(TakeVideoProbe.read(output))
        let verdict = TakeVideoTranscode.verify(original: original, converted: converted)
        print("""
            HEVC → H.264 con \(encoder): antes de recolocar primer fotograma \(raw.firstFrameTime) s; después \(converted.firstFrameTime) s \
            (original \(original.firstFrameTime) s, error \(abs(converted.firstFrameTime - original.firstFrameTime) * 1e3) ms); duración \
            \(converted.duration) s frente a \(original.duration) s; \(converted.frameCount) fotogramas; \(converted.fileSize) B; \
            verificación \(verdict ?? "bien")
            """)
        XCTAssertNil(verdict)
        XCTAssertEqual(converted.codec, .h264)
        XCTAssertEqual(converted.frameCount, original.frameCount)
        XCTAssertEqual(converted.width, 1280)
        XCTAssertEqual(converted.height, 720)

        // Media Foundation lo abre y lo decodifica: PTS del tema de cada fotograma (ayudante de VideoFileTests).
        let info = try MediaFoundationReader.info(output)
        XCTAssertEqual(info.videoCodec, "H264")
        XCTAssertFalse(info.hasAudio)
        let pts = try VideoFileTests.ptsOf(output)
        XCTAssertEqual(pts.count, 61)
        let worst = pts.enumerated().map { abs($1 - (20.0 + Double($0) / 30)) }.max() ?? .infinity
        print("PTS leídos con Media Foundation: primero \(pts.first ?? .nan) s, último \(pts.last ?? .nan) s, peor error frente a 20 + k/30: \(worst * 1e3) ms")
        XCTAssertEqual(pts.first ?? .nan, 20.0, accuracy: TakeVideoTranscode.firstFrameTolerance)
        XCTAssertLessThanOrEqual(worst, 0.001)
        // Lo que ve el montaje: tramo con imagen 20,0 … 20,0 + 61/30.
        let file = try XCTUnwrap(TakeVideoFile.open(output))
        XCTAssertEqual(file.available.lowerBound, 20.0, accuracy: TakeVideoTranscode.firstFrameTolerance)
        XCTAssertEqual(file.available.upperBound, 20.0 + 61.0 / 30, accuracy: 1.0 / 30)
    }
}
#endif
