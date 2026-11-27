#if os(Windows)
import CMediaFoundation
import Foundation
import NativeAudioFile

// Vista previa de toma, montaje y fuente de fotogramas del exportador en Windows (plan, «Fase 7c», paso 7, parte 7.9):
// lector de Media Foundation → compositor Direct2D. Misma API pública que el Mac donde el Mac no expone tipos de
// AVFoundation; el tiempo de cada pista sigue `MontageTrackPlan` (réplica de `LoadedTakeVideo.insert` del Mac).

/// Tolerancia al buscar el fotograma de un instante (las marcas del fichero van a 1/90 000 s).
private let frameLookupEpsilon = 1e-6

// MARK: - Fichero de vídeo de una toma

/// `video.mov` de una toma o de un punch: tamaño, fps y tramo con imagen en tiempo del tema. El PTS del tema = marca de
/// Media Foundation + `shift`, y `shift` se MIDE al abrir (`readerShift`): en este PC (Windows 11 x64) Media Foundation
/// ya aplica el tramo vacío de la lista de ediciones (marca del primer fotograma = PTS del tema, `shift` ≈ 0), pero no
/// conviene suponerlo, porque con un lector que no lo aplique la marca es el tiempo de los medios.
final class TakeVideoFile: @unchecked Sendable {
    let url: URL
    let naturalSize: CGSize
    let frameRate: Double
    /// PTS del tema con imagen (como los tramos no vacíos de la pista en el Mac).
    let available: ClosedRange<Double>
    /// Marca del lector + `shift` = PTS del tema.
    let shift: Double

    private init(url: URL, naturalSize: CGSize, frameRate: Double, available: ClosedRange<Double>, shift: Double) {
        self.url = url
        self.naturalSize = naturalSize
        self.frameRate = frameRate
        self.available = available
        self.shift = shift
    }

    /// `nil` sin URL o sin pista de vídeo.
    static func open(_ url: URL?) throws -> TakeVideoFile? {
        guard let url else { return nil }
        let info: MediaFoundationReader.Info
        do { info = try MediaFoundationReader.info(url) } catch let e as MediaFoundationReader.UndecodableVideo {
            throw MontageError.read(e.description)
        } catch { throw MontageError.read("\(url.lastPathComponent): \(error)") }
        guard info.hasVideo, info.width > 0, info.height > 0 else { return nil }
        var empty = 0.0, mediaStart = 0.0, length = info.duration
        var expectedFirst: Double?
        if let track = try? MP4EditList.tracks(in: url).first(where: { $0.handler == "vide" }) {
            expectedFirst = TakeVideoProbe.timing(track).first
            let movie = Double(max(1, track.movieTimescale)), media = Double(max(1, track.mediaTimescale))
            if track.edits.isEmpty {
                length = Double(track.sampleDuration) / media
            } else {
                var seenMedia = false
                var mediaLength = 0.0
                for e in track.edits {
                    if e.mediaTime < 0 {
                        if !seenMedia { empty += Double(e.segmentDuration) / movie }
                    } else {
                        if !seenMedia { mediaStart = Double(e.mediaTime) / media }
                        seenMedia = true
                        mediaLength += Double(e.segmentDuration) / movie
                    }
                }
                length = mediaLength
            }
        }
        guard length > 0 else { return nil }
        var readerFirst: Double?
        try? MediaFoundationReader.forEachFrame(url) { t, _, _ in readerFirst = t; return false }
        let shift = readerShift(expectedFirst: expectedFirst, readerFirst: readerFirst, fallback: empty - mediaStart)
        return TakeVideoFile(url: url, naturalSize: CGSize(width: info.width, height: info.height), frameRate: info.fps > 0 ? info.fps : 30,
                             available: empty...(empty + length), shift: shift)
    }

    /// Desfase marca de Media Foundation → PTS del tema: PTS del primer fotograma según las cajas (tramo vacío +
    /// composición del primero − inicio de los medios, `TakeVideoProbe.timing`) − marca que da el lector a ese
    /// fotograma. Sirve lo aplique o no el lector. Sin una de las dos (cajas ilegibles, fichero sin fotogramas o fallo al
    /// decodificar el primero) queda `fallback`, la cuenta de un lector que no aplica la lista (tramo vacío − inicio de
    /// los medios): sin fotogramas no hay nada que colocar, y un fallo de decodificación vuelve a salir, con su error,
    /// en `TakeFrameReader`.
    static func readerShift(expectedFirst: Double?, readerFirst: Double?, fallback: Double) -> Double {
        guard let expectedFirst, let readerFirst else { return fallback }
        return expectedFirst - readerFirst
    }
}

