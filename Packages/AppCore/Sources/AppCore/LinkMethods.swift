import Foundation
import SourceKit
import Store

// 8.3b: importación por enlace y herramientas externas (campos exactos en `Temp/win/step8-contract.md`, «8.3b»).
// `link.resolve` sigue el recorrido de la hoja del Mac; `link.import` crea un trabajo de la cola (`link-N`): descarga,
// conversión, importación en la biblioteca y, ya con `Library`, la separación y el análisis como `import.file`.

struct LinkURLParams: Codable, Sendable { var url: String }
struct LinkCancelParams: Codable, Sendable { var jobId: String? }
struct LinkImportParams: Codable, Sendable {
    var candidateId: String?
    var url: String?
    var title: String?
    var artist: String?
}
struct LinkSearchParams: Codable, Sendable { var query: String }
struct LinkAddManualParams: Codable, Sendable { var url: String }

/// Un resultado de la búsqueda en Spotify (`SpotifyTrackResult` del Mac).
struct LinkSpotifyTrack: Codable, Sendable, Equatable {
    var id: String
    var name: String
    var artists: [String]
    var album: String
    var year: Int?
    var durationText: String
    var imageURL: String?
    var trackURL: String
    var appURL: String
    init(_ t: SpotifyTrackResult) {
        id = t.id; name = t.name; artists = t.artists; album = t.album; year = t.year; durationText = t.durationText
        imageURL = t.imageURL?.absoluteString; trackURL = t.trackURL.absoluteString; appURL = t.appURL.absoluteString
    }
}

struct LinkSearchResult: Codable, Sendable {
    var query: String
    var tracks: [LinkSpotifyTrack]
}

struct LinkAddManualResult: Codable, Sendable {
    /// Id del vídeo añadido (ya va el primero de `resolution.candidates`).
    var added: String
    /// `false` si ese vídeo ya está en la biblioteca (el Mac no lo deja elegido).
    var selectable: Bool
    var resolution: LinkResolveResult
}

struct LinkJobResult: Codable, Sendable { var jobId: String }

struct LinkTrackInfo: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var artist: String?
    init(_ t: ExistingTrack) { id = t.id.uuidString; title = t.title; artist = t.artist }
}

struct LinkCandidateInfo: Codable, Sendable {
    var id: String
    var title: String
    var artist: String?
    var duration: Double?
    var thumbnail: String?
    var source: String
    var url: String
    var isClose: Bool
    var isLive: Bool
    var difference: Double?
    var inLibrary: LinkTrackInfo?
}

struct LinkResolveResult: Codable, Sendable {
    var link: String
    var pastedURL: String
    var title: String
    var artist: String?
    var album: String?
    var duration: Double?
    var thumbnail: String?
    var existing: LinkTrackInfo?
    var possibleDuplicate: LinkTrackInfo?
    var noCloseCandidate: Bool
    var candidates: [LinkCandidateInfo]
}

struct LinkFinished: Codable, Sendable {
    struct Failure: Codable, Sendable { var code: String; var message: String }
    var jobId: String
    var id: String?
    var duplicate: Bool
    var notices: [String]
    var error: Failure?
}

struct CancelledResult: Codable, Sendable { var cancelled: Bool }
struct RevertedResult: Codable, Sendable { var reverted: Bool }

struct ToolsInfoResult: Codable, Sendable {
    var ytDlpVersion: String?
    var ytDlpOrigin: String?
    var denoVersion: String?
    var ffmpegVersion: String?

    init(_ i: ExternalToolsInfo) {
        ytDlpVersion = i.ytDlpVersion
        ytDlpOrigin = i.ytDlpOrigin.map(Self.origin)
        denoVersion = i.denoVersion
        ffmpegVersion = i.ffmpegVersion
    }

    static func origin(_ o: SourceKit.HelperLocator.Origin) -> String { o == .updated ? "updated" : "embedded" }
}

struct UpdateYtDlpResult: Codable, Sendable {
    var version: String
    var origin: String
    var alreadyLatest: Bool
}

/// Núcleo de «Importar desde enlace»: una resolución viva (`LinkImportSession`) y una descarga a la vez en la cola.
final class LinkEngine: @unchecked Sendable {
    /// Prefijo de la clave opaca del trabajo en `jobs.progress` (`link-N`).
    static let keyPrefix = "link-"
    /// Miniatura de un candidato de YouTube sin miniatura propia (spec, «Fuentes externas» > Interfaz).
    static func thumbnailURL(videoID: String) -> String { "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg" }

