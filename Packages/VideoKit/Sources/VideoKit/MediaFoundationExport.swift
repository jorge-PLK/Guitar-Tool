#if os(Windows)
import Foundation
import NativeAudioFile

/// Cebado del AAC de Media Foundation (plan, «Fase 7c», paso 7, partes 7.2 y 7.9; P8, «d · Media Foundation»).
///
/// El codificador AAC de Media Foundation no añade cebado; es AVFoundation quien recorta 2112 muestras al leer. **Sin
/// compensar** (decisión de Jorge del 19/11/2026, sin opción de «compatibilidad Apple»): el audio se escribe tal cual,
/// sin silencio delante, sin iTunSMPB y sin lista de ediciones de audio. Media Foundation y ffmpeg leen el audio a 0 ms
/// del vídeo; los lectores de Apple lo oyen `samples` muestras antes (−44,0 ms a 48 kHz, −47,9 ms a 44,1 kHz).
/// La lista de ediciones del vídeo (tramo vacío delante para el PTS del tema) no cambia.
enum AACPriming {
    /// Lo que recorta AVFoundation al leer un AAC de Media Foundation, en muestras (el mismo a 44,1 y a 48 kHz). Solo
    /// sirve para comprobar el desfase en los lectores de Apple; el exportador no lo usa.
    static let samples = 2112
}

extension MontageExporter {
    /// Bytes por segundo del AAC de Media Foundation: admite 12 000, 16 000, 20 000 y 24 000 (96 a 192 kb/s en total).
    /// Se usa el más cercano por debajo de `aacBitRatePerChannel · canales` (mono 128 kb/s; estéreo 192, no 256).
    static func aacBytesPerSecond(channels: Int) -> Int {
        let wanted = aacBitRatePerChannel * channels / 8
        return [24_000, 20_000, 16_000, 12_000].first { $0 <= wanted } ?? 12_000
    }

    /// Frecuencias que acepta el AAC de Media Foundation.
    static let aacSampleRates: Set<Int> = [44_100, 48_000]

    /// Codifica `frames` y la mezcla (recortada a la duración del vídeo) en `url`, con parcial y sustitución como en el
    /// Mac. Siempre H.264 aunque se pida HEVC (Jorge, 21/11/2026, W2-E1; el resumen dice el usado).
    static func write(frames: any MontageFrameSource, mixURL: URL?, settings: MontageExportSettings, to url: URL,
                      progress: (@Sendable (Double) -> Void)?) async throws -> MontageExportSummary {
        let partial = url.deletingPathExtension().appendingPathExtension("partial." + settings.container.fileExtension)
        try? FileManager.default.removeItem(at: partial)
        var mix: DecodedAudio?
        if let mixURL {
            do { mix = try NativeAudioFile.read(mixURL) } catch { throw MontageError.audio(mixURL.lastPathComponent) }
            guard let m = mix, m.frameCount > 0, aacSampleRates.contains(Int(m.sampleRate)) else { throw MontageError.audio(mixURL.lastPathComponent) }
        }
        var used = settings
        if !MontageCodec.supported.contains(settings.codec) { used.codec = MontageCodec.supported[0] }
        let job = MuxJob(frames: frames, mix: mix, settings: used, url: partial, progress: progress)
        do {
            let n = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (done: CheckedContinuation<Int, Error>) in
                    DispatchQueue.global(qos: .userInitiated).async { done.resume(with: Result { try job.run() }) }
                }
            } onCancel: {
                job.cancel()
            }
            try? FileManager.default.removeItem(at: url)
            do { try FileManager.default.moveItem(at: partial, to: url) } catch { throw MontageError.write("\(error)") }
            progress?(1)
            return MontageExportSummary(url: url, settings: used, frames: n, duration: frames.duration, hasAudio: mix != nil)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    /// Bombeo en un hilo propio: vídeo fotograma a fotograma y, entre medias, el audio hasta el mismo instante.
    final class MuxJob: @unchecked Sendable {
        let frames: any MontageFrameSource
        let mix: DecodedAudio?
        let settings: MontageExportSettings
        let url: URL
        let progress: (@Sendable (Double) -> Void)?
        private let lock = NSLock()
        private var cancelled = false

