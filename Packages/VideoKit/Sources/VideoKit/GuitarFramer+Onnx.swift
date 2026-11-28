#if os(Windows)
import Foundation
import NativeONNX

// Encuadre en Windows (plan, «Corte del paso 7», parte 7.11): la toma se lee con Media Foundation (`LoadedTakeVideo`
// y `TakeFrameReader` de la parte 7.9, fotogramas BGRA ya girados) y la pose sale de MoveNet sobre ONNX Runtime
// (`MoveNetPose`, modelo de la parte 7.3). Misma API que la extensión de Vision del Mac, más `poseModel`.

/// MoveNet Thunder en ONNX Runtime: `image` (1, 256, 256, 3) → `output_0` (1, 1, 17, 3). Proveedor elegido por
/// `OnnxModelLoader`, como los predictores de StudyKit y TabKit.
final class OnnxPoseModel: PoseKeypointModel, @unchecked Sendable {
    private let session: OnnxSession

    init(modelURL: URL) throws {
        do {
            session = try OnnxModelLoader.session(modelURL: modelURL, model: MoveNetPose.modelFolder)
        } catch {
            throw GuitarFramerError.read("no se pudo cargar \(modelURL.lastPathComponent): \(error)")
        }
    }

    func keypoints(input: [Float]) throws -> [Float] {
        let s = MoveNetPose.inputSide, n = MoveNetPose.keypointCount
        guard input.count == s * s * 3 else {
            throw GuitarFramerError.read("entrada de \(input.count) valores, se esperaban \(s * s * 3)")
        }
        var image = input
        var out = [Float](repeating: 0, count: n * 3)
        try image.withUnsafeMutableBufferPointer { i in
            try out.withUnsafeMutableBufferPointer { o in
                try session.run(inputs: [OnnxBuffer(name: MoveNetPose.inputName, shape: [1, s, s, 3], pointer: i.baseAddress!)],
                                outputs: [OnnxBuffer(name: MoveNetPose.outputName, shape: [1, 1, n, 3], pointer: o.baseAddress!)])
            }
        }
        return out
    }
}

public extension GuitarFramer {
    /// Analiza la toma compuesta (base y punches con sus desfases, en tiempo del tema): el fotograma visible cada
    /// `interval` segundos, pose con MoveNet y `analyze(samples:…)`. `progress` recibe la fracción leída.
    /// `poseModel`: el `.onnx` de MoveNet; sin él, `<TF_MODELS_DIR o C:\tf-models>\pose\model.onnx`.
    static func analyze(video: MontagePartVideo, interval: Double = defaultInterval, poseModel: URL? = nil,
                        progress: (@Sendable (Double) -> Void)? = nil) async throws -> FramingAnalysis {
        guard let take = try LoadedTakeVideo.load(video), let first = take.firstImage, let last = take.lastImage else {
            throw GuitarFramerError.noVideo(video.url?.lastPathComponent ?? "sin vídeo")
        }
        let detector = try poseDetector(modelURL: poseModel)
        let readers = take.readers()
        var samples: [PoseSample] = []
        var size = (w: Int(take.frameSize.width), h: Int(take.frameSize.height))
        var index = 0
        while true {
            let t = first + Double(index) * interval
            guard t < last - 1e-6 else { break }
            index += 1
            try Task.checkCancellation()
            guard let piece = take.pieces.last(where: { t >= $0.start && t < $0.end }) else { continue }
            let frame: FramePixelBuffer?
            do { frame = try readers[piece.source].frame(at: piece.sourceStart + (t - piece.start)) } catch {
                throw GuitarFramerError.read("\(error)")
            }
            guard let frame else { continue }
            // Coordenadas de la imagen ya girada (las del encuadre), como en el Mac. Un fallo de inferencia deja el
            // fotograma sin pose, como Vision en el Mac (`frameJoints`); leer mal el vídeo sí es error.
            size = (frame.width, frame.height)
            let joints = detector.frameJoints(pixels: UnsafeRawPointer(frame.baseAddress), width: frame.width,
                                              height: frame.height, bytesPerRow: frame.bytesPerRow, layout: .bgra)
            samples.append(PoseSample(time: t, joints: joints))
            progress?(min(1, (t - first) / max(1e-6, last - first)))
        }
        return analyze(samples: samples, frameWidth: size.w, frameHeight: size.h, fingerprint: fingerprint(video: video))
    }

    /// Un vídeo suelto (`tf-video frame`): su tramo de imagen como toma, sin desfase ni punches.
    static func analyze(videoURL: URL, interval: Double = defaultInterval, poseModel: URL? = nil) async throws -> FramingAnalysis {
        guard let file = try TakeVideoFile.open(videoURL) else { throw GuitarFramerError.noVideo(videoURL.lastPathComponent) }
        let span = MontageSpan(start: file.available.lowerBound, end: file.available.upperBound)
        return try await analyze(video: MontagePartVideo(url: videoURL, videoOffset: 0, take: span), interval: interval,
                                 poseModel: poseModel)
    }

    /// `tf-video frame --png` (parte 7.11b): el fotograma BGRA visible en el centro del tramo de imagen de un vídeo
    /// suelto, sin giro, y ese instante (tiempo del tema), como el `AVAssetImageGenerator` del Mac; `nil` sin imagen.
    static func middleFrame(videoURL: URL) throws -> (time: Double, image: FramePixelBuffer)? {
        guard let file = try TakeVideoFile.open(videoURL) else { return nil }
        let mid = (file.available.lowerBound + file.available.upperBound) / 2
        let image: FramePixelBuffer?
        do { image = try TakeFrameReader(file: file, rotation: VideoRotation(degrees: 0)).frame(at: mid) } catch {
            throw GuitarFramerError.read("\(error)")
        }
        guard let image else { return nil }
        return (time: mid, image: image)
    }
}

extension GuitarFramer {
    /// MoveNet desde `modelURL`, `TF_MODELS_DIR`, el empaquetado junto al .exe (`models\pose`) o `C:\tf-models`
    /// (`OnnxDevelopmentModels.resolve`, carpeta `pose`).
    static func poseDetector(modelURL: URL?,
                             environment: [String: String] = ProcessInfo.processInfo.environment,
                             executableDirectory: URL? = OnnxDevelopmentModels.hostExecutableDirectory()) throws -> MoveNetPoseDetector {
        guard let url = modelURL ?? OnnxDevelopmentModels.resolve(MoveNetPose.modelFolder, environment: environment,
                                                                  executableDirectory: executableDirectory) else {
            let tried = OnnxDevelopmentModels.candidates(MoveNetPose.modelFolder, environment: environment,
                                                         executableDirectory: executableDirectory).map(\.path)
            throw GuitarFramerError.read("sin modelo de pose; rutas probadas: \(tried.joined(separator: ", "))")
        }
        return MoveNetPoseDetector(model: try OnnxPoseModel(modelURL: url))
    }
}
#endif
