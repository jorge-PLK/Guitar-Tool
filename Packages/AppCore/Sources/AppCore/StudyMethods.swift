import AudioKit
import Foundation
import Store

// Métodos `study.*` y eventos de Backing (parte 8.5). Contrato: `Temp/win/step8-contract.md`, «Backing: núcleo de estudio».

// MARK: - Constantes (mini-spec Fase 2 §2 y plan, paso 8)

enum StudyConstants {
    /// Máximo de eventos `study.position` y `study.levels` por segundo (encargo 8.5).
    static let eventHz = 30.0
    /// Separación mínima entre dos emisiones; un 10 % menos que el periodo para no perder ticks por jitter del reloj.
    static let minEventSpacing = 0.9 / eventHz
    /// Nivel por debajo del cual un canal cuenta como silencio (`BackingView`: `rmsDB > -119`).
    static let silentDB: Float = -119
    /// Orden y nombre de los canales del mezclador (`BackingMixer.order`).
    static let channelOrder: [(kind: StemKind, name: String)] = [
        (.vocals, "Voz"), (.drums, "Batería"), (.bass, "Bajo"), (.guitar, "Guitarra"), (.piano, "Piano"), (.other, "Resto")
    ]
    static func name(of kind: StemKind) -> String { channelOrder.first { $0.kind == kind }?.name ?? kind.rawValue }
}

// MARK: - Tipos JSON

struct StudyChannel: Codable, Sendable {
    var id: String
    var kind: String
    var guitarRole: String?
    var name: String
    var gainDB: Double
    var muted: Bool
    var solo: Bool
}

struct StudyMetronome: Codable, Sendable {
    var on: Bool
    var gainDB: Double
    var available: Bool
}

struct StudyLoop: Codable, Sendable {
    var start: Double
    var end: Double
    var name: String?
}

struct StudyTransport: Codable, Sendable {
    var playing: Bool
    var position: Double
    var duration: Double
    var rate: Double
    var transpose: Int
    var fineCents: Double
    var capo: Int
    var metronome: StudyMetronome
    var loop: StudyLoop?
    var masterGainDB: Double
    var channels: [StudyChannel]
    var anySolo: Bool
    var audioError: String?
    /// Nombre del aparato de salida (8.6d-C): igual que `study.open.audio.outputName`; ya al abrir también en Windows (8.6d-A).
    var outputName: String
}

struct StudyChord: Codable, Sendable {
    var start: Double
    var end: Double
    var index: Int
    var name: String
    var overridden: Bool
}

struct StudyKey: Codable, Sendable {
    var detected: String?
    var override: String?
    var effective: String?
    var confidence: Double?
}

struct StudyAnalysisInfo: Codable, Sendable {
    var state: String
    var error: String?
    var beats: [Double]
    var downbeats: [Double]
    var bpm: Double?
    var beatsPerBar: Int?
    var chords: [StudyChord]
    var key: StudyKey
}

struct StudyEmptyStem: Codable, Sendable {
    var kind: String
    var name: String
}

struct StudyOverrideInfo: Codable, Sendable {
    var start: Double
    var end: Double
    var index: Int
}

struct StudySectionInfo: Codable, Sendable {
    var id: String
    var name: String
    var start: Double
    var end: Double
    var solo: Bool
    var color: Int?
    var paletteIndex: Int?
}

struct StudySavedLoop: Codable, Sendable {
    var id: String
    var name: String
    var start: Double
    var end: Double
}

struct StudyAudioInfo: Codable, Sendable {
    var mode: String
    var outputName: String
}

struct StudyOpenResult: Codable, Sendable {
    var projectId: String
    var title: String
    var artist: String?
    var duration: Double
    var sampleRate: Double
    var loadError: String?
    var audio: StudyAudioInfo
    var transport: StudyTransport
    var emptyStems: [StudyEmptyStem]
    var usesSeparatedGuitars: Bool
    var analysis: StudyAnalysisInfo
    var chordOverrides: [StudyOverrideInfo]
    var sections: [StudySectionInfo]
    /// 8.6d-C: igual que `EditState.unappliedSections` y `EditState.guitars`.
    var unappliedSections: Bool
    var loops: [StudySavedLoop]
    var guitars: StudyGuitarsInfo
}

