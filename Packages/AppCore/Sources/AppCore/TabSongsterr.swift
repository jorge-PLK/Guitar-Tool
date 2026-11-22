import Foundation
import SourceKit
import Store
import StudyKit
import TabKit

// Hoja de Songsterr de la Tablatura (W2-G): puerto de `TabController.swift:384-598` y `TabSourceSheet.swift` (Mac).
// Contrato: `Temp/win/step8-contract.md`, «W2-G tab.songsterr.* y anfitrión». La lógica de lectura, alineación y
// emparejamiento es la de SourceKit y TabKit; aquí solo el flujo de la hoja y la costura con el navegador oculto.

// MARK: - Costura con el anfitrión: navegador oculto

/// Página ya cargada por el navegador oculto del anfitrión.
public struct HiddenPage: Sendable, Equatable {
    /// Estado HTTP de la respuesta del documento principal (200 si la carga fue bien).
    public var status: Int
    /// `document.documentElement.outerHTML` una vez cumplido `readyScript` (o tras la carga, sin él).
    public var html: String

    public init(status: Int, html: String) {
        self.status = status
        self.html = html
    }
}

/// Qué falló al cargar una página oculta.
public enum HiddenPageError: Error, Sendable, Equatable, LocalizedError {
    /// El anfitrión no tiene navegador oculto (implementación por omisión de `HostServices`).
    case unsupported
    /// No hubo navegación: sin red, DNS, fallo de conexión o tope de tiempo de la propia navegación.
    case offline
    /// La página cargó pero `readyScript` no llegó a dar `true` antes del tope de tiempo.
    case readyTimeout
    /// El documento principal respondió con un estado >= 400 (429 incluido). No se muestra la página.
    case httpStatus(Int)
    /// La carga se canceló (`Task` cancelada o `stopLoading`).
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unsupported: "Este programa no puede leer páginas de Songsterr."
        case .offline: "No se pudo cargar la página."
        case .readyTimeout: "La página tardó demasiado en cargar."
        case .httpStatus(let c): "La página respondió con el error \(c)."
        case .cancelled: "Carga cancelada."
        }
    }
}

/// Navegador oculto sin ventana: carga una URL como lo haría un navegador (JavaScript, cookies de sesión no
/// persistentes) y devuelve su HTML ya montado. Lo implementa el anfitrión (Windows: segundo WebView2 oculto; `tf-webdev`:
/// segundo `WKWebView`); `HostServices` lo hereda con una implementación por omisión que lanza `unsupported`.
///
/// Contrato del anfitrión (igual que `SongsterrWebLoader` del Mac):
/// 1. Almacén no persistente, tamaño de vista 1200x800, `userAgent` aplicado si no es `nil`.
/// 2. Navega a `url`. Si el documento principal responde con estado >= 400 cancela la navegación y lanza
///    `.httpStatus(código)`. Fallo de navegación (sin red, tiempo) -> `.offline`.
/// 3. Con `readyScript` (expresión JavaScript que da un booleano) la evalúa cada `SongsterrHiddenPage.pollMillis` ms tras
///    cargar, hasta que dé `true`; si pasa `timeout` (segundos, contados desde el inicio de la navegación) lanza `.readyTimeout`.
///    Un error al evaluar el script cuenta como `false`. Sin `readyScript`, devuelve nada más cargar.
/// 4. Devuelve `HiddenPage(status:, html: document.documentElement.outerHTML)`.
/// 5. Una carga a la vez: las que lleguen mientras otra está en curso esperan su turno (el núcleo puede lanzar dos).
/// 6. La cancelación de la `Task` detiene la navegación y lanza `.cancelled` (o `CancellationError`).
public protocol HiddenPageLoading: Sendable {
    func load(url: URL, userAgent: String?, readyScript: String?, timeout: TimeInterval) async throws -> HiddenPage
}

/// Valores de la lectura de Songsterr (Mac: `SongsterrWebLoader`).
public enum SongsterrHiddenPage {
    /// Tiempo máximo de una carga completa (navegación + estado embebido). Mac: `loadTimeout`.
    public static let loadTimeout: TimeInterval = 30
    /// Cada cuánto se evalúa `readyScript` (ms). Mac: `pollInterval`.
    public static let pollMillis = 250
    /// El estado del tema va en `<script id="state">`; se espera a que exista.
    public static let readyScript = "document.getElementById('state') !== null"
    /// Mismo user agent que el Mac (Safari). El anfitrión puede ignorarlo si prefiere el nativo de su motor.
    public static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
}

