// tf-p8-wasapi (parte 7.7, Fase 7c paso 7): prueba el shim CWASAPI.
//   devices                                   endpoints, formato de mezcla y periodos
//   run --seconds N [--exclusive] [--period F] [--rate R] [--render ID] [--capture ID]
//                                             dúplex por eventos, SILENCIO en la salida, la captura se descarta;
//                                             periodos, jitter, monotonía de marcas, discontinuidades, deriva
//   restarts --count N [--seconds S] [--exclusive] [...]
//                                             abre y cierra N veces: variación del desfase captura-salida
//   (sin argumentos)                          devices + run --seconds 2 + restarts --count 3 --seconds 1.5
// En una VM los números de latencia y desfase NO significan nada (tarjeta virtual); sí valen apertura, eventos,
// periodos, monotonía y estabilidad entre reinicios.
import Foundation

#if os(Windows)
import CWASAPI
import NativePlatform

// MARK: - Utilidades

func cstr<T>(_ t: T) -> String {
    withUnsafeBytes(of: t) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
}
func hex(_ hr: Int32) -> String { "0x" + String(UInt32(bitPattern: hr), radix: 16, uppercase: true) }
func f(_ x: Double, _ d: Int = 3) -> String { String(format: "%.\(d)f", x) }
func ms100ns(_ t: Int64) -> String { f(Double(t) / 1e4) + " ms" }
func fmtString(_ x: wasapi_format) -> String {
    "\(x.sample_rate) Hz, \(x.channels) ch, \(x.is_float != 0 ? "float" : "int")\(x.bits)/\(x.valid_bits)"
}
func pathName(_ p: Int32) -> String {
    switch Int(p) {
    case WASAPI_PATH_CLIENT3_SHARED: return "IAudioClient3::InitializeSharedAudioStream"
    case WASAPI_PATH_CLIENT_SHARED: return "IAudioClient::Initialize (compartido)"
    case WASAPI_PATH_AUTOCONVERT: return "IAudioClient::Initialize (compartido, AUTOCONVERTPCM)"
    case WASAPI_PATH_EXCLUSIVE: return "IAudioClient::Initialize (exclusivo)"
    default: return "ninguno"
    }
}
func eventName(_ k: Int) -> String {
    switch k {
    case WASAPI_EVENT_DEFAULT_CHANGED: return "cambio de dispositivo por defecto"
    case WASAPI_EVENT_DEVICE_REMOVED: return "dispositivo retirado"
    case WASAPI_EVENT_DEVICE_INVALIDATED: return "dispositivo invalidado"
    case WASAPI_EVENT_STREAM_ERROR: return "error del flujo"
    case WASAPI_EVENT_STALLED: return "flujo colgado"
    case WASAPI_EVENT_FORMAT_CHANGED: return "cambio de formato"
    default: return "evento \(k)"
    }
}

struct Stats {
    var mean = 0.0, p50 = 0.0, p99 = 0.0, max = 0.0, min = 0.0, std = 0.0, n = 0
    init(_ xs: [Double]) {
        guard !xs.isEmpty else { return }
        let s = xs.sorted()
        n = s.count
        mean = s.reduce(0, +) / Double(n)
        std = (s.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(n)).squareRoot()
        p50 = s[n / 2]
        p99 = s[Swift.min(n - 1, Int((Double(n) * 0.99).rounded(.up)) - 1)]
        max = s[n - 1]
        min = s[0]
    }
    func line(_ unit: String, _ d: Int = 3) -> String {
        "media \(f(mean, d)) · p50 \(f(p50, d)) · p99 \(f(p99, d)) · máx \(f(max, d)) · mín \(f(min, d)) \(unit) (n = \(n))"
    }
}

