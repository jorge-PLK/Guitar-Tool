import Foundation

/// Error de un método; viaja como `{"error":{"code","message"}}`.
public struct RPCError: Error, Sendable, Equatable {
    public let code: String
    public let message: String
    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

/// Resultado vacío (`{}`) y parámetros vacíos.
public struct Empty: Codable, Sendable {
    public init() {}
}

/// Registro de métodos tipados `ns.nombre`: parámetros `Decodable`, resultado `Encodable`, `async throws`.
/// Se amplía por pantalla registrando más métodos; nunca se cae con entrada malformada.
public final class Router: @unchecked Sendable {
    private typealias Handler = @Sendable (Data) async throws -> Data

    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]

    public init() {}

    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func register<P: Decodable & Sendable, R: Encodable & Sendable>(
        _ method: String, _ handler: @escaping @Sendable (P) async throws -> R
    ) {
        let h: Handler = { data in
            let params: P
            do { params = try Router.makeDecoder().decode(P.self, from: data) } catch {
                throw RPCError(code: "bad-params", message: "Parámetros no válidos para \(method): \(error)")
            }
            return try Router.makeEncoder().encode(try await handler(params))
        }
        lock.lock(); handlers[method] = h; lock.unlock()
    }

    private func lookup(_ method: String) -> Handler? {
        lock.lock(); defer { lock.unlock() }
        return handlers[method]
    }

    /// Procesa un mensaje de la página y devuelve la respuesta JSON (siempre; nunca lanza).
    public func handle(_ json: String) async -> String {
        guard let data = json.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let obj = any as? [String: Any] else {
            return Self.errorResponse(id: nil, RPCError(code: "bad-json", message: "El mensaje no es un objeto JSON."))
        }
        let id = (obj["id"] as? NSNumber).flatMap { Int(exactly: $0.int64Value) }
        guard let id, let method = obj["method"] as? String else {
            return Self.errorResponse(id: id, RPCError(code: "bad-request", message: "Falta «id» entero o «method»."))
        }
        let handler = lookup(method)
        guard let handler else {
            return Self.errorResponse(id: id, RPCError(code: "unknown-method", message: "Método desconocido: \(method)"))
        }
        let paramsObject = obj["params"] ?? [String: Any]()
        guard JSONSerialization.isValidJSONObject(paramsObject),
              let paramsData = try? JSONSerialization.data(withJSONObject: paramsObject) else {
            return Self.errorResponse(id: id, RPCError(code: "bad-params", message: "«params» no es JSON válido."))
        }
        do {
            let result = try await handler(paramsData)
            return "{\"id\":\(id),\"result\":\(String(decoding: result, as: UTF8.self))}"
        } catch let e as RPCError {
            return Self.errorResponse(id: id, e)
        } catch {
            return Self.errorResponse(id: id, RPCError(code: "internal", message: "\(error)"))
        }
    }

    /// Evento núcleo -> página.
    public static func eventMessage<T: Encodable>(_ name: String, _ payload: T) -> String? {
        guard let data = try? makeEncoder().encode(payload),
              let nameData = try? JSONEncoder().encode(name) else { return nil }
        return "{\"event\":\(String(decoding: nameData, as: UTF8.self)),\"payload\":\(String(decoding: data, as: UTF8.self))}"
    }

    private struct ErrorBody: Encodable { let code: String; let message: String }
    private struct ErrorEnvelope: Encodable {
        let id: Int?
        let error: ErrorBody
    }

    static func errorResponse(id: Int?, _ e: RPCError) -> String {
        let env = ErrorEnvelope(id: id, error: ErrorBody(code: e.code, message: e.message))
        let data = (try? JSONEncoder().encode(env)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
