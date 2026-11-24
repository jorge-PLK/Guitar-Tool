import Foundation
import Store
import XCTest
@testable import AppCore

/// Área `library` de `Contract/fixtures/` (ver `FixtureRig.swift`). Tres bancos: el principal (sin trabajo vivo), uno con una
/// separación en cola para `library.separate` y el error `work-in-progress`, y uno para el `library.relocate` que sale bien.
/// Ficheros con sufijo (`.noId`, `.null`) cubren la segunda variante de un método que tiene un solo nombre de fichero.
@MainActor
final class ContractFixturesLibraryTests: XCTestCase {
    private final class FakePhotos: ArtistPhotoProviding, @unchecked Sendable {
        let file: URL
        init(file: URL) { self.file = file }
        func photo(for name: String) async -> URL? { name == "Banda" ? file : nil }
    }

    /// Banco con su propio `Bridge` (el del `FixtureRig` abriría el explorador real en `library.reveal` y no tiene fotos).
    @MainActor private struct Bank {
        let rig: FixtureRig
        let bridge: Bridge

        init(photo: URL? = nil) throws {
            rig = try FixtureRig(area: "library")
            let services = JobServices(importer: FixtureImporter(), separator: FixtureSeparator(gate: FixtureGate()),
                                       levelMeter: nil, analyzer: nil, guitarSplitter: nil)
            bridge = try Bridge(
                options: LaunchOptions(projectsFolder: rig.projects, supportDir: rig.dir.appendingPathComponent("Support2")),
                mediaBase: "https://tf.media/", reveal: { _ in }, services: services,
                artistPhotos: photo.map { FakePhotos(file: $0) })
        }

        func raw(_ method: String, _ params: String) async throws -> [String: Any] {
            let r = await bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
        }

        /// Claves ordenadas ANTES de normalizar: el normalizador numera los UUID por orden de aparición y el orden de claves
        /// de `JSONSerialization` varía entre ejecuciones (con muchos UUID anidados saldrían numeraciones distintas).
        static func sorted(_ json: String) throws -> String {
            let v = try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
            let d = try JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
            return String(decoding: d, as: UTF8.self)
        }

        /// Valores que dependen de la máquina, sustituidos por otros fijos antes del golden:
        /// - `library.usage`: los tamaños son bloques asignados (APFS); cada `bytes` pasa a 1000·(posición+1), cada
        ///   `regenerableBytes` no nulo a 100 y los totales se recalculan como suma (se conserva la coherencia).
        /// - `library.list`: `skipped[].reason` lleva el texto de un `DecodingError` de Foundation (cambia entre versiones).
        static let skippedReason = "Unreadable project.json"
        static func stabilize(_ method: String, _ result: Any) -> Any {
            guard var o = result as? [String: Any] else { return result }
            if method == "library.usage", var ps = o["projects"] as? [[String: Any]] {
                var total = 0, regen = 0
                for i in ps.indices {
                    let b = 1000 * (i + 1)
                    let r = ((ps[i]["regenerableBytes"] as? Int) ?? 0) > 0 ? 100 : 0
                    ps[i]["bytes"] = b
                    ps[i]["regenerableBytes"] = r
                    total += b; regen += r
                }
                o["projects"] = ps
                o["totalBytes"] = total
                o["regenerableBytes"] = regen
            }
            if method == "library.list", var sk = o["skipped"] as? [[String: Any]] {
                for i in sk.indices { sk[i]["reason"] = skippedReason }
                o["skipped"] = sk
            }
            return o
        }

        @discardableResult
        func run(_ method: String, _ params: String = "{}", name: String? = nil,
                 file: StaticString = #filePath, line: UInt = #line) async throws -> [String: Any] {
            let o = try await raw(method, params)
            let n = name ?? method
            try rig.golden(n, .params, try Self.sorted(params), file: file, line: line)
            if let e = o["error"] {
                try rig.golden(n, .error, try Self.sorted(try FixtureRig.text(e)), file: file, line: line)
            } else {
                try rig.golden(n, .result, try Self.sorted(try FixtureRig.text(Self.stabilize(method, try XCTUnwrap(o["result"])))), file: file, line: line)
            }
            return o
        }

