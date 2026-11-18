import Foundation

/// Un resultado de la búsqueda de Spotify.
public struct SpotifyTrackResult: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let artists: [String]
    public let album: String
    public let year: Int?
    public let durationMs: Int
    public let imageURL: URL?

    public init(id: String, name: String, artists: [String], album: String, year: Int?,
                durationMs: Int, imageURL: URL?) {
        self.id = id; self.name = name; self.artists = artists; self.album = album
        self.year = year; self.durationMs = durationMs; self.imageURL = imageURL
    }

    public var trackURL: URL { URL(string: "https://open.spotify.com/track/\(id)")! }
    public var appURL: URL { URL(string: "spotify:track:\(id)")! }
    public var artistsText: String { artists.joined(separator: ", ") }
    /// m:ss
    public var durationText: String {
        let s = max(0, durationMs / 1000)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

public protocol SpotifySearching: Sendable {
    func search(_ query: String) async throws -> [SpotifyTrackResult]
}
