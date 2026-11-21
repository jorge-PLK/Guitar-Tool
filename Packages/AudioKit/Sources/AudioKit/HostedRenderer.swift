// Reproductor sobre AVAudioEngine: solo macOS (paso 7: reproductor).
#if canImport(AVFoundation)
import AVFoundation
import Synchronization

/// El reproductor renderizado dentro del `render` de una sesión de `AudioIO` (mini-spec Fase 3, «Alineado
/// con el backing» 1). El motor del `StudyPlayer` va en `manualRenderingMode` (`.realtime` en la app,
/// `.offline` en tests) y cada bloque de salida de la sesión pide al motor las mismas muestras: el backing
/// que suena y la entrada que se graba comparten el reloj del dispositivo, sin conversión ni segundo reloj.
///
/// **Línea de tiempo.** El motor cuenta sus propias muestras; tras cada bloque se anota
/// `hostOffset = muestra de la sesión − muestra del motor` (fin de bloque contra fin de bloque) en el reloj
/// de reproducción. Si la sesión salta muestras (sobrecarga del HAL: el `sampleTime` de salida avanza más que
/// el bloque anterior), el motor renderiza y tira las que faltan, hasta `maxCatchUpSeconds`, para que el
/// desplazamiento no cambie y el ancla de la pasada siga valiendo; más allá, el desplazamiento cambia, el
/// ancla también, y quien grabe lo ve (`AudioSession` corta la toma ahí).
///
/// **Arranque de pasada.** `activate`/`deactivate` encienden y apagan el render: el actor principal apaga,
/// para y programa los stems, los arranca y enciende. Así el primer render con stems en marcha es el
/// primero tras encender, igual que en render offline, y el ancla cae en la muestra exacta. En `.realtime`
/// los stems salen de `StemFeed` (arranque síncrono), no de `AVAudioPlayerNode`, y el ancla suma el retardo
/// que declara el TimePitch en ese modo (4096 muestras a velocidad 1). `deactivate`
/// espera a que acabe el render en curso (Dekker con orden secuencial sobre `active`/`busy`).
///
/// Tiempo real: `render` no reserva memoria; toma el cerrojo injusto del reloj (secciones cortas, como el
/// metrónomo) y, en `.offline`, rellena la cola de stems (bloquea: solo en tests).
final class HostedRenderer: @unchecked Sendable {
    /// Lo que se recupera de un salto de la sesión renderizando en vacío (decisión propia).
    static let maxCatchUpSeconds = 1.0

    private let block: AVAudioEngineManualRenderingBlock
    private let clock: PlaybackClock
    private let maxFrames: Int
    private let maxCatchUp: Int64
    private let abl: UnsafeMutableAudioBufferListPointer
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>
    /// Solo en render offline (tests): rellena la cola tras cada bloque.
    private let topUp: (@Sendable () -> Void)?
    let sampleRate: Double
    /// Latencia de salida para `currentTime` (solo para enseñar).
    let presentationLatencyFrames: Double

    private let active = Atomic<Bool>(false)
    private let busy = Atomic<Bool>(false)
    private let catchUps = Atomic<Int>(0)
    /// Solo del hilo de render.
    private var expected: Int64?
    private var owed: Int64 = 0

    init(block: @escaping AVAudioEngineManualRenderingBlock, clock: PlaybackClock, maxFrames: Int, sampleRate: Double,
         presentationLatencyFrames: Double, topUp: (@Sendable () -> Void)?) {
        self.block = block
        self.clock = clock
        self.maxFrames = maxFrames
        self.sampleRate = sampleRate
        self.presentationLatencyFrames = presentationLatencyFrames
        self.topUp = topUp
        maxCatchUp = Int64(Self.maxCatchUpSeconds * sampleRate)
        left = .allocate(capacity: maxFrames)
        right = .allocate(capacity: maxFrames)
        abl = AudioBufferList.allocate(maximumBuffers: 2)
        abl[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: UnsafeMutableRawPointer(left))
        abl[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: UnsafeMutableRawPointer(right))
    }

    deinit {
        left.deallocate()
        right.deallocate()
        abl.unsafeMutablePointer.deallocate()
    }

    /// Saltos de la sesión recuperados renderizando en vacío.
    var catchUpCount: Int { catchUps.load(ordering: .relaxed) }

    // Diagnóstico de `tf-audio verify` (solo se suman; nunca se reinician durante la pasada).
    private let catchUpFramesTotal = Atomic<Int>(0)
    private let failedPullFrames = Atomic<Int>(0)
    private let forwardJumps = Atomic<Int>(0)
    private let forwardJumpMax = Atomic<Int>(0)
    private let backwardJumps = Atomic<Int>(0)

