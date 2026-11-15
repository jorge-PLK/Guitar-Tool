import AVFoundation
import CoreAudio
import Foundation
import Synchronization

/// Sesión dúplex real sobre el HAL (mini-spec Fase 3, «Dispositivo y canales» y «Código»).
///
/// - **Mismo dispositivo** en entrada y salida: se abre tal cual (`clock == .single`).
/// - **Dispositivos distintos:** al arrancar se crea un dispositivo agregado privado (no aparece en el
///   sistema ni en `CoreAudioDeviceProvider`) con la salida como subdispositivo principal y reloj, y
///   corrección de deriva en la entrada (`clock == .aggregate`). Se destruye en `stop` y en `deinit`; los que
///   queden de una ejecución anterior (UID con `aggregateUIDPrefix`) se borran al crear el siguiente.
///
/// **Línea de tiempo.** `sampleTime` de cada bloque sale de las marcas del HAL, no de contar llamadas: la
/// salida lleva `inOutputTime.mSampleTime` y la entrada `inInputTime.mSampleTime`, las dos en el reloj del
/// dispositivo (o del agregado). Así `n − y` (muestra de entrada menos muestra de salida) es la latencia
/// física desde el búfer de salida del HAL hasta el de entrada, como en `SimulatedAudioIO`, y los búferes
/// del IOProc no cuentan. Por eso `declaredLatencySamples` es solo la suma de latencias declaradas
/// (dispositivo + margen de seguridad + stream, de entrada y de salida), sin los dos búferes que sumaba P2
/// (que contaba llamadas).
///
/// Huecos: si el HAL salta muestras (sobrecarga), los bloques llegan con su `sampleTime` real y el hueco se
/// cuenta en `discontinuities`; quien grabe rellena de silencio y no pierde la alineación.
///
/// Tiempo real: el IOProc no bloquea ni reserva memoria (todo preasignado). Los manejadores tampoco deben:
/// `AudioSession` pone un `CaptureRing` delante de la captura.
public final class CoreAudioIO: AudioIO, @unchecked Sendable {
    /// Prefijo del UID de los agregados privados que crea la app (lo único por lo que se reconocen).
    public static let aggregateUIDPrefix = "com.toneforge.private-aggregate."
    /// Bloque máximo que se admite por llamada (el pedido es `bufferFrames`).
    static let maxFrames = 8_192

    public let format: AudioIOFormat
    public let inputDeviceUID: String
    public let outputDeviceUID: String
    public let clock: AudioIOClock
    public let declaredLatencySamples: Double

    private let inputID: AudioDeviceID
    private let outputID: AudioDeviceID
    private let lock = NSLock()
    private var ioDevice: AudioDeviceID = 0
    private var aggregateID: AudioDeviceID?
    private var procID: AudioDeviceIOProcID?
    private var running = false
    private var interruptionHandler: (@Sendable (AudioIOInterruption) -> Void)?
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private let listenerQueue = DispatchQueue(label: "ToneForge.CoreAudioIO.listeners")

    private let counters = IOCounters()
    private let hostLog = HostTimeLog()
    /// Consultas periódicas de las latencias declaradas (en `listenerQueue`, nunca en el hilo de E/S).
    private var latencyTimer: DispatchSourceTimer?
    private var latencyLog: [DeclaredLatencySnapshot] = []
    /// Cada cuánto se vuelven a pedir las latencias declaradas, en segundos.
    static let latencyPollSeconds = 1.0

    /// Abre (sin arrancar) una sesión entre `inputUID` y `outputUID` a `sampleRate`. Pide la frecuencia a los
    /// dos dispositivos; si alguno no queda a ella, `AudioIOError.sampleRateMismatch` con la que tiene.
    public init(inputUID: String, outputUID: String, sampleRate: Double, bufferFrames: Int = 512) throws {
        guard let inID = HAL.deviceID(uid: inputUID), HAL.isAlive(inID) else { throw AudioIOError.notConnected(inputUID) }
        guard let outID = HAL.deviceID(uid: outputUID), HAL.isAlive(outID) else { throw AudioIOError.notConnected(outputUID) }
        let inChannels = HAL.channelCount(inID, kAudioObjectPropertyScopeInput)
        let outChannels = HAL.channelCount(outID, kAudioObjectPropertyScopeOutput)
        guard inChannels > 0 else { throw AudioIOError.noInput }
        guard outChannels > 0 else { throw AudioIOError.device("\(outputUID) no tiene salidas") }
        for id in Set([inID, outID]) where !HAL.setNominalSampleRate(id, sampleRate) {
            throw AudioIOError.sampleRateMismatch(device: HAL.nominalSampleRate(id) ?? 0, requested: sampleRate)
        }
        inputID = inID
        outputID = outID
        inputDeviceUID = inputUID
        outputDeviceUID = outputUID
        clock = inID == outID ? .single : .aggregate
        format = AudioIOFormat(sampleRate: sampleRate, inputChannels: inChannels, outputChannels: outChannels,
                               bufferFrames: bufferFrames)
        declaredLatencySamples = Double(HAL.declaredLatency(inID, kAudioObjectPropertyScopeInput)
                                        + HAL.declaredLatency(outID, kAudioObjectPropertyScopeOutput))
    }