/// Lectura de un fichero: el fotograma visible en un PTS del tema (el último con marca ≤ t). Avanza decodificando en
/// secuencia; si el instante pedido queda a más de `seekAhead` por delante o está por detrás del actual, salta con
/// `IMFSourceReader::SetCurrentPosition` (cae en el fotograma clave anterior) y decodifica hacia delante hasta él. La
/// exportación siempre avanza (nunca salta); la vista previa y la hoja «Encuadre» saltan. `seekAhead = .infinity` =
/// sin saltos (solo secuencial y, al retroceder, volver a abrir desde el principio).
final class TakeFrameReader: @unchecked Sendable {
    /// Salto hacia delante a partir de ~1 GOP (las tomas se graban con un fotograma clave por segundo) y media más.
    static let defaultSeekAhead = 1.5

    let file: TakeVideoFile
    let rotation: VideoRotation
    private let seekAhead: Double
    private var reader: UnsafeMutableRawPointer?
    private var eos = false
    /// Fotograma actual (NV12 copiado) y su versión BGRA girada, hecha solo si se pide.
    private var current: (pts: Double, nv12: FramePixelBuffer)?
    private var currentBGRA: FramePixelBuffer?
    private var pending: (pts: Double, nv12: FramePixelBuffer)?
    /// Saltos hechos con `tfmf_reader_seek` (tests y medidas).
    private(set) var seekCount = 0

    /// PTS del tema del fotograma elegido en la última llamada a `frame(at:)`.
    var currentPTS: Double? { current?.pts }

    init(file: TakeVideoFile, rotation: VideoRotation, seekAhead: Double = TakeFrameReader.defaultSeekAhead) {
        self.file = file
        self.rotation = rotation
        self.seekAhead = seekAhead
    }

    deinit { if let reader { tfmf_reader_release(reader) } }

    private func reset() {
        if let reader { tfmf_reader_release(reader) }
        reader = nil
        eos = false
        current = nil
        currentBGRA = nil
        pending = nil
    }

    private func openIfNeeded() throws {
        guard reader == nil else { return }
        var info = TFMFReaderInfo()
        var r: UnsafeMutableRawPointer?
        try MF.check(MF.withWidePath(file.url) { tfmf_reader_open($0, 1, 0, &r, &info) }, "abrir vídeo \(file.url.lastPathComponent)")
        reader = r
    }

    /// Salta a `t` (PTS del tema). Si el lector cae después de `t` (marca de acceso posterior) retrocede más hasta caer
    /// antes, o hasta el principio, donde un primer fotograma posterior a `t` es que aún no hay imagen.
    private func jump(to t: Double) throws {
        var margin = 0.0
        while true {
            try openIfNeeded()
            let target = max(0, t - file.shift - margin)
            try MF.check(tfmf_reader_seek(reader, Int64(target * 1e7)), "buscar en \(file.url.lastPathComponent)")
            seekCount += 1
            eos = false
            current = nil
            currentBGRA = nil
            pending = try next()
            if let p = pending, p.pts > t + frameLookupEpsilon, target > 0 {
                margin = margin == 0 ? 1 : margin * 2
                continue
            }
            return
        }
    }

    private func next() throws -> (pts: Double, nv12: FramePixelBuffer)? {
        try openIfNeeded()
        guard !eos else { return nil }
        var f = TFMFVideoFrame()
        var end: Int32 = 0
        let reader = reader
        try ExportProfile.measure(.decode) { try MF.check(tfmf_reader_video(reader, &f, &end), "leer vídeo \(file.url.lastPathComponent)") }
        if end != 0 { eos = true; return nil }
        let pb = FramePixelBuffer(pixelFormat: .nv12, width: Int(f.width), height: Int(f.height))
        ExportProfile.measure(.copy) {
            for y in 0..<pb.height {
                (pb.baseAddress + y * pb.bytesPerRow).copyMemory(from: f.y + y * Int(f.yStride), byteCount: pb.width)
            }
            let uv = pb.planeBaseAddress(1)
            for y in 0..<pb.planeHeight(1) {
                (uv + y * pb.bytesPerRow).copyMemory(from: f.uv + y * Int(f.uvStride), byteCount: 2 * ((pb.width + 1) / 2))
            }
        }
        return (Double(f.time100ns) / 1e7 + file.shift, pb)
    }

