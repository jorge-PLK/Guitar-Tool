import Foundation

/// Emparejamiento de un stem de la tablatura con una pista de Songsterr (mini-spec Fase 5b, «Recorrido» 3).
/// `stemID` es `TabSource.id` (`guitar-left`, `bass`, `drums`…); `partId` nil = transcripción automática de ese stem.
public struct TabStemPairing: Codable, Sendable, Equatable {
    public var stemID: String
    public var partId: Int?
    /// Solo el stem solista (decisión de Jorge, 17/11/2026): pista de cada sección de solo; ausente en el JSON de antes
    /// y en los demás stems. Con secciones, `partId` va nil y la pista lleva solo las notas de esas secciones.
    public var solos: [TabSoloPairing]?

    public init(stemID: String, partId: Int?, solos: [TabSoloPairing]? = nil) {
        self.stemID = stemID
        self.partId = partId
        self.solos = solos
    }

    /// Lleva notas de Songsterr: pista entera o alguna sección de solo con pista.
    public var usesSongsterr: Bool { partId != nil || (solos ?? []).contains { $0.partId != nil } }
}

/// Pista de Songsterr de una sección de solo (segundos de canción), con el parecido medido al importar.
public struct TabSoloPairing: Codable, Sendable, Equatable {
    public var start: Double
    public var end: Double
    /// nil = sin notas de Songsterr en esta sección.
    public var partId: Int?
    public var confidence: Double?

    public init(start: Double, end: Double, partId: Int?, confidence: Double?) {
        self.start = start
        self.end = end
        self.partId = partId
        self.confidence = confidence
    }
}

/// Fuente elegida para la tablatura de un tema (mini-spec Fase 5b, «Datos»). Ausente en `Project` = sin elegir.
public enum TabSourceChoice: Codable, Sendable, Equatable {
    /// Songsterr: `songId` + `revisionId` (huella) y el emparejamiento stem → pista.
    case songsterr(songId: Int, revisionId: Int, pairings: [TabStemPairing])
    /// Solo transcripción automática.
    case automatic

    private enum CodingKeys: String, CodingKey { case kind, songId, revisionId, pairings }
    private enum Kind: String, Codable { case songsterr, automatic }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .automatic:
            self = .automatic
        case .songsterr:
            self = .songsterr(songId: try c.decode(Int.self, forKey: .songId),
                              revisionId: try c.decode(Int.self, forKey: .revisionId),
                              pairings: try c.decodeIfPresent([TabStemPairing].self, forKey: .pairings) ?? [])
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .automatic:
            try c.encode(Kind.automatic, forKey: .kind)
        case let .songsterr(songId, revisionId, pairings):
            try c.encode(Kind.songsterr, forKey: .kind)
            try c.encode(songId, forKey: .songId)
            try c.encode(revisionId, forKey: .revisionId)
            try c.encode(pairings, forKey: .pairings)
        }
    }

    /// Pista de Songsterr emparejada con un stem; nil si es automática o el stem no tiene pareja.
    public func partId(forStem stemID: String) -> Int? {
        guard case let .songsterr(_, _, pairings) = self else { return nil }
        return pairings.first { $0.stemID == stemID }?.partId
    }

    /// El stem lleva notas de Songsterr (pista entera o secciones de solo): no lo transcribe la automática.
    public func importsSongsterr(forStem stemID: String) -> Bool {
        guard case let .songsterr(_, _, pairings) = self else { return false }
        return pairings.first { $0.stemID == stemID }?.usesSongsterr ?? false
    }
}
