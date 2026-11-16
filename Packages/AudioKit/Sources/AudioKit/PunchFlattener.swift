import AVFoundation
import Foundation

/// Audio de un punch-in (mini-spec Fase 6, «Punch-in»): la toma del punch, ya alineada (su muestra 0 cae en
/// `songStartFrame`), y el tramo marcado `[start, end)` en muestras del tema.
public struct PunchAudio: Sendable, Equatable {
    public var start: Int64
    public var end: Int64
    public var songStartFrame: Int64
    /// Canales no entrelazados.
    public var channels: [[Float]]

    public init(start: Int64, end: Int64, songStartFrame: Int64, channels: [[Float]]) {
        self.start = start
        self.end = end
        self.songStartFrame = songStartFrame
        self.channels = channels
    }
}

/// Un punch guardado en disco: `processed.wav` del punch, su `songStart` y el tramo, en segundos del tema
/// (los campos de `TakePunch` de Store).
public struct PunchFile: Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var url: URL
    public var songStart: Double

    public init(start: Double, end: Double, url: URL, songStart: Double) {
        self.start = start
        self.end = end
        self.url = url
        self.songStart = songStart
    }
}

public enum PunchFlattenerError: Error, Equatable, Sendable {
    case sampleRateMismatch(String)
    case unreadable(String)
    case write(String)
}

/// Aplanado del punch-in (mini-spec Fase 6, «Punch-in»): la toma original fuera de cada tramo, muestra a
/// muestra; el punch dentro, con fundidos cruzados de 10 ms en la entrada y en la salida; varios punches se
/// aplican en orden y el último manda en su tramo.
///
/// Decisiones propias (la spec no las fija):
/// - Los fundidos van **dentro** del tramo (`[start, start + F)` y `[end − F, end)`), para que fuera quede la
///   original intacta. Con un tramo menor de `2F`, cada fundido ocupa la mitad.
/// - Forma `w = sin²(π/2·(i + ½)/F)` (suma constante), la misma del fundido del bucle (`StemScheduler`):
///   entrada `base·(1 − w) + punch·w`; salida `punch·(1 − w) + base·w`.
/// - El resultado tiene la duración y el inicio de la original: un tramo que se salga de ella se recorta.
///   Fuera de su fichero, el punch aporta silencio.
/// - Un punch mono sobre una original estéreo (o al revés) usa su último canal disponible para los que falten.
///
/// El silencio de la toma vieja al reproducir (`TakeTrack.silencedFrom`) usa el mismo fundido de salida que la
/// original tiene aquí en la entrada del tramo: lo que se oye al grabar el punch es lo que queda al aplanar.
public enum PunchFlattener {
    /// Fundido cruzado de entrada y salida (mini-spec Fase 6, «Punch-in»: «fundidos cruzados de 10 ms»).
    public static let crossfadeSeconds = 0.010

    /// Muestras del fundido a `sampleRate` (441 a 44,1 kHz, 480 a 48 kHz).
    public static func crossfadeFrames(sampleRate: Double) -> Int {
        max(1, Int((crossfadeSeconds * sampleRate).rounded()))
    }

    /// Peso del punch en la muestra `i` de un fundido de `n` (0 → 1).
    public static func weight(_ i: Int, _ n: Int) -> Float { StemScheduler.crossfadeWeight(i, n) }

    /// Aplana `punches` (en orden; el último manda) sobre `base`, cuya muestra 0 cae en `baseStartFrame`.
    public static func flatten(base: [[Float]], baseStartFrame: Int64, punches: [PunchAudio], sampleRate: Double) -> [[Float]] {
        var out = base
        let fade = crossfadeFrames(sampleRate: sampleRate)
        let length = Int64(base.first?.count ?? 0)
        for p in punches {
            // Tramo en índices de la original, recortado a ella.
            let a = max(p.start - baseStartFrame, 0), b = min(p.end - baseStartFrame, length)
            guard b > a, !p.channels.isEmpty else { continue }
            let span = Int(b - a)
            let f = min(fade, span / 2)
            for c in out.indices {
                let src = p.channels[min(c, p.channels.count - 1)]
                // Índice en el punch de la muestra `a` de la original.
                let shift = Int(a + baseStartFrame - p.songStartFrame)
                var seg = [Float](repeating: 0, count: span)
                let lo = max(0, -shift), hi = min(span, src.count - shift)
                if hi > lo {
                    src.withUnsafeBufferPointer { s in
                        seg.withUnsafeMutableBufferPointer { d in
                            (d.baseAddress! + lo).update(from: s.baseAddress! + shift + lo, count: hi - lo)
                        }
                    }
                }
                out[c].withUnsafeMutableBufferPointer { o in
                    let dst = o.baseAddress! + Int(a)
                    // Entrada: base·(1 − w) + punch·w.
                    for i in 0..<f {
                        let w = weight(i, f)
                        dst[i] = dst[i] * (1 - w) + seg[i] * w
                    }
                    // Centro: el punch tal cual.
                    if span - 2 * f > 0 {
                        seg.withUnsafeBufferPointer { s in (dst + f).update(from: s.baseAddress! + f, count: span - 2 * f) }
                    }
                    // Salida: punch·(1 − w) + base·w.
                    for i in 0..<f {
                        let k = span - f + i
                        let w = weight(i, f)
                        dst[k] = seg[k] * (1 - w) + dst[k] * w
                    }
                }
            }
        }
        return out
    }

    /// Versión sobre ficheros: lee `base` (con su `songStart`), aplica `punches` y escribe el resultado en
    /// `output` (WAV float32 como las tomas). `output` puede ser el mismo fichero que `base`: se lee antes.
    public static func flattenFiles(base: URL, baseSongStart: Double, punches: [PunchFile], to output: URL) throws {
        let (baseChannels, rate) = try read(base)
        let start = Int64((baseSongStart * rate).rounded())
        var list: [PunchAudio] = []
        for p in punches {
            let (ch, r) = try read(p.url)
            guard r == rate else { throw PunchFlattenerError.sampleRateMismatch(p.url.lastPathComponent) }
            list.append(PunchAudio(start: Int64((p.start * rate).rounded()), end: Int64((p.end * rate).rounded()),
                                   songStartFrame: Int64((p.songStart * rate).rounded()), channels: ch))
        }
        let out = flatten(base: baseChannels, baseStartFrame: start, punches: list, sampleRate: rate)
        do { try TakeFile.write(out, sampleRate: rate, to: output) } catch {
            throw PunchFlattenerError.write("\(error)")
        }
    }

    private static func read(_ url: URL) throws -> ([[Float]], Double) {
        do {
            let rate = try AVAudioFile(forReading: url).processingFormat.sampleRate
            return (try TakeFile.read(url), rate)
        } catch {
            throw PunchFlattenerError.unreadable(url.lastPathComponent)
        }
    }
}
