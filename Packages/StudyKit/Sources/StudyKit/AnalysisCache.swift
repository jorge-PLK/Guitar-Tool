import Foundation

/// Huella del análisis: si cualquier campo cambia, la caché está desfasada.
/// No incluye la frecuencia de muestreo (todo va en segundos; mini-spec Fase 2 §2).
public struct AnalysisFingerprint: Codable, Equatable, Sendable {
    public var beatModelID: String
    public var beatModelVersion: String
    public var chordModelID: String
    public var chordModelVersion: String
    public var algorithmVersion: Int
    public var separationModel: String
    public var separationFinishedAt: Date
    public var sourceSHA256: String

    public init(beatModelID: String, beatModelVersion: String,
                chordModelID: String, chordModelVersion: String,
                algorithmVersion: Int,
                separationModel: String, separationFinishedAt: Date,
                sourceSHA256: String) {
        self.beatModelID = beatModelID
        self.beatModelVersion = beatModelVersion
        self.chordModelID = chordModelID
        self.chordModelVersion = chordModelVersion
        self.algorithmVersion = algorithmVersion
        self.separationModel = separationModel
        self.separationFinishedAt = separationFinishedAt
        self.sourceSHA256 = sourceSHA256
    }
}

/// Caché genérica del análisis (`cache/analysis.json`): huella + contenido.
public enum AnalysisCache {
    private struct Envelope<T: Codable>: Codable {
        var fingerprint: AnalysisFingerprint
        var analysis: T
    }

    /// Escribe de forma atómica, creando la carpeta si falta.
    public static func save<T: Codable>(_ value: T, fingerprint: AnalysisFingerprint, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Envelope(fingerprint: fingerprint, analysis: value))
        try data.write(to: url, options: .atomic)
    }

    /// nil si el fichero falta, no decodifica o la huella no coincide.
    public static func load<T: Codable>(_ type: T.Type = T.self, at url: URL, expecting fingerprint: AnalysisFingerprint) -> T? {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data),
              envelope.fingerprint == fingerprint else { return nil }
        return envelope.analysis
    }
}
