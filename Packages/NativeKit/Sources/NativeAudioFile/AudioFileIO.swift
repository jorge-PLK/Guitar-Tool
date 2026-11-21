import CDrAudio
import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Lector por bloques (como `AVAudioFile(forReading:commonFormat: .pcmFormatFloat32, interleaved: false)`).
/// No es seguro entre hilos: un lector por hilo.
public final class AudioFileReader {
    static let blockFrames = 1 << 16

    public let sampleRate: Double
    public let channelCount: Int
    /// Longitud en fotogramas (`AVAudioFile.length`).
    public let frameCount: Int
    /// Próximo fotograma que se leerá (`AVAudioFile.framePosition`).
    public private(set) var framePosition = 0

    private let impl: ReaderImpl

    public convenience init(url: URL) throws { try self.init(url: url, backend: .system) }

    init(url: URL, backend: AudioBackend) throws {
        if backend.usesAVFoundation {
            #if canImport(AVFoundation)
            impl = try AVReader(url: url)
            #else
            fatalError("sin AVFoundation")
            #endif
        } else {
            impl = try DrReader(url: url)
        }
        sampleRate = impl.sampleRate
        channelCount = impl.channelCount
        frameCount = impl.frameCount
    }

    /// Lee hasta `maxFrames` fotogramas en `channels[c]` (uno por canal, con sitio para `maxFrames`).
    /// Devuelve los leídos; 0 al final.
    public func read(into channels: [UnsafeMutablePointer<Float>], maxFrames: Int) throws -> Int {
        precondition(channels.count == channelCount, "AudioFileReader: hacen falta \(channelCount) canales")
        let want = min(maxFrames, frameCount - framePosition)
        guard want > 0 else { return 0 }
        let got = try impl.read(into: channels, frames: want)
        framePosition += got
        return got
    }

    /// Lee hasta `maxFrames` fotogramas; arrays vacíos al final.
    public func read(maxFrames: Int) throws -> [[Float]] {
        let want = max(0, min(maxFrames, frameCount - framePosition))
        var out = [[Float]](repeating: [Float](repeating: 0, count: want), count: channelCount)
        guard want > 0 else { return out }
        let got = try NativeAudioFile.withPointers(&out, offset: 0) { try read(into: $0, maxFrames: want) }
        if got < want { for c in out.indices { out[c].removeLast(want - got) } }
        return out
    }

    /// Salta al fotograma `frame` (0...frameCount).
    public func seek(toFrame frame: Int) throws {
        guard frame >= 0, frame <= frameCount else { throw AudioFileError.unreadable("posición \(frame) fuera de 0...\(frameCount)") }
        try impl.seek(frame)
        framePosition = frame
    }
}

/// Escritor de WAV por bloques. `close()` (o el `deinit`) completa la cabecera.
public final class AudioFileWriter {
    public let sampleRate: Double
    public let channelCount: Int
    public let format: WAVSampleFormat
    private var impl: WriterImpl?

    public convenience init(url: URL, sampleRate: Double, channelCount: Int, format: WAVSampleFormat) throws {
        try self.init(url: url, sampleRate: sampleRate, channelCount: channelCount, format: format, backend: .system)
    }

    init(url: URL, sampleRate: Double, channelCount: Int, format: WAVSampleFormat, backend: AudioBackend) throws {
        guard channelCount > 0, sampleRate > 0 else {
            throw AudioFileError.unwritable("\(channelCount) canales a \(sampleRate) Hz")
        }
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.format = format
        if backend.usesAVFoundation {
            #if canImport(AVFoundation)
            impl = try AVWriter(url: url, sampleRate: sampleRate, channels: channelCount, format: format)
            #endif
        } else {
            impl = try DrWriter(url: url, sampleRate: sampleRate, channels: channelCount, format: format)
        }
    }

    deinit { try? impl?.close() }

    /// Escribe `count` fotogramas, un puntero por canal.
    public func write(_ channels: [UnsafePointer<Float>], count: Int) throws {
        precondition(channels.count == channelCount, "AudioFileWriter: hacen falta \(channelCount) canales")
        guard let impl else { throw AudioFileError.unwritable("escritor cerrado") }
        guard count > 0 else { return }
        try impl.write(channels, count: count)
    }

    /// Escribe canales enteros (todos de la misma longitud).
    public func write(_ channels: [[Float]]) throws {
        precondition(channels.count == channelCount, "AudioFileWriter: hacen falta \(channelCount) canales")
        let n = channels.first?.count ?? 0
        precondition(channels.allSatisfy { $0.count == n }, "AudioFileWriter: canales de distinta longitud")
        func nest(_ i: Int, _ acc: [UnsafePointer<Float>]) throws {
            if i == channels.count { try write(acc, count: n); return }
            try channels[i].withUnsafeBufferPointer { try nest(i + 1, acc + [$0.baseAddress!]) }
        }
        try nest(0, [])
    }

    public func close() throws {
        guard let impl else { return }
        self.impl = nil
        try impl.close()
    }
}

// MARK: - Implementaciones

protocol ReaderImpl: AnyObject {
    var sampleRate: Double { get }
    var channelCount: Int { get }
    var frameCount: Int { get }
    func read(into channels: [UnsafeMutablePointer<Float>], frames: Int) throws -> Int
    func seek(_ frame: Int) throws
}