/// Recta y = a + b·x por mínimos cuadrados centrada; residuos en unidades de y.
struct Fit {
    var b = 0.0, residualStd = 0.0, residualMax = 0.0, x0 = 0.0, y0 = 0.0, ok = false
    init(_ x: [Double], _ y: [Double]) {
        let n = Double(x.count)
        guard x.count >= 3 else { return }
        x0 = x.reduce(0, +) / n
        y0 = y.reduce(0, +) / n
        var sxx = 0.0, sxy = 0.0
        for i in x.indices { sxx += (x[i] - x0) * (x[i] - x0); sxy += (x[i] - x0) * (y[i] - y0) }
        guard sxx > 0 else { return }
        b = sxy / sxx
        var ss = 0.0
        for i in x.indices {
            let r = y[i] - (y0 + b * (x[i] - x0))
            ss += r * r
            residualMax = Swift.max(residualMax, abs(r))
        }
        residualStd = (ss / n).squareRoot()
        ok = true
    }
    func y(_ x: Double) -> Double { y0 + b * (x - x0) }
}

// MARK: - Marcas (memoria fija; el hilo de audio no reserva ni toma cerrojos)

struct Marks {
    let cap: Int
    var rCount = 0, cCount = 0, overflow = 0
    let rWake, rWritten, rPos, rQPC: UnsafeMutablePointer<UInt64>
    let rFrames: UnsafeMutablePointer<UInt32>
    let cWake, cPos, cDev, cQPC: UnsafeMutablePointer<UInt64>
    let cFrames, cFlags: UnsafeMutablePointer<UInt32>
    var sync: DuplexClockSync
    var resets = 0
    var frequency: UInt64 = 0
    var events: (Int, Int, Int, Int, Int, Int, Int, Int) = (0, 0, 0, 0, 0, 0, 0, 0)

    init(cap: Int) {
        self.cap = cap
        rWake = .allocate(capacity: cap); rWritten = .allocate(capacity: cap)
        rPos = .allocate(capacity: cap); rQPC = .allocate(capacity: cap); rFrames = .allocate(capacity: cap)
        cWake = .allocate(capacity: cap); cPos = .allocate(capacity: cap); cDev = .allocate(capacity: cap); cQPC = .allocate(capacity: cap)
        cFrames = .allocate(capacity: cap); cFlags = .allocate(capacity: cap)
        sync = DuplexClockSync(sampleRate: 48_000)
    }

    func free() {
        for p in [rWake, rWritten, rPos, rQPC, cWake, cPos, cDev, cQPC] { p.deallocate() }
        for p in [rFrames, cFrames, cFlags] { p.deallocate() }
    }

    mutating func reset(sampleRate: Double) {
        rCount = 0; cCount = 0; overflow = 0; resets = 0
        sync = DuplexClockSync(sampleRate: sampleRate)
        events = (0, 0, 0, 0, 0, 0, 0, 0)
    }

    mutating func onRender(_ frames: UInt32, _ i: wasapi_render_info) {
        frequency = i.clock_frequency
        if i.clock_qpc_100ns != 0 {
            sync.addRenderClock(position: i.clock_position, frequency: i.clock_frequency,
                                hostSeconds: DuplexClockSync.seconds(qpc100ns: i.clock_qpc_100ns))
        }
        guard rCount < cap else { overflow += 1; return }
        rWake[rCount] = i.wake_qpc_ticks; rWritten[rCount] = i.frames_written
        rPos[rCount] = i.clock_position; rQPC[rCount] = i.clock_qpc_100ns; rFrames[rCount] = frames
        rCount += 1
    }

    mutating func onCapture(_ frames: UInt32, _ i: wasapi_capture_info) {
        if i.flags & UInt32(WASAPI_CAPTURE_DISCONTINUITY) != 0, cCount > 0 { sync.resetCapture(); resets += 1 }
        let tsOK = i.flags & UInt32(WASAPI_CAPTURE_TIMESTAMP_ERROR) == 0 && i.qpc_100ns != 0
        _ = sync.addCapturePacket(devicePosition: i.stream_position,
                                  hostSeconds: tsOK ? DuplexClockSync.seconds(qpc100ns: i.qpc_100ns) : 0)
        guard cCount < cap else { overflow += 1; return }
        cWake[cCount] = i.wake_qpc_ticks; cPos[cCount] = i.stream_position; cDev[cCount] = i.device_position; cQPC[cCount] = i.qpc_100ns
        cFrames[cCount] = frames; cFlags[cCount] = i.flags
        cCount += 1
    }

