#if canImport(AVFoundation)
import CoreImage
import XCTest
@testable import VideoKit

/// `MontageRenderer` sin códec: fuentes de color liso, render en memoria y valores exactos.
final class MontageRendererTests: XCTestCase {
    /// Búfer BGRA de color liso, como los que entrega AVFoundation al compositor.
    static func buffer(r: UInt8, g: UInt8, b: UInt8) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 320, 180, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        let base = CVPixelBufferGetBaseAddress(pb!)!.assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRow(pb!)
        for y in 0..<180 { for x in 0..<320 { let o = y * row + x * 4; base[o] = b; base[o + 1] = g; base[o + 2] = r; base[o + 3] = 255 } }
        CVPixelBufferUnlockBaseAddress(pb!, [])
        return pb!
    }

    func testPixelBufferSourceKeepsValue() {
        let parts = ["A", "B"].map {
            MontageTimeline.Part(id: $0, name: "Parte \($0)", isSolo: false, presence: [MontageSpan(start: 0, end: 10)], firstImage: 0,
                                 frameSize: CGSize(width: 320, height: 180))
        }
        let pbs = [Self.buffer(r: 234, g: 0, b: 2), Self.buffer(r: 0, g: 234, b: 2)]
        for layout in [MontageLayoutKind.side, .single] {
            let tl = MontageTimeline(canvas: MontageCanvas.landscape.size, layout: layout, span: MontageSpan(start: 0, end: 10), barDuration: 1,
                                     fadeIn: false, fadeOut: false, parts: parts)
            let st = tl.state(at: 5)
            let size = CGSize(width: 640, height: 360)
            let img = MontageRenderer().render(st, timeline: tl, caption: nil, renderSize: size) { CIImage(cvPixelBuffer: pbs[$0]) }
            let out = Self.buffer(r: 0, g: 0, b: 0)
            var big: CVPixelBuffer?
            CVPixelBufferCreate(nil, 640, 360, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &big)
            _ = out
            let ctx = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!, options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
            ctx.render(img, to: big!, bounds: CGRect(origin: .zero, size: size), colorSpace: nil)
            CVPixelBufferLockBaseAddress(big!, .readOnly)
            let base = CVPixelBufferGetBaseAddress(big!)!.assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRow(big!)
            let b = st.boxes.last!.rect
            let o = Int(b.midY / 3) * row + Int(b.midX / 3) * 4
            let c = [Int(base[o + 2]), Int(base[o + 1]), Int(base[o])]
            CVPixelBufferUnlockBaseAddress(big!, .readOnly)
            print("F7 render búfer \(layout): \(c)")
            XCTAssertEqual(c, st.boxes.last!.partID == "A" ? [234, 0, 2] : [0, 234, 2], "\(layout)")
        }
    }

    static func render(_ layout: MontageLayoutKind, at t: Double, size: CGSize, fade: Bool = false) -> (px: [UInt8], w: Int, h: Int, state: MontageFrameState) {
        let parts = ["A", "B"].map {
            MontageTimeline.Part(id: $0, name: "Parte \($0)", isSolo: false, presence: [MontageSpan(start: 0, end: 10)], firstImage: 0,
                                 frameSize: CGSize(width: 320, height: 180))
        }
        let tl = MontageTimeline(canvas: MontageCanvas.landscape.size, layout: layout, span: MontageSpan(start: 0, end: 10), barDuration: 1,
                                 fadeIn: fade, fadeOut: false, parts: parts)
        let colors = [CIColor(red: 1, green: 0, blue: 0), CIColor(red: 0, green: 1, blue: 0)]
        let st = tl.state(at: t)
        let img = MontageRenderer().render(st, timeline: tl, caption: nil, renderSize: size) { i in
            CIImage(color: colors[i]).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 180))
        }
        let ctx = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        let w = Int(size.width), h = Int(size.height)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        ctx.render(img, toBitmap: &px, rowBytes: w * 4, bounds: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: nil)
        return (px, w, h, st)
    }

    /// Píxel (x, y) con origen arriba a la izquierda (`render(toBitmap:)` escribe la fila de arriba primero; hasta la
    /// rejilla de 2 apilados ningún caso distinguía arriba de abajo).
    static func pixel(_ r: (px: [UInt8], w: Int, h: Int, state: MontageFrameState), _ x: Double, _ y: Double) -> [Int] {
        let xi = Int(x), yi = Int(y)
        let o = (yi * r.w + xi) * 4
        return [Int(r.px[o]), Int(r.px[o + 1]), Int(r.px[o + 2])]
    }

    func testBoxesKeepSourceColorBackgroundAndCorners() {
        for layout in [MontageLayoutKind.side, .grid, .single] {
            let size = CGSize(width: 640, height: 360)
            let r = Self.render(layout, at: 5, size: size)
            let k = size.width / 1920
            for b in r.state.boxes {
                let c = Self.pixel(r, b.rect.midX * k, b.rect.midY * k)
                XCTAssertEqual(c, b.partID == "A" ? [255, 0, 0] : [0, 255, 0], "\(layout) centro \(b.partID)")
            }
            if layout != .single {
                // Fondo #0F1113 fuera de los recuadros y esquina redondeada (el píxel de la esquina no es de la parte).
                XCTAssertEqual(Self.pixel(r, 2, 2), [0x0F, 0x11, 0x13], "\(layout) fondo")
                let a = r.state.boxes[0].rect
                let corner = Self.pixel(r, a.minX * k + 1, a.minY * k + 1)
                XCTAssertLessThan(corner[0], 128, "\(layout) esquina \(corner)")
            }
        }
        // Fundido global al 50 %: valores a la mitad.
        let half = Self.render(.side, at: 0.5, size: CGSize(width: 640, height: 360), fade: true)
        let a = half.state.boxes[0].rect
        let c = Self.pixel(half, a.midX / 3, a.midY / 3)
        XCTAssertEqual(Double(c[0]), 127.5, accuracy: 1.5)
        print("F7 render: centro con fundido 50 % = \(c)")
    }
}
#else
import Foundation
import XCTest
@testable import VideoKit

