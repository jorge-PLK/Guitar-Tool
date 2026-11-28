import AudioKit
import Foundation
import Store
import VideoKit

// Métodos `montage.*` y eventos de Montaje (W2-M1, paso 8 ola 2). Contrato: `Temp/win/step8-contract.md`, «W2-M1 montage.*».

// MARK: - Constantes

enum MontageConstants {
    /// Máximo de eventos `montage.position` por segundo (encargo W2-M1, como `study.position`).
    static let positionHz = 30.0
    static let minPositionSpacing = 0.9 / positionHz
    /// Como mucho 4 eventos de progreso por segundo (exportación y análisis), como `JobEngine.progressInterval`.
    static let progressInterval = 0.25
}

// MARK: - Tipos JSON

struct MontageRangeInfo: Codable, Sendable, Equatable {
    var start: Double
    var end: Double
}

struct MontageLaneInfo: Codable, Sendable, Equatable {
    var id: String
    var takeId: String
    var partName: String
    var isSolo: Bool
    /// Rol de la guitarra que sustituye (`rhythm`, `left`…), si sustituye alguna.
    var replaces: String?
    var presence: [MontageRangeInfo]
    var take: MontageRangeInfo
    var hasVideo: Bool
    /// Giro de la toma en grados (0, 90, 180, 270).
    var rotation: Int
}

struct MontageSegmentInfo: Codable, Sendable, Equatable {
    var start: Double
    var end: Double
    var fadeIn: Bool
    var fadeOut: Bool
}

struct MontageSectionInfo: Codable, Sendable, Equatable {
    var id: String
    var name: String
    var start: Double
    var end: Double
    var solo: Bool
}

struct MontageCutInfo: Codable, Sendable, Equatable {
    var id: String
    var time: Double
    /// nil = automático.
    var partId: String?
    /// La parte elegida tiene toma con imagen en ese instante (nil o automático: true).
    var covered: Bool
    /// Partes con toma con imagen en `time` (menú del corte; `MontagePlanning.cutEligibleParts`).
    var eligible: [String]
}

struct MontagePlaneShotInfo: Codable, Sendable, Equatable {
    var start: Double
    var end: Double
    var partId: String?
    var black: Bool
}

struct MontageBoxInfo: Codable, Sendable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct MontageOffsetInfo: Codable, Sendable, Equatable {
    var x: Double
    var y: Double
}

struct MontageFramingInfo: Codable, Sendable, Equatable {
    var takeId: String
    /// `pending`, `analyzing`, `ready`, `failed`.
    var status: String
    var progress: Double
    var samples: Int?
    var detected: Int?
    var error: String?
    /// `fixed` o `follow`.
    var mode: String
    var manualBox: MontageBoxInfo?
    var followZoom: Double
    var followOffset: MontageOffsetInfo
}

struct MontageResolutionInfo: Codable, Sendable, Equatable {
    var width: Int
    var height: Int
}

struct MontageExportOptions: Codable, Sendable, Equatable {
    /// Los que admite este sistema (VideoKit): en Windows solo `h264`; si hay uno, la página no enseña selector.
    var codecs: [String]
    var containers: [String]
    var resolutions: [MontageResolutionInfo]
    var fps: [Double]
}

struct MontageExportResultInfo: Codable, Sendable, Equatable {
    var path: String
    var tracksDirectory: String?
    var finalLUFS: Double?
    var finalTruePeakDB: Double
    var normalized: Bool
    var limitedByPeak: Bool
    var limiterEnabled: Bool
    var limiterApplied: Bool
    var limiterMaxReductionDB: Double
    var limiterOutOfTolerance: Bool
    var clippedFiles: [String]
    var codec: String
}

struct MontageExportInfo: Codable, Sendable, Equatable {
    /// Lo guardado en el montaje (puede ser HEVC venido del Mac).
    var codec: String
    /// Lo que se usará de verdad en este sistema.
    var effectiveCodec: String
    var container: String
    var resolution: MontageResolutionInfo
    /// Tamaño final del vídeo según el layout (el portrait gira la resolución).
    var size: MontageResolutionInfo
    var fps: Double
    var normalize: Bool
    var limiter: Bool
    var trackWAVs: Bool
    var options: MontageExportOptions
    var canExport: Bool
}

struct MontageExportEvent: Codable, Sendable, Equatable {
    /// `idle`, `running`, `done`, `failed`, `cancelled`.
    var phase: String
    var stage: String?
    var progress: Double
    var message: String?
    var result: MontageExportResultInfo?
}

struct MontageFramingEvent: Codable, Sendable, Equatable {
    var takeId: String
    var status: String
    var progress: Double
    var samples: Int?
    var detected: Int?
    var error: String?
}

struct MontageAudioInfo: Codable, Sendable, Equatable {
    /// `none`, `preparing`, `ready`, `silent`, `error`.
    var phase: String
    var error: String?
    var progress: Double
    /// Nombre del WAV de la vista previa en `cache/montage/` (nil: sin WAV).
    var file: String?
}

