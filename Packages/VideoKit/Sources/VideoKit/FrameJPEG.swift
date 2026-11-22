#if canImport(CoreVideo)
import Accelerate
import CoreGraphics
import CoreVideo
import ImageIO
#endif
import Foundation

/// Un fotograma en JPEG, ya reducido (paso 8, W2-E1: los fotogramas llegan a la página como JPEG en base64 por el
/// canal de mensajes; Jorge, 21/11/2026).
public struct JPEGFrame: Sendable, Equatable {
    public let data: Data
    public let width: Int
    public let height: Int

    public init(data: Data, width: Int, height: Int) {
        self.data = data
        self.width = width
        self.height = height
    }
}

public enum FrameJPEGError: Error, Equatable, Sendable {
    /// Formato de píxel que el codificador no lee (FOURCC o nombre).
    case unsupportedFormat(String)
    case encodeFailed(String)
}

/// De un fotograma BGRA o NV12 (`FramePixelBuffer`) a JPEG reducido a `maxWidth` como mucho (W2-E1).
///
/// - Mac: escala con vImage (antes de pasar a RGB si es 4:2:0) y codifica con ImageIO.
/// - Windows: reducción por promedio de área y JPEG base 4:2:0 en Swift (`PortableJPEG`), sin WIC ni cambios en el
///   shim; es el mismo código en el Mac y se prueba allí (`FrameJPEGTests`).
/// - Tamaño de salida: `outputSize` (par, sin ampliar). No ampliamos: un fotograma más estrecho sale a su tamaño.
///
/// Guarda búferes de trabajo entre llamadas: **una instancia por hilo** (el relevo usa una cola serie).
public final class FrameJPEGEncoder: @unchecked Sendable {
    /// Calidad por omisión (decisión propia, W2-E1: vista previa; ~25-45 kB a 640×360).
    public static let defaultQuality = 0.7
    /// Ancho máximo por omisión (encargo W2-E1: 640 px para la cámara).
    public static let defaultMaxWidth = 640

    public let maxWidth: Int
    /// Calidad en [0, 1] (1 = tablas de cuantización a 1).
    public let quality: Double

    #if canImport(CoreVideo)
    private var bgra: UnsafeMutableRawPointer?
    private var bgraBytes = 0
    private var luma: UnsafeMutableRawPointer?
    private var lumaBytes = 0
    private var chroma: UnsafeMutableRawPointer?
    private var chromaBytes = 0
    private var conversions: [Bool: vImage_YpCbCrToARGB] = [:]
    #else
    private let portable = PortableJPEG()
    #endif

    public init(maxWidth: Int = defaultMaxWidth, quality: Double = defaultQuality) {
        precondition(maxWidth >= 2, "FrameJPEGEncoder: maxWidth < 2")
        self.maxWidth = maxWidth
        self.quality = min(1, max(0, quality))
    }

    deinit {
        #if canImport(CoreVideo)
        bgra?.deallocate()
        luma?.deallocate()
        chroma?.deallocate()
        #endif
    }

    /// Tamaño de salida: ancho `min(width, maxWidth)`, alto en proporción redondeado, los dos pares (4:2:0) y ≥ 2.
    public static func outputSize(width: Int, height: Int, maxWidth: Int) -> (width: Int, height: Int) {
        let w = max(2, min(width, maxWidth) & ~1)
        let h = max(2, Int((Double(height) * Double(w) / Double(width)).rounded()) & ~1)
        return (w, h)
    }

    /// Calidad 1…100 de las tablas de libjpeg.
    static func percent(_ quality: Double) -> Int { max(1, min(100, Int((quality * 100).rounded()))) }

