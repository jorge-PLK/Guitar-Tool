import Foundation

/// Contadores del render alojado (`HostedRenderer`) en la pasada, para `tf-audio verify`.
public struct HostedRenderStats: Sendable, Equatable {
    /// Bloques en los que se recuperó un salto o una deuda renderizando en vacío.
    public var catchUps: Int
    /// Muestras renderizadas y tiradas para recuperar.
    public var catchUpFrames: Int
    /// Muestras que el motor no pudo dar a tiempo (salió silencio y se debieron).
    public var failedPullFrames: Int
    /// Saltos hacia delante del `sampleTime` de salida de la sesión.
    public var outputJumps: Int
    public var outputJumpMaxFrames: Int
    /// Saltos hacia atrás (no deberían ocurrir nunca).
    public var outputBackwardJumps: Int
}

/// Diagnóstico del reproductor alojado en una sesión.
public struct HostedPlaybackDiagnostics: Sendable, Equatable {
    public var render: HostedRenderStats
    /// Muestras dadas como silencio por las `StemFeed` (vacíos de la cola de stems).
    public var feedUnderrunFrames: Int
    /// Retardo que declaró el TimePitch en esta pasada (muestras enteras), el que se sumó al ancla.
    public var timePitchLatencyFrames: Double
    /// Latencia total de los nodos sumada al ancla (TimePitch + Varispeed), en muestras.
    public var anchorLatencyFrames: Double
}

/// Diagnóstico del ciclo de E/S del HAL (`CoreAudioIO`).
public struct AudioIODiagnostics: Sendable, Equatable {
    /// Avisos `kAudioDeviceProcessorOverload` del HAL.
    public var overloads: Int
    /// Saltos del `sampleTime` de entrada (bloque que no empieza donde acabó el anterior) y el mayor, en muestras.
    public var inputJumps: Int
    public var inputJumpMaxFrames: Int
    /// Ídem en la salida.
    public var outputJumps: Int
    public var outputJumpMaxFrames: Int
    /// Mínimo y máximo de `sampleTime` de salida − `sampleTime` de entrada en el mismo ciclo. Si cambian durante
    /// la sesión, la entrada y la salida dejaron de ir juntas y el ancla ya no vale para la entrada.
    public var outMinusInMin: Int?
    public var outMinusInMax: Int?
    public var callbacks: Int
    /// Solo WASAPI (0 en el HAL): discontinuidades de captura tras el primer paquete, fotogramas de captura tirados
    /// mientras no había offset y correcciones del offset tras una discontinuidad (`DuplexClockSync`).
    public var captureResets = 0
    public var droppedCaptureFrames = 0
    public var captureRealigns = 0
}

// MARK: Marcas de host (diagnóstico de los saltos de 12 muestras de la Flex Prime, 15/11/2026)

/// Marcas de un ciclo de E/S del HAL: `sampleTime` y hora de host (en segundos de `mach_absolute_time`) de
/// entrada y de salida, y su `mRateScalar`. Hora 0 = el HAL no la dio válida.
public struct HostTimingCycle: Sendable, Equatable {
    public var inputSampleTime: Double
    public var outputSampleTime: Double
    public var inputHostSeconds: Double
    public var outputHostSeconds: Double
    public var inputRateScalar: Double
    public var outputRateScalar: Double

    public init(inputSampleTime: Double, outputSampleTime: Double, inputHostSeconds: Double, outputHostSeconds: Double,
                inputRateScalar: Double = 1, outputRateScalar: Double = 1) {
        self.inputSampleTime = inputSampleTime
        self.outputSampleTime = outputSampleTime
        self.inputHostSeconds = inputHostSeconds
        self.outputHostSeconds = outputHostSeconds
        self.inputRateScalar = inputRateScalar
        self.outputRateScalar = outputRateScalar
    }
}

