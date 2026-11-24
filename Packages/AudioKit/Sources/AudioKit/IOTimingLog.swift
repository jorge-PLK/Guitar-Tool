import Foundation
import NativePlatform
import Synchronization

// Portátiles (plan, «Fase 7c», paso 6): los usa `CoreAudioIO` y los usará la E/S WASAPI del paso 7, con las
// marcas por búfer pasadas a tics de `HostClock`.

/// Registro circular de las marcas de cada ciclo (diagnóstico de los saltos de 12 muestras de la Flex Prime).
/// Un escritor (el hilo de E/S, sin reservar memoria) y lectores fuera de él: el índice se publica con
/// `releasing` después de escribir la entrada; el lector copia solo las que el escritor no puede estar pisando.
final class HostTimeLog: @unchecked Sendable {
    struct Raw {
        var inSample: Double
        var outSample: Double
        var inHost: UInt64
        var outHost: UInt64
        var inRate: Double
        var outRate: Double
    }
    /// 2^16 ciclos: 11,6 min a 512 muestras y 48 kHz (de sobra para `verify --seconds 300`).
    static let capacity = 1 << 16
    /// Entradas más recientes que el lector no copia mientras la sesión corre (las que el escritor puede estar pisando).
    static let guardEntries = 64
    private let buf: UnsafeMutablePointer<Raw>
    private let written = Atomic<Int>(0)

    init() {
        buf = .allocate(capacity: Self.capacity)
        buf.initialize(repeating: Raw(inSample: 0, outSample: 0, inHost: 0, outHost: 0, inRate: 0, outRate: 0),
                       count: Self.capacity)
    }

    deinit { buf.deallocate() }

    func reset() { written.store(0, ordering: .releasing) }

    /// Solo desde el hilo de E/S.
    func append(_ r: Raw) {
        let n = written.load(ordering: .relaxed)
        buf[n & (Self.capacity - 1)] = r
        written.store(n + 1, ordering: .releasing)
    }

    func snapshot() -> [Raw] {
        let n = written.load(ordering: .acquiring)
        let keep = min(n, Self.capacity - Self.guardEntries)
        return (n - keep..<n).map { buf[$0 & (Self.capacity - 1)] }
    }

    /// Segundos de host de `HostClock` (`mach_absolute_time` en el Mac, QPC en Windows). 0 = sin marca.
    static func seconds(_ ticks: UInt64) -> Double {
        guard ticks > 0 else { return 0 }
        return Double(ticks) * timebase / 1e9
    }

    /// Nanosegundos por tic de `HostClock`.
    static let timebase: Double = HostClock.timebase
}

/// Contadores compartidos entre el IOProc, los avisos del HAL y quien pregunte.
final class IOCounters: Sendable {
    let overloads = Atomic<Int>(0)
    let gaps = Atomic<Int>(0)
    let callbacks = Atomic<Int>(0)
    let gapMax = Atomic<Int>(0)
    let inGaps = Atomic<Int>(0)
    let inGapMax = Atomic<Int>(0)
    /// `Int.max` / `Int.min` = sin medir.
    let skewMin = Atomic<Int>(.max)
    let skewMax = Atomic<Int>(.min)
    /// Solo WASAPI (`WASAPIStreamCore`): discontinuidades de captura, fotogramas tirados sin offset y correcciones del
    /// offset tras una discontinuidad (`DuplexClockSync.realigns`).
    let captureResets = Atomic<Int>(0)
    let droppedCaptureFrames = Atomic<Int>(0)
    let captureRealigns = Atomic<Int>(0)

    func reset() {
        captureResets.store(0, ordering: .relaxed)
        droppedCaptureFrames.store(0, ordering: .relaxed)
        captureRealigns.store(0, ordering: .relaxed)
        overloads.store(0, ordering: .relaxed)
        gaps.store(0, ordering: .relaxed)
        callbacks.store(0, ordering: .relaxed)
        gapMax.store(0, ordering: .relaxed)
        inGaps.store(0, ordering: .relaxed)
        inGapMax.store(0, ordering: .relaxed)
        skewMin.store(.max, ordering: .relaxed)
        skewMax.store(.min, ordering: .relaxed)
    }

    /// Solo desde el hilo de E/S (un escritor): máximo sin carreras.
    static func raise(_ a: borrowing Atomic<Int>, _ v: Int) { if v > a.load(ordering: .relaxed) { a.store(v, ordering: .relaxed) } }
    static func lower(_ a: borrowing Atomic<Int>, _ v: Int) { if v < a.load(ordering: .relaxed) { a.store(v, ordering: .relaxed) } }

    var diagnostics: AudioIODiagnostics {
        let lo = skewMin.load(ordering: .relaxed), hi = skewMax.load(ordering: .relaxed)
        return AudioIODiagnostics(overloads: overloads.load(ordering: .relaxed), inputJumps: inGaps.load(ordering: .relaxed),
                                  inputJumpMaxFrames: inGapMax.load(ordering: .relaxed), outputJumps: gaps.load(ordering: .relaxed),
                                  outputJumpMaxFrames: gapMax.load(ordering: .relaxed), outMinusInMin: lo == .max ? nil : lo,
                                  outMinusInMax: hi == .min ? nil : hi, callbacks: callbacks.load(ordering: .relaxed),
                                  captureResets: captureResets.load(ordering: .relaxed),
                                  droppedCaptureFrames: droppedCaptureFrames.load(ordering: .relaxed),
                                  captureRealigns: captureRealigns.load(ordering: .relaxed))
    }
}