struct MontagePreviewInfo: Codable, Sendable, Equatable {
    /// `none` (sin plan), `preparing`, `ready`, `error`.
    var phase: String
    var error: String?
    var audio: MontageAudioInfo
    var fps: Double
    var maxDimension: Int
    /// Tamaño de los fotogramas (el lienzo reducido).
    var width: Int
    var height: Int
    /// Duración del vídeo (s), con la vista previa lista.
    var duration: Double?
    var delivered: Int
    var skipped: Int
    var lastFrameMillis: Double
    /// W2-E2: composición p50/p95 de los últimos 512 fotogramas (ms).
    var frameP50Ms: Double = 0
    var frameP95Ms: Double = 0
    /// Fase 7c: tomas cuyo vídeo aún no se puede leer (fase `converting` o `error`). El progreso vivo va por
    /// `jobs.progress` (clave `jobId`); aquí es el del momento de la instantánea.
    var videos: [TakeVideoStatusInfo] = []
}

struct MontageTransportInfo: Codable, Sendable, Equatable {
    var playing: Bool
    /// Posición en tiempo del tema.
    var position: Double
    /// Posición en tiempo del vídeo (el reloj del audio).
    var videoPosition: Double
    var span: MontageRangeInfo
    var audioError: String?
    /// `not-connected` | `sample-rate-mismatch` | `busy` | `unavailable`; nil si `audioError` es nil.
    var audioErrorCode: String?
}

struct MontageSnapshot: Codable, Sendable, Equatable {
    var projectId: String
    var title: String
    var artist: String?
    /// `side`, `grid`, `stack`, `single`, `single-landscape`.
    var layout: String
    var isPortrait: Bool
    var isSingleShot: Bool
    var canvasLabel: String
    var keepAspectApplies: Bool
    var caption: Bool
    var showPartLabels: Bool
    var keepVideoAspect: Bool
    var cutGaps: Bool
    var singleRhythmPartId: String?
    /// Partes que pueden ocupar el plano único (rítmicas con vídeo y presencia).
    var singleRhythmCandidates: [String]
    /// MO7: parte que el núcleo pone en el plano único cuando no hay elección manual válida (la primera no solista del plan;
    /// como `MontageTimeline.singleAppearances`). Solo con layout de plano único y plan; nil (clave omitida) en el resto.
    var autoPartId: String?
    /// Hay un plan de montaje (al menos una parte con toma y vídeo).
    var hasPlan: Bool
    var hasVideo: Bool
    var span: MontageRangeInfo
    var barDuration: Double
    /// Duración del tema en segundos (eje de la línea de tiempo; 0 si se desconoce).
    var songDuration: Double
    var anticipationLabel: String
    var lanes: [MontageLaneInfo]
    var audioOnlyParts: [String]
    var missingParts: [String]
    var segments: [MontageSegmentInfo]
    var sections: [MontageSectionInfo]
    var cuts: [MontageCutInfo]
    var cutCandidates: [String]
    var planeShots: [MontagePlaneShotInfo]
    var framing: [MontageFramingInfo]
    var isAnalyzing: Bool
    var export: MontageExportInfo
    var exportStatus: MontageExportEvent
    var preview: MontagePreviewInfo
    var transport: MontageTransportInfo
}

struct MontagePositionEvent: Codable, Sendable, Equatable {
    var seconds: Double
    var videoSeconds: Double
    var playing: Bool
}

struct MontageAddCutResult: Codable, Sendable {
    var cutId: String
    var snapshot: MontageSnapshot
}

struct MontageFramingFrameResult: Codable, Sendable {
    /// Ruta relativa a la carpeta del tema (con `/`); la página la sirve con `mediaBase`.
    var path: String
    var width: Int
    var height: Int
    var time: Double
    /// Cambia en cada fotograma nuevo (anti-caché de la imagen).
    var version: Int
    /// Caja de la guitarra (con el ajuste manual) en ese instante, normalizada sobre la imagen ya girada.
    var box: MontageBoxInfo?
}

struct MontageRevealResult: Codable, Sendable { var revealed: Bool }

struct MontageOpenParams: Decodable, Sendable { var projectId: String }
struct MontageLayoutParams: Decodable, Sendable { var layout: String }
struct MontagePartParams: Decodable, Sendable { var partId: String? }
struct MontageBoolParams: Decodable, Sendable { var on: Bool }
struct MontageMoveLaneParams: Decodable, Sendable { var id: String; var to: String }
struct MontageOrderParams: Decodable, Sendable { var ids: [String] }
struct MontageAddCutParams: Decodable, Sendable { var time: Double; var partId: String?; var exact: Bool? }
struct MontageCutMoveParams: Decodable, Sendable { var id: String; var time: Double }
struct MontageCutPartParams: Decodable, Sendable { var id: String; var partId: String? }
struct MontageIDParams: Decodable, Sendable { var id: String }
struct MontageSetExportParams: Decodable, Sendable {
    var codec: String?
    var container: String?
    var resolution: MontageResolutionInfo?
    var fps: Double?
    var normalize: Bool?
    var limiter: Bool?
    var trackWAVs: Bool?
}
struct MontageTakeParams: Decodable, Sendable { var takeId: String }
struct MontageSetFramingParams: Decodable, Sendable {
    var takeId: String
    var mode: String?
    var manualBox: MontageBoxInfo?
    /// true = vuelve a la caja automática (borra `manualBox`).
    var clearManualBox: Bool?
    var followZoom: Double?
    var followOffset: MontageOffsetInfo?
}
struct MontageFramingFrameParams: Decodable, Sendable { var takeId: String; var time: Double }
/// Consulta en vivo (solo lectura): caja efectiva en `time` con overrides sin guardar; mismos campos que `MontageSetFramingParams`.
struct MontageFramingBoxParams: Decodable, Sendable {
    var takeId: String
    var time: Double
    var mode: String?
    var manualBox: MontageBoxInfo?
    var clearManualBox: Bool?
    var followZoom: Double?
    var followOffset: MontageOffsetInfo?
}
struct MontageFramingBoxResult: Codable, Sendable, Equatable { var box: MontageBoxInfo? }
struct MontageCutTimeResult: Codable, Sendable, Equatable { var time: Double }
struct MontageSeekParams: Decodable, Sendable { var seconds: Double }
struct MontageFPSParams: Decodable, Sendable { var fps: Double }

