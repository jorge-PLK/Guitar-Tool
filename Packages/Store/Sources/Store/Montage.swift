import Foundation

/// Montaje de las mejores tomas en un vídeo (mini-spec Fase 7, «Datos»). Todo aditivo: un proyecto sin `montage` se
/// lee igual y no sube `schemaVersion`.

public enum MontageLayoutKind: String, Codable, Sendable, Equatable, CaseIterable {
    /// Landscape: una fila de columnas iguales.
    case side
    /// Landscape: rejilla (1 completo, 2 lado a lado, 3 dos arriba y uno abajo, 4 en 2 × 2).
    case grid
    /// Portrait: una columna de filas iguales.
    case stack
    /// Portrait: plano único (la rítmica elegida y, en los solos, la solista).
    case single
}

/// Rectángulo normalizado sobre el fotograma (0...1, origen arriba a la izquierda).
public struct NormalizedRect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum FramingMode: String, Codable, Sendable, Equatable, CaseIterable {
    /// Un recuadro para toda la toma.
    case fixed
    /// El recorte sigue la guitarra, suavizado.
    case follow
}

/// Ajuste de encuadre de una toma (mini-spec Fase 7, «Encuadre»). Sin ajuste manual vale el análisis automático.
public struct TakeFraming: Codable, Sendable, Equatable {
    public static let defaultFollowZoom: Double = 1

    public var mode: FramingMode
    /// Caja manual para el modo fijo; nil = la automática.
    public var manualBox: NormalizedRect?
    /// Zoom sobre la trayectoria en el modo seguir (1 = sin cambio).
    public var followZoom: Double
    /// Desplazamiento normalizado sobre la trayectoria en el modo seguir (x, y).
    public var followOffset: FramingOffset

    public init(mode: FramingMode = .fixed, manualBox: NormalizedRect? = nil,
                followZoom: Double = TakeFraming.defaultFollowZoom, followOffset: FramingOffset = .zero) {
        self.mode = mode
        self.manualBox = manualBox
        self.followZoom = followZoom
        self.followOffset = followOffset
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decodeIfPresent(FramingMode.self, forKey: .mode)) ?? .fixed
        manualBox = try c.decodeIfPresent(NormalizedRect.self, forKey: .manualBox)
        followZoom = try c.decodeIfPresent(Double.self, forKey: .followZoom) ?? Self.defaultFollowZoom
        followOffset = try c.decodeIfPresent(FramingOffset.self, forKey: .followOffset) ?? .zero
    }

    /// «Restablecer»: vuelve al automático (conserva el modo).
    public mutating func reset() {
        manualBox = nil
        followZoom = Self.defaultFollowZoom
        followOffset = .zero
    }
}

public struct FramingOffset: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = FramingOffset(x: 0, y: 0)
}

/// Copia editable de la exportación por defecto del perfil (mini-spec Fase 7, «Exportación»).
public struct MontageExport: Codable, Sendable, Equatable {
    public var codec: VideoCodec
    public var resolution: VideoResolution
    public var fps: Double
    /// Normalizar la mezcla a −14 LUFS (`VideoExportDefaults.normalizeLUFS`).
    public var normalize: Bool
    /// WAV por pista en `video/<tema>-<layout>-pistas/`.
    public var trackWAVs: Bool
    /// Limitador de pico en la mezcla normalizada.
    public var limiter: Bool

    public init(codec: VideoCodec = .hevc, resolution: VideoResolution = .fullHD,
                fps: Double = VideoSettings.defaultFPS, normalize: Bool = true, trackWAVs: Bool = true,
                limiter: Bool = true) {
        self.limiter = limiter
        self.codec = codec
        self.resolution = resolution
        self.fps = fps
        self.normalize = normalize
        self.trackWAVs = trackWAVs
    }

