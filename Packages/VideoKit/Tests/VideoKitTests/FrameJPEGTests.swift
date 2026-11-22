#if canImport(CoreVideo)
import CoreGraphics
import CoreVideo
import ImageIO
#endif
import Foundation
import XCTest
@testable import VideoKit

/// W2-E1: codificador JPEG de fotogramas para la página (dimensiones, que se decodifica, colores de un NV12 de
/// prueba dentro de tolerancia, y coste por fotograma 1080p→640 y 720p→640).
final class FrameJPEGTests: XCTestCase {
    typealias RGB = (r: Int, g: Int, b: Int)

    /// Colores de los cuatro cuadrantes (arriba izq., arriba dcha., abajo izq., abajo dcha.).
    static let quadrants: [RGB] = [(200, 30, 30), (30, 180, 40), (40, 50, 210), (128, 128, 128)]
    /// Tolerancia por canal tras NV12 (8 bits, BT.709 limitado) + JPEG calidad 0,7, en el centro de cada cuadrante
    /// (decisión propia: un 4 % del fondo de escala; el error de color que aprecia el ojo en una vista previa).
    static let colorTolerance = 10

    // MARK: - Señales de prueba (búferes en bruto, iguales en el Mac y en Windows)

    /// BT.709 de rango limitado, la cuenta de `FramePixelBuffer.ycbcr` (shim de Media Foundation).
    static func ycbcr709(_ c: RGB) -> (UInt8, UInt8, UInt8) {
        func cl(_ v: Int) -> UInt8 { UInt8(max(0, min(255, v))) }
        let y = 16 + ((11966 * c.r + 40254 * c.g + 4064 * c.b + 32768) >> 16)
        let u = 128 + ((-6598 * c.r - 22187 * c.g + 28784 * c.b + 32768) >> 16)
        let v = 128 + ((28784 * c.r - 26148 * c.g - 2637 * c.b + 32768) >> 16)
        return (cl(y), cl(u), cl(v))
    }

