#if canImport(AVFoundation) && !os(Windows)
import AVFoundation
import Foundation
import Store
import XCTest
@testable import AppCore

/// Diagnóstico (no entra en la suite normal): abre el montaje REAL de un proyecto del Mac con `MontageServices.production`
/// y mide los fotogramas de la vista previa. Solo corre con `TF_REAL_MONTAGE=<carpeta del proyecto>` (una copia clonada).
@MainActor
final class MacRealMontageTests: XCTestCase {
    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(pts: Double, luma: Double)] = []
        func add(_ pb: MontageFramePixels, _ pts: Double) { lock.withLock { items.append((pts, MacRealMontageTests.luma(pb))) } }
        var all: [(pts: Double, luma: Double)] { lock.withLock { items } }
    }

    /// Media de B, G y R (0-255) muestreando una rejilla.
    nonisolated static func luma(_ pb: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), row = CVPixelBufferGetBytesPerRow(pb)
        let p = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        var sum = 0.0, n = 0.0
        for y in stride(from: 0, to: h, by: 4) {
            for x in stride(from: 0, to: w, by: 4) {
                let o = y * row + x * 4
                sum += Double(p[o]) + Double(p[o + 1]) + Double(p[o + 2])
                n += 3
            }
        }
        return n == 0 ? 0 : sum / n
    }

    func testRealMontagePreviewFrames() async throws {
        guard let path = ProcessInfo.processInfo.environment["TF_REAL_MONTAGE"], !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else { throw XCTSkip("sin TF_REAL_MONTAGE") }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let project = try ProjectFile.load(folder: folder)
        let session = StudySession(project: project, folder: folder, store: FileStudyStore(folder: folder))
        let sink = Sink()
        let c = MontageController(session: session, video: nil, store: FileMontageStore(folder: folder), audio: ClockMontageAudio())
        c.onPreviewFrame = { pb, pts in sink.add(pb, pts) }
        c.open()
        let end = ProcessInfo.processInfo.systemUptime + 120
        while ProcessInfo.processInfo.systemUptime < end, c.previewPhase != .ready, c.previewPhase != .error {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        print("REAL fase=\(c.previewPhase) error=\(c.previewError ?? "-") duración=\(c.previewDuration ?? -1)")
        XCTAssertEqual(c.previewPhase, .ready)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        print("REAL still onPreviewFrame: \(sink.all.map { String(format: "pts %.0f luma %.1f", $0.pts, $0.luma) })")

        // Compositor suelto, mismo plan que la vista previa.
        let draft = try XCTUnwrap(c.draft)
        var plan = draft.plan
        plan.audio = []
        let composer = try await MontageServices.production.makeComposer(plan, MontagePlanning.previewMaxDimension)
        let d = composer.duration
        print("REAL composer duración \(d) s, tramos \(plan.parts.count), canvas \(plan.canvas)")
        for f in [0.0, 0.25, 0.5, 0.75, 0.95] {
            let t = d * f
            do {
                let pb = try composer.frame(atVideoTime: t)
                print(String(format: "REAL frame t=%.2f s -> %dx%d luma %.2f %@", t, CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb),
                             Self.luma(pb), Self.luma(pb) < 2 ? "NEGRO" : "ok"))
            } catch {
                print(String(format: "REAL frame t=%.2f s -> ERROR %@", t, String(reflecting: error)))
            }
        }

        // Reproducción real unos segundos.
        let before = sink.all.count
        try c.play()
        try await Task.sleep(nanoseconds: 3_000_000_000)
        c.pause()
        let played = Array(sink.all.dropFirst(before))
        print("REAL play: \(played.count) fotogramas, luma \(played.map { String(format: "%.1f", $0.luma) })")
        c.close()
    }
}
#endif
