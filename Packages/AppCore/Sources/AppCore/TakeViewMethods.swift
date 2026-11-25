import AudioKit
import Foundation
import Store
import VideoKit

// «Ver toma» en Windows (contrato W2-V): la toma y su backing suenan en el núcleo, con el mismo motor que Estudio y Grabar
// (`StudyAudio` + `StudyPlayer`, como la vista previa de Montaje), y el `<video>` de la página sigue a este reloj.
//
// Qué suena (como `TakeViewPlanning.plan` del Mac): la toma con el volumen de su canal «Tú · parte» y, con el backing
// encendido, las pistas de `library.takeBacking`. El tramo silenciado de la guitarra que la parte sustituye es el tramo
// entero de la toma, que es justo lo que se reproduce: esas pistas no se cargan (cuentan para `hasBacking`, como en el Mac).
// Tiempo del visor: 0 = inicio de la toma, hasta la duración de su `processed.wav`.

/// Números del visor de tomas (contrato W2-V).
enum TakeViewConstants {
    /// Eventos `takeview.position` por segundo mientras suena (como `study.position` y `montage.position`).
    static let positionHz = 30.0
    /// `TakeViewerModel.togglePlay` del Mac: a menos de 0,1 s del final, play vuelve al principio.
    static let restartMargin = 0.1
    /// Fin de la toma: se programa una parada exacta cuando quedan menos de estos periodos del ticker.
    static let endLookaheadPeriods = 2.0
    /// Id del canal de la toma en el reproductor.
    static let takeTrackID = "take"
    static let noAudioMessage = "Esta toma no tiene audio que reproducir."
    static let notOpenMessage = "No hay ninguna toma abierta en el visor."
    /// Hoja «Ajustar desfase» (W2-O, Mac `OffsetSheet.togglePlay`): a menos de un fotograma (1/30 s) del final, play vuelve al principio.
    static let offsetRestartMargin = 1.0 / 30
    static let noOffsetMessage = "No hay ninguna hoja de desfase abierta."
}

/// Toma de la hoja «Ajustar desfase» (W2-O). La da Grabar (`RecordController.offsetRequest`): la toma nueva aún no está en
/// `project.json`, así que no se puede abrir por `takeview.open`.
struct TakeViewOffsetSource: Sendable {
    var projectId: UUID
    var takeId: UUID
    /// `processed.wav` de la toma (lo único que suena en la hoja, como el `TakePreview` del Mac).
    var audioURL: URL
    var songStart: Double
    /// Vídeo de la base y de los punches (una toma del Mac puede ser HEVC: se convierte como en el visor).
    var videoURLs: [URL?] = []
    /// FC1: tamaño del fotograma y giro de la toma (0 = desconocido).
    var videoWidth: Int = 0
    var videoHeight: Int = 0
    var videoRotation: Int = 0
    /// Vídeo nativo (ola 3.3.AS): fichero de la base, punches, desfase inicial (s) y lectura en vivo del desfase de la hoja
    /// (nil si la hoja ya no está).
    var videoURL: URL? = nil
    var punches: [PreviewPunch] = []
    var offset: Double = 0
    var liveOffset: (@MainActor @Sendable () -> Double?)? = nil
}

/// Reloj que publica el núcleo: la posición del reproductor alisada contra el reloj de host (lazo de fase de primer orden).
/// `StudyPlayer.currentTime` avanza a saltos de bloque cuando lo renderiza una sesión (simulada o alojada) y con el
/// temblor de las llamadas del dispositivo; la página necesita una recta. Cada muestra corrige `gain` del residuo; un
/// residuo mayor que `resyncThreshold` es una discontinuidad (hueco del dispositivo) y se reancla.
struct TakeViewClock: Sendable {
    /// s. Por encima, el residuo no es temblor sino un salto del reproductor.
    static let resyncThreshold = 0.030
    /// A 30 Hz, constante de tiempo ≈ 1 / (0,1 · 30) ≈ 0,33 s; el temblor de un bloque se reduce ×0,23.
    static let gain = 0.1

