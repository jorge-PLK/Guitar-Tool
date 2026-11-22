import Foundation
#if os(Windows)
import WinSDK

// Humo de P9 7b en Windows: carga AppCoreFFI.dll con LoadLibrary/GetProcAddress (como hará el runner/Dart FFI) y
// ejercita solo la ABI C. `ffi-smoke` enlazaría el código Swift dentro del .exe y no probaría la DLL.
// Vía 1 sin Flutter: el hilo principal se queda en tf_core_run_main() (dispatchMain de la DLL); el trabajo va en otro hilo.
// Umbrales como ffi-smoke (docs/flutter/arquitectura.md + encargo P9 2.1).
let medianLimitMs = 5.0
let p99LimitMs = 16.0
let rounds = 1000
let methods = ["app.info", "library.list", "settings.get", "audio.devices"]

typealias MessageCb = @convention(c) (UnsafePointer<UInt8>?, Int32) -> Void

nonisolated(unsafe) let lib: HMODULE = {
    guard let h = LoadLibraryW("AppCoreFFI.dll".wide) else {
        print("FALLA: LoadLibrary(AppCoreFFI.dll) error \(GetLastError())"); exit(1)
    }
    return h
}()
func sym<T>(_ name: String, _ type: T.Type) -> T {
    guard let p = GetProcAddress(lib, name) else { print("FALLA: falta la exportacion \(name)"); exit(1) }
    return unsafeBitCast(p, to: type)
}
nonisolated(unsafe) let tf_core_start = sym("tf_core_start", (@convention(c) (UnsafePointer<CChar>?, MessageCb?, UnsafeRawPointer?) -> Int32).self)
nonisolated(unsafe) let tf_core_send = sym("tf_core_send", (@convention(c) (UnsafePointer<UInt8>?, Int32) -> Void).self)
nonisolated(unsafe) let tf_core_free = sym("tf_core_free", (@convention(c) (UnsafePointer<UInt8>?) -> Void).self)
nonisolated(unsafe) let tf_core_shutdown = sym("tf_core_shutdown", (@convention(c) (Int32) -> Void).self)
nonisolated(unsafe) let tf_debug_live_buffers = sym("tf_debug_live_buffers", (@convention(c) () -> Int64).self)
nonisolated(unsafe) let tf_debug_emit = sym("tf_debug_emit", (@convention(c) (Int32, Int32, Int32) -> Int32).self)
nonisolated(unsafe) let tf_core_run_main = sym("tf_core_run_main", (@convention(c) () -> Void).self)
nonisolated(unsafe) let tf_debug_mainactor_selftest = sym("tf_debug_mainactor_selftest", (@convention(c) (Int32) -> Int32).self)
nonisolated(unsafe) let tf_debug_is_main_thread = sym("tf_debug_is_main_thread", (@convention(c) () -> Int32).self)
nonisolated(unsafe) let tf_debug_apartment = sym("tf_debug_apartment", (@convention(c) () -> Int32).self)

extension String { var wide: [UInt16] { Array(self.utf16) + [0] } }

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