    #if canImport(CoreVideo)
    public func encode(_ frame: FramePixelBuffer) throws -> JPEGFrame {
        let format = CVPixelBufferGetPixelFormatType(frame)
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
        let w = CVPixelBufferGetWidth(frame), h = CVPixelBufferGetHeight(frame)
        let (ow, oh) = Self.outputSize(width: w, height: h, maxWidth: maxWidth)
        let rowBytes = ow * 4
        var dst = vImage_Buffer(data: Self.grow(&bgra, &bgraBytes, rowBytes * oh), height: vImagePixelCount(oh),
                                width: vImagePixelCount(ow), rowBytes: rowBytes)
        switch format {
        case kCVPixelFormatType_32BGRA:
            guard let base = CVPixelBufferGetBaseAddress(frame) else { throw FrameJPEGError.encodeFailed("sin memoria") }
            var src = vImage_Buffer(data: base, height: vImagePixelCount(h), width: vImagePixelCount(w),
                                    rowBytes: CVPixelBufferGetBytesPerRow(frame))
            try Self.check(vImageScale_ARGB8888(&src, &dst, nil, vImage_Flags(kvImageNoFlags)), "escala BGRA")
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            guard let yBase = CVPixelBufferGetBaseAddressOfPlane(frame, 0),
                  let cBase = CVPixelBufferGetBaseAddressOfPlane(frame, 1) else { throw FrameJPEGError.encodeFailed("sin planos") }
            var ySrc = vImage_Buffer(data: yBase, height: vImagePixelCount(h), width: vImagePixelCount(w),
                                     rowBytes: CVPixelBufferGetBytesPerRowOfPlane(frame, 0))
            var cSrc = vImage_Buffer(data: cBase, height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(frame, 1)),
                                     width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(frame, 1)),
                                     rowBytes: CVPixelBufferGetBytesPerRowOfPlane(frame, 1))
            // Se escala en 4:2:0 y se pasa a RGB ya pequeño: la conversión toca 9 veces menos píxeles en 1080p.
            var yDst = ySrc, cDst = cSrc
            if ow != w || oh != h {
                yDst = vImage_Buffer(data: Self.grow(&luma, &lumaBytes, ow * oh), height: vImagePixelCount(oh),
                                     width: vImagePixelCount(ow), rowBytes: ow)
                cDst = vImage_Buffer(data: Self.grow(&chroma, &chromaBytes, ow * (oh / 2)), height: vImagePixelCount(oh / 2),
                                     width: vImagePixelCount(ow / 2), rowBytes: ow)
                try Self.check(vImageScale_Planar8(&ySrc, &yDst, nil, vImage_Flags(kvImageNoFlags)), "escala Y")
                try Self.check(vImageScale_CbCr8(&cSrc, &cDst, nil, vImage_Flags(kvImageNoFlags)), "escala CbCr")
            }
            var info = try conversion(fullRange: format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            let permute: [UInt8] = [3, 2, 1, 0]   // ARGB → BGRA en memoria
            try Self.check(vImageConvert_420Yp8_CbCr8ToARGB8888(&yDst, &cDst, &dst, &info, permute, 255,
                                                                vImage_Flags(kvImageNoFlags)), "420 → BGRA")
        default:
            throw FrameJPEGError.unsupportedFormat(Self.fourCC(format))
        }
        return JPEGFrame(data: try Self.imageIO(dst, quality: quality), width: ow, height: oh)
    }

    private func conversion(fullRange: Bool) throws -> vImage_YpCbCrToARGB {
        if let c = conversions[fullRange] { return c }
        // BT.709 (la cámara del Mac y el vídeo de las tomas); rango limitado 16-235/16-240 o completo.
        var range = fullRange
            ? vImage_YpCbCrPixelRange(Yp_bias: 0, CbCr_bias: 128, YpRangeMax: 255, CbCrRangeMax: 255, YpMax: 255, YpMin: 0, CbCrMax: 255, CbCrMin: 0)
            : vImage_YpCbCrPixelRange(Yp_bias: 16, CbCr_bias: 128, YpRangeMax: 235, CbCrRangeMax: 240, YpMax: 235, YpMin: 16, CbCrMax: 240, CbCrMin: 16)
        var info = vImage_YpCbCrToARGB()
        // La de `kvImage_YpCbCrToARGBMatrix_ITU_R_709_2` (variable global que Swift 6 no deja leer sin aislamiento).
        var matrix = vImage_YpCbCrToARGBMatrix(Yp: 1, Cr_R: 1.5748, Cr_G: -0.468124, Cb_G: -0.187324, Cb_B: 1.8556)
        try Self.check(vImageConvert_YpCbCrToARGB_GenerateConversion(&matrix, &range, &info,
                                                                     kvImage420Yp8_CbCr8, kvImageARGB8888,
                                                                     vImage_Flags(kvImageNoFlags)), "matriz 709")
        conversions[fullRange] = info
        return info
    }

    private static func imageIO(_ buf: vImage_Buffer, quality: Double) throws -> Data {
        guard let provider = CGDataProvider(dataInfo: nil, data: buf.data, size: buf.rowBytes * Int(buf.height),
                                            releaseData: { _, _, _ in }),
              let image = CGImage(width: Int(buf.width), height: Int(buf.height), bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: buf.rowBytes, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                                                           | CGImageAlphaInfo.noneSkipFirst.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw FrameJPEGError.encodeFailed("CGImage")
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else {
            throw FrameJPEGError.encodeFailed("CGImageDestination")
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw FrameJPEGError.encodeFailed("ImageIO") }
        return out as Data
    }

    private static func grow(_ p: inout UnsafeMutableRawPointer?, _ bytes: inout Int, _ need: Int) -> UnsafeMutableRawPointer {
        if let q = p, bytes >= need { return q }
        p?.deallocate()
        let q = UnsafeMutableRawPointer.allocate(byteCount: need, alignment: 64)
        p = q
        bytes = need
        return q
    }

    private static func check(_ e: vImage_Error, _ what: String) throws {
        if e != kvImageNoError { throw FrameJPEGError.encodeFailed("vImage \(what): \(e)") }
    }

    static func fourCC(_ v: OSType) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((v >> $0) & 0xff) }, encoding: .ascii) ?? "\(v)"
    }
    #else
    public func encode(_ frame: FramePixelBuffer) throws -> JPEGFrame {
        let (ow, oh) = Self.outputSize(width: frame.width, height: frame.height, maxWidth: maxWidth)
        let q = Self.percent(quality)
        let base = UnsafePointer(frame.baseAddress.assumingMemoryBound(to: UInt8.self))
        let data: Data
        switch frame.pixelFormat {
        case .nv12:
            let uv = UnsafePointer(frame.planeBaseAddress(1).assumingMemoryBound(to: UInt8.self))
            data = portable.encodeNV12(y: base, yStride: frame.bytesPerRow, uv: uv, uvStride: frame.bytesPerRow,
                                       width: frame.width, height: frame.height, outWidth: ow, outHeight: oh, quality: q)
        case .bgra:
            data = portable.encodeBGRA(base, stride: frame.bytesPerRow, width: frame.width, height: frame.height,
                                       outWidth: ow, outHeight: oh, quality: q)
        }
        return JPEGFrame(data: data, width: ow, height: oh)
    }
    #endif
}