    private var anchor: (pos: Double, at: Double)?
    /// Posición en la que espera el reproductor recién arrancado (no se ancla hasta que se mueve).
    private var frozen: Double?

    /// Tras play, pausa o búsqueda: la próxima muestra se toma tal cual.
    mutating func reset() {
        anchor = nil
        frozen = nil
    }

    /// `raw`: posición del reproductor leída en `at` (s de host). Devuelve la posición publicada en `at` y si el reloj ya
    /// avanza (antes de que suene la primera muestra el reproductor da siempre la misma posición).
    mutating func sample(raw: Double, at: Double) -> (seconds: Double, moving: Bool) {
        guard let a = anchor else {
            if let f = frozen, raw != f {
                anchor = (raw, at)
                return (raw, true)
            }
            frozen = raw
            return (raw, false)
        }
        let predicted = a.pos + (at - a.at)
        let residual = raw - predicted
        let pos = abs(residual) > Self.resyncThreshold ? raw : predicted + Self.gain * residual
        anchor = (pos, at)
        return (pos, true)
    }
}

// MARK: - Tipos del puente

struct TakeViewOpenParams: Decodable, Sendable { var projectId: String; var takeId: String }
struct TakeViewSeekParams: Decodable, Sendable { var seconds: Double }
struct TakeViewBackingParams: Decodable, Sendable { var on: Bool }

struct TakeViewSnapshot: Codable, Sendable, Equatable {
    var projectId: String
    var takeId: String
    /// Duración de la toma (s).
    var duration: Double
    /// Inicio de la toma en el tema (s): el `<video>` busca el fotograma de PTS `songStart + seconds + desfase`.
    var songStart: Double
    /// Hay pistas de backing (si no, el botón no tiene nada que silenciar).
    var hasBacking: Bool
    var backingOn: Bool
    var playing: Bool
    /// Tiempo de la toma (s).
    var position: Double
    var epoch: Int
    var outputName: String
    var audioError: String?
    /// Fase 7c: el vídeo aún no se puede ver (convirtiéndose a H.264, convertido pero con el original aún en uso por otro
    /// programa, o fallido); nil = listo. El progreso vivo está en `jobs.progress` con la clave `video.jobId`; el cambio
    /// con el visor abierto llega por `takeview.video`.
    var video: TakeVideoStatusInfo? = nil
    /// FC1: tamaño del fotograma de la toma (px) y giro en grados horarios, para `TfVideoSurface`; nil = sin vídeo o desconocido.
    var videoWidth: Int? = nil
    var videoHeight: Int? = nil
    var videoRotation: Int = 0
}

/// `takeview.video` (Fase 7c, opción b' de Jorge): cambió el vídeo de la toma abierta en el visor o en la hoja de desfase
/// (sustitución aplicada, fallo o respaldo `busy`). `video` nil = ya se puede ver: la página carga solo el `<video>`,
/// sincronizado con el reloj del núcleo, sin cerrar el visor ni tocar el audio.
struct TakeViewVideoEvent: Codable, Sendable, Equatable {
    var takeId: String
    var video: TakeVideoStatusInfo?
}

/// `takeview.position`: reloj del visor.
struct TakeViewPositionEvent: Codable, Sendable, Equatable {
    /// Tiempo de la toma que se oye en `at` (s).
    var seconds: Double
    var playing: Bool
    /// 1 si el reloj avanza (suena), 0 si está quieto (pausa o esperando la primera muestra).
    var rate: Double
    /// Reloj de host del núcleo (QPC en Windows, `mach_absolute_time` en el Mac), s.
    var at: Double
    /// Sube en cada discontinuidad (play, pausa, búsqueda, final).
    var epoch: Int
}

// MARK: - Sesión

