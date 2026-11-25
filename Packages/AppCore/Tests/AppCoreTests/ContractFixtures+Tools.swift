import Foundation
import SourceKit
import XCTest
@testable import AppCore

// Parte 1.2b: volcado de `Contract/fixtures/tools/`. `tools.updateYtDlp` descarga de GitHub con un `URLSessionFetcher`
// fijo en `ExternalSources` (no inyectable sin tocar Sources): su `.result` se construye con el tipo real `UpdateYtDlpResult`.

final class ContractFixturesToolsTests: XCTestCase {
    func testInfoAndRevert() async throws {
        let env = try LinkFixtureEnv(area: "tools")
        defer { env.cleanup() }
        try await env.run("tools.info")

        // Un yt-dlp actualizado más nuevo en la carpeta de soporte manda; revertir vuelve al embebido.
        let fm = FileManager.default
        try fm.createDirectory(at: env.supportHelpers, withIntermediateDirectories: true)
        fm.createFile(atPath: env.supportHelpers.appendingPathComponent(SourceKit.HelperLocator.fileName("yt-dlp")).path,
                      contents: Data("y".utf8), attributes: [.posixPermissions: 0o755])
        let info = YtDlpInstallInfo(version: "2026.11.01", sha256: "00", installedAt: Date())
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try enc.encode(info).write(to: env.supportHelpers.appendingPathComponent(SourceKit.HelperLocator.infoFileName))
        let updated = try await env.run("tools.info.updated", method: "tools.info")
        XCTAssertEqual((updated["result"] as? [String: Any])?["ytDlpOrigin"] as? String, "updated")

        let rev = try await env.run("tools.revertYtDlp")
        XCTAssertEqual((rev["result"] as? [String: Any])?["reverted"] as? Bool, true)
    }

    func testUpdateYtDlp() throws {
        let env = try LinkFixtureEnv(area: "tools")
        defer { env.cleanup() }
        try env.base.golden("tools.updateYtDlp", .params, "{}")
        let data = try JSONEncoder().encode(UpdateYtDlpResult(version: "2026.11.01", origin: "updated", alreadyLatest: false))
        try env.base.golden("tools.updateYtDlp", .result, String(decoding: data, as: UTF8.self))
    }
}
