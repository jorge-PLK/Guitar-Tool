import AudioKit
import Foundation
import Store
import VideoKit
import XCTest
@testable import AppCore

// Fase 7f, ola 3 (parte 3.1): fixtures de `record.*` en `Contract/fixtures/record/` (y `takeview.*` en ContractFixtures+TakeView.swift).
// Convención de variantes: `<evento>.<variante>.event.json` (p. ej. `record.state.recording.event.json`). `record.state` es la
// instantánea real del Router con los campos de la variante cambiados (el estado vivo depende del reloj y del dispositivo);
// los métodos vuelcan `<método>.params.json` y `<método>.result.json` (o `.error.json`) con respuestas reales del Router
// sobre un tema determinista (audio y cámara simulados, UUID fijos, un vídeo de 640x360 girado 90 grados).

extension FixtureRig {
    /// Rig con audio simulado (el de `init(area:)` usa el audio por defecto). Mismos campos, otro `Bridge`.
    init(area: String, simulatedAudioProject world: RecordFixtureWorld) throws {
        self.init(area: area, dir: world.base, projects: world.root, bridge: world.bridge)
    }
}

extension FixtureRig {
    fileprivate init(area: String, dir: URL, projects: URL, bridge: Bridge) {
        self.area = area
        self.dir = dir
        self.projects = projects
        self.bridge = bridge
    }

    /// JSON con claves ordenadas: el orden de `JSONSerialization` no es estable y los UUID se numeran por aparición.
    static func sorted(_ any: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed, .withoutEscapingSlashes, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// Llama al Router real y vuelca params y result/error con el nombre `name` (por defecto el método).
    @discardableResult
    func dump(_ method: String, _ params: String = "{}", name: String? = nil, paramsOnly: Bool = false,
              file: StaticString = #filePath, line: UInt = #line) async throws -> [String: Any] {
        let n = name ?? method
        let p = try JSONSerialization.jsonObject(with: Data(params.utf8), options: [.fragmentsAllowed])
        try golden(n, .params, try Self.sorted(p), file: file, line: line)
        if paramsOnly { return [:] }
        let r = await bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
        if let e = o["error"] { try golden(n, .error, try Self.sorted(e), file: file, line: line) }
        else { try golden(n, .result, try Self.sorted(try XCTUnwrap(o["result"])), file: file, line: line) }
        return o
    }

    /// Evento con nombre de fichero `<evento>.<variante>` (o solo `<evento>` si `variant` es nil).
    func variantEvent<T: Encodable>(_ name: String, variant: String? = nil, _ payload: T,
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        let m = try XCTUnwrap(Router.eventMessage(name, payload))
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(m.utf8)) as? [String: Any])
        XCTAssertEqual(o["event"] as? String, name)
        try golden(variant.map { "\(name).\($0)" } ?? name, .event, try Self.sorted(try XCTUnwrap(o["payload"])), file: file, line: line)
    }
}

/// Tema determinista: una parte «Guitarra» con dos tomas (la 1 con vídeo y es la mejor; la 2 solo audio) y una sección.
@MainActor
final class RecordFixtureWorld {
    static let projectId = UUID(uuidString: "00000000-0000-0000-0000-0000000000A0")!
    static let partId = UUID(uuidString: "00000000-0000-0000-0000-0000000000B0")!
    static let take1 = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
    static let take2 = UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!
    static let sectionId = UUID(uuidString: "00000000-0000-0000-0000-0000000000D0")!
    static let date = Date(timeIntervalSince1970: 1_700_000_000)

    let base: URL
    let root: URL
    let bridge: Bridge
    let folder: URL

