#if os(Windows)
import CMediaFoundation
import Foundation

// Piezas comunes de Media Foundation en Windows (plan, «Fase 7c», paso 7, parte 7.2): errores, rutas, listado de
// codificadores, lector de ficheros y escritor MP4 de bajo nivel. Sin `import WinSDK` (choca con `UUID` de Foundation):
// todo lo de COM está en el shim C `CMediaFoundation`.

/// Fallo de una llamada a Media Foundation: paso y HRESULT.
struct MediaFoundationError: Error, CustomStringConvertible, Equatable {
    let hr: Int32
    let step: String
    var description: String { "\(step): HRESULT 0x" + String(UInt32(bitPattern: hr), radix: 16, uppercase: true) }
}

enum MF {
    static func check(_ hr: Int32, _ step: @autoclosure () -> String) throws {
        if hr < 0 { throw MediaFoundationError(hr: hr, step: step()) }
    }

    /// Ruta de sistema en UTF-16 terminada en 0.
    static func withWidePath<R>(_ url: URL, _ body: (UnsafePointer<UInt16>) throws -> R) rethrows -> R {
        let path = url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? url.path
        return try withWide(path, body)
    }

    static func withWide<R>(_ s: String, _ body: (UnsafePointer<UInt16>) throws -> R) rethrows -> R {
        var w = Array(s.utf16)
        w.append(0)
        return try w.withUnsafeBufferPointer { try body($0.baseAddress!) }
    }

    /// Texto de un `char[N]` de C (tupla en Swift) en UTF-8.
    static func string<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// FOURCC (Data1 de un subtipo de Media Foundation) en texto: 'H264', 'HEVC', 'NV12'…
    static func fourCC(_ v: UInt32) -> String {
        let bytes = (0..<4).map { UInt8((v >> (8 * $0)) & 0xff) }
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) else { return "0x" + String(v, radix: 16) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// fps como fracción: las de NTSC exactas (30000/1001…); el resto, con milésimas.
    static func rational(_ fps: Double) -> (Int32, Int32) {
        for base in [24.0, 30, 60, 120] where abs(fps - base * 1000 / 1001) < 1e-3 {
            return (Int32(base * 1000), 1001)
        }
        var n = Int((fps * 1000).rounded()), d = 1000
        var a = n, b = d
        while b != 0 { (a, b) = (b, a % b) }
        if a > 1 { n /= a; d /= a }
        return (Int32(n), Int32(d))
    }

    /// Segundos → unidades de 100 ns (redondeado).
    static func ticks(_ seconds: Double) -> Int64 { Int64((seconds * 1e7).rounded()) }

    /// Hora del sistema de Media Foundation (`MFGetSystemTime`: QPC en 100 ns), la escala de las marcas de la cámara.
    static func systemTime() -> Int64 { tfmf_system_time() }
}

extension FramePixelBuffer {
    /// Copia en otro formato (BT.709 de rango limitado, la cuenta del shim); el mismo objeto si ya lo está.
    func converted(to format: PixelFormat) -> FramePixelBuffer {
        guard format != pixelFormat else { return self }
        let out = FramePixelBuffer(pixelFormat: format, width: width, height: height)
        let src = baseAddress.assumingMemoryBound(to: UInt8.self), dst = out.baseAddress.assumingMemoryBound(to: UInt8.self)
        if format == .nv12 {
            tfmf_bgra_to_nv12(src, Int32(bytesPerRow), Int32(width), Int32(height), dst, Int32(out.bytesPerRow),
                              out.planeBaseAddress(1).assumingMemoryBound(to: UInt8.self), Int32(out.bytesPerRow))
        } else {
            tfmf_nv12_to_bgra(src, Int32(bytesPerRow), planeBaseAddress(1).assumingMemoryBound(to: UInt8.self), Int32(bytesPerRow),
                              Int32(width), Int32(height), dst, Int32(out.bytesPerRow))
        }
        return out
    }
}

// MARK: - Codificadores

/// Un codificador de vídeo del sistema.
public struct VideoEncoderInfo: Sendable, Equatable {
    public var codec: MontageCodec
    public var name: String
    public var isHardware: Bool
}

/// Codificadores de vídeo de Media Foundation (MFTEnumEx): para elegir HEVC solo si hay uno y para `tf-video` en un PC.
public enum MediaFoundationEncoders {
    /// Codificadores registrados para `codec`, de hardware primero (orden de Media Foundation).
    public static func available(_ codec: MontageCodec) -> [VideoEncoderInfo] {
        let c = codec == .hevc ? Int32(TFMF_CODEC_HEVC) : Int32(TFMF_CODEC_H264)
        let n = tfmf_list_encoders(c, nil, 0)
        guard n > 0 else { return [] }
        var list = [TFMFEncoderInfo](repeating: TFMFEncoderInfo(), count: Int(n))
        let got = list.withUnsafeMutableBufferPointer { tfmf_list_encoders(c, $0.baseAddress, n) }
        guard got > 0 else { return [] }
        return list.prefix(Int(min(got, n))).map { VideoEncoderInfo(codec: codec, name: MF.string($0.name), isHardware: $0.hardware != 0) }
    }