    /// Fotograma BGRA (girado) visible en el PTS del tema `t`; `nil` si el fichero no tiene ninguno hasta `t`.
    func frame(at t: Double) throws -> FramePixelBuffer? {
        if let c = current, t < c.pts - frameLookupEpsilon {
            if seekAhead.isFinite { try jump(to: t) } else { reset() }
        } else if seekAhead.isFinite {
            let last = pending?.pts ?? current?.pts ?? file.available.lowerBound
            if t - last > seekAhead { try jump(to: t) }
        }
        while true {
            if pending == nil { pending = try next() }
            guard let p = pending, p.pts <= t + frameLookupEpsilon else { break }
            current = p
            currentBGRA = nil
            pending = nil
        }
        guard let c = current else { return nil }
        if let done = currentBGRA { return done }
        let plain = ExportProfile.measure(.toBGRA) { c.nv12.converted(to: .bgra) }
        let bgra = ExportProfile.measure(.rotate) { rotation.apply(plain) }
        currentBGRA = bgra
        return bgra
    }
}

// MARK: - Toma abierta

/// Vídeo de una toma abierto (base y punches) con el plan de `TakePreviewPlan`, como `LoadedTakeVideo` del Mac.
final class LoadedTakeVideo: @unchecked Sendable {
    let pieces: [MontageTrackPlan.Piece]
    let files: [TakeVideoFile]
    /// Tamaño del fotograma ya girado.
    let frameSize: CGSize
    let frameRate: Double
    let rotation: VideoRotation

    var firstImage: Double? { pieces.first?.start }
    var lastImage: Double? { pieces.last?.end }

    private init(pieces: [MontageTrackPlan.Piece], files: [TakeVideoFile], frameSize: CGSize, frameRate: Double, rotation: VideoRotation) {
        self.pieces = pieces
        self.files = files
        self.frameSize = frameSize
        self.frameRate = frameRate
        self.rotation = rotation
    }

    static func load(_ video: MontagePartVideo) throws -> LoadedTakeVideo? {
        let base = try TakeVideoFile.open(video.url)
        let punchFiles = try video.punches.map { try TakeVideoFile.open($0.videoURL) }
        var files: [TakeVideoFile] = []
        var baseIndex: Int?
        if let base { baseIndex = 0; files.append(base) }
        var punchIndex: [Int?] = []
        for f in punchFiles {
            if let f { punchIndex.append(files.count); files.append(f) } else { punchIndex.append(nil) }
        }
        let plan = TakePreviewPlan.pieces(songStart: video.take.start, duration: video.take.duration, base: base?.available,
                                          baseOffset: video.videoOffset,
                                          punches: video.punches.enumerated().map { i, p in
                                              TakePreviewPlan.Punch(start: p.start, end: p.end, available: punchFiles[i]?.available, offset: p.videoOffset)
                                          })
        var pieces: [MontageTrackPlan.Piece] = []
        for p in plan {
            let index: Int? = switch p.source {
            case .base: baseIndex
            case .punch(let i): punchIndex[i]
            }
            guard let index else { continue }
            pieces.append(.init(start: video.take.start + p.start, end: video.take.start + p.end, source: index, sourceStart: p.sourceStart))
        }
        guard let first = pieces.first else { return nil }
        let f = files[first.source]
        return LoadedTakeVideo(pieces: pieces, files: files, frameSize: video.rotation.rotatedSize(f.naturalSize), frameRate: f.frameRate,
                               rotation: video.rotation)
    }

    /// Último instante del tema con imagen antes de `t`.
    func lastImage(before t: Double) -> Double? {
        pieces.filter { $0.start < t }.map { min($0.end, t) }.max()
    }

