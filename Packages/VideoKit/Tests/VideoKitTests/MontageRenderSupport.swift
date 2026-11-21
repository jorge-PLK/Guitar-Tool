#if canImport(CoreVideo)
import CoreVideo
#endif
import Foundation
import XCTest
@testable import VideoKit

/// Búferes BGRA y PNG iguales en el Mac (`CVPixelBuffer`) y en Windows (`FramePixelBuffer` propio), para los tests del
/// compositor por `MontageFrameRendering` (plan, «Fase 7c», paso 7, parte 7.9).
enum RenderSupport {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Búfer BGRA con el color de `f(x, y)` (origen arriba a la izquierda), alfa 255.
    static func buffer(width: Int, height: Int, _ f: (Int, Int) -> (r: UInt8, g: UInt8, b: UInt8)) -> FramePixelBuffer {
        let pb = empty(width: width, height: height)
        withBase(pb) { base, row in
            for y in 0..<height {
                for x in 0..<width {
                    let c = f(x, y), o = y * row + x * 4
                    base[o] = c.b; base[o + 1] = c.g; base[o + 2] = c.r; base[o + 3] = 255
                }
            }
        }
        return pb
    }

    static func empty(width: Int, height: Int) -> FramePixelBuffer {
        #if canImport(CoreVideo)
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
        return pb!
        #else
        return FramePixelBuffer(pixelFormat: .bgra, width: width, height: height)
        #endif
    }

    static func size(_ pb: FramePixelBuffer) -> (w: Int, h: Int) {
        #if canImport(CoreVideo)
        return (CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb))
        #else
        return (pb.width, pb.height)
        #endif
    }

    static func withBase<R>(_ pb: FramePixelBuffer, _ body: (UnsafeMutablePointer<UInt8>, Int) -> R) -> R {
        #if canImport(CoreVideo)
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        return body(CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self), CVPixelBufferGetBytesPerRow(pb))
        #else
        return body(pb.baseAddress.assumingMemoryBound(to: UInt8.self), pb.bytesPerRow)
        #endif
    }

    /// Píxeles RGBA de arriba abajo.
    static func rgba(_ pb: FramePixelBuffer) -> [UInt8] {
        let (w, h) = size(pb)
        return withBase(pb) { base, row in
            var out = [UInt8](repeating: 255, count: w * h * 4)
            for y in 0..<h {
                for x in 0..<w {
                    let s = y * row + x * 4, d = (y * w + x) * 4
                    out[d] = base[s + 2]; out[d + 1] = base[s + 1]; out[d + 2] = base[s]
                }
            }
            return out
        }
    }

    // MARK: PNG (RGB de 8 bits, sin compresión: deflate con bloques guardados, filtro 0)

    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func png(rgba: [UInt8], width w: Int, height h: Int) -> Data {
        func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)] }
        func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
            let t = Array(type.utf8)
            var c: UInt32 = 0xFFFF_FFFF
            for b in t + body { c = crcTable[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
            return be32(UInt32(body.count)) + t + body + be32(c ^ 0xFFFF_FFFF)
        }
        var raw = [UInt8]()
        raw.reserveCapacity(h * (1 + w * 3))
        for y in 0..<h {
            raw.append(0)
            for x in 0..<w { let o = (y * w + x) * 4; raw.append(rgba[o]); raw.append(rgba[o + 1]); raw.append(rgba[o + 2]) }
        }
        var z: [UInt8] = [0x78, 0x01]
        var i = 0
        while i < raw.count || raw.isEmpty {
            let n = min(65_535, raw.count - i)
            let final: UInt8 = i + n >= raw.count ? 1 : 0
            z += [final, UInt8(n & 0xff), UInt8(n >> 8), UInt8(~n & 0xff), UInt8((~n >> 8) & 0xff)]
            z += raw[i..<(i + n)]
            i += n
            if raw.isEmpty { break }
        }
        var a: UInt32 = 1, b: UInt32 = 0
        for v in raw { a = (a + UInt32(v)) % 65_521; b = (b + a) % 65_521 }
        z += be32(b << 16 | a)
        let header = be32(UInt32(w)) + be32(UInt32(h)) + [8, 2, 0, 0, 0]
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", header) + chunk("IDAT", z) + chunk("IEND", []))
    }

    /// PNG en `Temp/win/listen/<name>` (para el juicio visual de Jorge).
    @discardableResult
    static func writePNG(_ pb: FramePixelBuffer, _ name: String) throws -> URL {
        let dir = repo.appendingPathComponent("Temp/win/listen")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        let (w, h) = size(pb)
        try png(rgba: rgba(pb), width: w, height: h).write(to: url)
        return url
    }

    /// Dibuja `state` con el compositor de este sistema en un búfer de `size`.
    static func render(_ renderer: any MontageFrameRendering, _ tl: MontageTimeline, at t: Double, width: Int, height: Int,
                       caption: MontageCaption? = nil, sources: [FramePixelBuffer]) throws -> (pb: FramePixelBuffer, state: MontageFrameState) {
        let out = empty(width: width, height: height)
        let st = tl.state(at: t)
        try renderer.render(st, timeline: tl, caption: caption, into: out) { $0 < sources.count ? sources[$0] : nil }
        return (out, st)
    }
}