// MARK: - Servicio

/// Tema abierto en Montaje: controlador, sesión de estudio de solo lectura y reproductor de la vista previa. Vive en el hilo
/// principal.
@MainActor
final class MontageService {
    private let options: LaunchOptions
    private let root: ProjectsRoot
    private let profileStore: ProfileStore?
    private let storeFactory: @Sendable (URL) -> any MontageStoring
    private let reveal: @Sendable (URL) throws -> Void
    private let outbox = MontageOutbox()
    /// Antes de abrir y de dar a play: para lo que suene en Backing.
    private let pauseOthers: @MainActor @Sendable () -> Void
    /// Solo tests: sustituyen al compositor, la mezcla, el audio y la exportación reales.
    var services: MontageServices = .production
    var audioFactory: (@MainActor (LaunchOptions, OutputSelection) -> any MontageAudioPlaying)?
    var timing = MontageController.Timing()
    /// Fase 7c: conversión HEVC → H.264 de las tomas (la pone el `Bridge`; nil = sin conversión).
    nonisolated(unsafe) var videoConversion: VideoConversionEngine?

    private(set) var current: MontageController?
    private var ticker: Task<Void, Never>?
    private var statePending = false
    private var lastState: MontageSnapshot?
    private var lastPosition = MontagePositionEvent(seconds: -1, videoSeconds: -1, playing: false)
    private var lastPositionAt = 0.0
    private var lastExportAt = 0.0
    private var lastFramingAt: [UUID: Double] = [:]
    /// Los fotogramas de la vista previa van a este receptor (`FrameRelay`, canal `frames.montage`).
    private var frameSink: (@Sendable (MontageFramePixels, Double) -> Void)?

    nonisolated init(options: LaunchOptions, root: ProjectsRoot, storeFactory: @escaping @Sendable (URL) -> any MontageStoring,
                     reveal: @escaping @Sendable (URL) throws -> Void, pauseOthers: @escaping @MainActor @Sendable () -> Void = {}) {
        self.pauseOthers = pauseOthers
        self.options = options
        self.root = root
        self.storeFactory = storeFactory
        self.reveal = reveal
        if let dir = options.supportDir {
            profileStore = ProfileStore(url: dir.appendingPathComponent("profile.json"))
        } else {
            profileStore = options.audio == .simulated ? nil : ProfileStore()
        }
    }

    nonisolated func setSink(_ sink: @escaping @Sendable (String) -> Void) { outbox.set(sink) }

    /// Relevo propio `frames.montage` por tema abierto (W2-E2); lo da el `Bridge`. Un `setFrameSink` externo manda sobre él.
    /// Se pone una vez al crear el `Bridge`, antes de cualquier método.
    nonisolated(unsafe) var makeFrameRelay: (@Sendable () -> FrameRelay?)?
    private(set) var frameRelay: FrameRelay?

    /// El anfitrión recibe aquí los fotogramas (BGRA, tamaño reducido) y su PTS en ms de vídeo. nil = el relevo propio.
    func setFrameSink(_ sink: (@Sendable (MontageFramePixels, Double) -> Void)?) {
        frameSink = sink
        current?.onPreviewFrame = sink ?? frameRelay.map(Self.relaySink)
    }

    nonisolated static func relaySink(_ relay: FrameRelay) -> @Sendable (MontageFramePixels, Double) -> Void {
        { pixels, pts in relay.push(pixels, ptsMs: pts) }
    }

    func emit<T: Encodable>(_ event: String, _ payload: T) {
        if let m = Router.eventMessage(event, payload) { outbox.send(m) }
    }

