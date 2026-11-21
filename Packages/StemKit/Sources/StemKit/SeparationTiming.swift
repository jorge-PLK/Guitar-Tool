import Foundation
import NativePlatform

/// Desglose de tiempos de `tf-separate` por etapa (Fase 7c, arreglo F3: «Pendiente tras el paso 7», docs/plan.md).
/// Solo con `TF_SEPARATE_TIMING=1`; apagado, cada punto de medida es una lectura de `isEnabled` y la salida no cambia.
///
/// Los tiempos son **exclusivos**: una medida anidada (la escritura dentro del solape, la escritura dentro del
/// remuestreo de salida) se resta de la que la contiene, así que la suma de etapas nunca pasa del total de reloj y
/// «resto» (total − suma) es lo que queda sin medir. Todas las medidas se toman desde el hilo que separa; las etapas
/// paralelas (`concurrentPerform` por stem) se miden por fuera, en tiempo de pared.
public enum SeparationTiming {
    public static let environmentKey = "TF_SEPARATE_TIMING"

    /// Se lee una vez del entorno. Los tests lo cambian con `setEnabledForTesting`.
    nonisolated(unsafe) public private(set) static var isEnabled =
        ProcessInfo.processInfo.environment[environmentKey] == "1"

    enum Kind { case once, perChunk }

    enum Stage: Int, CaseIterable {
        case load, decode, resampleIn, chunking, stft, prepareInput, runFirst, run, readOutput, applyMask, istft,
             overlapAdd, write, resampleOut, finalize

        /// Etiquetas ASCII sin tildes (la consola de Windows no garantiza UTF-8).
        var label: String {
            switch self {
            case .load: "cargar modelo / crear sesion"
            case .decode: "decodificar entrada"
            case .resampleIn: "remuestreo entrada"
            case .chunking: "relleno y troceo"
            case .stft: "STFT"
            case .prepareInput: "preparar tensores entrada"
            case .runFirst: "Run modelo (1er trozo)"
            case .run: "Run modelo (regimen)"
            case .readOutput: "leer salida -> mascara"
            case .applyMask: "aplicar mascara"
            case .istft: "ISTFT"
            case .overlapAdd: "solape y suma"
            case .write: "escritura stems"
            case .resampleOut: "remuestreo salida"
            case .finalize: "mover stems a destino"
            }
        }

        var kind: Kind {
            switch self {
            case .load, .decode, .resampleIn, .runFirst, .resampleOut, .finalize: .once
            default: .perChunk
            }
        }
    }

    /// Acumulado de una etapa: tiempo exclusivo en ticks de `HostClock` y llamadas contadas.
    struct Entry: Equatable {
        var ticks: UInt64 = 0
        var count = 0
    }

    private struct State {
        var start: UInt64?
        var entries = [Entry](repeating: Entry(), count: Stage.allCases.count)
        /// Ticks de las medidas hijas de cada medida abierta (para el tiempo exclusivo).
        var childTicks: [UInt64] = []
        var engine: String?
    }

    nonisolated(unsafe) private static var state = State()
    private static let lock = NSLock()

    // MARK: API de tf-separate

    /// Marca el inicio del total de reloj (antes de cargar el modelo).
    public static func start() {
        guard isEnabled else { return }
        lock.withLock { state = State(); state.start = HostClock.now() }
    }

    /// Carga del modelo (Core ML) o creación de la sesión (ONNX Runtime, con la elección de proveedor).
    public static func measureModelLoad<R>(_ body: () throws -> R) rethrows -> R {
        try measure(.load, body)
    }

    /// Escribe la tabla en stderr. Sin `start()` previo no hace nada.
    public static func printReport() {
        guard isEnabled, let report = snapshot(end: HostClock.now()) else { return }
        // `write(contentsOf:)` lanza en vez de abortar: en Windows un proceso GUI no tiene stderr.
        try? FileHandle.standardError.write(contentsOf: Data(report.render().utf8))
    }

    // MARK: Puntos de medida

    @inline(__always)
    static func measure<R>(_ stage: Stage, counted: Bool = true, _ body: () throws -> R) rethrows -> R {
        guard isEnabled else { return try body() }
        return try measured(stage, counted: counted, body)
    }

    /// El `Run` del modelo: la primera llamada va a `.runFirst` (calentamiento) y las demás a `.run`.
    @inline(__always)
    static func measureRun<R>(_ body: () throws -> R) rethrows -> R {
        guard isEnabled else { return try body() }
        let first = lock.withLock { state.entries[Stage.runFirst.rawValue].count == 0 }
        return try measured(first ? .runFirst : .run, counted: true, body)
    }

