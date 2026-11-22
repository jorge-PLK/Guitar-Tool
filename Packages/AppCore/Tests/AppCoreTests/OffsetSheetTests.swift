import AudioKit
import Foundation
import VideoKit
import XCTest
@testable import AppCore
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

// W2-O: hoja «Ajustar desfase» con el audio en el núcleo (`takeview.openOffset`) y el desfase en vivo en la página
// (`CoreTakeSync.setOffset` de take-sync.js, el fichero real ejecutado en JavaScriptCore).

#if canImport(JavaScriptCore)
/// take-sync.js real con lo mínimo del navegador: reloj de página `__now` (s), sin `requestAnimationFrame` (el test llama a
/// `step()`), y un `<video>` falso que apunta las órdenes (`take()`) y cuyo estado pone el test desde `VideoSim`.
@MainActor
enum TakeSyncHarness {
    static let shims = """
    var __now = 0;
    var performance = { now: function () { return __now * 1000; } };
    function requestAnimationFrame() { return 0; }
    function cancelAnimationFrame() {}
    function mediaUrl(p) { return p; }
    function FakeVideo() { this.t = 0; this.paused = true; this.seeking = false; this.readyState = 4; this.playbackRate = 1;
      this.src = ''; this.handlers = {}; this.cmd = {}; }
    FakeVideo.prototype = {
      get currentTime() { return this.t; },
      set currentTime(v) { this.t = v; this.cmd.seek = v; },
      addEventListener: function (n, f) { (this.handlers[n] = this.handlers[n] || []).push(f); },
      fire: function (n) { (this.handlers[n] || []).forEach(function (f) { f(); }); },
      play: function () { this.cmd.play = true; return { catch: function () {} }; },
      pause: function () { this.cmd.pause = true; },
      load: function () { this.cmd.load = true; },
      removeAttribute: function () {},
      take: function () { var c = this.cmd; this.cmd = {}; return c; }
    };
    """

    static func load(songStart: Double, offsetMs: Double, duration: Double) throws -> (JSContext, JSValue, JSValue) {
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
        ctx.evaluateScript(shims + "\n" + script + """

        var video = new FakeVideo();
        var sync = new CoreTakeSync(video, { songStart: \(songStart), offsetMs: \(offsetMs), basePath: 'take/video.mp4', punches: [], duration: \(duration) });
        """)
        XCTAssertNil(jsError, "take-sync.js no carga: \(jsError ?? "")")
        return (ctx, try XCTUnwrap(ctx.objectForKeyedSubscript("sync")), try XCTUnwrap(ctx.objectForKeyedSubscript("video")))
    }

    /// Un fotograma de página en `now`: estado del vídeo simulado → `step()` → órdenes al vídeo simulado.
    static func frame(_ ctx: JSContext, _ sync: JSValue, _ fv: JSValue, _ video: inout TakeViewTests.VideoSim, dt: Double, now: Double) {
        ctx.setObject(now, forKeyedSubscript: "__now" as NSString)
        let done = video.advance(dt, now: now)
        fv.setValue(video.reported, forProperty: "t")
        fv.setValue(video.paused, forProperty: "paused")
        fv.setValue(video.seekingUntil != nil, forProperty: "seeking")
        if done { fv.invokeMethod("fire", withArguments: ["seeked"]) }
        sync.invokeMethod("step", withArguments: [])
        let cmd = fv.invokeMethod("take", withArguments: []).toDictionary() as? [String: Any] ?? [:]
        if cmd["load"] != nil { fv.invokeMethod("fire", withArguments: ["loadedmetadata"]) }
        var a: [String: Any] = ["rate": fv.forProperty("playbackRate").toDouble()]
        if let s = cmd["seek"] as? Double { a["seek"] = s }
        if cmd["play"] != nil { a["play"] = true }
        if cmd["pause"] != nil { a["pause"] = true }
        video.apply(a, now: now)
    }

    static func ms(_ xs: [Double]) -> (max: Double, mean: Double) {
        ((xs.map(abs).max() ?? 0) * 1000, xs.map(abs).reduce(0, +) / Double(max(1, xs.count)) * 1000)
    }
}
#endif

