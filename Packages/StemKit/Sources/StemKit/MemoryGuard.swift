import Darwin
import Dispatch
import Synchronization

/// Vigilante de memoria de un proceso hijo: cada `interval` lee su memoria con
/// `proc_pid_rusage(RUSAGE_INFO_V4)` (máximo entre `phys_footprint` y residente, como
/// Probes/P4-modelos/common/guard.py), guarda el pico y, si pasa de `limitBytes`, le manda SIGKILL.
public final class MemoryGuard: Sendable {
    /// Límite por defecto de un proceso pesado (guard.py: `--limit-gb 10`).
    public static let defaultLimitBytes: UInt64 = 10_000_000_000
    /// Periodo de sondeo de guard.py.
    public static let defaultInterval: Double = 0.5

    public let pid: pid_t
    public let limitBytes: UInt64
    public let interval: Double

    private struct State {
        var peak: UInt64 = 0
        var exceeded = false
        var timer: DispatchSourceTimer?
    }
    private let state = Mutex(State())
    private let onExceeded: (@Sendable (UInt64) -> Void)?

    /// - Parameter onExceeded: se llama una vez, tras el SIGKILL, con el pico medido.
    public init(pid: pid_t, limitBytes: UInt64 = MemoryGuard.defaultLimitBytes,
                interval: Double = MemoryGuard.defaultInterval,
                onExceeded: (@Sendable (UInt64) -> Void)? = nil) {
        self.pid = pid
        self.limitBytes = limitBytes
        self.interval = interval
        self.onExceeded = onExceeded
    }

    deinit { stop() }

    /// Empieza a sondear (la primera lectura es inmediata).
    public func start() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in self?.sample() }
        state.withLock { $0.timer = timer }
        timer.resume()
    }

    /// Deja de sondear. Idempotente.
    public func stop() {
        let timer = state.withLock { s -> DispatchSourceTimer? in
            defer { s.timer = nil }
            return s.timer
        }
        timer?.cancel()
    }

    /// Pico observado en bytes.
    public var peakBytes: UInt64 { state.withLock { $0.peak } }
    /// `true` si el vigilante mató al proceso por pasar del límite.
    public var limitExceeded: Bool { state.withLock { $0.exceeded } }

    private func sample() {
        guard let bytes = Self.footprint(pid: pid) else { return }
        let kill = state.withLock { s -> Bool in
            s.peak = max(s.peak, bytes)
            guard bytes > limitBytes, !s.exceeded else { return false }
            s.exceeded = true
            return true
        }
        if kill {
            Darwin.kill(pid, SIGKILL)
            stop()
            onExceeded?(peakBytes)
        }
    }

    /// Memoria de un proceso: `max(phys_footprint, resident_size)` de `rusage_info_v4`; nil si no existe.
    public static func footprint(pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard rc == 0 else { return nil }
        return max(info.ri_phys_footprint, info.ri_resident_size)
    }
}