    func readers() -> [TakeFrameReader] { files.map { TakeFrameReader(file: $0, rotation: rotation) } }
}

// MARK: - Vista previa de una toma

/// Vista previa de una toma en Windows (mini-spec Fase 6, «Cámara y sincronía» y «Punch-in»): mismo plan que el Mac
/// (`TakePreviewPlan`); en lugar de una composición de AVFoundation da el fotograma de cada instante. Tiempo 0 =
/// `songStart` de la toma (muestra 0 del WAV).
public final class TakePreview: @unchecked Sendable {
    public let songStart: Double
    /// Duración del WAV (s).
    public let duration: Double
    public let punches: [PreviewPunch]
    public let rotation: VideoRotation
    private let base: TakeVideoFile?
    private let punchFiles: [TakeVideoFile?]
    private let lock = NSLock()
    private var readers: [URL: TakeFrameReader] = [:]

    private init(songStart: Double, duration: Double, punches: [PreviewPunch], rotation: VideoRotation, base: TakeVideoFile?,
                 punchFiles: [TakeVideoFile?]) {
        self.songStart = songStart
        self.duration = duration
        self.punches = punches
        self.rotation = rotation
        self.base = base
        self.punchFiles = punchFiles
    }

    public static func load(audioURL: URL, songStart: Double, videoURL: URL?, punches: [PreviewPunch],
                            rotation: VideoRotation = .none) async throws -> TakePreview {
        let duration: Double
        do {
            let r = try AudioFileReader(url: audioURL)
            duration = Double(r.frameCount) / r.sampleRate
        } catch { throw TakePreviewError.noAudio(audioURL.lastPathComponent) }
        return TakePreview(songStart: songStart, duration: duration, punches: punches, rotation: rotation, base: try TakeVideoFile.open(videoURL),
                           punchFiles: try punches.map { try TakeVideoFile.open($0.videoURL) })
    }

    /// Plan de tramos para un desfase (el mismo cálculo que en el Mac).
    public func pieces(videoOffset: Double, punchOffsets: [Double]? = nil) -> [PreviewPiece] {
        TakePreviewPlan.pieces(songStart: songStart, duration: duration, base: base?.available, baseOffset: videoOffset,
                               punches: punches.enumerated().map { i, p in
                                   TakePreviewPlan.Punch(start: p.start, end: p.end, available: punchFiles[i]?.available,
                                                         offset: punchOffsets?[safe: i] ?? p.videoOffset)
                               })
    }

    /// Fotograma BGRA (girado) que se ve en `time` s de la vista previa con ese desfase; `nil` en un tramo sin imagen.
    public func frame(at time: Double, videoOffset: Double, punchOffsets: [Double]? = nil) throws -> FramePixelBuffer? {
        guard let p = pieces(videoOffset: videoOffset, punchOffsets: punchOffsets).last(where: { time >= $0.start && time < $0.end }) else {
            return nil
        }
        let file: TakeVideoFile? = switch p.source {
        case .base: base
        case .punch(let i): punchFiles[i]
        }
        guard let file else { return nil }
        return try lock.withLock {
            let reader = readers[file.url] ?? TakeFrameReader(file: file, rotation: rotation)
            readers[file.url] = reader
            return try reader.frame(at: p.sourceStart + (time - p.start))
        }
    }
}

// MARK: - Montaje

/// Audio de una pista en la vista previa de Windows: dónde suena el fichero en el vídeo y la envolvente de volumen, con
/// los mismos vértices y rampas lineales que el `AVAudioMix` del Mac (compuertas con fundidos de 80 ms y fundido global).
public struct MontagePreviewAudio: Sendable {
    public struct Placement: Sendable, Equatable {
        /// Instante del fichero (s) que suena en `videoStart`.
        public var fileStart: Double
        public var videoStart: Double
        public var duration: Double
    }

    public struct Ramp: Sendable, Equatable {
        public var start: Double
        public var end: Double
        public var from: Double
        public var to: Double
    }

    public let track: MontageAudioTrack
    public let placements: [Placement]
    /// Rampas en tiempo del vídeo, en orden.
    public let ramps: [Ramp]

