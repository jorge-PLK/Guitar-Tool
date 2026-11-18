import AVFoundation
import CoreImage
import CoreText
import Foundation
import Metal

/// Instrucción del montaje: una sola para todo el vídeo, con el plan puro y la pista de cada recuadro.
final class MontageInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid

    let timeline: MontageTimeline
    /// Pista de la composición de cada parte de `timeline.parts`.
    let trackIDs: [CMPersistentTrackID]
    /// Giro de cada pista (`VideoRotation`), aplicado a cada fotograma antes de dibujarlo.
    let rotations: [VideoRotation]
    let caption: MontageCaption?

    init(timeRange: CMTimeRange, timeline: MontageTimeline, trackIDs: [CMPersistentTrackID], rotations: [VideoRotation] = [],
         caption: MontageCaption?) {
        self.timeRange = timeRange
        self.timeline = timeline
        self.trackIDs = trackIDs
        self.rotations = rotations
        self.caption = caption
        requiredSourceTrackIDs = trackIDs.map { NSNumber(value: $0) }
    }
}

/// Compositor del montaje (mini-spec Fase 7, «Compositor y vista previa»): `AVVideoCompositing` con Core Image sobre
/// Metal. Para cada fotograma pide a `MontageTimeline` el estado en ese instante y dibuja: fondo #0F1113, cada
/// recuadro (recorte, escala, desenfoque, esquinas redondeadas, sombra suave, nombre abajo a la izquierda,
/// opacidad), el rótulo y el fundido global a negro.
///
/// Sin gestión de color (espacio de trabajo nulo): las mezclas y los fundidos van sobre los valores codificados, como
/// en un editor de vídeo; un fundido al 50 % deja el valor a la mitad.
public final class MontageCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private static let pixelFormat: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int]()
    ]

    private let context: CIContext
    private let renderer = MontageRenderer()

    public override init() {
        let options: [CIContextOption: Any] = [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
        super.init()
    }

    public var sourcePixelBufferAttributes: [String: any Sendable]? { Self.pixelFormat }
    public var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] { Self.pixelFormat }
    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    public func cancelAllPendingVideoCompositionRequests() {}

    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let ins = request.videoCompositionInstruction as? MontageInstruction, let out = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "MontageCompositor", code: 1, userInfo: [NSLocalizedDescriptionKey: "instrucción o búfer"]))
            return
        }
        let t = ins.timeline.timeMap.songTime(videoTime: CMTimeGetSeconds(request.compositionTime))
        let size = CGSize(width: CVPixelBufferGetWidth(out), height: CVPixelBufferGetHeight(out))
        let image = renderer.render(ins.timeline.state(at: t), timeline: ins.timeline, caption: ins.caption, renderSize: size) { i in
            guard i < ins.trackIDs.count, let pb = request.sourceFrame(byTrackID: ins.trackIDs[i]) else { return nil }
            return (ins.rotations[safe: i] ?? .none).apply(CIImage(cvPixelBuffer: pb))
        }
        context.render(image, to: out, bounds: CGRect(origin: .zero, size: size), colorSpace: nil)
        request.finish(withComposedVideoFrame: out)
    }
}

/// Dibujo de un estado en Core Image (coordenadas de Core Image: origen abajo a la izquierda).
final class MontageRenderer: @unchecked Sendable {
    private let lock = NSLock()
    private var textCache: [String: CIImage] = [:]

    func render(_ state: MontageFrameState, timeline: MontageTimeline, caption: MontageCaption?, renderSize: CGSize,
                frame: (Int) -> CIImage?) -> CIImage {
        let s = renderSize.width / max(1, timeline.canvas.width)
        let bounds = CGRect(origin: .zero, size: renderSize)
        func toCI(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * s, y: renderSize.height - r.maxY * s, width: r.width * s, height: r.height * s)
        }
        let bg = MontageStyle.background
        var image = CIImage(color: CIColor(red: Double(bg.r) / 255, green: Double(bg.g) / 255, blue: Double(bg.b) / 255)).cropped(to: bounds)
        let decorated = !timeline.layout.isSingle