    /// Descripción del motor (proveedor y opciones de sesión), para la cabecera.
    static func setEngine(_ text: @autoclosure () -> String) {
        guard isEnabled else { return }
        let value = text()
        lock.withLock { state.engine = value }
    }

    private static func measured<R>(_ stage: Stage, counted: Bool, _ body: () throws -> R) rethrows -> R {
        lock.withLock { state.childTicks.append(0) }
        let t0 = HostClock.now()
        defer {
            let elapsed = HostClock.now() &- t0
            lock.withLock {
                let children = state.childTicks.removeLast()
                state.entries[stage.rawValue].ticks &+= elapsed > children ? elapsed - children : 0
                if counted { state.entries[stage.rawValue].count += 1 }
                if !state.childTicks.isEmpty { state.childTicks[state.childTicks.count - 1] &+= elapsed }
            }
        }
        return try body()
    }

    // MARK: Informe

    static func snapshot(end: UInt64) -> Report? {
        lock.withLock {
            guard let start = state.start else { return nil }
            return Report(totalSeconds: HostClock.seconds(ticks: end &- start),
                          seconds: state.entries.map { HostClock.seconds(ticks: $0.ticks) },
                          counts: state.entries.map(\.count), engine: state.engine,
                          processors: ProcessInfo.processInfo.activeProcessorCount)
        }
    }

    static func setEnabledForTesting(_ on: Bool) {
        lock.withLock { isEnabled = on; state = State() }
    }

    struct Report {
        let totalSeconds: Double
        /// Por `Stage.rawValue`.
        let seconds: [Double]
        let counts: [Int]
        let engine: String?
        let processors: Int

        /// Trozos = llamadas al modelo.
        var chunks: Int { counts[Stage.runFirst.rawValue] + counts[Stage.run.rawValue] }
        var measuredSeconds: Double { seconds.reduce(0, +) }
        var restSeconds: Double { totalSeconds - measuredSeconds }

        /// Media por trozo en ms: las etapas por trozo entre sus llamadas contadas; `.runFirst` es una sola llamada;
        /// las de una vez y «resto» se reparten entre los trozos (coste amortizado).
        func meanMilliseconds(_ stage: Stage) -> Double? {
            let s = seconds[stage.rawValue], n = counts[stage.rawValue]
            switch stage.kind {
            case .perChunk: return n > 0 ? 1000 * s / Double(n) : nil
            case .once:
                if stage == .runFirst { return n > 0 ? 1000 * s / Double(n) : nil }
                return chunks > 0 ? 1000 * s / Double(chunks) : nil
            }
        }

        func render() -> String {
            let pct: (Double) -> String = { totalSeconds > 0 ? String(format: "%6.1f", 100 * $0 / totalSeconds) : "     -" }
            let ms: (Double?) -> String = { $0.map { String(format: "%11.1f", $0) } ?? String(repeating: " ", count: 10) + "-" }
            func pad(_ s: String, _ w: Int) -> String { s.count >= w ? s : s + String(repeating: " ", count: w - s.count) }
            let rule = String(repeating: "-", count: 74)
            var lines = ["", "tf-separate TF_SEPARATE_TIMING: \(chunks) trozos, \(processors) CPU logicas",
                         "motor: \(engine ?? "?")", rule,
                         pad("etapa", 30) + "      n     total s  ms/trozo      %", rule]
            for stage in Stage.allCases {
                let n = counts[stage.rawValue], s = seconds[stage.rawValue]
                lines.append(pad(stage.label, 30) + String(format: "%7d %11.3f", n, s) + ms(meanMilliseconds(stage))
                             + " " + pct(s))
            }
            let blankN = String(repeating: " ", count: 7)
            let restMean = chunks > 0 ? 1000 * restSeconds / Double(chunks) : nil
            lines.append(pad("resto (total - suma)", 30) + blankN + String(format: " %11.3f", restSeconds) + ms(restMean)
                         + " " + pct(restSeconds))
            lines.append(rule)
            let totalMean = chunks > 0 ? 1000 * totalSeconds / Double(chunks) : nil
            lines.append(pad("total de reloj", 30) + blankN + String(format: " %11.3f", totalSeconds) + ms(totalMean)
                         + " " + pct(totalSeconds))
            lines.append("ms/trozo: etapas de una vez y resto, amortizadas entre los trozos; tiempos exclusivos.")
            return lines.joined(separator: "\n") + "\n"
        }
    }
}
