import Foundation
import XCTest
@testable import VideoKit

/// Sondeo de las tomas reales de «El roce» (copia de prueba del Mac; se salta si no existe).
final class TakeVideoProbeRealFilesTests: XCTestCase {
    static let root = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Music/ToneForge-prueba-7f/El roce de tu cuerpo - Platero Y Tu/takes", isDirectory: true)

    func testRealTakesReadAsHEVC() throws {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil)) ?? []
        let files = dirs.map { $0.appendingPathComponent("video.mov") }.filter { FileManager.default.fileExists(atPath: $0.path) }
        try XCTSkipIf(files.isEmpty, "sin copia de prueba de «El roce»")
        for f in files {
            do {
                let p = try TakeVideoProbe.read(f)
                print("PROBE \(f.deletingLastPathComponent().lastPathComponent): \(String(describing: p))")
                let probe = try XCTUnwrap(p, "\(f.path): sin pista de vídeo")
                XCTAssertEqual(probe.codec, .hevc, "\(f.path): \(probe.sampleEntry)")
            } catch {
                XCTFail("\(f.path): \(error)")
            }
        }
    }
}
