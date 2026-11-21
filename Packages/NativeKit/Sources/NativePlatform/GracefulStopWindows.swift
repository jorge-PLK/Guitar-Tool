#if os(Windows)
import Foundation
import WinSDK

/// Parada ordenada entre procesos en Windows (plan, «Corte del paso 7», parte 7.8): no hay SIGTERM entre procesos y
/// `ChildProcess.terminate` es `TerminateJobObject` (el hijo no limpia nada). El padre crea un evento con nombre y
/// pasa el nombre al hijo (p. ej. por el entorno); el hijo lo vigila y, al señalarse, sale por su camino ordenado.
/// El padre sigue usando `ChildProcess.terminate(grace:)` como respaldo si el hijo no sale a tiempo.
/// (Fichero aparte: `import WinSDK` choca con `Foundation.UUID`; aquí no se usa `UUID`.)
public final class StopEvent: @unchecked Sendable {
    /// Variable de entorno con el nombre del evento que vigila el hijo.
    public static let environmentKey = "TF_STOP_EVENT"

    public let name: String
    private let handle: HANDLE

    /// Padre: crea el evento (reinicio manual, sin señalar). `name` p. ej. `Local\ToneForge-stop-<id>`.
    public init?(name: String) {
        guard let h = name.withCString(encodedAs: UTF16.self, { CreateEventW(nil, true, false, $0) }) else { return nil }
        handle = h
        self.name = name
    }

    deinit { CloseHandle(handle) }

    /// Pide al hijo que pare.
    public func signal() { SetEvent(handle) }

    private struct Handle: @unchecked Sendable { let raw: HANDLE }

    /// Hijo: abre el evento `name` y llama a `handler` desde un hilo propio cuando el padre lo señale.
    /// `false` si el evento no existe (el padre no lo creó o ya salió).
    @discardableResult
    public static func watch(name: String, handler: @escaping @Sendable () -> Void) -> Bool {
        guard let h = name.withCString(encodedAs: UTF16.self, { OpenEventW(DWORD(SYNCHRONIZE), false, $0) }) else {
            return false
        }
        let event = Handle(raw: h)
        Thread.detachNewThread {
            if WaitForSingleObject(event.raw, INFINITE) == WAIT_OBJECT_0 { handler() }
            CloseHandle(event.raw)
        }
        return true
    }
}
#endif
