import Foundation
import XCTest
@testable import SourceKit

final class OrphanDownloadTests: XCTestCase {
    func testRemovesWorkRootWithContents() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("sourcekit-orphan-\(UUID().uuidString)")
        let work = base.appendingPathComponent("ToneForge-source", isDirectory: true)
        let sub = work.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "x".write(to: sub.appendingPathComponent("a.webm"), atomically: true, encoding: .utf8)
        let sibling = base.appendingPathComponent("other.txt")
        try "keep".write(to: sibling, atomically: true, encoding: .utf8)

        XCTAssertTrue(SourceImporter.removeOrphanedDownloads(workRoot: work))
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
        XCTAssertFalse(SourceImporter.removeOrphanedDownloads(workRoot: work), "sin carpeta no hace nada")
        try? FileManager.default.removeItem(at: base)
    }
}
