import Foundation
import SourceKit
import Store
import VideoKit
import XCTest
@testable import AppCore

/// Conversión HEVC → H.264 de las tomas (Fase 7c, `VideoConversion.swift`): motor con un ffmpeg de guion
/// (`ScriptedProcessRunner`) y MP4 sintéticos (solo cajas), sustitución al terminar aunque el visor tenga la toma abierta
/// (opción b' de Jorge) con el respaldo `busy` (original en uso), puerta del montaje y visor por el puente con el evento
/// `takeview.video`. Portátil: la política y el `busy` de NTFS se inyectan.
final class VideoConversionTests: XCTestCase {    // MARK: MP4 sintéticos

    enum MP4 {
        static func u32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
        static func box(_ type: String, _ body: Data) -> Data { u32(UInt32(8 + body.count)) + Data(type.utf8) + body }
        static func put32(_ d: inout Data, _ at: Int, _ v: UInt32) { d.replaceSubrange(at..<(at + 4), with: u32(v)) }

        /// Pista de vídeo con `frames` muestras de `delta` (escala `mediaTS`) y lista de ediciones `(duración, inicio)`
        /// (inicio −1 = tramo vacío), detrás de `mdat` (como `IMFSinkWriter` y el ffmpeg sin `+faststart`).
        static func write(_ url: URL, entry: String, movieTS: UInt32, mediaTS: UInt32, frames: UInt32, delta: UInt32,
                          edits: [(UInt32, Int32)]) throws {
            var mvhd = Data(count: 100)
            put32(&mvhd, 12, movieTS)
            var tkhd = Data(count: 84)
            put32(&tkhd, 12, 1)
            var mdhd = Data(count: 24)
            put32(&mdhd, 12, mediaTS)
            put32(&mdhd, 16, frames * delta)
            var hdlr = Data(count: 25)
            hdlr.replaceSubrange(8..<12, with: Array("vide".utf8))
            var visual = Data(count: 78)
            visual[24] = 0x05; visual[25] = 0x00   // 1280
            visual[26] = 0x02; visual[27] = 0xD0   // 720
            let stsd = box("stsd", Data(count: 4) + u32(1) + box(entry, visual))
            let stts = box("stts", Data(count: 4) + u32(1) + u32(frames) + u32(delta))
            let mdia = box("mdia", box("mdhd", mdhd) + box("hdlr", hdlr) + box("minf", box("stbl", stsd + stts)))
            var elst = Data(count: 4) + u32(UInt32(edits.count))
            for (d, t) in edits { elst += u32(d) + u32(UInt32(bitPattern: t)) + u32(0x0001_0000) }
            let moov = box("moov", box("mvhd", mvhd) + box("trak", box("tkhd", tkhd) + box("edts", box("elst", elst)) + mdia))
            let ftyp = box("ftyp", Data("isom".utf8) + Data(count: 4) + Data("isom".utf8))
            try (ftyp + box("mdat", Data(count: 1000)) + moov).write(to: url)
        }

        /// Toma del Mac: HEVC, 30 fotogramas a 30 fps (1 s) que empiezan a 20,0 s del tema.
        static func macTake(_ url: URL) throws {
            try write(url, entry: "hvc1", movieTS: 600, mediaTS: 600, frames: 30, delta: 20, edits: [(12_000, -1), (600, 0)])
        }

        /// Lo que deja ffmpeg: H.264 a 90 000, desde 0 (sin tramo vacío: lo pone `alignStart`).
        static func ffmpegOutput(_ url: URL, frames: UInt32 = 30) throws {
            try write(url, entry: "avc1", movieTS: 90_000, mediaTS: 90_000, frames: frames, delta: 3000, edits: [(frames * 3000, 0)])
        }
    }

    // MARK: Ayudas

