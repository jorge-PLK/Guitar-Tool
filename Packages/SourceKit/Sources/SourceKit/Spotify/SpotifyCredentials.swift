import Foundation

/// Credenciales de la app de Spotify. Nunca se imprimen (spec Fase 7b, punto 4, «Secretos»).
public struct SpotifyCredentials: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let idKey = "SPOTIFY_CLIENT_ID"
    public static let secretKey = "SPOTIFY_CLIENT_SECRET"

    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    public var description: String { "SpotifyCredentials(<oculto>)" }
    public var debugDescription: String { description }

    /// `<support dir>/.env`; si no existe, el del directorio por defecto; después, variable a variable, el entorno manda.
    public static func load(supportDir: URL, defaultSupportDir: URL,
                            environment: [String: String]) -> SpotifyCredentials? {
        let fm = FileManager.default
        let primary = supportDir.appendingPathComponent(".env")
        let file = fm.fileExists(atPath: primary.path) ? primary : defaultSupportDir.appendingPathComponent(".env")
        var values: [String: String] = [:]
        if let text = try? String(contentsOf: file, encoding: .utf8) { values = DotEnv.parse(text) }
        func pick(_ key: String) -> String? {
            let v = environment[key].flatMap { $0.isEmpty ? nil : $0 } ?? values[key]
            return v.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let id = pick(idKey), let secret = pick(secretKey) else { return nil }
        return SpotifyCredentials(clientID: id, clientSecret: secret)
    }
}
