#if os(Windows)
import CDirect2D
import Foundation

/// `MontageFrameRendering` de Windows (plan, «Fase 7c», paso 7, parte 7.9): Direct2D + DirectWrite sobre D3D11 de
/// hardware si lo hay o WARP (software), con las mismas capas y la misma geometría que `MontageRenderer` del Mac.
///
/// Texto: el Mac usa la fuente del sistema (SF, `CTFontCreateUIFontForLanguage` .system / .emphasizedSystem); aquí
/// `fontFamily` (Segoe UI, la de la interfaz de Windows) en Regular / Bold, con la misma caja por línea (ancho del
/// avance, alto ascendente + descendente) y las mismas placas. Las placas se guardan por texto y tamaño, como en el Mac.
public final class Direct2DMontageRenderer: MontageFrameRendering, @unchecked Sendable {
    public struct Device: Sendable, Equatable {
        public var hardware: Bool
        public var adapter: String
    }

    /// Equivalente en Windows de la fuente del sistema del Mac.
    public static let fontFamily = "Segoe UI"
    /// Primer hueco de placa (los de 0 a 63 son las fuentes).
    static let firstPlateSlot: Int32 = 64

    private let lock = NSLock()
    private let allowHardware: Bool
    private var context: UnsafeMutableRawPointer?
    private var size = (width: 0, height: 0)
    private var plates: [String: (slot: Int32, width: Double, height: Double)] = [:]
    private var nextPlate = firstPlateSlot
    private var device_: Device?

    /// `allowHardware` false fuerza WARP (para comparar).
    public init(allowHardware: Bool = true) throws {
        self.allowHardware = allowHardware
        try lock.withLock { _ = try context(width: 16, height: 16) }
    }

    deinit { if let context { tfd2d_release(context) } }

    /// Adaptador en uso.
    public var device: Device? { lock.withLock { device_ } }

    private func check(_ hr: Int32, _ step: String) throws {
        guard hr >= 0 else { throw MontageError.composition("Direct2D \(step): HRESULT 0x" + String(UInt32(bitPattern: hr), radix: 16, uppercase: true)) }
    }

    private func context(width: Int, height: Int) throws -> UnsafeMutableRawPointer {
        if let context, size == (width, height) { return context }
        if let context { tfd2d_release(context) }
        context = nil
        plates = [:]
        nextPlate = Self.firstPlateSlot
        var info = TFD2DInfo()
        var c: UnsafeMutableRawPointer?
        try check(tfd2d_create(Int32(width), Int32(height), allowHardware ? 1 : 0, &c, &info), "crear el contexto \(width)×\(height)")
        guard let c else { throw MontageError.composition("Direct2D sin contexto") }
        let name = withUnsafeBytes(of: info.adapter) { raw in
            String(decoding: raw.bindMemory(to: UInt16.self).prefix { $0 != 0 }, as: UTF16.self)
        }
        device_ = Device(hardware: info.hardware != 0, adapter: name)
        try Self.wide(Self.fontFamily) { try check(tfd2d_set_font(c, $0), "fuente") }
        context = c
        size = (width, height)
        return c
    }

    static func wide<R>(_ s: String, _ body: (UnsafePointer<UInt16>) throws -> R) rethrows -> R {
        let w = Array(s.utf16) + [0]
        return try w.withUnsafeBufferPointer { try body($0.baseAddress!) }
    }

    /// Placa en caché (`key`), creada con `make` la primera vez.
    private func plate(_ c: UnsafeMutableRawPointer, key: String, line1: String, size1: Double, bold1: Bool, line2: String = "", size2: Double = 0,
                       bold2: Bool = false, padX: Double, padY: Double, gap: Double, radius: Double, alpha: Double) throws -> (slot: Int32, width: Double, height: Double) {
        if let hit = plates[key] { return hit }
        guard nextPlate < 1024 else { throw MontageError.composition("Direct2D: demasiadas placas") }
        var w: Float = 0, h: Float = 0
        let slot = nextPlate
        try Self.wide(line1) { l1 in
            try Self.wide(line2) { l2 in
                var p = TFD2DPlate(line1: l1, size1: Float(size1), bold1: bold1 ? 1 : 0, line2: l2, size2: Float(size2), bold2: bold2 ? 1 : 0,
                                   padX: Float(padX), padY: Float(padY), gap: Float(gap), radius: Float(radius), alpha: Float(alpha))
                try check(tfd2d_make_plate(c, slot, &p, &w, &h), "placa «\(line1)»")
            }
        }
        nextPlate += 1
        let out = (slot: slot, width: Double(w), height: Double(h))
        plates[key] = out
        return out
    }

