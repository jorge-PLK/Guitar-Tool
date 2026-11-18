// Prueba a del paso 4 (Fase 7c): lo que AudioKit, StemKit, VideoKit y SourceKit piden al runtime.
// Una línea "OK|FALLO <pieza>: <números>" por pieza; código 1 si alguna falla.
import Dispatch
import Foundation
import Observation
import Synchronization
#if os(Windows)
import WinSDK
#endif

#if arch(arm64)
let arch = "arm64"
#elseif arch(x86_64)
let arch = "x86_64"
#else
let arch = "?"
#endif

nonisolated(unsafe) var failures = 0
func report(_ ok: Bool, _ name: String, _ detail: String) {
    print("\(ok ? "OK" : "FALLO") \(name): \(detail)")
    fflush(stdout)
    if !ok { failures += 1 }
}

// MARK: Reloj de host (sustituto de mach_absolute_time)

enum Host {
    #if os(Windows)
    static let frequency: Double = {
        var f = LARGE_INTEGER()
        QueryPerformanceFrequency(&f)
        return Double(f.QuadPart)
    }()
    static var ticks: Int64 {
        var c = LARGE_INTEGER()
        QueryPerformanceCounter(&c)
        return c.QuadPart
    }
    #else
    static let frequency: Double = 1e9
    static var ticks: Int64 { Int64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) }
    #endif
    static var seconds: Double { Double(ticks) / frequency }
}

// Modo eco: el propio exe imprime sus argumentos (ida y vuelta del entrecomillado de Process en Windows).
if CommandLine.arguments.dropFirst().first == "--echo-args" {
    for a in CommandLine.arguments.dropFirst(2) { print("«\(a)»") }
    exit(0)
}

print("tf-p8-runtime arch=\(arch)")

// QPC: frecuencia, resolución (menor salto distinto de cero) y coherencia con Date en 200 ms.
do {
    var minStep = Int64.max
    for _ in 0..<10_000 {
        let a = Host.ticks
        var b = Host.ticks
        while b == a { b = Host.ticks }
        minStep = min(minStep, b - a)
    }
    let h0 = Host.seconds, d0 = Date()
    Thread.sleep(forTimeInterval: 0.2)
    let dh = Host.seconds - h0, dd = Date().timeIntervalSince(d0)
    let res = Double(minStep) / Host.frequency * 1e9
    report(abs(dh - dd) < 0.002, "QPC", String(format: "frecuencia %.0f Hz, resolución %.0f ns, sleep(200 ms) QPC %.3f ms vs Date %.3f ms", Host.frequency, res, dh * 1e3, dd * 1e3))
}

// Mutex y Atomic: 8 hilos × 100 000 incrementos.
do {
    let m = Mutex(0)
    let a = Atomic<Int>(0)
    let t0 = Host.seconds
    DispatchQueue.concurrentPerform(iterations: 8) { _ in
        for _ in 0..<100_000 {
            m.withLock { $0 += 1 }
            a.wrappingAdd(1, ordering: .relaxed)
        }
    }
    let dt = (Host.seconds - t0) * 1e3
    let mv = m.withLock { $0 }, av = a.load(ordering: .relaxed)
    report(mv == 800_000 && av == 800_000, "Mutex+Atomic", "mutex \(mv), atomic \(av) de 800000 (\(String(format: "%.1f", dt)) ms)")
}

// @Observable con withObservationTracking (se llama al final: en la primera pasada el proceso cayó justo después).
@Observable final class Model: @unchecked Sendable { var value = 0 }
final class Counter: @unchecked Sendable { let n = Atomic<Int>(0) }
func observationTest() {
    let model = Model()
    let fired = Counter()
    withObservationTracking { _ = model.value } onChange: { fired.n.add(1, ordering: .relaxed) }
    print("  observable: tracking puesto"); fflush(stdout)
    model.value = 1
    print("  observable: value = 1"); fflush(stdout)
    model.value = 2
    print("  observable: value = 2"); fflush(stdout)
    report(fired.n.load(ordering: .relaxed) == 1, "@Observable", "onChange llamado \(fired.n.load(ordering: .relaxed)) vez (esperado 1)")
}