    /// Volumen en `v` (s del vídeo) como `AVAudioMixInputParameters`: lineal dentro de una rampa, el final de la anterior
    /// entre rampas y 1 antes de la primera.
    public func gain(atVideoTime v: Double) -> Double {
        var value = 1.0
        for r in ramps {
            if v < r.start { break }
            if v < r.end { return r.from + (r.to - r.from) * (v - r.start) / max(1e-12, r.end - r.start) }
            value = r.to
        }
        return value
    }

    /// Instante del fichero que suena en `v`, o `nil` (silencio).
    public func fileTime(atVideoTime v: Double) -> Double? {
        placements.first { v >= $0.videoStart && v < $0.videoStart + $0.duration }.map { $0.fileStart + v - $0.videoStart }
    }
}

/// Monta el plan en Windows (mini-spec Fase 7, «Compositor y vista previa»): abre las tomas una vez (`load`) y da
/// vistas previas a cualquier resolución (`make`), compuestas con Direct2D.
public final class MontageBuilder: @unchecked Sendable {
    public let plan: MontagePlan
    public let timeline: MontageTimeline
    /// Tomas con imagen, en el orden de `timeline.parts`.
    let videos: [LoadedTakeVideo]
    private let audio: [(track: MontageAudioTrack, duration: Double)]

    private init(plan: MontagePlan, timeline: MontageTimeline, videos: [LoadedTakeVideo], audio: [(track: MontageAudioTrack, duration: Double)]) {
        self.plan = plan
        self.timeline = timeline
        self.videos = videos
        self.audio = audio
    }

    public static func load(_ plan: MontagePlan, includeAudio: Bool = true) async throws -> MontageBuilder {
        var loaded: [String: LoadedTakeVideo] = [:]
        for p in plan.parts {
            guard let v = p.video else { continue }
            if let take = try LoadedTakeVideo.load(v) { loaded[p.id] = take }
        }
        let timeline = MontageTimeline(plan: plan, images: loaded.compactMapValues { v in
            v.firstImage.map { (firstImage: $0, frameSize: v.frameSize) }
        }, imageSpans: loaded.mapValues { $0.pieces.map { MontageSpan(start: $0.start, end: $0.end) } })
        var audio: [(track: MontageAudioTrack, duration: Double)] = []
        if includeAudio {
            for a in plan.audio {
                do {
                    let r = try AudioFileReader(url: a.url)
                    audio.append((a, Double(r.frameCount) / r.sampleRate))
                } catch { throw MontageError.audio(a.url.lastPathComponent) }
            }
        }
        return MontageBuilder(plan: plan, timeline: timeline, videos: timeline.parts.map { loaded[$0.id]! }, audio: audio)
    }

    /// Vista previa a una resolución (`nil`: la del lienzo).
    public func make(renderSize: CGSize? = nil, includeAudio: Bool = true) throws -> MontagePreview {
        guard !videos.isEmpty else { throw MontageError.noVideo }
        let map = timeline.timeMap
        let end = map.segments.last?.end ?? 0
        // La toma con imagen más tardía se congela hasta el final (`LoadedTakeVideo.insert(fillToEnd:)` del Mac).
        let filler = videos.indices.max { (videos[$0].lastImage(before: end) ?? -.infinity) < (videos[$1].lastImage(before: end) ?? -.infinity) }
        let tracks = videos.enumerated().map { i, v in
            MontageTrackPlan.ranges(pieces: v.pieces, available: { v.files[$0].available }, map: map, hold: MontageStyle.transition,
                                    frameRate: v.frameRate, fillToEnd: i == filler)
        }
        var mixes: [MontagePreviewAudio] = []
        if includeAudio {
            for a in audio {
                var placements: [MontagePreviewAudio.Placement] = []
                var ramps: [MontagePreviewAudio.Ramp] = []
                for (k, seg) in map.segments.enumerated() {
                    let base = map.videoStarts[k] - seg.start
                    let lo = max(a.track.songStart, seg.start), hi = min(a.track.songStart + a.duration, seg.end)
                    if hi > lo { placements.append(.init(fileStart: lo - a.track.songStart, videoStart: lo + base, duration: hi - lo)) }
                    let points = MontageAudioEnvelope.breakpoints(a.track, timeline: timeline, segment: k)
                    for (x, y) in zip(points, points.dropFirst()) {
                        // Al final del segmento la ganancia del siguiente no vale: se toma justo antes.
                        let g0 = MontageAudioEnvelope.gain(a.track, at: x, timeline: timeline)
                        let g1 = MontageAudioEnvelope.gain(a.track, at: y == seg.end ? y - 1e-9 : y, timeline: timeline)
                        // Mismos valores que el `AVAudioMix` (volúmenes en Float).
                        ramps.append(.init(start: x + base, end: y + base, from: Double(Float(g0)), to: Double(Float(g1))))
                    }
                }
                if !placements.isEmpty { mixes.append(MontagePreviewAudio(track: a.track, placements: placements, ramps: ramps)) }
            }
        }
        let size = renderSize ?? plan.canvas.size
        return try MontagePreview(timeline: timeline, caption: plan.caption, fps: plan.fps, renderSize: size, videos: videos, tracks: tracks,
                                  audio: mixes)
    }

