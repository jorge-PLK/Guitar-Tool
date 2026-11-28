import AudioKit
import Foundation

/// Códigos estables del fallo de la salida de audio (`audioErrorCode` en los estados de Estudio, visor de toma y
/// Montaje, y `args.code` de `audio-unavailable`). Los usa la UI para elegir el aviso; no cambiarlos sin avisar a Dart.
enum AudioErrorCode {
    static let notConnected = "not-connected"
    static let sampleRateMismatch = "sample-rate-mismatch"
    static let busy = "busy"
    static let unavailable = "unavailable"
}

/// Código estable de un fallo de audio (contrato con la UI).
func audioErrorCode(_ error: Error) -> String {
    switch error {
    case let e as AudioIOError:
        switch e {
        case .notConnected, .noInput: return AudioErrorCode.notConnected
        case .sampleRateMismatch: return AudioErrorCode.sampleRateMismatch
        case .alreadyRunning: return AudioErrorCode.busy
        case .device: return AudioErrorCode.unavailable
        }
    case let e as AudioSessionError:
        switch e {
        case .notConnected, .noInputDevice: return AudioErrorCode.notConnected
        case .sampleRateMismatch: return AudioErrorCode.sampleRateMismatch
        case .busy: return AudioErrorCode.busy
        default: return AudioErrorCode.unavailable
        }
    default: return AudioErrorCode.unavailable
    }
}

/// Textos humanos y errores del audio, comunes a Estudio, visor de toma y Montaje.
enum AudioErrorText {
    /// Texto del error sin nombres de caso ni identificadores.
    static func describe(_ error: Error) -> String { (error as? LocalizedError)?.errorDescription ?? "\(error)" }

    /// Alias de `audioErrorCode(_:)` para llamarlo desde tipos que tienen una propiedad con ese nombre.
    static func code(_ error: Error) -> String { audioErrorCode(error) }

    static func openMessage(_ error: Error) -> String {
        "No se pudo abrir la salida de audio (\(describe(error)))."
    }

    static func playMessage(_ error: Error) -> String {
        "No se pudo reproducir: la salida de audio no abre (\(describe(error)))."
    }

    /// `audio-unavailable` con el código en `args.code`.
    static func playRPCError(_ error: Error, message: String) -> RPCError {
        RPCError(code: "audio-unavailable", message: message, args: ["code": .string(code(error))])
    }
}
