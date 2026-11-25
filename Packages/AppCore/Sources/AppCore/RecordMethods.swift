import AudioKit
import Foundation
import Store
import VideoKit

// Métodos y eventos `record.*` (paso 8, ola 2, W2-R1). Contrato en `Temp/win/step8-contract.md`, sección «W2-R1 record.*».
// Los textos de error son los de `RecordController.swift` y `AppLogic.swift` (RecordBlock) del Mac.

// MARK: - Tipos del contrato

struct RecordGuitarRole: Codable, Sendable, Equatable {
    var role: String
    var name: String
}

struct RecordPunchTake: Codable, Sendable, Equatable {
    var start: Double
    var end: Double
    var hasVideo: Bool
    /// Ruta relativa a la carpeta de proyectos (`<tema>/takes/<id>/punch-1/video.mov`).
    var videoPath: String?
    var videoOffsetMs: Double?
}

struct RecordTakeFormat: Codable, Sendable, Equatable {
    var cameraId: String
    var cameraName: String
    var width: Int
    var height: Int
    var fps: Double
}

struct RecordTakeInfo: Codable, Sendable, Equatable {
    var id: String
    /// Posición en su parte (1...).
    var number: Int
    var createdAt: Date
    var best: Bool
    var selected: Bool
    var discarded: Bool
    var durationSeconds: Double?
    var songStart: Double?
    var hasVideo: Bool
    var videoPath: String?
    /// Desfase audio/vídeo (ms, positivo = la imagen llega tarde).
    var videoOffsetMs: Double?
    var videoRotation: Int
    var videoFormat: RecordTakeFormat?
    var audioPath: String?
    var punches: [RecordPunchTake]
}

struct RecordPartInfo: Codable, Sendable, Equatable {
    var id: String
    var name: String
    var replaces: String?
    var isLead: Bool
    /// `pending` | `recording` | `done`.
    var status: String
    var bestTakeId: String?
    var takes: [RecordTakeInfo]
}

struct RecordPunchInfo: Codable, Sendable, Equatable {
    var enabled: Bool
    var `in`: Double?
    var out: Double?
    /// Hay toma elegida con audio alineado y entrada y salida marcadas.
    var ready: Bool
}

struct RecordMixChannel: Codable, Sendable, Equatable {
    var id: String
    var kind: String
    var guitarRole: String?
    var name: String
    var gainDB: Double
    var muted: Bool
    var solo: Bool
    /// La guitarra de la parte que se graba: silenciada y no se puede reactivar.
    var forcedMuted: Bool
}

struct RecordTakeChannel: Codable, Sendable, Equatable {
    var id: String
    var partId: String
    /// «Tú · nombre de la parte».
    var name: String
    var gainDB: Double
    var muted: Bool
    var solo: Bool
}

struct RecordMixInfo: Codable, Sendable, Equatable {
    var masterGainDB: Double
    var channels: [RecordMixChannel]
    var takeChannels: [RecordTakeChannel]
    var anySolo: Bool
    var outputName: String
}

struct RecordCameraEntry: Codable, Sendable, Equatable {
    var id: String
    var name: String
}

struct RecordCameraInfo: Codable, Sendable, Equatable {
    /// `idle` | `none` | `denied` | `simulated` | `failed` | `live`.
    var state: String
    var message: String?
    var name: String?
    var label: String?
    var width: Int?
    var height: Int?
    var fps: Double?
    var rotation: Int
    var defaultOffsetMs: Double?
    var cameras: [RecordCameraEntry]
    var chosenId: String?
}

struct RecordOffsetInfo: Codable, Sendable, Equatable {
    var takeId: String
    var isNew: Bool
    var videoPath: String
    var audioPath: String
    var songStart: Double
    var fps: Double
    var frameMs: Double
    var cameraId: String
    var cameraName: String
    var initialMs: Double
    var valueMs: Double
    var minMs: Double
    var maxMs: Double
    var rotation: Int
    var punches: [RecordPunchTake]
}

struct RecordAudioInfo: Codable, Sendable, Equatable {
    var sessionOpen: Bool
    var hosting: Bool
    var recording: Bool
    var outputName: String
}

