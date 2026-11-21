#if canImport(AVFoundation)
import AVFoundation
import CoreVideo
#endif
import Foundation

/// Destino de los fotogramas de una toma con su tiempo del tema (el escritor real o uno de prueba).
public protocol VideoFrameSink: AnyObject, Sendable {
    /// Escribe `frame` con PTS = `songTime`. `false` si no se escribió (anterior al último, negativo, sin
    /// imagen o el codificador no admitía más).
    func append(_ frame: CameraFrame, songTime: Double) -> Bool
}

/// Resumen de un `video.mov` escrito.
public struct VideoTakeSummary: Sendable, Equatable {
    public var url: URL
    public var format: VideoFormat
    public var framesWritten: Int
    public var framesRejected: Int
    /// PTS (tiempo del tema) del primer y del último fotograma escritos.
    public var firstSongTime: Double?
    public var lastSongTime: Double?
}

public enum VideoTakeWriterError: Error, Equatable, Sendable {
    case cannotCreate(String)
    case failed(String)
    /// No llegó ningún fotograma con tiempo del tema (el fichero se borra).
    case empty
}

/// Escala de tiempo de los PTS en tiempo del tema (90 000, ver `VideoTakeWriter`), también sin CoreMedia.
let songTimescale: Int32 = 90_000

#if canImport(AVFoundation)
/// `takes/<id>/video.mov` (mini-spec Fase 6, «Cámara y sincronía»): HEVC, solo vídeo, con la resolución y los fps
/// reales, y **PTS = tiempo del tema** sin el desfase manual.
///
/// - La sesión del escritor empieza en 0 (`startSession(atSourceTime: .zero)`): el tiempo del fichero es el del
///   tema; una toma que empieza a mitad de tema lleva un tramo vacío delante (lista de ediciones), sin imágenes.
/// - Escala de tiempo de 90 000 en la pista y en la película (exacta para 24, 25, 30, 60 y 29,97 fps; la de 600 por
///   defecto redondearía el tramo vacío a 1,7 ms).
/// - Un fotograma perdido deja un hueco (el anterior dura más): los siguientes conservan su PTS.
/// - Se descartan los PTS negativos (antes del principio del tema) o que no avanzan.
/// - `realTime` (por defecto): si el codificador no admite más, el fotograma se descarta y se cuenta; sin él
///   (tests y ficheros), se espera.
public final class VideoTakeWriter: VideoFrameSink, @unchecked Sendable {
    /// Escala de tiempo de pista y película (decisión propia, ver arriba).
    public static let timescale: CMTimeScale = songTimescale
    /// Espera máxima por fotograma sin `realTime`.
    static let busyTimeoutSeconds = 5.0

    public let url: URL
    public let format: VideoFormat
    public let realTime: Bool
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let lock = NSLock()
    private var last: CMTime?
    private var first: CMTime?
    private var written = 0
    private var rejected = 0
    private var finished = false

    public init(url: URL, format: VideoFormat, realTime: Bool = true) throws {
        self.url = url
        self.format = format
        self.realTime = realTime
        try? FileManager.default.removeItem(at: url)
        do { writer = try AVAssetWriter(outputURL: url, fileType: .mov) } catch {
            throw VideoTakeWriterError.cannotCreate("\(error)")
        }
        writer.movieTimeScale = Self.timescale
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: format.width,
            AVVideoHeightKey: format.height,
            AVVideoCompressionPropertiesKey: [AVVideoExpectedSourceFrameRateKey: format.fps]
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = realTime
        input.mediaTimeScale = Self.timescale
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw VideoTakeWriterError.cannotCreate("no se puede añadir la pista de vídeo") }
        writer.add(input)
        guard writer.startWriting() else { throw VideoTakeWriterError.cannotCreate("\(writer.error.map { "\($0)" } ?? "startWriting")") }
        writer.startSession(atSourceTime: .zero)
    }

    /// Tiempo del tema → PTS en la escala del fichero.
    public static func time(_ songTime: Double) -> CMTime {
        CMTime(value: CMTimeValue((songTime * Double(timescale)).rounded()), timescale: timescale)
    }

    public func append(_ frame: CameraFrame, songTime: Double) -> Bool {
        lock.withLock {
            guard !finished, songTime.isFinite, songTime >= 0, let pb = frame.pixelBuffer else {
                rejected += 1
                return false
            }
            let pts = Self.time(songTime)
            if let last, CMTimeCompare(pts, last) <= 0 {
                rejected += 1
                return false
            }
            if !input.isReadyForMoreMediaData {
                guard !realTime else {
                    rejected += 1
                    return false
                }
                let deadline = Date().addingTimeInterval(Self.busyTimeoutSeconds)
                while !input.isReadyForMoreMediaData && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
            }
            guard input.isReadyForMoreMediaData, adaptor.append(pb, withPresentationTime: pts) else {
                rejected += 1
                return false
            }
            if first == nil { first = pts }
            last = pts
            written += 1
            return true
        }
    }

    /// Cierra el fichero. El último fotograma dura un periodo nominal.
    public func finish() async throws -> VideoTakeSummary {
        let (lastPTS, firstPTS, nWritten, nRejected) = lock.withLock { () -> (CMTime?, CMTime?, Int, Int) in
            finished = true
            return (last, first, written, rejected)
        }
        guard nWritten > 0 else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw VideoTakeWriterError.empty
        }
        input.markAsFinished()
        if let lastPTS {
            writer.endSession(atSourceTime: CMTimeAdd(lastPTS, Self.time(1 / max(1, format.fps))))
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw VideoTakeWriterError.failed(writer.error.map { "\($0)" } ?? "estado \(writer.status.rawValue)")
        }
        return VideoTakeSummary(url: url, format: format, framesWritten: nWritten, framesRejected: nRejected,
                                firstSongTime: firstPTS.map(CMTimeGetSeconds), lastSongTime: lastPTS.map(CMTimeGetSeconds))
    }

    /// Descarta el fichero.
    public func cancel() {
        lock.withLock { finished = true }
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: url)
    }
}
#endif
