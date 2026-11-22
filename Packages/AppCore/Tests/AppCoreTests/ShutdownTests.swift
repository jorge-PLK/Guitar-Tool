import XCTest
@testable import AppCore

/// B6: cierre ordenado compartido por Mac y Windows (`Bridge.shutdownAsync`).
final class ShutdownTests: XCTestCase {
    private final class Order: @unchecked Sendable {
        let lock = NSLock()
        var events: [String] = []
        func add(_ e: String) { lock.withLock { events.append(e) } }
    }

    func testShutdownRunsLinkAndPlaylistHooksThenCustomOnesWithinBudget() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-shutdown-\(UUID().uuidString)", isDirectory: true)
        let projects = dir.appendingPathComponent("P", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bridge = try Bridge(options: LaunchOptions(projectsFolder: projects, supportDir: dir.appendingPathComponent("S")),
                                mediaBase: "https://tf.media/", reveal: nil)
        // Los enlaces y la lista ya enganchan su cancelación al arrancar el puente.
        XCTAssertGreaterThanOrEqual(bridge.shutdownHooks.count, 2)
        let order = Order()
        bridge.addShutdownHook { order.add("hook") }
        let start = Date()
        await bridge.shutdownAsync()
        XCTAssertEqual(order.events, ["hook"])
        XCTAssertLessThan(Date().timeIntervalSince(start), JobEngine.shutdownBudget + 1)
        // Idempotente: un segundo cierre (main.swift lo repite tras on_close) no falla ni se cuelga.
        await bridge.shutdownAsync()
        XCTAssertEqual(order.events, ["hook", "hook"])
    }
}