/// `SongsterrPageLoading` (lo que pide `SongsterrClient`) sobre el navegador oculto del anfitrión.
struct HiddenPageSongsterrLoader: SongsterrPageLoading {
    let pages: any HiddenPageLoading

    func html(for url: URL) async throws -> String {
        guard url.scheme == "https", SongsterrReader.isSongsterrHost(url.host) else { throw SongsterrError.invalidHost }
        let page: HiddenPage
        do {
            page = try await pages.load(url: url, userAgent: SongsterrHiddenPage.userAgent,
                                        readyScript: SongsterrHiddenPage.readyScript, timeout: SongsterrHiddenPage.loadTimeout)
        } catch let e as HiddenPageError {
            switch e {
            case .unsupported: throw e
            case .offline: throw SongsterrError.offline
            case .readyTimeout: throw SongsterrError.unknownFormat("sin script de estado")
            case .httpStatus(let c): throw c == 429 ? SongsterrError.rateLimited : SongsterrError.httpStatus(c)
            case .cancelled: throw SongsterrError.cancelled
            }
        }
        if page.status == 429 { throw SongsterrError.rateLimited }
        if page.status >= 400 { throw SongsterrError.httpStatus(page.status) }
        return page.html
    }
}

/// Anfitrión sin navegador oculto (para los servicios que se construyen sin él).
struct NoHiddenPages: HiddenPageLoading {
    func load(url: URL, userAgent: String?, readyScript: String?, timeout: TimeInterval) async throws -> HiddenPage {
        throw HiddenPageError.unsupported
    }
}

// MARK: - Servicio portátil: búsqueda, lectura, descarga, alineación

/// Entrada de la importación de un tema (todo `Sendable`, para correr fuera del hilo principal).
struct SongsterrImportInput: Sendable {
    var songId: Int
    /// Tema ya leído (viene de la hoja); nil = leerlo ahora (cambiar emparejamiento).
    var song: SongsterrSong?
    var layout: ProjectLayout
    var beats: [Double]
    var downbeats: [Double]
    var beatsPerBar: Int?
    /// WAV de cada stem por papel (con `.guitar` si hay uno completo y no hay separados).
    var stems: [SongsterrStemRole: URL]
    var slots: [SongsterrStemSlot]
    /// Secciones de solo del proyecto, en segundos.
    var soloSpans: [ClosedRange<Double>]
    /// Texto de espera de la hoja («Descargando pistas de Songsterr…», «Alineando con el audio…»).
    var progress: @Sendable (String) -> Void
}

struct SongsterrPrepared: Sendable {
    var song: SongsterrSong
    var plan: SongsterrImportPlan
    /// Rejilla del metrónomo corregida (nil si el tema no trae tempo escrito).
    var grid: SongsterrGridFile?
}

/// Lo que la hoja necesita de Songsterr: el buscador (`SongsterrServing`) y la importación. `SongsterrWebBackend` en
/// producción; los tests, un doble.
protocol SongsterrBackend: SongsterrServing {
    func prepare(_ input: SongsterrImportInput) async throws -> SongsterrPrepared
}

/// Servicios de Songsterr de `TabServices`: nil = los de producción sobre el navegador oculto del anfitrión.
struct SongsterrServices: Sendable {
    var makeBackend: @Sendable (any HiddenPageLoading) -> any SongsterrBackend
}

/// `SongsterrClient` (HTTP para la búsqueda y las pistas, navegador oculto para la página del tema) más la importación
/// de `TabController.runImport` del Mac.
struct SongsterrWebBackend: SongsterrBackend {
    let client: SongsterrClient

    init(pages: any HiddenPageLoading) {
        client = SongsterrClient(loader: HiddenPageSongsterrLoader(pages: pages))
    }

    func search(artist: String, title: String) async throws -> [SongsterrSearchResult] {
        try await client.search(artist: artist, title: title)
    }
    func song(songId: Int) async throws -> SongsterrSong { try await client.song(songId: songId) }
    func song(link: String) async throws -> SongsterrSong { try await client.song(link: link) }

