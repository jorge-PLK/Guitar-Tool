import Foundation

/// Lo que se escribe en el popup «Importar tema» (spec Fase 7b, punto 3).
public enum ImportQuery: Equatable, Sendable {
    /// Enlace listo para `SourceLink.parse` (con esquema si faltaba).
    case link(String)
    case search(String)
    case empty

    /// Prefijos que se aceptan como enlace sin esquema (spec 7b, punto 3).
    static let schemelessPrefixes = ["www.", "youtube.com", "youtu.be", "music.youtube.com", "open.spotify.com"]

    public static func classify(_ text: String) -> ImportQuery {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return .empty }
        let lower = s.lowercased()
        if lower.hasPrefix("spotify:") { return .link(s) }
        if !s.contains(where: \.isWhitespace) {
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
                if let host = URLComponents(string: s)?.host, !host.isEmpty { return .link(s) }
                return .search(s)
            }
            if schemelessPrefixes.contains(where: { lower.hasPrefix($0) }) { return .link("https://" + s) }
        }
        return .search(s)
    }
}
