import Foundation
import Store
import XCTest
@testable import AppCore

// PC-7: el bucle de eventos de la biblioteca no debe retener el JobEngine (ni el árbol que cuelga de él).
@MainActor
final class JobEngineLifetimeTests: XCTestCase {
    private func waitUntil(_ seconds: Double = 2, _ cond: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if cond() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return cond()
    }

    private final class WeakBox<T: AnyObject> { weak var value: T? }

    private func startEngine(_ dir: URL, _ box: WeakBox<JobEngine>) async throws {
        let engine = JobEngine(root: ProjectsRoot(dir.appendingPathComponent("Projects", isDirectory: true)),
                               profileStore: ProfileStore(url: dir.appendingPathComponent("p.json")), indexURL: nil,
                               services: { JobServices(importer: EditsImporter(), separator: EditsSeparator(),
                                                       levelMeter: nil, analyzer: nil, guitarSplitter: nil) })
        box.value = engine
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Projects"), withIntermediateDirectories: true)
        await engine.start()
    }

    func testJobEngineIsReleasedAfterLibraryStarted() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jobengine-life-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let box = WeakBox<JobEngine>()
        try await startEngine(dir, box)
        let released = await waitUntil { box.value == nil }
        XCTAssertTrue(released, "JobEngine retenido por el bucle de eventos de la biblioteca")
    }

    func testOpenedStudyReleasesPumpThreads() async throws {
        let before = RealtimePump.liveCount
        let box = WeakBox<Bridge>()
        var dirToClean: URL?
        do {
            let rig = try FixtureRig(area: "pc7-life")
            dirToClean = rig.dir
            box.value = rig.bridge
            let p = try FixtureSeed.project(in: rig.projects)
            _ = try await rig.call("study.open", "{\"projectId\":\"\(p.id.uuidString)\"}")
        }
        defer { if let d = dirToClean { try? FileManager.default.removeItem(at: d) } }
        let released = await waitUntil(3) { box.value == nil && RealtimePump.liveCount <= before }
        XCTAssertTrue(released, "Bridge nil: \(box.value == nil), bombas \(RealtimePump.liveCount) vs \(before)")
    }
}