    func prepare(_ input: SongsterrImportInput) async throws -> SongsterrPrepared {
        let song: SongsterrSong
        if let s = input.song { song = s } else { song = try await client.song(songId: input.songId) }
        input.progress("Descargando pistas de Songsterr…")
        let dir = input.layout.songsterrCacheDir(songId: song.songId, revisionId: song.revisionId)
        let files = try await client.downloadTracks(song.tracks, to: dir)
        input.progress("Alineando con el audio…")
        // (Sin nombrar el tipo: `SongsterrTrack` existe en SourceKit y en TabKit.)
        let tracks = try song.tracks.map { t in
            guard let f = files[t.partId] else { throw SongsterrError.unknownFormat("pista \(t.partId)") }
            var c = try SongsterrTrackConverter.convert(try Data(contentsOf: f), isDrums: t.isDrums)
            c.songId = song.songId
            c.revisionId = song.revisionId
            c.partId = t.partId
            if !t.name.isEmpty { c.name = t.name }
            return c
        }
        let raw = BeatTimes(beats: input.beats, downbeats: input.downbeats, beatsPerBar: input.beatsPerBar)
        // Pulsos llevados a negras de Songsterr (pliegue de doble o mitad de tempo, pulsos perdidos o sobrantes)
        // ANTES de alinear; la rejilla del metrónomo sale de ellos.
        let prepared = SongsterrBeatGrid.writtenTempo(tracks).map { SongsterrBeatGrid.prepare(raw, writtenTempo: $0) }
        let times = prepared?.beats ?? raw
        let stems = input.stems
        let spans = input.soloSpans
        let (alignment, meter) = try await Task.detached(priority: .userInitiated) {
            let a = try SongsterrAligner.align(tracks: tracks, beats: times, stems: stems, soloSpans: spans)
            let grid = try prepared.map {
                try SongsterrBeatGrid.build(prepared: $0, tracks: tracks, alignment: a, drums: stems[.drums])
            }
            return (a, grid)
        }.value
        try Task.checkCancellation()
        let plan = SongsterrImportPlan(alignment: alignment, tracks: tracks, slots: input.slots,
                                       songId: song.songId, revisionId: song.revisionId)
        let gridFile = meter.map {
            SongsterrGridFile(songId: song.songId, revisionId: song.revisionId, beats: $0.beats, downbeats: $0.downbeats,
                              writtenTempo: $0.writtenTempo)
        }
        return SongsterrPrepared(song: song, plan: plan, grid: gridFile)
    }
}

// MARK: - Tipos JSON

struct SongsterrIssueInfo: Codable, Sendable, Equatable {
    /// noResults | rateLimited | offline | formatChanged | invalidLink | other
    var kind: String
    var message: String
    var canRetry: Bool
    /// «Puedes transcribir el tema automáticamente.» cuando la hoja la enseña (Mac: `issueBox`); si no, ausente.
    var suggestion: String?

    init(_ issue: SongsterrIssue) {
        kind = switch issue {
        case .noResults: "noResults"
        case .rateLimited: "rateLimited"
        case .offline: "offline"
        case .formatChanged: "formatChanged"
        case .invalidLink: "invalidLink"
        case .other: "other"
        }
        message = issue.message
        canRetry = issue.canRetry
        suggestion = issue.suggestsAutomatic && (issue == .noResults || !issue.canRetry)
            ? SongsterrSheet.automaticSuggestion : nil
    }
}

struct SongsterrTrackInfo: Codable, Sendable {
    var partId: Int
    var name: String
    var instrument: String
    /// MIDI de la cuerda más aguda a la más grave; ausente en batería.
    var tuning: [Int]?
    /// «E A D G B E» de la más grave a la más aguda; «-» sin afinación.
    var tuningText: String
}

struct SongsterrResultInfo: Codable, Sendable {
    var songId: Int
    var artist: String
    var title: String
    var selected: Bool
    /// Se están leyendo sus pistas.
    var loading: Bool
    /// https://www.songsterr.com/a/wsa/song-tab-s<id> (para la vista previa; no se carga desde el núcleo).
    var previewUrl: String?
}

struct SongsterrSongInfo: Codable, Sendable {
    var songId: Int
    var revisionId: Int
    var artist: String
    var title: String
    var tracks: [SongsterrTrackInfo]
    var previewUrl: String?
}

struct SongsterrSearchInfo: Codable, Sendable {
    /// idle | searching | results | failed
    var phase: String
    var issue: SongsterrIssueInfo?
}

struct SongsterrChoiceInfo: Codable, Sendable {
    var track: Int
    var name: String
    var similarity: Double?
    /// «Rítmica (80 %)».
    var label: String
}

