#if os(Windows)
import Foundation
import NativePlatform

/// `AudioIO` sobre WASAPI propio (plan, «Fase 7c», «Audio»: dúplex por eventos, IAudioClient3 o exclusivo).
/// **Paso 7: wasapi.** Hoy solo la costura: `init` lanza `PlatformError.unsupported`.
///
/// Contrato que tendrá que cumplir (el mismo que `CoreAudioIO`, para no tocar calibración ni alineado):
/// - Render y captura por eventos en un hilo MMCSS «Pro Audio»; los manejadores reciben `AudioIOBuffer` no
///   entrelazados (la E/S desentrelaza), sin reservar memoria.
/// - `sampleTime` y `hostSeconds` de cada búfer salen de `DuplexClockSync`: render con `IAudioClock::GetPosition`
///   (+ su QPC) y el contador de fotogramas escritos; captura con `u64DevicePosition`/`u64QPCPosition` de
///   `GetBuffer` (`DuplexClockSync.seconds(qpc100ns:)`). Un paquete con `AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY`
///   → `resetCapture()` y se cuenta en `diagnostics.inputJumps`.
/// - `declaredLatencySamples`: la latencia de flujo declarada (`IAudioClient::GetStreamLatency`) de entrada y de
///   salida, en muestras; como en el HAL, solo vale sin calibración.
/// - Marcas por ciclo en `HostTimeLog` (tics de `HostClock`) y contadores en `IOCounters` para `HostTimingAnalysis`.
/// - Desconexión o cambio de formato (`IMMNotificationClient`) → `AudioIOInterruption`.
public final class WASAPIAudioIO: AudioIO, @unchecked Sendable {
    public let format: AudioIOFormat
    public let inputDeviceUID: String
    public let outputDeviceUID: String
    public let clock: AudioIOClock = .single
    public let declaredLatencySamples: Double = 0
    public var isRunning: Bool { false }

    public init(setup: AudioSetup) throws {
        throw PlatformError.unsupported("paso 7: wasapi")
    }

    public func start(render: @escaping AudioIORenderHandler, capture: @escaping AudioIOCaptureHandler) throws {
        throw PlatformError.unsupported("paso 7: wasapi")
    }

    public func stop() {}
    public func setInterruptionHandler(_ handler: (@Sendable (AudioIOInterruption) -> Void)?) {}
}
#endif