    static func quadrant(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Int { (y < h / 2 ? 0 : 2) + (x < w / 2 ? 0 : 1) }

    /// NV12 de cuadrantes: plano Y de `w × h` y UV entrelazado de `w × h/2`, filas de `stride` bytes.
    static func nv12Quadrants(width w: Int, height h: Int, stride: Int) -> (y: [UInt8], uv: [UInt8]) {
        var y = [UInt8](repeating: 0, count: stride * h), uv = [UInt8](repeating: 0, count: stride * ((h + 1) / 2))
        let codes = quadrants.map(ycbcr709)
        for r in 0..<h { for x in 0..<w { y[r * stride + x] = codes[quadrant(x, r, w, h)].0 } }
        for r in 0..<(h + 1) / 2 {
            for x in 0..<(w + 1) / 2 {
                let c = codes[quadrant(2 * x, 2 * r, w, h)]
                uv[r * stride + 2 * x] = c.1
                uv[r * stride + 2 * x + 1] = c.2
            }
        }
        return (y, uv)
    }

    static func bgraQuadrants(width w: Int, height h: Int, stride: Int) -> [UInt8] {
        var p = [UInt8](repeating: 255, count: stride * h)
        for r in 0..<h {
            for x in 0..<w {
                let c = quadrants[quadrant(x, r, w, h)], o = r * stride + 4 * x
                p[o] = UInt8(c.b); p[o + 1] = UInt8(c.g); p[o + 2] = UInt8(c.r)
            }
        }
        return p
    }

    /// «Escena» con textura (degradados, rejilla fina y ruido determinista) para tamaños y tiempos realistas: los
    /// colores planos comprimen demasiado bien.
    static func bgraScene(width w: Int, height h: Int, stride: Int) -> [UInt8] {
        var p = [UInt8](repeating: 255, count: stride * h)
        var seed: UInt32 = 0x1234_5678
        for r in 0..<h {
            for x in 0..<w {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let n = Int(seed >> 27) - 16                                    // ruido ±16
                let grid = ((x / 7 + r / 7) & 1) * 40                           // rejilla de 7 px
                let o = r * stride + 4 * x
                p[o] = UInt8(max(0, min(255, x * 255 / w + n)))
                p[o + 1] = UInt8(max(0, min(255, r * 255 / h + grid + n)))
                p[o + 2] = UInt8(max(0, min(255, (x + r) * 255 / (w + h) + n)))
            }
        }
        return p
    }

    // MARK: - Decodificación (solo Mac: ImageIO; en Windows se comprueba la estructura)

    struct Decoded {
        let width: Int, height: Int
        let pixels: [UInt8]   // RGBA
        func rgb(_ x: Int, _ y: Int) -> RGB { let o = (y * width + x) * 4; return (Int(pixels[o]), Int(pixels[o + 1]), Int(pixels[o + 2])) }
    }

    static func decode(_ data: Data) -> Decoded? {
        #if canImport(ImageIO)
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? Decoded(width: w, height: h, pixels: px) : nil
        #else
        return nil
        #endif
    }

    /// SOI, EOI y el tamaño del SOF0 (lo que se puede comprobar sin decodificador).
    static func sofSize(_ data: Data) -> (width: Int, height: Int)? {
        let b = [UInt8](data)
        guard b.count > 4, b[0] == 0xFF, b[1] == 0xD8, b[b.count - 2] == 0xFF, b[b.count - 1] == 0xD9 else { return nil }
        var i = 2
        while i + 9 < b.count, b[i] == 0xFF {
            let len = Int(b[i + 2]) << 8 | Int(b[i + 3])
            if b[i + 1] == 0xC0 { return (Int(b[i + 7]) << 8 | Int(b[i + 8]), Int(b[i + 5]) << 8 | Int(b[i + 6])) }
            i += 2 + len
        }
        return nil
    }

    /// Peor error por canal en el centro de cada cuadrante (ventana de 5×5 promediada).
    static func worstQuadrantError(_ d: Decoded) -> Int {
        var worst = 0
        for (q, c) in quadrants.enumerated() {
            let cx = (q & 1 == 0 ? 1 : 3) * d.width / 4, cy = (q < 2 ? 1 : 3) * d.height / 4
            var s = (0, 0, 0)
            for dy in -2...2 { for dx in -2...2 { let p = d.rgb(cx + dx, cy + dy); s.0 += p.r; s.1 += p.g; s.2 += p.b } }
            let m = (s.0 / 25, s.1 / 25, s.2 / 25)
            worst = max(worst, abs(m.0 - c.r), abs(m.1 - c.g), abs(m.2 - c.b))
        }
        return worst
    }

    // MARK: - Tamaño de salida

    func testOutputSize() {
        XCTAssertTrue(FrameJPEGEncoder.outputSize(width: 1920, height: 1080, maxWidth: 640) == (640, 360))
        XCTAssertTrue(FrameJPEGEncoder.outputSize(width: 1280, height: 720, maxWidth: 640) == (640, 360))
        XCTAssertTrue(FrameJPEGEncoder.outputSize(width: 1080, height: 1920, maxWidth: 640) == (640, 1138))
        XCTAssertTrue(FrameJPEGEncoder.outputSize(width: 320, height: 240, maxWidth: 640) == (320, 240), "no amplía")
        XCTAssertTrue(FrameJPEGEncoder.outputSize(width: 333, height: 201, maxWidth: 640) == (332, 200), "pares")
    }

    // MARK: - Núcleo portátil (el de Windows), probado en el Mac

    func testPortableNV12ColorsAndSize() throws {
        for (w, h) in [(1920, 1080), (1280, 720)] {
            let stride = (w + 63) / 64 * 64
            let (y, uv) = Self.nv12Quadrants(width: w, height: h, stride: stride)
            let (ow, oh) = FrameJPEGEncoder.outputSize(width: w, height: h, maxWidth: 640)
            let data = y.withUnsafeBufferPointer { yp in uv.withUnsafeBufferPointer { cp in
                PortableJPEG().encodeNV12(y: yp.baseAddress!, yStride: stride, uv: cp.baseAddress!, uvStride: stride,
                                          width: w, height: h, outWidth: ow, outHeight: oh, quality: 70)
            }}
            let sof = try XCTUnwrap(Self.sofSize(data))
            XCTAssertTrue(sof == (640, 360), "\(w)×\(h): SOF \(sof)")
            #if canImport(ImageIO)
            let d = try XCTUnwrap(Self.decode(data), "\(w)×\(h): ImageIO no lo decodifica")
            XCTAssertEqual(d.width, 640); XCTAssertEqual(d.height, 360)
            let err = Self.worstQuadrantError(d)
            print(String(format: "W2-E1 portátil NV12 %d×%d → 640×360: %d B, error de color máx. %d (tolerancia %d)",
                         w, h, data.count, err, Self.colorTolerance))
            XCTAssertLessThanOrEqual(err, Self.colorTolerance)
            #endif
        }
    }

    /// Tamaños que no son múltiplo de 16 (bordes repetidos en los MCU) y sin reducción (copia directa).
    func testPortableBGRAOddSizesAndNoScale() throws {
        for (w, h) in [(333, 201), (640, 360), (98, 50)] {
            let stride = w * 4 + 12
            let px = Self.bgraQuadrants(width: w, height: h, stride: stride)
            let (ow, oh) = FrameJPEGEncoder.outputSize(width: w, height: h, maxWidth: 640)
            let data = px.withUnsafeBufferPointer {
                PortableJPEG().encodeBGRA($0.baseAddress!, stride: stride, width: w, height: h, outWidth: ow, outHeight: oh, quality: 70)
            }
            let sof = try XCTUnwrap(Self.sofSize(data))
            XCTAssertTrue(sof == (ow, oh), "\(w)×\(h): SOF \(sof), esperado \(ow)×\(oh)")
            #if canImport(ImageIO)
            let d = try XCTUnwrap(Self.decode(data))
            XCTAssertLessThanOrEqual(Self.worstQuadrantError(d), Self.colorTolerance, "\(w)×\(h)")
            #endif
        }
    }

    /// Más calidad → más bytes y menos error en la escena con textura.
    func testPortableQualityOrdersSizeAndError() throws {
        let (w, h) = (640, 360), stride = 640 * 4
        let px = Self.bgraScene(width: w, height: h, stride: stride)
        var sizes: [Int] = []
        for q in [30, 70, 95] {
            let data = px.withUnsafeBufferPointer {
                PortableJPEG().encodeBGRA($0.baseAddress!, stride: stride, width: w, height: h, outWidth: w, outHeight: h, quality: q)
            }
            sizes.append(data.count)
            #if canImport(ImageIO)
            XCTAssertNotNil(Self.decode(data), "calidad \(q)")
            #endif
        }
        XCTAssertLessThan(sizes[0], sizes[1]); XCTAssertLessThan(sizes[1], sizes[2])
    }

    #if canImport(CoreVideo)
    // MARK: - Camino del Mac (vImage + ImageIO) con `CVPixelBuffer`

    static func pixelBuffer(_ format: OSType, width w: Int, height h: Int) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        guard CVPixelBufferCreate(nil, w, h, format, attrs, &pb) == kCVReturnSuccess, let pb else {
            throw FrameJPEGError.encodeFailed("CVPixelBufferCreate")
        }
        return pb
    }