    nonisolated func register(on router: Router) {
        router.register("montage.open") { [self] (p: MontageOpenParams) -> MontageSnapshot in try await open(p) }
        router.register("montage.close") { [self] (_: Empty) -> Empty in await close(); return Empty() }
        router.register("montage.snapshot") { [self] (_: Empty) -> MontageSnapshot in try await with { _ in } }
        router.register("montage.setLayout") { [self] (p: MontageLayoutParams) -> MontageSnapshot in
            guard let kind = Store.MontageLayoutKind(rawValue: p.layout) else {
                throw RPCError(code: "bad-params", message: "«layout» no es un layout de montaje: \(p.layout)")
            }
            return try await with { $0.setLayout(kind) }
        }
        router.register("montage.setSingleRhythm") { [self] (p: MontagePartParams) -> MontageSnapshot in
            let id = try Self.optionalID(p.partId, "partId")
            return try await with { $0.setSingleRhythm(id) }
        }
        router.register("montage.setCutGaps") { [self] (p: MontageBoolParams) -> MontageSnapshot in try await with { $0.setCutGaps(p.on) } }
        router.register("montage.moveLane") { [self] (p: MontageMoveLaneParams) -> MontageSnapshot in
            let id = try Self.id(p.id, "id"), to = try Self.id(p.to, "to")
            return try await with { $0.moveLane(id, to: to) }
        }
        router.register("montage.setPartOrder") { [self] (p: MontageOrderParams) -> MontageSnapshot in
            let ids = try p.ids.map { try Self.id($0, "ids") }
            return try await with { $0.setPartOrder(ids) }
        }
        router.register("montage.setCaption") { [self] (p: MontageBoolParams) -> MontageSnapshot in try await with { $0.setCaption(p.on) } }
        router.register("montage.setShowPartLabels") { [self] (p: MontageBoolParams) -> MontageSnapshot in
            try await with { $0.setShowPartLabels(p.on) }
        }
        router.register("montage.setKeepVideoAspect") { [self] (p: MontageBoolParams) -> MontageSnapshot in
            try await with { $0.setKeepVideoAspect(p.on) }
        }
        router.register("montage.addCut") { [self] (p: MontageAddCutParams) -> MontageAddCutResult in try await addCut(p) }
        router.register("montage.moveCut") { [self] (p: MontageCutMoveParams) -> MontageSnapshot in
            let id = try Self.id(p.id, "id")
            return try await with { $0.moveCut(id, to: p.time) }
        }
        router.register("montage.setCutPart") { [self] (p: MontageCutPartParams) -> MontageSnapshot in
            let id = try Self.id(p.id, "id"), part = try Self.optionalID(p.partId, "partId")
            return try await with { $0.setCutPart(id, part) }
        }
        router.register("montage.removeCut") { [self] (p: MontageIDParams) -> MontageSnapshot in
            let id = try Self.id(p.id, "id")
            return try await with { $0.removeCut(id) }
        }
        router.register("montage.clearCuts") { [self] (_: Empty) -> MontageSnapshot in try await with { $0.clearCuts() } }
        router.register("montage.setExport") { [self] (p: MontageSetExportParams) -> MontageSnapshot in
            var codec: VideoCodec?, container: MontageContainer?
            if let c = p.codec {
                guard let v = VideoCodec(rawValue: c) else { throw RPCError(code: "bad-params", message: "«codec» no es hevc ni h264: \(c)") }
                codec = v
            }
            if let c = p.container {
                guard let v = MontageContainer(rawValue: c) else { throw RPCError(code: "bad-params", message: "«container» no es mov ni mp4: \(c)") }
                container = v
            }
            if let r = p.resolution, r.width <= 0 || r.height <= 0 { throw RPCError(code: "bad-params", message: "«resolution» no es válida.") }
            if let f = p.fps, !(f > 0 && f.isFinite) { throw RPCError(code: "bad-params", message: "«fps» no es válido.") }
            return try await with { c in
                c.updateExport { e in
                    if let codec { e.codec = codec }
                    if let container { e.container = container }
                    if let r = p.resolution { e.resolution = VideoResolution(width: r.width, height: r.height) }
                    if let f = p.fps { e.fps = f }
                    if let v = p.normalize { e.normalize = v }
                    if let v = p.limiter { e.limiter = v }
                    if let v = p.trackWAVs { e.trackWAVs = v }
                }
            }
        }
        router.register("montage.setFraming") { [self] (p: MontageSetFramingParams) -> MontageSnapshot in
            let take = try Self.id(p.takeId, "takeId")
            try Self.validateFramingMode(p.mode)
            return try await with { c in
                c.updateFraming(take) { f in
                    Self.applyFraming(&f, mode: p.mode, clearManualBox: p.clearManualBox, manualBox: p.manualBox,
                                      followZoom: p.followZoom, followOffset: p.followOffset)
                }
            }
        }
        router.register("montage.snapCut") { [self] (p: MontageCutMoveParams) -> MontageCutTimeResult in
            let id = try Self.id(p.id, "id")
            return try await snapCut(id, p.time)
        }
        router.register("montage.framingBox") { [self] (p: MontageFramingBoxParams) -> MontageFramingBoxResult in try await framingBox(p) }
        router.register("montage.resetFraming") { [self] (p: MontageTakeParams) -> MontageSnapshot in
            let take = try Self.id(p.takeId, "takeId")
            return try await with { $0.resetFraming(take) }
        }
        router.register("montage.reanalyze") { [self] (p: MontageTakeParams) -> MontageSnapshot in
            let take = try Self.id(p.takeId, "takeId")
            return try await with { $0.reanalyze(take) }
        }
        router.register("montage.rotateTake") { [self] (p: MontageTakeParams) -> MontageSnapshot in
            let take = try Self.id(p.takeId, "takeId")
            return try await with { $0.rotateTake(take) }
        }
        router.register("montage.framingFrame") { [self] (p: MontageFramingFrameParams) -> MontageFramingFrameResult in
            try await framingFrame(p)
        }
        router.register("montage.play") { [self] (_: Empty) -> MontageSnapshot in
            try await with { c in pauseOthers(); try c.play() }
        }
        router.register("montage.pause") { [self] (_: Empty) -> MontageSnapshot in try await with { $0.pause() } }
        router.register("montage.seek") { [self] (p: MontageSeekParams) -> MontageSnapshot in
            guard p.seconds.isFinite else { throw RPCError(code: "bad-params", message: "«seconds» no es válido.") }
            return try await with { $0.seek(to: p.seconds) }
        }
        router.register("montage.setPreviewFps") { [self] (p: MontageFPSParams) -> MontageSnapshot in
            guard p.fps.isFinite else { throw RPCError(code: "bad-params", message: "«fps» no es válido.") }
            return try await with { $0.previewFPS = p.fps }
        }
        router.register("montage.startExport") { [self] (_: Empty) -> MontageSnapshot in
            try await with { c in
                c.refreshVideoStates()
                guard c.canExport else {
                    throw RPCError(code: "not-ready", message: c.draft == nil ? "No hay tomas con vídeo que montar."
                                   : c.isExporting ? "Ya hay una exportación en curso."
                                   : !c.videoStates.isEmpty ? MontageController.videoWaitMessage
                                   : "El análisis de encuadre aún no ha terminado.")
                }
                c.startExport()
            }
        }
        router.register("montage.cancelExport") { [self] (_: Empty) -> MontageSnapshot in try await with { $0.cancelExport() } }
        router.register("montage.dismissExport") { [self] (_: Empty) -> MontageSnapshot in try await with { $0.dismissExportResult() } }
        router.register("montage.reveal") { [self] (_: Empty) -> MontageRevealResult in try await revealVideoFolder() }
    }