/// Toma abierta en el visor: su propia salida (`StudyAudio`) con la toma y el backing.
@MainActor
final class TakeViewSession {
    let projectId: UUID
    let takeId: UUID
    let audio: StudyAudio
    let duration: Double
    let songStart: Double
    /// Tiempo del reproductor que corresponde al 0 de la toma (`songStart` con backing; 0 si la toma va sola).
    let base: Double
    let backingIDs: [String]
    let hasBacking: Bool
    /// s antes del final en que play vuelve al principio (visor 0,1 s; hoja de desfase 1 fotograma).
    let restartMargin: Double
    /// Reproductor de la hoja «Ajustar desfase» (W2-O): Grabar lo cierra antes de guardar o descartar la toma.
    let isOffset: Bool
    private(set) var backingOn = true
    private(set) var epoch = 0
    private(set) var audioError: String?
    var clock = TakeViewClock()
    /// FC1: formato del vídeo de la toma (nil = sin vídeo).
    var videoWidth: Int?
    var videoHeight: Int?
    var videoRotation = 0
    /// Último instante pedido por la página en pausa (el reproductor lo guarda igual; aquí para no depender de él).
    var player: StudyPlayer { audio.player }

    init(projectId: UUID, takeId: UUID, audio: StudyAudio, duration: Double, songStart: Double, base: Double,
         backingIDs: [String], hasBacking: Bool, audioError: String?,
         restartMargin: Double = TakeViewConstants.restartMargin, isOffset: Bool = false) {
        self.restartMargin = restartMargin
        self.isOffset = isOffset
        if isOffset { backingOn = false }
        self.projectId = projectId
        self.takeId = takeId
        self.audio = audio
        self.duration = duration
        self.songStart = songStart
        self.base = base
        self.backingIDs = backingIDs
        self.hasBacking = hasBacking
        self.audioError = audioError
    }

    var isPlaying: Bool { player.isPlaying }
    /// Tiempo de la toma sin alisar.
    var rawPosition: Double { player.currentTime - base }
    var position: Double { min(max(rawPosition, 0), duration) }

    func bump() {
        epoch += 1
        clock.reset()
    }

    func play() throws {
        if position >= duration - restartMargin { player.seek(to: base) }
        do {
            try player.play()
            audioError = nil
        } catch {
            let message = "No se pudo reproducir: la salida de audio no abre (\(BackingController.describe(error)))."
            audioError = message
            throw RPCError(code: "audio-unavailable", message: message)
        }
        bump()
    }

    func pause() {
        player.pause()
        bump()
    }

    func seek(to t: Double) {
        player.seek(to: base + min(max(t, 0), duration))
        bump()
    }

    /// Final de la toma: para y deja la posición en la duración (como el `AVPlayer` del Mac). Devuelve el backing que
    /// sonó tras la toma (`audible`, s) y cuánto tarde lo vio el reloj (`detected`, s). El reproductor no programa nada
    /// tras su `endTime` (= final de la toma, `open`): lo que sonó llega como mucho hasta ahí aunque el hilo principal
    /// lo vea un bloque o un tic de temporizador después.
    func stopAtEnd() -> (audible: Double, detected: Double) {
        let raw = rawPosition
        let audioEnd = (player.endTime ?? player.duration) - base
        player.pause()
        player.seek(to: base + duration)
        bump()
        return (min(raw, audioEnd) - duration, raw - duration)
    }

    /// Backing apagado = sus canales en silencio (sin recargar: la toma sigue sin cortes).
    func setBacking(_ on: Bool) {
        backingOn = on
        for id in backingIDs { player.setMute(id, !on) }
    }

    func shutdown() { audio.shutdown() }
}

// MARK: - Servicio

