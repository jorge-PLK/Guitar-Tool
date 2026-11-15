import AVFoundation
import Foundation

/// Ancla de reproducción (mini-spec Fase 3, «Alineado con el backing» 1): la posición del tema `songTime`
/// suena en la muestra de salida `outputSample` de la línea común de `AudioIO`, contando la latencia de los
/// nodos del reproductor (Varispeed y TimePitch).
public struct PlaybackAnchor: Sendable, Equatable {
    public var songTime: Double
    public var outputSample: Double
    public var sampleRate: Double
    /// Velocidad de la pasada (la grabación solo admite 1).
    public var rate: Double

    public init(songTime: Double, outputSample: Double, sampleRate: Double, rate: Double = 1) {
        self.songTime = songTime
        self.outputSample = outputSample
        self.sampleRate = sampleRate
        self.rate = rate
    }

    /// Posición del tema (en muestras) que suena en la muestra de salida `y` (sin bucle).
    public func songFrame(atOutputSample y: Double) -> Double {
        songTime * sampleRate + (y - outputSample) * rate
    }

    /// La misma ancla con la muestra de salida en otra línea de tiempo (`y + offset`).
    public func offsettingOutput(by offset: Double) -> PlaybackAnchor {
        var a = self
        a.outputSample += offset
        return a
    }
}

/// Metadatos de una toma grabada (mini-spec Fase 3, «Grabación»): los campos aditivos de `Take`.
public struct RecordedTake: Sendable, Equatable {
    /// Instante del tema (s) de la muestra 0 del fichero; siempre un número entero de muestras.
    public var songStart: Double
    public var sampleRate: Double
    public var frameCount: Int
    public var channelCount: Int
    /// Latencia usada: la del canal de referencia si lo hay; si no, la calibrada de `guitarIn`; sin
    /// calibración válida, la declarada por el dispositivo.
    public var latencySamples: Double
    /// Retardo del rig usado (solo con canal de referencia).
    public var rigDelaySamples: Double?
    public var rigDelayReliable: Bool?
    public var latencyCalibrated: Bool
    public var calibrationKey: LatencyCalibrationKey
    public var clock: AudioIOClock

    /// Desplazamiento entero aplicado (latencia + rig, redondeado).
    public var shiftSamples: Int { TakeAligner.shiftSamples(latency: latencySamples, rigDelay: rigDelaySamples) }
    public var songStartFrame: Int64 { Int64((songStart * sampleRate).rounded()) }
}

public enum TakeRecorderError: Error, Equatable, Sendable {
    case noAnchor
    /// Solo se graba al 100 % (mini-spec Fase 3, «Reglas propias»).
    case unsupportedRate(Double)
    case nothingCaptured
    case write(String)
}

/// Captura de una toma sobre una sesión de `AudioIO` (mini-spec Fase 3, «Grabación» y «Alineado»).
///
/// El dueño de la sesión pasa `capture` como manejador de entrada y da el ancla del reproductor con
/// `setAnchor` (antes de `finish`). Se guardan `guitarIn` y, si la calibración vale y tiene canal de
/// referencia, ese canal solo en memoria para medir el retardo del rig. `finish` alinea y escribe
/// `processed.wav` (float32, mono o estéreo) con la muestra 0 en `songStart`.
///
/// La posición del tema de la muestra de entrada `n` es `n + round(ancla.tema − ancla.salida) − desplazamiento`.
/// Con el reproductor a velocidad 1 los dos términos del ancla son enteros, así que el único redondeo es
/// el del desplazamiento (≤ media muestra).
///
/// Nota para la parte 2: `capture` toma un cerrojo y añade a arrays (puede reservar memoria); en tiempo real
/// conviene ponerle delante un búfer circular.
public final class TakeRecorder: @unchecked Sendable {
    public let sampleRate: Double
    public let guitarIn: [Int]
    public let key: LatencyCalibrationKey
    public let clock: AudioIOClock
    public let declaredLatencySamples: Double
    /// Calibración que se usa (`nil` si no hay o no vale para `key`).
    public let calibration: LatencyCalibrationResult?
    private let lastReliableRigDelay: Double?
    /// Índices (desde 0) de los canales guardados: `guitarIn` y, al final, la referencia si la hay.
    private let stored: [Int]

    private let lock = NSLock()
    private var anchor: PlaybackAnchor?
    private var first: Int64?
    private var data: [[Float]]

    /// `guitarIn` y `backingOutLeft`, desde 1. `lastReliableRigDelay`: último retardo del rig fiable (si no,
    /// el de la calibración).
    public init(sampleRate: Double, guitarIn: [Int], key: LatencyCalibrationKey, clock: AudioIOClock,
                declaredLatencySamples: Double, calibration: LatencyCalibrationResult?, lastReliableRigDelay: Double? = nil) {
        precondition((1...2).contains(guitarIn.count))
        self.sampleRate = sampleRate
        self.guitarIn = guitarIn
        self.key = key
        self.clock = clock
        self.declaredLatencySamples = declaredLatencySamples
        let usable = calibration.flatMap { $0.applies(to: key) ? $0 : nil }
        self.calibration = usable
        self.lastReliableRigDelay = lastReliableRigDelay
        var idx = guitarIn.map { $0 - 1 }
        if let ref = usable?.reference { idx.append(ref.channel - 1) }
        stored = idx
        data = Array(repeating: [], count: idx.count)
    }

