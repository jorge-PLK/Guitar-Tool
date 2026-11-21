import Foundation
#if os(Windows)
import CWASAPI
import NativePlatform

/// `AudioIO` sobre WASAPI propio (plan, «Fase 7c», «Audio»: dúplex por eventos, IAudioClient3 o exclusivo; «Corte del
/// paso 7», parte 7.10), sobre el shim `CWASAPI` de la parte 7.7 y con la lógica de bombeo en `WASAPIStreamCore`
/// (portátil, probada en el Mac).
///
/// Mismo contrato que `CoreAudioIO`, para no tocar calibración ni alineado:
/// - Render y captura por eventos en un hilo MMCSS «Pro Audio» del shim; los manejadores reciben `AudioIOBuffer` no
///   entrelazados (trozos de hasta `WASAPIStreamCore.defaultChunkFrames`), sin reservar memoria.
/// - `sampleTime` y `hostSeconds` salen de `DuplexClockSync`: render con `IAudioClock::GetPosition` (+ su QPC) y los
///   fotogramas escritos; captura con la posición del flujo y `u64QPCPosition`. Los paquetes de captura anteriores a
///   fijar el offset (≈1 s de arranque) se descartan, como el arranque de una sesión; una discontinuidad posterior
///   reinicia el offset y se cuenta en `diagnostics.inputJumps`.
/// - `declaredLatencySamples`: `GetStreamLatency` de entrada y de salida, en muestras (como en el HAL, solo sin
///   calibración).
/// - Se abre en `init` (el dispositivo queda tomado en exclusivo mientras viva el objeto) y se arranca y para las veces
///   que haga falta; cada arranque reinicia las posiciones (la línea puede saltar entre `stop` y `start`).
/// - Desconexión, flujo muerto o cambio de frecuencia de la salida → `AudioIOInterruption` (`WASAPIEvent.action`).
/// - `clock` es `.single`: WASAPI no corrige deriva entre dispositivos (con dos, `status.driftPPM` la deja a la vista).
public final class WASAPIAudioIO: AudioIO, @unchecked Sendable {
    /// Lo propio de WASAPI que no está en `AudioSetup`.
    public struct Options: Sendable, Equatable {
        public var mode: WASAPIShareMode
        /// Periodo pedido en fotogramas; `nil` = `AudioSetup.bufferFrames` (512, como en el Mac); 0 = el mínimo del
        /// camino. El concedido queda en `format.bufferFrames` y en `streamInfo`.
        public var periodFrames: Int?
        /// Solo tests y diagnóstico (por defecto apagada): en compartido, admite la entrada a otra frecuencia que la de
        /// trabajo con el remuestreo de Windows (AUTOCONVERTPCM), que mete retardo sin medir (`WASAPIRateRule`).
        public var allowInputResampling: Bool

        public init(mode: WASAPIShareMode = .shared, periodFrames: Int? = nil, allowInputResampling: Bool = false) {
            self.mode = mode
            self.periodFrames = periodFrames
            self.allowInputResampling = allowInputResampling
        }
    }

    public let format: AudioIOFormat
    public let inputDeviceUID: String
    public let outputDeviceUID: String
    public let clock: AudioIOClock = .single
    public let declaredLatencySamples: Double
    /// Lo que quedó abierto (caminos, formatos del dispositivo, búferes y periodos concedidos).
    public let streamInfo: WASAPIStreamInfo

    private let allowInputResampling: Bool
    private let bridge: WASAPIBridge
    private let core: WASAPIStreamCore
    private let counters: IOCounters
    private let hostLog: HostTimeLog
    private let lock = NSLock()
    private var stream: OpaquePointer?
    private var running = false
    private var interruptionHandler: (@Sendable (AudioIOInterruption) -> Void)?
    private var lastStatus = WASAPIStreamStatus()

    /// Dúplex sobre los endpoints de `setup` (salida vacía = render por defecto), modo compartido.
    public convenience init(setup: AudioSetup) throws {
        try self.init(setup: setup, options: Options())
    }

    public convenience init(setup: AudioSetup, options: Options) throws {
        try self.init(inputUID: setup.inputDeviceUID, outputUID: setup.outputDeviceUID, sampleRate: setup.sampleRate,
                      periodFrames: options.periodFrames ?? setup.bufferFrames, mode: options.mode, useCapture: true,
                      allowInputResampling: options.allowInputResampling)
    }

