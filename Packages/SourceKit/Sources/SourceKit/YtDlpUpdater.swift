import CryptoKit
import Foundation

/// Baja `yt-dlp_macos` y `SHA2-256SUMS` de la última release, verifica y lo instala en
/// `Application Support/ToneForge/Helpers/yt-dlp` con su `yt-dlp.json`.
public struct YtDlpUpdater: Sendable {
    public static let releaseBase = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/")!
    static let assetName = "yt-dlp_macos"
    static let sumsName = "SHA2-256SUMS"

    private let supportDirectory: URL
    private let http: HTTPFetching
    private let runner: ProcessRunning
    private let releaseBase: URL
    private let now: @Sendable () -> Date

    public init(supportDirectory: URL = HelperLocator.defaultSupportDirectory, http: HTTPFetching,
                runner: ProcessRunning, releaseBase: URL = YtDlpUpdater.releaseBase,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.supportDirectory = supportDirectory
        self.http = http
        self.runner = runner
        self.releaseBase = releaseBase
        self.now = now
    }

    /// Descarga, verifica el SHA-256 (si no coincide lanza `checksumMismatch` y no instala nada),
    /// comprueba que el binario arranca (`--version`) y lo instala.
    @discardableResult
    public func update() async throws -> YtDlpInstallInfo {
        let sums = try await http.data(from: releaseBase.appendingPathComponent(Self.sumsName), headers: [:])
        let binary = try await http.data(from: releaseBase.appendingPathComponent(Self.assetName), headers: [:])
        guard let expected = Self.expectedHash(in: String(decoding: sums, as: UTF8.self)) else {
            throw SourceError.updateFailed("\(Self.sumsName) no lista \(Self.assetName)")
        }
        let actual = SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw SourceError.checksumMismatch }

        let fm = FileManager.default
        try fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let staged = supportDirectory.appendingPathComponent("yt-dlp.new")
        try binary.write(to: staged)
        defer { try? fm.removeItem(at: staged) }
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)

        let r = try await runner.run(.init(executable: staged, arguments: ["--version"], timeout: YtDlpClient.infoTimeout))
        let version = String(decoding: r.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard r.status == 0, !version.isEmpty else { throw SourceError.updateFailed("el yt-dlp descargado no arranca") }

        let target = supportDirectory.appendingPathComponent("yt-dlp")
        if fm.fileExists(atPath: target.path) { _ = try fm.replaceItemAt(target, withItemAt: staged) }
        else { try fm.moveItem(at: staged, to: target) }

        let info = YtDlpInstallInfo(version: version, sha256: actual, installedAt: now())
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(info).write(to: supportDirectory.appendingPathComponent(HelperLocator.infoFileName))
        return info
    }

    static func expectedHash(in sums: String) -> String? {
        for line in sums.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "*" || $0 == "\t" })
            if parts.count == 2, parts[1] == assetName { return parts[0].lowercased() }
        }
        return nil
    }
}
