import XCTest
@testable import AppCore

/// B4: `library.artistPhoto` (el Mac usa `ArtistPhotoService` desde `ArtistGrid`).
final class ArtistPhotoTests: XCTestCase {
    private final class FakePhotos: ArtistPhotoProviding, @unchecked Sendable {
        let lock = NSLock()
        var files: [String: URL] = [:]
        var asked: [String] = []
        func photo(for name: String) async -> URL? { lock.withLock { asked.append(name); return files[name] } }
    }

    private func rig(_ photos: FakePhotos) throws -> (Bridge, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-photo-\(UUID().uuidString)", isDirectory: true)
        let projects = dir.appendingPathComponent("P", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let bridge = try Bridge(options: LaunchOptions(projectsFolder: projects, supportDir: dir.appendingPathComponent("S")),
                                mediaBase: "https://tf.media/", reveal: nil, artistPhotos: photos)
        return (bridge, dir)
    }

    private func photo(_ bridge: Bridge, _ name: String) async -> Any? {
        let params = String(data: try! JSONEncoder().encode(ArtistPhotoParams(name: name)), encoding: .utf8)!
        let r = await bridge.router.handle("{\"id\":1,\"method\":\"library.artistPhoto\",\"params\":\(params)}")
        let o = (try? JSONSerialization.jsonObject(with: Data(r.utf8))) as? [String: Any]
        return (o?["result"] as? [String: Any])?["photo"]
    }

    func testPhotoComesAsDataURLAndMissingIsNull() async throws {
        let fake = FakePhotos()
        let (bridge, dir) = try rig(fake)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("metallica.img")
        try Data([0xFF, 0xD8, 0xFF, 0x01, 0x02]).write(to: file)
        fake.files["Metallica"] = file
        let hit = await photo(bridge, "  Metallica ")
        XCTAssertEqual(hit as? String, "data:image/jpeg;base64,\(Data([0xFF, 0xD8, 0xFF, 0x01, 0x02]).base64EncodedString())")
        XCTAssertEqual(fake.asked, ["Metallica"], "el nombre se recorta")
        let none = await photo(bridge, "Desconocido")
        XCTAssertTrue(none is NSNull, "sin foto: la página pinta iniciales")
        let empty = await photo(bridge, "   ")
        XCTAssertTrue(empty is NSNull)
        XCTAssertEqual(fake.asked.count, 2, "un nombre vacío no consulta")
    }

    func testImageMimeBySignature() {
        XCTAssertEqual(Bridge.imageMime(Data([0x89, 0x50, 0x4E, 0x47, 0])), "image/png")
        XCTAssertEqual(Bridge.imageMime(Data([0x52, 0x49, 0x46, 0x46, 0])), "image/webp")
        XCTAssertEqual(Bridge.imageMime(Data([0xFF, 0xD8])), "image/jpeg")
    }
}
