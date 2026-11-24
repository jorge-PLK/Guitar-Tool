import Foundation
import ModelKit
import Store

// W2-A: núcleo de Ajustes que no es audio (pestañas «Biblioteca» y «Cámara y vídeo» del Mac:
// `App/Sources/SettingsView.swift`, `VideoSettingsView.swift`). Todo se guarda en el `profile.json` de Store.
// `tools.*` está en `LinkMethods.swift` y `host.pickProjectsFolder` en `ImportMethods.swift`; `audio.*` es de otra parte.

// MARK: - Cámaras (protocolo propio de AppCore; el adaptador a VideoKit lo pone el anfitrión)

public struct SettingsFrameRange: Sendable, Equatable {
    public var min: Double
    public var max: Double
    public init(min: Double, max: Double) { self.min = min; self.max = max }
    func clamp(_ fps: Double) -> Double { Swift.min(Swift.max(fps, min), max) }
}

public struct SettingsCameraFormat: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var frameRates: [SettingsFrameRange]
    public init(width: Int, height: Int, frameRates: [SettingsFrameRange]) {
        self.width = width; self.height = height; self.frameRates = frameRates
    }
    func closestFrameRate(to fps: Double) -> Double {
        frameRates.map { $0.clamp(fps) }.min { abs($0 - fps) < abs($1 - fps) } ?? fps
    }
}

public struct SettingsCamera: Sendable, Equatable {
    public var id: String
    public var name: String
    /// `builtIn`, `external`, `continuity`, `simulated` u `other` (solo para enseñarlo).
    public var kind: String
    public var formats: [SettingsCameraFormat]
    public init(id: String, name: String, kind: String = "other", formats: [SettingsCameraFormat]) {
        self.id = id; self.name = name; self.kind = kind; self.formats = formats
    }
}

/// Cámaras del sistema detrás de un protocolo. Pendiente: adaptador a `VideoKit.MediaFoundationCameraProvider`
/// (lo cablea W2-C o el anfitrión con `SettingsEnvironment.cameras`); mientras tanto no hay cámaras.
public protocol SettingsCameraProviding: AnyObject, Sendable {
    func cameras() -> [SettingsCamera]
    /// Cámara por defecto del sistema (`nil` si no hay ninguna).
    func defaultCamera() -> SettingsCamera?
    /// Aviso al conectar o desconectar una cámara (en cualquier hilo).
    func setChangeHandler(_ handler: (@Sendable () -> Void)?)
}

/// Proveedor por omisión: sin cámaras.
final class NoCameraProvider: SettingsCameraProviding, @unchecked Sendable {
    func cameras() -> [SettingsCamera] { [] }
    func defaultCamera() -> SettingsCamera? { nil }
    func setChangeHandler(_ handler: (@Sendable () -> Void)?) {}
}

/// Proveedor simulado (tests y `--audio simulated`): lista fija, con aviso de cambio a mano.
public final class SimulatedSettingsCameras: SettingsCameraProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var list: [SettingsCamera]
    private var handler: (@Sendable () -> Void)?
    public init(cameras: [SettingsCamera]) { list = cameras }
    public func cameras() -> [SettingsCamera] { lock.withLock { list } }
    public func defaultCamera() -> SettingsCamera? { lock.withLock { list.first } }
    public func setChangeHandler(_ handler: (@Sendable () -> Void)?) { lock.withLock { self.handler = handler } }
    public func setCameras(_ cameras: [SettingsCamera]) {
        let h = lock.withLock { () -> (@Sendable () -> Void)? in list = cameras; return handler }
        h?()
    }
}

/// Punto de inyección del anfitrión (se lee en cada llamada, así que puede ponerse tras crear el `Bridge`).
public enum SettingsEnvironment {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _cameras: (any SettingsCameraProviding)?
    public static var cameras: (any SettingsCameraProviding)? {
        get { lock.withLock { _cameras } }
        set { lock.withLock { _cameras = newValue } }
    }
}

// MARK: - Lógica pura copiada de `CameraChoices` (VideoSettingsView.swift:42-82)

