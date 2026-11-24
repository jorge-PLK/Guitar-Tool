import Foundation

// Conversión HEVC → H.264 de las tomas en Windows (plan, «Fase 7c», mini-spec «Tomas HEVC en Windows»): el Mac graba
// HEVC (`VideoTakeWriter` de AVFoundation) y Windows sin «Extensiones de vídeo HEVC» no lo decodifica ni en Media
// Foundation ni en WebView2. Aquí, lo puro y portátil (se prueba en el Mac y en Windows): leer el códec y los tiempos del
// fichero, los argumentos de ffmpeg, recolocar el primer fotograma y comprobar el resultado. El trabajo en segundo plano
// (cola, proceso, sustitución) es de AppCore (`VideoConversionEngine`). El códec no se guarda en `project.json`: se lee
// del fichero cada vez.

/// Códec de vídeo según la primera entrada de `stsd`.
public enum TakeVideoCodec: Sendable, Equatable, CustomStringConvertible {
    case hevc
    case h264
    case other(String)

    init(sampleEntry: String) {
        switch sampleEntry {
        case "hvc1", "hev1": self = .hevc
        case "avc1", "avc3": self = .h264
        default: self = .other(sampleEntry)
        }
    }

    public var description: String {
        switch self {
        case .hevc: "HEVC"
        case .h264: "H.264"
        case .other(let s): s
        }
    }
}

/// Lo que se sabe de la pista de vídeo de una toma sin decodificarla (cajas `moov`, delante o detrás de `mdat`).
public struct TakeVideoProbe: Sendable, Equatable {
    public var codec: TakeVideoCodec
    /// Tipo de la entrada de `stsd` (`hvc1`, `hev1`, `avc1`…).
    public var sampleEntry: String
    public var width: Int
    public var height: Int
    public var frameCount: Int
    /// Duración con imagen (s): los tramos no vacíos de la lista de ediciones o, sin lista, la suma de las muestras
    /// (la misma cuenta que `TakeVideoFile.open`).
    public var duration: Double
    /// PTS del tema del primer fotograma que se ve: tramo vacío delante + (composición del primero − inicio del tramo).
    public var firstFrameTime: Double
    /// PTS del tema del último fotograma que se ve (misma cuenta que `firstFrameTime` con la mayor composición dentro de
    /// los tramos de medios). Con el primero acota la rejilla: si ffmpeg recoloca los fotogramas, este se mueve.
    public var lastFrameTime: Double = 0
    public var fileSize: Int64

    public var frameRate: Double { duration > 0 ? Double(frameCount) / duration : 0 }
    /// Bits por segundo del fichero entero (cota superior del vídeo: la toma no lleva audio).
    public var bitrate: Double { duration > 0 ? Double(fileSize) * 8 / duration : 0 }

    /// `nil` si el fichero no tiene pista de vídeo; lanza si no es un MP4/QuickTime legible.
    public static func read(_ url: URL) throws -> TakeVideoProbe? {
        guard let t = try MP4EditList.tracks(in: url).first(where: { $0.handler == "vide" }), let entry = t.sampleEntry else { return nil }
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
        let (first, last, duration) = timing(t)
        return TakeVideoProbe(codec: TakeVideoCodec(sampleEntry: entry), sampleEntry: entry, width: t.width, height: t.height,
                              frameCount: t.sampleCount, duration: duration, firstFrameTime: first, lastFrameTime: last, fileSize: size)
    }

    /// Primer y último fotograma en tiempo del tema y duración con imagen.
    static func timing(_ t: MP4EditList.Track) -> (first: Double, last: Double, duration: Double) {
        let movie = Double(max(1, t.movieTimescale)), media = Double(max(1, t.mediaTimescale))
        guard let firstMedia = t.edits.firstIndex(where: { $0.mediaTime >= 0 }) else {
            return (Double(t.firstCompositionTime) / media, Double(t.lastCompositionTime) / media, Double(t.sampleDuration) / media)
        }
        let empty = t.edits[..<firstMedia].reduce(0.0) { $0 + Double($1.segmentDuration) } / movie
        let start = t.edits[firstMedia].mediaTime
        let shown = t.edits.filter { $0.mediaTime >= 0 }.reduce(0.0) { $0 + Double($1.segmentDuration) } / movie
        return (empty + Double(max(0, t.firstCompositionTime - start)) / media,
                empty + Double(max(0, t.lastCompositionTime - start)) / media, shown)
    }
}

