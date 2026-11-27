import Foundation
import SourceKit
import XCTest
@testable import AppCore

/// Regresión W-1 (Fase 7f): Ajustes · Fuentes externas mostraba yt-dlp, Deno y ffmpeg «no disponible» en Windows.
@MainActor
final class ExternalSourcesHelpersTests: XCTestCase {
    func testResolveBundleDirectoryPicksFirstCandidateWithYtDlp() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("w1-\(UUID().uuidString)", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let full = root.appendingPathComponent("full", isDirectory: true)
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        try fm.createDirectory(at: full, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let exe = full.appendingPathComponent(SourceKit.HelperLocator.fileName("yt-dlp"))
        try Data("x".utf8).write(to: exe)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)

        XCTAssertEqual(ExternalSources.resolveBundleDirectory(candidates: [empty, full]).path, full.path)
        XCTAssertEqual(ExternalSources.resolveBundleDirectory(candidates: [empty]).path, empty.path)
        XCTAssertFalse(ExternalSources.hostDirectoryCandidates().isEmpty)
    }

    /// Con `TF_HELPERS` (carpeta con yt-dlp, deno y ffmpeg) se leen las tres versiones.
    func testFindsAndVersionsAllHelpers() async throws {
        guard let folder = ProcessInfo.processInfo.environment[ExternalSources.environmentKey], !folder.isEmpty else {
            throw XCTSkip("TF_HELPERS sin definir (carpeta con yt-dlp, deno y ffmpeg)")
        }
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("w1-\(UUID().uuidString)", isDirectory: true)
        let sources = ExternalSources.production(supportDir: support, environment: [ExternalSources.environmentKey: folder])
        let t0 = Date()
        let info = await sources.toolsInfo()
        print("W1DIAG info=\(info) segundos=\(Date().timeIntervalSince(t0))")
        XCTAssertNotNil(info.ytDlpVersion)
        XCTAssertNotNil(info.denoVersion)
        XCTAssertNotNil(info.ffmpegVersion)
    }
}
