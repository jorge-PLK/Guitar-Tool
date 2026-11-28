import Foundation
import VideoKit
import XCTest
@testable import AppCore

/// Caché de `TakePreview` de `takeFrame` (Mac y Windows): clave por ficheros y punches, acierto con la misma instancia,
/// carga única con fallos simultáneos y `clear()`.
final class TakePreviewCacheTests: XCTestCase {
    private final class Obj: Sendable {}
    private actor Counter {
        var n = 0
        func bump() -> Int { n += 1; return n }
    }

    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("take-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: d) }
        return d
    }

    private func write(_ url: URL, _ bytes: Int, mtime: Date = Date(timeIntervalSince1970: 1_700_000_000)) throws {
        try Data(count: bytes).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
    }

    func testKeyIsStableAndChangesWithFilesAndPunches() throws {
        let d = try tempDir()
        let audio = d.appendingPathComponent("a.wav"), vid = d.appendingPathComponent("video.mov"), pv = d.appendingPathComponent("p.mov")
        try write(audio, 10); try write(vid, 100); try write(pv, 50)
        let take = MontageSpan(start: 1, end: 3)
        func video(offset: Double = 0, punchEnd: Double = 2, rotation: VideoRotation = .none) -> MontagePartVideo {
            MontagePartVideo(url: vid, videoOffset: offset,
                             punches: [PreviewPunch(start: 1.5, end: punchEnd, videoURL: pv, videoOffset: 0.01)], take: take, rotation: rotation)
        }
        let k = TakePreviewCache.key(video: video(), audioURL: audio)
        XCTAssertEqual(k, TakePreviewCache.key(video: video(), audioURL: audio))
        // El desfase de la base no entra: el fotograma se pide con `videoOffset` en cada llamada.
        XCTAssertEqual(k, TakePreviewCache.key(video: video(offset: 0.5), audioURL: audio))
        XCTAssertNotEqual(k, TakePreviewCache.key(video: video(punchEnd: 2.1), audioURL: audio))
        XCTAssertNotEqual(k, TakePreviewCache.key(video: video(rotation: .clockwise90), audioURL: audio))

        try write(vid, 101)   // otro tamaño (p. ej. tras la conversión HEVC→H.264)
        let bySize = TakePreviewCache.key(video: video(), audioURL: audio)
        XCTAssertNotEqual(k, bySize)
        try write(vid, 101, mtime: Date(timeIntervalSince1970: 1_700_000_500))
        let byDate = TakePreviewCache.key(video: video(), audioURL: audio)
        XCTAssertNotEqual(bySize, byDate)
        try write(pv, 50, mtime: Date(timeIntervalSince1970: 1_700_000_900))
        XCTAssertNotEqual(byDate, TakePreviewCache.key(video: video(), audioURL: audio))
    }

    func testHitReturnsSameInstanceAndClearEmpties() async throws {
        let cache = LoadOnceCache<Obj>(maxEntries: 4)
        let loads = Counter()
        let load: @Sendable () async throws -> Obj = { _ = await loads.bump(); return Obj() }
        let a = try await cache.value(key: "a", load: load)
        let again = try await cache.value(key: "a", load: load)
        XCTAssertTrue(a === again)
        let n1 = await loads.n
        XCTAssertEqual(n1, 1)
        XCTAssertEqual(cache.count, 1)
        cache.clear()
        XCTAssertEqual(cache.count, 0)
        let b = try await cache.value(key: "a", load: load)
        XCTAssertFalse(a === b)
    }

    func testConcurrentMissesLoadOnce() async throws {
        let cache = LoadOnceCache<Obj>(maxEntries: 4)
        let loads = Counter()
        let results = try await withThrowingTaskGroup(of: Obj.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    try await cache.value(key: "k") {
                        _ = await loads.bump()
                        try await Task.sleep(nanoseconds: 100_000_000)
                        return Obj()
                    }
                }
            }
            var all: [Obj] = []
            for try await r in group { all.append(r) }
            return all
        }
        let n = await loads.n
        XCTAssertEqual(n, 1)
        XCTAssertTrue(results.allSatisfy { $0 === results[0] })
    }

    func testFailureIsNotCachedAndExceedingMaxDropsAll() async throws {
        struct Boom: Error {}
        let cache = LoadOnceCache<Obj>(maxEntries: 2)
        do { _ = try await cache.value(key: "x") { throw Boom() }; XCTFail("debía fallar") } catch is Boom {}
        XCTAssertEqual(cache.count, 0)
        _ = try await cache.value(key: "x") { Obj() }
        _ = try await cache.value(key: "y") { Obj() }
        XCTAssertEqual(cache.count, 2)
        _ = try await cache.value(key: "z") { Obj() }
        XCTAssertEqual(cache.count, 1)
    }
}