    mutating func onEvent(_ kind: Int32) {
        switch kind {
        case 1: events.1 += 1
        case 2: events.2 += 1
        case 3: events.3 += 1
        case 4: events.4 += 1
        case 5: events.5 += 1
        case 6: events.6 += 1
        default: events.0 += 1
        }
    }
}

let renderCB: wasapi_render_cb = { ctx, _, frames, _, info in
    ctx!.assumingMemoryBound(to: Marks.self).pointee.onRender(frames, info!.pointee)   // el búfer llega a cero: silencio
}
let captureCB: wasapi_capture_cb = { ctx, _, frames, _, info in
    ctx!.assumingMemoryBound(to: Marks.self).pointee.onCapture(frames, info!.pointee)  // las muestras se descartan
}
let eventCB: wasapi_event_cb = { ctx, kind, _, _, _ in
    ctx!.assumingMemoryBound(to: Marks.self).pointee.onEvent(kind)
}

// MARK: - Opciones

struct Options {
    var seconds = 2.0, count = 3, exclusive = false, period: UInt32 = 0, rate: UInt32 = 0
    var renderID = "", captureID = "", dump = 0
    init(_ args: ArraySlice<String>) throws {
        var it = args.makeIterator()
        while let a = it.next() {
            func value() throws -> String {
                guard let v = it.next() else { throw ProbeError("falta el valor de \(a)") }
                return v
            }
            switch a {
            case "--seconds": seconds = Double(try value()) ?? seconds
            case "--count": count = Int(try value()) ?? count
            case "--exclusive": exclusive = true
            case "--period": period = UInt32(try value()) ?? 0
            case "--rate": rate = UInt32(try value()) ?? 0
            case "--render": renderID = try value()
            case "--capture": captureID = try value()
            case "--dump": dump = Int(try value()) ?? 0
            default: throw ProbeError("opción desconocida \(a)")
            }
        }
    }
}

struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

// MARK: - Sesión

final class Session {
    let marks: UnsafeMutablePointer<Marks>
    var stream: OpaquePointer?
    var info = wasapi_stream_info()
    var status = wasapi_stream_status()
    var openMS = 0.0, startMS = 0.0, stopMS = 0.0

    init(seconds: Double) {
        marks = .allocate(capacity: 1)
        marks.initialize(to: Marks(cap: Int(seconds * 4000) + 4096))   // hasta ~0,25 ms de periodo
    }
    deinit { close(); marks.pointee.free(); marks.deinitialize(count: 1); marks.deallocate() }

    func open(_ o: Options) throws {
        var p = wasapi_open_params()
        p.mode = Int32(o.exclusive ? WASAPI_MODE_EXCLUSIVE : WASAPI_MODE_SHARED)
        p.sample_rate = o.rate
        p.period_frames = o.period
        p.use_render = 1
        p.use_capture = 1
        p.render = renderCB
        p.capture = captureCB
        p.event = eventCB
        p.ctx = UnsafeMutableRawPointer(marks)
        var step: UnsafePointer<CChar>?
        let t0 = HostClock.now()
        var opened: OpaquePointer?
        var got = wasapi_stream_info()
        let hr = o.renderID.withCString { rid in
            o.captureID.withCString { cid in   // el shim no guarda los punteros
                p.render_id = rid
                p.capture_id = cid
                return wasapi_open(&p, &opened, &got, &step)
            }
        }
        stream = opened
        info = got
        openMS = HostClock.seconds(ticks: HostClock.now() - t0) * 1e3
        guard hr == 0 else {
            throw ProbeError("wasapi_open falló en \(step.map { String(cString: $0) } ?? "?"): \(hex(hr))")
        }
        marks.pointee.reset(sampleRate: Double(info.render_format.sample_rate))
    }

