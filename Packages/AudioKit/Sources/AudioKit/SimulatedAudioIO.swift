import NativeDSP
import Foundation

/// Copia retrasada que llega después de la primera (eco del bucle o repetición de un delay del rig).
public struct SimulatedEcho: Sendable, Equatable {
    /// Retardo respecto a la primera llegada, en muestras con decimales.
    public var delaySamples: Double
    /// Ganancia respecto a la primera llegada (> 1 = eco más fuerte que ella).
    public var gain: Double

    public init(delaySamples: Double, gain: Double) {
        self.delaySamples = delaySamples
        self.gain = gain
    }
}

/// Tono continuo en la entrada: la oscilación sostenida de un bucle que realimenta (salida → cable → entrada
/// → rig → salida). Con la Flex Prime y el rig vacío se midió uno de 2793,8 Hz a 0,088 de pico (verify del 15/11).
public struct SimulatedTone: Sendable, Equatable {
    public var frequencyHz: Double
    /// Pico lineal (1 = fondo de escala).
    public var peak: Double

    public init(frequencyHz: Double, peak: Double) {
        self.frequencyHz = frequencyHz
        self.peak = peak
    }
}

/// Lo que llega por un canal de entrada del dispositivo simulado. Cadena: primera llegada + ecos →
/// saturación `tanh(drive·x)` (si `drive > 0`) → ganancia → tono → ruido → recorte del conversor a ±1.
public struct SimulatedInput: Sendable, Equatable {
    /// Canal de salida (desde 1) que entra por aquí, como un cable. `nil` = sin señal (solo ruido).
    public var source: Int?
    /// Retardo añadido a la latencia del dispositivo (p. ej. el del rig), en muestras con decimales.
    public var extraDelaySamples: Double
    public var echoes: [SimulatedEcho]
    /// Saturación tipo rig con ganancia; 0 = lineal.
    public var drive: Double
    /// Ganancia lineal tras la saturación.
    public var gain: Double
    /// Ruido blanco gaussiano, RMS en dBFS; `nil` = sin ruido.
    public var noiseDBFS: Double?
    /// Oscilación sostenida del bucle; `nil` = ninguna.
    public var tone: SimulatedTone?

    public init(source: Int?, extraDelaySamples: Double = 0, echoes: [SimulatedEcho] = [], drive: Double = 0,
                gain: Double = 1, noiseDBFS: Double? = nil, tone: SimulatedTone? = nil) {
        self.source = source
        self.extraDelaySamples = extraDelaySamples
        self.echoes = echoes
        self.drive = drive
        self.gain = gain
        self.noiseDBFS = noiseDBFS
        self.tone = tone
    }

    /// Ecos de un bucle que recircula: el k-ésimo llega `k·loopSamples` después con ganancia `loopGain^k`,
    /// hasta que cae por debajo de `floor`.
    public static func recirculating(loopSamples: Double, loopGain: Double, floor: Double = 0.02) -> [SimulatedEcho] {
        var out: [SimulatedEcho] = []
        var g = loopGain, k = 1.0
        while g >= floor && out.count < 64 {
            out.append(SimulatedEcho(delaySamples: k * loopSamples, gain: g))
            g *= loopGain
            k += 1
        }
        return out
    }
}

