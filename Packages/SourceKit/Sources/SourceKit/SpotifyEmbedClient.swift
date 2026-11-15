import Foundation

/// Metadatos de una canción de Spotify leídos del embed.
public struct SpotifyTrack: Sendable, Equatable {
    public var id: String
    public var title: String
    public var artists: [String]
    public var durationSeconds: Double
    /// La mayor de las carátulas del embed.
    public var artworkURL: URL?
}

/// Tema de una lista de Spotify (del `trackList` del embed).
public struct SpotifyPlaylistTrack: Sendable, Equatable, Identifiable {
    /// Identificador de Spotify (del `uri`).
    public var id: String
    public var title: String
    /// `subtitle` del embed, tal cual.
    public var artistText: String
    public var durationSeconds: Double
    public var isExplicit: Bool
    /// Primer artista del `subtitle` (el que se usa para buscar).
    public var firstArtist: String { artists.first ?? artistText }
    /// Artistas del `subtitle` (separados por coma; el embed a veces usa un espacio duro tras la coma).
    public var artists: [String] {
        artistText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

public struct SpotifyPlaylist: Sendable, Equatable {
    public var id: String
    public var name: String
    public var tracks: [SpotifyPlaylistTrack]
    /// Llegaron justo 100 temas: el embed no declara el total y Spotify puede haber cortado la lista.
    public var mayBeTruncated: Bool
}

public protocol SpotifyMetadataFetching: Sendable {
    func track(id: String) async throws -> SpotifyTrack
    func playlist(id: String) async throws -> SpotifyPlaylist
    /// Un álbum se lee como una lista (`embed/album/<id>`, mismo `trackList`).
    func album(id: String) async throws -> SpotifyPlaylist
}

public extension SpotifyMetadataFetching {
    /// Por defecto, sin soporte de listas (para simulaciones que solo implementan `track`).
    func playlist(id: String) async throws -> SpotifyPlaylist { throw SourceError.spotifyMetadataUnreadable }
    func album(id: String) async throws -> SpotifyPlaylist { throw SourceError.spotifyMetadataUnreadable }
}

/// `GET https://open.spotify.com/embed/track/<id>` y lectura del JSON `__NEXT_DATA__`
/// (spec, «Recorrido» paso 2). Sin credenciales ni API.
public struct SpotifyEmbedClient: SpotifyMetadataFetching {
    private let http: HTTPFetching

    public init(http: HTTPFetching) { self.http = http }

    public func track(id: String) async throws -> SpotifyTrack {
        let url = URL(string: "https://open.spotify.com/embed/track/\(id)")!
        let data: Data
        do { data = try await http.data(from: url, headers: [:]) } catch SourceError.httpStatus {
            throw SourceError.spotifyMetadataUnreadable
        }
        return try Self.parse(html: String(decoding: data, as: UTF8.self), id: id)
    }

    /// Número de temas a partir del cual se avisa de un posible corte (spec, «Listas» > Lectura).
    public static let playlistTruncationCount = 100

    /// `GET https://open.spotify.com/embed/playlist/<id>` y su `__NEXT_DATA__`.
    public func playlist(id: String) async throws -> SpotifyPlaylist { try await trackList(kind: "playlist", id: id) }

    /// `GET https://open.spotify.com/embed/album/<id>`: misma estructura que la lista.
    public func album(id: String) async throws -> SpotifyPlaylist { try await trackList(kind: "album", id: id) }

    private func trackList(kind: String, id: String) async throws -> SpotifyPlaylist {
        let url = URL(string: "https://open.spotify.com/embed/\(kind)/\(id)")!
        let data: Data
        do { data = try await http.data(from: url, headers: [:]) } catch SourceError.httpStatus {
            throw SourceError.spotifyMetadataUnreadable
        }
        return try Self.parsePlaylist(html: String(decoding: data, as: UTF8.self), id: id)
    }

    public static func parsePlaylist(html: String, id: String) throws -> SpotifyPlaylist {
        guard let entity = entity(in: html), let list = entity["trackList"] as? [[String: Any]],
              let name = (entity["name"] as? String) ?? (entity["title"] as? String) else {
            throw SourceError.spotifyMetadataUnreadable
        }
        let tracks = list.compactMap { t -> SpotifyPlaylistTrack? in
            guard let uri = t["uri"] as? String, uri.hasPrefix("spotify:track:"), let title = t["title"] as? String,
                  let ms = (t["duration"] as? NSNumber)?.doubleValue, ms > 0 else { return nil }
            return SpotifyPlaylistTrack(
                id: String(uri.dropFirst("spotify:track:".count)), title: title,
                artistText: t["subtitle"] as? String ?? "", durationSeconds: ms / 1000,
                isExplicit: t["isExplicit"] as? Bool ?? false)
        }
        return SpotifyPlaylist(id: (entity["id"] as? String) ?? id, name: name, tracks: tracks,
                               mayBeTruncated: list.count >= playlistTruncationCount)
    }

    private static func entity(in html: String) -> [String: Any]? {
        guard let marker = html.range(of: "id=\"__NEXT_DATA__\""),
              let open = html.range(of: ">", range: marker.upperBound..<html.endIndex),
              let close = html.range(of: "</script>", range: open.upperBound..<html.endIndex),
              let json = try? JSONSerialization.jsonObject(with: Data(html[open.upperBound..<close.lowerBound].utf8)) as? [String: Any],
              let props = json["props"] as? [String: Any], let page = props["pageProps"] as? [String: Any],
              let state = page["state"] as? [String: Any], let data = state["data"] as? [String: Any] else { return nil }
        return data["entity"] as? [String: Any]
    }

    /// Extrae la entidad de `__NEXT_DATA__`. Lanza `spotifyMetadataUnreadable` si no hay título y duración.
    public static func parse(html: String, id: String) throws -> SpotifyTrack {
        guard let marker = html.range(of: "id=\"__NEXT_DATA__\""),
              let open = html.range(of: ">", range: marker.upperBound..<html.endIndex),
              let close = html.range(of: "</script>", range: open.upperBound..<html.endIndex),
              let json = try? JSONSerialization.jsonObject(with: Data(html[open.upperBound..<close.lowerBound].utf8)) as? [String: Any],
              let props = json["props"] as? [String: Any], let page = props["pageProps"] as? [String: Any],
              let state = page["state"] as? [String: Any], let data = state["data"] as? [String: Any],
              let entity = data["entity"] as? [String: Any],
              let title = (entity["title"] as? String) ?? (entity["name"] as? String), !title.isEmpty,
              let ms = (entity["duration"] as? NSNumber)?.doubleValue, ms > 0 else {
            throw SourceError.spotifyMetadataUnreadable
        }
        let artists = (entity["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let images = ((entity["visualIdentity"] as? [String: Any])?["image"] as? [[String: Any]]) ?? []
        let best = images.max { ($0["maxWidth"] as? Int ?? 0) < ($1["maxWidth"] as? Int ?? 0) }
        return SpotifyTrack(
            id: (entity["id"] as? String) ?? id, title: title, artists: artists, durationSeconds: ms / 1000,
            artworkURL: (best?["url"] as? String).flatMap(URL.init(string:)))
    }
}
