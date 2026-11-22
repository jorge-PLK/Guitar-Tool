import Foundation
import Store
import VideoKit
import XCTest
@testable import AppCore

/// Paso 8 de la 7c, relevo 10, casos 2 y 3: borrar una toma que alguien tiene abierta. En NTFS no se borra un fichero
/// con un lector abierto (`MoveFileEx` error 5). En el Mac se comprueba de forma verificable: justo antes de borrar
/// (gancho `willDeleteTake`, lo último antes de `Library.deleteTake`) no puede quedar ningún descriptor de este proceso
/// dentro de la carpeta de la toma (`F_GETPATH`). En Windows el propio borrado falla si queda uno.
extension RecordTests {
    /// Rutas abiertas por este proceso dentro de `dir` (Darwin: `F_GETPATH` por descriptor; fuera de Darwin, []).
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

    final class OpenAtDelete: @unchecked Sendable {
        private let lock = NSLock()
        private var v: [String]?
        func set(_ x: [String]) { lock.withLock { v = x } }
        var value: [String]? { lock.withLock { v } }
    }

    /// Rig sin cámara con una sección de 1 s; graba una toma en la parte activa y devuelve su id.
    func rigWithOneTake() async throws -> (Rig, UUID) {
        let sec = Section(name: "Estrofa", start: 0, end: 1.0)
        let r = try await makeRig(sections: [sec], cameras: .simulated(provider: SimulatedCameraProvider(cameras: [])))
        Bridge.wireOffsetSheet(record: r.svc, takeView: r.bridge.takeViewService)
        _ = try await openRecord(r, camera: "none")
        _ = try await snap(r, "record.setPreRoll", "{\"bars\":0}")
        _ = try await snap(r, "record.setStartSection", "{\"sectionId\":\"\(sec.id.uuidString)\"}")
        _ = try await snap(r, "record.start")
        let s = try await until(r, timeout: 8) { $0.phase == "idle" && ($0.parts.first?.takes.count ?? 0) == 1 }
        return (r, try XCTUnwrap(UUID(uuidString: try XCTUnwrap(s.parts.first?.takes.first?.id))))
    }

    /// Envuelve el gancho de antes de borrar para anotar qué queda abierto dentro de la carpeta de la toma.
    func watchOpenFilesAtDelete(_ r: Rig, _ takeID: UUID) -> OpenAtDelete {
        let seen = OpenAtDelete()
        let dir = r.layout.takeDirectory(takeId: takeID)
        let original = r.svc.willDeleteTake
        r.svc.willDeleteTake = { id in
            await original?(id)
            seen.set(Self.openPaths(under: dir))
        }
        return seen
    }

    /// Caso 3: la toma es la mejor de la primera parte y suena como «Tú · Guitarra» mientras se graba la segunda.
    /// Grabar suelta esa pista antes de borrar (`reloadTakeTracks(excluding:)`).
    func testDeleteTakeOpenAsTakeChannelReleasesReaderFirst() async throws {
        let (r, takeID) = try await rigWithOneTake()
        var s = try await snap(r, "record.addPart", "{\"name\":\"Solo\",\"replaces\":\"lead\"}")
        XCTAssertEqual(s.mix.takeChannels.map(\.name), ["Tú · Guitarra"])
        let dir = r.layout.takeDirectory(takeId: takeID)
        #if canImport(Darwin)
        XCTAssertFalse(Self.openPaths(under: dir).isEmpty, "precondición: el reproductor de Grabar tiene abierta la toma")
        #endif
        let seen = watchOpenFilesAtDelete(r, takeID)
        s = try await snap(r, "record.deleteTake", "{\"takeId\":\"\(takeID.uuidString)\"}")
        XCTAssertEqual(seen.value, [], "lectores abiertos al borrar: \(seen.value ?? ["(no se llegó a borrar)"])")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        XCTAssertEqual(s.mix.takeChannels.count, 0)
        XCTAssertTrue(s.messages.isEmpty, "\(s.messages)")
    }

    /// Caso 2: «Eliminar toma» desde el visor. La página manda `record.deleteTake` sin esperar a `takeview.close`;
    /// el núcleo cierra el visor de esa toma antes de borrar.
    func testDeleteTakeWithViewerOpenClosesViewerFirst() async throws {
        let (r, takeID) = try await rigWithOneTake()
        let pid = try r.project.id.uuidString
        _ = await call(r.router, "record.prepareViewTake")
        _ = try await takeView(r, "takeview.open", "{\"projectId\":\"\(pid)\",\"takeId\":\"\(takeID.uuidString)\"}")
        XCTAssertEqual(r.bridge.takeViewService.current?.takeId, takeID)
        let dir = r.layout.takeDirectory(takeId: takeID)
        #if canImport(Darwin)
        XCTAssertFalse(Self.openPaths(under: dir).isEmpty, "precondición: el visor tiene abierta la toma")
        #endif
        let seen = watchOpenFilesAtDelete(r, takeID)
        let s = try await snap(r, "record.deleteTake", "{\"takeId\":\"\(takeID.uuidString)\"}")
        XCTAssertEqual(seen.value, [], "lectores abiertos al borrar: \(seen.value ?? ["(no se llegó a borrar)"])")
        XCTAssertNil(r.bridge.takeViewService.current, "el visor de la toma borrada queda cerrado")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        XCTAssertTrue(s.parts.first?.takes.isEmpty ?? false)
        // El `takeview.close` tardío de la página no falla.
        _ = try await takeView(r, "takeview.close")
    }

    /// El visor abierto en OTRA toma no se cierra al borrar una distinta.
    func testDeleteTakeKeepsViewerOfAnotherTake() async throws {
        let (r, first) = try await rigWithOneTake()
        _ = try await snap(r, "record.start")
        let s = try await until(r, timeout: 8) { $0.phase == "idle" && ($0.parts.first?.takes.count ?? 0) == 2 }
        let second = try XCTUnwrap(s.parts.first?.takes.map(\.id).first { $0 != first.uuidString })
        let pid = try r.project.id.uuidString
        _ = await call(r.router, "record.prepareViewTake")
        _ = try await takeView(r, "takeview.open", "{\"projectId\":\"\(pid)\",\"takeId\":\"\(second)\"}")
        _ = try await snap(r, "record.deleteTake", "{\"takeId\":\"\(first.uuidString)\"}")
        XCTAssertEqual(r.bridge.takeViewService.current?.takeId.uuidString, second)
        _ = try await takeView(r, "takeview.close")
    }
}
