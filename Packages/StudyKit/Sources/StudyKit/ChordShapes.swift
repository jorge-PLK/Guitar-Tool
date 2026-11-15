import Foundation

/// Diagrama de acorde de guitarra en afinación estándar (E A D G B E).
public struct ChordShape: Hashable, Sendable {
    /// Cejilla: traste y cuerdas cubiertas (numeradas como en guitarra: 6 = Mi grave, 1 = Mi agudo).
    public struct Barre: Hashable, Sendable {
        public let fret: Int
        public let fromString: Int
        public let toString: Int
    }

    /// Traste de cada cuerda, de la 6.ª a la 1.ª (índice 0 = 6.ª). 0 = al aire, nil = muteada.
    public let frets: [Int?]
    /// Dedo (1…4) de cada cuerda en el mismo orden; nil si no se indica. Las formas generadas no lo traen.
    public let fingers: [Int?]?
    /// Traste inicial del diagrama (1 si todo cabe en los 4 primeros trastes).
    public let baseFret: Int
    public let barre: Barre?

    public init(frets: [Int?], fingers: [Int?]? = nil, barre: Barre? = nil) {
        precondition(frets.count == 6, "Una forma tiene 6 cuerdas")
        self.frets = frets
        self.fingers = fingers
        self.barre = barre
        let pressed = frets.compactMap { $0 }.filter { $0 > 0 }
        if let maxFret = pressed.max(), maxFret > 4, let minFret = pressed.min() {
            baseFret = minFret
        } else {
            baseFret = 1
        }
    }

    /// Clase de altura sonando en cada cuerda (nil si muteada).
    public var pitchClasses: [Int?] {
        zip(frets, ChordShapes.openStrings).map { fret, open in fret.map { (open + $0) % 12 } }
    }
}

/// Tabla de formas de acorde. Datos revisables abajo: formas abiertas explícitas y plantillas de cejilla
/// tipo E (raíz en la 6.ª) y tipo A (raíz en la 5.ª) para el resto. Mini-spec Fase 2 §1.
public enum ChordShapes {
    /// Clases de altura de las cuerdas al aire, 6.ª a 1.ª: E A D G B E.
    public static let openStrings = [4, 9, 2, 7, 11, 4]

    /// Forma del acorde con capo `capo` (cejilla virtual): la de la etiqueta transpuesta −capo semitonos.
    /// nil para X y N.
    public static func shape(for label: ChordLabel, capo: Int = 0) -> ChordShape? {
        let l = label.transposed(by: -capo)
        guard let root = l.root, let quality = l.quality else { return nil }
        if let open = openShapes[OpenKey(root: root, quality: quality)] {
            return ChordShape(frets: open)
        }
        var candidates: [ChordShape] = []
        if let t = eForm[quality] { candidates.append(barreShape(template: t, firstString: 6, rootFret: (root - 4 + 12) % 12)) }
        if let t = aForm[quality] { candidates.append(barreShape(template: t, firstString: 5, rootFret: (root - 9 + 12) % 12)) }
        return candidates.min { lowest($0) < lowest($1) }
    }

    // MARK: - Datos

    private struct OpenKey: Hashable { let root: Int; let quality: ChordQuality }

