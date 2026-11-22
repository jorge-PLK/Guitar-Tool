#if canImport(AVFoundation) && !os(Windows)
import AVFoundation
#endif
import AudioKit
import Foundation
import NativeAudioFile
import Store
import VideoKit

// Costuras del núcleo de Montaje (W2-M1): lo que depende del sistema (compositor, lector de tomas, pose, reproductor) va
// detrás de cierres/protocolos con versión simulada para los tests. Contrato: `Temp/win/step8-contract.md`, «W2-M1».

/// Compositor de la vista previa: fotogramas BGRA compuestos en cualquier instante del vídeo (Windows: `MontagePreview`).
protocol MontageComposing: AnyObject, Sendable {
    /// Duración del vídeo (s): la suma de los tramos.
    var duration: Double { get }
    func songTime(videoTime: Double) -> Double
    func videoTime(songTime: Double) -> Double
    func frame(atVideoTime t: Double) throws -> MontageFramePixels
}

/// Reloj y salida del audio de la vista previa: el WAV de la mezcla, cuyo tiempo es el tiempo del vídeo.
@MainActor
protocol MontageAudioPlaying: AnyObject {
    /// Carga el WAV; `nil` = sin audio (el reloj sigue solo).
    func load(url: URL?, duration: Double) throws
    var isPlaying: Bool { get }
    /// Segundos de vídeo.
    var currentTime: Double { get }
    func play() throws
    func pause()
    func seek(to t: Double)
    func shutdown()
}

/// Lo que el exportador devuelve al controlador (`MontageExportSummary` no se puede construir fuera de VideoKit).
struct MontageExportOutcome: Sendable, Equatable {
    /// Códec con que se escribió de verdad (en Windows siempre `h264`).
    var codec: String
}

/// Lo que el controlador pide al sistema.
struct MontageServices: Sendable {
    /// Compositor para el plan, con el lado mayor de la vista previa en `maxDimension`.
    var makeComposer: @Sendable (_ plan: MontagePlan, _ maxDimension: Int) async throws -> any MontageComposing
    /// Fotograma de una toma (hoja «Encuadre») en el instante `songTime`, ya girado; `nil` = sin imagen ahí.
    var takeFrame: @Sendable (_ video: MontagePartVideo, _ audioURL: URL, _ songTime: Double) async throws -> MontageFramePixels?
    var analyze: @Sendable (_ video: MontagePartVideo, _ progress: @escaping @Sendable (Double) -> Void) async throws -> FramingAnalysis
    var mix: @Sendable (_ job: MontageMixJob, _ progress: @escaping @Sendable (Double) -> Void) async throws -> MontageMixResult
    var export: @Sendable (_ plan: MontagePlan, _ mixURL: URL?, _ settings: MontageExportSettings, _ url: URL,
                           _ progress: @escaping @Sendable (Double) -> Void) async throws -> MontageExportOutcome

    static let production = MontageServices(
        makeComposer: { plan, maxDimension in
            #if os(Windows)
            let builder = try await MontageBuilder.load(plan, includeAudio: false)
            let size = MontageBuilder.renderSize(canvas: plan.canvas, maxDimension: maxDimension)
            return WindowsMontageComposer(preview: try builder.make(renderSize: size, includeAudio: false))
            #elseif canImport(AVFoundation)
            // W2-E2: en el Mac (tf-webdev), la composición de AVFoundation con `MontageCompositor`.
            let builder = try await MontageBuilder.load(plan, includeAudio: false)
            let size = MontageBuilder.renderSize(canvas: plan.canvas, maxDimension: maxDimension)
            return MacMontageComposer(preview: try builder.make(renderSize: size, includeAudio: false), size: size)
            #else
            throw MontageError.composition("sin compositor de fotogramas en este sistema")
            #endif
        },
        takeFrame: { video, audioURL, t in
            #if os(Windows)
            let preview = try await TakePreview.load(audioURL: audioURL, songStart: video.take.start, videoURL: video.url,
                                                     punches: video.punches, rotation: video.rotation)
            return try preview.frame(at: t - video.take.start, videoOffset: video.videoOffset)
            #elseif canImport(AVFoundation)
            // M1 (parte 3): en el Mac, el mismo `TakePreview` (plan de tramos, punches, giro) con `AVAssetImageGenerator`.
            let preview = try await TakePreview.load(audioURL: audioURL, songStart: video.take.start, videoURL: video.url,
                                                     punches: video.punches, rotation: video.rotation)
            guard let image = try await preview.frame(at: t - video.take.start, videoOffset: video.videoOffset) else { return nil }
            return try MacMontageComposer.bgra(image)
            #else
            return nil
            #endif
        },
        analyze: { video, progress in try await GuitarFramer.analyze(video: video, progress: progress) },
        mix: { job, progress in try await MontageMixer.mix(job, progress: progress) },
        export: { plan, mixURL, settings, url, progress in
            let r = try await MontageExporter.export(plan: plan, mixURL: mixURL, settings: settings, to: url, progress: progress)
            return MontageExportOutcome(codec: r.settings.codec.rawValue)
        })
}