        init(frames: any MontageFrameSource, mix: DecodedAudio?, settings: MontageExportSettings, url: URL,
             progress: (@Sendable (Double) -> Void)?) {
            self.frames = frames
            self.mix = mix
            self.settings = settings
            self.url = url
            self.progress = progress
        }

        func cancel() { lock.withLock { cancelled = true } }
        var isCancelled: Bool { lock.withLock { cancelled } }

        func run() throws -> Int {
            let fps = settings.fps
            let channels = mix.map { max(1, min(2, $0.channelCount)) } ?? 0
            let sr = mix.map { Int($0.sampleRate) } ?? 0
            let pcm = mix.map { Self.interleaved($0, channels: channels, frames: Int((frames.duration * $0.sampleRate).rounded())) } ?? []
            let audioFrames = channels > 0 ? pcm.count / channels : 0
            var muxer: MediaFoundationMuxer? = try {
                do {
                    return try MediaFoundationMuxer(url: url, config: .init(
                        width: settings.width, height: settings.height, fps: fps, codec: settings.codec,
                        videoBitrate: MediaFoundationMuxer.exportBitrate(width: settings.width, height: settings.height, fps: fps, codec: settings.codec),
                        audio: channels > 0 ? .init(sampleRate: sr, channels: channels, bytesPerSecond: MontageExporter.aacBytesPerSecond(channels: channels)) : nil,
                        realTime: false))
                } catch { throw MontageError.write("\(error)") }
            }()
            defer { muxer = nil }
            var audioDone = 0   // muestras del PCM ya escritas
            let total = frames.frameCount
            for i in 0..<total {
                if isCancelled { throw CancellationError() }
                let pb: FramePixelBuffer
                do { pb = try frames.frame(i) } catch { throw MontageError.composition("\(error)") }
                let t0 = MF.ticks(Double(i) / fps), t1 = MF.ticks(Double(i + 1) / fps)
                do { try muxer?.writeVideo(pb, time: t0, duration: t1 - t0) } catch { throw MontageError.write("\(error)") }
                if channels > 0 {
                    let until = i == total - 1 ? audioFrames : min(audioFrames, Int((Double(i + 1) / fps * Double(sr)).rounded()))
                    if until > audioDone {
                        try Self.writeAudio(muxer, pcm, channels: channels, from: audioDone, to: until, sampleRate: sr)
                        audioDone = until
                    }
                }
                progress?(min(1, Double(i + 1) / Double(max(1, total))))
            }
            if channels > 0, audioFrames > audioDone {
                try Self.writeAudio(muxer, pcm, channels: channels, from: audioDone, to: audioFrames, sampleRate: sr)
            }
            do { try muxer?.finalize() } catch { throw MontageError.write("\(error)") }
            muxer = nil
            return total
        }

        static func writeAudio(_ muxer: MediaFoundationMuxer?, _ pcm: [Int16], channels: Int, from: Int, to: Int, sampleRate: Int) throws {
            do {
                try pcm.withUnsafeBufferPointer { p in
                    try muxer?.writeAudio(UnsafeBufferPointer(rebasing: p[(from * channels)..<(to * channels)]),
                                          time: Int64(from) * 10_000_000 / Int64(sampleRate))
                }
            } catch { throw MontageError.write("\(error)") }
        }

        /// PCM de 16 bits entrelazado: la mezcla sin cebado (ver `AACPriming`), recortada a `frames` muestras.
        static func interleaved(_ a: DecodedAudio, channels: Int, frames: Int) -> [Int16] {
            let n = min(frames, a.frameCount)
            var out = [Int16](repeating: 0, count: n * channels)
            for c in 0..<channels {
                let src = a.channels[min(c, a.channelCount - 1)]
                for i in 0..<n {
                    out[i * channels + c] = Int16(max(-1, min(1, src[i])) * 32767)
                }
            }
            return out
        }
    }
}

#endif
