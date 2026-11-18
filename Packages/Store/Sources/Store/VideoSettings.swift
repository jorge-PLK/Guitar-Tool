import Foundation

/// Ajustes de cámara y vídeo del perfil (mini-spec Fase 6, «Datos» y «Ajustes · Cámara y vídeo»). Aditivo: un perfil
/// anterior no trae `video` y se lee igual.

public struct VideoResolution: Codable, Sendable, Equatable, Hashable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public static let hd720 = VideoResolution(width: 1280, height: 720)
    public static let fullHD = VideoResolution(width: 1920, height: 1080)
    public static let uhd4K = VideoResolution(width: 3840, height: 2160)
}

public enum VideoCodec: String, Codable, Sendable, Equatable, CaseIterable {
    case hevc, h264
}

/// Exportación por defecto (mini-spec Fase 6: solo se guarda; la usa la Fase 7).
public struct VideoExportDefaults: Codable, Sendable, Equatable {
    /// Mini-spec Fase 6, «Ajustes · Cámara y vídeo»: la exportación normaliza a −14 LUFS, valor fijo.
    public static let normalizeLUFS: Double = -14

    public var codec: VideoCodec
    public var resolution: VideoResolution
    public var titleOverlay: Bool
    public var exportStemWAVs: Bool
    /// Siempre −14 (no se guarda; se expone para quien exporta).
    public var normalizeLUFS: Double { Self.normalizeLUFS }

    public init(codec: VideoCodec = .hevc, resolution: VideoResolution = .fullHD, titleOverlay: Bool = true,
                exportStemWAVs: Bool = true) {
        self.codec = codec
        self.resolution = resolution
        self.titleOverlay = titleOverlay
        self.exportStemWAVs = exportStemWAVs
    }

    private enum CodingKeys: String, CodingKey { case codec, resolution, titleOverlay, exportStemWAVs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        codec = try c.decodeIfPresent(VideoCodec.self, forKey: .codec) ?? .hevc
        resolution = try c.decodeIfPresent(VideoResolution.self, forKey: .resolution) ?? .fullHD
        titleOverlay = try c.decodeIfPresent(Bool.self, forKey: .titleOverlay) ?? true
        exportStemWAVs = try c.decodeIfPresent(Bool.self, forKey: .exportStemWAVs) ?? true
    }
}

public struct VideoSettings: Codable, Sendable, Equatable {
    public static let defaultFPS: Double = 30

    /// nil = la cámara por defecto del sistema.
    public var cameraUID: String?
    public var resolution: VideoResolution
    public var fps: Double
    /// Desfase por defecto (s, positivo = la imagen llega tarde) por UID de cámara.
    public var offsets: [String: Double]
    public var export: VideoExportDefaults
    /// Giro de la imagen (grados en sentido horario: 0, 90, 180 o 270) por UID de cámara (decisión de Jorge del
    /// 17/11/2026: vídeo vertical). Aditivo; sin entrada, 0.
    public var rotations: [String: Int]

    public init(cameraUID: String? = nil, resolution: VideoResolution = .fullHD, fps: Double = VideoSettings.defaultFPS,
                offsets: [String: Double] = [:], export: VideoExportDefaults = VideoExportDefaults(), rotations: [String: Int] = [:]) {
        self.cameraUID = cameraUID
        self.resolution = resolution
        self.fps = fps
        self.offsets = offsets
        self.export = export
        self.rotations = rotations
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cameraUID = try c.decodeIfPresent(String.self, forKey: .cameraUID)
        resolution = try c.decodeIfPresent(VideoResolution.self, forKey: .resolution) ?? .fullHD
        fps = try c.decodeIfPresent(Double.self, forKey: .fps) ?? Self.defaultFPS
        offsets = try c.decodeIfPresent([String: Double].self, forKey: .offsets) ?? [:]
        export = try c.decodeIfPresent(VideoExportDefaults.self, forKey: .export) ?? VideoExportDefaults()
        rotations = try c.decodeIfPresent([String: Int].self, forKey: .rotations) ?? [:]
    }

    /// Giro de esa cámara (0 si no hay), normalizado.
    public func defaultRotation(for cameraUID: String) -> Int { Self.normalizedRotation(rotations[cameraUID] ?? 0) }

    public mutating func setDefaultRotation(_ degrees: Int, for cameraUID: String) {
        rotations[cameraUID] = Self.normalizedRotation(degrees)
    }

    /// Cuartos de vuelta: cualquier entero → 0, 90, 180 o 270 (se redondea al cuarto más cercano).
    public static func normalizedRotation(_ degrees: Int) -> Int {
        let q = Int((Double(degrees) / 90).rounded())
        return ((q % 4) + 4) % 4 * 90
    }

    /// Desfase por defecto de esa cámara (0 si no hay).
    public func defaultOffset(for cameraUID: String) -> Double { offsets[cameraUID] ?? 0 }

    public mutating func setDefaultOffset(_ seconds: Double, for cameraUID: String) { offsets[cameraUID] = seconds }
}