    // MARK: Ayudas

    nonisolated private static var notOpen: RPCError { RPCError(code: "not-open", message: "No hay ningún tema abierto en Montaje.") }

    nonisolated private static func id(_ s: String, _ name: String) throws -> UUID {
        guard let u = UUID(uuidString: s) else { throw RPCError(code: "bad-params", message: "«\(name)» no es un UUID.") }
        return u
    }

    nonisolated private static func optionalID(_ s: String?, _ name: String) throws -> UUID? { try s.map { try id($0, name) } }

    nonisolated private static func box(_ r: NormalizedRect) -> MontageBoxInfo { MontageBoxInfo(x: r.x, y: r.y, width: r.width, height: r.height) }

    private func addCut(_ p: MontageAddCutParams) throws -> MontageAddCutResult {
        let part = try Self.optionalID(p.partId, "partId")
        guard let c = current else { throw Self.notOpen }
        let id: UUID
        if p.partId != nil || p.exact == true { id = c.addCut(at: p.time, partID: part, exact: p.exact ?? false) } else { id = c.addCut(at: p.time) }
        stateChanged()
        return MontageAddCutResult(cutId: id.uuidString, snapshot: snapshot(c))
    }

    nonisolated private static func validateFramingMode(_ m: String?) throws {
        if let m, FramingMode(rawValue: m) == nil { throw RPCError(code: "bad-params", message: "«mode» no es fixed ni follow: \(m)") }
    }

    /// Aplicación de los overrides de encuadre, compartida por `setFraming` (guarda) y `framingBox` (solo lectura).
    nonisolated private static func applyFraming(_ f: inout TakeFraming, mode: String?, clearManualBox: Bool?, manualBox: MontageBoxInfo?,
                                                 followZoom: Double?, followOffset: MontageOffsetInfo?) {
        if let m = mode, let mode = FramingMode(rawValue: m) { f.mode = mode }
        if clearManualBox == true { f.manualBox = nil }
        if let b = manualBox { f.manualBox = NormalizedRect(x: b.x, y: b.y, width: b.width, height: b.height) }
        if let z = followZoom, z.isFinite, z > 0 { f.followZoom = z }
        if let o = followOffset { f.followOffset = FramingOffset(x: o.x, y: o.y) }
    }

    /// Solo lectura: no toca el estado ni emite `montage.state`. Un corte desconocido devuelve `time` tal cual (como `draggedCutTime`).
    private func snapCut(_ id: UUID, _ time: Double) throws -> MontageCutTimeResult {
        guard let c = current else { throw Self.notOpen }
        return MontageCutTimeResult(time: c.draggedCutTime(id, to: time))
    }

    private func framingBox(_ p: MontageFramingBoxParams) throws -> MontageFramingBoxResult {
        let take = try Self.id(p.takeId, "takeId")
        try Self.validateFramingMode(p.mode)
        guard let c = current else { throw Self.notOpen }
        var f = c.framing(for: take)
        Self.applyFraming(&f, mode: p.mode, clearManualBox: p.clearManualBox, manualBox: p.manualBox, followZoom: p.followZoom, followOffset: p.followOffset)
        return MontageFramingBoxResult(box: c.effectiveBox(takeID: take, at: p.time, framing: f).map(Self.box))
    }

    private func framingFrame(_ p: MontageFramingFrameParams) async throws -> MontageFramingFrameResult {
        let take = try Self.id(p.takeId, "takeId")
        guard let c = current else { throw Self.notOpen }
        let f = try await c.framingFrame(takeID: take, at: p.time)
        return MontageFramingFrameResult(path: f.relativePath, width: f.width, height: f.height, time: f.time, version: f.version,
                                         box: c.effectiveBox(takeID: take, at: p.time).map(Self.box))
    }

    /// Con una exportación terminada y el fichero en disco, lo SELECCIONA en el gestor de archivos (MO2); si no, abre la carpeta de vídeo.
    private func revealVideoFolder() throws -> MontageRevealResult {
        guard let c = current else { throw Self.notOpen }
        if case .done(let r) = c.exportPhase, FileManager.default.fileExists(atPath: r.url.path) {
            try reveal(r.url)
            return MontageRevealResult(revealed: true)
        }
        let folder = c.session.layout.videoDir
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try reveal(folder)
        return MontageRevealResult(revealed: true)
    }

