import Foundation

/// Trazas del vídeo de la toma (ola 3.3.AU): con `TF_TRACE_TAKE=1`, una línea por suceso en stderr con el tiempo (s desde el
/// primer suceso). Apagado cuesta una lectura de booleano.
public enum TakeTrace {
    public static let enabled = ProcessInfo.processInfo.environment["TF_TRACE_TAKE"] == "1"
    private static let t0 = DispatchTime.now().uptimeNanoseconds

    public static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let start = t0  // antes de leer «ahora»: la primera lectura inicializa `t0`
        let t = Double(DispatchTime.now().uptimeNanoseconds &- start) / 1e9
        FileHandle.standardError.write(Data((String(format: "[take %8.3f] ", t) + message() + "\n").utf8))
    }
}