    /// Solo salida (reproductor portátil sin sesión): `outputUID` vacío = render por defecto; `sampleRate` `nil` = la de
    /// mezcla del endpoint (el reproductor remuestrea los stems).
    public convenience init(outputUID: String, sampleRate: Double? = nil, options: Options = Options()) throws {
        try self.init(inputUID: "", outputUID: outputUID, sampleRate: sampleRate,
                      periodFrames: options.periodFrames ?? AudioSetup.defaultBufferFrames, mode: options.mode,
                      useCapture: false, allowInputResampling: options.allowInputResampling)
    }

    private init(inputUID: String, outputUID: String, sampleRate: Double?, periodFrames: Int, mode: WASAPIShareMode,
                 useCapture: Bool, allowInputResampling: Bool) throws {
        assert(WASAPIEvent.formatChanged.rawValue == Int32(WASAPI_EVENT_FORMAT_CHANGED)
               && WASAPIStreamPath.exclusive.rawValue == Int32(WASAPI_PATH_EXCLUSIVE)
               && WASAPICaptureMarks.discontinuity == UInt32(WASAPI_CAPTURE_DISCONTINUITY)
               && WASAPICaptureMarks.timestampError == UInt32(WASAPI_CAPTURE_TIMESTAMP_ERROR))
        let devices = try WASAPIAudioIO.devices()
        let render: WASAPIDeviceInfo
        if outputUID.isEmpty {
            guard let d = devices.first(where: { $0.flow == .render && $0.isDefault }) else {
                throw AudioIOError.notConnected(outputUID)
            }
            render = d
        } else {
            guard let d = devices.first(where: { $0.flow == .render && $0.id == outputUID }) else {
                throw AudioIOError.notConnected(outputUID)
            }
            render = d
        }
        guard render.mix.channels > 0 else { throw AudioIOError.device("\(render.name) no tiene salidas") }
        var capture: WASAPIDeviceInfo?
        if useCapture {
            guard let d = devices.first(where: { $0.flow == .capture && $0.id == inputUID }) else {
                throw AudioIOError.notConnected(inputUID)
            }
            guard d.mix.channels > 0 else { throw AudioIOError.noInput }
            capture = d
        }
        let captureID = capture?.id
        let rate = sampleRate ?? render.mix.sampleRate
        if let device = WASAPIRateRule.mismatch(mode: mode, renderMixRate: render.mix.sampleRate, working: rate) {
            throw AudioIOError.sampleRateMismatch(device: device, requested: rate)
        }
        if let c = capture, let device = WASAPIRateRule.inputMismatch(mode: mode, captureMixRate: c.mix.sampleRate, working: rate,
                                                                      allowResampling: allowInputResampling) {
            throw AudioIOError.sampleRateMismatch(device: device, requested: rate)
        }

        let bridge = WASAPIBridge()
        let (opened, raw) = try WASAPIAudioIO.open(renderID: render.id, captureID: captureID, mode: mode, rate: rate,
                                          periodFrames: periodFrames, bridge: bridge)
        let info = WASAPIStreamInfo(raw)
        let inChannels = useCapture ? info.captureFormat?.channels ?? 0 : 0
        let outChannels = info.renderFormat?.channels ?? 0
        let counters = IOCounters()
        let hostLog = HostTimeLog()
        let core = WASAPIStreamCore(sampleRate: rate, inputChannels: inChannels, outputChannels: outChannels,
                                    shared: mode == .shared, counters: counters, hostLog: hostLog)
        bridge.core = core   // sin hilo de audio todavía: lo arranca `wasapi_start`

        self.allowInputResampling = allowInputResampling
        self.bridge = bridge
        self.core = core
        self.counters = counters
        self.hostLog = hostLog
        stream = opened
        streamInfo = info
        format = AudioIOFormat(sampleRate: rate, inputChannels: inChannels, outputChannels: outChannels,
                               bufferFrames: info.renderPeriodFrames)
        inputDeviceUID = useCapture ? wasapiString(raw.capture_id) : ""
        outputDeviceUID = wasapiString(raw.render_id)
        declaredLatencySamples = info.declaredLatencySamples(sampleRate: rate)
        // Todo asignado: ya se puede dar `self` (débil) al puente de avisos.
        bridge.setOwner(self)
    }

    deinit {
        stop()
        lock.withLock {
            wasapi_close(stream)
            stream = nil
        }
    }

    public var isRunning: Bool { lock.withLock { running } }

    /// Contadores del ciclo de E/S desde el último `start` (para `tf-audio verify`).
    public var diagnostics: AudioIODiagnostics? { counters.diagnostics }

