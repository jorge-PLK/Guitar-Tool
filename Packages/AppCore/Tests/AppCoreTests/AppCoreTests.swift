import Foundation
import Store
import XCTest
@testable import AppCore

private func obj(_ s: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] ?? [:]
}

private func tempDir() throws -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

final class LaunchOptionsTests: XCTestCase {
    func testParseAll() {
        let o = LaunchOptions.parse(["tf.exe", "--projects-folder", "/p", "--support-dir=/s", "--screen", "library",
                                     "--project", "abc", "--snapshot", "/x.png", "--snapshot-delay", "3.5",
                                     "--window", "1280x800"])
        XCTAssertEqual(o.projectsFolder?.path, "/p")
        XCTAssertEqual(o.supportDir?.path, "/s")
        XCTAssertEqual(o.screen, "library")
        XCTAssertEqual(o.project, "abc")
        XCTAssertEqual(o.snapshot?.path, "/x.png")
        XCTAssertEqual(o.snapshotDelay, 3.5)
        XCTAssertEqual(o.window?.width, 1280)
        XCTAssertEqual(o.window?.height, 800)
    }

    func testDefaultsAndGarbage() {
        let o = LaunchOptions.parse(["--window", "bad", "--snapshot-delay", "x", "--unknown", "--screen"])
        XCTAssertNil(o.window)
        XCTAssertNil(o.screen)
        XCTAssertEqual(o.snapshotDelay, 2)
        XCTAssertNil(o.projectsFolder)
    }
}

final class RouterTests: XCTestCase {
    struct Add: Codable, Sendable { var a: Int; var b: Int }
    struct Sum: Codable, Sendable { var sum: Int }

    private func router() -> Router {
        let r = Router()
        r.register("math.add") { (p: Add) in Sum(sum: p.a + p.b) }
        r.register("math.fail") { (_: Empty) -> Empty in throw RPCError(code: "nope", message: "no") }
        r.register("math.crash") { (_: Empty) -> Empty in struct E: Error {}; throw E() }
        return r
    }