/// Visor de tomas del núcleo: una toma abierta a la vez. Vive en el hilo principal.
@MainActor
final class TakeViewService {
    private let options: LaunchOptions
    private let root: ProjectsRoot
    private let profileStore: ProfileStore?
    private let outbox = TakeViewOutbox()
    /// Antes de abrir y de dar a play: para lo que suene en Backing.
    private let pauseOthers: @MainActor @Sendable () -> Void
    /// Reloj de host del campo `at` (tests: sustituible).
    var now: @MainActor () -> Double = { HostClock.nowSeconds }
    /// W2-O: la toma de la hoja de desfase abierta en Grabar (nil = no hay hoja); también pausa lo que suene en Grabar.
    /// La pone el `Bridge` al registrar `record.*`.
    nonisolated(unsafe) var offsetSource: (@MainActor @Sendable () -> TakeViewOffsetSource?)?
    /// Espera a los guardados de tomas pendientes del tema (`StudySession.awaitTakeSaves`) antes de leer `project.json`:
    /// Grabar anuncia la toma en `record.state` antes de que su `Task` la escriba en disco. La pone el `Bridge`.
    nonisolated(unsafe) var awaitTakeSaves: (@MainActor @Sendable (_ projectId: UUID) async -> Void)?
    /// Fase 7c: conversión HEVC → H.264 (la pone el `Bridge`). El visor no se cierra por ella: la sustitución se aplica al
    /// terminar aunque la toma esté abierta y la página recarga solo el `<video>` (`takeview.video`, opción b' de Jorge).
    nonisolated(unsafe) var videoConversion: VideoConversionEngine?
    /// Último `takeview.video` emitido (tests).
    private(set) var lastVideoEvent: TakeViewVideoEvent?

    #if canImport(AVFoundation)
    /// Reproductor nativo del vídeo de la toma abierta (nil = sin vídeo o fallo). Esclavo de `takeview.position`.
    private(set) var videoPlayer: TakeVideoPlayer?
    /// Receptor del reproductor (canal `take` de AppCoreFFI): recibe el reproductor al abrir y nil al cerrar. La pone el `Bridge`.
    nonisolated(unsafe) var takeVideoSink: (@Sendable (TakeVideoPlayer?) -> Void)?
    private var liveOffset: (@MainActor @Sendable () -> Double?)?

    /// Arma el reproductor de vídeo; un fallo no impide abrir el visor (el audio sigue).
    private func startVideo(audioURL: URL, songStart: Double, videoURL: URL?, punches: [PreviewPunch], offset: Double,
                            live: (@MainActor @Sendable () -> Double?)?) async {
        guard videoURL != nil || punches.contains(where: { $0.videoURL != nil }) else { return }
        guard let preview = try? await TakePreview.load(audioURL: audioURL, songStart: songStart, videoURL: videoURL, punches: punches),
              let p = try? TakeVideoPlayer(preview: preview, offset: offset) else { return }
        videoPlayer = p
        liveOffset = live
        takeVideoSink?(p)
    }
    #endif

    private(set) var current: TakeViewSession?
    private var ticker: Task<Void, Never>?
    private var endTask: Task<Void, Never>?
    private var lastPosition: TakeViewPositionEvent?
    /// Backing que sonó tras el final de la toma en la última parada (s; tests).
    private(set) var lastEndOvershoot: Double?
    /// Cuánto después del final vio la parada el hilo principal (s; solo diagnóstico: el audio ya paró en `endTime`).
    private(set) var lastEndDetectionLag: Double?

    nonisolated init(options: LaunchOptions, root: ProjectsRoot, pauseOthers: @escaping @MainActor @Sendable () -> Void = {}) {
        self.options = options
        self.root = root
        self.pauseOthers = pauseOthers
        if let dir = options.supportDir {
            profileStore = ProfileStore(url: dir.appendingPathComponent("profile.json"))
        } else {
            profileStore = options.audio == .simulated ? nil : ProfileStore()
        }
    }

    nonisolated func setSink(_ sink: @escaping @Sendable (String) -> Void) { outbox.set(sink) }

    func emit<T: Encodable>(_ event: String, _ payload: T) {
        if let m = Router.eventMessage(event, payload) { outbox.send(m) }
    }

