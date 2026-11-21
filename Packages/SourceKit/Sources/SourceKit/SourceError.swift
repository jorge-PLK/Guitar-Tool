import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Motivo de un vídeo no disponible (spec, «Fuentes externas» > Errores).
public enum UnavailableReason: Sendable, Equatable {
    case region, privateVideo, removed
}

/// Errores del recorrido de importación desde enlace (spec, «Fuentes externas» > Errores).
public enum SourceError: Error, Sendable, Equatable {
    /// Sin red: error de URLSession o yt-dlp con fallo de resolución o conexión.
    case offline
    /// El enlace pegado no es un vídeo de YouTube ni una canción de Spotify.
    case unsupportedLink
    /// Falta `__NEXT_DATA__` o no trae título y duración.
    case spotifyMetadataUnreadable
    /// «Sign in to confirm your age». No se usan cookies ni cuentas.
    case ageRestricted
    case unavailable(UnavailableReason)
    /// «Requested format is not available»: ni Opus ni M4A.
    case noAudioFormat
    /// Error de extractor, firma/nsig, HTTP 403 o salida distinta de 0 sin clasificar.
    case extractorBroken(version: String?, detail: String)
    case ffmpegFailed(String)
    case helperMissing(String)
    case launchFailed(String)
    case httpStatus(Int)
    case timedOut
    case cancelled
    case checksumMismatch
    case updateFailed(String)
    /// Límite de YouTube: «Sign in to confirm you're not a bot» o HTTP 429. La cola de listas se detiene.
    case rateLimited
    /// yt-dlp terminó bien pero no dejó fichero de audio.
    case noAudioProduced

    /// Los errores tras los que la hoja vuelve a la lista de candidatos.
    public var returnsToCandidates: Bool {
        switch self {
        case .ageRestricted, .unavailable, .noAudioFormat: true
        default: false
        }
    }

    /// Los que ofrecen «Actualizar y reintentar».
    public var suggestsYtDlpUpdate: Bool {
        if case .extractorBroken = self { return true }
        return false
    }
}
