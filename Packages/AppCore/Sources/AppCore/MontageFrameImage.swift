import Foundation
import VideoKit
#if canImport(CoreVideo)
import CoreVideo
#endif

/// Fotograma BGRA de la vista previa del montaje: el `FramePixelBuffer` de VideoKit en Windows y, para poder probar el
/// núcleo en el Mac, el `CVPixelBuffer` (W2-M1).
#if canImport(CoreVideo)
public typealias MontageFramePixels = CVPixelBuffer
#else
public typealias MontageFramePixels = FramePixelBuffer
#endif

/// Contenedor para pasar un fotograma entre tareas (el compositor no lo toca después de devolverlo).
struct MontageFrameBox: @unchecked Sendable {
    var pixels: MontageFramePixels
}

#if canImport(CoreVideo)
/// Búferes BGRA que pueden acabar en una textura de Flutter (runner de macOS: `copyPixelBuffer` -> `CVMetalTextureCache`),
/// lo que exige respaldo IOSurface y compatibilidad con Metal. Un `CVPixelBufferPool` por tamaño (se recrea si cambia
/// w×h); el pool respeta la retención, así que no reutiliza un búfer que Flutter aún tiene.
final class TextureBufferPool: @unchecked Sendable {
    static let shared = TextureBufferPool()

    nonisolated(unsafe) static let bufferAttributes: CFDictionary = [
        kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        kCVPixelBufferMetalCompatibilityKey: true,
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ] as CFDictionary

    private let lock = NSLock()
    private var pool: CVPixelBufferPool?
    private var size = (w: 0, h: 0)

    /// Búfer BGRA con IOSurface de `width`×`height` (contenido sin definir).
    func make(width: Int, height: Int) -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        if pool == nil || size != (width, height) {
            var p: CVPixelBufferPool?
            let attrs = [kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height].merging(
                Self.bufferAttributes as! [CFString: Any]) { a, _ in a }
            guard CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &p) == kCVReturnSuccess, let p else { return nil }
            pool = p
            size = (width, height)
        }
        var out: CVPixelBuffer?
        if let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out) == kCVReturnSuccess, let out { return out }
        // Sin pool (o agotado): búfer suelto con los mismos atributos.
        var plain: CVPixelBuffer?
        let attrs = Self.bufferAttributes
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs, &plain) == kCVReturnSuccess else { return nil }
        return plain
    }
}
#endif

/// Copia en memoria de un fotograma BGRA y escritura de PNG sin compresión (hoja «Encuadre»: la página lo carga como
/// imagen desde `cache/montage/`; no hace falta un codificador ni zlib).
enum MontageFrameImage {
    struct Raw: Equatable {
        var width: Int
        var height: Int
        var bytesPerRow: Int
        var bytes: [UInt8]
    }

    /// Lado mayor de la imagen de la hoja «Encuadre» (el Mac pedía 1280 × 720 a `AVAssetImageGenerator`).
    static let framingMaxDimension = 1280

    static func raw(_ p: MontageFramePixels) -> Raw? {
        #if canImport(CoreVideo)
        guard CVPixelBufferGetPixelFormatType(p) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(p, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(p, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(p) else { return nil }
        let h = CVPixelBufferGetHeight(p), stride = CVPixelBufferGetBytesPerRow(p)
        return Raw(width: CVPixelBufferGetWidth(p), height: h, bytesPerRow: stride,
                   bytes: Array(UnsafeRawBufferPointer(start: base, count: h * stride)))
        #else
        guard p.pixelFormat == .bgra else { return nil }
        return Raw(width: p.width, height: p.height, bytesPerRow: p.bytesPerRow,
                   bytes: Array(UnsafeRawBufferPointer(start: p.baseAddress, count: p.height * p.bytesPerRow)))
        #endif
    }

    /// Fotograma BGRA liso (tests y simulación).
    static func solid(width: Int, height: Int, b: UInt8, g: UInt8, r: UInt8) -> MontageFramePixels? {
        #if canImport(CoreVideo)
        guard let p = TextureBufferPool.shared.make(width: width, height: height) else { return nil }
        CVPixelBufferLockBaseAddress(p, [])
        defer { CVPixelBufferUnlockBaseAddress(p, []) }
        guard let base = CVPixelBufferGetBaseAddress(p) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(p)
        for y in 0..<height {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width { row[x * 4] = b; row[x * 4 + 1] = g; row[x * 4 + 2] = r; row[x * 4 + 3] = 255 }
        }
        return p
        #else
        let p = FramePixelBuffer(pixelFormat: .bgra, width: width, height: height)
        p.fill(b: b, g: g, r: r)
        return p
        #endif
    }

    // MARK: PNG

    /// PNG RGB de 8 bits; con el lado mayor por encima de `maxDimension` se reduce (muestreo, misma proporción).
    static func png(_ raw: Raw, maxDimension: Int = framingMaxDimension) -> Data {
        let k = min(1, Double(maxDimension) / Double(max(raw.width, raw.height)))
        let w = max(1, Int((Double(raw.width) * k).rounded())), h = max(1, Int((Double(raw.height) * k).rounded()))
        var scan = [UInt8]()
        scan.reserveCapacity(h * (w * 3 + 1))
        for y in 0..<h {
            scan.append(0)   // filtro «ninguno»
            let sy = min(raw.height - 1, y * raw.height / h)
            for x in 0..<w {
                let sx = min(raw.width - 1, x * raw.width / w)
                let o = sy * raw.bytesPerRow + sx * 4
                scan.append(raw.bytes[o + 2]); scan.append(raw.bytes[o + 1]); scan.append(raw.bytes[o])
            }
        }
        var out = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var ihdr = Data()
        ihdr.append(be32(w)); ihdr.append(be32(h)); ihdr.append(contentsOf: [8, 2, 0, 0, 0])
        chunk("IHDR", ihdr, into: &out)
        chunk("IDAT", zlibStored(scan), into: &out)
        chunk("IEND", Data(), into: &out)
        return out
    }

    private static func be32(_ v: Int) -> Data {
        let u = UInt32(truncatingIfNeeded: v)
        return Data([UInt8(u >> 24), UInt8((u >> 16) & 255), UInt8((u >> 8) & 255), UInt8(u & 255)])
    }

    private static func chunk(_ type: String, _ body: Data, into out: inout Data) {
        out.append(be32(body.count))
        var typed = Data(type.utf8)
        typed.append(body)
        out.append(typed)
        out.append(be32(Int(crc32(typed))))
    }

    /// zlib con bloques «stored» (sin compresión), de hasta 65 535 bytes.
    private static func zlibStored(_ data: [UInt8]) -> Data {
        var out = Data([0x78, 0x01])
        var i = 0
        repeat {
            let n = min(65_535, data.count - i)
            let final: UInt8 = i + n >= data.count ? 1 : 0
            out.append(final)
            out.append(UInt8(n & 255)); out.append(UInt8(n >> 8))
            out.append(UInt8(~n & 255)); out.append(UInt8((~n >> 8) & 255))
            out.append(contentsOf: data[i..<(i + n)])
            i += n
        } while i < data.count
        out.append(be32(Int(adler32(data))))
        return out
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in d { c = crcTable[Int((c ^ UInt32(b)) & 255)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    static func adler32(_ d: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for x in d { a = (a + UInt32(x)) % 65_521; b = (b + a) % 65_521 }
        return (b << 16) | a
    }
}
