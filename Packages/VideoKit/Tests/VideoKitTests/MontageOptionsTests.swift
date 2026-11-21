#if canImport(AVFoundation)
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
#endif
import XCTest
@testable import VideoKit

/// Peticiones de Jorge del 17/11/2026: rejilla con 2 apilados, rótulos de parte opcionales, «Mantener aspect ratio de
/// vídeo», plano único landscape y cortes libres del plano único. `MontageRenderer` es el mismo que usa
/// `MontageCompositor` en la vista previa y en la exportación.
final class MontageOptionsTests: XCTestCase {
    static let frame = CGSize(width: 320, height: 180)
    static let solos = [MontageSpan(start: 4, end: 5), MontageSpan(start: 7.5, end: 8.5)]
    static let background = [0x0F, 0x11, 0x13]

    // MARK: Ayudas

    #if canImport(AVFoundation)
    /// Búfer BGRA 320 × 180 con el color de `f(x, y)` (origen arriba a la izquierda).
    static func buffer(_ f: (Int, Int) -> (r: UInt8, g: UInt8, b: UInt8)) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 320, 180, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        let base = CVPixelBufferGetBaseAddress(pb!)!.assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRow(pb!)
        for y in 0..<180 {
            for x in 0..<320 {
                let c = f(x, y), o = y * row + x * 4
                base[o] = c.b; base[o + 1] = c.g; base[o + 2] = c.r; base[o + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pb!, [])
        return pb!
    }

    static func flat(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> CVPixelBuffer { buffer { _, _ in (r, g, b) } }

    /// Toma sintética para mirar a ojo: degradado con cuadrícula y una barra diagonal clara, teñida por `hue`
    /// (0 rojo, 1 verde, 2 azul).
    static func pattern(_ hue: Int) -> CVPixelBuffer {
        buffer { x, y in
            let gx = Double(x) / 319, gy = Double(y) / 179
            let check = ((x / 20) + (y / 20)) % 2 == 0 ? 1.0 : 0.72
            let bar = abs(Double(x) - Double(y) * 1.78 - 60) < 10 ? 1.0 : 0.0
            var c = [0.25 + 0.75 * gx, 0.2 + 0.5 * gy, 0.3 + 0.4 * (1 - gx)].map { $0 * check }
            c = [c[(3 - hue) % 3], c[(4 - hue) % 3], c[(5 - hue) % 3]]
            c[hue] = max(c[hue], 0.9 * check)
            c = c.map { min(1, $0 + bar * 0.6) }
            return (UInt8(c[0] * 255), UInt8(c[1] * 255), UInt8(c[2] * 255))
        }
    }

    struct Pixels {
        let px: [UInt8]
        let w: Int
        let h: Int
        let image: CIImage
        let state: MontageFrameState

        /// (x, y) en unidades del lienzo con origen arriba a la izquierda, a escala `k` (`render(toBitmap:)` escribe la
        /// fila de arriba primero).
        func at(_ x: Double, _ y: Double, k: Double) -> [Int] {
            let xi = min(max(Int(x * k), 0), w - 1), yi = min(max(Int(y * k), 0), h - 1)
            let o = (yi * w + xi) * 4
            return [Int(px[o]), Int(px[o + 1]), Int(px[o + 2])]
        }
    }

    static let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    static func render(_ tl: MontageTimeline, at t: Double, scale k: Double, sources: [CVPixelBuffer]) -> Pixels {
        let size = CGSize(width: (tl.canvas.width * k).rounded(), height: (tl.canvas.height * k).rounded())
        let st = tl.state(at: t)
        let img = MontageRenderer().render(st, timeline: tl, caption: nil, renderSize: size) { CIImage(cvPixelBuffer: sources[$0]) }
        let w = Int(size.width), h = Int(size.height)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        context.render(img, toBitmap: &px, rowBytes: w * 4, bounds: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: nil)
        return Pixels(px: px, w: w, h: h, image: img, state: st)
    }

    /// PNG para que Jorge lo mire, en `Temp/fase-7/shots/` del repositorio.
    @discardableResult
    static func png(_ p: Pixels, _ name: String) throws -> URL {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let dir = repo.appendingPathComponent("Temp/fase-7/shots")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        let cg = try XCTUnwrap(context.createCGImage(p.image, from: CGRect(x: 0, y: 0, width: p.w, height: p.h), format: .RGBA8,
                                                     colorSpace: CGColorSpaceCreateDeviceRGB()))
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        print("F7 PNG: \(url.path)")
        return url
    }
    #endif

    static func parts(_ ids: [String], solo: Set<String> = []) -> [MontageTimeline.Part] {
        ids.map { id in
            MontageTimeline.Part(id: id, name: "Parte \(id)", isSolo: solo.contains(id),
                                 presence: solo.contains(id) ? solos : [MontageSpan(start: 0, end: 10)], firstImage: 0, frameSize: frame)
        }
    }

    static func timeline(_ layout: MontageLayoutKind, _ parts: [MontageTimeline.Part], labels: Bool = true, aspect: Bool = false,
                         cuts: [MontageCut] = []) -> MontageTimeline {
        MontageTimeline(canvas: layout.defaultCanvas.size, layout: layout, span: MontageSpan(start: 0, end: 10), barDuration: 1,
                        fadeIn: false, fadeOut: false, parts: parts, showPartLabels: labels, keepVideoAspect: aspect, singleCuts: cuts)
    }

    static func near(_ c: [Int], _ e: [Double], _ tol: Double) -> Bool { zip(c, e).allSatisfy { abs(Double($0) - $1) <= tol } }

    #if !canImport(AVFoundation)
    // Windows (parte 7.9): los mismos casos con `Direct2DMontageRenderer`.
    struct Pixels {
        let px: [UInt8]
        let w: Int
        let h: Int
        let state: MontageFrameState

        func at(_ x: Double, _ y: Double, k: Double) -> [Int] {
            let xi = min(max(Int(x * k), 0), w - 1), yi = min(max(Int(y * k), 0), h - 1)
            let o = (yi * w + xi) * 4
            return [Int(px[o]), Int(px[o + 1]), Int(px[o + 2])]
        }
    }

    static func buffer(_ f: (Int, Int) -> (r: UInt8, g: UInt8, b: UInt8)) -> FramePixelBuffer { RenderSupport.buffer(width: 320, height: 180, f) }
    static func flat(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> FramePixelBuffer { buffer { _, _ in (r, g, b) } }
    static var banded: FramePixelBuffer { buffer { x, _ in x < 32 ? (0, 255, 0) : (255, 0, 0) } }
    nonisolated(unsafe) static var shared: Direct2DMontageRenderer?

    static func render(_ tl: MontageTimeline, at t: Double, scale k: Double, sources: [FramePixelBuffer]) throws -> Pixels {
        let r = try shared ?? Direct2DMontageRenderer()
        shared = r
        let (pb, st) = try RenderSupport.render(r, tl, at: t, width: Int((tl.canvas.width * k).rounded()), height: Int((tl.canvas.height * k).rounded()),
                                                sources: sources)
        return Pixels(px: RenderSupport.rgba(pb), w: pb.width, h: pb.height, state: st)
    }

    func testGridTwoStackedRender() throws {
        let tl = Self.timeline(.grid, Self.parts(["A", "B"]))
        let p = try Self.render(tl, at: 5, scale: 0.5, sources: [Self.flat(255, 0, 0), Self.flat(0, 255, 0)])
        let a = p.state.boxes[0].rect, b = p.state.boxes[1].rect
        XCTAssertEqual(p.at(a.midX, a.midY, k: 0.5), [255, 0, 0])
        XCTAssertEqual(p.at(b.midX, b.midY, k: 0.5), [0, 255, 0])
        XCTAssertLessThan(a.maxY, b.minY, "A encima de B")
        XCTAssertEqual(p.at(a.minX / 2, a.midY, k: 0.5), Self.background)
        XCTAssertEqual(p.at((a.maxX + 1920) / 2, b.midY, k: 0.5), Self.background)
    }

    func testPartLabelsCanBeHidden() throws {
        let sources = [Self.flat(255, 0, 0), Self.flat(0, 255, 0)]
        for layout in [MontageLayoutKind.side, .stack, .single, .singleLandscape] {
            let on = try Self.render(Self.timeline(layout, Self.parts(["A", "B"])), at: 5, scale: 0.5, sources: sources)
            let off = try Self.render(Self.timeline(layout, Self.parts(["A", "B"]), labels: false), at: 5, scale: 0.5, sources: sources)
            let r = on.state.boxes.last!.rect
            let color = on.state.boxes.last!.partID == "A" ? [255, 0, 0] : [0, 255, 0]
            let x = r.minX + MontageStyle.labelInset + 5, y = r.maxY - MontageStyle.labelInset - 22
            let withLabel = on.at(x, y, k: 0.5), without = off.at(x, y, k: 0.5)
            XCTAssertNotEqual(withLabel, color, "\(layout): con rótulo, la placa oscurece")
            XCTAssertLessThan(withLabel.max()!, 200, "\(layout) \(withLabel)")
            XCTAssertEqual(without, color, "\(layout): sin rótulo, el color de la toma")
            XCTAssertEqual(on.at(r.midX, r.midY, k: 0.5), off.at(r.midX, r.midY, k: 0.5))
            print("7.9 rótulos \(layout.rawValue): placa con rótulo \(withLabel), sin rótulo \(without)")
        }
    }

    func testKeepAspectInStackShowsWholeFrameOverDimmedFill() throws {
        let k = 0.5
        let on = try Self.render(Self.timeline(.stack, Self.parts(["A", "B"]), aspect: true), at: 5, scale: k, sources: [Self.banded, Self.banded])
        let off = try Self.render(Self.timeline(.stack, Self.parts(["A", "B"])), at: 5, scale: k, sources: [Self.banded, Self.banded])
        XCTAssertTrue(on.state.boxes.allSatisfy { $0.fit && $0.crop == .full })
        for box in on.state.boxes {
            let r = box.rect
            let fitH = r.width * 9 / 16, strip = (r.height - fitH) / 2
            XCTAssertEqual(on.at(r.midX, r.midY, k: k), [255, 0, 0], "centro: la toma")
            XCTAssertEqual(on.at(r.minX + 10, r.midY, k: k), [0, 255, 0], "borde izquierdo: la franja verde (fotograma entero)")
            XCTAssertEqual(off.at(r.minX + 10, r.midY, k: k), [255, 0, 0], "sin la bandera, el encuadre recorta la franja")
            for y in [r.minY + strip / 2, r.maxY - strip / 2] {
                let fill = on.at(r.midX, y, k: k)
                XCTAssertTrue(Self.near(fill, [255 * MontageStyle.fillDim, 0, 0], 3), "relleno = toma oscurecida: \(fill)")
                XCTAssertNotEqual(fill, Self.background)
                print("7.9 aspecto apilado \(box.partID): relleno \(fill) (esperado \(255 * MontageStyle.fillDim), 0, 0)")
            }
        }
    }

    func testKeepAspectChangesNothingInSideAndGrid() throws {
        for layout in [MontageLayoutKind.side, .grid] {
            let tlOn = Self.timeline(layout, Self.parts(["A", "B", "C"]), aspect: true)
            XCTAssertFalse(tlOn.keepVideoAspect)
            let on = try Self.render(tlOn, at: 5, scale: 0.25, sources: [Self.banded, Self.banded, Self.banded])
            let off = try Self.render(Self.timeline(layout, Self.parts(["A", "B", "C"])), at: 5, scale: 0.25, sources: [Self.banded, Self.banded, Self.banded])
            XCTAssertEqual(on.px, off.px, "\(layout): misma imagen con y sin la bandera")
        }
    }

    func testKeepAspectSingleCrossfadeEachWithOwnFill() throws {
        let tl = Self.timeline(.single, Self.parts(["A", "C"], solo: ["C"]), aspect: true)
        let p = try Self.render(tl, at: 3.75, scale: 0.5, sources: [Self.flat(255, 0, 0), Self.flat(0, 0, 255)])
        XCTAssertEqual(p.state.boxes.map(\.partID), ["A", "C"])
        for b in p.state.boxes { XCTAssertEqual(b.opacity, 0.5, accuracy: 1e-9) }
        let dim = 255 * MontageStyle.fillDim
        let bg: [Double] = Self.background.map { Double($0) }
        let dimA: [Double] = [dim, 0, 0], dimC: [Double] = [0, 0, dim]
        var expected: [Double] = []
        for c in 0..<3 { expected.append(0.5 * dimC[c] + 0.5 * (0.5 * dimA[c] + 0.5 * bg[c])) }
        let fill = p.at(540, 300, k: 0.5)
        XCTAssertTrue(Self.near(fill, expected, 3), "relleno en el fundido \(fill), esperado \(expected)")
        print("7.9 aspecto plano único, fundido al 50 %: relleno \(fill), esperado \(expected.map { Int($0.rounded()) })")
    }

    func testSingleLandscapeFullCanvas() throws {
        XCTAssertEqual(MontageLayoutKind.singleLandscape.rawValue, "single-landscape")
        XCTAssertEqual(MontageLayoutKind.singleLandscape.defaultCanvas, .landscape)
        XCTAssertEqual(MontageLayoutKind.single.defaultCanvas, .portrait)
        let tl = Self.timeline(.singleLandscape, Self.parts(["A", "C"], solo: ["C"]))
        let p = try Self.render(tl, at: 2, scale: 0.5, sources: [Self.flat(255, 0, 0), Self.flat(0, 0, 255)])
        XCTAssertEqual([p.w, p.h], [960, 540])
        XCTAssertEqual(p.state.boxes.map(\.partID), ["A"])
        XCTAssertEqual(p.state.boxes[0].rect, CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(p.at(1, 1, k: 0.5), [255, 0, 0])
        XCTAssertEqual(p.at(960, 540, k: 0.5), [255, 0, 0])
        let solo = try Self.render(tl, at: 4.5, scale: 0.5, sources: [Self.flat(255, 0, 0), Self.flat(0, 0, 255)])
        XCTAssertEqual(solo.state.boxes.map(\.partID), ["C"])
        XCTAssertEqual(solo.at(960, 540, k: 0.5), [0, 0, 255])
    }

    /// Plano único landscape con cortes y sin rótulos por `MontageBuilder` y el compositor de Windows.
    func testBuilderSingleLandscapeCutsWithoutLabels() async throws {
        let fx = try await MontageGateTests.fixture()
        defer { try? FileManager.default.removeItem(at: fx.dir) }
        var plan = fx.plan(.singleLandscape, .landscape)
        plan.showPartLabels = false
        plan.singleCuts = Self.shuffled
        let builder = try await MontageBuilder.load(plan)
        let size = MontageBuilder.renderSize(canvas: plan.canvas, maxDimension: 480)
        let preview = try builder.make(renderSize: size, includeAudio: false)
        let k = size.width / 1920
        let expect: [(Double, String)] = [(3.2, "verde"), (4.5, "verde"), (5.7, "azul"), (6.7, "rojo"), (7.7, "azul"), (9.0, "rojo")]
        var seen: [String] = []
        for (t, name) in expect {
            let f = MontageGateTests.Frame(try preview.frame(at: preview.videoTime(songTime: t)))
            XCTAssertEqual([f.width, f.height], [Int(size.width), Int(size.height)])
            let center = MontageGateTests.name(f.rgb(960 * k, 540 * k))
            let label = MontageGateTests.name(f.rgb((MontageStyle.labelInset + 8) * k, (1080 - MontageStyle.labelInset - 22) * k))
            XCTAssertEqual(center, name, "centro en \(t)")
            XCTAssertEqual(label, name, "sitio del rótulo en \(t): sin placa")
            seen.append("\(t): \(center)")
        }
        print("7.9 compositor plano único landscape \(Int(size.width))×\(Int(size.height)) con cortes y sin rótulos: \(seen)")
    }
    #else
    // MARK: 1. Rejilla con 2

    func testGridTwoStackedRender() throws {
        let tl = Self.timeline(.grid, Self.parts(["A", "B"]))
        let p = Self.render(tl, at: 5, scale: 0.5, sources: [Self.flat(255, 0, 0), Self.flat(0, 255, 0)])
        let a = p.state.boxes[0].rect, b = p.state.boxes[1].rect
        XCTAssertEqual(p.at(a.midX, a.midY, k: 0.5), [255, 0, 0])
        XCTAssertEqual(p.at(b.midX, b.midY, k: 0.5), [0, 255, 0])
        XCTAssertLessThan(a.maxY, b.minY, "A encima de B")
        // Fondo a los lados, a media altura de cada recuadro.
        XCTAssertEqual(p.at(a.minX / 2, a.midY, k: 0.5), Self.background)
        XCTAssertEqual(p.at((a.maxX + 1920) / 2, b.midY, k: 0.5), Self.background)
        let big = Self.render(tl, at: 5, scale: 1, sources: [Self.pattern(0), Self.pattern(2)])
        try Self.png(big, "rejilla-2.png")
        print("F7 rejilla 2: A \(a), B \(b)")
    }

    // MARK: 2. Rótulos de parte

    func testPartLabelsCanBeHidden() {
        let sources = [Self.flat(255, 0, 0), Self.flat(0, 255, 0)]
        for layout in [MontageLayoutKind.side, .stack, .single, .singleLandscape] {
            let on = Self.render(Self.timeline(layout, Self.parts(["A", "B"])), at: 5, scale: 0.5, sources: sources)
            let off = Self.render(Self.timeline(layout, Self.parts(["A", "B"]), labels: false), at: 5, scale: 0.5, sources: sources)
            let r = on.state.boxes.last!.rect
            let color = on.state.boxes.last!.partID == "A" ? [255, 0, 0] : [0, 255, 0]
            // Borde izquierdo de la placa del nombre, a media altura (placa negra al 50 %).
            let x = r.minX + MontageStyle.labelInset + 5, y = r.maxY - MontageStyle.labelInset - 22
            let withLabel = on.at(x, y, k: 0.5), without = off.at(x, y, k: 0.5)
            XCTAssertNotEqual(withLabel, color, "\(layout): con rótulo, la placa oscurece")
            XCTAssertLessThan(withLabel.max()!, 200, "\(layout) \(withLabel)")
            XCTAssertEqual(without, color, "\(layout): sin rótulo, el color de la toma")
            XCTAssertEqual(on.at(r.midX, r.midY, k: 0.5), off.at(r.midX, r.midY, k: 0.5))
            print("F7 rótulos \(layout.rawValue): placa con rótulo \(withLabel), sin rótulo \(without)")
        }
    }

    // MARK: 3. Mantener aspect ratio

    /// Toma roja con una franja verde en el 10 % izquierdo: si se ve la franja, se ve el fotograma entero.
    static var banded: CVPixelBuffer { buffer { x, _ in x < 32 ? (0, 255, 0) : (255, 0, 0) } }

    func testKeepAspectInStackShowsWholeFrameOverDimmedFill() throws {
        let k = 0.5
        let on = Self.render(Self.timeline(.stack, Self.parts(["A", "B"]), aspect: true), at: 5, scale: k, sources: [Self.banded, Self.banded])
        let off = Self.render(Self.timeline(.stack, Self.parts(["A", "B"])), at: 5, scale: k, sources: [Self.banded, Self.banded])
        XCTAssertTrue(on.state.boxes.allSatisfy { $0.fit && $0.crop == .full })
        for box in on.state.boxes {
            let r = box.rect
            // Ajuste por ancho: 984 × 553,5 centrado en vertical; franjas de relleno arriba y abajo.
            let fitH = r.width * 9 / 16, strip = (r.height - fitH) / 2
            XCTAssertEqual(on.at(r.midX, r.midY, k: k), [255, 0, 0], "centro: la toma")
            XCTAssertEqual(on.at(r.minX + 10, r.midY, k: k), [0, 255, 0], "borde izquierdo: la franja verde (fotograma entero)")
            XCTAssertEqual(off.at(r.minX + 10, r.midY, k: k), [255, 0, 0], "sin la bandera, el encuadre recorta la franja")
            for y in [r.minY + strip / 2, r.maxY - strip / 2] {
                let fill = on.at(r.midX, y, k: k)
                XCTAssertTrue(Self.near(fill, [255 * MontageStyle.fillDim, 0, 0], 3), "relleno = toma oscurecida: \(fill)")
                XCTAssertNotEqual(fill, Self.background)
                print("F7 aspecto apilado \(box.partID): relleno \(fill) (esperado \(255 * MontageStyle.fillDim), 0, 0), franja \(strip) px")
            }
        }
        let big = Self.render(Self.timeline(.stack, Self.parts(["A", "B"]), aspect: true), at: 5, scale: 1,
                              sources: [Self.pattern(0), Self.pattern(2)])
        try Self.png(big, "aspecto-apilado.png")
    }

    func testKeepAspectChangesNothingInSideAndGrid() {
        for layout in [MontageLayoutKind.side, .grid] {
            let tlOn = Self.timeline(layout, Self.parts(["A", "B", "C"]), aspect: true)
            XCTAssertFalse(tlOn.keepVideoAspect)
            let on = Self.render(tlOn, at: 5, scale: 0.25, sources: [Self.banded, Self.banded, Self.banded])
            let off = Self.render(Self.timeline(layout, Self.parts(["A", "B", "C"])), at: 5, scale: 0.25, sources: [Self.banded, Self.banded, Self.banded])
            XCTAssertEqual(on.px, off.px, "\(layout): misma imagen con y sin la bandera")
        }
    }

    /// Plano único: en el fundido cruzado rítmica (rojo) → solista (azul), cada una con su propio relleno.
    func testKeepAspectSingleCrossfadeEachWithOwnFill() throws {
        let tl = Self.timeline(.single, Self.parts(["A", "C"], solo: ["C"]), aspect: true)
        let p = Self.render(tl, at: 3.75, scale: 0.5, sources: [Self.flat(255, 0, 0), Self.flat(0, 0, 255)])
        XCTAssertEqual(p.state.boxes.map(\.partID), ["A", "C"])
        for b in p.state.boxes { XCTAssertEqual(b.opacity, 0.5, accuracy: 1e-9) }
        // Relleno: fondo, A oscurecido al 50 % de opacidad, C oscurecido al 50 % encima.
        let dim = 255 * MontageStyle.fillDim
        let bg: [Double] = Self.background.map { Double($0) }
        let dimA: [Double] = [dim, 0, 0], dimC: [Double] = [0, 0, dim]
        var expected: [Double] = []
        for c in 0..<3 {
            let under = 0.5 * dimA[c] + 0.5 * bg[c]
            expected.append(0.5 * dimC[c] + 0.5 * under)
        }
        let fill = p.at(540, 300, k: 0.5)
        XCTAssertTrue(Self.near(fill, expected, 3), "relleno en el fundido \(fill), esperado \(expected)")
        print("F7 aspecto plano único, fundido al 50 %: relleno \(fill), esperado \(expected.map { Int($0.rounded()) })")
        let still = Self.render(Self.timeline(.single, Self.parts(["A", "C"], solo: ["C"]), aspect: true), at: 2, scale: 1,
                                sources: [Self.pattern(0), Self.pattern(2)])
        try Self.png(still, "aspecto-plano-unico.png")
        let cross = Self.render(tl, at: 3.75, scale: 1, sources: [Self.pattern(0), Self.pattern(2)])
        try Self.png(cross, "aspecto-plano-unico-fundido.png")
    }

    // MARK: 4. Plano único landscape

    func testSingleLandscapeFullCanvas() throws {
        XCTAssertEqual(MontageLayoutKind.singleLandscape.rawValue, "single-landscape")
        XCTAssertEqual(MontageLayoutKind.singleLandscape.defaultCanvas, .landscape)
        XCTAssertEqual(MontageLayoutKind.single.defaultCanvas, .portrait)
        let tl = Self.timeline(.singleLandscape, Self.parts(["A", "C"], solo: ["C"]))
        let p = Self.render(tl, at: 2, scale: 0.5, sources: [Self.flat(255, 0, 0), Self.flat(0, 0, 255)])
        XCTAssertEqual([p.w, p.h], [960, 540])
        XCTAssertEqual(p.state.boxes.map(\.partID), ["A"])
        XCTAssertEqual(p.state.boxes[0].rect, CGRect(x: 0, y: 0, width: 1920, height: 1080))
        // Sin esquinas: el píxel de la esquina es de la toma.
        XCTAssertEqual(p.at(1, 1, k: 0.5), [255, 0, 0])
        XCTAssertEqual(p.at(960, 540, k: 0.5), [255, 0, 0])
        // En el solo, la solista.
        let solo = Self.render(tl, at: 4.5, scale: 0.5, sources: [Self.flat(255, 0, 0), Self.flat(0, 0, 255)])
        XCTAssertEqual(solo.state.boxes.map(\.partID), ["C"])
        XCTAssertEqual(solo.at(960, 540, k: 0.5), [0, 0, 255])
        let big = Self.render(tl, at: 2, scale: 1, sources: [Self.pattern(0), Self.pattern(2)])
        try Self.png(big, "plano-unico-landscape.png")
        let aspect = Self.render(Self.timeline(.singleLandscape, Self.parts(["A"]), aspect: true), at: 2, scale: 1, sources: [Self.pattern(1)])
        try Self.png(aspect, "plano-unico-landscape-aspecto.png")
    }
    #endif

    // MARK: 5. Cortes libres

    /// Rítmica A (2–10), rítmica B con imagen solo en 2–6 y solista C con solos en 4–5 y 7,5–8,5 (imagen en 2–10).
    static func cutParts() -> [MontageTimeline.Part] {
        [
            MontageTimeline.Part(id: "A", name: "A", isSolo: false, presence: [MontageSpan(start: 2, end: 10)], firstImage: 2, frameSize: frame),
            MontageTimeline.Part(id: "B", name: "B", isSolo: false, presence: [MontageSpan(start: 2, end: 6)], firstImage: 2, frameSize: frame,
                                 images: [MontageSpan(start: 2, end: 6)]),
            MontageTimeline.Part(id: "C", name: "C", isSolo: true, presence: solos, firstImage: 2, frameSize: frame,
                                 images: [MontageSpan(start: 2, end: 10)])
        ]
    }

    /// 3 → B (pisa el solo de 4–5), 5,5 → C, 6,5 → B (sin imagen: automático = A), 7,5 → automático (solo de C).
    static let cuts = [MontageCut(time: 3, partID: "B"), MontageCut(time: 5.5, partID: "C"), MontageCut(time: 6.5, partID: "B"),
                       MontageCut(time: 7.5, partID: nil)]
    static let shuffled = [cuts[2], cuts[0], cuts[3], cuts[1]]

    static func cutTimeline(_ cuts: [MontageCut], layout: MontageLayoutKind = .single) -> MontageTimeline {
        MontageTimeline(canvas: layout.defaultCanvas.size, layout: layout, span: MontageSpan(start: 2, end: 10), barDuration: 1,
                        fadeIn: false, fadeOut: false, parts: cutParts(), singleCuts: cuts)
    }

    static func opacity(_ tl: MontageTimeline, _ id: String, _ t: Double) -> Double {
        tl.state(at: t).boxes.first { $0.partID == id }?.opacity ?? 0
    }

    func testSingleCutsDecideImage() {
        for layout in [MontageLayoutKind.single, .singleLandscape] {
            let tl = Self.cutTimeline(Self.shuffled, layout: layout)
            // Quién está entero en cada instante.
            let expect: [(Double, String)] = [(3.0, "B"), (4.5, "B"), (5.5, "C"), (5.95, "C"), (6.5, "A"), (7.0, "A"), (7.5, "C"), (8.4, "C"), (9.0, "A")]
            for (t, id) in expect {
                let st = tl.state(at: t)
                let full = st.boxes.filter { $0.opacity > 1 - 1e-9 }.map(\.partID)
                XCTAssertEqual(full, [id], "\(layout) t = \(t): \(st.boxes.map { "\($0.partID) \($0.opacity)" })")
                XCTAssertEqual(st.boxes.map(\.partID), [id], "\(layout) t = \(t): solo un recuadro")
            }
            // Anticipación de 0,5 s: el fundido cruzado A → B ocupa 2,5–3,0 y B está entero en el corte.
            XCTAssertEqual(Self.opacity(tl, "B", 2.5), 0, accuracy: 1e-12)
            XCTAssertEqual(Self.opacity(tl, "B", 2.75), 0.5, accuracy: 1e-12)
            XCTAssertEqual(Self.opacity(tl, "A", 2.75), 0.5, accuracy: 1e-12)
            XCTAssertEqual(Self.opacity(tl, "B", 3.0), 1, accuracy: 1e-12)
            XCTAssertEqual(Self.opacity(tl, "C", 5.25), 0.5, accuracy: 1e-12)
            // Caída a automático: B no tiene imagen tras 6 s, así que no aparece nunca después de su salida (5,0–5,5).
            var t = 5.5
            while t <= 10 { XCTAssertEqual(Self.opacity(tl, "B", t), 0, "B sin imagen en \(t)"); t += 0.01 }
        }
    }

    /// Cada 1 ms en 2,5–10 s: las opacidades suman 1 (nunca un recuadro vacío ni dos enteros) y ningún salto supera la
    /// pendiente máxima de la ease-in-out (3/0,5 s por segundo).
    func testSingleCutsContinuousAndNeverEmpty() {
        let tl = Self.cutTimeline(Self.shuffled)
        let step = 0.001, slope = 3 / MontageStyle.transition * step
        var prev: [String: Double] = [:], worstSum = 0.0, worstStep = 0.0
        for b in tl.state(at: 2.5 - step).boxes { prev[b.partID] = b.opacity }
        var t = 2.5
        while t <= 10 - step {
            let st = tl.state(at: t)
            worstSum = max(worstSum, abs(st.boxes.reduce(0) { $0 + $1.opacity } - 1))
            var now: [String: Double] = [:]
            for b in st.boxes { now[b.partID] = b.opacity }
            for id in Set(now.keys).union(prev.keys) { worstStep = max(worstStep, abs((now[id] ?? 0) - (prev[id] ?? 0))) }
            prev = now
            t += step
        }
        XCTAssertLessThan(worstSum, 1e-9, "suma de opacidades")
        XCTAssertLessThanOrEqual(worstStep, slope + 1e-9, "salto de opacidad por ms")
        print(String(format: "F7 cortes: |Σ opacidad − 1| máx %.2e; salto máx %.5f/ms (tope %.5f)", worstSum, worstStep, slope))
    }

    func testSingleCutsOrderEmptyAndOtherLayouts() {
        let sorted = Self.cutTimeline(Self.cuts), shuffled = Self.cutTimeline(Self.shuffled)
        let auto = Self.cutTimeline([]), unknown = Self.cutTimeline([MontageCut(time: 3, partID: "X"), MontageCut(time: 5, partID: nil)])
        XCTAssertEqual(MontageCut.normalized(Self.shuffled), Self.cuts)
        XCTAssertEqual(MontageCut.normalized([MontageCut(time: 4, partID: "A"), MontageCut(time: 2, partID: nil), MontageCut(time: 4, partID: "C")]),
                       [MontageCut(time: 2, partID: nil), MontageCut(time: 4, partID: "C")])
        let plain = MontageTimeline(canvas: MontageCanvas.portrait.size, layout: .single, span: MontageSpan(start: 2, end: 10), barDuration: 1,
                                    fadeIn: false, fadeOut: false, parts: Self.cutParts())
        var t = 2.0
        while t <= 10 {
            XCTAssertEqual(sorted.state(at: t), shuffled.state(at: t), "desordenados en \(t)")
            XCTAssertEqual(auto.state(at: t), plain.state(at: t), "sin cortes en \(t)")
            XCTAssertEqual(unknown.state(at: t), plain.state(at: t), "parte desconocida o nil en \(t)")
            t += 0.05
        }
        // En los layouts con varios recuadros, los cortes no cuentan.
        let side = MontageTimeline(canvas: MontageCanvas.landscape.size, layout: .side, span: MontageSpan(start: 2, end: 10), barDuration: 1,
                                   fadeIn: false, fadeOut: false, parts: Self.cutParts(), singleCuts: Self.cuts)
        let sidePlain = MontageTimeline(canvas: MontageCanvas.landscape.size, layout: .side, span: MontageSpan(start: 2, end: 10), barDuration: 1,
                                        fadeIn: false, fadeOut: false, parts: Self.cutParts())
        XCTAssertEqual(side.state(at: 4.5), sidePlain.state(at: 4.5))
    }

    // MARK: Plan

    func testPlanCodableWithNewFields() throws {
        let old = """
        {"canvas":{"width":1080,"height":1920},"fps":30,"layout":"single","segments":[{"start":2,"end":10}],"barDuration":1,
         "fadeIn":true,"fadeOut":false,"parts":[]}
        """
        let p = try JSONDecoder().decode(MontagePlan.self, from: Data(old.utf8))
        XCTAssertTrue(p.showPartLabels)
        XCTAssertFalse(p.keepVideoAspect)
        XCTAssertEqual(p.singleCuts, [])
        var q = p
        q.layout = .singleLandscape
        q.canvas = .landscape
        q.showPartLabels = false
        q.keepVideoAspect = true
        q.singleCuts = Self.shuffled
        let data = try JSONEncoder().encode(q)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"single-landscape\""))
        XCTAssertEqual(try JSONDecoder().decode(MontagePlan.self, from: data), q)
    }

    // MARK: Composición real (la de la vista previa y la exportación)

    #if canImport(AVFoundation)
    /// Plano único landscape con cortes y sin rótulos, por `MontageBuilder` y el compositor: dimensiones, colores en
    /// cada instante y el sitio del rótulo con el color de la toma.
    func testBuilderSingleLandscapeCutsWithoutLabels() async throws {
        let fx = try await MontageGateTests.fixture()
        defer { try? FileManager.default.removeItem(at: fx.dir) }
        var plan = fx.plan(.singleLandscape, .landscape)
        plan.showPartLabels = false
        plan.singleCuts = Self.shuffled
        let builder = try await MontageBuilder.load(plan)
        let size = MontageBuilder.renderSize(canvas: plan.canvas, maxDimension: 480)
        let preview = try builder.make(renderSize: size, includeAudio: false)
        let gen = MontageGateTests.generator(preview.composition, videoComposition: preview.videoComposition)
        let k = size.width / 1920
        // B (verde) tiene imagen hasta 6 s en la toma de la puerta: mismos instantes que el test del timeline.
        let expect: [(Double, String)] = [(3.2, "verde"), (4.5, "verde"), (5.7, "azul"), (6.7, "rojo"), (7.7, "azul"), (9.0, "rojo")]
        var seen: [String] = []
        for (t, name) in expect {
            let f = try await MontageGateTests.frame(gen, at: preview.timeline.timeMap.videoTime(songTime: t))
            XCTAssertEqual([f.width, f.height], [Int(size.width), Int(size.height)])
            let center = MontageGateTests.name(f.rgb(960 * k, 540 * k))
            let label = MontageGateTests.name(f.rgb((MontageStyle.labelInset + 8) * k, (1080 - MontageStyle.labelInset - 22) * k))
            XCTAssertEqual(center, name, "centro en \(t)")
            XCTAssertEqual(label, name, "sitio del rótulo en \(t): sin placa")
            seen.append("\(t): \(center)")
        }
        print("F7 compositor plano único landscape \(Int(size.width))×\(Int(size.height)) con cortes y sin rótulos: \(seen)")
    }
    #endif
}