enum SettingsCameraChoices {
    /// Códecs que se ofrecen: en Windows solo H.264 (decisión del 21/11/2026), así la página no pinta selector.
    #if os(Windows)
    static let codecs: [VideoCodec] = [.h264]
    #else
    static let codecs: [VideoCodec] = VideoCodec.allCases
    #endif

    /// Códec que se guarda (W2-E2): uno que no se ofrece (p. ej. `hevc` en Windows) se normaliza al primero ofrecido (`h264`).
    static func normalized(_ c: VideoCodec, offered: [VideoCodec] = codecs) -> VideoCodec {
        offered.contains(c) ? c : (offered.first ?? c)
    }

    /// Resoluciones del producto (mini-spec Fase 6): 720p, 1080p y 4K.
    static let presets: [VideoResolution] = [.hd720, .fullHD, .uhd4K]
    /// Frecuencias habituales; se ofrecen las que caen dentro de algún rango del formato.
    static let commonFPS: [Double] = [24, 25, 30, 50, 60, 120]
    /// Rango del desfase por defecto en ms (`VideoSettingsView.offsetRangeMs`).
    static let offsetRangeMs: ClosedRange<Double> = -500...500

    static func resolutions(of camera: SettingsCamera?) -> [VideoResolution] {
        guard let camera else { return [] }
        let all = Set(camera.formats.map { VideoResolution(width: $0.width, height: $0.height) })
        let known = presets.filter(all.contains)
        return known.isEmpty ? all.sorted { $0.width * $0.height < $1.width * $1.height } : known
    }

    static func frameRates(of camera: SettingsCamera?, at r: VideoResolution) -> [Double] {
        guard let camera else { return [] }
        let ranges = camera.formats.filter { $0.width == r.width && $0.height == r.height }.flatMap(\.frameRates)
        let fps = commonFPS.filter { f in ranges.contains { f >= $0.min - 1e-6 && f <= $0.max + 1e-6 } }
        return fps.isEmpty ? Array(Set(ranges.map(\.max))).sorted() : fps
    }

    static func label(_ r: VideoResolution) -> String {
        switch r {
        case .hd720: "720p"
        case .fullHD: "1080p"
        case .uhd4K: "4K"
        default: "\(r.width)×\(r.height)"
        }
    }

    static func label(fps: Double) -> String {
        if fps == fps.rounded() { return "\(Int(fps)) fps" }
        var s = String(format: "%.2f", fps)
        while s.hasSuffix("0") { s.removeLast() }
        return "\(s) fps"
    }

    /// Formato más cercano al pedido (`CameraDevice.closestFormat`): primero la resolución, luego los fps.
    static func closest(_ camera: SettingsCamera, width: Int, height: Int, fps: Double) -> (format: SettingsCameraFormat, fps: Double)? {
        func distance(_ f: SettingsCameraFormat) -> (Double, Double) {
            let area = log(Double(f.width * f.height) / Double(max(1, width * height)))
            let aspect = log((Double(f.width) / Double(max(1, f.height))) / (Double(width) / Double(max(1, height))))
            return ((abs(area) * 1e6).rounded(), (abs(aspect) * 1e6).rounded())
        }
        let best = camera.formats.enumerated().min { a, b in
            let ra = distance(a.element), rb = distance(b.element)
            if ra != rb { return ra < rb }
            let fa = abs(a.element.closestFrameRate(to: fps) - fps), fb = abs(b.element.closestFrameRate(to: fps) - fps)
            if fa != fb { return fa < fb }
            return a.offset < b.offset
        }
        return best.map { ($0.element, $0.element.closestFrameRate(to: fps)) }
    }
}

// MARK: - JSON con nulos explícitos

enum SJ: Encodable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case num(Double)
    case str(String)
    case arr([SJ])
    case obj([String: SJ])

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .num(let d): try c.encode(d)
        case .str(let s): try c.encode(s)
        case .arr(let a): try c.encode(a)
        case .obj(let o): try c.encode(o)
        }
    }

    static func opt(_ s: String?) -> SJ { s.map(SJ.str) ?? .null }
    static func res(_ r: VideoResolution) -> SJ {
        .obj(["width": .int(Int64(r.width)), "height": .int(Int64(r.height)), "label": .str(SettingsCameraChoices.label(r))])
    }
}