/// `AudioIO` simulado (mini-spec Fase 3, «Demostración sin hardware»): devuelve por la entrada lo que sale
/// por la salida con una latencia conocida con decimales (retardo fraccionario por sinc enventanado,
/// 64 coeficientes, Kaiser β 9, tabla de 4096 fases), deriva en ppm y latencia declarada distinta de la real.
///
/// Dos modos: `automatic == false` (por defecto) no corre solo: cada `pump()` hace un ciclo (salida y
/// luego entrada del mismo bloque) en el hilo que llama, lo que permite tocar el `StudyPlayer` en render
/// offline desde el manejador. Con `automatic == true`, `start` lanza un hilo que encadena ciclos lo más
/// rápido posible hasta `stop`.
public final class SimulatedAudioIO: AudioIO, @unchecked Sendable {
    public let format: AudioIOFormat
    public let inputDeviceUID: String
    public let outputDeviceUID: String
    public let clock: AudioIOClock
    public let declaredLatencySamples: Double
    /// Latencia real de ida y vuelta (de la muestra de salida a la de entrada), en muestras.
    public let latencySamples: Double
    /// Deriva del reloj de entrada frente al de salida, en ppm (positivo: la entrada corre más rápido).
    public let driftPPM: Double
    /// Reloj de host simulado (mini-spec Fase 6, «Cámara y sincronía»): segundos de host de la muestra de
    /// salida `initialSampleTime`.
    public let hostStartSeconds: Double
    /// Deriva del reloj del dispositivo (la línea de salida) frente al de host, en ppm (positivo: el
    /// dispositivo corre más rápido y da más muestras por segundo de host que su frecuencia nominal).
    public let hostDriftPPM: Double
    public let automatic: Bool
    /// Para simular una sesión WASAPI en la clave de calibración (F2): modo y contenedores. nil = como CoreAudio.
    public let wasapiIdentity: WASAPIIdentity?

    /// Capacidad del historial de salida: 2¹⁸ muestras (5,4 s a 48 kHz) de retardo máximo.
    private static let historyFrames = 1 << 18

    private let lock = NSLock()
    private var inputs: [SimulatedInput]
    private var noise: [SeededNoise]
    private var render: AudioIORenderHandler?
    private var capture: AudioIOCaptureHandler?
    private var running = false
    private var now: Int64
    private let origin: Int64
    private var history: [[Float]]
    private let outData: [UnsafeMutablePointer<Float>]
    private let inData: [UnsafeMutablePointer<Float>]
    private let outPointers: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>>
    private let inPointers: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>>
    private var worker: Thread?
    private let finished = DispatchSemaphore(value: 0)
    private static let maxBlock = 8_192

    public init(sampleRate: Double, outputChannels: Int = 2, inputs: [SimulatedInput], latencySamples: Double,
                declaredLatencySamples: Double, driftPPM: Double = 0, bufferFrames: Int = 512,
                inputDeviceUID: String = "sim-in", outputDeviceUID: String = "sim-out",
                clock: AudioIOClock = .single, initialSampleTime: Int64 = 0, seed: UInt64 = 1,
                automatic: Bool = false, hostStartSeconds: Double = SimulatedAudioIO.defaultHostStartSeconds,
                hostDriftPPM: Double = 0, wasapiIdentity: WASAPIIdentity? = nil) {
        self.wasapiIdentity = wasapiIdentity
        format = AudioIOFormat(sampleRate: sampleRate, inputChannels: inputs.count, outputChannels: outputChannels,
                               bufferFrames: bufferFrames)
        self.hostStartSeconds = hostStartSeconds
        self.hostDriftPPM = hostDriftPPM
        self.inputDeviceUID = inputDeviceUID
        self.outputDeviceUID = outputDeviceUID
        self.clock = clock
        self.declaredLatencySamples = declaredLatencySamples
        self.latencySamples = latencySamples
        self.driftPPM = driftPPM
        self.automatic = automatic
        self.inputs = inputs
        noise = inputs.indices.map { SeededNoise(seed: seed &* 1_000_003 &+ UInt64($0)) }
        now = initialSampleTime
        origin = initialSampleTime
        history = Array(repeating: [Float](repeating: 0, count: 2 * Self.historyFrames), count: outputChannels)
        outData = (0..<outputChannels).map { _ in .allocate(capacity: Self.maxBlock) }
        inData = inputs.indices.map { _ in .allocate(capacity: Self.maxBlock) }
        outPointers = .allocate(capacity: outputChannels)
        inPointers = .allocate(capacity: inputs.count)
        _ = outPointers.initialize(from: outData)
        _ = inPointers.initialize(from: inData)
        for i in inputs { Self.checkCausal(i, latencySamples) }
    }

