import Foundation

public struct HTTPResponse: Sendable {
    public let status: Int
    /// Cabeceras con el nombre en minúsculas.
    public let headers: [String: String]
    public let data: Data
    public init(status: Int, headers: [String: String] = [:], data: Data = Data()) {
        self.status = status
        self.headers = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        self.data = data
    }
}

/// Petición con estado y cabeceras de vuelta (POST, 401, Retry-After). No lanza por el código de estado.
public protocol HTTPSending: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionSender: HTTPSending {
    public init() {}
    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        var request = request
        request.timeoutInterval = URLSessionFetcher.metadataTimeout
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SourceError.offline }
            var headers: [String: String] = [:]
            for (k, v) in http.allHeaderFields { headers["\(k)"] = "\(v)" }
            return HTTPResponse(status: http.statusCode, headers: headers, data: data)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw SourceError.offline
        }
    }
}
