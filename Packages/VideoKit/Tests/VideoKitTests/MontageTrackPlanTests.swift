#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation
import XCTest
@testable import VideoKit

/// `MontageTrackPlan` (parte 7.9): qué fotograma ve cada pista del montaje en Windows. Portable: un caso a mano. Mac:
/// los tramos coinciden con los que `LoadedTakeVideo.insert` mete en la composición de AVFoundation (a 2/90 000 s).
final class MontageTrackPlanTests: XCTestCase {
    /// Toma con imagen en 2,0–4,0 y un segmento 1,5–5,0: vacío hasta 0,5 s del vídeo, la toma, y su último fotograma
    /// congelado `hold` + 1 fotograma (0,5 + 1/30 s); sin `fillToEnd`, vacío después.
    func testHandCase() {
        let map = MontageTimeMap(segments: [MontageSpan(start: 1.5, end: 5.0)])
        let pieces = [MontageTrackPlan.Piece(start: 2, end: 4, source: 0, sourceStart: 2)]
        let r = MontageTrackPlan.ranges(pieces: pieces, available: { _ in 2...4 }, map: map, hold: 0.5, frameRate: 30, fillToEnd: false)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0], MontageTrackPlan.Range(start: 0.5, end: 2.5, source: 0, sourceStart: 2, rate: 1))
        XCTAssertEqual(r[1].start, 2.5, accuracy: 1e-12)
        XCTAssertEqual(r[1].end, 2.5 + 0.5 + 1.0 / 30, accuracy: 1e-12)
        XCTAssertEqual(r[1].sourceStart, 4 - 1.0 / 30, accuracy: 1e-12)
        XCTAssertNil(MontageTrackPlan.range(at: 0.2, in: r))
        XCTAssertNil(MontageTrackPlan.range(at: 3.2, in: r))
        XCTAssertEqual(MontageTrackPlan.range(at: 1.0, in: r)?.sourceTime(at: 1.0) ?? 0, 2.5, accuracy: 1e-12)
        // Con `fillToEnd`, el congelado llega al final del vídeo.
        let f = MontageTrackPlan.ranges(pieces: pieces, available: { _ in 2...4 }, map: map, hold: 0.5, frameRate: 30, fillToEnd: true)
        XCTAssertEqual(f.last?.end ?? 0, 3.5, accuracy: 1e-12)
    }

    #if canImport(AVFoundation)
    /// Las tomas de 29,97 fps de `MontageCompositionCoverageTests` y la puerta con dos segmentos: los tramos de
    /// `MontageTrackPlan` frente a los de la pista de la composición (destino, origen y escala).
    func testMatchesAVFoundationComposition() async throws {
        let dir = try TestWav.tempDir("MontageTrackPlanTests")
        defer { try? FileManager.default.removeItem(at: dir) }
        var parts: [MontagePart] = []
        for v in MontageCompositionCoverageTests.variants {
            let url = dir.appendingPathComponent("\(v.name).mov")
            _ = try await MontageCompositionCoverageTests.writeCameraVideo(url, frames: v.frames)
            parts.append(MontagePart(id: v.name, name: v.name, isSolo: false, presence: [v.take], video: MontagePartVideo(url: url, videoOffset: 0, take: v.take)))
        }
        let maps = [MontageTimeMap(segments: [MontageSpan(start: 59.0 / 30, end: 4.4)]),
                    MontageTimeMap(segments: [MontageSpan(start: 2.0, end: 3.0), MontageSpan(start: 3.5, end: 4.4)])]
        var worst = 0.0, compared = 0
        for p in parts {
            let loaded = try await LoadedTakeVideo.load(p.video!)
            let video = try XCTUnwrap(loaded)
            var urls: [URL] = []
            let pieces = video.pieces.map { piece -> MontageTrackPlan.Piece in
                let u = piece.source.asset.url
                if !urls.contains(u) { urls.append(u) }
                return .init(start: piece.start, end: piece.end, source: urls.firstIndex(of: u)!, sourceStart: piece.sourceStart)
            }
            let available = video.pieces.first!.source.available
            for map in maps {
                for fill in [false, true] {
                    let comp = AVMutableComposition()
                    let track = try XCTUnwrap(comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
                    try video.insert(into: track, map: map, hold: MontageStyle.transition, fillToEnd: fill)
                    let av = track.segments.filter { !$0.isEmpty }.map { s -> (Double, Double, Double, Double) in
                        let t = s.timeMapping.target, src = s.timeMapping.source
                        return (CMTimeGetSeconds(t.start), CMTimeGetSeconds(CMTimeRangeGetEnd(t)), CMTimeGetSeconds(src.start),
                                CMTimeGetSeconds(src.duration) / CMTimeGetSeconds(t.duration))
                    }
                    let mine = MontageTrackPlan.ranges(pieces: pieces, available: { _ in available }, map: map, hold: MontageStyle.transition,
                                                       frameRate: video.frameRate, fillToEnd: fill)
                    XCTAssertEqual(av.count, mine.count, "\(p.id) \(map.segments) fill \(fill)")
                    for (a, m) in zip(av, mine) {
                        let d = max(abs(a.0 - m.start), abs(a.1 - m.end), abs(a.2 - m.sourceStart))
                        worst = max(worst, d)
                        compared += 1
                        XCTAssertLessThanOrEqual(d, 2.0 / 90_000, "\(p.id) \(a) frente a \(m)")
                        XCTAssertEqual(a.3, m.rate, accuracy: 1e-3, "\(p.id) escala")
                    }
                }
            }
        }
        print(String(format: "7.9 MontageTrackPlan frente a AVFoundation: %d tramos, máx |Δ| %.2e s (tolerancia %.2e)", compared, worst, 2.0 / 90_000))
    }
    #endif
}
