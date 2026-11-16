import CoreMedia
import Darwin
import Foundation

/// Reloj de host en segundos (mini-spec Fase 6, «Cámara y sincronía»): la escala común de cámara y audio.
///
/// Segundos = ticks de `mach_absolute_time` × base de tiempos / 10⁹: la misma cuenta que AudioKit usa para
/// `AudioIOBuffer.hostSeconds` (`HostTimeLog.seconds`). Las marcas de la cámara llegan como `CMTime` del reloj
/// de host de CoreMedia (`CMClockGetHostTimeClock`), que se pasan a ticks con
/// `CMClockConvertHostTimeToSystemUnits` y de ahí a segundos con la misma fórmula, de modo que las dos marcas
/// son comparables sin suponer nada sobre la escala del `CMTime`.
public enum HostClock {
    static let timebase: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(max(1, tb.denom))
    }()

    /// Segundos de host de `ticks` de `mach_absolute_time`.
    public static func seconds(ticks: UInt64) -> Double { Double(ticks) * timebase / 1e9 }

    /// Ticks de `mach_absolute_time` de unos segundos de host (redondeado).
    public static func ticks(seconds: Double) -> UInt64 { UInt64((seconds * 1e9 / timebase).rounded()) }

    /// Segundos de host de un `CMTime` del reloj de host de CoreMedia.
    public static func seconds(hostTime: CMTime) -> Double { seconds(ticks: CMClockConvertHostTimeToSystemUnits(hostTime)) }

    /// `CMTime` del reloj de host de CoreMedia de unos segundos de host.
    public static func hostTime(seconds s: Double) -> CMTime { CMClockMakeHostTimeFromSystemUnits(ticks(seconds: s)) }

    /// Hora de host ahora.
    public static var nowSeconds: Double { seconds(ticks: mach_absolute_time()) }
}

/// Host ↔ tiempo del tema (mini-spec Fase 6, «Cámara y sincronía»).
///
/// Dos relaciones:
/// - **Reloj del audio**: qué instante de host corresponde a cada muestra de salida de la sesión. Se ajusta una
///   recta por mínimos cuadrados (Welford, estable con muchas muestras) a las marcas `(muestra, host)` de cada
///   ciclo (`AudioSession.outputHostClock` en AudioKit). La pendiente absorbe la deriva del dispositivo frente
///   al host (o la del maestro del agregado con dos dispositivos) y el ajuste promedia el ruido de las marcas.
///   Con una sola marca se usa la frecuencia nominal.
/// - **Anclas del reproductor** (`PlaybackAnchor` de AudioKit con tipos propios): qué posición del tema suena en
///   qué muestra de salida. Un seek o una pasada nueva añaden un ancla; cada una manda desde su muestra.
///
/// No se compensa la latencia de salida del dispositivo (del búfer del HAL al altavoz) ni el retardo propio de la
/// cámara: son constantes para un mismo equipo y cámara y los absorbe el desfase manual (`videoOffset`).
public struct HostTimeMap: Sendable, Equatable {
    /// Ancla del reproductor: la posición del tema `songTime` (s) suena en la muestra de salida `outputSample`.
    public struct Anchor: Sendable, Equatable {
        public var songTime: Double
        public var outputSample: Double
        public var sampleRate: Double
        public var rate: Double

        public init(songTime: Double, outputSample: Double, sampleRate: Double, rate: Double = 1) {
            self.songTime = songTime
            self.outputSample = outputSample
            self.sampleRate = sampleRate
            self.rate = rate
        }

        public func songTime(atOutputSample y: Double) -> Double { songTime + (y - outputSample) * rate / sampleRate }
        public func outputSample(atSongTime t: Double) -> Double { outputSample + (t - songTime) * sampleRate / rate }
    }

    /// Frecuencia nominal de la sesión (la pendiente por defecto).
    public let sampleRate: Double
    /// Anclas por orden de muestra de salida.
    public private(set) var anchors: [Anchor] = []

    // Ajuste de host = a + b·muestra (Welford) sobre valores relativos a la primera marca (con la hora de host
    // absoluta, ~10⁵ s, el redondeo de la media sesgaba la pendiente en 5·10⁻¹⁰): medias, co-momentos y número.
    private var refSample = 0.0
    private var refHost = 0.0
    private var count = 0
    private var meanSample = 0.0
    private var meanHost = 0.0
    private var cSS = 0.0
    private var cSH = 0.0

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    /// Marcas de reloj usadas en el ajuste.
    public var clockPointCount: Int { count }

