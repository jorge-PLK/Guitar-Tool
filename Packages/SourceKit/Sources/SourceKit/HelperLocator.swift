import Foundation

/// Contenido de `yt-dlp.json`, junto a un yt-dlp actualizado (spec, «Helpers embebidos»).
public struct YtDlpInstallInfo: Codable, Sendable, Equatable {
    public var version: String
    public var sha256: String
    public var installedAt: Date

    public init(version: String, sha256: String, installedAt: Date) {
        self.version = version
        self.sha256 = sha256
        self.installedAt = installedAt
    }
}

/// Rutas de los tres helpers. Para yt-dlp elige la versión más nueva entre la del bundle y la de
/// `Application Support/ToneForge/Helpers`. Ante un empate gana el bundle.
public struct HelperLocator: Sendable {
    public enum Origin: Sendable, Equatable { case bundle, updated }

    public struct YtDlpChoice: Sendable, Equatable {
        public var url: URL
        public var version: String?
        public var origin: Origin
    }

    public static let infoFileName = "yt-dlp.json"

    public let bundleDirectory: URL
    public let supportDirectory: URL
    private let bundleYtDlpVersion: String?

    /// `bundleDirectory`: donde están `yt-dlp`, `deno` y `ffmpeg` del bundle (`Contents/MacOS`).
    /// `bundleYtDlpVersion`: versión del yt-dlp del bundle; si es nil se lee de un `yt-dlp.json` a su lado.
    public init(bundleDirectory: URL, supportDirectory: URL = HelperLocator.defaultSupportDirectory,
                bundleYtDlpVersion: String? = nil) {
        self.bundleDirectory = bundleDirectory
        self.supportDirectory = supportDirectory
        self.bundleYtDlpVersion = bundleYtDlpVersion
    }

    public static var defaultSupportDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("ToneForge/Helpers", isDirectory: true)
    }

    public func ytDlp() throws -> YtDlpChoice {
        let bundled = bundleDirectory.appendingPathComponent("yt-dlp")
        let updated = supportDirectory.appendingPathComponent("yt-dlp")
        let fm = FileManager.default
        let hasBundled = fm.isExecutableFile(atPath: bundled.path)
        let hasUpdated = fm.isExecutableFile(atPath: updated.path)
        let bundledVersion = bundleYtDlpVersion ?? Self.readInfo(in: bundleDirectory)?.version
        let updatedVersion = Self.readInfo(in: supportDirectory)?.version
        switch (hasBundled, hasUpdated) {
        case (false, false): throw SourceError.helperMissing("yt-dlp")
        case (true, false): return .init(url: bundled, version: bundledVersion, origin: .bundle)
        case (false, true): return .init(url: updated, version: updatedVersion, origin: .updated)
        case (true, true):
            // Sin versión conocida del bundle, la actualizada gana; sin la de la actualizada, el bundle.
            guard let updatedVersion else { return .init(url: bundled, version: bundledVersion, origin: .bundle) }
            if let bundledVersion, Self.compare(bundledVersion, updatedVersion) >= 0 {
                return .init(url: bundled, version: bundledVersion, origin: .bundle)
            }
            return .init(url: updated, version: updatedVersion, origin: .updated)
        }
    }

    public func deno() throws -> URL { try bundled("deno") }
    public func ffmpeg() throws -> URL { try bundled("ffmpeg") }

    /// Borra el yt-dlp actualizado («Volver a la embebida»).
    public func removeUpdate() throws {
        for name in ["yt-dlp", Self.infoFileName] {
            let u = supportDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: u.path) { try FileManager.default.removeItem(at: u) }
        }
    }

    private func bundled(_ name: String) throws -> URL {
        let u = bundleDirectory.appendingPathComponent(name)
        guard FileManager.default.isExecutableFile(atPath: u.path) else { throw SourceError.helperMissing(name) }
        return u
    }

    static func readInfo(in directory: URL) -> YtDlpInstallInfo? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(infoFileName)) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(YtDlpInstallInfo.self, from: data)
    }

    /// Compara versiones de yt-dlp por fecha (`2025.10.22`, `2025.10.22.123456`): negativo, 0 o positivo.
    public static func compare(_ a: String, _ b: String) -> Int {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }
}