struct RecordSnapshot: Codable, Sendable {
    var projectId: String
    var title: String
    /// `idle` | `counting` | `recording` | `finishing` | `adjusting`.
    var phase: String
    /// Pulso de la cuenta (1...compás) en `counting`.
    var countBeat: Int?
    var beatsPerBar: Int
    var barSeconds: Double
    var bpm: Double
    var downbeats: [Double]
    var duration: Double
    /// Posición del reproductor de Grabar; no cuenta como cambio para `record.state` (va en `record.position`).
    var position: Double
    var busy: Bool
    var blockReason: String?
    /// `blockReason` por código: `{code:"record-block-…", message, args?}`; nil si se puede grabar.
    var block: CoreMessage?
    var loadError: String?
    var messages: [String]
    /// Avisos de la última toma del dispositivo (`AudioController.takeNotices`).
    var notices: [String]
    var takeSaveError: String?
    var countIn: Bool
    var preRollBars: Int
    var startSectionId: String?
    var startTime: Double
    var plannedStop: Double?
    var sections: [StudySectionInfo]
    var guitarRoles: [RecordGuitarRole]
    var parts: [RecordPartInfo]
    var activePartId: String?
    var nextTakeNumber: Int
    var selectedTakeId: String?
    var punch: RecordPunchInfo
    var mix: RecordMixInfo
    var camera: RecordCameraInfo
    var offset: RecordOffsetInfo?
    var audio: RecordAudioInfo
}

struct RecordPositionEvent: Codable, Sendable {
    var seconds: Double
    var playing: Bool
    var phase: String
}

struct RecordLevelsEvent: Codable, Sendable {
    var channels: [String: StudyMeter]
}

struct RecordOpenParams: Decodable, Sendable { var projectId: String? }
struct RecordPartParams: Decodable, Sendable { var partId: String }
struct RecordAddPartParams: Decodable, Sendable { var name: String; var replaces: String? }
struct RecordSectionParams: Decodable, Sendable { var sectionId: String? }
struct RecordOnParams: Decodable, Sendable { var on: Bool }
struct RecordBarsParams: Decodable, Sendable { var bars: Int }
struct RecordTakeParams: Decodable, Sendable { var takeId: String? }
struct RecordPunchParams: Decodable, Sendable {
    var enabled: Bool?
    var entry: Double?
    var exit: Double?
    var clearIn: Bool?
    var clearOut: Bool?
    var free: Bool?
    private enum CodingKeys: String, CodingKey { case enabled, entry = "in", exit = "out", clearIn, clearOut, free }
}
struct RecordCameraParams: Decodable, Sendable { var cameraId: String? }
struct RecordOffsetParams: Decodable, Sendable { var valueMs: Double?; var deltaMs: Double?; var frames: Double? }
struct RecordFinishOffsetParams: Decodable, Sendable { var save: Bool; var makeDefault: Bool? }
struct RecordMixParams: Decodable, Sendable { var channel: String; var gainDB: Double?; var mute: Bool?; var solo: Bool? }
struct RecordAllowedResult: Codable, Sendable { var allowed: Bool }

// MARK: - Servicio

/// Pantalla Grabar del tema abierto en Backing: dueño del `RecordController` y de los eventos. Vive en el hilo principal.
@MainActor
final class RecordService {
    /// Canal de la cámara (contrato W2-E1): `frames.camera`.
    nonisolated static let cameraChannel = "camera"
    private let options: LaunchOptions
    private let studyService: StudyService
    private let emitRaw: @Sendable (String) -> Void
    /// Cámaras (los tests las ponen antes de `record.open`); nil = `RecordEnvironment.cameras` o según `--audio`.
    var cameras: RecordCameraSource?
    /// Relevo `frames.camera` mientras Grabar está abierta (W2-E2); lo da el `Bridge` (tests: uno a medida). nil = sin vista previa.
    /// Se pone al crear el `Bridge`, antes de cualquier método (o en los tests antes de `record.open`).
    nonisolated(unsafe) var makeCameraRelay: (@Sendable () -> FrameRelay?)?
    /// Antes de abrir la cámara de Grabar (la vista previa de Ajustes la suelta).
    nonisolated(unsafe) var willOpenCamera: (@MainActor @Sendable () -> Void)?
    /// W2-O: antes de cerrar la hoja de desfase (guardar o descartar) y de cerrar Grabar: suelta el reproductor de la hoja.
    nonisolated(unsafe) var willFinishOffset: (@MainActor @Sendable () async -> Void)?
    /// Justo antes de borrar los ficheros de una toma (Grabar ya soltó sus pistas): el visor suelta esa toma si la tiene.
    nonisolated(unsafe) var willDeleteTake: (@MainActor @Sendable (UUID) async -> Void)?
    private(set) var cameraRelay: FrameRelay?
    private let pixelSinkLock = NSLock()
    private nonisolated(unsafe) var _cameraPixelSink: (@Sendable (FramePixelBuffer, Double) -> Void)?

