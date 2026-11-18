import Foundation

/// Perfil de equipo global (no es de un proyecto).
public struct EquipmentProfile: Codable, Sendable, Equatable {
    public static let allowedSampleRates: [Double] = [44100, 48000]
    public static let defaultSampleRate: Double = 44100

    /// nil = la app debe preguntar en el primer arranque.
    public var projectsFolder: URL?
    public var workingSampleRate: Double {
        didSet { if !Self.allowedSampleRates.contains(workingSampleRate) { workingSampleRate = Self.defaultSampleRate } }
    }

    /// Volumen global de la pantalla Backing (stems + metrónomo), en dB; igual en todos los temas.
    public var masterGainDB: Double

    /// Dispositivo, canales y calibración de latencia (mini-spec Fase 3). Aditivo: un perfil antiguo no lo trae.
    public var audio: AudioSettings?

    /// Cámara y vídeo (mini-spec Fase 6). Aditivo: un perfil antiguo no lo trae.
    public var video: VideoSettings?

    public init(projectsFolder: URL? = nil, workingSampleRate: Double = EquipmentProfile.defaultSampleRate,
                masterGainDB: Double = 0, audio: AudioSettings? = nil,
                video: VideoSettings? = nil) {
        self.video = video
        self.masterGainDB = masterGainDB
        self.audio = audio
        self.projectsFolder = projectsFolder
        self.workingSampleRate = Self.allowedSampleRates.contains(workingSampleRate) ? workingSampleRate : Self.defaultSampleRate
    }

    /// Un `profile.json` antiguo con `guitars` se lee ignorando la clave y se reescribe sin ella (Fase 7b, punto 10).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(projectsFolder: try c.decodeIfPresent(URL.self, forKey: .projectsFolder),
                  workingSampleRate: try c.decodeIfPresent(Double.self, forKey: .workingSampleRate) ?? Self.defaultSampleRate,
                  masterGainDB: try c.decodeIfPresent(Double.self, forKey: .masterGainDB) ?? 0,
                  audio: try c.decodeIfPresent(AudioSettings.self, forKey: .audio),
                  video: try c.decodeIfPresent(VideoSettings.self, forKey: .video))
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
