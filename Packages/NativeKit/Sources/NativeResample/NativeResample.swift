import CResampler
import Foundation

/// Fallos de la conversión de frecuencia.
public enum ResampleError: Error, Equatable, Sendable {
    /// Frecuencia de origen o destino no positiva o no finita.
    case invalidRate
    /// Canales de distinta longitud, o ninguno.
    case invalidChannels
    /// r8brain no pudo crear el conversor.
    case creationFailed
}

/// Conversión de frecuencia fuera de línea (r8brain-free-src, MIT) en Mac y Windows.
public enum Resampler {
    /// Convierte un buffer mono entero. La latencia del filtro queda compensada y la salida tiene
    /// `round(n · to / from)` muestras.
    public static func resample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) throws -> [Float] {
        try resample(channels: [samples], from: sourceRate, to: targetRate)[0]
    }

    /// Igual que `resample(_:from:to:)` para varios canales de la misma longitud.
    public static func resample(channels: [[Float]], from: Double, to: Double) throws -> [[Float]] {
        guard let first = channels.first, channels.allSatisfy({ $0.count == first.count }) else {
            throw ResampleError.invalidChannels
        }
        let stream = try StreamResampler(from: from, to: to, channels: channels.count)
        var out = stream.process(channels)
        let tail = stream.flush()
        for c in out.indices { out[c] += tail[c] }
        return out
    }
}

/// Conversión de frecuencia por bloques. Provisional: la afinará la parte 7.1.
public final class StreamResampler {
    /// Tamaño máximo de bloque que se entrega a r8brain.
    private static let blockFrames = 16_384

    private let ratio: Double
    private let handles: [OpaquePointer]
    private var skipRemaining: Int
    private var framesIn = 0
    private var framesOut = 0
    private var scratch: [Double]

    /// Muestras de salida que se descartan al principio para compensar el filtro (r8brain 7.x ya recorta su
    /// latencia entera por dentro, así que suele ser 0).
    public let latencyFrames: Int

    public init(from: Double, to: Double, channels: Int) throws {
        guard from.isFinite, to.isFinite, from > 0, to > 0 else { throw ResampleError.invalidRate }
        guard channels > 0 else { throw ResampleError.invalidChannels }
        var made: [OpaquePointer] = []
        for _ in 0..<channels {
            guard let h = tf_r8b_create(from, to, Int32(Self.blockFrames)) else {
                made.forEach { tf_r8b_destroy($0) }
                throw ResampleError.creationFailed
            }
            made.append(h)
        }
        handles = made
        ratio = to / from
        latencyFrames = Int(tf_r8b_latency(made[0]))
        skipRemaining = latencyFrames
        scratch = [Double](repeating: 0, count: Self.blockFrames)
    }

    deinit { handles.forEach { tf_r8b_destroy($0) } }

    /// Procesa un bloque (un array por canal, todos de la misma longitud) y devuelve lo que ya salió.
    public func process(_ input: [[Float]]) -> [[Float]] {
        precondition(input.count == handles.count, "número de canales distinto del de init")
        let n = input[0].count
        precondition(input.allSatisfy { $0.count == n }, "canales de distinta longitud")
        framesIn += n
        return run(frames: n) { c, start, count, dst in
            input[c].withUnsafeBufferPointer { src in
                let s = src.baseAddress! + start
                for i in 0..<count { dst[i] = Double(s[i]) }
            }
        }
    }

    /// Vacía el filtro: entrega las muestras que faltan hasta `round(entrada · to / from)` en total.
    public func flush() -> [[Float]] {
        let expected = Int((Double(framesIn) * ratio).rounded())
        var out = [[Float]](repeating: [], count: handles.count)
        var loops = 0
        while framesOut < expected && loops < 1_000_000 {
            loops += 1
            var chunk = run(frames: Self.blockFrames) { _, _, count, dst in
                for i in 0..<count { dst[i] = 0 }
            }
            let excess = framesOut - expected
            if excess > 0 {
                for c in chunk.indices { chunk[c].removeLast(excess) }
                framesOut = expected
            }
            for c in out.indices { out[c] += chunk[c] }
        }
        return out
    }

    /// Alimenta `frames` muestras por canal en bloques, con `fill` rellenando el búfer de entrada.
    private func run(frames: Int, fill: (_ channel: Int, _ start: Int, _ count: Int, _ dst: UnsafeMutablePointer<Double>) -> Void) -> [[Float]] {
        var out = [[Float]](repeating: [], count: handles.count)
        var start = 0
        while start < frames {
            let count = min(Self.blockFrames, frames - start)
            var drop = 0
            for c in handles.indices {
                var ptr: UnsafePointer<Double>?
                var got = 0
                scratch.withUnsafeMutableBufferPointer { buf in
                    fill(c, start, count, buf.baseAddress!)
                    got = Int(tf_r8b_process(handles[c], buf.baseAddress!, Int32(count), &ptr))
                }
                // Todos los canales devuelven lo mismo por bloque, así que el descarte de latencia es común.
                drop = min(got, skipRemaining)
                if got > drop, let ptr {
                    let k = got - drop, old = out[c].count
                    out[c].append(contentsOf: repeatElement(0, count: k))
                    out[c].withUnsafeMutableBufferPointer { o in
                        let d = o.baseAddress! + old, s = ptr + drop
                        for i in 0..<k { d[i] = Float(s[i]) }
                    }
                }
            }
            skipRemaining -= drop
            start += count
        }
        framesOut += out[0].count
        return out
    }
}