/// Latencias que declaran el dispositivo y sus streams en un instante (consultadas fuera del hilo de E/S), en
/// muestras.
public struct DeclaredLatencySnapshot: Sendable, Equatable {
    public var hostSeconds: Double
    public var inputDevice: Int
    public var inputSafety: Int
    public var inputStream: Int
    public var outputDevice: Int
    public var outputSafety: Int
    public var outputStream: Int

    public init(hostSeconds: Double, inputDevice: Int, inputSafety: Int, inputStream: Int, outputDevice: Int,
                outputSafety: Int, outputStream: Int) {
        self.hostSeconds = hostSeconds
        self.inputDevice = inputDevice
        self.inputSafety = inputSafety
        self.inputStream = inputStream
        self.outputDevice = outputDevice
        self.outputSafety = outputSafety
        self.outputStream = outputStream
    }

    public var total: Int { inputDevice + inputSafety + inputStream + outputDevice + outputSafety + outputStream }
}

/// Resumen de un segundo de marcas.
public struct HostTimingSecond: Sendable, Equatable {
    /// Inicio del segundo en hora de host.
    public var hostSeconds: Double
    /// Media de (hora de host de salida − hora de host de entrada) pasada a muestras (con el `rateScalar`).
    public var hostOutMinusInSamples: Double
    /// Media de `sampleTime` de salida − `sampleTime` de entrada (con la Flex Prime, 1112 constante).
    public var sampleOutMinusIn: Double
    /// Hora de host frente a `sampleTime`, en muestras y respecto al primer ciclo (la deriva entre el reloj del
    /// Mac y el del aparato sale como pendiente; un reanclaje del HAL, como escalón). Mediana del segundo.
    public var inputHostResidualSamples: Double
    public var outputHostResidualSamples: Double
    public var inputRateScalar: Double
    public var outputRateScalar: Double
    /// Última consulta de latencias declaradas antes del final del segundo.
    public var latencies: DeclaredLatencySnapshot?
}

/// Cambio de nivel en una serie de marcas.
public struct HostTimingStep: Sendable, Equatable {
    public enum Series: String, Sendable {
        case hostOutMinusIn = "host salida − entrada"
        case inputResidual = "host − sampleTime de entrada"
        case outputResidual = "host − sampleTime de salida"
        case declaredLatency = "latencia declarada"
    }
    public var series: Series
    /// Hora de host del primer segundo con el nivel nuevo.
    public var hostSeconds: Double
    public var sizeSamples: Double
}

public struct HostTimingReport: Sendable, Equatable {
    public var cycles: Int
    public var seconds: [HostTimingSecond]
    public var steps: [HostTimingStep]
}

/// Agrupa las marcas por segundo y busca escalones (pura: se prueba con marcas sintéticas).
public enum HostTimingAnalysis {
    /// Cambio de nivel mínimo que se cuenta, en muestras (encargo del diagnóstico: «≥ 3 muestras»; el salto
    /// observado es de 12).
    public static let stepThresholdSamples = 3.0
    /// Diferencia entre segundos consecutivos (quitada la deriva) a partir de la cual un segundo puede ser parte de
    /// un escalón repartido entre dos segundos.
    static let candidateSamples = 1.0

