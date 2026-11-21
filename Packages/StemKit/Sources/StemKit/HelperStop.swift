#if os(Windows)
import Foundation
import NativeONNX
import NativePlatform

/// Parada ordenada de `tf-separate` en Windows (plan, «Corte del paso 7», parte 7.8). `SeparationRunner` crea un
/// evento con nombre y lo pasa en `TF_STOP_EVENT`; al cancelar lo señala y espera `terminateGrace` antes de
/// `TerminateJobObject`. El helper vigila el evento: levanta su bandera de cancelación (la consulta antes de cada
/// trozo) y corta la inferencia en curso (un trozo de separación tarda 10-25 s en CPU, más que el margen), así el
/// separador sale por su camino de error y borra su carpeta `.tf-separate-*`.
public enum HelperStop {
    /// Helper: empieza a vigilar el evento del padre, si lo hay. `onStop` se llama desde otro hilo.
    @discardableResult
    public static func watchParent(environment: [String: String] = ProcessInfo.processInfo.environment,
                                   onStop: @escaping @Sendable () -> Void) -> Bool {
        guard let name = environment[StopEvent.environmentKey] else { return false }
        return StopEvent.watch(name: name) {
            onStop()
            OnnxSession.terminateAll()
        }
    }

    /// Padre: evento nuevo con nombre único para un helper.
    static func makeEvent() -> StopEvent? {
        StopEvent(name: "Local\\ToneForge-tf-separate-\(UUID().uuidString)")
    }
}
#endif
