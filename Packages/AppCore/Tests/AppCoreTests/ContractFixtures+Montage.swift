import Foundation
import XCTest
@testable import AppCore

// Fase 7f, ola 4: fixtures de `montage.*` en `Contract/fixtures/montage/`. Mismo tema determinista que `record`/`takeview`
// (`RecordFixtureWorld`: UUID fijos, la toma 1 con vídeo 640x360 girado 90 grados). Montaje con servicios y audio simulados
// (nada de hardware). `montage.play` y `montage.reveal` dependen del reloj / abren el Finder real: se vuelca el params y,
// en `reveal`, el result a partir del tipo real. Los eventos periódicos se vuelcan con valores fijos; `montage.state` es la
// instantánea real de `montage.open` ya asentada y `montage.export` el evento `done` real de la exportación simulada.
extension FixtureRig {
    /// Las medidas de la vista previa (tiempos de fotograma, contadores) y el nombre del WAV (lleva un hash) cambian de una
    /// ejecución a otra: se fijan antes de volcar. Recorre el JSON entero (result o payload).
    static func stabilizeMontage(_ any: Any) -> Any {
        if var d = any as? [String: Any] {
            if d["frameP50Ms"] != nil {
                for k in ["frameP50Ms", "frameP95Ms", "lastFrameMillis"] { d[k] = 1.0 }
                d["delivered"] = 4
                d["skipped"] = 0
            }
            if d["phase"] != nil, d["progress"] != nil, d["file"] != nil { d["file"] = "preview-fixture.wav" }
            return d.mapValues { stabilizeMontage($0) }
        }
        if let a = any as? [Any] { return a.map { stabilizeMontage($0) } }
        return any
    }

    /// Como `dump`, con las medidas inestables fijadas.
    @discardableResult
    func dumpStable(_ method: String, _ params: String = "{}", name: String? = nil, paramsOnly: Bool = false,
                    file: StaticString = #filePath, line: UInt = #line) async throws -> [String: Any] {
        let n = name ?? method
        let p = try JSONSerialization.jsonObject(with: Data(params.utf8), options: [.fragmentsAllowed])
        try golden(n, .params, try Self.sorted(p), file: file, line: line)
        if paramsOnly { return [:] }
        let r = await bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
        if let e = o["error"] { try golden(n, .error, try Self.sorted(e), file: file, line: line) }
        else { try golden(n, .result, try Self.sorted(Self.stabilizeMontage(try XCTUnwrap(o["result"]))), file: file, line: line) }
        return o
    }
}