        func expectError(_ method: String, _ params: String, file: StaticString = #filePath, line: UInt = #line) async throws {
            let o = try await raw(method, params)
            let e = try XCTUnwrap(o["error"], "\(method) debía fallar", file: file, line: line)
            try rig.golden(method, .error, try FixtureRig.text(e), file: file, line: line)
        }

        /// Crea un tema en disco (con su fuente) y devuelve el proyecto.
        @discardableResult
        func seed(_ title: String, artist: String?, state: SeparationState, name: String? = nil,
                  stems: Bool = false, edit: (inout Project) -> Void = { _ in }) throws -> Project {
            var p = Project(song: Song(title: title, artist: artist, source: "source/original.wav", sourceSHA256: "abc",
                                       sourceFormat: "wav", sourceSampleRate: 44100, sourceChannels: 2,
                                       sampleRate: 44100, duration: 10))
            p.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
            p.updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
            p.separation = state
            if stems { p.stems = [Stem(kind: .bass, file: "stems/bass.wav"), Stem(kind: .drums, file: "stems/drums.wav", isEmpty: true)] }
            edit(&p)
            let folder = rig.projects.appendingPathComponent(name ?? "\(artist.map { $0 + " - " } ?? "")\(title)", isDirectory: true)
            let layout = ProjectLayout(folder: folder)
            try layout.createSkeleton()
            try "wav".write(to: layout.url(relative: "source/original.wav"), atomically: true, encoding: .utf8)
            if stems { try StudyTests.writeSine(layout.stemURL(.bass), frequency: 110, seconds: 1) }
            try ProjectFile.save(p, to: folder)
            return p
        }
    }

    private func q(_ s: String) -> String { String(decoding: (try? JSONEncoder().encode(s)) ?? Data(), as: UTF8.self) }

