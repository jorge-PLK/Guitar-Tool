import AudioKit
import Foundation

/// Mensaje del núcleo compuesto por código (`docs/flutter/arquitectura.md` regla 6): Dart traduce `code` con `args` y, si no
/// conoce el código, enseña `message` (el texto español de siempre). `args` se omite si está vacío.
public struct CoreMessage: Codable, Equatable, Sendable {
    public var code: String
    public var message: String
    public var args: [String: JSONValue]?

    public init(code: String, message: String, args: [String: JSONValue] = [:]) {
        self.code = code
        self.message = message
        self.args = args.isEmpty ? nil : args
    }
}

extension JSONValue: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
}

extension RecordBlock {
    /// Código estable del motivo, sin prefijo de superficie (`record-block-` / `audio-block-`).
    var reasonCode: String {
        switch self {
        case .noInputDevice: return "no-input-device"
        case .noGuitarInput: return "no-guitar-input"
        case .invalidChannels: return "invalid-channels"
        case .inputDisconnected: return "input-disconnected"
        case .outputDisconnected: return "output-disconnected"
        case .rateMismatch: return "rate-mismatch"
        case .sessionUnavailable: return "session-unavailable"
        case .speed: return "speed"
        case .loop: return "loop"
        case .busy: return "busy"
        }
    }

    /// Datos variables del motivo (frecuencias en Hz como número; `detail` es el texto del error del sistema).
    var reasonArgs: [String: JSONValue] {
        switch self {
        case let .rateMismatch(device, working): return ["deviceHz": .double(device), "workingHz": .double(working)]
        case .sessionUnavailable(let s): return ["detail": .string(s)]
        case .speed(let r): return ["rate": .double(r)]
        default: return [:]
        }
    }

    func coreMessage(prefix: String) -> CoreMessage {
        CoreMessage(code: "\(prefix)-block-\(reasonCode)", message: message, args: reasonArgs)
    }
}