    /// Receptor de píxeles de la cámara (Grabar y vista previa de Ajustes), p. ej. la textura de AppCoreFFI. Con receptor,
    /// el relevo entrega los píxeles sin JPEG; nil = `frames.camera` en JPEG. Vale para las aperturas siguientes.
    nonisolated var cameraPixelSink: (@Sendable (FramePixelBuffer, Double) -> Void)? {
        get { pixelSinkLock.lock(); defer { pixelSinkLock.unlock() }; return _cameraPixelSink }
        set { pixelSinkLock.lock(); _cameraPixelSink = newValue; pixelSinkLock.unlock() }
    }

    /// Relevo de la cámara: de píxeles si hay receptor, si no el JPEG del `Bridge`.
    nonisolated func cameraRelayFactory(_ bridge: Bridge?) -> FrameRelay? {
        if let sink = cameraPixelSink { return FrameRelay(channel: Self.cameraChannel, pixelSink: sink) }
        return bridge?.makeFrameRelay(channel: Self.cameraChannel)
    }

    private(set) var controller: RecordController?
    private var ticker: Task<Void, Never>?
    private var statePending = false
    private var lastKey: Data?
    private var lastPosition = -1.0
    private var lastPlaying = false
    private var lastPhase = "idle"
    private var lastPositionAt = 0.0
    private var lastLevelsAt = 0.0
    private var lastLevelsLoud = false

    nonisolated init(options: LaunchOptions, studyService: StudyService, emit: @escaping @Sendable (String) -> Void) {
        self.options = options
        self.studyService = studyService
        self.emitRaw = emit
    }

    private func emit<T: Encodable>(_ event: String, _ payload: T) {
        if let m = Router.eventMessage(event, payload) { emitRaw(m) }
    }