    public static func analyze(cycles: [HostTimingCycle], latencies: [DeclaredLatencySnapshot],
                               sampleRate fs: Double) -> HostTimingReport {
        let valid = cycles.filter { $0.inputHostSeconds > 0 && $0.outputHostSeconds > 0 }
        guard let first = valid.first else { return HostTimingReport(cycles: cycles.count, seconds: [], steps: []) }
        let t0 = first.inputHostSeconds
        var buckets: [Int: [HostTimingCycle]] = [:]
        for c in valid { buckets[Int(((c.inputHostSeconds - t0)).rounded(.down)), default: []].append(c) }
        let lats = latencies.sorted { $0.hostSeconds < $1.hostSeconds }
        var rows: [HostTimingSecond] = []
        // La diferencia de host se busca en su mediana del segundo, para que un ciclo raro no cuente.
        var skew: [Double] = []
        for k in buckets.keys.sorted() {
            let cs = buckets[k]!
            func mean(_ f: (HostTimingCycle) -> Double) -> Double { cs.reduce(0) { $0 + f($1) } / Double(cs.count) }
            func median(_ f: (HostTimingCycle) -> Double) -> Double {
                let v = cs.map(f).sorted()
                return v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
            }
            let start = t0 + Double(k)
            skew.append(median { ($0.outputHostSeconds - $0.inputHostSeconds) * fs / rate($0) })
            rows.append(HostTimingSecond(
                hostSeconds: start,
                hostOutMinusInSamples: mean { ($0.outputHostSeconds - $0.inputHostSeconds) * fs / rate($0) },
                sampleOutMinusIn: mean { $0.outputSampleTime - $0.inputSampleTime },
                inputHostResidualSamples: median { ($0.inputHostSeconds - t0) * fs - ($0.inputSampleTime - first.inputSampleTime) },
                outputHostResidualSamples: median {
                    ($0.outputHostSeconds - first.outputHostSeconds) * fs - ($0.outputSampleTime - first.outputSampleTime)
                },
                inputRateScalar: mean(\.inputRateScalar), outputRateScalar: mean(\.outputRateScalar),
                latencies: lats.last { $0.hostSeconds < start + 1 }))
        }
        var steps: [HostTimingStep] = []
        let t = rows.map(\.hostSeconds)
        steps += levelSteps(skew, t).map { HostTimingStep(series: .hostOutMinusIn, hostSeconds: $0.0, sizeSamples: $0.1) }
        steps += levelSteps(rows.map(\.inputHostResidualSamples), t)
            .map { HostTimingStep(series: .inputResidual, hostSeconds: $0.0, sizeSamples: $0.1) }
        steps += levelSteps(rows.map(\.outputHostResidualSamples), t)
            .map { HostTimingStep(series: .outputResidual, hostSeconds: $0.0, sizeSamples: $0.1) }
        for (a, b) in zip(lats, lats.dropFirst()) where a.total != b.total {
            steps.append(HostTimingStep(series: .declaredLatency, hostSeconds: b.hostSeconds, sizeSamples: Double(b.total - a.total)))
        }
        steps.sort { $0.hostSeconds < $1.hostSeconds }
        return HostTimingReport(cycles: cycles.count, seconds: rows, steps: steps)
    }

    private static func rate(_ c: HostTimingCycle) -> Double {
        let r = (c.inputRateScalar + c.outputRateScalar) / 2
        return r > 0 ? r : 1
    }

    /// Escalones en una serie por segundo: diferencias consecutivas menos la deriva (su mediana); las seguidas que
    /// pasan de `candidateSamples` se suman (un escalón a mitad de segundo puede repartirse en dos) y cuenta si el
    /// total llega a `stepThresholdSamples`. Devuelve (instante del primer segundo con el nivel nuevo, tamaño).
    static func levelSteps(_ m: [Double], _ t: [Double]) -> [(Double, Double)] {
        guard m.count >= 3 else { return [] }
        let d = zip(m.dropFirst(), m).map { $0 - $1 }
        let sorted = d.sorted()
        let drift = sorted[sorted.count / 2]
        var out: [(Double, Double)] = []
        var i = 0
        while i < d.count {
            guard abs(d[i] - drift) >= candidateSamples else { i += 1; continue }
            var sum = 0.0, j = i
            while j < d.count, abs(d[j] - drift) >= candidateSamples {
                sum += d[j] - drift
                j += 1
            }
            if abs(sum) >= stepThresholdSamples {
                // Tamaño entre los segundos vecinos, que no comparten ciclos con el escalón (el segundo que lo
                // contiene tiene la mediana algo corrida hacia el nivel nuevo).
                let a = max(0, i - 1), b = min(m.count - 1, j + 1)
                out.append((t[i + 1], m[b] - m[a] - drift * Double(b - a)))
            }
            i = j
        }
        return out
    }
}
