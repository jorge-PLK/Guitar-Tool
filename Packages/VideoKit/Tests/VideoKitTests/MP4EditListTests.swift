#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation
import XCTest
@testable import VideoKit

/// Listas de ediciones del MP4 de Windows y marcas QPC (parte 7.2): piezas puras, en el Mac y en Windows.
final class MP4EditListTests: XCTestCase {
    static func box(_ type: String, _ body: Data) -> Data { MP4EditList.box(type, body) }

    /// `moov` mínima: película a `movieTS`, pistas (handler, escala, duración de medios).
    static func moov(movieTS: UInt32, tracks: [(String, UInt32, UInt32)]) -> Data {
        var mvhd = Data(count: 100)
        MP4EditList.put32(&mvhd, 12, movieTS)
        var body = box("mvhd", mvhd)
        for (i, (handler, ts, dur)) in tracks.enumerated() {
            var tkhd = Data(count: 84)
            MP4EditList.put32(&tkhd, 12, UInt32(i + 1))
            var mdhd = Data(count: 24)
            MP4EditList.put32(&mdhd, 12, ts)
            MP4EditList.put32(&mdhd, 16, dur)
            var hdlr = Data(count: 25)
            hdlr.replaceSubrange(8..<12, with: Array(handler.utf8))
            body.append(box("trak", box("tkhd", tkhd) + box("mdia", box("mdhd", mdhd) + box("hdlr", hdlr))))
        }
        return box("moov", body)
    }

    func testPatchWritesReadsAndRemovesEditLists() throws {
        let m = Self.moov(movieTS: 1000, tracks: [("vide", 90_000, 180_000), ("soun", 48_000, 96_000 + 2112)])
        let patched = try MP4EditList.patch(moov: m) { t in
            t.handler == "vide" ? [.empty(500), .init(segmentDuration: 2000, mediaTime: 0)] : [.init(segmentDuration: 2000, mediaTime: 2112)]
        }
        let tracks = try MP4EditList.tracks(moov: patched)
        XCTAssertEqual(tracks.map(\.handler), ["vide", "soun"])
        XCTAssertEqual(tracks[0].edits, [.empty(500), .init(segmentDuration: 2000, mediaTime: 0)])
        XCTAssertEqual(tracks[1].edits, [.init(segmentDuration: 2000, mediaTime: 2112)])
        XCTAssertEqual(tracks[1].mediaTimescale, 48_000)
        // Duraciones: tkhd = suma de tramos; mvhd = la mayor.
        let d = patched
        let kids = try MP4EditList.children(d, try MP4EditList.children(d, d.startIndex..<d.endIndex)[0].body)
        let mvhd = try XCTUnwrap(kids.first { $0.type == "mvhd" })
        XCTAssertEqual(MP4EditList.be32(d, mvhd.body.lowerBound + 16), 2500)
        let traks = kids.filter { $0.type == "trak" }
        let tk0 = try XCTUnwrap(try MP4EditList.children(d, traks[0].body).first { $0.type == "tkhd" })
        XCTAssertEqual(MP4EditList.be32(d, tk0.body.lowerBound + 20), 2500)
        // Quitar: sin edts y duración de los medios.
        let removed = try MP4EditList.patch(moov: patched) { $0.handler == "vide" ? [] : nil }
        let again = try MP4EditList.tracks(moov: removed)
        XCTAssertEqual(again[0].edits, [])
        XCTAssertEqual(again[1].edits, [.init(segmentDuration: 2000, mediaTime: 2112)])
        XCTAssertEqual(removed.count, patched.count - 8 - 8 - 8 - 2 * 20)
    }

    /// Lector de iTunSMPB (el exportador de Windows ya no lo escribe: AAC sin compensar, decisión de Jorge del
    /// 19/11/2026): nada en un `moov` sin él; el texto en uno con `udta/meta/ilst/----` como el de iTunes.
    func testGaplessInfoReader() throws {
        let bare = Self.moov(movieTS: 1000, tracks: [("soun", 48_000, 98_304)])
        XCTAssertNil(MP4EditList.gaplessInfo(moov: bare))
        let text = " 00000000 00000840 000003C0 0000000000017700"
        let item = Self.box("----", Self.box("mean", Data(count: 4) + Data("com.apple.iTunes".utf8))
                            + Self.box("name", Data(count: 4) + Data("iTunSMPB".utf8))
                            + Self.box("data", Data([0, 0, 0, 1, 0, 0, 0, 0]) + Data(text.utf8)))
        var tagged = bare
        tagged.append(Self.box("udta", Self.box("meta", Data(count: 4) + Self.box("ilst", item))))
        MP4EditList.put32(&tagged, 0, UInt32(tagged.count))
        XCTAssertEqual(MP4EditList.gaplessInfo(moov: tagged), text)
    }

