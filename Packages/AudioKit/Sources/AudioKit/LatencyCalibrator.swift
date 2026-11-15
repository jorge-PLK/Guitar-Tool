import Foundation

/// Clave de una calibración (mini-spec Fase 3, «Calibración de latencia» · Lo que se guarda): vale mientras
/// no cambie ningún campo. Mismos campos que `CalibrationKey` de Store (la app hace de puente).
public struct LatencyCalibrationKey: Sendable, Equatable, Hashable, Codable {
    public var inputUID: String
    public var outputUID: String
    public var sampleRate: Double
    public var bufferFrames: Int
    /// Canal de entrada medido (el primero de `guitarIn`), desde 1.
    public var inputChannel: Int
    /// Canal de salida del barrido (el izquierdo de `backingOut`), desde 1.
    public var outputChannel: Int

    public init(inputUID: String, outputUID: String, sampleRate: Double, bufferFrames: Int,
                inputChannel: Int, outputChannel: Int) {
        self.inputUID = inputUID
        self.outputUID = outputUID
        self.sampleRate = sampleRate
        self.bufferFrames = bufferFrames
        self.inputChannel = inputChannel
        self.outputChannel = outputChannel
    }

    /// Clave de una sesión con esos canales (desde 1).
    public init(io: any AudioIO, backingOutLeft: Int, guitarIn: [Int]) {
        self.init(inputUID: io.inputDeviceUID, outputUID: io.outputDeviceUID, sampleRate: io.format.sampleRate,
                  bufferFrames: io.format.bufferFrames, inputChannel: guitarIn.first ?? 1, outputChannel: backingOutLeft)
    }
}

/// Canal de referencia interno: llega antes que `guitarIn` porque no pasa por el rig.
public struct ReferenceInput: Sendable, Equatable, Codable {
    /// Canal de entrada, desde 1.
    public var channel: Int
    public var latencySamples: Double

    public init(channel: Int, latencySamples: Double) {
        self.channel = channel
        self.latencySamples = latencySamples
    }
}

/// Resultado de una calibración.
public struct LatencyCalibrationResult: Sendable, Equatable {
    public var key: LatencyCalibrationKey
    public var date: Date
    /// Canales de `guitarIn` (desde 1).
    public var guitarIn: [Int]
    /// Medida de cada canal de entrada del dispositivo (`[i]` es el canal `i + 1`).
    public var channels: [LatencyChannelMeasurement]
    public var reference: ReferenceInput?

    public init(key: LatencyCalibrationKey, date: Date, guitarIn: [Int], channels: [LatencyChannelMeasurement],
                reference: ReferenceInput?) {
        self.key = key
        self.date = date
        self.guitarIn = guitarIn
        self.channels = channels
        self.reference = reference
    }

    /// Medida del primer canal de `guitarIn`.
    public var guitar: LatencyChannelMeasurement { channels[(guitarIn.first ?? 1) - 1] }
    /// Latencia de ida y vuelta hasta `guitarIn` (mediana), en muestras con decimales.
    public var latencySamples: Double { guitar.latencySamples }
    public var spreadSamples: Double { guitar.spreadSamples }
    public var failure: LatencyFailure? { guitar.failure }
    public var isValid: Bool { guitar.isValid }
    /// Retardo del rig durante la calibración (`guitarIn` menos referencia), si hay referencia.
    public var rigDelayAtCalibration: Double? { reference.map { latencySamples - $0.latencySamples } }

    /// La calibración vale para una sesión con esta clave.
    public func applies(to key: LatencyCalibrationKey) -> Bool { isValid && self.key == key }
}

/// Calibra la latencia sobre una sesión de `AudioIO` (mini-spec Fase 3, «Calibración de latencia»): emite el
/// estímulo de `LatencyProbe` por `backingOutLeft`, graba todos los canales de entrada y elige el canal de
/// referencia interno.
///
/// Se usa de dos formas: `calibrate(on:)` abre y cierra la sesión, o el dueño de la sesión pasa `render` y
/// `capture` a `AudioIO.start` y espera a `isComplete` (así se hace con `SimulatedAudioIO.pump`). En el hilo
/// de E/S no reserva memoria: la captura está reservada de antemano.
public final class LatencyCalibrator: @unchecked Sendable {
    /// Decisión propia (la spec dice «llega antes»): un canal es referencia si llega al menos una muestra
    /// antes que `guitarIn` (la precisión de la medida es de centésimas de muestra).
    public static let referenceMinLeadSamples = 1.0