    final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var v: T
        init(_ v: T) { self.v = v }
        var value: T {
            get { lock.withLock { v } }
            set { lock.withLock { v = newValue } }
        }
    }

    /// Respaldo `busy` simulado en cualquier sistema: los próximos `failures` intentos de sustituir fallan como NTFS con el
    /// original abierto; `attempts` cuenta los intentos.
    final class BusyOriginal: @unchecked Sendable {
        let failures = Box(0)
        let attempts = Box(0)
    }

    /// Eventos que el núcleo manda a la página (`bridge.send`).
    final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(name: String, payload: [String: Any])] = []
        func add(_ json: String) {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
                  let name = o["event"] as? String else { return }
            lock.withLock { items.append((name, o["payload"] as? [String: Any] ?? [:])) }
        }
        func all(_ name: String) -> [[String: Any]] { lock.withLock { items.filter { $0.name == name }.map(\.payload) } }
        /// Nombres en orden de llegada.
        var names: [String] { lock.withLock { items.map(\.name) } }
    }

    struct Rig {
        var dir: URL
        var takeId: UUID
        var video: URL
        var temp: URL
        var engine: VideoConversionEngine
        var runner: ScriptedProcessRunner
        var jobs: Box<[JobInfo]>
        var seen: Box<[TakeVideoState]>
        var busy: BusyOriginal
    }

    /// Reintentos del respaldo `busy` en los tests (la pausa real, 0,5 s, solo alarga la espera).
    static let testRetries = 2
    static let testRetryDelay: TimeInterval = 0.01

    static func ffmpegRule(frames: UInt32 = 30, gate: DispatchSemaphore? = nil) -> ScriptedResponse {
        ScriptedResponse(progressLines: ["out_time_us=500000", "progress=continue", "out_time_us=1000000", "progress=end"],
                         sideEffect: { req in
                             _ = gate?.wait(timeout: .now() + 5)
                             try MP4.ffmpegOutput(URL(fileURLWithPath: req.arguments.last!), frames: frames)
                         })
    }

    static func hooks(_ runner: ScriptedProcessRunner, busy: BusyOriginal? = nil) -> VideoConversionEngine.Hooks {
        var h = VideoConversionEngine.Hooks(ffmpeg: { URL(fileURLWithPath: "ffmpeg.exe") }, runner: runner, needsConversion: { $0.codec == .hevc })
        if let busy {
            h.replace = { original, converted in
                busy.attempts.value += 1
                if busy.failures.value > 0 {
                    busy.failures.value -= 1
                    throw CocoaError(.fileWriteNoPermission)
                }
                try FileOps.atomicReplace(original, with: converted)
            }
        }
        return h
    }

    func makeRig(rules: [(String, ScriptedResponse)] = [("h264_nvenc", ffmpegRule())]) throws -> Rig {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("videoconv-\(UUID().uuidString)", isDirectory: true)
        let takeId = UUID()
        let takeDir = dir.appendingPathComponent("takes/\(takeId.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: takeDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let video = takeDir.appendingPathComponent("video.mov")
        try MP4.macTake(video)
        let runner = ScriptedProcessRunner()
        for (n, r) in rules { runner.on(n, r) }
        let jobEngine = JobEngine(root: nil, profileStore: ProfileStore(url: dir.appendingPathComponent("p.json")), indexURL: nil,
                                  services: { fatalError("no se usa") })
        let jobs = Box<[JobInfo]>([])
        jobEngine.setSinks(job: { j in jobs.value.append(j) }, changed: {})
        let busy = BusyOriginal()
        let engine = VideoConversionEngine(jobs: jobEngine, hooks: Self.hooks(runner, busy: busy))
        engine.releaseRetries = Self.testRetries
        engine.releaseRetryDelay = Self.testRetryDelay
        let seen = Box<[TakeVideoState]>([])
        engine.addObserver { _, s in seen.value.append(s) }
        return Rig(dir: dir, takeId: takeId, video: video, temp: takeDir.appendingPathComponent(".converting-video.mov"), engine: engine,
                   runner: runner, jobs: jobs, seen: seen, busy: busy)
    }

    func codec(_ url: URL) throws -> TakeVideoCodec? { try TakeVideoProbe.read(url)?.codec }

    func start(_ r: Rig) -> TakeVideoState { r.engine.state(takeId: r.takeId, files: [r.video, nil], title: "Tema · vídeo de la toma") }

    /// Conversión terminada con el original en uso hasta agotar los reintentos: queda pendiente (`awaitingRelease`).
    func startPending(_ r: Rig) async {
        r.busy.failures.value = 1_000
        _ = start(r)
        await r.engine.wait(takeId: r.takeId)
        XCTAssertEqual(r.engine.currentState(takeId: r.takeId), .awaitingRelease)
        r.busy.failures.value = 0
    }

    @discardableResult
    func waitUntil(_ timeout: Double = 5, _ cond: @escaping () -> Bool) async -> Bool {
        let end = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < end {
            if cond() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return cond()
    }

    // MARK: Motor

    /// HEVC → ffmpeg (NVENC) → tramo vacío del original → verificación → sustitución: el fichero pasa a H.264 con el primer
    /// fotograma en el mismo PTS del tema (20,0 s ± 1 ms), sin temporal, y el trabajo `video-<takeId>` acaba en `done`.
    func testConvertsHEVCTakeAndReplacesOriginal() async throws {
        let r = try makeRig()
        XCTAssertEqual(try codec(r.video), .hevc)
        XCTAssertEqual(start(r), .converting(nil))
        // La segunda petición no encola otro trabajo: sigue `converting` (con progreso ya, si el motor es rápido, como en Windows).
        if case .converting = start(r) {} else { XCTFail("una segunda petición no encola otro trabajo") }
        await r.engine.wait(takeId: r.takeId)
        XCTAssertEqual(r.engine.currentState(takeId: r.takeId), .ready)
        let after = try XCTUnwrap(TakeVideoProbe.read(r.video))
        XCTAssertEqual(after.codec, .h264)
        XCTAssertEqual(after.firstFrameTime, 20.0, accuracy: TakeVideoTranscode.firstFrameTolerance)
        XCTAssertEqual(after.duration, 1.0, accuracy: 1.0 / 30)
        XCTAssertFalse(FileManager.default.fileExists(atPath: r.temp.path))
        XCTAssertEqual(r.runner.requests.count, 1)
        let args = r.runner.requests[0].arguments
        XCTAssertTrue(args.contains("h264_nvenc"))
        XCTAssertEqual(args.last, r.temp.path)
        XCTAssertEqual(r.seen.value, [.ready])
        XCTAssertEqual(r.busy.attempts.value, 1, "se sustituye al primer intento, sin esperar a nadie")
        let mine = r.jobs.value.filter { $0.id == "video-\(r.takeId.uuidString)" }
        XCTAssertEqual(mine.first?.state, "queued")
        XCTAssertEqual(mine.last?.state, "done")
        XCTAssertTrue(mine.allSatisfy { $0.stage == "video" }, "la página no debe pintarlo como separación")
        // Ya es H.264: la siguiente petición no convierte.
        XCTAssertEqual(start(r), .ready)
        XCTAssertEqual(r.runner.requests.count, 1)
    }

    /// Sin NVENC (código 1), Media Foundation (`h264_mf`).
    func testFallsBackToMediaFoundationEncoder() async throws {
        let r = try makeRig(rules: [("h264_nvenc", ScriptedResponse(stderr: "No NVENC capable devices found", status: 1)),
                                    ("h264_mf", Self.ffmpegRule())])
        _ = start(r)
        await r.engine.wait(takeId: r.takeId)
        XCTAssertEqual(r.engine.currentState(takeId: r.takeId), .ready)
        XCTAssertEqual(r.runner.requests.map { $0.arguments.contains("h264_nvenc") }, [true, false])
        XCTAssertTrue(r.runner.requests[1].arguments.contains("h264_mf"))
        XCTAssertEqual(try codec(r.video), .h264)
    }

    /// La conversión que no pasa la verificación (le faltan fotogramas) deja el original, sin temporal; el fallo se recuerda
    /// (no se reintenta en cada vista previa) hasta `forget`.
    func testVerificationFailureKeepsOriginal() async throws {
        let r = try makeRig(rules: [("h264_nvenc", Self.ffmpegRule(frames: 20))])
        _ = start(r)
        await r.engine.wait(takeId: r.takeId)
        guard case .failed(let m) = r.engine.currentState(takeId: r.takeId) else { return XCTFail("debía fallar") }
        XCTAssertTrue(m.contains("verificación"), m)
        XCTAssertEqual(try codec(r.video), .hevc)
        XCTAssertFalse(FileManager.default.fileExists(atPath: r.temp.path))
        XCTAssertEqual(r.jobs.value.last?.state, "failed")
        if case .failed = start(r) {} else { XCTFail("el fallo se recuerda") }
        XCTAssertEqual(r.runner.requests.count, 1)
        r.engine.forget(takeIds: [r.takeId])
        XCTAssertEqual(start(r), .converting(nil))
        await r.engine.wait(takeId: r.takeId)
        XCTAssertEqual(r.runner.requests.count, 2)
    }

    /// Respaldo `busy` (antes `testViewerHoldsSwapUntilReleased`): si el original sigue en uso al terminar, se reintenta
    /// `releaseRetries` veces; agotados, el convertido verificado espera como `.converting-video.mov` (`awaitingRelease`)
    /// y se aplica en cuanto el original se libera.
    func testBusyOriginalKeepsSwapPendingAfterRetries() async throws {
        let r = try makeRig()
        await startPending(r)
        XCTAssertEqual(r.busy.attempts.value, 1 + Self.testRetries, "un intento y sus reintentos")
        XCTAssertEqual(try codec(r.video), .hevc, "el original sigue en su sitio")
        XCTAssertEqual(try codec(r.temp), .h264, "el convertido verificado espera junto al original")
        XCTAssertEqual(r.engine.pendingSwaps(takeId: r.takeId).map(\.converted), [r.temp])
        XCTAssertEqual(r.seen.value.last, .awaitingRelease)
        XCTAssertFalse(r.seen.value.contains(.ready))
        XCTAssertEqual(r.jobs.value.last?.state, "running")
        XCTAssertEqual(r.jobs.value.last?.text, VideoConversionConstants.awaitingText)
        let info = try XCTUnwrap(TakeVideoStatusInfo(takeId: r.takeId, state: .awaitingRelease))
        XCTAssertEqual(info.code, "video-converting")
        XCTAssertEqual(info.message, VideoConversionEngine.awaitingMessage)

        let released = await r.engine.applyPending(takeId: r.takeId)
        XCTAssertEqual(released, .applied)
        XCTAssertEqual(try codec(r.video), .h264)
        XCTAssertEqual(try XCTUnwrap(TakeVideoProbe.read(r.video)).firstFrameTime, 20.0, accuracy: TakeVideoTranscode.firstFrameTolerance)
        XCTAssertFalse(FileManager.default.fileExists(atPath: r.temp.path))
        XCTAssertEqual(r.engine.currentState(takeId: r.takeId), .ready)
        XCTAssertEqual(r.seen.value.last, .ready)
        XCTAssertEqual(r.jobs.value.last?.state, "done")
        let again = await r.engine.applyPending(takeId: r.takeId)
        XCTAssertEqual(again, .nothing)
    }

    /// Si el original se libera durante los reintentos, la sustitución se aplica en el mismo trabajo, sin quedar pendiente.
    func testBusyOriginalSwapsOnRetry() async throws {
        let r = try makeRig()
        r.busy.failures.value = Self.testRetries
        _ = start(r)
        await r.engine.wait(takeId: r.takeId)
        XCTAssertEqual(r.busy.attempts.value, 1 + Self.testRetries)
        XCTAssertEqual(r.engine.currentState(takeId: r.takeId), .ready)
        XCTAssertEqual(try codec(r.video), .h264)
        XCTAssertEqual(r.seen.value.last, .ready)
        XCTAssertFalse(FileManager.default.fileExists(atPath: r.temp.path))
    }

    /// La siguiente petición del vídeo (montaje, encuadre, export o el visor) aplica la sustitución pendiente si el
    /// original ya se liberó.
    func testNextRequestAppliesPendingSwap() async throws {
        let r = try makeRig()
        await startPending(r)
        XCTAssertEqual(start(r), .awaitingRelease, "la respuesta es inmediata; la sustitución va en segundo plano")
        let ok = await waitUntil { r.engine.currentState(takeId: r.takeId) == .ready }
        XCTAssertTrue(ok)
        XCTAssertEqual(try codec(r.video), .h264)
        XCTAssertEqual(r.runner.requests.count, 1, "no se vuelve a convertir")
    }

    /// Borrar la toma descarta su conversión pendiente (sin tocar el original, que borra quien borra la toma).
    func testDiscardDropsPendingConversion() async throws {
        let r = try makeRig()
        await startPending(r)
        await r.engine.discard(takeId: r.takeId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: r.temp.path))
        XCTAssertEqual(r.engine.currentState(takeId: r.takeId), .ready)
        XCTAssertEqual(try codec(r.video), .hevc)
        XCTAssertEqual(r.jobs.value.last?.state, "cancelled")
    }

    /// Si la toma desaparece mientras espera, el convertido se tira y no se recrea la carpeta.
    func testTakeDeletedWhilePendingIsDropped() async throws {
        let r = try makeRig()
        await startPending(r)
        try FileManager.default.removeItem(at: r.video)
        let outcome = await r.engine.applyPending(takeId: r.takeId)
        XCTAssertEqual(outcome, .gone)
        XCTAssertFalse(FileManager.default.fileExists(atPath: r.video.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: r.temp.path))
        XCTAssertEqual(r.engine.currentState(takeId: r.takeId), .ready)
    }

    #if os(Windows)
    /// NTFS de verdad: con el original abierto por otro (aquí un `FileHandle`), la sustitución real (`FileOps.atomicReplace`)
    /// falla en cada reintento y queda pendiente (`busy`); al cerrarlo, se aplica.
    func testOpenFileKeepsSwapPending() async throws {
        let r = try makeRig()
        let runner = ScriptedProcessRunner()
        runner.on("h264_nvenc", Self.ffmpegRule())
        let engine = VideoConversionEngine(jobs: r.engine.jobs, hooks: Self.hooks(runner))
        engine.releaseRetries = Self.testRetries
        engine.releaseRetryDelay = Self.testRetryDelay
        let handle = try FileHandle(forReadingFrom: r.video)
        _ = engine.state(takeId: r.takeId, files: [r.video], title: "Tema · vídeo de la toma")
        await engine.wait(takeId: r.takeId)
        XCTAssertEqual(engine.currentState(takeId: r.takeId), .awaitingRelease)
        XCTAssertEqual(try codec(r.video), .hevc)
        let busy = await engine.applyPending(takeId: r.takeId)
        XCTAssertEqual(busy, .busy)
        try handle.close()
        let applied = await engine.applyPending(takeId: r.takeId)
        XCTAssertEqual(applied, .applied)
        XCTAssertEqual(try codec(r.video), .h264)
    }
    #endif

    // MARK: Visor por el puente

    struct ViewerRig {
        var bridge: Bridge
        var events: Events
        var runner: ScriptedProcessRunner
        var projectId: UUID
        var takeId: UUID
        var video: URL
        var temp: URL
        var openParams: String { "{\"projectId\":\"\(projectId.uuidString)\",\"takeId\":\"\(takeId.uuidString)\"}" }
    }

    /// Proyecto con una toma de 3 s (seno) y su vídeo HEVC del Mac; puente con el audio simulado y el ffmpeg de guion.
    @MainActor
    func makeViewerRig(ffmpeg: ScriptedResponse = ffmpegRule()) throws -> ViewerRig {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("videoconv-tv-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("projects", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        var p = Project(song: Song(title: "Tema", artist: "Banda", source: "source/original.wav", sourceSHA256: "abc",
                                   sourceFormat: "wav", sourceSampleRate: StudyTests.sampleRate, sourceChannels: 2,
                                   sampleRate: StudyTests.sampleRate, duration: StudyTests.seconds))
        p.separation = SeparationState(state: .done, model: "m", finishedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let folder = root.appendingPathComponent("Banda - Tema", isDirectory: true)
        let layout = ProjectLayout(folder: folder)
        try layout.createSkeleton()
        var take = Take(processedFile: "takes/t1/processed.wav", songStart: 2)
        take.videoFile = "takes/t1/video.mov"
        try FileManager.default.createDirectory(at: layout.url(relative: "takes/t1"), withIntermediateDirectories: true)
        try StudyTests.writeSine(layout.url(relative: "takes/t1/processed.wav"), frequency: 330, seconds: 3)
        let video = layout.url(relative: "takes/t1/video.mov")
        try MP4.macTake(video)
        p.takes = [take]
        let part = RecordingPart(name: "Rítmica", replaces: .rhythm, takeIDs: [take.id], bestTakeID: take.id)
        p.recording = RecordingState(parts: [part], mix: [], partMix: [])
        try ProjectFile.save(p, to: folder)
        let runner = ScriptedProcessRunner()
        runner.on("h264_nvenc", ffmpeg)
        let bridge = try Bridge(options: LaunchOptions(projectsFolder: root, supportDir: support, audio: .simulated), mediaBase: "m",
                                reveal: nil, videoHooks: Self.hooks(runner))
        let events = Events()
        bridge.send = { events.add($0) }
        return ViewerRig(bridge: bridge, events: events, runner: runner, projectId: p.id, takeId: take.id, video: video,
                         temp: layout.url(relative: "takes/t1/.converting-video.mov"))
    }

    /// `waitUntil` en el hilo principal (la condición lee el visor, que vive en él).
    @MainActor
    @discardableResult
    func waitOnMain(_ timeout: Double = 5, _ cond: @escaping @MainActor () -> Bool) async -> Bool {
        let end = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < end {
            if cond() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return cond()
    }

    @MainActor
    func call(_ v: ViewerRig, _ method: String, _ params: String = "{}") async -> [String: Any] {
        let out = await v.bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        return (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] ?? [:]
    }

    /// Opción b' de Jorge, de punta a punta (antes `testViewerKeepsOriginalUntilClosed`): `takeview.open` de una toma HEVC
    /// encola la conversión y avisa en `video`; al acabar, la sustitución se aplica con el visor abierto (sin esperar a
    /// `takeview.close`), la página recibe `takeview.video` sin `video` (= ya se puede ver) y la instantánea deja de
    /// marcarla como en conversión.
    @MainActor
    func testViewerOpenGetsConvertedVideoAtOnce() async throws {
        let v = try makeViewerRig()
        let opened = await call(v, "takeview.open", v.openParams)
        let snap = try XCTUnwrap(opened["result"] as? [String: Any], "\(opened)")
        let n = try XCTUnwrap(snap["video"] as? [String: Any], "el visor avisa de la conversión")
        XCTAssertEqual(n["code"] as? String, "video-converting")
        XCTAssertEqual(n["jobId"] as? String, "video-\(v.takeId.uuidString)")
        await v.bridge.videoConversion.wait(takeId: v.takeId)
        XCTAssertEqual(v.bridge.videoConversion.currentState(takeId: v.takeId), .ready)
        XCTAssertEqual(try codec(v.video), .h264, "con el visor abierto se sustituye ya")
        XCTAssertEqual(try XCTUnwrap(TakeVideoProbe.read(v.video)).firstFrameTime, 20.0, accuracy: TakeVideoTranscode.firstFrameTolerance)
        XCTAssertFalse(FileManager.default.fileExists(atPath: v.temp.path))
        XCTAssertEqual(v.bridge.takeViewService.current?.takeId, v.takeId, "el visor no se cierra")

        let arrived = await waitOnMain { !v.events.all("takeview.video").isEmpty }
        XCTAssertTrue(arrived, "la página recibe takeview.video")
        let evs = v.events.all("takeview.video")
        XCTAssertEqual(evs.count, 1)
        XCTAssertEqual(evs.first?["takeId"] as? String, v.takeId.uuidString)
        XCTAssertNil(evs.first?["video"], "sin `video` = ya se puede ver: la página carga el <video>")
        XCTAssertEqual(v.bridge.takeViewService.lastVideoEvent, TakeViewVideoEvent(takeId: v.takeId.uuidString, video: nil))
        let during = await call(v, "takeview.snapshot")
        let ds = try XCTUnwrap(during["result"] as? [String: Any])
        XCTAssertNil(ds["video"], "la instantánea ya no la marca como en conversión")

        _ = await call(v, "takeview.close")
        // Volver a abrir: ya es H.264, sin aviso ni otra conversión.
        let reopened = await call(v, "takeview.open", v.openParams)
        XCTAssertNil((reopened["result"] as? [String: Any])?["video"] as? [String: Any])
        XCTAssertEqual(v.runner.requests.count, 1)
        _ = await call(v, "takeview.close")
    }

    /// El evento llega con la toma sonando y no toca el audio: misma sesión, sigue en play, la época del reloj no cambia
    /// (ninguna discontinuidad) y la posición sigue al reloj real desde el play (± 0,15 s, como `TakeViewTests`). El ffmpeg
    /// de guion espera al play (semáforo), así que la conversión acaba siempre con la toma sonando.
    @MainActor
    func testVideoEventKeepsViewerAndAudioRunning() async throws {
        let gate = DispatchSemaphore(value: 0)
        let v = try makeViewerRig(ffmpeg: Self.ffmpegRule(gate: gate))
        let opened = await call(v, "takeview.open", v.openParams)
        XCTAssertNotNil((opened["result"] as? [String: Any])?["video"] as? [String: Any])
        let played = await call(v, "takeview.play")
        let ps = try XCTUnwrap(played["result"] as? [String: Any], "\(played)")
        XCTAssertEqual(ps["playing"] as? Bool, true)
        let epoch = try XCTUnwrap(ps["epoch"] as? Int)
        let t0 = ProcessInfo.processInfo.systemUptime
        let session = try XCTUnwrap(v.bridge.takeViewService.current)
        gate.signal()

        let arrived = await waitOnMain { !v.events.all("takeview.video").isEmpty }
        XCTAssertTrue(arrived, "la página recibe takeview.video con la toma sonando")
        XCTAssertNil(v.events.all("takeview.video").first?["video"])
        XCTAssertEqual(try codec(v.video), .h264)
        XCTAssertTrue(v.bridge.takeViewService.current === session, "el visor no se cierra ni se reabre")
        XCTAssertTrue(session.isPlaying, "el audio no se para")
        let elapsed = ProcessInfo.processInfo.systemUptime - t0
        XCTAssertEqual(session.position, elapsed, accuracy: 0.15, "el audio no se reinicia")
        let snap = await call(v, "takeview.snapshot")
        let s = try XCTUnwrap(snap["result"] as? [String: Any])
        XCTAssertEqual(s["playing"] as? Bool, true)
        XCTAssertEqual(s["epoch"] as? Int, epoch, "sin discontinuidad del reloj")
        XCTAssertNil(s["video"])
        // El reloj sigue publicando con la misma época tras el evento.
        let before = v.events.all("takeview.position").count
        let more = await waitOnMain(2) { v.events.all("takeview.position").count > before + 3 }
        XCTAssertTrue(more)
        let last = try XCTUnwrap(v.events.all("takeview.position").last)
        XCTAssertEqual(last["playing"] as? Bool, true)
        XCTAssertEqual(last["epoch"] as? Int, epoch)
        await v.bridge.closeTakeView()
    }
}

// MARK: - Puerta del montaje

extension MontageTests {
    /// Fase 7c: mientras el vídeo de una toma se convierte, la vista previa queda en `converting`, su encuadre en espera,
    /// el fotograma del encuadre da `video-converting` y no se exporta; al acabar, todo sigue solo.
    func testMontageWaitsForVideoConversion() async throws {
        let rig = try makeRig()
        let c = try makeController(rig, services: .simulated())
        let converting = rig.takeIDs[0]
        let states = VideoConversionTests.Box<[UUID: TakeVideoState]>([converting: .converting(0.25)])
        var asked: [UUID: [URL?]] = [:]
        c.videoGate = { id, files in
            asked[id] = files
            return states.value[id] ?? .ready
        }
        c.open()
        await waitUntil { c.previewPhase == .converting }
        XCTAssertEqual(c.previewPhase, .converting)
        XCTAssertEqual(asked[converting]?.first ?? nil, rig.layout.videoURL(takeId: converting))
        XCTAssertEqual(c.videoStates[converting], .converting(0.25))
        await waitUntil { c.framingStatus[rig.takeIDs[1]].map { if case .ready = $0 { return true }; return false } ?? false }
        XCTAssertEqual(c.framingStatus[converting], .pending, "sin vídeo legible no se analiza")
        XCTAssertFalse(c.canExport)
        do {
            _ = try await c.framingFrame(takeID: converting, at: 5)
            XCTFail("el encuadre debía esperar")
        } catch let e as RPCError {
            XCTAssertEqual(e.code, "video-converting")
        }
        c.startExport()
        XCTAssertFalse(c.isExporting)

        states.value = [:]
        c.videoConversionFinished(takeId: converting, state: .ready)
        let ready = await waitUntil { c.previewPhase == .ready && !c.isAnalyzing }
        XCTAssertTrue(ready)
        XCTAssertTrue(c.videoStates.isEmpty)
        XCTAssertTrue(c.canExport)
        c.close()
    }

    /// Conversión fallida: la vista previa da el error con el motivo y el encuadre de esa toma también.
    func testMontageShowsVideoConversionFailure() async throws {
        let rig = try makeRig()
        let c = try makeController(rig, services: .simulated())
        let bad = rig.takeIDs[1]
        c.videoGate = { id, _ in id == bad ? .failed("ffmpeg no pudo convertirlo (h264_mf: error)") : .ready }
        c.open()
        await waitUntil { c.previewPhase == .error }
        XCTAssertEqual(c.previewPhase, .error)
        XCTAssertTrue(c.previewError?.contains("ffmpeg no pudo convertirlo") ?? false, c.previewError ?? "")
        await waitUntil { if case .failed = c.framingStatus[bad] { return true }; return false }
        if case .failed(let m) = c.framingStatus[bad] { XCTAssertTrue(m.contains("H.264"), m) } else { XCTFail("encuadre fallido") }
        XCTAssertFalse(c.canExport)
        c.close()
    }
}