/// Windows (parte 7.9): los mismos casos con `Direct2DMontageRenderer` en lugar de Core Image.
final class MontageRendererTests: XCTestCase {
    static func parts() -> [MontageTimeline.Part] {
        ["A", "B"].map {
            MontageTimeline.Part(id: $0, name: "Parte \($0)", isSolo: false, presence: [MontageSpan(start: 0, end: 10)], firstImage: 0,
                                 frameSize: CGSize(width: 320, height: 180))
        }
    }

    static func flat(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> FramePixelBuffer { RenderSupport.buffer(width: 320, height: 180) { _, _ in (r, g, b) } }

    static func pixel(_ pb: FramePixelBuffer, _ x: Double, _ y: Double) -> [Int] {
        let p = pb.pixel(x: Int(x), y: Int(y))
        return [Int(p.r), Int(p.g), Int(p.b)]
    }

    func testPixelBufferSourceKeepsValue() throws {
        let renderer = try Direct2DMontageRenderer()
        let pbs = [Self.flat(234, 0, 2), Self.flat(0, 234, 2)]
        for layout in [MontageLayoutKind.side, .single] {
            let tl = MontageTimeline(canvas: MontageCanvas.landscape.size, layout: layout, span: MontageSpan(start: 0, end: 10), barDuration: 1,
                                     fadeIn: false, fadeOut: false, parts: Self.parts())
            let (out, st) = try RenderSupport.render(renderer, tl, at: 5, width: 640, height: 360, sources: pbs)
            let b = st.boxes.last!.rect
            let c = Self.pixel(out, b.midX / 3, b.midY / 3)
            print("7.9 render búfer \(layout): \(c)")
            XCTAssertEqual(c, st.boxes.last!.partID == "A" ? [234, 0, 2] : [0, 234, 2], "\(layout)")
        }
    }

    func testBoxesKeepSourceColorBackgroundAndCorners() throws {
        let renderer = try Direct2DMontageRenderer()
        let sources = [Self.flat(255, 0, 0), Self.flat(0, 255, 0)]
        func render(_ layout: MontageLayoutKind, at t: Double, fade: Bool = false) throws -> (FramePixelBuffer, MontageFrameState) {
            let tl = MontageTimeline(canvas: MontageCanvas.landscape.size, layout: layout, span: MontageSpan(start: 0, end: 10), barDuration: 1,
                                     fadeIn: fade, fadeOut: false, parts: Self.parts())
            return try RenderSupport.render(renderer, tl, at: t, width: 640, height: 360, sources: sources)
        }
        for layout in [MontageLayoutKind.side, .grid, .single] {
            let (out, st) = try render(layout, at: 5)
            let k = 640.0 / 1920
            for b in st.boxes {
                XCTAssertEqual(Self.pixel(out, b.rect.midX * k, b.rect.midY * k), b.partID == "A" ? [255, 0, 0] : [0, 255, 0], "\(layout) centro \(b.partID)")
            }
            if layout != .single {
                XCTAssertEqual(Self.pixel(out, 2, 2), [0x0F, 0x11, 0x13], "\(layout) fondo")
                let a = st.boxes[0].rect
                let corner = Self.pixel(out, a.minX * k + 1, a.minY * k + 1)
                XCTAssertLessThan(corner[0], 128, "\(layout) esquina \(corner)")
            }
        }
        let (half, st) = try render(.side, at: 0.5, fade: true)
        let a = st.boxes[0].rect
        let c = Self.pixel(half, a.midX / 3, a.midY / 3)
        XCTAssertEqual(Double(c[0]), 127.5, accuracy: 1.5)
        print("7.9 render: centro con fundido 50 % = \(c)")
    }
}
#endif // canImport(AVFoundation)
