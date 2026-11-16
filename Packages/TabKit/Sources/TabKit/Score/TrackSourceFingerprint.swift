import Foundation

/// Huella del origen de una pista (mini-spec Fase 5, «Desfase por pista»): ruta, tamaño y fecha del WAV, versión
/// del modelo y de los parámetros. La afinación no entra: cambiarla reasigna cuerdas sin transcribir.
public struct TrackSourceFingerprint: Codable, Sendable, Hashable {
    /// Ruta del WAV, relativa a la carpeta del proyecto (la elige la app).
    public var path: String
    public var size: Int64
    /// Fecha de modificación en milisegundos desde 1970: entero para que la huella sobreviva a cualquier
    /// estrategia de fechas del `JSONEncoder` sin perder precisión.
    public var modifiedMillis: Int64
    public var modelVersion: String
    public var parametersVersion: Int

    public init(path: String, size: Int64, modifiedMillis: Int64, modelVersion: String,
                parametersVersion: Int = TabTrackBuilder.parametersVersion) {
        self.path = path
        self.size = size
        self.modifiedMillis = modifiedMillis
        self.modelVersion = modelVersion
        self.parametersVersion = parametersVersion
    }

    /// Lee tamaño y fecha del fichero en `url`; `path` es la ruta que se guarda (relativa al proyecto).
    public static func of(fileAt url: URL, path: String, modelVersion: String,
                          parametersVersion: Int = TabTrackBuilder.parametersVersion) throws -> TrackSourceFingerprint {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let date = attrs[.modificationDate] as? Date ?? .distantPast
        return TrackSourceFingerprint(path: path, size: size,
                                      modifiedMillis: Int64((date.timeIntervalSince1970 * 1000).rounded()),
                                      modelVersion: modelVersion, parametersVersion: parametersVersion)
    }
}

/// Qué pistas hay que transcribir y cuáles sobran frente a los ficheros actuales.
public struct TabStaleness: Sendable, Equatable {
    /// Pistas nuevas o con huella distinta (o sin huella), en el orden de `current`.
    public var needsTranscription: [String]
    /// Pistas de la partitura que ya no existen en `current`.
    public var obsolete: [String]
}

extension TabScore {
    /// Compara la huella guardada de cada pista con la actual (`current`: id de pista → huella).
    public func staleness(current: [(id: String, fingerprint: TrackSourceFingerprint)]) -> TabStaleness {
        let ids = Set(current.map(\.id))
        let needs = current.filter { item in
            guard let track = tracks.first(where: { $0.id == item.id }) else { return true }
            return track.source != item.fingerprint
        }.map(\.id)
        return TabStaleness(needsTranscription: needs, obsolete: tracks.map(\.id).filter { !ids.contains($0) })
    }
}
