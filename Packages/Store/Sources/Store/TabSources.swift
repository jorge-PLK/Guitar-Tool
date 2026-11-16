import Foundation

/// Pista de la tablatura según el estado actual del proyecto (mini-spec Fase 5, decisión 2).
public struct TabSource: Sendable, Equatable {
    public enum Kind: String, Sendable { case guitar, bass, drums }

    /// Estable entre aperturas: `guitar-rhythm`, `guitar-left`, `guitar-right`, `guitar-lead`, `guitar`, `bass`, `drums`.
    public var id: String
    public var name: String
    public var kind: Kind
    /// WAV de origen, relativo a la carpeta del proyecto.
    public var relativePath: String
    /// Id del canal del stem en el reproductor de estudio (`guitar_L`, `bass`…).
    public var playerTrackID: String

    public init(id: String, name: String, kind: Kind, relativePath: String, playerTrackID: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.relativePath = relativePath
        self.playerTrackID = playerTrackID
    }
}

public extension Project {
    /// Una pista por guitarra con fichero (nombre de `Guitar.name`); sin pistas separadas, `stems/guitar.wav` como
    /// una sola «Guitarra». Más bajo y batería. Los stems vacíos no generan pista. Orden: guitarras, bajo, batería.
    /// `fileExists` decide si el WAV está en disco (inyectable para tests).
    func tabSources(fileExists: (String) -> Bool) -> [TabSource] {
        var out: [TabSource] = []
        let separated = guitarTracks.filter { g in g.file.map(fileExists) == true }
        if separated.isEmpty {
            if let s = stems.first(where: { $0.kind == .guitar && !$0.isEmpty }), fileExists(s.file) {
                out.append(TabSource(id: "guitar", name: "Guitarra", kind: .guitar, relativePath: s.file,
                                     playerTrackID: StemKind.guitar.rawValue))
            }
        } else {
            for g in separated {
                guard let file = g.file else { continue }
                out.append(TabSource(id: "guitar-\(g.role.rawValue)", name: g.name, kind: .guitar, relativePath: file,
                                     playerTrackID: String(g.role.fileName.dropLast(4))))
            }
        }
        for (kind, k) in [(StemKind.bass, TabSource.Kind.bass), (.drums, .drums)] {
            guard let s = stems.first(where: { $0.kind == kind && !$0.isEmpty }), fileExists(s.file) else { continue }
            out.append(TabSource(id: kind.rawValue, name: kind == .bass ? "Bajo" : "Batería", kind: k,
                                 relativePath: s.file, playerTrackID: kind.rawValue))
        }
        return out
    }
}
