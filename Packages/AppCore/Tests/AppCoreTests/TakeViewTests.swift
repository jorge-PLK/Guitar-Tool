import AudioKit
import Foundation
import Store
import XCTest
@testable import AppCore
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

/// «Ver toma» con el audio en el núcleo (W2-V): `--audio simulated` y proyectos temporales.
@MainActor
final class TakeViewTests: XCTestCase {
    struct Rig {
        var folder: URL
        var project: Project
        var take: Take
        var bridge: Bridge
        var events: StudyTests.Events
    }

    static let takeStart = 2.0
    static let takeSeconds = 3.0

    /// Tema con bajo y guitarra (la parte sustituye a la rítmica: la guitarra completa no suena en el visor) y una toma de 3 s
    /// que empieza en 2 s.
    func makeRig(stems: Bool = true) throws -> Rig {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("takeview-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("projects", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        var p = Project(song: Song(title: "Tema", artist: "Banda", source: "source/original.wav", sourceSHA256: "abc",
                                   sourceFormat: "wav", sourceSampleRate: StudyTests.sampleRate, sourceChannels: 2,
                                   sampleRate: StudyTests.sampleRate, duration: StudyTests.seconds))
        p.separation = SeparationState(state: .done, model: "m", finishedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let folder = root.appendingPathComponent("Banda - Tema", isDirectory: true)
        let layout = ProjectLayout(folder: folder)
        try layout.createSkeleton()
        if stems {
            p.stems = [Stem(kind: .bass, file: "stems/bass.wav"), Stem(kind: .guitar, file: "stems/guitar.wav")]
            try StudyTests.writeSine(layout.stemURL(.bass), frequency: 110)
            try StudyTests.writeSine(layout.stemURL(.guitar), frequency: 220)
        }
        let take = Take(processedFile: "takes/t1/processed.wav", songStart: Self.takeStart)
        try FileManager.default.createDirectory(at: layout.url(relative: "takes/t1"), withIntermediateDirectories: true)
        try StudyTests.writeSine(layout.url(relative: "takes/t1/processed.wav"), frequency: 330, seconds: Self.takeSeconds)
        p.takes = [take]
        let part = RecordingPart(name: "Rítmica", replaces: .rhythm, takeIDs: [take.id], bestTakeID: take.id)
        p.recording = RecordingState(parts: [part], mix: [StemMix(kind: .bass, gainDB: -6)], partMix: [PartMix(partID: part.id, gainDB: 3)])
        try ProjectFile.save(p, to: folder)
        let events = StudyTests.Events()
        let bridge = try Bridge(options: LaunchOptions(projectsFolder: root, supportDir: support, audio: .simulated), mediaBase: "m")
        bridge.send = { events.add($0) }
        return Rig(folder: folder, project: p, take: take, bridge: bridge, events: events)
    }

    func call(_ r: Rig, _ method: String, _ params: String = "{}") async -> [String: Any] {
        let out = await r.bridge.router.handle("{\"id\":1,\"method\":\"\(method)\",\"params\":\(params)}")
        return (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] ?? [:]
    }

    func result(_ r: Rig, _ method: String, _ params: String = "{}") async throws -> [String: Any] {
        let o = await call(r, method, params)
        return try XCTUnwrap(o["result"] as? [String: Any], "\(method): \(o)")
    }

    func open(_ r: Rig) async throws -> [String: Any] {
        try await result(r, "takeview.open", "{\"projectId\":\"\(r.project.id.uuidString)\",\"takeId\":\"\(r.take.id.uuidString)\"}")
    }

    func sleep(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }

    /// Espera una condición (hasta `timeout` s) en vez de un tiempo fijo: el primer bloque tarda lo que tarde el hilo del
    /// reproductor en arrancar y bajo carga (pasada completa en Windows) eso no es acotable.
    func waitFor(timeout: Double = 5, _ condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { await sleep(0.01) }
        return condition()
    }

    func positions(_ r: Rig) -> [[String: Any]] { r.events.all("takeview.position").map(\.payload) }

    // MARK: Transporte

