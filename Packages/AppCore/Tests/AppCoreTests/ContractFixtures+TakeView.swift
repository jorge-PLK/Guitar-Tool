import Foundation
import XCTest
@testable import AppCore

// Fase 7f, ola 3 (parte 3.1c): fixtures de `takeview.*` en `Contract/fixtures/takeview/`. Mismo tema determinista que
// `record` (`RecordFixtureWorld`): la toma 1 lleva vídeo 640x360 girado 90 grados (FC1), la 2 solo audio.
// `takeview.play` depende del reloj real, así que se vuelca solo su params; pause/seek se vuelcan tras una pausa.
@MainActor
final class ContractFixturesTakeViewTests: XCTestCase {
    func testTakeViewArea() async throws {
        let world = try RecordFixtureWorld()
        let rig = try FixtureRig(area: "takeview", simulatedAudioProject: world)
        defer { rig.cleanup() }
        try await world.openStudy()
        let pid = RecordFixtureWorld.projectId.uuidString, t1 = RecordFixtureWorld.take1.uuidString, t2 = RecordFixtureWorld.take2.uuidString

        let open = try await rig.dump("takeview.open", "{\"projectId\":\"\(pid)\",\"takeId\":\"\(t1)\"}")
        let snap = try XCTUnwrap(open["result"] as? [String: Any])
        // FC1: tamaño del fotograma y giro de la toma 1.
        XCTAssertEqual(snap["videoWidth"] as? Int, 640)
        XCTAssertEqual(snap["videoHeight"] as? Int, 360)
        XCTAssertEqual(snap["videoRotation"] as? Int, 90)
        try await rig.dump("takeview.snapshot")
        try await rig.dump("takeview.setBacking", "{\"on\":false}")
        try await rig.dump("takeview.seek", "{\"seconds\":1.25}")
        try await rig.dump("takeview.play", paramsOnly: true)
        try await rig.dump("takeview.pause")
        try await rig.dump("takeview.close")

        let noVideo = try await rig.dump("takeview.open", "{\"projectId\":\"\(pid)\",\"takeId\":\"\(t2)\"}", name: "takeview.open.no-video")
        let nv = try XCTUnwrap(noVideo["result"] as? [String: Any])
        XCTAssertNil(nv["videoWidth"])
        XCTAssertNil(nv["videoHeight"])
        XCTAssertEqual(nv["videoRotation"] as? Int, 0)
        try await rig.dump("takeview.close", name: "takeview.close.no-video", paramsOnly: true)
        _ = await world.bridge.router.handle("{\"id\":1,\"method\":\"takeview.close\",\"params\":{}}")

        // Hoja de desfase: `record.open` + `record.adjustOffset` dejan la toma preparada para `takeview.openOffset`.
        _ = await world.bridge.router.handle("{\"id\":1,\"method\":\"record.open\",\"params\":{\"projectId\":\"\(pid)\"}}")
        let adj = await world.bridge.router.handle("{\"id\":1,\"method\":\"record.adjustOffset\",\"params\":{\"takeId\":\"\(t1)\"}}")
        XCTAssertTrue(adj.contains("\"result\""), adj)
        let off = try await rig.dump("takeview.openOffset")
        XCTAssertNotNil(off["result"], "\(off)")
        _ = await world.bridge.router.handle("{\"id\":1,\"method\":\"record.finishOffset\",\"params\":{\"save\":false,\"makeDefault\":false}}")
        _ = await world.bridge.router.handle("{\"id\":1,\"method\":\"takeview.close\",\"params\":{}}")
        _ = await world.bridge.router.handle("{\"id\":1,\"method\":\"record.close\",\"params\":{}}")

        // Eventos.
        try rig.variantEvent("takeview.position", variant: "paused", TakeViewPositionEvent(seconds: 1.25, playing: false, rate: 0, at: 1000.5, epoch: 2))
        try rig.variantEvent("takeview.position", variant: "playing", TakeViewPositionEvent(seconds: 0.5, playing: true, rate: 1, at: 1000.75, epoch: 1))
        let id = RecordFixtureWorld.take1
        try rig.variantEvent("takeview.video", variant: "ready", TakeViewVideoEvent(takeId: t1, video: nil))
        try rig.variantEvent("takeview.video", variant: "error",
                             TakeViewVideoEvent(takeId: t1, video: TakeVideoStatusInfo(takeId: id, state: .failed("No se pudo convertir el vídeo."))))
        try rig.variantEvent("takeview.video", variant: "converting",
                             TakeViewVideoEvent(takeId: t1, video: TakeVideoStatusInfo(takeId: id, state: .converting(0.4))))
    }
}