    nonisolated func register(on router: Router) {
        router.register("record.open") { [self] (p: RecordOpenParams) -> RecordSnapshot in try await open(p) }
        router.register("record.close") { [self] (_: Empty) -> Empty in await close(resume: true); return Empty() }
        router.register("record.state") { [self] (_: Empty) -> RecordSnapshot in try await with { _ in } }
        router.register("record.start") { [self] (_: Empty) -> RecordSnapshot in
            try await with { c in
                if let reason = c.blockReason { throw RPCError(code: "record-blocked", message: reason) }
                guard c.phase == .idle else { throw RPCError(code: "busy", message: "Ya hay una toma en curso.") }
                c.startTake()
            }
        }
        router.register("record.stop") { [self] (_: Empty) -> RecordSnapshot in try await with { $0.stopTake() } }
        router.register("record.cancel") { [self] (_: Empty) -> RecordSnapshot in try await with { $0.cancelTake() } }
        router.register("record.selectPart") { [self] (p: RecordPartParams) -> RecordSnapshot in
            try await with { c in
                guard let id = UUID(uuidString: p.partId), c.state.part(id) != nil else {
                    throw RPCError(code: "not-found", message: "No hay ninguna parte con id \(p.partId).")
                }
                c.selectPart(id)
            }
        }
        router.register("record.addPart") { [self] (p: RecordAddPartParams) -> RecordSnapshot in
            try await with { c in
                var role: GuitarRole?
                if let r = p.replaces {
                    guard let g = GuitarRole(rawValue: r) else { throw RPCError(code: "bad-params", message: "«replaces» no es un papel de guitarra: \(r)") }
                    role = g
                }
                guard c.phase == .idle else { throw RPCError(code: "busy", message: "No se puede añadir una parte grabando.") }
                c.addPart(name: p.name, replaces: role)
            }
        }
        router.register("record.setStartSection") { [self] (p: RecordSectionParams) -> RecordSnapshot in
            try await with { c in
                if let s = p.sectionId {
                    guard let id = UUID(uuidString: s), c.sections.contains(where: { $0.id == id }) else {
                        throw RPCError(code: "not-found", message: "No hay ninguna sección con id \(s).")
                    }
                    c.setStartSection(id)
                } else { c.setStartSection(nil) }
            }
        }
        router.register("record.setCountIn") { [self] (p: RecordOnParams) -> RecordSnapshot in try await with { $0.setCountIn(p.on) } }
        router.register("record.setPreRoll") { [self] (p: RecordBarsParams) -> RecordSnapshot in
            try await with { c in
                guard RecordingState.allowedPreRollBars.contains(p.bars) else {
                    throw RPCError(code: "bad-params", message: "«bars» va de 0 a 2.")
                }
                c.setPreRoll(p.bars)
            }
        }
        router.register("record.setPunch") { [self] (p: RecordPunchParams) -> RecordSnapshot in
            try await with { c in
                guard c.phase == .idle else { return }
                // GR1 (SwiftUI `RecordView.swift:517-518`): al activar el punch sin toma elegida, se elige la mejor de la parte.
                if p.enabled == true, c.selectedTakeID == nil, let best = c.activePart?.bestTakeID { c.selectTake(best) }
                if let e = p.enabled { c.punchEnabled = e }
                guard c.punchEnabled else { return }
                let free = p.free ?? false
                if p.clearIn == true { c.setPunchPoint(entry: true, seconds: nil, free: free) }
                if p.clearOut == true { c.setPunchPoint(entry: false, seconds: nil, free: free) }
                if let t = p.entry, t.isFinite { c.setPunchPoint(entry: true, seconds: t, free: free) }
                if let t = p.exit, t.isFinite { c.setPunchPoint(entry: false, seconds: t, free: free) }
            }
        }
        router.register("record.startPunch") { [self] (p: RecordTakeParams) -> RecordSnapshot in
            try await with { c in c.startPunch(on: try Self.takeID(p, c)) }
        }
        router.register("record.selectTake") { [self] (p: RecordTakeParams) -> RecordSnapshot in
            try await with { c in
                if p.takeId == nil { c.selectTake(nil) } else { c.selectTake(try Self.takeID(p, c)) }
            }
        }
        router.register("record.markBest") { [self] (p: RecordTakeParams) -> RecordSnapshot in
            try await with { c in c.markBest(try Self.takeID(p, c)) }
        }
        router.register("record.deleteTake") { [self] (p: RecordTakeParams) -> RecordSnapshot in
            try await deleteTake(p)
        }
        router.register("record.setCamera") { [self] (p: RecordCameraParams) -> RecordSnapshot in
            try await setCamera(p)
        }
        router.register("record.rotate") { [self] (_: Empty) -> RecordSnapshot in try await with { $0.rotateCamera() } }
        // Sondeo de cámara (SwiftUI lo hace cada 2 s mientras se busca); desvío GR10.
        router.register("record.pollCamera") { [self] (_: Empty) -> RecordSnapshot in try await with { $0.pollCamera() } }
        router.register("record.adjustOffset") { [self] (p: RecordTakeParams) -> RecordSnapshot in
            try await with { c in
                let id = try Self.takeID(p, c)
                guard c.phase == .idle else { throw RPCError(code: "busy", message: "No se puede ajustar el desfase grabando.") }
                c.adjustOffset(takeID: id)
                guard c.offsetRequest != nil else { throw RPCError(code: "no-video", message: "Esa toma no tiene vídeo.") }
            }
        }
        router.register("record.setOffset") { [self] (p: RecordOffsetParams) -> RecordSnapshot in
            try await with { c in
                guard c.offsetRequest != nil else { throw RPCError(code: "no-offset", message: "No hay ninguna hoja de desfase abierta.") }
                if let v = p.valueMs { c.setOffsetMs(v) }
                c.nudgeOffset(ms: p.deltaMs ?? 0, frames: p.frames ?? 0)
            }
        }
        router.register("record.finishOffset") { [self] (p: RecordFinishOffsetParams) -> RecordSnapshot in
            await willFinishOffset?()
            return try await with { c in c.finishOffset(save: p.save, makeDefault: p.makeDefault ?? true) }
        }
        router.register("record.setMix") { [self] (p: RecordMixParams) -> RecordSnapshot in
            try await with { c in try Self.setMix(c, p) }
        }
        router.register("record.setMaster") { [self] (p: StudyMasterParams) -> RecordSnapshot in
            try await with { $0.setMaster(p.gainDB) }
        }
        router.register("record.prepareViewTake") { [self] (_: Empty) -> RecordAllowedResult in
            try await prepareViewTake()
        }
    }

    private func deleteTake(_ p: RecordTakeParams) async throws -> RecordSnapshot {
        let id = try takeID(p)
        if let message = await controller?.deleteTake(id) { throw RPCError(code: "internal", message: message) }
        return try await with { _ in }
    }

    private func setCamera(_ p: RecordCameraParams) async throws -> RecordSnapshot {
        guard let c = controller else { throw Self.notOpen }
        await c.chooseCamera(p.cameraId)
        return try await with { _ in }
    }