    nonisolated func register(on router: Router) {
        router.register("takeview.open") { [self] (p: TakeViewOpenParams) -> TakeViewSnapshot in try await open(p) }
        router.register("takeview.openOffset") { [self] (_: Empty) -> TakeViewSnapshot in try await openOffset() }
        router.register("takeview.close") { [self] (_: Empty) -> Empty in await close(); return Empty() }
        router.register("takeview.snapshot") { [self] (_: Empty) -> TakeViewSnapshot in try await with { _ in } }
        router.register("takeview.play") { [self] (_: Empty) -> TakeViewSnapshot in
            try await with { s in
                pauseOthers()
                try s.play()
            }
        }
        router.register("takeview.pause") { [self] (_: Empty) -> TakeViewSnapshot in try await with { $0.pause() } }
        router.register("takeview.seek") { [self] (p: TakeViewSeekParams) -> TakeViewSnapshot in
            guard p.seconds.isFinite else { throw RPCError(code: "bad-params", message: "«seconds» no es un número.") }
            return try await with { $0.seek(to: p.seconds) }
        }
        router.register("takeview.setBacking") { [self] (p: TakeViewBackingParams) -> TakeViewSnapshot in
            try await with { $0.setBacking(p.on) }
        }
    }

    nonisolated private static var notOpen: RPCError { RPCError(code: "not-open", message: TakeViewConstants.notOpenMessage) }

    /// Aplica el cambio, publica la posición (cada cambio de transporte es una discontinuidad) y devuelve la instantánea.
    private func with(_ change: @MainActor (TakeViewSession) throws -> Void) throws -> TakeViewSnapshot {
        guard let s = current else { throw Self.notOpen }
        let before = s.epoch
        try change(s)
        if s.epoch != before {
            cancelEnd()
            publish(s, force: true)
        }
        return snapshot(s)
    }

    func snapshot(_ s: TakeViewSession) -> TakeViewSnapshot {
        TakeViewSnapshot(projectId: s.projectId.uuidString, takeId: s.takeId.uuidString, duration: s.duration, songStart: s.songStart,
                         hasBacking: s.hasBacking, backingOn: s.backingOn, playing: s.isPlaying, position: s.position,
                         epoch: s.epoch, outputName: s.audio.outputName, audioError: s.audioError,
                         video: videoConversion.flatMap { TakeVideoStatusInfo(takeId: s.takeId, state: $0.currentState(takeId: s.takeId)) },
                         videoWidth: s.videoWidth, videoHeight: s.videoHeight, videoRotation: s.videoRotation)
    }

    /// Pide el vídeo de la toma al motor de conversión (encola si es HEVC). Justo antes de `install`, sin `await` entre
    /// medias: cuando llegue el fin de la conversión (`videoConversionFinished`, en el hilo principal), `current` ya es esta.
    private func requestVideo(takeId: UUID, files: [URL?], title: String) {
        _ = videoConversion?.state(takeId: takeId, files: files, title: title)
    }

    /// Fase 7c (opción b' de Jorge): fin de una conversión o de su sustitución. Si el visor o la hoja de desfase tiene esa
    /// toma abierta, emite `takeview.video` para que la página cargue solo el `<video>` (o actualice el aviso); el visor
    /// sigue abierto y el audio no se para ni se reinicia.
    func videoConversionFinished(takeId: UUID, state: TakeVideoState) {
        guard current?.takeId == takeId else { return }
        let e = TakeViewVideoEvent(takeId: takeId.uuidString, video: TakeVideoStatusInfo(takeId: takeId, state: state))
        lastVideoEvent = e
        emit("takeview.video", e)
    }

    // MARK: Abrir y cerrar