    /// Añade una marca del reloj del audio: la muestra de salida `outputSample` salió en `hostSeconds`.
    public mutating func addClockPoint(outputSample: Double, hostSeconds: Double) {
        guard hostSeconds > 0, outputSample.isFinite else { return }
        if count == 0 {
            refSample = outputSample
            refHost = hostSeconds
        }
        let s = outputSample - refSample, h = hostSeconds - refHost
        count += 1
        let dS = s - meanSample
        meanSample += dS / Double(count)
        let dH = h - meanHost
        meanHost += dH / Double(count)
        cSS += dS * (s - meanSample)
        cSH += dS * (h - meanHost)
    }

    /// Pone el ancla de una pasada. Las que empezaban en o tras su muestra se descartan (ya no sonarán).
    public mutating func setAnchor(_ anchor: Anchor) {
        if anchors.last == anchor { return }
        anchors.removeAll { $0.outputSample >= anchor.outputSample }
        anchors.append(anchor)
    }

    /// Segundos de host por muestra de salida (la pendiente ajustada; la nominal con menos de dos marcas).
    public var secondsPerSample: Double {
        count >= 2 && cSS > 0 ? cSH / cSS : 1 / sampleRate
    }

    /// Deriva del reloj del audio frente al de host, en ppm (positivo: el audio da más muestras por segundo de
    /// host que su frecuencia nominal). `nil` con menos de dos marcas.
    public var audioClockPPM: Double? {
        guard count >= 2, cSS > 0 else { return nil }
        return (1 / (secondsPerSample * sampleRate) - 1) * 1e6
    }

    /// Instante de host de la muestra de salida `y`. `nil` sin marcas.
    public func hostSeconds(atOutputSample y: Double) -> Double? {
        guard count > 0 else { return nil }
        return refHost + (meanHost + ((y - refSample) - meanSample) * secondsPerSample)
    }

    /// Muestra de salida que sale en el instante de host `h`. `nil` sin marcas.
    public func outputSample(atHostSeconds h: Double) -> Double? {
        guard count > 0 else { return nil }
        return refSample + (meanSample + ((h - refHost) - meanHost) / secondsPerSample)
    }

    /// Índice del ancla que manda en la muestra de salida `y` (la última que empieza en o antes de ella).
    public func anchorIndex(atOutputSample y: Double) -> Int? {
        anchors.lastIndex { $0.outputSample <= y }
    }

    /// Tiempo del tema que suena en el instante de host `h`. `nil` sin marcas, sin ancla o antes de la primera.
    public func songTime(atHostSeconds h: Double) -> Double? { songPosition(atHostSeconds: h)?.songTime }

    /// Tiempo del tema en `h` y el índice del ancla (la pasada) que manda allí.
    public func songPosition(atHostSeconds h: Double) -> (songTime: Double, anchorIndex: Int)? {
        guard let y = outputSample(atHostSeconds: h), let i = anchorIndex(atOutputSample: y) else { return nil }
        return (anchors[i].songTime(atOutputSample: y), i)
    }

    /// Instante de host en que la pasada `anchorIndex` toca el tiempo del tema `t` (sin mirar dónde acaba).
    public func hostSeconds(atSongTime t: Double, anchorIndex i: Int) -> Double? {
        guard anchors.indices.contains(i) else { return nil }
        return hostSeconds(atOutputSample: anchors[i].outputSample(atSongTime: t))
    }

    /// Instante de host en que suena el tiempo del tema `t`. Si `t` suena en varias pasadas (un seek hacia atrás,
    /// o la última pasada, que no tiene fin conocido, llegará a él), devuelve el de la más reciente. `nil` si no
    /// suena en ninguna. Para volver exactamente a un instante, `songPosition` + `hostSeconds(atSongTime:anchorIndex:)`.
    public func hostSeconds(atSongTime t: Double) -> Double? {
        for i in anchors.indices.reversed() {
            let a = anchors[i]
            guard t >= a.songTime else { continue }
            let y = a.outputSample(atSongTime: t)
            if i + 1 < anchors.count, y >= anchors[i + 1].outputSample { continue }
            return hostSeconds(atOutputSample: y)
        }
        return nil
    }
}