    /// Tamaño de la placa del nombre y del rótulo a escala `s` en un contexto de `width` × `height` (comparación con el Mac).
    func labelPlateSize(_ name: String, size: Double, width: Int, height: Int) throws -> CGSize {
        try lock.withLock {
            let c = try context(width: width, height: height)
            let p = try plate(c, key: "label|\(name)|\(Int(size * 4))", line1: name, size1: size, bold1: true,
                              padX: size * 0.4, padY: size * 0.2, gap: 0, radius: -1, alpha: 0.5)
            return CGSize(width: p.width, height: p.height)
        }
    }

    func captionPlateSize(_ caption: MontageCaption, scale s: Double, width: Int, height: Int) throws -> CGSize {
        try lock.withLock {
            let c = try context(width: width, height: height)
            let p = try plate(c, key: "caption|\(caption.title)|\(caption.artist)|\(Int(s * 1000))",
                              line1: caption.title, size1: MontageStyle.captionTitleFont * s, bold1: true,
                              line2: caption.artist, size2: MontageStyle.captionArtistFont * s, bold2: false,
                              padX: 24 * s, padY: 24 * s, gap: 8 * s, radius: 16 * s, alpha: 0.55)
            return CGSize(width: p.width, height: p.height)
        }
    }

    public func render(_ state: MontageFrameState, timeline: MontageTimeline, caption: MontageCaption?, into output: FramePixelBuffer,
                       source: (Int) -> FramePixelBuffer?) throws {
        guard output.pixelFormat == .bgra else { throw MontageError.composition("Direct2D: la salida debe ser BGRA") }
        try lock.withLock {
            let c = try context(width: output.width, height: output.height)
            let s = Double(output.width) / max(1, timeline.canvas.width)
            let height = Double(output.height)
            // Fuentes de este fotograma (una vez por parte).
            var present = Set<Int>()
            for box in state.boxes where !present.contains(box.partIndex) {
                guard var pb = source(box.partIndex) else { continue }
                if pb.pixelFormat != .bgra { pb = pb.converted(to: .bgra) }
                try check(tfd2d_set_source(c, Int32(box.partIndex), pb.baseAddress.assumingMemoryBound(to: UInt8.self), Int32(pb.bytesPerRow),
                                           Int32(pb.width), Int32(pb.height)), "fuente \(box.partIndex)")
                present.insert(box.partIndex)
            }
            // Placas antes de abrir el fotograma.
            var labels: [Int: (slot: Int32, width: Double, height: Double)] = [:]
            if timeline.showPartLabels {
                for (i, box) in state.boxes.enumerated() {
                    let size = MontageStyle.labelFont * s * box.scale
                    guard size >= 4, !box.name.isEmpty else { continue }
                    labels[i] = try plate(c, key: "label|\(box.name)|\(Int(size * 4))", line1: box.name, size1: size, bold1: true,
                                          padX: size * 0.4, padY: size * 0.2, gap: 0, radius: -1, alpha: 0.5)
                }
            }
            var captionPlate: (slot: Int32, width: Double, height: Double)?
            if let caption, state.captionOpacity > 0, !(caption.title.isEmpty && caption.artist.isEmpty) {
                captionPlate = try plate(c, key: "caption|\(caption.title)|\(caption.artist)|\(Int(s * 1000))",
                                         line1: caption.title, size1: MontageStyle.captionTitleFont * s, bold1: true,
                                         line2: caption.artist, size2: MontageStyle.captionArtistFont * s, bold2: false,
                                         padX: 24 * s, padY: 24 * s, gap: 8 * s, radius: 16 * s, alpha: 0.55)
            }
            let bg = MontageStyle.background
            try check(tfd2d_begin(c, Float(bg.r) / 255, Float(bg.g) / 255, Float(bg.b) / 255), "empezar")
            let decorated = !timeline.layout.isSingle
            var failure: Error?
            for (i, box) in state.boxes.enumerated() {
                let d = box.displayRect
                let x = d.minX * s, y = d.minY * s, w = d.width * s, h = d.height * s
                let inset = MontageStyle.labelInset * s * box.scale
                let label = labels[i]
                var b = TFD2DBox(
                    x: Float(x), y: Float(y), w: Float(w), h: Float(h),
                    slot: present.contains(box.partIndex) ? Int32(box.partIndex) : -1, fit: box.fit ? 1 : 0,
                    cropX: Float(box.crop.x), cropY: Float(box.crop.y), cropW: Float(box.crop.width), cropH: Float(box.crop.height),
                    blur: box.blur * s > 0.1 ? Float(box.blur * s) : 0,
                    fillScale: Float(MontageStyle.fillDownsample), fillBlur: Float(MontageStyle.fillBlur * s), fillDim: Float(MontageStyle.fillDim),
                    brightness: Float(min(max(box.brightness, 0), 1)), opacity: Float(min(max(box.opacity, 0), 1)),
                    decorated: decorated ? 1 : 0, radius: Float(MontageStyle.cornerRadius * s * box.scale),
                    shadowOffset: Float(MontageStyle.shadowOffset * s), shadowBlur: Float(MontageStyle.shadowBlur * s),
                    shadowAlpha: Float(MontageStyle.shadowAlpha),
                    labelSlot: label?.slot ?? -1,
                    // Abajo a la izquierda del recuadro, como en Core Image (origen abajo).
                    labelX: Float(x + inset), labelY: Float(y + h - inset - (label?.height ?? 0)))
                let hr = tfd2d_box(c, &b)
                if hr < 0, failure == nil { failure = MontageError.composition("Direct2D recuadro \(box.partID): HRESULT \(hr)") }
            }
            if let captionPlate {
                let inset = MontageStyle.captionInset * s
                _ = tfd2d_overlay(c, captionPlate.slot, Float(inset), Float(height - inset - captionPlate.height), Float(state.captionOpacity))
            }
            try check(tfd2d_end(c, Float(state.fade), output.baseAddress.assumingMemoryBound(to: UInt8.self), Int32(output.bytesPerRow)), "terminar")
            if let failure { throw failure }
        }
    }
}

