#if canImport(CoreVideo)
import CoreVideo
#endif
import Foundation

/// Dibujo de un instante del montaje en un búfer BGRA (costura del compositor; plan, «Fase 7c», paso 7, parte 7.9).
///
/// Mismas capas y misma geometría en los dos sistemas: fondo #0F1113, cada recuadro de `state` (recorte o ajuste con
/// relleno, desenfoque de entrada, esquinas y sombra fuera del plano único, nombre de la parte, fundido a negro de la
/// toma, opacidad), el rótulo y el fundido global. Mac: Core Image (`CoreImageMontageRenderer`, el mismo
/// `MontageRenderer` que usa `MontageCompositor`). Windows: Direct2D + DirectWrite (`Direct2DMontageRenderer`).
public protocol MontageFrameRendering: AnyObject, Sendable {
    /// Dibuja `state` en `output` (BGRA; su tamaño es la resolución de salida, en la proporción del lienzo).
    /// `source(i)`: fotograma de la parte `timeline.parts[i]` ya girado, o `nil` (recuadro en negro).
    func render(_ state: MontageFrameState, timeline: MontageTimeline, caption: MontageCaption?, into output: FramePixelBuffer,
                source: (Int) -> FramePixelBuffer?) throws
}

public enum MontageFrameRenderers {
    /// El de este sistema.
    public static func make() throws -> any MontageFrameRendering {
        #if canImport(CoreImage) && canImport(AVFoundation)
        return CoreImageMontageRenderer()
        #elseif os(Windows)
        return try Direct2DMontageRenderer()
        #else
        throw MontageError.composition("sin compositor en este sistema")
        #endif
    }
}

/// Lo común de la vista previa del montaje en los dos sistemas (plan, «Fase 7c», paso 7, parte 7.9). En el Mac,
/// `MontagePreview` es además la composición de AVFoundation (`makePlayerItem`); en Windows da los fotogramas compuestos
/// (`frame(at:)`) y las ganancias de audio por pista.
public protocol MontagePreviewing: AnyObject, Sendable {
    var timeline: MontageTimeline { get }
    /// Duración del vídeo: la suma de los segmentos.
    var duration: Double { get }
}

extension MontagePreviewing {
    /// Tiempo del vídeo → tiempo del tema, y al revés (un instante dentro de un hueco cortado va al inicio del segmento
    /// siguiente).
    public func songTime(videoTime: Double) -> Double { timeline.timeMap.songTime(videoTime: videoTime) }
    public func videoTime(songTime: Double) -> Double { timeline.timeMap.videoTime(songTime: songTime) }
}

/// Qué instante de qué fichero ve una pista del montaje en cada tiempo del vídeo (plan, «Fase 7c», paso 7, parte 7.9).
/// Réplica pura de `LoadedTakeVideo.insert(into:map:hold:fillToEnd:)` del Mac (tramos de la toma segmento a segmento,
/// congelado del último fotograma `hold` + 1 fotograma o hasta el final con `fillToEnd`), en segundos en lugar de
/// `CMTime`; en el Mac se comprueba contra la composición de AVFoundation.
enum MontageTrackPlan {
    /// Tramo de la toma en tiempo del tema y de dónde sale (`source`: índice del fichero; `sourceStart`: PTS que se ve
    /// en `start`).
    struct Piece: Equatable, Sendable {
        var start: Double
        var end: Double
        var source: Int
        var sourceStart: Double
    }

    /// Tramo de la pista en tiempo del vídeo: en `v` se ve el PTS `sourceStart + (v − start) · rate` de `source`
    /// (`rate` < 1: el último fotograma estirado, como `scaleTimeRange`).
    struct Range: Equatable, Sendable {
        var start: Double
        var end: Double
        var source: Int
        var sourceStart: Double
        var rate: Double

        func sourceTime(at v: Double) -> Double { sourceStart + (v - start) * rate }
    }

    static func ranges(pieces: [Piece], available: (Int) -> ClosedRange<Double>, map: MontageTimeMap, hold: Double, frameRate: Double,
                       fillToEnd: Bool) -> [Range] {
        var out: [Range] = []
        var cursor = 0.0
        let frame = 1 / frameRate
        for (k, seg) in map.segments.enumerated() {
            let origin = seg.start, videoStart = map.videoStarts[k], duration = seg.duration
            let fill = fillToEnd && k == map.segments.count - 1
            let total = videoStart + duration
            var last: (source: Int, sourceEnd: Double)?
            for p in pieces {
                let a = max(p.start, origin), b = min(p.end, origin + duration)
                guard b > a else { continue }
                let at = a - origin + videoStart, end = b - origin + videoStart
                let start = max(at, cursor)
                guard end > start else { continue }
                let from = p.sourceStart + (a - p.start) + (start - at)
                out.append(Range(start: start, end: end, source: p.source, sourceStart: from, rate: 1))
                cursor = end
                last = (p.source, from + (end - start))
            }
            if fill, last == nil, let p = pieces.last(where: { $0.start < origin }) {
                // Sin imagen en este segmento: se congela la última de los anteriores.
                last = (p.source, p.sourceStart + (p.end - p.start))
            }
            let filling = fill && total > cursor
            if let last, filling || (hold > 0 && total - cursor > frame) {
                let src = max(available(last.source).lowerBound, last.sourceEnd - frame)
                let one = last.sourceEnd - src
                let stretched = filling ? total - cursor : min(hold + frame, total - cursor)
                if stretched > 0 {
                    out.append(Range(start: cursor, end: cursor + stretched, source: last.source, sourceStart: src, rate: one / stretched))
                }
                cursor += stretched
            }
            cursor = max(cursor, total)
        }
        return out
    }

    /// Tramo que cubre `v` (`[start, end)`), o `nil` (vacío: recuadro en negro).
    static func range(at v: Double, in ranges: [Range]) -> Range? {
        ranges.last { v >= $0.start - 1e-9 && v < $0.end - 1e-9 }
    }
}
