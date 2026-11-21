import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Token de client credentials, solo en memoria (spec Fase 7b, punto 4).
public actor SpotifyTokenProvider {
    /// Margen antes de la caducidad (spec 7b, punto 4).
    public static let expiryMargin: TimeInterval = 60
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    private let loadCredentials: @Sendable () -> SpotifyCredentials?
    private let http: any HTTPSending
    private let now: @Sendable () -> Date
    private var credentials: SpotifyCredentials?
    private var token: String?
    private var expiry = Date.distantPast

    public init(credentials: @escaping @Sendable () -> SpotifyCredentials?, http: any HTTPSending,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.loadCredentials = credentials
        self.http = http
        self.now = now
    }

    public func token() async throws -> String {
        if let token, now() < expiry { return token }
        guard let creds = credentials ?? loadCredentials() else { throw SpotifySearchError.missingCredentials }
        credentials = creds
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        let basic = Data("\(creds.clientID):\(creds.clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("grant_type=client_credentials".utf8)
        let response: HTTPResponse
        do { response = try await http.send(request) } catch is CancellationError { throw CancellationError() } catch {
            throw SpotifySearchError.network
        }
        switch response.status {
        case 200..<300: break
        case 429: throw SpotifySearchError.rateLimited(retryAfter: Self.retryAfter(response))
        case 400, 401, 403:
            credentials = nil  // se vuelve a leer el .env en la próxima búsqueda
            throw SpotifySearchError.rejected(response.status)
        default: throw SpotifySearchError.badResponse
        }
        struct Body: Decodable { let access_token: String; let expires_in: Double? }
        guard let body = try? JSONDecoder().decode(Body.self, from: response.data), !body.access_token.isEmpty else {
            throw SpotifySearchError.badResponse
        }
        token = body.access_token
        expiry = now().addingTimeInterval((body.expires_in ?? 3600) - Self.expiryMargin)
        return body.access_token
    }

    /// Olvida el token (tras un 401).
    public func invalidate() { token = nil }

    /// Olvida también las credenciales para releer el `.env`.
    public func reset() { token = nil; credentials = nil }

    static func retryAfter(_ r: HTTPResponse) -> Int {
        r.headers["retry-after"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 1
    }
}