// MARK: - Parámetros

struct OptionalIDParams: Codable, Sendable { var id: String? }
struct ModelIDParams: Decodable, Sendable { var id: String? }
struct ResolutionParams: Decodable, Sendable { var width: Int; var height: Int }
struct ExportParams: Decodable, Sendable {
    var codec: String?
    var resolution: ResolutionParams?
    var titleOverlay: Bool?
    var exportStemWAVs: Bool?
}
struct OffsetParams: Decodable, Sendable { var cameraId: String?; var ms: Double }
struct RotationParams: Decodable, Sendable { var cameraId: String?; var degrees: Int }

/// `video.setSettings`: solo cambia lo que viene. `cameraUID: null` = «Por defecto del sistema» (la clave presente con null).
struct SetVideoParams: Decodable, Sendable {
    var hasCamera = false
    var cameraUID: String?
    var resolution: ResolutionParams?
    var fps: Double?
    var offset: OffsetParams?
    var rotation: RotationParams?
    var export: ExportParams?

    private enum Keys: String, CodingKey { case cameraUID, resolution, fps, offset, rotation, export }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        hasCamera = c.contains(.cameraUID)
        if hasCamera { cameraUID = try c.decodeIfPresent(String.self, forKey: .cameraUID) }
        resolution = try c.decodeIfPresent(ResolutionParams.self, forKey: .resolution)
        fps = try c.decodeIfPresent(Double.self, forKey: .fps)
        offset = try c.decodeIfPresent(OffsetParams.self, forKey: .offset)
        rotation = try c.decodeIfPresent(RotationParams.self, forKey: .rotation)
        export = try c.decodeIfPresent(ExportParams.self, forKey: .export)
    }
}

// MARK: - Servicio

/// Perfil, uso de disco, limpieza total, modelos y cámara y vídeo. Un servicio por `Bridge`.
final class SettingsService: @unchecked Sendable {
    /// Modelo de la sección «Modelos» del Mac (`SettingsView.models`: solo BS-RoFormer).
    static let modelID = ModelCatalog.separatorBSRoformerSW.id
    /// Escrituras del `profile.json` en este proceso (leer-modificar-guardar), compartido con quien más lo toque.
    static let profileLock = NSLock()

    private let profile: ProfileStore
    private let jobs: JobEngine
    private let activeFolder: ProjectsRoot
    private let store: ModelStore
    private let resolver: ModelResolver
    private let cameraOverride: (any SettingsCameraProviding)?
    /// Las de `--camera`/`--audio` (W2-E2); detrás de la inyección del anfitrión.
    private var resolvedCameras: (any SettingsCameraProviding)?
    private let sinkLock = NSLock()
    private var _sink: @Sendable (String) -> Void = { _ in }
    private var downloading = Set<String>()
    /// Nombres de cámara vistos en esta sesión, para nombrar la elegida que ya no está conectada (`CameraList.names` del Mac).
    private var knownCameraNames: [String: String] = [:]

    init(profile: ProfileStore, jobs: JobEngine, activeFolder: ProjectsRoot, modelsRoot: URL,
         environment: [String: String] = ProcessInfo.processInfo.environment,
         cameras: (any SettingsCameraProviding)? = nil, downloader: (any ModelDownloading)? = nil) {
        self.profile = profile
        self.jobs = jobs
        self.activeFolder = activeFolder
        let store = downloader.map { ModelStore(root: modelsRoot, downloader: $0, bundleResourceDirectory: Bundle.main.resourceURL) }
            ?? ModelStore(root: modelsRoot, bundleResourceDirectory: Bundle.main.resourceURL)
        self.store = store
        self.resolver = ModelResolver(store: store, environment: environment)
        self.cameraOverride = cameras
    }