    deinit { stop() }

    public var isRunning: Bool { lock.withLock { running } }
    /// Avisos de sobrecarga del HAL desde el último `start`.
    public var overloads: Int { counters.overloads.load(ordering: .relaxed) }
    /// Saltos en la línea de tiempo de salida desde el último `start`.
    public var discontinuities: Int { counters.gaps.load(ordering: .relaxed) }
    public var callbacks: Int { counters.callbacks.load(ordering: .relaxed) }
    /// Contadores del ciclo de E/S desde el último `start` (para `tf-audio verify`).
    public var diagnostics: AudioIODiagnostics? { counters.diagnostics }

    /// Marcas de host de cada ciclo desde el último `start` (las últimas 2^16), por segundo y con sus escalones,
    /// junto con las latencias declaradas consultadas cada `latencyPollSeconds`.
    public func hostTimingReport() -> HostTimingReport {
        let raw = hostLog.snapshot()
        let cycles = raw.compactMap { r -> HostTimingCycle? in
            guard !r.outSample.isNaN else { return nil }
            return HostTimingCycle(inputSampleTime: r.inSample, outputSampleTime: r.outSample,
                                   inputHostSeconds: HostTimeLog.seconds(r.inHost), outputHostSeconds: HostTimeLog.seconds(r.outHost),
                                   inputRateScalar: r.inRate, outputRateScalar: r.outRate)
        }
        let lats = lock.withLock { latencyLog }
        return HostTimingAnalysis.analyze(cycles: cycles, latencies: lats, sampleRate: format.sampleRate)
    }

    /// Hora de host ahora, en la misma escala que `HostTimingSecond.hostSeconds`.
    public static var hostNowSeconds: Double { HostTimeLog.seconds(mach_absolute_time()) }

    public func setInterruptionHandler(_ handler: (@Sendable (AudioIOInterruption) -> Void)?) {
        lock.withLock { interruptionHandler = handler }
    }

    // MARK: Arranque y parada

    public func start(render: @escaping AudioIORenderHandler, capture: @escaping AudioIOCaptureHandler) throws {
        try lock.withLock {
            guard !running else { throw AudioIOError.alreadyRunning }
            let device: AudioDeviceID
            var inOffset = 0, outOffset = 0
            if clock == .single {
                device = inputID
            } else {
                Self.removeOrphanAggregates()
                device = try Self.createAggregate(outputUID: outputDeviceUID, inputUID: inputDeviceUID,
                                                  expectedInputs: format.inputChannels, expectedOutputs: format.outputChannels)
                aggregateID = device
                // Canales del agregado: los del subdispositivo principal (salida) primero, luego los de la entrada.
                inOffset = HAL.channelCount(outputID, kAudioObjectPropertyScopeInput)
                outOffset = 0
            }
            HAL.set(device, kAudioDevicePropertyBufferFrameSize, UInt32(format.bufferFrames))
            let proc = IOProcState(inLayout: HAL.bufferLayout(device, kAudioObjectPropertyScopeInput), inOffset: inOffset,
                                   inChannels: format.inputChannels,
                                   outLayout: HAL.bufferLayout(device, kAudioObjectPropertyScopeOutput), outOffset: outOffset,
                                   outChannels: format.outputChannels, render: render, capture: capture,
                                   counters: counters, hostLog: hostLog)
            counters.reset()
            hostLog.reset()
            latencyLog.removeAll()
            var id: AudioDeviceIOProcID?
            // Cola nil: el bloque corre en el hilo de E/S del HAL, sin saltos de cola.
            var status = AudioDeviceCreateIOProcIDWithBlock(&id, device, nil) { _, inData, inTime, outData, outTime in
                proc.run(inData, inTime, outData, outTime)
            }
            guard status == noErr, let id else {
                destroyAggregateLocked()
                throw AudioIOError.device("AudioDeviceCreateIOProcIDWithBlock (OSStatus \(status))")
            }
            status = AudioDeviceStart(device, id)
            guard status == noErr else {
                AudioDeviceDestroyIOProcID(device, id)
                destroyAggregateLocked()
                throw AudioIOError.device("AudioDeviceStart (OSStatus \(status))")
            }
            ioDevice = device
            procID = id
            running = true
            installListenersLocked()
            startLatencyPollLocked()
        }
    }

