import Foundation

/// Marcas de Media Foundation → ticks de QPC (plan, «Fase 7c», paso 7, parte 7.2). Las muestras de una cámara llevan
/// `MFSampleExtension_DeviceTimestamp` y `MFGetSystemTime` da la hora: las dos son QPC en unidades de 100 ns
/// (`ticks · 10⁷ / frecuencia`). Para la escala de `HostClock` hay que volver a ticks (`100 ns · frecuencia / 10⁷`)
/// antes de `HostClock.seconds(ticks:)`. Puro: se prueba en el Mac y en Windows.
enum QPCTime {
    static let hundredNanosecondsPerSecond: UInt64 = 10_000_000

    /// Ticks de QPC de una marca en 100 ns, redondeados al más cercano, con aritmética de 128 bits (sin desbordar con
    /// meses de encendido ni con frecuencias de GHz). Negativo → 0.
    static func ticks(hundredNanoseconds t: Int64, frequency: UInt64) -> UInt64 {
        guard t > 0, frequency > 0 else { return 0 }
        let wide = UInt64(t).multipliedFullWidth(by: frequency)
        let (q, r) = hundredNanosecondsPerSecond.dividingFullWidth((wide.high, wide.low))
        return r >= hundredNanosecondsPerSecond / 2 ? q + 1 : q
    }

    /// Frecuencia de QPC a partir de la base de `HostClock` (nanosegundos por tick = 10⁹ / frecuencia; exacta para
    /// frecuencias enteras de hasta 10¹⁰ Hz).
    static func frequency(timebase: Double) -> UInt64 { UInt64((1e9 / timebase).rounded()) }
}
