import Foundation
import NativeDSP
import NativeAudioFile
import NativeResample
import CSignalsmith
import Synchronization

// Motor del reproductor sin AVFoundation (plan, «Corte del paso 7», parte 7.6): el de `PortableStudyPlayer`, que en
// Windows es `StudyPlayer`. Compila también en el Mac, donde se prueba con los mismos casos que el de AVAudioEngine.

/// Números del motor portátil (decisiones propias de la parte 7.6; los del reproductor, en `StudyPlayerConstants`).
enum PortablePlaybackConstants {
    /// Bloque interno máximo: los bloques mayores del dispositivo se parten.
    static let maxBlock = 1_024
    /// Capacidad de cada anillo, en segundos de salida: cola a velocidad 2 (2 × 0,5 s) + trozo + margen.
    static let ringSeconds = 1.6
    /// Cada cuánto rellena el hilo lector en tiempo real (en Windows `Thread.sleep` redondea a ~15,6 ms: sobra con
    /// 0,5 s de cola).
    static let readerIntervalSeconds = 0.005
    static let maxClickVoices = 32
    static let clickEventCapacity = 1_024
    /// Lo que se recupera de un salto del dispositivo renderizando en vacío (el mismo que `HostedRenderer`).
    static let maxCatchUpSeconds = 1.0
    /// Fundido al sustituir una pasada que sonaba (buscar, velocidad): el mismo que el corte del bucle
    /// (`StudyPlayerConstants.loopCrossfadeSeconds`, mini-spec §1 AudioKit).
    static let declickSeconds = StudyPlayerConstants.loopCrossfadeSeconds
}

// MARK: - Atómicos de coma flotante

final class AtomicFloat: Sendable {
    private let bits: Atomic<UInt32>
    init(_ v: Float) { bits = Atomic(v.bitPattern) }
    func load() -> Float { Float(bitPattern: bits.load(ordering: .relaxed)) }
    func store(_ v: Float) { bits.store(v.bitPattern, ordering: .relaxed) }
}

final class AtomicDouble: Sendable {
    private let bits: Atomic<UInt64>
    init(_ v: Double) { bits = Atomic(v.bitPattern) }
    func load() -> Double { Double(bitPattern: bits.load(ordering: .acquiring)) }
    func store(_ v: Double) { bits.store(v.bitPattern, ordering: .releasing) }
}

// MARK: - Anillo estéreo sin cerrojos (un productor, un consumidor)

/// Anillo de muestras estéreo planas. Productor: el lector (con su cerrojo); consumidor: el hilo de E/S. Sin cerrojos
/// ni reservas en `read`/`skip`. `reset` solo con los dos parados.
final class FrameRing: @unchecked Sendable {
    let capacity: Int
    private let mask: Int
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>
    private let head = Atomic<Int>(0)
    private let tail = Atomic<Int>(0)

    init(minimumCapacity: Int) {
        var c = 1
        while c < minimumCapacity { c <<= 1 }
        capacity = c
        mask = c - 1
        left = .allocate(capacity: c)
        right = .allocate(capacity: c)
        left.initialize(repeating: 0, count: c)
        right.initialize(repeating: 0, count: c)
    }

    deinit {
        left.deallocate()
        right.deallocate()
    }

    var readable: Int { head.load(ordering: .acquiring) - tail.load(ordering: .acquiring) }
    var writable: Int { capacity - readable }

    func write(left l: UnsafePointer<Float>, right r: UnsafePointer<Float>, count n: Int) {
        guard n > 0 else { return }
        let h = head.load(ordering: .relaxed)
        Self.copyIn(l, into: left, at: h & mask, count: n, capacity: capacity)
        Self.copyIn(r, into: right, at: h & mask, count: n, capacity: capacity)
        head.store(h + n, ordering: .releasing)
    }

    /// Copia hasta `n` muestras en `l`/`r` y devuelve cuántas había.
    func read(into l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, count n: Int) -> Int {
        let t = tail.load(ordering: .relaxed)
        let k = min(n, head.load(ordering: .acquiring) - t)
        guard k > 0 else { return 0 }
        Self.copyOut(left, at: t & mask, into: l, count: k, capacity: capacity)
        Self.copyOut(right, at: t & mask, into: r, count: k, capacity: capacity)
        tail.store(t + k, ordering: .releasing)
        return k
    }

    func skip(_ n: Int) -> Int {
        let t = tail.load(ordering: .relaxed)
        let k = min(n, head.load(ordering: .acquiring) - t)
        guard k > 0 else { return 0 }
        tail.store(t + k, ordering: .releasing)
        return k
    }

    func reset() {
        head.store(0, ordering: .sequentiallyConsistent)
        tail.store(0, ordering: .sequentiallyConsistent)
    }

    private static func copyIn(_ src: UnsafePointer<Float>, into dst: UnsafeMutablePointer<Float>, at i: Int, count n: Int,
                               capacity: Int) {
        let first = min(n, capacity - i)
        (dst + i).update(from: src, count: first)
        if n > first { dst.update(from: src + first, count: n - first) }
    }

    private static func copyOut(_ src: UnsafeMutablePointer<Float>, at i: Int, into dst: UnsafeMutablePointer<Float>, count n: Int,
                                capacity: Int) {
        let first = min(n, capacity - i)
        dst.update(from: src + i, count: first)
        if n > first { (dst + first).update(from: src, count: n - first) }
    }
}

/// Anillo de eventos de clic (muestra de salida relativa al arranque de la pasada, acento, generación).
final class ClickEventRing: @unchecked Sendable {
    private let capacity = PortablePlaybackConstants.clickEventCapacity
    private let starts: UnsafeMutablePointer<Int64>
    private let accents: UnsafeMutablePointer<Bool>
    private let gens: UnsafeMutablePointer<Int>
    private let head = Atomic<Int>(0)
    private let tail = Atomic<Int>(0)