    init(withVideoTake: Bool = true) throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-fixtures-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("Projects", isDirectory: true)
        let support = base.appendingPathComponent("Support", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        var profile = EquipmentProfile()
        profile.video = VideoSettings(resolution: VideoResolution(width: 640, height: 360), fps: 30)
        try ProfileStore(url: support.appendingPathComponent("profile.json")).save(profile)
        let rate = StudyTests.sampleRate
        var p = Project(id: Self.projectId, song: Song(title: "Tema", artist: "Banda", source: "source/original.wav", sourceSHA256: "abc",
                                                      sourceFormat: "wav", sourceSampleRate: rate, sourceChannels: 2, sampleRate: rate,
                                                      duration: StudyTests.seconds))
        p.separation = SeparationState(state: .done, model: "m", finishedAt: Self.date)
        p.stems = [Stem(kind: .bass, file: "stems/bass.wav")]
        p.sections = [Section(id: Self.sectionId, name: "Estrofa", start: 0.5, end: 2.0)]
        folder = root.appendingPathComponent("Banda - Tema", isDirectory: true)
        let layout = ProjectLayout(folder: folder)
        try layout.createSkeleton()
        try StudyTests.writeSine(layout.stemURL(.bass), frequency: 110)
        var takes: [Take] = []
        for (id, video) in [(Self.take1, withVideoTake), (Self.take2, false)] {
            let rel = "takes/\(id.uuidString)/processed.wav"
            try FileManager.default.createDirectory(at: layout.url(relative: "takes/\(id.uuidString)"), withIntermediateDirectories: true)
            try StudyTests.writeSine(layout.url(relative: rel), frequency: 330, seconds: 3)
            var t = Take(id: id, processedFile: rel, createdAt: Self.date, songStart: 2, partID: Self.partId)
            if video {
                t.videoFile = "takes/\(id.uuidString)/video.mov"
                t.videoOffset = 0.04
                t.videoFormat = TakeVideoFormat(cameraUID: "sim-camera", cameraName: "Cámara simulada", width: 640, height: 360, fps: 30)
                t.videoRotation = 90
            }
            takes.append(t)
        }
        p.takes = takes
        p.recording = RecordingState(parts: [RecordingPart(id: Self.partId, name: "Guitarra", takeIDs: [Self.take1, Self.take2],
                                                           bestTakeID: Self.take1)])
        try ProjectFile.save(p, to: folder)
        let services = JobServices(importer: FixtureImporter(), separator: FixtureSeparator(gate: FixtureGate()),
                                   levelMeter: nil, analyzer: nil, guitarSplitter: nil)
        bridge = try Bridge(options: LaunchOptions(projectsFolder: root, supportDir: support, audio: .simulated),
                            mediaBase: "https://tf.media/", reveal: nil, services: services)
    }

    /// Asigna la guitarra y abre el tema en Backing (requisito de `record.open`).
    func openStudy() async throws {
        _ = await bridge.router.handle("{\"id\":1,\"method\":\"audio.setSettings\",\"params\":{\"inputDeviceUID\":\"sim-in\",\"guitarIn\":[1]}}")
        let r = await bridge.router.handle("{\"id\":1,\"method\":\"study.open\",\"params\":{\"projectId\":\"\(Self.projectId.uuidString)\"}}")
        XCTAssertTrue(r.contains("\"result\""), r)
    }
}

@MainActor
final class ContractFixturesRecordTests: XCTestCase {
    func decodeSnapshot(_ o: [String: Any]) throws -> RecordSnapshot {
        try Router.makeDecoder().decode(RecordSnapshot.self, from: JSONSerialization.data(withJSONObject: try XCTUnwrap(o["result"])))
    }

