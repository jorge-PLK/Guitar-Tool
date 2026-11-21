#if canImport(AVFoundation)
import AVFoundation
#else
import NativePlatform
#endif
import Foundation

public enum MontageCodec: String, Codable, Sendable, CaseIterable {
    case hevc, h264

    #if canImport(AVFoundation)
    var avCodec: AVVideoCodecType { self == .hevc ? .hevc : .h264 }
    #endif
}

/// Contenedor del fichero exportado (Jorge, 17/11/2026: selector MOV / MP4 en Exportación). Mismo vídeo y mismo
/// AAC en los dos, escritos directamente por `AVAssetWriter`.
public enum MontageVideoContainer: String, Codable, Sendable, CaseIterable {
    case mov, mp4

    /// Extensión que debe llevar la URL de destino (sin punto).
    public var fileExtension: String { rawValue }
    #if canImport(AVFoundation)
    public var fileType: AVFileType { self == .mov ? .mov : .mp4 }
    #endif
}

/// Formato del vídeo exportado (mini-spec Fase 7, «Exportación»: HEVC o H.264, resolución y fps de Ajustes;
/// contenedor MOV o MP4).
public struct MontageExportSettings: Codable, Sendable, Equatable {
    public var codec: MontageCodec
    public var width: Int
    public var height: Int
    public var fps: Double
    public var container: MontageVideoContainer

    public init(codec: MontageCodec, width: Int, height: Int, fps: Double, container: MontageVideoContainer = .mov) {
        self.codec = codec
        self.width = width
        self.height = height
        self.fps = fps
        self.container = container
    }

    private enum CodingKeys: String, CodingKey { case codec, width, height, fps, container }

    /// Ajustes guardados antes de existir el contenedor: `.mov`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        codec = try c.decode(MontageCodec.self, forKey: .codec)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        fps = try c.decode(Double.self, forKey: .fps)
        container = try c.decodeIfPresent(MontageVideoContainer.self, forKey: .container) ?? .mov
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

#if !canImport(AVFoundation)
/// Windows (plan, «Fase 7c», paso 7, parte 7.2): misma API que en el Mac. La escritura y el mux son de Media
/// Foundation (`write(frames:…)`); los fotogramas compuestos los da el compositor Direct2D (parte 7.9) por
/// `frameSource(for:settings:)`: el `MontagePreview` de Windows es la fuente.
public enum MontageExporter {
    /// AAC por canal (decisión propia).
    public static let aacBitRatePerChannel = 128_000

    public static func export(plan: MontagePlan, mixURL: URL?, settings: MontageExportSettings, to url: URL,
                              progress: (@Sendable (Double) -> Void)? = nil) async throws -> MontageExportSummary {
        guard url.pathExtension.lowercased() == settings.container.fileExtension else {
            throw MontageError.containerMismatch(expected: settings.container.fileExtension, got: url.pathExtension)
        }
        var p = plan
        p.fps = settings.fps
        let frames = try await frameSource(for: p, settings: settings)
        #if os(Windows)
        return try await write(frames: frames, mixURL: mixURL, settings: settings, to: url, progress: progress)
        #else
        throw PlatformError.unsupported("sin Media Foundation")
        #endif
    }

    /// Costura con el compositor (parte 7.9): fotogramas del plan ya compuestos al tamaño de `settings`.
    static func frameSource(for plan: MontagePlan, settings: MontageExportSettings) async throws -> any MontageFrameSource {
        #if os(Windows)
        // Lector (Media Foundation) → compositor (Direct2D), fotograma a fotograma en la rejilla de `plan.fps`.
        let builder = try await MontageBuilder.load(plan, includeAudio: false)
        return try builder.make(renderSize: CGSize(width: settings.width, height: settings.height), includeAudio: false)
        #else
        throw PlatformError.unsupported("sin compositor")
        #endif
    }
}

/// Fotogramas compuestos de un montaje (los da el compositor; el exportador solo los codifica).
protocol MontageFrameSource: Sendable {
    /// Fotogramas del tramo (`duration · fps` cuantizado).
    var frameCount: Int { get }
    /// Duración del vídeo (s).
    var duration: Double { get }
    /// Fotograma `index` (0 en el principio del tramo), BGRA o NV12 del tamaño de exportación.
    func frame(_ index: Int) throws -> FramePixelBuffer
}
#else

/// Exporta el montaje (mini-spec Fase 7, «Exportación»): la composición con `MontageCompositor` leída con
/// `AVAssetReaderVideoCompositionOutput` y codificada con `AVAssetWriter`; de audio, el WAV de la mezcla ya
/// normalizada (lo hace AudioKit), multiplexado como AAC y recortado a la duración del vídeo.
///
/// Escribe en `<nombre>.partial.<mov|mp4>` junto al destino y solo al terminar sustituye el fichero (si existía): al
/// cancelar o fallar se borra el parcial y el vídeo anterior queda intacto.
///
/// La URL la decide quien llama y su extensión debe ser la del contenedor (`MontageVideoContainer.fileExtension`,
/// sin distinguir mayúsculas); si no, `MontageError.containerMismatch` antes de escribir nada: un `.mov` con
/// contenido MP4 (o al revés) confundiría al usuario y a otros programas.
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
        // Con otros fps, los tramos se vuelven a cuantizar (`MontagePlan.fps`): el WAV solo dura lo mismo que el vídeo si
        // se mezcló con los tramos de un plan con estos fps (como hace la app).
        guard url.pathExtension.lowercased() == settings.container.fileExtension else {
            throw MontageError.containerMismatch(expected: settings.container.fileExtension, got: url.pathExtension)
        }
        var p = plan
        p.fps = settings.fps
        let builder = try await MontageBuilder.load(p, includeAudio: false)
        let preview = try builder.make(renderSize: CGSize(width: settings.width, height: settings.height), includeAudio: false)
        let partial = url.deletingPathExtension().appendingPathExtension("partial." + settings.container.fileExtension)
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

