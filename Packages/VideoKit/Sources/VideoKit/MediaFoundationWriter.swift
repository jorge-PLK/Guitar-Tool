#if os(Windows)
import Foundation

/// `takes/<id>/video.mov` en Windows (plan, «Fase 7c», paso 7, parte 7.2) con el contrato del Mac: solo vídeo, con la
/// resolución y los fps reales, y **PTS = tiempo del tema** sin el desfase manual, en escala de 90 000.
///
/// - Códec: siempre H.264 (`MontageCodec.supported`; Jorge, 21/11/2026, paso 8 W2-E1: en Windows el único códec de
///   vídeo es H.264, sin rama HEVC). Contenedor MPEG-4 aunque la extensión sea `.mov`.
/// - El fichero empieza en el tiempo 0 del tema: una toma que empieza a mitad lleva un tramo vacío delante (lista de
///   ediciones, `MP4EditList`), como el `.mov` de `AVAssetWriter`.
/// - Cada fotograma se escribe al llegar el siguiente, con duración = siguiente PTS − PTS: un fotograma perdido deja un
///   hueco (el anterior dura más) y los siguientes conservan su PTS. El último dura un periodo nominal.
/// - Se descartan los PTS negativos o que no avanzan, los fotogramas sin imagen y los de otro tamaño.
/// - Codifica en una cola propia. `realTime` (por defecto): si hay más de `realTimeBacklog` fotogramas esperando, el
///   nuevo se descarta y se cuenta; sin él (tests y ficheros), `append` espera a que se escriba.
public final class VideoTakeWriter: VideoFrameSink, @unchecked Sendable {
    /// Escala de tiempo de los PTS (la del Mac).
    public static let timescale: Int32 = songTimescale
    /// Fotogramas en cola como mucho con `realTime` (decisión propia: 0,25 s a 30 fps).
    static let realTimeBacklog = 8

    public let url: URL
    public let format: VideoFormat
    public let realTime: Bool
    /// Códec con que se escribe (en Windows, siempre H.264).
    public let codec: MontageCodec
    private let queue = DispatchQueue(label: "ToneForge.VideoTakeWriter", qos: .userInitiated)
    private let lock = NSLock()
    private var muxer: MediaFoundationMuxer?
    private var held: (FramePixelBuffer, Int64)?
    private var last: Int64?
    private var first: Int64?
    private var written = 0
    private var rejected = 0
    private var pending = 0
    private var finished = false
    private var failure: String?

    public init(url: URL, format: VideoFormat, realTime: Bool = true) throws {
        self.url = url
        self.format = format
        self.realTime = realTime
        try? FileManager.default.removeItem(at: url)
        var lastError = ""
        var made: (MediaFoundationMuxer, MontageCodec)?
        for c in MontageCodec.supported {
            do {
                let m = try MediaFoundationMuxer(url: url, config: .init(
                    width: format.width, height: format.height, fps: format.fps, codec: c,
                    videoBitrate: MediaFoundationMuxer.defaultBitrate(width: format.width, height: format.height, fps: format.fps, codec: c),
                    audio: nil, realTime: realTime))
                made = (m, c)
                break
            } catch {
                lastError = "\(error)"
                try? FileManager.default.removeItem(at: url)
            }
        }
        guard let (m, c) = made else { throw VideoTakeWriterError.cannotCreate(lastError) }
        muxer = m
        codec = c
    }

    /// Tiempo del tema → PTS en la escala de 90 000.
    static func pts(_ songTime: Double) -> Int64 { Int64((songTime * Double(timescale)).rounded()) }

    /// PTS de 90 000 → unidades de 100 ns de Media Foundation (redondeado: error ≤ 50 ns).
    static func hundredNanoseconds(_ pts: Int64) -> Int64 { (pts * 10_000_000 + Int64(timescale) / 2) / Int64(timescale) }