    func run(seconds: Double) throws {
        guard let stream else { throw ProbeError("sin flujo") }
        let t0 = HostClock.now()
        let hr = wasapi_start(stream)
        startMS = HostClock.seconds(ticks: HostClock.now() - t0) * 1e3
        guard hr == 0 else { throw ProbeError("wasapi_start: \(hex(hr))") }
        Thread.sleep(forTimeInterval: seconds)
        let t1 = HostClock.now()
        wasapi_stop(stream)
        stopMS = HostClock.seconds(ticks: HostClock.now() - t1) * 1e3
        wasapi_get_status(stream, &status)
    }

    func close() {
        wasapi_close(stream)
        stream = nil
    }
}

// MARK: - Análisis

struct Analysis {
    var renderInterval = Stats([]), captureInterval = Stats([])
    var renderDev = Stats([]), renderFrames = Stats([]), captureFrames = Stats([])
    var renderQPCBack = 0, renderQPCEqual = 0, renderPosBack = 0, renderPosEqual = 0, writtenErrors = 0
    var captureQPCBack = 0, captureGaps = 0, captureOverlaps = 0
    var discontinuityFirst = 0, discontinuityLater = 0, silent = 0, tsError = 0
    var renderFit = Fit([], []), captureFit = Fit([], [])
    var offsetFull: Double?
    var nominalMS = 0.0
    var counterDrift = Stats([])

