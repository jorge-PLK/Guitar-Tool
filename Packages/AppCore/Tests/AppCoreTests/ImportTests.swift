import Foundation
import Store
import XCTest
@testable import AppCore

// 8.3a: importación por fichero, cola, edición de temas y anfitrión, con servicios simulados (sin modelos).

private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var open = true
    var isOpen: Bool { lock.withLock { open } }
    func set(_ v: Bool) { lock.withLock { open = v } }
}

private struct FakeImporter: AudioImporting {
    func importAudio(from source: URL, to destination: URL, sampleRate: Double,
                     progress: @escaping @Sendable (Double) -> Void) async throws -> ImportedAudioInfo {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "wav".write(to: destination, atomically: true, encoding: .utf8)
        progress(0.5); progress(1)
        return ImportedAudioInfo(title: nil, artist: nil, duration: 10, sourceFormat: source.pathExtension,
                                 sourceSampleRate: 44100, sourceChannels: 2)
    }
    func resample(_ file: URL, to destination: URL, sampleRate: Double) async throws {
        try "stem".write(to: destination, atomically: true, encoding: .utf8)
    }
}

private struct FakeSeparator: StemSeparating {
    let gate: Gate
    var fail = false
    var hang = false
    var modelIdentifier: String? { "fake@1" }
    func separate(input: URL, outputDirectory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        progress(0.25)
        while !gate.isOpen || hang { try await Task.sleep(for: .milliseconds(10)) }
        if fail { throw SeparationFailure(message: "modelo roto") }
        for kind in StemKind.allCases {
            try "stem".write(to: outputDirectory.appendingPathComponent("\(kind.rawValue).wav"), atomically: true, encoding: .utf8)
        }
        progress(1)
    }
}

private struct FakeAnalyzer: StudyAnalyzing {
    func isCurrent(project: Project, layout: ProjectLayout) async -> Bool {
        FileManager.default.fileExists(atPath: layout.analysisCache.path)
    }
    func analyze(project: Project, layout: ProjectLayout) async throws {
        try FileManager.default.createDirectory(at: layout.cacheDir, withIntermediateDirectories: true)
        try "{}".write(to: layout.analysisCache, atomically: true, encoding: .utf8)
    }
}

private struct FakeHost: HostServices {
    var file: URL?
    var folder: URL?
    func pickFile(types: [String]) async -> URL? { file }
    func pickFolder() async -> URL? { folder }
    var many: [URL]?
    func pickFiles(types: [String]) async -> [URL] { many ?? (file.map { [$0] } ?? []) }
    /// Esquemas que «abre» el anfitrión simulado.
    var opens: Set<String> = []
    func openURL(_ url: URL) async -> Bool { opens.contains(url.scheme ?? "") }
}

/// Anfitrión que apunta los avisos de cambio de carpeta (B2).
private final class RemapHost: HostServices, @unchecked Sendable {
    private let lock = NSLock()
    private var _remapped: [URL] = []
    var remapped: [URL] { lock.withLock { _remapped } }
    func pickFile(types: [String]) async -> URL? { nil }
    var folder: URL?
    private var _initials: [URL?] = []
    var initials: [URL?] { lock.withLock { _initials } }
    func pickFolder() async -> URL? { folder }
    func pickFolder(initial: URL?) async -> URL? { lock.withLock { _initials.append(initial) }; return folder }
    func projectsFolderChanged(_ url: URL) async -> Bool { lock.withLock { _remapped.append(url) }; return true }
}

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [String] = []
    func add(_ s: String) { lock.withLock { all.append(s) } }
    var messages: [String] { lock.withLock { all } }
    func named(_ n: String) -> [[String: Any]] {
        messages.compactMap { m in
            guard let o = (try? JSONSerialization.jsonObject(with: Data(m.utf8))) as? [String: Any],
                  o["event"] as? String == n else { return nil }
            return o["payload"] as? [String: Any]
        }
    }
}

private struct Rig {
    let dir: URL
    let projects: URL
    let bridge: Bridge
    let events = Events()
    let gate = Gate()

    init(fail: Bool = false, hang: Bool = false, analyzer: Bool = true, host: FakeHost? = nil) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-import-\(UUID().uuidString)", isDirectory: true)
        projects = dir.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let support = dir.appendingPathComponent("Support", isDirectory: true)
        let services = JobServices(importer: FakeImporter(), separator: FakeSeparator(gate: gate, fail: fail, hang: hang),
                                   levelMeter: nil, analyzer: analyzer ? FakeAnalyzer() : nil, guitarSplitter: nil)
        bridge = try Bridge(options: LaunchOptions(projectsFolder: projects, supportDir: support),
                            mediaBase: "https://tf.media/", reveal: nil, services: services)
        let sink = events
        bridge.send = { sink.add($0) }
        bridge.host = host
    }

    func audioFile(_ name: String = "Song.mp3", content: String = "audio-1") throws -> String {
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func call(_ method: String, _ params: String = "{}") async -> [String: Any] {
        let r = await bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        return (try? JSONSerialization.jsonObject(with: Data(r.utf8))) as? [String: Any] ?? [:]
    }

    func result(_ method: String, _ params: String = "{}") async -> [String: Any] {
        (await call(method, params))["result"] as? [String: Any] ?? [:]
    }

    func importID() async throws -> String {
        let r = await result("import.file", "{\"path\":\(jsonString(try audioFile()))}")
        return try XCTUnwrap(r["id"] as? String)
    }

    func project(_ id: String) async -> [String: Any]? {
        let l = await result("library.list")
        return (l["projects"] as? [[String: Any]])?.first { $0["id"] as? String == id }
    }

    func cleanup() { try? FileManager.default.removeItem(at: dir) }
}

