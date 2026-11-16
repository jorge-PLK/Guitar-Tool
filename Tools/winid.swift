// Uso: swiftc Tools/winid.swift -o <bin> ; <bin> [proceso]  -> imprime el windowID de su ventana mayor (para screencapture -l).
import CoreGraphics
import Foundation

let name = CommandLine.arguments.dropFirst().first ?? "ToneForge"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let wins = list.filter { ($0[kCGWindowOwnerName as String] as? String) == name && ($0[kCGWindowLayer as String] as? Int) == 0 }
func area(_ w: [String: Any]) -> CGFloat {
    let b = (w[kCGWindowBounds as String] as? [String: CGFloat]) ?? [:]
    return (b["Width"] ?? 0) * (b["Height"] ?? 0)
}
if let id = wins.max(by: { area($0) < area($1) })?[kCGWindowNumber as String] as? Int { print(id) } else { exit(1) }
