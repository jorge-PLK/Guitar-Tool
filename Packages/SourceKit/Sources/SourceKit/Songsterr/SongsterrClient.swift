import Compression
import Foundation

/// Carga una página de Songsterr como lo haría un navegador y devuelve su HTML ya cargado. La implementa la app con
/// un `WKWebView` oculto; los tests, con un doble.
public protocol SongsterrPageLoading: Sendable {
    func html(for url: URL) async throws -> String
}

/// Búsqueda, tema y descarga de pistas de Songsterr (spec, «Calidad de la tablatura (Fase 5b)», parte 1).
public struct SongsterrClient: Sendable {
    /// Espera antes del único reintento tras un 429 o un fallo de red (spec: sin bucles, un solo reintento educado).
    public static let retryDelay: Duration = .seconds(5)
    static let browserHeaders: [String: String] = [
        "Accept": "application/json,text/plain,*/*",
        "Accept-Language": "es-ES,es;q=0.9,en;q=0.8"
    ]

    private let loader: any SongsterrPageLoading
    private let fetcher: any HTTPFetching
    private let retryDelay: Duration

    public init(loader: any SongsterrPageLoading, fetcher: any HTTPFetching = URLSessionFetcher(timeout: 30),
                retryDelay: Duration = SongsterrClient.retryDelay) {
        self.loader = loader
        self.fetcher = fetcher
        self.retryDelay = retryDelay
    }

    /// Busca por artista y título en el endpoint JSON (URLSession, sin WKWebView). `SongsterrError.noResults` si no hay
    /// ninguno. Sin reintento automático: un 429 se devuelve como `rateLimited`.
    public func search(artist: String, title: String) async throws -> [SongsterrSearchResult] {
        guard let url = SongsterrReader.searchAPIURL(artist: artist, title: title) else { throw SongsterrError.noResults }
        guard url.scheme == "https", SongsterrReader.isSongsterrHost(url.host) else { throw SongsterrError.invalidHost }
        return try SongsterrReader.parseSearch(json: try await fetch(url))
    }

    /// Pistas de un tema por un enlace pegado (se valida el host).
    public func song(link: String) async throws -> SongsterrSong {
        try await song(url: SongsterrReader.songURL(from: link))
    }

    public func song(songId: Int) async throws -> SongsterrSong {
        guard let url = SongsterrReader.songURL(songId: songId) else { throw SongsterrError.unknownFormat("songId") }
        return try await song(url: url)
    }

    public func song(url: URL) async throws -> SongsterrSong {
        guard url.scheme == "https", SongsterrReader.isSongsterrHost(url.host) else { throw SongsterrError.invalidHost }
        return try SongsterrReader.parseSong(html: try await load(url))
    }

    private func load(_ url: URL) async throws -> String {
        do { return try await loader.html(for: url) } catch let e as SongsterrError { throw e } catch is CancellationError {
            throw SongsterrError.cancelled
        }
    }

    // MARK: Pistas

    /// Descarga los JSON de las pistas indicadas a `directory` (`<partId>.json`), saltando las que ya están. Devuelve
    /// partId -> fichero. `directory` es `ProjectLayout.songsterrCacheDir(songId:revisionId:)`.
    public func downloadTracks(_ tracks: [SongsterrTrack], to directory: URL) async throws -> [Int: URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var files: [Int: URL] = [:]
        for track in tracks {
            try Task.checkCancellation()
            let dst = directory.appendingPathComponent("\(track.partId).json")
            if FileManager.default.fileExists(atPath: dst.path) {
                files[track.partId] = dst
                continue
            }
            guard SongsterrReader.isValidTrackURL(track.url) else { throw SongsterrError.invalidHost }
            let data = Self.gunzipIfNeeded(try await fetchWithOneRetry(track.url))
            guard let obj = try? JSONSerialization.jsonObject(with: data), obj is [String: Any] || obj is [Any] else {
                throw SongsterrError.unknownFormat("JSON de pista \(track.partId)")
            }
            try data.write(to: dst, options: .atomic)
            files[track.partId] = dst
        }
        return files
    }

    /// Un intento y, si falla por 429, red o tiempo, un único reintento tras `retryDelay`. 404 y demás no se reintentan.
    private func fetchWithOneRetry(_ url: URL) async throws -> Data {
        do { return try await fetch(url) } catch let e as SongsterrError where e == .rateLimited || e == .offline {
            try await Task.sleep(for: retryDelay)
            return try await fetch(url)
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        do {
            return try await fetcher.data(from: url, headers: Self.browserHeaders)
        } catch let e as SourceError {
            switch e {
            case .httpStatus(429), .rateLimited: throw SongsterrError.rateLimited
            case .httpStatus(let c): throw SongsterrError.httpStatus(c)
            case .offline, .timedOut: throw SongsterrError.offline
            case .cancelled: throw SongsterrError.cancelled
            default: throw SongsterrError.offline
            }
        }
    }

    /// El CDN a veces sirve gzip sin `Content-Encoding`. Cabecera gzip (RFC 1952) + deflate crudo.
    static func gunzipIfNeeded(_ data: Data) -> Data {
        let b = [UInt8](data)
        guard b.count > 18, b[0] == 0x1f, b[1] == 0x8b, b[2] == 8 else { return data }
        let flags = b[3]
        var pos = 10
        if flags & 4 != 0 {
            guard pos + 2 <= b.count else { return data }
            pos += 2 + Int(b[pos]) + Int(b[pos + 1]) << 8
        }
        for bit: UInt8 in [8, 16] where flags & bit != 0 {
            while pos < b.count, b[pos] != 0 { pos += 1 }
            pos += 1
        }
        if flags & 2 != 0 { pos += 2 }
        guard pos < b.count - 8 else { return data }
        let body = Data(b[pos..<(b.count - 8)])
        return (try? (body as NSData).decompressed(using: .zlib) as Data) ?? data
    }
}
