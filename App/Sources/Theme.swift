import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// Paleta y tipografía de los bocetos (docs/design/*.dc.html).
enum TF {
    static let bg = Color(hex: 0x0F1113)
    static let sidebar = Color(hex: 0x15181B)
    static let card = Color(hex: 0x171A1D)
    static let field = Color(hex: 0x1C2024)
    static let line = Color(hex: 0x252A2F)
    static let fieldLine = Color(hex: 0x2A3036)
    static let text = Color(hex: 0xE8EAED)
    static let text2 = Color(hex: 0xC9CED4)
    static let muted = Color(hex: 0x9AA3AD)
    static let accent = Color(hex: 0xF2A33A)
    static let accentBg = Color(hex: 0x2A2116)
    static let accentInk = Color(hex: 0x1A1206)
    static let ok = Color(hex: 0x6FD99E)
    static let okBg = Color(hex: 0x16301F)
    static let neutralBg = Color(hex: 0x1F242A)
    static let danger = Color(hex: 0xF07178)
    static let dangerBg = Color(hex: 0x331A1C)

    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .custom("Space Grotesk", size: size).weight(weight)
    }
    static func body(_ size: CGFloat = 14, _ weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: size).weight(weight)
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TF.body(14, .semibold)).foregroundStyle(TF.accentInk)
            .padding(.horizontal, 20).frame(height: 44)
            .background(TF.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SecondaryButton: ButtonStyle {
    var height: CGFloat = 44
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TF.body(14, .medium)).foregroundStyle(TF.text)
            .padding(.horizontal, 16).frame(height: height)
            .background(TF.field.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(TF.fieldLine))
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .background(TF.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(TF.line))
    }
}

struct Chip: View {
    enum Kind { case ok, working, neutral, error }
    let text: String
    let kind: Kind
    var body: some View {
        let (fg, bg): (Color, Color) = switch kind {
        case .ok: (TF.ok, TF.okBg)
        case .working: (TF.accent, TF.accentBg)
        case .neutral: (TF.text2, TF.neutralBg)
        case .error: (TF.danger, TF.dangerBg)
        }
        Text(text).font(TF.body(12, .semibold)).foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(bg, in: Capsule())
    }
}

enum Fmt {
    static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
    static func percent(_ f: Double) -> String { "\(Int((f * 100).rounded())) %" }
    static func duration(_ s: Double) -> String {
        let t = Int(s.rounded()); return String(format: "%d:%02d", t / 60, t % 60)
    }
    static func rate(_ hz: Double) -> String {
        hz == 44100 ? "44,1 kHz" : hz == 48000 ? "48 kHz" : "\(Int(hz)) Hz"
    }
}
