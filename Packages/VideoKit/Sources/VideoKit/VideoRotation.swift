import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// Giro de la imagen de una toma en sentido horario (decisión de Jorge del 17/11/2026: vídeo vertical). Se aplica al
/// leer, sin recodificar: `MontageCompositor` gira cada fotograma, `TakePreview` pone la transformación en la pista,
/// `GuitarFramer` pasa la orientación a Vision. A 90° y 270° el fotograma entregado tiene ancho y alto intercambiados.
public enum VideoRotation: Int, Codable, Sendable, CaseIterable {
    case none = 0
    case clockwise90 = 90
    case upsideDown = 180
    case clockwise270 = 270

    /// Cualquier entero de grados, al cuarto de vuelta más cercano.
    public init(degrees: Int) {
        let q = Int((Double(degrees) / 90).rounded())
        self = VideoRotation(rawValue: ((q % 4) + 4) % 4 * 90) ?? .none
    }

    public var degrees: Int { rawValue }
    /// El siguiente al pulsar «Rotar» (90° más).
    public var next: VideoRotation { VideoRotation(degrees: rawValue + 90) }
    /// ¿Intercambia ancho y alto?
    public var swapsSize: Bool { self == .clockwise90 || self == .clockwise270 }

    /// Tamaño del fotograma ya girado.
    public func rotatedSize(_ s: CGSize) -> CGSize { swapsSize ? CGSize(width: s.height, height: s.width) : s }

    /// Transformación de pista (`preferredTransform`, origen arriba a la izquierda) que gira un fotograma de tamaño
    /// natural `s` y lo deja en el primer cuadrante.
    public func transform(naturalSize s: CGSize) -> CGAffineTransform {
        switch self {
        case .none: .identity
        case .clockwise90: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: s.height, ty: 0)
        case .upsideDown: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: s.width, ty: s.height)
        case .clockwise270: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: s.width)
        }
    }

    /// Orientación EXIF que, al mostrarse, gira la imagen así (la que entienden Vision y `CIImage.oriented`).
    public var orientation: CGImagePropertyOrientation {
        switch self {
        case .none: .up
        case .clockwise90: .right
        case .upsideDown: .down
        case .clockwise270: .left
        }
    }

    /// Imagen de Core Image girada, con su extensión de nuevo en el origen.
    public func apply(_ image: CIImage) -> CIImage {
        guard self != .none else { return image }
        let o = image.oriented(orientation)
        return o.transformed(by: CGAffineTransform(translationX: -o.extent.minX, y: -o.extent.minY))
    }

    /// `CGImage` girada (hoja «Encuadre»); `nil` si no se pudo dibujar.
    public func apply(_ image: CGImage) -> CGImage? {
        guard self != .none else { return image }
        let ci = apply(CIImage(cgImage: image))
        return CIContext(options: [.workingColorSpace: NSNull()]).createCGImage(ci, from: ci.extent)
    }
}