struct StudyPositionEvent: Codable, Sendable {
    var seconds: Double
    var playing: Bool
}

struct StudyMeter: Codable, Sendable {
    var rmsDB: Double
    var peakDB: Double
}

struct StudyLevelsEvent: Codable, Sendable {
    var channels: [String: StudyMeter]
}

struct StudyErrorEvent: Codable, Sendable {
    var code: String
    var message: String
}

struct StudyOpenParams: Decodable, Sendable { var projectId: String }
struct StudySeekParams: Decodable, Sendable { var seconds: Double }
struct StudyRateParams: Decodable, Sendable { var rate: Double }
struct StudyTransposeParams: Decodable, Sendable { var semitones: Int?; var fineCents: Double? }
struct StudyCapoParams: Decodable, Sendable { var capo: Int }
struct StudyLoopParams: Decodable, Sendable { var start: Double?; var end: Double?; var name: String? }
struct StudyMixParams: Decodable, Sendable { var channel: String; var gainDB: Double?; var mute: Bool?; var solo: Bool? }
struct StudyMasterParams: Decodable, Sendable { var gainDB: Double }
struct StudyMetronomeParams: Decodable, Sendable { var on: Bool?; var gainDB: Double? }

// MARK: - Servicio

/// Tema abierto en Backing: sesión de estudio + controlador del reproductor + salida de audio. Lo usará Tablatura.
struct StudyOpen {
    let session: StudySession
    let controller: BackingController
}

/// Salida de eventos y estado de la pantalla Backing. Vive en el hilo principal (el reproductor es `@MainActor`).
@MainActor
final class StudyService {
    private let options: LaunchOptions
    private let root: ProjectsRoot
    /// Dónde se escribe el estudio de un tema (por defecto `project.json` directo; 8.3a puede poner `Library`).
    var storeFactory: @Sendable (URL) -> any StudyStoring = { FileStudyStore(folder: $0) }

    private let outbox = Outbox()
    /// Tema abierto (para Tablatura: la sesión y el reproductor, con pista extra y mute/solo compartidos).
    private(set) var current: StudyOpen?

    private var ticker: Task<Void, Never>?
    private var statePending = false
    private var lastPosition = -1.0
    private var lastPositionPlaying = false
    private var lastPlaying = false
    private var lastPositionAt = 0.0
    private var lastLevelsAt = 0.0
    private var lastLevelsLoud = false
    private var masterSaveTask: Task<Void, Never>?
    /// Cola de trabajos y último estado de análisis emitido (parte 8.5b, `StudyEdits.swift`).
    let edits = StudyEditsLink()
    private let profileStore: ProfileStore?
    /// W2-C: servicio de `audio.*` (dueño de la sesión de audio). Si hay una sesión abierta con guitarra asignada, el reproductor de
    /// estudio se engancha a ella (como `BackingController` con `AudioController` en el Mac). nil = sin `audio.*`.
    nonisolated(unsafe) var audioService: AudioService?
    /// W2-R1: se llama al empezar `close()` (Grabar se cierra con el tema).
    nonisolated(unsafe) var onClosing: (@MainActor @Sendable () async -> Void)?
    /// Controlador al que está enganchado el tema abierto.
    private var audioController: AudioController?

    nonisolated init(options: LaunchOptions, root: ProjectsRoot, storeFactory: (@Sendable (URL) -> any StudyStoring)? = nil) {
        self.options = options
        self.root = root
        if let storeFactory { self.storeFactory = storeFactory }
        // En simulado sin `--support-dir` no se toca el perfil real (el volumen master solo vive en memoria).
        if let dir = options.supportDir {
            profileStore = ProfileStore(url: dir.appendingPathComponent("profile.json"))
        } else {
            profileStore = options.audio == .simulated ? nil : ProfileStore()
        }
    }

    /// La pone el anfitrión (vía `Bridge`); cualquier hilo.
    nonisolated func setSink(_ sink: @escaping @Sendable (String) -> Void) { outbox.set(sink) }

