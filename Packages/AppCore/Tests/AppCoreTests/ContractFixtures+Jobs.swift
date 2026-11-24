import Foundation
import Store
import XCTest
@testable import AppCore

final class ContractFixturesJobsTests: XCTestCase {
    func testJobsArea() async throws {
        let rig = try FixtureRig(area: "jobs")
        defer { rig.cleanup() }
        let song = rig.dir.appendingPathComponent("Song.mp3")
        try "audio-1".write(to: song, atomically: true, encoding: .utf8)
        let imported = try await rig.run("import.file", params: "{\"path\":\(rig.jsonString(song.path))}")
        let id = try XCTUnwrap((imported["result"] as? [String: Any])?["id"] as? String)

        // Espera a que la separación esté en marcha (etapa y fracción fijas por el doble).
        var live = false
        for _ in 0..<400 where !live {
            let r = await rig.bridge.router.handle("{\"id\":1,\"method\":\"jobs.list\"}")
            let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
            let jobs = (o["result"] as? [String: Any])?["jobs"] as? [[String: Any]] ?? []
            live = jobs.contains { $0["stage"] as? String == "separation" && $0["state"] as? String == "running"
                && $0["fraction"] as? Double == 0.25 }
            if !live { try await Task.sleep(for: .milliseconds(20)) }
        }
        XCTAssertTrue(live, "La separación no llegó a 0.25")
        try await rig.run("jobs.list")

        // Evento construido con el codificador real (el emitido por la cola depende del reloj).
        try rig.event("jobs.progress", JobInfo(id: id, title: "Song", stage: "separation", state: "running",
                                               fraction: 0.25, text: "Separando pistas", error: nil))

        try await rig.runExpectingError("jobs.cancel", params: "{\"id\":\"no-es-uuid\"}")
        try await rig.run("jobs.cancel", params: "{\"id\":\(rig.jsonString(id))}")
    }
}