@MainActor
final class OffsetSheetTests: XCTestCase {
    #if canImport(JavaScriptCore)
    /// (a) y (b) en tiempo virtual (24 s, reproducible): núcleo simulado → eventos a 30 Hz con el retraso de entrega de
    /// TakeViewTests → `CoreTakeSync` real → vídeo simulado (80 ms de arranque, 120 ms por salto, +80 ppm).
    /// Guion del desfase: +65 ms al abrir; play 0,5 s; −65 ms en t=8 (cambio de 130 ms); −65+1 fotograma en t=13;
    /// +1 ms en t=17; +65 ms en t=20; pausa t=23 y −65 ms en pausa en t=24.
    /// Error = fotograma mostrado − (songStart + audio que se oye + desfase en curso).
    func testVideoHoldsLiveOffsetAgainstCoreClock() throws {
        let songStart = 0.5
        let frameMs = 1000.0 / 30
        let (ctx, sync, fv) = try TakeSyncHarness.load(songStart: songStart, offsetMs: 65, duration: 60)
        var rng = SplitMix(seed: 2026)
        let coreOffset = 1234.5, audioLatency = 0.03
        var audio = 0.0, playing = false, startedAt = 0.0, epoch = 0
        var video = TakeViewTests.VideoSim()
        var pending: [(deliver: Double, ev: [String: Any])] = []
        var lastEventAt = -1.0, lastJump = 0.0
        var offset = 65.0
        let transport: [(Double, Bool)] = [(0.5, true), (23, false)]
        let offsets: [(Double, Double)] = [(8, -65), (13, -65 + frameMs), (17, -65 + frameMs + 1), (20, 65), (24, -65)]
        var nextT = 0, nextO = 0
        var changedAt = 0.5
        var plus: [Double] = [], minus: [Double] = [], pausedErr: [Double] = []
        var settle: [(Double, Double?, Double?)] = []   // (cambio ms, hasta <½ fotograma, hasta <5 ms)
        var half: Double?, fine: Double?, fineSince: Double?, halfSince: Double?
        var lastChange = 0.0
        let dt = 1 / 60.0
        var t = 0.0
        func closeSettle() { if lastChange != 0 { settle.append((lastChange, half, fine)) } }
        while t < 26 {
            t += dt
            while nextT < transport.count, transport[nextT].0 <= t {
                playing = transport[nextT].1
                nextT += 1; epoch += 1; lastJump = t
                if playing { startedAt = t }
            }
            while nextO < offsets.count, offsets[nextO].0 <= t {
                closeSettle()
                lastChange = offsets[nextO].1 - offset
                offset = offsets[nextO].1
                nextO += 1
                sync.invokeMethod("setOffset", withArguments: [offset])
                changedAt = t; half = nil; fine = nil; halfSince = nil; fineSince = nil
            }
            let moving = playing && t - startedAt >= audioLatency
            if moving { audio += dt }
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
                sync.invokeMethod("push", withArguments: [f.ev, f.deliver])
            }
            TakeSyncHarness.frame(ctx, sync, fv, &video, dt: dt, now: t)
            let err = video.media - (songStart + audio + offset / 1000)
            if moving {
                if t - changedAt > 1.5, t - lastJump > 1.5 {
                    if offset == 65 { plus.append(err) } else if offset == -65 { minus.append(err) }
                }
                if t - changedAt > 0 {
                    if abs(err) < frameMs / 2000 { halfSince = halfSince ?? t } else { halfSince = nil }
                    if abs(err) < 0.005 { fineSince = fineSince ?? t } else { fineSince = nil }
                    if half == nil, let s = halfSince, t - s > 0.3 { half = s - changedAt }
                    if fine == nil, let s = fineSince, t - s > 0.3 { fine = s - changedAt }
                }
            } else if !playing, t - changedAt > 0.3, t - lastJump > 0.3 {
                pausedErr.append(err)
            }
        }
        let p = TakeSyncHarness.ms(plus), m = TakeSyncHarness.ms(minus), z = TakeSyncHarness.ms(pausedErr)
        let fmt = { (x: Double?) in x.map { String(format: "%.0f", $0 * 1000) } ?? "—" }
        print("W2-O desfase +65 ms estable: máx=\(String(format: "%.1f", p.max)) ms medio=\(String(format: "%.1f", p.mean)) ms n=\(plus.count); −65 ms: máx=\(String(format: "%.1f", m.max)) ms medio=\(String(format: "%.1f", m.mean)) ms n=\(minus.count); en pausa tras cambiar: máx=\(String(format: "%.2f", z.max)) ms")
        for s in settle { print("W2-O cambio de desfase \(String(format: "%+.1f", s.0)) ms sonando: <½ fotograma en \(fmt(s.1)) ms, <5 ms en \(fmt(s.2)) ms") }
        XCTAssertGreaterThan(plus.count, 100)
        XCTAssertGreaterThan(minus.count, 100)
        XCTAssertLessThan(p.max, 10, "+65 ms: menos de ⅓ de fotograma")
        XCTAssertLessThan(m.max, 10, "−65 ms: menos de ⅓ de fotograma")
        XCTAssertLessThan(p.mean, 5)
        XCTAssertLessThan(m.mean, 5)
        XCTAssertLessThan(z.max, 2, "en pausa, el fotograma exacto con el desfase nuevo")
        XCTAssertEqual(settle.count, 4)
        for s in settle where abs(s.0) >= 2 {
            XCTAssertLessThan(try XCTUnwrap(s.1, "cambio \(s.0) ms sin asentarse"), 0.5, "cambio \(s.0) ms: <½ fotograma en menos de 0,5 s")
            XCTAssertLessThan(try XCTUnwrap(s.2, "cambio \(s.0) ms sin asentarse"), 1.0, "cambio \(s.0) ms: <5 ms en menos de 1 s")
        }
    }
    #endif
}

