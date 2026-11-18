import Foundation

/// Búsqueda de pistas en la API web de Spotify (spec Fase 7b, punto 4).
public struct SpotifySearchClient: SpotifySearching {
    public static let resultLimit = 10
    private let tokens: SpotifyTokenProvider
    private let http: any HTTPSending

    public init(tokens: SpotifyTokenProvider, http: any HTTPSending) {
        self.tokens = tokens
        self.http = http
    }

    /// Cliente real: lee la clave al buscar, con el orden de `SpotifyCredentials.load`.
    public static func live(supportDir: URL, defaultSupportDir: URL,
                            environment: [String: String] = ProcessInfo.processInfo.environment) -> SpotifySearchClient {
        let http = URLSessionSender()
        let provider = SpotifyTokenProvider(credentials: {
            SpotifyCredentials.load(supportDir: supportDir, defaultSupportDir: defaultSupportDir, environment: environment)
        }, http: http)
        return SpotifySearchClient(tokens: provider, http: http)
    }

    static func searchURL(_ query: String) -> URL {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let q = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "https://api.spotify.com/v1/search?type=track&limit=\(resultLimit)&q=\(q)")!
    }

    public func search(_ query: String) async throws -> [SpotifyTrackResult] {
        try Self.parse(try await get(Self.searchURL(query)))
    }

    /// GET con token; un 401 renueva el token y reintenta una vez; 403 y 429 sin reintento.
    func get(_ url: URL) async throws -> Data {
        var retried = false
        while true {
            let token = try await tokens.token()
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let response: HTTPResponse
            do { response = try await http.send(request) } catch is CancellationError { throw CancellationError() } catch {
                throw SpotifySearchError.network
            }
            switch response.status {
            case 200..<300: return response.data
            case 401:
                if retried { await tokens.reset(); throw SpotifySearchError.rejected(401) }
                retried = true
                await tokens.invalidate()
            case 403:
                await tokens.reset()
                throw SpotifySearchError.rejected(403)
            case 429: throw SpotifySearchError.rateLimited(retryAfter: SpotifyTokenProvider.retryAfter(response))
            default: throw SpotifySearchError.badResponse
            }
        }
    }

    static func parse(_ data: Data) throws -> [SpotifyTrackResult] {
        struct Image: Decodable { let url: String; let width: Int? }
        struct Album: Decodable { let name: String?; let release_date: String?; let images: [Image]? }
        struct Artist: Decodable { let name: String }
        struct Item: Decodable {
            let id: String; let name: String; let artists: [Artist]?; let album: Album?; let duration_ms: Int?
        }
        struct Tracks: Decodable { let items: [Item?] }
        struct Root: Decodable { let tracks: Tracks }
        guard let root = try? JSONDecoder().decode(Root.self, from: data) else { throw SpotifySearchError.badResponse }
        return root.tracks.items.compactMap { item -> SpotifyTrackResult? in
            guard let item else { return nil }
            // Carátula pequeña: la menor que tenga al menos 64 px; si no, la última.
            let images = item.album?.images ?? []
            let image = images.filter { ($0.width ?? 0) >= 64 }.min { ($0.width ?? 0) < ($1.width ?? 0) } ?? images.last
            let year = item.album?.release_date.flatMap { Int($0.prefix(4)) }
            return SpotifyTrackResult(
                id: item.id, name: item.name, artists: (item.artists ?? []).map(\.name),
                album: item.album?.name ?? "", year: year, durationMs: item.duration_ms ?? 0,
                imageURL: image.flatMap { URL(string: $0.url) })
        }
    }
}
