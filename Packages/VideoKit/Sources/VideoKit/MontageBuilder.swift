import AVFoundation
import Foundation

public enum MontageError: Error, Equatable, Sendable {
    /// Ninguna parte tiene imagen.
    case noVideo
    case audio(String)
    case composition(String)
    case read(String)
    case write(String)
    /// La extensión de la URL de destino no es la del contenedor pedido (`MontageVideoContainer.fileExtension`).
    case containerMismatch(expected: String, got: String)
}

/// Texto para el mensaje de la app («No se pudo exportar el vídeo (…)»): la causa, no el nombre del caso.
extension MontageError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .noVideo: "ninguna parte tiene imagen"
        case .audio(let s): "no se pudo leer el audio \(s)"
        case .composition(let s): s
        case .read(let s): "lectura de la composición: \(s)"
        case .write(let s): "escritura del fichero: \(s)"
        case .containerMismatch(let expected, let got): "la extensión .\(got) no es la del contenedor .\(expected)"
        }
    }
}

/// Composición del montaje lista para `AVPlayer` o para exportar. Tiempo 0 del item = `plan.span.start`.
public final class MontagePreview: @unchecked Sendable {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
    /// Mezcla de la vista previa (volúmenes, compuertas con fundidos de 80 ms y fundido global); `nil` sin audio.
    public let audioMix: AVMutableAudioMix?
    public let timeline: MontageTimeline

    init(composition: AVMutableComposition, videoComposition: AVMutableVideoComposition, audioMix: AVMutableAudioMix?, timeline: MontageTimeline) {
        self.composition = composition
        self.videoComposition = videoComposition
        self.audioMix = audioMix
        self.timeline = timeline
    }

    /// Duración del vídeo: la suma de los segmentos.
    public var duration: Double { timeline.timeMap.duration }

    /// Item para `AVPlayer` con el compositor y la mezcla.
    @MainActor
    public func makePlayerItem() -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        item.audioMix = audioMix
        return item
    }

    /// Tiempo del item → tiempo del tema, y al revés (un instante dentro de un hueco cortado va al inicio del
    /// segmento siguiente).
    public func songTime(itemTime: CMTime) -> Double { timeline.timeMap.songTime(videoTime: CMTimeGetSeconds(itemTime)) }
    public func itemTime(songTime: Double) -> CMTime { VideoTakeWriter.time(timeline.timeMap.videoTime(songTime: songTime)) }
}

/// Monta el plan (mini-spec Fase 7, «Compositor y vista previa»): una pista de vídeo por parte con imagen (desfase y
/// punches como `TakePreview`, sin recodificar; el último fotograma congelado mientras dura su salida), las pistas de
/// audio de la vista previa y una `AVVideoComposition` con `MontageCompositor`.
///
/// `load` abre los ficheros una vez; `make` solo inserta tramos y es barato (otra resolución, otro plan de layout
/// con las mismas tomas: `load` de nuevo).
public final class MontageBuilder: @unchecked Sendable {
    public let plan: MontagePlan
    public let timeline: MontageTimeline
    /// Tomas con imagen, en el orden de `timeline.parts`.
    private let videos: [LoadedTakeVideo]
    private let audio: [(track: MontageAudioTrack, asset: AVURLAsset, source: AVAssetTrack, range: CMTimeRange)]

    private init(plan: MontagePlan, timeline: MontageTimeline, videos: [LoadedTakeVideo],
                 audio: [(MontageAudioTrack, AVURLAsset, AVAssetTrack, CMTimeRange)]) {
        self.plan = plan
        self.timeline = timeline
        self.videos = videos
        self.audio = audio
    }