    init(_ m: Marks, _ info: wasapi_stream_info) {
        let rate = Double(info.render_format.sample_rate)
        let tick = HostClock.timebase / 1e6   // ms por tick
        nominalMS = Double(info.render_period_frames) / rate * 1e3
        var ri: [Double] = [], rd: [Double] = [], rf: [Double] = []
        for i in 0..<m.rCount {
            rf.append(Double(m.rFrames[i]))
            if i > 0 {
                let d = Double(m.rWake[i] &- m.rWake[i - 1]) * tick
                ri.append(d); rd.append(abs(d - nominalMS))
                if m.rQPC[i] != 0, m.rQPC[i - 1] != 0 {
                    if m.rQPC[i] < m.rQPC[i - 1] { renderQPCBack += 1 } else if m.rQPC[i] == m.rQPC[i - 1] { renderQPCEqual += 1 }
                }
                if m.rPos[i] < m.rPos[i - 1] { renderPosBack += 1 } else if m.rPos[i] == m.rPos[i - 1] { renderPosEqual += 1 }
                if m.rWritten[i] != m.rWritten[i - 1] + UInt64(m.rFrames[i - 1]) { writtenErrors += 1 }
            }
        }
        renderInterval = Stats(ri); renderDev = Stats(rd); renderFrames = Stats(rf)
        var ci: [Double] = [], cf: [Double] = []
        var lastWake: UInt64 = 0
        for i in 0..<m.cCount {
            cf.append(Double(m.cFrames[i]))
            if m.cWake[i] != lastWake {
                if lastWake != 0 { ci.append(Double(m.cWake[i] &- lastWake) * tick) }
                lastWake = m.cWake[i]
            }
            let fl = m.cFlags[i]
            if fl & UInt32(WASAPI_CAPTURE_DISCONTINUITY) != 0 { if i == 0 { discontinuityFirst += 1 } else { discontinuityLater += 1 } }
            if fl & UInt32(WASAPI_CAPTURE_SILENT) != 0 { silent += 1 }
            if fl & UInt32(WASAPI_CAPTURE_TIMESTAMP_ERROR) != 0 { tsError += 1 }
            if i > 0 {
                if m.cQPC[i] != 0, m.cQPC[i - 1] != 0, m.cQPC[i] <= m.cQPC[i - 1] { captureQPCBack += 1 }
                let expected = m.cPos[i - 1] + UInt64(m.cFrames[i - 1])
                if m.cPos[i] > expected { captureGaps += 1 } else if m.cPos[i] < expected { captureOverlaps += 1 }
            }
        }
        captureInterval = Stats(ci); captureFrames = Stats(cf)
        // Rectas fotograma(host) con todas las marcas: residuos = temblor de las marcas; offset con todos los puntos.
        let freq = Double(max(1, m.frequency))
        var rx: [Double] = [], ry: [Double] = [], cx: [Double] = [], cy: [Double] = []
        for i in 0..<m.rCount where m.rQPC[i] != 0 {
            rx.append(Double(m.rQPC[i]) / 1e7); ry.append(Double(m.rPos[i]) * rate / freq)
        }
        // Tras una discontinuidad la posición de captura salta: la recta solo usa el último tramo continuo.
        var firstC = 0
        for i in 1..<max(1, m.cCount) where m.cFlags[i] & UInt32(WASAPI_CAPTURE_DISCONTINUITY) != 0 { firstC = i }
        for i in firstC..<m.cCount where m.cQPC[i] != 0 && m.cFlags[i] & UInt32(WASAPI_CAPTURE_TIMESTAMP_ERROR) == 0 {
            cx.append(Double(m.cQPC[i]) / 1e7); cy.append(Double(m.cPos[i]))
        }
        // Contador del flujo frente a la posición del endpoint (solo difieren con AUTOCONVERTPCM): su recorrido es lo
        // que el contador consecutivo se aparta de la marca del dispositivo dentro de la sesión.
        let ratio = Double(info.capture_format.sample_rate) / Double(max(1, info.capture_device_rate))
        var dev: [Double] = []
        for i in firstC..<m.cCount { dev.append(Double(m.cPos[i]) - Double(m.cDev[i]) * ratio) }
        counterDrift = Stats(dev)
        renderFit = Fit(rx, ry); captureFit = Fit(cx, cy)
        // Evaluado en el mismo instante en que DuplexClockSync fija el suyo (media de las marcas de captura hasta tener
        // `minimumPoints` de cada lado), para que la deriva no se cuele en la comparación.
        let k = DuplexClockSync.defaultMinimumPoints
        if renderFit.ok, captureFit.ok, rx.count >= k, cx.count >= k {
            let tFix = max(rx[k - 1], cx[k - 1])
            let early = cx.filter { $0 <= tFix }
            let t = early.reduce(0, +) / Double(max(1, early.count))
            offsetFull = renderFit.y(t) - captureFit.y(t)
        }
    }
}

// MARK: - Comandos

func devices() throws {
    var list = [wasapi_device_info](repeating: wasapi_device_info(), count: 64)
    let n = wasapi_enumerate(&list, 64)
    guard n >= 0 else { throw ProbeError("wasapi_enumerate: \(hex(n))") }
    print("DEVICES \(n) endpoints activos")
    for d in list.prefix(Int(min(n, 64))) {
        let flow = Int(d.flow) == WASAPI_FLOW_RENDER ? "render " : "captura"
        print("  [\(flow)]\(d.is_default != 0 ? " *" : "  ") \(cstr(d.name))")
        print("      id \(cstr(d.id))")
        print("      mezcla \(fmtString(d.mix)) · periodo por defecto \(ms100ns(d.default_period_100ns)) · mínimo (exclusivo) \(ms100ns(d.minimum_period_100ns))")
        if d.has_client3 != 0 {
            let r = Double(max(1, d.mix.sample_rate))
            print("      IAudioClient3 motor: defecto \(d.engine_default_frames) · paso \(d.engine_fundamental_frames) · mín \(d.engine_min_frames) (\(f(Double(d.engine_min_frames) / r * 1e3)) ms) · máx \(d.engine_max_frames) fotogramas")
        } else {
            print("      IAudioClient3: no")
        }
        print("      exclusivo float32 al formato de mezcla: \(d.exclusive_float_ok != 0 ? "sí" : "no")\(d.hresult != 0 ? " · error \(hex(d.hresult))" : "")")
    }
}