struct SongsterrSoloRowInfo: Codable, Sendable {
    var index: Int
    var start: Double
    var end: Double
    /// «m:ss» del inicio (la hoja pinta «Solo 1 (0:12)»).
    var clock: String
    var track: Int?
    var confidence: Double?
    /// «82 %» o «sin medir»; ausente si no hay pista.
    var confidenceText: String?
    var choices: [SongsterrChoiceInfo]
}

struct SongsterrSlotInfo: Codable, Sendable {
    var stemId: String
    var name: String
    /// guitar | bass | drums | vocal
    var kind: String
    /// Papel del stem; `lead` = el solista (una fila por solo, sin pista entera).
    var role: String
    var track: Int?
    var confidence: Double?
    var confidenceText: String?
    var choices: [SongsterrChoiceInfo]
    /// Solo el solista.
    var solos: [SongsterrSoloRowInfo]
}

struct SongsterrPairingInfo: Codable, Sendable {
    var intro: String
    var slots: [SongsterrSlotInfo]
    var extraNames: [String]
    /// «Pistas extra, sin stem: …»; ausente si no hay.
    var extraText: String?
    var warnings: [String]
}

struct SongsterrSheetState: Codable, Sendable {
    var open: Bool
    /// choosing | working | pairing | failed
    var stage: String
    /// «Artista · Título» del tema (la hoja pinta «Búsqueda: …»).
    var query: String?
    var search: SongsterrSearchInfo?
    var results: [SongsterrResultInfo]
    var selected: SongsterrSongInfo?
    /// Resultado cuyas pistas se leen; -1 = el enlace pegado.
    var loadingSongId: Int?
    var detailIssue: SongsterrIssueInfo?
    var linkIssue: SongsterrIssueInfo?
    /// Búsqueda o lectura en curso (deshabilita «Usar enlace»).
    var busy: Bool
    /// «Usar esta» disponible (hay resultado marcado con sus pistas).
    var canUse: Bool
    /// Texto de espera en `stage == "working"`.
    var workingText: String?
    /// Fallo de la importación en `stage == "failed"`.
    var failure: SongsterrIssueInfo?
    var pairing: SongsterrPairingInfo?
}

struct SongsterrSelectParams: Decodable, Sendable { var songId: Int }
struct SongsterrLinkParams: Decodable, Sendable { var link: String }
struct SongsterrAssignParams: Decodable, Sendable {
    var stemId: String
    /// Índice de la pista de Songsterr; ausente o null = transcripción automática (o «Ninguna» en un solo).
    var track: Int?
    /// Índice de la sección de solo (solista); ausente = el stem entero.
    var solo: Int?
}

// MARK: - La hoja

@MainActor
final class SongsterrSheet {
    nonisolated static let automaticSuggestion = "Puedes transcribir el tema automáticamente."
    nonisolated static let pairingIntro = "Qué pista de Songsterr va con cada stem. La confianza es el parecido medido con el audio."
    nonisolated static let readingText = "Leyendo Songsterr…"
    nonisolated static let downloadingText = "Descargando pistas de Songsterr…"

    enum Stage: Equatable {
        case choosing
        case working(String)
        case pairing
        case failed(SongsterrIssue)
    }

    private unowned let owner: TabService
    private var backend: (any SongsterrBackend)?
    private var lookup: SongsterrLookup?
    private var tasks: [Task<Void, Never>] = []
    private var importTask: Task<Void, Never>?
    private var lastImport: (songId: Int, song: SongsterrSong?, keeping: [TabStemPairing]?)?
    private var plan: SongsterrImportPlan?
    private var grid: SongsterrGridFile?
    private(set) var isOpen = false
    private var stage: Stage = .choosing

    init(owner: TabService) { self.owner = owner }

    /// Suelta todo (cambio de tema o cierre de la tablatura).
    func reset() {
        importTask?.cancel()
        tasks.forEach { $0.cancel() }
        tasks = []
        importTask = nil
        lookup = nil
        backend = nil
        plan = nil
        grid = nil
        lastImport = nil
        isOpen = false
        stage = .choosing
    }

    // MARK: Hoja