    public static func load(_ plan: MontagePlan, includeAudio: Bool = true) async throws -> MontageBuilder {
        var loaded: [String: LoadedTakeVideo] = [:]
        for p in plan.parts {
            guard let v = p.video else { continue }
            if let take = try await LoadedTakeVideo.load(v) { loaded[p.id] = take }
        }
        let timeline = MontageTimeline(plan: plan, images: loaded.compactMapValues { v in
            v.firstImage.map { (firstImage: $0, frameSize: v.frameSize) }
        }, imageSpans: loaded.mapValues { $0.pieces.map { MontageSpan(start: $0.start, end: $0.end) } })
        var audio: [(MontageAudioTrack, AVURLAsset, AVAssetTrack, CMTimeRange)] = []
        if includeAudio {
            for a in plan.audio {
                let asset = AVURLAsset(url: a.url)
                guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw MontageError.audio(a.url.lastPathComponent) }
                audio.append((a, asset, track, try await track.load(.timeRange)))
            }
        }
        return MontageBuilder(plan: plan, timeline: timeline, videos: timeline.parts.map { loaded[$0.id]! }, audio: audio)
    }

    /// Composición para una resolución (`nil`: la del lienzo). Una resolución menor aligera la vista previa.
    public func make(renderSize: CGSize? = nil, includeAudio: Bool = true) throws -> MontagePreview {
        guard !videos.isEmpty else { throw MontageError.noVideo }
        func t(_ s: Double) -> CMTime { VideoTakeWriter.time(s) }
        let map = timeline.timeMap
        let comp = AVMutableComposition()
        // Duración del vídeo en la rejilla (la misma que lee el exportador y la de `mezcla.wav`).
        let total = t(map.duration)
        // La toma con imagen más tardía se congela hasta el final: así la composición dura `total` aunque las tomas
        // acaben antes que el último tramo cuantizado (`LoadedTakeVideo.insert(fillToEnd:)`).
        let end = map.segments.last?.end ?? 0
        let filler = videos.indices.max { (videos[$0].lastImage(before: end) ?? -.infinity) < (videos[$1].lastImage(before: end) ?? -.infinity) }
        var ids: [CMPersistentTrackID] = []
        for (i, v) in videos.enumerated() {
            guard let track = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw MontageError.composition("pista de vídeo")
            }
            do { try v.insert(into: track, map: map, hold: MontageStyle.transition, fillToEnd: i == filler) } catch {
                throw MontageError.composition("\(error)")
            }
            ids.append(track.trackID)
        }
        guard CMTimeCompare(comp.duration, total) >= 0 else {
            throw MontageError.composition(String(format: "las pistas de vídeo acaban en %.4f s y el montaje dura %.4f s",
                                                  CMTimeGetSeconds(comp.duration), CMTimeGetSeconds(total)))
        }

        var mix: AVMutableAudioMix?
        if includeAudio && !audio.isEmpty {
            var params: [AVMutableAudioMixInputParameters] = []
            for a in audio {
                guard let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                let p = AVMutableAudioMixInputParameters(track: track)
                // Fichero [0, d) suena en [songStart, songStart + d) del tema; recortado a cada segmento y puesto en
                // su sitio del vídeo, con las rampas del segmento.
                let fileDur = CMTimeGetSeconds(a.range.duration)
                var inserted = false
                for (k, seg) in map.segments.enumerated() {
                    let base = map.videoStarts[k] - seg.start
                    let lo = max(a.track.songStart, seg.start), hi = min(a.track.songStart + fileDur, seg.end)
                    if hi > lo {
                        let from = CMTimeAdd(a.range.start, t(lo - a.track.songStart)), at = t(lo + base)
                        let end = track.segments.last.map { CMTimeRangeGetEnd($0.timeMapping.target) } ?? .zero
                        if CMTimeCompare(at, end) > 0 { track.insertEmptyTimeRange(CMTimeRange(start: end, end: at)) }
                        do { try track.insertTimeRange(CMTimeRange(start: from, duration: t(hi - lo)), of: a.source, at: at) } catch {
                            throw MontageError.composition("\(error)")
                        }
                        inserted = true
                    }
                    let points = MontageAudioEnvelope.breakpoints(a.track, timeline: timeline, segment: k)
                    for (x, y) in zip(points, points.dropFirst()) {
                        // Al final del segmento la ganancia del siguiente no vale: se toma justo antes.
                        let g0 = Float(MontageAudioEnvelope.gain(a.track, at: x, timeline: timeline))
                        let g1 = Float(MontageAudioEnvelope.gain(a.track, at: y == seg.end ? y - 1e-9 : y, timeline: timeline))
                        p.setVolumeRamp(fromStartVolume: g0, toEndVolume: g1, timeRange: CMTimeRange(start: t(x + base), end: t(y + base)))
                    }
                }
                if inserted { params.append(p) } else { comp.removeTrack(track) }
            }
            let m = AVMutableAudioMix()
            m.inputParameters = params
            mix = m
        }

        let video = AVMutableVideoComposition()
        video.customVideoCompositorClass = MontageCompositor.self
        // La misma rejilla en la que `MontagePlan.quantized` pone los tramos.
        video.frameDuration = MontagePlan.frameTime(fps: plan.fps)
        video.renderSize = renderSize ?? plan.canvas.size
        // Fotogramas compuestos etiquetados en BT.709, como el fichero exportado.
        video.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        video.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        video.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        // Una instrucción sin huecos de 0 al final del vídeo (y de la composición, si un tick de redondeo la alarga).
        video.instructions = [MontageInstruction(timeRange: CMTimeRange(start: .zero, duration: CMTimeMaximum(comp.duration, total)), timeline: timeline,
                                                 trackIDs: ids, rotations: videos.map(\.rotation), caption: plan.caption)]
        return MontagePreview(composition: comp, videoComposition: video, audioMix: mix, timeline: timeline)
    }

    /// Resolución de vista previa con el lado mayor en `maxDimension` (par, misma proporción que el lienzo).
    public static func renderSize(canvas: MontageCanvas, maxDimension: Int) -> CGSize {
        let k = min(1, Double(maxDimension) / Double(max(canvas.width, canvas.height)))
        func even(_ x: Double) -> Int { max(2, Int((x / 2).rounded()) * 2) }
        return CGSize(width: even(Double(canvas.width) * k), height: even(Double(canvas.height) * k))
    }
}