// MARK: - JPEG portátil

/// JPEG base (ITU T.81, secuencial, Huffman de las tablas del anexo K), 4:2:0, JFIF (YCbCr BT.601 de rango completo).
/// Reducción por promedio de área y conversión de color en coma fija; DCT flotante AAN (la de `jfdctflt.c`).
///
/// - NV12 de entrada: BT.709 de rango limitado (la de `FramePixelBuffer`); se pasa a BT.601 completo con una matriz
///   3×3 sobre (Y, Cb, Cr) para que un decodificador JFIF dé los mismos RGB.
/// - Búferes de trabajo reutilizados: una instancia por hilo.
final class PortableJPEG {
    private var scratch: [Int: (UnsafeMutableRawPointer, Int)] = [:]
    private var tablesQuality = -1
    private let qLuma = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)    // orden natural
    private let qChroma = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private let fdLuma = UnsafeMutablePointer<Float>.allocate(capacity: 64)   // 1 / (q · escala AAN · 8)
    private let fdChroma = UnsafeMutablePointer<Float>.allocate(capacity: 64)

    deinit {
        for (p, _) in scratch.values { p.deallocate() }
        qLuma.deallocate(); qChroma.deallocate(); fdLuma.deallocate(); fdChroma.deallocate()
    }

    private enum Slot: Int { case y, cb, cr, tmpA, tmpB, sums, bounds, recip, out }

    private func buffer(_ slot: Slot, _ bytes: Int) -> UnsafeMutableRawPointer {
        if let (p, n) = scratch[slot.rawValue], n >= bytes { return p }
        scratch[slot.rawValue]?.0.deallocate()
        let p = UnsafeMutableRawPointer.allocate(byteCount: max(bytes, 64), alignment: 64)
        scratch[slot.rawValue] = (p, max(bytes, 64))
        return p
    }

    // MARK: Entradas

    func encodeNV12(y: UnsafePointer<UInt8>, yStride: Int, uv: UnsafePointer<UInt8>, uvStride: Int, width: Int, height: Int,
                    outWidth ow: Int, outHeight oh: Int, quality: Int) -> Data {
        let cw = (ow + 1) / 2, ch = (oh + 1) / 2
        let ys = buffer(.tmpA, ow * oh).assumingMemoryBound(to: UInt8.self)
        let cs = buffer(.tmpB, cw * 2 * ch).assumingMemoryBound(to: UInt8.self)
        boxScale(src: y, srcStride: yStride, srcW: width, srcH: height, channels: 1, dst: ys, dstStride: ow, dstW: ow, dstH: oh)
        boxScale(src: uv, srcStride: uvStride, srcW: (width + 1) / 2, srcH: (height + 1) / 2, channels: 2,
                 dst: cs, dstStride: cw * 2, dstW: cw, dstH: ch)
        let yp = buffer(.y, ow * oh).assumingMemoryBound(to: UInt8.self)
        let cbp = buffer(.cb, cw * ch).assumingMemoryBound(to: UInt8.self)
        let crp = buffer(.cr, cw * ch).assumingMemoryBound(to: UInt8.self)
        let m = ColorLUT.shared
        m.y.withUnsafeBufferPointer { ly in
        m.yCb.withUnsafeBufferPointer { lyb in
        m.yCr.withUnsafeBufferPointer { lyr in
            for r in 0..<oh {
                let src = ys + r * ow, dst = yp + r * ow, c = cs + (r >> 1) * cw * 2
                for x in 0..<ow {
                    let k = (x >> 1) << 1
                    dst[x] = clamp8((ly[Int(src[x])] + lyb[Int(c[k])] + lyr[Int(c[k + 1])] + 32768) >> 16)
                }
            }
        }}}
        m.cbCb.withUnsafeBufferPointer { a in
        m.cbCr.withUnsafeBufferPointer { b in
        m.crCb.withUnsafeBufferPointer { c in
        m.crCr.withUnsafeBufferPointer { d in
            for i in 0..<(cw * ch) {
                let u = Int(cs[2 * i]), v = Int(cs[2 * i + 1])
                cbp[i] = clamp8(128 + ((a[u] + b[v] + 32768) >> 16))
                crp[i] = clamp8(128 + ((c[u] + d[v] + 32768) >> 16))
            }
        }}}}
        return encodePlanes(y: yp, cb: cbp, cr: crp, width: ow, height: oh, quality: quality)
    }

    func encodeBGRA(_ src: UnsafePointer<UInt8>, stride: Int, width: Int, height: Int, outWidth ow: Int, outHeight oh: Int,
                    quality: Int) -> Data {
        var px = src, pxStride = stride
        if ow != width || oh != height {
            let t = buffer(.tmpA, ow * 4 * oh).assumingMemoryBound(to: UInt8.self)
            boxScale(src: src, srcStride: stride, srcW: width, srcH: height, channels: 4, dst: t, dstStride: ow * 4, dstW: ow, dstH: oh)
            px = UnsafePointer(t)
            pxStride = ow * 4
        }
        let cw = (ow + 1) / 2, ch = (oh + 1) / 2
        let yp = buffer(.y, ow * oh).assumingMemoryBound(to: UInt8.self)
        let cbp = buffer(.cb, cw * ch).assumingMemoryBound(to: UInt8.self)
        let crp = buffer(.cr, cw * ch).assumingMemoryBound(to: UInt8.self)
        // JFIF: BT.601 de rango completo, coma fija de 16 bits.
        for r in 0..<oh {
            let s = px + r * pxStride, d = yp + r * ow
            for x in 0..<ow {
                let b = Int(s[4 * x]), g = Int(s[4 * x + 1]), rr = Int(s[4 * x + 2])
                d[x] = clamp8((19595 * rr + 38470 * g + 7471 * b + 32768) >> 16)
            }
        }
        for cy in 0..<ch {
            let r0 = px + (2 * cy) * pxStride, r1 = px + min(2 * cy + 1, oh - 1) * pxStride
            for cx in 0..<cw {
                let x0 = 8 * cx, x1 = 4 * min(2 * cx + 1, ow - 1)
                let b = Int(r0[x0]) + Int(r0[x1]) + Int(r1[x0]) + Int(r1[x1])
                let g = Int(r0[x0 + 1]) + Int(r0[x1 + 1]) + Int(r1[x0 + 1]) + Int(r1[x1 + 1])
                let rr = Int(r0[x0 + 2]) + Int(r0[x1 + 2]) + Int(r1[x0 + 2]) + Int(r1[x1 + 2])
                // Suma de 4 → división por 4 dentro del desplazamiento (>> 18).
                cbp[cy * cw + cx] = clamp8(128 + ((-11059 * rr - 21709 * g + 32768 * b + 131_072) >> 18))
                crp[cy * cw + cx] = clamp8(128 + ((32768 * rr - 27439 * g - 5329 * b + 131_072) >> 18))
            }
        }
        return encodePlanes(y: yp, cb: cbp, cr: crp, width: ow, height: oh, quality: quality)
    }

    // MARK: Reducción

    /// Promedio por área de `channels` canales entrelazados (sin ampliar: `dstW ≤ srcW`, `dstH ≤ srcH`). Cada píxel de
    /// salida promedia el rectángulo de origen `[x·sw/dw, (x+1)·sw/dw)`; divide con recíprocos en coma fija de 20 bits.
    func boxScale(src: UnsafePointer<UInt8>, srcStride: Int, srcW: Int, srcH: Int, channels ch: Int,
                  dst: UnsafeMutablePointer<UInt8>, dstStride: Int, dstW: Int, dstH: Int) {
        precondition(dstW <= srcW && dstH <= srcH && dstW > 0 && dstH > 0, "boxScale: no amplía")
        if dstW == srcW && dstH == srcH {
            for r in 0..<dstH { (dst + r * dstStride).update(from: src + r * srcStride, count: dstW * ch) }
            return
        }
        let xb = buffer(.bounds, (dstW + 1) * MemoryLayout<Int>.stride).assumingMemoryBound(to: Int.self)
        for i in 0...dstW { xb[i] = i * srcW / dstW }
        let maxCount = ((srcW + dstW - 1) / dstW + 1) * ((srcH + dstH - 1) / dstH + 1)
        let recip = buffer(.recip, (maxCount + 1) * MemoryLayout<Int>.stride).assumingMemoryBound(to: Int.self)
        recip[0] = 0
        for n in 1...maxCount { recip[n] = ((1 << 20) + n / 2) / n }
        let sums = buffer(.sums, dstW * ch * MemoryLayout<UInt32>.stride).assumingMemoryBound(to: UInt32.self)
        for oy in 0..<dstH {
            let y0 = oy * srcH / dstH, y1 = (oy + 1) * srcH / dstH
            sums.initialize(repeating: 0, count: dstW * ch)
            for sy in y0..<y1 {
                let row = src + sy * srcStride
                for ox in 0..<dstW {
                    let s = sums + ox * ch
                    for sx in xb[ox]..<xb[ox + 1] {
                        let p = row + sx * ch
                        for c in 0..<ch { s[c] &+= UInt32(p[c]) }
                    }
                }
            }
            let rows = y1 - y0, out = dst + oy * dstStride
            for ox in 0..<dstW {
                let r = recip[(xb[ox + 1] - xb[ox]) * rows]
                for c in 0..<ch {
                    out[ox * ch + c] = UInt8(truncatingIfNeeded: (Int(sums[ox * ch + c]) * r + (1 << 19)) >> 20)
                }
            }
        }
    }

    // MARK: JPEG

    private func makeTables(quality: Int) {
        guard quality != tablesQuality else { return }
        tablesQuality = quality
        let scale = quality < 50 ? 5000 / quality : 200 - 2 * quality
        for i in 0..<64 {
            qLuma[i] = UInt8(max(1, min(255, (Int(JPEGTables.lumaQ[i]) * scale + 50) / 100)))
            qChroma[i] = UInt8(max(1, min(255, (Int(JPEGTables.chromaQ[i]) * scale + 50) / 100)))
            let aan = JPEGTables.aan[i >> 3] * JPEGTables.aan[i & 7] * 8
            fdLuma[i] = Float(1 / (Double(qLuma[i]) * aan))
            fdChroma[i] = Float(1 / (Double(qChroma[i]) * aan))
        }
    }

    func encodePlanes(y: UnsafePointer<UInt8>, cb: UnsafePointer<UInt8>, cr: UnsafePointer<UInt8>, width w: Int, height h: Int,
                      quality: Int) -> Data {
        makeTables(quality: quality)
        let cw = (w + 1) / 2, chh = (h + 1) / 2
        var header = [UInt8]()
        header.reserveCapacity(640)
        header += [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00]
        header += [0xFF, 0xDB, 0x00, 0x84, 0x00]
        for k in 0..<64 { header.append(qLuma[Int(JPEGTables.zigzag[k])]) }
        header.append(0x01)
        for k in 0..<64 { header.append(qChroma[Int(JPEGTables.zigzag[k])]) }
        header += [0xFF, 0xC0, 0x00, 0x11, 0x08, UInt8(h >> 8), UInt8(h & 0xFF), UInt8(w >> 8), UInt8(w & 0xFF),
                   0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01]
        header += [0xFF, 0xC4, 0x01, 0xA2]
        for (cls, t) in [(0x00, HuffTable.dcLuma), (0x10, HuffTable.acLuma), (0x01, HuffTable.dcChroma), (0x11, HuffTable.acChroma)] {
            header.append(UInt8(cls))
            header += t.bits
            header += t.values
        }
        header += [0xFF, 0xDA, 0x00, 0x0C, 0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3F, 0x00]

        // Margen por MCU: 6 bloques × 64 × 27 bits, duplicado por los 0xFF00 → < 24 kB.
        let mcuMargin = 24 * 1024
        var cap = max(64 * 1024, w * h / 2 + header.count + mcuMargin)
        var bw = BitWriter(buf: buffer(.out, cap).assumingMemoryBound(to: UInt8.self))
        header.withUnsafeBufferPointer { bw.buf.update(from: $0.baseAddress!, count: $0.count) }
        bw.len = header.count

        let blk = UnsafeMutablePointer<Float>.allocate(capacity: 64)
        let q = UnsafeMutablePointer<Int32>.allocate(capacity: 64)
        defer { blk.deallocate(); q.deallocate() }
        var dcY: Int32 = 0, dcCb: Int32 = 0, dcCr: Int32 = 0
        let dcL = HuffTable.dcLuma, acL = HuffTable.acLuma, dcC = HuffTable.dcChroma, acC = HuffTable.acChroma
        for my in stride(from: 0, to: h, by: 16) {
            for mx in stride(from: 0, to: w, by: 16) {
                if bw.len + mcuMargin > cap {
                    cap *= 2
                    let bigger = UnsafeMutableRawPointer.allocate(byteCount: cap, alignment: 64)
                    bigger.copyMemory(from: bw.buf, byteCount: bw.len)
                    scratch[Slot.out.rawValue]?.0.deallocate()
                    scratch[Slot.out.rawValue] = (bigger, cap)
                    bw.buf = bigger.assumingMemoryBound(to: UInt8.self)
                }
                for (dx, dy) in [(0, 0), (8, 0), (0, 8), (8, 8)] {
                    Self.load(y, stride: w, w: w, h: h, x: mx + dx, y: my + dy, into: blk)
                    Self.fdct(blk)
                    Self.quantize(blk, fdLuma, into: q)
                    bw.block(q, dc: &dcY, dcL, acL)
                }
                Self.load(cb, stride: cw, w: cw, h: chh, x: mx / 2, y: my / 2, into: blk)
                Self.fdct(blk)
                Self.quantize(blk, fdChroma, into: q)
                bw.block(q, dc: &dcCb, dcC, acC)
                Self.load(cr, stride: cw, w: cw, h: chh, x: mx / 2, y: my / 2, into: blk)
                Self.fdct(blk)
                Self.quantize(blk, fdChroma, into: q)
                bw.block(q, dc: &dcCr, dcC, acC)
            }
        }
        bw.flush()
        bw.byte(0xFF); bw.byte(0xD9)
        return Data(bytes: bw.buf, count: bw.len)
    }

    /// Bloque 8×8 desplazado −128; fuera de la imagen repite el borde.
    @inline(__always)
    static func load(_ p: UnsafePointer<UInt8>, stride: Int, w: Int, h: Int, x: Int, y: Int, into b: UnsafeMutablePointer<Float>) {
        if x + 8 <= w && y + 8 <= h {
            for r in 0..<8 {
                let row = p + (y + r) * stride + x
                for c in 0..<8 { b[r * 8 + c] = Float(row[c]) - 128 }
            }
        } else {
            for r in 0..<8 {
                let row = p + min(y + r, h - 1) * stride
                for c in 0..<8 { b[r * 8 + c] = Float(row[min(x + c, w - 1)]) - 128 }
            }
        }
    }

    @inline(__always)
    static func quantize(_ b: UnsafeMutablePointer<Float>, _ fd: UnsafeMutablePointer<Float>, into q: UnsafeMutablePointer<Int32>) {
        JPEGTables.zigzag.withUnsafeBufferPointer { zz in
            for k in 0..<64 {
                let n = Int(zz[k])
                let v = (b[n] * fd[n]).rounded()
                // Base: AC con 10 bits como mucho, DC con 11.
                q[k] = Int32(max(-2047, min(2047, v)))
                if k > 0 { q[k] = max(-1023, min(1023, q[k])) }
            }
        }
    }

    /// DCT directa flotante AAN (Arai, Agui, Nakajima; `jfdctflt.c` de libjpeg), filas y columnas, sin escalar.
    @inline(__always)
    static func fdct(_ d: UnsafeMutablePointer<Float>) {
        for pass in 0..<2 {
            let step = pass == 0 ? 1 : 8, next = pass == 0 ? 8 : 1
            for i in 0..<8 {
                let p = d + i * next
                let t0 = p[0] + p[7 * step], t7 = p[0] - p[7 * step]
                let t1 = p[step] + p[6 * step], t6 = p[step] - p[6 * step]
                let t2 = p[2 * step] + p[5 * step], t5 = p[2 * step] - p[5 * step]
                let t3 = p[3 * step] + p[4 * step], t4 = p[3 * step] - p[4 * step]
                var t10 = t0 + t3, t13 = t0 - t3, t11 = t1 + t2, t12 = t1 - t2
                p[0] = t10 + t11
                p[4 * step] = t10 - t11
                let z1 = (t12 + t13) * 0.707106781
                p[2 * step] = t13 + z1
                p[6 * step] = t13 - z1
                t10 = t4 + t5; t11 = t5 + t6; t12 = t6 + t7
                let z5 = (t10 - t12) * 0.382683433
                let z2 = 0.541196100 * t10 + z5
                let z4 = 1.306562965 * t12 + z5
                let z3 = t11 * 0.707106781
                let z11 = t7 + z3, z13 = t7 - z3
                p[5 * step] = z13 + z2
                p[3 * step] = z13 - z2
                p[step] = z11 + z4
                p[7 * step] = z11 - z4
            }
        }
    }
}

