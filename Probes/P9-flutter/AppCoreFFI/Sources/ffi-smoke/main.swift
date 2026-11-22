import CAppCoreFFI
#if canImport(Darwin)
import Darwin
#endif
import Foundation
#if canImport(AVFoundation)
import AppCoreFFI
#endif

// Humo de P9 prueba 2: ejercita solo la ABI C de tf_core.h. Hilo principal en dispatchMain(); trabajo en otro hilo.
// Umbrales (docs/flutter/arquitectura.md + encargo P9 2.1): 0 errores, mediana < 5 ms, p99 < 16 ms, retraso principal <= 16 ms.
let medianLimitMs = 5.0
let p99LimitMs = 16.0
let mainDelayLimitMs = 16.0
let rounds = 1000
let methods = ["app.info", "library.list", "settings.get", "audio.devices"]

func nowMs() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

final class Inbox: @unchecked Sendable {
    let lock = NSLock()
    let sem = DispatchSemaphore(value: 0)
    let shutdownSem = DispatchSemaphore(value: 0)
    var expectedID = -1
    var arrival = 0.0
    var errorCode: String?
    var shutdownClean: Bool?
    var shutdownAt = 0.0
    var watchStop = false
    var maxDelay = 0.0
    var tickSeqs: [Int] = []
    var tickSizes: [Int] = []
    var doneCount: Int?
    let probeSem = DispatchSemaphore(value: 0)
    let mainActorSem = DispatchSemaphore(value: 0)
    var mainActorOK: Bool?
    var dispatchMainOK: Bool?
    var mainActorMs: Int?
}
let inbox = Inbox()

nonisolated(unsafe) let onMessage: tf_message_cb = { ptr, len in
    let t = nowMs()
    guard let ptr else { return }
    let data = Data(bytes: ptr, count: Int(len))
    let size = Int(len)
    tf_core_free(ptr)
    guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
    if let event = obj["event"] as? String {
        if event == "core.shutdown" {
            inbox.lock.lock()
            inbox.shutdownClean = (obj["payload"] as? [String: Any])?["clean"] as? Bool
            inbox.shutdownAt = t
            inbox.lock.unlock()
            inbox.shutdownSem.signal()
        }
        if event == "probe.mainactor" {
            let p = obj["payload"] as? [String: Any]
            inbox.lock.lock()
            inbox.mainActorOK = p?["mainActor"] as? Bool
            inbox.dispatchMainOK = p?["dispatchMain"] as? Bool
            inbox.mainActorMs = p?["ms"] as? Int
            inbox.lock.unlock()
            inbox.mainActorSem.signal()
        }
        if event == "probe.tick" {
            inbox.lock.lock()
            inbox.tickSeqs.append(((obj["payload"] as? [String: Any])?["seq"] as? Int) ?? -1)
            inbox.tickSizes.append(size)
            inbox.lock.unlock()
        } else if event == "probe.done" {
            inbox.lock.lock()
            inbox.doneCount = (obj["payload"] as? [String: Any])?["count"] as? Int
            inbox.lock.unlock()
            inbox.probeSem.signal()
        }
        return
    }
    guard let id = obj["id"] as? Int else { return }
    inbox.lock.lock()
    if id == inbox.expectedID {
        inbox.arrival = t
        if let e = obj["error"] as? [String: Any] { inbox.errorCode = "\(e["code"] ?? "?")" } else { inbox.errorCode = nil }
        inbox.expectedID = -1
        inbox.lock.unlock()
        inbox.sem.signal()
    } else { inbox.lock.unlock() }
}

nonisolated(unsafe) var nextID = 1
/// Ida y vuelta: devuelve (ms, código de error o nil). Tope de 10 s.
func call(_ method: String) -> (Double, String?) {
    let id = nextID; nextID += 1
    let msg = Array("{\"id\":\(id),\"method\":\"\(method)\",\"params\":{}}".utf8)
    inbox.lock.lock(); inbox.expectedID = id; inbox.lock.unlock()
    let t0 = nowMs()
    msg.withUnsafeBufferPointer { tf_core_send($0.baseAddress, Int32($0.count)) }
    if inbox.sem.wait(timeout: .now() + 10) == .timedOut { return (10_000, "timeout") }
    inbox.lock.lock(); defer { inbox.lock.unlock() }
    return (inbox.arrival - t0, inbox.errorCode)
}