    private func prepareViewTake() throws -> RecordAllowedResult {
        guard let c = controller else { throw Self.notOpen }
        return RecordAllowedResult(allowed: c.prepareToViewTake())
    }

    nonisolated static let notOpen = RPCError(code: "not-open", message: "La pantalla Grabar no está abierta.")

    private func takeID(_ p: RecordTakeParams) throws -> UUID {
        guard let c = controller else { throw Self.notOpen }
        return try Self.takeID(p, c)
    }

    private static func takeID(_ p: RecordTakeParams, _ c: RecordController) throws -> UUID {
        guard let s = p.takeId, let id = UUID(uuidString: s) else { throw RPCError(code: "bad-params", message: "«takeId» no es un UUID.") }
        guard c.take(id) != nil else { throw RPCError(code: "not-found", message: "No hay ninguna toma con id \(s).") }
        return id
    }

    private static func setMix(_ c: RecordController, _ p: RecordMixParams) throws {
        if p.channel.hasPrefix("take-"), let id = UUID(uuidString: String(p.channel.dropFirst("take-".count))) {
            guard c.state.part(id) != nil else { throw RPCError(code: "bad-params", message: "«channel» no es un canal de Grabar: \(p.channel)") }
            c.updateTakeMix(id) { m in
                if let g = p.gainDB { m.gainDB = g }
                if let v = p.mute { m.muted = v }
                if let v = p.solo { m.solo = v }
            }
            return
        }
        let forced = c.isForcedMuted(p.channel)
        func change(_ m: inout StemMix) {
            if let g = p.gainDB { m.gainDB = g }
            if !forced {
                if let v = p.mute { m.muted = v }
                if let v = p.solo { m.solo = v }
            }
        }
        if let kind = StemKind(rawValue: p.channel), c.session.mixerStems.contains(kind) {
            c.updateMix(kind, change)
        } else if let g = c.session.guitarTracks.first(where: { $0.role.trackID == p.channel }) {
            c.updateMix(guitar: g.role, change)
        } else {
            throw RPCError(code: "bad-params", message: "«channel» no es un canal de Grabar: \(p.channel)")
        }
    }

    // MARK: Abrir y cerrar

    func open(_ p: RecordOpenParams) async throws -> RecordSnapshot {
        guard let o = studyService.current else {
            throw RPCError(code: "not-open", message: "No hay ningún tema abierto en Backing.")
        }
        if let pid = p.projectId, pid != o.session.projectID.uuidString {
            throw RPCError(code: "bad-params", message: "«projectId» no es el del tema abierto.")
        }
        guard let audioService = studyService.audioService else {
            throw RPCError(code: "internal", message: "No hay servicio de audio.")
        }
        if let c = controller {
            if c.session === o.session { return snapshot(c) }
            await close(resume: false)
        }
        // Backing se aparta: su reproductor suelta la sesión de audio para que Grabar aloje el suyo.
        o.controller.pause()
        let host = audioService.controller()
        host.unbind()
        let jobs = studyService.edits.jobs
        let projectID = o.session.projectID
        let c = RecordController(session: o.session, audio: host, mode: options.audio, cameras: cameraSource(),
                                 deleteTake: { [weak self] takeID in
            guard let jobs else { throw RPCError(code: "internal", message: "No hay biblioteca.") }
            await self?.willDeleteTake?(takeID)
            try await jobs.library().deleteTake(projectID: projectID, takeID: takeID)
        })
        c.onChange = { [weak self] in self?.stateChanged() }
        if let relay = makeCameraRelay?() {
            cameraRelay = relay
            c.onPreviewFrame = Self.previewHook(relay)
        }
        willOpenCamera?()
        c.open()
        controller = c
        lastKey = nil
        startTicker()
        return snapshot(c)
    }

    /// Hay una cuenta atrás, una toma o un ajuste en curso (B2: no se mueve la carpeta mientras tanto).
    var isBusy: Bool { controller.map { $0.phase != .idle } ?? false }

    /// `resume`: devuelve el reproductor de Backing a la sesión de audio (false si Backing también se cierra).
    func close(resume: Bool) async {
        await willFinishOffset?()
        ticker?.cancel()
        ticker = nil
        guard let c = controller else { return }
        controller = nil
        c.onChange = nil
        c.onPreviewFrame = nil
        cameraRelay?.stop()
        cameraRelay = nil
        await c.close()
        if resume, let o = studyService.current, let host = studyService.audioService?.controller() {
            host.bind(player: o.controller.player, study: o.session)
            o.controller.audio.restoreOwnOutput()
        }
    }

