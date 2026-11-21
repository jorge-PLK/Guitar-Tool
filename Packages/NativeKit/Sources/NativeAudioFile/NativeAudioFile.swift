import Foundation
import NativeDSP

/// Lectura de WAV/AIFF/FLAC/MP3 a `Float` y escritura de WAV (plan, «Fase 7c», paso 6: NativeAudioFile).
/// En el Mac, `AVAudioFile` (lo de hoy, mismas muestras); fuera, dr_wav/dr_flac/dr_mp3. Las muestras van
/// por canales separados (planar), como `AVAudioPCMBuffer.floatChannelData` con `interleaved: false`.
public enum NativeAudioFile {
    /// El fichero entero.
    public static func read(_ url: URL) throws -> DecodedAudio {
        try read(url, backend: .system)
    }

    /// Mezcla mono: media de los canales con `DSP.vsma` canal a canal (k = 1/canales), como `MonoAudio` de
    /// TabKit y `ChordAudio` de StudyKit.
    public static func readMono(_ url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let audio = try read(url)
        return (mixToMono(audio.channels, frames: audio.frameCount), audio.sampleRate)
    }

    /// Escribe un WAV entero.
    public static func write(_ url: URL, channels: [[Float]], sampleRate: Double, format: WAVSampleFormat) throws {
        let w = try AudioFileWriter(url: url, sampleRate: sampleRate, channelCount: channels.count, format: format)
        try w.write(channels)
        try w.close()
    }

    static func read(_ url: URL, backend: AudioBackend) throws -> DecodedAudio {
        let r = try AudioFileReader(url: url, backend: backend)
        var channels = [[Float]](repeating: [Float](repeating: 0, count: r.frameCount), count: r.channelCount)
        var pos = 0
        while pos < r.frameCount {
            let want = min(AudioFileReader.blockFrames, r.frameCount - pos)
            let got = try withPointers(&channels, offset: pos) { try r.read(into: $0, maxFrames: want) }
            if got == 0 { break }
            pos += got
        }
        if pos < r.frameCount { for c in channels.indices { channels[c].removeLast(r.frameCount - pos) } }
        return DecodedAudio(sampleRate: r.sampleRate, channels: channels)
    }

    static func mixToMono(_ channels: [[Float]], frames: Int) -> [Float] {
        var mono = [Float](repeating: 0, count: frames)
        guard frames > 0 else { return mono }
        var k = 1 / Float(max(channels.count, 1))
        mono.withUnsafeMutableBufferPointer { m in
            let dst = m.baseAddress!
            for ch in channels { DSP.vsma(ch, 1, &k, dst, 1, dst, 1, DSPLength(frames)) }
        }
        return mono
    }

    /// Punteros mutables a cada canal desde `offset`, válidos durante `body`.
    static func withPointers<R>(_ channels: inout [[Float]], offset: Int,
                                _ body: ([UnsafeMutablePointer<Float>]) throws -> R) throws -> R {
        try channels.withUnsafeMutableBufferPointer { outer in
            func nest(_ i: Int, _ acc: [UnsafeMutablePointer<Float>]) throws -> R {
                if i == outer.count { return try body(acc) }
                return try outer[i].withUnsafeMutableBufferPointer { try nest(i + 1, acc + [$0.baseAddress! + offset]) }
            }
            return try nest(0, [])
        }
    }
}

/// Audio decodificado: un `[Float]` por canal, todos de la misma longitud.
public struct DecodedAudio: Sendable, Equatable {
    public var sampleRate: Double
    public var channels: [[Float]]
    public init(sampleRate: Double, channels: [[Float]]) {
        self.sampleRate = sampleRate
        self.channels = channels
    }
    public var channelCount: Int { channels.count }
    public var frameCount: Int { channels.first?.count ?? 0 }
}

/// Formato de muestra al escribir WAV.
public enum WAVSampleFormat: Sendable, Equatable {
    /// PCM entero de 16 bits.
    case int16
    /// PCM entero de 24 bits.
    case int24
    /// IEEE float de 32 bits (lo que escriben hoy StemKit, AudioKit y TabKit).
    case float32

    var bits: Int {
        switch self {
        case .int16: 16
        case .int24: 24
        case .float32: 32
        }
    }
}

public enum AudioFileError: Error, Equatable, LocalizedError {
    case unreadable(String)
    case unwritable(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let s): "No se puede leer el audio: \(s)"
        case .unwritable(let s): "No se puede escribir el audio: \(s)"
        }
    }
}

/// Implementación detrás de lectores y escritores. `.system` es `AVAudioFile` en el Mac y dr_* fuera;
/// `.portable` fuerza dr_* (los tests del Mac lo comparan con `AVAudioFile`).
enum AudioBackend {
    case system
    case portable

    var usesAVFoundation: Bool {
        #if canImport(AVFoundation)
        return self == .system
        #else
        return false
        #endif
    }
}

/// Ruta del sistema de ficheros en UTF-8 para C. En Windows quita la «/» que algunas versiones de Foundation
/// anteponen a la letra de unidad («/C:/…»).
func fileSystemPath(_ url: URL) -> String {
    let p = url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? url.path
    #if os(Windows)
    let chars = Array(p.utf8.prefix(3))
    if chars.count == 3, chars[0] == UInt8(ascii: "/"), chars[2] == UInt8(ascii: ":") { return String(p.dropFirst()) }
    #endif
    return p
}
