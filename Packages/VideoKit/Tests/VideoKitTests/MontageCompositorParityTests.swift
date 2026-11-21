#if canImport(CoreImage)
import CoreImage
#endif
import Foundation
import XCTest
@testable import VideoKit

/// Mismo plan y mismo instante con el compositor de cada sistema (plan, «Fase 7c», paso 7, parte 7.9): Core Image en el
/// Mac, Direct2D en Windows. Deja `Temp/win/listen/CHECK_d2d_<caso>_<mac|win>.png` (juicio visual de Jorge) y la geometría
/// de cada capa en `Temp/win/d2d/<caso>_<mac|win>.json`; la comparación de los dos (bordes a ±1 px y diferencia de imagen
/// fuera del texto) la hace un script en el Mac con los dos PNG.
final class MontageCompositorParityTests: XCTestCase {
    #if canImport(CoreImage) && canImport(AVFoundation)
    static let platform = "mac"
    #else
    static let platform = "win"
    #endif

    /// Toma sintética: degradado con cuadrícula y una barra diagonal clara, teñida por `hue` (0 rojo, 1 verde, 2 azul,
    /// 3 amarillo); marca blanca de 40 × 40 arriba a la izquierda para ver el giro.
    static func pattern(_ hue: Int, width: Int = 320, height: Int = 180) -> FramePixelBuffer {
        RenderSupport.buffer(width: width, height: height) { x, y in
            if x < 40 && y < 40 { return (255, 255, 255) }
            let gx = Double(x) / Double(width - 1), gy = Double(y) / Double(height - 1)
            let check = ((x / 20) + (y / 20)) % 2 == 0 ? 1.0 : 0.72
            let bar = abs(Double(x) - Double(y) * 1.78 - 60) < 10 ? 1.0 : 0.0
            var c = [0.25 + 0.75 * gx, 0.2 + 0.5 * gy, 0.3 + 0.4 * (1 - gx)].map { $0 * check }
            let h = hue % 3
            c = [c[(3 - h) % 3], c[(4 - h) % 3], c[(5 - h) % 3]]
            c[h] = max(c[h], 0.9 * check)
            if hue == 3 { c[1] = max(c[1], 0.9 * check) }
            c = c.map { min(1, $0 + bar * 0.6) }
            return (UInt8(c[0] * 255), UInt8(c[1] * 255), UInt8(c[2] * 255))
        }
    }

