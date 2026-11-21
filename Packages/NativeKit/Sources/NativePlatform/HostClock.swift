#if canImport(Darwin)
import Darwin
#elseif os(Windows)
import WinSDK
#endif

/// Reloj de host: `mach_absolute_time` en el Mac y `QueryPerformanceCounter` en Windows (plan, «Fase 7c»,
/// paso 6: reloj QPC en vez de `mach_absolute_time`, con la misma unidad). Los ticks son los del sistema;
/// la conversión a segundos es la misma cuenta que usan hoy AudioKit (`HostTimeLog.seconds`) y VideoKit
/// (`HostClock.seconds(ticks:)`): `Double(ticks) · base / 10⁹`, con base = nanosegundos por tick.
public enum HostClock {
    /// Nanosegundos por tick = `numer / denom`.
    static let ratio: (numer: UInt64, denom: UInt64) = {
        #if canImport(Darwin)
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return (UInt64(tb.numer), UInt64(max(1, tb.denom)))
        #elseif os(Windows)
        var f = LARGE_INTEGER()
        QueryPerformanceFrequency(&f)
        return (1_000_000_000, UInt64(max(1, f.QuadPart)))
        #else
        return (1, 1)
        #endif
    }()

    /// Nanosegundos por tick, en Double (la «base de tiempos» de AudioKit y VideoKit).
    public static let timebase: Double = Double(ratio.numer) / Double(ratio.denom)

    /// Ticks de ahora.
    @inline(__always)
    public static func now() -> UInt64 {
        #if canImport(Darwin)
        return mach_absolute_time()
        #elseif os(Windows)
        var c = LARGE_INTEGER()
        QueryPerformanceCounter(&c)
        return UInt64(c.QuadPart)
        #else
        return 0
        #endif
    }

    /// Segundos de host de unos ticks.
    public static func seconds(ticks: UInt64) -> Double { Double(ticks) * timebase / 1e9 }

    /// Ticks de unos segundos de host (redondeado).
    public static func ticks(seconds: Double) -> UInt64 { UInt64((seconds * 1e9 / timebase).rounded()) }

    /// Nanosegundos exactos de unos ticks (aritmética entera de 128 bits, truncada).
    public static func nanoseconds(ticks: UInt64) -> UInt64 {
        let wide = ticks.multipliedFullWidth(by: ratio.numer)
        return ratio.denom.dividingFullWidth((wide.high, wide.low)).quotient
    }

    /// Hora de host ahora, en segundos.
    public static var nowSeconds: Double { seconds(ticks: now()) }
}