protocol WriterImpl: AnyObject {
    func write(_ channels: [UnsafePointer<Float>], count: Int) throws
    func close() throws
}

/// dr_wav / dr_flac / dr_mp3.
final class DrReader: ReaderImpl {
    let handle: OpaquePointer
    let sampleRate: Double
    let channelCount: Int
    let frameCount: Int
    private var scratch: [Float] = []

    init(url: URL) throws {
        guard let h = tfaudio_open(fileSystemPath(url)) else {
            throw AudioFileError.unreadable(url.lastPathComponent)
        }
        handle = h
        sampleRate = Double(tfaudio_sample_rate(h))
        channelCount = Int(tfaudio_channels(h))
        frameCount = Int(tfaudio_frame_count(h))
    }

    deinit { tfaudio_close(handle) }

    func read(into channels: [UnsafeMutablePointer<Float>], frames: Int) throws -> Int {
        let ch = channelCount
        if scratch.count < frames * ch { scratch = [Float](repeating: 0, count: frames * ch) }
        let got = scratch.withUnsafeMutableBufferPointer { s -> Int in
            let p = s.baseAddress!
            let n = Int(tfaudio_read_f32(handle, p, UInt64(frames)))
            for c in 0..<ch {
                let dst = channels[c]
                for i in 0..<n { dst[i] = p[i * ch + c] }
            }
            return n
        }
        return got
    }

    func seek(_ frame: Int) throws {
        guard tfaudio_seek(handle, UInt64(frame)) != 0 else { throw AudioFileError.unreadable("seek a \(frame)") }
    }
}

final class DrWriter: WriterImpl {
    let handle: OpaquePointer
    let channels: Int
    private var scratch: [Float] = []

    init(url: URL, sampleRate: Double, channels: Int, format: WAVSampleFormat) throws {
        guard let h = tfaudio_writer_open(fileSystemPath(url), UInt32(sampleRate.rounded()), UInt32(channels),
                                          Int32(format.bits)) else {
            throw AudioFileError.unwritable(url.lastPathComponent)
        }
        handle = h
        self.channels = channels
    }

    func write(_ src: [UnsafePointer<Float>], count: Int) throws {
        let ch = channels
        if scratch.count < count * ch { scratch = [Float](repeating: 0, count: count * ch) }
        let written = scratch.withUnsafeMutableBufferPointer { s -> Int in
            let p = s.baseAddress!
            for c in 0..<ch {
                let from = src[c]
                for i in 0..<count { p[i * ch + c] = from[i] }
            }
            return Int(tfaudio_writer_write_f32(handle, p, UInt64(count)))
        }
        if written != count { throw AudioFileError.unwritable("escritos \(written) de \(count) fotogramas") }
    }

    func close() throws {
        guard tfaudio_writer_close(handle) != 0 else { throw AudioFileError.unwritable("cierre") }
    }
}

#if canImport(AVFoundation)
/// `AVAudioFile` como hoy en los paquetes: float32 no entrelazado.
final class AVReader: ReaderImpl {
    let file: AVAudioFile
    let sampleRate: Double
    let channelCount: Int
    let frameCount: Int
    private var buffer: AVAudioPCMBuffer?

    init(url: URL) throws {
        do {
            file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw AudioFileError.unreadable("\(url.lastPathComponent): \(error.localizedDescription)")
        }
        sampleRate = file.processingFormat.sampleRate
        channelCount = Int(file.processingFormat.channelCount)
        frameCount = Int(file.length)
    }

    func read(into channels: [UnsafeMutablePointer<Float>], frames: Int) throws -> Int {
        if buffer == nil || Int(buffer!.frameCapacity) < frames {
            buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames))
        }
        guard let buf = buffer else { throw AudioFileError.unreadable("sin búfer para \(file.processingFormat)") }
        do {
            try file.read(into: buf, frameCount: AVAudioFrameCount(frames))
        } catch {
            throw AudioFileError.unreadable(error.localizedDescription)
        }
        let n = Int(buf.frameLength)
        let data = buf.floatChannelData!
        for c in 0..<channelCount { channels[c].update(from: data[c], count: n) }
        return n
    }

    func seek(_ frame: Int) throws { file.framePosition = AVAudioFramePosition(frame) }
}

final class AVWriter: WriterImpl {
    let file: AVAudioFile
    let channels: Int
    private var buffer: AVAudioPCMBuffer?

    init(url: URL, sampleRate: Double, channels: Int, format: WAVSampleFormat) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: format.bits,
            AVLinearPCMIsFloatKey: format == .float32,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw AudioFileError.unwritable("\(url.lastPathComponent): \(error.localizedDescription)")
        }
        self.channels = channels
    }

    func write(_ src: [UnsafePointer<Float>], count: Int) throws {
        let block = AudioFileReader.blockFrames
        if buffer == nil {
            buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(block))
        }
        guard let buf = buffer else { throw AudioFileError.unwritable("sin búfer") }
        var pos = 0
        while pos < count {
            let n = min(block, count - pos)
            let data = buf.floatChannelData!
            for c in 0..<channels { data[c].update(from: src[c] + pos, count: n) }
            buf.frameLength = AVAudioFrameCount(n)
            do { try file.write(from: buf) } catch { throw AudioFileError.unwritable(error.localizedDescription) }
            pos += n
        }
    }

    func close() throws { file.close() }
}
#endif
