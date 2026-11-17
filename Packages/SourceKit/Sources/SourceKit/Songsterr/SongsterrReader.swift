import Foundation

/// Extrae el estado embebido de las páginas de Songsterr (`<script id="state">`). Lógica pura, sin red.
/// Formato de referencia: `Probes/P5b-guitarra/songsterr_fetch.py`. Spec, «Calidad de la tablatura (Fase 5b)», parte 1.
public enum SongsterrReader {
    /// Hosts de revisiones en el CDN conocidos (comparación exacta, nunca por subcadena).
    public static let cdnHosts: [String] = ["dqsljvtekg760.cloudfront.net", "d3d3l6a6rcgkaf.cloudfront.net"]
    /// Máximo de resultados de búsqueda que se devuelven.
    public static let maxSearchResults = 20

    static let siteHost = "songsterr.com"

    // MARK: URLs

    /// `host` es `songsterr.com` o un subdominio suyo (sufijo con punto, no subcadena).
    public static func isSongsterrHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == siteHost || host.hasSuffix("." + siteHost)
    }

    public static func isCDNHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return cdnHosts.contains(host)
    }

    /// Valida un enlace pegado: https, host de Songsterr y ruta de un tema (`…-s<id>`).
    public static func songURL(from text: String) throws -> URL {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: t), url.scheme == "https", isSongsterrHost(url.host), url.user == nil else {
            throw SongsterrError.invalidHost
        }
        guard songId(inPath: url.path) != nil else { throw SongsterrError.unknownFormat("enlace sin tema") }
        return url
    }

    /// URL de un tema por su identificador. Songsterr redirige `…/song-tab-s<id>` (301) a la ruta canónica con el
    /// slug; `…/song-s<id>` da 404 (comprobado el 17/11/2026).
    public static func songURL(songId: Int) -> URL? { URL(string: "https://www.songsterr.com/a/wsa/song-tab-s\(songId)") }

    static func songId(inPath path: String) -> Int? {
        guard let r = path.range(of: #"-s(\d+)$"#, options: .regularExpression) else { return nil }
        return Int(path[r].dropFirst(2))
    }

    // MARK: Estado

    /// Contenido de `<script id="state">` ya decodificado a JSON (con percent-encoding o sin él).
    public static func stateJSON(fromHTML html: String) throws -> Any {
        guard let m = html.range(of: #"<script[^>]*\bid="state"[^>]*>"#, options: .regularExpression),
              let end = html.range(of: "</script>", range: m.upperBound..<html.endIndex) else {
            throw SongsterrError.unknownFormat("sin script de estado")
        }
        return try stateJSON(fromScriptContent: String(html[m.upperBound..<end.lowerBound]))
    }

    /// Igual que `stateJSON(fromHTML:)` pero con el contenido del script (lo que devuelve el JS del `WKWebView`).
    public static func stateJSON(fromScriptContent content: String) throws -> Any {
        var raw = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("%") {
            guard let decoded = raw.removingPercentEncoding else { throw SongsterrError.unknownFormat("percent-encoding") }
            raw = decoded
        }
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data), json is [String: Any] else {
            throw SongsterrError.unknownFormat("JSON de estado")
        }
        return json
    }

    // MARK: Búsqueda

    /// Endpoint JSON de búsqueda (la página de búsqueda trae la lista vacía en el estado y la rellena por JS):
    /// `https://www.songsterr.com/api/songs?size=<n>&pattern=<artista título>`.
    public static func searchAPIURL(artist: String, title: String) -> URL? {
        let pattern = [artist, title].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard !pattern.isEmpty else { return nil }
        var c = URLComponents()
        c.scheme = "https"
        c.host = "www.songsterr.com"
        c.path = "/api/songs"
        c.queryItems = [URLQueryItem(name: "size", value: String(maxSearchResults)),
                        URLQueryItem(name: "pattern", value: pattern)]
        return c.url
    }

    /// Resultados del endpoint de búsqueda: un array JSON de `{songId, artist, title, …}`. Los marcados `isJunk` se
    /// descartan. `noResults` si no queda ninguno; `unknownFormat` si no es un array de objetos con esos campos.
    public static func parseSearch(json data: Data) throws -> [SongsterrSearchResult] {
        guard let arr = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            throw SongsterrError.unknownFormat("búsqueda: no es un array")
        }
        var out: [SongsterrSearchResult] = []
        var seen = Set<Int>()
        for e in arr {
            guard let d = e as? [String: Any], let id = intValue(d["songId"]), let title = d["title"] as? String,
                  let artist = d["artist"] as? String else {
                throw SongsterrError.unknownFormat("búsqueda: elemento")
            }
            if (d["isJunk"] as? Bool) == true || !seen.insert(id).inserted { continue }
            out.append(SongsterrSearchResult(songId: id, artist: artist, title: title))
        }
        guard !out.isEmpty else { throw SongsterrError.noResults }
        return Array(out.prefix(maxSearchResults))
    }

    // MARK: Tema

    public static func parseSong(html: String) throws -> SongsterrSong {
        try parseSong(state: stateJSON(fromHTML: html))
    }

    public static func parseSong(state: Any) throws -> SongsterrSong {
        guard let root = state as? [String: Any], let meta = root["meta"] as? [String: Any],
              let cur = meta["current"] as? [String: Any],
              let songId = intValue(cur["songId"]), let revisionId = intValue(cur["revisionId"]),
              let image = cur["image"] as? String, isSafeSegment(image),
              let rawTracks = cur["tracks"] as? [[String: Any]] else {
            throw SongsterrError.unknownFormat("meta.current")
        }
        guard !rawTracks.isEmpty else { throw SongsterrError.unknownFormat("tema sin pistas") }
        var tracks: [SongsterrTrack] = []
        for (i, t) in rawTracks.enumerated() {
            let partId = intValue(t["partId"]) ?? i
            let instrumentId = intValue(t["instrumentId"]) ?? 0
            guard let url = trackURL(songId: songId, revisionId: revisionId, image: image, partId: partId) else {
                throw SongsterrError.unknownFormat("pista")
            }
            let name = (t["name"] as? String) ?? (t["title"] as? String) ?? ""
            let tuning = (t["tuning"] as? [Any])?.compactMap { intValue($0) }
            let isDrums = (t["isDrums"] as? Bool) ?? (instrumentId >= 1024)
            tracks.append(SongsterrTrack(
                index: i, partId: partId, name: name, instrument: (t["instrument"] as? String) ?? "",
                instrumentId: instrumentId, tuning: (tuning?.isEmpty ?? true) ? nil : tuning, isDrums: isDrums,
                isBass: (t["isBassGuitar"] as? Bool) ?? false, isGuitar: (t["isGuitar"] as? Bool) ?? false, url: url))
        }
        return SongsterrSong(songId: songId, revisionId: revisionId, artist: (cur["artist"] as? String) ?? "",
                             title: (cur["title"] as? String) ?? "", tracks: tracks)
    }

    /// `https://<cdn>/<songId>/<revisionId>/<image>/<partId>.json` (formato de revision-fetcher.ts, MIT).
    public static func trackURL(songId: Int, revisionId: Int, image: String, partId: Int, cdnHost: String? = nil) -> URL? {
        let host = cdnHost ?? cdnHosts[0]
        guard isCDNHost(host), isSafeSegment(image), songId >= 0, revisionId >= 0, partId >= 0 else { return nil }
        return URL(string: "https://\(host)/\(songId)/\(revisionId)/\(image)/\(partId).json")
    }

    /// Comprueba que una URL de pista es https, de un host de CDN conocido y sin credenciales.
    public static func isValidTrackURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && isCDNHost(url.host)
    }

    static func isSafeSegment(_ s: String) -> Bool {
        s.range(of: #"^[A-Za-z0-9_-]{1,100}$"#, options: .regularExpression) != nil
    }

    static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double, d == d.rounded() { return Int(d) }
        if let s = any as? String { return Int(s) }
        return nil
    }
}
