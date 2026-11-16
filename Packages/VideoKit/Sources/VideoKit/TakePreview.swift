import AVFoundation
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

    /// Pista de vídeo cargada y el tramo (en PTS) en que tiene imagen.
    struct Source {
        let asset: AVURLAsset
        let track: AVAssetTrack
        let available: ClosedRange<Double>
        let transform: CGAffineTransform
    }

    private init(songStart: Double, duration: Double, punches: [PreviewPunch], audioAsset: AVURLAsset, audioTrack: AVAssetTrack,
                 audioRange: CMTimeRange, base: Source?, punchSources: [Source?]) {
        self.audioAsset = audioAsset
        self.songStart = songStart
        self.duration = duration
        self.punches = punches
        self.audioTrack = audioTrack
        self.audioRange = audioRange
        self.base = base
        self.punchSources = punchSources
    }

    /// Abre la toma: `audioURL` (`processed.wav`), su `songStart`, el vídeo de la toma (o `nil`) y sus punches en orden.
    public static func load(audioURL: URL, songStart: Double, videoURL: URL?, punches: [PreviewPunch]) async throws -> TakePreview {
        let audio = AVURLAsset(url: audioURL)
        guard let track = try await audio.loadTracks(withMediaType: .audio).first else {
            throw TakePreviewError.noAudio(audioURL.lastPathComponent)
        }
        let range = try await track.load(.timeRange)
        var sources: [Source?] = []
        for p in punches { sources.append(try await source(p.videoURL)) }
        return TakePreview(songStart: songStart, duration: CMTimeGetSeconds(range.duration), punches: punches, audioAsset: audio, audioTrack: track,
                           audioRange: range, base: try await source(videoURL), punchSources: sources)
    }

    /// También la usan `MontageBuilder` y `GuitarFramer`.
    static func source(_ url: URL?) async throws -> Source? {
        guard let url else { return nil }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let (segments, transform) = try await track.load(.segments, .preferredTransform)
        let full = segments.filter { !$0.isEmpty }.map(\.timeMapping.target)
        guard let first = full.first, let last = full.last else { return nil }
        let lo = CMTimeGetSeconds(first.start), hi = CMTimeGetSeconds(CMTimeRangeGetEnd(last))
        guard hi > lo else { return nil }
        return Source(asset: asset, track: track, available: lo...hi, transform: transform)
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
    /// tramo recortado a lo que su fichero tiene.
    static func plan(songStart: Double, duration: Double, base: ClosedRange<Double>?, baseOffset: Double,
                     punches: [(start: Double, end: Double, available: ClosedRange<Double>?, offset: Double)]) -> [PreviewPiece] {
        // Intervalos en tiempo del tema con su fuente (-1 = base).
        var spans: [(a: Double, b: Double, src: Int)] = [(songStart, songStart + duration, -1)]
        for (i, p) in punches.enumerated() {
            let a = max(p.start, songStart), b = min(p.end, songStart + duration)
            guard b > a else { continue }
            var next: [(a: Double, b: Double, src: Int)] = []
            for s in spans {
                if s.b <= a || s.a >= b { next.append(s); continue }
                if s.a < a { next.append((s.a, a, s.src)) }
                if s.b > b { next.append((b, s.b, s.src)) }
            }
            next.append((a, b, i))
            spans = next.sorted { $0.a < $1.a }
        }
        var out: [PreviewPiece] = []
        for s in spans {
            let available = s.src < 0 ? base : punches[s.src].available
            let offset = s.src < 0 ? baseOffset : punches[s.src].offset
            guard let available else { continue }
            // Fichero: [a + o, b + o) recortado a donde hay imagen.
            let lo = max(s.a + offset, available.lowerBound), hi = min(s.b + offset, available.upperBound)
            guard hi > lo else { continue }
            out.append(PreviewPiece(start: lo - offset - songStart, end: hi - offset - songStart,
                                    source: s.src < 0 ? .base : .punch(s.src), sourceStart: lo))
        }
        return out
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
        if let base { v.preferredTransform = base.transform } else if let s = punchSources.compactMap({ $0 }).first {
            v.preferredTransform = s.transform
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

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
