import Foundation

/// Nombres de pista (mini-spec Fase 5c, decisión 5): el nombre de Songsterr si existe; si está vacío, el del
/// instrumento («Guitarra», «Bajo», «Batería», «Voz»), con número desde la segunda repetición («Guitarra 2»).
public enum TabTrackNames {
    /// Nombre por defecto de un tipo de pista.
    public static func defaultName(for kind: TabTrackKind) -> String {
        switch kind {
        case .guitar: "Guitarra"
        case .bass: "Bajo"
        case .drums: "Batería"
        case .vocal: "Voz"
        }
    }

    /// Un nombre por entrada, en el mismo orden. Solo se numeran los nombres por defecto repetidos entre sí.
    public static func resolve(_ entries: [(name: String, kind: TabTrackKind)]) -> [String] {
        var seen: [TabTrackKind: Int] = [:]
        return entries.map { e in
            let trimmed = e.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return e.name }
            let n = (seen[e.kind] ?? 0) + 1
            seen[e.kind] = n
            return n == 1 ? defaultName(for: e.kind) : "\(defaultName(for: e.kind)) \(n)"
        }
    }
}

extension TabScore {
    /// Nombre que se enseña de cada pista (en el orden de `tracks`), con la regla de `TabTrackNames`.
    public var trackDisplayNames: [String] {
        TabTrackNames.resolve(tracks.map { (name: $0.name, kind: $0.kind) })
    }
}