    func testRecordArea() async throws {
        let world = try RecordFixtureWorld()
        let rig = try FixtureRig(area: "record", simulatedAudioProject: world)
        defer { rig.cleanup() }
        try await world.openStudy()
        let pid = RecordFixtureWorld.projectId.uuidString, t1 = RecordFixtureWorld.take1.uuidString, t2 = RecordFixtureWorld.take2.uuidString

        let first = await world.bridge.router.handle("{\"id\":1,\"method\":\"record.open\",\"params\":{\"projectId\":\"\(pid)\"}}")
        XCTAssertTrue(first.contains("\"result\""), first)
        // La cámara simulada tarda en abrirse: se espera a `simulated` para que el estado sea el fijo.
        var cameraState = ""
        for _ in 0..<200 {
            let r = await world.bridge.router.handle("{\"id\":1,\"method\":\"record.state\",\"params\":{}}")
            let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
            cameraState = try decodeSnapshot(o).camera.state
            if cameraState == "simulated" { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(cameraState, "simulated")
        // Resultado de `record.open` ya con la cámara viva (reabrir es idempotente).
        try await rig.dump("record.open", "{\"projectId\":\"\(pid)\"}")

        try await rig.dump("record.close", paramsOnly: true)
        try await rig.dump("record.setCountIn", "{\"on\":false}")
        try await rig.dump("record.setPreRoll", "{\"bars\":0}")
        try await rig.dump("record.setStartSection", "{\"sectionId\":\"\(RecordFixtureWorld.sectionId.uuidString)\"}")
        try await rig.dump("record.selectPart", "{\"partId\":\"\(RecordFixtureWorld.partId.uuidString)\"}")
        try await rig.dump("record.selectTake", "{}", name: "record.selectTake.none")
        // GR1: con la toma 1 como mejor y ninguna elegida, activar el punch elige la mejor y deja `blockReason` por las marcas.
        let punchOn = try await rig.dump("record.setPunch", "{\"enabled\":true}", name: "record.setPunch.enabled")
        let withBest = try decodeSnapshot(punchOn)
        XCTAssertEqual(withBest.selectedTakeId, t1)
        XCTAssertFalse(withBest.punch.ready)
        try await rig.variantEvent("record.state", variant: "punch-armed-no-marks", withBest)
        let marked = try await rig.dump("record.setPunch", "{\"in\":0.5,\"out\":1.2,\"free\":true}", name: "record.setPunch.marks")
        let readySnap = try decodeSnapshot(marked)
        XCTAssertTrue(readySnap.punch.ready)
        try await rig.variantEvent("record.state", variant: "punch-armed-marks", readySnap)
        try await rig.dump("record.setPunch", "{\"clearIn\":true,\"clearOut\":true}", name: "record.setPunch.clear")
        try await rig.dump("record.setPunch", "{\"enabled\":false}", name: "record.setPunch.disabled")
        try await rig.dump("record.startPunch", "{\"takeId\":\"\(t1)\"}", paramsOnly: true)
        try await rig.dump("record.selectTake", "{\"takeId\":\"\(t2)\"}")
        try await rig.dump("record.markBest", "{\"takeId\":\"\(t2)\"}")
        try await rig.dump("record.markBest", "{\"takeId\":\"\(t1)\"}", name: "record.markBest.restore")
        try await rig.dump("record.addPart", "{\"name\":\"Solo\"}")
        try await rig.dump("record.selectPart", "{\"partId\":\"\(RecordFixtureWorld.partId.uuidString)\"}", name: "record.selectPart.back")
        try await rig.dump("record.rotate")
        try await rig.dump("record.setMix", "{\"channel\":\"bass\",\"gainDB\":-3,\"mute\":false}")
        try await rig.dump("record.setMaster", "{\"gainDB\":-1.5}")
        try await rig.dump("record.setCamera", "{}", name: "record.setCamera")
        try await rig.dump("record.pollCamera")
        try await rig.dump("record.prepareViewTake")
        let adjustSnap = try decodeSnapshot(try await rig.dump("record.adjustOffset", "{\"takeId\":\"\(t1)\"}"))
        try await rig.dump("record.setOffset", "{\"valueMs\":40}")
        try await rig.dump("record.finishOffset", "{\"save\":true,\"makeDefault\":false}")
        try await rig.dump("record.adjustOffset", "{\"takeId\":\"\(t2)\"}", name: "record.adjustOffset.no-video")
        try await rig.dump("record.start", paramsOnly: true)
        try await rig.dump("record.stop", paramsOnly: true)
        try await rig.dump("record.cancel", paramsOnly: true)
        try await rig.dump("record.deleteTake", "{\"takeId\":\"\(t2)\"}")
        let final = try decodeSnapshot(try await rig.dump("record.state", name: "record.state.after-delete"))
        XCTAssertEqual(final.parts.first?.takes.count, 1)
        try await rig.dump("record.state", paramsOnly: false)

        // Eventos: `record.state` por fase y estado de cámara a partir de la instantánea real (idle con cámara simulada).
        var base = try decodeSnapshot(try await rig.dump("record.state", name: "record.state.base"))
        base.position = 0
        try rig.variantEvent("record.state", variant: "idle", base)
        var counting = base; counting.phase = "counting"; counting.countBeat = 2; counting.busy = true
        try rig.variantEvent("record.state", variant: "counting", counting)
        var recording = base; recording.phase = "recording"; recording.busy = true; recording.audio.recording = true; recording.position = 1.5
        try rig.variantEvent("record.state", variant: "recording", recording)
        var finishing = base; finishing.phase = "finishing"; finishing.busy = true
        try rig.variantEvent("record.state", variant: "finishing", finishing)
        // El snapshot real de `record.adjustOffset` lleva `offset` en fase adjusting: la variante lo copia.
        var adjusting = base; adjusting.phase = "adjusting"; adjusting.busy = true; adjusting.offset = adjustSnap.offset
        XCTAssertNotNil(adjusting.offset)
        try rig.variantEvent("record.state", variant: "adjusting", adjusting)
        for (state, message): (String, String?) in [("none", "No hay ninguna cámara conectada. Se grabará solo el audio."),
                                                   ("denied", "ToneForge no tiene permiso para usar la cámara."),
                                                   ("failed", "No se pudo abrir la cámara."), ("live", nil)] {
            var s = base
            s.camera.state = state
            s.camera.message = message
            if state != "live" { s.camera.width = nil; s.camera.height = nil; s.camera.fps = nil; s.camera.label = nil }
            try rig.variantEvent("record.state", variant: "camera-\(state)", s)
        }
        try rig.variantEvent("record.state", variant: "camera-simulated", base)
        var best = base; best.selectedTakeId = t1
        try rig.variantEvent("record.state", variant: "take-best-selected", best)
        try rig.variantEvent("record.position", RecordPositionEvent(seconds: 1.5, playing: true, phase: "recording"))
        try rig.variantEvent("record.levels", RecordLevelsEvent(channels: ["bass": StudyMeter(rmsDB: -18.5, peakDB: -6.25),
                                                                           "guitar": StudyMeter(rmsDB: -120, peakDB: -120)]))
        _ = await world.bridge.router.handle("{\"id\":1,\"method\":\"record.close\",\"params\":{}}")
    }
}
