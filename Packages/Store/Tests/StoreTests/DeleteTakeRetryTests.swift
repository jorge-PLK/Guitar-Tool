import Foundation
import XCTest
@testable import Store

/// Paso 8 de la 7c, relevo 10, caso 5: borrado de la carpeta de toma con reintento corto. En NTFS no se borra un
/// fichero con un lector abierto (`MoveFileEx` error 5); el `<video>` de WebView2 o el antivirus lo sueltan tarde.
/// En el Mac se simula esa semántica de forma verificable: el borrador falla mientras este proceso tenga abierto algún
/// descriptor dentro de la carpeta (`F_GETPATH`); en Windows el borrado real ya tiene esa semántica.
final class DeleteTakeRetryTests: XCTestCase {
    /// Rutas abiertas por este proceso dentro de `dir` (Darwin: `F_GETPATH` sobre cada descriptor). Fuera de Darwin
    /// devuelve [] y la semántica la pone el propio sistema de ficheros.
    static func openPaths(under dir: URL) -> [String] {
        #if canImport(Darwin)
        guard let real = realpath(dir.path, nil) else { return [] }
        let prefix = String(cString: real) + "/"
        free(real)
        var out: [String] = []
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        for fd in 0..<getdtablesize() where fcntl(fd, F_GETPATH, &buf) != -1 {
            let p = String(cString: buf)
            if p.hasPrefix(prefix) { out.append(p) }
        }
        return out
        #else
        return []
        #endif
    }