    deinit {
        stop()
        outData.forEach { $0.deallocate() }
        inData.forEach { $0.deallocate() }
        outPointers.deallocate()
        inPointers.deallocate()
    }

    /// La muestra pedida debe estar ya escrita: retardo total ≥ semiancho del núcleo + 1.
    private static func checkCausal(_ input: SimulatedInput, _ latency: Double) {
        precondition(latency + input.extraDelaySamples >= Double(SignalMath.sincHalfWidth + 1),
                     "SimulatedAudioIO: retardo total menor que \(SignalMath.sincHalfWidth + 1) muestras")
    }

    /// Cambia lo que llega por el canal de entrada `channel` (desde 1), p. ej. el retardo del rig entre tomas.
    public func setInput(_ channel: Int, _ input: SimulatedInput) {
        Self.checkCausal(input, latencySamples)
        lock.withLock { inputs[channel - 1] = input }
    }

    public var isRunning: Bool { lock.withLock { running } }

    private var interruptionHandler: (@Sendable (AudioIOInterruption) -> Void)?

    public func setInterruptionHandler(_ handler: (@Sendable (AudioIOInterruption) -> Void)?) {
        lock.withLock { interruptionHandler = handler }
    }

    /// Simula que se desconecta el dispositivo de entrada: para la sesión y avisa, como `CoreAudioIO`.
    /// En modo manual, llamarlo entre dos `pump()`.
    public func disconnect() {
        stop()
        lock.withLock { interruptionHandler }?(.disconnected(inputDeviceUID))
    }

    /// Muestra de la línea común en la que empieza el próximo ciclo.
    public var sampleTime: Int64 { lock.withLock { now } }

    /// Hora de host inicial por defecto (un Mac encendido hace unos 17 min; decisión propia).
    public static let defaultHostStartSeconds = 1_000.0

    /// Muestras de salida por segundo de host (frecuencia nominal con la deriva frente al host).
    public var hostRate: Double { format.sampleRate * (1 + hostDriftPPM * 1e-6) }

    /// Ley exacta del reloj simulado: segundos de host en que sale la muestra `y` de la línea común. Es lo que
    /// llevan los bloques de salida en `hostSeconds`; los tests la usan como verdad.
    public func hostSeconds(atOutputSample y: Double) -> Double {
        hostStartSeconds + (y - Double(origin)) / hostRate
    }

    /// Inversa de `hostSeconds(atOutputSample:)`.
    public func outputSample(atHostSeconds h: Double) -> Double {
        Double(origin) + (h - hostStartSeconds) * hostRate
    }

    /// Segundos de host de la muestra de entrada `n`: el instante de la línea de salida que oye (con `driftPPM`).
    func hostSeconds(atInputSample n: Int64) -> Double {
        hostSeconds(atOutputSample: Double(origin) + Double(n - origin) / (1 + driftPPM * 1e-6))
    }

    public func start(render: @escaping AudioIORenderHandler, capture: @escaping AudioIOCaptureHandler) throws {
        try lock.withLock {
            guard !running else { throw AudioIOError.alreadyRunning }
            self.render = render
            self.capture = capture
            running = true
        }
        guard automatic else { return }
        let t = Thread { [weak self] in
            while let self, self.isRunning { self.pump() }
            self?.finished.signal()
        }
        worker = t
        t.start()
    }

    public func stop() {
        let wasAutomatic = lock.withLock { () -> Bool in
            guard running else { return false }
            running = false
            render = nil
            capture = nil
            return worker != nil
        }
        guard wasAutomatic else { return }
        if Thread.current != worker { finished.wait() }
        worker = nil
    }

