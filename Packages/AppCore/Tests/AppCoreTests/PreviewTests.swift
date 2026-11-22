import Foundation
import VideoKit
import XCTest
@testable import AppCore

// W2-H: host.preview.show / host.preview.hide con anfitrión simulado.

private final class PreviewHost: HostServices, @unchecked Sendable {
    private let lock = NSLock()
    private var _shown: [(URL, PreviewRect)] = []
    private var _hides = 0
    let supported: Bool
    init(supported: Bool = true) { self.supported = supported }
    var shown: [(URL, PreviewRect)] { lock.withLock { _shown } }
    var hides: Int { lock.withLock { _hides } }
    func pickFile(types: [String]) async -> URL? { nil }
    func pickFolder() async -> URL? { nil }
    func showPreview(url: URL, rect: PreviewRect) async -> Bool {
        guard supported else { return false }
        lock.withLock { _shown.append((url, rect)) }
        return true
    }
    func hidePreview() async { lock.withLock { _hides += 1 } }
}

final class PreviewTests: XCTestCase {
    private func bridge(host: (any HostServices)?) throws -> (Bridge, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-preview-\(UUID().uuidString)", isDirectory: true)
        let projects = dir.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let b = try Bridge(options: LaunchOptions(projectsFolder: projects, supportDir: dir.appendingPathComponent("Support")),
                           mediaBase: "https://tf.media/", reveal: nil, services: nil)
        b.host = host
        return (b, dir)
    }

    private func call(_ b: Bridge, _ method: String, _ params: String) async -> [String: Any] {
        let r = await b.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        return (try? JSONSerialization.jsonObject(with: Data(r.utf8))) as? [String: Any] ?? [:]
    }

    private func code(_ r: [String: Any]) -> String? { (r["error"] as? [String: Any])?["code"] as? String }

    func testShowAndHide() async throws {
        let host = PreviewHost()
        let (b, dir) = try bridge(host: host)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ok = await call(b, "host.preview.show",
                            #"{"url":"https://www.songsterr.com/a/wsa/song-tab-s7","x":10,"y":20.5,"width":600,"height":400}"#)
        XCTAssertEqual((ok["result"] as? [String: Any])?["shown"] as? Bool, true)
        XCTAssertEqual(host.shown.first?.1, PreviewRect(x: 10, y: 20.5, width: 600, height: 400))
        let h1 = await call(b, "host.preview.hide", "{}")
        let h2 = await call(b, "host.preview.hide", "{}")
        XCTAssertEqual((h1["result"] as? [String: Any])?["hidden"] as? Bool, true)
        XCTAssertEqual((h2["result"] as? [String: Any])?["hidden"] as? Bool, true)
        XCTAssertEqual(host.hides, 2)
    }

    func testValidationAndUnsupported() async throws {
        let host = PreviewHost()
        let (b, dir) = try bridge(host: host)
        defer { try? FileManager.default.removeItem(at: dir) }
        for url in ["http://www.songsterr.com/x", "https://example.com/x", "file:///C:/x"] {
            let r = await call(b, "host.preview.show", "{\"url\":\"\(url)\",\"x\":0,\"y\":0,\"width\":10,\"height\":10}")
            XCTAssertEqual(code(r), "bad-params", url)
        }
        let flat = await call(b, "host.preview.show", #"{"url":"https://www.songsterr.com/a","x":0,"y":0,"width":0,"height":10}"#)
        XCTAssertEqual(code(flat), "bad-params")
        XCTAssertTrue(host.shown.isEmpty)

        let valid = #"{"url":"https://www.songsterr.com/a","x":0,"y":0,"width":10,"height":10}"#
        let (b2, dir2) = try bridge(host: PreviewHost(supported: false))
        defer { try? FileManager.default.removeItem(at: dir2) }
        let un = await call(b2, "host.preview.show", valid)
        XCTAssertEqual(code(un), "unsupported")
        let (b3, dir3) = try bridge(host: nil)
        defer { try? FileManager.default.removeItem(at: dir3) }
        let none = await call(b3, "host.preview.show", valid)
        XCTAssertEqual(code(none), "unsupported")
        let hide = await call(b3, "host.preview.hide", "{}")
        XCTAssertEqual((hide["result"] as? [String: Any])?["hidden"] as? Bool, true)
    }
}


// W2-N: modos `denied` y `failed` de `video.preview.start`, y «Abrir Ajustes del Sistema».

private final class PrivacyOpener: CameraPrivacyOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var _opened = 0
    var failing = false
    var opened: Int { lock.withLock { _opened } }
    func openCameraPrivacy() throws {
        if failing { throw RPCError(code: "internal", message: "no") }
        lock.withLock { _opened += 1 }
    }
}

private struct OpenFailure: Error {}

@MainActor
final class CameraPreviewModesTests: XCTestCase {
    private func service(access: Bool, make: @escaping @Sendable (CameraDevice) throws -> any CameraCapture) throws -> (CameraPreviewService, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-camera-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let s = CameraPreviewService(options: LaunchOptions(projectsFolder: nil, supportDir: dir))
        s.cameras = RecordCameraSource(provider: SimulatedCameraProvider(), makeCapture: make, ensureAccess: { access }, isSimulated: false)
        s.makeRelay = { FrameRelay(channel: "t-modes-\(UUID().uuidString)", emit: { _, _ in }) }
        return (s, dir)
    }

    func testDeniedWhenPermissionIsRefused() async throws {
        let (s, dir) = try service(access: false) { SimulatedCameraCapture(camera: $0, config: .init(pixels: true), automatic: true) }
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = await s.start()
        XCTAssertEqual(r.state, "denied")
        XCTAssertEqual(r.message, "ToneForge no tiene permiso para usar la cámara.")
        XCTAssertNotNil(r.cameraId)
    }

    func testDeniedWhenOpeningThrowsNoAccess() async throws {
        let (s, dir) = try service(access: true) { _ in throw CameraError.noAccess }
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = await s.start()
        XCTAssertEqual(r.state, "denied")
        XCTAssertEqual(r.message, CameraPreviewService.deniedMessage)
    }

    func testFailedWhenOpeningThrows() async throws {
        let (s, dir) = try service(access: true) { _ in throw OpenFailure() }
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = await s.start()
        XCTAssertEqual(r.state, "failed")
        XCTAssertTrue(r.message?.hasPrefix("No se pudo abrir la cámara (") == true, "\(String(describing: r.message))")
        XCTAssertNil(r.width)
    }

    func testOpenCameraPrivacyMethod() async throws {
        let (s, dir) = try service(access: true) { _ in throw OpenFailure() }
        defer { try? FileManager.default.removeItem(at: dir) }
        let opener = PrivacyOpener()
        s.privacy = opener
        let router = Router()
        s.register(on: router)
        let ok = await router.handle(#"{"id":1,"method":"video.openCameraPrivacy","params":{}}"#)
        XCTAssertTrue(ok.contains("\"opened\":true"), ok)
        XCTAssertEqual(opener.opened, 1)
        opener.failing = true
        let bad = await router.handle(#"{"id":2,"method":"video.openCameraPrivacy","params":{}}"#)
        XCTAssertTrue(bad.contains("\"error\""), bad)
    }
}
