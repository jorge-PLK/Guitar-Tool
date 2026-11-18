import Foundation
import Observation

/// Una sola pasada viva a la vez (Fase 7b, punto 3: «Importar» del popup). Mientras hay una en curso `start` se
/// niega a lanzar otra, y una pasada cancelada deja de ser «la actual»: su cuerpo debe consultar `isCurrent`
/// tras cada `await` y no escribir estado si devuelve false.
@MainActor @Observable
public final class PassGate {
    public private(set) var isRunning = false
    private var task: Task<Void, Never>?
    private var generation = 0

    public init() {}

    /// Lanza `body` si no hay otra pasada en curso. Devuelve false (sin hacer nada) si la hay.
    /// `isCurrent` es false en cuanto la pasada se cancela o se desplaza.
    @discardableResult
    public func start(_ body: @escaping @MainActor (_ isCurrent: @MainActor () -> Bool) async -> Void) -> Bool {
        guard !isRunning else { return false }
        generation += 1
        let mine = generation
        isRunning = true
        task = Task { [weak self] in
            await body { [weak self] in
                guard let self else { return false }
                return self.generation == mine && !Task.isCancelled
            }
            guard let self, self.generation == mine else { return }
            self.isRunning = false
            self.task = nil
        }
        return true
    }

    /// Cancela de verdad la pasada en curso y libera la puerta al instante.
    public func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isRunning = false
    }
}
