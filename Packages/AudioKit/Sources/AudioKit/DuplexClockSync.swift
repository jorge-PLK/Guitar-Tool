import Foundation

/// Línea de tiempo común a partir de marcas de host por búfer (plan, «Fase 7c», «Audio»: WASAPI propio con marcas QPC
/// por búfer «para conservar la medida de latencia y el alineado actuales»). Portátil y sin E/S: la E/S WASAPI del
/// paso 7 le pasa las marcas y pone en cada `AudioIOBuffer` lo que devuelve, con el mismo contrato que `CoreAudioIO`
/// (`AudioIO`, `AudioIOBuffer`), así que `LatencyCalibrator`, `TakeRecorder` y `TakeAligner` no cambian.
///
/// - **Salida (maestra).** La línea común es la posición del flujo de render en muestras: el búfer que empieza en el
///   fotograma escrito `k` lleva `sampleTime = k`. `IAudioClock::GetPosition` (posición en unidades de
///   `GetFrequency`, con su QPC) da puntos `(host, fotograma)` → `addRenderClock`.
/// - **Entrada.** Cada paquete de `IAudioCaptureClient::GetBuffer` trae `u64DevicePosition` (fotograma de captura del
///   primer fotograma) y `u64QPCPosition` → `addCapturePacket`. `sampleTime = devicePosition + offset`, con `offset`
///   entero y fijo en la sesión: los bloques de entrada quedan consecutivos (sin huecos ni solapes inventados por el
///   ruido del QPC) y `n − y` es la latencia física más una constante que la calibración absorbe, como en el HAL.
/// - **Precisión.** Las marcas sueltas tiemblan (en WASAPI compartido, centenares de µs). El offset no sale de un
///   paquete sino de dos rectas por mínimos cuadrados (render y captura, `fotograma = a + b·host`) evaluadas en el
///   mismo instante, con `minimumPoints` puntos de cada lado. El temblor de cada marca entra dividido por √N
///   (`DuplexClockSyncTests`: peor caso 0,10 ms en 50 arranques con ±0,5 ms de temblor, frente a 3,3 ms con un solo
///   paquete; el alineado exige 1 ms, `AlignmentCheck`).
/// - **Un solo reloj.** Pensado para entrada y salida del mismo dispositivo (la Flex Prime, `AudioIOClock.single`):
///   las dos pendientes son la misma frecuencia. Con dos dispositivos habría deriva (el agregado del HAL la corrige
///   remuestreando); `driftPPM` la deja a la vista y el paso 7 decide.
public struct DuplexClockSync: Sendable {
    /// Puntos de cada recta antes de fijar el offset (decisión propia: 100 búferes de 10 ms = 1 s de arranque).
    public static let defaultMinimumPoints = 100

    public let sampleRate: Double
    public let minimumPoints: Int
    private var render = LineFit()
    private var capture = LineFit()
    /// Offset fijado (muestras de la línea común menos fotograma de captura); `nil` mientras se calienta.
    public private(set) var captureOffset: Int64?

    public init(sampleRate: Double, minimumPoints: Int = DuplexClockSync.defaultMinimumPoints) {
        self.sampleRate = sampleRate
        self.minimumPoints = max(2, minimumPoints)
    }

    /// Segundos de host de una marca QPC de WASAPI (`u64QPCPosition` viene en unidades de 100 ns, no en tics):
    /// misma escala y origen que `HostClock.nowSeconds` en Windows. 0 = sin marca.
    public static func seconds(qpc100ns: UInt64) -> Double { Double(qpc100ns) / 1e7 }

    /// Lectura de `IAudioClock::GetPosition`: posición en unidades de `frequency` y su instante de host.
    public mutating func addRenderClock(position: UInt64, frequency: UInt64, hostSeconds: Double) {
        guard frequency > 0, hostSeconds > 0 else { return }
        render.add(x: hostSeconds, y: Double(position) * sampleRate / Double(frequency))
        fixOffsetIfReady()
    }

