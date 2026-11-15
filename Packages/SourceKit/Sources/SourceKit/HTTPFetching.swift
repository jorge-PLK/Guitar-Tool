import Foundation

/// Descarga de datos por HTTP, inyectable para que los tests no toquen la red.
public protocol HTTPFetching: Sendable {
    func data(from url: URL, headers: [String: String]) async throws -> Data
}

public extension HTTPFetching {
    func data(from url: URL) async throws -> Data { try await data(from: url, headers: [:]) }
}

/// Implementación real sobre URLSession. Traduce los fallos de conexión a `SourceError.offline`.
public struct URLSessionFetcher: HTTPFetching {
    /// Tiempo límite de los metadatos (spec, «Errores»: 15 s).
    public static let metadataTimeout: TimeInterval = 15
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private let timeout: TimeInterval

    public init(timeout: TimeInterval = URLSessionFetcher.metadataTimeout) { self.timeout = timeout }

    public func data(from url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw SourceError.httpStatus(http.statusCode)
            }
            return data
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw SourceError.cancelled
            case .timedOut: throw SourceError.timedOut
            default: throw SourceError.offline
            }
        }
    }
}
