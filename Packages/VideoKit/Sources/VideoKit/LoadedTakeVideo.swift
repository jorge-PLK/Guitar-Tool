// Solo Apple. En Windows no existe: paso 7: media-foundation.
#if canImport(AVFoundation)
import AVFoundation
import Foundation

/// Vídeo de una toma abierto: fuentes (base y punches) y tramos de imagen en tiempo del tema, con el mismo plan que
/// `TakePreview` (el último punch manda en su tramo; cada tramo recortado a lo que su fichero tiene).
final class LoadedTakeVideo: @unchecked Sendable {
    /// Tramo en tiempo del tema y de dónde sale (instante del fichero que se ve en `start`).
    struct Piece {
        var start: Double
        var end: Double
        var source: TakePreview.Source
        var sourceStart: Double
    }

    let pieces: [Piece]
    /// Tamaño del fotograma ya girado (`rotation`): el que ven el timeline y el encuadre.
    let frameSize: CGSize
    let frameRate: Double
    /// Giro que el compositor (o Vision) aplica a cada fotograma leído de las pistas, que siguen sin girar.
    let rotation: VideoRotation
    /// Los `AVAsset` se guardan dentro de `Source`: sus pistas no los retienen.
    private let sources: [TakePreview.Source]

    var firstImage: Double? { pieces.first?.start }
    var lastImage: Double? { pieces.last?.end }

    private init(pieces: [Piece], frameSize: CGSize, frameRate: Double, rotation: VideoRotation, sources: [TakePreview.Source]) {
        self.pieces = pieces
        self.frameSize = frameSize
        self.frameRate = frameRate
        self.rotation = rotation
        self.sources = sources
    }

    /// `nil` si la toma no tiene ninguna imagen.
    static func load(_ video: MontagePartVideo) async throws -> LoadedTakeVideo? {
        let base = try await TakePreview.source(video.url)
        var punchSources: [TakePreview.Source?] = []
        for p in video.punches { punchSources.append(try await TakePreview.source(p.videoURL)) }
        let plan = TakePreview.plan(songStart: video.take.start, duration: video.take.duration, base: base?.available,
                                    baseOffset: video.videoOffset,
                                    punches: video.punches.enumerated().map { i, p in (p.start, p.end, punchSources[i]?.available, p.videoOffset) })
        var pieces: [Piece] = []
        for p in plan {
            let src: TakePreview.Source? = switch p.source {
            case .base: base
            case .punch(let i): punchSources[i]
            }
            guard let src else { continue }
            pieces.append(Piece(start: video.take.start + p.start, end: video.take.start + p.end, source: src, sourceStart: p.sourceStart))
        }
        guard let first = pieces.first else { return nil }
        let (size, rate) = try await first.source.track.load(.naturalSize, .nominalFrameRate)
        return LoadedTakeVideo(pieces: pieces, frameSize: video.rotation.rotatedSize(size), frameRate: rate > 0 ? Double(rate) : 30,
                               rotation: video.rotation, sources: ([base] + punchSources).compactMap { $0 })
    }

    /// Inserta los tramos en `track` con el tiempo 0 de la composición en `origin` (tiempo del tema), recortados a
    /// `[origin, origin + duration)`. Tras el último tramo, congela su último fotograma `hold` segundos (la salida de
    /// la parte dura más que su toma) y rellena con vacío hasta `duration`. Nada se recodifica.
    func insert(into track: AVMutableCompositionTrack, origin: Double, duration: Double, hold: Double) throws {
        try insert(into: track, map: MontageTimeMap(segments: [MontageSpan(start: origin, end: origin + duration)]), hold: hold)
    }

    /// Igual, segmento a segmento de `map`: cada uno en su sitio del vídeo, con su congelado y su relleno.
    ///
    /// `fillToEnd`: en el último segmento el congelado dura hasta el final del vídeo (aunque pase de `hold` o el hueco
    /// sea de menos de un fotograma). Un tramo vacío al final de una pista no cuenta en la duración de la composición:
    /// si ninguna pista llega con imagen al final (los tramos cuantizados acaban hasta un fotograma después que la
    /// toma), la composición dura menos que el plan y `AVAssetReader` rechaza la lectura con -11841.
    func insert(into track: AVMutableCompositionTrack, map: MontageTimeMap, hold: Double, fillToEnd: Bool = false) throws {
        var cursor = CMTime.zero
        for (k, seg) in map.segments.enumerated() {
            cursor = try insert(into: track, origin: seg.start, videoStart: map.videoStarts[k], duration: seg.duration, hold: hold,
                                fill: fillToEnd && k == map.segments.count - 1, cursor: cursor)
        }
    }

    /// Último instante del tema con imagen antes de `t` (para elegir la pista que se congela hasta el final).
    func lastImage(before t: Double) -> Double? {
        pieces.filter { $0.start < t }.map { min($0.end, t) }.max()
    }

    private func insert(into track: AVMutableCompositionTrack, origin: Double, videoStart: Double, duration: Double, hold: Double,
                        fill: Bool = false, cursor start: CMTime) throws -> CMTime {
        func t(_ s: Double) -> CMTime { VideoTakeWriter.time(s) }
        let total = t(videoStart + duration)
        var cursor = start
        var last: (source: TakePreview.Source, sourceEnd: Double)?
        for p in pieces {
            let a = max(p.start, origin), b = min(p.end, origin + duration)
            guard b > a else { continue }
            let at = t(a - origin + videoStart), end = t(b - origin + videoStart)
            if CMTimeCompare(at, cursor) > 0 { track.insertEmptyTimeRange(CMTimeRange(start: cursor, end: at)) }
            let start = CMTimeMaximum(at, cursor)
            guard CMTimeCompare(end, start) > 0 else { continue }
            let from = p.sourceStart + (a - p.start) + CMTimeGetSeconds(CMTimeSubtract(start, at))
            try track.insertTimeRange(CMTimeRange(start: t(from), duration: CMTimeSubtract(end, start)), of: p.source.track, at: start)
            cursor = end
            last = (p.source, from + CMTimeGetSeconds(CMTimeSubtract(end, start)))
        }
        let frame = 1 / frameRate
        if fill, last == nil, let p = pieces.last(where: { $0.start < origin }) {
            // Sin imagen en este segmento: se congela la última de los anteriores.
            last = (p.source, p.sourceStart + (p.end - p.start))
        }
        let filling = fill && CMTimeCompare(total, cursor) > 0
        if let last, filling || (hold > 0 && CMTimeGetSeconds(CMTimeSubtract(total, cursor)) > frame) {
            // Congelado: el último fotograma insertado, estirado (`scaleTimeRange`, sin recodificar).
            let src = max(last.source.available.lowerBound, last.sourceEnd - frame)
            let one = t(last.sourceEnd - src)
            try track.insertTimeRange(CMTimeRange(start: t(src), duration: one), of: last.source.track, at: cursor)
            let stretched = filling ? CMTimeSubtract(total, cursor) : CMTimeMinimum(t(hold + frame), CMTimeSubtract(total, cursor))
            track.scaleTimeRange(CMTimeRange(start: cursor, duration: one), toDuration: stretched)
            cursor = CMTimeAdd(cursor, stretched)
        }
        if CMTimeCompare(total, cursor) > 0 { track.insertEmptyTimeRange(CMTimeRange(start: cursor, end: total)) }
        return CMTimeMaximum(cursor, total)
    }
}
#endif