        for box in state.boxes {
            let d = toCI(box.displayRect)
            var content: CIImage
            if let src = frame(box.partIndex) {
                if box.fit {
                    content = Self.fitted(src, in: d, scale: s)
                } else {
                    let e = src.extent, c = box.crop
                    let crop = CGRect(x: e.minX + c.x * e.width, y: e.minY + (1 - c.y - c.height) * e.height,
                                      width: c.width * e.width, height: c.height * e.height)
                    content = src.cropped(to: crop)
                        .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                        .transformed(by: CGAffineTransform(scaleX: d.width / crop.width, y: d.height / crop.height))
                        .transformed(by: CGAffineTransform(translationX: d.minX, y: d.minY))
                }
                if box.blur * s > 0.1 {
                    content = content.clampedToExtent().applyingGaussianBlur(sigma: box.blur * s).cropped(to: d)
                }
            } else {
                content = CIImage(color: .black).cropped(to: d)
            }
            if timeline.showPartLabels, let label = label(box.name, size: MontageStyle.labelFont * s * box.scale) {
                let inset = MontageStyle.labelInset * s * box.scale
                content = label.transformed(by: CGAffineTransform(translationX: d.minX + inset, y: d.minY + inset)).composited(over: content)
            }
            // Fundido a negro al acabar la toma: imagen, relleno y nombre (el recuadro sigue, en negro).
            if box.brightness < 1 { content = Self.dimmed(content, box.brightness) }
            var layer = content
            if decorated {
                let r = MontageStyle.cornerRadius * s * box.scale
                // Máscara por alfa (el generador da alfa 1 dentro y suavizado en el borde).
                layer = content.applyingFilter("CIBlendWithAlphaMask", parameters: [
                    kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: roundedRect(d, radius: r, color: .white)
                ])
                let shadow = roundedRect(d.offsetBy(dx: 0, dy: -MontageStyle.shadowOffset * s), radius: r,
                                         color: CIColor(red: 0, green: 0, blue: 0, alpha: MontageStyle.shadowAlpha))
                    .applyingGaussianBlur(sigma: MontageStyle.shadowBlur * s)
                layer = layer.composited(over: shadow)
            }
            image = Self.opacity(layer, box.opacity).composited(over: image)
        }