    func testOk() async {
        let o = obj(await router().handle(#"{"id":7,"method":"math.add","params":{"a":2,"b":3}}"#))
        XCTAssertEqual(o["id"] as? Int, 7)
        XCTAssertEqual((o["result"] as? [String: Any])?["sum"] as? Int, 5)
    }

    func testMissingParamsUsesEmptyObject() async {
        let o = obj(await router().handle(#"{"id":1,"method":"math.fail"}"#))
        XCTAssertEqual((o["error"] as? [String: Any])?["code"] as? String, "nope")
    }

    func testErrors() async {
        let r = router()
        let unknown = obj(await r.handle(#"{"id":2,"method":"x.y"}"#))
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? String, "unknown-method")
        XCTAssertEqual(unknown["id"] as? Int, 2)
        let badParams = obj(await r.handle(#"{"id":3,"method":"math.add","params":{"a":"x"}}"#))
        XCTAssertEqual((badParams["error"] as? [String: Any])?["code"] as? String, "bad-params")
        for bad in ["not json", "[1,2]", "", #"{"method":"math.add"}"#, #"{"id":"x","method":"a"}"#] {
            let o = obj(await r.handle(bad))
            XCTAssertNotNil(o["error"], bad)
            XCTAssertNil(o["result"])
        }
        let crash = obj(await r.handle(#"{"id":4,"method":"math.crash"}"#))
        XCTAssertEqual((crash["error"] as? [String: Any])?["code"] as? String, "internal")
    }

    func testEvent() throws {
        let m = try XCTUnwrap(Router.eventMessage("library.changed", Empty()))
        let o = obj(m)
        XCTAssertEqual(o["event"] as? String, "library.changed")
        XCTAssertNotNil(o["payload"] as? [String: Any])
    }
}

final class BridgeTests: XCTestCase {
    private func makeProject(in root: URL, title: String, artist: String?, cover: Bool = false,
                             state: SeparationStatus = .none) throws -> Project {
        var p = Project(song: Song(title: title, artist: artist, source: "source/original.wav", sourceSHA256: "x",
                                   sourceFormat: "wav", sourceSampleRate: 44100, sourceChannels: 2,
                                   sampleRate: 44100, duration: 123.5))
        p.separation = SeparationState(state: state)
        let folder = root.appendingPathComponent(FolderNaming.baseName(title: title, artist: artist), isDirectory: true)
        try ProjectLayout(folder: folder).createSkeleton()
        if cover { try Data([1, 2, 3]).write(to: ProjectLayout(folder: folder).coverFile) }
        try ProjectFile.save(p, to: folder)
        return p
    }

    private func call(_ b: Bridge, _ json: String) async -> [String: Any] {
        let exp = expectation(description: "send")
        let box = Box()
        b.send = { box.value = $0; exp.fulfill() }
        b.receive(json)
        await fulfillment(of: [exp], timeout: 5)
        return obj(box.value)
    }

    final class Box: @unchecked Sendable { var value = "" }

    func testAppInfo() async throws {
        let root = try tempDir()
        var opts = LaunchOptions(projectsFolder: root)
        opts.screen = "library"
        opts.snapshot = URL(fileURLWithPath: "/x.png")
        let b = try Bridge(options: opts, mediaBase: "https://tf.media/")
        XCTAssertEqual(b.mediaFolder, root)
        let rRaw = await call(b, #"{"id":1,"method":"app.info"}"#)
        let r = try XCTUnwrap(rRaw["result"] as? [String: Any])
        XCTAssertEqual(r["mediaBase"] as? String, "https://tf.media/")
        XCTAssertEqual(r["projectsFolder"] as? String, root.path)
        let launch = try XCTUnwrap(r["launch"] as? [String: Any])
        XCTAssertEqual(launch["screen"] as? String, "library")
        XCTAssertEqual(launch["snapshot"] as? Bool, true)
        XCTAssertTrue(["macos", "windows"].contains(r["platform"] as? String ?? ""))
    }

    func testListAndDetail() async throws {
        let root = try tempDir()
        let a = try makeProject(in: root, title: "Zeta", artist: "Band", cover: true, state: .done)
        _ = try makeProject(in: root, title: "alfa", artist: nil)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("vacia"), withIntermediateDirectories: true)
        let b = try Bridge(options: LaunchOptions(projectsFolder: root), mediaBase: "m")
        let listRaw = await call(b, #"{"id":1,"method":"library.list"}"#)
        let list = try XCTUnwrap(listRaw["result"] as? [String: Any])
        let projects = try XCTUnwrap(list["projects"] as? [[String: Any]])
        XCTAssertEqual(projects.map { $0["title"] as? String }, ["alfa", "Zeta"])
        let z = projects[1]
        XCTAssertEqual(z["id"] as? String, a.id.uuidString)
        XCTAssertEqual(z["cover"] as? String, "Band - Zeta/source/cover.jpg")
        XCTAssertEqual(z["separationState"] as? String, "done")
        XCTAssertEqual(z["duration"] as? Double, 123.5)
        XCTAssertTrue(projects[0]["cover"] is NSNull || projects[0]["cover"] == nil)

        let dRaw = await call(b, #"{"id":2,"method":"library.project","params":{"id":"\#(a.id.uuidString)"}}"#)
        let d = try XCTUnwrap(dRaw["result"] as? [String: Any])
        XCTAssertEqual(d["title"] as? String, "Zeta")
        XCTAssertNotNil(d["stems"] as? [Any])
        XCTAssertNotNil(d["parts"] as? [Any])

        let nf = await call(b, #"{"id":3,"method":"library.project","params":{"id":"\#(UUID().uuidString)"}}"#)
        XCTAssertEqual((nf["error"] as? [String: Any])?["code"] as? String, "not-found")
        let bp = await call(b, #"{"id":4,"method":"library.project","params":{"id":"zz"}}"#)
        XCTAssertEqual((bp["error"] as? [String: Any])?["code"] as? String, "bad-params")
    }

    func testGuitarsAndReveal() async throws {
        let root = try tempDir()
        var p = try makeProject(in: root, title: "G", artist: "A")
        p.guitars = [Guitar(role: .left, name: "Izq"), Guitar(role: .right)]
        try ProjectFile.save(p, to: root.appendingPathComponent("A - G"))
        _ = try makeProject(in: root, title: "Sin", artist: nil)
        let opened = Box()
        let b = try Bridge(options: LaunchOptions(projectsFolder: root), mediaBase: "m",
                           reveal: { opened.value = $0.lastPathComponent })
        let listRaw = await call(b, #"{"id":1,"method":"library.list"}"#)
        let projects = try XCTUnwrap((listRaw["result"] as? [String: Any])?["projects"] as? [[String: Any]])
        let g = try XCTUnwrap(projects.first { $0["title"] as? String == "G" })
        XCTAssertEqual((g["guitars"] as? [String])?.first, "Izq")
        XCTAssertEqual((g["guitars"] as? [String])?.count, 2)
        let s = try XCTUnwrap(projects.first { $0["title"] as? String == "Sin" })
        XCTAssertEqual((s["guitars"] as? [String]) ?? ["x"], [])
        let ok = await call(b, #"{"id":2,"method":"library.reveal","params":{"id":"\#(p.id.uuidString)"}}"#)
        XCTAssertEqual((ok["result"] as? [String: Any])?["revealed"] as? Bool, true)
        XCTAssertEqual(opened.value, "A - G")
        let nf = await call(b, #"{"id":3,"method":"library.reveal","params":{"id":"\#(UUID().uuidString)"}}"#)
        XCTAssertEqual((nf["error"] as? [String: Any])?["code"] as? String, "not-found")
    }

    func testNoProjectsFolder() async throws {
        let support = try tempDir()  // sin profile.json: perfil por defecto, sin carpeta
        let b = try Bridge(options: LaunchOptions(supportDir: support), mediaBase: "m")
        XCTAssertNil(b.mediaFolder)
        let e = await call(b, #"{"id":1,"method":"library.list"}"#)
        XCTAssertEqual((e["error"] as? [String: Any])?["code"] as? String, "no-projects-folder")
    }

    func testProjectsFolderFromProfile() async throws {
        let support = try tempDir()
        let root = try tempDir()
        try ProfileStore(url: support.appendingPathComponent("profile.json")).save(EquipmentProfile(projectsFolder: root))
        let b = try Bridge(options: LaunchOptions(supportDir: support), mediaBase: "m")
        XCTAssertEqual(b.mediaFolder?.standardizedFileURL.path, root.standardizedFileURL.path)
    }
}