@inline(__always)
private func clamp8(_ v: Int) -> UInt8 { UInt8(truncatingIfNeeded: max(0, min(255, v))) }

/// Escritor de bits del segmento entrópico (relleno 0xFF → 0xFF 0x00).
private struct BitWriter {
    var buf: UnsafeMutablePointer<UInt8>
    var len = 0
    var acc: UInt64 = 0
    var n = 0

    init(buf: UnsafeMutablePointer<UInt8>) { self.buf = buf }

    @inline(__always)
    mutating func byte(_ b: UInt8) { buf[len] = b; len += 1 }

    @inline(__always)
    mutating func put(_ code: UInt32, _ size: Int) {
        acc = (acc << UInt64(size)) | UInt64(code)
        n += size
        while n >= 8 {
            n -= 8
            let b = UInt8(truncatingIfNeeded: acc >> UInt64(n))
            buf[len] = b; len += 1
            if b == 0xFF { buf[len] = 0; len += 1 }
        }
    }

    /// Relleno final con unos.
    mutating func flush() {
        if n > 0 { put((1 << UInt32(8 - n)) - 1, 8 - n) }
    }

    @inline(__always)
    mutating func block(_ q: UnsafeMutablePointer<Int32>, dc: inout Int32, _ dcT: HuffTable, _ acT: HuffTable) {
        let diff = q[0] - dc
        dc = q[0]
        if diff == 0 {
            put(UInt32(dcT.code[0]), Int(dcT.size[0]))
        } else {
            let a = UInt32(abs(diff)), bits = 32 - a.leadingZeroBitCount
            put(UInt32(dcT.code[bits]), Int(dcT.size[bits]))
            put(UInt32(bitPattern: diff < 0 ? diff - 1 : diff) & ((1 << UInt32(bits)) - 1), bits)
        }
        var run = 0
        for k in 1..<64 {
            let c = q[k]
            if c == 0 { run += 1; continue }
            while run > 15 { put(UInt32(acT.code[0xF0]), Int(acT.size[0xF0])); run -= 16 }
            let a = UInt32(abs(c)), bits = 32 - a.leadingZeroBitCount
            let sym = (run << 4) | bits
            put(UInt32(acT.code[sym]), Int(acT.size[sym]))
            put(UInt32(bitPattern: c < 0 ? c - 1 : c) & ((1 << UInt32(bits)) - 1), bits)
            run = 0
        }
        if run > 0 { put(UInt32(acT.code[0]), Int(acT.size[0])) }
    }
}