func printOpen(_ s: Session) {
    let i = s.info
    print("OPEN  \(i.mode == Int32(WASAPI_MODE_EXCLUSIVE) ? "exclusivo" : "compartido") en \(f(s.openMS, 1)) ms")
    print("      salida  \(cstr(i.render_name)): \(pathName(i.render_path)); \(fmtString(i.render_format)); búfer \(i.render_buffer_frames) · periodo \(i.render_period_frames) fotogramas; latencia de flujo \(ms100ns(i.render_latency_100ns)); IAudioClock \(i.clock_frequency) Hz")
    print("      entrada \(cstr(i.capture_name)): \(pathName(i.capture_path)); \(fmtString(i.capture_format)); búfer \(i.capture_buffer_frames) · periodo \(i.capture_period_frames) fotogramas; latencia de flujo \(ms100ns(i.capture_latency_100ns)); endpoint a \(i.capture_device_rate) Hz")
}

func printEvents(_ m: Marks) {
    let e = m.events
    let all = [(1, e.1), (2, e.2), (3, e.3), (4, e.4), (5, e.5), (6, e.6), (0, e.0)].filter { $0.1 > 0 }
    print("EVENT \(all.isEmpty ? "ninguno" : all.map { "\(eventName($0.0)) ×\($0.1)" }.joined(separator: ", "))")
}