    func emit<T: Encodable>(_ event: String, _ payload: T) {
        if let m = Router.eventMessage(event, payload) { outbox.send(m) }
    }

    nonisolated func register(on router: Router) {
        router.register("study.open") { [self] (p: StudyOpenParams) -> StudyOpenResult in try await open(p) }
        router.register("study.close") { [self] (_: Empty) -> Empty in await close(); return Empty() }
        router.register("study.play") { [self] (_: Empty) -> StudyTransport in
            try await with { c in try c.play() }
        }
        router.register("study.pause") { [self] (_: Empty) -> StudyTransport in try await with { c in c.pause() } }
        router.register("study.seek") { [self] (p: StudySeekParams) -> StudyTransport in
            try await with { c in c.seek(to: p.seconds) }
        }
        router.register("study.setRate") { [self] (p: StudyRateParams) -> StudyTransport in
            try await with { c in c.setRate(p.rate) }
        }
        router.register("study.setTranspose") { [self] (p: StudyTransposeParams) -> StudyTransport in
            try await with { c in
                if let s = p.semitones { c.setTranspose(s) }
                if let f = p.fineCents { c.setFineCents(f) }
            }
        }
        router.register("study.setCapo") { [self] (p: StudyCapoParams) -> StudyTransport in
            try await with { c in c.setCapo(p.capo) }
        }
        router.register("study.setLoop") { [self] (p: StudyLoopParams) -> StudyTransport in
            try await with { c in
                if let s = p.start, let e = p.end, s.isFinite, e.isFinite { c.setLoop(s...max(s, e), name: p.name) } else { c.setLoop(nil) }
            }
        }
        router.register("study.setMix") { [self] (p: StudyMixParams) -> StudyTransport in
            try await with { c in
                guard c.setMix(playerTrack: p.channel, gainDB: p.gainDB, mute: p.mute, solo: p.solo) else {
                    throw RPCError(code: "bad-params", message: "«channel» no es un canal del mezclador: \(p.channel)")
                }
            }
        }
        router.register("study.setMaster") { [self] (p: StudyMasterParams) -> StudyTransport in
            try await with { c in c.setMaster(p.gainDB) }
        }
        router.register("study.setMetronome") { [self] (p: StudyMetronomeParams) -> StudyTransport in
            try await with { c in c.setMetronome(on: p.on, gainDB: p.gainDB) }
        }
        registerEdits(on: router)   // 8.5b, `StudyEdits.swift`
    }

    // MARK: Abrir y cerrar

    func open(_ p: StudyOpenParams) async throws -> StudyOpenResult {
        guard let id = UUID(uuidString: p.projectId) else {
            throw RPCError(code: "bad-params", message: "«projectId» no es un UUID.")
        }
        let folder = try Bridge.service(root).folder(id: id)
        let project: Project
        do { project = try ProjectFile.load(folder: folder) } catch {
            throw RPCError(code: "internal", message: "No se pudo leer project.json: \(error)")
        }
        await close()
        let profile = (try? profileStore?.load()) ?? EquipmentProfile()
        let output = OutputSelection(deviceUID: profile.audio?.outputDeviceUID,
                                     left: profile.audio?.backingOut.left ?? 1, right: profile.audio?.backingOut.right ?? 2)
        let session = StudySession(project: project, folder: folder, store: storeFactory(folder))
        let audio = StudyAudio(mode: options.audio, output: output)
        let hostController = audioService?.controller()
        if let hostController {
            hostController.start()
            audio.externalHost = { hostController.wouldHostPlayer }
        }
        let controller = BackingController(session: session, audio: audio, masterGainDB: profile.masterGainDB)
        if let hostController {
            hostController.onHostingEnded = { [weak audio] in audio?.restoreOwnOutput() }
            hostController.bind(player: controller.player, study: session)
            audioController = hostController
        }
        // Como el Mac (`AppModel.openStudy`): un tema separado sin análisis vigente lo pide al abrir.
        // Sin analizador o sin separación no es error: se queda en `missing`.
        if let jobs = edits.jobs, project.separation.state == .done,
           let state = try? await jobs.library().ensureAnalysis(id: id), state != .missing {
            session.setAnalysisState(state)
        }
        session.onChange = { [weak self] in self?.stateChanged() }
        controller.onMasterChange = { [weak self] g in self?.saveMaster(g) }
        current = StudyOpen(session: session, controller: controller)
        resetTicker()
        lastPosition = controller.player.currentTime
        return snapshot(session, controller)
    }

