import Foundation

/// Lo que todavía no existe en este sistema. Los stubs de Windows del paso 6 lanzan
/// `.unsupported("paso 7: <pieza>")` (plan, «Fase 7c», corte del paso 6) y sus tests se saltan con
/// `XCTSkip("[paso 7] <pieza>")`.
public enum PlatformError: Error, Equatable, Sendable, LocalizedError {
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let what): "No disponible en este sistema: \(what)"
        }
    }
}