// DispatchSourceTimer: 40 disparos a 10 ms y a 16 ms; intervalo medio y peor desviación.
final class Stamps: @unchecked Sendable {
    let m = Mutex<[Double]>([])
}
func timerStats(ms: Int, count: Int, leeway: Int?) -> (mean: Double, worst: Double) {
    print("  timer \(ms) ms: cola"); fflush(stdout)
    let q = DispatchQueue(label: "p8.timer")
    let stamps = Stamps()
    let done = DispatchSemaphore(value: 0)
    print("  timer \(ms) ms: creando"); fflush(stdout)
    let t = DispatchSource.makeTimerSource(queue: q)
    print("  timer \(ms) ms: schedule"); fflush(stdout)
    if let leeway {
        t.schedule(deadline: .now(), repeating: .milliseconds(ms), leeway: .milliseconds(leeway))
    } else {
        t.schedule(deadline: .now(), repeating: .milliseconds(ms))
    }
    t.setEventHandler {
        let n = stamps.m.withLock { s -> Int in s.append(Host.seconds); return s.count }
        if n == count + 1 { done.signal() }
    }
    print("  timer \(ms) ms: resume"); fflush(stdout)
    t.resume()
    _ = done.wait(timeout: .now() + .seconds(10))
    t.cancel()
    q.sync {}
    let s = stamps.m.withLock { $0 }
    guard s.count > 1 else { return (.nan, .nan) }
    let d = zip(s.dropFirst(), s).map { ($0 - $1) * 1e3 }
    let mean = d.reduce(0, +) / Double(d.count)
    return (mean, d.map { abs($0 - Double(ms)) }.max()!)
}
// 20 ms sin leeway (StemScheduler.refillInterval) y 16 ms con leeway 1 ms (CameraCapture simulada); en Windows,
// otra vez tras timeBeginPeriod(1) (el tic por defecto es 15,6 ms).
func timerRound(_ tag: String) {
    for (ms, leeway) in [(20, nil), (16, 1)] as [(Int, Int?)] {
        let (mean, worst) = timerStats(ms: ms, count: 40, leeway: leeway)
        // Se mira la media: solo se usa para rellenos de stems y la cámara simulada.
        report(abs(mean - Double(ms)) < Double(ms) * 0.25, "DispatchSourceTimer \(ms) ms leeway \(leeway.map { "\($0) ms" } ?? "no")\(tag)",
               String(format: "media %.2f ms, peor desviación %.2f ms", mean, worst))
    }
}
timerRound("")
#if os(Windows)
timeBeginPeriod(1)
timerRound(" + timeBeginPeriod(1)")
do {
    let t0 = Host.seconds
    Thread.sleep(forTimeInterval: 0.005)
    print(String(format: "  Thread.sleep(5 ms) con timeBeginPeriod(1): %.2f ms", (Host.seconds - t0) * 1e3))
}
timeEndPeriod(1)
#endif

// Process: cmd /c echo, ruta con espacios, argumentos con espacios y comillas, terminate().
func run(_ exe: String, _ args: [String], cwd: String? = nil) -> (code: Int32, out: String, err: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    do { try p.run() } catch { return (-1, "", "\(error)") }
    let o = out.fileHandleForReading.readDataToEndOfFile()
    let e = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: o, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            String(decoding: e, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}
#if os(Windows)
let cmd = "C:\\Windows\\System32\\cmd.exe"
do {
    let r = run(cmd, ["/c", "echo", "hola"])
    report(r.code == 0 && r.out == "hola", "Process cmd /c echo", "código \(r.code), salida «\(r.out)» \(r.err)")
}
do {
    // Ejecutable y directorio de trabajo con espacios (como %LOCALAPPDATA% de un usuario «Jorge F»).
    let dir = "C:\\ToneForge\\p8 con espacios"
    try? FileManager.default.removeItem(atPath: dir)
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let exe = dir + "\\cmd copia.exe"
    try FileManager.default.copyItem(atPath: cmd, toPath: exe)
    let r = run(exe, ["/c", "cd"], cwd: dir)
    report(r.code == 0 && r.out == dir, "Process ruta con espacios", "código \(r.code), cwd «\(r.out)» \(r.err)")
} catch {
    report(false, "Process ruta con espacios", "\(error)")
}
do {
    // Argumentos con espacios, comillas, barras finales y no ASCII (títulos y rutas que se pasan a yt-dlp/ffmpeg),
    // ida y vuelta a través del propio exe.
    let sent = ["a b", "\"c\"", "d\\", "e\\\\\"f", "C:\\Mis temas\\", "canción ñ €", "x"]
    let r = run(CommandLine.arguments[0], ["--echo-args"] + sent)
    // "\r\n" es un solo Character en Swift: se parte por isNewline, no por "\n".
    let got = r.out.split(whereSeparator: \.isNewline).map { String($0.dropFirst().dropLast()) }
    let bad = zip(sent, got).filter { $0 != $1 }.map { "«\($0)»→«\($1)»" }
    report(r.code == 0 && got.count == sent.count && bad.isEmpty, "Process args (eco)",
           "\(got.count)/\(sent.count) recibidos, distintos: \(bad.isEmpty ? "ninguno" : bad.joined(separator: " "))")
}
// terminate(): hijo directo (tf-separate) y nieto detrás de cmd (yt-dlp lanza ffmpeg/deno).
for (name, exe, args) in [("directo ping", "C:\\Windows\\System32\\PING.EXE", ["-n", "30", "127.0.0.1"]),
                          ("cmd→ping", cmd, ["/c", "ping", "-n", "30", "127.0.0.1"])] {
    do {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        Thread.sleep(forTimeInterval: 0.3)
        let t0 = Host.seconds
        p.terminate()
        p.waitUntilExit()
        let ms = (Host.seconds - t0) * 1e3
        report(ms < 2000, "Process terminate \(name)",
               String(format: "waitUntilExit volvió en %.1f ms, motivo %@, código %d", ms, p.terminationReason == .uncaughtSignal ? "señal" : "salida", p.terminationStatus))
    } catch {
        report(false, "Process terminate \(name)", "\(error)")
    }
}
#else
do {
    let r = run("/bin/echo", ["hola"])
    report(r.code == 0 && r.out == "hola", "Process echo", "código \(r.code), salida «\(r.out)»")
}
#endif

observationTest()
print("  observable: modelo liberado"); fflush(stdout)

print("fallos \(failures)")
exit(failures == 0 ? 0 : 1)