    /// Borrador con la semántica de NTFS: si hay un lector abierto dentro, no toca nada y lanza (error 5).
    static let ntfsLikeRemove: @Sendable (URL) throws -> Void = { url in
        let open = openPaths(under: url)
        guard open.isEmpty else { throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: open[0]]) }
        try FileManager.default.removeItem(at: url)
    }

    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var v: [Double] = []
        func add(_ x: Double) { lock.withLock { v.append(x) } }
        var values: [Double] { lock.withLock { v } }
    }

    func makeTakeDir() throws -> (dir: URL, video: URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("takedel-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let dir = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096).write(to: dir.appendingPathComponent("processed.wav"))
        let video = dir.appendingPathComponent("video.mov")
        try Data(repeating: 2, count: 4096).write(to: video)
        return (dir, video)
    }

    /// El simulador de NTFS es fiel: con un lector abierto falla y no borra; cerrado, borra.
    func testNTFSLikeRemoverRefusesWhileReaderOpen() throws {
        let (dir, video) = try makeTakeDir()
        let reader = try FileHandle(forReadingFrom: video)
        #if canImport(Darwin)
        XCTAssertEqual(Self.openPaths(under: dir).count, 1)
        XCTAssertThrowsError(try Self.ntfsLikeRemove(dir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: video.path))
        #endif
        try reader.close()
        XCTAssertNoThrow(try Self.ntfsLikeRemove(dir))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    /// Tope: 5 intentos, esperas 50+100+200+400 ms = 0,75 s ≤ 1 s; agotados, lanza el último error.
    func testRetryGivesUpWithinBudget() async throws {
        let (dir, _) = try makeTakeDir()
        let waits = Box()
        struct Locked: Error {}
        do {
            try await FileOps.removeRetrying(dir, remove: { _ in throw Locked() }, sleep: { waits.add($0) })
            XCTFail("debió lanzar")
        } catch { XCTAssertTrue(error is Locked) }
        XCTAssertEqual(waits.values.count, FileOps.removeRetryAttempts - 1)
        XCTAssertEqual(waits.values, [0.05, 0.1, 0.2, 0.4])
        XCTAssertEqual(waits.values.reduce(0, +), 0.75, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(waits.values.reduce(0, +), 1.0, "tope total de espera ≤ 1 s")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    /// Si la carpeta ya no existe tras un fallo (otro la borró), se da por hecho sin esperar.
    func testRetryStopsWhenAlreadyGone() async throws {
        let (dir, _) = try makeTakeDir()
        let waits = Box()
        struct Late: Error {}
        let n = try await FileOps.removeRetrying(dir, remove: { url in
            try FileManager.default.removeItem(at: url)
            throw Late()
        }, sleep: { waits.add($0) })
        XCTAssertEqual(n, 1)
        XCTAssertTrue(waits.values.isEmpty)
    }

    /// Un lector (el `<video>`) suelta `video.mov` 150 ms después: el borrado reintenta y acaba antes de 1 s.
    func testRetrySucceedsWhenReaderLetsGoLate() async throws {
        #if canImport(Darwin)
        let (dir, video) = try makeTakeDir()
        let reader = try FileHandle(forReadingFrom: video)
        let t0 = Date()
        let release = Task.detached {
            try? await Task.sleep(nanoseconds: 150_000_000)
            try? reader.close()
        }
        let n = try await FileOps.removeRetrying(dir, remove: Self.ntfsLikeRemove)
        let elapsed = Date().timeIntervalSince(t0)
        await release.value
        XCTAssertGreaterThanOrEqual(n, 2, "el primer intento tuvo que fallar con el lector abierto")
        XCTAssertLessThan(elapsed, 1.0, "borrado con reintento en \(elapsed) s")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        #endif
    }

    // MARK: Library.deleteTake

    func makeProjectWithTake() async throws -> (env: Env, id: UUID, take: UUID, video: URL) {
        let env = try await Env(autoSeparate: false)
        let id = try await env.library.importSong(from: try env.makeSource("a.mp3", content: "A"))
        let layout = ProjectLayout(folder: try env.folder(id))
        var part = RecordingPart(name: "Ritmo", replaces: .rhythm)
        var t = Take()
        part.addTake(t.id)
        t.partID = part.id
        try await env.library.saveTakes(id: id, [t])
        try await env.library.saveRecording(id: id, RecordingState(parts: [part], countIn: false))
        let dir = layout.takeDirectory(takeId: t.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("processed.wav"))
        let video = layout.videoURL(takeId: t.id)
        try Data("v".utf8).write(to: video)
        await env.library.setTakeFolderRemover(Self.ntfsLikeRemove)
        return (env, id, t.id, video)
    }

    func testDeleteTakeWaitsForLateReader() async throws {
        #if canImport(Darwin)
        let (env, id, take, video) = try await makeProjectWithTake()
        let reader = try FileHandle(forReadingFrom: video)
        let release = Task.detached {
            try? await Task.sleep(nanoseconds: 150_000_000)
            try? reader.close()
        }
        let t0 = Date()
        try await env.library.deleteTake(projectID: id, takeID: take)
        let elapsed = Date().timeIntervalSince(t0)
        await release.value
        XCTAssertLessThan(elapsed, 1.0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: video.deletingLastPathComponent().path))
        let saved = try await env.project(id)
        XCTAssertTrue(saved.takes.isEmpty)
        #endif
    }

    /// Lector que no suelta: tras el tope, error y la toma sigue en `project.json` (no se pierde el rastro).
    func testDeleteTakeFailsAfterBudgetAndKeepsTake() async throws {
        #if canImport(Darwin)
        let (env, id, take, video) = try await makeProjectWithTake()
        let reader = try FileHandle(forReadingFrom: video)
        defer { try? reader.close() }
        let t0 = Date()
        do {
            try await env.library.deleteTake(projectID: id, takeID: take)
            XCTFail("debió lanzar")
        } catch {}
        let elapsed = Date().timeIntervalSince(t0)
        XCTAssertGreaterThanOrEqual(elapsed, 0.7, "agotó los reintentos (0,75 s de espera)")
        XCTAssertLessThan(elapsed, 1.5)
        let saved = try await env.project(id)
        XCTAssertEqual(saved.takes.map(\.id), [take])
        #endif
    }
}
