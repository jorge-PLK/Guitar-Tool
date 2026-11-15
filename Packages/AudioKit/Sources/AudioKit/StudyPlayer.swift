import AVFoundation
import Observation

/// Reproductor de estudio (mini-spec Fase 2 §1 AudioKit).
///
/// Grafo: un `AVAudioPlayerNode` por stem → mezclador por canal → submezcla → Varispeed (corrección
/// fina de la velocidad, ver `TimePitchSetting`) → `AVAudioUnitTimePitch` (overlap 8) → mezclador
/// principal ← metrónomo (`AVAudioSourceNode`, sin estirar) → `mainMixerNode` → salida.
///
/// **Pasadas.** `play`, `seek` y cambiar `rate` (o pasar el tono de 0 a ≠ 0 a velocidad 1) paran los
/// players, reinician TimePitch y Varispeed y arrancan todos los stems en el mismo ciclo de render. Un
/// TimePitch recién reiniciado casi no tiene latencia (medido: −8…+6 ms, modelado en
/// `TimePitchSetting.latencyFrames`); en caliente tendría 75–100 ms con una fase imprevisible. En
/// tiempo real el motor solo corre durante la reproducción (`pause` lo para).
///
/// **Tiempo.** El primer render de la pasada fija la muestra de salida de arranque. La salida `y` oye la
/// muestra acumulada `(y − arranque − latencia)·rate`, que se traduce a canción con los tramos
/// programados (bucle incluido). `currentTime` y los clics salen de esa misma cuenta.
///
/// **Bucle.** Se programa por trozos de 0,25 s, como mucho 0,5 s por delante de lo que ya se renderizó.
/// En el corte, un fundido cruzado de 5 ms centrado en `b → a`, así que cada vuelta dura `b − a` muestras
/// exactas. Cambiar o quitar el bucle afecta a lo que aún no está programado: sin cortes, con hasta
/// ~0,75 s de retraso. Si la posición está antes del bucle, se toca hasta su final y vuelve; si está en
/// o tras su final, salta a su inicio (con el mismo fundido).
///
/// Los cambios de mezcla se oyen ~0,1 s después (el TimePitch lee por delante).
///
/// **Concurrencia.** La clase es del actor principal. El hilo de render (metrónomo y reloj) y los taps
/// de nivel comparten estado con cerrojos injustos (`PlaybackClock`, `MeterStore`); la programación de
/// los stems vive en la cola serie de `StemScheduler`. Los avisos de dispositivos llegan en otra cola
/// y se pasan al actor principal.
@MainActor
@Observable
public final class StudyPlayer {
    public private(set) var tracks: [Track] = []
    public private(set) var duration: Double = 0
    public private(set) var isPlaying = false
    /// Nombre de la salida en uso («» si no hay ninguna).
    public private(set) var outputDeviceName = ""

    private var rateValue = 1.0
    private var pitchValue = 0.0
    private var loopValue: ClosedRange<Double>?
    private var metronomeValue = Metronome()
    private var pausedTime = 0.0
    private var masterGainValue = 0.0
    private var mix: [StemMix] = []

    private struct StemMix {
        var gainDB = 0.0
        var muted = false
        var solo = false
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let submix = AVAudioMixerNode()
    @ObservationIgnored private let varispeed = AVAudioUnitVarispeed()
    @ObservationIgnored private let timePitch = AVAudioUnitTimePitch()
    @ObservationIgnored private let postMix = AVAudioMixerNode()
    @ObservationIgnored private var clickNode: AVAudioSourceNode?
    @ObservationIgnored private var players: [AVAudioPlayerNode] = []
    @ObservationIgnored private var channels: [AVAudioMixerNode] = []
    @ObservationIgnored private let clock = PlaybackClock()
    @ObservationIgnored private let scheduler: StemScheduler
    @ObservationIgnored private let meterStore = MeterStore()
    @ObservationIgnored private var sampleRate: Double = 0
    @ObservationIgnored private var lengthFrames: Int64 = 0
    @ObservationIgnored private var setting = TimePitchSetting(rate: 1)
    @ObservationIgnored private var runGeneration = 0
    @ObservationIgnored private let offline: Bool
    @ObservationIgnored private var output: OutputController?
    @ObservationIgnored private(set) var appliedRoute: OutputRoute?
    @ObservationIgnored private var configObserver: (any NSObjectProtocol)?

    static let offlineBlock: AVAudioFrameCount = 512

    /// Reproductor en tiempo real con salida según `OutputRouting`.
    public convenience init(devices: any AudioDeviceProviding = CoreAudioDeviceProvider()) {
        self.init(offline: false, devices: devices)
    }

