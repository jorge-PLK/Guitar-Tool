import Foundation
import XCTest
@testable import VideoKit

/// Conversión HEVC → H.264 de las tomas en Windows (mini-spec «Tomas HEVC en Windows»): lectura del códec y de los
/// tiempos de `stsd`/`stts`/`ctts`/`elst`, recolocación del primer fotograma y verificación. Puro: en el Mac y en Windows.
final class TakeVideoProbeTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)
    /// Toma HEVC grabada en el Mac (Tornado Of Souls, 1280×720, 30 fps, 61 fotogramas con B, empieza en 20,0 s).
    static let hevcFixture = fixtures.appendingPathComponent("hevc-take.mov")

    static func box(_ type: String, _ body: Data) -> Data { MP4EditList.box(type, body) }

    /// `moov` con una pista de vídeo completa: entrada de `stsd` (`entry`, tamaño), `stts` (cuántas, delta), `ctts`
    /// opcional (cuántas, desfase; versión 1 = con signo) y lista de ediciones opcional.
    static func videoMoov(entry: String, width: Int = 1280, height: Int = 720, movieTS: UInt32, mediaTS: UInt32,
                          stts: [(UInt32, UInt32)], ctts: [(UInt32, Int32)]? = nil, cttsVersion: UInt8 = 0,
                          edits: [MP4EditList.Edit]? = nil) -> Data {
        var mvhd = Data(count: 100)
        MP4EditList.put32(&mvhd, 12, movieTS)
        var tkhd = Data(count: 84)
        MP4EditList.put32(&tkhd, 12, 1)
        var mdhd = Data(count: 24)
        MP4EditList.put32(&mdhd, 12, mediaTS)
        MP4EditList.put32(&mdhd, 16, stts.reduce(0) { $0 + $1.0 * $1.1 })
        var hdlr = Data(count: 25)
        hdlr.replaceSubrange(8..<12, with: Array("vide".utf8))
        var visual = Data(count: 78)
        visual[24] = UInt8(width >> 8); visual[25] = UInt8(width & 0xff)
        visual[26] = UInt8(height >> 8); visual[27] = UInt8(height & 0xff)
        let stsd = box("stsd", Data(count: 4) + MP4EditList.u32(1) + box(entry, visual))
        var sttsBody = Data(count: 4) + MP4EditList.u32(UInt32(stts.count))
        for (n, d) in stts { sttsBody += MP4EditList.u32(n) + MP4EditList.u32(d) }
        var stbl = stsd + box("stts", sttsBody)
        if let ctts {
            var c = Data([cttsVersion, 0, 0, 0]) + MP4EditList.u32(UInt32(ctts.count))
            for (n, o) in ctts { c += MP4EditList.u32(n) + MP4EditList.u32(UInt32(bitPattern: o)) }
            stbl += box("ctts", c)
        }
        let mdia = box("mdia", box("mdhd", mdhd) + box("hdlr", hdlr) + box("minf", box("stbl", stbl)))
        var trak = box("tkhd", tkhd)
        if let edits { trak += MP4EditList.edtsBox(edits) }
        trak += mdia
        return box("moov", box("mvhd", mvhd) + box("trak", trak))
    }

    /// Fichero con `ftyp`, `mdat` de `payload` bytes y la `moov`, detrás (como `IMFSinkWriter`) o delante (`+faststart`).
    static func write(_ moov: Data, to url: URL, moovFirst: Bool = false, payload: Int = 1000) throws {
        let ftyp = box("ftyp", Data("isom".utf8) + Data(count: 4) + Data("isom".utf8))
        let mdat = box("mdat", Data(count: payload))
        try (moovFirst ? ftyp + moov + mdat : ftyp + mdat + moov).write(to: url)
    }

    func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TakeVideoProbeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    // MARK: Códec

    /// `hvc1` y `hev1` son HEVC, `avc1` H.264, lo demás tal cual; con `moov` detrás o delante (la detección no exige
    /// `moov` al final; `rewrite` sí, porque mueve los desplazamientos de `mdat`).
    func testCodecFromFirstSampleEntryWithMoovFrontOrBack() throws {
        let dir = try tempDir()
        for (entry, codec) in [("hvc1", TakeVideoCodec.hevc), ("hev1", .hevc), ("avc1", .h264), ("mp4v", .other("mp4v"))] {
            for front in [false, true] {
                let url = dir.appendingPathComponent("\(entry)-\(front).mov")
                try Self.write(Self.videoMoov(entry: entry, width: 1920, height: 1080, movieTS: 600, mediaTS: 90_000, stts: [(30, 3000)]),
                               to: url, moovFirst: front)
                let p = try XCTUnwrap(TakeVideoProbe.read(url), "\(entry) front \(front)")
                XCTAssertEqual(p.codec, codec, "\(entry) front \(front)")
                XCTAssertEqual(p.sampleEntry, entry)
                XCTAssertEqual(p.width, 1920)
                XCTAssertEqual(p.height, 1080)
                XCTAssertEqual(p.frameCount, 30)
                XCTAssertEqual(p.frameRate, 30, accuracy: 1e-9)
                if front {
                    XCTAssertThrowsError(try MP4EditList.rewrite(url) { _ in [] }) { XCTAssertEqual($0 as? MP4EditList.Failure, .moovNotLast) }
                }
            }
        }
        // Sin pista de vídeo: nil, no un error.
        let audio = dir.appendingPathComponent("audio.m4a")
        try Self.write(MP4EditListTests.moov(movieTS: 1000, tracks: [("soun", 48_000, 48_000)]), to: audio)
        XCTAssertNil(try TakeVideoProbe.read(audio))
    }

    // MARK: Tiempos

    /// El primer fotograma que se ve: tramo vacío + (composición mínima − inicio del tramo). Con fotogramas B como los de
    /// la toma del Mac (DTS 0, 3000…; composición 6000, 18000, 12000, 9000, 15000) y el tramo de medios en 6000, el primero
    /// cae justo al final del tramo vacío (20,0 s); con el tramo en 0, 6000/90 000 s después. `ctts` de versión 1 con
    /// desfases negativos, también.
    func testFirstFrameTimeHonoursCompositionOffsetsAndEditList() throws {
        let dir = try tempDir()
        let ctts: [(UInt32, Int32)] = [(1, 6000), (1, 15000), (1, 6000), (1, 0), (1, 3000)]
        let a = dir.appendingPathComponent("a.mov")
        try Self.write(Self.videoMoov(entry: "hvc1", movieTS: 600, mediaTS: 90_000, stts: [(5, 3000)], ctts: ctts,
                                      edits: [.empty(20 * 600), .init(segmentDuration: 300, mediaTime: 6000)]), to: a)
        let pa = try XCTUnwrap(TakeVideoProbe.read(a))
        XCTAssertEqual(pa.firstFrameTime, 20.0, accuracy: 1e-12)
        XCTAssertEqual(pa.lastFrameTime, 20.0 + 12_000.0 / 90_000, accuracy: 1e-12)   // composición mayor 18000
        XCTAssertEqual(pa.duration, 0.5, accuracy: 1e-12)
        let b = dir.appendingPathComponent("b.mov")
        try Self.write(Self.videoMoov(entry: "hvc1", movieTS: 600, mediaTS: 90_000, stts: [(5, 3000)], ctts: ctts,
                                      edits: [.empty(20 * 600), .init(segmentDuration: 300, mediaTime: 0)]), to: b)
        let pb = try XCTUnwrap(TakeVideoProbe.read(b))
        XCTAssertEqual(pb.firstFrameTime, 20.0 + 6000.0 / 90_000, accuracy: 1e-12)
        XCTAssertEqual(pb.lastFrameTime, 20.0 + 18_000.0 / 90_000, accuracy: 1e-12)
        // Sin lista: la composición mínima en la escala de la pista; duración = suma de `stts`.
        let c = dir.appendingPathComponent("c.mov")
        try Self.write(Self.videoMoov(entry: "avc1", movieTS: 1000, mediaTS: 90_000, stts: [(4, 3000)],
                                      ctts: [(1, 3000), (1, 9000), (1, 0), (1, -3000)], cttsVersion: 1), to: c)
        let pc = try XCTUnwrap(TakeVideoProbe.read(c))
        XCTAssertEqual(pc.firstFrameTime, 3000.0 / 90_000, accuracy: 1e-12)   // composiciones 3000, 12000, 6000, 6000
        XCTAssertEqual(pc.lastFrameTime, 12_000.0 / 90_000, accuracy: 1e-12)
        XCTAssertEqual(pc.duration, 12_000.0 / 90_000, accuracy: 1e-12)
        // El último que se ve: un tramo de medios que corta el final (0 … 9000) deja fuera los fotogramas de 9000 y 12000.
        let d = dir.appendingPathComponent("d.mov")
        try Self.write(Self.videoMoov(entry: "avc1", movieTS: 90_000, mediaTS: 90_000, stts: [(5, 3000)],
                                      edits: [.empty(90_000), .init(segmentDuration: 9000, mediaTime: 0)]), to: d)
        let pd = try XCTUnwrap(TakeVideoProbe.read(d))
        XCTAssertEqual(pd.firstFrameTime, 1.0, accuracy: 1e-12)
        XCTAssertEqual(pd.lastFrameTime, 1.0 + 6000.0 / 90_000, accuracy: 1e-12)
    }

    /// El fichero real del Mac: HEVC (`hvc1`), 1280×720, 61 fotogramas a 30 fps, primer fotograma en 20,0 s del tema (lo
    /// que da también `ffmpeg -i`: «start 20.000000», 2,03 s).
    func testHEVCFixtureFromTheMac() throws {
        let p = try XCTUnwrap(TakeVideoProbe.read(Self.hevcFixture))
        print("HEVC fixture: \(p)")
        XCTAssertEqual(p.codec, .hevc)
        XCTAssertEqual(p.sampleEntry, "hvc1")
        XCTAssertEqual(p.width, 1280)
        XCTAssertEqual(p.height, 720)
        XCTAssertEqual(p.frameCount, 61)
        XCTAssertEqual(p.firstFrameTime, 20.0, accuracy: 1e-6)
        XCTAssertEqual(p.lastFrameTime, 20.0 + 60.0 / 30, accuracy: 1e-6)
        XCTAssertEqual(p.duration, 61.0 / 30, accuracy: 1.0 / 30)
        XCTAssertEqual(p.frameRate, 30, accuracy: 0.5)
    }

    // MARK: Recolocar y verificar

    /// Lo que deja ffmpeg (H.264 desde 0, sin lista, película a 90 000) se recoloca con un tramo vacío para que su primer
    /// fotograma caiga en el PTS del original: error 0 en la rejilla de 90 000 (≤ 1/90 000 s fuera de ella), muy por debajo
    /// de 1 ms. Luego `verify` lo da por bueno; con 2 ms o 2 fotogramas de diferencia, o si sigue siendo HEVC, no.
    func testAlignStartPutsFirstFrameOnOriginalPTSAndVerifyChecksIt() throws {
        let dir = try tempDir()
        let original = TakeVideoProbe(codec: .hevc, sampleEntry: "hvc1", width: 1280, height: 720, frameCount: 61,
                                      duration: 61.0 / 30, firstFrameTime: 20.0, lastFrameTime: 22.0, fileSize: 9834)
        for (target, label) in [(20.0, "rejilla"), (12.345_678, "fuera de la rejilla")] {
            let url = dir.appendingPathComponent("conv-\(label).mov")
            try Self.write(Self.videoMoov(entry: "avc1", movieTS: 90_000, mediaTS: 90_000, stts: [(61, 3000)]), to: url)
            try TakeVideoTranscode.alignStart(url, firstFrameTime: target)
            let p = try XCTUnwrap(TakeVideoProbe.read(url))
            let err = abs(p.firstFrameTime - target)
            print("alignStart \(label): primer fotograma \(p.firstFrameTime) s, error \(err * 1e6) µs (tolerancia \(TakeVideoTranscode.firstFrameTolerance * 1e3) ms)")
            XCTAssertLessThanOrEqual(err, 1.0 / 90_000 + 1e-12, label)
            XCTAssertLessThanOrEqual(abs(p.lastFrameTime - (target + 2.0)), 1.0 / 90_000 + 1e-12, label)   // 60 × 3000 ticks
            XCTAssertEqual(p.duration, 61.0 / 30, accuracy: 1e-9, label)
            let edits = try XCTUnwrap(MP4EditList.tracks(in: url).first).edits
            XCTAssertEqual(edits.count, 2)
            XCTAssertEqual(edits.last?.mediaTime, 0)
            var o = original
            o.firstFrameTime = target
            o.lastFrameTime = target + 2.0
            XCTAssertNil(TakeVideoTranscode.verify(original: o, converted: p), label)
        }
        // Con tramo de medios propio (fotogramas B de ffmpeg: empieza en 6000) se conserva y el tramo vacío lo compensa.
        let b = dir.appendingPathComponent("conv-b.mov")
        try Self.write(Self.videoMoov(entry: "avc1", movieTS: 90_000, mediaTS: 90_000, stts: [(5, 3000)],
                                      ctts: [(1, 6000), (1, 15000), (1, 6000), (1, 0), (1, 3000)],
                                      edits: [.init(segmentDuration: 15_000, mediaTime: 6000)]), to: b)
        try TakeVideoTranscode.alignStart(b, firstFrameTime: 20.0)
        XCTAssertEqual(try MP4EditList.tracks(in: b).first?.edits, [.empty(1_800_000), .init(segmentDuration: 15_000, mediaTime: 6000)])
        XCTAssertEqual(try XCTUnwrap(TakeVideoProbe.read(b)).firstFrameTime, 20.0, accuracy: 1e-12)

        // Rechazos.
        var conv = TakeVideoProbe(codec: .h264, sampleEntry: "avc1", width: 1280, height: 720, frameCount: 61,
                                  duration: 61.0 / 30, firstFrameTime: 20.0, lastFrameTime: 22.0, fileSize: 6841)
        XCTAssertNil(TakeVideoTranscode.verify(original: original, converted: conv))
        conv.duration = original.duration + 1.0 / 30   // un fotograma: vale
        XCTAssertNil(TakeVideoTranscode.verify(original: original, converted: conv))
        conv.duration = original.duration + 2.0 / 30
        XCTAssertNotNil(TakeVideoTranscode.verify(original: original, converted: conv))
        conv.duration = original.duration
        conv.firstFrameTime = 20.0009
        XCTAssertNil(TakeVideoTranscode.verify(original: original, converted: conv))
        conv.firstFrameTime = 20.002
        XCTAssertEqual(TakeVideoTranscode.verify(original: original, converted: conv),
                       "el primer fotograma no coincide (20.0020 s frente a 20.0000 s del original)")
        conv.firstFrameTime = 20.0
        // El último fotograma: la rejilla fija de ffmpeg lo movía hasta medio fotograma con el primero en su sitio.
        conv.lastFrameTime = 22.0009
        XCTAssertNil(TakeVideoTranscode.verify(original: original, converted: conv))
        conv.lastFrameTime = 22.0144
        XCTAssertEqual(TakeVideoTranscode.verify(original: original, converted: conv),
                       "el último fotograma no coincide (22.0144 s frente a 22.0000 s del original)")
        conv.lastFrameTime = 22.0
        conv.codec = .hevc
        XCTAssertNotNil(TakeVideoTranscode.verify(original: original, converted: conv))
        // Un primer fotograma que cae después del objetivo no se arregla con un tramo vacío.
        let late = dir.appendingPathComponent("late.mov")
        try Self.write(Self.videoMoov(entry: "avc1", movieTS: 90_000, mediaTS: 90_000, stts: [(5, 3000)],
                                      edits: [.empty(90_000 * 30), .init(segmentDuration: 15_000, mediaTime: 0)]), to: late)
        XCTAssertNoThrow(try TakeVideoTranscode.alignStart(late, firstFrameTime: 20.0))   // el tramo vacío de ffmpeg se sustituye
        let after = dir.appendingPathComponent("after.mov")
        try Self.write(Self.videoMoov(entry: "avc1", movieTS: 90_000, mediaTS: 90_000, stts: [(5, 3000)], ctts: [(5, 9000)],
                                      edits: [.init(segmentDuration: 15_000, mediaTime: 0)]), to: after)
        XCTAssertThrowsError(try TakeVideoTranscode.alignStart(after, firstFrameTime: 0.05)) {
            XCTAssertEqual($0 as? TakeVideoTranscodeError, .startAfterTarget(0.1, 0.05))
        }
    }

    // MARK: ffmpeg

    /// Los argumentos conservan la sincronía (mini-spec, punto 4) y no piden `+faststart`.
    func testFFmpegArgumentsKeepSync() {
        let args = TakeVideoTranscode.ffmpegArguments(input: URL(fileURLWithPath: "/t/video.mov"), output: URL(fileURLWithPath: "/t/.converting-video.mov"),
                                                      encoder: "h264_nvenc", bitrate: 2_000_000, gop: 30)
        let line = args.joined(separator: " ")
        for needle in ["-an", "-fps_mode passthrough", "-enc_time_base demux", "-video_track_timescale 90000", "-movie_timescale 90000", "-progress pipe:1",
                       "-nostats", "-c:v h264_nvenc", "-b:v 2000000", "-bf 0", "-map 0:v:0", "-f mp4"] {
            XCTAssertTrue(line.contains(needle), needle)
        }
        XCTAssertFalse(line.contains("faststart"))
        XCTAssertEqual(args.last, URL(fileURLWithPath: "/t/.converting-video.mov").path)
        XCTAssertEqual(TakeVideoTranscode.encoders, ["h264_nvenc", "h264_mf"])
        XCTAssertEqual(TakeVideoTranscode.progressMicroseconds("out_time_us=2033333"), 2_033_333)
        XCTAssertNil(TakeVideoTranscode.progressMicroseconds("out_time_us=N/A"))
        XCTAssertNil(TakeVideoTranscode.progressMicroseconds("progress=end"))
    }

    /// Bitrate: el de la fuente ×1,5, con el objetivo por resolución de tope (0,10 bpp: 1080p30 = 6,22 Mb/s) y 250 kb/s
    /// de suelo.
    func testBitrateRule() {
        func probe(_ w: Int, _ h: Int, bytes: Int64, seconds: Double) -> TakeVideoProbe {
            TakeVideoProbe(codec: .hevc, sampleEntry: "hvc1", width: w, height: h, frameCount: Int(seconds * 30), duration: seconds,
                           firstFrameTime: 0, fileSize: bytes)
        }
        XCTAssertEqual(TakeVideoTranscode.bitrate(for: probe(1920, 1080, bytes: 3_000_000, seconds: 8)), 4_500_000)   // 3 Mb/s × 1,5
        XCTAssertEqual(TakeVideoTranscode.bitrate(for: probe(1920, 1080, bytes: 10_000_000, seconds: 8)), 6_220_800)  // tope
        XCTAssertEqual(TakeVideoTranscode.bitrate(for: probe(1280, 720, bytes: 9834, seconds: 2.0333)), 250_000)      // suelo
        XCTAssertEqual(TakeVideoTranscode.gop(for: probe(1280, 720, bytes: 1, seconds: 2)), 30)
    }
}