    static func production(options: LaunchOptions, jobs: JobEngine, root: ProjectsRoot) -> SettingsService {
        let profile = options.supportDir.map { ProfileStore(url: $0.appendingPathComponent("profile.json")) } ?? ProfileStore()
        let models = options.supportDir.map { $0.appendingPathComponent("Models", isDirectory: true) } ?? ModelStore.defaultRoot
        let s = SettingsService(profile: profile, jobs: jobs, activeFolder: root, modelsRoot: models)
        s.resolvedCameras = resolvedCameras(options)
        return s
    }

    /// W2-E2: las mismas cámaras que Grabar y la vista previa (`RecordCameraSource.resolve`), para que el selector, el
    /// subtítulo y la imagen hablen de la misma cámara (`--camera simulated` lista la simulada). Una sola fuente de verdad
    /// también en el Mac (desvío AJ1/A1): sin opciones de prueba lista las cámaras reales, como `video.preview.start` y
    /// Grabar. Los tests inyectan `SettingsEnvironment.cameras` (o pasan `--camera simulated`) y no llegan aquí.
    static func resolvedCameras(_ options: LaunchOptions) -> (any SettingsCameraProviding)? {
        RecordCameraSource.resolve(options).map { VideoKitCameraAdapter($0.provider) }
    }

    func setSink(_ f: @escaping @Sendable (String) -> Void) { sinkLock.withLock { _sink = f } }
    private func emit<T: Encodable>(_ event: String, _ payload: T) {
        let f = sinkLock.withLock { _sink }
        if let m = Router.eventMessage(event, payload) { f(m) }
    }

    private var cameras: any SettingsCameraProviding {
        cameraOverride ?? SettingsEnvironment.cameras ?? resolvedCameras ?? NoCameraProvider()
    }

    // MARK: Registro

    func register(on router: Router) {
        router.register("settings.get") { [self] (_: Empty) in try settingsGet() }
        router.register("library.usage") { [self] (_: Empty) in try await usage() }
        router.register("library.cleanupInfo") { [self] (p: OptionalIDParams) in try await cleanupInfo(p.id) }
        router.register("library.cleanup") { [self] (p: OptionalIDParams) in try await cleanup(p.id) }
        router.register("models.list") { [self] (_: Empty) in await modelsList() }
        router.register("models.download") { [self] (p: ModelIDParams) in try await modelsDownload(p.id) }
        router.register("models.delete") { [self] (p: ModelIDParams) in try await modelsDelete(p.id) }
        router.register("video.cameras") { [self] (_: Empty) in videoCameras() }
        router.register("video.settings") { [self] (_: Empty) in try videoSettings() }
        router.register("video.setSettings") { [self] (p: SetVideoParams) in try setVideo(p) }
        // Diferido: `register` corre al crear el Bridge, en el hilo de UI de Windows, y enumerar abre cada cámara (Media
        // Foundation, que inicializa COM en MTA e impediría WebView2 en ese hilo). `rememberNames` va bajo `sinkLock`.
        let cams = cameras
        Task.detached { [weak self] in self?.rememberNames(cams.cameras()) }
        // Aviso de cambio en la lista de cámaras (sin sondeo).
        cameras.setChangeHandler { [weak self] in self?.emit("video.camerasChanged", Empty()) }
    }

    // MARK: Perfil y biblioteca

    private func loadProfile() throws -> EquipmentProfile {
        do { return try profile.load() } catch {
            throw RPCError(code: "internal", message: "No se pudo leer el perfil: \(error)")
        }
    }

    private func settingsGet() throws -> SJ {
        let p = try loadProfile()
        return .obj(["projectsFolder": .opt(p.projectsFolder?.path),
                     "activeProjectsFolder": .opt(activeFolder.url?.path),
                     "video": try videoSettings()])
    }

    private func usage() async throws -> SJ {
        let report = try await jobs.diskUsageReport()
        return .obj(["totalBytes": .int(report.totalBytes), "regenerableBytes": .int(report.regenerableBytes),
                     "projects": .arr(report.projects.map {
                         .obj(["id": .str($0.id.uuidString), "folderName": .str($0.folderName),
                               "bytes": .int($0.bytes), "regenerableBytes": .int($0.regenerableBytes)])
                     })])
    }

