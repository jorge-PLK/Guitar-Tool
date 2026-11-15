import Foundation

/// Modelo de `project.json` (spec: proyecto = carpeta; project.json es la fuente de verdad).

public enum SeparationStatus: String, Codable, Sendable, Equatable {
    case none, queued, running, done, failed
}

public struct SeparationState: Codable, Sendable, Equatable {
    public var state: SeparationStatus
    /// p. ej. `bs-roformer-sw@gridshift-fp16`
    public var model: String?
    public var finishedAt: Date?
    public var error: String?

    public init(state: SeparationStatus = .none, model: String? = nil, finishedAt: Date? = nil, error: String? = nil) {
        self.state = state
        self.model = model
        self.finishedAt = finishedAt
        self.error = error
    }
}

/// rawValue = nombre de fichero sin extensión; el orden de `allCases` es el canónico.
public enum StemKind: String, Codable, Sendable, Equatable, CaseIterable {
    case bass, drums, other, vocals, guitar, piano
}

public struct Stem: Codable, Sendable, Equatable {
    public var kind: StemKind
    /// Ruta relativa a la carpeta del proyecto (`stems/drums.wav`).
    public var file: String
    /// Stem silencioso (mini-spec Fase 2, «Stems vacíos»): su WAV se borró y no cuenta como separación dañada.
    public var isEmpty: Bool
    /// Ya se midió su nivel (así los proyectos separados antes se miden una sola vez al abrirlos).
    public var levelMeasured: Bool

    public init(kind: StemKind, file: String, isEmpty: Bool = false, levelMeasured: Bool = false) {
        self.kind = kind
        self.file = file
        self.isEmpty = isEmpty
        self.levelMeasured = levelMeasured
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(StemKind.self, forKey: .kind)
        file = try c.decode(String.self, forKey: .file)
        isEmpty = try c.decodeIfPresent(Bool.self, forKey: .isEmpty) ?? false
        levelMeasured = try c.decodeIfPresent(Bool.self, forKey: .levelMeasured) ?? false
    }
}

/// Origen de un tema importado desde un enlace (mini-spec Fase 2b, «Datos»). Los campos que pueden faltar son opcionales.
public struct SongOrigin: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case youtube, spotify
    }

    public var kind: Kind
    /// El enlace pegado.
    public var url: String
    public var videoID: String?
    public var channel: String?
    public var spotifyID: String?
    public var album: String?
    /// Relativa: `source/cover.jpg`.
    public var artwork: String?
    public var codec: String?
    public var ytDlpVersion: String?
    public var importedAt: Date
    /// Lista de la que vino el tema (mini-spec Fase 2b, «Listas»). Aditivo: sin ella no se escribe la clave.
    public var playlistID: String?
    public var playlistName: String?

    public init(kind: Kind, url: String, videoID: String? = nil, channel: String? = nil, spotifyID: String? = nil,
                album: String? = nil, artwork: String? = nil, codec: String? = nil, ytDlpVersion: String? = nil,
                importedAt: Date = Date(), playlistID: String? = nil, playlistName: String? = nil) {
        self.playlistID = playlistID
        self.playlistName = playlistName
        self.kind = kind
        self.url = url
        self.videoID = videoID
        self.channel = channel
        self.spotifyID = spotifyID
        self.album = album
        self.artwork = artwork
        self.codec = codec
        self.ytDlpVersion = ytDlpVersion
        self.importedAt = importedAt
    }
}

public struct Song: Codable, Sendable, Equatable {
    public var title: String
    public var artist: String?
    /// Relativa: `source/original.mp3`.
    public var source: String
    public var sourceSHA256: String
    public var sourceFormat: String
    public var sourceSampleRate: Double
    public var sourceChannels: Int
    /// Relativa: `audio/song.wav`.
    public var audio: String
    /// Frecuencia ACTUAL de los ficheros de trabajo (44100 o 48000).
    public var sampleRate: Double
    /// Segundos.
    public var duration: Double
    /// Solo si el tema vino de un enlace (mini-spec Fase 2b, «Datos»). Aditivo: no sube `schemaVersion`.
    public var origin: SongOrigin?