    public func append(_ frame: CameraFrame, songTime: Double) -> Bool {
        let accepted = lock.withLock { () -> (FramePixelBuffer, Int64)? in
            guard !finished, failure == nil, songTime.isFinite, songTime >= 0, let pb = frame.pixelBuffer,
                  pb.width == format.width, pb.height == format.height else {
                rejected += 1
                return nil
            }
            let pts = Self.pts(songTime)
            if let last, pts <= last {
                rejected += 1
                return nil
            }
            if realTime, pending >= Self.realTimeBacklog {
                rejected += 1
                return nil
            }
            if first == nil { first = pts }
            last = pts
            written += 1
            pending += 1
            return (pb, pts)
        }
        guard let (pb, pts) = accepted else { return false }
        let work: @Sendable () -> Void = { [self] in
            self.write(pb, pts: pts)
            self.lock.withLock { self.pending -= 1 }
        }
        if realTime { queue.async(execute: work) } else { queue.sync(execute: work) }
        return true
    }

    /// En la cola: escribe el fotograma retenido con duración hasta `pts` y retiene este.
    private func write(_ pb: FramePixelBuffer, pts: Int64) {
        if let (prev, prevPTS) = held { emit(prev, prevPTS, duration: pts - prevPTS) }
        held = (pb, pts)
    }

    private func emit(_ pb: FramePixelBuffer, _ pts: Int64, duration: Int64) {
        guard let muxer, lock.withLock({ failure == nil }) else { return }
        let t = Self.hundredNanoseconds(pts)
        do {
            try muxer.writeVideo(pb, time: t, duration: Self.hundredNanoseconds(pts + duration) - t)
        } catch {
            lock.withLock { failure = "\(error)" }
        }
    }

    /// Cierra el fichero: escribe el último fotograma (un periodo nominal), finaliza y pone el tramo vacío delante.
    public func finish() async throws -> VideoTakeSummary {
        let (firstPTS, lastPTS, nWritten, nRejected) = lock.withLock { () -> (Int64?, Int64?, Int, Int) in
            finished = true
            return (first, last, written, rejected)
        }
        let period = Self.pts(1 / max(1, format.fps))
        let result: Result<Void, Error> = await withCheckedContinuation { done in
            queue.async { [self] in
                done.resume(returning: Result { try self.close(period: period, empty: nWritten == 0) })
            }
        }
        guard nWritten > 0 else {
            try? FileManager.default.removeItem(at: url)
            throw VideoTakeWriterError.empty
        }
        try result.get()
        if let firstPTS, firstPTS > 0 {
            do { try Self.addLeadingGap(url, songTimePTS: firstPTS) } catch { throw VideoTakeWriterError.failed("lista de ediciones: \(error)") }
        }
        return VideoTakeSummary(url: url, format: format, framesWritten: nWritten, framesRejected: nRejected,
                                firstSongTime: firstPTS.map { Double($0) / Double(Self.timescale) },
                                lastSongTime: lastPTS.map { Double($0) / Double(Self.timescale) })
    }

    /// En la cola.
    private func close(period: Int64, empty: Bool) throws {
        defer { muxer = nil }   // suelta el fichero (IMFSinkWriter lo tiene abierto hasta liberarse)
        if empty { return }
        if let (pb, pts) = held { emit(pb, pts, duration: period) }
        held = nil
        if let f = lock.withLock({ failure }) { throw VideoTakeWriterError.failed(f) }
        do { try muxer?.finalize() } catch { throw VideoTakeWriterError.failed("\(error)") }
    }

    /// Tramo vacío de `songTimePTS` (escala de 90 000) delante de la pista de vídeo: el primer fotograma cae en su tiempo
    /// del tema. Media Foundation escribe las muestras desde 0, ninguna lista de ediciones y en `mdhd` la marca absoluta
    /// del final (se corrige a la suma de las muestras).
    static func addLeadingGap(_ url: URL, songTimePTS: Int64) throws {
        try MP4EditList.rewrite(url) { t in
            guard t.handler == "vide" else { return nil }
            let gap = UInt64((Double(songTimePTS) / Double(timescale) * Double(t.movieTimescale)).rounded())
            let kept = t.edits.filter { $0.mediaTime >= 0 }
            let body = kept.isEmpty
                ? [MP4EditList.Edit(segmentDuration: t.sampleDuration * UInt64(t.movieTimescale) / UInt64(max(1, t.mediaTimescale)), mediaTime: 0)]
                : kept
            return [.empty(gap)] + body
        }
    }

    /// Descarta el fichero.
    public func cancel() {
        lock.withLock { finished = true }
        queue.sync {
            held = nil
            muxer = nil
        }
        try? FileManager.default.removeItem(at: url)
    }
}
#endif
