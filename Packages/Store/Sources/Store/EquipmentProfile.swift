import Foundation

public enum PickupType: String, Codable, Sendable, Equatable {
    case passive, active
}

public struct OwnedGuitar: Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var pickups: PickupType
    public var isDefault: Bool

    public init(id: UUID = UUID(), name: String, pickups: PickupType = .passive, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.pickups = pickups
        self.isDefault = isDefault
    }
}

/// Perfil de equipo global (no es de un proyecto).
public struct EquipmentProfile: Codable, Sendable, Equatable {
    public static let allowedSampleRates: [Double] = [44100, 48000]
    public static let defaultSampleRate: Double = 44100

    /// nil = la app debe preguntar en el primer arranque.
    public var projectsFolder: URL?
    public var workingSampleRate: Double {
        didSet { if !Self.allowedSampleRates.contains(workingSampleRate) { workingSampleRate = Self.defaultSampleRate } }
    }
    public var guitars: [OwnedGuitar] {
        didSet { Self.normalizeDefault(&guitars) }
    }

    /// Volumen global de la pantalla Backing (stems + metrónomo), en dB; igual en todos los temas.
    public var masterGainDB: Double

    /// Dispositivo, canales y calibración de latencia (mini-spec Fase 3). Aditivo: un perfil antiguo no lo trae.
    public var audio: AudioSettings?

    public init(projectsFolder: URL? = nil, workingSampleRate: Double = EquipmentProfile.defaultSampleRate,
                guitars: [OwnedGuitar] = [], masterGainDB: Double = 0, audio: AudioSettings? = nil) {
        self.masterGainDB = masterGainDB
        self.audio = audio
        self.projectsFolder = projectsFolder
        self.workingSampleRate = Self.allowedSampleRates.contains(workingSampleRate) ? workingSampleRate : Self.defaultSampleRate
        var g = guitars
        Self.normalizeDefault(&g)
        self.guitars = g
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(projectsFolder: try c.decodeIfPresent(URL.self, forKey: .projectsFolder),
                  workingSampleRate: try c.decodeIfPresent(Double.self, forKey: .workingSampleRate) ?? Self.defaultSampleRate,
                  guitars: try c.decodeIfPresent([OwnedGuitar].self, forKey: .guitars) ?? [],
                  masterGainDB: try c.decodeIfPresent(Double.self, forKey: .masterGainDB) ?? 0,
                  audio: try c.decodeIfPresent(AudioSettings.self, forKey: .audio))
    }

    /// Como mucho una por defecto: se conserva la primera marcada.
    private static func normalizeDefault(_ g: inout [OwnedGuitar]) {
        var seen = false
        for i in g.indices where g[i].isDefault {
            if seen { g[i].isDefault = false } else { seen = true }
        }
    }

    /// Marca `id` como la guitarra por defecto (desmarca las demás).
    public mutating func setDefaultGuitar(_ id: UUID) {
        for i in guitars.indices { guitars[i].isDefault = (guitars[i].id == id) }
    }
}

public struct ProfileStore: Sendable {
    public let url: URL

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("ToneForge/profile.json")
    }

    public init(url: URL = ProfileStore.defaultURL) { self.url = url }

    /// Si el fichero no existe devuelve el perfil por defecto.
    public func load() throws -> EquipmentProfile {
        guard FileManager.default.fileExists(atPath: url.path) else { return EquipmentProfile() }
        return try ProjectFile.makeDecoder().decode(EquipmentProfile.self, from: Data(contentsOf: url))
    }

    public func save(_ profile: EquipmentProfile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileOps.atomicWrite(ProjectFile.makeEncoder().encode(profile), to: url)
    }
}