    /// Abre la hoja con la búsqueda por artista y título del proyecto (la lanza si aún no se hizo).
    func open() async throws -> SongsterrSheetState {
        let (session, _) = try owner.require()
        if backend == nil {
            let host = owner.hostProvider()
            let services = owner.services.songsterr
            guard host != nil || services != nil else {
                throw RPCError(code: "unsupported", message: "Este anfitrión no puede leer páginas de Songsterr.")
            }
            let pages: any HiddenPageLoading = host ?? NoHiddenPages()
            backend = services?.makeBackend(pages) ?? SongsterrWebBackend(pages: pages)
        }
        if lookup == nil, let backend { lookup = SongsterrLookup(service: backend) }
        importTask?.cancel()
        plan = nil
        stage = .choosing
        isOpen = true
        if lookup?.phase == .idle { search(session.project.song) }
        await Task.yield()
        return state()
    }

    func close() -> SongsterrSheetState {
        importTask?.cancel()
        isOpen = false
        plan = nil
        stage = .choosing
        return state()
    }

    private func requireOpen() throws {
        guard isOpen, lookup != nil else { throw RPCError(code: "not-open", message: "La hoja de Songsterr no está abierta.") }
    }

    private func spawn(_ work: @escaping @MainActor () async -> Void) {
        tasks.removeAll { $0.isCancelled }
        tasks.append(Task { [weak self] in
            await work()
            self?.push()
        })
    }

    private func push() { if isOpen { owner.emit("tab.songsterr.state", state()) } }

    private func search(_ song: Song) {
        guard let lookup else { return }
        spawn { await lookup.search(artist: song.artist ?? "", title: song.title) }
    }

    // MARK: Búsqueda

    func research() async throws -> SongsterrSheetState {
        try requireOpen()
        guard let session = owner.session else { throw RPCError(code: "not-open", message: "No hay ninguna tablatura abierta.") }
        search(session.project.song)
        await Task.yield()
        return state()
    }

    func retry() async throws -> SongsterrSheetState {
        try requireOpen()
        guard let lookup else { return state() }
        spawn { await lookup.retry() }
        await Task.yield()
        return state()
    }

    func select(songId: Int) async throws -> SongsterrSheetState {
        try requireOpen()
        guard let lookup else { return state() }
        spawn { await lookup.select(songId) }
        await Task.yield()
        return state()
    }

    func submitLink(_ text: String) async throws -> SongsterrSheetState {
        try requireOpen()
        guard let lookup else { return state() }
        lookup.link = text
        spawn { await lookup.submitLink() }
        await Task.yield()
        return state()
    }

    // MARK: Importación

    /// «Usar esta».
    func useSelected() throws -> SongsterrSheetState {
        try requireOpen()
        guard let song = lookup?.selectedSong else { throw RPCError(code: "not-ready", message: "No hay ningún tema marcado.") }
        beginImport(songId: song.songId, song: song, keeping: nil)
        return state()
    }

    /// Menú «Fuente» > «Cambiar emparejamiento…»: lee otra vez el tema elegido y vuelve a proponer con lo ya elegido.
    func reviewPairing() async throws -> SongsterrSheetState {
        guard case let .songsterr(songId, _, pairings)? = owner.session?.project.tabSource else {
            throw RPCError(code: "not-ready", message: "La tablatura no usa Songsterr.")
        }
        _ = try await open()
        beginImport(songId: songId, song: nil, keeping: pairings)
        return state()
    }

    func retryImport() throws -> SongsterrSheetState {
        try requireOpen()
        guard let r = lastImport else { throw RPCError(code: "not-ready", message: "No hay ninguna importación que repetir.") }
        beginImport(songId: r.songId, song: r.song, keeping: r.keeping)
        return state()
    }

    func back() throws -> SongsterrSheetState {
        try requireOpen()
        importTask?.cancel()
        plan = nil
        stage = .choosing
        return state()
    }

    private func beginImport(songId: Int, song: SongsterrSong?, keeping: [TabStemPairing]?) {
        importTask?.cancel()
        lastImport = (songId, song, keeping)
        plan = nil
        isOpen = true
        stage = .working(song == nil ? Self.readingText : Self.downloadingText)
        importTask = Task { [weak self] in await self?.runImport() }
    }

    /// Roles de stem con los que el alineador mide cada fuente (`TabSource.id` -> `SongsterrStemRole`).
    nonisolated static func role(of source: TabSource) -> SongsterrStemRole {
        switch source.id {
        case "guitar-left": .guitarLeft
        case "guitar-right": .guitarRight
        case "guitar-lead": .guitarLead
        case "bass": .bass
        case "drums": .drums
        default: .guitar   // «guitar» y «guitar-rhythm»
        }
    }