    /// Paquete de captura: `u64DevicePosition` y su instante de host. Devuelve el `sampleTime` en la línea común, o
    /// `nil` mientras no hay offset (la E/S descarta esos paquetes, como el arranque de una sesión).
    public mutating func addCapturePacket(devicePosition: UInt64, hostSeconds: Double) -> Int64? {
        // Sin marca válida (TIMESTAMP_ERROR o QPC 0) la comprobación no se gasta: espera al siguiente paquete con marca.
        if discontinuityPending, hostSeconds > 0 {
            checkAfterDiscontinuity(devicePosition: devicePosition, hostSeconds: hostSeconds)
        }
        if hostSeconds > 0 {
            if refit != nil {
                refit!.add(x: hostSeconds, y: Double(devicePosition))
                finishRefitIfReady()
            } else {
                // Tras fijar el offset la recta sigue afinándose (deriva, `captureHostSeconds`); el offset no se mueve.
                capture.add(x: hostSeconds, y: Double(devicePosition))
                fixOffsetIfReady()
            }
        }
        return captureOffset.map { Int64(devicePosition) + $0 }
    }

    /// `sampleTime` y segundos de host del búfer de salida que empieza en el fotograma escrito `framesWritten`.
    public func renderBuffer(framesWritten: Int64) -> (sampleTime: Int64, hostSeconds: Double) {
        (framesWritten, render.x(atY: Double(framesWritten)) ?? 0)
    }

    /// Segundos de host del primer fotograma de un paquete de captura (sobre la recta, sin el temblor de la marca).
    public func captureHostSeconds(devicePosition: UInt64) -> Double {
        capture.x(atY: Double(devicePosition) + Double(refitShift)) ?? 0
    }

    /// Deriva de la captura frente al render en ppm (0 con un solo reloj); `nil` sin puntos suficientes.
    public var driftPPM: Double? {
        guard let r = render.slope, let c = capture.slope, r > 0 else { return nil }
        return (c / r - 1) * 1e6
    }

    /// Olvida el offset (reinicio del flujo, o discontinuidad antes de fijarlo): se vuelve a estimar con puntos nuevos.
    public mutating func resetCapture() {
        capture = LineFit()
        refit = nil
        refitShift = 0
        captureOffset = nil
    }

    // MARK: Discontinuidad a mitad de flujo (Parte C de la ronda 7c, decisión de Jorge)
    //
    // Antes, `resetCapture` tiraba el audio durante `minimumPoints` paquetes (1 s) hasta volver a fijar el offset, y la
    // toma se rellenaba con ese segundo de ceros (punch real: 1007 ms). Ahora el offset se conserva: el hueco que queda en
    // la línea común es el que dice la posición del dispositivo (el motor la avanza por los fotogramas perdidos), y la
    // recta de captura anterior comprueba con la marca QPC del primer paquete que la traiga válida que esa posición casa
    // con el tiempo. La
    // recta nueva se ajusta en segundo plano y, al tener `minimumPoints` puntos, corrige el offset si se movió más de
    // `realignToleranceSeconds` (un salto de pocas muestras: hacia delante la toma lo rellena con ceros, hacia atrás
    // descarta las repetidas, `TakeRecorder.capture`).

    /// Por debajo de esto un offset re-estimado no se aplica: el temblor de la estimación es ≤ 0,10 ms
    /// (`DuplexClockSyncTests`) y el alineado admite 1 ms (`AlignmentCheck.passThresholdSeconds`); decisión propia: 1/4.
    public static let realignToleranceSeconds = AlignmentCheck.passThresholdSeconds / 4
    /// Desacuerdo mínimo entre posición y marca QPC para no fiarse de la posición tras una discontinuidad (decisión
    /// propia): 1 ms o 6 veces el residuo de la recta anterior (temblor de una marca suelta), lo que sea mayor.
    public static let positionTrustFloorSeconds = 0.001
    static let positionTrustSigmas = 6.0

    /// Recta nueva en curso tras una discontinuidad (posiciones crudas del paquete); `nil` si no hay.
    private var refit: LineFit?
    /// Mientras dura `refit`: fotogramas que se suman a la posición para usar la recta anterior (0 si la posición casó).
    private var refitShift: Int64 = 0
    private var discontinuityPending = false
    /// Correcciones del offset aplicadas tras una discontinuidad (por la marca QPC o por la recta nueva).
    public private(set) var realigns = 0