/// Grabar de verdad (audio y cámara simulados): toma nueva → hoja → audio de la toma en el núcleo.
extension RecordTests {
    /// Toma nueva de `seconds` hasta la hoja de desfase; `takeview.openOffset` toma lo que pide Grabar (aún no está en project.json).
    func recordToOffsetSheet(seconds: Double = 1.2) async throws -> (Rig, RecordOffsetInfo) {
        let r = try await makeRig()
        Bridge.wireOffsetSheet(record: r.svc, takeView: r.bridge.takeViewService)
        _ = try await openRecord(r)
        _ = try await snap(r, "record.start")
        await sleep(seconds)
        _ = try await snap(r, "record.stop")
        let s = try await until(r, timeout: 10) { $0.phase == "adjusting" }
        return (r, try XCTUnwrap(s.offset))
    }

    func takeView(_ r: Rig, _ method: String, _ params: String = "{}") async throws -> [String: Any] {
        let o = await call(r.bridge.router, method, params)
        return try XCTUnwrap(o["result"] as? [String: Any], "\(method): \(o)")
    }

    /// Solo suena la toma, a 0 dB, desde 0, sin backing; Grabar queda en pausa; a 1 fotograma del final play vuelve a 0.
    func testOffsetSheetOpensTakeAudioInCore() async throws {
        let (r, o) = try await recordToOffsetSheet()
        let opened = try await takeView(r, "takeview.openOffset")
        XCTAssertEqual(opened["takeId"] as? String, o.takeId)
        XCTAssertEqual(try XCTUnwrap(opened["songStart"] as? Double), o.songStart, accuracy: 1e-9)
        XCTAssertEqual(opened["hasBacking"] as? Bool, false)
        XCTAssertEqual(opened["backingOn"] as? Bool, false)
        XCTAssertEqual(opened["position"] as? Double, 0)
        let duration = try XCTUnwrap(opened["duration"] as? Double)
        XCTAssertEqual(duration, 1.2, accuracy: 0.6)
        let session = try XCTUnwrap(r.bridge.takeViewService.current)
        XCTAssertTrue(session.isOffset)
        XCTAssertEqual(session.base, 0)
        XCTAssertEqual(session.player.tracks.map(\.id), [TakeViewConstants.takeTrackID])
        XCTAssertFalse(try XCTUnwrap(r.svc.controller).player.isPlaying, "Grabar en pausa")
        // Margen de reinicio del Mac (1 fotograma): a 20 ms del final, play vuelve a 0; a 50 ms, sigue desde ahí.
        _ = try await takeView(r, "takeview.seek", "{\"seconds\":\(duration - 0.05)}")
        var played = try await takeView(r, "takeview.play")
        XCTAssertGreaterThan(try XCTUnwrap(played["position"] as? Double), duration - 0.06)
        _ = try await takeView(r, "takeview.pause")
        _ = try await takeView(r, "takeview.seek", "{\"seconds\":\(duration - 0.02)}")
        played = try await takeView(r, "takeview.play")
        XCTAssertLessThan(try XCTUnwrap(played["position"] as? Double), 0.01)
        await r.bridge.closeTakeView()
        _ = try await snap(r, "record.finishOffset", "{\"save\":false}")
        let none = await call(r.bridge.router, "takeview.openOffset")
        XCTAssertEqual((none["error"] as? [String: Any])?["code"] as? String, "no-offset")
        _ = await call(r.router, "record.close")
    }

