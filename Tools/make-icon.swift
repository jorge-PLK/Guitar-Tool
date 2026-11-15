// Rasteriza un SVG a un PNG cuadrado con transparencia usando AppKit (respeta degradados).
// Uso: swift Tools/make-icon.swift <entrada.svg> <salida.png> [lado=1024]
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let image = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write("uso: make-icon.swift <entrada.svg> <salida.png> [lado]\n".data(using: .utf8)!)
    exit(1)
}
let side = args.count > 3 ? Int(args[3]) ?? 1024 : 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
rep.size = NSSize(width: side, height: side)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[2]))