    func open(_ p: TakeViewOpenParams) async throws -> TakeViewSnapshot {
        guard let pid = UUID(uuidString: p.projectId), let tid = UUID(uuidString: p.takeId) else {
            throw RPCError(code: "bad-params", message: "«projectId» y «takeId» deben ser UUID.")
        }
        await awaitTakeSaves?(pid)
        let lib = try Bridge.service(root)
        let folder = try lib.folder(id: pid)
        let project: Project
        do { project = try ProjectFile.load(folder: folder) } catch {
            throw RPCError(code: "internal", message: "No se pudo leer project.json: \(error)")
        }
        guard let take = project.takes.first(where: { $0.id == tid }), let rel = take.processedFile, take.songStart != nil else {
            throw RPCError(code: "not-found", message: TakeViewConstants.noAudioMessage)
        }
        let takeURL = ProjectLayout(folder: folder).url(relative: rel)
        guard let duration = LibraryService.duration(of: takeURL), duration > 0 else {
            throw RPCError(code: "not-found", message: TakeViewConstants.noAudioMessage)
        }
        let backing = try lib.takeBacking(id: pid, takeId: tid)
        await close()
        pauseOthers()

        let audio = makeAudio()
        let start = backing.takeStart
        // El tramo silenciado cubre la toma entera (es la toma): esas pistas no suenan nunca en el visor.
        let playable = backing.tracks.filter { t in
            guard let m = t.mutedSpan else { return true }
            return m.end <= start || m.start >= start + duration
        }
        let ids = playable.indices.map { "backing-\($0)" }
        let base: Double
        let first: URL
        do {
            if playable.isEmpty {
                try audio.player.load(tracks: [Track(id: TakeViewConstants.takeTrackID, url: takeURL)])
                audio.player.setGain(TakeViewConstants.takeTrackID, dB: Self.dB(backing.takeVolume))
                base = 0
                first = takeURL
            } else {
                let tracks = zip(ids, playable).map { Track(id: $0, url: lib.root.appendingPathComponent($1.path)) }
                try audio.player.load(tracks: tracks)
                try audio.player.setTakes([TakeTrack(id: TakeViewConstants.takeTrackID, url: takeURL, songStart: start,
                                                     gainDB: Self.dB(backing.takeVolume))])
                for (id, t) in zip(ids, playable) { audio.player.setGain(id, dB: Self.dB(t.volume)) }
                base = start
                first = tracks[0].url
            }
        } catch {
            audio.shutdown()
            throw RPCError(code: "load-failed", message: "No se pudo preparar la toma (\(BackingController.describe(error))).")
        }
        // Parada exacta al final de la toma por muestras, en el reproductor (el ticker solo actualiza el estado).
        audio.player.endTime = base + duration
        let audioError = Self.prepare(audio, first: first)
        audio.player.seek(to: base)
        let layout = ProjectLayout(folder: folder)
        #if canImport(AVFoundation)
        await startVideo(audioURL: takeURL, songStart: start, videoURL: take.videoFile.map { layout.url(relative: $0) },
                         punches: (take.punches ?? []).map {
                             PreviewPunch(start: $0.start, end: $0.end, videoURL: $0.videoFile.map { layout.url(relative: $0) },
                                          videoOffset: $0.videoOffset ?? take.videoOffset ?? 0)
                         }, offset: take.videoOffset ?? 0, live: nil)
        #endif
        requestVideo(takeId: tid, files: [take.videoFile.map { layout.url(relative: $0) }]
                        + (take.punches ?? []).map { $0.videoFile.map { layout.url(relative: $0) } },
                     title: "\(project.song.title) · vídeo de la toma")
        let session = TakeViewSession(projectId: pid, takeId: tid, audio: audio, duration: duration, songStart: start, base: base,
                                      backingIDs: ids, hasBacking: !backing.tracks.isEmpty, audioError: audioError)
        if take.videoFile != nil, let f = take.videoFormat {
            session.videoWidth = f.width
            session.videoHeight = f.height
            session.videoRotation = take.rotationDegrees
        }
        return install(session)
    }

