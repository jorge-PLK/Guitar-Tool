import AudioKit
import Foundation
import Store
import VideoKit
import XCTest
@testable import AppCore

/// W2-R1: Grabar (`RecordController`, `record.*`) con audio y cámara simulados; nunca se abre un dispositivo real.
@MainActor
final class RecordTests: XCTestCase {
    override func tearDown() async throws {
        RecordEnvironment.cameras = nil
    }

    // MARK: Tiempos en compases (`BarTiming`; el Mac no tiene tests propios, casos de la mini-spec Fase 6)

    func testBarTimingWithGrid() {
        // 120 BPM, 4/4: compás de 2 s, inicios de compás en 0, 2, 4, ...
        let beats = stride(from: 0.0, through: 30, by: 0.5).map { $0 }
        let downbeats = stride(from: 0.0, through: 30, by: 2).map { $0 }
        let t = BarTiming(beats: beats, downbeats: downbeats)
        XCTAssertEqual(t.beatsPerBar, 4)
        XCTAssertEqual(t.barSeconds, 2, accuracy: 1e-9)
        XCTAssertEqual(t.preRollStart(for: 10, bars: 2), 6, accuracy: 1e-9)
        XCTAssertEqual(t.preRollStart(for: 10.03, bars: 2), 6, accuracy: 1e-9, "tolerancia de 50 ms sobre el inicio de compás")
        XCTAssertEqual(t.preRollStart(for: 3, bars: 2), 0, accuracy: 1e-9, "nunca antes de 0")
        XCTAssertEqual(t.preRollStart(for: 10, bars: 0), 10, accuracy: 1e-9)
        XCTAssertEqual(t.sectionStop(sectionEnd: 10, bars: 2, duration: 100), 14, accuracy: 1e-9)
        XCTAssertEqual(t.sectionStop(sectionEnd: 10, bars: 0, duration: 100), 10, accuracy: 1e-9)
        XCTAssertEqual(t.sectionStop(sectionEnd: 29, bars: 2, duration: 30), 30, accuracy: 1e-9, "tope: el final del tema")
        XCTAssertEqual(t.nearestBar(5.1), 6, accuracy: 1e-9)
        XCTAssertEqual(t.nearestBar(4.9), 4, accuracy: 1e-9)
    }

    func testBarTimingWithoutGridFallsBackTo120BPM() {
        let t = BarTiming(beats: [], downbeats: [])
        XCTAssertEqual(t.beatSeconds, 0.5, accuracy: 1e-9)
        XCTAssertEqual(t.beatsPerBar, 4)
        XCTAssertEqual(t.preRollStart(for: 9, bars: 2), 5, accuracy: 1e-9)
        XCTAssertEqual(t.sectionStop(sectionEnd: 9, bars: 1, duration: 100), 11, accuracy: 1e-9)
        XCTAssertEqual(t.nearestBar(5.1), 6, accuracy: 1e-9)
    }

    // MARK: Equipo de pruebas (puente real, audio y cámara simulados)