    /// Relee el proyecto si es el tema abierto en Backing (como `model.study?.reload()` del Mac tras borrar una toma).
    func reloadIfOpen(_ id: UUID) {
        if current?.session.projectID == id { current?.session.reload() }
    }

    /// Para, guarda ya (`flush`) y suelta los ficheros de audio. También lo llama el cierre del anfitrión.
    func close() async {
        ticker?.cancel()
        ticker = nil
        await onClosing?()   // W2-R1: Grabar usa la sesión del tema; se cierra antes
        guard let o = current else { return }
        current = nil
        o.session.onChange = nil
        audioController?.unbind()
        audioController = nil
        o.controller.shutdown()
        if o.session.hasPendingSave { await o.session.flush() }
        if let t = masterSaveTask {
            t.cancel()
            masterSaveTask = nil
            writeMaster(o.controller.masterGainDB)
        }
    }

    /// Ejecuta un cambio sobre el controlador y devuelve el transporte ya actualizado.
    private func with(_ change: @MainActor (BackingController) throws -> Void) async throws -> StudyTransport {
        guard let o = current else { throw RPCError(code: "not-open", message: "No hay ningún tema abierto en Backing.") }
        defer { stateChanged() }
        try change(o.controller)
        return transport(o.session, o.controller)
    }

    // MARK: Volumen master (perfil)

    private func saveMaster(_ gainDB: Double) {
        guard profileStore != nil else { return }
        masterSaveTask?.cancel()
        masterSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(StudySession.saveDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.masterSaveTask = nil
            self?.writeMaster(gainDB)
        }
    }

    private func writeMaster(_ gainDB: Double) {
        guard let store = profileStore else { return }
        var profile = (try? store.load()) ?? EquipmentProfile()
        guard profile.masterGainDB != gainDB else { return }
        profile.masterGainDB = gainDB
        try? store.save(profile)
    }

    // MARK: Estado

