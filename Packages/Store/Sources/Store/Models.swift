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

public struct Section: Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var start: Double
    public var end: Double
    public var kind: String?
    /// Marca «Solo» (mini-spec Fase 4: el solo es una sección más). Opcional y aditiva: ausente = no es solo.
    public var solo: Bool?
    /// Índice en la paleta de colores de sección (`SectionEditor.paletteCount`); nil = automático. Los solos van
    /// siempre en naranja y no usan este campo (se conserva para cuando se quite la marca). Opcional y aditivo.
    public var color: Int?

    public var isSolo: Bool { solo ?? false }

    public init(id: UUID = UUID(), name: String, start: Double, end: Double, kind: String? = nil, solo: Bool? = nil,
                color: Int? = nil) {
        self.color = color
        self.id = id
        self.name = name
        self.start = start
        self.end = end
        self.kind = kind
        self.solo = solo
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

    // Grabación con el dispositivo (mini-spec Fase 3, «Grabación»). Todos opcionales y aditivos: las tomas
    // anteriores no los traen.
    /// Instante del tema (s) al que corresponde la muestra 0 del fichero ya alineado.
    public var songStart: Double?
    public var sampleRate: Double?
    /// Latencia con la que se alineó, en muestras con decimales.
    public var latencySamples: Double?
    /// Retardo del rig medido en esta toma (o el último fiable), en muestras.
    public var rigDelaySamples: Double?
    public var rigDelayReliable: Bool?
    /// false = alineada con la latencia declarada por el dispositivo, sin calibrar.
    public var latencyCalibrated: Bool?
    /// Clave con la que se calibró; permite recolocar la toma al calibrar después.
    public var calibrationKey: CalibrationKey?
    public var clock: ClockMode?

    // Grabación con vídeo (mini-spec Fase 6, «Datos»). Opcionales y aditivos.
    public var partID: UUID?
    /// Ruta relativa (`takes/<id>/video.mov`); las marcas del fichero están en tiempo del tema.
    public var videoFile: String?
    /// Desfase manual (s, positivo = la imagen llega tarde).
    public var videoOffset: Double?
    public var videoFormat: TakeVideoFormat?
    public var punches: [TakePunch]?
    /// Audio original antes de aplanar un punch (`takes/<id>/base/processed.wav`).
    public var baseProcessedFile: String?

    public init(id: UUID = UUID(), guitarId: UUID? = nil, sectionId: UUID? = nil, diFile: String? = nil,
                processedFile: String? = nil, micFile: String? = nil, discarded: Bool = false, createdAt: Date = Date(),
                songStart: Double? = nil, sampleRate: Double? = nil, latencySamples: Double? = nil,
                rigDelaySamples: Double? = nil, rigDelayReliable: Bool? = nil, latencyCalibrated: Bool? = nil,
                calibrationKey: CalibrationKey? = nil, clock: ClockMode? = nil,
                partID: UUID? = nil, videoFile: String? = nil, videoOffset: Double? = nil,
                videoFormat: TakeVideoFormat? = nil, punches: [TakePunch]? = nil, baseProcessedFile: String? = nil) {
        self.partID = partID
        self.videoFile = videoFile
        self.videoOffset = videoOffset
        self.videoFormat = videoFormat
        self.punches = punches
        self.baseProcessedFile = baseProcessedFile
        self.songStart = songStart
        self.sampleRate = sampleRate
        self.latencySamples = latencySamples
        self.rigDelaySamples = rigDelaySamples
        self.rigDelayReliable = rigDelayReliable
        self.latencyCalibrated = latencyCalibrated
        self.calibrationKey = calibrationKey
        self.clock = clock
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
    /// Si no es nil, el canal es de esa pista de guitarra (`kind` = `.guitar`) y no del stem entero.
    public var guitarRole: GuitarRole?

    public init(kind: StemKind, gainDB: Double = 0, muted: Bool = false, solo: Bool = false, guitarRole: GuitarRole? = nil) {
        self.guitarRole = guitarRole
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
    /// Ajustes de guitarras guardados (Fase 4): solo el interruptor L/R. Los tramos de solo no se guardan aquí: salen
    /// de las secciones con «Solo» (`guitarOptions`). Aditivo; clave JSON `guitarOptions`.
    public var guitarSettings: GuitarSettings
    /// Con qué opciones y qué entrada se produjeron las pistas de `guitars`; nil si no se procesó. Aditivo.
    public var guitarApplied: GuitarAppliedState?
    /// Grabación con vídeo por partes (Fase 6). Aditivo; nil si no se ha abierto Grabar.
    public var recording: RecordingState?
    public var createdAt: Date
    public var updatedAt: Date

    public init(schemaVersion: Int = Project.currentSchemaVersion, id: UUID = UUID(), song: Song,
                separation: SeparationState = SeparationState(), stems: [Stem] = [], guitars: [Guitar] = [],
                sections: [Section] = [], rigs: [Rig] = [], takes: [Take] = [], videos: [Video] = [],
                study: StudyState = StudyState(),
                createdAt: Date = Date(), updatedAt: Date = Date(), guitarSettings: GuitarSettings = GuitarSettings(),
                guitarApplied: GuitarAppliedState? = nil, recording: RecordingState? = nil) {
        self.recording = recording
        self.guitarSettings = guitarSettings
        self.guitarApplied = guitarApplied
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

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, song, separation, stems, guitars, sections, rigs, takes, videos, study
        case guitarSettings = "guitarOptions"
        case guitarApplied, recording, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Migración en memoria: un v1 se lee como v2 y sube de versión al guardar.
        schemaVersion = max(try c.decode(Int.self, forKey: .schemaVersion), Project.currentSchemaVersion)
        study = try c.decodeIfPresent(StudyState.self, forKey: .study) ?? StudyState()
        guitarSettings = try c.decodeIfPresent(GuitarSettings.self, forKey: .guitarSettings) ?? GuitarSettings()
        guitarApplied = try c.decodeIfPresent(GuitarAppliedState.self, forKey: .guitarApplied)
        recording = try c.decodeIfPresent(RecordingState.self, forKey: .recording)
        id = try c.decode(UUID.self, forKey: .id)
        song = try c.decode(Song.self, forKey: .song)
        separation = try c.decodeIfPresent(SeparationState.self, forKey: .separation) ?? SeparationState()
        stems = try c.decodeIfPresent([Stem].self, forKey: .stems) ?? []
        // Las entradas que no sean de este formato (stub de antes de la Fase 4) se ignoran.
        guitars = ((try? c.decodeIfPresent([LossyGuitar].self, forKey: .guitars)) ?? nil)?.compactMap(\.value) ?? []
        sections = try c.decodeIfPresent([Section].self, forKey: .sections) ?? []
        rigs = try c.decodeIfPresent([Rig].self, forKey: .rigs) ?? []
        takes = try c.decodeIfPresent([Take].self, forKey: .takes) ?? []
        videos = try c.decodeIfPresent([Video].self, forKey: .videos) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

private struct LossyGuitar: Decodable {
    let value: Guitar?
    init(from decoder: Decoder) throws { value = try? Guitar(from: decoder) }
}
