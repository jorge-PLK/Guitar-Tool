import AVFoundation
import Foundation

public enum MontageCodec: String, Codable, Sendable, CaseIterable {
    case hevc, h264

    var avCodec: AVVideoCodecType { self == .hevc ? .hevc : .h264 }
}

/// Formato del vídeo exportado (mini-spec Fase 7, «Exportación»: HEVC o H.264, resolución y fps de Ajustes).
public struct MontageExportSettings: Codable, Sendable, Equatable {
    public var codec: MontageCodec
    public var width: Int
    public var height: Int
    public var fps: Double

    public init(codec: MontageCodec, width: Int, height: Int, fps: Double) {
        self.codec = codec
        self.width = width
        self.height = height
        self.fps = fps
    }
}

public struct MontageExportSummary: Sendable, Equatable {
    public var url: URL
    public var settings: MontageExportSettings
    public var frames: Int
    /// Duración del vídeo (s): la del tramo.
    public var duration: Double
    public var hasAudio: Bool
}

/// Exporta el montaje (mini-spec Fase 7, «Exportación»): la composición con `MontageCompositor` leída con
/// `AVAssetReaderVideoCompositionOutput` y codificada con `AVAssetWriter`; de audio, el WAV de la mezcla ya
/// normalizada (lo hace AudioKit), multiplexado como AAC y recortado a la duración del vídeo.
///
/// Escribe en `<nombre>.partial.mov` junto al destino y solo al terminar sustituye el fichero (si existía): al
/// cancelar o fallar se borra el parcial y el vídeo anterior queda intacto.
public enum MontageExporter {
    /// AAC por canal (decisión propia).
    public static let aacBitRatePerChannel = 128_000
    /// Color del vídeo exportado: BT.709 (HD).
    static let colorProperties: [String: String] = [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
    ]

