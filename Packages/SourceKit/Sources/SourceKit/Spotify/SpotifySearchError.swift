import Foundation

/// Fallos de la búsqueda en Spotify, con los mensajes de la spec Fase 7b, punto 4. Sin secretos ni cuerpos de respuesta.
public enum SpotifySearchError: Error, Equatable, Sendable, LocalizedError {
    case missingCredentials
    case rejected(Int)
    case rateLimited(retryAfter: Int)
    case network
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .missingCredentials: "Búsqueda en Spotify no disponible: falta la clave (.env)"
        case .rejected: "Spotify ha rechazado la clave"
        case .rateLimited(let n): "Spotify pide esperar \(n) s"
        case .network: "Sin conexión con Spotify"
        case .badResponse: "Spotify ha devuelto una respuesta inesperada"
        }
    }
}