    /// Todos: HEVC y H.264.
    public static func all() -> [VideoEncoderInfo] { available(.hevc) + available(.h264) }

    /// Si hay algún codificador HEVC (se consulta una vez por proceso).
    public static let hasHEVC: Bool = !available(.hevc).isEmpty
}

// MARK: - Lector

/// Lector de ficheros de vídeo y audio con `IMFSourceReader` (tests, y después el compositor y `tf-video`).
enum MediaFoundationReader {
    struct Info: Equatable {
        var hasVideo: Bool
        var width: Int
        var height: Int
        var fps: Double
        var videoCodec: String
        var hasAudio: Bool
        var sampleRate: Double
        var channels: Int
        /// Data1 del subtipo de audio (0x1610 = AAC).
        var audioFormatTag: UInt32
        var duration: Double
    }

    /// El fichero tiene pista de vídeo y Media Foundation no la abre (sin decodificador: una toma HEVC del Mac en un
    /// Windows sin «Extensiones de vídeo HEVC»). Antes el reintento solo de audio tapaba este error con
    /// `MF_E_INVALIDSTREAMNUMBER` (0xC00D36B3).
    struct UndecodableVideo: Error, Equatable, CustomStringConvertible {
        var file: String
        /// FOURCC del subtipo que da Media Foundation ('HEVC'…) o, si no lo da, el de `stsd` (`hvc1`…).
        var codec: String
        var hr: Int32
        var description: String {
            "\(file): este equipo no puede decodificar el vídeo \(codec) (HRESULT 0x" + String(UInt32(bitPattern: hr), radix: 16, uppercase: true) + ")"
        }
    }

    static func info(_ url: URL) throws -> Info {
        var info = TFMFReaderInfo()
        var r: UnsafeMutableRawPointer?
        var hr = MF.withWidePath(url) { tfmf_reader_open($0, 1, 0, &r, &info) }
        if hr < 0 {
            // El shim rellena `hasVideo` y `videoFourCC` antes de fallar en `SetCurrentMediaType`: con pista de vídeo el
            // error es ese, no el del reintento de audio. Sin el subtipo, el códec lo dice `stsd`. (Si el shim no llegó
            // a ver las pistas, el fallo es de abrir el fichero y lo cuenta el reintento.)
            if info.hasVideo != 0 {
                let stsd = (try? MP4EditList.tracks(in: url).first { $0.handler == "vide" })?.sampleEntry
                throw UndecodableVideo(file: url.lastPathComponent, codec: info.videoFourCC != 0 ? MF.fourCC(info.videoFourCC) : (stsd ?? "?"), hr: hr)
            }
            hr = MF.withWidePath(url) { tfmf_reader_open($0, 0, 1, &r, &info) }
        }
        try MF.check(hr, "abrir \(url.lastPathComponent)")
        tfmf_reader_release(r)
        return Info(hasVideo: info.hasVideo != 0, width: Int(info.width), height: Int(info.height),
                    fps: info.fpsDen > 0 ? Double(info.fpsNum) / Double(info.fpsDen) : 0, videoCodec: MF.fourCC(info.videoFourCC),
                    hasAudio: info.hasAudio != 0, sampleRate: Double(info.sampleRate), channels: Int(info.channels),
                    audioFormatTag: info.audioFormatTag, duration: Double(info.duration100ns) / 1e7)
    }

    /// Recorre los fotogramas decodificados (PTS y duración en s, imagen en `format`); `body` devuelve `false` para parar.
    static func forEachFrame(_ url: URL, format: FramePixelBuffer.PixelFormat = .nv12,
                             _ body: (Double, Double, FramePixelBuffer) throws -> Bool) throws {
        var info = TFMFReaderInfo()
        var r: UnsafeMutableRawPointer?
        try MF.check(MF.withWidePath(url) { tfmf_reader_open($0, 1, 0, &r, &info) }, "abrir vídeo \(url.lastPathComponent)")
        defer { tfmf_reader_release(r) }
        while true {
            var f = TFMFVideoFrame()
            var eos: Int32 = 0
            try MF.check(tfmf_reader_video(r, &f, &eos), "leer vídeo")
            if eos != 0 { return }
            let pb = FramePixelBuffer(pixelFormat: format, width: Int(f.width), height: Int(f.height))
            if format == .nv12 {
                for y in 0..<pb.height {
                    (pb.baseAddress + y * pb.bytesPerRow).copyMemory(from: f.y + y * Int(f.yStride), byteCount: pb.width)
                }
                let uv = pb.planeBaseAddress(1)
                for y in 0..<pb.planeHeight(1) {
                    (uv + y * pb.bytesPerRow).copyMemory(from: f.uv + y * Int(f.uvStride), byteCount: 2 * ((pb.width + 1) / 2))
                }
            } else {
                tfmf_nv12_to_bgra(f.y, f.yStride, f.uv, f.uvStride, f.width, f.height,
                                  pb.baseAddress.assumingMemoryBound(to: UInt8.self), Int32(pb.bytesPerRow))
            }
            guard try body(Double(f.time100ns) / 1e7, Double(f.duration100ns) / 1e7, pb) else { return }
        }
    }

