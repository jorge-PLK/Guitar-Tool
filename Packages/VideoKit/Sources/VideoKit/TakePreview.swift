#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation

/// Un punch de la toma visto por la vista previa (los campos de `TakePunch` de Store que importan aquí).
public struct PreviewPunch: Sendable, Equatable, Codable {
    /// Tramo en tiempo del tema (s).
    public var start: Double
    public var end: Double
    /// `video.mov` del punch (`nil`: se grabó sin cámara; el tramo queda en negro).
    public var videoURL: URL?
    /// Desfase manual del punch (positivo: su imagen llega tarde).
    public var videoOffset: Double

    public init(start: Double, end: Double, videoURL: URL?, videoOffset: Double) {
        self.start = start
        self.end = end
        self.videoURL = videoURL
        self.videoOffset = videoOffset
    }
}

/// Tramo de la composición y de dónde sale su imagen.
public struct PreviewPiece: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case base
        case punch(Int)
    }
    /// Tramo en segundos de la composición (0 = `songStart` de la toma).
    public var start: Double
    public var end: Double
    public var source: Source
    /// Instante del fichero de vídeo (su PTS, tiempo del tema) que se ve en `start`.
    public var sourceStart: Double
}

public enum TakePreviewError: Error, Equatable, Sendable {
    case noAudio(String)
    case composition(String)
}

// `TakePreview` del Mac (composición AVFoundation). La de Windows (Media Foundation) está en `WindowsMontage.swift`.
#if canImport(AVFoundation)
/// Vista previa de una toma (mini-spec Fase 6, «Cámara y sincronía» y «Punch-in»): `processed.wav` (ya aplanado)
/// con el vídeo de la toma desplazado `videoOffset` y, en el tramo de cada punch, el vídeo del punch con su propio
/// desfase; fuera, la base. El último punch manda en su tramo. Nada se recodifica.
///
/// Tiempo: la composición empieza en el `songStart` de la toma (muestra 0 del WAV) y dura lo que el WAV. El
/// fotograma con PTS `p` (tiempo del tema) se ve en `p − desfase`; un tramo sin imagen (antes del primer
/// fotograma o tras el último) queda vacío.
///
/// **Barato al cambiar el desfase.** `load` abre los ficheros y lee sus pistas una vez; `composition(videoOffset:)`
/// solo inserta tramos de esas pistas (sin leer ni decodificar), así que la hoja «Ajustar desfase» puede
/// rehacerla en cada pulsación.
public final class TakePreview: @unchecked Sendable {
    public let songStart: Double
    /// Duración del WAV (s).
    public let duration: Double
    public let punches: [PreviewPunch]
    /// Los `AVAsset` se guardan: sus pistas no los retienen y sin ellos no se pueden insertar.
    private let audioAsset: AVURLAsset
    private let audioTrack: AVAssetTrack
    private let audioRange: CMTimeRange
    private let base: Source?
    private let punchSources: [Source?]
    /// Giro de la imagen (`VideoRotation`), en la `preferredTransform` de la pista de vídeo de la composición.
    public let rotation: VideoRotation

    /// Pista de vídeo cargada y el tramo (en PTS) en que tiene imagen.
    struct Source {
        let asset: AVURLAsset
        let track: AVAssetTrack
        let available: ClosedRange<Double>
        let transform: CGAffineTransform
        let naturalSize: CGSize
    }

    private init(songStart: Double, duration: Double, punches: [PreviewPunch], audioAsset: AVURLAsset, audioTrack: AVAssetTrack,
                 audioRange: CMTimeRange, base: Source?, punchSources: [Source?], rotation: VideoRotation) {
        self.rotation = rotation
        self.audioAsset = audioAsset
        self.songStart = songStart
        self.duration = duration
        self.punches = punches
        self.audioTrack = audioTrack
        self.audioRange = audioRange
        self.base = base
        self.punchSources = punchSources
    }