    final class Rig {
        let bridge: Bridge
        let svc: RecordService
        let router: Router
        let events: AudioTests.Events
        let folder: URL
        let support: URL
        var layout: ProjectLayout { ProjectLayout(folder: folder) }
        init(bridge: Bridge, svc: RecordService, router: Router, events: AudioTests.Events, folder: URL, support: URL) {
            self.bridge = bridge; self.svc = svc; self.router = router; self.events = events; self.folder = folder; self.support = support
        }
        var project: Project { get throws { try ProjectFile.load(folder: folder) } }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.withLock { n += 1 } }
        var value: Int { lock.withLock { n } }
    }

    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("record-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: d) }
        return d
    }

    func makeRig(guitar: Bool = true, sections: [Section] = [], cameras: RecordCameraSource? = nil) async throws -> Rig {
        let base = try tempDir()
        let root = base.appendingPathComponent("projects", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        var profile = EquipmentProfile()
        profile.video = VideoSettings(resolution: VideoResolution(width: 640, height: 360), fps: 30)
        try ProfileStore(url: support.appendingPathComponent("profile.json")).save(profile)
        let rate = StudyTests.sampleRate
        var project = Project(song: Song(title: "Tema", artist: "Banda", source: "source/original.wav", sourceSHA256: "abc",
                                         sourceFormat: "wav", sourceSampleRate: rate, sourceChannels: 2, sampleRate: rate,
                                         duration: StudyTests.seconds))
        project.separation = SeparationState(state: .done, model: "m", finishedAt: Date(timeIntervalSince1970: 1_700_000_000))
        project.stems = [Stem(kind: .bass, file: "stems/bass.wav")]
        project.sections = sections
        let folder = root.appendingPathComponent("Banda - Tema", isDirectory: true)
        let layout = ProjectLayout(folder: folder)
        try layout.createSkeleton()
        try StudyTests.writeSine(layout.stemURL(.bass), frequency: 110)
        try ProjectFile.save(project, to: folder)
        let events = AudioTests.Events()
        let services = JobServices(importer: EditsImporter(), separator: EditsSeparator(), levelMeter: nil,
                                   analyzer: nil, guitarSplitter: nil)
        let options = LaunchOptions(projectsFolder: root, supportDir: support, audio: .simulated)
        let bridge = try Bridge(options: options, mediaBase: "https://tf.media/", reveal: nil, services: services)
        bridge.send = { events.add($0) }
        let svc = RecordService(options: options, studyService: bridge.studyService, emit: { events.add($0) })
        svc.cameras = cameras ?? .simulated()
        let router = Router()
        svc.register(on: router)
        bridge.studyService.onClosing = { [weak svc] in await svc?.close(resume: false) }
        let rig = Rig(bridge: bridge, svc: svc, router: router, events: events, folder: folder, support: support)
        if guitar { _ = await call(bridge.router, "audio.setSettings", "{\"inputDeviceUID\":\"sim-in\",\"guitarIn\":[1]}") }
        let open = await call(bridge.router, "study.open", "{\"projectId\":\"\(project.id.uuidString)\"}")
        XCTAssertNotNil(open["result"], "\(open)")
        return rig
    }

    func call(_ router: Router, _ method: String, _ params: String = "{}") async -> [String: Any] {
        let out = await router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        return (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] ?? [:]
    }

    func snap(_ r: Rig, _ method: String, _ params: String = "{}") async throws -> RecordSnapshot {
        let out = await call(r.router, method, params)
        let result = try XCTUnwrap(out["result"], "\(out)")
        return try Router.makeDecoder().decode(RecordSnapshot.self, from: JSONSerialization.data(withJSONObject: result))
    }

    func errorCode(_ r: Rig, _ method: String, _ params: String = "{}") async -> String? {
        ((await call(r.router, method, params))["error"] as? [String: Any])?["code"] as? String
    }

    /// Espera (hasta `timeout` s) a que `cond` sea cierta sobre `record.state`.
    @discardableResult
    func until(_ r: Rig, timeout: Double = 8, _ cond: (RecordSnapshot) -> Bool) async throws -> RecordSnapshot {
        let end = Date().addingTimeInterval(timeout)
        var s = try await snap(r, "record.state")
        while !cond(s), Date() < end {
            try await Task.sleep(nanoseconds: 25_000_000)
            s = try await snap(r, "record.state")
        }
        XCTAssertTrue(cond(s), "tiempo agotado: fase \(s.phase), cámara \(s.camera.state), mensajes \(s.messages)")
        return s
    }

    func sleep(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }

    /// Abre Grabar sin cuenta atrás y espera a la cámara (si la hay).
    func openRecord(_ r: Rig, camera: String? = "simulated") async throws -> RecordSnapshot {
        _ = try await snap(r, "record.open")
        _ = try await snap(r, "record.setCountIn", "{\"on\":false}")
        if let camera { return try await until(r) { $0.camera.state == camera } }
        return try await snap(r, "record.state")
    }

    // MARK: Abrir y estado

    func testOpenGivesFullSnapshot() async throws {
        let sec = Section(name: "Estrofa", start: 0.5, end: 2.0)
        let r = try await makeRig(sections: [sec])
        let s = try await openRecord(r)
        XCTAssertEqual(s.phase, "idle")
        XCTAssertEqual(s.parts.map(\.name), ["Guitarra"])
        XCTAssertEqual(s.parts.first?.status, "pending")
        XCTAssertEqual(s.activePartId, s.parts.first?.id)
        XCTAssertNil(s.blockReason, "con guitarra asignada y el reproductor alojado se puede grabar")
        XCTAssertTrue(s.audio.hosting)
        XCTAssertEqual(s.sections.map(\.name), ["Estrofa"])
        XCTAssertEqual(s.beatsPerBar, 4)
        XCTAssertEqual(s.bpm, 120, accuracy: 1e-9)
        XCTAssertEqual(s.camera.name, "Cámara simulada")
        XCTAssertEqual(s.camera.label, "640×360 · 30 fps", "\(s.camera.label ?? "-")")
        XCTAssertEqual(s.mix.channels.map(\.id), ["bass"])
        XCTAssertEqual(s.mix.outputName.isEmpty, false)
        XCTAssertEqual(s.nextTakeNumber, 1)
        _ = await call(r.router, "record.close")
    }

    /// «Ir al montaje» (record/store.js `closeRecord({keepStudy})`): `record.close` deja el tema de Backing abierto y
    /// `montage.open` funciona a continuación; Grabar se puede volver a abrir.
    func testGoToMontageAfterRecordClose() async throws {
        let r = try await makeRig()
        _ = try await openRecord(r, camera: nil)
        _ = await call(r.router, "record.close")
        let list = (await call(r.bridge.router, "library.list"))["result"] as? [String: Any]
        let id = try XCTUnwrap(((list?["projects"] as? [[String: Any]])?.first)?["id"] as? String)
        let m = await call(r.bridge.router, "montage.open", "{\"projectId\":\"\(id)\"}")
        XCTAssertEqual((m["result"] as? [String: Any])?["projectId"] as? String, id, "\(m)")
        _ = await call(r.bridge.router, "montage.close")
        let again = await errorCode(r, "record.state")
        XCTAssertEqual(again, "not-open", "tras record.close hay que volver a record.open")
    }

    func testBlockedWithoutGuitar() async throws {
        let r = try await makeRig(guitar: false)
        let s = try await openRecord(r, camera: nil)
        XCTAssertNotNil(s.blockReason, "sin guitarra asignada no se puede grabar")
        let code = await errorCode(r, "record.start")
        XCTAssertEqual(code, "record-blocked")
        _ = await call(r.router, "record.close")
    }

    func testRecordMethodsNeedOpenScreenAndStudy() async throws {
        let r = try await makeRig()
        let code = await errorCode(r, "record.state")
        XCTAssertEqual(code, "not-open")
        _ = await call(r.bridge.router, "study.close")
        let code2 = await errorCode(r, "record.open")
        XCTAssertEqual(code2, "not-open", "sin tema abierto en Backing")
    }

    func testBridgeRegistersRecordAndStudyCloseClosesIt() async throws {
        let r = try await makeRig()
        let open = await call(r.bridge.router, "record.open")
        XCTAssertNotNil(open["result"], "\(open)")
        let st = await call(r.bridge.router, "record.state")
        XCTAssertNotNil(st["result"], "\(st)")
        _ = await call(r.bridge.router, "study.close")
        let after = await call(r.bridge.router, "record.state")
        XCTAssertEqual((after["error"] as? [String: Any])?["code"] as? String, "not-open")
    }

    // MARK: Toma con vídeo y desfase

    func testTakeWithVideoIsSavedWithOffset() async throws {
        let r = try await makeRig()
        _ = try await openRecord(r)
        let start = Date()
        var s = try await snap(r, "record.start")
        XCTAssertEqual(s.phase, "recording")
        try await Task.sleep(nanoseconds: 1_500_000_000)
        s = try await snap(r, "record.stop")
        s = try await until(r, timeout: 10) { $0.phase == "adjusting" }
        let o = try XCTUnwrap(s.offset)
        XCTAssertTrue(o.isNew)
        XCTAssertTrue(o.videoPath.hasPrefix("Banda - Tema/takes/"), o.videoPath)
        XCTAssertTrue(o.videoPath.hasSuffix("/video.mov"))
        XCTAssertEqual(o.frameMs, 1000.0 / 30, accuracy: 1e-6)
        XCTAssertEqual(o.valueMs, 0)

        // Ajustes del desfase: ±1 fotograma, ±1 ms, valor, recorte a ±500 ms.
        s = try await snap(r, "record.setOffset", "{\"frames\":1}")
        XCTAssertEqual(s.offset?.valueMs ?? 0, 1000.0 / 30, accuracy: 1e-6)
        s = try await snap(r, "record.setOffset", "{\"deltaMs\":-1}")
        XCTAssertEqual(s.offset?.valueMs ?? 0, 1000.0 / 30 - 1, accuracy: 1e-6)
        s = try await snap(r, "record.setOffset", "{\"valueMs\":9999}")
        XCTAssertEqual(s.offset?.valueMs, 500)
        s = try await snap(r, "record.setOffset", "{\"valueMs\":-9999}")
        XCTAssertEqual(s.offset?.valueMs, -500)
        s = try await snap(r, "record.setOffset", "{\"valueMs\":40}")
        s = try await snap(r, "record.finishOffset", "{\"save\":true,\"makeDefault\":true}")
        XCTAssertEqual(s.phase, "idle")
        XCTAssertNil(s.offset)
        let take = try XCTUnwrap(s.parts.first?.takes.first)
        XCTAssertTrue(take.hasVideo)
        XCTAssertEqual(take.videoOffsetMs ?? 0, 40, accuracy: 1e-9)
        XCTAssertEqual(take.videoPath, "Banda - Tema/takes/\(take.id)/video.mov")
        XCTAssertEqual(take.number, 1)
        XCTAssertTrue(take.best)
        XCTAssertEqual(take.videoFormat?.width, 640)
        XCTAssertEqual(s.parts.first?.status, "done")
        XCTAssertEqual(s.selectedTakeId, take.id)
        XCTAssertEqual(try XCTUnwrap(take.durationSeconds), 1.5, accuracy: 0.6)

        // Medido en simulado: sincronía de los fotogramas y marcas.
        let report = try XCTUnwrap(r.svc.controller?.lastSyncReport)
        XCTAssertGreaterThan(report.framesWritten, 20, "1,5 s a 30 fps")
        XCTAssertEqual(report.framesAfterCut, 0)
        print("RECORD-SYNC elapsed=\(Date().timeIntervalSince(start)) report=\(report)")

        _ = await call(r.router, "record.close")
        let saved = try r.project
        let t = try XCTUnwrap(saved.takes.first)
        XCTAssertEqual(t.videoFile, "takes/\(t.id.uuidString)/video.mov")
        XCTAssertEqual(try XCTUnwrap(t.videoOffset), 0.040, accuracy: 1e-9)
        XCTAssertEqual(t.partID, saved.recording?.parts.first?.id)
        XCTAssertEqual(saved.recording?.parts.first?.takeIDs, [t.id])
        XCTAssertEqual(saved.recording?.parts.first?.bestTakeID, t.id)
        XCTAssertNotNil(t.songStart)
        XCTAssertEqual(t.videoFormat?.cameraUID, "sim-camera")
        let attrs = try FileManager.default.attributesOfItem(atPath: r.layout.videoURL(takeId: t.id).path)
        XCTAssertGreaterThan((attrs[.size] as? Int) ?? 0, 1000, "video.mov escrito")
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.layout.processedURL(takeId: t.id).path))
        // «Por defecto de esta cámara» quedó en el perfil.
        let profile = try ProfileStore(url: r.support.appendingPathComponent("profile.json")).load()
        XCTAssertEqual(try XCTUnwrap(profile.video?.defaultOffset(for: "sim-camera")), 0.040, accuracy: 1e-9)
    }

    func testAdjustOffsetOfSavedTakeAndRotation() async throws {
        let r = try await makeRig()
        _ = try await openRecord(r)
        _ = try await snap(r, "record.start")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        _ = try await snap(r, "record.stop")
        _ = try await until(r, timeout: 10) { $0.phase == "adjusting" }
        var s = try await snap(r, "record.finishOffset", "{\"save\":true,\"makeDefault\":false}")
        let id = try XCTUnwrap(s.parts.first?.takes.first?.id)
        s = try await snap(r, "record.adjustOffset", "{\"takeId\":\"\(id)\"}")
        XCTAssertEqual(s.phase, "idle")
        XCTAssertEqual(s.offset?.isNew, false)
        _ = try await snap(r, "record.setOffset", "{\"valueMs\":-25}")
        s = try await snap(r, "record.finishOffset", "{\"save\":true,\"makeDefault\":false}")
        XCTAssertEqual(try XCTUnwrap(s.parts.first?.takes.first?.videoOffsetMs), -25, accuracy: 1e-9)
        s = try await snap(r, "record.rotate")
        XCTAssertEqual(s.camera.rotation, 90)
        s = try await snap(r, "record.rotate")
        XCTAssertEqual(s.camera.rotation, 180)
        _ = await call(r.router, "record.close")
        XCTAssertEqual(try r.project.takes.first?.videoOffset ?? 0, -0.025, accuracy: 1e-9)
    }

    func testDiscardingTheNewTakeRemovesIt() async throws {
        let r = try await makeRig()
        _ = try await openRecord(r)
        _ = try await snap(r, "record.start")
        try await Task.sleep(nanoseconds: 800_000_000)
        _ = try await snap(r, "record.stop")
        let s = try await until(r, timeout: 10) { $0.phase == "adjusting" }
        let path = try XCTUnwrap(s.offset?.videoPath)
        let done = try await snap(r, "record.finishOffset", "{\"save\":false}")
        XCTAssertEqual(done.phase, "idle")
        XCTAssertEqual(done.parts.first?.takes.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: r.folder.deletingLastPathComponent().appendingPathComponent(path).path))
        _ = await call(r.router, "record.close")
        XCTAssertEqual(try r.project.takes.count, 0)
    }

    // MARK: Cuenta, parada automática, cancelar

    func testCountInRunsOneBarThenRecords() async throws {
        let r = try await makeRig(cameras: .simulated(provider: SimulatedCameraProvider(cameras: [])))
        _ = try await snap(r, "record.open")
        var s = try await snap(r, "record.start")
        XCTAssertEqual(s.phase, "counting")
        var beats: [Int] = []
        let end = Date().addingTimeInterval(5)
        while Date() < end {
            s = try await snap(r, "record.state")
            if let b = s.countBeat, beats.last != b { beats.append(b) }
            if s.phase == "recording" { break }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        XCTAssertEqual(s.phase, "recording")
        XCTAssertEqual(beats, [1, 2, 3, 4], "una cuenta de 4 pulsos (120 BPM, 4/4 por defecto)")
        // W2-E2, paridad con el Mac: cancelar mientras graba no hace nada (el Mac solo tiene «Parar», que guarda).
        s = try await snap(r, "record.cancel")
        XCTAssertEqual(s.phase, "recording")
        await sleep(0.3)
        s = try await snap(r, "record.state")
        XCTAssertEqual(s.phase, "recording", "sigue grabando tras record.cancel")
        _ = try await snap(r, "record.stop")
        s = try await until(r) { $0.phase == "idle" }
        XCTAssertEqual(s.parts.first?.takes.count, 1, "Parar guarda la toma")
        XCTAssertNotEqual(s.audio.recording, true)
        _ = await call(r.router, "record.close")
        XCTAssertEqual(try r.project.takes.count, 1)
    }

    /// W2-E2, paridad con el Mac: si el reproductor de la cuenta no abre, la toma se aborta con el literal del Mac.
    func testCountInPlayerFailureAbortsTake() async throws {
        struct NoOutput: Error, CustomStringConvertible { var description: String { "salida ocupada" } }
        let r = try await makeRig(cameras: .simulated(provider: SimulatedCameraProvider(cameras: [])))
        _ = try await snap(r, "record.open")
        let c = try XCTUnwrap(r.svc.controller)
        c.openCountInAudio = { _, _, _ in throw NoOutput() }
        _ = try await snap(r, "record.start")
        let s = try await until(r) { $0.phase == "idle" }
        XCTAssertEqual(s.messages, ["No se pudo grabar la toma (salida ocupada)."])
        XCTAssertEqual(s.parts.first?.takes.count, 0)
        XCTAssertNotEqual(s.audio.recording, true)
        let takes = r.layout.folder.appendingPathComponent("takes")
        let left = (try? FileManager.default.contentsOfDirectory(atPath: takes.path)) ?? []
        XCTAssertTrue(left.isEmpty, "sin carpeta de toma: \(left)")
        _ = await call(r.router, "record.close")
        XCTAssertEqual(try r.project.takes.count, 0)
    }

    func testCancelDuringCountIn() async throws {
        let r = try await makeRig(cameras: .simulated(provider: SimulatedCameraProvider(cameras: [])))
        _ = try await snap(r, "record.open")
        _ = try await snap(r, "record.start")
        try await Task.sleep(nanoseconds: 300_000_000)
        _ = try await snap(r, "record.cancel")
        let s = try await until(r) { $0.phase == "idle" }
        XCTAssertEqual(s.parts.first?.takes.count, 0)
        XCTAssertTrue(s.messages.isEmpty, "cancelar la cuenta no es un error: \(s.messages)")
        _ = await call(r.router, "record.close")
    }

    func testAutoStopAtSectionEndWithoutCamera() async throws {
        let sec = Section(name: "Estrofa", start: 0.5, end: 2.0)
        let r = try await makeRig(sections: [sec], cameras: .simulated(provider: SimulatedCameraProvider(cameras: [])))
        _ = try await openRecord(r, camera: "none")
        var s = try await snap(r, "record.setPreRoll", "{\"bars\":0}")
        s = try await snap(r, "record.setStartSection", "{\"sectionId\":\"\(sec.id.uuidString)\"}")
        XCTAssertEqual(try XCTUnwrap(s.plannedStop), 2.0, accuracy: 1e-9, "final de la sección + 0 compases")
        s = try await snap(r, "record.setPreRoll", "{\"bars\":1}")
        XCTAssertEqual(try XCTUnwrap(s.plannedStop), 4.0, accuracy: 1e-9, "final + 1 compás (2 s a 120 BPM)")
        s = try await snap(r, "record.setPreRoll", "{\"bars\":0}")
        XCTAssertEqual(s.camera.message, "No hay ninguna cámara conectada. Se grabará solo el audio.")
        s = try await snap(r, "record.start")
        XCTAssertEqual(s.phase, "recording")
        let t0 = Date()
        s = try await until(r, timeout: 8) { $0.phase == "idle" }   // sin pulsar «Parar»
        let took = Date().timeIntervalSince(t0)
        XCTAssertLessThan(took, 3.5, "paró sola al llegar al final de la sección")
        let take = try XCTUnwrap(s.parts.first?.takes.first)
        XCTAssertFalse(take.hasVideo, "sin cámara: solo audio")
        XCTAssertNil(take.videoPath)
        XCTAssertEqual(try XCTUnwrap(take.songStart), 0.5, accuracy: 0.3)
        XCTAssertEqual(try XCTUnwrap(take.durationSeconds), 1.5, accuracy: 0.5, "de 0,5 s a 2,0 s")
        print("RECORD-AUTOSTOP took=\(took) songStart=\(take.songStart ?? -1) duration=\(take.durationSeconds ?? -1)")
        _ = await call(r.router, "record.close")
        let t = try XCTUnwrap(try r.project.takes.first)
        XCTAssertNil(t.videoFile)
        XCTAssertEqual(try r.project.recording?.startSectionID, sec.id)
        XCTAssertEqual(try r.project.recording?.preRollBars, 0)
    }

    // MARK: Punch-in

    /// Relevo 10 caso 4: durante el punch el reproductor tiene abierta la toma (`take-self`). En NTFS reescribir
    /// `processed.wav` con un lector abierto falla (`MoveFileEx` error 5): al aplanar no debe quedar ningún descriptor.
    func testPunchFlattensWithNoReaderOpenOnProcessed() async throws {
        final class Seen: @unchecked Sendable {
            private let lock = NSLock()
            private var v: [[String]?] = []
            func add(_ x: [String]?) { lock.withLock { v.append(x) } }
            var all: [[String]?] { lock.withLock { v } }
        }
        let sec = Section(name: "Estrofa", start: 0, end: 2.0)
        let r = try await makeRig(sections: [sec], cameras: .simulated(provider: SimulatedCameraProvider(cameras: [])))
        _ = try await openRecord(r, camera: "none")
        _ = try await snap(r, "record.setPreRoll", "{\"bars\":0}")
        _ = try await snap(r, "record.setStartSection", "{\"sectionId\":\"\(sec.id.uuidString)\"}")
        _ = try await snap(r, "record.start")
        var s = try await until(r, timeout: 8) { $0.phase == "idle" && ($0.parts.first?.takes.count ?? 0) == 1 }
        let takeID = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(s.parts.first?.takes.first).id))
        let processed = r.layout.processedURL(takeId: takeID)
        let c = try XCTUnwrap(r.svc.controller)
        let seen = Seen(), real = c.flattenPunch
        c.flattenPunch = { base, start, punches, to, rate in
            seen.add(OpenFiles.stillOpen([base, to]))
            try real(base, start, punches, to, rate)
        }
        s = try await snap(r, "record.setPunch", "{\"enabled\":true}")
        s = try await snap(r, "record.setPunch", "{\"in\":0.5,\"out\":1.2,\"free\":true}")
        s = try await snap(r, "record.start")
        _ = try await until(r, timeout: 4) { $0.phase != "idle" }
        let openWhilePunching = OpenFiles.stillOpen([processed])
        s = try await until(r, timeout: 8) { $0.phase == "idle" }
        let why = "messages=\(s.messages) notices=\(s.notices)"
        _ = await call(r.router, "record.close")
        XCTAssertEqual(try r.project.takes.first?.punches?.count, 1, why)
        if let open = openWhilePunching {
            XCTAssertEqual(open.count, 1, "el reproductor tiene abierta la toma durante el punch (si no, el test no prueba nada)")
        }
        XCTAssertEqual(seen.all.count, 1, "se aplana una vez")
        if let open = seen.all.first ?? nil { XCTAssertEqual(open, [], "ningún descriptor sobre processed.wav al aplanar") }
        print("A1 caso 4: abiertas durante el punch \(openWhilePunching.map { "\($0.count)" } ?? "n/d"), al aplanar "
              + "\((seen.all.first ?? nil).map { "\($0.count)" } ?? "n/d")")
    }

    func testPunchInReplacesSpanAndKeepsBase() async throws {
        let sec = Section(name: "Estrofa", start: 0, end: 2.0)
        let r = try await makeRig(sections: [sec], cameras: .simulated(provider: SimulatedCameraProvider(cameras: [])))
        _ = try await openRecord(r, camera: "none")
        _ = try await snap(r, "record.setPreRoll", "{\"bars\":0}")
        _ = try await snap(r, "record.setStartSection", "{\"sectionId\":\"\(sec.id.uuidString)\"}")
        _ = try await snap(r, "record.start")
        var s = try await until(r, timeout: 8) { $0.phase == "idle" && ($0.parts.first?.takes.count ?? 0) == 1 }
        let take = try XCTUnwrap(s.parts.first?.takes.first)
        XCTAssertEqual(s.selectedTakeId, take.id)

        // Sin marcas no se puede; con ellas sí.
        s = try await snap(r, "record.setPunch", "{\"enabled\":true}")
        XCTAssertEqual(s.blockReason, "Marca la entrada y la salida del punch-in en la línea de tiempo.")
        s = try await snap(r, "record.setPunch", "{\"in\":1.3,\"free\":true}")
        XCTAssertEqual(s.punch.in, 1.3)
        s = try await snap(r, "record.setPunch", "{\"in\":1.3}")   // con imán: compás de 2 s
        XCTAssertEqual(try XCTUnwrap(s.punch.in), 2.0, accuracy: 1e-9)
        s = try await snap(r, "record.setPunch", "{\"in\":0.5,\"out\":1.2,\"free\":true}")
        XCTAssertEqual(s.punch.in, 0.5)
        XCTAssertEqual(s.punch.out, 1.2)
        XCTAssertTrue(s.punch.ready)
        XCTAssertNil(s.blockReason)
        XCTAssertNil(s.plannedStop, "el punch tiene su propia parada: salida + 0,5 s")
        s = try await snap(r, "record.setPunch", "{\"out\":0.2,\"free\":true}")   // salida antes de la entrada: se cruzan
        XCTAssertEqual(s.punch.in, 0.2)
        XCTAssertEqual(s.punch.out, 0.5)
        s = try await snap(r, "record.setPunch", "{\"in\":0.5,\"out\":1.2,\"free\":true}")
        s = try await snap(r, "record.start")
        let t0 = Date()
        s = try await until(r, timeout: 8) { $0.phase == "idle" }
        XCTAssertLessThan(Date().timeIntervalSince(t0), 3, "paró sola en salida + 0,5 s")
        // Si el punch no queda, que el fallo diga por qué (el error de `commitPunch` acaba en `messages`).
        let takeDir = r.layout.takeDirectory(takeId: try XCTUnwrap(UUID(uuidString: take.id)))
        let files = (FileManager.default.enumerator(atPath: takeDir.path)?.allObjects as? [String] ?? []).sorted()
        let why = "messages=\(s.messages) notices=\(s.notices) blockReason=\(s.blockReason ?? "-") ficheros=\(files)"
        _ = await call(r.router, "record.close")

        let saved = try XCTUnwrap(try r.project.takes.first)
        XCTAssertEqual(saved.punches?.count, 1, why)
        XCTAssertEqual(saved.punches?.first?.start, 0.5)
        XCTAssertEqual(saved.punches?.first?.end, 1.2)
        XCTAssertNotNil(saved.baseProcessedFile, "la original se conserva en base/")
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.layout.url(relative: try XCTUnwrap(saved.baseProcessedFile)).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.layout.url(relative: try XCTUnwrap(saved.punches?.first?.processedFile)).path))
        XCTAssertEqual(try r.project.recording?.parts.first?.takeIDs.count, 1, "el punch no crea toma nueva")
    }

    // MARK: Partes, mezcla «Tú · parte», borrar, puntuar

    func testPartsMixRestoredAndMarkBestAndDelete() async throws {
        let sec = Section(name: "Estrofa", start: 0, end: 1.0)
        let r = try await makeRig(sections: [sec], cameras: .simulated(provider: SimulatedCameraProvider(cameras: [])))
        _ = try await openRecord(r, camera: "none")
        _ = try await snap(r, "record.setPreRoll", "{\"bars\":0}")
        _ = try await snap(r, "record.setStartSection", "{\"sectionId\":\"\(sec.id.uuidString)\"}")
        var ids: [String] = []
        for _ in 0..<2 {
            _ = try await snap(r, "record.start")
            let n = ids.count + 1
            let s = try await until(r, timeout: 8) { $0.phase == "idle" && ($0.parts.first?.takes.count ?? 0) == n }
            ids = s.parts.first?.takes.map(\.id) ?? []
        }
        var s = try await snap(r, "record.state")
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(s.parts.first?.bestTakeId, ids[1], "la última pasa a ser la mejor")
        s = try await snap(r, "record.markBest", "{\"takeId\":\"\(ids[0])\"}")
        XCTAssertEqual(s.parts.first?.bestTakeId, ids[0])
        XCTAssertEqual(s.parts.first?.takes.map(\.best), [true, false])
        let firstPart = try XCTUnwrap(s.parts.first?.id)

        // Una parte nueva oye la mejor toma de la primera como «Tú · Guitarra».
        s = try await snap(r, "record.addPart", "{\"name\":\"Solo\",\"replaces\":\"lead\"}")
        XCTAssertEqual(s.parts.map(\.name), ["Guitarra", "Solo"])
        XCTAssertEqual(s.parts.last?.isLead, true)
        XCTAssertEqual(s.activePartId, s.parts.last?.id)
        XCTAssertEqual(s.mix.takeChannels.map(\.name), ["Tú · Guitarra"])
        XCTAssertEqual(s.mix.takeChannels.first?.id, "take-\(firstPart)")
        s = try await snap(r, "record.setMix", "{\"channel\":\"take-\(firstPart)\",\"gainDB\":-6,\"mute\":true}")
        XCTAssertEqual(s.mix.takeChannels.first?.gainDB, -6)
        XCTAssertEqual(s.mix.takeChannels.first?.muted, true)
        s = try await snap(r, "record.setMix", "{\"channel\":\"bass\",\"gainDB\":-3,\"solo\":true}")
        XCTAssertEqual(s.mix.channels.first?.solo, true)
        XCTAssertTrue(s.mix.anySolo)
        let bad = await errorCode(r, "record.setMix", "{\"channel\":\"nope\",\"gainDB\":0}")
        XCTAssertEqual(bad, "bad-params")
        s = try await snap(r, "record.setMaster", "{\"gainDB\":-4}")
        XCTAssertEqual(s.mix.masterGainDB, -4)

        // Reabrir: el fader «Tú · parte» vuelve como se dejó.
        _ = await call(r.router, "record.close")
        s = try await snap(r, "record.open")
        XCTAssertEqual(s.parts.count, 2)
        s = try await snap(r, "record.selectPart", "{\"partId\":\"\(s.parts[1].id)\"}")
        XCTAssertEqual(s.mix.takeChannels.first?.gainDB, -6)
        XCTAssertEqual(s.mix.takeChannels.first?.muted, true)
        XCTAssertEqual(s.mix.channels.first?.gainDB, -3)

        // Borrar una toma: carpeta y rastro; la mejor pasa a la que quede.
        s = try await snap(r, "record.selectPart", "{\"partId\":\"\(firstPart)\"}")
        s = try await snap(r, "record.deleteTake", "{\"takeId\":\"\(ids[0])\"}")
        XCTAssertEqual(s.parts.first?.takes.map(\.id), [ids[1]])
        XCTAssertEqual(s.parts.first?.bestTakeId, ids[1])
        XCTAssertFalse(FileManager.default.fileExists(atPath: r.layout.takeDirectory(takeId: UUID(uuidString: ids[0])!).path))
        let missing = await errorCode(r, "record.deleteTake", "{\"takeId\":\"\(ids[0])\"}")
        XCTAssertEqual(missing, "not-found")
        _ = await call(r.router, "record.close")
        let saved = try r.project
        XCTAssertEqual(saved.takes.map(\.id.uuidString), [ids[1]])
        XCTAssertEqual(saved.recording?.parts.first?.takeIDs.map(\.uuidString), [ids[1]])
    }

    // MARK: Cámara

    func testCameraAbsentThenAppearsAndDisconnects() async throws {
        let provider = SimulatedCameraProvider(cameras: [])
        let r = try await makeRig(cameras: .simulated(provider: provider))
        var s = try await openRecord(r, camera: "none")
        XCTAssertEqual(s.camera.message, "No hay ninguna cámara conectada. Se grabará solo el audio.")
        XCTAssertTrue(s.camera.cameras.isEmpty)
        // Se conecta: el sondeo (2 s) la reacopla.
        provider.setCameras([.simulated])
        let controller = try XCTUnwrap(r.svc.controller)
        controller.pollCamera()
        s = try await until(r) { $0.camera.state == "simulated" }
        XCTAssertEqual(s.camera.cameras.map(\.id), ["sim-camera"])
        // Se desconecta.
        provider.setCameras([])
        controller.pollCamera()
        s = try await until(r) { $0.camera.state == "none" }
        XCTAssertEqual(s.camera.message, "Se desconectó la cámara: se grabará solo el audio. Se grabará solo el audio.")
        _ = await call(r.router, "record.close")
    }

    func testChosenCameraMissingMessage() async throws {
        let r = try await makeRig()
        _ = try await call(r.bridge.router, "audio.state")
        let store = ProfileStore(url: r.support.appendingPathComponent("profile.json"))
        var p = try store.load()
        p.video?.cameraUID = "otra"
        try store.save(p)
        _ = r.svc   // el controlador de audio relee el perfil al abrir Grabar
        await r.bridge.studyService.audioService?.controller().reloadProfile()
        let s = try await openRecord(r, camera: "none")
        XCTAssertEqual(s.camera.message, "La cámara elegida en Ajustes no está conectada. Se grabará solo el audio.")
        _ = await call(r.router, "record.close")
    }

    func testPreviewFrameHookGetsEveryFrameWhileOpen() async throws {
        let r = try await makeRig()
        _ = try await snap(r, "record.open")
        let counter = Counter()
        let controller = try XCTUnwrap(r.svc.controller)
        controller.onPreviewFrame = { _ in counter.bump() }
        _ = try await until(r) { $0.camera.state == "simulated" }
        await sleep(1.0)
        XCTAssertGreaterThan(counter.value, 15, "unos 30 fotogramas por segundo sin grabar")
        let before = counter.value
        _ = await call(r.router, "record.close")
        await sleep(0.3)
        let after = counter.value
        await sleep(0.3)
        XCTAssertEqual(counter.value, after, "cerrada la pantalla no llegan más")
        XCTAssertGreaterThan(after, before - 1)
    }

    /// W2-E2, punto fino: el relevo `frames.camera` no frena al escritor de la toma. Codificador que tarda 200 ms por
    /// fotograma (≈13 veces el periodo de una cámara a 15 fps): el gancho de la captura sigue volviendo en < 1 ms, el
    /// escritor recibe todos los fotogramas y ninguno llega tarde.
    nonisolated static let maxHookMs = 1.0
    nonisolated static let slowEncodeSeconds = 0.2

    final class Durations: @unchecked Sendable {
        private let lock = NSLock()
        private var v: [Double] = []
        func add(_ x: Double) { lock.withLock { v.append(x) } }
        var all: [Double] { lock.withLock { v } }
    }

    func testCameraRelayDoesNotBlockTakeWriter() async throws {
        let r = try await makeRig()
        let encodes = Counter()
        let events = Counter()
        r.svc.makeCameraRelay = {
            FrameRelay(channel: "camera-test", maxFPS: FrameRelay.defaultMaxFPS, maxWidth: 640,
                       encode: { _ in encodes.bump(); Thread.sleep(forTimeInterval: Self.slowEncodeSeconds)
                                 return JPEGFrame(data: Data([0xFF, 0xD8, 0xFF, 0xD9]), width: 64, height: 36) },
                       emit: { _, _ in events.bump() })
        }
        _ = try await openRecord(r)
        let c = try XCTUnwrap(r.svc.controller)
        let relay = try XCTUnwrap(r.svc.cameraRelay, "Grabar abierta -> relevo de cámara")
        let hook = try XCTUnwrap(c.onPreviewFrame, "el servicio enchufa la captura al relevo")
        let durations = Durations()
        c.onPreviewFrame = { f in
            let t0 = DispatchTime.now().uptimeNanoseconds
            hook(f)
            durations.add(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        }
        _ = try await snap(r, "record.start")
        try await Task.sleep(nanoseconds: 1_500_000_000)
        _ = try await snap(r, "record.stop")
        _ = try await until(r, timeout: 10) { $0.phase == "adjusting" }
        let report = try XCTUnwrap(c.lastSyncReport)
        let d = durations.all.sorted()
        let stats = relay.stats
        let worst = d.last ?? 0, p95 = d.isEmpty ? 0 : d[Int(Double(d.count - 1) * 0.95)]
        print("CAMERA-RELAY hook n=\(d.count) p95=\(p95) ms max=\(worst) ms; relay sent=\(stats.sent) busy=\(stats.droppedBusy) "
              + "rate=\(stats.droppedRate); writer received=\(report.framesReceived) written=\(report.framesWritten) "
              + "rejected=\(report.framesRejected) lag=\(String(describing: report.arrivalLag))")
        XCTAssertGreaterThan(d.count, 40, "≈30 fps durante ~2 s")
        XCTAssertLessThan(worst, Self.maxHookMs, "el gancho de la captura no espera al codificador")
        XCTAssertGreaterThan(stats.droppedBusy, 10, "el codificador estuvo ocupado de verdad")
        XCTAssertLessThanOrEqual(encodes.value, 16, "≤ 1 cada 200 ms")
        XCTAssertGreaterThan(report.framesWritten, 35, "1,5 s a 30 fps: el escritor no pierde fotogramas")
        XCTAssertEqual(report.framesRejected, 0)
        if let lag = report.arrivalLag { XCTAssertLessThan(lag.max, 0.05, "ningún fotograma llega tarde al escritor") }
        _ = await call(r.router, "record.close")
        XCTAssertNil(r.svc.cameraRelay)
        XCTAssertFalse(relay.stats.running, "cerrar Grabar para el relevo")
    }

    func testBridgeWiresCameraRelay() async throws {
        let r = try await makeRig()
        // El servicio del puente (no el del equipo de pruebas) trae los relevos cableados.
        let open = await call(r.bridge.router, "record.open")
        XCTAssertNotNil(open["result"], "\(open)")
        let end = Date().addingTimeInterval(5)
        var stats: [String: Any] = [:]
        while Date() < end {
            stats = (await call(r.bridge.router, "frames.stats", "{\"channel\":\"camera\"}"))["result"] as? [String: Any] ?? [:]
            if (stats["sent"] as? Int ?? 0) >= 3 { break }
            await sleep(0.05)
        }
        XCTAssertGreaterThanOrEqual(stats["sent"] as? Int ?? 0, 3, "\(stats)")
        XCTAssertEqual(stats["running"] as? Bool, true)
        XCTAssertFalse(r.events.all("frames.camera").isEmpty, "salen eventos frames.camera")
        _ = await call(r.bridge.router, "record.close")
        stats = (await call(r.bridge.router, "frames.stats", "{\"channel\":\"camera\"}"))["result"] as? [String: Any] ?? [:]
        XCTAssertEqual(stats["running"] as? Bool, false, "cerrar Grabar para el relevo")
    }

    /// W2-E2: `video.preview.start/stop` (Ajustes) por `frames.camera` sin grabar; con Grabar abierta comparte su cámara.
    func testSettingsCameraPreviewStartStopAndSharesRecord() async throws {
        let r = try await makeRig()
        func stats() async -> [String: Any] {
            (await call(r.bridge.router, "frames.stats", "{\"channel\":\"camera\"}"))["result"] as? [String: Any] ?? [:]
        }
        let started = (await call(r.bridge.router, "video.preview.start"))["result"] as? [String: Any] ?? [:]
        XCTAssertEqual(started["state"] as? String, "simulated", "\(started)")
        XCTAssertEqual(started["cameraName"] as? String, "Cámara simulada")
        XCTAssertEqual(started["fromRecord"] as? Bool, false)
        XCTAssertNotNil(started["width"] as? Int)
        let end = Date().addingTimeInterval(5)
        var st = await stats()
        while Date() < end, st["sent"] as? Int ?? 0 < 3 { await sleep(0.05); st = await stats() }
        XCTAssertGreaterThanOrEqual(st["sent"] as? Int ?? 0, 3, "\(st)")
        let stopped = (await call(r.bridge.router, "video.preview.stop"))["result"] as? [String: Any] ?? [:]
        XCTAssertEqual(stopped["state"] as? String, "idle")
        st = await stats()
        XCTAssertEqual(st["running"] as? Bool, false)
        // Grabar abierta: no se abre otra captura.
        _ = await call(r.bridge.router, "video.preview.start")
        _ = await call(r.bridge.router, "record.open")
        let shared = (await call(r.bridge.router, "video.preview.start"))["result"] as? [String: Any] ?? [:]
        XCTAssertEqual(shared["fromRecord"] as? Bool, true, "\(shared)")
        _ = await call(r.bridge.router, "record.close")
        _ = await call(r.bridge.router, "video.preview.stop")
        // Cámara elegida desconectada: `noCamera` con el texto del subtítulo, sin caer a la del sistema ni abrir captura.
        _ = await call(r.bridge.router, "video.setSettings", #"{"cameraUID":"desconectada-1"}"#)
        let gone = (await call(r.bridge.router, "video.preview.start"))["result"] as? [String: Any] ?? [:]
        XCTAssertEqual(gone["state"] as? String, "noCamera", "\(gone)")
        XCTAssertEqual(gone["message"] as? String, "La cámara elegida está desconectada.")
        XCTAssertEqual(gone["cameraId"] as? String, "desconectada-1")
        st = await stats()
        XCTAssertEqual(st["running"] as? Bool, false, "sin captura con la cámara elegida desconectada")
    }

    // MARK: Eventos

    func testStateAndPositionEvents() async throws {
        let sec = Section(name: "Estrofa", start: 0, end: 1.2)
        let r = try await makeRig(sections: [sec], cameras: .simulated(provider: SimulatedCameraProvider(cameras: [])))
        _ = try await openRecord(r, camera: "none")
        _ = try await snap(r, "record.setPreRoll", "{\"bars\":0}")
        _ = try await snap(r, "record.setStartSection", "{\"sectionId\":\"\(sec.id.uuidString)\"}")
        let before = r.events.all("record.state").count
        _ = try await snap(r, "record.start")
        _ = try await until(r, timeout: 8) { $0.phase == "idle" && ($0.parts.first?.takes.count ?? 0) == 1 }
        await sleep(0.2)
        let states = r.events.all("record.state")
        XCTAssertGreaterThan(states.count, before, "hubo cambios de fase")
        let phases = states.compactMap { $0["phase"] as? String }
        XCTAssertTrue(phases.contains("recording"), "\(phases)")
        // Solo cambios: nunca dos seguidos iguales.
        var last: String?
        for s in states {
            let data = try JSONSerialization.data(withJSONObject: s.merging(["position": 0]) { _, b in b }, options: [.sortedKeys])
            let key = String(decoding: data, as: UTF8.self)
            XCTAssertNotEqual(key, last)
            last = key
        }
        let positions = r.events.all("record.position")
        XCTAssertGreaterThan(positions.count, 5)
        XCTAssertLessThanOrEqual(positions.count, 60, "<= 30 Hz durante ~1,5 s")
        XCTAssertTrue(positions.contains { ($0["playing"] as? Bool) == true })
        _ = await call(r.router, "record.close")
    }

    // MARK: StudySession: tomas

    func testStudySessionSavesTakesAndReportsFailure() async throws {
        let r = try await makeRig()
        let o = try XCTUnwrap(r.bridge.studyService.current)
        let rate = StudyTests.sampleRate
        let t = Take(processedFile: "takes/x/processed.wav", createdAt: Date(timeIntervalSince1970: 10), songStart: 0, sampleRate: rate)
        o.session.saveTakes([t])
        await o.session.awaitTakeSaves()
        XCTAssertNil(o.session.takeSaveError)
        XCTAssertEqual(o.session.playableTakes.map(\.id), [t.id])
        XCTAssertEqual(try r.project.takes.map(\.id), [t.id])
        // Un almacén que no guarda tomas lo dice.
        let s2 = StudySession(project: try r.project, folder: r.folder, store: FailingStudyStore())
        s2.saveTakes([Take()])
        XCTAssertNotNil(s2.takeSaveError)
        XCTAssertTrue(s2.takeSaveError?.hasPrefix("No se pudo guardar la toma en el proyecto") == true)
    }
}
