import Foundation

/// Búsqueda de temas en Biblioteca (spec Fase 7b, punto 2).
public enum LibraryFilter {
    /// Plegado sin mayúsculas, acentos ni espacios de los extremos.
    public static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cada palabra de la consulta debe aparecer en el título o en el artista. Consulta vacía: todo.
    public static func matches(title: String, artist: String?, query: String) -> Bool {
        let words = fold(query).split(whereSeparator: \.isWhitespace)
        if words.isEmpty { return true }
        let haystack = fold(title) + "\u{1}" + fold(artist ?? "")
        return words.allSatisfy { haystack.contains($0) }
    }
}

/// Un grupo de la vista por artista (spec Fase 7b, punto 5).
public struct ArtistGroup<Item>: Identifiable {
    /// Clave plegada; vacía para «Sin artista».
    public let id: String
    /// Primera grafía encontrada; nil para «Sin artista».
    public let name: String?
    public let items: [Item]
    public var count: Int { items.count }
}

extension ArtistGroup: Sendable where Item: Sendable {}

public enum LibraryGrouping {
    /// Agrupa por artista sin distinguir mayúsculas, acentos ni espacios de los extremos. Aplica el filtro antes de agrupar.
    /// Grupos en orden alfabético local con «Sin artista» al final; dentro de cada grupo, temas por título.
    public static func byArtist<Item>(_ items: [Item], query: String = "",
                                      title: (Item) -> String, artist: (Item) -> String?) -> [ArtistGroup<Item>] {
        var order: [String] = []
        var names: [String: String] = [:]
        var buckets: [String: [Item]] = [:]
        for item in items where LibraryFilter.matches(title: title(item), artist: artist(item), query: query) {
            let raw = artist(item)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let key = LibraryFilter.fold(raw)
            if buckets[key] == nil { order.append(key); names[key] = raw.isEmpty ? nil : raw }
            buckets[key, default: []].append(item)
        }
        let collator: (String, String) -> Bool = {
            $0.compare($1, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: Locale(identifier: "es")) == .orderedAscending
        }
        let keys = order.filter { !$0.isEmpty }.sorted { collator(names[$0] ?? $0, names[$1] ?? $1) }
            + order.filter { $0.isEmpty }
        return keys.map { key in
            ArtistGroup(id: key, name: names[key],
                        items: buckets[key]!.sorted { collator(title($0), title($1)) })
        }
    }

    public static func sortedByTitle<Item>(_ items: [Item], query: String = "",
                                           title: (Item) -> String, artist: (Item) -> String?) -> [Item] {
        items.filter { LibraryFilter.matches(title: title($0), artist: artist($0), query: query) }
            .sorted { title($0).localizedCaseInsensitiveCompare(title($1)) == .orderedAscending }
    }
}