    private func uuid(_ s: String) throws -> UUID {
        guard let id = UUID(uuidString: s) else { throw RPCError(code: "bad-params", message: "«id» no es un UUID.") }
        return id
    }

    /// `id` nulo o ausente = toda la biblioteca («Limpiar toda la biblioteca» del Mac, `requestCleanup(id: nil)`).
    private func cleanupInfo(_ id: String?) async throws -> CleanupInfoResult {
        guard let id else { return CleanupInfoResult(bytes: try await jobs.diskUsageReport().regenerableBytes) }
        return CleanupInfoResult(bytes: try await jobs.cleanupBytes(id: try uuid(id)))
    }

    private func cleanup(_ id: String?) async throws -> CleanupResult {
        guard let id else { return CleanupResult(cleaned: true, bytes: try await jobs.cleanupEverything()) }
        return CleanupResult(cleaned: true, bytes: try await jobs.cleanup(id: try uuid(id)))
    }

    // MARK: Modelos

    private func modelEntry() async -> SJ {
        let d = ModelCatalog.separatorBSRoformerSW
        let archive = ModelFormat.native == .onnx
            ? (d.onnxFile(physicalMemory: ProcessInfo.processInfo.physicalMemory)?.bytes ?? d.archiveBytes) : d.archiveBytes
        var state = "notInstalled"
        var fraction = SJ.null, bytes = SJ.null, message = SJ.null, source = SJ.null
        switch await store.state(d.id) {
        case .notInstalled: break
        case .downloading(let p): state = "downloading"; fraction = .num(p)
        case .verifying: state = "verifying"
        case .installing: state = "installing"
        case .installed(_, let b): state = "installed"; bytes = .int(b); source = .str("store")
        case .failed(let m): state = "failed"; message = .str(m)
        }
        // Windows: un `.onnx` en `TF_MODELS_DIR` también deja el modelo listo (sin tamaño que enseñar ni cosa que borrar).
        if state == "notInstalled" || state == "failed", await resolver.isInstalled(d.id) { state = "installed"; source = .str("folder") }
        return .obj(["id": .str(d.id), "name": .str(d.displayName), "state": .str(state), "fraction": fraction,
                     "bytes": bytes, "archiveBytes": .int(archive), "message": message, "source": source])
    }

    private func modelsList() async -> SJ {
        .obj(["models": .arr([await modelEntry()]), "modelsBytes": .int(await store.diskUsage())])
    }

    private func checkModel(_ id: String?) throws {
        if let id, id != Self.modelID { throw RPCError(code: "not-found", message: "No hay ningún modelo con id \(id).") }
    }

    /// `ModelStore.ensureInstalled` (descarga, verifica, instala). Progreso por `models.progress`; fin por `models.changed`.
    private func modelsDownload(_ id: String?) async throws -> SJ {
        try checkModel(id)
        let started = sinkLock.withLock { downloading.insert(Self.modelID).inserted }
        guard started else { return .obj(["started": .bool(false)]) }
        let id = Self.modelID
        Task { [self] in
            var failure = SJ.null
            let last = ProgressGate()
            do {
                _ = try await store.ensureInstalled(id) { [self] f in
                    if last.pass(f) { emit("models.progress", ModelProgress(id: id, fraction: f)) }
                }
            } catch let e {
                let text = (e as? LocalizedError)?.errorDescription ?? "\(e)"
                failure = .obj(["code": .str("model-failed"), "message": .str(text)])
            }
            sinkLock.withLock { _ = downloading.remove(id) }
            emit("models.changed", SJ.obj(["models": .arr([await modelEntry()]), "error": failure]))
        }
        return .obj(["started": .bool(true)])
    }

    private func modelsDelete(_ id: String?) async throws -> SJ {
        try checkModel(id)
        do { try await store.delete(Self.modelID) } catch let e as ModelError {
            if case .busy = e { throw RPCError(code: "busy", message: "El modelo se está descargando.") }
            throw RPCError(code: "internal", message: "No se pudo borrar el modelo: \(e.errorDescription ?? "\(e)")")
        } catch { throw RPCError(code: "internal", message: "No se pudo borrar el modelo: \(error)") }
        return await modelsList()
    }