private func eventually(_ timeout: TimeInterval = 8, _ cond: () async -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if await cond() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await cond()
}

final class ImportTests: XCTestCase {
    func testImportSeparatesAndAnalyzes() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        let path = try rig.audioFile("Band - Song.mp3")
        let r = await rig.result("import.file", "{\"path\":\(jsonString(path))}")
        let id = try XCTUnwrap(r["id"] as? String)
        XCTAssertEqual(r["duplicate"] as? Bool, false)
        XCTAssertNotNil(UUID(uuidString: id))

        let done = await eventually { (await rig.project(id))?["hasAnalysis"] as? Bool == true }
        XCTAssertTrue(done)
        let pOpt = await rig.project(id)
        let p = try XCTUnwrap(pOpt)
        XCTAssertEqual(p["separationState"] as? String, "done")
        XCTAssertEqual(p["stemCount"] as? Int, StemKind.allCases.count)
        // Mismo layout que el Mac.
        let folder = rig.projects.appendingPathComponent(p["folderName"] as! String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("project.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("audio/song.wav").path))

        let ended = await eventually { rig.events.named("jobs.progress").contains { $0["stage"] as? String == "analysis" && $0["state"] as? String == "done" } }
        XCTAssertTrue(ended)
        let progress = rig.events.named("jobs.progress")
        let stages = Set(progress.compactMap { $0["stage"] as? String })
        XCTAssertTrue(stages.isSuperset(of: ["import", "separation", "analysis"]), "\(stages)")
        XCTAssertTrue(progress.contains { $0["id"] as? String == id && $0["stage"] as? String == "separation" && $0["state"] as? String == "queued" })
        XCTAssertFalse(rig.events.named("library.changed").isEmpty)
        let list = await rig.result("jobs.list")
        XCTAssertEqual((list["jobs"] as? [Any])?.count, 0)
    }

    func testDuplicateIsNotAnError() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        let path = try rig.audioFile()
        let first = await rig.result("import.file", "{\"path\":\(jsonString(path))}")
        let second = await rig.result("import.file", "{\"path\":\(jsonString(path))}")
        XCTAssertEqual(second["duplicate"] as? Bool, true)
        XCTAssertEqual(second["id"] as? String, first["id"] as? String)
        let l = await rig.result("library.list")
        XCTAssertEqual((l["projects"] as? [Any])?.count, 1)
    }