        if let caption, state.captionOpacity > 0, let plate = captionImage(caption, scale: s) {
            let inset = MontageStyle.captionInset * s
            image = Self.opacity(plate.transformed(by: CGAffineTransform(translationX: inset, y: inset)), state.captionOpacity).composited(over: image)
        }
        if state.fade < 1 {
            let f = CGFloat(max(0, state.fade))
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: f, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: f, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: f, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        }
        return image.cropped(to: bounds)
    }

    /// «Mantener aspect ratio de vídeo» (petición de Jorge del 17/11/2026): la toma entera ajustada y centrada en `d`
    /// sobre un relleno de la misma toma ampliada hasta cubrir `d`, difuminada (`MontageStyle.fillBlur`) y
    /// oscurecida (`fillDim`). El relleno se escala a `fillDownsample` antes de difuminar: el desenfoque trabaja sobre
    /// 1/64 de los píxeles. Mismo fotograma que la imagen nítida, y la opacidad, la escala y el desenfoque de entrada
    /// del recuadro se aplican a los dos juntos.
    static func fitted(_ src: CIImage, in d: CGRect, scale s: Double) -> CIImage {
        let e = src.extent
        guard e.width > 0, e.height > 0, e.width.isFinite, e.height.isFinite else { return CIImage(color: .black).cropped(to: d) }
        func placed(_ k: Double, center: CGPoint) -> CIImage {
            src.transformed(by: CGAffineTransform(translationX: -e.midX, y: -e.midY))
                .transformed(by: CGAffineTransform(scaleX: k, y: k))
                .transformed(by: CGAffineTransform(translationX: center.x, y: center.y))
        }
        let fit = min(d.width / e.width, d.height / e.height), cover = max(d.width / e.width, d.height / e.height)
        let sharp = placed(fit, center: CGPoint(x: d.midX, y: d.midY)).cropped(to: d)
        let q = MontageStyle.fillDownsample, dim = CGFloat(MontageStyle.fillDim)
        let lowRect = CGRect(x: d.minX * q, y: d.minY * q, width: d.width * q, height: d.height * q)
        let fill = placed(cover * q, center: CGPoint(x: d.midX * q, y: d.midY * q)).cropped(to: lowRect)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: MontageStyle.fillBlur * s * q)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: dim, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: dim, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: dim, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
            .transformed(by: CGAffineTransform(scaleX: 1 / q, y: 1 / q))
            .cropped(to: d)
        return sharp.composited(over: fill)
    }

    /// RGB multiplicado por `k` (0…1), alfa intacto.
    static func dimmed(_ image: CIImage, _ k: Double) -> CIImage {
        let f = CGFloat(min(max(k, 0), 1))
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: f, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: f, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: f, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
    }

    static func opacity(_ image: CIImage, _ a: Double) -> CIImage {
        guard a < 1 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(max(0, a)))])
    }

    func roundedRect(_ r: CGRect, radius: Double, color: CIColor) -> CIImage {
        let f = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: r), "inputRadius": max(0, radius), "inputColor": color
        ])
        return f?.outputImage?.cropped(to: r) ?? CIImage(color: color).cropped(to: r)
    }

    /// Nombre de la parte: texto blanco sobre placa oscura translúcida.
    func label(_ text: String, size: Double) -> CIImage? {
        guard size >= 4, !text.isEmpty else { return nil }
        let key = "label|\(text)|\(Int(size * 4))"
        if let hit = lock.withLock({ textCache[key] }) { return hit }
        guard let t = Self.text(text, size: size, bold: true) else { return nil }
        let pad = size * 0.4
        let r = CGRect(x: 0, y: 0, width: t.extent.width + 2 * pad, height: t.extent.height + pad)
        let img = t.transformed(by: CGAffineTransform(translationX: pad, y: pad / 2))
            .composited(over: roundedRect(r, radius: r.height / 2, color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.5)))
        lock.withLock { textCache[key] = img }
        return img
    }

    /// Rótulo: título y debajo artista sobre placa oscura translúcida.
    func captionImage(_ c: MontageCaption, scale s: Double) -> CIImage? {
        let key = "caption|\(c.title)|\(c.artist)|\(Int(s * 1000))"
        if let hit = lock.withLock({ textCache[key] }) { return hit }
        let title = Self.text(c.title, size: MontageStyle.captionTitleFont * s, bold: true)
        let artist = Self.text(c.artist, size: MontageStyle.captionArtistFont * s, bold: false)
        guard title != nil || artist != nil else { return nil }
        let pad = 24 * s, gap = 8 * s
        let w = max(title?.extent.width ?? 0, artist?.extent.width ?? 0) + 2 * pad
        let h = (title?.extent.height ?? 0) + (artist?.extent.height ?? 0) + (title != nil && artist != nil ? gap : 0) + 2 * pad
        var img = roundedRect(CGRect(x: 0, y: 0, width: w, height: h), radius: 16 * s, color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.55))
        if let artist { img = artist.transformed(by: CGAffineTransform(translationX: pad, y: pad)).composited(over: img) }
        if let title {
            let y = pad + (artist.map { $0.extent.height + gap } ?? 0)
            img = title.transformed(by: CGAffineTransform(translationX: pad, y: y)).composited(over: img)
        }
        lock.withLock { textCache[key] = img }
        return img
    }

    static func text(_ text: String, size: Double, bold: Bool) -> CIImage? {
        guard !text.isEmpty, size > 0 else { return nil }
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let w = Int(ceil(width)), h = Int(ceil(ascent + descent))
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.textPosition = CGPoint(x: 0, y: descent)
        CTLineDraw(line, ctx)
        return ctx.makeImage().map { CIImage(cgImage: $0) }
    }
}