    public let probe: LatencyProbe
    public let key: LatencyCalibrationKey
    public let guitarIn: [Int]
    private let outIndex: Int
    private let inputChannels: Int
    private let lock = NSLock()
    private var origin: Int64?
    private var recordings: [[Float]]
    private var filled = 0
    private var waiter: CheckedContinuation<Void, Never>?

    /// `backingOutLeft` y `guitarIn`, desde 1.
    public init(sampleRate: Double, inputChannels: Int, backingOutLeft: Int, guitarIn: [Int], key: LatencyCalibrationKey) {
        precondition(!guitarIn.isEmpty && guitarIn.allSatisfy { $0 >= 1 && $0 <= inputChannels })
        probe = LatencyProbe(sampleRate: sampleRate)
        self.key = key
        self.guitarIn = guitarIn
        self.inputChannels = inputChannels
        outIndex = backingOutLeft - 1
        recordings = Array(repeating: [Float](repeating: 0, count: probe.captureFrames), count: inputChannels)
    }

    public convenience init(io: any AudioIO, backingOutLeft: Int, guitarIn: [Int]) {
        self.init(sampleRate: io.format.sampleRate, inputChannels: io.format.inputChannels, backingOutLeft: backingOutLeft,
                  guitarIn: guitarIn, key: LatencyCalibrationKey(io: io, backingOutLeft: backingOutLeft, guitarIn: guitarIn))
    }

    /// Manejador de salida: el estímulo empieza en la primera muestra del primer bloque pedido.
    public func render(_ buffer: AudioIOBuffer) {
        guard outIndex >= 0, outIndex < buffer.channelCount else { return }
        let start = lock.withLock { () -> Int64 in
            if origin == nil { origin = buffer.sampleTime }
            return origin!
        }
        let out = buffer[outIndex]
        let rel = Int(buffer.sampleTime - start)
        for i in 0..<buffer.frameCount { out[i] = probe.stimulus(at: rel + i) }
    }

    /// Manejador de entrada.
    public func capture(_ buffer: AudioIOBuffer) {
        let done = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            guard let start = origin, filled < probe.captureFrames else { return nil }
            let rel = Int(buffer.sampleTime - start)
            let lo = max(0, -rel), hi = min(buffer.frameCount, probe.captureFrames - rel)
            guard lo < hi else { return nil }
            for ch in 0..<min(inputChannels, buffer.channelCount) {
                let src = buffer[ch]
                recordings[ch].withUnsafeMutableBufferPointer { dst in
                    for i in lo..<hi { dst[rel + i] = src[i] }
                }
            }
            filled = max(filled, rel + hi)
            guard filled >= probe.captureFrames else { return nil }
            defer { waiter = nil }
            return waiter
        }
        done?.resume()
    }

    public var isComplete: Bool { lock.withLock { filled >= probe.captureFrames } }

    /// Analiza lo capturado (aunque no esté completo: lo que falte cuenta como silencio).
    public func result(date: Date = Date()) -> LatencyCalibrationResult {
        let recs = lock.withLock { recordings }
        let channels = recs.enumerated().map { probe.analyze($0.element, channel: $0.offset + 1) }
        let guitar = channels[guitarIn[0] - 1]
        var reference: ReferenceInput?
        if guitar.isValid {
            let lead = channels.filter {
                !guitarIn.contains($0.channel) && $0.isValid
                    && $0.latencySamples <= guitar.latencySamples - Self.referenceMinLeadSamples
            }
            if let first = lead.min(by: { $0.latencySamples < $1.latencySamples }) {
                reference = ReferenceInput(channel: first.channel, latencySamples: first.latencySamples)
            }
        }
        return LatencyCalibrationResult(key: key, date: date, guitarIn: guitarIn, channels: channels, reference: reference)
    }

    /// Abre la sesión, emite el estímulo, espera la captura (o `timeout` segundos de reloj) y cierra.
    public func calibrate(on io: any AudioIO, timeout: Double = 15) async throws -> LatencyCalibrationResult {
        try io.start(render: { [self] in render($0) }, capture: { [self] in capture($0) })
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                if filled >= probe.captureFrames { return true }
                waiter = c
                return false
            }
            if resumeNow { c.resume() }
            Task { [self] in
                try? await Task.sleep(for: .seconds(timeout))
                let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                    defer { waiter = nil }
                    return waiter
                }
                pending?.resume()
            }
        }
        io.stop()
        return result()
    }
}