    #if canImport(JavaScriptCore)
    /// (b) en tiempo real con el núcleo de verdad: toma de ≈2,2 s; suena y la página mueve el desfase dos veces (+65 ms en
    /// 0,6 s, −65 ms en 1,3 s). El audio no salta: misma época y `seconds` sigue la recta de `at`. El vídeo (take-sync.js
    /// real con los eventos del núcleo) queda al desfase pedido.
    func testOffsetChangeDoesNotTouchCoreAudio() async throws {
        let (r, o) = try await recordToOffsetSheet(seconds: 2.2)
        let opened = try await takeView(r, "takeview.openOffset")
        let duration = try XCTUnwrap(opened["duration"] as? Double)
        // Se reproduce desde 0 y se mide hasta 0,1 s antes del final.
        let (ctx, sync, fv) = try TakeSyncHarness.load(songStart: o.songStart, offsetMs: 0, duration: duration)
        var video = TakeViewTests.VideoSim()
        let session = try XCTUnwrap(r.bridge.takeViewService.current)
        _ = try await takeView(r, "takeview.play")
        let epoch = session.epoch
        let t0 = HostClock.nowSeconds
        var seen = 0, last = t0, offset = 0.0, changes: [Double] = [0.6, 1.3]
        var latest: (s: Double, at: Double)?
        var errs: [(t: Double, offset: Double, err: Double)] = []
        while HostClock.nowSeconds - t0 < duration - 0.1 {
            try? await Task.sleep(nanoseconds: 8_000_000)
            let now = HostClock.nowSeconds
            let evs = r.events.all("takeview.position")
            for e in evs.dropFirst(seen) {
                sync.invokeMethod("push", withArguments: [e, now])
                if (e["rate"] as? Double) == 1, let s = e["seconds"] as? Double, let at = e["at"] as? Double { latest = (s, at) }
            }
            seen = evs.count
            if let c = changes.first, now - t0 >= c {
                changes.removeFirst()
                offset = offset == 0 ? 65 : -65
                sync.invokeMethod("setOffset", withArguments: [offset])
            }
            TakeSyncHarness.frame(ctx, sync, fv, &video, dt: now - last, now: now)
            last = now
            if let l = latest {
                let heard: Double = l.s + (now - l.at)
                let want: Double = o.songStart + heard + offset / 1000
                errs.append((t: now - t0, offset: offset, err: video.media - want))
            }
        }
        XCTAssertEqual(session.epoch, epoch, "cambiar el desfase no es una discontinuidad del núcleo")
        XCTAssertTrue(session.isPlaying)
        // Audio: incrementos de `seconds` frente a los de `at` en la época de play (salto = |Δs − Δat|).
        let moving = r.events.all("takeview.position").filter { ($0["epoch"] as? Int) == epoch && ($0["rate"] as? Double) == 1 }
            .compactMap { e -> (Double, Double)? in
                guard let s = e["seconds"] as? Double, let at = e["at"] as? Double else { return nil }
                return (at, s)
            }
        let jumps = zip(moving.dropFirst(), moving).map { abs(($0.1 - $1.1) - ($0.0 - $1.0)) }
        let (jMax, jMean) = TakeSyncHarness.ms(jumps)
        print("W2-O audio del núcleo mientras cambia el desfase: n=\(moving.count) salto máx=\(String(format: "%.2f", jMax)) ms medio=\(String(format: "%.2f", jMean)) ms, época sin cambios=\(session.epoch == epoch)")
        XCTAssertGreaterThan(moving.count, 20)
        XCTAssertLessThan(jMax, 5, "sin saltos de audio (residuo del lazo del núcleo)")
        // Vídeo: error en los últimos 0,15 s de cada tramo con desfase (tiempo real, más ruidoso que el virtual).
        for (from, to, off) in [(0.4, 0.6, 0.0), (1.1, 1.3, 65.0), (duration - 0.35, duration - 0.1, -65.0)] {
            let e = errs.filter { $0.t >= from && $0.t < to && $0.offset == off }.map(\.err)
            let (mx, mn) = TakeSyncHarness.ms(e)
            print("W2-O tiempo real, desfase \(Int(off)) ms en [\(String(format: "%.2f", from)), \(String(format: "%.2f", to))) s: máx=\(String(format: "%.1f", mx)) ms medio=\(String(format: "%.1f", mn)) ms n=\(e.count)")
            // El primer tramo es el arranque tras play (W2-V: 0,7–1,2 s); los otros, 0,5 s tras cada cambio de desfase.
            if off != 0 {
                XCTAssertGreaterThan(e.count, 5)
                XCTAssertLessThan(mn, 10, "0,5 s tras cambiar a \(Int(off)) ms el vídeo ya está a ese desfase")
            }
        }
        await r.bridge.closeTakeView()
        _ = await call(r.router, "record.close")
    }
    #endif

