import Foundation

public struct RankedCandidate: Sendable, Equatable, Identifiable {
    public var candidate: Candidate
    /// Duración del candidato menos la de Spotify, con signo; nil si el candidato no trae duración.
    public var difference: Double?
    /// Diferencia absoluta de `CandidateRanker.closeThreshold` o menos («cercano»).
    public var isClose: Bool
    /// El título dice «directo», «en directo», «en vivo», «live» o «concierto»: nunca se propone en las listas.
    public var isLive: Bool = false
    public var id: String { candidate.id }
}

/// Orden por diferencia absoluta de duración y marca «cercano» (spec, «Recorrido» paso 3).
public enum CandidateRanker {
    /// Umbral de «cercano», en segundos (spec: 3 s; se revisa con la prueba ampliada).
    public static let closeThreshold: Double = 3

    /// Marca «directo» (spec, «Recorrido» paso 3): palabras enteras, sin distinguir mayúsculas ni acentos.
    /// «en vivo» solo cuenta como expresión; «vivo» suelto no.
    public static func isLive(title: String) -> Bool {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        let words = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.contains(where: { ["directo", "live", "concierto"].contains($0) }) { return true }
        return zip(words, words.dropFirst()).contains { $0 == "en" && $1 == "vivo" }
    }

    /// Orden por diferencia absoluta dentro de cada grupo. `referenceTitle` es el título del tema de Spotify:
    /// si no es un directo, los candidatos «directo» van detrás de todos los de estudio (aunque su diferencia sea
    /// menor); si lo es, van primero. «Cercano» solo depende de la diferencia. Sin título se trata como estudio.
    public static func rank(_ candidates: [Candidate], referenceDuration: Double,
                            referenceTitle: String? = nil) -> [RankedCandidate] {
        let referenceIsLive = referenceTitle.map(isLive(title:)) ?? false
        let ranked = candidates.map { c -> RankedCandidate in
            let diff = c.durationSeconds.map { $0 - referenceDuration }
            return RankedCandidate(candidate: c, difference: diff, isClose: diff.map { abs($0) <= closeThreshold } ?? false,
                                   isLive: isLive(title: c.title))
        }
        // sorted(by:) no es estable: se desempata por posición original.
        return ranked.enumerated().sorted { a, b in
            if a.element.isLive != b.element.isLive { return a.element.isLive == referenceIsLive }
            switch (a.element.difference, b.element.difference) {
            case let (x?, y?): return abs(x) != abs(y) ? abs(x) < abs(y) : a.offset < b.offset
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.element)
    }
}