    /// Ejecuta un cambio sobre el controlador y devuelve la instantánea ya al día.
    private func with(_ change: @MainActor (MontageController) throws -> Void) async throws -> MontageSnapshot {
        guard let c = current else { throw Self.notOpen }
        defer { stateChanged() }
        try change(c)
        return snapshot(c)
    }

    // MARK: Abrir y cerrar

    func open(_ p: MontageOpenParams) async throws -> MontageSnapshot {
        guard let id = UUID(uuidString: p.projectId) else { throw RPCError(code: "bad-params", message: "«projectId» no es un UUID.") }
        let folder = try Bridge.service(root).folder(id: id)
        let project: Project
        do { project = try ProjectFile.load(folder: folder) } catch {
            throw RPCError(code: "internal", message: "No se pudo leer project.json: \(error)")
        }
        await close()
        pauseOthers()
        let profile = (try? profileStore?.load()) ?? EquipmentProfile()
        let output = OutputSelection(deviceUID: profile.audio?.outputDeviceUID,
                                     left: profile.audio?.backingOut.left ?? 1, right: profile.audio?.backingOut.right ?? 2)
        let session = StudySession(project: project, folder: folder, store: FileStudyStore(folder: folder))
        let player: any MontageAudioPlaying = audioFactory?(options, output) ?? StudyMontageAudio(mode: options.audio, output: output)
        let c = MontageController(session: session, video: profile.video, store: storeFactory(folder), services: services, audio: player,
                                  timing: timing)
        frameRelay = makeFrameRelay?()
        c.onPreviewFrame = frameSink ?? frameRelay.map(Self.relaySink)
        c.onChange = { [weak self] in self?.stateChanged() }
        c.onExport = { [weak self] in self?.exportChanged() }
        c.onFraming = { [weak self] id in self?.framingChanged(id) }
        if let engine = videoConversion {
            // Abrir de nuevo reintenta las conversiones que fallaron.
            engine.forget(takeIds: project.takes.map(\.id))
            let title = "\(project.song.title) · vídeo de la toma"
            c.videoGate = { id, files in engine.state(takeId: id, files: files, title: title) }
        }
        current = c
        lastState = nil
        c.open()
        resetTicker()
        let s = snapshot(c)
        lastState = Self.stable(s)
        return s
    }

    /// Guarda ya el montaje y suelta el audio. También lo llama el cierre del anfitrión.
    func close() async {
        ticker?.cancel()
        ticker = nil
        guard let c = current else { return }
        current = nil
        c.onChange = nil
        c.onExport = nil
        c.onFraming = nil
        c.onPreviewFrame = nil
        frameRelay?.stop()
        frameRelay = nil
        c.close()
        await c.flush()
    }

    // MARK: Instantánea