@MainActor
final class ContractFixturesMontageTests: XCTestCase {
    private func settle(_ world: RecordFixtureWorld) async {
        let end = ProcessInfo.processInfo.systemUptime + 8
        while ProcessInfo.processInfo.systemUptime < end {
            if let c = world.bridge.montageService.current, c.previewPhase == .ready, c.audioPhase == .ready, !c.isAnalyzing { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    func testMontageArea() async throws {
        let world = try RecordFixtureWorld()
        let rig = try FixtureRig(area: "montage", simulatedAudioProject: world)
        defer { rig.cleanup() }
        let b = world.bridge
        let events = MontageTests.Events()
        b.send = { events.add($0) }
        b.montageService.services = .simulated()
        b.montageService.audioFactory = { _, _ in ClockMontageAudio() }
        b.montageService.timing = MontageController.Timing(previewDebounce: 0.01, saveDelay: 0.05)
        let pid = RecordFixtureWorld.projectId.uuidString, t1 = RecordFixtureWorld.take1.uuidString
        let part = RecordFixtureWorld.partId.uuidString

        // Antes de abrir.
        try await rig.dumpStable("montage.snapshot", name: "montage.snapshot.not-open")

        let open = try await rig.dumpStable("montage.open", "{\"projectId\":\"\(pid)\"}")
        XCTAssertNotNil(open["result"], "\(open)")
        await settle(world)
        let snap = try await rig.dumpStable("montage.snapshot")
        let snapResult = try XCTUnwrap(snap["result"] as? [String: Any], "\(snap)")
        XCTAssertEqual(snapResult["hasPlan"] as? Bool, true)
        try rig.golden("montage.state", .event, try FixtureRig.sorted(FixtureRig.stabilizeMontage(snapResult)))

        try await rig.dumpStable("montage.setLayout", "{\"layout\":\"grid\"}")
        try await rig.dumpStable("montage.setLayout", "{\"layout\":\"nope\"}", name: "montage.setLayout.bad-params")
        try await rig.dumpStable("montage.setSingleRhythm", "{\"partId\":\"\(part)\"}")
        try await rig.dumpStable("montage.setCutGaps", "{\"on\":false}")
        try await rig.dumpStable("montage.moveLane", "{\"id\":\"\(part)\",\"to\":\"\(part)\"}")
        try await rig.dumpStable("montage.setPartOrder", "{\"ids\":[\"\(part)\"]}")
        try await rig.dumpStable("montage.setCaption", "{\"on\":false}")
        try await rig.dumpStable("montage.setShowPartLabels", "{\"on\":false}")
        try await rig.dumpStable("montage.setKeepVideoAspect", "{\"on\":true}")

        // Plano único y cortes.
        try await rig.dumpStable("montage.setLayout", "{\"layout\":\"single\"}", name: "montage.setLayout.single")
        // MO7: instantánea con plano único (lleva `autoPartId`).
        // El fixture `montage.snapshot.single` lo escribe `testMontageStates` (estado `single`, con dos cortes).
        let singleRaw = await b.router.handle("{\"id\":1,\"method\":\"montage.snapshot\",\"params\":{}}")
        XCTAssertTrue(singleRaw.contains("autoPartId"), singleRaw)
        try rig.golden("montage.snapshot.single", .params, "{}")
        let add = try await rig.dumpStable("montage.addCut", "{\"time\":3,\"partId\":\"\(part)\",\"exact\":true}")
        let added = try XCTUnwrap(add["result"] as? [String: Any], "\(add)")
        let cutId = try XCTUnwrap(added["cutId"] as? String)
        try await rig.dumpStable("montage.moveCut", "{\"id\":\"\(cutId)\",\"time\":3.5}")
        try await rig.dumpStable("montage.setCutPart", "{\"id\":\"\(cutId)\"}")
        try await rig.dumpStable("montage.removeCut", "{\"id\":\"\(cutId)\"}")
        _ = await b.router.handle("{\"id\":1,\"method\":\"montage.addCut\",\"params\":{\"time\":3,\"exact\":true}}")
        try await rig.dumpStable("montage.clearCuts")
        try await rig.dumpStable("montage.setLayout", "{\"layout\":\"side\"}", name: "montage.setLayout.side")

        // Exportación (ajustes).
        try await rig.dumpStable("montage.setExport",
                           "{\"container\":\"mp4\",\"trackWAVs\":false,\"fps\":25,\"resolution\":{\"width\":1280,\"height\":720}}")

        // Encuadre.
        try await rig.dumpStable("montage.setFraming",
                           "{\"takeId\":\"\(t1)\",\"mode\":\"fixed\",\"manualBox\":{\"x\":0.1,\"y\":0.1,\"width\":0.5,\"height\":0.5}}")
        try await rig.dumpStable("montage.framingFrame", "{\"takeId\":\"\(t1)\",\"time\":3}")
        try await rig.dumpStable("montage.setFraming",
                           "{\"takeId\":\"\(t1)\",\"mode\":\"follow\",\"followZoom\":1.4,\"followOffset\":{\"x\":0.1,\"y\":-0.1}}",
                           name: "montage.setFraming.follow")
        try await rig.dumpStable("montage.resetFraming", "{\"takeId\":\"\(t1)\"}")
        try await rig.dumpStable("montage.reanalyze", "{\"takeId\":\"\(t1)\"}")
        await settle(world)
        try await rig.dumpStable("montage.rotateTake", "{\"takeId\":\"\(t1)\"}")
        try await rig.dumpStable("montage.rotateTake", "{\"takeId\":\"x\"}", name: "montage.rotateTake.bad-params")
        await settle(world)

        // Transporte.
        try await rig.dumpStable("montage.seek", "{\"seconds\":4}")
        try await rig.dumpStable("montage.play", paramsOnly: true)
        try await rig.dumpStable("montage.pause")
        try await rig.dumpStable("montage.setPreviewFps", "{\"fps\":30}")

        // Exportación (fases).
        try await rig.dumpStable("montage.startExport")
        let end = ProcessInfo.processInfo.systemUptime + 8
        while ProcessInfo.processInfo.systemUptime < end,
              !events.all("montage.export").contains(where: { $0.payload["phase"] as? String == "done" }) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let done = try XCTUnwrap(events.all("montage.export").last?.payload)
        XCTAssertEqual(done["phase"] as? String, "done")
        try rig.golden("montage.export.done", .event, try FixtureRig.sorted(done))
        try await rig.dumpStable("montage.dismissExport")
        try await rig.dumpStable("montage.cancelExport")

        try await rig.dumpStable("montage.reveal", paramsOnly: true)
        try rig.variantResult("montage.reveal", variant: "ok", MontageRevealResult(revealed: true))

        try await rig.dumpStable("montage.close")
        try await rig.dumpStable("montage.snapshot", name: "montage.snapshot.closed")

        // Eventos de valores fijos.
        try rig.variantEvent("montage.export", variant: "running",
                             MontageExportEvent(phase: "running", stage: "Codificando el vídeo", progress: 0.4, message: nil, result: nil))
        try rig.variantEvent("montage.export", variant: "running-mixing",
                             MontageExportEvent(phase: "running", stage: "Mezclando el audio", progress: 0.1, message: nil, result: nil))
        try rig.variantEvent("montage.export", variant: "failed",
                             MontageExportEvent(phase: "failed", stage: nil, progress: 0.4, message: "No se pudo exportar.", result: nil))
        try rig.variantEvent("montage.export", variant: "cancelled",
                             MontageExportEvent(phase: "cancelled", stage: nil, progress: 0.4, message: nil, result: nil))
        try rig.variantEvent("montage.framing", variant: "analyzing",
                             MontageFramingEvent(takeId: t1, status: "analyzing", progress: 0.5, samples: nil, detected: nil, error: nil))
        try rig.variantEvent("montage.framing", variant: "ready",
                             MontageFramingEvent(takeId: t1, status: "ready", progress: 1, samples: 20, detected: 18, error: nil))
        try rig.variantEvent("montage.framing", variant: "failed",
                             MontageFramingEvent(takeId: t1, status: "failed", progress: 0, samples: nil, detected: nil,
                                                 error: "No se pudo analizar el vídeo."))
        try rig.variantEvent("montage.position", variant: "paused", MontagePositionEvent(seconds: 4, videoSeconds: 1.5, playing: false))
        try rig.variantEvent("montage.position", variant: "playing", MontagePositionEvent(seconds: 4.5, videoSeconds: 2, playing: true))
    }

    // MARK: - Variantes de estado (`--mock --screen montage --state <S>`)

    private func prepare(_ world: RecordFixtureWorld) {
        let b = world.bridge
        b.send = { _ in }
        b.montageService.services = .simulated()
        b.montageService.audioFactory = { _, _ in ClockMontageAudio() }
        b.montageService.timing = MontageController.Timing(previewDebounce: 0.01, saveDelay: 0.05)
    }

    private func currentSnapshot(_ world: RecordFixtureWorld) async throws -> MontageSnapshot {
        let r = await world.bridge.router.handle("{\"id\":1,\"method\":\"montage.snapshot\",\"params\":{}}")
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any], r)
        return try Router.makeDecoder().decode(MontageSnapshot.self, from: JSONSerialization.data(withJSONObject: try XCTUnwrap(o["result"], r)))
    }

    /// `montage.open.S` y `montage.snapshot.S` (resultados) y, si `event`, `montage.state.S` (evento) a partir de una instantánea real.
    private func writeState(_ rig: FixtureRig, _ s: String, _ snap: MontageSnapshot, event: Bool = false) throws {
        let m = try XCTUnwrap(Router.eventMessage("x", snap))
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(m.utf8)) as? [String: Any])
        let json = try FixtureRig.sorted(FixtureRig.stabilizeMontage(try XCTUnwrap(o["payload"])))
        try rig.golden("montage.open.\(s)", .result, json)
        try rig.golden("montage.snapshot.\(s)", .result, json)
        if event { try rig.golden("montage.state.\(s)", .event, json) }
    }

    func testMontageStates() async throws {
        // no-takes: tema sin ninguna toma con vídeo.
        do {
            let world = try RecordFixtureWorld(withVideoTake: false)
            let rig = try FixtureRig(area: "montage", simulatedAudioProject: world)
            defer { rig.cleanup() }
            prepare(world)
            let pid = RecordFixtureWorld.projectId.uuidString
            _ = await world.bridge.router.handle("{\"id\":1,\"method\":\"montage.open\",\"params\":{\"projectId\":\"\(pid)\"}}")
            await settle(world)
            let snap = try await currentSnapshot(world)
            XCTAssertFalse(snap.lanes.contains { $0.hasVideo })
            try writeState(rig, "no-takes", snap)
        }

        let world = try RecordFixtureWorld()
        let rig = try FixtureRig(area: "montage", simulatedAudioProject: world)
        defer { rig.cleanup() }
        prepare(world)
        let router = world.bridge.router
        let pid = RecordFixtureWorld.projectId.uuidString, t1 = RecordFixtureWorld.take1.uuidString
        let part = RecordFixtureWorld.partId.uuidString
        _ = await router.handle("{\"id\":1,\"method\":\"montage.open\",\"params\":{\"projectId\":\"\(pid)\"}}")
        await settle(world)

        // portrait: lienzo vertical apilado.
        _ = await router.handle("{\"id\":1,\"method\":\"montage.setLayout\",\"params\":{\"layout\":\"stack\"}}")
        await settle(world)
        var snap = try await currentSnapshot(world)
        XCTAssertTrue(snap.isPortrait)
        XCTAssertEqual(snap.canvasLabel, "1080 × 1920")
        try writeState(rig, "portrait", snap)

        // single: plano único con dos cortes (uno cubierto y otro no, si el núcleo lo distingue).
        _ = await router.handle("{\"id\":1,\"method\":\"montage.setLayout\",\"params\":{\"layout\":\"single\"}}")
        _ = await router.handle("{\"id\":1,\"method\":\"montage.addCut\",\"params\":{\"time\":3,\"partId\":\"\(part)\",\"exact\":true}}")
        _ = await router.handle("{\"id\":1,\"method\":\"montage.addCut\",\"params\":{\"time\":6.8,\"exact\":true}}")
        await settle(world)
        snap = try await currentSnapshot(world)
        XCTAssertEqual(snap.cuts.count, 2, "\(snap.cuts)")
        XCTAssertNotNil(snap.autoPartId)
        try writeState(rig, "single", snap)
        _ = await router.handle("{\"id\":1,\"method\":\"montage.clearCuts\",\"params\":{}}")
        _ = await router.handle("{\"id\":1,\"method\":\"montage.setLayout\",\"params\":{\"layout\":\"side\"}}")
        await settle(world)

        // framing-follow: la toma en modo seguir.
        _ = await router.handle("{\"id\":1,\"method\":\"montage.setFraming\",\"params\":{\"takeId\":\"\(t1)\",\"mode\":\"follow\",\"followZoom\":1.4,\"followOffset\":{\"x\":0.1,\"y\":-0.1}}}")
        await settle(world)
        try await rig.dumpStable("montage.framingFrame", "{\"takeId\":\"\(t1)\",\"time\":3}", name: "montage.framingFrame.framing-follow")
        let follow = try await currentSnapshot(world)
        XCTAssertEqual(follow.framing.first { $0.takeId == t1 }?.mode, "follow")
        try writeState(rig, "framing-follow", follow, event: true)

        // El resto parte de la instantánea real con el estado de exportación o de análisis cambiado.
        var base = follow
        if let i = base.framing.firstIndex(where: { $0.takeId == t1 }) {
            base.framing[i].mode = "fixed"
            base.framing[i].followZoom = 1
            base.framing[i].followOffset = MontageOffsetInfo(x: 0, y: 0)
        }

        var analyzing = base
        if let i = analyzing.framing.firstIndex(where: { $0.takeId == t1 }) {
            analyzing.framing[i].status = "analyzing"
            analyzing.framing[i].progress = 0.5
            analyzing.framing[i].samples = nil
            analyzing.framing[i].detected = nil
            analyzing.framing[i].error = nil
        }
        analyzing.isAnalyzing = true
        try writeState(rig, "analyzing", analyzing, event: true)

        let exporting = MontageExportEvent(phase: "running", stage: "Codificando el vídeo", progress: 0.42, message: nil, result: nil)
        var s = base
        s.exportStatus = exporting
        try writeState(rig, "exporting", s, event: true)
        try rig.variantEvent("montage.export", variant: "exporting", exporting)

        let result = MontageExportResultInfo(
            path: "/private/<dir>/Projects/Banda - Tema/video/Banda - Tema-side.mp4",
            tracksDirectory: "/private/<dir>/Projects/Banda - Tema/video/Banda - Tema-side-pistas",
            finalLUFS: -14, finalTruePeakDB: -1.0, normalized: true, limitedByPeak: true, limiterEnabled: true,
            limiterApplied: true, limiterMaxReductionDB: 2.5, limiterOutOfTolerance: false,
            clippedFiles: ["Guitarra.wav"], codec: "hevc")
        let exported = MontageExportEvent(phase: "done", stage: nil, progress: 1, message: nil, result: result)
        s = base
        s.exportStatus = exported
        try writeState(rig, "exported", s, event: true)
        try rig.variantEvent("montage.export", variant: "exported", exported)

        let failed = MontageExportEvent(phase: "failed", stage: nil, progress: 0.42, message: "No se pudo exportar.", result: nil)
        s = base
        s.exportStatus = failed
        try writeState(rig, "export-failed", s, event: true)
        try rig.variantEvent("montage.export", variant: "export-failed", failed)
    }
}
