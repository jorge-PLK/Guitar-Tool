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

    /// PTS de cada fotograma de la primera pista de vídeo en ticks de su base (ffmpeg `-copyts -c copy -f framecrc`: sin
    /// decodificar y con la lista de ediciones aplicada), ordenados, y la base.
    static func framePTS(_ exe: URL, _ url: URL) throws -> (ticks: [Int64], timebase: String) {
        let (status, lines, stderr) = try run(exe, ["-hide_banner", "-nostdin", "-v", "error", "-copyts", "-i", url.path,
                                                    "-map", "0:v:0", "-c", "copy", "-f", "framecrc", "-"])
        guard status == 0 else { throw XCTSkip("framecrc falló: \(stderr.suffix(300))") }
        let tb = lines.first { $0.hasPrefix("#tb 0:") }.map { String($0.dropFirst("#tb 0:".count)).trimmingCharacters(in: .whitespaces) } ?? "?"
        let ticks = lines.filter { !$0.hasPrefix("#") }.compactMap { line -> Int64? in
            let f = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return f.count > 2 ? Int64(f[2]) : nil
        }
        return (ticks.sorted(), tb)
    }

    /// Regresión de la rejilla (ronda de validación 7c, 23/11/2026): una toma VFR como las del iPhone (deltas de 3001-3002
    /// ticks, no 3003) salía con cada PTS redondeado a la rejilla 1/fps del codificador (hasta medio fotograma, 16,7 ms),
    /// aunque el primero, la cuenta y la duración cuadraban. Con `-enc_time_base demux` el codificador usa la base del
    /// original. Fuente sintética de 45 fotogramas HEVC que empieza en 12,345 s del tema con deltas de 1200 a 4800 ticks de
    /// 1/90 000; tras convertir con cada codificador y recolocar, los 45 PTS caen a ≤ 1 tick del original (framecrc) y a
    /// ≤ 0,1 ms leídos con Media Foundation, y `verify` da el último fotograma por bueno.
    func testVFRTakeKeepsEveryFramePTS() throws {
        guard let exe = Self.ffmpeg() else { throw XCTSkip("sin ffmpeg (TF_HELPERS o Vendor/helpers-win)") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TakeVideoTranscodeVFR-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("video.mov")
        let frames = 45
        let startTicks: Int64 = 1_111_050   // 12,345 s × 90 000
        // HEVC por software (kvazaar, también en arm64); si no, el de la GPU o el de Media Foundation; en último caso H.264.
        var source: String?
        for enc in ["libkvazaar", "hevc_nvenc", "hevc_mf", "libopenh264"] {
            try? FileManager.default.removeItem(at: input)
            let (status, _, _) = try Self.run(exe, [
                "-hide_banner", "-nostdin", "-y", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=30",
                "-frames:v", String(frames), "-vf", "settb=1/90000,setpts=\(startTicks)+floor(N*3000+900*sin(N*1.7))",
                "-c:v", enc, "-pix_fmt", "yuv420p", "-enc_time_base", "1:90000", "-fps_mode", "passthrough",
                "-video_track_timescale", "90000", "-f", "mov", input.path])
            if status == 0, FileManager.default.fileExists(atPath: input.path) { source = enc; break }
        }
        let sourceEncoder = try XCTUnwrap(source, "no se pudo generar la fuente")
        let original = try XCTUnwrap(TakeVideoProbe.read(input))
        let (want, wantTB) = try Self.framePTS(exe, input)
        XCTAssertEqual(wantTB, "1/90000")
        XCTAssertEqual(want.count, frames)
        XCTAssertEqual(want.first, startTicks)
        let deltas = zip(want.dropFirst(), want).map { $0 - $1 }
        print("Fuente VFR con \(sourceEncoder) (\(original.codec)): deltas \(deltas.min() ?? 0)…\(deltas.max() ?? 0) ticks, primer fotograma \(original.firstFrameTime) s, último \(original.lastFrameTime) s")
        XCTAssertGreaterThan((deltas.max() ?? 0) - (deltas.min() ?? 0), 1000, "la fuente tiene que ser VFR")
        XCTAssertEqual(original.firstFrameTime, Double(startTicks) / 90_000, accuracy: 1e-9)
        XCTAssertEqual(original.lastFrameTime, Double(want.last ?? 0) / 90_000, accuracy: 1e-9)

        var converted: [String] = []
        for encoder in TakeVideoTranscode.encoders {
            let output = dir.appendingPathComponent(".converting-\(encoder).mov")
            let args = TakeVideoTranscode.ffmpegArguments(input: input, output: output, encoder: encoder,
                                                          bitrate: TakeVideoTranscode.bitrate(for: original), gop: TakeVideoTranscode.gop(for: original))
            let (status, _, stderr) = try Self.run(exe, args)
            guard status == 0, FileManager.default.fileExists(atPath: output.path) else {
                print("VFR: \(encoder) no disponible (\(status)): \(stderr.suffix(200))")
                continue
            }
            converted.append(encoder)
            try TakeVideoTranscode.alignStart(output, firstFrameTime: original.firstFrameTime)
            let probe = try XCTUnwrap(TakeVideoProbe.read(output))
            let (got, gotTB) = try Self.framePTS(exe, output)
            XCTAssertEqual(gotTB, "1/90000", encoder)
            XCTAssertEqual(got.count, want.count, encoder)
            let errors = zip(got, want).map { abs($0 - $1) }
            let worst = errors.max() ?? .max
            let mf = try VideoFileTests.ptsOf(output)
            let worstMF = zip(mf, want).map { abs($0 - Double($1) / 90_000) }.max() ?? .infinity
            print("""
                VFR \(encoder): peor error \(worst) ticks (\(Double(worst) / 90) ms), \(errors.filter { $0 > 1 }.count) de \(errors.count) \
                fotogramas a más de 1 tick; Media Foundation peor \(worstMF * 1e3) ms; último fotograma \(probe.lastFrameTime) s frente a \
                \(original.lastFrameTime) s; verificación \(TakeVideoTranscode.verify(original: original, converted: probe) ?? "bien")
                """)
            XCTAssertLessThanOrEqual(worst, 1, "\(encoder): PTS fuera de su sitio")
            XCTAssertEqual(mf.count, frames, encoder)
            XCTAssertLessThanOrEqual(worstMF, 0.000_1, encoder)
            XCTAssertNil(TakeVideoTranscode.verify(original: original, converted: probe), encoder)
        }
        XCTAssertFalse(converted.isEmpty, "ningún codificador convirtió")
    }
}
#endif