    init() {
        starts = .allocate(capacity: capacity)
        accents = .allocate(capacity: capacity)
        gens = .allocate(capacity: capacity)
        starts.initialize(repeating: 0, count: capacity)
        accents.initialize(repeating: false, count: capacity)
        gens.initialize(repeating: 0, count: capacity)
    }

    deinit {
        starts.deallocate()
        accents.deallocate()
        gens.deallocate()
    }

    @discardableResult
    func push(start: Int64, accent: Bool, gen: Int) -> Bool {
        let h = head.load(ordering: .relaxed)
        guard h - tail.load(ordering: .acquiring) < capacity else { return false }
        let i = h % capacity
        starts[i] = start
        accents[i] = accent
        gens[i] = gen
        head.store(h + 1, ordering: .releasing)
        return true
    }

    func peek() -> (start: Int64, accent: Bool, gen: Int)? {
        let t = tail.load(ordering: .relaxed)
        guard head.load(ordering: .acquiring) > t else { return nil }
        let i = t % capacity
        return (starts[i], accents[i], gens[i])
    }

    func pop() { tail.store(tail.load(ordering: .relaxed) + 1, ordering: .releasing) }

    func reset() {
        head.store(0, ordering: .sequentiallyConsistent)
        tail.store(0, ordering: .sequentiallyConsistent)
    }
}

// MARK: - Signalsmith Stretch

/// Signalsmith Stretch 1.3 (NativeKit `CSignalsmith`, MIT), estéreo, Float32 plano. Sin reservas en `process` ni en
/// `setTranspose`: se puede llamar desde el hilo de E/S. `outputSeek` reserva (hilo principal, render apagado).
final class TimeStretcher: @unchecked Sendable {
    private let handle: OpaquePointer
    private let inPtrs: UnsafeMutablePointer<UnsafePointer<Float>?>
    private let outPtrs: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>

    init?(sampleRate: Double) {
        guard let h = tf_stretch_create(2, Float(sampleRate)) else { return nil }
        handle = h
        inPtrs = .allocate(capacity: 2)
        outPtrs = .allocate(capacity: 2)
        inPtrs.initialize(repeating: nil, count: 2)
        outPtrs.initialize(repeating: nil, count: 2)
    }

    deinit {
        tf_stretch_destroy(handle)
        inPtrs.deallocate()
        outPtrs.deallocate()
    }

    var inputLatency: Int { Int(tf_stretch_input_latency(handle)) }
    var outputLatency: Int { Int(tf_stretch_output_latency(handle)) }
    var blockSamples: Int { Int(tf_stretch_block_samples(handle)) }
    var intervalSamples: Int { Int(tf_stretch_interval_samples(handle)) }

    func outputSeekLength(rate: Double) -> Int { Int(tf_stretch_output_seek_length(handle, Float(rate))) }

    /// Cents (±1250, como el TimePitch); sin límite de tonalidad.
    func setTranspose(cents: Double) {
        tf_stretch_set_transpose_factor(handle, Float(pow(2, cents / 1_200)), 0)
    }

    func reset() { tf_stretch_reset(handle) }

    func outputSeek(left l: UnsafePointer<Float>, right r: UnsafePointer<Float>, count n: Int) {
        inPtrs[0] = l
        inPtrs[1] = r
        tf_stretch_output_seek(handle, inPtrs, Int32(n))
    }

    func process(left l: UnsafePointer<Float>, right r: UnsafePointer<Float>, count n: Int,
                 outLeft ol: UnsafeMutablePointer<Float>, outRight or: UnsafeMutablePointer<Float>, outCount m: Int) {
        inPtrs[0] = l
        inPtrs[1] = r
        outPtrs[0] = ol
        outPtrs[1] = or
        tf_stretch_process(handle, inPtrs, Int32(n), outPtrs, Int32(m))
    }
}

// MARK: - Stems

/// Un canal del motor: fichero, dónde cae su muestra 0 en el tema (pista de toma) y punch-in.
struct PortableStem: Sendable {
    var url: URL
    /// Muestra del tema (a la frecuencia de los stems) donde cae la 0 del fichero.
    var offset: Int64 = 0
    /// Punch-in (mini-spec Fase 6): desde esta muestra del tema el canal se silencia con el fundido de `PunchFlattener`.
    var fadeOutFrom: Int64?
}

/// Lectura de un stem por tramos del tema, con ceros fuera del fichero y el fundido del punch-in. Solo el lector.
final class StemSource {
    let stem: PortableStem
    let reader: AudioFileReader
    let length: Int64
    private var extra: [UnsafeMutablePointer<Float>] = []
    private let capacity: Int
    private let punchFade: Int