    nonisolated static func slotKind(_ k: TabSource.Kind) -> TabTrackKind {
        switch k {
        case .guitar: .guitar
        case .bass: .bass
        case .drums: .drums
        case .vocal: .vocal
        }
    }

    nonisolated static func issue(for error: Error) -> SongsterrIssue {
        if error is SongsterrFormatError { return .formatChanged }
        if let a = error as? SongsterrAlignmentError, a == .nothingToAlign {
            return .other("Ninguna pista de guitarra o bajo de Songsterr se pudo medir con el audio del tema.")
        }
        return SongsterrIssue(error)
    }

    private func runImport() async {
        guard let req = lastImport, let backend, let session = owner.session else { return }
        guard session.hasBeatGrid else {
            stage = .failed(.other("El tema aún no tiene análisis de pulso."))
            push()
            return
        }
        push()
        var stems: [SongsterrStemRole: URL] = [:]
        let layout = session.layout
        let sources = owner.sources
        for s in sources { stems[Self.role(of: s)] = layout.url(relative: s.relativePath) }
        if stems[.guitar] == nil,
           let full = session.project.stems.first(where: { $0.kind == .guitar && !$0.isEmpty }) {
            stems[.guitar] = layout.url(relative: full.file)
        }
        let slots = sources.map { SongsterrStemSlot(id: $0.id, name: $0.name, kind: Self.slotKind($0.kind), role: Self.role(of: $0)) }
        let input = SongsterrImportInput(
            songId: req.songId, song: req.song, layout: layout, beats: session.beats, downbeats: session.downbeats,
            beatsPerBar: session.analysis?.beatsPerBar, stems: stems, slots: slots,
            soloSpans: session.sections.filter(\.isSolo).map { $0.start...$0.end },
            progress: { [weak self] text in Task { @MainActor in self?.setWorking(text) } })
        do {
            let prepared = try await backend.prepare(input)
            try Task.checkCancellation()
            var proposal = prepared.plan
            let tracks = proposal.tracks
            for p in req.keeping ?? [] {
                // Secciones de solo: cada una con la guardada que empiece a menos de 1 s.
                if let saved = p.solos, let current = proposal.assignment(for: p.stemID)?.solos {
                    for (k, s) in current.enumerated() {
                        guard let old = saved.first(where: { abs($0.start - s.span.lowerBound) < 1 }) else { continue }
                        let track = old.partId.flatMap { id in tracks.firstIndex { $0.partId == id } }
                        proposal.assign(stemID: p.stemID, solo: k, track: track)
                    }
                    continue
                }
                if let id = p.partId {
                    if let i = tracks.firstIndex(where: { $0.partId == id }) { proposal.assign(stemID: p.stemID, track: i) }
                } else {
                    proposal.assign(stemID: p.stemID, track: nil)
                }
            }
            plan = proposal
            grid = prepared.grid
            stage = .pairing
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            stage = .failed(Self.issue(for: error))
        }
        push()
    }

    private func setWorking(_ text: String) {
        guard case .working = stage else { return }
        stage = .working(text)
        push()
    }

    // MARK: Emparejamiento

    func assign(stemId: String, track: Int?, solo: Int?) throws -> SongsterrSheetState {
        guard plan != nil, stage == .pairing else { throw RPCError(code: "not-ready", message: "No hay emparejamiento abierto.") }
        if let solo { plan?.assign(stemID: stemId, solo: solo, track: track) } else { plan?.assign(stemID: stemId, track: track) }
        return state()
    }

    func allAutomatic() throws -> SongsterrSheetState {
        guard plan != nil, stage == .pairing else { throw RPCError(code: "not-ready", message: "No hay emparejamiento abierto.") }
        plan?.useAutomaticForAll()
        return state()
    }

