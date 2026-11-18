#if DEBUG
import Foundation
import SourceKit

/// `--spotify-demo <results|error>`: abre el popup «Importar tema» con una búsqueda simulada (sin red ni clave) para capturas.
private struct DemoSearcher: SpotifySearching {
    let fail: Bool
    func search(_ query: String) async throws -> [SpotifyTrackResult] {
        if fail { throw SpotifySearchError.missingCredentials }
        return [
            SpotifyTrackResult(id: "4uLU6hMCjMI75M1A2tKUQC", name: "One", artists: ["Metallica"],
                               album: "...And Justice for All", year: 1988, durationMs: 447_000, imageURL: nil),
            SpotifyTrackResult(id: "5dLU6hMCjMI75M1A2tKUQC", name: "Enter Sandman", artists: ["Metallica"],
                               album: "Metallica", year: 1991, durationMs: 331_000, imageURL: nil),
            SpotifyTrackResult(id: "6eLU6hMCjMI75M1A2tKUQC", name: "One (Live)", artists: ["Metallica", "Invitado"],
                               album: "S&M", year: 1999, durationMs: 452_000, imageURL: nil)
        ]
    }
}

@MainActor
extension AppModel {
    func openSpotifyDemo(_ mode: String) {
        openLinkImportDemo("vacio")
        guard let s = linkImport else { return }
        s.searcher = DemoSearcher(fail: mode == "error")
        s.text = "metallica one"
        s.importTapped()
    }
}
#endif

#if DEBUG
import AppKit

extension AppModel {
    /// `--artists-demo`: fotos simuladas (degradados generados) para la mitad de los artistas; el resto, iniciales.
    func installArtistsDemo() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tf-artists-demo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        artistPhotoProvider = { name in
            let key = name.lowercased()
            let h = key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
            guard h % 2 == 0 else { return nil }
            let url = dir.appendingPathComponent("\(h).png")
            if FileManager.default.fileExists(atPath: url.path) { return url }
            let size = 240
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            let a = NSColor(hue: CGFloat(h % 360) / 360, saturation: 0.55, brightness: 0.8, alpha: 1)
            let b = NSColor(hue: CGFloat((h + 60) % 360) / 360, saturation: 0.7, brightness: 0.35, alpha: 1)
            NSGradient(starting: a, ending: b)?.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: 55)
            NSGraphicsContext.restoreGraphicsState()
            guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
            try? png.write(to: url)
            return url
        }
    }
}
#endif