    static func macNV12(width w: Int, height h: Int) throws -> CVPixelBuffer {
        let pb = try pixelBuffer(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, width: w, height: h)
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        let ys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), cs = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
        let yp = CVPixelBufferGetBaseAddressOfPlane(pb, 0)!.assumingMemoryBound(to: UInt8.self)
        let cp = CVPixelBufferGetBaseAddressOfPlane(pb, 1)!.assumingMemoryBound(to: UInt8.self)
        let codes = quadrants.map(ycbcr709)
        for r in 0..<h { for x in 0..<w { yp[r * ys + x] = codes[quadrant(x, r, w, h)].0 } }
        for r in 0..<h / 2 {
            for x in 0..<w / 2 {
                let c = codes[quadrant(2 * x, 2 * r, w, h)]
                cp[r * cs + 2 * x] = c.1; cp[r * cs + 2 * x + 1] = c.2
            }
        }
        return pb
    }

    static func macBGRA(width w: Int, height h: Int, scene: Bool) throws -> CVPixelBuffer {
        let pb = try pixelBuffer(kCVPixelFormatType_32BGRA, width: w, height: h)
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        let stride = CVPixelBufferGetBytesPerRow(pb)
        let src = scene ? bgraScene(width: w, height: h, stride: stride) : bgraQuadrants(width: w, height: h, stride: stride)
        src.withUnsafeBytes { CVPixelBufferGetBaseAddress(pb)!.copyMemory(from: $0.baseAddress!, byteCount: stride * h) }
        return pb
    }

    func testMacNV12AndBGRAColors() throws {
        let enc = FrameJPEGEncoder()
        for (w, h) in [(1920, 1080), (1280, 720)] {
            for (name, pb) in [("NV12", try Self.macNV12(width: w, height: h)), ("BGRA", try Self.macBGRA(width: w, height: h, scene: false))] {
                let f = try enc.encode(pb)
                XCTAssertEqual(f.width, 640); XCTAssertEqual(f.height, 360)
                let d = try XCTUnwrap(Self.decode(f.data), "\(name) \(w)×\(h)")
                XCTAssertEqual(d.width, 640); XCTAssertEqual(d.height, 360)
                let err = Self.worstQuadrantError(d)
                print(String(format: "W2-E1 Mac %@ %d×%d → 640×360: %d B, error de color máx. %d (tolerancia %d)",
                             name, w, h, f.data.count, err, Self.colorTolerance))
                XCTAssertLessThanOrEqual(err, Self.colorTolerance, "\(name) \(w)×\(h)")
            }
        }
    }

    func testMacRejectsOtherFormats() throws {
        let pb = try Self.pixelBuffer(kCVPixelFormatType_422YpCbCr8, width: 64, height: 64)
        XCTAssertThrowsError(try FrameJPEGEncoder().encode(pb)) { XCTAssertEqual($0 as? FrameJPEGError, .unsupportedFormat("2vuy")) }
    }

    // MARK: - Coste por fotograma (números del informe)

    /// Presupuesto por fotograma del relevo (decisión propia, W2-E1: la mitad de un periodo de 15 fps, 66,7 ms, para
    /// dejar sitio al base64 y al envío). Sirve de techo holgado también en Debug.
    static let budgetMs = 33.0

    static func percentile(_ v: [Double], _ p: Double) -> Double {
        let s = v.sorted()
        return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))]
    }

    func testCostPerFrame() throws {
        #if DEBUG
        let build = "Debug"
        #else
        let build = "release"
        #endif
        let runs = 30
        for (w, h) in [(1920, 1080), (1280, 720)] {
            // Escena con textura en NV12 (la cámara) y en BGRA (el compositor).
            let bgra = try Self.macBGRA(width: w, height: h, scene: true)
            let nv12 = try Self.pixelBuffer(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, width: w, height: h)
            try Self.bgraToNV12(bgra, nv12)
            let enc = FrameJPEGEncoder()
            for (name, pb) in [("NV12", nv12), ("BGRA", bgra)] {
                var ms: [Double] = [], bytes = 0
                for _ in 0..<runs {
                    let t0 = DispatchTime.now().uptimeNanoseconds
                    let f = try enc.encode(pb)
                    ms.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
                    bytes += f.data.count
                }
                print(String(format: "W2-E1 coste Mac %@ %@ %d×%d → 640×360: p50 %.2f ms, p95 %.2f ms, JPEG medio %d B",
                             build, name, w, h, Self.percentile(ms, 0.5), Self.percentile(ms, 0.95), bytes / runs))
                XCTAssertLessThan(Self.percentile(ms, 0.5), Self.budgetMs, "\(name) \(w)×\(h)")
            }
            // Núcleo portátil (el de Windows) sobre los mismos píxeles. En Debug tarda ~1 s por fotograma (Swift sin
            // optimizar): 3 vueltas solo para el número; el de release sale de un `swiftc -O` aparte (informe W2-E1).
            let portable = PortableJPEG()
            var ms: [Double] = [], bytes = 0
            let portableRuns = build == "Debug" ? 3 : runs
            CVPixelBufferLockBaseAddress(nv12, .readOnly)
            let yp = CVPixelBufferGetBaseAddressOfPlane(nv12, 0)!.assumingMemoryBound(to: UInt8.self)
            let cp = CVPixelBufferGetBaseAddressOfPlane(nv12, 1)!.assumingMemoryBound(to: UInt8.self)
            for _ in 0..<portableRuns {
                let t0 = DispatchTime.now().uptimeNanoseconds
                let d = portable.encodeNV12(y: yp, yStride: CVPixelBufferGetBytesPerRowOfPlane(nv12, 0), uv: cp,
                                            uvStride: CVPixelBufferGetBytesPerRowOfPlane(nv12, 1), width: w, height: h,
                                            outWidth: 640, outHeight: 360, quality: 70)
                ms.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
                bytes += d.count
            }
            CVPixelBufferUnlockBaseAddress(nv12, .readOnly)
            print(String(format: "W2-E1 coste portátil %@ NV12 %d×%d → 640×360: p50 %.2f ms, p95 %.2f ms, JPEG medio %d B",
                         build, w, h, Self.percentile(ms, 0.5), Self.percentile(ms, 0.95), bytes / portableRuns))
        }
    }

    /// BGRA → 420v con vImage (para el banco de NV12 con la misma escena).
    static func bgraToNV12(_ src: CVPixelBuffer, _ dst: CVPixelBuffer) throws {
        // Conversión directa en BT.709 limitado con la cuenta de la prueba (sin prisa: solo prepara datos).
        CVPixelBufferLockBaseAddress(src, .readOnly); CVPixelBufferLockBaseAddress(dst, [])
        defer { CVPixelBufferUnlockBaseAddress(src, .readOnly); CVPixelBufferUnlockBaseAddress(dst, []) }
        let w = CVPixelBufferGetWidth(src), h = CVPixelBufferGetHeight(src)
        let s = CVPixelBufferGetBaseAddress(src)!.assumingMemoryBound(to: UInt8.self), ss = CVPixelBufferGetBytesPerRow(src)
        let yp = CVPixelBufferGetBaseAddressOfPlane(dst, 0)!.assumingMemoryBound(to: UInt8.self)
        let cp = CVPixelBufferGetBaseAddressOfPlane(dst, 1)!.assumingMemoryBound(to: UInt8.self)
        let ys = CVPixelBufferGetBytesPerRowOfPlane(dst, 0), cs = CVPixelBufferGetBytesPerRowOfPlane(dst, 1)
        for r in 0..<h {
            for x in 0..<w {
                let o = r * ss + 4 * x
                let c = ycbcr709((Int(s[o + 2]), Int(s[o + 1]), Int(s[o])))
                yp[r * ys + x] = c.0
                if r & 1 == 0 && x & 1 == 0 { cp[(r / 2) * cs + x] = c.1; cp[(r / 2) * cs + x + 1] = c.2 }
            }
        }
    }
    #endif
}