func rssMB() -> Double {
#if canImport(Darwin)
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
    }
    return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
#else
    return -1
#endif
}

func watchTick() {
    let deadline = DispatchTime.now() + .milliseconds(5)
    DispatchQueue.main.asyncAfter(deadline: deadline) {
        let late = nowMs() - Double(deadline.uptimeNanoseconds) / 1e6
        inbox.lock.lock()
        inbox.maxDelay = max(inbox.maxDelay, late)
        let stop = inbox.watchStop
        inbox.lock.unlock()
        if !stop { watchTick() }
    }
}

func argValue(_ flag: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
    return a[i + 1]
}

func childProcessesEmpty() -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    p.arguments = ["-P", "\(getpid())"]
    let pipe = Pipe()
    p.standardOutput = pipe
    guard (try? p.run()) != nil else { return false }
    let out = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return out.isEmpty
}

func run() {
    guard let projects = argValue("--projects-folder"), let support = argValue("--support-dir") else {
        print("uso: ffi-smoke --projects-folder <dir> --support-dir <dir>"); exit(1)
    }
    var ok = true
    func check(_ cond: Bool, _ what: String) { if !cond { ok = false; print("FALLA: \(what)") } }

    let options = ["args": ["--projects-folder", projects, "--support-dir", support, "--audio", "simulated"]]
    let json = String(decoding: try! JSONSerialization.data(withJSONObject: options), as: UTF8.self)
    let first = tf_core_start(json, onMessage, nil)
    let second = tf_core_start(json, onMessage, nil)
    print("start: \(first), segunda: \(second)")
    check(first == 0, "primer start == 0")
    check(second == 1, "segundo start == 1")
    if first != 0 { exit(1) }

    var errors = 0
    for m in methods {
        let (ms, err) = call(m)
        print("\(m): \(err.map { "error \($0)" } ?? "ok") (\(String(format: "%.2f", ms)) ms)")
        if err != nil { errors += 1 }
    }

    let rssBefore = rssMB()
    DispatchQueue.main.async { watchTick() }
    var times: [Double] = []
    times.reserveCapacity(rounds * methods.count)
    for _ in 0..<rounds {
        for m in methods {
            let (ms, err) = call(m)
            times.append(ms)
            if err != nil { errors += 1 }
        }
    }
    inbox.lock.lock(); inbox.watchStop = true; inbox.lock.unlock()
    Thread.sleep(forTimeInterval: 0.1)
    let rssAfter = rssMB()
    times.sort()
    let median = times[times.count / 2]
    let p99 = times[Int(Double(times.count - 1) * 0.99)]
    let maxMs = times.last!
    inbox.lock.lock(); let delay = inbox.maxDelay; inbox.lock.unlock()
    let live = tf_debug_live_buffers()
    print(String(format: "idas y vueltas: %d, errores: %d", times.count, errors))
    print(String(format: "mediana %.3f ms, p99 %.3f ms, max %.3f ms", median, p99, maxMs))
    print(String(format: "retraso max hilo principal: %.2f ms", delay))
    print(String(format: "RSS antes %.1f MB, despues %.1f MB", rssBefore, rssAfter))
    print("live_buffers: \(live)")
    check(errors == 0, "0 errores")
    check(median < medianLimitMs, "mediana < \(medianLimitMs) ms")
    check(p99 < p99LimitMs, "p99 < \(p99LimitMs) ms")
    check(delay <= mainDelayLimitMs, "retraso principal <= \(mainDelayLimitMs) ms")

    // Pasada del emisor sintético por callback.
    let emitRC = tf_debug_emit(60, 120, 300)
    check(emitRC == 0, "tf_debug_emit == 0")
    let emitDone = emitRC == 0 && inbox.probeSem.wait(timeout: .now() + 10) == .success
    inbox.lock.lock()
    let seqs = inbox.tickSeqs; let sizes = inbox.tickSizes; let done = inbox.doneCount
    inbox.lock.unlock()
    let emitOK = emitDone && seqs == Array(0..<120) && sizes.allSatisfy { $0 == 300 } && done == 120
    print("emisor: \(seqs.count) ticks, done \(done.map { "\($0)" } ?? "?"), tamanos \(Set(sizes).sorted()), orden \(seqs == Array(0..<120))")
    check(emitDone, "probe.done recibido")
    check(emitOK, "120 ticks en orden, 300 bytes, done=120")
    check(tf_debug_live_buffers() == 0, "emisor: live_buffers == 0")

    // P9 prueba 7: cola principal / @MainActor drenados y comprobación del hilo principal.
    let maRC = tf_debug_mainactor_selftest(3000)
    check(maRC == 0, "tf_debug_mainactor_selftest == 0")
    let maGot = maRC == 0 && inbox.mainActorSem.wait(timeout: .now() + 5) == .success
    inbox.lock.lock(); let maA = inbox.mainActorOK; let maD = inbox.dispatchMainOK; let maMs = inbox.mainActorMs; inbox.lock.unlock()
    print("mainactor: evento \(maGot ? "recibido" : "NO recibido"), mainActor \(maA.map { "\($0)" } ?? "?"), dispatchMain \(maD.map { "\($0)" } ?? "?"), \(maMs.map { "\($0)" } ?? "?") ms")
    check(maGot && maA == true && maD == true, "probe.mainactor con mainActor y dispatchMain a true")
    let isMain = tf_debug_is_main_thread()
    print("is_main_thread (hilo de trabajo): \(isMain)")
    check(isMain == 0, "tf_debug_is_main_thread == 0 desde el hilo de trabajo")

    let tShutdown = nowMs()
    tf_core_shutdown(5000)
    let got = inbox.shutdownSem.wait(timeout: .now() + 8) == .success
    inbox.lock.lock(); let clean = inbox.shutdownClean; let at = inbox.shutdownAt; inbox.lock.unlock()
    print(String(format: "shutdown: evento %@, clean %@, %.0f ms", got ? "recibido" : "NO recibido", clean.map { "\($0)" } ?? "?", at - tShutdown))
    check(got && clean == true, "clean == true")
    let liveEnd = tf_debug_live_buffers()
    check(liveEnd == 0 && live == 0, "live_buffers == 0")
    let noChildren = childProcessesEmpty()
    print("sin procesos hijos: \(noChildren)")
    check(noChildren, "sin procesos hijos")
    print(ok ? "RESULTADO: OK" : "RESULTADO: FALLA")
    exit(ok ? 0 : 1)
}

