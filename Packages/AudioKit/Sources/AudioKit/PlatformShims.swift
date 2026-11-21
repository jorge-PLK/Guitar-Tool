import Foundation
#if canImport(os)
import os
#endif

// Costuras internas de plataforma (plan, «Fase 7c», paso 6). En el Mac todo sigue siendo lo de siempre.

#if canImport(os)
/// Cerrojo con estado: en el Mac, `OSAllocatedUnfairLock` tal cual (cero cambio de comportamiento).
typealias StateLock<State> = OSAllocatedUnfairLock<State>
#else
/// Cerrojo con estado en Windows (no hay `os`): el subconjunto de `OSAllocatedUnfairLock` que usa el paquete.
final class StateLock<State>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State

    init(initialState: State) { state = initialState }
    init(uncheckedState: State) { state = uncheckedState }

    func withLock<R>(_ body: (inout State) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }

    func withLockUnchecked<R>(_ body: (inout State) throws -> R) rethrows -> R { try withLock(body) }
}
#endif

/// Reproductor alojado en la sesión (`StudyPlayer.attach(to:)`): lo que `AudioSession` necesita de él en el hilo
/// de E/S. En el Mac lo cumple `HostedRenderer` (render manual de `AVAudioEngine`); en Windows, el mezclador propio
/// del paso 7 (paso 7: reproductor).
protocol HostedPlayback: AnyObject, Sendable {
    /// Ancla entre la línea de la sesión y el tiempo del tema; `nil` antes del primer bloque.
    var anchor: PlaybackAnchor? { get }
    /// Suma el backing en los canales `left` y `right` del bloque de salida. Tiempo real: sin cerrojos ni memoria.
    func render(into buffer: AudioIOBuffer, left: Int, right: Int)
}
