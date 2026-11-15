import XCTest
@testable import Store

final class OriginTests: XCTestCase {
    private func makeOrigin(videoID: String? = "abc123") -> SongOrigin {
        SongOrigin(kind: .youtube, url: "https://youtu.be/abc123", videoID: videoID, channel: "Canal",
                   album: "Disco", codec: "opus", ytDlpVersion: "2026.01.01",
                   importedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testOriginRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("origin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var origin = makeOrigin()
        origin.artwork = ProjectLayout.coverRelativePath
        let song = Song(title: "T", source: "source/original.opus", sourceSHA256: "x", sourceFormat: "opus",
                        sourceSampleRate: 48000, sourceChannels: 2, sampleRate: 44100, duration: 10, origin: origin)
        let project = Project(song: song)
        try ProjectFile.save(project, to: dir)
        let loaded = try ProjectFile.load(folder: dir)
        XCTAssertEqual(loaded.song.origin, origin)
        XCTAssertEqual(loaded.schemaVersion, 2)
    }

    func testProjectWithoutOriginStillLoads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("origin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let song = Song(title: "T", source: "source/original.mp3", sourceSHA256: "x", sourceFormat: "mp3",
                        sourceSampleRate: 44100, sourceChannels: 2, sampleRate: 44100, duration: 10)
        try ProjectFile.save(Project(song: song), to: dir)
        let loaded = try ProjectFile.load(folder: dir)
        XCTAssertNil(loaded.song.origin)
        let json = try String(contentsOf: ProjectLayout(folder: dir).projectFile, encoding: .utf8)
        XCTAssertFalse(json.contains("\"origin\""), "sin origen no se escribe la clave")
        XCTAssertEqual(loaded.schemaVersion, 2)
    }

    func testImportWithMetadataUsesTitleArtistAndCopiesCover() async throws {
        let env = try await Env(autoSeparate: false)
        await env.importer.setMeta(title: "DeFichero", artist: "OtroArtista")
        let cover = try env.makeSource("cover-src.jpg", content: "JPEG")
        let meta = ImportMetadata(title: "Titulo Real", artist: "Artista Real", origin: makeOrigin(), artworkFile: cover)
        let id = try await env.library.importSong(from: try env.makeSource("descarga.opus", content: "A"), metadata: meta)
        let p = try await env.project(id)
        XCTAssertEqual(p.song.title, "Titulo Real")
        XCTAssertEqual(p.song.artist, "Artista Real")
        XCTAssertEqual(p.song.source, "source/original.opus")
        XCTAssertEqual(p.song.origin?.artwork, "source/cover.jpg")
        XCTAssertEqual(p.song.origin?.videoID, "abc123")
        let folder = try XCTUnwrap(ProjectScanner.scan(root: env.root).found.first { $0.project.id == id }?.folder)
        let layout = ProjectLayout(folder: folder)
        XCTAssertEqual(try String(contentsOf: layout.coverFile, encoding: .utf8), "JPEG")
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.url(relative: p.song.source).path))
    }

    func testPlaylistFieldsRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("origin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var origin = makeOrigin()
        origin.playlistID = "PL123"
        origin.playlistName = "Mi lista"
        let song = Song(title: "T", source: "source/original.opus", sourceSHA256: "x", sourceFormat: "opus",
                        sourceSampleRate: 48000, sourceChannels: 2, sampleRate: 44100, duration: 10, origin: origin)
        try ProjectFile.save(Project(song: song), to: dir)
        let loaded = try ProjectFile.load(folder: dir)
        XCTAssertEqual(loaded.song.origin?.playlistID, "PL123")
        XCTAssertEqual(loaded.song.origin?.playlistName, "Mi lista")
        XCTAssertEqual(loaded.schemaVersion, 2)
    }

    func testOriginWithoutPlaylistFieldsDoesNotWriteKeys() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("origin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let song = Song(title: "T", source: "source/original.opus", sourceSHA256: "x", sourceFormat: "opus",
                        sourceSampleRate: 48000, sourceChannels: 2, sampleRate: 44100, duration: 10, origin: makeOrigin())
        try ProjectFile.save(Project(song: song), to: dir)
        let json = try String(contentsOf: ProjectLayout(folder: dir).projectFile, encoding: .utf8)
        XCTAssertFalse(json.contains("playlistID"))
        XCTAssertFalse(json.contains("playlistName"))
        let loaded = try ProjectFile.load(folder: dir)
        XCTAssertNil(loaded.song.origin?.playlistID)
        XCTAssertNil(loaded.song.origin?.playlistName)
        XCTAssertEqual(loaded.song.origin, makeOrigin())
    }

    func testProjectBySpotifyID() async throws {
        let env = try await Env(autoSeparate: false)
        let none = await env.library.project(withSpotifyID: "sp1")
        XCTAssertNil(none)
        let origin = SongOrigin(kind: .spotify, url: "https://open.spotify.com/track/sp1", spotifyID: "sp1",
                                importedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let id = try await env.library.importSong(from: try env.makeSource("s.opus", content: "S"),
                                                  metadata: ImportMetadata(origin: origin))
        let found = await env.library.project(withSpotifyID: "sp1")
        XCTAssertEqual(found?.id, id)
        let other = await env.library.project(withSpotifyID: "otro")
        XCTAssertNil(other)
    }

    func testDuplicateByVideoID() async throws {
        let env = try await Env(autoSeparate: false)
        let none = await env.library.project(withVideoID: "abc123")
        XCTAssertNil(none)
        let first = try await env.library.importSong(from: try env.makeSource("a.opus", content: "A"),
                                                     metadata: ImportMetadata(origin: makeOrigin()))
        let found = await env.library.project(withVideoID: "abc123")
        XCTAssertEqual(found?.id, first)
        do {
            // Contenido distinto: solo el videoID lo delata.
            _ = try await env.library.importSong(from: try env.makeSource("b.opus", content: "B"),
                                                 metadata: ImportMetadata(origin: makeOrigin()))
            XCTFail("debía lanzar duplicate")
        } catch {
            XCTAssertEqual(error as? LibraryError, .duplicate(first))
        }
        XCTAssertEqual(ProjectScanner.scan(root: env.root).found.count, 1)
    }
}