    /// Coalesce los cambios de un mismo turno en un solo `study.state`, ya con el reproductor al día.
    func stateChanged() {
        guard !statePending else { return }
        statePending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            statePending = false
            guard let o = current else { return }
            emit("study.state", transport(o.session, o.controller))
        }
    }

    func channels(_ s: StudySession) -> [StudyChannel] {
        var out: [StudyChannel] = []
        let mixer = s.mixerStems
        for (kind, name) in StudyConstants.channelOrder {
            if kind == .guitar, s.usesSeparatedGuitars {
                for g in s.guitarTracks {
                    let m = s.mix(forGuitar: g.role)
                    out.append(StudyChannel(id: g.role.trackID, kind: "guitar", guitarRole: g.role.rawValue,
                                            name: s.guitarName(g.role), gainDB: m.gainDB, muted: m.muted, solo: m.solo))
                }
            } else if mixer.contains(kind) {
                let m = s.mix(for: kind)
                out.append(StudyChannel(id: kind.rawValue, kind: kind.rawValue, guitarRole: nil, name: name,
                                        gainDB: m.gainDB, muted: m.muted, solo: m.solo))
            }
        }
        return out
    }

    func transport(_ s: StudySession, _ c: BackingController) -> StudyTransport {
        let p = c.settings
        return StudyTransport(
            playing: c.isPlaying, position: c.player.currentTime, duration: c.duration, rate: p.rate,
            transpose: p.transpose, fineCents: p.fineCents, capo: p.capo,
            metronome: StudyMetronome(on: p.metronomeOn, gainDB: p.metronomeGainDB, available: s.hasBeatGrid),
            loop: c.loop.map { StudyLoop(start: $0.lowerBound, end: $0.upperBound, name: c.loopName) },
            masterGainDB: c.masterGainDB, channels: channels(s), anySolo: c.anyStemSolo, audioError: c.audioError,
            outputName: c.audio.outputName)
    }

    func snapshot(_ s: StudySession, _ c: BackingController) -> StudyOpenResult {
        let analysis = analysisInfo(s)
        let sections = sectionInfos(s)
        return StudyOpenResult(
            projectId: s.projectID.uuidString, title: s.project.song.title, artist: s.project.song.artist,
            duration: c.duration, sampleRate: s.project.song.sampleRate, loadError: c.loadError,
            audio: StudyAudioInfo(mode: c.audio.mode.rawValue, outputName: c.audio.outputName),
            transport: transport(s, c),
            emptyStems: s.emptyStems.map { StudyEmptyStem(kind: $0.rawValue, name: StudyConstants.name(of: $0)) },
            usesSeparatedGuitars: s.usesSeparatedGuitars, analysis: analysis,
            chordOverrides: s.study.chordOverrides.map { StudyOverrideInfo(start: $0.start, end: $0.end, index: $0.index) },
            sections: sections, unappliedSections: s.hasUnappliedSections,
            loops: s.study.loops.map { StudySavedLoop(id: $0.id.uuidString, name: $0.name, start: $0.start, end: $0.end) },
            guitars: guitarsInfo(s))
    }

    // MARK: Posición y niveles (máx. 30 Hz)

    private func resetTicker() {
        lastPosition = -1
        lastPositionPlaying = false
        lastPlaying = false
        lastPositionAt = 0
        lastLevelsAt = 0
        lastLevelsLoud = false
        ticker?.cancel()
        ticker = Task { [weak self] in
            let clock = ContinuousClock()
            let period = Duration.nanoseconds(Int64(1_000_000_000 / StudyConstants.eventHz))
            var next = clock.now + period
            while !Task.isCancelled {
                try? await clock.sleep(until: next)
                guard !Task.isCancelled, let self else { return }
                tick()
                next = max(next + period, clock.now)
            }
        }
    }

    private func tick() {
        guard let o = current else { return }
        let c = o.controller
        let now = ProcessInfo.processInfo.systemUptime
        let playing = c.isPlaying
        if playing != lastPlaying {   // fin del tema o parada desde fuera
            lastPlaying = playing
            stateChanged()
        }
        if now - lastPositionAt >= StudyConstants.minEventSpacing {
            let t = c.player.currentTime
            if playing || t != lastPosition || playing != lastPositionPlaying {
                lastPositionAt = now
                lastPosition = t
                lastPositionPlaying = playing
                emit("study.position", StudyPositionEvent(seconds: t, playing: playing))
            }
        }
        if now - lastLevelsAt >= StudyConstants.minEventSpacing, playing || lastLevelsLoud {
            let ids = Set(channels(o.session).map(\.id))
            let meters = c.player.meters.filter { ids.contains($0.key) }
            let loud = meters.values.contains { $0.rmsDB > StudyConstants.silentDB }
            lastLevelsAt = now
            lastLevelsLoud = loud   // al quedar en silencio sale una última, ya a -120 dB, y se para
            emit("study.levels", StudyLevelsEvent(channels: meters.mapValues {
                StudyMeter(rmsDB: Double($0.rmsDB.isFinite ? $0.rmsDB : -120), peakDB: Double($0.peakDB.isFinite ? $0.peakDB : -120))
            }))
        }
    }
}

/// Sale de eventos segura entre hilos (la pone el anfitrión desde cualquiera).
private final class Outbox: @unchecked Sendable {
    private let lock = NSLock()
    private var sink: @Sendable (String) -> Void = { _ in }
    func set(_ s: @escaping @Sendable (String) -> Void) { lock.withLock { sink = s } }
    func send(_ m: String) { lock.withLock { sink }(m) }
}

// MARK: - Bridge

extension Bridge {
    /// Guarda el tema abierto en Backing y suelta su audio; el anfitrión lo llama al cerrar la ventana.
    public func closeStudy() async { await studyService.close() }
}
