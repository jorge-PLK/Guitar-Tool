/// Afinaciones del selector por pista (mini-spec Fase 5, decisión 5).
public enum TuningPreset: String, Codable, Sendable, CaseIterable {
    case standard
    case halfStepDown
    case wholeStepDown
    case dropD
    /// Alturas exactas de cada cuerda que no son ningún preset (Do estándar, 7 cuerdas…; mini-spec Fase 5b,
    /// decisión 7). Las alturas viven en `Tuning.strings`; un fichero anterior sin este caso se lee igual.
    case custom

    /// Los presets que se pueden construir sin más datos (todos menos `custom`).
    public static var fixed: [TuningPreset] { allCases.filter { $0 != .custom } }
}

/// Afinación de una pista: alturas MIDI al aire de la cuerda 1 (la más aguda) a la última.
public struct Tuning: Codable, Sendable, Hashable {
    public var preset: TuningPreset
    public var strings: [Int]

    public init(preset: TuningPreset, strings: [Int]) {
        self.preset = preset
        self.strings = strings
    }

    /// Trastes válidos (mini-spec Fase 5, «Cuerdas y trastes»).
    public static let fretRange = 0...24

    /// EADGBE = E4 B3 G3 D3 A2 E2 desde la cuerda 1.
    static let guitarStandard = [64, 59, 55, 50, 45, 40]
    /// EADG = G2 D2 A1 E1 desde la cuerda 1.
    static let bassStandard = [43, 38, 33, 28]

    public static func guitar(_ preset: TuningPreset) -> Tuning {
        Tuning(preset: preset, strings: apply(preset, to: guitarStandard))
    }

    public static func bass(_ preset: TuningPreset) -> Tuning {
        Tuning(preset: preset, strings: apply(preset, to: bassStandard))
    }

    /// Medio tono y un tono bajan todas las cuerdas; drop D baja solo la más grave un tono.
    static func apply(_ preset: TuningPreset, to standard: [Int]) -> [Int] {
        switch preset {
        case .standard, .custom: return standard
        case .halfStepDown: return standard.map { $0 - 1 }
        case .wholeStepDown: return standard.map { $0 - 2 }
        case .dropD: return standard.dropLast() + [standard[standard.count - 1] - 2]
        }
    }

    /// Una afinación personalizada con las alturas exactas de cada cuerda (cuerda 1 la más aguda).
    public static func custom(strings: [Int]) -> Tuning { Tuning(preset: .custom, strings: strings) }

    /// Notas de las cuerdas de la más grave a la más aguda, p. ej. «C G C F A D» (nombres en inglés, con sostenidos).
    public var noteNames: [String] {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return strings.reversed().map { names[(($0 % 12) + 12) % 12] }
    }

    /// «Personalizada (C G C F A D)» para el selector.
    public var customLabel: String { "Personalizada (\(noteNames.joined(separator: " ")))" }

    /// Altura más grave y más aguda tocables (cuerda al aire más grave, traste 24 de la más aguda).
    public var lowestPitch: Int { strings.min() ?? 0 }
    public var highestPitch: Int { (strings.max() ?? 0) + Self.fretRange.upperBound }
}