#if os(Windows)
/// `MontagePreview` de VideoKit (Direct2D) como compositor de la vista previa.
final class WindowsMontageComposer: MontageComposing, @unchecked Sendable {
    private let preview: MontagePreview
    init(preview: MontagePreview) { self.preview = preview }
    var duration: Double { preview.duration }
    func songTime(videoTime: Double) -> Double { preview.songTime(videoTime: videoTime) }
    func videoTime(songTime: Double) -> Double { preview.videoTime(songTime: songTime) }
    func frame(atVideoTime t: Double) throws -> MontageFramePixels { try preview.frame(at: t) }
}
#endif

#if canImport(AVFoundation) && !os(Windows)
/// Mac (W2-E2, para `tf-webdev`): fotogramas de `MontagePreview` con `AVAssetImageGenerator` sobre la composición y su
/// `videoComposition` (el mismo `MontageCompositor` que exporta), pasados a `CVPixelBuffer` BGRA (lo que lee
/// `FrameJPEGEncoder`). Uno a uno: el bucle de la vista previa ya pide de uno en uno.
final class MacMontageComposer: MontageComposing, @unchecked Sendable {
    private let preview: MontagePreview
    private let generator: AVAssetImageGenerator
    private let lock = NSLock()

    init(preview: MontagePreview, size: CGSize) {
        self.preview = preview
        generator = AVAssetImageGenerator(asset: preview.composition)
        generator.videoComposition = preview.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = size
    }

    var duration: Double { preview.duration }
    func songTime(videoTime: Double) -> Double { preview.songTime(videoTime: videoTime) }
    func videoTime(songTime: Double) -> Double { preview.videoTime(songTime: songTime) }

    private final class Box: @unchecked Sendable { var result: Result<CGImage, Error> = .failure(MontageError.composition("sin fotograma")) }

    func frame(atVideoTime t: Double) throws -> MontageFramePixels {
        lock.lock()
        defer { lock.unlock() }
        // El último instante válido está un poco antes del final.
        let time = CMTime(seconds: min(max(0, t), max(0, duration - 0.001)), preferredTimescale: 90_000)
        let box = Box(), done = DispatchSemaphore(value: 0)
        generator.generateCGImageAsynchronously(for: time) { image, _, error in
            if let image { box.result = .success(image) } else if let error { box.result = .failure(error) }
            done.signal()
        }
        done.wait()
        return try Self.bgra(try box.result.get())
    }

    /// CGImage -> `CVPixelBuffer` BGRA del mismo tamaño.
    static func bgra(_ image: CGImage) throws -> CVPixelBuffer {
        let w = image.width, h = image.height
        var out: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, nil, &out) == kCVReturnSuccess, let pb = out else {
            throw MontageError.composition("sin búfer de \(w)×\(h)")
        }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            throw MontageError.composition("sin contexto de dibujo")
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pb
    }
}
#endif

// MARK: - Audio de la vista previa