    /// Audio decodificado en float, colocado por su marca: la muestra `i` es el instante `i / sampleRate` del fichero
    /// (lo anterior a 0 se descarta). `firstTime`: marca del primer trozo.
    static func audio(_ url: URL) throws -> (channels: [[Float]], sampleRate: Double, firstTime: Double) {
        var info = TFMFReaderInfo()
        var r: UnsafeMutableRawPointer?
        try MF.check(MF.withWidePath(url) { tfmf_reader_open($0, 0, 1, &r, &info) }, "abrir audio \(url.lastPathComponent)")
        defer { tfmf_reader_release(r) }
        let sr = Double(info.sampleRate), nch = Int(max(1, info.channels))
        var out = [[Float]](repeating: [], count: nch)
        var first: Double?
        while true {
            var c = TFMFAudioChunk()
            var eos: Int32 = 0
            try MF.check(tfmf_reader_audio(r, &c, &eos), "leer audio")
            if eos != 0 { break }
            let t = Double(c.time100ns) / 1e7
            if first == nil { first = t }
            let start = Int((t * sr).rounded())
            let frames = Int(c.frames)
            for ch in 0..<nch {
                if out[ch].count < start + frames { out[ch].append(contentsOf: repeatElement(0, count: start + frames - out[ch].count)) }
            }
            for i in 0..<frames where start + i >= 0 {
                for ch in 0..<nch { out[ch][start + i] = c.samples[i * Int(c.channels) + ch] }
            }
        }
        return (out, sr, first ?? 0)
    }
}

// MARK: - Escritor de bajo nivel

/// MP4 (H.264 o HEVC, AAC opcional) con `IMFSinkWriter`. Tiempos en unidades de 100 ns; sin lógica de PTS ni de desfase
/// (eso es de `VideoTakeWriter` y del exportador).
final class MediaFoundationMuxer {
    struct Audio: Equatable {
        var sampleRate: Int
        var channels: Int
        var bytesPerSecond: Int
    }

    struct Config: Equatable {
        var width: Int
        var height: Int
        var fps: Double
        var codec: MontageCodec
        var videoBitrate: Int
        var audio: Audio?
        var realTime: Bool
    }

    let config: Config
    private var handle: UnsafeMutableRawPointer?

    init(url: URL, config: Config) throws {
        self.config = config
        let (n, d) = MF.rational(config.fps)
        var c = TFMFWriterConfig()
        c.width = Int32(config.width)
        c.height = Int32(config.height)
        c.fpsNum = n
        c.fpsDen = d
        c.codec = config.codec == .hevc ? Int32(TFMF_CODEC_HEVC) : Int32(TFMF_CODEC_H264)
        c.videoBitrate = Int32(config.videoBitrate)
        c.audioChannels = Int32(config.audio?.channels ?? 0)
        c.audioSampleRate = Int32(config.audio?.sampleRate ?? 0)
        c.audioBytesPerSecond = Int32(config.audio?.bytesPerSecond ?? 0)
        c.realTime = config.realTime ? 1 : 0
        var h: UnsafeMutableRawPointer?
        var step: UnsafePointer<CChar>?
        let hr = MF.withWidePath(url) { tfmf_writer_create($0, &c, &h, &step) }
        try MF.check(hr, step.map { String(cString: $0) } ?? "crear el escritor")
        handle = h
    }

    deinit { tfmf_writer_release(handle) }

    func writeVideo(_ pb: FramePixelBuffer, time: Int64, duration: Int64) throws {
        precondition(pb.width == config.width && pb.height == config.height, "MediaFoundationMuxer: tamaño distinto del configurado")
        let fmt = pb.pixelFormat == .bgra ? Int32(TFMF_PIXEL_BGRA) : Int32(TFMF_PIXEL_NV12)
        try MF.check(tfmf_writer_video(handle, fmt, pb.baseAddress.assumingMemoryBound(to: UInt8.self), Int32(pb.bytesPerRow), time, duration),
                     "escribir vídeo")
    }

    /// PCM de 16 bits entrelazado.
    func writeAudio(_ interleaved: UnsafeBufferPointer<Int16>, time: Int64) throws {
        let ch = config.audio?.channels ?? 1
        try MF.check(tfmf_writer_audio(handle, interleaved.baseAddress, Int32(interleaved.count / ch), time), "escribir audio")
    }

    func finalize() throws { try MF.check(tfmf_writer_finalize(handle), "cerrar el fichero") }

    /// Bitrate de vídeo por defecto (decisión propia): 0,10 bits por píxel y fotograma en H.264 y 0,07 en HEVC
    /// (1080p30: 6,2 y 4,4 Mb/s).
    static func defaultBitrate(width: Int, height: Int, fps: Double, codec: MontageCodec) -> Int {
        Int(Double(width * height) * max(1, fps) * (codec == .hevc ? 0.07 : 0.10))
    }
}
#endif
