import Foundation

/// Grabación con vídeo por partes (mini-spec Fase 6, «Partes y tomas» y «Datos»). Todo aditivo: un proyecto sin
/// `recording` se lee igual. Tiempos en segundos del tema.

public struct RecordingPart: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    /// Pista de guitarra que sustituye; nil = parte añadida.
    public var replaces: GuitarRole?
    /// El montaje de la Fase 7 la enseña solo en los solos.
    public var isLead: Bool
    public var takeIDs: [UUID]
    public var bestTakeID: UUID?

    public init(id: UUID = UUID(), name: String, replaces: GuitarRole? = nil, isLead: Bool? = nil,
                takeIDs: [UUID] = [], bestTakeID: UUID? = nil) {
        self.id = id
        self.name = name
        self.replaces = replaces
        self.isLead = isLead ?? (replaces == .lead)
        self.takeIDs = takeIDs
        self.bestTakeID = bestTakeID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        replaces = try c.decodeIfPresent(GuitarRole.self, forKey: .replaces)
        isLead = try c.decodeIfPresent(Bool.self, forKey: .isLead) ?? (replaces == .lead)
        takeIDs = try c.decodeIfPresent([UUID].self, forKey: .takeIDs) ?? []
        bestTakeID = try c.decodeIfPresent(UUID.self, forKey: .bestTakeID)
    }

    /// Propuesta inicial: una parte por pista de guitarra del proyecto, con su nombre; solista si sustituye a la lead.
    public static func proposed(from guitars: [Guitar]) -> [RecordingPart] {
        guitars.map { RecordingPart(name: $0.name, replaces: $0.role) }
    }

    /// Añade una toma recién grabada: pasa a ser la mejor (la última hasta que se elige otra).
    public mutating func addTake(_ takeID: UUID) {
        if !takeIDs.contains(takeID) { takeIDs.append(takeID) }
        bestTakeID = takeID
    }

    /// Marca como mejor una toma de la parte; false (y sin cambios) si no es suya.
    @discardableResult
    public mutating func setBest(_ takeID: UUID) -> Bool {
        guard takeIDs.contains(takeID) else { return false }
        bestTakeID = takeID
        return true
    }

    /// Quita una toma; si era la mejor, la mejor pasa a la última que quede (nil si no queda ninguna).
    public mutating func removeTake(_ takeID: UUID) {
        takeIDs.removeAll { $0 == takeID }
        if bestTakeID == takeID || (bestTakeID != nil && !takeIDs.contains(bestTakeID!)) { bestTakeID = takeIDs.last }
    }
}

/// Toma de otra parte que suena al grabar («tus tomas anteriores»), como canal «Tú · nombre de la parte».
public struct BackingTake: Sendable, Equatable {
    public var partID: UUID
    public var partName: String
    public var takeID: UUID
    public var channelName: String { "Tú · \(partName)" }
}

/// Volumen (y silencio) del canal «Tú · parte» de Grabar, por id de parte (mini-spec Fase 7, «Exportación»).
public struct PartMix: Codable, Sendable, Equatable {
    public var partID: UUID
    public var gainDB: Double
    public var muted: Bool

    public init(partID: UUID, gainDB: Double = 0, muted: Bool = false) {
        self.partID = partID
        self.gainDB = gainDB
        self.muted = muted
    }
}

public struct RecordingState: Codable, Sendable, Equatable {
    /// Compases de margen admitidos antes de la entrada (mini-spec: 2 por defecto; 1 o sin margen).
    public static let allowedPreRollBars = 0...2
    public static let defaultPreRollBars = 2

    public var parts: [RecordingPart]
    /// Mezcla de Grabar, aparte de la de Backing; la primera vez se copia de `study.mixer`.
    public var mix: [StemMix]
    /// Mezcla de los canales «Tú · parte»; ausente = 0 dB sin silenciar.
    public var partMix: [PartMix]
    public var startSectionID: UUID?
    public var countIn: Bool
    public var preRollBars: Int {
        didSet { preRollBars = Self.clampPreRoll(preRollBars) }
    }

    public init(parts: [RecordingPart] = [], mix: [StemMix] = [], partMix: [PartMix] = [], startSectionID: UUID? = nil,
                countIn: Bool = true, preRollBars: Int = RecordingState.defaultPreRollBars) {
        self.parts = parts
        self.mix = mix
        self.partMix = partMix
        self.startSectionID = startSectionID
        self.countIn = countIn
        self.preRollBars = Self.clampPreRoll(preRollBars)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(parts: try c.decodeIfPresent([RecordingPart].self, forKey: .parts) ?? [],
                  mix: try c.decodeIfPresent([StemMix].self, forKey: .mix) ?? [],
                  partMix: try c.decodeIfPresent([PartMix].self, forKey: .partMix) ?? [],
                  startSectionID: try c.decodeIfPresent(UUID.self, forKey: .startSectionID),
                  countIn: try c.decodeIfPresent(Bool.self, forKey: .countIn) ?? true,
                  preRollBars: try c.decodeIfPresent(Int.self, forKey: .preRollBars) ?? Self.defaultPreRollBars)
    }