#if canImport(Darwin)
func cpuSeconds() -> Double {
    var u = rusage()
    getrusage(RUSAGE_SELF, &u)
    func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
    return s(u.ru_utime) + s(u.ru_stime)
}

/// P9 prueba 3: generador de fotogramas sin host de texturas. Copia textura (+1 y se suelta) y BGRA a 30 Hz.
func runFrames() {
    var ok = true
    for (w, h) in [(1280, 720), (1920, 1080)] {
        let rc = tf_debug_frames_start(0, Int32(w), Int32(h), 30)
        if rc != 0 { print("FALLA: start \(w)x\(h) rc \(rc)"); ok = false; continue }
        var dst = [UInt8](repeating: 0, count: w * h * 4)
        var ow: Int32 = 0, oh: Int32 = 0, seq: Int64 = 0
        var copyMs: [Double] = []
        var monotonic = true, pixelsMatch = true
        var prev: Int64 = 0
        let cpu0 = cpuSeconds(); let t0 = nowMs()
        var tick = 0
        while nowMs() - t0 < 5000 {
            if let p = tf_frame_copy(0) { Unmanaged<AnyObject>.fromOpaque(p).release() }
            let c0 = nowMs()
            let n = dst.withUnsafeMutableBufferPointer { tf_debug_frame_bgra(0, $0.baseAddress, Int32($0.count), &ow, &oh, &seq) }
            if n > 0 {
                copyMs.append(nowMs() - c0)
                if seq <= prev { monotonic = false }
                prev = seq
                var decoded: Int64 = 0
                for i in 0..<8 { decoded |= Int64(dst[i * 4]) << Int64(8 * i) }
                if decoded != seq || Int(ow) != w || Int(oh) != h || n != Int32(w * h * 4) { pixelsMatch = false }
            } else if n < 0 { ok = false; print("FALLA: bgra rc \(n)") }
            tick += 1
            // 30 Hz con fechas absolutas.
            let wait = t0 + Double(tick) * 1000.0 / 30.0 - nowMs()
            if wait > 0 { Thread.sleep(forTimeInterval: wait / 1000) }
        }
        let elapsed = nowMs() - t0
        let cpu = cpuSeconds() - cpu0
        var produced: Int64 = 0, tex: Int64 = 0, distinct: Int64 = 0, bgra: Int64 = 0
        tf_debug_frames_stats(0, &produced, &tex, &distinct, &bgra)
        let cost = Double(tf_debug_frames_cost_us(0)) / 1000
        tf_debug_frames_stop(0)
        let fps = Double(max(produced - 1, 0)) / (elapsed / 1000)  // N fotogramas = N-1 intervalos
        let avgCopy = copyMs.isEmpty ? 0 : copyMs.reduce(0, +) / Double(copyMs.count)
        print(String(format: "%dx%d: producidos %lld, fps %.2f, generador %.3f ms/fot, copia BGRA %.3f ms (n=%d), CPU %.1f %%, texturaCopias %lld distintas %lld, bgra %lld, secuencia monotona %@, pixeles=seq %@",
                     w, h, produced, fps, cost, avgCopy, copyMs.count, cpu / (elapsed / 1000) * 100, tex, distinct, bgra,
                     monotonic ? "si" : "NO", pixelsMatch ? "si" : "NO"))
        if abs(fps - 30) > 0.2 { ok = false; print("FALLA: fps fuera de 30 +- 0.2") }
        if !monotonic || !pixelsMatch { ok = false }
    }
    print(ok ? "RESULTADO: OK" : "RESULTADO: FALLA")
    exit(ok ? 0 : 1)
}