    public convenience init(io: any AudioIO, backingOutLeft: Int, guitarIn: [Int], calibration: LatencyCalibrationResult?,
                            lastReliableRigDelay: Double? = nil) {
        self.init(sampleRate: io.format.sampleRate, guitarIn: guitarIn,
                  key: LatencyCalibrationKey(io: io, backingOutLeft: backingOutLeft, guitarIn: guitarIn),
                  clock: io.clock, declaredLatencySamples: io.declaredLatencySamples, calibration: calibration,
                  lastReliableRigDelay: lastReliableRigDelay)
    }

    /// La toma se alinea con la latencia calibrada (si no, con la declarada y queda marcada).
    public var isCalibrated: Bool { calibration != nil }

    public func setAnchor(_ anchor: PlaybackAnchor) { lock.withLock { self.anchor = anchor } }

    /// Manejador de entrada. Los huecos entre bloques se rellenan con silencio para no perder la alineación.
    public func capture(_ buffer: AudioIOBuffer) {
        lock.withLock {
            if first == nil { first = buffer.sampleTime }
            let at = Int(buffer.sampleTime - first!)
            let have = data.first?.count ?? 0
            guard at + buffer.frameCount > have else { return }
            let skip = max(0, have - at)
            for (s, ch) in stored.enumerated() {
                if at > have { data[s].append(contentsOf: repeatElement(0, count: at - have)) }
                if ch < buffer.channelCount {
                    data[s].append(contentsOf: buffer[ch][skip...])
                } else {
                    data[s].append(contentsOf: repeatElement(0, count: buffer.frameCount - skip))
                }
            }
        }
    }

    /// Alinea lo capturado y escribe el WAV en `url`.
    public func finish(writingTo url: URL) throws -> RecordedTake {
        let (anchorValue, firstValue, captured) = lock.withLock { (anchor, first, data) }
        guard let anchor = anchorValue else { throw TakeRecorderError.noAnchor }
        guard abs(anchor.rate - 1) < 1e-9 else { throw TakeRecorderError.unsupportedRate(anchor.rate) }
        guard let first = firstValue, let count = captured.first?.count, count > 0 else { throw TakeRecorderError.nothingCaptured }

        let latency: Double
        var rig: Double?
        var reliable: Bool?
        if let cal = calibration, let ref = cal.reference {
            let est = TakeAligner.rigDelay(guitar: captured[0], reference: captured[guitarIn.count], sampleRate: sampleRate,
                                           lastReliable: lastReliableRigDelay ?? cal.rigDelayAtCalibration ?? 0)
            latency = ref.latencySamples
            rig = est.samples
            reliable = est.reliable
        } else if let cal = calibration {
            latency = cal.latencySamples
        } else {
            latency = declaredLatencySamples
        }
        let shift = Int64(TakeAligner.shiftSamples(latency: latency, rigDelay: rig))
        let anchorSong = Int64((anchor.songTime * sampleRate).rounded())
        let anchorOut = Int64(anchor.outputSample.rounded())
        // Primera muestra de entrada que cae en o tras el ancla y en o tras el principio del tema.
        let offset = anchorSong - anchorOut - shift
        let n0 = max(first, anchorOut + shift, -offset)
        let skip = Int(n0 - first)
        guard skip < count else { throw TakeRecorderError.nothingCaptured }
        let channels = captured[0..<guitarIn.count].map { Array($0[skip...]) }
        do { try TakeFile.write(channels, sampleRate: sampleRate, to: url) } catch {
            throw TakeRecorderError.write("\(error)")
        }
        return RecordedTake(songStart: Double(n0 + offset) / sampleRate, sampleRate: sampleRate, frameCount: count - skip,
                            channelCount: channels.count, latencySamples: latency, rigDelaySamples: rig, rigDelayReliable: reliable,
                            latencyCalibrated: calibration != nil, calibrationKey: key, clock: clock)
    }
}

/// WAV float32 no entrelazado de una toma.
enum TakeFile {
    static func write(_ channels: [[Float]], sampleRate: Double, to url: URL) throws {
        let frames = channels.first?.count ?? 0
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels.count,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = 65_536
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(chunk))!
        var at = 0
        while at < frames {
            let n = min(chunk, frames - at)
            buf.frameLength = AVAudioFrameCount(n)
            for (c, ch) in channels.enumerated() {
                ch.withUnsafeBufferPointer { buf.floatChannelData![c].update(from: $0.baseAddress! + at, count: n) }
            }
            try file.write(from: buf)
            at += n
        }
    }

    static func read(_ url: URL) throws -> [[Float]] {
        // Un solo `read(into:)` puede devolver menos de lo pedido (medido: 2 878 464 de 2 878 753): por trozos.
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let channels = Int(file.processingFormat.channelCount)
        var out = Array(repeating: [Float](), count: channels)
        for c in 0..<channels { out[c].reserveCapacity(Int(file.length)) }
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65_536)!
        while file.framePosition < file.length {
            try file.read(into: buf)
            guard buf.frameLength > 0 else { break }
            for c in 0..<channels {
                out[c].append(contentsOf: UnsafeBufferPointer(start: buf.floatChannelData![c], count: Int(buf.frameLength)))
            }
        }
        return out
    }
}