    private func startLatencyPollLocked() {
        let inID = inputID, outID = outputID
        let timer = DispatchSource.makeTimerSource(queue: listenerQueue)
        timer.schedule(deadline: .now(), repeating: Self.latencyPollSeconds)
        timer.setEventHandler { [weak self] in
            let i = HAL.latencyParts(inID, kAudioObjectPropertyScopeInput)
            let o = HAL.latencyParts(outID, kAudioObjectPropertyScopeOutput)
            let s = DeclaredLatencySnapshot(hostSeconds: Self.hostNowSeconds, inputDevice: i.device, inputSafety: i.safety,
                                            inputStream: i.stream, outputDevice: o.device, outputSafety: o.safety,
                                            outputStream: o.stream)
            guard let self else { return }
            self.lock.withLock { if self.running { self.latencyLog.append(s) } }
        }
        timer.resume()
        latencyTimer = timer
    }

    public func stop() {
        lock.withLock { stopLocked() }
    }

    private func stopLocked() {
        guard running else { return }
        running = false
        latencyTimer?.cancel()
        latencyTimer = nil
        removeListenersLocked()
        if let id = procID {
            // Fuera del hilo de E/S, AudioDeviceStop vuelve cuando el IOProc ya no se llama.
            AudioDeviceStop(ioDevice, id)
            AudioDeviceDestroyIOProcID(ioDevice, id)
        }
        procID = nil
        destroyAggregateLocked()
    }

    private func destroyAggregateLocked() {
        if let a = aggregateID { AudioHardwareDestroyAggregateDevice(a) }
        aggregateID = nil
    }

    // MARK: Avisos del HAL