    /// Formas abiertas (6.ª a 1.ª; nil = muteada). Solo las que no salen de una plantilla con traste 0.
    private static let openShapes: [OpenKey: [Int?]] = [
        // C = 0
        OpenKey(root: 0, quality: .maj): [nil, 3, 2, 0, 1, 0],
        OpenKey(root: 0, quality: .dom7): [nil, 3, 2, 3, 1, 0],
        OpenKey(root: 0, quality: .maj7): [nil, 3, 2, 0, 0, 0],
        OpenKey(root: 0, quality: .sus2): [nil, 3, 0, 0, 1, 3],
        // D = 2
        OpenKey(root: 2, quality: .maj): [nil, nil, 0, 2, 3, 2],
        OpenKey(root: 2, quality: .min): [nil, nil, 0, 2, 3, 1],
        OpenKey(root: 2, quality: .dim): [nil, nil, 0, 1, 3, 1],
        OpenKey(root: 2, quality: .min6): [nil, nil, 0, 2, 0, 1],
        OpenKey(root: 2, quality: .maj6): [nil, nil, 0, 2, 0, 2],
        OpenKey(root: 2, quality: .min7): [nil, nil, 0, 2, 1, 1],
        OpenKey(root: 2, quality: .minmaj7): [nil, nil, 0, 2, 2, 1],
        OpenKey(root: 2, quality: .maj7): [nil, nil, 0, 2, 2, 2],
        OpenKey(root: 2, quality: .dom7): [nil, nil, 0, 2, 1, 2],
        OpenKey(root: 2, quality: .dim7): [nil, nil, 0, 1, 0, 1],
        OpenKey(root: 2, quality: .hdim7): [nil, nil, 0, 1, 1, 1],
        OpenKey(root: 2, quality: .sus2): [nil, nil, 0, 2, 3, 0],
        OpenKey(root: 2, quality: .sus4): [nil, nil, 0, 2, 3, 3],
        // F = 5
        OpenKey(root: 5, quality: .maj7): [nil, nil, 3, 2, 1, 0],
        // G = 7
        OpenKey(root: 7, quality: .maj): [3, 2, 0, 0, 0, 3],
        OpenKey(root: 7, quality: .dom7): [3, 2, 0, 0, 0, 1],
        OpenKey(root: 7, quality: .maj7): [3, 2, 0, 0, 0, 2],
        OpenKey(root: 7, quality: .maj6): [3, 2, 0, 0, 0, 0],
    ]

    /// Plantillas: traste relativo al de la raíz (0 = cejilla / al aire si la raíz cae al aire).
    /// Tipo E: 6.ª a 1.ª, raíz en la 6.ª (traste = raíz − E).
    private static let eForm: [ChordQuality: [Int?]] = [
        .maj: [0, 2, 2, 1, 0, 0],
        .min: [0, 2, 2, 0, 0, 0],
        .dim: [0, 1, 2, 0, nil, nil],
        .aug: [0, 3, 2, 1, 1, 0],
        .min6: [0, 2, 2, 0, 2, 0],
        .maj6: [0, 2, 2, 1, 2, 0],
        .min7: [0, 2, 0, 0, 0, 0],
        .minmaj7: [0, 2, 1, 0, 0, 0],
        .maj7: [0, 2, 1, 1, 0, 0],
        .dom7: [0, 2, 0, 1, 0, 0],
        .dim7: [0, 1, 2, 0, 2, nil],
        .hdim7: [0, 1, 0, 0, nil, nil],
        .sus4: [0, 2, 2, 2, 0, 0],
        // sus2 no tiene forma tipo E con apertura ≤ 4 trastes: se usa la tipo A.
    ]

    /// Tipo A: raíz en la 5.ª (traste = raíz − A), 6.ª muteada.
    private static let aForm: [ChordQuality: [Int?]] = [
        .maj: [nil, 0, 2, 2, 2, 0],
        .min: [nil, 0, 2, 2, 1, 0],
        .dim: [nil, 0, 1, 2, 1, nil],
        .aug: [nil, 0, 3, 2, 2, 1],
        .min6: [nil, 0, 2, 2, 1, 2],
        .maj6: [nil, 0, 2, 2, 2, 2],
        .min7: [nil, 0, 2, 0, 1, 0],
        .minmaj7: [nil, 0, 2, 1, 1, 0],
        .maj7: [nil, 0, 2, 1, 2, 0],
        .dom7: [nil, 0, 2, 0, 2, 0],
        .dim7: [nil, 0, 1, 2, 1, 2],
        .hdim7: [nil, 0, 1, 0, 1, nil],
        .sus2: [nil, 0, 2, 2, 0, 0],
        .sus4: [nil, 0, 2, 2, 3, 0],
    ]

    private static func barreShape(template: [Int?], firstString: Int, rootFret: Int) -> ChordShape {
        let frets = template.map { $0.map { $0 + rootFret } }
        var barre: ChordShape.Barre?
        if rootFret > 0 {
            // Cejilla hasta la última cuerda con offset 0 (si hay al menos dos).
            let zeros = template.enumerated().filter { $0.element == 0 }.map { 6 - $0.offset }
            if zeros.count >= 2, let last = zeros.min() {
                barre = ChordShape.Barre(fret: rootFret, fromString: firstString, toString: last)
            }
        }
        return ChordShape(frets: frets, barre: barre)
    }

    /// Traste más alto usado (criterio para elegir la forma más cercana al mástil).
    private static func lowest(_ shape: ChordShape) -> Int {
        shape.frets.compactMap { $0 }.max() ?? 0
    }
}