/// Reloj propio sin audio (montaje sin pistas, o sin WAV todavía) y reproductor simulado de los tests: el tiempo avanza con
/// el reloj monótono desde la última posición, y se detiene al final.
@MainActor
final class ClockMontageAudio: MontageAudioPlaying {
    private let now: () -> Double
    private var base = 0.0
    private var startedAt: Double?
    private var duration = Double.infinity

    init(now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) { self.now = now }

    func load(url: URL?, duration: Double) throws {
        self.duration = duration
        base = min(base, duration)
    }

    var isPlaying: Bool { startedAt != nil && currentTime < duration }
    var currentTime: Double {
        guard let s = startedAt else { return base }
        return min(duration, base + now() - s)
    }
    func play() throws { if startedAt == nil { startedAt = now() } }
    func pause() {
        base = currentTime
        startedAt = nil
    }
    func seek(to t: Double) {
        base = min(max(0, t), duration)
        if startedAt != nil { startedAt = now() }
    }
    func shutdown() { pause() }
}

/// El reproductor portátil (`StudyPlayer`, el de Backing) con el WAV de la vista previa como única pista. Sin WAV, reloj propio.
@MainActor
final class StudyMontageAudio: MontageAudioPlaying {
    static let trackID = "montage-preview"
    private let audio: StudyAudio
    private let fallback = ClockMontageAudio()
    private var useFallback = true

    init(mode: AudioMode, output: OutputSelection) { audio = StudyAudio(mode: mode, output: output) }

    private var player: StudyPlayer { audio.player }

    func load(url: URL?, duration: Double) throws {
        let t = currentTime
        let wasPlaying = isPlaying
        pause()
        guard let url else {
            useFallback = true
            try fallback.load(url: nil, duration: duration)
            fallback.seek(to: t)
            return
        }
        try player.load(tracks: [Track(id: Self.trackID, url: url)])
        try audio.prepare(firstTrack: url)
        useFallback = false
        player.seek(to: min(t, duration))
        if wasPlaying { try play() }
    }

    var isPlaying: Bool { useFallback ? fallback.isPlaying : player.isPlaying }
    var currentTime: Double { useFallback ? fallback.currentTime : player.currentTime }
    func play() throws { if useFallback { try fallback.play() } else { try player.play() } }
    func pause() { if useFallback { fallback.pause() } else { player.pause() } }
    func seek(to t: Double) { if useFallback { fallback.seek(to: t) } else { player.seek(to: t) } }
    func shutdown() {
        fallback.shutdown()
        audio.shutdown()
    }
}

/// Dónde guarda el montaje lo que cambia (la `Library` de la cola; los tests, una versión en memoria).
protocol MontageStoring: Sendable {
    func saveMontage(id: UUID, _ montage: MontageState) async throws
    func saveTakes(id: UUID, _ takes: [Take]) async throws
}

extension Library: MontageStoring {}

/// Guardado por la `Library` de la cola (se serializa con el resto de escrituras de `project.json`).
struct QueueMontageStore: MontageStoring {
    let jobs: JobEngine
    func saveMontage(id: UUID, _ montage: MontageState) async throws { try await jobs.library().saveMontage(id: id, montage) }
    func saveTakes(id: UUID, _ takes: [Take]) async throws { try await jobs.library().saveTakes(id: id, takes) }
}

/// Escritura directa de `project.json` (tests y modo sin biblioteca).
final class FileMontageStore: MontageStoring, @unchecked Sendable {
    private let folder: URL
    private let lock = NSLock()
    init(folder: URL) { self.folder = folder }

    func saveMontage(id: UUID, _ montage: MontageState) async throws {
        try lock.withLock {
            var p = try ProjectFile.load(folder: folder)
            p.montage = montage
            p.updatedAt = Date()
            try ProjectFile.save(p, to: folder)
        }
    }

    func saveTakes(id: UUID, _ takes: [Take]) async throws {
        try lock.withLock {
            var p = try ProjectFile.load(folder: folder)
            for t in takes {
                if let i = p.takes.firstIndex(where: { $0.id == t.id }) { p.takes[i] = t } else { p.takes.append(t) }
            }
            p.updatedAt = Date()
            try ProjectFile.save(p, to: folder)
        }
    }
}