    func testLibraryArea() async throws {
        // Foto pequeña (firma JPEG) fuera de la carpeta de proyectos.
        let photoDir = FileManager.default.temporaryDirectory.appendingPathComponent("lib-photo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: photoDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: photoDir) }
        let photo = photoDir.appendingPathComponent("banda.img")
        try Data([0xFF, 0xD8, 0xFF, 0x01, 0x02]).write(to: photo)

        let bank = try Bank(photo: photo)
        defer { bank.rig.cleanup() }

        // Temas: los cinco estados de separación, uno sin artista y uno con detalle completo (partes y tomas).
        try bank.seed("Alfa", artist: "Banda", state: SeparationState(state: .none))
        try bank.seed("Bravo", artist: "Banda", state: SeparationState(state: .queued))
        try bank.seed("Charlie", artist: nil, state: SeparationState(state: .running))
        try bank.seed("Eco", artist: "Banda", state: SeparationState(state: .failed, model: "fake@1", error: "Fallo de memoria al separar."))
        // Tomas del detalle: dos partes; la primera con tres tomas (mejor, con vídeo y punches, y sin audio → sin duración).
        let t1 = Take(id: UUID(), processedFile: nil, createdAt: Date(timeIntervalSince1970: 1_700_000_200))
        let t2 = Take(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_700_000_300))
        let t3 = Take(id: UUID(), discarded: true, createdAt: Date(timeIntervalSince1970: 1_700_000_400))
        let t4 = Take(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_700_000_500))
        let delta = try bank.seed("Delta", artist: "Banda", state: SeparationState(state: .done, model: "fake@1"), stems: true) { p in
            func rel(_ t: Take, _ f: String) -> String { "takes/\(t.id.uuidString)/\(f)" }
            var a = t1, b = t2, c = t3, d = t4
            a.partID = nil
            b.processedFile = rel(b, "processed.wav")
            b.songStart = 2
            b.videoFile = rel(b, "video.mov")
            b.punches = [TakePunch(start: 3, end: 4, processedFile: nil, videoFile: rel(b, "punch1.mov"), videoOffset: 0.05)]
            c.processedFile = rel(c, "processed.wav")
            c.songStart = 0
            d.processedFile = rel(d, "processed.wav")
            d.songStart = 5
            p.takes = [a, b, c, d]
            p.recording = RecordingState(parts: [
                RecordingPart(name: "Rítmica", takeIDs: [a.id, b.id, c.id], bestTakeID: b.id),
                RecordingPart(name: "Solo", replaces: .lead, takeIDs: [d.id], bestTakeID: d.id),
            ])
        }
        let deltaFolder = bank.rig.projects.appendingPathComponent("Banda - Delta", isDirectory: true)
        let dl = ProjectLayout(folder: deltaFolder)
        for t in [t2, t3, t4] {
            let url = dl.url(relative: "takes/\(t.id.uuidString)/processed.wav")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try StudyTests.writeSine(url, frequency: 220, seconds: 1)
        }
        // Temas para borrar y un directorio con un project.json roto (sale en `skipped`).
        let trash = try bank.seed("Papelera", artist: "Banda", state: SeparationState(state: .none))
        let purge = try bank.seed("Borrar", artist: "Banda", state: SeparationState(state: .none))
        let broken = bank.rig.projects.appendingPathComponent("Rota", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try "no es json".write(to: broken.appendingPathComponent("project.json"), atomically: true, encoding: .utf8)

        let id = delta.id.uuidString
        let idParams = "{\"id\":\(q(id))}"

        try await bank.run("library.list")
        try await bank.run("library.project", idParams)
        try await bank.run("library.reveal", idParams)
        try await bank.run("library.rename", "{\"id\":\(q(id)),\"title\":\"Delta bis\",\"artist\":\"Banda\"}")
        try await bank.expectError("library.rename", "{\"id\":\(q(id)),\"title\":\"   \"}")

        try await bank.run("library.cleanupInfo", idParams)
        try await bank.run("library.cleanupInfo", "{\"id\":null}", name: "library.cleanupInfo.noId")
        try await bank.run("library.cleanup", idParams)
        try await bank.run("library.usage")

        // Marcar mejor: la tercera toma de la primera parte (`t1`, la que no tiene audio).
        try await bank.run("library.markBest", "{\"id\":\(q(id)),\"takeId\":\(q(t1.id.uuidString))}")
        try await bank.run("library.deleteTake", "{\"id\":\(q(id)),\"takeId\":\(q(t3.id.uuidString))}")

        try await bank.run("library.artistPhoto", "{\"name\":\"Banda\"}")
        try await bank.run("library.artistPhoto", "{\"name\":\"Desconocido\"}", name: "library.artistPhoto.null")

        // Papelera real: solo al regenerar (así las pasadas de comparación no llenan la Papelera del Mac).
        if ProcessInfo.processInfo.environment["TF_WRITE_FIXTURES"] == "1" {
            try await bank.run("library.trash", "{\"id\":\(q(trash.id.uuidString))}")
        } else {
            try bank.rig.golden("library.trash", .params, "{\"id\":\(q(trash.id.uuidString))}")
        }
        try await bank.expectError("library.trash", "{\"id\":\"00000000-0000-0000-0000-0000000000AA\"}")
        try await bank.run("library.delete", "{\"id\":\(q(purge.id.uuidString))}")

        // Eventos con el codificador real.
        try bank.rig.event("library.changed", Empty())
        try bank.rig.event("library.relocateProgress", RelocateProgress(fraction: 0.5))
        let moved = bank.rig.dir.appendingPathComponent("Moved").path
        try bank.rig.event("library.relocated", RelocateResult(path: moved, mediaRemapped: true))

        // Separar (cola viva) y, con trabajo en curso, `library.relocate` se rechaza.
        let busy = try Bank()
        defer { busy.rig.cleanup() }
        let alfa = try busy.seed("Alfa", artist: "Banda", state: SeparationState(state: .none))
        try await busy.run("library.separate", "{\"id\":\(q(alfa.id.uuidString))}")
        let dest = busy.rig.dir.appendingPathComponent("Moved", isDirectory: true)
        try await busy.expectError("library.relocate", "{\"path\":\(q(dest.path)),\"mode\":\"move\"}")

        // Mover la carpeta (sin trabajo en curso).
        let free = try Bank()
        defer { free.rig.cleanup() }
        try free.seed("Alfa", artist: "Banda", state: SeparationState(state: .none))
        let target = free.rig.dir.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try await free.run("library.relocate", "{\"path\":\(q(target.path)),\"mode\":\"move\"}")
    }
}