/// Tabla de Huffman de códigos por símbolo (anexo C de T.81) a partir de las del anexo K.3.
final class HuffTable: @unchecked Sendable {
    let bits: [UInt8]
    let values: [UInt8]
    let code: UnsafeMutablePointer<UInt16>
    let size: UnsafeMutablePointer<UInt8>

    init(bits: [UInt8], values: [UInt8]) {
        self.bits = bits
        self.values = values
        code = .allocate(capacity: 256)
        code.initialize(repeating: 0, count: 256)
        size = .allocate(capacity: 256)
        size.initialize(repeating: 0, count: 256)
        var c: UInt16 = 0, k = 0
        for len in 1...16 {
            for _ in 0..<Int(bits[len - 1]) {
                code[Int(values[k])] = c
                size[Int(values[k])] = UInt8(len)
                c += 1
                k += 1
            }
            c <<= 1
        }
    }

    // Vive lo que el proceso (tablas estáticas): no se libera.

    static let dcLuma = HuffTable(bits: [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0], values: Array(0...11))
    static let dcChroma = HuffTable(bits: [0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0], values: Array(0...11))
    static let acLuma = HuffTable(bits: [0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7D], values: [
        0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
        0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08, 0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0,
        0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
        0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
        0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
        0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7,
        0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5,
        0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
        0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8,
        0xF9, 0xFA
    ])
    static let acChroma = HuffTable(bits: [0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77], values: [
        0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71,
        0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0,
        0x15, 0x62, 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34, 0xE1, 0x25, 0xF1, 0x17, 0x18, 0x19, 0x1A, 0x26,
        0x27, 0x28, 0x29, 0x2A, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
        0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
        0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
        0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5,
        0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3,
        0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA,
        0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8,
        0xF9, 0xFA
    ])
}

