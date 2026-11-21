import Foundation
import Store
import XCTest
@testable import AppCore

/// Backing (8.5): todo en modo `--audio simulated` (nunca se abre un dispositivo real) y con proyectos temporales.
@MainActor
final class StudyTests: XCTestCase {
    final class Events: @unchecked Sendable {
        struct Item { var time: Double; var name: String; var payload: [String: Any] }
        private let lock = NSLock()
        private var items: [Item] = []
        func add(_ json: String) {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
                  let name = o["event"] as? String else { return }
            let item = Item(time: ProcessInfo.processInfo.systemUptime, name: name, payload: o["payload"] as? [String: Any] ?? [:])
            lock.withLock { items.append(item) }
        }
        func all(_ name: String) -> [Item] { lock.withLock { items.filter { $0.name == name } } }
        func clear() { lock.withLock { items = [] } }
    }

    struct Fixture {
        var root: URL
        var support: URL
        var folder: URL
        var project: Project
        var bridge: Bridge
        var events: Events
    }

    static let sampleRate = 44100.0
    static let seconds = 8.0

    /// WAV PCM 16 bits estéreo con un seno (generado aquí: sin audios en el repo).
    static func writeSine(_ url: URL, frequency: Double, seconds: Double = StudyTests.seconds) throws {
        let frames = Int(seconds * sampleRate)
        var data = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + frames * 4)); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(2); u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 4)
        u16(4); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(UInt32(frames * 4))
        for i in 0..<frames {
            let v = Int16(0.3 * 32767 * sin(2 * .pi * frequency * Double(i) / sampleRate))
            u16(UInt16(bitPattern: v)); u16(UInt16(bitPattern: v))
        }
        try data.write(to: url)
    }

    func makeFixture(analysis: Bool = true) throws -> Fixture {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("study-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("projects", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }

        var p = Project(song: Song(title: "Tema", artist: "Banda", source: "source/original.wav", sourceSHA256: "abc",
                                   sourceFormat: "wav", sourceSampleRate: Self.sampleRate, sourceChannels: 2,
                                   sampleRate: Self.sampleRate, duration: Self.seconds))
        p.separation = SeparationState(state: .done, model: "m", finishedAt: Date(timeIntervalSince1970: 1_700_000_000))
        p.stems = [Stem(kind: .bass, file: "stems/bass.wav"), Stem(kind: .drums, file: "stems/drums.wav"),
                   Stem(kind: .piano, file: "stems/piano.wav", isEmpty: true)]
        p.sections = [Section(name: "Intro", start: 0, end: 2), Section(name: "Solo", start: 2, end: 4, solo: true)]
        p.study.loops = [Loop(name: "Riff", start: 1, end: 2)]
        p.study.chordOverrides = [ChordOverride(start: 2, end: 4, index: 14)]
        p.study.keyOverride = "A:min"
        let folder = root.appendingPathComponent("Banda - Tema", isDirectory: true)
        let layout = ProjectLayout(folder: folder)
        try layout.createSkeleton()
        try Self.writeSine(layout.stemURL(.bass), frequency: 110)
        try Self.writeSine(layout.stemURL(.drums), frequency: 330)
        if analysis {
            let source = StudyKitBridge.Source(separationModel: "m", separationFinishedAt: p.separation.finishedAt,
                                               sourceSHA256: "abc")
            let chords = [StudyKitBridge.Chord(start: 0, end: 2, index: 0), StudyKitBridge.Chord(start: 2, end: 4, index: 7)]
            try StudyKitBridge.saveCache(
                StudyKitBridge.Analysis(beats: [0.5, 1.0, 1.5, 2.0, 2.5, 3.0], downbeats: [0.5, 2.5], bpm: 120, beatsPerBar: 4,
                                        chords: chords, key: "C:maj", keyConfidence: 0.4),
                source: source, cache: layout.analysisCache)
        }
        try ProjectFile.save(p, to: folder)

        let events = Events()
        // Sin analizador: `study.open` no lanza análisis real (los tests de análisis usan `StudyEditsTests.makeRig`).
        let services = JobServices(importer: EditsImporter(), separator: EditsSeparator(), levelMeter: nil,
                                   analyzer: nil, guitarSplitter: nil)
        let bridge = try Bridge(options: LaunchOptions(projectsFolder: root, supportDir: support, audio: .simulated),
                                mediaBase: "https://tf.media/", reveal: nil, services: services)
        bridge.send = { events.add($0) }
        return Fixture(root: root, support: support, folder: folder, project: p, bridge: bridge, events: events)
    }

    func call(_ f: Fixture, _ method: String, _ params: String = "{}") async -> [String: Any] {
        let json = "{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}"
        let out = await f.bridge.router.handle(json)
        return (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] ?? [:]
    }

    func open(_ f: Fixture) async throws -> [String: Any] {
        let r = await call(f, "study.open", "{\"projectId\":\"\(f.project.id.uuidString)\"}")
        return try XCTUnwrap(r["result"] as? [String: Any], "\(r)")
    }

    func sleep(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }

    func positions(_ f: Fixture) -> [(time: Double, seconds: Double, playing: Bool)] {
        f.events.all("study.position").map { ($0.time, $0.payload["seconds"] as? Double ?? -1, $0.payload["playing"] as? Bool ?? false) }
    }

    func savedProject(_ f: Fixture) throws -> Project { try ProjectFile.load(folder: f.folder) }

    // MARK: Opciones

    func testAudioOptionParse() {
        XCTAssertEqual(LaunchOptions.parse([]).audio, .device)
        XCTAssertEqual(LaunchOptions.parse(["--audio", "simulated"]).audio, .simulated)
        XCTAssertEqual(LaunchOptions.parse(["--audio=device"]).audio, .device)
        XCTAssertEqual(LaunchOptions.parse(["--audio", "nope"]).audio, .device)
    }

    // MARK: Abrir

    func testOpenReturnsFullState() async throws {
        let f = try makeFixture()
        let r = try await open(f)
        XCTAssertEqual(r["title"] as? String, "Tema")
        XCTAssertEqual(r["duration"] as? Double ?? 0, Self.seconds, accuracy: 0.01)
        XCTAssertNil(r["loadError"] as? String)
        XCTAssertEqual((r["audio"] as? [String: Any])?["mode"] as? String, "simulated")
        let t = try XCTUnwrap(r["transport"] as? [String: Any])
        let channels = try XCTUnwrap(t["channels"] as? [[String: Any]])
        XCTAssertEqual(channels.compactMap { $0["id"] as? String }, ["drums", "bass"])
        XCTAssertEqual(channels.compactMap { $0["name"] as? String }, ["Batería", "Bajo"])
        XCTAssertEqual((r["emptyStems"] as? [[String: Any]])?.first?["kind"] as? String, "piano")
        XCTAssertEqual(t["rate"] as? Double, 1)
        XCTAssertEqual(t["playing"] as? Bool, false)
        XCTAssertEqual((t["metronome"] as? [String: Any])?["available"] as? Bool, true)

        let a = try XCTUnwrap(r["analysis"] as? [String: Any])
        XCTAssertEqual(a["state"] as? String, "ready")
        XCTAssertEqual((a["beats"] as? [Double])?.count, 6)
        XCTAssertEqual(a["beatsPerBar"] as? Int, 4)
        let chords = try XCTUnwrap(a["chords"] as? [[String: Any]])
        XCTAssertEqual(chords.count, 2)
        XCTAssertEqual(chords[0]["overridden"] as? Bool, false)
        // El tramo 2...4 está corregido por el usuario (índice 14 en lugar de 7).
        XCTAssertEqual(chords[1]["index"] as? Int, 14)
        XCTAssertEqual(chords[1]["overridden"] as? Bool, true)
        XCTAssertFalse((chords[1]["name"] as? String ?? "").isEmpty)
        let key = try XCTUnwrap(a["key"] as? [String: Any])
        XCTAssertEqual(key["detected"] as? String, "C:maj")
        XCTAssertEqual(key["effective"] as? String, "A:min")
        XCTAssertEqual(key["override"] as? String, "A:min")

        let sections = try XCTUnwrap(r["sections"] as? [[String: Any]])
        XCTAssertEqual(sections.map { $0["name"] as? String }, ["Intro", "Solo"])
        XCTAssertEqual(sections[1]["solo"] as? Bool, true)
        XCTAssertEqual((r["loops"] as? [[String: Any]])?.first?["name"] as? String, "Riff")
        XCTAssertEqual((r["chordOverrides"] as? [[String: Any]])?.count, 1)
        _ = await call(f, "study.close")
    }

    func testOpenWithoutAnalysis() async throws {
        let f = try makeFixture(analysis: false)
        let r = try await open(f)
        let a = try XCTUnwrap(r["analysis"] as? [String: Any])
        XCTAssertEqual(a["state"] as? String, "missing")
        // Sin análisis solo quedan los tramos que el usuario corrigió.
        XCTAssertEqual((a["chords"] as? [[String: Any]])?.map { $0["overridden"] as? Bool }, [true])
        let t = try XCTUnwrap(r["transport"] as? [String: Any])
        XCTAssertEqual((t["metronome"] as? [String: Any])?["available"] as? Bool, false)
        _ = await call(f, "study.close")
    }

    func testErrors() async throws {
        let f = try makeFixture()
        for m in ["study.play", "study.pause", "study.setRate"] {
            let r = await call(f, m, "{\"rate\":1}")
            XCTAssertEqual((r["error"] as? [String: Any])?["code"] as? String, "not-open", m)
        }
        let bad = await call(f, "study.open", "{\"projectId\":\"x\"}")
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? String, "bad-params")
        let missing = await call(f, "study.open", "{\"projectId\":\"\(UUID().uuidString)\"}")
        XCTAssertEqual((missing["error"] as? [String: Any])?["code"] as? String, "not-found")
        _ = try await open(f)
        let ch = await call(f, "study.setMix", "{\"channel\":\"nope\",\"gainDB\":0}")
        XCTAssertEqual((ch["error"] as? [String: Any])?["code"] as? String, "bad-params")
        let piano = await call(f, "study.setMix", "{\"channel\":\"piano\",\"mute\":true}")
        XCTAssertNotNil(piano["error"], "un stem vacío no es un canal")
        _ = await call(f, "study.close")
        let after = await call(f, "study.play")
        XCTAssertEqual((after["error"] as? [String: Any])?["code"] as? String, "not-open")
    }

    // MARK: Transporte

    func testPlayEmitsIncreasingPositionAtMost30Hz() async throws {
        let f = try makeFixture()
        _ = try await open(f)
        f.events.clear()
        let play = await call(f, "study.play")
        XCTAssertNil(play["error"], "\(play)")
        await sleep(1.6)
        _ = await call(f, "study.pause")
        await sleep(0.3)
        let ps = positions(f)
        let playing = ps.filter(\.playing)
        XCTAssertGreaterThan(playing.count, 12)
        XCTAssertLessThanOrEqual(playing.count, Int(1.7 * 30) + 2)
        var last = -1.0
        for p in playing {
            XCTAssertGreaterThanOrEqual(p.seconds, last)
            last = p.seconds
        }
        XCTAssertGreaterThan(last, 1.0)
        XCTAssertLessThan(last, 2.2)
        // Cualquier ventana de 1 s tiene como mucho 30 (+1 por el borde) eventos.
        for p in playing {
            XCTAssertLessThanOrEqual(playing.filter { $0.time >= p.time && $0.time < p.time + 1 }.count, 31)
        }
        // Al parar sale una última con playing:false y después nada más (parado y sin cambios).
        XCTAssertEqual(ps.last?.playing, false)
        let n = positions(f).count
        await sleep(0.3)
        XCTAssertEqual(positions(f).count, n)
        XCTAssertFalse(f.events.all("study.state").isEmpty)
        let levels = f.events.all("study.levels")
        XCTAssertFalse(levels.isEmpty)
        XCTAssertNotNil((levels.last?.payload["channels"] as? [String: Any])?["bass"])
        _ = await call(f, "study.close")
    }

    func testRateScalesPositionSpeed() async throws {
        let f = try makeFixture()
        _ = try await open(f)
        let set = await call(f, "study.setRate", "{\"rate\":0.7}")
        XCTAssertEqual((set["result"] as? [String: Any])?["rate"] as? Double, 0.7)
        _ = await call(f, "study.play")
        await sleep(0.8)   // arranque del motor
        f.events.clear()
        await sleep(2.0)
        let ps = positions(f).filter(\.playing)
        let first = try XCTUnwrap(ps.first), last = try XCTUnwrap(ps.last)
        let speed = (last.seconds - first.seconds) / (last.time - first.time)
        XCTAssertEqual(speed, 0.7, accuracy: 0.08, "velocidad de la posición")
        let states = f.events.all("study.state")
        _ = states
        _ = await call(f, "study.close")
    }

    func testLoopReturnsToStart() async throws {
        let f = try makeFixture()
        _ = try await open(f)
        let l = await call(f, "study.setLoop", "{\"start\":1.0,\"end\":1.6,\"name\":\"Riff\"}")
        let loop = try XCTUnwrap((l["result"] as? [String: Any])?["loop"] as? [String: Any])
        XCTAssertEqual(loop["name"] as? String, "Riff")
        _ = await call(f, "study.seek", "{\"seconds\":1.0}")
        f.events.clear()
        _ = await call(f, "study.play")
        await sleep(2.6)
        let ps = positions(f).filter(\.playing).map(\.seconds)
        XCTAssertGreaterThan(ps.count, 30)
        XCTAssertLessThan(ps.max() ?? 99, 1.6 + 0.2)
        XCTAssertGreaterThan(ps.min() ?? 0, 1.0 - 0.2)
        let wraps = zip(ps, ps.dropFirst()).filter { $1 < $0 - 0.3 }.count
        XCTAssertGreaterThanOrEqual(wraps, 2, "el bucle de 0,6 s tiene que dar al menos dos vueltas en 2,6 s")
        // Quitar el bucle: la posición sigue hacia delante.
        let off = await call(f, "study.setLoop", "{}")
        XCTAssertTrue(((off["result"] as? [String: Any])?["loop"]) == nil || (off["result"] as? [String: Any])?["loop"] is NSNull)
        _ = await call(f, "study.close")
    }

    func testSeekWhilePausedEmitsPositionOnce() async throws {
        let f = try makeFixture()
        _ = try await open(f)
        f.events.clear()
        let r = await call(f, "study.seek", "{\"seconds\":3.5}")
        XCTAssertEqual((r["result"] as? [String: Any])?["position"] as? Double ?? 0, 3.5, accuracy: 0.01)
        await sleep(0.3)
        let ps = positions(f)
        XCTAssertEqual(ps.count, 1)
        XCTAssertEqual(ps.first?.seconds ?? 0, 3.5, accuracy: 0.01)
        XCTAssertEqual(ps.first?.playing, false)
        _ = await call(f, "study.close")
    }

    // MARK: Mezcla y guardado

    func testMixSavesWithDebounceAndFlushOnClose() async throws {
        let f = try makeFixture()
        _ = try await open(f)
        let m = await call(f, "study.setMix", "{\"channel\":\"bass\",\"gainDB\":-6,\"mute\":true}")
        let ch = try XCTUnwrap(((m["result"] as? [String: Any])?["channels"] as? [[String: Any]])?.first { $0["id"] as? String == "bass" })
        XCTAssertEqual(ch["gainDB"] as? Double, -6)
        XCTAssertEqual(ch["muted"] as? Bool, true)
        let s = await call(f, "study.setMix", "{\"channel\":\"drums\",\"solo\":true}")
        XCTAssertEqual((s["result"] as? [String: Any])?["anySolo"] as? Bool, true)
        // Aún no se ha escrito nada (rebote de 0,5 s).
        XCTAssertTrue(try savedProject(f).study.mixer.isEmpty)
        await sleep(StudySession.saveDelay + 0.5)
        let saved = try savedProject(f)
        XCTAssertEqual(saved.study.mixer.first { $0.kind == .bass }?.gainDB, -6)
        XCTAssertEqual(saved.study.mixer.first { $0.kind == .bass }?.muted, true)
        XCTAssertEqual(saved.study.mixer.first { $0.kind == .drums }?.solo, true)
        // Cambios seguidos de un cierre inmediato: `study.close` guarda ya.
        _ = await call(f, "study.setRate", "{\"rate\":0.8}")
        _ = await call(f, "study.setTranspose", "{\"semitones\":-2,\"fineCents\":10}")
        _ = await call(f, "study.setMetronome", "{\"on\":true,\"gainDB\":-3}")
        _ = await call(f, "study.setCapo", "{\"capo\":3}")
        _ = await call(f, "study.close")
        let p = try savedProject(f).study.player
        XCTAssertEqual(p.rate, 0.8)
        XCTAssertEqual(p.transpose, -2)
        XCTAssertEqual(p.fineCents, 10)
        XCTAssertEqual(p.capo, 3)
        XCTAssertTrue(p.metronomeOn)
        XCTAssertEqual(p.metronomeGainDB, -3)
        // Lo que no se tocó se conserva (secciones, bucles, correcciones).
        let kept = try savedProject(f)
        XCTAssertEqual(kept.sections.count, 2)
        XCTAssertEqual(kept.study.loops.count, 1)
        XCTAssertEqual(kept.study.keyOverride, "A:min")
        // Al reabrir, vuelve lo guardado.
        let r = try await open(f)
        let t = try XCTUnwrap(r["transport"] as? [String: Any])
        XCTAssertEqual(t["rate"] as? Double, 0.8)
        XCTAssertEqual(t["transpose"] as? Int, -2)
        let bass = try XCTUnwrap((t["channels"] as? [[String: Any]])?.first { $0["id"] as? String == "bass" })
        XCTAssertEqual(bass["muted"] as? Bool, true)
        _ = await call(f, "study.close")
    }

    func testMasterGoesToProfileNotProject() async throws {
        let f = try makeFixture()
        _ = try await open(f)
        let m = await call(f, "study.setMaster", "{\"gainDB\":-9}")
        XCTAssertEqual((m["result"] as? [String: Any])?["masterGainDB"] as? Double, -9)
        _ = await call(f, "study.close")
        let profile = try ProfileStore(url: f.support.appendingPathComponent("profile.json")).load()
        XCTAssertEqual(profile.masterGainDB, -9)
        let r = try await open(f)
        XCTAssertEqual((r["transport"] as? [String: Any])?["masterGainDB"] as? Double, -9)
        _ = await call(f, "study.close")
    }

    func testReopenClosesPrevious() async throws {
        let f = try makeFixture()
        _ = try await open(f)
        _ = await call(f, "study.setRate", "{\"rate\":0.6}")
        _ = try await open(f)   // segundo open: guarda el primero
        XCTAssertEqual(try savedProject(f).study.player.rate, 0.6)
        _ = await call(f, "study.close")
    }
}