    /// 100 ns de QPC → ticks: exacto con 10 MHz, redondeado al más cercano con otras frecuencias, sin desbordar con 200
    /// días de encendido a 3 GHz.
    func testQPCHundredNanosecondsToTicks() {
        XCTAssertEqual(QPCTime.ticks(hundredNanoseconds: 123_456_789, frequency: 10_000_000), 123_456_789)
        XCTAssertEqual(QPCTime.ticks(hundredNanoseconds: 10_000_000, frequency: 24_000_000), 24_000_000)
        // 1 unidad de 100 ns a 3,579545 MHz = 0,358 ticks → 0; 2 → 0,716 → 1.
        XCTAssertEqual(QPCTime.ticks(hundredNanoseconds: 1, frequency: 3_579_545), 0)
        XCTAssertEqual(QPCTime.ticks(hundredNanoseconds: 2, frequency: 3_579_545), 1)
        let days200 = Int64(200 * 86_400) * 10_000_000
        XCTAssertEqual(QPCTime.ticks(hundredNanoseconds: days200, frequency: 3_000_000_000), UInt64(200 * 86_400) * 3_000_000_000)
        XCTAssertEqual(QPCTime.ticks(hundredNanoseconds: -5, frequency: 10_000_000), 0)
        // Ida y vuelta con la frecuencia de la base de HostClock: error < 1 tick y < 100 ns.
        for f: UInt64 in [10_000_000, 24_000_000, 19_200_000, 3_579_545] {
            XCTAssertEqual(QPCTime.frequency(timebase: 1e9 / Double(f)), f)
            let ticks: UInt64 = 987_654_321_987
            let hns = Int64((Double(ticks) * 1e7 / Double(f)).rounded())
            let back = QPCTime.ticks(hundredNanoseconds: hns, frequency: f)
            XCTAssertLessThanOrEqual(abs(Double(back) - Double(ticks)) / Double(f), 1e-7, "f \(f)")
        }
    }

    #if canImport(AVFoundation)
    /// Las listas que escribe `MP4EditList` (elst de versión 1) las respeta AVFoundation: un tramo vacío de 0,5 s delante
    /// de un MP4 de `AVAssetWriter` sin él pone el primer fotograma en 0,5 s.
    func testAVFoundationHonoursRewrittenEditList() async throws {
        let dir = try TestWav.tempDir("MP4EditListTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("v.mp4")
        let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        w.add(input)
        XCTAssertTrue(w.startWriting())
        w.startSession(atSourceTime: .zero)
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &pb)
        for i in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            XCTAssertTrue(adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30)))
        }
        input.markAsFinished()
        await w.finishWriting()
        let before = try MP4EditList.tracks(in: url)
        try MP4EditList.rewrite(url) { t in
            let media = t.sampleDuration * UInt64(t.movieTimescale) / UInt64(t.mediaTimescale)
            return [.empty(UInt64(t.movieTimescale) / 2), .init(segmentDuration: media, mediaTime: t.edits.first { $0.mediaTime >= 0 }?.mediaTime ?? 0)]
        }
        let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first!
        let segs = try await track.load(.segments).filter { !$0.isEmpty }
        let start = CMTimeGetSeconds(try XCTUnwrap(segs.first).timeMapping.target.start)
        let range = try await track.load(.timeRange)
        print("7.2 elst: antes \(before.map(\.edits)), primer tramo en \(start) s, pista \(CMTimeGetSeconds(range.start))–\(CMTimeGetSeconds(range.end)) s")
        XCTAssertEqual(start, 0.5, accuracy: 1e-3)
        XCTAssertEqual(CMTimeGetSeconds(range.end), 1.5, accuracy: 2e-3)
    }
    #endif
}