    init(stem: PortableStem, maxFrames: Int, sampleRate: Double) throws {
        self.stem = stem
        do { reader = try AudioFileReader(url: stem.url) } catch {
            throw StudyPlayerError.unreadable(stem.url.lastPathComponent)
        }
        length = Int64(reader.frameCount)
        capacity = maxFrames
        punchFade = PunchFlattener.crossfadeFrames(sampleRate: sampleRate)
        if reader.channelCount > 2 {
            extra = (2..<reader.channelCount).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: maxFrames) }
        }
    }

    deinit { for p in extra { p.deallocate() } }

    /// `[s, s + n)` del tema en `l`/`r` (mono → los dos canales; más de dos → los dos primeros).
    func read(songStart s: Int64, frames n: Int, left l: UnsafeMutablePointer<Float>, right r: UnsafeMutablePointer<Float>) {
        precondition(n <= capacity)
        l.update(repeating: 0, count: n)
        r.update(repeating: 0, count: n)
        let a = s - stem.offset
        let lo = max(a, 0), hi = min(a + Int64(n), length)
        if hi > lo {
            let off = Int(lo - a)
            do {
                if reader.framePosition != Int(lo) { try reader.seek(toFrame: Int(lo)) }
                var done = 0
                let want = Int(hi - lo)
                while done < want {
                    var ptrs = [l + off + done]
                    if reader.channelCount >= 2 { ptrs.append(r + off + done) }
                    for p in extra { ptrs.append(p) }
                    let got = try reader.read(into: ptrs, maxFrames: want - done)
                    if got == 0 { break }
                    done += got
                }
                if reader.channelCount == 1 { (r + off).update(from: l + off, count: done) }
            } catch {
                // Fichero dañado a mitad: lo que no se pudo leer queda en silencio.
            }
        }
        if let m = stem.fadeOutFrom, s + Int64(n) > m {
            for j in 0..<n {
                let g = Self.punchGain(s + Int64(j), from: m, fade: punchFade)
                l[j] *= g
                r[j] *= g
            }
        }
    }

    /// La misma curva que `StemScheduler.punchGain` (1 antes de `m`, `1 − w` en el fundido, 0 después).
    static func punchGain(_ f: Int64, from m: Int64, fade: Int) -> Float {
        if f < m { return 1 }
        let i = f - m
        return i < Int64(fade) ? 1 - PunchFlattener.weight(Int(i), fade) : 0
    }
}

// MARK: - Motor

/// Mezclador por extracción del reproductor portátil.
///
/// **Cadena.** Cada stem → anillo sin cerrojos (lo llena el lector) → ganancia del canal → submezcla → Signalsmith
/// (solo si la velocidad ≠ 1 o el tono ≠ 0) → + metrónomo (sin estirar) → ganancia global. El render lo pide el hilo de
/// E/S (`render`): sin cerrojos ni reservas; lee atómicos y los anillos.
///
/// **Lector.** Mismo plan que el de AVAudioEngine (`SchedulePlanner`: trozos de 0,25 s, cola de 0,5 s, bucle con fundido
/// cruzado de 5 ms en `b → a`). En tiempo real lo hace un hilo propio cada 5 ms; offline (tests, `tf-audio --simulated`),
/// `topUp()` tras cada bloque. Si la salida va a otra frecuencia que los stems, cada stem pasa por un `StreamResampler`
/// (r8brain, latencia 0) en el lector.
///
/// **Tiempo.** Como `ClockState`: la salida `y` oye la muestra acumulada `k = (y − arranque − latencia)·ritmo`, con
/// `ritmo = velocidad · fs_stems / fs_salida`, traducida a canción con los tramos programados. El arranque es la muestra
/// del primer bloque de la pasada. A velocidad 1 y tono 0 la latencia es 0 y la salida es la suma exacta de los stems.
/// Con Signalsmith, la pasada arranca con `outputSeek` (pre-cálculo de su latencia de salida con la entrada desde el
/// punto de arranque), así que la latencia de modelo también es 0; `stretchResidualFrames` recoge lo medido.
final class PortablePlaybackEngine: @unchecked Sendable {
    /// Desfase medido de Signalsmith tras `outputSeek`, en muestras de salida (`PortablePlayerMeasurementTests`).
    static let stretchResidualFrames = 0.0

    let songRate: Double
    let outputRate: Double
    let realtime: Bool
    let length: Int64
    let halfFade: Int64
    let stemCount: Int

    private let rings: [FrameRing]
    private let stretcher: TimeStretcher
    private let maxBlock = PortablePlaybackConstants.maxBlock
    private let scratchFrames: Int
    // Solo el hilo de E/S (o el principal con el render apagado).
    private let subL, subR, tmpL, tmpR, outL, outR: UnsafeMutablePointer<Float>
    private let owed: UnsafeMutablePointer<Int>
    private let normalClick: [Float]
    private let accentClick: [Float]
    private let voiceStart: UnsafeMutablePointer<Int64>
    private let voiceAccent: UnsafeMutablePointer<Bool>
    private var voiceCount = 0
    private var rendered: Int64 = 0
    private var appliedCents = 0.0
    private var bypass = true
    private var stretchRate = 1.0
    private let events = ClickEventRing()
    private let declickFrames: Int
    private var fadeLeft = 0
    private var fadeFromL: Float = 0
    private var fadeFromR: Float = 0
    private var lastL: Float = 0
    private var lastR: Float = 0

    // Del principal al hilo de E/S.
    private let active = Atomic<Bool>(false)
    private let busy = Atomic<Bool>(false)
    private let gains: [AtomicFloat]
    private let master = AtomicFloat(1)
    private let clickGain = AtomicFloat(0)
    private let cents = AtomicDouble(0)
    private let clickGen = Atomic<Int>(0)
    private let sourceEnded = Atomic<Bool>(false)

    // Del hilo de E/S al resto (y el ancla, que lee la sesión en su hilo de E/S: sin cerrojos).
    private let runStarted = Atomic<Bool>(false)
    private let runStart = Atomic<Int64>(0)
    private let lastStart = Atomic<Int64>(0)
    private let lastFrames = Atomic<Int>(0)
    private let renderedAtomic = Atomic<Int64>(0)
    private let lastHost = AtomicDouble(0)
    private let meterPeak: [AtomicFloat]
    private let meterRMS: [AtomicFloat]
    private let underruns = Atomic<Int>(0)
    private let anchorRunning = Atomic<Bool>(false)
    private let anchorSong = AtomicDouble(0)
    private let anchorRate = AtomicDouble(1)
    private let anchorLatency = AtomicDouble(0)
    // Diagnóstico (solo se suman).
    private let catchUps = Atomic<Int>(0)
    private let catchUpFrames = Atomic<Int>(0)
    private let forwardJumps = Atomic<Int>(0)
    private let forwardJumpMax = Atomic<Int>(0)
    private let backwardJumps = Atomic<Int>(0)

