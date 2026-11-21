import Foundation
import VideoKit

/// `tf-video frame --png` fuera del Mac (parte 7.11b): cajas trazadas sobre un fotograma BGRA y PNG RGB de 8 bits sin
/// compresión (deflate con bloques guardados, filtro 0), sin dependencias. Puro y portable: se prueba en el Mac
/// (`FramePNGTests`); en el Mac `frame` sigue con Core Graphics e ImageIO.
enum FramePNG {
    typealias RGB = (r: UInt8, g: UInt8, b: UInt8)

    /// Colores del Mac (`MontageCommands.frame`): rojo = caja fija, verde = trayectoria.
    static let fixedColor: RGB = (255, 51, 51)
    static let trackColor: RGB = (51, 255, 77)

    /// Grosor como el Mac: máx(2, ancho/300) px.
    static func lineWidth(imageWidth w: Int) -> Int { max(2, Int((Double(w) / 300).rounded())) }

    /// Traza el borde de `box` (normalizada, origen arriba a la izquierda) centrado en el borde, como
    /// `CGContext.stroke`: cada lado ocupa `lineWidth` px repartidos a ambos lados de la línea, recortado a la imagen.
    static func stroke(_ box: FramingBox, color: RGB, lineWidth lw: Int, pixels: UnsafeMutableRawPointer, width: Int,
                       height: Int, bytesPerRow: Int) {
        let x0 = box.x * Double(width), x1 = (box.x + box.width) * Double(width)
        let y0 = box.y * Double(height), y1 = (box.y + box.height) * Double(height)
        let half = Double(lw) / 2
        func fill(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) {
            let xa = max(0, Int(ax.rounded())), xb = min(width, Int(bx.rounded()))
            let ya = max(0, Int(ay.rounded())), yb = min(height, Int(by.rounded()))
            guard xa < xb, ya < yb else { return }
            let p = pixels.assumingMemoryBound(to: UInt8.self)
            for y in ya..<yb {
                for x in xa..<xb {
                    let o = y * bytesPerRow + x * 4
                    p[o] = color.b; p[o + 1] = color.g; p[o + 2] = color.r; p[o + 3] = 255
                }
            }
        }
        fill(x0 - half, y0 - half, x1 + half, y0 + half)   // arriba
        fill(x0 - half, y1 - half, x1 + half, y1 + half)   // abajo
        fill(x0 - half, y0 - half, x0 + half, y1 + half)   // izquierda
        fill(x1 - half, y0 - half, x1 + half, y1 + half)   // derecha
    }

    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    /// PNG RGB de 8 bits de un búfer BGRA (el alfa se descarta).
    static func encode(pixels: UnsafeRawPointer, width w: Int, height h: Int, bytesPerRow: Int) -> Data {
        func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)] }
        func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
            let t = Array(type.utf8)
            var c: UInt32 = 0xFFFF_FFFF
            for b in t { c = crcTable[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
            for b in body { c = crcTable[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
            return be32(UInt32(body.count)) + t + body + be32(c ^ 0xFFFF_FFFF)
        }
        let src = pixels.assumingMemoryBound(to: UInt8.self)
        var raw = [UInt8]()
        raw.reserveCapacity(h * (1 + w * 3))
        for y in 0..<h {
            raw.append(0)
            for x in 0..<w {
                let o = y * bytesPerRow + x * 4
                raw.append(src[o + 2]); raw.append(src[o + 1]); raw.append(src[o])
            }
        }
        var z: [UInt8] = [0x78, 0x01]
        z.reserveCapacity(raw.count + raw.count / 65_535 * 5 + 16)
        var i = 0
        repeat {
            let n = min(65_535, raw.count - i)
            let final: UInt8 = i + n >= raw.count ? 1 : 0
            z += [final, UInt8(n & 0xff), UInt8(n >> 8), UInt8(~n & 0xff), UInt8((~n >> 8) & 0xff)]
            z += raw[i..<(i + n)]
            i += n
        } while i < raw.count
        var a: UInt32 = 1, b: UInt32 = 0
        for v in raw { a = (a + UInt32(v)) % 65_521; b = (b + a) % 65_521 }
        z += be32(b << 16 | a)
        let header = be32(UInt32(w)) + be32(UInt32(h)) + [8, 2, 0, 0, 0]
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", header) + chunk("IDAT", z) + chunk("IEND", []))
    }
}