enum JPEGTables {
    /// Cuantización del anexo K.1 (calidad 50), orden natural.
    static let lumaQ: [UInt8] = [
        16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55,
        14, 13, 16, 24, 40, 57, 69, 56, 14, 17, 22, 29, 51, 87, 80, 62,
        18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92,
        49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99
    ]
    static let chromaQ: [UInt8] = [
        17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99,
        24, 26, 56, 99, 99, 99, 99, 99, 47, 66, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99
    ]
    /// Posición zigzag k → índice natural.
    static let zigzag: [UInt8] = [
        0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
        12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
        35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
        58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63
    ]
    /// Factores de escala de la DCT AAN: cos(k·π/16)·√2 (k > 0), 1 para k = 0.
    static let aan: [Double] = [1.0, 1.387039845, 1.306562965, 1.175875602, 1.0, 0.785694958, 0.541196100, 0.275899379]
}

/// Tablas de NV12 (BT.709, rango limitado) → JFIF (BT.601, rango completo) en coma fija de 16 bits.
///
/// RGB = M709⁻¹·(Y', Cb', Cr') con Y' = (Y−16)·255/219 y C' = (C−128)·255/224; luego (Y, Cb, Cr)₆₀₁ = M601·RGB. Como las
/// dos son lineales, Y₆₀₁ = Y' + a·Cb' + b·Cr' y C₆₀₁ = combinación de Cb', Cr' (Y' no entra en el croma).
final class ColorLUT: Sendable {
    let y: [Int], yCb: [Int], yCr: [Int]
    let cbCb: [Int], cbCr: [Int], crCb: [Int], crCr: [Int]