    private static func clampPreRoll(_ n: Int) -> Int {
        min(max(n, allowedPreRollBars.lowerBound), allowedPreRollBars.upperBound)
    }

    public func partMix(for partID: UUID) -> PartMix { partMix.first { $0.partID == partID } ?? PartMix(partID: partID) }

    public func part(_ id: UUID) -> RecordingPart? { parts.first { $0.id == id } }

    public func part(containingTake takeID: UUID) -> RecordingPart? { parts.first { $0.takeIDs.contains(takeID) } }

    /// Guitarra del backing que se silencia al grabar esa parte (la que sustituye; nil en una parte añadida).
    public func mutedGuitar(whileRecording partID: UUID) -> GuitarRole? { part(partID)?.replaces }

    /// Mejores tomas de las otras partes, en el orden de las partes; las partes sin toma no suenan.
    public func backingTakes(whileRecording partID: UUID) -> [BackingTake] {
        parts.compactMap { p in
            guard p.id != partID, let best = p.bestTakeID else { return nil }
            return BackingTake(partID: p.id, partName: p.name, takeID: best)
        }
    }

    /// Quita la toma de su parte (si está en alguna) y reasigna la mejor.
    public mutating func removeTake(_ takeID: UUID) {
        for i in parts.indices where parts[i].takeIDs.contains(takeID) || parts[i].bestTakeID == takeID {
            parts[i].removeTake(takeID)
        }
    }
}

extension Project {
    /// Estado de grabación existente, o el inicial: partes propuestas desde las guitarras y mezcla copiada de Backing.
    public func recordingOrInitial() -> RecordingState {
        recording ?? RecordingState(parts: RecordingPart.proposed(from: guitars), mix: study.mixer)
    }

    /// Proyecto degradado: hay tomas con `partID` o `videoFile` pero `recording` no existe o ninguna parte referencia
    /// tomas (p. ej. lo guardó una app sin Fase 6, que descarta `recording`). No se deben fabricar partes por defecto.
    public var hasOrphanedTakes: Bool {
        guard takes.contains(where: { $0.partID != nil || $0.videoFile != nil }) else { return false }
        guard let r = recording else { return true }
        return !r.parts.contains { !$0.takeIDs.isEmpty }
    }

    /// Reconstruye `recording` desde `takes[].partID` (orden de `createdAt`, la mejor = la última). Nombre, `replaces` e
    /// `isLead` no son recuperables: «Parte recuperada N». nil si no hay tomas con `partID` (no inventa nada).
    /// Conserva el resto de `recording` si existía; devuelve el estado, no modifica el proyecto.
    public func reconstructedRecording() -> RecordingState? {
        guard hasOrphanedTakes else { return nil }
        let withPart = takes.enumerated().filter { $0.element.partID != nil }
        guard !withPart.isEmpty else { return nil }
        let groups = Dictionary(grouping: withPart, by: { $0.element.partID! })
        let ordered = groups.values.map { g in
            g.sorted { ($0.element.createdAt, $0.offset) < ($1.element.createdAt, $1.offset) }
        }.sorted { ($0[0].element.createdAt, $0[0].element.partID!.uuidString) < ($1[0].element.createdAt, $1[0].element.partID!.uuidString) }
        let parts = ordered.enumerated().map { i, g in
            RecordingPart(id: g[0].element.partID!, name: "Parte recuperada \(i + 1)", replaces: nil, isLead: false,
                          takeIDs: g.map(\.element.id), bestTakeID: g.last!.element.id)
        }
        var state = recording ?? RecordingState(mix: study.mixer)
        state.parts = parts
        return state
    }

    /// Quita una toma del proyecto: de `takes` y de su parte (reasignando la mejor). No toca disco.
    public mutating func removeTake(_ takeID: UUID) {
        takes.removeAll { $0.id == takeID }
        recording?.removeTake(takeID)
    }
}

/// Fotograma de la cámara con el que se grabó una toma (formato real, no el pedido).
public struct TakeVideoFormat: Codable, Sendable, Equatable {
    public var cameraUID: String
    public var cameraName: String
    public var width: Int
    public var height: Int
    public var fps: Double

    public init(cameraUID: String, cameraName: String, width: Int, height: Int, fps: Double) {
        self.cameraUID = cameraUID
        self.cameraName = cameraName
        self.width = width
        self.height = height
        self.fps = fps
    }
}

/// Tramo regrabado de una toma (mini-spec Fase 6, «Punch-in»); tiempos del tema, ficheros relativos al proyecto.
public struct TakePunch: Codable, Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var processedFile: String?
    public var videoFile: String?
    public var videoOffset: Double?

    public init(start: Double, end: Double, processedFile: String? = nil, videoFile: String? = nil,
                videoOffset: Double? = nil) {
        self.start = start
        self.end = end
        self.processedFile = processedFile
        self.videoFile = videoFile
        self.videoOffset = videoOffset
    }
}