    /// Fotograma girado con el código del producto de cada sistema.
    static func rotated(_ pb: FramePixelBuffer, _ r: VideoRotation) -> FramePixelBuffer {
        #if canImport(CoreImage) && canImport(AVFoundation)
        let img = r.apply(CIImage(cvPixelBuffer: pb))
        let out = RenderSupport.empty(width: Int(img.extent.width), height: Int(img.extent.height))
        CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()]).render(img, to: out, bounds: img.extent, colorSpace: nil)
        return out
        #else
        return r.apply(pb)
        #endif
    }

    struct Case {
        let name: String
        let timeline: MontageTimeline
        let time: Double
        let caption: MontageCaption?
        let sources: [FramePixelBuffer]
    }

    static func parts(_ ids: [String], frame: CGSize = CGSize(width: 320, height: 180), presence: [String: MontageSpan] = [:]) -> [MontageTimeline.Part] {
        ids.map { id in
            MontageTimeline.Part(id: id, name: "Parte \(id)", isSolo: false, presence: [presence[id] ?? MontageSpan(start: 0, end: 10)],
                                 firstImage: 0, frameSize: frame)
        }
    }

    static func cases() -> [Case] {
        let span = MontageSpan(start: 0, end: 10)
        func tl(_ layout: MontageLayoutKind, _ parts: [MontageTimeline.Part], labels: Bool, aspect: Bool = false, caption: Bool = false) -> MontageTimeline {
            MontageTimeline(canvas: layout.defaultCanvas.size, layout: layout, span: span, barDuration: 1, fadeIn: false, fadeOut: false,
                            parts: parts, hasCaption: caption, showPartLabels: labels, keepVideoAspect: aspect)
        }
        let caption = MontageCaption(title: "Tema de prueba", artist: "ToneForge")
        let portrait = rotated(pattern(0), .clockwise90)
        return [
            // 1 toma a lienzo completo (plano único landscape), sin texto.
            Case(name: "una", timeline: tl(.singleLandscape, parts(["A"]), labels: false), time: 5, caption: nil, sources: [pattern(0)]),
            // Rejilla 2 × 2: esquinas, sombras y recortes, sin texto.
            Case(name: "rejilla", timeline: tl(.grid, parts(["A", "B", "C", "D"]), labels: false), time: 5, caption: nil,
                 sources: [pattern(0), pattern(1), pattern(2), pattern(3)]),
            // Apilado portrait con una toma girada 90° y «Mantener aspect ratio» (ajuste + relleno difuminado), sin texto.
            Case(name: "rotacion", timeline: tl(.stack, parts(["A", "B"], frame: CGSize(width: 180, height: 320)), labels: false, aspect: true),
                 time: 5, caption: nil, sources: [portrait, pattern(2)]),
            // Lado a lado con nombres de parte y rótulo.
            Case(name: "rotulo", timeline: tl(.side, parts(["A", "B"]), labels: true, caption: true), time: 1.5, caption: caption,
                 sources: [pattern(0), pattern(1)]),
            // Entrada de B a mitad (escala, opacidad y desenfoque), sin texto.
            Case(name: "entrada", timeline: tl(.side, parts(["A", "B"], presence: ["B": MontageSpan(start: 3, end: 10)]), labels: false),
                 time: 2.75, caption: nil, sources: [pattern(0), pattern(2)])
        ]
    }

    func testRenderCasesForComparison() throws {
        let renderer = try MontageFrameRenderers.make()
        let dir = RenderSupport.repo.appendingPathComponent("Temp/win/d2d")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for c in Self.cases() {
            let w = Int(c.timeline.canvas.width), h = Int(c.timeline.canvas.height)
            let s = 1.0
            let (pb, st) = try RenderSupport.render(renderer, c.timeline, at: c.time, width: w, height: h, caption: c.caption, sources: c.sources)
            try RenderSupport.writePNG(pb, "CHECK_d2d_\(c.name)_\(Self.platform).png")
            // Geometría de cada capa (px): recuadro mostrado y, si hay, placa del nombre y del rótulo.
            var layers: [[String: Any]] = []
            for b in st.boxes {
                let d = b.displayRect
                var layer: [String: Any] = ["part": b.partID, "box": [d.minX * s, d.minY * s, d.width * s, d.height * s],
                                            "opacity": b.opacity, "blur": b.blur, "scale": b.scale]
                if c.timeline.showPartLabels, let plate = try plateSize(renderer, b.name, size: MontageStyle.labelFont * s * b.scale, w, h) {
                    let inset = MontageStyle.labelInset * s * b.scale
                    layer["label"] = [d.minX * s + inset, d.maxY * s - inset - plate.height, plate.width, plate.height]
                }
                layers.append(layer)
            }
            var json: [String: Any] = ["case": c.name, "platform": Self.platform, "width": w, "height": h, "layers": layers,
                                       "background": [MontageStyle.background.r, MontageStyle.background.g, MontageStyle.background.b]]
            if let caption = c.caption, let plate = try captionSize(renderer, caption, scale: s, w, h) {
                let inset = MontageStyle.captionInset * s
                json["caption"] = [inset, Double(h) - inset - plate.height, plate.width, plate.height]
            }
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: dir.appendingPathComponent("\(c.name)_\(Self.platform).json"))
            print("7.9 comparación \(c.name) (\(Self.platform)): \(w)×\(h), recuadros \(st.boxes.map(\.partID))")
        }
        // Tiempo por fotograma compuesto (1080p, rejilla 2 × 2 con sombras), 20 fotogramas tras uno de calentamiento.
        let grid = Self.cases()[1]
        let out = RenderSupport.empty(width: 1920, height: 1080)
        let st = grid.timeline.state(at: grid.time)
        try renderer.render(st, timeline: grid.timeline, caption: nil, into: out) { grid.sources[$0] }
        let t0 = Date()
        for _ in 0..<20 { try renderer.render(st, timeline: grid.timeline, caption: nil, into: out) { grid.sources[$0] } }
        let ms = Date().timeIntervalSince(t0) / 20 * 1000
        #if os(Windows)
        let device = (renderer as? Direct2DMontageRenderer)?.device
        print(String(format: "7.9 compositor %@: %.1f ms por fotograma 1920×1080 (rejilla 2×2); adaptador «%@», hardware %@", Self.platform, ms,
                     device?.adapter ?? "?", device?.hardware == true ? "sí" : "no"))
        #else
        print(String(format: "7.9 compositor %@: %.1f ms por fotograma 1920×1080 (rejilla 2×2)", Self.platform, ms))
        #endif
    }

    func plateSize(_ r: any MontageFrameRendering, _ name: String, size: Double, _ w: Int, _ h: Int) throws -> CGSize? {
        guard size >= 4 else { return nil }
        #if canImport(CoreImage) && canImport(AVFoundation)
        return (r as? CoreImageMontageRenderer)?.labelPlateSize(name, size: size)
        #else
        return try (r as? Direct2DMontageRenderer)?.labelPlateSize(name, size: size, width: w, height: h)
        #endif
    }

    func captionSize(_ r: any MontageFrameRendering, _ c: MontageCaption, scale: Double, _ w: Int, _ h: Int) throws -> CGSize? {
        #if canImport(CoreImage) && canImport(AVFoundation)
        return (r as? CoreImageMontageRenderer)?.captionPlateSize(c, scale: scale)
        #else
        return try (r as? Direct2DMontageRenderer)?.captionPlateSize(c, scale: scale, width: w, height: h)
        #endif
    }
}