func run(_ o: Options) throws {
    let s = Session(seconds: o.seconds)
    try s.open(o)
    printOpen(s)
    try s.run(seconds: o.seconds)
    let m = s.marks.pointee, st = s.status
    let a = Analysis(m, s.info)
    let rate = Double(s.info.render_format.sample_rate)
    print("RUN   \(f(o.seconds, 1)) s · arranque \(f(s.startMS, 1)) ms · parada \(f(s.stopMS, 1)) ms · MMCSS «Pro Audio» \(st.mmcss_ok != 0 ? "sí" : "NO") · motivo de parada \(st.stop_reason == 0 ? "pedida" : eventName(Int(st.stop_reason)))\(st.last_hresult != 0 ? " (\(hex(st.last_hresult)))" : "")")
    print("      búferes de salida \(st.render_buffers) · sin hueco \(st.render_starved) · paquetes de captura \(st.capture_packets) · despertares \(st.wakeups) · GetPosition fallidos \(st.clock_failures)\(m.overflow > 0 ? " · marcas no guardadas \(m.overflow)" : "")")
    print("      fotogramas por búfer de salida: \(a.renderFrames.line("", 1))")
    print("      fotogramas por paquete de captura: \(a.captureFrames.line("", 1))")
    print("JITTER periodo nominal \(f(a.nominalMS)) ms")
    print("      intervalo de despertar (salida): \(a.renderInterval.line("ms"))")
    print("      |intervalo − nominal| (salida): \(a.renderDev.line("ms"))")
    print("      intervalo de despertar (captura): \(a.captureInterval.line("ms"))")
    print("MARKS QPC de IAudioClock: retrocesos \(a.renderQPCBack) · repetidos \(a.renderQPCEqual); posición: retrocesos \(a.renderPosBack) · repetidas \(a.renderPosEqual); fotogramas escritos no consecutivos \(a.writtenErrors)")
    print("      QPC de captura: retrocesos o repetidos \(a.captureQPCBack); posición de captura (flujo): huecos \(a.captureGaps) · solapes \(a.captureOverlaps)")
    if s.info.capture_device_rate != s.info.capture_format.sample_rate {
        print("      AUTOCONVERTPCM \(s.info.capture_device_rate) → \(s.info.capture_format.sample_rate) Hz: contador del flujo − u64DevicePosition·razón: recorrido \(f(a.counterDrift.max - a.counterDrift.min, 1)) fotogramas (\(a.counterDrift.line("", 1)))")
    }
    if a.renderFit.ok {
        print("      temblor de la marca de salida (residuo de la recta): σ \(f(a.renderFit.residualStd / rate * 1e6, 1)) µs · máx \(f(a.renderFit.residualMax / rate * 1e6, 1)) µs")
    }
    if a.captureFit.ok {
        print("      temblor de la marca de captura (residuo de la recta): σ \(f(a.captureFit.residualStd / rate * 1e6, 1)) µs · máx \(f(a.captureFit.residualMax / rate * 1e6, 1)) µs")
    }
    print("DISC  discontinuidad en el primer paquete \(a.discontinuityFirst) · después \(a.discontinuityLater) (resetCapture ×\(m.resets)) · silencio \(a.silent) · error de marca \(a.tsError)")
    let drift = m.sync.driftPPM.map { f($0, 2) + " ppm" } ?? "sin puntos"
    let off = m.sync.captureOffset.map { "\($0) muestras (\(f(Double($0) / rate * 1e3)) ms)" } ?? "sin fijar"
    print("SYNC  deriva captura-salida \(drift) · desfase fijado (DuplexClockSync, \(DuplexClockSync.defaultMinimumPoints) puntos) \(off)\(a.offsetFull.map { " · con todos los puntos \(f($0, 1)) muestras" } ?? "")")
    print("      (en la VM el desfase es de la tarjeta virtual: no es latencia de nada)")
    printEvents(m)
    if o.dump > 0 {
        let q0 = Double(m.rCount > 0 ? m.rQPC[0] : (m.cCount > 0 ? m.cQPC[0] : 0)) / 1e4, w0 = m.rCount > 0 ? m.rWake[0] : 0
        let tick = HostClock.timebase / 1e6
        print("DUMP  salida: escritos · posición(fotogramas) · QPC ms · despertar ms · fotogramas")
        for i in 0..<min(o.dump, m.rCount) {
            print("      r\(i) \(m.rWritten[i]) · \(f(Double(m.rPos[i]) * rate / Double(max(1, m.frequency)), 1)) · \(f(Double(m.rQPC[i]) / 1e4 - q0)) · \(f(Double(m.rWake[i] &- w0) * tick)) · \(m.rFrames[i])")
        }
        print("DUMP  captura: flujo · dispositivo · QPC ms · despertar ms · fotogramas · flags")
        for i in 0..<min(o.dump, m.cCount) {
            print("      c\(i) \(m.cPos[i]) · \(m.cDev[i]) · \(f(Double(m.cQPC[i]) / 1e4 - q0)) · \(f(Double(m.cWake[i] &- w0) * tick)) · \(m.cFrames[i]) · \(m.cFlags[i])")
        }
    }
    if st.stop_reason != 0 { throw ProbeError("el flujo se detuvo solo: \(eventName(Int(st.stop_reason)))") }
    if st.render_buffers == 0 || st.capture_packets == 0 { throw ProbeError("sin búferes de salida o de captura") }
}

