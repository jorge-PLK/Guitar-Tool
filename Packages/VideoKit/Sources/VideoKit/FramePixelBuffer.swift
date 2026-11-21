#if !canImport(CoreVideo)
import Foundation

/// Imagen de un fotograma fuera del Mac (plan, «Fase 7c», paso 7, parte 7.2): búfer propio en memoria del proceso,
/// el mismo para la captura (NV12 de Media Foundation), el escritor (BGRA o NV12) y el compositor Direct2D (BGRA).
///
/// Forma: `baseAddress` apunta a `byteCount` bytes contiguos, alineados a 64. BGRA: un plano de `height` filas de
/// `bytesPerRow` bytes (B, G, R, A por píxel, de arriba abajo). NV12: plano Y de `height` filas y, justo detrás
/// (`planeBaseAddress(1)`), el plano UV entrelazado (U, V) de `(height + 1) / 2` filas, los dos con `bytesPerRow`.
/// Color BT.709 de rango limitado (16-235) en NV12, como el vídeo exportado del Mac.
///
/// La memoria es del objeto (se libera en `deinit`); quien comparte un búfer entre hilos no lo escribe a la vez.
public final class FramePixelBuffer: @unchecked Sendable {
    public enum PixelFormat: String, Sendable, Equatable {
        case bgra, nv12
    }

    /// Alineación de las filas y de la base (decisión propia: la de una línea de caché, la que pide Direct2D a lo sumo).
    public static let alignment = 64

    public let pixelFormat: PixelFormat
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let byteCount: Int
    public let baseAddress: UnsafeMutableRawPointer

    /// Búfer a cero (negro en BGRA con alfa 0; en NV12, Y = 0 y UV = 0). `bytesPerRow` por defecto: el mínimo redondeado
    /// a `alignment`.
    public init(pixelFormat: PixelFormat, width: Int, height: Int, bytesPerRow: Int? = nil) {
        precondition(width > 0 && height > 0, "FramePixelBuffer: tamaño vacío")
        let minRow = pixelFormat == .bgra ? 4 * width : 2 * ((width + 1) / 2)
        let row = bytesPerRow ?? (minRow + Self.alignment - 1) / Self.alignment * Self.alignment
        precondition(row >= minRow, "FramePixelBuffer: bytesPerRow \(row) < \(minRow)")
        self.pixelFormat = pixelFormat
        self.width = width
        self.height = height
        self.bytesPerRow = row
        let rows = pixelFormat == .bgra ? height : height + (height + 1) / 2
        byteCount = row * rows
        baseAddress = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: Self.alignment)
        baseAddress.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
    }

    deinit { baseAddress.deallocate() }

    public var planeCount: Int { pixelFormat == .bgra ? 1 : 2 }

    /// Filas del plano (`height`, o `(height + 1) / 2` para el UV de NV12).
    public func planeHeight(_ plane: Int) -> Int { plane == 0 ? height : (height + 1) / 2 }

    public func planeBaseAddress(_ plane: Int) -> UnsafeMutableRawPointer {
        precondition(plane >= 0 && plane < planeCount)
        return plane == 0 ? baseAddress : baseAddress + bytesPerRow * height
    }

    /// Rellena con un color (BGRA tal cual; NV12 convertido a BT.709 de rango limitado).
    public func fill(b: UInt8, g: UInt8, r: UInt8, a: UInt8 = 255) {
        switch pixelFormat {
        case .bgra:
            for y in 0..<height {
                let row = (baseAddress + y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width {
                    row[4 * x] = b
                    row[4 * x + 1] = g
                    row[4 * x + 2] = r
                    row[4 * x + 3] = a
                }
            }
        case .nv12:
            let (yv, u, v) = Self.ycbcr(r: Int(r), g: Int(g), b: Int(b))
            for y in 0..<height {
                (baseAddress + y * bytesPerRow).initializeMemory(as: UInt8.self, repeating: yv, count: width)
            }
            let uv = planeBaseAddress(1)
            for y in 0..<planeHeight(1) {
                let row = (uv + y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<(width + 1) / 2 {
                    row[2 * x] = u
                    row[2 * x + 1] = v
                }
            }
        }
    }

    /// Color de un píxel en (B, G, R) (NV12 pasado de BT.709 de rango limitado).
    public func pixel(x: Int, y: Int) -> (b: UInt8, g: UInt8, r: UInt8) {
        precondition(x >= 0 && x < width && y >= 0 && y < height)
        switch pixelFormat {
        case .bgra:
            let p = (baseAddress + y * bytesPerRow + 4 * x).assumingMemoryBound(to: UInt8.self)
            return (p[0], p[1], p[2])
        case .nv12:
            let yv = Int((baseAddress + y * bytesPerRow + x).load(as: UInt8.self))
            let c = (planeBaseAddress(1) + (y / 2) * bytesPerRow + 2 * (x / 2)).assumingMemoryBound(to: UInt8.self)
            return Self.rgb(y: yv, u: Int(c[0]), v: Int(c[1]))
        }
    }

    /// BT.709 de rango limitado en coma fija de 16 bits (la misma cuenta que el shim de Media Foundation).
    static func ycbcr(r: Int, g: Int, b: Int) -> (UInt8, UInt8, UInt8) {
        let y = 16 + ((11966 * r + 40254 * g + 4064 * b + 32768) >> 16)
        let u = 128 + ((-6598 * r - 22187 * g + 28784 * b + 32768) >> 16)
        let v = 128 + ((28784 * r - 26148 * g - 2637 * b + 32768) >> 16)
        return (clamp(y), clamp(u), clamp(v))
    }

    static func rgb(y: Int, u: Int, v: Int) -> (b: UInt8, g: UInt8, r: UInt8) {
        let c = 76309 * (y - 16), d = u - 128, e = v - 128
        return (clamp((c + 138_438 * d + 32768) >> 16), clamp((c - 13975 * d - 34925 * e + 32768) >> 16),
                clamp((c + 117_489 * e + 32768) >> 16))
    }

    static func clamp(_ v: Int) -> UInt8 { UInt8(max(0, min(255, v))) }
}
#endif