    let jobs: JobEngine
    let sources: ExternalSources
    private let root: URL?
    private let lock = NSLock()
    private var _session: LinkImportSession?
    private var counter = 0
    private var tail: Task<Void, Never>?
    private var running: [String: Task<Void, Never>] = [:]
    private var _emitFinished: @Sendable (LinkFinished) -> Void = { _ in }

    init(jobs: JobEngine, sources: ExternalSources, root: URL?) {
        self.jobs = jobs
        self.sources = sources
        self.root = root
    }

    func setSink(_ f: @escaping @Sendable (LinkFinished) -> Void) { lock.withLock { _emitFinished = f } }

    @MainActor
    private func session() -> LinkImportSession {
        if let s = lock.withLock({ _session }) { return s }
        let sources = self.sources, root = self.root
        let s = LinkImportSession(hooks: .init(
            makeImporter: { try await sources.makeImporter() },
            lookup: { await Task.detached { LibraryLookup.scan(root: root) }.value }))
        lock.withLock { _session = s }
        return s
    }

    // MARK: Resolver

    func resolve(url: String) async throws -> LinkResolveResult {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw RPCError(code: "bad-params", message: "«url» está vacía.") }
        _ = try Bridge.service(root)
        let s = await session()
        do {
            let r = try await s.resolve(text)
            return Self.result(r)
        } catch { throw SourceMessages.rpc(error) }
    }

    /// Búsqueda de Spotify por texto (`LinkImportSession.search` del Mac). El texto del error es el del Mac.
    func search(_ query: String, with searcher: any SpotifySearching) async throws -> LinkSearchResult {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw RPCError(code: "bad-params", message: "«query» está vacía.") }
        do {
            return LinkSearchResult(query: q, tracks: try await searcher.search(q).map(LinkSpotifyTrack.init))
        } catch let e as SpotifySearchError {
            let code: String = switch e {
            case .missingCredentials: "spotify-missing-credentials"
            case .rejected: "spotify-rejected"
            case .rateLimited: "spotify-rate-limited"
            case .network: "spotify-offline"
            case .badResponse: "spotify-bad-response"
            }
            throw RPCError(code: code, message: e.localizedDescription)
        } catch is CancellationError {
            throw RPCError(code: "cancelled", message: "Cancelado")
        } catch {
            throw RPCError(code: "spotify-offline", message: "Sin conexión con Spotify")
        }
    }

    /// Enlace de YouTube pegado a mano entre los candidatos de la última resolución.
    func addManual(url: String) async throws -> LinkAddManualResult {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw RPCError(code: "bad-params", message: "«url» está vacía.") }
        let s = await session()
        do {
            let (r, id) = try await s.addManual(text)
            return LinkAddManualResult(added: id, selectable: r.libraryVideos[id] == nil, resolution: Self.result(r))
        } catch { throw SourceMessages.rpc(error) }
    }

    @discardableResult
    func cancelResolve() async -> Bool { await session().cancel() }

    static func result(_ r: LinkResolution) -> LinkResolveResult {
        let kind: String = { if case .spotify = r.link { "spotify" } else { "youtube" } }()
        if let e = r.existing {
            return LinkResolveResult(link: kind, pastedURL: r.pastedURL, title: e.title, artist: e.artist,
                                     existing: LinkTrackInfo(e), noCloseCandidate: false, candidates: [])
        }
        guard let s = r.resolved else {
            return LinkResolveResult(link: kind, pastedURL: r.pastedURL, title: "", noCloseCandidate: false, candidates: [])
        }
        func info(_ c: Candidate, thumbnail: String?, close: Bool, live: Bool, difference: Double?) -> LinkCandidateInfo {
            LinkCandidateInfo(id: c.id, title: c.title, artist: c.channel, duration: c.durationSeconds,
                              thumbnail: thumbnail ?? thumbnailURL(videoID: c.id), source: "youtube", url: c.url.absoluteString,
                              isClose: close, isLive: live, difference: difference,
                              inLibrary: r.libraryVideos[c.id].map(LinkTrackInfo.init))
        }
        var list: [LinkCandidateInfo] = []
        if let c = s.confirmation {
            list.append(info(c, thumbnail: s.artworkURL?.absoluteString, close: true,
                             live: CandidateRanker.isLive(title: c.title), difference: nil))
        }
        list += s.candidates.map { info($0.candidate, thumbnail: nil, close: $0.isClose, live: $0.isLive, difference: $0.difference) }
        return LinkResolveResult(
            link: kind, pastedURL: s.pastedURL, title: s.title, artist: s.artist.isEmpty ? nil : s.artist, album: s.album,
            duration: s.durationSeconds, thumbnail: s.artworkURL?.absoluteString,
            existing: nil, possibleDuplicate: r.possibleDuplicate.map(LinkTrackInfo.init),
            noCloseCandidate: s.noCloseCandidate, candidates: list)
    }

    // MARK: Importar

    private struct Plan {
        var pasted: String
        var candidate: Candidate?
        var title: String?
        var artist: String?
    }

    /// Valida, crea el trabajo en la cola (`queued`) y vuelve; el resto sale por `jobs.progress` y `link.finished`.
    func startImport(_ p: LinkImportParams) async throws -> LinkJobResult {
        _ = try Bridge.service(root)
        func clean(_ s: String?) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t?.isEmpty ?? true) ? nil : t
        }
        var plan: Plan
        if let id = clean(p.candidateId) {
            let last = await MainActor.run { self.session().last }
            guard let s = last?.resolved,
                  let c = s.confirmation?.id == id ? s.confirmation : s.candidates.first(where: { $0.id == id })?.candidate else {
                throw RPCError(code: "not-found",
                               message: "Ese candidato no está en la última resolución; vuelve a resolver el enlace.")
            }
            plan = Plan(pasted: s.pastedURL, candidate: c, title: s.title, artist: s.artist)
        } else if let url = clean(p.url) {
            guard case .youtube? = try? SourceLink.parse(url) else {
                throw RPCError(code: "bad-params",
                               message: "Con «url» solo se admite un vídeo de YouTube; para Spotify hace falta «candidateId».")
            }
            plan = Plan(pasted: url)
        } else {
            throw RPCError(code: "bad-params", message: "Hace falta «candidateId» o «url».")
        }
        if let t = clean(p.title) { plan.title = t }
        if let a = p.artist { plan.artist = clean(a) ?? "" }

        let key: String = lock.withLock { counter += 1; return "\(Self.keyPrefix)\(counter)" }
        let shown = Self.display(title: plan.title, artist: plan.artist) ?? plan.pasted
        jobs.update(key, title: shown, stage: "download", state: "queued", text: "En cola")
        let previous = lock.withLock { tail }
        let task = Task { [self] in
            await run(key: key, plan: plan, shown: shown, after: previous)
        }
        lock.withLock { tail = task; running[key] = task }
        return LinkJobResult(jobId: key)
    }

    private static func display(title: String?, artist: String?) -> String? {
        let parts = [artist, title].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }

    /// Cancela una descarga (en cola o en marcha). `true` si existía.
    func cancelJob(_ key: String) -> Bool {
        guard let t = lock.withLock({ running[key] }) else { return false }
        t.cancel()
        return true
    }

    private func finish(_ f: LinkFinished) {
        let emit = lock.withLock { running[f.jobId] = nil; return _emitFinished }
        emit(f)
    }

    private func run(key: String, plan: Plan, shown: String, after previous: Task<Void, Never>?) async {
        await previous?.value
        var title = shown
        var stage = "download"
        var notices: [String] = []
        do {
            try Task.checkCancellation()
            let lib = try await jobs.library()
            jobs.update(key, title: title, stage: "download", state: "running", fraction: nil, text: "Descargando audio…")
            let importer = try await sources.makeImporter()
            let resolved = try await importer.resolveWithoutSearch(plan.pasted)
            try Task.checkCancellation()
            guard let candidate = plan.candidate ?? resolved.confirmation else { throw SourceError.unsupportedLink }
            let songTitle = plan.title ?? resolved.title
            let songArtist = plan.artist ?? resolved.artist
            title = Self.display(title: songTitle, artist: songArtist) ?? title

            if let dup = await lib.project(withVideoID: candidate.id) {
                jobs.update(key, title: title, stage: "import", state: "done", fraction: 1)
                finish(LinkFinished(jobId: key, id: dup.id.uuidString, duplicate: true, notices: [], error: nil))
                return
            }

            let jobs = self.jobs
            let progressTitle = title
            await MainActor.run {
                importer.onStateChange = { state in
                    guard case .downloading(let s, let p) = state else { return }
                    if s == .converting {
                        jobs.update(key, title: progressTitle, stage: "download", state: "running", fraction: nil,
                                    text: "Convirtiendo a WAV…")
                    } else {
                        let text = p.map { "Descargando audio… \(Int(($0 * 100).rounded())) %" } ?? "Descargando audio…"
                        jobs.update(key, title: progressTitle, stage: "download", state: "running", fraction: p, text: text)
                    }
                }
            }
            let source = try await importer.download(candidate: candidate, title: songTitle, artist: songArtist)
            defer { source.cleanUp() }
            notices = source.notices.map(\.message)
            try Task.checkCancellation()

            stage = "import"
            jobs.update(key, title: title, stage: "import", state: "running", fraction: 0)
            var cover: URL?
            if let art = source.artworkURL { cover = await sources.preparedCover(art, in: source.workDirectory) }
            let meta = ImportMetadata(title: songTitle, artist: songArtist.isEmpty ? nil : songArtist,
                                      origin: SongOrigin(source.origin), artworkFile: cover)
            do {
                let id = try await lib.importSong(from: source.wavURL, metadata: meta) { p in
                    jobs.update(key, title: progressTitle, stage: "import", state: "running", fraction: min(max(p, 0), 1))
                }
                jobs.update(key, title: title, stage: "import", state: "done", fraction: 1)
                finish(LinkFinished(jobId: key, id: id.uuidString, duplicate: false, notices: notices, error: nil))
            } catch LibraryError.duplicate(let existing) {
                jobs.update(key, title: title, stage: "import", state: "done", fraction: 1)
                finish(LinkFinished(jobId: key, id: existing.uuidString, duplicate: true, notices: notices, error: nil))
            }
        } catch {
            let rpc = SourceMessages.rpc(error)
            if rpc.code == "cancelled" {
                jobs.update(key, title: title, stage: stage, state: "cancelled")
            } else {
                let detail = rpc.message.split(separator: "\n", maxSplits: 1).last.map(String.init) ?? rpc.message
                jobs.update(key, title: title, stage: stage, state: "failed", error: detail)
            }
            finish(LinkFinished(jobId: key, id: nil, duplicate: false, notices: notices,
                                error: .init(code: rpc.code, message: rpc.message)))
        }
    }
}