    /// (c) Cerrar la hoja suelta el reproductor: «Descartar toma» (`record.finishOffset`) lo cierra antes de borrar la carpeta
    /// de la toma (en Windows no se borra un fichero abierto), y `takeview.close` también.
    func testFinishingOffsetSheetReleasesCorePlayer() async throws {
        let (r, o) = try await recordToOffsetSheet()
        _ = try await takeView(r, "takeview.openOffset")
        _ = try await takeView(r, "takeview.play")
        weak var player = r.bridge.takeViewService.current?.player
        weak var audio = r.bridge.takeViewService.current?.audio
        XCTAssertNotNil(player)
        let takeDir = r.layout.takeDirectory(takeId: try XCTUnwrap(UUID(uuidString: o.takeId)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: takeDir.path))
        let s = try await snap(r, "record.finishOffset", "{\"save\":false}")
        XCTAssertEqual(s.phase, "idle")
        XCTAssertNil(r.bridge.takeViewService.current, "el reproductor de la hoja se cierra con la hoja")
        await sleep(0.1)
        XCTAssertNil(audio, "la salida se suelta")
        XCTAssertNil(player, "el reproductor se suelta")
        XCTAssertFalse(FileManager.default.fileExists(atPath: takeDir.path), "toma descartada: carpeta borrada")
        let after = await call(r.bridge.router, "takeview.play")
        XCTAssertEqual((after["error"] as? [String: Any])?["code"] as? String, "not-open")

        // `takeview.close` (la hoja se desmonta) también suelta; el visor normal no lo cierra `record.finishOffset`.
        _ = try await snap(r, "record.start")
        await sleep(1.0)
        _ = try await snap(r, "record.stop")
        _ = try await until(r, timeout: 10) { $0.phase == "adjusting" }
        _ = try await takeView(r, "takeview.openOffset")
        weak var player2 = r.bridge.takeViewService.current?.player
        _ = try await takeView(r, "takeview.close")
        XCTAssertNil(r.bridge.takeViewService.current)
        await sleep(0.1)
        XCTAssertNil(player2)
        _ = try await snap(r, "record.finishOffset", "{\"save\":true,\"makeDefault\":false}")
        _ = await call(r.router, "record.close")
    }
}