    /// Un ciclo: pide `frames` muestras de salida, las pasa al historial y entrega la entrada del mismo
    /// bloque. Sin sesión abierta no hace nada.
    public func pump(frames: Int? = nil) {
        let n = min(frames ?? format.bufferFrames, Self.maxBlock)
        let state = lock.withLock { () -> (AudioIORenderHandler, AudioIOCaptureHandler, Int64, [SimulatedInput])? in
            guard running, let r = self.render, let c = self.capture else { return nil }
            return (r, c, now, self.inputs)
        }
        guard let state else { return }
        let (render, capture, t0, inputs) = state

        for p in outData { p.update(repeating: 0, count: n) }
        render(AudioIOBuffer(sampleTime: t0, frameCount: n, channels: UnsafeBufferPointer(outPointers),
                             hostSeconds: hostSeconds(atOutputSample: Double(t0))))
        writeHistory(t0, n)
        for (c, input) in inputs.enumerated() { synthesize(input, channel: c, t0: t0, frames: n) }
        capture(AudioIOBuffer(sampleTime: t0, frameCount: n, channels: UnsafeBufferPointer(inPointers),
                              hostSeconds: hostSeconds(atInputSample: t0)))
        lock.withLock { now = t0 + Int64(n) }
    }

    private func writeHistory(_ t0: Int64, _ n: Int) {
        let size = Self.historyFrames, mask = Int64(size - 1)
        for ch in 0..<outData.count {
            let src = outData[ch]
            history[ch].withUnsafeMutableBufferPointer { h in
                for i in 0..<n {
                    let idx = Int((t0 + Int64(i)) & mask)
                    h[idx] = src[i]
                    h[idx + size] = src[i]
                }
            }
        }
    }

    private func synthesize(_ input: SimulatedInput, channel c: Int, t0: Int64, frames n: Int) {
        let dst = inData[c]
        dst.update(repeating: 0, count: n)
        let size = Self.historyFrames, mask = Int64(size - 1)
        let width = 2 * SignalMath.sincHalfWidth
        let phases = SignalMath.tablePhases
        let ratio = 1 / (1 + driftPPM * 1e-6)
        if let src = input.source, src >= 1, src <= history.count {
            let taps = [SimulatedEcho(delaySamples: 0, gain: 1)] + input.echoes
            history[src - 1].withUnsafeBufferPointer { h in
                SignalMath.sincTable.withUnsafeBufferPointer { table in
                    for tap in taps {
                        let delay = latencySamples + input.extraDelaySamples + tap.delaySamples
                        let g = Float(tap.gain)
                        for i in 0..<n {
                            // Muestra de salida que oye la muestra de entrada t0 + i (con deriva).
                            let local = Double(t0 - origin) + Double(i)
                            let t = Double(origin) + local * ratio - delay
                            var base = Int64(t.rounded(.down))
                            var p = Int(((t - Double(base)) * Double(phases)).rounded())
                            if p == phases { p = 0; base += 1 }
                            let start = Int((base - Int64(SignalMath.sincHalfWidth - 1)) & mask)
                            var v: Float = 0
                            DSP.dotpr(h.baseAddress! + start, 1, table.baseAddress! + p * width, 1, &v, DSPLength(width))
                            dst[i] += g * v
                        }
                    }
                }
            }
        }
        let drive = input.drive, gain = Float(input.gain)
        let sigma = input.noiseDBFS.map { pow(10, $0 / 20) } ?? 0
        let tone = input.tone
        for i in 0..<n {
            var v = dst[i]
            if drive > 0 { v = Float(tanh(drive * Double(v))) }
            v *= gain
            if let tone {
                let t = Double(t0 + Int64(i)) / format.sampleRate
                v += Float(tone.peak * sin(2 * Double.pi * (tone.frequencyHz * t).truncatingRemainder(dividingBy: 1)))
            }
            if sigma > 0 { v += Float(sigma * noise[c].gaussian()) }
            dst[i] = min(1, max(-1, v))
        }
    }
}