    /// W2-O «Ajustar desfase»: solo la toma (`processed.wav`, a 0 dB como el `AVPlayer` del Mac), sin backing; tiempo 0 = inicio
    /// de la toma. El desfase no toca el audio: lo aplica la página al objetivo del `<video>` (`CoreTakeSync.setOffset`).
    func openOffset() async throws -> TakeViewSnapshot {
        guard let src = offsetSource?() else { throw RPCError(code: "no-offset", message: TakeViewConstants.noOffsetMessage) }
        guard let duration = LibraryService.duration(of: src.audioURL), duration > 0 else {
            throw RPCError(code: "not-found", message: TakeViewConstants.noAudioMessage)
        }
        await close()
        pauseOthers()
        let audio = makeAudio()
        do {
            try audio.player.load(tracks: [Track(id: TakeViewConstants.takeTrackID, url: src.audioURL)])
        } catch {
            audio.shutdown()
            throw RPCError(code: "load-failed", message: "No se pudo preparar la toma (\(BackingController.describe(error))).")
        }
        audio.player.endTime = duration
        let audioError = Self.prepare(audio, first: src.audioURL)
        audio.player.seek(to: 0)
        #if canImport(AVFoundation)
        await startVideo(audioURL: src.audioURL, songStart: src.songStart, videoURL: src.videoURL, punches: src.punches,
                         offset: src.offset, live: src.liveOffset)
        #endif
        requestVideo(takeId: src.takeId, files: src.videoURLs, title: "Vídeo de la toma")
        let session = TakeViewSession(projectId: src.projectId, takeId: src.takeId, audio: audio, duration: duration,
                                      songStart: src.songStart, base: 0, backingIDs: [], hasBacking: false, audioError: audioError,
                                      restartMargin: TakeViewConstants.offsetRestartMargin, isOffset: true)
        if src.videoWidth > 0, src.videoHeight > 0 {
            session.videoWidth = src.videoWidth
            session.videoHeight = src.videoHeight
            session.videoRotation = src.videoRotation
        }
        return install(session)
    }

    /// W2-O: cierra el reproductor solo si es el de la hoja de desfase. Grabar lo llama antes de guardar o descartar la toma
    /// (en Windows no se puede borrar un `processed.wav` abierto).
    func closeOffset() async {
        if current?.isOffset == true { await close() }
    }

    /// Antes de borrar una toma: si el visor (o la hoja de desfase) la tiene abierta, la cierra y suelta sus ficheros.
    /// En NTFS no se borra un fichero con un lector abierto, y el `takeview.close` de la página puede llegar después.
    func release(takeId: UUID) async {
        if current?.takeId == takeId { await close() }
    }

    /// Salida del perfil (canales de backing), como Montaje y Estudio.
    private func makeAudio() -> StudyAudio {
        let profile = (try? profileStore?.load()) ?? EquipmentProfile()
        let output = OutputSelection(deviceUID: profile.audio?.outputDeviceUID,
                                     left: profile.audio?.backingOut.left ?? 1, right: profile.audio?.backingOut.right ?? 2)
        return StudyAudio(mode: options.audio, output: output)
    }

    private static func prepare(_ audio: StudyAudio, first: URL) -> String? {
        do { try audio.prepare(firstTrack: first) } catch {
            return "No se pudo abrir la salida de audio (\(BackingController.describe(error)))."
        }
        return nil
    }

    private func install(_ s: TakeViewSession) -> TakeViewSnapshot {
        current = s
        lastEndOvershoot = nil
        lastEndDetectionLag = nil
        resetTicker()
        publish(s, force: true)
        return snapshot(s)
    }

    /// Para y suelta la salida y los ficheros. También lo llama el cierre del anfitrión.
    func close() async {
        ticker?.cancel()
        ticker = nil
        cancelEnd()
        #if canImport(AVFoundation)
        if let v = videoPlayer {
            videoPlayer = nil
            liveOffset = nil
            takeVideoSink?(nil)
            v.close()
        }
        #endif
        guard let s = current else { return }
        current = nil
        lastPosition = nil
        s.shutdown()
        // Respaldo `busy` (opción b' de Jorge): si la sustitución se quedó pendiente porque el original seguía en uso, se
        // reintenta ahora que el visor soltó sus ficheros.
        if let engine = videoConversion, engine.currentState(takeId: s.takeId) == .awaitingRelease {
            let id = s.takeId
            Task { await engine.applyPendingSoon(takeId: id) }
        }
    }

    static func dB(_ linear: Double) -> Double { 20 * log10(max(linear, 1e-6)) }

    // MARK: Reloj