    // MARK: Cámara y vídeo

    private func effective(_ uid: String?, _ list: [SettingsCamera]) -> SettingsCamera? {
        guard let uid else { return cameras.defaultCamera() }
        return list.first { $0.id == uid }
    }

    private func rememberNames(_ list: [SettingsCamera]) {
        sinkLock.withLock { for c in list { knownCameraNames[c.id] = c.name } }
    }

    private func name(ofCamera id: String) -> String? { sinkLock.withLock { knownCameraNames[id] } }

    private func videoCameras() -> SJ {
        let list = cameras.cameras()
        let def = cameras.defaultCamera()
        rememberNames(list)
        return .obj(["cameras": .arr(list.map { c in
            .obj(["id": .str(c.id), "name": .str(c.name), "kind": .str(c.kind), "isDefault": .bool(c.id == def?.id),
                  "resolutions": .arr(SettingsCameraChoices.resolutions(of: c).map { r in
                      guard case .obj(var o) = SJ.res(r) else { return .null }
                      o["fps"] = .arr(SettingsCameraChoices.frameRates(of: c, at: r).map {
                          .obj(["value": .num($0), "label": .str(SettingsCameraChoices.label(fps: $0))])
                      })
                      return .obj(o)
                  })])
        }), "defaultId": .opt(def?.id)])
    }

    private func videoSettings() throws -> SJ { videoJSON(try loadProfile().video ?? VideoSettings()) }

    private func videoJSON(_ v: VideoSettings) -> SJ {
        let list = cameras.cameras()
        rememberNames(list)
        let camera = effective(v.cameraUID, list)
        let uid = camera?.id ?? v.cameraUID
        // Lo que se enseña como elegido: el valor del perfil si la cámara lo admite; si no, lo más cercano (el perfil no se toca).
        var shown = SJ.null
        if let camera, let m = SettingsCameraChoices.closest(camera, width: v.resolution.width, height: v.resolution.height, fps: v.fps) {
            shown = .obj(["resolution": .res(VideoResolution(width: m.format.width, height: m.format.height)), "fps": .num(m.fps),
                          "fpsLabel": .str(SettingsCameraChoices.label(fps: m.fps))])
        }
        let export = v.export
        return .obj([
            "cameraUID": .opt(v.cameraUID),
            "cameraConnected": .bool(camera != nil),
            "cameraName": .opt(camera?.name ?? v.cameraUID.flatMap { name(ofCamera: $0) }),
            "effectiveCameraId": .opt(uid),
            "noCamera": .bool(list.isEmpty && cameras.defaultCamera() == nil),
            "resolution": .res(v.resolution),
            "fps": .num(v.fps),
            "fpsLabel": .str(SettingsCameraChoices.label(fps: v.fps)),
            "shown": shown,
            "offsetMs": .int(uid.map { Int64((v.defaultOffset(for: $0) * 1000).rounded()) } ?? 0),
            "rotation": .int(Int64(uid.map { v.defaultRotation(for: $0) } ?? 0)),
            "offsetsMs": .obj(v.offsets.mapValues { .int(Int64(($0 * 1000).rounded())) }),
            "rotations": .obj(v.rotations.mapValues { .int(Int64(VideoSettings.normalizedRotation($0))) }),
            "export": .obj(["codec": .str(export.codec.rawValue), "resolution": .res(export.resolution),
                            "titleOverlay": .bool(export.titleOverlay), "exportStemWAVs": .bool(export.exportStemWAVs),
                            "normalizeLUFS": .num(VideoExportDefaults.normalizeLUFS)]),
            "choices": .obj(["codecs": .arr(SettingsCameraChoices.codecs.map { .str($0.rawValue) }),
                             "exportResolutions": .arr(SettingsCameraChoices.presets.map(SJ.res)),
                             "rotations": .arr([0, 90, 180, 270].map { .int($0) }),
                             "offsetRangeMs": .obj(["min": .num(SettingsCameraChoices.offsetRangeMs.lowerBound),
                                                    "max": .num(SettingsCameraChoices.offsetRangeMs.upperBound)])]),
        ])
    }

