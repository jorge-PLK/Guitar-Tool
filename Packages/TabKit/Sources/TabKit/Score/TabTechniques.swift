import Foundation

/// Técnicas de una nota de guitarra o bajo (Fase 5b, adornos de Songsterr). Nombres y valores siguen el modelo de
/// alphaTab (`model.Note` y `model.Beat`), que es el de Guitar Pro, para que la tablatura y la exportación las copien
/// tal cual. Las que alphaTab guarda en el beat (`tapping`, `tremoloPicking`, `whammy`, `pickStroke`, `brush`) van en
/// cada nota del acorde.
///
/// Codable aditivo: solo se escriben las que están puestas y un JSON sin alguna (o sin ninguna) la lee como ausente.
public struct TabTechniques: Codable, Sendable, Equatable {
    /// `Note.isPalmMute`.
    public var palmMute = false
    /// `Note.isLetRing`.
    public var letRing = false
    /// `Note.vibrato`.
    public var vibrato: TabVibrato?
    /// `Note.bendType` + `Note.bendPoints`.
    public var bend: TabBend?
    /// `Note.slideInType`.
    public var slideIn: TabSlideIn?
    /// `Note.slideOutType` (shift y legato van hasta la siguiente nota de la misma cuerda).
    public var slideOut: TabSlideOut?
    /// Ligado (hammer-on o pull-off) hacia la siguiente nota de la misma cuerda: `Note.isHammerPullOrigin`.
    public var hammerPull = false
    /// `Note.harmonicType` + `Note.harmonicValue`.
    public var harmonic: TabHarmonic?
    /// Nota muerta (x): `Note.isDead`.
    public var dead = false
    /// `Note.isGhost`.
    public var ghost = false
    /// `Note.accentuated`.
    public var accent: TabAccent?
    /// `Note.isStaccato`.
    public var staccato = false
    /// Tapping con la mano derecha: `Beat.tap`.
    public var tapping = false
    /// Trémolo de púa: `Beat.tremoloSpeed`.
    public var tremoloPicking: TabTremoloSpeed?
    /// Palanca: `Beat.whammyBarType` + `Beat.whammyBarPoints` (mismos puntos que un bend; valores negativos = hacia abajo).
    public var whammy: TabBend?
    /// Púa abajo o arriba: `Beat.pickStroke`.
    public var pickStroke: TabStrokeDirection?
    /// Rasgueo: `Beat.brushType` (`brushDown` / `brushUp`).
    public var brush: TabStrokeDirection?
    /// Notas de adorno delante de esta, en orden: los beats de adorno de alphaTab (`Beat.graceType`), sin tiempo propio
    /// en la rejilla. Cada una dice en qué beat de adorno va (`TabGrace.step`) y en qué cuerda (`TabGrace.string`, nil =
    /// la de esta nota). Las de otra cuerda sin nota principal en la suya (rastrillos) van en la nota del acorde de la
    /// cuerda más cercana. Las de todas las notas del acorde con el mismo `step` forman un beat de adorno.
    public var graces: [TabGrace] = []

    public init() {}

    public var isEmpty: Bool { self == TabTechniques() }

    /// Las técnicas puestas, en el orden de `TabTechniqueKind`.
    public var kinds: [TabTechniqueKind] {
        TabTechniqueKind.allCases.filter { k in
            switch k {
            case .palmMute: palmMute
            case .letRing: letRing
            case .vibrato: vibrato != nil
            case .bend: bend != nil
            case .slide: slideIn != nil || slideOut != nil
            case .hammerPull: hammerPull
            case .harmonic: harmonic != nil
            case .dead: dead
            case .ghost: ghost
            case .accent: accent != nil
            case .staccato: staccato
            case .tapping: tapping
            case .tremoloPicking: tremoloPicking != nil
            case .whammy: whammy != nil
            case .pickStroke: pickStroke != nil
            case .brush: brush != nil
            case .grace: !graces.isEmpty
            }
        }
    }