    /// Render offline (`manualRenderingMode`) para tests; no suena. Con `devices`, la ruta solo se anota.
    convenience init(offlineWith devices: (any AudioDeviceProviding)? = nil) {
        self.init(offline: true, devices: devices)
    }

    private init(offline: Bool, devices: (any AudioDeviceProviding)?) {
        self.offline = offline
        scheduler = StemScheduler(clock: clock)
        timePitch.overlap = StudyPlayerConstants.timePitchOverlap
        for node in [submix, varispeed, timePitch, postMix] as [AVAudioNode] { engine.attach(node) }
        if let devices {
            let controller = OutputController(provider: devices)
            output = controller
            controller.onRouteChange = { [weak self] route in self?.routeChanged(route) }
            applyRoute(controller.route)
        }
        if !offline {
            configObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
            ) { [weak self] _ in
                Task { @MainActor in self?.engineConfigurationChanged() }
            }
        }
    }

    // MARK: Carga

    public func load(tracks newTracks: [Track]) throws {
        guard !newTracks.isEmpty else { throw StudyPlayerError.noTracks }
        if isPlaying { pause() }
        scheduler.stop()
        var stems: [StemScheduler.Stem] = []
        var rate: Double?
        var length: Int64 = 0
        for track in newTracks {
            let file: AVAudioFile, reader: AVAudioFile
            do {
                file = try AVAudioFile(forReading: track.url)
                reader = try AVAudioFile(forReading: track.url)
            } catch {
                throw StudyPlayerError.unreadable(track.url.lastPathComponent)
            }
            let r = file.processingFormat.sampleRate
            if let rate, rate != r { throw StudyPlayerError.sampleRateMismatch }
            rate = r
            length = max(length, file.length)
            stems.append(.init(player: AVAudioPlayerNode(), file: file, reader: reader))
        }
        let sr = rate!

        engine.stop()
        for (p, c) in zip(players, channels) {
            c.removeTap(onBus: 0)
            engine.detach(p)
            engine.detach(c)
        }
        meterStore.reset()
        if sr != sampleRate || clickNode == nil { try configureGraph(sampleRate: sr) }

        let stereo = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        var newChannels: [AVAudioMixerNode] = []
        for (i, stem) in stems.enumerated() {
            let channel = AVAudioMixerNode()
            engine.attach(stem.player)
            engine.attach(channel)
            engine.connect(stem.player, to: channel, format: stem.file.processingFormat)
            engine.connect(channel, to: submix, fromBus: 0, toBus: submix.nextAvailableInputBus, format: stereo)
            MeterStore.installTap(on: channel, index: i, store: meterStore)
            newChannels.append(channel)
        }
        players = stems.map(\.player)
        channels = newChannels
        tracks = newTracks
        mix = newTracks.map { _ in StemMix() }
        lengthFrames = length
        duration = Double(length) / sr
        pausedTime = 0
        scheduler.configure(stems: stems, length: length, sampleRate: sr) { [weak self] generation in
            Task { @MainActor in await self?.reachedEnd(generation) }
        }
        applyMix()
        loop = loopValue
        applyMetronome()
        if offline {
            do { try engine.start() } catch { throw StudyPlayerError.engine("\(error)") }
        }
    }

    private func configureGraph(sampleRate sr: Double) throws {
        let stereo = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        if offline {
            do {
                try engine.enableManualRenderingMode(.offline, format: stereo, maximumFrameCount: Self.offlineBlock)
            } catch { throw StudyPlayerError.engine("\(error)") }
        }
        if let old = clickNode { engine.detach(old) }
        let node = ClickRenderer(clock: clock, sampleRate: sr).makeNode(format: stereo)
        engine.attach(node)
        engine.connect(submix, to: varispeed, format: stereo)
        engine.connect(varispeed, to: timePitch, format: stereo)
        engine.connect(timePitch, to: postMix, fromBus: 0, toBus: 0, format: stereo)
        engine.connect(node, to: postMix, fromBus: 0, toBus: 1, format: stereo)
        engine.connect(postMix, to: engine.mainMixerNode, format: stereo)
        engine.mainMixerNode.outputVolume = Float(pow(10, masterGainValue / 20))
        clickNode = node
        sampleRate = sr
    }

    // MARK: Transporte

    public func play() throws {
        guard !isPlaying, !players.isEmpty else { return }
        try startRun(at: pausedTime >= duration - 0.001 ? 0 : pausedTime)
    }

    public func pause() {
        guard isPlaying else { return }
        let t = currentTime
        stopRun()
        pausedTime = t
        isPlaying = false
    }