    /// Comprueba la composición antes de leerla (`AVVideoComposition.isValid`, con un delegado que dice qué falla):
    /// si no, `AVAssetReader` la rechaza con -11841 (`AVErrorInvalidVideoComposition`) sin decir por qué.
    static func validate(_ preview: MontagePreview, range: CMTimeRange) throws {
        let comp = preview.composition
        let check = CompositionCheck()
        let ok = preview.videoComposition.isValid(for: comp.tracks, assetDuration: comp.duration, timeRange: range, validationDelegate: check)
        guard !ok || !check.problems.isEmpty else { return }
        let detail = check.problems.isEmpty ? "sin detalle de AVFoundation" : check.problems.joined(separator: "; ")
        throw MontageError.composition("composición de vídeo no válida: \(detail) (composición \(CompositionCheck.text(comp.duration)), "
            + "lectura \(CompositionCheck.text(range)))")
    }

    /// Recoge lo que `AVVideoComposition.isValid` encuentra, en texto para el mensaje de error.
    final class CompositionCheck: NSObject, AVVideoCompositionValidationHandling {
        private(set) var problems: [String] = []

        static func text(_ t: CMTime) -> String { t.isNumeric ? String(format: "%.4f s", CMTimeGetSeconds(t)) : "\(t)" }
        static func text(_ r: CMTimeRange) -> String { "[\(text(r.start)), \(text(CMTimeRangeGetEnd(r))))" }

        func videoComposition(_ videoComposition: AVVideoComposition,
                              shouldContinueValidatingAfterFindingInvalidValueForKey key: String) -> Bool {
            problems.append("valor no válido en \(key)")
            return true
        }

        func videoComposition(_ videoComposition: AVVideoComposition,
                              shouldContinueValidatingAfterFindingEmptyTimeRange timeRange: CMTimeRange) -> Bool {
            problems.append("tramo sin instrucción \(Self.text(timeRange))")
            return true
        }

        func videoComposition(_ videoComposition: AVVideoComposition,
                              shouldContinueValidatingAfterFindingInvalidTimeRangeIn instruction: any AVVideoCompositionInstructionProtocol) -> Bool {
            problems.append("instrucción con tramo no válido \(Self.text(instruction.timeRange))")
            return true
        }

        func videoComposition(_ videoComposition: AVVideoComposition,
                              shouldContinueValidatingAfterFindingInvalidTrackIDIn instruction: any AVVideoCompositionInstructionProtocol,
                              layerInstruction: AVVideoCompositionLayerInstruction, asset: AVAsset) -> Bool {
            problems.append("pista \(layerInstruction.trackID) inexistente en la instrucción \(Self.text(instruction.timeRange))")
            return true
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
            try MontageExporter.validate(preview, range: range)
            do { reader = try AVAssetReader(asset: comp) } catch { throw MontageError.read("\(error)") }
            videoOut = AVAssetReaderVideoCompositionOutput(videoTracks: comp.tracks(withMediaType: .video),
                                                           videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            videoOut.videoComposition = preview.videoComposition
            videoOut.alwaysCopiesSampleData = false
            guard reader.canAdd(videoOut) else { throw MontageError.read("salida de vídeo") }
            reader.add(videoOut)
            reader.timeRange = range

            do { writer = try AVAssetWriter(outputURL: url, fileType: settings.container.fileType) } catch { throw MontageError.write("\(error)") }
            writer.movieTimeScale = VideoTakeWriter.timescale
            // MP4 para compartir: índice (`moov`) al principio, reproducible mientras se descarga. El `.mov` no cambia.
            // HEVC sale con la etiqueta `hvc1` (la de AVAssetWriter; lo comprueba la puerta MP4).
            if settings.container == .mp4 { writer.shouldOptimizeForNetworkUse = true }
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
#endif