    public init(title: String, artist: String? = nil, source: String, sourceSHA256: String, sourceFormat: String,
                sourceSampleRate: Double, sourceChannels: Int, audio: String = ProjectLayout.audioRelativePath,
                sampleRate: Double, duration: Double, origin: SongOrigin? = nil) {
        self.origin = origin
        self.title = title
        self.artist = artist
        self.source = source
        self.sourceSHA256 = sourceSHA256
        self.sourceFormat = sourceFormat
        self.sourceSampleRate = sourceSampleRate
        self.sourceChannels = sourceChannels
        self.audio = audio
        self.sampleRate = sampleRate
        self.duration = duration
    }
}

// MARK: - Entidades de fases futuras (campos mínimos; opcionales para poder crecer)

public struct Guitar: Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var stem: StemKind?
    public var side: String?
    public var role: String?

    public init(id: UUID = UUID(), name: String, stem: StemKind? = nil, side: String? = nil, role: String? = nil) {
        self.id = id
        self.name = name
        self.stem = stem
        self.side = side
        self.role = role
    }
}

public struct Section: Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var start: Double
    public var end: Double
    public var kind: String?

    public init(id: UUID = UUID(), name: String, start: Double, end: Double, kind: String? = nil) {
        self.id = id
        self.name = name
        self.start = start
        self.end = end
        self.kind = kind
    }
}

public struct Rig: Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var scene: String?
    public var file: String?

    public init(id: UUID = UUID(), name: String, scene: String? = nil, file: String? = nil) {
        self.id = id
        self.name = name
        self.scene = scene
        self.file = file
    }
}

public struct Take: Codable, Sendable, Equatable {
    public var id: UUID
    public var guitarId: UUID?
    public var sectionId: UUID?
    public var diFile: String?
    public var processedFile: String?
    public var micFile: String?
    public var discarded: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), guitarId: UUID? = nil, sectionId: UUID? = nil, diFile: String? = nil,
                processedFile: String? = nil, micFile: String? = nil, discarded: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.guitarId = guitarId
        self.sectionId = sectionId
        self.diFile = diFile
        self.processedFile = processedFile
        self.micFile = micFile
        self.discarded = discarded
        self.createdAt = createdAt
    }

    /// Ficheros de la toma (relativos).
    public var files: [String] { [diFile, processedFile, micFile].compactMap { $0 } }
}

public struct Video: Codable, Sendable, Equatable {
    public var id: UUID
    public var takeId: UUID?
    public var file: String
    public var fps: Double?
    public var cameraOffsetMs: Double?

    public init(id: UUID = UUID(), takeId: UUID? = nil, file: String, fps: Double? = nil, cameraOffsetMs: Double? = nil) {
        self.id = id
        self.takeId = takeId
        self.file = file
        self.fps = fps
        self.cameraOffsetMs = cameraOffsetMs
    }
}

// MARK: - Herramienta de estudio (mini-spec Fase 2, §1 Store). Tiempos en segundos de canción.

/// Acorde corregido por el usuario; `index` es la etiqueta 0…169 de StudyKit (Store no la interpreta).
public struct ChordOverride: Codable, Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var index: Int

    public init(start: Double, end: Double, index: Int) {
        self.start = start
        self.end = end
        self.index = index
    }
}

public struct Loop: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var start: Double
    public var end: Double

    public init(id: UUID = UUID(), name: String, start: Double, end: Double) {
        self.id = id
        self.name = name
        self.start = start
        self.end = end
    }
}

public struct StemMix: Codable, Sendable, Equatable {
    public var kind: StemKind
    public var gainDB: Double
    public var muted: Bool
    public var solo: Bool

    public init(kind: StemKind, gainDB: Double = 0, muted: Bool = false, solo: Bool = false) {
        self.kind = kind
        self.gainDB = gainDB
        self.muted = muted
        self.solo = solo
    }
}