    /// Valores iniciales desde la exportación por defecto del perfil (30 fps si no se da otro).
    public init(defaults: VideoExportDefaults, fps: Double = VideoSettings.defaultFPS) {
        self.init(codec: defaults.codec, resolution: defaults.resolution, fps: fps, normalize: true,
                  trackWAVs: defaults.exportStemWAVs)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        codec = try c.decodeIfPresent(VideoCodec.self, forKey: .codec) ?? .hevc
        resolution = try c.decodeIfPresent(VideoResolution.self, forKey: .resolution) ?? .fullHD
        fps = try c.decodeIfPresent(Double.self, forKey: .fps) ?? VideoSettings.defaultFPS
        normalize = try c.decodeIfPresent(Bool.self, forKey: .normalize) ?? true
        trackWAVs = try c.decodeIfPresent(Bool.self, forKey: .trackWAVs) ?? true
        limiter = try c.decodeIfPresent(Bool.self, forKey: .limiter) ?? true
    }
}

public struct MontageState: Codable, Sendable, Equatable {
    public var layout: MontageLayoutKind
    /// Rítmica que ocupa el plano único; nil = la primera con vídeo.
    public var singleRhythmPartID: UUID?
    /// Rótulo con título y artista en los 5 primeros segundos.
    public var caption: Bool
    public var export: MontageExport
    /// Encuadre por toma; sin entrada = fijo y automático.
    public var framing: [UUID: TakeFraming]
    /// Recortar los huecos sin ninguna parte en vez de enseñar el fondo con el backing.
    public var cutGaps: Bool

    public init(layout: MontageLayoutKind = .side, singleRhythmPartID: UUID? = nil, caption: Bool = true,
                export: MontageExport = MontageExport(), framing: [UUID: TakeFraming] = [:], cutGaps: Bool = false) {
        self.cutGaps = cutGaps
        self.layout = layout
        self.singleRhythmPartID = singleRhythmPartID
        self.caption = caption
        self.export = export
        self.framing = framing
    }

    /// Estado inicial desde los ajustes de vídeo del perfil (nil = valores por defecto).
    public static func initial(from video: VideoSettings?) -> MontageState {
        guard let video else { return MontageState() }
        return MontageState(caption: video.export.titleOverlay,
                            export: MontageExport(defaults: video.export, fps: video.fps))
    }

    private enum CodingKeys: String, CodingKey { case layout, singleRhythmPartID, caption, export, framing, cutGaps }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = (try? c.decodeIfPresent(MontageLayoutKind.self, forKey: .layout)) ?? .side
        singleRhythmPartID = try c.decodeIfPresent(UUID.self, forKey: .singleRhythmPartID)
        caption = try c.decodeIfPresent(Bool.self, forKey: .caption) ?? true
        cutGaps = try c.decodeIfPresent(Bool.self, forKey: .cutGaps) ?? false
        export = try c.decodeIfPresent(MontageExport.self, forKey: .export) ?? MontageExport()
        // Se guarda como objeto con el UUID como clave (legible); las claves que no sean UUID se ignoran.
        let raw = try c.decodeIfPresent([String: TakeFraming].self, forKey: .framing) ?? [:]
        framing = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(layout, forKey: .layout)
        try c.encodeIfPresent(singleRhythmPartID, forKey: .singleRhythmPartID)
        try c.encode(caption, forKey: .caption)
        try c.encode(cutGaps, forKey: .cutGaps)
        try c.encode(export, forKey: .export)
        try c.encode(Dictionary(uniqueKeysWithValues: framing.map { ($0.key.uuidString, $0.value) }), forKey: .framing)
    }

    /// Ajuste de una toma, o el predeterminado (fijo, automático).
    public func framing(for takeID: UUID) -> TakeFraming { framing[takeID] ?? TakeFraming() }

    /// Quita el ajuste de una toma (al borrarla).
    public mutating func removeFraming(_ takeID: UUID) { framing[takeID] = nil }
}

extension Project {
    /// Estado de montaje existente, o el inicial según los ajustes de vídeo del perfil.
    public func montageOrInitial(video: VideoSettings? = nil) -> MontageState {
        montage ?? MontageState.initial(from: video)
    }
}