    /// «Aceptar»: crea la tablatura con lo emparejado y guarda la fuente. Las pistas sin pareja quedan `queued`
    /// (la página llama a `tab.transcribe`; el Mac las transcribe al abrir).
    func accept() async throws -> TabState {
        guard let plan, stage == .pairing else { throw RPCError(code: "not-ready", message: "No hay emparejamiento que aceptar.") }
        let (session, ctl) = try owner.require()
        guard let store = owner.tabStore else {
            throw RPCError(code: "unsupported", message: "No hay biblioteca donde guardar la fuente.")
        }
        let result = plan.build()
        let pairings = plan.assignments.map { a in
            TabStemPairing(stemID: a.stemID, partId: a.track.flatMap { plan.tracks[$0].partId },
                           solos: a.solos.isEmpty ? nil : a.solos.map { s in
                               TabSoloPairing(start: s.span.lowerBound, end: s.span.upperBound,
                                              partId: s.track.flatMap { plan.tracks[$0].partId }, confidence: s.confidence)
                           })
        }
        let choice = TabSourceChoice.songsterr(songId: plan.songId, revisionId: plan.revisionId, pairings: pairings)
        importTask?.cancel()
        owner.replaceScore(result.score)
        if let grid {
            do { try grid.save(to: session.layout.tabSongsterrGridFile) } catch {
                throw RPCError(code: "internal", message: "No se pudo guardar la rejilla de Songsterr: \(error)")
            }
            session.songsterrGrid = grid
        }
        do { try await store.saveTabSource(choice, for: session.projectID) } catch {
            throw RPCError(code: "internal", message: "No se pudo guardar la fuente: \(error)")
        }
        session.reload()
        ctl.refreshMetronome()
        let warnings = plan.warnings
        _ = close()
        let opened = try await owner.open(projectId: session.projectID.uuidString)
        _ = opened
        owner.setNotices(warnings)
        return owner.state()
    }

    /// «Transcribir automáticamente»: vuelve a `automatic`.
    func chooseAutomatic() async throws -> TabState {
        _ = try owner.require()
        _ = close()
        return try await owner.setSource("automatic")
    }

    // MARK: Estado

    func state() -> SongsterrSheetState {
        var s = SongsterrSheetState(open: isOpen, stage: "choosing", query: nil, search: nil, results: [], selected: nil,
                                    loadingSongId: nil, detailIssue: nil, linkIssue: nil, busy: false, canUse: false,
                                    workingText: nil, failure: nil, pairing: nil)
        guard isOpen, let lookup else { return s }
        let song = owner.session?.project.song
        s.query = song.map { [$0.artist, $0.title].compactMap { $0 }.joined(separator: " · ") }
        switch stage {
        case .choosing: s.stage = "choosing"
        case .working(let t): s.stage = "working"; s.workingText = t
        case .pairing: s.stage = "pairing"
        case .failed(let i): s.stage = "failed"; s.failure = SongsterrIssueInfo(i)
        }
        let phase: String
        var issue: SongsterrIssueInfo?
        switch lookup.phase {
        case .idle: phase = "idle"
        case .searching: phase = "searching"
        case .results: phase = "results"
        case .failed(let i): phase = "failed"; issue = SongsterrIssueInfo(i)
        }
        s.search = SongsterrSearchInfo(phase: phase, issue: issue)
        s.results = lookup.results.map {
            SongsterrResultInfo(songId: $0.songId, artist: $0.artist, title: $0.title, selected: $0.songId == lookup.selectedID,
                                loading: $0.songId == lookup.loadingID, previewUrl: SongsterrReader.songURL(songId: $0.songId)?.absoluteString)
        }
        if let sel = lookup.selectedSong {
            s.selected = SongsterrSongInfo(
                songId: sel.songId, revisionId: sel.revisionId, artist: sel.artist, title: sel.title,
                tracks: sel.tracks.map {
                    SongsterrTrackInfo(partId: $0.partId, name: $0.name, instrument: $0.instrument, tuning: $0.tuning,
                                       tuningText: Self.tuningText($0.tuning))
                },
                previewUrl: SongsterrReader.songURL(songId: sel.songId)?.absoluteString)
        }
        s.loadingSongId = lookup.loadingID
        s.detailIssue = lookup.detailIssue.map(SongsterrIssueInfo.init)
        s.linkIssue = lookup.linkIssue.map(SongsterrIssueInfo.init)
        s.busy = lookup.isBusy
        s.canUse = lookup.selectedSong != nil
        if stage == .pairing, let plan { s.pairing = Self.pairingInfo(plan) }
        return s
    }

    /// «E A D G B E» de la cuerda más grave a la más aguda; «-» en batería (Mac: `TabSourceSheet.tuningText`).
    nonisolated static func tuningText(_ tuning: [Int]?) -> String {
        guard let tuning, !tuning.isEmpty else { return "-" }
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return tuning.reversed().map { names[(($0 % 12) + 12) % 12] }.joined(separator: " ")
    }