public struct PlayerSettings: Codable, Sendable, Equatable {
    /// 0,5…2,0 (1 = tempo original).
    public var rate: Double
    /// Semitonos, −12…+12.
    public var transpose: Int
    /// Afinación fina en cents, ±50.
    public var fineCents: Double
    /// Capo virtual (traste); solo cambia los diagramas.
    public var capo: Int
    public var metronomeOn: Bool
    public var metronomeGainDB: Double

    public init(rate: Double = 1, transpose: Int = 0, fineCents: Double = 0, capo: Int = 0,
                metronomeOn: Bool = false, metronomeGainDB: Double = 0) {
        self.rate = rate
        self.transpose = transpose
        self.fineCents = fineCents
        self.capo = capo
        self.metronomeOn = metronomeOn
        self.metronomeGainDB = metronomeGainDB
    }
}

public struct StudyState: Codable, Sendable, Equatable {
    public var chordOverrides: [ChordOverride]
    public var keyOverride: String?
    public var loops: [Loop]
    public var mixer: [StemMix]
    public var player: PlayerSettings

    public init(chordOverrides: [ChordOverride] = [], keyOverride: String? = nil, loops: [Loop] = [],
                mixer: [StemMix] = [], player: PlayerSettings = PlayerSettings()) {
        self.chordOverrides = chordOverrides
        self.keyOverride = keyOverride
        self.loops = loops
        self.mixer = mixer
        self.player = player
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chordOverrides = try c.decodeIfPresent([ChordOverride].self, forKey: .chordOverrides) ?? []
        keyOverride = try c.decodeIfPresent(String.self, forKey: .keyOverride)
        loops = try c.decodeIfPresent([Loop].self, forKey: .loops) ?? []
        mixer = try c.decodeIfPresent([StemMix].self, forKey: .mixer) ?? []
        player = try c.decodeIfPresent(PlayerSettings.self, forKey: .player) ?? PlayerSettings()
    }
}

public struct Project: Codable, Sendable, Equatable {
    /// 2: añade `study` (Fase 2). Un v1 se lee como v2 con `study` por defecto.
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var id: UUID
    public var song: Song
    public var separation: SeparationState
    public var stems: [Stem]
    public var guitars: [Guitar]
    public var sections: [Section]
    public var rigs: [Rig]
    public var takes: [Take]
    public var videos: [Video]
    public var study: StudyState
    public var createdAt: Date
    public var updatedAt: Date

    public init(schemaVersion: Int = Project.currentSchemaVersion, id: UUID = UUID(), song: Song,
                separation: SeparationState = SeparationState(), stems: [Stem] = [], guitars: [Guitar] = [],
                sections: [Section] = [], rigs: [Rig] = [], takes: [Take] = [], videos: [Video] = [],
                study: StudyState = StudyState(),
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.study = study
        self.schemaVersion = schemaVersion
        self.id = id
        self.song = song
        self.separation = separation
        self.stems = stems
        self.guitars = guitars
        self.sections = sections
        self.rigs = rigs
        self.takes = takes
        self.videos = videos
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Migración en memoria: un v1 se lee como v2 y sube de versión al guardar.
        schemaVersion = max(try c.decode(Int.self, forKey: .schemaVersion), Project.currentSchemaVersion)
        study = try c.decodeIfPresent(StudyState.self, forKey: .study) ?? StudyState()
        id = try c.decode(UUID.self, forKey: .id)
        song = try c.decode(Song.self, forKey: .song)
        separation = try c.decodeIfPresent(SeparationState.self, forKey: .separation) ?? SeparationState()
        stems = try c.decodeIfPresent([Stem].self, forKey: .stems) ?? []
        guitars = try c.decodeIfPresent([Guitar].self, forKey: .guitars) ?? []
        sections = try c.decodeIfPresent([Section].self, forKey: .sections) ?? []
        rigs = try c.decodeIfPresent([Rig].self, forKey: .rigs) ?? []
        takes = try c.decodeIfPresent([Take].self, forKey: .takes) ?? []
        videos = try c.decodeIfPresent([Video].self, forKey: .videos) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}