extension VideoRotation {
    /// Fotograma BGRA girado (Windows; el Mac gira la `CIImage`). Copia exacta de píxeles, sin remuestrear.
    public func apply(_ pb: FramePixelBuffer) -> FramePixelBuffer {
        guard self != .none else { return pb }
        let src = pb.pixelFormat == .bgra ? pb : pb.converted(to: .bgra)
        let w = src.width, h = src.height
        let out = FramePixelBuffer(pixelFormat: .bgra, width: swapsSize ? h : w, height: swapsSize ? w : h)
        let s = src.baseAddress.assumingMemoryBound(to: UInt32.self), d = out.baseAddress.assumingMemoryBound(to: UInt32.self)
        let sr = src.bytesPerRow / 4, dr = out.bytesPerRow / 4
        for y in 0..<out.height {
            for x in 0..<out.width {
                // Píxel de salida (x, y) ← fuente: 90° horario lleva la esquina superior izquierda a la superior derecha.
                let (sx, sy): (Int, Int) = switch self {
                case .none: (x, y)
                case .clockwise90: (y, h - 1 - x)
                case .upsideDown: (w - 1 - x, h - 1 - y)
                case .clockwise270: (w - 1 - y, x)
                }
                d[y * dr + x] = s[sy * sr + sx]
            }
        }
        return out
    }
}
#endif