    private func installListenersLocked() {
        func listen(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ body: @escaping @Sendable () -> Void) {
            var a = HAL.addr(sel)
            let block: AudioObjectPropertyListenerBlock = { _, _ in body() }
            if AudioObjectAddPropertyListenerBlock(obj, &a, listenerQueue, block) == noErr {
                listeners.append((obj, a, block))
            }
        }
        let rate = format.sampleRate
        for (id, uid) in [(inputID, inputDeviceUID), (outputID, outputDeviceUID)] {
            listen(id, kAudioDevicePropertyDeviceIsAlive) { [weak self] in
                if !HAL.isAlive(id) { self?.interrupt(.disconnected(uid)) }
            }
            listen(id, kAudioDevicePropertyNominalSampleRate) { [weak self] in
                if let r = HAL.nominalSampleRate(id), abs(r - rate) >= 0.5 { self?.interrupt(.sampleRateChanged(r)) }
            }
        }
        // La lista de dispositivos cambia también cuando se desenchufa sin aviso de «vivo».
        listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices) { [weak self] in
            guard let self else { return }
            for (id, uid) in [(self.inputID, self.inputDeviceUID), (self.outputID, self.outputDeviceUID)]
            where HAL.deviceID(uid: uid) != id || !HAL.isAlive(id) {
                self.interrupt(.disconnected(uid))
                return
            }
        }
        let counters = self.counters
        listen(ioDevice, kAudioDeviceProcessorOverload) { counters.overloads.add(1, ordering: .relaxed) }
    }

    private func removeListenersLocked() {
        for (obj, a, block) in listeners {
            var addr = a
            AudioObjectRemovePropertyListenerBlock(obj, &addr, listenerQueue, block)
        }
        listeners.removeAll()
    }

    private func interrupt(_ reason: AudioIOInterruption) {
        let handler = lock.withLock { () -> (@Sendable (AudioIOInterruption) -> Void)? in
            guard running else { return nil }
            stopLocked()
            return interruptionHandler
        }
        handler?(reason)
    }

    // MARK: Agregado privado

    /// Borra los agregados que llevan el prefijo propio (de una sesión que no se cerró). Devuelve cuántos.
    @discardableResult
    public static func removeOrphanAggregates() -> Int {
        var n = 0
        for id in HAL.allDevices() {
            guard let uid = HAL.string(id, kAudioDevicePropertyDeviceUID), uid.hasPrefix(aggregateUIDPrefix) else { continue }
            if AudioHardwareDestroyAggregateDevice(id) == noErr { n += 1 }
        }
        return n
    }

    private static func createAggregate(outputUID: String, inputUID: String, expectedInputs: Int,
                                        expectedOutputs: Int) throws -> AudioDeviceID {
        let uid = aggregateUIDPrefix + UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "ToneForge",
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceClockDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID, kAudioSubDeviceDriftCompensationKey: 0],
                [kAudioSubDeviceUIDKey: inputUID, kAudioSubDeviceDriftCompensationKey: 1]
            ]
        ]
        var id = AudioDeviceID(0)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
        guard status == noErr, id != 0 else { throw AudioIOError.device("AudioHardwareCreateAggregateDevice (OSStatus \(status))") }
        // El agregado tarda en publicar sus streams.
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if HAL.channelCount(id, kAudioObjectPropertyScopeInput) >= expectedInputs,
               HAL.channelCount(id, kAudioObjectPropertyScopeOutput) >= expectedOutputs { return id }
            Thread.sleep(forTimeInterval: 0.02)
        }
        AudioHardwareDestroyAggregateDevice(id)
        throw AudioIOError.device("el agregado privado no publicó sus canales")
    }

    // MARK: Permiso

    /// Permiso de entrada de audio (sin él el HAL entrega ceros). Pregunta si aún no se decidió.
    public static func ensureInputPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}

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

    /// Segundos de host de `mach_absolute_time`.
    static func seconds(_ ticks: UInt64) -> Double {
        guard ticks > 0 else { return 0 }
        return Double(ticks) * timebase / 1e9
    }

    static let timebase: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(max(1, tb.denom))
    }()
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

    func reset() {
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
                                  outMinusInMax: hi == .min ? nil : hi, callbacks: callbacks.load(ordering: .relaxed))
    }
}

/// Estado del IOProc: todo preasignado. Solo lo toca el hilo de E/S (salvo los contadores atómicos).
private final class IOProcState: @unchecked Sendable {
    typealias Slot = (buf: Int, off: Int, stride: Int)
    /// Por canal de la sesión: búfer del HAL, posición dentro y canales del búfer.
    private let inMap: [Slot]
    private let outMap: [Slot]
    private let inData: [UnsafeMutablePointer<Float>]
    private let outData: [UnsafeMutablePointer<Float>]
    private let inPointers: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>>
    private let outPointers: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>>
    private let render: AudioIORenderHandler
    private let capture: AudioIOCaptureHandler
    private let counters: IOCounters
    private let hostLog: HostTimeLog
    private var expectedOut: Double = .nan
    private var expectedIn: Double = .nan

    init(inLayout: [Int], inOffset: Int, inChannels: Int, outLayout: [Int], outOffset: Int, outChannels: Int,
         render: @escaping AudioIORenderHandler, capture: @escaping AudioIOCaptureHandler, counters: IOCounters,
         hostLog: HostTimeLog) {
        self.hostLog = hostLog
        func map(_ layout: [Int], _ offset: Int, _ count: Int) -> [Slot] {
            var all: [Slot] = []
            for (b, n) in layout.enumerated() { for c in 0..<n { all.append((b, c, n)) } }
            return (0..<count).map { offset + $0 < all.count ? all[offset + $0] : (-1, 0, 1) }
        }
        inMap = map(inLayout, inOffset, inChannels)
        outMap = map(outLayout, outOffset, outChannels)
        let n = CoreAudioIO.maxFrames
        inData = (0..<inChannels).map { _ in .allocate(capacity: n) }
        outData = (0..<outChannels).map { _ in .allocate(capacity: n) }
        inPointers = .allocate(capacity: max(1, inChannels))
        outPointers = .allocate(capacity: max(1, outChannels))
        _ = inPointers.initialize(from: inData)
        _ = outPointers.initialize(from: outData)
        self.render = render
        self.capture = capture
        self.counters = counters
    }