    // Lector: todo bajo `readerLock` (el hilo de E/S nunca lo toma).
    private let readerLock = NSLock()
    /// Vacío tras `shutdown()`: los lectores (y sus ficheros) se sueltan ahí, no cuando muera el motor.
    private var sources: [StemSource]
    private var closed = false
    private var resamplers: [StreamResampler?] = []
    private var planner: SchedulePlanner
    private var clock = ClockState()
    private var cumScheduled: Int64 = 0
    private var clickCursor: Int64 = 0
    private var generation = 0
    private var runActive = false
    private var endReported = false
    private var flushed = false
    private var queueTarget = 0
    private var maxPieceRingFrames = 0
    private let onEnd: @Sendable (Int) -> Void
    private var readL: [Float]
    private var readR: [Float]
    private var fadeL: [Float]
    private var fadeR: [Float]
    private let alive = Atomic<Bool>(true)

    init(stems: [PortableStem], songRate: Double, length: Int64, outputRate: Double, realtime: Bool,
         onEnd: @escaping @Sendable (Int) -> Void) throws {
        precondition(!stems.isEmpty)
        self.songRate = songRate
        self.outputRate = outputRate
        self.realtime = realtime
        self.length = length
        self.onEnd = onEnd
        stemCount = stems.count
        let chunk = Int64(StudyPlayerConstants.chunkSeconds * songRate)
        halfFade = max(1, Int64((StudyPlayerConstants.loopCrossfadeSeconds * songRate / 2).rounded()))
        planner = SchedulePlanner(length: length, chunkFrames: chunk, halfFade: halfFade, songPos: 0, loop: nil)
        let maxRead = Int(max(chunk, 2 * halfFade)) + 16
        sources = try stems.map { try StemSource(stem: $0, maxFrames: maxRead, sampleRate: songRate) }
        guard let st = TimeStretcher(sampleRate: outputRate) else { throw StudyPlayerError.engine("Signalsmith") }
        stretcher = st
        let ringFrames = Int(PortablePlaybackConstants.ringSeconds * outputRate) + st.outputSeekLength(rate: 2)
        rings = stems.map { _ in FrameRing(minimumCapacity: ringFrames) }
        gains = stems.map { _ in AtomicFloat(1) }
        meterPeak = stems.map { _ in AtomicFloat(0) }
        meterRMS = stems.map { _ in AtomicFloat(0) }
        scratchFrames = 2 * PortablePlaybackConstants.maxBlock + 16
        func buf() -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: 2 * PortablePlaybackConstants.maxBlock + 16)
            p.initialize(repeating: 0, count: 2 * PortablePlaybackConstants.maxBlock + 16)
            return p
        }
        subL = buf(); subR = buf(); tmpL = buf(); tmpR = buf(); outL = buf(); outR = buf()
        owed = .allocate(capacity: stems.count)
        owed.initialize(repeating: 0, count: stems.count)
        voiceStart = .allocate(capacity: PortablePlaybackConstants.maxClickVoices)
        voiceStart.initialize(repeating: 0, count: PortablePlaybackConstants.maxClickVoices)
        voiceAccent = .allocate(capacity: PortablePlaybackConstants.maxClickVoices)
        voiceAccent.initialize(repeating: false, count: PortablePlaybackConstants.maxClickVoices)
        declickFrames = max(1, Int(PortablePlaybackConstants.declickSeconds * outputRate))
        normalClick = ClickSynth.template(accent: false, sampleRate: outputRate)
        accentClick = ClickSynth.template(accent: true, sampleRate: outputRate)
        readL = [Float](repeating: 0, count: maxRead)
        readR = [Float](repeating: 0, count: maxRead)
        fadeL = [Float](repeating: 0, count: maxRead)
        fadeR = [Float](repeating: 0, count: maxRead)
        let ratio = outputRate / songRate
        maxPieceRingFrames = Int((Double(max(chunk, 2 * halfFade)) * ratio).rounded(.up)) + 1_024
        if realtime { startReaderThread() }
    }

    deinit {
        for p in [subL, subR, tmpL, tmpR, outL, outR] { p.deallocate() }
        owed.deallocate()
        voiceStart.deallocate()
        voiceAccent.deallocate()
    }

    /// Para el render y el hilo lector y cierra los ficheros de los stems antes de volver (plan, «Pendiente tras el
    /// paso 7»): aunque alguien retenga aún el motor (la sesión, el cierre de la salida propia), no queda ningún lector
    /// abierto y en Windows los ficheros se pueden borrar o reescribir ya. El hilo de E/S nunca toca los lectores (solo
    /// los anillos), y el lector solo bajo `readerLock`: soltarlos bajo el cerrojo no compite con nadie. Después el
    /// motor ya no vuelve a sonar (`start` no hace nada). Llamar al dejar de usar el motor.
    func shutdown() {
        stop()
        alive.store(false, ordering: .relaxed)
        readerLock.lock()
        closed = true
        sources = []
        readerLock.unlock()
    }

    /// Lectores abiertos (solo tests: comprueban con referencias débiles que `shutdown` los suelta).
    var stemReadersForTests: [AudioFileReader] { readerLock.withLock { sources.map(\.reader) } }

    var clickFrames: Int { normalClick.count }
    var stretchInputLatency: Int { stretcher.inputLatency }
    var stretchOutputLatency: Int { stretcher.outputLatency }

    // MARK: Pasadas (hilo principal)

    /// Nueva pasada desde `songFrame` (muestra del tema). Para el render, vacía anillos, programa la cola y, con
    /// Signalsmith, lo arranca con `outputSeek`. El primer bloque que pida el dispositivo es la muestra 0 de la pasada.
    ///
    /// `declick`: la pasada sustituye a otra que sonaba (buscar, cambiar velocidad): los primeros
    /// `declickSeconds` pasan del último valor que salió a la pasada nueva con el fundido del bucle, sin escalón.
    /// `forceStretch`: Signalsmith también a velocidad 1 y tono 0 (solo para medirlo).
    @discardableResult
    func start(songFrame: Int64, loop: Range<Int64>?, rate: Double, cents c: Double, declick: Bool = false,
               forceStretch: Bool = false) -> Int {
        deactivate()
        fadeLeft = declick ? declickFrames : 0
        fadeFromL = lastL
        fadeFromR = lastR
        readerLock.lock()
        defer { readerLock.unlock() }
        guard !closed else { return generation }
        generation += 1
        runActive = true
        // Antes de programar: la poda de tramos y los clics miran lo renderizado en esta pasada.
        rendered = 0
        renderedAtomic.store(0, ordering: .relaxed)
        endReported = false
        flushed = false
        sourceEnded.store(false, ordering: .relaxed)
        for r in rings { r.reset() }
        events.reset()
        owed.update(repeating: 0, count: stemCount)
        voiceCount = 0
        resamplers = (0..<stemCount).map { _ in
            outputRate == songRate ? nil : try? StreamResampler(from: songRate, to: outputRate, channels: 2)
        }
        planner.songPos = songFrame
        planner.loop = loop
        bypass = rate == 1 && c == 0 && !forceStretch
        stretchRate = rate
        let latency = bypass ? 0 : Self.stretchResidualFrames
        clock.running = true
        clock.pendingStart = true
        clock.rate = rate * songRate / outputRate
        clock.latencyFrames = latency
        clock.startSongFrame = Double(songFrame)
        clock.spans.removeAll(keepingCapacity: true)
        cumScheduled = 0
        clickCursor = 0
        clickGen.add(1, ordering: .releasing)
        let seekLength = bypass ? 0 : stretcher.outputSeekLength(rate: rate)
        queueTarget = Int(StudyPlayerConstants.queueSeconds * outputRate * max(1, rate)) + seekLength
        topUpLocked()
        if !bypass {
            stretcher.reset()
            stretcher.setTranspose(cents: c)
            appliedCents = c
            var l = [Float](repeating: 0, count: seekLength), r = l
            l.withUnsafeMutableBufferPointer { lp in
                r.withUnsafeMutableBufferPointer { rp in
                    mix(seekLength, into: lp.baseAddress!, rp.baseAddress!)
                    stretcher.outputSeek(left: lp.baseAddress!, right: rp.baseAddress!, count: seekLength)
                }
            }
            topUpLocked()
        }
        cents.store(c)
        anchorSong.store(Double(songFrame) / songRate)
        anchorRate.store(rate)
        anchorLatency.store(latency)
        runStarted.store(false, ordering: .sequentiallyConsistent)
        anchorRunning.store(true, ordering: .sequentiallyConsistent)
        active.store(true, ordering: .sequentiallyConsistent)
        return generation
    }

    /// Para el render (espera al bloque en curso) y deja de programar.
    func stop() {
        deactivate()
        anchorRunning.store(false, ordering: .sequentiallyConsistent)
        readerLock.lock()
        runActive = false
        generation += 1
        clock.running = false
        readerLock.unlock()
    }

    /// Cambia el bucle para lo que aún no está programado (sin cortes, como en el Mac).
    func setLoop(_ loop: Range<Int64>?) {
        readerLock.lock()
        planner.loop = loop
        readerLock.unlock()
    }

    /// Última muestra del tema que se programa (exclusiva; como mucho `length`): tras ella los anillos se vacían, la
    /// salida es silencio y llega `onEnd`. En marcha vale para lo que aún no está programado.
    func setEnd(_ frames: Int64) {
        readerLock.lock()
        planner.length = min(max(0, frames), length)
        readerLock.unlock()
    }

    /// Clics del metrónomo (muestras del tema, ordenados). En marcha, los ya programados se rehacen desde lo que suena.
    func setClicks(_ clicks: [ClickFrame]) {
        readerLock.lock()
        defer { readerLock.unlock() }
        clock.clicks = clicks
        guard runActive else { return }
        clickGen.add(1, ordering: .releasing)
        let y = Double(renderedAtomic.load(ordering: .acquiring))
        let renderedCum = Int64(max(0, (y - clock.latencyFrames) * clock.rate).rounded(.up))
        clickCursor = min(cumScheduled, renderedCum)
        emitClicks()
    }

    func setMetronome(on: Bool, gain: Float) { clickGain.store(on ? gain : 0) }
    func setGain(_ i: Int, _ g: Float) { if i < gains.count { gains[i].store(g) } }
    func setMasterGain(_ g: Float) { master.store(g) }
    /// Tono en vivo (solo con Signalsmith activo; a velocidad 1 pasar de 0 a ≠ 0 pide nueva pasada).
    func setCents(_ c: Double) { cents.store(c) }

    func meter(_ i: Int) -> ChannelMeter {
        guard i < meterPeak.count else { return .silent }
        func db(_ x: Float) -> Float { x > 1e-6 ? 20 * log10(x) : -120 }
        return ChannelMeter(rmsDB: db(meterRMS[i].load()), peakDB: db(meterPeak[i].load()))
    }

    var underrunFrames: Int { underruns.load(ordering: .relaxed) }
    var usesStretch: Bool { readerLock.withLock { runActive && !bypass } }
    var modelLatencyFrames: Double { readerLock.withLock { clock.latencyFrames } }

    var renderStats: HostedRenderStats {
        HostedRenderStats(catchUps: catchUps.load(ordering: .relaxed), catchUpFrames: catchUpFrames.load(ordering: .relaxed),
                          failedPullFrames: 0, outputJumps: forwardJumps.load(ordering: .relaxed),
                          outputJumpMaxFrames: forwardJumpMax.load(ordering: .relaxed),
                          outputBackwardJumps: backwardJumps.load(ordering: .relaxed))
    }

    /// Estado del reloj con lo último que renderizó el hilo de E/S (para `currentTime` y los tests).
    func snapshot() -> ClockState {
        readerLock.lock()
        var c = clock
        readerLock.unlock()
        c.pendingStart = !runStarted.load(ordering: .acquiring)
        c.runStartFrame = Double(runStart.load(ordering: .relaxed))
        c.lastRenderStart = Double(lastStart.load(ordering: .relaxed))
        c.lastRenderFrames = Double(lastFrames.load(ordering: .relaxed))
        return c
    }

    /// Segundos de host del último bloque (0 = sin marca).
    var lastRenderHostSeconds: Double { lastHost.load() }

    /// Qué posición del tema suena en qué muestra de salida (línea de tiempo de quien llama a `render`). Sin cerrojos:
    /// lo lee la sesión en su hilo de E/S.
    var anchor: PlaybackAnchor? {
        guard anchorRunning.load(ordering: .sequentiallyConsistent), runStarted.load(ordering: .acquiring) else { return nil }
        return PlaybackAnchor(songTime: anchorSong.load(),
                              outputSample: Double(runStart.load(ordering: .relaxed)) + anchorLatency.load(),
                              sampleRate: outputRate, rate: anchorRate.load())
    }

    private func deactivate() {
        active.store(false, ordering: .sequentiallyConsistent)
        while busy.load(ordering: .sequentiallyConsistent) { Thread.sleep(forTimeInterval: 0.000_05) }
    }

    // MARK: Render (hilo de E/S)

    /// Escribe (sobrescribe) `n` muestras de la pasada en `l`/`r` (`nil` = se renderiza y se tira). `y` es la muestra del
    /// primer frame en la línea de tiempo de quien llama; el primer bloque activo fija el arranque. Si `y` salta hacia
    /// delante, se renderiza en vacío lo que falta (hasta 1 s) para que el ancla siga valiendo. Devuelve false parado
    /// (sin tocar `l`/`r`).
    @discardableResult
    func render(at y: Int64, frames n: Int, hostSeconds: Double,
                left l: UnsafeMutablePointer<Float>?, right r: UnsafeMutablePointer<Float>?) -> Bool {
        busy.store(true, ordering: .sequentiallyConsistent)
        defer { busy.store(false, ordering: .sequentiallyConsistent) }
        guard active.load(ordering: .sequentiallyConsistent) else { return false }
        if !runStarted.load(ordering: .relaxed) {
            runStart.store(y, ordering: .relaxed)
            runStarted.store(true, ordering: .releasing)
        } else {
            let expected = runStart.load(ordering: .relaxed) + rendered
            if y > expected {
                let gap = y - expected
                forwardJumps.add(1, ordering: .relaxed)
                if Int(gap) > forwardJumpMax.load(ordering: .relaxed) { forwardJumpMax.store(Int(gap), ordering: .relaxed) }
                let c = min(gap, Int64(PortablePlaybackConstants.maxCatchUpSeconds * outputRate))
                catchUps.add(1, ordering: .relaxed)
                catchUpFrames.add(Int(c), ordering: .relaxed)
                var left = Int(c)
                while left > 0 {
                    let k = min(maxBlock, left)
                    renderBlock(k)
                    left -= k
                }
                if gap > c { runStart.store(runStart.load(ordering: .relaxed) + gap - c, ordering: .relaxed) }
            } else if y < expected {
                backwardJumps.add(1, ordering: .relaxed)
                runStart.store(runStart.load(ordering: .relaxed) - (expected - y), ordering: .relaxed)
            }
        }
        var done = 0
        while done < n {
            let k = min(maxBlock, n - done)
            renderBlock(k)
            if let l, l == r {
                // Backing mono (M-3d): mismo puntero para L y R = suma a mono.
                BackingMono.mix(left: outL, right: outR, into: l + done, count: k)
            } else {
                if let l { (l + done).update(from: outL, count: k) }
                if let r { (r + done).update(from: outR, count: k) }
            }
            done += k
        }
        lastStart.store(y, ordering: .relaxed)
        lastFrames.store(n, ordering: .relaxed)
        lastHost.store(hostSeconds)
        renderedAtomic.store(rendered, ordering: .releasing)
        return true
    }

    private func renderBlock(_ k: Int) {
        if bypass {
            mix(k, into: outL, outR)
        } else {
            let c = cents.load()
            if c != appliedCents {
                stretcher.setTranspose(cents: c)
                appliedCents = c
            }
            let need = Int((Double(rendered + Int64(k)) * stretchRate).rounded(.down))
                - Int((Double(rendered) * stretchRate).rounded(.down))
            mix(need, into: subL, subR)
            stretcher.process(left: subL, right: subR, count: need, outLeft: outL, outRight: outR, outCount: k)
        }
        renderClicks(k)
        var g = master.load()
        if g != 1 {
            DSP.vsmul(outL, 1, &g, outL, 1, DSPLength(k))
            DSP.vsmul(outR, 1, &g, outR, 1, DSPLength(k))
        }
        if fadeLeft > 0 {
            let m = min(k, fadeLeft)
            for j in 0..<m {
                let w = Crossfade.weight(declickFrames - fadeLeft + j, declickFrames)
                outL[j] = outL[j] * w + fadeFromL * (1 - w)
                outR[j] = outR[j] * w + fadeFromR * (1 - w)
            }
            fadeLeft -= m
        }
        lastL = outL[k - 1]
        lastR = outR[k - 1]
        rendered += Int64(k)
    }

    /// Suma `m` muestras de todos los stems (con su ganancia) en `a`/`b`, por trozos del tamaño de la memoria de trabajo.
    private func mix(_ m: Int, into a: UnsafeMutablePointer<Float>, _ b: UnsafeMutablePointer<Float>) {
        a.update(repeating: 0, count: m)
        b.update(repeating: 0, count: m)
        let ended = sourceEnded.load(ordering: .acquiring)
        var done = 0
        while done < m {
            let k = min(scratchFrames, m - done)
            for i in 0..<stemCount {
                let ring = rings[i]
                if owed[i] > 0 { owed[i] -= ring.skip(owed[i]) }
                let got = ring.read(into: tmpL, tmpR, count: k)
                if got < k {
                    (tmpL + got).update(repeating: 0, count: k - got)
                    (tmpR + got).update(repeating: 0, count: k - got)
                    if !ended {
                        underruns.add(k - got, ordering: .relaxed)
                        owed[i] += k - got
                    }
                }
                var g = gains[i].load()
                if g != 1 {
                    DSP.vsmul(tmpL, 1, &g, tmpL, 1, DSPLength(k))
                    DSP.vsmul(tmpR, 1, &g, tmpR, 1, DSPLength(k))
                }
                var pl: Float = 0, pr: Float = 0, ml: Float = 0, mr: Float = 0
                DSP.maxmgv(tmpL, 1, &pl, DSPLength(k))
                DSP.maxmgv(tmpR, 1, &pr, DSPLength(k))
                DSP.measqv(tmpL, 1, &ml, DSPLength(k))
                DSP.measqv(tmpR, 1, &mr, DSPLength(k))
                meterPeak[i].store(max(pl, pr))
                meterRMS[i].store(sqrt((ml + mr) / 2))
                DSP.vadd(tmpL, 1, a + done, 1, a + done, 1, DSPLength(k))
                DSP.vadd(tmpR, 1, b + done, 1, b + done, 1, DSPLength(k))
            }
            done += k
        }
    }

    /// Clics que empiezan en el bloque (o antes y aún suenan), desde el anillo de eventos que llena el lector.
    private func renderClicks(_ n: Int) {
        let rel = rendered
        let len = Int64(normalClick.count)
        let gen = clickGen.load(ordering: .acquiring)
        while let e = events.peek() {
            if e.gen != gen { events.pop(); continue }
            if e.start >= rel + Int64(n) { break }
            events.pop()
            if e.start + len <= rel { continue }
            if voiceCount < PortablePlaybackConstants.maxClickVoices {
                voiceStart[voiceCount] = e.start
                voiceAccent[voiceCount] = e.accent
                voiceCount += 1
            }
        }
        var g = clickGain.load()
        var v = 0
        while v < voiceCount {
            let start = Int(voiceStart[v] - rel)
            if g > 0 {
                let t = voiceAccent[v] ? accentClick : normalClick
                let i0 = max(0, start), i1 = min(n, start + t.count)
                if i1 > i0 {
                    t.withUnsafeBufferPointer { tp in
                        let src = tp.baseAddress! + (i0 - start)
                        DSP.vsma(src, 1, &g, outL + i0, 1, outL + i0, 1, DSPLength(i1 - i0))
                        DSP.vsma(src, 1, &g, outR + i0, 1, outR + i0, 1, DSPLength(i1 - i0))
                    }
                }
            }
            if voiceStart[v] + len <= rel + Int64(n) {
                voiceCount -= 1
                voiceStart[v] = voiceStart[voiceCount]
                voiceAccent[v] = voiceAccent[voiceCount]
            } else {
                v += 1
            }
        }
    }

    // MARK: Lector

    /// Rellena la cola ya (offline: tras cada bloque; en tiempo real lo hace el hilo lector).
    func topUp() {
        readerLock.lock()
        topUpLocked()
        readerLock.unlock()
    }

    private func startReaderThread() {
        let t = Thread { [weak self] in
            while Self.readerTick(self) { Thread.sleep(forTimeInterval: PortablePlaybackConstants.readerIntervalSeconds) }
        }
        t.name = "ToneForge.PortablePlayback.reader"
        t.qualityOfService = .userInteractive
        t.start()
    }

    private static func readerTick(_ engine: PortablePlaybackEngine?) -> Bool {
        guard let engine, engine.alive.load(ordering: .relaxed) else { return false }
        engine.topUp()
        return true
    }

    private func minReadable() -> Int { rings.reduce(Int.max) { min($0, $1.readable) } }

    private func topUpLocked() {
        guard runActive, !closed else { return }
        while minReadable() < queueTarget {
            guard rings.allSatisfy({ $0.writable >= maxPieceRingFrames }) else { break }
            guard let piece = planner.next() else {
                finishSource()
                break
            }
            switch piece {
            case let .body(s, n):
                for i in 0..<stemCount { writeBody(i, songStart: s, frames: Int(n)) }
            case let .crossfade(from, to):
                for i in 0..<stemCount { writeCrossfade(i, from: from, to: to) }
            }
            let spans = planner.spans(of: piece, at: cumScheduled)
            clock.spans.append(contentsOf: spans)
            cumScheduled += spans.reduce(0) { $0 + $1.length }
            emitClicks()
        }
        if sourceEnded.load(ordering: .relaxed), !endReported, rings.allSatisfy({ $0.readable == 0 }) {
            endReported = true
            onEnd(generation)
        }
        // Historia de tramos (para `currentTime` y los clics recientes), como `StemScheduler`.
        let y = Double(renderedAtomic.load(ordering: .acquiring))
        let k = (y - StudyPlayerConstants.historySeconds * outputRate - clock.latencyFrames) * clock.rate
        if let n = clock.spans.firstIndex(where: { Double($0.cumEnd) > k }), n > 0 { clock.spans.removeFirst(n) }
    }

    private func finishSource() {
        if !flushed {
            flushed = true
            for i in 0..<stemCount {
                guard let rs = resamplers[i] else { continue }
                push(i, rs.flush())
            }
        }
        sourceEnded.store(true, ordering: .releasing)
    }

    private func writeBody(_ i: Int, songStart s: Int64, frames n: Int) {
        readL.withUnsafeMutableBufferPointer { lp in
            readR.withUnsafeMutableBufferPointer { rp in
                sources[i].read(songStart: s, frames: n, left: lp.baseAddress!, right: rp.baseAddress!)
                push(i, lp.baseAddress!, rp.baseAddress!, n)
            }
        }
    }

    /// Fundido cruzado del bucle: sale `[from, from + 2h)` y entra `[to − h, to + h)` con `Crossfade.weight`.
    private func writeCrossfade(_ i: Int, from: Int64, to: Int64) {
        let n = Int(2 * halfFade)
        readL.withUnsafeMutableBufferPointer { lp in
            readR.withUnsafeMutableBufferPointer { rp in
                fadeL.withUnsafeMutableBufferPointer { fl in
                    fadeR.withUnsafeMutableBufferPointer { fr in
                        let a = lp.baseAddress!, b = rp.baseAddress!, c = fl.baseAddress!, d = fr.baseAddress!
                        sources[i].read(songStart: from, frames: n, left: a, right: b)
                        sources[i].read(songStart: to - halfFade, frames: n, left: c, right: d)
                        for j in 0..<n {
                            let w = Crossfade.weight(j, n)
                            a[j] = a[j] * (1 - w) + c[j] * w
                            b[j] = b[j] * (1 - w) + d[j] * w
                        }
                        push(i, a, b, n)
                    }
                }
            }
        }
    }

    private func push(_ i: Int, _ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int) {
        if let rs = resamplers[i] {
            push(i, rs.process([Array(UnsafeBufferPointer(start: l, count: n)), Array(UnsafeBufferPointer(start: r, count: n))]))
        } else {
            rings[i].write(left: l, right: r, count: n)
        }
    }

    private func push(_ i: Int, _ channels: [[Float]]) {
        guard channels.count == 2, !channels[0].isEmpty else { return }
        channels[0].withUnsafeBufferPointer { l in
            channels[1].withUnsafeBufferPointer { r in
                rings[i].write(left: l.baseAddress!, right: r.baseAddress!, count: min(l.count, r.count))
            }
        }
    }

    /// Clics de los tramos programados desde `clickCursor` → muestra de salida relativa al arranque, al anillo.
    private func emitClicks() {
        defer { clickCursor = cumScheduled }
        let clicks = clock.clicks
        guard !clicks.isEmpty, clickCursor < cumScheduled else { return }
        let gen = clickGen.load(ordering: .relaxed)
        for span in clock.spans where span.cumEnd > clickCursor && span.cumStart < cumScheduled {
            let c = Double(span.cumStart), s = Double(span.songStart)
            let lowSong = s + Double(max(0, clickCursor - span.cumStart))
            let highSong = s + Double(min(span.length, cumScheduled - span.cumStart))
            var lo = 0, hi = clicks.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if clicks[mid].songFrame < lowSong { lo = mid + 1 } else { hi = mid }
            }
            var i = lo
            while i < clicks.count, clicks[i].songFrame < highSong {
                let y = clock.latencyFrames + (c + clicks[i].songFrame - s) / clock.rate
                events.push(start: Int64(y.rounded()), accent: clicks[i].accent, gen: gen)
                i += 1
            }
        }
    }
}

/// El motor portátil alojado en una `AudioSession` (`HostedPlayback`): el render de la sesión pide las muestras en su
/// línea de tiempo, así que el ancla ya está en ella. Offline (tests), rellena la cola tras cada bloque.
final class PortableHostedRenderer: HostedPlayback, @unchecked Sendable {
    let engine: PortablePlaybackEngine
    let presentationLatencyFrames: Double

    init(engine: PortablePlaybackEngine, presentationLatencyFrames: Double) {
        self.engine = engine
        self.presentationLatencyFrames = presentationLatencyFrames
    }

    var anchor: PlaybackAnchor? { engine.anchor }

    func render(into buffer: AudioIOBuffer, left l: Int, right r: Int) {
        let lp = l >= 0 && l < buffer.channelCount ? buffer[l].baseAddress : nil
        let rp = r >= 0 && r < buffer.channelCount ? buffer[r].baseAddress : nil
        engine.render(at: buffer.sampleTime, frames: buffer.frameCount, hostSeconds: buffer.hostSeconds, left: lp, right: rp)
        if !engine.realtime { engine.topUp() }
    }
}