    /// Contadores del hilo del shim: en marcha, los actuales del shim (sin los de `DuplexClockSync`, que el hilo de
    /// audio está escribiendo); parado, los completos del último arranque.
    public var status: WASAPIStreamStatus {
        lock.withLock {
            guard running, let stream else { return lastStatus }
            return statusLocked(stream, withSync: false)
        }
    }

    /// Marcas de cada paquete de captura desde el último `start` (las últimas 2^16), con la última marca de salida, por
    /// segundo y con sus escalones (como `CoreAudioIO.hostTimingReport`; sin latencias declaradas periódicas:
    /// `GetStreamLatency` no cambia con el flujo abierto).
    public func hostTimingReport() -> HostTimingReport {
        let cycles = hostLog.snapshot().compactMap { r -> HostTimingCycle? in
            guard !r.outSample.isNaN else { return nil }
            return HostTimingCycle(inputSampleTime: r.inSample, outputSampleTime: r.outSample,
                                   inputHostSeconds: HostTimeLog.seconds(r.inHost),
                                   outputHostSeconds: HostTimeLog.seconds(r.outHost),
                                   inputRateScalar: r.inRate, outputRateScalar: r.outRate)
        }
        return HostTimingAnalysis.analyze(cycles: cycles, latencies: [], sampleRate: format.sampleRate)
    }

    /// Hora de host ahora (QPC), en la escala de `AudioIOBuffer.hostSeconds`.
    public static var hostNowSeconds: Double { HostTimeLog.seconds(HostClock.now()) }

    public func setInterruptionHandler(_ handler: (@Sendable (AudioIOInterruption) -> Void)?) {
        lock.withLock { interruptionHandler = handler }
    }

    // MARK: Arranque y parada

    public func start(render: @escaping AudioIORenderHandler, capture: @escaping AudioIOCaptureHandler) throws {
        _ = HostTimeLog.timebase
        try lock.withLock {
            guard !running else { throw AudioIOError.alreadyRunning }
            guard let stream else { throw AudioIOError.device("flujo WASAPI cerrado") }
            core.prepare(render: render, capture: capture)   // sin hilo de audio: `wasapi_start` lo crea después
            let hr = wasapi_start(stream)
            guard hr == 0 else {
                core.clear()
                throw AudioIOError.device("wasapi_start: \(hexHR(hr))")
            }
            running = true
        }
    }

    /// Vuelve con el hilo de audio parado (el shim espera como mucho `WASAPI_STALL_MS` + 500 ms). No llamar desde un
    /// manejador.
    public func stop() {
        lock.withLock { stopLocked() }
    }

    private func stopLocked() {
        guard running, let stream else { return }
        running = false
        wasapi_stop(stream)
        lastStatus = statusLocked(stream, withSync: true)   // hilo de audio ya parado: se puede leer el núcleo
        core.clear()
    }

    private func statusLocked(_ stream: OpaquePointer, withSync: Bool) -> WASAPIStreamStatus {
        var st = wasapi_stream_status()
        wasapi_get_status(stream, &st)
        var out = WASAPIStreamStatus(mmcss: st.mmcss_ok != 0, lastHResult: st.last_hresult, stopReason: st.stop_reason,
                                     renderBuffers: Int(st.render_buffers), renderStarved: Int(st.render_starved),
                                     capturePackets: Int(st.capture_packets), wakeups: Int(st.wakeups),
                                     clockFailures: Int(st.clock_failures))
        if withSync {
            let sync = core.sync
            out.droppedCaptureFrames = core.droppedCaptureFrames
            out.captureResets = core.captureResets
            out.driftPPM = sync.driftPPM
            out.captureOffset = sync.captureOffset
        }
        return out
    }

    // MARK: Avisos (en la cola del puente, nunca en el hilo de audio ni en el de COM)

    fileprivate func handle(kind: Int32, flow: Int32, deviceID: String?) {
        switch WASAPIEvent.action(kind: kind, flow: flow, deviceID: deviceID, inputUID: inputDeviceUID,
                                  outputUID: outputDeviceUID) {
        case .ignore:
            return
        case .interrupt(let reason):
            interrupt(reason)
        case let .checkRate(uid, side):
            guard let d = (try? Self.devices())?.first(where: { $0.id == uid && $0.flow == side }) else { return }
            let r = side == .render
                ? WASAPIRateRule.mismatch(mode: streamInfo.mode, renderMixRate: d.mix.sampleRate, working: format.sampleRate)
                : WASAPIRateRule.inputMismatch(mode: streamInfo.mode, captureMixRate: d.mix.sampleRate,
                                               working: format.sampleRate, allowResampling: allowInputResampling)
            guard let r else { return }
            interrupt(.sampleRateChanged(r))
        }
    }

