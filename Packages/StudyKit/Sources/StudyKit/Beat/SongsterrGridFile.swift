import Foundation

/// Rejilla del metrónomo corregida desde Songsterr (`SongsterrBeatGrid.build`), en `tab/songsterr-grid.json`. Va con
/// el tema y la revisión de los que salió: solo vale mientras `Project.tabSource` sea ese mismo.
/// Compartida por la app del Mac y AppCore (una sola definición; mismo JSON y mismo fichero).
public struct SongsterrGridFile: Codable, Equatable, Sendable {
    public var songId: Int
    public var revisionId: Int
    public var beats: [Double]
    public var downbeats: [Double]
    /// Tempo escrito principal de Songsterr (BPM de negra).
    public var writtenTempo: Double

    public init(songId: Int, revisionId: Int, beats: [Double], downbeats: [Double], writtenTempo: Double) {
        self.songId = songId
        self.revisionId = revisionId
        self.beats = beats
        self.downbeats = downbeats
        self.writtenTempo = writtenTempo
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    public static func load(_ url: URL) -> SongsterrGridFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SongsterrGridFile.self, from: data)
    }

    /// Regla de uso: la rejilla solo vale si es del mismo tema y revisión que la fuente de la tablatura y trae al menos
    /// 2 pulsos; si no, nil (el llamador usa la del análisis).
    public func metronomeGrid(songId: Int, revisionId: Int) -> BeatGrid? {
        guard self.songId == songId, self.revisionId == revisionId, beats.count >= 2 else { return nil }
        return BeatGrid(beats: beats, downbeats: downbeats)
    }
}