nonisolated(unsafe) let onMessage: MessageCb = { ptr, len in
    let t = nowMs()
    guard let ptr else { return }
    let data = Data(bytes: ptr, count: Int(len))
    let size = Int(len)
    tf_core_free(ptr)
    guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
    if let event = obj["event"] as? String {
        let p = obj["payload"] as? [String: Any]
        inbox.lock.lock()
        switch event {
        case "core.shutdown":
            inbox.shutdownClean = p?["clean"] as? Bool; inbox.shutdownAt = t
            inbox.lock.unlock(); inbox.shutdownSem.signal()
        case "probe.mainactor":
            inbox.mainActorOK = p?["mainActor"] as? Bool; inbox.dispatchMainOK = p?["dispatchMain"] as? Bool
            inbox.mainActorMs = p?["ms"] as? Int
            inbox.lock.unlock(); inbox.mainActorSem.signal()
        case "probe.tick":
            inbox.tickSeqs.append((p?["seq"] as? Int) ?? -1); inbox.tickSizes.append(size)
            inbox.lock.unlock()
        case "probe.done":
            inbox.doneCount = p?["count"] as? Int
            inbox.lock.unlock(); inbox.probeSem.signal()
        default: inbox.lock.unlock()
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

func argValue(_ flag: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
    return a[i + 1]
}

func run() {
    guard let projects = argValue("--projects-folder"), let support = argValue("--support-dir") else {
        print("uso: ffi-smoke-win --projects-folder <dir> --support-dir <dir>"); exit(1)
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

    var times: [Double] = []
    times.reserveCapacity(rounds * methods.count)
    for _ in 0..<rounds {
        for m in methods {
            let (ms, err) = call(m)
            times.append(ms)
            if err != nil { errors += 1 }
        }
    }
    times.sort()
    let median = times[times.count / 2]
    let p99 = times[Int(Double(times.count - 1) * 0.99)]
    let maxMs = times.last!
    let live = tf_debug_live_buffers()
    print(String(format: "idas y vueltas: %d, errores: %d", times.count, errors))
    print(String(format: "mediana %.3f ms, p99 %.3f ms, max %.3f ms", median, p99, maxMs))
    print("live_buffers: \(live)")
    check(errors == 0, "0 errores")
    check(median < medianLimitMs, "mediana < \(medianLimitMs) ms")
    check(p99 < p99LimitMs, "p99 < \(p99LimitMs) ms")

    let emitRC = tf_debug_emit(60, 120, 300)
    check(emitRC == 0, "tf_debug_emit == 0")
    let emitDone = emitRC == 0 && inbox.probeSem.wait(timeout: .now() + 10) == .success
    inbox.lock.lock()
    let seqs = inbox.tickSeqs; let sizes = inbox.tickSizes; let done = inbox.doneCount
    inbox.lock.unlock()
    let emitOK = emitDone && seqs == Array(0..<120) && sizes.allSatisfy { $0 == 300 } && done == 120
    print("emisor: \(seqs.count) ticks, done \(done.map { "\($0)" } ?? "?"), orden \(seqs == Array(0..<120))")
    check(emitOK, "120 ticks en orden, 300 bytes, done=120")
    check(tf_debug_live_buffers() == 0, "emisor: live_buffers == 0")

    // P9 prueba 7: cola principal / @MainActor drenados (el hilo principal esta en tf_core_run_main).
    let maRC = tf_debug_mainactor_selftest(3000)
    check(maRC == 0, "tf_debug_mainactor_selftest == 0")
    let maGot = maRC == 0 && inbox.mainActorSem.wait(timeout: .now() + 5) == .success
    inbox.lock.lock(); let maA = inbox.mainActorOK; let maD = inbox.dispatchMainOK; let maMs = inbox.mainActorMs; inbox.lock.unlock()
    print("mainactor: evento \(maGot ? "recibido" : "NO recibido"), mainActor \(maA.map { "\($0)" } ?? "?"), dispatchMain \(maD.map { "\($0)" } ?? "?"), \(maMs.map { "\($0)" } ?? "?") ms")
    check(maGot && maA == true && maD == true, "probe.mainactor con mainActor y dispatchMain a true")
    let isMain = tf_debug_is_main_thread()
    print("is_main_thread (hilo de trabajo): \(isMain), apartment (hilo de trabajo): \(tf_debug_apartment())")
    check(isMain == 0, "tf_debug_is_main_thread == 0 desde el hilo de trabajo")

    let tShutdown = nowMs()
    tf_core_shutdown(5000)
    let got = inbox.shutdownSem.wait(timeout: .now() + 8) == .success
    inbox.lock.lock(); let clean = inbox.shutdownClean; let at = inbox.shutdownAt; inbox.lock.unlock()
    print(String(format: "shutdown: evento %@, clean %@, %.0f ms", got ? "recibido" : "NO recibido", clean.map { "\($0)" } ?? "?", at - tShutdown))
    check(got && clean == true, "clean == true")
    check(tf_debug_live_buffers() == 0 && live == 0, "live_buffers == 0")
    print(ok ? "RESULTADO: OK" : "RESULTADO: FALLA")
    exit(ok ? 0 : 1)
}

Thread.detachNewThread { run() }
tf_core_run_main()
#else
print("ffi-smoke-win solo existe en Windows; en macOS usa ffi-smoke.")
#endif