    func testImportErrors() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        let missing = await rig.call("import.file", "{\"path\":\(jsonString(rig.dir.appendingPathComponent("no.mp3").path))}")
        XCTAssertEqual((missing["error"] as? [String: Any])?["code"] as? String, "not-found")
        let txt = try rig.audioFile("notes.txt")
        let bad = await rig.call("import.file", "{\"path\":\(jsonString(txt))}")
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? String, "unsupported")
        let noParams = await rig.call("import.file", "{}")
        XCTAssertEqual((noParams["error"] as? [String: Any])?["code"] as? String, "bad-params")
    }

    func testLiveStateCancelAndRelaunch() async throws {
        let rig = try Rig(analyzer: false)
        defer { rig.cleanup() }
        rig.gate.set(false)
        let id = try await rig.importID()
        let running = await eventually { (await rig.project(id))?["separationState"] as? String == "running" }
        XCTAssertTrue(running)
        let jobs = (await rig.result("jobs.list"))["jobs"] as? [[String: Any]] ?? []
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs.first?["stage"] as? String, "separation")
        XCTAssertEqual(jobs.first?["id"] as? String, id)
        let fraction = await eventually { (((await rig.result("jobs.list"))["jobs"] as? [[String: Any]])?.first?["fraction"] as? Double) == 0.25 }
        XCTAssertTrue(fraction)

        let c = await rig.result("jobs.cancel", "{\"id\":\"\(id)\"}")
        XCTAssertEqual(c["cancelled"] as? Bool, true)
        let afterCancel = await rig.project(id)
        XCTAssertEqual(afterCancel?["separationState"] as? String, "none")
        XCTAssertTrue(rig.events.named("jobs.progress").contains { $0["state"] as? String == "cancelled" })
        let again = await rig.result("jobs.cancel", "{\"id\":\"\(id)\"}")
        XCTAssertEqual(again["cancelled"] as? Bool, false)

        // Relanzar.
        rig.gate.set(true)
        let q = await rig.result("library.separate", "{\"id\":\"\(id)\"}")
        XCTAssertEqual(q["queued"] as? Bool, true)
        let done = await eventually { (await rig.project(id))?["separationState"] as? String == "done" }
        XCTAssertTrue(done)
        let gone = await rig.call("library.separate", "{\"id\":\"\(UUID().uuidString)\"}")
        XCTAssertEqual((gone["error"] as? [String: Any])?["code"] as? String, "not-found")
    }

    func testFailureIsReported() async throws {
        let rig = try Rig(fail: true, analyzer: false)
        defer { rig.cleanup() }
        let id = try await rig.importID()
        let failed = await eventually { (await rig.project(id))?["separationState"] as? String == "failed" }
        XCTAssertTrue(failed)
        let ev = await eventually { rig.events.named("jobs.progress").contains { $0["state"] as? String == "failed" } }
        XCTAssertTrue(ev)
        let f = rig.events.named("jobs.progress").first { $0["state"] as? String == "failed" }
        XCTAssertEqual(f?["error"] as? String, "modelo roto")
        let detail = await rig.result("library.project", "{\"id\":\"\(id)\"}")
        XCTAssertEqual(detail["separationError"] as? String, "modelo roto")
    }

    func testRenameDeleteAndTrashErrors() async throws {
        let rig = try Rig(analyzer: false)
        defer { rig.cleanup() }
        let id = try await rig.importID()
        _ = await eventually { (await rig.project(id))?["separationState"] as? String == "done" }

        let r = await rig.result("library.rename", "{\"id\":\"\(id)\",\"title\":\"  Nuevo \",\"artist\":\"   \"}")
        XCTAssertEqual(r["title"] as? String, "Nuevo")
        XCTAssertTrue(r["artist"] is NSNull)
        let p = await rig.project(id)
        XCTAssertEqual(p?["title"] as? String, "Nuevo")
        XCTAssertTrue(p?["artist"] == nil || p?["artist"] is NSNull)
        let empty = await rig.call("library.rename", "{\"id\":\"\(id)\",\"title\":\" \",\"artist\":\"X\"}")
        XCTAssertEqual((empty["error"] as? [String: Any])?["code"] as? String, "empty-title")

        let nf = await rig.call("library.trash", "{\"id\":\"\(UUID().uuidString)\"}")
        XCTAssertEqual((nf["error"] as? [String: Any])?["code"] as? String, "not-found")
        let badID = await rig.call("library.delete", "{\"id\":\"x\"}")
        XCTAssertEqual((badID["error"] as? [String: Any])?["code"] as? String, "bad-params")

        let before = rig.events.named("library.changed").count
        let d = await rig.result("library.delete", "{\"id\":\"\(id)\"}")
        XCTAssertEqual(d["removed"] as? Bool, true)
        let gone = await rig.project(id)
        XCTAssertNil(gone)
        XCTAssertGreaterThan(rig.events.named("library.changed").count, before)
        let contents = try FileManager.default.contentsOfDirectory(atPath: rig.projects.path)
        XCTAssertTrue(contents.isEmpty, "\(contents)")
    }

    func testCleanupInfoAndCleanup() async throws {
        let rig = try Rig(analyzer: false)
        defer { rig.cleanup() }
        let id = try await rig.importID()
        _ = await eventually { (await rig.project(id))?["separationState"] as? String == "done" }

        let info = await rig.result("library.cleanupInfo", "{\"id\":\"\(id)\"}")
        let bytes = try XCTUnwrap((info["bytes"] as? NSNumber)?.int64Value)
        XCTAssertGreaterThan(bytes, 0, "los stems de un tema separado son regenerables")
        let done = await rig.result("library.cleanup", "{\"id\":\"\(id)\"}")
        XCTAssertEqual(done["cleaned"] as? Bool, true)
        XCTAssertEqual((done["bytes"] as? NSNumber)?.int64Value, bytes)
        let after = await rig.result("library.cleanupInfo", "{\"id\":\"\(id)\"}")
        XCTAssertEqual((after["bytes"] as? NSNumber)?.int64Value, 0)

        let nf = await rig.call("library.cleanup", "{\"id\":\"\(UUID().uuidString)\"}")
        XCTAssertEqual((nf["error"] as? [String: Any])?["code"] as? String, "not-found")
        let bad = await rig.call("library.cleanupInfo", "{\"id\":\"x\"}")
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? String, "bad-params")
    }

    /// WAV PCM16 mono de `frames` muestras a `rate` Hz (cabecera de 44 bytes).
    private func wav(frames: Int, rate: Int) -> Data {
        func le<T: FixedWidthInteger>(_ v: T) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        var d = Data("RIFF".utf8)
        d.append(contentsOf: le(UInt32(36 + frames * 2))); d.append(Data("WAVEfmt ".utf8))
        d.append(contentsOf: le(UInt32(16)) + le(UInt16(1)) + le(UInt16(1)) + le(UInt32(rate)) + le(UInt32(rate * 2)) + le(UInt16(2)) + le(UInt16(16)))
        d.append(Data("data".utf8)); d.append(contentsOf: le(UInt32(frames * 2)))
        d.append(Data(count: frames * 2))
        return d
    }

    func testTakesDetailAndDeleteTake() async throws {
        let rig = try Rig(analyzer: false)
        defer { rig.cleanup() }
        let id = try await rig.importID()
        _ = await eventually { (await rig.project(id))?["separationState"] as? String == "done" }
        let p0Opt = await rig.project(id)
        let p0 = try XCTUnwrap(p0Opt)
        let folder = rig.projects.appendingPathComponent(p0["folderName"] as! String)
        var project = try ProjectFile.load(folder: folder)
        let layout = ProjectLayout(folder: folder)
        let t1 = Take(id: UUID(), processedFile: "takes/A/processed.wav", partID: nil)
        var t2 = Take(id: UUID(), processedFile: nil)
        t2.punches = [TakePunch(start: 1, end: 2, videoFile: "takes/B/punch.mov")]
        let t1ID = t1.id
        var t1b = t1
        t1b.processedFile = "takes/\(t1ID.uuidString)/processed.wav"
        try FileManager.default.createDirectory(at: layout.takeDirectory(takeId: t1ID), withIntermediateDirectories: true)
        try wav(frames: 90_000, rate: 48_000).write(to: layout.url(relative: t1b.processedFile!))
        project.takes = [t1b, t2]
        project.recording = RecordingState(parts: [RecordingPart(name: "Rítmica", takeIDs: [t1ID, t2.id], bestTakeID: t1ID)])
        try ProjectFile.save(project, to: folder)

        let d = await rig.result("library.project", "{\"id\":\"\(id)\"}")
        let parts = try XCTUnwrap(d["parts"] as? [[String: Any]])
        let takes = try XCTUnwrap(parts.first?["takes"] as? [[String: Any]])
        XCTAssertEqual(takes.count, 2)
        XCTAssertEqual((takes[0]["duration"] as? Double) ?? -1, 1.875, accuracy: 0.001)
        XCTAssertEqual(takes[0]["isBest"] as? Bool, true)
        XCTAssertEqual(takes[0]["hasVideo"] as? Bool, false)
        XCTAssertTrue(takes[1]["duration"] == nil || takes[1]["duration"] is NSNull)
        XCTAssertEqual(takes[1]["hasVideo"] as? Bool, true, "un punch con vídeo cuenta como «Con vídeo»")
        XCTAssertEqual(takes[1]["punchCount"] as? Int, 1)

        let bad = await rig.call("library.deleteTake", "{\"id\":\"\(id)\",\"takeId\":\"x\"}")
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? String, "bad-params")
        let nf = await rig.call("library.deleteTake", "{\"id\":\"\(id)\",\"takeId\":\"\(UUID().uuidString)\"}")
        XCTAssertEqual((nf["error"] as? [String: Any])?["code"] as? String, "not-found")
        let r = await rig.result("library.deleteTake", "{\"id\":\"\(id)\",\"takeId\":\"\(t1ID.uuidString)\"}")
        XCTAssertEqual(r["removed"] as? Bool, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.takeDirectory(takeId: t1ID).path))
        let d2 = await rig.result("library.project", "{\"id\":\"\(id)\"}")
        let left = ((d2["parts"] as? [[String: Any]])?.first?["takes"] as? [[String: Any]]) ?? []
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(left.first?["isBest"] as? Bool, true, "al borrar la mejor se reasigna")
    }

    // MARK: B2: carpeta de proyectos en caliente

    func testRelocateMoveSwitchesFolderWithoutRestart() async throws {
        let host = RemapHost()
        let rig = try Rig(analyzer: false)
        rig.bridge.host = host
        defer { rig.cleanup() }
        let id = try await rig.importID()
        let done = await eventually { (await rig.project(id))?["separationState"] as? String == "done" }
        XCTAssertTrue(done)
        let dest = rig.dir.appendingPathComponent("Nueva", isDirectory: true)
        let r = await rig.result("library.relocate", "{\"path\":\(jsonString(dest.path)),\"mode\":\"move\"}")
        XCTAssertEqual(r["path"] as? String, dest.path)
        XCTAssertEqual(host.remapped.map(\.path), [dest.path])
        // La lista sale ya de la carpeta nueva y el original quedó vacío.
        let still = await rig.project(id)
        XCTAssertNotNil(still)
        XCTAssertEqual(try ProjectScanner.scan(root: dest).found.count, 1)
        XCTAssertEqual(try ProjectScanner.scan(root: rig.projects).found.count, 0)
        XCTAssertEqual(rig.bridge.mediaFolder?.standardizedFileURL.path, dest.standardizedFileURL.path)
        let s = await rig.result("settings.get")
        XCTAssertEqual(s["activeProjectsFolder"] as? String, dest.path)
        XCTAssertEqual(s["projectsFolder"] as? String, dest.path)
        let info = await rig.result("app.info")
        XCTAssertEqual(info["projectsFolder"] as? String, dest.path)
        XCTAssertFalse(rig.events.named("library.relocateProgress").isEmpty)
        // Un tema nuevo se importa en la carpeta nueva.
        let id2 = try await rig.importID()
        let done2 = await eventually { (await rig.project(id2)) != nil }
        XCTAssertTrue(done2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rig.projects.appendingPathComponent("Song").path))
    }

    func testRelocatePointOnlyKeepsOldFiles() async throws {
        let rig = try Rig(analyzer: false)
        defer { rig.cleanup() }
        let id = try await rig.importID()
        let done = await eventually { (await rig.project(id))?["separationState"] as? String == "done" }
        XCTAssertTrue(done)
        let dest = rig.dir.appendingPathComponent("Otra", isDirectory: true)
        _ = await rig.result("library.relocate", "{\"path\":\(jsonString(dest.path)),\"mode\":\"point\"}")
        XCTAssertEqual(try ProjectScanner.scan(root: rig.projects).found.count, 1, "solo apunta: lo viejo se queda")
        let gone = await rig.project(id)
        XCTAssertNil(gone, "la carpeta nueva está vacía")
        XCTAssertEqual(rig.bridge.mediaFolder?.standardizedFileURL.path, dest.standardizedFileURL.path)
    }

    func testRelocateRefusedWhileJobsRun() async throws {
        let rig = try Rig(hang: true, analyzer: false)
        defer { rig.cleanup() }
        let id = try await rig.importID()
        let running = await eventually { (await rig.project(id))?["separationState"] as? String == "running" }
        XCTAssertTrue(running)
        let dest = rig.dir.appendingPathComponent("Nueva", isDirectory: true)
        let e = await rig.call("library.relocate", "{\"path\":\(jsonString(dest.path)),\"mode\":\"move\"}")
        XCTAssertEqual((e["error"] as? [String: Any])?["code"] as? String, "work-in-progress")
        XCTAssertEqual(rig.bridge.mediaFolder?.standardizedFileURL.path, rig.projects.standardizedFileURL.path)
        let bad = await rig.call("library.relocate", "{\"path\":\"x\",\"mode\":\"zip\"}")
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? String, "bad-params")
        await rig.bridge.shutdownAsync()
    }

    /// B2, caso de error: destino con contenido. Se rechaza sin tocar nada y la biblioteca sigue operativa.
    func testRelocateToNonEmptyFolderFailsAndKeepsEverything() async throws {
        let host = RemapHost()
        let rig = try Rig(analyzer: false)
        rig.bridge.host = host
        defer { rig.cleanup() }
        let id = try await rig.importID()
        let done = await eventually { (await rig.project(id))?["separationState"] as? String == "done" }
        XCTAssertTrue(done)
        let dest = rig.dir.appendingPathComponent("Ocupada", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dest.appendingPathComponent("ajeno.txt"))
        let before = await rig.result("settings.get")
        let e = await rig.call("library.relocate", "{\"path\":\(jsonString(dest.path)),\"mode\":\"move\"}")
        XCTAssertNotNil(e["error"], "move a una carpeta no vacía debe fallar: \(e)")
        XCTAssertTrue(host.remapped.isEmpty, "no se remapea el anfitrión si falla")
        XCTAssertEqual(try ProjectScanner.scan(root: rig.projects).found.count, 1, "el original sigue")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dest.path), ["ajeno.txt"], "lo ajeno intacto")
        XCTAssertEqual(rig.bridge.mediaFolder?.standardizedFileURL.path, rig.projects.standardizedFileURL.path)
        let s = await rig.result("settings.get")
        XCTAssertEqual(s["projectsFolder"] as? String, before["projectsFolder"] as? String, "el perfil no cambia")
        let still = await rig.project(id)
        XCTAssertNotNil(still, "la biblioteca sigue sirviendo el tema")
        XCTAssertTrue(rig.events.named("library.relocated").isEmpty)
    }

    // MARK: B3: primer arranque sin reiniciar

    #if os(Windows)
    /// B3: en Windows la propuesta es `<KnownFolder Música>\ToneForge`, no `~\Music`.
    func testDefaultProposedFolderUsesKnownMusicFolderOnWindows() throws {
        // Tools/flutter/pc/common.ps1 pone un USERPROFILE falso (bajo Temp\p9) para SwiftPM y SHGetKnownFolderPath falla con él.
        if windowsMusicFolder() == nil, ProcessInfo.processInfo.environment["USERPROFILE"]?.contains("\\p9\\") == true {
            throw XCTSkip("USERPROFILE falso del arnés del PC (Tools/flutter/pc/common.ps1): sin carpeta Música real")
        }
        let music = try XCTUnwrap(windowsMusicFolder(), "SHGetKnownFolderPath(FOLDERID_Music) falló")
        XCTAssertEqual(Bridge.defaultProposedFolder.standardizedFileURL.path,
                       music.appendingPathComponent("ToneForge", isDirectory: true).standardizedFileURL.path)
        XCTAssertEqual(Bridge.defaultProposedFolder.lastPathComponent, "ToneForge")
    }
    #endif

    /// B3: tras aceptar, un segundo arranque con el mismo `supportDir` ya tiene la carpeta (no hay primer arranque).
    func testSecondLaunchUsesSavedFolderAndDoesNotAskAgain() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-second-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let support = dir.appendingPathComponent("Support", isDirectory: true)
        let chosen = dir.appendingPathComponent("Elegida", isDirectory: true)
        func make() throws -> Bridge {
            let services = JobServices(importer: FakeImporter(), separator: FakeSeparator(gate: Gate(), fail: false, hang: false),
                                       levelMeter: nil, analyzer: nil, guitarSplitter: nil)
            return try Bridge(options: LaunchOptions(projectsFolder: nil, supportDir: support),
                              mediaBase: "https://tf.media/", reveal: nil, services: services)
        }
        func call(_ b: Bridge, _ m: String) async -> [String: Any] {
            let r = await b.router.handle("{\"id\":1,\"method\":\"\(m)\",\"params\":{}}")
            return (try? JSONSerialization.jsonObject(with: Data(r.utf8))) as? [String: Any] ?? [:]
        }
        let first = try make()
        let host = RemapHost()
        host.folder = chosen
        first.host = host
        _ = await call(first, "host.pickProjectsFolder")
        await first.shutdownAsync()

        let second = try make()
        let info = (await call(second, "app.info"))["result"] as? [String: Any]
        XCTAssertEqual(info?["projectsFolder"] as? String, chosen.path)
        let list = await call(second, "library.list")
        XCTAssertNotNil(list["result"], "la biblioteca arranca sola con la carpeta guardada: \(list)")
        await second.shutdownAsync()
    }

    func testFirstRunAdoptsFolderWithoutRestart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-first-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let support = dir.appendingPathComponent("Support", isDirectory: true)
        let chosen = dir.appendingPathComponent("Elegida", isDirectory: true)
        let proposed = dir.appendingPathComponent("Music/ToneForge", isDirectory: true)
        let services = JobServices(importer: FakeImporter(), separator: FakeSeparator(gate: Gate(), fail: false, hang: false),
                                   levelMeter: nil, analyzer: nil, guitarSplitter: nil)
        let bridge = try Bridge(options: LaunchOptions(projectsFolder: nil, supportDir: support),
                                mediaBase: "https://tf.media/", reveal: nil, services: services)
        bridge.proposedFolder = proposed
        let host = RemapHost()
        host.folder = chosen
        bridge.host = host
        func call(_ m: String) async -> [String: Any] {
            let r = await bridge.router.handle("{\"id\":1,\"method\":\"\(m)\",\"params\":{}}")
            return (try? JSONSerialization.jsonObject(with: Data(r.utf8))) as? [String: Any] ?? [:]
        }
        let before = await call("app.info")
        XCTAssertTrue(((before["result"] as? [String: Any])?["projectsFolder"]) is NSNull || (before["result"] as? [String: Any])?["projectsFolder"] == nil)
        let noList = await call("library.list")
        XCTAssertEqual((noList["error"] as? [String: Any])?["code"] as? String, "no-projects-folder")

        let r = (await call("host.pickProjectsFolder"))["result"] as? [String: Any]
        XCTAssertEqual(r?["path"] as? String, chosen.path)
        XCTAssertEqual(r?["restartRequired"] as? Bool, false)
        XCTAssertEqual(host.initials.first??.path, proposed.path, "el selector abre en la propuesta")
        XCTAssertTrue(FileManager.default.fileExists(atPath: proposed.path), "la propuesta se crea antes de abrir el selector")
        XCTAssertEqual(host.remapped.map(\.path), [chosen.path])
        XCTAssertEqual(bridge.mediaFolder?.standardizedFileURL.path, chosen.standardizedFileURL.path)
        let list = await call("library.list")
        XCTAssertNotNil(list["result"], "\(list)")
        let info = (await call("app.info"))["result"] as? [String: Any]
        XCTAssertEqual(info?["projectsFolder"] as? String, chosen.path)
        let profile = try ProfileStore(url: support.appendingPathComponent("profile.json")).load()
        XCTAssertEqual(profile.projectsFolder?.standardizedFileURL.path, chosen.standardizedFileURL.path)
        await bridge.shutdownAsync()
    }

    func testTestPickFolderVariableSkipsDialog() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-envpick-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let support = dir.appendingPathComponent("Support", isDirectory: true)
        let injected = dir.appendingPathComponent("Inyectada", isDirectory: true)
        let services = JobServices(importer: FakeImporter(), separator: FakeSeparator(gate: Gate(), fail: false, hang: false),
                                   levelMeter: nil, analyzer: nil, guitarSplitter: nil)
        func run(env: [String: String]) async throws -> (RemapHost, [String: Any], [String: Any]) {
            let bridge = try Bridge(options: LaunchOptions(projectsFolder: nil, supportDir: support),
                                    mediaBase: "https://tf.media/", reveal: nil, services: services)
            bridge.proposedFolder = dir.appendingPathComponent("Music/ToneForge", isDirectory: true)
            bridge.environment = { env }
            let host = RemapHost()
            host.folder = dir.appendingPathComponent("Dialogo", isDirectory: true)
            bridge.host = host
            func call(_ m: String) async -> [String: Any] {
                let r = await bridge.router.handle("{\"id\":1,\"method\":\"\(m)\",\"params\":{}}")
                return ((try? JSONSerialization.jsonObject(with: Data(r.utf8))) as? [String: Any])?["result"] as? [String: Any] ?? [:]
            }
            let chosen = await call("host.chooseFolder")
            let picked = await call("host.pickProjectsFolder")
            await bridge.shutdownAsync()
            return (host, chosen, picked)
        }
        let (hostEnv, chosenEnv, pickedEnv) = try await run(env: [Bridge.testPickFolderVariable: injected.path])
        XCTAssertEqual(chosenEnv["path"] as? String, injected.path)
        XCTAssertEqual(pickedEnv["path"] as? String, injected.path)
        XCTAssertTrue(hostEnv.initials.isEmpty, "con la variable no se abre el diálogo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: injected.path))
        let profile = try ProfileStore(url: support.appendingPathComponent("profile.json")).load()
        XCTAssertEqual(profile.projectsFolder?.standardizedFileURL.path, injected.standardizedFileURL.path)

        try? FileManager.default.removeItem(at: support)
        let (hostNo, chosenNo, pickedNo) = try await run(env: [:])
        XCTAssertEqual(hostNo.initials.count, 2, "sin la variable se llama al diálogo")
        XCTAssertEqual(chosenNo["path"] as? String, dir.appendingPathComponent("Dialogo").path)
        XCTAssertEqual(pickedNo["path"] as? String, dir.appendingPathComponent("Dialogo").path)
    }

    func testHostMethods() async throws {
        let noHost = try Rig()
        defer { noHost.cleanup() }
        for m in ["host.pickAudioFile", "host.pickAudioFiles", "host.pickProjectsFolder"] {
            let e = await noHost.call(m)
            XCTAssertEqual((e["error"] as? [String: Any])?["code"] as? String, "unsupported", m)
        }

        let chosen = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-folder-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: chosen) }
        let rig = try Rig(host: FakeHost(file: URL(fileURLWithPath: "/x/a.mp3"), folder: chosen))
        defer { rig.cleanup() }
        let f = await rig.result("host.pickAudioFile")
        XCTAssertEqual(f["path"] as? String, "/x/a.mp3")
        let one = await rig.result("host.pickAudioFiles")
        XCTAssertEqual(one["paths"] as? [String], ["/x/a.mp3"])
        var multi = FakeHost(file: nil, folder: nil)
        multi.many = [URL(fileURLWithPath: "/x/a.mp3"), URL(fileURLWithPath: "/x/b.flac")]
        let rigMulti = try Rig(host: multi)
        defer { rigMulti.cleanup() }
        let two = await rigMulti.result("host.pickAudioFiles")
        XCTAssertEqual(two["paths"] as? [String], ["/x/a.mp3", "/x/b.flac"])
        let r = await rig.result("host.pickProjectsFolder")
        XCTAssertEqual(r["path"] as? String, chosen.path)
        XCTAssertEqual(r["restartRequired"] as? Bool, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: chosen.path))
        let profile = try ProfileStore(url: rig.dir.appendingPathComponent("Support/profile.json")).load()
        XCTAssertEqual(profile.projectsFolder?.standardizedFileURL.path, chosen.standardizedFileURL.path)

        let cancelled = try Rig(host: FakeHost(file: nil, folder: nil))
        defer { cancelled.cleanup() }
        let n = await cancelled.result("host.pickProjectsFolder")
        XCTAssertTrue(n["path"] is NSNull)
        XCTAssertEqual(n["restartRequired"] as? Bool, false)
        let nf = await cancelled.result("host.pickAudioFile")
        XCTAssertTrue(nf["path"] is NSNull)
        let none = await cancelled.result("host.pickAudioFiles")
        XCTAssertEqual(none["paths"] as? [String], [])
    }

    func testOpenURLTriesAppThenWeb() async throws {
        let urls = ["spotify:track:abc", "https://open.spotify.com/track/abc"]
        let params = "{\"urls\":[\"spotify:track:abc\",\"https://open.spotify.com/track/abc\"]}"
        var noApp = FakeHost(file: nil, folder: nil)
        noApp.opens = ["https"]
        let rigWeb = try Rig(host: noApp)
        defer { rigWeb.cleanup() }
        let web = await rigWeb.call("host.openURL", params)
        XCTAssertEqual((web["result"] as? [String: Any])?["opened"] as? String, urls[1])

        var app = FakeHost(file: nil, folder: nil)
        app.opens = ["spotify", "https"]
        let rigApp = try Rig(host: app)
        defer { rigApp.cleanup() }
        let first = await rigApp.call("host.openURL", params)
        XCTAssertEqual((first["result"] as? [String: Any])?["opened"] as? String, urls[0])
        let bad = await rigApp.call("host.openURL", "{\"urls\":[\"file:///C:/x\",\"javascript:1\"]}")
        XCTAssertNil((bad["result"] as? [String: Any])?["opened"] as? String)

        let none = try Rig()
        defer { none.cleanup() }
        let e = await none.call("host.openURL", params)
        XCTAssertEqual((e["error"] as? [String: Any])?["code"] as? String, "unsupported")
    }

    func testShutdownCancelsHangingJobsWithinBudget() async throws {
        let rig = try Rig(hang: true, analyzer: false)
        defer { rig.cleanup() }
        let id = try await rig.importID()
        let running = await eventually { (await rig.project(id))?["separationState"] as? String == "running" }
        XCTAssertTrue(running)
        let start = Date()
        await rig.bridge.shutdownAsync()
        XCTAssertLessThan(Date().timeIntervalSince(start), 3.2)
        // Lo guardado en disco sigue `running`: el próximo arranque lo re-encola (como el Mac).
        let state = try ProjectScanner.scan(root: rig.projects).found.first?.project.separation.state
        XCTAssertEqual(state, .running)
        let list = await rig.result("jobs.list")
        XCTAssertEqual((list["jobs"] as? [Any])?.count, 0)
    }

    func testProgressThrottle() {
        let clock = ClockBox()
        let emitted = Counter()
        let engine = JobEngine(root: nil, profileStore: ProfileStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("p.json")),
                               indexURL: nil, services: { fatalError("no se usa") }, now: { clock.value })
        engine.setSinks(job: { _ in emitted.bump() }, changed: {})
        // 10 s simulados, 100 actualizaciones por segundo: como mucho 4 por segundo (+1 de alta).
        for i in 0..<1000 {
            clock.value = Date(timeIntervalSince1970: 1_000 + Double(i) * 0.01)
            engine.update("a", title: "t", stage: "separation", state: "running", fraction: Double(i) / 1000)
        }
        XCTAssertLessThanOrEqual(emitted.count, 4 * 10 + 1)
        XCTAssertGreaterThanOrEqual(emitted.count, 30)
        // Un cambio de etapa sale siempre.
        let before = emitted.count
        engine.update("a", title: "t", stage: "analysis", state: "queued")
        XCTAssertEqual(emitted.count, before + 1)
        engine.update("a", title: "t", stage: "analysis", state: "done")
        XCTAssertEqual(emitted.count, before + 2)
        XCTAssertTrue(engine.list().isEmpty)
    }

    func testOverlayMarksQueuedAndRunning() {
        let engine = JobEngine(root: nil, profileStore: ProfileStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("p.json")),
                               indexURL: nil, services: { fatalError("no se usa") })
        let id = UUID()
        func summary(_ state: String) -> ProjectSummary {
            ProjectSummary(id: id, title: "t", artist: nil, folderName: "t", duration: 1, sampleRate: 44100, cover: nil,
                           createdAt: Date(), updatedAt: Date(), separationState: state, stemCount: 0, takeCount: 0,
                           rigCount: 0, hasAnalysis: false, origin: nil, guitars: [])
        }
        let list = LibraryListResult(projects: [summary("done")], skipped: [])
        XCTAssertEqual(engine.overlay(list).projects[0].separationState, "done")
        engine.update(id.uuidString, title: "t", stage: "analysis", state: "queued")
        XCTAssertEqual(engine.overlay(list).projects[0].separationState, "queued")
        engine.update(id.uuidString, title: "t", stage: "analysis", state: "running")
        XCTAssertEqual(engine.overlay(list).projects[0].separationState, "running")
    }

    func testModelAndHelperLocation() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("appcore-models-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appendingPathComponent("beat_this")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertNil(ModelResolver.developmentModel(folder: "beat_this", environment: [:]))
        XCTAssertNil(ModelResolver.developmentModel(folder: "beat_this", environment: ["TF_MODELS_DIR": dir.path]))
        try "x".write(to: folder.appendingPathComponent("model.onnx"), atomically: true, encoding: .utf8)
        let found = ModelResolver.developmentModel(folder: "beat_this", environment: ["TF_MODELS_DIR": dir.path])
        XCTAssertNotNil(found, "TF_MODELS_DIR=\(dir.path) model=\(folder.appendingPathComponent("model.onnx").path) existe=\(FileManager.default.fileExists(atPath: folder.appendingPathComponent("model.onnx").path))")
        XCTAssertEqual(ModelResolver.separatorFolders(physicalMemory: 8 << 30), ["bs_roformer"])
        XCTAssertEqual(ModelResolver.separatorFolders(physicalMemory: 32 << 30), ["bs_roformer"], "T575 desactivado")

        let exe = dir.appendingPathComponent(HelperLocator.helperFileName)
        XCTAssertNil(HelperLocator.separateHelper(environment: [:], executableDirectory: dir))
        try "#!/bin/sh\n".write(to: exe, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: exe.path, isDirectory: &isDir)
        let info = "buscado=\(exe.path) existe=\(exists) esDir=\(isDir.boolValue) isExecutable=\(FileManager.default.isExecutableFile(atPath: exe.path)) isHelper=\(HelperLocator.isHelper(atPath: exe.path))"
        XCTAssertEqual(HelperLocator.separateHelper(environment: [:], executableDirectory: dir)?.lastPathComponent,
                       HelperLocator.helperFileName, info)
        let viaEnv = HelperLocator.separateHelper(environment: ["TF_SEPARATE": exe.path], executableDirectory: nil)
        XCTAssertEqual(viaEnv?.standardizedFileURL.path, exe.standardizedFileURL.path, info)
    }
}

private final class ClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _v = Date(timeIntervalSince1970: 1_000)
    var value: Date {
        get { lock.withLock { _v } }
        set { lock.withLock { _v = newValue } }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.withLock { n += 1 } }
    var count: Int { lock.withLock { n } }
}

private func jsonString(_ s: String) -> String {
    let d = (try? JSONEncoder().encode(s)) ?? Data()
    return String(decoding: d, as: UTF8.self)
}