    public func seek(to time: Double) {
        let t = min(max(time, 0), duration)
        guard isPlaying else { pausedTime = t; return }
        restart(at: t)
    }

    /// Tiempo de canción de lo que se oye. No es observable: la vista lo consulta en cada fotograma.
    public var currentTime: Double {
        guard isPlaying, sampleRate > 0 else { return pausedTime }
        let sr = sampleRate
        let realtime = !offline
        let latency = realtime ? engine.outputNode.presentationLatency * sr : 0
        let frame = clock.read { s -> Double in
            guard !s.pendingStart else { return s.startSongFrame }
            var y = s.lastRenderStart + s.lastRenderFrames
            if realtime, s.lastRenderHostTime != 0 {
                let elapsed = AVAudioTime.seconds(forHostTime: mach_absolute_time())
                    - AVAudioTime.seconds(forHostTime: s.lastRenderHostTime)
                y = s.lastRenderStart + min(max(0, elapsed * sr), 2 * s.lastRenderFrames)
            }
            return s.songFrame(atOutput: y - latency)
        }
        return frame / sr
    }

    private func startRun(at time: Double) throws {
        guard !players.isEmpty else { return }
        stopRun()
        var frame = Int64((min(max(time, 0), duration) * sampleRate).rounded())
        let loopFrames = loopRange()
        if let l = loopFrames, frame >= l.upperBound { frame = l.lowerBound }
        let s = TimePitchSetting(rate: rateValue)
        setting = s
        timePitch.reset()
        varispeed.reset()
        timePitch.rate = s.timePitchRate
        timePitch.pitch = s.timePitchCents(for: pitchValue)
        varispeed.rate = s.varispeedRate
        varispeed.bypass = s.varispeedRate == 1
        clock.update { c in
            c.running = true
            c.pendingStart = true
            c.rate = s.rate
            c.latencyFrames = s.latencyFrames
            c.startSongFrame = Double(frame)
            c.spans.removeAll(keepingCapacity: true)
        }
        runGeneration = scheduler.start(songFrame: frame, loop: loopFrames, realtime: !offline)
        if !offline {
            do { try engine.start() } catch {
                stopRun()
                throw StudyPlayerError.engine("\(error)")
            }
        }
        // En tiempo real el primer ciclo llega milisegundos después de `start()`: los players arrancan antes.
        for p in players { p.play() }
        isPlaying = true
    }

    private func stopRun() {
        scheduler.stop()
        if !offline { engine.stop() }
        for p in players { p.stop() }
        clock.update { $0.running = false }
    }

    private func restart(at time: Double) {
        do { try startRun(at: time) } catch {
            isPlaying = false
            pausedTime = time
        }
    }

    private func reachedEnd(_ generation: Int) async {
        // Lo último entregado al TimePitch tarda en sonar; se espera antes de parar.
        try? await Task.sleep(for: .milliseconds(300))
        guard isPlaying, generation == runGeneration, loopRange() == nil else { return }
        pause()
        pausedTime = duration
    }

    // MARK: Mezcla

    public func setGain(_ id: String, dB: Double) {
        guard let i = index(of: id) else { return }
        mix[i].gainDB = dB
        applyMix()
    }

    public func setMute(_ id: String, _ muted: Bool) {
        guard let i = index(of: id) else { return }
        mix[i].muted = muted
        applyMix()
    }

    /// Con algún solo activo solo suenan los canales en solo; el mute siempre silencia.
    public func setSolo(_ id: String, _ solo: Bool) {
        guard let i = index(of: id) else { return }
        mix[i].solo = solo
        applyMix()
    }

    /// Ganancia global (stems + metrónomo) en dB, sobre el mezclador principal. Mini-spec Fase 2, P8.
    public var masterGainDB: Double {
        get { masterGainValue }
        set {
            masterGainValue = newValue
            engine.mainMixerNode.outputVolume = Float(pow(10, newValue / 20))
        }
    }

    /// Nivel por canal tras ganancia, mute y solo.
    public var meters: [String: ChannelMeter] {
        var out: [String: ChannelMeter] = [:]
        for (i, t) in tracks.enumerated() { out[t.id] = meterStore.get(i) }
        return out
    }

    private func index(of id: String) -> Int? { tracks.firstIndex { $0.id == id } }

    private func applyMix() {
        let anySolo = mix.contains { $0.solo }
        for (i, m) in mix.enumerated() where i < channels.count {
            let audible = !m.muted && (!anySolo || m.solo)
            channels[i].outputVolume = audible ? Float(pow(10, m.gainDB / 20)) : 0
        }
    }

    // MARK: Velocidad, tono, bucle, metrónomo

