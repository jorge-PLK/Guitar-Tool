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
    /// Landscape (1920 × 1080): plano único, como `single` pero apaisado. El raw value se usa en los nombres de fichero.
    case singleLandscape = "single-landscape"

    /// Lienzo vertical (1080 × 1920).
    public var isPortrait: Bool { self == .stack || self == .single }
    /// Plano único (una sola parte a la vez, con cortes libres `MontageState.singleCuts`).
    public var isSingleShot: Bool { self == .single || self == .singleLandscape }
    /// Tamaño del lienzo a resolución Full HD, en píxeles (ancho, alto).
    public var canvasSize: (width: Int, height: Int) { isPortrait ? (1080, 1920) : (1920, 1080) }
}

/// Corte libre del plano único (mini-spec Fase 7, «Datos»): desde `time` hasta el siguiente corte manda `partID`.
public struct MontageSingleCut: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Segundos en tiempo del tema.
    public var time: Double
    /// Parte que sale desde ese instante; nil = volver al automático (rítmica elegida; en los solos, la solista).
    public var partID: UUID?

    public init(id: UUID = UUID(), time: Double, partID: UUID?) {
        self.id = id
        self.time = time
        self.partID = partID
    }
}

extension Array where Element == MontageSingleCut {
    /// Ordenados por tiempo, sin dos cortes en el mismo instante (gana el último de la lista), sin tiempos no finitos
    /// ni negativos (se llevan a 0), y sin cortes consecutivos que no cambian nada (el primero parte de automático).
    public func normalizedSingleCuts() -> [MontageSingleCut] {
        let valid = enumerated().filter { $0.element.time.isFinite }
            .map { (i: $0.offset, cut: MontageSingleCut(id: $0.element.id, time: Swift.max(0, $0.element.time),
                                                        partID: $0.element.partID)) }
        let sorted = valid.sorted { $0.cut.time != $1.cut.time ? $0.cut.time < $1.cut.time : $0.i < $1.i }
        var byTime: [MontageSingleCut] = []
        for e in sorted {
            if let last = byTime.last, last.time == e.cut.time { byTime[byTime.count - 1] = e.cut } else { byTime.append(e.cut) }
        }
        var out: [MontageSingleCut] = []
        var current: UUID? = nil
        for c in byTime where c.partID != current {
            out.append(c)
            current = c.partID
        }
        return out
    }
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

    /// El mismo encuadre sobre la imagen girada `quarterTurns` cuartos de vuelta en sentido horario (botón «Rotar» de
    /// Montaje): la caja manual y el desplazamiento se giran con la imagen (en coordenadas normalizadas, un cuarto de
    /// vuelta lleva (x, y) a (1 − y, x)); modo y zoom no cambian.
    public func rotatedClockwise(quarterTurns: Int) -> TakeFraming {
        var f = self
        for _ in 0..<(((quarterTurns % 4) + 4) % 4) {
            if let b = f.manualBox { f.manualBox = NormalizedRect(x: 1 - b.y - b.height, y: b.x, width: b.height, height: b.width) }
            f.followOffset = FramingOffset(x: -f.followOffset.y, y: f.followOffset.x)
        }
        return f
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
    /// Contenedor del vídeo (mini-spec Fase 7, «Exportación»): `.mov` por defecto.
    public var container: MontageContainer

    public init(codec: VideoCodec = .hevc, resolution: VideoResolution = .fullHD,
                fps: Double = VideoSettings.defaultFPS, normalize: Bool = true, trackWAVs: Bool = true,
                limiter: Bool = true, container: MontageContainer = .mov) {
        self.limiter = limiter
        self.container = container
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
        container = (try? c.decodeIfPresent(MontageContainer.self, forKey: .container)) ?? .mov
    }
}

/// Contenedor del vídeo montado; la extensión del fichero sale de aquí.
public enum MontageContainer: String, Codable, Sendable, Equatable, CaseIterable {
    case mov, mp4

    public var fileExtension: String { rawValue }
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
    /// Rótulo con el nombre de cada parte en su recuadro. No es `caption` (título y artista).
    public var showPartLabels: Bool = true
    /// «Mantener aspect ratio de vídeo»: en apilado y plano único la toma se ve entera (16:9) sobre su propia imagen
    /// ampliada, difuminada y oscurecida, sin recorte de encuadre.
    public var keepVideoAspect: Bool = false
    /// Cortes libres del plano único (`single` y `singleLandscape`); vacío = automático.
    public var singleCuts: [MontageSingleCut] = []