    /// Resolución de vista previa con el lado mayor en `maxDimension` (par, misma proporción que el lienzo).
    public static func renderSize(canvas: MontageCanvas, maxDimension: Int) -> CGSize {
        let k = min(1, Double(maxDimension) / Double(max(canvas.width, canvas.height)))
        func even(_ x: Double) -> Int { max(2, Int((x / 2).rounded()) * 2) }
        return CGSize(width: even(Double(canvas.width) * k), height: even(Double(canvas.height) * k))
    }
}

/// Vista previa del montaje en Windows: fotogramas compuestos con Direct2D en cualquier instante del vídeo y la mezcla
/// de la vista previa por pista. Es también la fuente de fotogramas del exportador (rejilla de `fps`). Tiempo 0 =
/// inicio del primer segmento.
public final class MontagePreview: MontagePreviewing, MontageFrameSource, @unchecked Sendable {
    public let timeline: MontageTimeline
    public let caption: MontageCaption?
    public let fps: Double
    public let renderSize: CGSize
    /// Mezcla de la vista previa (vacía sin audio).
    public let audioTracks: [MontagePreviewAudio]
    let tracks: [[MontageTrackPlan.Range]]
    private let readers: [[TakeFrameReader]]
    private let renderer: Direct2DMontageRenderer
    private let lock = NSLock()

    init(timeline: MontageTimeline, caption: MontageCaption?, fps: Double, renderSize: CGSize, videos: [LoadedTakeVideo],
         tracks: [[MontageTrackPlan.Range]], audio: [MontagePreviewAudio]) throws {
        self.timeline = timeline
        self.caption = caption
        self.fps = fps
        self.renderSize = renderSize
        self.tracks = tracks
        readers = videos.map { $0.readers() }
        audioTracks = audio
        renderer = try Direct2DMontageRenderer()
    }

    public var duration: Double { timeline.timeMap.duration }
    /// Adaptador de Direct2D (hardware o WARP).
    public var device: Direct2DMontageRenderer.Device? { renderer.device }

    /// Fotogramas del vídeo en la rejilla de `fps`.
    public var frameCount: Int { Int((duration * fps).rounded()) }

    /// Fotograma compuesto (BGRA, `renderSize`) en `videoTime` s del vídeo.
    public func frame(at videoTime: Double) throws -> FramePixelBuffer {
        try lock.withLock {
            let state = timeline.state(at: timeline.timeMap.songTime(videoTime: videoTime))
            var sources: [Int: FramePixelBuffer] = [:]
            for box in state.boxes where sources[box.partIndex] == nil && box.partIndex < tracks.count {
                guard let r = MontageTrackPlan.range(at: videoTime, in: tracks[box.partIndex]) else { continue }
                if let pb = try readers[box.partIndex][r.source].frame(at: r.sourceTime(at: videoTime)) { sources[box.partIndex] = pb }
            }
            let out = FramePixelBuffer(pixelFormat: .bgra, width: Int(renderSize.width), height: Int(renderSize.height))
            try ExportProfile.measure(.compose) { try renderer.render(state, timeline: timeline, caption: caption, into: out) { sources[$0] } }
            return out
        }
    }

    func frame(_ index: Int) throws -> FramePixelBuffer { try frame(at: Double(index) / fps) }
}
#endif