    nonisolated static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded())) %" }

    private nonisolated static func choice(_ c: SongsterrTrackChoice) -> SongsterrChoiceInfo {
        SongsterrChoiceInfo(track: c.track, name: c.name, similarity: c.similarity,
                            label: c.name + (c.similarity.map { " (\(percent($0)))" } ?? ""))
    }

    nonisolated static func pairingInfo(_ plan: SongsterrImportPlan) -> SongsterrPairingInfo {
        let slots = plan.slots.map { slot -> SongsterrSlotInfo in
            let a = plan.assignment(for: slot.id)
            let lead = slot.role == .guitarLead
            let solos = lead ? (a?.solos ?? []).enumerated().map { k, s in
                SongsterrSoloRowInfo(index: k, start: s.span.lowerBound, end: s.span.upperBound,
                                     clock: SongsterrImportPlan.clockText(s.span.lowerBound), track: s.track,
                                     confidence: s.confidence,
                                     confidenceText: s.track == nil ? nil : (s.confidence.map(percent) ?? "sin medir"),
                                     choices: plan.soloChoices(for: slot.id, solo: k).map(choice))
            } : []
            return SongsterrSlotInfo(
                stemId: slot.id, name: slot.name, kind: slot.kind.rawValue, role: lead ? "lead" : slot.role.rawValue,
                track: lead ? nil : a?.track, confidence: lead ? nil : a?.confidence,
                confidenceText: lead || a?.track == nil ? nil : (a?.confidence.map(percent) ?? "sin medir"),
                choices: lead ? [] : plan.choices(for: slot.id).map(choice), solos: solos)
        }
        let extra = plan.extraTracks.map { plan.tracks[$0].name }
        return SongsterrPairingInfo(
            intro: pairingIntro, slots: slots, extraNames: extra,
            extraText: extra.isEmpty ? nil
                : "Pistas extra, sin stem: \(extra.joined(separator: ", ")). Entran en la tablatura y en el .gp y solo suenan con «Oír transcripción».",
            warnings: plan.warnings)
    }
}

// MARK: - Métodos tab.songsterr.*

extension TabService {
    nonisolated func registerSongsterr(on router: Router) {
        router.register("tab.songsterr.open") { [self] (_: Empty) -> SongsterrSheetState in try await songsterr.open() }
        router.register("tab.songsterr.state") { [self] (_: Empty) -> SongsterrSheetState in await songsterr.state() }
        router.register("tab.songsterr.close") { [self] (_: Empty) -> SongsterrSheetState in await songsterr.close() }
        router.register("tab.songsterr.search") { [self] (_: Empty) -> SongsterrSheetState in try await songsterr.research() }
        router.register("tab.songsterr.retry") { [self] (_: Empty) -> SongsterrSheetState in try await songsterr.retry() }
        router.register("tab.songsterr.select") { [self] (p: SongsterrSelectParams) -> SongsterrSheetState in
            try await songsterr.select(songId: p.songId)
        }
        router.register("tab.songsterr.link") { [self] (p: SongsterrLinkParams) -> SongsterrSheetState in
            try await songsterr.submitLink(p.link)
        }
        router.register("tab.songsterr.use") { [self] (_: Empty) -> SongsterrSheetState in try await songsterr.useSelected() }
        router.register("tab.songsterr.review") { [self] (_: Empty) -> SongsterrSheetState in try await songsterr.reviewPairing() }
        router.register("tab.songsterr.retryImport") { [self] (_: Empty) -> SongsterrSheetState in try await songsterr.retryImport() }
        router.register("tab.songsterr.back") { [self] (_: Empty) -> SongsterrSheetState in try await songsterr.back() }
        router.register("tab.songsterr.assign") { [self] (p: SongsterrAssignParams) -> SongsterrSheetState in
            try await songsterr.assign(stemId: p.stemId, track: p.track, solo: p.solo)
        }
        router.register("tab.songsterr.allAutomatic") { [self] (_: Empty) -> SongsterrSheetState in try await songsterr.allAutomatic() }
        router.register("tab.songsterr.accept") { [self] (_: Empty) -> TabState in try await songsterr.accept() }
        router.register("tab.songsterr.automatic") { [self] (_: Empty) -> TabState in try await songsterr.chooseAutomatic() }
    }
}
