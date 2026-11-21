// Reproductor sobre AVAudioEngine: solo macOS (paso 7: reproductor).
#if canImport(AVFoundation)
import AVFoundation
import os

/// Fuente de un stem en el reproductor alojado en tiempo real (mini-spec Fase 3, «Alineado con el backing» 1).
/// Sustituye al `AVAudioPlayerNode` en ese modo: un `AVAudioSourceNode` que entrega, muestra a muestra y en
/// orden, los búferes que prepara `StemScheduler` (trozos del fichero, fundidos del bucle, relleno de la pista
/// de toma). Va al mismo mezclador del canal que el player, así que ganancia, mute, solo y nivel no cambian.
///
/// Por qué no el player: en `manualRenderingMode(.realtime)` `play()` llega al hilo de render de forma
/// asíncrona y, si el primer bloque sale antes, el player empieza un bloque tarde (medido: 0 o 256/512
/// muestras según la carrera). Aquí `start()` cambia el estado bajo el cerrojo antes de encender el render:
/// el primer bloque tras `HostedRenderer.activate()` entrega la muestra 0, sin carrera.
///
/// Si la cola se vacía (el programador no llegó), sale silencio y se anota la deuda: esas muestras se tiran
/// al llegar los búferes, para que el stem siga en la muestra de los demás y del reloj.
///
/// Tiempo real: `render` no reserva memoria; toma un cerrojo injusto (como `PlaybackClock`) y solo copia.
/// Los búferes consumidos se sueltan en `enqueue`/`stop` (cola del programador o actor principal).
final class StemFeed: @unchecked Sendable {
    private struct State {
        var buffers: [AVAudioPCMBuffer] = []
        /// Búfer en curso y muestra dentro de él.
        var head = 0
        var offset = 0
        var playing = false
        /// Muestras que se dieron como silencio por falta de datos y se tirarán al llegar.
        var owed = 0
        var underrunFrames = 0
    }

    let format: AVAudioFormat
    private let state: OSAllocatedUnfairLock<State>

    init(format: AVAudioFormat) {
        self.format = format
        var s = State()
        s.buffers.reserveCapacity(64)
        state = OSAllocatedUnfairLock(uncheckedState: s)
    }

    func makeNode() -> AVAudioSourceNode { Self.makeNode(feed: self) }

    /// Fuera de cualquier actor: el bloque se llama en el hilo de render.
    private static func makeNode(feed: StemFeed) -> AVAudioSourceNode {
        AVAudioSourceNode(format: feed.format) { _, _, frameCount, abl in
            feed.render(frames: Int(frameCount), abl: abl)
            return noErr
        }
    }

    /// Añade un búfer a la cola (formato `format`).
    func enqueue(_ buffer: AVAudioPCMBuffer) {
        state.withLockUnchecked { s in
            if s.head > 0 {
                s.buffers.removeFirst(s.head)
                s.head = 0
            }
            s.buffers.append(buffer)
        }
    }

    /// Empieza a entregar en el siguiente bloque.
    func start() {
        state.withLockUnchecked { $0.playing = true }
    }

    /// Para y vacía la cola.
    func stop() {
        let old = state.withLockUnchecked { s -> [AVAudioPCMBuffer] in
            let b = s.buffers
            s.buffers.removeAll(keepingCapacity: true)
            s.head = 0
            s.offset = 0
            s.owed = 0
            s.playing = false
            return b
        }
        _ = old
    }

    /// Muestras entregadas como silencio por falta de datos desde que se creó.
    var underrunFrames: Int { state.withLockUnchecked { $0.underrunFrames } }

    private func render(frames n: Int, abl: UnsafeMutablePointer<AudioBufferList>) {
        let out = UnsafeMutableAudioBufferListPointer(abl)
        for b in out { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }
        state.withLockUnchecked { s in
            guard s.playing else { return }
            // Deuda de un vacío anterior: se tira para no quedarse atrás.
            while s.owed > 0, s.head < s.buffers.count {
                let left = Int(s.buffers[s.head].frameLength) - s.offset
                let k = min(left, s.owed)
                s.owed -= k
                s.offset += k
                if s.offset >= Int(s.buffers[s.head].frameLength) { s.head += 1; s.offset = 0 }
            }
            var done = 0
            while done < n, s.owed == 0, s.head < s.buffers.count {
                let buf = s.buffers[s.head]
                let len = Int(buf.frameLength)
                let k = min(len - s.offset, n - done)
                if let src = buf.floatChannelData {
                    for ch in 0..<min(out.count, Int(buf.format.channelCount)) {
                        guard let d = out[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
                        (d + done).update(from: src[ch] + s.offset, count: k)
                    }
                }
                done += k
                s.offset += k
                if s.offset >= len { s.head += 1; s.offset = 0 }
            }
            if done < n {
                s.owed += n - done
                s.underrunFrames += n - done
            }
        }
    }
}

#endif // canImport(AVFoundation)