    deinit {
        inData.forEach { $0.deallocate() }
        outData.forEach { $0.deallocate() }
        inPointers.deallocate()
        outPointers.deallocate()
    }

    private static func frames(_ list: UnsafeMutableAudioBufferListPointer) -> Int {
        guard let b = list.first, b.mNumberChannels > 0 else { return 0 }
        return Int(b.mDataByteSize) / (MemoryLayout<Float>.size * Int(b.mNumberChannels))
    }

    func run(_ inData: UnsafePointer<AudioBufferList>, _ inTime: UnsafePointer<AudioTimeStamp>,
             _ outList: UnsafeMutablePointer<AudioBufferList>, _ outTime: UnsafePointer<AudioTimeStamp>) {
        counters.callbacks.add(1, ordering: .relaxed)
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
        let outs = UnsafeMutableAudioBufferListPointer(outList)
        for b in outs { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }

        // Entrada: de entrelazado a canales, con la marca de tiempo de entrada del HAL.
        let nIn = min(Self.frames(ins), CoreAudioIO.maxFrames)
        if nIn > 0, !inMap.isEmpty, inTime.pointee.mFlags.contains(.sampleTimeValid) {
            for (c, s) in inMap.enumerated() {
                let dst = self.inData[c]
                guard s.buf >= 0, s.buf < ins.count, let raw = ins[s.buf].mData else {
                    dst.update(repeating: 0, count: nIn)
                    continue
                }
                let src = raw.assumingMemoryBound(to: Float.self)
                for i in 0..<nIn { dst[i] = src[i * s.stride + s.off] }
            }
            let x = inTime.pointee.mSampleTime
            let it = inTime.pointee, ot = outTime.pointee
            hostLog.append(HostTimeLog.Raw(
                inSample: x, outSample: ot.mFlags.contains(.sampleTimeValid) ? ot.mSampleTime : .nan,
                inHost: it.mFlags.contains(.hostTimeValid) ? it.mHostTime : 0,
                outHost: ot.mFlags.contains(.hostTimeValid) ? ot.mHostTime : 0,
                inRate: it.mFlags.contains(.rateScalarValid) ? it.mRateScalar : 0,
                outRate: ot.mFlags.contains(.rateScalarValid) ? ot.mRateScalar : 0))
            if !expectedIn.isNaN, abs(x - expectedIn) > 0.5 {
                counters.inGaps.add(1, ordering: .relaxed)
                IOCounters.raise(counters.inGapMax, Int(abs(x - expectedIn).rounded()))
            }
            expectedIn = x + Double(nIn)
            if outTime.pointee.mFlags.contains(.sampleTimeValid) {
                let skew = Int((outTime.pointee.mSampleTime - x).rounded())
                IOCounters.lower(counters.skewMin, skew)
                IOCounters.raise(counters.skewMax, skew)
            }
            capture(AudioIOBuffer(sampleTime: Int64(inTime.pointee.mSampleTime.rounded()), frameCount: nIn,
                                  channels: UnsafeBufferPointer(inPointers)))
        }

        // Salida: el manejador escribe por canales, con la marca de tiempo de salida del HAL.
        let nOut = min(Self.frames(outs), CoreAudioIO.maxFrames)
        guard nOut > 0, !outMap.isEmpty, outTime.pointee.mFlags.contains(.sampleTimeValid) else { return }
        let y = outTime.pointee.mSampleTime
        if !expectedOut.isNaN, abs(y - expectedOut) > 0.5 {
            counters.gaps.add(1, ordering: .relaxed)
            IOCounters.raise(counters.gapMax, Int(abs(y - expectedOut).rounded()))
        }
        expectedOut = y + Double(nOut)
        for p in outData { p.update(repeating: 0, count: nOut) }
        render(AudioIOBuffer(sampleTime: Int64(y.rounded()), frameCount: nOut, channels: UnsafeBufferPointer(outPointers)))
        for (c, s) in outMap.enumerated() {
            guard s.buf >= 0, s.buf < outs.count, let raw = outs[s.buf].mData else { continue }
            let dst = raw.assumingMemoryBound(to: Float.self)
            let src = outData[c]
            for i in 0..<nOut { dst[i * s.stride + s.off] = src[i] }
        }
    }
}
