#if os(Windows)
import Foundation

/// Tiempo por fase de la exportación de montaje en Windows, para medir cuellos de botella. Solo cuenta con la variable de
/// entorno `TF_EXPORT_PROFILE` (cualquier valor); sin ella `measure` ejecuta el cuerpo sin tocar el reloj. Los tiempos son
/// de reloj de pared sumados entre hilos (con trabajo en paralelo la suma supera la duración real).
enum ExportProfile {
    enum Phase: Int, CaseIterable {
        case decode, copy, toBGRA, rotate, compose, toNV12, encode
        var label: String {
            switch self {
            case .decode: "decodificar (MF ReadSample)"
            case .copy: "copiar NV12"
            case .toBGRA: "NV12 a BGRA"
            case .rotate: "girar"
            case .compose: "componer (Direct2D)"
            case .toNV12: "BGRA a NV12"
            case .encode: "codificar (WriteSample)"
            }
        }
    }

    static let enabled = ProcessInfo.processInfo.environment["TF_EXPORT_PROFILE"] != nil
    private static let lock = NSLock()
    private nonisolated(unsafe) static var nanos = [UInt64](repeating: 0, count: Phase.allCases.count)
    private nonisolated(unsafe) static var counts = [Int](repeating: 0, count: Phase.allCases.count)

    @inline(__always)
    static func measure<T>(_ phase: Phase, _ body: () throws -> T) rethrows -> T {
        guard enabled else { return try body() }
        let t0 = DispatchTime.now().uptimeNanoseconds
        defer { add(phase, DispatchTime.now().uptimeNanoseconds &- t0) }
        return try body()
    }

    static func add(_ phase: Phase, _ ns: UInt64) {
        lock.withLock { nanos[phase.rawValue] += ns; counts[phase.rawValue] += 1 }
    }

    static func reset() {
        lock.withLock {
            for i in nanos.indices { nanos[i] = 0; counts[i] = 0 }
        }
    }

    /// Tabla de texto: fase, llamadas, total (s) y ms por llamada.
    static func report() -> String {
        lock.withLock {
            Phase.allCases.map { p in
                let n = counts[p.rawValue], s = Double(nanos[p.rawValue]) / 1e9
                return "PROFILE \(p.label): \(n) llamadas, \(String(format: "%.2f", s)) s, \(String(format: "%.2f", n > 0 ? s * 1000 / Double(n) : 0)) ms/llamada"
            }.joined(separator: "\n")
        }
    }
}
#endif