    var stats: HostedRenderStats {
        HostedRenderStats(catchUps: catchUpCount, catchUpFrames: catchUpFramesTotal.load(ordering: .relaxed),
                          failedPullFrames: failedPullFrames.load(ordering: .relaxed),
                          outputJumps: forwardJumps.load(ordering: .relaxed),
                          outputJumpMaxFrames: forwardJumpMax.load(ordering: .relaxed),
                          outputBackwardJumps: backwardJumps.load(ordering: .relaxed))
    }

    func activate() {
        clock.update { $0.hostOffset = nil }
        expectedReset.store(true, ordering: .sequentiallyConsistent)
        active.store(true, ordering: .sequentiallyConsistent)
    }

    private let expectedReset = Atomic<Bool>(true)

    /// Apaga el render y espera a que termine el que esté en curso. Nunca desde el hilo de render.
    func deactivate() {
        active.store(false, ordering: .sequentiallyConsistent)
        while busy.load(ordering: .sequentiallyConsistent) { sched_yield() }
    }

    /// Ancla de la pasada en curso en la línea de tiempo de la sesión.
    var anchor: PlaybackAnchor? {
        let sr = sampleRate
        return clock.read { s -> PlaybackAnchor? in
            guard s.running, !s.pendingStart, let off = s.hostOffset else { return nil }
            return PlaybackAnchor(songTime: s.startSongFrame / sr, outputSample: s.runStartFrame + s.latencyFrames + off,
                                  sampleRate: sr, rate: s.rate)
        }
    }

    /// Hilo de E/S: escribe el estéreo del reproductor en los canales `l` y `r` (índices desde 0; fuera de
    /// rango = no se escribe) del bloque de salida.
    func render(into buffer: AudioIOBuffer, left l: Int, right r: Int) {
        busy.store(true, ordering: .sequentiallyConsistent)
        defer { busy.store(false, ordering: .sequentiallyConsistent) }
        guard active.load(ordering: .sequentiallyConsistent) else { return }
        if expectedReset.exchange(false, ordering: .relaxed) {
            expected = nil
            owed = 0
        }

        let t = buffer.sampleTime
        // Lo que falta: el salto de la sesión y lo que el motor no pudo dar en el bloque anterior.
        var gap = owed
        if let e = expected, t > e {
            gap += t - e
            forwardJumps.add(1, ordering: .relaxed)
            let size = Int(t - e)
            if size > forwardJumpMax.load(ordering: .relaxed) { forwardJumpMax.store(size, ordering: .relaxed) }
        } else if let e = expected, t < e {
            backwardJumps.add(1, ordering: .relaxed)
        }
        owed = 0
        if gap > 0 {
            gap = min(gap, maxCatchUp)
            catchUps.add(1, ordering: .relaxed)
            while gap > 0 {
                let n = Int(min(gap, Int64(maxFrames)))
                if !pull(n) { owed += gap; break }
                catchUpFramesTotal.add(n, ordering: .relaxed)
                gap -= Int64(n)
            }
        }
        var done = 0
        let total = buffer.frameCount
        while done < total {
            let n = min(maxFrames, total - done)
            if pull(n) {
                if l >= 0, l < buffer.channelCount { (buffer[l].baseAddress! + done).update(from: left, count: n) }
                if r >= 0, r < buffer.channelCount { (buffer[r].baseAddress! + done).update(from: right, count: n) }
            } else {
                owed += Int64(n)
                failedPullFrames.add(n, ordering: .relaxed)
            }
            done += n
        }
        expected = t + Int64(total)
        let end = Double(t + Int64(total))
        clock.update { $0.hostOffset = end - ($0.lastRenderStart + $0.lastRenderFrames) }
    }

    /// Pide `n` muestras al motor.
    private func pull(_ n: Int) -> Bool {
        let bytes = UInt32(n * MemoryLayout<Float>.size)
        abl[0].mDataByteSize = bytes
        abl[0].mData = UnsafeMutableRawPointer(left)
        abl[1].mDataByteSize = bytes
        abl[1].mData = UnsafeMutableRawPointer(right)
        var err: OSStatus = noErr
        let status = block(AVAudioFrameCount(n), abl.unsafeMutablePointer, &err)
        topUp?()
        // `.cannotDoInCurrentContext` (el motor no puede dar las muestras sin bloquear): no avanzó; se
        // devuelve false y se recuperan en el siguiente bloque.
        guard status == .success else {
            left.update(repeating: 0, count: n)
            right.update(repeating: 0, count: n)
            return false
        }
        return true
    }
}

extension HostedRenderer: HostedPlayback {}

#endif // canImport(AVFoundation)