    /// `grace`: la nota de adorno única de antes (Fase 5b, primera versión), que se sigue leyendo como `graces` de una.
    private enum CodingKeys: String, CodingKey {
        case palmMute, letRing, vibrato, bend, slideIn, slideOut, hammerPull, harmonic, dead, ghost, accent, staccato
        case tapping, tremoloPicking, whammy, pickStroke, brush, graces, grace
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        palmMute = try c.decodeIfPresent(Bool.self, forKey: .palmMute) ?? false
        letRing = try c.decodeIfPresent(Bool.self, forKey: .letRing) ?? false
        vibrato = try c.decodeIfPresent(TabVibrato.self, forKey: .vibrato)
        bend = try c.decodeIfPresent(TabBend.self, forKey: .bend)
        slideIn = try c.decodeIfPresent(TabSlideIn.self, forKey: .slideIn)
        slideOut = try c.decodeIfPresent(TabSlideOut.self, forKey: .slideOut)
        hammerPull = try c.decodeIfPresent(Bool.self, forKey: .hammerPull) ?? false
        harmonic = try c.decodeIfPresent(TabHarmonic.self, forKey: .harmonic)
        dead = try c.decodeIfPresent(Bool.self, forKey: .dead) ?? false
        ghost = try c.decodeIfPresent(Bool.self, forKey: .ghost) ?? false
        accent = try c.decodeIfPresent(TabAccent.self, forKey: .accent)
        staccato = try c.decodeIfPresent(Bool.self, forKey: .staccato) ?? false
        tapping = try c.decodeIfPresent(Bool.self, forKey: .tapping) ?? false
        tremoloPicking = try c.decodeIfPresent(TabTremoloSpeed.self, forKey: .tremoloPicking)
        whammy = try c.decodeIfPresent(TabBend.self, forKey: .whammy)
        pickStroke = try c.decodeIfPresent(TabStrokeDirection.self, forKey: .pickStroke)
        brush = try c.decodeIfPresent(TabStrokeDirection.self, forKey: .brush)
        graces = try c.decodeIfPresent([TabGrace].self, forKey: .graces)
            ?? (try c.decodeIfPresent(TabGrace.self, forKey: .grace)).map { [$0] } ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        func flag(_ v: Bool, _ k: CodingKeys) throws { if v { try c.encode(true, forKey: k) } }
        try flag(palmMute, .palmMute)
        try flag(letRing, .letRing)
        try c.encodeIfPresent(vibrato, forKey: .vibrato)
        try c.encodeIfPresent(bend, forKey: .bend)
        try c.encodeIfPresent(slideIn, forKey: .slideIn)
        try c.encodeIfPresent(slideOut, forKey: .slideOut)
        try flag(hammerPull, .hammerPull)
        try c.encodeIfPresent(harmonic, forKey: .harmonic)
        try flag(dead, .dead)
        try flag(ghost, .ghost)
        try c.encodeIfPresent(accent, forKey: .accent)
        try flag(staccato, .staccato)
        try flag(tapping, .tapping)
        try c.encodeIfPresent(tremoloPicking, forKey: .tremoloPicking)
        try c.encodeIfPresent(whammy, forKey: .whammy)
        try c.encodeIfPresent(pickStroke, forKey: .pickStroke)
        try c.encodeIfPresent(brush, forKey: .brush)
        if !graces.isEmpty { try c.encode(graces, forKey: .graces) }
    }
}

/// Nota de adorno (`GraceType` de alphaTab): va en una nota principal, sin ocupar tiempo.
public struct TabGrace: Codable, Sendable, Hashable {
    /// `GraceType` de alphaTab (sin `none`).
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case beforeBeat, onBeat, bendGrace
    }

    /// Traste de la nota de adorno (en `string`; en un flam de batería, su nota de percusión GM).
    public var fret: Int
    /// Cuerda (1 = la más aguda, como `TabNote.string`) si no es la de la nota principal que la lleva; nil = la misma.
    public var string: Int?
    /// Beat de adorno donde va, contando hacia atrás desde la principal: 1 = el inmediatamente anterior, 2 = el de
    /// antes… (un rastrillo de dos notas: 2 y 1). En el JSON solo si no es 1.
    public var step: Int
    public var type: Kind
    /// Figura: 32 = fusa, 16 = semicorchea, 8…; nil = la de por defecto.
    public var duration: Int?
    /// Slide de la nota de adorno a la principal.
    public var slide: Bool
    /// Ligado (hammer-on o pull-off) de la nota de adorno a la principal.
    public var hammerPull: Bool
    /// Nota de adorno muerta (x).
    public var dead: Bool

    public init(fret: Int, type: Kind, duration: Int? = nil, slide: Bool = false, hammerPull: Bool = false,
                dead: Bool = false, string: Int? = nil, step: Int = 1) {
        self.fret = fret
        self.string = string
        self.step = step
        self.type = type
        self.duration = duration
        self.slide = slide
        self.hammerPull = hammerPull
        self.dead = dead
    }

    private enum CodingKeys: String, CodingKey { case fret, string, step, type, duration, slide, hammerPull, dead }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fret = try c.decode(Int.self, forKey: .fret)
        string = try c.decodeIfPresent(Int.self, forKey: .string)
        step = max(1, try c.decodeIfPresent(Int.self, forKey: .step) ?? 1)
        type = try c.decode(Kind.self, forKey: .type)
        duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        slide = try c.decodeIfPresent(Bool.self, forKey: .slide) ?? false
        hammerPull = try c.decodeIfPresent(Bool.self, forKey: .hammerPull) ?? false
        dead = try c.decodeIfPresent(Bool.self, forKey: .dead) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fret, forKey: .fret)
        try c.encodeIfPresent(string, forKey: .string)
        if step != 1 { try c.encode(step, forKey: .step) }
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(duration, forKey: .duration)
        if slide { try c.encode(true, forKey: .slide) }
        if hammerPull { try c.encode(true, forKey: .hammerPull) }
        if dead { try c.encode(true, forKey: .dead) }
    }
}