func restarts(_ o: Options) throws {
    var offsets: [Double] = [], fulls: [Double] = [], estErrors: [Double] = [], drifts: [Double] = [], opens: [Double] = [], starts: [Double] = []
    var rate = 48_000.0
    var failures = 0
    print("RESTARTS \(o.count) × (abrir, \(f(o.seconds, 1)) s, cerrar) · \(o.exclusive ? "exclusivo" : "compartido")")
    for k in 0..<o.count {
        let s = Session(seconds: o.seconds)
        do {
            try s.open(o)
            if k == 0 { printOpen(s) }
            try s.run(seconds: o.seconds)
            rate = Double(s.info.render_format.sample_rate)
            let m = s.marks.pointee
            let a = Analysis(m, s.info)
            opens.append(s.openMS); starts.append(s.startMS)
            if let d = m.sync.driftPPM { drifts.append(d) }
            if let off = m.sync.captureOffset {
                offsets.append(Double(off))
                print("  #\(k + 1): desfase \(off) muestras · todos los puntos \(a.offsetFull.map { f($0, 1) } ?? "-") · deriva \(m.sync.driftPPM.map { f($0, 2) } ?? "-") ppm · búferes \(s.status.render_buffers)/\(s.status.capture_packets)\(s.status.stop_reason != 0 ? " · parada: \(eventName(Int(s.status.stop_reason)))" : "")")
            } else {
                failures += 1
                print("  #\(k + 1): desfase sin fijar (búferes \(s.status.render_buffers)/\(s.status.capture_packets); hacen falta \(DuplexClockSync.defaultMinimumPoints) de cada lado)")
            }
            if let full = a.offsetFull {
                fulls.append(full)
                if let off = m.sync.captureOffset { estErrors.append(Double(off) - full) }
            }
        } catch {
            failures += 1
            print("  #\(k + 1): \(error)")
        }
        s.close()
    }
    // El desfase incluye el desfase de arranque entre los dos clientes (Start de captura y de salida no son simultáneos):
    // varía entre arranques sin ser error, porque n − y lo descuenta al pasar las dos posiciones por la hora de host.
    // Lo que sí entra en n − y desde las marcas es el error de estimación: desfase fijado (100 puntos) − desfase con
    // todas las marcas de la sesión. El resto de la variación de n − y (sesgo de las marcas del driver por arranque)
    // solo se ve con un bucle físico: `tf-audio latency --restarts 10` en un PC.
    let so = Stats(offsets), sf = Stats(fulls), se = Stats(estErrors)
    if !offsets.isEmpty {
        let span = so.max - so.min
        print("SPREAD desfase fijado: máx − mín \(f(span, 0)) muestras = \(f(span / rate * 1e3)) ms · σ \(f(so.std, 2)) muestras (\(f(so.std / rate * 1e3, 4)) ms) · n = \(so.n)")
        print("       (incluye el desfase de arranque entre captura y salida: no es error de n − y)")
    }
    if !fulls.isEmpty {
        let span = sf.max - sf.min
        print("       con todos los puntos: máx − mín \(f(span, 1)) muestras = \(f(span / rate * 1e3)) ms · σ \(f(sf.std, 2)) muestras")
    }
    if !estErrors.isEmpty {
        let worst = Swift.max(abs(se.max), abs(se.min))
        print("ESTERR error de estimación (fijado − todos los puntos): peor \(f(worst, 2)) muestras = \(f(worst / rate * 1e3, 4)) ms · máx − mín \(f(se.max - se.min, 2)) muestras = \(f((se.max - se.min) / rate * 1e3, 4)) ms · σ \(f(se.std, 2)) muestras")
    }
    print("       umbral del plan (en un PC con la Flex Prime, no en la VM): variación < 0,2 ms = \(f(0.2e-3 * rate, 1)) muestras")
    print("       abrir \(Stats(opens).line("ms", 1)) · arrancar \(Stats(starts).line("ms", 1))")
    if !drifts.isEmpty { print("       deriva \(Stats(drifts).line("ppm", 2))") }
    if failures > 0 { throw ProbeError("\(failures) de \(o.count) arranques sin desfase") }
}

// MARK: - Entrada

let args = Array(CommandLine.arguments.dropFirst())
do {
    print("tf-p8-wasapi · shim v\(wasapi_shim_version()) · AVISO: en una VM la latencia y el desfase no significan nada")
    switch args.first {
    case nil:
        try devices()
        try run(try Options(["--seconds", "2"]))
        try restarts(try Options(["--count", "3", "--seconds", "1.5"]))
    case "devices": try devices()
    case "run": try run(try Options(args.dropFirst()))
    case "restarts": try restarts(try Options(args.dropFirst()))
    default: throw ProbeError("uso: tf-p8-wasapi [devices | run --seconds N [--exclusive] | restarts --count N]")
    }
} catch {
    print("ERROR \(error)")
    exit(1)
}
#else
print("tf-p8-wasapi: solo Windows (WASAPI)")
#endif