    private func resetTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            let clock = ContinuousClock()
            let period = Duration.nanoseconds(Int64(1_000_000_000 / TakeViewConstants.positionHz))
            var next = clock.now + period
            while !Task.isCancelled {
                try? await clock.sleep(until: next)
                guard !Task.isCancelled, let self else { return }
                tick()
                next = max(next + period, clock.now)
            }
        }
    }

    func tick() {
        guard let s = current else { return }
        #if canImport(AVFoundation)
        if let off = liveOffset?() { videoPlayer?.setOffset(off) }
        #endif
        if s.isPlaying {
            let remaining = s.duration - s.rawPosition
            if remaining <= 0 { finish(s); return }
            if remaining <= TakeViewConstants.endLookaheadPeriods / TakeViewConstants.positionHz, endTask == nil { scheduleEnd(after: remaining) }
        }
        publish(s, force: false)
    }

    /// Estado de parada al final: duerme lo que queda y vuelve a mirar (el reloj del dispositivo manda, no el del hilo).
    /// El audio ya no depende de esto: el reproductor no programa nada tras `endTime`. Con temporizadores de ~15,6 ms
    /// (Windows) o bloques a ráfagas, esto llega tarde; solo cambia cuándo se publica `playing: false`.
    private func scheduleEnd(after seconds: Double) {
        endTask = Task { [weak self] in
            var wait = seconds
            while wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1e9))
                guard !Task.isCancelled, let self, let s = current, s.isPlaying else { return }
                wait = s.duration - s.rawPosition
            }
            guard let self, let s = current, s.isPlaying else { return }
            endTask = nil
            finish(s)
        }
    }

    private func cancelEnd() {
        endTask?.cancel()
        endTask = nil
    }

    private func finish(_ s: TakeViewSession) {
        cancelEnd()
        (lastEndOvershoot, lastEndDetectionLag) = s.stopAtEnd()
        publish(s, force: true)
    }

    /// Posición alisada en el instante de host en que se lee (`at` se toma justo tras leer el reproductor).
    private func publish(_ s: TakeViewSession, force: Bool) {
        let e: TakeViewPositionEvent
        if s.isPlaying {
            let raw = s.rawPosition
            let at = now()
            let c = s.clock.sample(raw: raw, at: at)
            e = TakeViewPositionEvent(seconds: min(max(c.seconds, 0), s.duration), playing: true, rate: c.moving ? 1 : 0, at: at, epoch: s.epoch)
        } else {
            e = TakeViewPositionEvent(seconds: s.position, playing: false, rate: 0, at: now(), epoch: s.epoch)
        }
        // En pausa solo se repite si cambió algo (el `at` no cuenta).
        if !force, !e.playing, let last = lastPosition, !last.playing, last.epoch == e.epoch, last.seconds == e.seconds { return }
        lastPosition = e
        #if canImport(AVFoundation)
        videoPlayer?.apply(e)
        #endif
        emit("takeview.position", e)
    }
}

/// Salida de eventos segura entre hilos (la pone el anfitrión desde cualquiera).
private final class TakeViewOutbox: @unchecked Sendable {
    private let lock = NSLock()
    private var sink: @Sendable (String) -> Void = { _ in }
    func set(_ s: @escaping @Sendable (String) -> Void) { lock.withLock { sink = s } }
    func send(_ m: String) { lock.withLock { sink }(m) }
}

// MARK: - Bridge

extension Bridge {
    /// Para y suelta el visor de tomas (cierre del anfitrión; también `shutdownAsync`).
    public func closeTakeView() async { await takeViewService.close() }

    func registerTakeViewMethods() {
        takeViewService.setSink { [weak self] in self?.send($0) }
        // La toma recién grabada puede no estar aún en `project.json` (StudySession.saveTakes la guarda en un `Task`).
        takeViewService.awaitTakeSaves = { [weak self] pid in
            guard let s = self?.studyService.current?.session, s.projectID == pid else { return }
            await s.awaitTakeSaves()
        }
        takeViewService.register(on: router)
    }
}