    private func setVideo(_ p: SetVideoParams) throws -> SJ {
        if let r = p.resolution, r.width <= 0 || r.height <= 0 {
            throw RPCError(code: "bad-params", message: "«resolution» no es válida.")
        }
        if let f = p.fps, !(f.isFinite && f > 0) { throw RPCError(code: "bad-params", message: "«fps» no es válido.") }
        var codec: VideoCodec?
        if let c = p.export?.codec {
            guard let v = VideoCodec(rawValue: c) else { throw RPCError(code: "bad-params", message: "«export.codec» es hevc o h264.") }
            codec = SettingsCameraChoices.normalized(v)
        }
        if let r = p.export?.resolution, r.width <= 0 || r.height <= 0 {
            throw RPCError(code: "bad-params", message: "«export.resolution» no es válida.")
        }
        // Desfase y giro van a la cámara indicada o, si no, a la que se usaría ahora (`syncGroup` del Mac).
        let list = cameras.cameras()
        func target(_ explicit: String?, _ v: VideoSettings) throws -> String {
            if let explicit { return explicit }
            guard let uid = effective(v.cameraUID, list)?.id ?? v.cameraUID else {
                throw RPCError(code: "bad-params", message: "No hay ninguna cámara a la que aplicarlo: indica «cameraId».")
            }
            return uid
        }
        Self.profileLock.lock(); defer { Self.profileLock.unlock() }
        var all = try loadProfile()
        var v = all.video ?? VideoSettings()
        if p.hasCamera { v.cameraUID = p.cameraUID }
        if let r = p.resolution { v.resolution = VideoResolution(width: r.width, height: r.height) }
        if let f = p.fps { v.fps = f }
        if let o = p.offset {
            guard o.ms.isFinite else { throw RPCError(code: "bad-params", message: "«offset.ms» no es válido.") }
            let clamped = min(max(o.ms.rounded(), SettingsCameraChoices.offsetRangeMs.lowerBound), SettingsCameraChoices.offsetRangeMs.upperBound)
            v.setDefaultOffset(clamped / 1000, for: try target(o.cameraId, v))
        }
        if let r = p.rotation { v.setDefaultRotation(r.degrees, for: try target(r.cameraId, v)) }
        if let e = p.export {
            if let codec { v.export.codec = codec }
            if let r = e.resolution { v.export.resolution = VideoResolution(width: r.width, height: r.height) }
            if let t = e.titleOverlay { v.export.titleOverlay = t }
            if let w = e.exportStemWAVs { v.export.exportStemWAVs = w }
        }
        all.video = v
        do { try profile.save(all) } catch {
            throw RPCError(code: "internal", message: "No se pudo guardar el perfil: \(error)")
        }
        return videoJSON(v)
    }
}

struct ModelProgress: Codable, Sendable { var id: String; var fraction: Double }

/// Deja pasar un progreso cada punto porcentual (el aviso de descarga no inunda el puente).
private final class ProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1
    func pass(_ f: Double) -> Bool {
        let step = Int((f * 100).rounded(.down))
        return lock.withLock { if step == last { return false }; last = step; return true }
    }
}

extension JobEngine {
    /// `Library.diskUsage` (espacio usado y lo que liberaría «Limpiar…»).
    func diskUsageReport() async throws -> DiskUsageReport {
        let lib = try await library()
        return await lib.diskUsage()
    }

    /// «Limpiar toda la biblioteca»: `Library.cleanupAll` (salta los temas ocupados), como `AppModel.performCleanup(id: nil)`.
    func cleanupEverything() async throws -> Int64 {
        let lib = try await library()
        do { return try await lib.cleanupAll() } catch { throw Self.map(error) }
    }
}

extension Bridge {
    func registerSettingsMethods(root: ProjectsRoot, options: LaunchOptions) {
        let service = SettingsService.production(options: options, jobs: jobs, root: root)
        service.setSink { [weak self] in self?.send($0) }
        service.register(on: router)
    }
}