    func snapshot(_ c: MontageController) -> MontageSnapshot {
        let s = c.session
        let lanes = c.lanes.map {
            MontageLaneInfo(id: $0.id.uuidString, takeId: $0.takeID.uuidString, partName: $0.partName, isSolo: $0.isSolo,
                            replaces: $0.replaces?.rawValue, presence: $0.presence.map { MontageRangeInfo(start: $0.start, end: $0.end) },
                            take: MontageRangeInfo(start: $0.take.start, end: $0.take.end), hasVideo: $0.hasVideo,
                            rotation: c.rotation(takeID: $0.takeID))
        }
        let framing: [MontageFramingInfo] = c.videoLanes.map { l in
            let f = c.framing(for: l.takeID)
            let ev = Self.framingEvent(l.takeID, c.framingStatus[l.takeID])
            return MontageFramingInfo(takeId: l.takeID.uuidString, status: ev.status, progress: ev.progress, samples: ev.samples,
                                      detected: ev.detected, error: ev.error, mode: f.mode.rawValue, manualBox: f.manualBox.map(Self.box),
                                      followZoom: f.followZoom, followOffset: MontageOffsetInfo(x: f.followOffset.x, y: f.followOffset.y))
        }
        let e = c.state.export
        let size = MontagePlanning.exportSize(e.resolution, kind: c.state.layout)
        let canvas = MontagePlanning.canvas(for: c.state.layout)
        let render = MontageBuilder.renderSize(canvas: canvas, maxDimension: MontagePlanning.previewMaxDimension)
        let span = c.span
        return MontageSnapshot(
            projectId: s.projectID.uuidString, title: c.song.title, artist: c.song.artist, layout: c.state.layout.rawValue,
            isPortrait: c.isPortrait, isSingleShot: c.isSingleShot, canvasLabel: c.canvasLabel, keepAspectApplies: c.keepAspectApplies,
            caption: c.state.caption, showPartLabels: c.state.showPartLabels, keepVideoAspect: c.state.keepVideoAspect,
            cutGaps: c.state.cutGaps, singleRhythmPartId: c.state.singleRhythmPartID?.uuidString,
            singleRhythmCandidates: c.singleRhythmCandidates.map { $0.id.uuidString },
            autoPartId: c.isSingleShot ? c.draft.flatMap { d in (d.plan.parts.first { !$0.isSolo } ?? d.plan.parts.first)?.id } : nil,
            hasPlan: c.draft != nil,
            hasVideo: !c.videoLanes.isEmpty, span: MontageRangeInfo(start: span.start, end: span.end), barDuration: c.barDuration,
            songDuration: c.song.duration,
            anticipationLabel: MontageController.anticipationLabel, lanes: lanes, audioOnlyParts: c.draft?.audioOnlyParts ?? [],
            missingParts: c.draft?.missingParts ?? [],
            segments: (c.draft?.segments ?? []).map { MontageSegmentInfo(start: $0.start, end: $0.end, fadeIn: $0.fadeIn, fadeOut: $0.fadeOut) },
            sections: c.sections.map { MontageSectionInfo(id: $0.id.uuidString, name: $0.name, start: $0.start, end: $0.end, solo: $0.isSolo) },
            cuts: c.cuts.map { MontageCutInfo(id: $0.id.uuidString, time: $0.time, partId: $0.partID?.uuidString, covered: c.cutPartCovered($0),
                                      eligible: c.cutEligiblePartIDs(at: $0.time).map { $0.uuidString }.sorted()) },
            cutCandidates: c.cutCandidates.map { $0.id.uuidString },
            planeShots: c.planeShots.map { MontagePlaneShotInfo(start: $0.start, end: $0.end, partId: $0.part?.uuidString, black: $0.black) },
            framing: framing, isAnalyzing: c.isAnalyzing,
            export: MontageExportInfo(
                codec: e.codec.rawValue, effectiveCodec: c.effectiveCodec.rawValue, container: e.container.rawValue,
                resolution: MontageResolutionInfo(width: e.resolution.width, height: e.resolution.height),
                size: MontageResolutionInfo(width: size.width, height: size.height), fps: e.fps, normalize: e.normalize,
                limiter: e.limiter, trackWAVs: e.trackWAVs,
                options: MontageExportOptions(
                    codecs: c.codecOptions.map(\.rawValue), containers: c.containerOptions.map(\.rawValue),
                    resolutions: MontageController.exportResolutions.map { MontageResolutionInfo(width: $0.width, height: $0.height) },
                    fps: Array(Set(MontageController.exportFPSChoices + [e.fps])).sorted()),
                canExport: c.canExport),
            exportStatus: Self.exportEvent(c.exportPhase),
            preview: MontagePreviewInfo(
                phase: c.previewPhase.rawValue, error: c.previewError,
                audio: MontageAudioInfo(phase: c.audioPhase.rawValue, error: c.audioError, progress: c.audioProgress,
                                        file: c.previewAudioURL?.lastPathComponent),
                fps: c.previewFPS, maxDimension: MontagePlanning.previewMaxDimension, width: Int(render.width), height: Int(render.height),
                duration: c.previewDuration, delivered: c.previewStats.delivered, skipped: c.previewStats.skipped,
                lastFrameMillis: c.previewStats.lastFrameMillis, frameP50Ms: c.previewStats.percentile(0.5),
                frameP95Ms: c.previewStats.percentile(0.95), videos: videoStatuses(c)),
            transport: MontageTransportInfo(playing: c.isPlaying, position: c.songTime, videoPosition: c.videoPosition,
                                            span: MontageRangeInfo(start: span.start, end: span.end), audioError: c.audioError,
                                            audioErrorCode: c.audioErrorCode))
    }

    static func exportEvent(_ p: MontageController.ExportPhase) -> MontageExportEvent {
        switch p {
        case .idle: return MontageExportEvent(phase: "idle", stage: nil, progress: 0, message: nil, result: nil)
        case .running(let stage, let progress): return MontageExportEvent(phase: "running", stage: stage, progress: progress, message: nil, result: nil)
        case .failed(let m): return MontageExportEvent(phase: "failed", stage: nil, progress: 0, message: m, result: nil)
        case .cancelled: return MontageExportEvent(phase: "cancelled", stage: nil, progress: 0, message: nil, result: nil)
        case .done(let r):
            return MontageExportEvent(phase: "done", stage: nil, progress: 1, message: nil, result: MontageExportResultInfo(
                path: r.url.path, tracksDirectory: r.tracksDirectory?.path, finalLUFS: r.finalLUFS, finalTruePeakDB: r.finalTruePeakDB,
                normalized: r.normalized, limitedByPeak: r.limitedByPeak, limiterEnabled: r.limiterEnabled, limiterApplied: r.limiterApplied,
                limiterMaxReductionDB: r.limiterMaxReductionDB, limiterOutOfTolerance: r.limiterOutOfTolerance, clippedFiles: r.clippedFiles,
                codec: r.codec))
        }
    }

    static func framingEvent(_ id: UUID, _ s: MontageController.FramingStatus?) -> MontageFramingEvent {
        switch s {
        case nil, .pending?: return MontageFramingEvent(takeId: id.uuidString, status: "pending", progress: 0, samples: nil, detected: nil, error: nil)
        case .analyzing(let p)?: return MontageFramingEvent(takeId: id.uuidString, status: "analyzing", progress: p, samples: nil, detected: nil, error: nil)
        case .ready(let n, let d)?: return MontageFramingEvent(takeId: id.uuidString, status: "ready", progress: 1, samples: n, detected: d, error: nil)
        case .failed(let m)?: return MontageFramingEvent(takeId: id.uuidString, status: "failed", progress: 0, samples: nil, detected: nil, error: m)
        }
    }