    private func cameraSource() -> RecordCameraSource? {
        if let cameras { return cameras }
        return RecordCameraSource.resolve(options)
    }

    /// Gancho de la captura hacia el relevo: en el hilo de la captura, sin convertir ni copiar; `push` no bloquea (si el
    /// codificador va ocupado, descarta). PTS = marca de host de la cámara en ms.
    nonisolated static func previewHook(_ relay: FrameRelay) -> @Sendable (CameraFrame) -> Void {
        { f in
            guard let pb = f.pixelBuffer else { return }
            relay.push(pb, ptsMs: f.hostSeconds * 1000)
        }
    }

    private func with(_ change: @MainActor (RecordController) throws -> Void) async throws -> RecordSnapshot {
        guard let c = controller else { throw Self.notOpen }
        if c.session !== studyService.current?.session {
            await close(resume: false)
            throw Self.notOpen
        }
        defer { stateChanged() }
        try change(c)
        return snapshot(c)
    }

    // MARK: Eventos

    /// Emite `record.state` (agrupado en un solo mensaje por turno) si cambió algo distinto de la posición.
    func stateChanged() {
        guard !statePending else { return }
        statePending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            statePending = false
            guard let c = controller else { return }
            var s = snapshot(c)
            let key = Self.key(s)
            guard key != lastKey else { return }
            lastKey = key
            s.position = c.player.currentTime
            emit("record.state", s)
        }
    }

    private static func key(_ s: RecordSnapshot) -> Data? {
        var k = s
        k.position = 0
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]   // el orden de claves del codificador no es estable entre llamadas
        e.dateEncodingStrategy = .iso8601
        return try? e.encode(k)
    }

    private func startTicker() {
        ticker?.cancel()
        lastPosition = -1
        lastPlaying = false
        lastPhase = "idle"
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: UInt64(1e9 / StudyConstants.eventHz))
            }
        }
    }

    /// Una vuelta del reloj de eventos: `record.position` y `record.levels` a 30 Hz como máximo.
    func tick() {
        guard let c = controller else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let playing = c.player.isPlaying
        let phase = c.phase.name
        if playing != lastPlaying || phase != lastPhase {
            lastPlaying = playing
            lastPhase = phase
            stateChanged()
        }
        if now - lastPositionAt >= StudyConstants.minEventSpacing {
            let t = c.player.currentTime
            if playing || t != lastPosition {
                lastPositionAt = now
                lastPosition = t
                emit("record.position", RecordPositionEvent(seconds: t, playing: playing, phase: phase))
            }
        }
        if now - lastLevelsAt >= StudyConstants.minEventSpacing, playing || lastLevelsLoud {
            let ids = Set(Self.mixChannels(c).map(\.id) + Self.takeChannels(c).map(\.id))
            let meters = c.player.meters.filter { ids.contains($0.key) }
            lastLevelsAt = now
            lastLevelsLoud = meters.values.contains { $0.rmsDB > StudyConstants.silentDB }
            emit("record.levels", RecordLevelsEvent(channels: meters.mapValues {
                StudyMeter(rmsDB: Double($0.rmsDB.isFinite ? $0.rmsDB : -120), peakDB: Double($0.peakDB.isFinite ? $0.peakDB : -120))
            }))
        }
    }

    // MARK: Instantánea

    /// Ruta relativa a la carpeta de proyectos de un fichero relativo al tema.
    private func mediaPath(_ c: RecordController, _ relative: String?) -> String? {
        guard let relative, !relative.isEmpty else { return nil }
        return c.session.folder.lastPathComponent + "/" + relative
    }

    func snapshot(_ c: RecordController) -> RecordSnapshot {
        let s = c.session
        let t = c.timing
        var countBeat: Int?
        if case .counting(let n) = c.phase { countBeat = n }
        let palette = SectionEditor.paletteIndices(c.sections)
        let sections = c.sections.map {
            StudySectionInfo(id: $0.id.uuidString, name: $0.name, start: $0.start, end: $0.end, solo: $0.isSolo,
                             color: $0.color, paletteIndex: palette[$0.id])
        }
        let parts = c.state.parts.map { part -> RecordPartInfo in
            let takes = part.takeIDs.enumerated().compactMap { i, id -> RecordTakeInfo? in
                guard let tk = c.take(id) else { return nil }
                return takeInfo(c, tk, number: i + 1, best: part.bestTakeID == id)
            }
            return RecordPartInfo(id: part.id.uuidString, name: part.name, replaces: part.replaces?.rawValue, isLead: part.isLead,
                                  status: c.status(of: part).rawValue, bestTakeId: part.bestTakeID?.uuidString, takes: takes)
        }
        let punchReady = c.punchPlan() != nil
        let offset = c.offsetRequest.map { r in
            RecordOffsetInfo(takeId: r.takeID.uuidString, isNew: r.isNew, videoPath: mediaPath(c, r.videoRelative) ?? "",
                             audioPath: mediaPath(c, r.audioRelative) ?? "", songStart: r.songStart, fps: r.fps,
                             frameMs: 1000 / max(r.fps, 1), cameraId: r.cameraID, cameraName: r.cameraName,
                             initialMs: (r.initialOffset * 1000).rounded(), valueMs: r.offsetMs,
                             minMs: RecordController.offsetRangeMs.lowerBound, maxMs: RecordController.offsetRangeMs.upperBound,
                             rotation: r.rotation, punches: punchInfos(c, r.punches))
        }
        let f = c.videoFormat
        let camera = RecordCameraInfo(
            state: c.cameraState.name, message: c.cameraMessage, name: c.cameraName, label: c.cameraLabel,
            width: f?.width, height: f?.height, fps: f?.fps, rotation: c.cameraRotation,
            defaultOffsetMs: c.defaultOffset.map { ($0 * 1000).rounded() },
            cameras: c.availableCameras.map { RecordCameraEntry(id: $0.id, name: $0.name) }, chosenId: c.chosenCameraID)
        let host = c.audio
        return RecordSnapshot(
            projectId: s.projectID.uuidString, title: s.project.song.title, phase: c.phase.name, countBeat: countBeat,
            beatsPerBar: t.beatsPerBar, barSeconds: t.barSeconds, bpm: 60 / t.beatSeconds, downbeats: t.downbeats,
            duration: c.duration, position: c.player.currentTime, busy: c.isBusy, blockReason: c.blockReason,
            block: c.blockMessage, loadError: c.loadError, messages: c.messages, notices: host.takeNotices, takeSaveError: s.takeSaveError,
            countIn: c.state.countIn, preRollBars: c.state.preRollBars, startSectionId: c.startSectionID?.uuidString,
            startTime: c.startTime, plannedStop: c.plannedStop, sections: sections,
            guitarRoles: c.guitarRoles.map { RecordGuitarRole(role: $0.rawValue, name: c.guitarName($0)) },
            parts: parts, activePartId: c.activePartID?.uuidString, nextTakeNumber: c.nextTakeNumber,
            selectedTakeId: c.selectedTakeID?.uuidString,
            punch: RecordPunchInfo(enabled: c.punchEnabled, in: c.punchIn, out: c.punchOut, ready: punchReady),
            mix: RecordMixInfo(masterGainDB: c.masterGainDB, channels: Self.mixChannels(c), takeChannels: Self.takeChannels(c),
                               anySolo: c.anySolo, outputName: c.studyAudio.outputName),
            camera: camera, offset: offset,
            audio: RecordAudioInfo(sessionOpen: host.session?.isOpen ?? false, hosting: host.isHostingPlayer,
                                   recording: host.isRecording, outputName: c.studyAudio.outputName))
    }

    private func punchInfos(_ c: RecordController, _ punches: [PreviewPunch]) -> [RecordPunchTake] {
        let folder = c.session.folder.path
        return punches.map { p in
            var rel: String?
            if let u = p.videoURL, u.path.hasPrefix(folder) { rel = String(u.path.dropFirst(folder.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/\\")) }
            return RecordPunchTake(start: p.start, end: p.end, hasVideo: p.videoURL != nil, videoPath: mediaPath(c, rel),
                                   videoOffsetMs: p.videoOffset * 1000)
        }
    }

    private func takeInfo(_ c: RecordController, _ t: Take, number: Int, best: Bool) -> RecordTakeInfo {
        let punches = (t.punches ?? []).map {
            RecordPunchTake(start: $0.start, end: $0.end, hasVideo: $0.videoFile != nil, videoPath: mediaPath(c, $0.videoFile),
                            videoOffsetMs: ($0.videoOffset ?? t.videoOffset).map { $0 * 1000 })
        }
        let fmt = t.videoFormat.map {
            RecordTakeFormat(cameraId: $0.cameraUID, cameraName: $0.cameraName, width: $0.width, height: $0.height, fps: $0.fps)
        }
        return RecordTakeInfo(id: t.id.uuidString, number: number, createdAt: t.createdAt, best: best,
                              selected: c.selectedTakeID == t.id, discarded: t.discarded, durationSeconds: c.duration(of: t),
                              songStart: t.songStart, hasVideo: t.videoFile != nil, videoPath: mediaPath(c, t.videoFile),
                              videoOffsetMs: t.videoOffset.map { $0 * 1000 }, videoRotation: t.rotationDegrees, videoFormat: fmt,
                              audioPath: mediaPath(c, t.processedFile), punches: punches)
    }

    static func mixChannels(_ c: RecordController) -> [RecordMixChannel] {
        var out: [RecordMixChannel] = []
        let s = c.session
        func channel(_ id: String, _ kind: String, _ role: String?, _ name: String, _ m: StemMix) -> RecordMixChannel {
            let forced = c.isForcedMuted(id)
            return RecordMixChannel(id: id, kind: kind, guitarRole: role, name: name, gainDB: m.gainDB,
                                    muted: forced || m.muted, solo: forced ? false : m.solo, forcedMuted: forced)
        }
        for (kind, name) in StudyConstants.channelOrder {
            if kind == .guitar, s.usesSeparatedGuitars {
                for g in s.guitarTracks {
                    out.append(channel(g.role.trackID, "guitar", g.role.rawValue, s.guitarName(g.role), c.mix(forGuitar: g.role)))
                }
            } else if s.mixerStems.contains(kind), !s.emptyStems.contains(kind) {
                out.append(channel(kind.rawValue, kind.rawValue, nil, name, c.mix(for: kind)))
            }
        }
        return out
    }

    static func takeChannels(_ c: RecordController) -> [RecordTakeChannel] {
        c.backingTakeChannels.map { bt in
            let m = c.takeMix(bt.partID)
            return RecordTakeChannel(id: RecordController.takeTrackID(bt.partID), partId: bt.partID.uuidString, name: bt.channelName,
                                     gainDB: m.gainDB, muted: m.muted, solo: m.solo)
        }
    }
}

extension Bridge {
    /// Sustituye el receptor de los fotogramas de la cámara (Grabar y vista previa de Ajustes): píxeles tal cual, sin JPEG.
    /// Sin llamarlo, el núcleo los manda por `frames.camera`; nil vuelve a eso. Vale para las aperturas siguientes. Cualquier hilo.
    public func setCameraFrameSink(_ sink: (@Sendable (FramePixelBuffer, Double) -> Void)?) {
        recordService?.cameraPixelSink = sink
    }

    /// Registra `record.*` y cierra Grabar cuando se cierra el tema de Backing.
    func registerRecordMethods(options: LaunchOptions) {
        let service = RecordService(options: options, studyService: studyService, emit: { [weak self] in self?.send($0) })
        // W2-E2: cámara en vivo hacia la página (15 fps, 640 px), igual en ToneForge.exe y en tf-webdev.
        service.makeCameraRelay = { [weak self, weak service] in service?.cameraRelayFactory(self) }
        service.register(on: router)
        recordService = service
        Self.wireOffsetSheet(record: service, takeView: takeViewService)
        // W2-E2: vista previa de Ajustes por el mismo canal; Grabar le quita la cámara al abrir y la comparte mientras está abierta.
        let preview = CameraPreviewService(options: options)
        preview.makeRelay = { [weak self, weak service] in service?.cameraRelayFactory(self) }
        preview.recordController = { [weak service] in service?.controller }
        service.willOpenCamera = { [weak preview] in preview?.stop() }
        preview.register(on: router)   // el router lo retiene
        studyService.onClosing = { [weak service] in await service?.close(resume: false) }
    }

    /// W2-O: la hoja «Ajustar desfase» suena por el visor del núcleo (`takeview.openOffset`) con la toma que pide Grabar
    /// (pausa antes el reproductor de Grabar), y Grabar suelta ese reproductor antes de guardar o descartar la toma.
    static func wireOffsetSheet(record service: RecordService, takeView: TakeViewService) {
        takeView.offsetSource = { [weak service] in
            guard let c = service?.controller, let r = c.offsetRequest else { return nil }
            c.player.pause()
            return TakeViewOffsetSource(projectId: c.session.projectID, takeId: r.takeID, audioURL: r.audioURL, songStart: r.songStart,
                                        videoURLs: [r.videoURL] + r.punches.map(\.videoURL),
                                        videoWidth: r.videoWidth, videoHeight: r.videoHeight, videoRotation: r.rotation)
        }
        service.willFinishOffset = { [weak takeView] in await takeView?.closeOffset() }
        service.willDeleteTake = { [weak takeView] takeID in await takeView?.release(takeId: takeID) }
    }
}