    /// 0,5…2,0. En marcha reinicia la pasada en la posición actual.
    public var rate: Double {
        get { rateValue }
        set {
            let r = min(max(newValue, StudyPlayerConstants.rateRange.lowerBound), StudyPlayerConstants.rateRange.upperBound)
            guard r != rateValue else { return }
            rateValue = r
            if isPlaying { restart(at: currentTime) }
        }
    }

    /// Transposición × 100 + fina, ±1250 cents. Se aplica en vivo salvo cuando el TimePitch pasa de
    /// inactivo (velocidad 1, tono 0) a activo o al revés: entonces reinicia la pasada.
    public var pitchCents: Double {
        get { pitchValue }
        set {
            let c = min(max(newValue, StudyPlayerConstants.pitchCentsRange.lowerBound),
                        StudyPlayerConstants.pitchCentsRange.upperBound)
            guard c != pitchValue else { return }
            let idle = setting.timePitchRate == 1
            let flips = idle && ((pitchValue == 0) != (c == 0))
            pitchValue = c
            if isPlaying && flips {
                restart(at: currentTime)
            } else {
                timePitch.pitch = setting.timePitchCents(for: c)
            }
        }
    }

    /// Bucle en segundos de canción. Menor de 50 ms o fuera del tema → sin bucle.
    public var loop: ClosedRange<Double>? {
        get { loopValue }
        set {
            loopValue = newValue
            if sampleRate > 0, newValue != nil, loopRange() == nil { loopValue = nil }
            scheduler.setLoop(loopRange())
        }
    }

    public var metronome: Metronome {
        get { metronomeValue }
        set {
            metronomeValue = newValue
            applyMetronome()
        }
    }

    private func loopRange() -> Range<Int64>? {
        guard let l = loopValue, sampleRate > 0 else { return nil }
        let a = max(0, Int64((l.lowerBound * sampleRate).rounded()))
        let b = min(lengthFrames, Int64((l.upperBound * sampleRate).rounded()))
        guard Double(b - a) >= StudyPlayerConstants.minimumLoopSeconds * sampleRate else { return nil }
        return a..<b
    }

    private func applyMetronome() {
        let sr = sampleRate
        let frames = metronomeValue.clicks
            .map { ClickFrame(songFrame: $0.time * sr, accent: $0.accent) }
            .sorted { $0.songFrame < $1.songFrame }
        let on = metronomeValue.isEnabled
        let gain = Float(pow(10, metronomeValue.gainDB / 20))
        clock.update { s in
            s.clicks = frames
            s.metronomeOn = on
            s.metronomeGain = gain
        }
    }

    // MARK: Salida

    private func routeChanged(_ route: OutputRoute?) {
        if isPlaying { pause() }
        applyRoute(route)
    }

    private func applyRoute(_ route: OutputRoute?) {
        appliedRoute = route
        outputDeviceName = route?.device.name ?? ""
        guard !offline, let route else { return }
        engine.stop()
        do {
            try engine.outputNode.auAudioUnit.setDeviceID(route.device.id)
            engine.outputNode.auAudioUnit.channelMap = route.channelMap?.map { NSNumber(value: $0) }
        } catch {
            outputDeviceName = ""
        }
    }

    private func engineConfigurationChanged() {
        if isPlaying { pause() }
        output?.refresh()
        applyRoute(output?.route)
    }

    // MARK: Solo para tests (render offline)

    /// Renderiza `frames` muestras. Devuelve la muestra de salida del primer frame y los dos canales.
    func renderOffline(frames: Int) throws -> (start: Int64, channels: [[Float]]) {
        let start = engine.manualRenderingSampleTime
        var out: [[Float]] = [[], []]
        out[0].reserveCapacity(frames)
        out[1].reserveCapacity(frames)
        let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: Self.offlineBlock)!
        var left = frames
        while left > 0 {
            let n = AVAudioFrameCount(min(Int(Self.offlineBlock), left))
            let status = try engine.renderOffline(n, to: buf)
            guard status == .success else { throw StudyPlayerError.engine("renderOffline \(status.rawValue)") }
            for ch in 0..<2 {
                out[ch].append(contentsOf: UnsafeBufferPointer(start: buf.floatChannelData![ch], count: Int(buf.frameLength)))
            }
            left -= Int(buf.frameLength)
            scheduler.topUp()
        }
        return (start, out)
    }

    var runStartFrame: Double { clock.read { $0.runStartFrame } }
    var modelLatencyFrames: Double { setting.latencyFrames }
    var halfFadeFrames: Int64 { scheduler.halfFadeFrames }

    func songTime(atOutputFrame y: Double) -> Double {
        clock.read { $0.songFrame(atOutput: y) } / sampleRate
    }
}