    public static func export(plan: MontagePlan, mixURL: URL?, settings: MontageExportSettings, to url: URL,
                              progress: (@Sendable (Double) -> Void)? = nil) async throws -> MontageExportSummary {
        var p = plan
        p.fps = settings.fps
        let builder = try await MontageBuilder.load(p, includeAudio: false)
        let preview = try builder.make(renderSize: CGSize(width: settings.width, height: settings.height), includeAudio: false)
        let partial = url.deletingPathExtension().appendingPathExtension("partial.mov")
        try? FileManager.default.removeItem(at: partial)
        var mix: Job.Mix?
        if let mixURL {
            let asset = AVURLAsset(url: mixURL)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first, let desc = try await track.load(.formatDescriptions).first,
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee
            else { throw MontageError.audio(mixURL.lastPathComponent) }
            mix = Job.Mix(asset: asset, track: track, sampleRate: asbd.mSampleRate, channels: Int(max(1, min(2, asbd.mChannelsPerFrame))))
        }
        let job = try Job(preview: preview, mix: mix, settings: settings, url: partial, progress: progress)
        do {
            let frames = try await withTaskCancellationHandler {
                try await job.run()
            } onCancel: {
                job.cancel()
            }
            try? FileManager.default.removeItem(at: url)
            do { try FileManager.default.moveItem(at: partial, to: url) } catch { throw MontageError.write("\(error)") }
            return MontageExportSummary(url: url, settings: settings, frames: frames, duration: preview.duration, hasAudio: mix != nil)
        } catch {
            job.abort()
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    /// Lectores, escritor y bombeo de muestras (las colas de `requestMediaDataWhenReady` comparten este estado).
    final class Job: @unchecked Sendable {
        let reader: AVAssetReader
        let videoOut: AVAssetReaderVideoCompositionOutput
        let audioReader: AVAssetReader?
        let audioOut: AVAssetReaderTrackOutput?
        let writer: AVAssetWriter
        let videoIn: AVAssetWriterInput
        let audioIn: AVAssetWriterInput?
        let duration: Double
        let progress: (@Sendable (Double) -> Void)?
        private let lock = NSLock()
        private var cancelled = false
        private var frames = 0

        struct Mix {
            let asset: AVURLAsset
            let track: AVAssetTrack
            let sampleRate: Double
            let channels: Int
        }

        init(preview: MontagePreview, mix: Mix?, settings: MontageExportSettings, url: URL, progress: (@Sendable (Double) -> Void)?) throws {
            self.progress = progress
            duration = preview.duration
            let comp = preview.composition
            let range = CMTimeRange(start: .zero, duration: VideoTakeWriter.time(preview.duration))
            do { reader = try AVAssetReader(asset: comp) } catch { throw MontageError.read("\(error)") }
            videoOut = AVAssetReaderVideoCompositionOutput(videoTracks: comp.tracks(withMediaType: .video),
                                                           videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            videoOut.videoComposition = preview.videoComposition
            videoOut.alwaysCopiesSampleData = false
            guard reader.canAdd(videoOut) else { throw MontageError.read("salida de vídeo") }
            reader.add(videoOut)
            reader.timeRange = range

            do { writer = try AVAssetWriter(outputURL: url, fileType: .mov) } catch { throw MontageError.write("\(error)") }
            writer.movieTimeScale = VideoTakeWriter.timescale
            videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: settings.codec.avCodec, AVVideoWidthKey: settings.width, AVVideoHeightKey: settings.height,
                AVVideoCompressionPropertiesKey: [AVVideoExpectedSourceFrameRateKey: settings.fps],
                // BT.709 explícito: sin él el codificador elige la matriz según el tamaño y un lector puede usar otra
                // (rojo 234 leído como 214 en la puerta).
                AVVideoColorPropertiesKey: MontageExporter.colorProperties
            ])
            videoIn.expectsMediaDataInRealTime = false
            videoIn.mediaTimeScale = VideoTakeWriter.timescale
            guard writer.canAdd(videoIn) else { throw MontageError.write("pista de vídeo") }
            writer.add(videoIn)

            if let mix {
                let ar: AVAssetReader
                do { ar = try AVAssetReader(asset: mix.asset) } catch { throw MontageError.read("\(error)") }
                let out = AVAssetReaderTrackOutput(track: mix.track, outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false
                ])
                ar.add(out)
                ar.timeRange = range
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: mix.sampleRate, AVNumberOfChannelsKey: mix.channels,
                    AVEncoderBitRateKey: MontageExporter.aacBitRatePerChannel * mix.channels
                ])
                input.expectsMediaDataInRealTime = false
                guard writer.canAdd(input) else { throw MontageError.write("pista de audio") }
                writer.add(input)
                audioReader = ar
                audioOut = out
                audioIn = input
            } else {
                audioReader = nil
                audioOut = nil
                audioIn = nil
            }
        }

        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }

        func abort() {
            reader.cancelReading()
            audioReader?.cancelReading()
            if writer.status == .writing { writer.cancelWriting() }
        }

        /// Devuelve los fotogramas escritos.
        func run() async throws -> Int {
            guard writer.startWriting() else { throw MontageError.write(writer.error.map { "\($0)" } ?? "startWriting") }
            writer.startSession(atSourceTime: .zero)
            guard reader.startReading() else { throw MontageError.read(reader.error.map { "\($0)" } ?? "startReading") }
            if let audioReader, !audioReader.startReading() {
                throw MontageError.read(audioReader.error.map { "\($0)" } ?? "startReading audio")
            }
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                let group = DispatchGroup()
                group.enter()
                pump(videoIn, queue: DispatchQueue(label: "montage.export.video"), next: { [videoOut] in videoOut.copyNextSampleBuffer() },
                     onSample: { [weak self] sb in self?.didWriteVideo(sb) }, done: { group.leave() })
                if let audioIn, let audioOut {
                    group.enter()
                    pump(audioIn, queue: DispatchQueue(label: "montage.export.audio"), next: { audioOut.copyNextSampleBuffer() },
                         onSample: { _ in }, done: { group.leave() })
                }
                group.notify(queue: .global()) { done.resume() }
            }
            if isCancelled { throw CancellationError() }
            if reader.status == .failed { throw MontageError.read(reader.error.map { "\($0)" } ?? "lectura de vídeo") }
            if let audioReader, audioReader.status == .failed {
                throw MontageError.read(audioReader.error.map { "\($0)" } ?? "lectura de audio")
            }
            await writer.finishWriting()
            guard writer.status == .completed else { throw MontageError.write(writer.error.map { "\($0)" } ?? "estado \(writer.status.rawValue)") }
            progress?(1)
            return lock.withLock { frames }
        }

        private func didWriteVideo(_ sb: CMSampleBuffer) {
            let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            lock.withLock { frames += 1 }
            progress?(min(1, max(0, t / max(1e-6, duration))))
        }

        private func pump(_ input: AVAssetWriterInput, queue: DispatchQueue, next: @escaping () -> CMSampleBuffer?,
                          onSample: @escaping (CMSampleBuffer) -> Void, done: @escaping () -> Void) {
            let pump = Pump(job: self, input: input, next: next, onSample: onSample, done: done)
            input.requestMediaDataWhenReady(on: queue) { pump.drain() }
        }
    }

    /// Copia muestras de `next` a `input` mientras acepte; al acabar, al fallar o al cancelar, cierra la entrada una
    /// vez. Solo se usa desde la cola de su entrada.
    final class Pump: @unchecked Sendable {
        let job: Job
        let input: AVAssetWriterInput
        let next: () -> CMSampleBuffer?
        let onSample: (CMSampleBuffer) -> Void
        let done: () -> Void
        private var finished = false

        init(job: Job, input: AVAssetWriterInput, next: @escaping () -> CMSampleBuffer?, onSample: @escaping (CMSampleBuffer) -> Void,
             done: @escaping () -> Void) {
            self.job = job
            self.input = input
            self.next = next
            self.onSample = onSample
            self.done = done
        }

        func drain() {
            guard !finished else { return }
            while input.isReadyForMoreMediaData {
                guard !job.isCancelled, job.writer.status == .writing, let sb = next() else {
                    finished = true
                    input.markAsFinished()
                    done()
                    return
                }
                if input.append(sb) { onSample(sb) }
            }
        }
    }
}
