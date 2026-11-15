import Foundation

/// Calidad de acorde del vocabulario BTC grande, en el orden del modelo
/// (mini-spec Fase 2 §1: min, maj, dim, aug, min6, maj6, min7, minmaj7, maj7, 7, dim7, hdim7, sus2, sus4).
public enum ChordQuality: Int, CaseIterable, Sendable, Codable {
    case min, maj, dim, aug, min6, maj6, min7, minmaj7, maj7, dom7, dim7, hdim7, sus2, sus4

    /// Sufijo en notación de guitarrista («m7», «maj7», «°7»…).
    public var suffix: String {
        switch self {
        case .min: return "m"
        case .maj: return ""
        case .dim: return "°"
        case .aug: return "+"
        case .min6: return "m6"
        case .maj6: return "6"
        case .min7: return "m7"
        case .minmaj7: return "m(maj7)"
        case .maj7: return "maj7"
        case .dom7: return "7"
        case .dim7: return "°7"
        case .hdim7: return "ø7"
        case .sus2: return "sus2"
        case .sus4: return "sus4"
        }
    }

    /// Nombre de calidad al estilo `.lab` (Harte): `C:min`, `C:hdim7`…
    public var labName: String {
        switch self {
        case .min: return "min"
        case .maj: return "maj"
        case .dim: return "dim"
        case .aug: return "aug"
        case .min6: return "min6"
        case .maj6: return "maj6"
        case .min7: return "min7"
        case .minmaj7: return "minmaj7"
        case .maj7: return "maj7"
        case .dom7: return "7"
        case .dim7: return "dim7"
        case .hdim7: return "hdim7"
        case .sus2: return "sus2"
        case .sus4: return "sus4"
        }
    }

    /// Semitonos sobre la raíz de las notas del acorde.
    public var intervals: [Int] {
        switch self {
        case .min: return [0, 3, 7]
        case .maj: return [0, 4, 7]
        case .dim: return [0, 3, 6]
        case .aug: return [0, 4, 8]
        case .min6: return [0, 3, 7, 9]
        case .maj6: return [0, 4, 7, 9]
        case .min7: return [0, 3, 7, 10]
        case .minmaj7: return [0, 3, 7, 11]
        case .maj7: return [0, 4, 7, 11]
        case .dom7: return [0, 4, 7, 10]
        case .dim7: return [0, 3, 6, 9]
        case .hdim7: return [0, 3, 6, 10]
        case .sus2: return [0, 2, 7]
        case .sus4: return [0, 5, 7]
        }
    }
}

/// Etiqueta de acorde: índice 0…169 del vocabulario BTC grande.
/// `índice = raíz × 14 + calidad`; 168 = X (desconocido), 169 = N (sin acorde).
public struct ChordLabel: Hashable, Sendable, Codable {
    public static let qualityCount = 14
    public static let chordCount = 12 * qualityCount   // 168
    public static let unknownIndex = 168
    public static let noChordIndex = 169

    public static let unknown = ChordLabel(uncheckedIndex: unknownIndex)
    public static let noChord = ChordLabel(uncheckedIndex: noChordIndex)

    public let index: Int

    private static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let flatNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    private init(uncheckedIndex: Int) { self.index = uncheckedIndex }

    /// nil si el índice no está en 0…169.
    public init?(index: Int) {
        guard (0...Self.noChordIndex).contains(index) else { return nil }
        self.index = index
    }

    /// `root` se reduce módulo 12 (admite negativos).
    public init(root: Int, quality: ChordQuality) {
        let r = ((root % 12) + 12) % 12
        self.index = r * Self.qualityCount + quality.rawValue
    }

    public var isChord: Bool { index < Self.chordCount }

    /// Clase de altura 0…11 (C = 0); nil para X y N.
    public var root: Int? { isChord ? index / Self.qualityCount : nil }

    public var quality: ChordQuality? { isChord ? ChordQuality(rawValue: index % Self.qualityCount) : nil }

    /// Clases de altura de las notas del acorde (vacío para X y N).
    public var pitchClasses: [Int] {
        guard let r = root, let q = quality else { return [] }
        return q.intervals.map { (r + $0) % 12 }
    }

    /// Nombre legible en notación de guitarrista, sostenidos por defecto («F#m7», «Cø7»).
    public var name: String { name(preferFlats: false) }

    public func name(preferFlats: Bool) -> String {
        guard let r = root, let q = quality else { return index == Self.noChordIndex ? "N" : "X" }
        let names = preferFlats ? Self.flatNames : Self.sharpNames
        return names[r] + q.suffix
    }

    /// Nombre estilo `.lab`: `C:min`, `F#:7`, `X`, `N`.
    public var labName: String {
        guard let r = root, let q = quality else { return index == Self.noChordIndex ? "N" : "X" }
        return Self.sharpNames[r] + ":" + q.labName
    }

    /// Lee `C:min`, `Db:maj7`, `C` (= mayor), `N`, `X`. Ignora el bajo tras `/`. nil si no se reconoce.
    public init?(labName: String) {
        let text = labName.trimmingCharacters(in: .whitespaces)
        if text == "N" { self = .noChord; return }
        if text == "X" { self = .unknown; return }
        let head = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? text
        let parts = head.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let rootText = parts.first, !rootText.isEmpty else { return nil }
        let table = Self.sharpNames
        let root: Int?
        if let i = table.firstIndex(of: rootText) {
            root = i
        } else if let i = Self.flatNames.firstIndex(of: rootText) {
            root = i
        } else {
            root = nil
        }
        guard let root else { return nil }
        let quality: ChordQuality
        if parts.count == 1 {
            quality = .maj
        } else if let q = ChordQuality.allCases.first(where: { $0.labName == parts[1] }) {
            quality = q
        } else {
            return nil
        }
        self.init(root: root, quality: quality)
    }

    /// Sube (o baja, si es negativo) la raíz `semitones`; X y N no cambian.
    public func transposed(by semitones: Int) -> ChordLabel {
        guard let r = root, let q = quality else { return self }
        return ChordLabel(root: r + semitones, quality: q)
    }
}