    public init(layout: MontageLayoutKind = .side, singleRhythmPartID: UUID? = nil, caption: Bool = true,
                export: MontageExport = MontageExport(), framing: [UUID: TakeFraming] = [:], cutGaps: Bool = false,
                showPartLabels: Bool = true, keepVideoAspect: Bool = false, singleCuts: [MontageSingleCut] = []) {
        self.showPartLabels = showPartLabels
        self.keepVideoAspect = keepVideoAspect
        self.singleCuts = singleCuts
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

    /// Orden propio de los recuadros/carriles (ids de parte); vacío = el orden de las partes. Aditivo: sin subir `schemaVersion`.
    public var partOrder: [UUID] = []

    /// Orden efectivo: los ids guardados que siguen existiendo, y las partes nuevas al final en su orden natural.
    public func effectiveOrder(of partIDs: [UUID]) -> [UUID] {
        let existing = Set(partIDs)
        var seen = Set<UUID>()
        let saved = partOrder.filter { existing.contains($0) && seen.insert($0).inserted }
        return saved + partIDs.filter { !seen.contains($0) }
    }

    private enum CodingKeys: String, CodingKey { case layout, singleRhythmPartID, caption, export, framing, cutGaps, partOrder
        case showPartLabels, keepVideoAspect, singleCuts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = (try? c.decodeIfPresent(MontageLayoutKind.self, forKey: .layout)) ?? .side
        singleRhythmPartID = try c.decodeIfPresent(UUID.self, forKey: .singleRhythmPartID)
        caption = try c.decodeIfPresent(Bool.self, forKey: .caption) ?? true
        cutGaps = try c.decodeIfPresent(Bool.self, forKey: .cutGaps) ?? false
        export = try c.decodeIfPresent(MontageExport.self, forKey: .export) ?? MontageExport()
        showPartLabels = try c.decodeIfPresent(Bool.self, forKey: .showPartLabels) ?? true
        keepVideoAspect = try c.decodeIfPresent(Bool.self, forKey: .keepVideoAspect) ?? false
        singleCuts = try c.decodeIfPresent([MontageSingleCut].self, forKey: .singleCuts) ?? []
        let order = try c.decodeIfPresent([String].self, forKey: .partOrder) ?? []
        partOrder = order.compactMap { UUID(uuidString: $0) }
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
        try c.encode(showPartLabels, forKey: .showPartLabels)
        try c.encode(keepVideoAspect, forKey: .keepVideoAspect)
        if !singleCuts.isEmpty { try c.encode(singleCuts, forKey: .singleCuts) }
        if !partOrder.isEmpty { try c.encode(partOrder.map(\.uuidString), forKey: .partOrder) }
        try c.encode(export, forKey: .export)
        try c.encode(Dictionary(uniqueKeysWithValues: framing.map { ($0.key.uuidString, $0.value) }), forKey: .framing)
    }

    /// Parte que manda en el plano único en el instante `time` (segundos del tema). nil = automático (sin corte anterior,
    /// corte vigente automático). Los cortes cuya parte no está en `existingPartIDs` se ignoran (sin borrarlos): sigue
    /// mandando el corte válido anterior.
    public func singlePart(at time: Double, existingPartIDs: [UUID]) -> UUID? {
        let existing = Set(existingPartIDs)
        var result: UUID? = nil
        for c in singleCuts.normalizedSingleCuts() {
            if c.time > time { break }
            if c.partID == nil { result = nil } else if let p = c.partID, existing.contains(p) { result = p }
        }
        return result
    }

    /// Añade un corte (gana a otro en el mismo instante). Devuelve el estado con los cortes normalizados.
    public func addingSingleCut(at time: Double, partID: UUID?, id: UUID = UUID()) -> MontageState {
        var s = self
        s.singleCuts = (singleCuts + [MontageSingleCut(id: id, time: time, partID: partID)]).normalizedSingleCuts()
        return s
    }

    /// Mueve un corte a otro instante (gana a otro que haya allí). Sin efecto si el id no existe.
    public func movingSingleCut(_ id: UUID, to time: Double) -> MontageState {
        guard var cut = singleCuts.first(where: { $0.id == id }) else { return self }
        cut.time = time
        var s = self
        s.singleCuts = (singleCuts.filter { $0.id != id } + [cut]).normalizedSingleCuts()
        return s
    }

    /// Cambia la parte de un corte (nil = automático). Sin efecto si el id no existe.
    public func settingSingleCut(_ id: UUID, partID: UUID?) -> MontageState {
        guard singleCuts.contains(where: { $0.id == id }) else { return self }
        var s = self
        s.singleCuts = singleCuts.map { $0.id == id ? MontageSingleCut(id: id, time: $0.time, partID: partID) : $0 }
            .normalizedSingleCuts()
        return s
    }

    /// Borra un corte.
    public func removingSingleCut(_ id: UUID) -> MontageState {
        var s = self
        s.singleCuts = singleCuts.filter { $0.id != id }.normalizedSingleCuts()
        return s
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
