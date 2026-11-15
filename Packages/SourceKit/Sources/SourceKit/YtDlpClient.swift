import Foundation

/// Vídeo de YouTube con los metadatos que importan (de `yt-dlp -J`).
public struct VideoInfo: Sendable, Equatable {
    public var id: String
    /// `track` si viene; si no, `title`.
    public var title: String
    /// `artist` si viene; si no, el canal.
    public var artist: String
    public var channel: String?
    public var album: String?
    public var durationSeconds: Double?
    public var thumbnailURL: URL?
}

/// Resultado de la búsqueda o candidato elegido a mano.
public struct Candidate: Sendable, Equatable, Identifiable {
    public var id: String
    public var url: URL
    public var title: String
    public var channel: String?
    public var durationSeconds: Double?

    public init(id: String, url: URL, title: String, channel: String? = nil, durationSeconds: Double? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.channel = channel
        self.durationSeconds = durationSeconds
    }
}

/// Lista de YouTube leída con `--flat-playlist -J`.
public struct YouTubePlaylist: Sendable, Equatable {
    public var id: String
    public var title: String
    public var channel: String?
    /// Id, título, canal y duración de cada vídeo.
    public var entries: [Candidate]
}

/// Audio descargado y códec real (`opus` o `aac`).
public struct DownloadedAudio: Sendable, Equatable {
    public var url: URL
    public var codec: String
    /// El vídeo no ofrecía Opus y se cayó a M4A (spec, «Recorrido» paso 4).
    public var fellBackToM4A: Bool { codec != "opus" }
}

/// `info`, `search` y `download` sobre `ProcessRunning`; clasifica stderr en `SourceError`.
public struct YtDlpClient: Sendable {
    /// Tiempos límite de la spec, «Errores».
    public static let infoTimeout: ProcessTimeout = .total(15)
    public static let searchTimeout: ProcessTimeout = .total(30)
    public static let downloadTimeout: ProcessTimeout = .idle(60)
    /// Opus primero; si el vídeo no lo ofrece, M4A (spec, «Recorrido» paso 4).
    public static let formatSelector = "bestaudio[acodec=opus]/bestaudio[ext=m4a]"
    public static let searchCount = 5
    static let progressPrefix = "TFPROGRESS"

    public let executable: URL
    public let deno: URL
    private let runner: ProcessRunning

    public init(executable: URL, deno: URL, runner: ProcessRunning) {
        self.executable = executable
        self.deno = deno
        self.runner = runner
    }

