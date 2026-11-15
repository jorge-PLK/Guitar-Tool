import Foundation

/// Enlace pegado por el usuario (spec, «Recorrido» paso 1).
public enum SourceLink: Equatable, Sendable {
    case youtube(videoID: String)
    case spotify(trackID: String)

    public static func parse(_ text: String) throws -> SourceLink {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("spotify:") {
            let parts = s.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            if parts.count == 3, parts[1] == "track", isSpotifyID(parts[2]) { return .spotify(trackID: parts[2]) }
            throw SourceError.unsupportedLink
        }
        let withScheme = s.contains("://") ? s : "https://" + s
        guard let url = URLComponents(string: withScheme), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host?.lowercased() else {
            throw SourceError.unsupportedLink
        }
        let path = url.path.split(separator: "/").map(String.init)
        switch host {
        case "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com":
            if path == ["watch"], let v = url.queryItems?.first(where: { $0.name == "v" })?.value, isVideoID(v) {
                return .youtube(videoID: v)
            }
        case "youtu.be":
            if path.count == 1, isVideoID(path[0]) { return .youtube(videoID: path[0]) }
        case "open.spotify.com":
            var p = path
            if let first = p.first, first.hasPrefix("intl-") { p.removeFirst() }
            if p.count == 2, p[0] == "track", isSpotifyID(p[1]) { return .spotify(trackID: p[1]) }
        default: break
        }
        throw SourceError.unsupportedLink
    }

    public var canonicalURL: URL {
        switch self {
        case .youtube(let id): URL(string: "https://www.youtube.com/watch?v=\(id)")!
        case .spotify(let id): URL(string: "https://open.spotify.com/track/\(id)")!
        }
    }

    private static func isVideoID(_ s: String) -> Bool {
        s.count == 11 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
    private static func isSpotifyID(_ s: String) -> Bool {
        s.count == 22 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}

/// Enlace de una lista o de un álbum de Spotify (spec, «Listas» > Enlaces).
public enum PlaylistLink: Equatable, Sendable {
    case spotify(playlistID: String)
    case youtube(listID: String)
    /// Los álbumes de Spotify entran igual que las listas.
    case spotifyAlbum(albumID: String)

    public static func parse(_ text: String) throws -> PlaylistLink {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("spotify:") {
            let parts = s.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            if parts.count == 3, parts[1] == "playlist", isSpotifyID(parts[2]) { return .spotify(playlistID: parts[2]) }
            if parts.count == 3, parts[1] == "album", isSpotifyID(parts[2]) { return .spotifyAlbum(albumID: parts[2]) }
            throw SourceError.unsupportedLink
        }
        let withScheme = s.contains("://") ? s : "https://" + s
        guard let url = URLComponents(string: withScheme), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host?.lowercased() else {
            throw SourceError.unsupportedLink
        }
        var path = url.path.split(separator: "/").map(String.init)
        switch host {
        case "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com":
            // `watch?v=…&list=…` es un solo vídeo: solo cuenta la ruta `/playlist`.
            if path == ["playlist"], let l = url.queryItems?.first(where: { $0.name == "list" })?.value, isListID(l) {
                return .youtube(listID: l)
            }
        case "open.spotify.com":
            if let first = path.first, first.hasPrefix("intl-") { path.removeFirst() }
            if path.count == 2, path[0] == "playlist", isSpotifyID(path[1]) { return .spotify(playlistID: path[1]) }
            if path.count == 2, path[0] == "album", isSpotifyID(path[1]) { return .spotifyAlbum(albumID: path[1]) }
        default: break
        }
        throw SourceError.unsupportedLink
    }

    public var canonicalURL: URL {
        switch self {
        case .spotify(let id): URL(string: "https://open.spotify.com/playlist/\(id)")!
        case .spotifyAlbum(let id): URL(string: "https://open.spotify.com/album/\(id)")!
        case .youtube(let id): URL(string: "https://www.youtube.com/playlist?list=\(id)")!
        }
    }

    private static func isSpotifyID(_ s: String) -> Bool {
        s.count == 22 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
    private static func isListID(_ s: String) -> Bool {
        s.count >= 2 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
}

/// Lo que puede ser el enlace pegado en «Desde enlace…»: un tema o una lista.
/// `SourceLink.parse` no cambia (sigue rechazando listas); la hoja usa este para reconocer el tipo.
public enum SourceInput: Equatable, Sendable {
    case single(SourceLink)
    case playlist(PlaylistLink)

    public static func parse(_ text: String) throws -> SourceInput {
        if let list = try? PlaylistLink.parse(text) { return .playlist(list) }
        return .single(try SourceLink.parse(text))
    }
}
