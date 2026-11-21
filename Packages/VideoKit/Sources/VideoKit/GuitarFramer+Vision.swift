#if canImport(Vision)
import AVFoundation
import CoreVideo
import Vision
#else
import NativePlatform
#endif
import Foundation

public enum GuitarFramerError: Error, Equatable, Sendable {
    case noVideo(String)
    case read(String)
}

#if !canImport(Vision)
/// Windows: sin lector de vídeo ni detector de pose todavía (paso 7: encuadre). Misma API que la extensión de
/// Vision; la lógica de la caja (`analyze(samples:…)`, `crop`, `box`) sí está.
public extension GuitarFramer {
    static func analyze(video: MontagePartVideo, interval: Double = defaultInterval,
                        progress: (@Sendable (Double) -> Void)? = nil) async throws -> FramingAnalysis {
        throw PlatformError.unsupported("paso 7: encuadre")
    }

    static func analyze(videoURL: URL, interval: Double = defaultInterval) async throws -> FramingAnalysis {
        throw PlatformError.unsupported("paso 7: encuadre")
    }
}
#else

/// La parte de `GuitarFramer` que lee la toma y llama a Vision (pose corporal).
public extension GuitarFramer {
    /// Analiza la toma compuesta (base y punches con sus desfases, en tiempo del tema): un fotograma cada `interval`
    /// segundos, pose con Vision y `analyze(samples:…)`. `progress` recibe la fracción leída.
    static func analyze(video: MontagePartVideo, interval: Double = defaultInterval,
                        progress: (@Sendable (Double) -> Void)? = nil) async throws -> FramingAnalysis {
        guard let take = try await LoadedTakeVideo.load(video), let first = take.firstImage, let last = take.lastImage else {
            throw GuitarFramerError.noVideo(video.url?.lastPathComponent ?? "sin vídeo")
        }
        let comp = AVMutableComposition()
        guard let track = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw GuitarFramerError.read("pista de vídeo")
        }
        try take.insert(into: track, origin: first, duration: last - first, hold: 0)
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: comp) } catch { throw GuitarFramerError.read("\(error)") }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        out.alwaysCopiesSampleData = false
        reader.add(out)
        guard reader.startReading() else { throw GuitarFramerError.read(reader.error.map { "\($0)" } ?? "startReading") }

        var samples: [PoseSample] = []
        var size = (w: Int(take.frameSize.width), h: Int(take.frameSize.height))
        var next = first
        while let sb = out.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
            let song = first + CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            guard song + 1e-6 >= next else { continue }
            // Coordenadas de la imagen ya girada (las del encuadre): Vision recibe la orientación y el tamaño se gira.
            let rotated = take.rotation.rotatedSize(CGSize(width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb)))
            size = (Int(rotated.width), Int(rotated.height))
            samples.append(PoseSample(time: song, joints: (try? joints(in: pb, orientation: take.rotation.orientation)) ?? [:]))
            while next <= song + 1e-6 { next += interval }
            progress?(min(1, (song - first) / max(1e-6, last - first)))
        }
        if reader.status == .failed { throw GuitarFramerError.read(reader.error.map { "\($0)" } ?? "lectura") }
        return analyze(samples: samples, frameWidth: size.w, frameHeight: size.h, fingerprint: fingerprint(video: video))
    }

    /// Un vídeo suelto (`tf-video frame`): su tramo de imagen como toma, sin desfase ni punches.
    static func analyze(videoURL: URL, interval: Double = defaultInterval) async throws -> FramingAnalysis {
        guard let src = try await TakePreview.source(videoURL) else { throw GuitarFramerError.noVideo(videoURL.lastPathComponent) }
        let span = MontageSpan(start: src.available.lowerBound, end: src.available.upperBound)
        return try await analyze(video: MontagePartVideo(url: videoURL, videoOffset: 0, take: span), interval: interval)
    }

    /// Articulaciones de la persona más grande del fotograma (las de confianza ≥ `minConfidence`), normalizadas con
    /// origen arriba a la izquierda, sobre la imagen ya orientada con `orientation` (giro de la toma).
    static func joints(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up) throws -> [PoseJoint: PosePoint] {
        let request = VNDetectHumanBodyPoseRequest()
        try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation).perform([request])
        let names: [PoseJoint: VNHumanBodyPoseObservation.JointName] = [
            .leftWrist: .leftWrist, .rightWrist: .rightWrist, .leftElbow: .leftElbow, .rightElbow: .rightElbow,
            .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder, .neck: .neck, .root: .root,
            .leftHip: .leftHip, .rightHip: .rightHip
        ]
        var best: [PoseJoint: PosePoint] = [:]
        var bestArea = -1.0
        for obs in request.results ?? [] {
            var j: [PoseJoint: PosePoint] = [:]
            for (k, name) in names {
                guard let p = try? obs.recognizedPoint(name), p.confidence >= minConfidence else { continue }
                j[k] = PosePoint(x: Double(p.location.x), y: 1 - Double(p.location.y))
            }
            guard !j.isEmpty else { continue }
            let xs = j.values.map(\.x), ys = j.values.map(\.y)
            let area = (xs.max()! - xs.min()!) * (ys.max()! - ys.min()!)
            if area > bestArea { bestArea = area; best = j }
        }
        return best
    }
}
#endif
