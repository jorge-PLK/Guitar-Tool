import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VideoKit

/// `frame` y `montage` (Fase 7, desarrollo).
extension CLI {
    static func f(_ b: FramingBox) -> String { "x \(b.x.fixed(3)) y \(b.y.fixed(3)) ancho \(b.width.fixed(3)) alto \(b.height.fixed(3))" }

    /// Caja fija y resumen de la trayectoria de `GuitarFramer`; con `--png`, el fotograma central con las cajas.
    static func frame(_ o: Options, _ env: Env) async throws -> Int32 {
        let url = URL(fileURLWithPath: o.positional[0])
        let a = try await GuitarFramer.analyze(videoURL: url, interval: o.interval ?? GuitarFramer.defaultInterval)
        env.line("Vídeo: \(url.path) (\(a.frameWidth)×\(a.frameHeight))")
        env.line("Muestras: \(a.samples), con pose: \(a.detected)")
        if let b = a.fixed { env.line("Caja fija (normalizada, origen arriba a la izquierda): \(f(b))") } else {
            env.line("Caja fija: sin detección (fotograma entero)")
        }
        if let first = a.track.first, let last = a.track.last {
            let xs = a.track.map(\.box.midX), ys = a.track.map(\.box.midY), ws = a.track.map(\.box.width)
            let step = zip(a.track, a.track.dropFirst()).map { max(abs($1.box.midX - $0.box.midX), abs($1.box.midY - $0.box.midY)) }.max() ?? 0
            env.line("Trayectoria: \(a.track.count) puntos de \(first.time.fixed(2)) a \(last.time.fixed(2)) s; centro x \(xs.min()!.fixed(3))–\(xs.max()!.fixed(3)), y \(ys.min()!.fixed(3))–\(ys.max()!.fixed(3)); ancho \(ws.min()!.fixed(3))–\(ws.max()!.fixed(3)); paso máx \(step.fixed(4))")
        } else {
            env.line("Trayectoria: vacía")
        }
        if let png = o.png {
            let asset = AVURLAsset(url: url)
            let range = try await asset.loadTracks(withMediaType: .video).first!.load(.timeRange)
            let mid = CMTimeGetSeconds(range.start) + CMTimeGetSeconds(range.duration) / 2
            let gen = AVAssetImageGenerator(asset: asset)
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = .zero
            let (img, _) = try await gen.image(at: CMTime(seconds: mid, preferredTimescale: 90_000))
            let w = img.width, h = img.height
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CLIError("No se pudo dibujar el PNG.") }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setLineWidth(max(2, CGFloat(w) / 300))
            func stroke(_ b: FramingBox, _ c: CGColor) {
                ctx.setStrokeColor(c)
                ctx.stroke(CGRect(x: b.x * Double(w), y: (1 - b.y - b.height) * Double(h), width: b.width * Double(w), height: b.height * Double(h)))
            }
            if let b = a.fixed { stroke(b, CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)) }
            if let b = a.trackBox(at: mid) { stroke(b, CGColor(red: 0.2, green: 1, blue: 0.3, alpha: 1)) }
            let out = URL(fileURLWithPath: png)
            guard let image = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw CLIError("No se pudo escribir \(png).")
            }
            CGImageDestinationAddImage(dest, image, nil)
            guard CGImageDestinationFinalize(dest) else { throw CLIError("No se pudo escribir \(png).") }
            env.line("PNG: \(out.path) (fotograma a \(mid.fixed(2)) s; rojo = caja fija, verde = trayectoria)")
        }
        return Exit.ok
    }

    /// Exporta un `MontagePlan` en JSON.
    static func montage(_ o: Options, _ env: Env) async throws -> Int32 {
        let planURL = URL(fileURLWithPath: o.positional[0]), out = URL(fileURLWithPath: o.positional[1])
        let plan: MontagePlan
        do { plan = try JSONDecoder().decode(MontagePlan.self, from: Data(contentsOf: planURL)) } catch {
            throw CLIError("Plan no válido (\(planURL.lastPathComponent)): \(error)")
        }
        let container: MontageVideoContainer = (o.container ?? out.pathExtension.lowercased()) == "mp4" ? .mp4 : .mov
        guard out.pathExtension.lowercased() == container.fileExtension else {
            throw CLIError("La salida debe acabar en .\(container.fileExtension) con --container \(container.rawValue).")
        }
        let settings = MontageExportSettings(codec: o.codec == "h264" ? .h264 : .hevc, width: o.sizeGiven ? o.width : plan.canvas.width,
                                             height: o.sizeGiven ? o.height : plan.canvas.height, fps: o.fpsGiven ? o.fps : plan.fps,
                                             container: container)
        env.line("Plan: \(plan.layout.rawValue), \(plan.parts.count) partes, tramo \(plan.span.start.fixed(3))–\(plan.span.end.fixed(3)) s")
        final class Step: @unchecked Sendable { let lock = NSLock(); var next = 0.1 }
        let step = Step()
        let s = try await MontageExporter.export(plan: plan, mixURL: o.mix.map { URL(fileURLWithPath: $0) }, settings: settings, to: out) { p in
            let show = step.lock.withLock { () -> Bool in
                guard p >= step.next else { return false }
                while step.next <= p { step.next += 0.1 }
                return true
            }
            if show { env.line("  \(Int((p * 100).rounded())) %") }
        }
        env.line("Vídeo: \(s.url.path)")
        env.line("\(s.settings.container.rawValue.uppercased()), \(s.settings.width)×\(s.settings.height) \(s.settings.codec.rawValue) a \(s.settings.fps.fixed(2)) fps, \(s.frames) fotogramas, \(s.duration.fixed(3)) s, audio: \(s.hasAudio ? "sí" : "no")")
        return Exit.ok
    }
}