/// Fallos de `TakeVideoTranscode`.
public enum TakeVideoTranscodeError: Error, Equatable, CustomStringConvertible {
    /// Sin pista de vídeo legible en el fichero convertido.
    case noVideo(String)
    /// El primer fotograma del fichero convertido cae después del instante pedido (no se puede adelantar con un tramo vacío).
    case startAfterTarget(Double, Double)

    public var description: String {
        switch self {
        case .noVideo(let f): "\(f) no tiene pista de vídeo"
        case .startAfterTarget(let got, let want): String(format: "el primer fotograma cae en %.4f s y debía caer en %.4f s", got, want)
        }
    }
}

/// Recetas de la conversión: argumentos de ffmpeg, bitrate, recolocación del primer fotograma y verificación.
public enum TakeVideoTranscode {
    /// Escala de los PTS del fichero convertido y de su película (la de `VideoTakeWriter`): con 90 000 el tramo vacío y los
    /// PTS del tema caen exactos en la rejilla (mini-spec, punto 4: `-video_track_timescale 90000`).
    public static let timescale = 90_000
    /// Codificadores de ffmpeg por orden: NVENC si hay una GPU de NVIDIA; si falla, el de Media Foundation, que viene con
    /// Windows (el ffmpeg embebido es LGPL, sin libx264; mini-spec, punto 4).
    public static let encoders = ["h264_nvenc", "h264_mf"]
    /// Bits por píxel y fotograma del objetivo por resolución (el de `MediaFoundationMuxer.defaultBitrate` para H.264:
    /// 1080p30 = 6,2 Mb/s).
    public static let targetBitsPerPixel = 0.10
    /// H.264 necesita más bits que HEVC para la misma calidad (decisión propia: ×1,5 del bitrate de la fuente).
    public static let hevcToH264Factor = 1.5
    /// Suelo del bitrate (decisión propia): una toma casi quieta no baja de aquí.
    public static let minimumBitrate = 250_000
    /// Tolerancia del PTS del primer fotograma frente al original (s): el punto fino de la sincronía (1 ms, la del resto
    /// de la cadena de vídeo).
    public static let firstFrameTolerance = 0.001
    /// Tolerancia del PTS del último fotograma frente al original (s): la misma de 1 ms. Si ffmpeg recolocara los
    /// fotogramas en una rejilla fija (sin `-enc_time_base demux`), el último se iría hasta medio fotograma.
    public static let lastFrameTolerance = 0.001
    /// Tolerancia de la duración: un fotograma de la fuente (mini-spec, punto 5).
    public static let durationToleranceFrames = 1.0

    /// Bitrate (b/s): el de la fuente ×1,5, sin pasar del objetivo por resolución ni bajar del suelo.
    public static func bitrate(for source: TakeVideoProbe) -> Int {
        let fps = source.frameRate > 0 ? source.frameRate : 30
        let target = Double(max(1, source.width) * max(1, source.height)) * fps * targetBitsPerPixel
        let fromSource = source.bitrate > 0 ? source.bitrate * hevcToH264Factor : target
        return max(minimumBitrate, Int(min(target, fromSource)))
    }

    /// GOP de un segundo (búsquedas rápidas del `<video>` del visor).
    public static func gop(for source: TakeVideoProbe) -> Int { max(1, Int((source.frameRate > 0 ? source.frameRate : 30).rounded())) }