    private func interrupt(_ reason: AudioIOInterruption) {
        let handler = lock.withLock { () -> (@Sendable (AudioIOInterruption) -> Void)? in
            guard running else { return nil }
            stopLocked()
            return interruptionHandler
        }
        handler?(reason)
    }

    // MARK: Dispositivos

    /// Endpoints activos de render y captura (el listado de `tf-audio`: id, formato de mezcla, periodos mínimos).
    public static func devices() throws -> [WASAPIDeviceInfo] {
        var capacity: Int32 = 32
        while true {
            var list = [wasapi_device_info](repeating: wasapi_device_info(), count: Int(capacity))
            let n = wasapi_enumerate(&list, capacity)
            guard n >= 0 else { throw AudioIOError.device("wasapi_enumerate: \(hexHR(n))") }
            if n <= capacity { return list.prefix(Int(n)).map { WASAPIDeviceInfo($0) } }
            capacity = n
        }
    }

    /// Abre sin arrancar. Los punteros de id solo valen durante `wasapi_open` (el shim no los guarda).
    private static func open(renderID: String, captureID: String?, mode: WASAPIShareMode, rate: Double,
                             periodFrames: Int, bridge: WASAPIBridge) throws -> (OpaquePointer, wasapi_stream_info) {
        // Funciones C sin capturas: todo pasa por `ctx` (el puente, vivo mientras viva el flujo).
        let renderCB: wasapi_render_cb = { ctx, data, frames, channels, info in
            guard let ctx, let data, let info else { return }
            let bridge = Unmanaged<WASAPIBridge>.fromOpaque(ctx).takeUnretainedValue()
            bridge.core?.render(interleaved: data, frames: Int(frames), channels: Int(channels),
                                marks: WASAPIRenderMarks(info.pointee))
        }
        let captureCB: wasapi_capture_cb = { ctx, data, frames, channels, info in
            guard let ctx, let data, let info else { return }
            let bridge = Unmanaged<WASAPIBridge>.fromOpaque(ctx).takeUnretainedValue()
            bridge.core?.capture(interleaved: data, frames: Int(frames), channels: Int(channels),
                                 marks: WASAPICaptureMarks(info.pointee))
        }
        let eventCB: wasapi_event_cb = { ctx, kind, flow, deviceID, _ in
            guard let ctx else { return }
            let id = deviceID.map { String(cString: $0) }
            Unmanaged<WASAPIBridge>.fromOpaque(ctx).takeUnretainedValue().event(kind: kind, flow: flow, deviceID: id)
        }
        var p = wasapi_open_params()
        p.mode = Int32(mode == .exclusive ? WASAPI_MODE_EXCLUSIVE : WASAPI_MODE_SHARED)
        p.sample_rate = UInt32(rate.rounded())
        p.period_frames = UInt32(max(0, periodFrames))
        p.use_render = 1
        p.use_capture = captureID == nil ? 0 : 1
        p.render = renderCB
        p.capture = captureCB
        p.event = eventCB
        p.ctx = Unmanaged.passUnretained(bridge).toOpaque()
        var step: UnsafePointer<CChar>?
        var opened: OpaquePointer?
        var info = wasapi_stream_info()
        let hr = renderID.withCString { rid in
            (captureID ?? "").withCString { cid in
                p.render_id = rid
                p.capture_id = cid
                return wasapi_open(&p, &opened, &info, &step)
            }
        }
        guard hr == 0, let opened else {
            wasapi_close(opened)
            let where_ = step.map { String(cString: $0) } ?? "?"
            throw AudioIOError.device("wasapi_open (\(where_)): \(hexHR(hr))\(Self.hint(hr))")
        }
        return (opened, info)
    }

    private static func hint(_ hr: Int32) -> String {
        switch UInt32(bitPattern: hr) {
        case 0x8889_000A: return " · el dispositivo está en uso en exclusivo por otra aplicación"
        case 0x8889_0008: return " · formato no admitido"
        case 0x8889_0004: return " · dispositivo invalidado (desconectado)"
        default: return ""
        }
    }
}