    func testOpenLoadsTakeAndAudibleBacking() async throws {
        let r = try makeRig()
        let s = try await open(r)
        XCTAssertEqual(try XCTUnwrap(s["duration"] as? Double), Self.takeSeconds, accuracy: 0.001)
        XCTAssertEqual(s["songStart"] as? Double, Self.takeStart)
        XCTAssertEqual(s["hasBacking"] as? Bool, true)
        XCTAssertEqual(s["backingOn"] as? Bool, true)
        XCTAssertEqual(s["playing"] as? Bool, false)
        XCTAssertEqual(s["position"] as? Double, 0)
        let session = try XCTUnwrap(r.bridge.takeViewService.current)
        // La guitarra sustituida (tramo silenciado = la toma entera) no se carga; el bajo y la toma, sí.
        XCTAssertEqual(session.player.tracks.map(\.id), ["backing-0", TakeViewConstants.takeTrackID])
        XCTAssertEqual(session.base, Self.takeStart)
        XCTAssertEqual(session.player.currentTime, Self.takeStart, accuracy: 1e-9)
        let first = try XCTUnwrap(positions(r).last)
        XCTAssertEqual(first["playing"] as? Bool, false)
        XCTAssertEqual(first["seconds"] as? Double, 0)
        let off = try await result(r, "takeview.setBacking", #"{"on":false}"#)
        XCTAssertEqual(off["backingOn"] as? Bool, false)
        await r.bridge.closeTakeView()
    }

    func testTakeAloneWithoutStems() async throws {
        let r = try makeRig(stems: false)
        let s = try await open(r)
        XCTAssertEqual(s["hasBacking"] as? Bool, false)
        let session = try XCTUnwrap(r.bridge.takeViewService.current)
        XCTAssertEqual(session.player.tracks.map(\.id), [TakeViewConstants.takeTrackID])
        XCTAssertEqual(session.base, 0)
        await r.bridge.closeTakeView()
    }

    func testPlayPauseSeek() async throws {
        let r = try makeRig()
        _ = try await open(r)
        let played = try await result(r, "takeview.play")
        XCTAssertEqual(played["playing"] as? Bool, true)
        let svc = r.bridge.takeViewService
        let session = try XCTUnwrap(svc.current)
        // Primero a que suene la primera muestra; desde ahí 0,6 s de reloj real son ≈ 0,6 s de posición.
        let started = await waitFor { session.position > 0.02 }
        XCTAssertTrue(started, "el reproductor empieza a avanzar")
        let p0 = session.position
        await sleep(0.6)
        XCTAssertEqual(session.position - p0, 0.6, accuracy: 0.15, "avanza con el reloj real")
        let enoughEvents = await waitFor { self.positions(r).filter { ($0["playing"] as? Bool) == true && ($0["rate"] as? Double) == 1 }.count > 10 }
        XCTAssertTrue(enoughEvents, "≈30 eventos por segundo mientras suena")

        let paused = try await result(r, "takeview.pause")
        XCTAssertEqual(paused["playing"] as? Bool, false)
        let at = try XCTUnwrap(paused["position"] as? Double)
        await sleep(0.25)
        XCTAssertEqual(session.position, at, accuracy: 1e-9, "en pausa no avanza")
        XCTAssertEqual(positions(r).last?["playing"] as? Bool, false)

        let sought = try await result(r, "takeview.seek", #"{"seconds":2.0}"#)
        XCTAssertEqual(sought["position"] as? Double, 2.0)
        XCTAssertEqual(session.player.currentTime, Self.takeStart + 2.0, accuracy: 1e-9)
        let epochs = positions(r).compactMap { $0["epoch"] as? Int }
        XCTAssertEqual(epochs, epochs.sorted(), "la época solo sube")
        XCTAssertGreaterThanOrEqual(epochs.last ?? 0, 3, "play, pausa y búsqueda son discontinuidades")

        // Búsqueda sonando: sigue sonando desde ahí.
        _ = try await result(r, "takeview.play")
        _ = try await result(r, "takeview.seek", #"{"seconds":0.5}"#)
        let resumed = await waitFor { session.position > 0.52 }
        XCTAssertTrue(resumed, "sigue sonando desde la búsqueda")
        let p1 = session.position
        await sleep(0.3)
        XCTAssertTrue(session.isPlaying)
        XCTAssertEqual(session.position - p1, 0.3, accuracy: 0.15)
        await r.bridge.closeTakeView()
    }

    /// Al final de la toma para sola en la duración; play vuelve al principio (Mac `togglePlay`).
    func testStopsAtTakeEnd() async throws {
        let r = try makeRig()
        _ = try await open(r)
        _ = try await result(r, "takeview.seek", #"{"seconds":2.6}"#)
        _ = try await result(r, "takeview.play")
        await sleep(0.8)
        let svc = r.bridge.takeViewService
        let session = try XCTUnwrap(svc.current)
        XCTAssertFalse(session.isPlaying)
        XCTAssertEqual(session.position, Self.takeSeconds, accuracy: 1e-9)
        let over = try XCTUnwrap(svc.lastEndOvershoot)
        let lag = svc.lastEndDetectionLag ?? .nan
        print("W2-V fin de toma: backing tras la toma \(String(format: "%.1f", over * 1000)) ms; el reloj lo vio \(String(format: "%.1f", lag * 1000)) ms tarde")
        XCTAssertLessThan(abs(over), 0.015, "parada exacta: menos de 15 ms de backing tras la toma")
        XCTAssertEqual(positions(r).last?["playing"] as? Bool, false)
        XCTAssertEqual(positions(r).last?["seconds"] as? Double, Self.takeSeconds)
        _ = try await result(r, "takeview.play")
        XCTAssertLessThan(session.position, 0.1)
        await r.bridge.closeTakeView()
    }

    func testCloseReleasesPlayer() async throws {
        let r = try makeRig()
        _ = try await open(r)
        _ = try await result(r, "takeview.play")
        weak var player = r.bridge.takeViewService.current?.player
        weak var audio = r.bridge.takeViewService.current?.audio
        XCTAssertNotNil(player)
        let closed = await call(r, "takeview.close")
        XCTAssertNotNil(closed["result"])
        XCTAssertNil(r.bridge.takeViewService.current)
        await sleep(0.1)
        XCTAssertNil(audio, "la salida se suelta")
        XCTAssertNil(player, "el reproductor se suelta")
        let after = await call(r, "takeview.play")
        XCTAssertEqual((after["error"] as? [String: Any])?["code"] as? String, "not-open")
        let nf = await call(r, "takeview.open", "{\"projectId\":\"\(r.project.id.uuidString)\",\"takeId\":\"\(UUID().uuidString)\"}")
        XCTAssertEqual((nf["error"] as? [String: Any])?["code"] as? String, "not-found")
    }

    // MARK: Reloj del núcleo

    /// Lo que publica el núcleo sonando de verdad (salida simulada a tiempo real, bloques de 512): residuo frente a la recta
    /// ajustada `seconds ≈ a + b·at` en una misma época.
    func testPublishedClockIsStraight() async throws {
        let r = try makeRig()
        _ = try await open(r)
        _ = try await result(r, "takeview.play")
        let session = try XCTUnwrap(r.bridge.takeViewService.current)
        // 1,5 s de reloj en marcha (rate 1), no 1,5 s desde play: el reloj no avanza hasta que suena la primera muestra.
        let ran = await waitFor(timeout: 8) {
            let ats = self.positions(r).filter { ($0["rate"] as? Double) == 1 && ($0["epoch"] as? Int) == session.epoch }
                .compactMap { $0["at"] as? Double }
            return (ats.last ?? 0) - (ats.first ?? 0) >= 1.5
        }
        XCTAssertTrue(ran, "el reloj avanza 1,5 s")
        let pts = positions(r).filter { ($0["rate"] as? Double) == 1 && ($0["epoch"] as? Int) == session.epoch }
            .compactMap { e -> (Double, Double)? in
                guard let s = e["seconds"] as? Double, let at = e["at"] as? Double else { return nil }
                return (at, s)
            }
        XCTAssertGreaterThan(pts.count, 30)
        // Se descarta el primer 0,4 s (el lazo se asienta).
        let t0 = pts[0].0
        let steady = pts.filter { $0.0 - t0 > 0.4 }
        let n = Double(steady.count)
        let mx = steady.map(\.0).reduce(0, +) / n, my = steady.map(\.1).reduce(0, +) / n
        let sxy = steady.map { ($0.0 - mx) * ($0.1 - my) }.reduce(0, +), sxx = steady.map { ($0.0 - mx) * ($0.0 - mx) }.reduce(0, +)
        let slope = sxy / sxx
        let res = steady.map { abs($0.1 - (my + slope * ($0.0 - mx))) }
        let maxMs = (res.max() ?? 0) * 1000, meanMs = res.reduce(0, +) / n * 1000
        print("W2-V reloj del núcleo: n=\(steady.count) pendiente=\(String(format: "%.5f", slope)) residuo máx=\(String(format: "%.2f", maxMs)) ms medio=\(String(format: "%.2f", meanMs)) ms")
        XCTAssertEqual(slope, 1, accuracy: 0.01)
        #if os(macOS)
        let maxResidualMs = 4.0
        #else
        // El hilo de la salida simulada (`RealtimePump`) duerme 2 ms, que en Windows son ~15,6 ms (sin `timeBeginPeriod`): la
        // posición cruda llega a saltos de varios bloques y el lazo (ganancia 0,1) los reparte; medido 3 ms en Windows.
        let maxResidualMs = 8.0
        #endif
        XCTAssertLessThan(maxMs, maxResidualMs)
        await r.bridge.closeTakeView()
    }

    /// El lazo con una entrada a saltos de bloque (512 muestras a 44,1 kHz = 11,6 ms) muestreada a 30 Hz con temblor.
    func testClockSmoothsBlockSteps() {
        var c = TakeViewClock()
        let block = 512 / 44_100.0
        var rng = SplitMix(seed: 7)
        var rawErr: [Double] = [], outErr: [Double] = []
        var t = 0.0
        while t < 10 {
            t += 1 / 30.0 + (rng.next() - 0.5) * 0.004
            let raw = (t / block).rounded(.down) * block   // reproductor alojado: avanza por bloques
            let out = c.sample(raw: raw, at: t).seconds
            guard t > 1 else { continue }
            rawErr.append(raw - (t - block / 2))
            outErr.append(out - (t - block / 2))
        }
        let rawMax = rawErr.map(abs).max()! * 1000, outMax = outErr.map(abs).max()! * 1000
        let outMean = outErr.map(abs).reduce(0, +) / Double(outErr.count) * 1000
        print("W2-V lazo: entrada máx=\(String(format: "%.2f", rawMax)) ms, salida máx=\(String(format: "%.2f", outMax)) ms medio=\(String(format: "%.2f", outMean)) ms")
        XCTAssertLessThan(outMax, rawMax / 2)
        XCTAssertLessThan(outMax, 3)
    }

    // MARK: Desfase núcleo-vídeo (take-sync.js real con JavaScriptCore)

    #if canImport(JavaScriptCore)
    /// `<video>` simulado: `play()` tarda `playDelay` en arrancar; un salto congela la imagen `seekDelay` y sigue desde el
    /// destino (como Chromium: `currentTime` da el destino al instante); su reloj va `ppm` más rápido que el del audio.
    struct VideoSim {
        var media = 0.0
        var paused = true
        var rate = 1.0
        var seekingUntil: Double?
        var seekTarget = 0.0
        var startsAt = 0.0
        let playDelay = 0.08
        let seekDelay = 0.12
        let ppm = 80e-6

        var reported: Double { seekingUntil == nil ? media : seekTarget }
        /// Avanza hasta `now`; devuelve true si acaba un salto.
        mutating func advance(_ dt: Double, now: Double) -> Bool {
            if let u = seekingUntil {
                guard now >= u else { return false }
                seekingUntil = nil
                media = seekTarget
                return true
            }
            if !paused, now >= startsAt { media += dt * rate * (1 + ppm) }
            return false
        }
        mutating func apply(_ a: [String: Any], now: Double) {
            if let r = a["rate"] as? Double { rate = r }
            if let s = a["seek"] as? Double { seekTarget = s; seekingUntil = now + seekDelay }
            if a["play"] != nil, paused { paused = false; startsAt = now + playDelay }
            if a["pause"] != nil { paused = true }
        }
    }

    func loadTakeSync() throws -> JSContext {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../WinApp/Web/record/take-sync.js")
            .standardizedFileURL
        let src = try String(contentsOf: url, encoding: .utf8)
        let script = src.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("import ") }
            .map { $0.hasPrefix("export ") ? String($0.dropFirst("export ".count)) : String($0) }
            .joined(separator: "\n")
        let ctx = try XCTUnwrap(JSContext())
        var jsError: String?
        ctx.exceptionHandler = { _, e in jsError = e?.toString() }
        ctx.evaluateScript(script + "\nvar clock = new CoreClock(); var follower = new VideoFollower();")
        XCTAssertNil(jsError, "take-sync.js no carga: \(jsError ?? "")")
        return ctx
    }

    /// Simulación de 24 s en tiempo virtual: núcleo (reloj exacto + 1 ms de ruido del lazo) → eventos a 30 Hz con retraso de
    /// entrega 1 ms + exponencial de media 3 ms y un 5 % de picos de 20–40 ms → CoreClock → VideoFollower → vídeo simulado,
    /// a 60 fotogramas por segundo de página. Guion: play 0,5 s; búsqueda sonando a 20 s en t=6; pausa t=12; búsqueda en
    /// pausa a 5 s en t=13; play t=14. Desfase = imagen mostrada − audio que se oye.
    func testVideoFollowsCoreClock() throws {
        let ctx = try loadTakeSync()
        let clock = try XCTUnwrap(ctx.objectForKeyedSubscript("clock")), follower = try XCTUnwrap(ctx.objectForKeyedSubscript("follower"))
        var rng = SplitMix(seed: 42)
        let coreOffset = 1234.5          // reloj de host del núcleo − reloj de la página
        let audioLatency = 0.03          // el núcleo publica `rate: 0` hasta que suena
        var audio = 0.0, playing = false, startedAt = 0.0, epoch = 0
        var video = VideoSim()
        var pending: [(deliver: Double, ev: [String: Any])] = []
        var lastEventAt = -1.0
        var lastJump = 0.0
        let script: [(Double, String, Double)] = [(0.5, "play", 0), (6, "seek", 20), (12, "pause", 0), (13, "seek", 5), (14, "play", 0)]
        var next = 0
        let dt = 1 / 60.0
        var steady: [Double] = [], paused: [Double] = []
        var settle: [Double] = []
        var settledSince: Double?
        var settleDone = true
        var t = 0.0
        while t < 24 {
            t += dt
            // Transporte del núcleo.
            while next < script.count, script[next].0 <= t {
                let (_, what, arg) = script[next]
                next += 1
                epoch += 1
                lastJump = t
                settledSince = nil
                settleDone = false
                switch what {
                case "play": playing = true; startedAt = t
                case "pause": playing = false
                default: audio = arg; startedAt = t
                }
            }
            let moving = playing && t - startedAt >= audioLatency
            if moving { audio += dt * (1 + 0) }
            // Eventos del núcleo a 30 Hz (y uno inmediato en cada discontinuidad).
            if t - lastEventAt >= 1 / 30.0 || t - lastJump < dt / 2 {
                lastEventAt = t
                let noise = (rng.next() - 0.5) * 0.002
                let ev: [String: Any] = ["seconds": audio + (moving ? noise : 0), "playing": playing, "rate": moving ? 1 : 0,
                                         "at": t + coreOffset, "epoch": epoch]
                var delay = 0.001 - 0.003 * log(max(1e-9, rng.next()))
                if rng.next() < 0.05 { delay += 0.02 + 0.02 * rng.next() }
                pending.append((t + delay, ev))
            }
            pending.sort { $0.deliver < $1.deliver }
            while let f = pending.first, f.deliver <= t {
                pending.removeFirst()
                clock.invokeMethod("push", withArguments: [f.ev, f.deliver])
            }
            // Fotograma de página.
            if video.advance(dt, now: t) { follower.invokeMethod("seeked", withArguments: [t]) }
            let target = max(0, clock.invokeMethod("position", withArguments: [t]).toDouble())
            let running = clock.forProperty("running").toBool()
            let ep = clock.forProperty("epoch").toInt32()
            let v: [String: Any] = ["time": video.reported, "paused": video.paused, "seeking": video.seekingUntil != nil]
            let a = follower.invokeMethod("update", withArguments: [t, v, target, running, ep]).toDictionary() as? [String: Any] ?? [:]
            video.apply(a, now: t)
            // Medida.
            let err = video.media - audio
            if playing && moving {
                if t - lastJump > 1.5 { steady.append(err) }
                if abs(err) < 0.02 { if settledSince == nil { settledSince = t } } else { settledSince = nil }
                if let s = settledSince, t - s > 0.5, !settleDone { settle.append(s - lastJump); settleDone = true }
            } else if !playing, t - lastJump > 0.3 {
                paused.append(err)
            }
        }
        let ms = { (xs: [Double]) -> (Double, Double) in ((xs.map(abs).max() ?? 0) * 1000, xs.map(abs).reduce(0, +) / Double(max(1, xs.count)) * 1000) }
        let (sMax, sMean) = ms(steady), (pMax, _) = ms(paused)
        let settleMs = settle.map { Int(($0 * 1000).rounded()) }
        print("W2-V desfase vídeo-núcleo (estable, >1,5 s tras cada cambio): máx=\(String(format: "%.1f", sMax)) ms medio=\(String(format: "%.1f", sMean)) ms n=\(steady.count); en pausa máx=\(String(format: "%.1f", pMax)) ms; hasta |desfase|<20 ms tras cada cambio sonando: \(settleMs) ms; adelanto aprendido=\(String(format: "%.0f", follower.forProperty("lead").toDouble() * 1000)) ms")
        XCTAssertFalse(steady.isEmpty)
        XCTAssertLessThan(sMax, 10, "estable: menos de 10 ms (un tercio de fotograma a 30 fps)")
        XCTAssertLessThan(sMean, 5)
        XCTAssertLessThan(pMax, 2, "en pausa, el fotograma exacto")
        XCTAssertTrue(settle.allSatisfy { $0 < 1.3 }, "cada cambio se asienta en menos de 1,3 s: \(settleMs)")
    }
    #endif
}

/// Generador reproducible (SplitMix64) en [0, 1).
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
