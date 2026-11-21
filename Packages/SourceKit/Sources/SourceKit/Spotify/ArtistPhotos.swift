import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Foto de un artista desde Spotify (spec Fase 7b, punto 6c).
public enum ArtistImagePicker {
    /// Anchura mínima de la imagen elegida (spec 7b, 6c: «la menor de al menos 160 px»).
    public static let minimumWidth = 160
    static let limit = 5

    /// Plegado sin mayúsculas, acentos ni espacios de los extremos (como `LibraryFilter.fold` de Store).
    public static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func searchURL(_ name: String) -> URL {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let q = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "https://api.spotify.com/v1/search?type=artist&limit=\(limit)&q=\(q)")!
    }

    /// Imagen del primer resultado cuyo nombre coincide con `name` (plegado); nil si ninguno coincide o no tiene imagen.
    public static func pick(from data: Data, artist name: String) throws -> URL? {
        struct Image: Decodable { let url: String; let width: Int? }
        struct Artist: Decodable { let name: String; let images: [Image]? }
        struct Artists: Decodable { let items: [Artist?] }
        struct Root: Decodable { let artists: Artists }
        guard let root = try? JSONDecoder().decode(Root.self, from: data) else { throw SpotifySearchError.badResponse }
        let key = fold(name)
        guard let match = root.artists.items.compactMap({ $0 }).first(where: { fold($0.name) == key }) else { return nil }
        let images = match.images ?? []
        let big = images.filter { ($0.width ?? 0) >= minimumWidth }.min { ($0.width ?? 0) < ($1.width ?? 0) }
        // Si ninguna llega a 160 px, la mayor disponible.
        let chosen = big ?? images.max { ($0.width ?? 0) < ($1.width ?? 0) }
        return chosen.flatMap { URL(string: $0.url) }
    }
}

extension SpotifySearchClient {
    /// URL de la imagen del artista, o nil si Spotify no tiene una coincidencia exacta.
    public func artistImageURL(for name: String) async throws -> URL? {
        try ArtistImagePicker.pick(from: try await get(ArtistImagePicker.searchURL(name)), artist: name)
    }
}

/// Foto en caché de cada artista, en `<support dir>/artists/` (spec 7b, 6c).
public actor ArtistPhotoService {
    /// Cuánto dura la negativa «Spotify no lo conoce» (spec 7b, 6c).
    public static let negativeTTL: TimeInterval = 7 * 24 * 3600
    /// Peticiones simultáneas (spec 7b, 6c).
    public static let maxConcurrent = 2

    private let client: SpotifySearchClient
    private let http: any HTTPSending
    private let directory: URL
    private let now: @Sendable () -> Date
    private var running = 0
    /// Artistas que han fallado por clave, red o error en esta sesión: no se reintentan hasta el próximo arranque.
    private var failedThisSession: Set<String> = []

    public init(client: SpotifySearchClient, http: any HTTPSending, directory: URL,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.http = http
        self.directory = directory
        self.now = now
    }

    /// Cliente real.
    public static func live(supportDir: URL, defaultSupportDir: URL) -> ArtistPhotoService {
        let http = URLSessionSender()
        let tokens = SpotifyTokenProvider(credentials: {
            SpotifyCredentials.load(supportDir: supportDir, defaultSupportDir: defaultSupportDir,
                                    environment: ProcessInfo.processInfo.environment)
        }, http: http)
        return ArtistPhotoService(client: SpotifySearchClient(tokens: tokens, http: http), http: http,
                                  directory: supportDir.appendingPathComponent("artists", isDirectory: true))
    }

    /// Nombre de fichero estable derivado del nombre plegado: legible más un hash FNV-1a para evitar choques.
    nonisolated static func fileStem(_ name: String) -> String {
        let key = ArtistImagePicker.fold(name)
        var h: UInt64 = 0xcbf29ce484222325
        for b in key.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        let slug = String(key.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }.prefix(40))
        return "\(slug)-\(String(h, radix: 16))"
    }

    nonisolated func photoURL(_ name: String) -> URL { directory.appendingPathComponent(Self.fileStem(name) + ".img") }
    nonisolated func missURL(_ name: String) -> URL { directory.appendingPathComponent(Self.fileStem(name) + ".miss") }

    /// Fichero de la foto ya guardada, sin red.
    public nonisolated func cachedPhoto(for name: String) -> URL? {
        let u = photoURL(name)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    private func missIsFresh(_ name: String) -> Bool {
        guard let text = try? String(contentsOf: missURL(name), encoding: .utf8),
              let t = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return now().timeIntervalSince1970 - t < Self.negativeTTL
    }

    /// Foto del artista: caché, o una petición a Spotify (máximo 2 a la vez). nil si no hay (iniciales).
    public func photo(for name: String) async -> URL? {
        let key = ArtistImagePicker.fold(name)
        if key.isEmpty { return nil }
        if let cached = cachedPhoto(for: name) { return cached }
        if missIsFresh(name) || failedThisSession.contains(key) { return nil }
        // Turno: espera cancelable, para que un recuadro que sale de pantalla no ocupe plaza.
        while running >= Self.maxConcurrent {
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return nil }
        }
        if Task.isCancelled { return nil }
        running += 1
        defer { running -= 1 }
        do {
            guard let imageURL = try await client.artistImageURL(for: name) else {
                recordMiss(name)
                return nil
            }
            var request = URLRequest(url: imageURL)
            request.httpMethod = "GET"
            let response = try await http.send(request)
            guard (200..<300).contains(response.status), !response.data.isEmpty else {
                failedThisSession.insert(key)
                return nil
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let dest = photoURL(name)
            try response.data.write(to: dest, options: .atomic)
            try? FileManager.default.removeItem(at: missURL(name))
            return dest
        } catch is CancellationError {
            return nil
        } catch {
            failedThisSession.insert(key)
            return nil
        }
    }

    private func recordMiss(_ name: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(String(now().timeIntervalSince1970).utf8).write(to: missURL(name), options: .atomic)
    }
}