    /// Abre la toma: `audioURL` (`processed.wav`), su `songStart`, el vídeo de la toma (o `nil`), sus punches en orden y
    /// el giro de la imagen.
    public static func load(audioURL: URL, songStart: Double, videoURL: URL?, punches: [PreviewPunch],
                            rotation: VideoRotation = .none) async throws -> TakePreview {
        let audio = AVURLAsset(url: audioURL)
        guard let track = try await audio.loadTracks(withMediaType: .audio).first else {
            throw TakePreviewError.noAudio(audioURL.lastPathComponent)
        }
        let range = try await track.load(.timeRange)
        var sources: [Source?] = []
        for p in punches { sources.append(try await source(p.videoURL)) }
        return TakePreview(songStart: songStart, duration: CMTimeGetSeconds(range.duration), punches: punches, audioAsset: audio, audioTrack: track,
                           audioRange: range, base: try await source(videoURL), punchSources: sources, rotation: rotation)
    }

    /// También la usan `MontageBuilder` y `GuitarFramer`.
    static func source(_ url: URL?) async throws -> Source? {
        guard let url else { return nil }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let (segments, transform, size) = try await track.load(.segments, .preferredTransform, .naturalSize)
        let full = segments.filter { !$0.isEmpty }.map(\.timeMapping.target)
        guard let first = full.first, let last = full.last else { return nil }
        let lo = CMTimeGetSeconds(first.start), hi = CMTimeGetSeconds(CMTimeRangeGetEnd(last))
        guard hi > lo else { return nil }
        return Source(asset: asset, track: track, available: lo...hi, transform: transform, naturalSize: size)
    }

    /// Plan de tramos para un desfase (función pura; `composition` la sigue). `punchOffsets` sustituye los desfases
    /// de los punches si se da (mismo orden).
    public func pieces(videoOffset: Double, punchOffsets: [Double]? = nil) -> [PreviewPiece] {
        Self.plan(songStart: songStart, duration: duration, base: base.map(\.available), baseOffset: videoOffset,
                  punches: punches.enumerated().map { i, p in
                      (p.start, p.end, punchSources[i]?.available, punchOffsets?[safe: i] ?? p.videoOffset)
                  })
    }

    /// Tramos de imagen: base en todo el tramo de la toma, cada punch encima en el suyo (el último manda), y cada
    /// tramo recortado a lo que su fichero tiene. El cálculo es `TakePreviewPlan` (puro, también en Windows).
    static func plan(songStart: Double, duration: Double, base: ClosedRange<Double>?, baseOffset: Double,
                     punches: [(start: Double, end: Double, available: ClosedRange<Double>?, offset: Double)]) -> [PreviewPiece] {
        TakePreviewPlan.pieces(songStart: songStart, duration: duration, base: base, baseOffset: baseOffset,
                               punches: punches.map { TakePreviewPlan.Punch(start: $0.start, end: $0.end, available: $0.available, offset: $0.offset) })
    }

    /// Composición de vídeo + toma procesada para un desfase. Barata: no lee ficheros.
    public func composition(videoOffset: Double, punchOffsets: [Double]? = nil) throws -> AVMutableComposition {
        let comp = AVMutableComposition()
        func t(_ s: Double) -> CMTime { VideoTakeWriter.time(s) }
        guard let a = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw TakePreviewError.composition("pista de audio")
        }
        do { try a.insertTimeRange(audioRange, of: audioTrack, at: .zero) } catch { throw TakePreviewError.composition("\(error)") }
        let plan = pieces(videoOffset: videoOffset, punchOffsets: punchOffsets)
        guard !plan.isEmpty, let v = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return comp
        }
        if let s = base ?? punchSources.compactMap({ $0 }).first {
            // Giro de la toma después de la transformación del fichero (las grabadas por la app traen la identidad).
            v.preferredTransform = s.transform.concatenating(rotation.transform(naturalSize: s.naturalSize))
        }
        var cursor = CMTime.zero
        for p in plan {
            let src: Source? = switch p.source {
            case .base: base
            case .punch(let i): punchSources[i]
            }
            guard let src else { continue }
            let at = t(p.start), end = t(p.end)
            if CMTimeCompare(at, cursor) > 0 {
                v.insertEmptyTimeRange(CMTimeRange(start: cursor, end: at))
            }
            let start = CMTimeMaximum(at, cursor)
            guard CMTimeCompare(end, start) > 0 else { continue }
            let from = t(p.sourceStart + CMTimeGetSeconds(CMTimeSubtract(start, at)))
            do {
                try v.insertTimeRange(CMTimeRange(start: from, duration: CMTimeSubtract(end, start)), of: src.track, at: start)
            } catch { throw TakePreviewError.composition("\(error)") }
            cursor = end
        }
        return comp
    }
}
#endif

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