    public func version() async throws -> String {
        let r = try await runner.run(.init(executable: executable, arguments: ["--version"], timeout: Self.infoTimeout))
        guard r.status == 0 else { throw Self.classify(stderr: r.stderr, status: r.status, version: nil) }
        return String(decoding: r.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `yt-dlp -J --no-playlist <url>`.
    public func info(url: URL) async throws -> VideoInfo {
        let args = ["-J", "--no-playlist", "--js-runtimes", "deno:\(deno.path)", url.absoluteString]
        let r = try await runner.run(.init(executable: executable, arguments: args, timeout: Self.infoTimeout))
        try await check(r)
        return try Self.parseInfo(r.stdout)
    }

    /// `yt-dlp --flat-playlist -J ytsearch5:<consulta>`.
    public func search(query: String) async throws -> [Candidate] {
        let args = ["--flat-playlist", "-J", "ytsearch\(Self.searchCount):\(query)"]
        let r = try await runner.run(.init(executable: executable, arguments: args, timeout: Self.searchTimeout))
        try await check(r)
        return try Self.parseSearch(r.stdout)
    }

    /// `yt-dlp --flat-playlist -J <url>` sobre una lista de YouTube (spec, «Listas»).
    public func playlist(url: URL) async throws -> YouTubePlaylist {
        let args = ["--flat-playlist", "-J", url.absoluteString]
        let r = try await runner.run(.init(executable: executable, arguments: args, timeout: Self.searchTimeout))
        try await check(r)
        return try Self.parsePlaylist(r.stdout)
    }

    /// Descarga el audio sin recodificar a `directory/audio.<ext>`. `progress` recibe 0...1.
    public func download(url: URL, into directory: URL,
                         progress: (@Sendable (Double) -> Void)? = nil) async throws -> DownloadedAudio {
        let args = [
            "-f", Self.formatSelector, "--no-playlist", "--js-runtimes", "deno:\(deno.path)",
            "--newline", "--progress-template",
            "download:\(Self.progressPrefix) %(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s",
            "-o", directory.appendingPathComponent("audio.%(ext)s").path, url.absoluteString
        ]
        func attempt() async throws -> ProcessResult {
            try await runner.run(.init(executable: executable, arguments: args, timeout: Self.downloadTimeout)) { line in
                if let f = Self.parseProgress(line) { progress?(f) }
            }
        }
        var r = try await attempt()
        // Un HTTP 403 en la descarga se reintenta una vez: en la prueba ampliada fue transitorio (spec, «Errores»).
        if r.status != 0, r.stderr.localizedCaseInsensitiveContains("HTTP Error 403") { r = try await attempt() }
        try await check(r, context: .download)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        guard let file = files.first(where: { $0.deletingPathExtension().lastPathComponent == "audio"
            && !["part", "ytdl"].contains($0.pathExtension) }) else { throw SourceError.noAudioProduced }
        return DownloadedAudio(url: file, codec: Self.codec(forExtension: file.pathExtension))
    }

    // MARK: - Parseo

    static func codec(forExtension ext: String) -> String {
        ["m4a", "mp4", "aac"].contains(ext.lowercased()) ? "aac" : "opus"
    }

    static func parseProgress(_ line: String) -> Double? {
        let p = line.split(separator: " ")
        guard p.count == 4, p[0] == progressPrefix, let done = Double(p[1]) else { return nil }
        let total = Double(p[2]) ?? Double(p[3])
        guard let total, total > 0 else { return nil }
        return min(1, done / total)
    }

    private struct RawInfo: Decodable {
        var id: String?, title: String?, track: String?, artist: String?, channel: String?, uploader: String?
        var album: String?, duration: Double?, thumbnail: String?
    }

    static func parseInfo(_ data: Data) throws -> VideoInfo {
        guard let raw = try? JSONDecoder().decode(RawInfo.self, from: data), let id = raw.id,
              let title = raw.track ?? raw.title else {
            throw SourceError.extractorBroken(version: nil, detail: "JSON de yt-dlp ilegible")
        }
        let channel = raw.channel ?? raw.uploader
        return VideoInfo(id: id, title: title, artist: raw.artist ?? channel ?? "", channel: channel, album: raw.album,
                         durationSeconds: raw.duration, thumbnailURL: raw.thumbnail.flatMap(URL.init(string:)))
    }

    private struct RawSearch: Decodable {
        struct Entry: Decodable {
            var id: String?, url: String?, title: String?, channel: String?, uploader: String?, duration: Double?
        }
        var entries: [Entry]?
    }

    static func parseSearch(_ data: Data) throws -> [Candidate] {
        guard let raw = try? JSONDecoder().decode(RawSearch.self, from: data) else {
            throw SourceError.extractorBroken(version: nil, detail: "JSON de búsqueda ilegible")
        }
        return (raw.entries ?? []).compactMap { e in
            guard let id = e.id, let title = e.title else { return nil }
            let url = e.url.flatMap(URL.init(string:)) ?? URL(string: "https://www.youtube.com/watch?v=\(id)")!
            return Candidate(id: id, url: url, title: title, channel: e.channel ?? e.uploader, durationSeconds: e.duration)
        }
    }

    private struct RawPlaylist: Decodable {
        var id: String?, title: String?, channel: String?, uploader: String?
    }

    static func parsePlaylist(_ data: Data) throws -> YouTubePlaylist {
        guard let raw = try? JSONDecoder().decode(RawPlaylist.self, from: data) else {
            throw SourceError.extractorBroken(version: nil, detail: "JSON de lista ilegible")
        }
        return YouTubePlaylist(id: raw.id ?? "", title: raw.title ?? "", channel: raw.channel ?? raw.uploader,
                               entries: try parseSearch(data))
    }

    // MARK: - Errores

    enum Context { case metadata, download }

    private func check(_ r: ProcessResult, context: Context = .metadata) async throws {
        guard r.status != 0 else { return }
        let error = Self.classify(stderr: r.stderr, status: r.status, version: nil, context: context)
        if case .extractorBroken(_, let detail) = error {
            throw SourceError.extractorBroken(version: try? await version(), detail: detail)
        }
        throw error
    }

    /// Clasifica el stderr de yt-dlp (spec, «Errores»). El orden importa: lo específico antes que lo genérico.
    static func classify(stderr: String, status: Int32, version: String?, context: Context = .metadata) -> SourceError {
        func has(_ needles: String...) -> Bool { needles.contains { stderr.localizedCaseInsensitiveContains($0) } }
        if has("Sign in to confirm your age") { return .ageRestricted }
        if has("not a bot", "HTTP Error 429", "Too Many Requests") { return .rateLimited }
        if has("not available in your country", "available in your country", "blocked it in your country") { return .unavailable(.region) }
        if has("Private video") { return .unavailable(.privateVideo) }
        if has("Video unavailable") { return .unavailable(.removed) }
        if context == .download, has("Requested format is not available") { return .noAudioFormat }
        if has("Temporary failure in name resolution", "Name or service not known", "nodename nor servname",
               "Network is unreachable", "Unable to connect", "Connection refused", "Connection reset",
               "getaddrinfo failed", "Failed to resolve", "No address associated", "timed out") {
            return .offline
        }
        let tail = stderr.split(separator: "\n").suffix(6).joined(separator: "\n")
        return .extractorBroken(version: version, detail: tail)
    }
}
