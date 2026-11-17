import Foundation

/// Errores del lector de Songsterr (spec, «Calidad de la tablatura (Fase 5b)» > Errores).
public enum SongsterrError: Error, Sendable, Equatable {
    /// La búsqueda no trae resultados: «No está en Songsterr».
    case noResults
    /// Página o pista con un formato que no se reconoce: «Songsterr ha cambiado su formato».
    case unknownFormat(String)
    /// HTTP 429 o bloqueo equivalente. No se insiste en bucle.
    case rateLimited
    /// Sin red.
    case offline
    /// Otro estado HTTP.
    case httpStatus(Int)
    /// Enlace o URL de pista cuyo host no es el esperado.
    case invalidHost
    case cancelled
}

/// Un resultado de la búsqueda de Songsterr.
public struct SongsterrSearchResult: Sendable, Equatable, Identifiable {
    public var id: Int { songId }
    public let songId: Int
    public let artist: String
    public let title: String

    public init(songId: Int, artist: String, title: String) {
        self.songId = songId
        self.artist = artist
        self.title = title
    }
}

/// Una pista de un tema de Songsterr.
public struct SongsterrTrack: Sendable, Equatable, Identifiable {
    public var id: Int { partId }
    /// Posición en la lista de pistas del tema.
    public let index: Int
    /// Identificador de la pista en el CDN (`partId`).
    public let partId: Int
    public let name: String
    public let instrument: String
    public let instrumentId: Int
    /// Afinación en MIDI de la cuerda más aguda a la más grave, si viene.
    public let tuning: [Int]?
    public let isDrums: Bool
    public let isBass: Bool
    public let isGuitar: Bool
    /// JSON de la pista en el CDN (host validado).
    public let url: URL

    public init(index: Int, partId: Int, name: String, instrument: String, instrumentId: Int, tuning: [Int]?,
                isDrums: Bool, isBass: Bool, isGuitar: Bool, url: URL) {
        self.index = index
        self.partId = partId
        self.name = name
        self.instrument = instrument
        self.instrumentId = instrumentId
        self.tuning = tuning
        self.isDrums = isDrums
        self.isBass = isBass
        self.isGuitar = isGuitar
        self.url = url
    }
}

/// Un tema de Songsterr con sus pistas.
public struct SongsterrSong: Sendable, Equatable {
    public let songId: Int
    public let revisionId: Int
    public let artist: String
    public let title: String
    public let tracks: [SongsterrTrack]

    public init(songId: Int, revisionId: Int, artist: String, title: String, tracks: [SongsterrTrack]) {
        self.songId = songId
        self.revisionId = revisionId
        self.artist = artist
        self.title = title
        self.tracks = tracks
    }
}