    /// Discontinuidad de captura a mitad de flujo: conserva el offset y lo comprueba en el siguiente paquete con marca
    /// QPC válida. Sin offset aún, equivale a `resetCapture`.
    public mutating func captureDiscontinuity() {
        guard captureOffset != nil else { resetCapture(); return }
        discontinuityPending = true
    }

    /// Primer paquete con marca válida tras la discontinuidad: si su posición no casa con la recta anterior en su marca
    /// QPC, el hueco sale de la marca (offset += desacuerdo). Empieza la recta nueva.
    ///
    /// Los paquetes sin marca que llegan antes (TIMESTAMP_ERROR, Parte E de la ronda 7c) se entregan con el offset
    /// conservado, sin comprobar (decisión propia): es lo correcto cuando la posición avanza por los fotogramas perdidos
    /// (el caso normal, sin coste), y si la posición mentía el desfase dura solo hasta la siguiente marca válida
    /// (`WASAPIStreamCoreTests`, caso C), no el segundo de la recta nueva. Tirarlos costaría su audio siempre, también
    /// cuando la posición es buena. Con varias discontinuidades seguidas sin marca la comprobación sigue pendiente y la
    /// hace la primera marca válida: la recta anterior y `refitShift` no cambian entre medias y la posición ya incluye
    /// todos los fotogramas perdidos.
    private mutating func checkAfterDiscontinuity(devicePosition: UInt64, hostSeconds: Double) {
        discontinuityPending = false
        let p = Double(devicePosition)
        if let offset = captureOffset, let expected = capture.y(atX: hostSeconds) {
            let delta = expected - (p + Double(refitShift))
            let trust = max(Self.positionTrustFloorSeconds * sampleRate, Self.positionTrustSigmas * (capture.residualRMS ?? 0))
            if abs(delta) > trust {
                let d = Int64(delta.rounded())
                captureOffset = offset + d
                refitShift += d
                realigns += 1
            }
        }
        refit = LineFit()
    }

    private mutating func finishRefitIfReady() {
        guard let fresh = refit, fresh.count >= minimumPoints, render.count >= minimumPoints, let offset = captureOffset,
              let t = fresh.meanX, let r = render.y(atX: t), let c = fresh.y(atX: t) else { return }
        let candidate = Int64((r - c).rounded())
        if Double(abs(candidate - offset)) > Self.realignToleranceSeconds * sampleRate {
            captureOffset = candidate
            realigns += 1
        }
        capture = fresh
        refit = nil
        refitShift = 0
    }

    private mutating func fixOffsetIfReady() {
        guard captureOffset == nil, render.count >= minimumPoints, capture.count >= minimumPoints,
              let t = capture.meanX, let r = render.y(atX: t), let c = capture.y(atX: t) else { return }
        captureOffset = Int64((r - c).rounded())
    }
}

/// Recta `y = a + b·x` por mínimos cuadrados, acumulada (centrada en el primer punto para no perder precisión con
/// segundos de host grandes).
private struct LineFit: Sendable {
    private var x0 = 0.0, y0 = 0.0
    private var n = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, syy = 0.0

    var count: Int { Int(n) }

    mutating func add(x: Double, y: Double) {
        if n == 0 { x0 = x; y0 = y }
        let dx = x - x0, dy = y - y0
        n += 1; sx += dx; sy += dy; sxx += dx * dx; sxy += dx * dy; syy += dy * dy
    }

    /// Residuo cuadrático medio en unidades de `y` (el temblor de una marca suelta); `nil` con menos de 3 puntos.
    var residualRMS: Double? {
        guard n >= 3, let b = slope else { return nil }
        let sse = (syy - sy * sy / n) - b * (sxy - sx * sy / n)
        return (max(0, sse) / (n - 2)).squareRoot()
    }

    var slope: Double? {
        let d = n * sxx - sx * sx
        guard n >= 2, d > 0 else { return nil }
        return (n * sxy - sx * sy) / d
    }

    var meanX: Double? { n > 0 ? x0 + sx / n : nil }

    func y(atX x: Double) -> Double? {
        guard let b = slope else { return nil }
        return y0 + sy / n + b * (x - x0 - sx / n)
    }

    func x(atY y: Double) -> Double? {
        guard let b = slope, b != 0 else { return nil }
        return x0 + sx / n + (y - y0 - sy / n) / b
    }
}