    static let shared = ColorLUT()

    private init() {
        // M709⁻¹ (Kr = 0,2126, Kb = 0,0722) sobre (Y', Cb', Cr') centrados.
        let rCr = 1.5748, gCb = -0.187324, gCr = -0.468124, bCb = 1.8556
        // M601 (Kr = 0,299, Kb = 0,114).
        let (yr, yg, yb) = (0.299, 0.587, 0.114)
        let (ur, ug, ub) = (-0.168736, -0.331264, 0.5)
        let (vr, vg, vb) = (0.5, -0.418688, -0.081312)
        // Coeficientes de (Cb', Cr') en cada salida (Y' entra con 1 en Y₆₀₁ y con 0 en el croma).
        let a = yg * gCb + yb * bCb, b = yr * rCr + yg * gCr
        let c = ug * gCb + ub * bCb, d = ur * rCr + ug * gCr
        let e = vg * gCb + vb * bCb, f = vr * rCr + vg * gCr
        func lut(_ k: Double, luma: Bool) -> [Int] {
            (0..<256).map { v in
                let x = luma ? (Double(v) - 16) * 255 / 219 : (Double(v) - 128) * 255 / 224
                return Int((k * x * 65536).rounded())
            }
        }
        y = lut(1, luma: true)
        yCb = lut(a, luma: false); yCr = lut(b, luma: false)
        cbCb = lut(c, luma: false); cbCr = lut(d, luma: false)
        crCb = lut(e, luma: false); crCr = lut(f, luma: false)
    }
}