    /// La instantánea sin lo que cambia continuamente (posición, progresos, medidas): `montage.state` solo sale si cambia otra cosa.
    static func stable(_ s: MontageSnapshot) -> MontageSnapshot {
        var s = s
        s.transport.position = 0
        s.transport.videoPosition = 0
        s.preview.audio.progress = 0
        s.preview.delivered = 0
        s.preview.skipped = 0
        s.preview.lastFrameMillis = 0
        s.preview.frameP50Ms = 0
        s.preview.frameP95Ms = 0
        s.exportStatus.progress = 0
        s.framing = s.framing.map { var f = $0; f.progress = 0; return f }
        // El porcentaje de una conversión en marcha no cuenta (ni en `progress` ni en el texto); «pendiente» y fallo, sí.
        s.preview.videos = s.preview.videos.map { v in
            guard v.code == VideoConversionConstants.convertingCode, v.progress != 1 else { return v }
            var u = v
            u.progress = 0
            u.message = ""
            return u
        }
        return s
    }

    /// Tomas del montaje cuyo vídeo espera (orden de las calles), con el estado vivo del motor.
    func videoStatuses(_ c: MontageController) -> [TakeVideoStatusInfo] {
        c.videoLanes.compactMap { l -> TakeVideoStatusInfo? in
            guard let s = c.videoStates[l.takeID] else { return nil }
            return TakeVideoStatusInfo(takeId: l.takeID, state: videoConversion?.currentState(takeId: l.takeID) ?? s)
        }
    }

    /// Fin de una conversión (el motor avisa desde cualquier hilo; el `Bridge` lo trae aquí).
    func videoConversionFinished(takeId: UUID, state: TakeVideoState) {
        guard let c = current else { return }
        c.videoConversionFinished(takeId: takeId, state: state)
        stateChanged()
    }

    // MARK: Eventos

    /// Coalesce los cambios de un mismo turno y solo emite `montage.state` si la instantánea cambió de verdad.
    func stateChanged() {
        guard !statePending else { return }
        statePending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            statePending = false
            guard let c = current else { return }
            let s = Self.stable(snapshot(c))
            guard s != lastState else { return }
            lastState = s
            emit("montage.state", snapshot(c))
        }
    }

    private func exportChanged() {
        guard let c = current else { return }
        let ev = Self.exportEvent(c.exportPhase)
        let now = ProcessInfo.processInfo.systemUptime
        if ev.phase == "running", now - lastExportAt < MontageConstants.progressInterval, ev.progress < 1 { return }
        lastExportAt = now
        emit("montage.export", ev)
    }

    private func framingChanged(_ id: UUID) {
        guard let c = current else { return }
        let ev = Self.framingEvent(id, c.framingStatus[id])
        let now = ProcessInfo.processInfo.systemUptime
        if ev.status == "analyzing", now - (lastFramingAt[id] ?? 0) < MontageConstants.progressInterval, ev.progress > 0 { return }
        lastFramingAt[id] = now
        emit("montage.framing", ev)
    }

    private func resetTicker() {
        lastPosition = MontagePositionEvent(seconds: -1, videoSeconds: -1, playing: false)
        lastPositionAt = 0
        ticker?.cancel()
        ticker = Task { [weak self] in
            let clock = ContinuousClock()
            let period = Duration.nanoseconds(Int64(1_000_000_000 / MontageConstants.positionHz))
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
        guard let c = current else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPositionAt >= MontageConstants.minPositionSpacing else { return }
        let e = MontagePositionEvent(seconds: c.songTime, videoSeconds: c.videoPosition, playing: c.isPlaying)
        guard c.isPlaying || e != lastPosition else { return }
        lastPositionAt = now
        lastPosition = e
        emit("montage.position", e)
        if e.playing != lastState?.transport.playing { stateChanged() }
    }
}

/// Salida de eventos segura entre hilos (la pone el anfitrión desde cualquiera).
private final class MontageOutbox: @unchecked Sendable {
    private let lock = NSLock()
    private var sink: @Sendable (String) -> Void = { _ in }
    func set(_ s: @escaping @Sendable (String) -> Void) { lock.withLock { sink = s } }
    func send(_ m: String) { lock.withLock { sink }(m) }
}

// MARK: - Bridge

extension Bridge {
    /// Guarda el montaje abierto y suelta su audio; el anfitrión lo llama al cerrar la ventana (también `shutdownAsync`).
    public func closeMontage() async { await montageService.close() }

    /// Sustituye el receptor de los fotogramas de la vista previa (BGRA reducido, PTS en ms de vídeo). Sin llamarlo, el
    /// núcleo los manda solo por `frames.montage` (W2-E2); nil vuelve a eso. Cualquier hilo.
    public func setMontageFrameSink(_ sink: (@Sendable (MontageFramePixels, Double) -> Void)?) {
        Task { @MainActor [montageService] in montageService.setFrameSink(sink) }
    }

    /// Relevo de Montaje: hasta 60 fps (manda `setPreviewFps`, 1…60) y `latestWins` para no perder el fotograma de una
    /// pausa o un `seek` (W2-E2).
    static let montageRelayMaxFPS = 60.0

    func registerMontageMethods() {
        montageService.makeFrameRelay = { [weak self] in
            self?.makeFrameRelay(channel: "montage", maxFPS: Bridge.montageRelayMaxFPS, latestWins: true)
        }
        montageService.setSink { [weak self] in self?.send($0) }
        montageService.register(on: router)
    }
}