/// P9.5b prueba 5: reproductor de vídeo nativo esclavo de un reloj. Emula al runner: `tf_frame_copy` a 60 Hz desde un hilo.
/// Uso: --video <fichero> [--case steady|seek|loop|all] [--report <json>]
func runVideo() {
    guard let path = argValue("--video") else { print("falta fichero"); exit(2) }
    let cases = argValue("--case") ?? "all"
    let toleranceMs = 1001.0 / 30000 * 1000 / 2  // medio fotograma
    let frameMs = 1001.0 / 30000 * 1000
    guard ffiDebugVideoOpen(0, path) == 0 else { print("FALLA: no abre \(path)"); exit(1) }
    for _ in 0..<500 where ffiDebugVideoState(0) == 0 { Thread.sleep(forTimeInterval: 0.01) }
    guard ffiDebugVideoState(0) == 1 else { print("FALLA: apertura no llega a listo (estado \(ffiDebugVideoState(0)))"); exit(1) }
    var info: [String: Any] = [:]
    if let p = ffiDebugVideoInfo(0) {
        info = (try? JSONSerialization.jsonObject(with: Data(String(cString: p).utf8))) as? [String: Any] ?? [:]
        free(p)
    }
    let duration = info["duration"] as? Double ?? 0
    print("info: \(info)")
    var report: [String: Any] = ["file": path, "info": info]

    struct Sample { var t: Double; var e: Double?; var n: Int; var item: Double }
    func fetch() -> (samples: [Sample], events: [(Double, String)], stats: [String: Any]) {
        guard let p = ffiDebugVideoStats(0, 1) else { return ([], [], [:]) }
        defer { free(p) }
        let j = (try? JSONSerialization.jsonObject(with: Data(String(cString: p).utf8))) as? [String: Any] ?? [:]
        let s = (j["samples"] as? [[Any]] ?? []).map {
            Sample(t: ($0[0] as? Double) ?? 0, e: $0[1] as? Double, n: ($0[2] as? Int) ?? -1, item: ($0[3] as? Double) ?? 0)
        }
        let ev = (j["events"] as? [[Any]] ?? []).map { (($0[0] as? Double) ?? 0, ($0[1] as? String) ?? "") }
        return (s, ev, j)
    }
    /// Bombea tf_frame_copy a 60 Hz durante `ms`; `script` son (ms, acción) ordenadas.
    func pump(_ ms: Double, _ script: [(Double, () -> Void)] = []) {
        let t0 = nowMs(); var tick = 0; var pending = script[...]
        while nowMs() - t0 < ms {
            while let f = pending.first, nowMs() - t0 >= f.0 { f.1(); pending = pending.dropFirst() }
            if let p = tf_frame_copy(0) { Unmanaged<AnyObject>.fromOpaque(p).release() }
            tick += 1
            let wait = t0 + Double(tick) * 1000.0 / 60.0 - nowMs()
            if wait > 0 { Thread.sleep(forTimeInterval: wait / 1000) }
        }
    }
    func pct(_ v: [Double], _ q: Double) -> Double {
        guard !v.isEmpty else { return .nan }
        let s = v.sorted(); return s[min(s.count - 1, Int(q * Double(s.count)))]
    }
    func outOfTol(_ e: Double?) -> Bool { guard let e else { return true }; return e < -toleranceMs || e >= 1.5 * frameMs }
    func clean(_ x: Double) -> Any { x.isFinite ? (x * 100).rounded() / 100 : NSNull() }
    func summarize(_ ss: [Sample]) -> [String: Any] {
        let es = ss.compactMap { $0.e }
        var rep = 0, skip = 0
        for i in 1..<max(ss.count, 1) where ss[i].n >= 0 && ss[i - 1].n >= 0 {
            let d = ss[i].n - ss[i - 1].n
            if d <= 0 { rep += 1 } else if d > 1 { skip += d - 1 }
        }
        return ["n": ss.count, "unreadable": ss.count - es.count, "median": clean(pct(es, 0.5)), "p95": clean(pct(es, 0.95)),
                "p99": clean(pct(es, 0.99)), "min": clean(es.min() ?? .nan), "max": clean(es.max() ?? .nan),
                "outPct": clean(ss.isEmpty ? .nan : Double(ss.filter { outOfTol($0.e) }.count) / Double(ss.count) * 100),
                "repeated": rep, "skipped": skip]
    }
    /// ms desde `from` hasta la primera muestra dentro de tolerancia que ya no se sale antes de `until`; nil si no se recupera.
    func recovery(_ ss: [Sample], from: Double, until: Double) -> Double? {
        let w = ss.filter { $0.t >= from && $0.t < until }
        var idx = w.count
        while idx > 0, !outOfTol(w[idx - 1].e) { idx -= 1 }
        guard idx < w.count else { return nil }
        return w[idx].t - from
    }
    var ok = true
    var cpuAll: [String: Any] = [:]
    func withCPU(_ name: String, _ body: () -> Void) {
        let c0 = cpuSeconds(); let t0 = nowMs()
        body()
        let pctCPU = (cpuSeconds() - c0) / ((nowMs() - t0) / 1000) * 100
        cpuAll[name] = clean(pctCPU)
        print(String(format: "  CPU %@: %.1f %%", name, pctCPU))
    }

    if cases == "steady" || cases == "all" {
        var out: [String: Any] = [:]
        for rate in [1.0, 0.7, 0.5] {
            _ = fetch()
            withCPU("steady\(rate)") {
                ffiDebugVideoClock(0, 0, rate, 1, 1)
                pump(11000)
            }
            let r = fetch()
            let first = r.samples.first
            let kept = r.samples.filter { $0.t >= 1000 }
            var s = summarize(kept)
            s["resyncs"] = r.stats["resyncs"] ?? 0; s["driftResyncs"] = r.stats["driftResyncs"] ?? 0
            s["firstItemTime"] = first?.item ?? NSNull()
            out["rate\(rate)"] = s
            print("steady rate \(rate): \(s)")
            if let o = s["outPct"] as? Double, o > 1 { ok = false }
            if (s["n"] as? Int ?? 0) == 0 { ok = false }
        }
        report["steady"] = out
    }
    if cases == "seek" || cases == "all" {
        let start = 5.0
        let targets = [20.0, 8.0, 0.0, 25.0, 2.0, max(0, duration - 2)]
        _ = fetch()
        ffiDebugVideoClock(0, start, 1, 1, 1)
        pump(2000)
        _ = fetch()
        var script: [(Double, () -> Void)] = []
        for (i, tg) in targets.enumerated() { script.append((Double(i) * 2500, { ffiDebugVideoClock(0, tg, 1, 1, 1) })) }
        withCPU("seek") { pump(Double(targets.count) * 2500, script) }
        let r = fetch()
        let jumps = r.events.filter { $0.1 == "clock" }.map { $0.0 }
        var recs: [Any] = []
        var worst = 0.0
        for (i, j) in jumps.enumerated() {
            let until = i + 1 < jumps.count ? jumps[i + 1] : (jumps.last ?? 0) + 2500
            if let ms = recovery(r.samples, from: j, until: until) { recs.append(clean(ms)); worst = max(worst, ms) } else { recs.append(NSNull()); worst = .infinity }
        }
        print("seek: saltos a \(targets), recuperacion ms \(recs), eventos \(r.events.count), resyncs \(r.stats["resyncs"] ?? 0)")
        report["seek"] = ["targets": targets, "recoveryMs": recs, "resyncs": r.stats["resyncs"] ?? 0, "driftResyncs": r.stats["driftResyncs"] ?? 0]
        if worst >= 300 { ok = false }
    }
    if cases == "loop" || cases == "all" {
        _ = fetch()
        ffiDebugVideoLoop(0, 4, 6, 1)
        ffiDebugVideoClock(0, 4, 1, 1, 1)
        withCPU("loop") { pump(12500) }
        ffiDebugVideoLoop(0, 0, 0, 0)
        let r = fetch()
        let wraps = r.events.filter { $0.1 == "clock" }.map { $0.0 }.dropFirst()
        var recs: [Any] = []
        let wl = Array(wraps)
        for (i, j) in wl.enumerated() {
            let until = i + 1 < wl.count ? wl[i + 1] : j + 2000
            if let ms = recovery(r.samples, from: j, until: until) { recs.append(clean(ms)) } else { recs.append(NSNull()) }
        }
        let s = summarize(r.samples.filter { $0.t >= 1000 })
        print("loop: vueltas \(wl.count), recuperacion ms \(recs), \(s), resyncs \(r.stats["resyncs"] ?? 0)")
        report["loop"] = ["wraps": wl.count, "recoveryMs": recs, "e": s, "resyncs": r.stats["resyncs"] ?? 0, "driftResyncs": r.stats["driftResyncs"] ?? 0]
    }
    report["cpuPercent"] = cpuAll
    ffiDebugVideoClose(0)
    if let rp = argValue("--report"), let d = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
        try? d.write(to: URL(fileURLWithPath: rp))
    }
    print(ok ? "RESULTADO: OK" : "RESULTADO: FALLA")
    exit(ok ? 0 : 1)
}
#endif

#if canImport(Darwin)
if CommandLine.arguments.contains("--video") {
    Thread.detachNewThread { runVideo() }
} else if CommandLine.arguments.contains("--frames") {
    Thread.detachNewThread { runFrames() }
} else {
    Thread.detachNewThread { run() }
}
dispatchMain()
#else
// El modo --frames solo existe en macOS.
if CommandLine.arguments.contains("--frames") {
    print("--frames no existe en esta plataforma")
    exit(2)
} else {
    Thread.detachNewThread { run() }
}
dispatchMain()
#endif