extension Bridge {
    func registerLinkMethods(root: URL?, options: LaunchOptions) {
        let sources = link ?? ExternalSources.production(supportDir: options.supportDir,
                                                          environment: ProcessInfo.processInfo.environment)
        let defaultDir = SourceKit.HelperLocator.defaultSupportDirectory.deletingLastPathComponent()
        let supportDir = options.supportDir ?? defaultDir
        let searcher: any SpotifySearching = spotify
            ?? SpotifySearchClient.live(supportDir: supportDir, defaultSupportDir: defaultDir)
        let engine = LinkEngine(jobs: jobs, sources: sources, root: root)
        engine.setSink { [weak self] in self?.emit("link.finished", $0) }

        router.register("link.resolve") { (p: LinkURLParams) in try await engine.resolve(url: p.url) }
        router.register("link.cancel") { (p: LinkCancelParams) in
            if let key = p.jobId { return CancelledResult(cancelled: engine.cancelJob(key)) }
            return CancelledResult(cancelled: await engine.cancelResolve())
        }
        router.register("link.search") { (p: LinkSearchParams) in try await engine.search(p.query, with: searcher) }
        router.register("link.addManual") { (p: LinkAddManualParams) in try await engine.addManual(url: p.url) }
        router.register("link.import") { (p: LinkImportParams) in try await engine.startImport(p) }

        router.register("tools.info") { (_: Empty) in ToolsInfoResult(await sources.toolsInfo()) }
        router.register("tools.updateYtDlp") { (_: Empty) -> UpdateYtDlpResult in
            let info: YtDlpInstallInfo
            do { info = try await sources.updateYtDlp() } catch { throw SourceMessages.rpc(error) }
            let now = await sources.toolsInfo()
            let origin = now.ytDlpOrigin ?? .bundle
            return UpdateYtDlpResult(version: info.version, origin: ToolsInfoResult.origin(origin),
                                     alreadyLatest: origin != .updated)
        }
        router.register("tools.revertYtDlp") { (_: Empty) -> RevertedResult in
            do { try await sources.removeUpdate() } catch {
                throw RPCError(code: "internal", message: "No se pudo volver a la embebida: \(JobEngine.describe(error))")
            }
            return RevertedResult(reverted: true)
        }
    }
}
