import AudioKit
import Foundation

/// Destino de las líneas de diagnóstico de los paquetes de núcleo para el anfitrión, que solo depende de AppCore (Parte C
/// de la ronda 7c: `audio.take|`, una línea por toma con los huecos de la entrada). Hoy reenvía a `AudioKitLog`.
public enum CoreLog {
    public static func setSink(_ sink: (@Sendable (String) -> Void)?) { AudioKitLog.setSink(sink) }
}