/// Contexto de las funciones C del shim: el núcleo de bombeo (hilo de audio) y el dueño, débil, para los avisos.
final class WASAPIBridge: @unchecked Sendable {
    /// Se pone antes de arrancar y no cambia; solo lo lee el hilo de audio.
    var core: WASAPIStreamCore?
    private let queue = DispatchQueue(label: "ToneForge.WASAPIAudioIO.events")
    private let lock = NSLock()
    private weak var owner: WASAPIAudioIO?

    func setOwner(_ io: WASAPIAudioIO) { lock.withLock { owner = io } }

    /// Desde un hilo de COM o desde el de audio al salir: vuelve enseguida y no llama a `wasapi_stop`/`wasapi_close`
    /// (contrato de CWASAPI.h); el dueño lo atiende en `queue` (si muere ahí, su `deinit` también corre en `queue`).
    func event(kind: Int32, flow: Int32, deviceID: String?) {
        queue.async { [weak self] in
            guard let self else { return }
            let io = self.lock.withLock { self.owner }
            io?.handle(kind: kind, flow: flow, deviceID: deviceID)
        }
    }
}

// MARK: - De CWASAPI a tipos portátiles

private func wasapiString<T>(_ t: T) -> String {
    withUnsafeBytes(of: t) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
}

private func hexHR(_ hr: Int32) -> String { "0x" + String(UInt32(bitPattern: hr), radix: 16, uppercase: true) }

extension WASAPIRenderMarks {
    fileprivate init(_ i: wasapi_render_info) {
        self.init(framesWritten: i.frames_written, clockPosition: i.clock_position, clockQPC100ns: i.clock_qpc_100ns,
                  clockFrequency: i.clock_frequency, paddingFrames: i.padding_frames)
    }
}

extension WASAPICaptureMarks {
    fileprivate init(_ i: wasapi_capture_info) {
        self.init(streamPosition: i.stream_position, qpc100ns: i.qpc_100ns, flags: i.flags)
    }
}

extension WASAPIFormat {
    fileprivate init(_ f: wasapi_format) {
        self.init(sampleRate: Double(f.sample_rate), channels: Int(f.channels), bits: Int(f.bits),
                  validBits: Int(f.valid_bits), isFloat: f.is_float != 0)
    }
}

extension WASAPIDeviceInfo {
    fileprivate init(_ d: wasapi_device_info) {
        let engine = d.has_client3 != 0
            ? WASAPIEnginePeriods(defaultFrames: Int(d.engine_default_frames), fundamentalFrames: Int(d.engine_fundamental_frames),
                                  minimumFrames: Int(d.engine_min_frames), maximumFrames: Int(d.engine_max_frames))
            : nil
        self.init(id: wasapiString(d.id), name: wasapiString(d.name), flow: Int(d.flow) == WASAPI_FLOW_CAPTURE ? .capture : .render,
                  isDefault: d.is_default != 0, mix: WASAPIFormat(d.mix), defaultPeriod100ns: d.default_period_100ns,
                  minimumPeriod100ns: d.minimum_period_100ns, engine: engine, exclusiveFloat: d.exclusive_float_ok != 0,
                  hresult: d.hresult,
                  driver: WASAPIDriverInfo(adapterInstance: wasapiString(d.adapter_instance), adapterName: wasapiString(d.adapter_name),
                                           service: wasapiString(d.driver_service), provider: wasapiString(d.driver_provider),
                                           version: wasapiString(d.driver_version), description: wasapiString(d.driver_desc),
                                           infPath: wasapiString(d.driver_inf), hresult: d.driver_hresult))
    }
}

extension WASAPIStreamInfo {
    fileprivate init(_ i: wasapi_stream_info) {
        let rp = WASAPIStreamPath(rawValue: i.render_path) ?? .none
        let cp = WASAPIStreamPath(rawValue: i.capture_path) ?? .none
        self.init(mode: Int(i.mode) == WASAPI_MODE_EXCLUSIVE ? .exclusive : .shared, renderPath: rp, capturePath: cp,
                  renderFormat: rp == .none ? nil : WASAPIFormat(i.render_format),
                  captureFormat: cp == .none ? nil : WASAPIFormat(i.capture_format),
                  renderBufferFrames: Int(i.render_buffer_frames), captureBufferFrames: Int(i.capture_buffer_frames),
                  renderPeriodFrames: Int(i.render_period_frames), capturePeriodFrames: Int(i.capture_period_frames),
                  renderLatency100ns: i.render_latency_100ns, captureLatency100ns: i.capture_latency_100ns,
                  captureDeviceRate: Double(i.capture_device_rate), renderName: wasapiString(i.render_name),
                  captureName: wasapiString(i.capture_name))
    }
}
#endif