/// Tipo de técnica, para recuentos y avisos.
public enum TabTechniqueKind: String, Codable, Sendable, CaseIterable {
    case palmMute, letRing, vibrato, bend, slide, hammerPull, harmonic, dead, ghost, accent, staccato, tapping
    case tremoloPicking, whammy, pickStroke, brush, grace
}

/// `VibratoType` de alphaTab (sin `none`).
public enum TabVibrato: String, Codable, Sendable, CaseIterable {
    case slight, wide
}

/// `SlideInType` de alphaTab (sin `none`).
public enum TabSlideIn: String, Codable, Sendable, CaseIterable {
    case intoFromBelow, intoFromAbove
}

/// `SlideOutType` de alphaTab (sin `none`).
public enum TabSlideOut: String, Codable, Sendable, CaseIterable {
    case shift, legato, outUp, outDown, pickSlideDown, pickSlideUp
}

/// `HarmonicType` de alphaTab (sin `none`).
public enum TabHarmonicType: String, Codable, Sendable, CaseIterable {
    case natural, artificial, pinch, tap, semi, feedback
}

public struct TabHarmonic: Codable, Sendable, Equatable {
    public var type: TabHarmonicType
    /// Traste donde suena el armónico (`Note.harmonicValue`; 2.4, 3.2… en naturales). nil si la fuente no lo trae.
    public var fret: Double?

    public init(type: TabHarmonicType, fret: Double? = nil) {
        self.type = type
        self.fret = fret
    }
}

/// `AccentuationType` de alphaTab (sin `none`).
public enum TabAccent: String, Codable, Sendable, CaseIterable {
    case normal, heavy, tenuto

    /// El que más pesa de dos acentos del mismo golpe (fuerte > normal > tenuto > ninguno).
    static func stronger(_ a: TabAccent?, _ b: TabAccent?) -> TabAccent? {
        let rank: [TabAccent?] = [nil, .tenuto, .normal, .heavy]
        return (rank.firstIndex(of: a) ?? 0) >= (rank.firstIndex(of: b) ?? 0) ? a : b
    }
}

/// Figura de cada golpe del trémolo de púa (`Beat.tremoloSpeed`: corchea, semicorchea, fusa).
public enum TabTremoloSpeed: Int, Codable, Sendable, CaseIterable {
    case eighth = 8
    case sixteenth = 16
    case thirtySecond = 32
}

/// Sentido de la púa o del rasgueo (`PickStroke` / `BrushType` de alphaTab).
public enum TabStrokeDirection: String, Codable, Sendable, CaseIterable {
    case down, up
}

/// Bend (o palanca) como en alphaTab y Guitar Pro: tipo y curva sobre la duración de la nota.
public struct TabBend: Codable, Sendable, Equatable {
    /// Posición final de la curva (`BendPoint.MaxPosition` de alphaTab, la de Guitar Pro).
    public static let maxPosition = 60
    /// Cuartos de tono por tono entero (`BendPoint.value` de alphaTab: 4 = bend de un tono).
    public static let quarterTonesPerTone = 4

    /// `BendType` de alphaTab (sin `none`).
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case custom, bend, release, bendRelease, hold, prebend, prebendBend, prebendRelease
    }

    public var type: Kind
    /// Ordenados por posición; al menos dos.
    public var points: [TabBendPoint]

    public init(type: Kind, points: [TabBendPoint]) {
        self.type = type
        self.points = points
    }

    /// Bend con el tipo deducido de la curva (como lo dibujaría Guitar Pro); nil si la curva no se mueve de 0.
    public init?(points: [TabBendPoint]) {
        guard points.count >= 2, points.contains(where: { $0.value != 0 }) else { return nil }
        self.init(type: Self.kind(of: points.map(\.value)), points: points)
    }

    /// Sube desde 0 (bend), sube y baja (bend-release), sale doblada (pre-bend, quieta, subiendo o bajando);
    /// cualquier otra forma es `custom`.
    static func kind(of v: [Int]) -> Kind {
        let first = v[0], last = v[v.count - 1], top = v.max() ?? 0
        let rising = zip(v, v.dropFirst()).allSatisfy { $0 <= $1 }
        let falling = zip(v, v.dropFirst()).allSatisfy { $0 >= $1 }
        if first == 0 {
            if rising { return .bend }
            let peak = v.firstIndex(of: top) ?? 0
            let up = v[...peak], down = v[peak...]
            let unimodal = zip(up, up.dropFirst()).allSatisfy { $0 <= $1 }
                && zip(down, down.dropFirst()).allSatisfy { $0 >= $1 }
            return unimodal && last < top ? .bendRelease : .custom
        }
        if rising && falling { return .prebend }
        if rising { return .prebendBend }
        if falling { return .prebendRelease }
        return .custom
    }
}

public struct TabBendPoint: Codable, Sendable, Hashable {
    /// 0…`TabBend.maxPosition` a lo largo de la duración de la nota.
    public var position: Int
    /// Cuartos de tono sobre la nota pisada (4 = un tono).
    public var value: Int

    public init(position: Int, value: Int) {
        self.position = position
        self.value = value
    }
}