    /// Argumentos de ffmpeg. Conservan la sincronía: solo la primera pista de vídeo, sin audio (`-an`), cada fotograma con
    /// su PTS (`-fps_mode passthrough` y `-enc_time_base demux`: sin este, el codificador trabaja en 1/fps y redondea
    /// cada PTS de una toma VFR del iPhone a esa rejilla, hasta medio fotograma), escala de 90 000, sin fotogramas B
    /// (el fichero queda como los de `VideoTakeWriter`: el tramo de medios empieza en 0) y SIN `+faststart` (`TakeVideoFile.open` y `rewrite` quieren
    /// `moov` al final). MPEG-4 aunque la extensión sea `.mov`, como el escritor de Windows. Progreso por stdout
    /// (`-progress pipe:1 -nostats`: `ProcessRunning.onLine` solo recibe stdout).
    public static func ffmpegArguments(input: URL, output: URL, encoder: String, bitrate: Int, gop: Int) -> [String] {
        ["-hide_banner", "-nostdin", "-y", "-v", "error", "-progress", "pipe:1", "-nostats",
         "-i", input.path,
         "-map", "0:v:0", "-an", "-sn", "-dn",
         "-c:v", encoder, "-b:v", String(bitrate), "-bf", "0", "-g", String(gop), "-pix_fmt", "yuv420p",
         "-fps_mode", "passthrough", "-enc_time_base", "demux", "-video_track_timescale", String(timescale), "-movie_timescale", String(timescale),
         "-f", "mp4", output.path]
    }

    /// Microsegundos de la línea `out_time_us=` del progreso de ffmpeg (nil en las demás o con `N/A`).
    public static func progressMicroseconds(_ line: String) -> Int64? {
        let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard l.hasPrefix("out_time_us=") else { return nil }
        return Int64(l.dropFirst("out_time_us=".count))
    }

    /// Pone delante de la pista de vídeo el tramo vacío que deja su primer fotograma en `firstFrameTime` (s del tema),
    /// conservando el tramo de medios que escribió ffmpeg. ffmpeg empieza la salida en 0 (resta el inicio de la entrada):
    /// la lista de ediciones del original (tramo vacío delante) se reaplica aquí, como `addLeadingGap` del escritor.
    public static func alignStart(_ url: URL, firstFrameTime: Double) throws {
        var failure: TakeVideoTranscodeError?
        var sawVideo = false
        try MP4EditList.rewrite(url) { t in
            guard t.handler == "vide" else { return nil }
            sawVideo = true
            let media = Double(max(1, t.mediaTimescale)), movie = Double(max(1, t.movieTimescale))
            var body = t.edits.filter { $0.mediaTime >= 0 }
            if body.isEmpty {
                let start = max(0, t.firstCompositionTime)
                let shown = t.sampleDuration - min(t.sampleDuration, UInt64(start))
                body = [.init(segmentDuration: UInt64((Double(shown) / media * movie).rounded()), mediaTime: start)]
            }
            let offset = Double(max(0, t.firstCompositionTime - body[0].mediaTime)) / media
            let gap = firstFrameTime - offset
            guard gap > -0.5 / movie else {
                failure = .startAfterTarget(offset, firstFrameTime)
                return nil
            }
            let ticks = UInt64(max(0, (gap * movie).rounded()))
            return ticks > 0 ? [.empty(ticks)] + body : body
        }
        if let failure { throw failure }
        if !sawVideo { throw TakeVideoTranscodeError.noVideo(url.lastPathComponent) }
    }

    /// `nil` si el convertido vale: H.264, misma duración (±1 fotograma de la fuente) y mismo PTS del primer fotograma
    /// (±`firstFrameTolerance`) y del último (±`lastFrameTolerance`; no recorre los demás). Si no, el motivo (texto para
    /// el trabajo fallido).
    public static func verify(original: TakeVideoProbe, converted: TakeVideoProbe) -> String? {
        guard converted.codec == .h264 else { return "el fichero convertido es \(converted.codec), no H.264" }
        let frame = 1 / (original.frameRate > 0 ? original.frameRate : 30)
        let dd = abs(converted.duration - original.duration)
        if dd > durationToleranceFrames * frame + 1e-9 {
            return String(format: "la duración no coincide (%.4f s frente a %.4f s del original)", converted.duration, original.duration)
        }
        let df = abs(converted.firstFrameTime - original.firstFrameTime)
        if df > firstFrameTolerance {
            return String(format: "el primer fotograma no coincide (%.4f s frente a %.4f s del original)",
                          converted.firstFrameTime, original.firstFrameTime)
        }
        let dl = abs(converted.lastFrameTime - original.lastFrameTime)
        if dl > lastFrameTolerance {
            return String(format: "el último fotograma no coincide (%.4f s frente a %.4f s del original)",
                          converted.lastFrameTime, original.lastFrameTime)
        }
        return nil
    }
}
