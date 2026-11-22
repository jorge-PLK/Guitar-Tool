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
    /// Colores de sección apagados para el tema oscuro (sin naranja: es de los solos). El orden es el de
    /// `SectionEditor.paletteCount`: azul, verde, violeta, rosa, turquesa, lima, coral.
    static let sectionPalette: [Color] = [0x6C9BD2, 0x6FB58A, 0x9C86C9, 0xC97F9E, 0x5DB5B5, 0xA6B85C, 0xC8706A].map { Color(hex: $0) }
    static let danger = Color(hex: 0xF07178)
    static let dangerBg = Color(hex: 0x331A1C)

    /// Fuentes del diseño, empaquetadas en App/Resources/Fonts (mismos TTF que la web de Windows). Solo existen
    /// estas caras, así que cada peso pedido se mapea a una que existe y se pide por nombre PostScript
    /// (`.custom(...).weight()` sobre una fuente sin variable no cambia de cara).
    ///
    /// Peso pedido -> cara usada (la interfaz de Windows usa la misma tabla):
    ///   display (familia "Space Grotesk"; PostScript SpaceGroteskLight-*):
    ///     .ultraLight .thin .light .regular .medium -> 500 (SpaceGroteskLight-Medium)
    ///     .semibold .bold .heavy .black             -> 700 (SpaceGroteskLight-Bold)
    ///   body (familia "Inter"):
    ///     .ultraLight .thin .light .regular         -> 400 (Inter-Regular)
    ///     .medium                                   -> 500 (Inter-Medium)
    ///     .semibold .bold .heavy .black             -> 600 (Inter-SemiBold)
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        switch weight {
        case .semibold, .bold, .heavy, .black: .custom("SpaceGroteskLight-Bold", size: size)
        default: .custom("SpaceGroteskLight-Medium", size: size)
        }
    }
    static func body(_ size: CGFloat = 14, _ weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .semibold, .bold, .heavy, .black: .custom("Inter-SemiBold", size: size)
        case .medium: .custom("Inter-Medium", size: size)
        default: .custom("Inter-Regular", size: size)
        }
    }
}

struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TF.body(14, .semibold)).foregroundStyle(isEnabled ? TF.accentInk : TF.muted)
            .padding(.horizontal, 20).frame(height: 44)
            .background(isEnabled ? TF.accent.opacity(configuration.isPressed ? 0.8 : 1) : TF.neutralBg,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isEnabled ? .clear : TF.fieldLine))
    }
}

struct SecondaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = 44
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TF.body(14, .medium)).foregroundStyle(isEnabled ? TF.text : TF.muted)
            .padding(.horizontal, 16).frame(height: height)
            .background(TF.field.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(TF.fieldLine))
            .opacity(isEnabled ? 1 : 0.6)
    }
}

/// Barra de progreso en el color de acento (la `ProgressView` lineal sale gris con la ventana inactiva).
/// Sin valor, un tramo que va y viene.
struct AccentBar: View {
    var value: Double?
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(TF.field)
                if let v = value {
                    Capsule().fill(TF.accent).frame(width: max(height, geo.size.width * min(1, max(0, v))))
                } else {
                    TimelineView(.animation) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        let w = geo.size.width * 0.3
                        Capsule().fill(TF.accent).frame(width: w)
                            .offset(x: (geo.size.width - w) * (0.5 - 0.5 * cos(t * 2 * .pi)))
                    }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
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
