// Reproductor sobre AVAudioEngine: solo macOS (paso 7: reproductor).
#if canImport(AVFoundation)
import AVFoundation
import Observation

// `TakeTrack` vive en `StudyPlayerTypes.swift` (portátil, paso 7c): lo usa también `PortableStudyPlayer`.

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
///
/// **Alojado en una sesión (Fase 3).** Con `attach(to:)` el motor pasa a `manualRenderingMode(.realtime)`
/// y lo renderiza el `render` de la `AudioSession` (`HostedRenderer`): backing y grabación con un solo reloj,
/// el del dispositivo. `playbackAnchor` queda entonces en la línea de tiempo de la sesión. `detach()` (o el
/// fin de la sesión) lo devuelve a su propia salida según `AudioRouting`.
@MainActor
@Observable
public final class StudyPlayer {
    /// Stems y, al final, las pistas de toma en su orden.
    public private(set) var tracks: [Track] = []
    /// Pistas de toma en uso (Fase 6: varias).
    public private(set) var takes: [TakeTrack] = []
    /// Primera pista de toma (la única antes de la Fase 6).
    public var take: TakeTrack? { takes.first }
    public private(set) var duration: Double = 0
    public private(set) var isPlaying = false
    /// Nombre de la salida en uso («» si no hay ninguna).
    public private(set) var outputDeviceName = ""

    private var rateValue = 1.0
    private var pitchValue = 0.0
    private var loopValue: ClosedRange<Double>?
    private var endValue: Double?
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
    /// Formato de cada stem (el de su fichero), en el orden de `channels`.
    @ObservationIgnored private var stemFormats: [AVAudioFormat] = []
    /// Alojado en tiempo real: la fuente de cada stem (en lugar del player) y su nodo, en la entrada 1 del
    /// mezclador del canal. Vacío en cualquier otro modo.
    @ObservationIgnored private var feeds: [StemFeed] = []
    @ObservationIgnored private var feedNodes: [AVAudioSourceNode] = []
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
    @ObservationIgnored private var stemTracks: [Track] = []
    @ObservationIgnored private var host: HostedRenderer?
    @ObservationIgnored private weak var hostSession: AudioSession?

    static let offlineBlock: AVAudioFrameCount = 512
    /// Bloque máximo del motor alojado (el de la sesión es 512; los saltos se recuperan por trozos).
    static let hostedMaxFrames: AVAudioFrameCount = 4_096

    /// Reproductor en tiempo real con salida según `AudioRouting`.
    public convenience init(devices: any AudioDeviceProviding = CoreAudioDeviceProvider(),
                            output: OutputSelection = OutputSelection()) {
        self.init(offline: false, devices: devices, selection: output)
    }

    /// Cambia el dispositivo y el par de canales del backing (los del perfil de equipo).
    public func setOutput(_ selection: OutputSelection) { output?.select(selection) }

    /// Render offline (`manualRenderingMode`) para tests y `tf-audio --simulated`; no suena. Con `devices`, la
    /// ruta solo se anota. Alojado en una sesión (`attach(to:)`), la sesión lo renderiza bloque a bloque.
    public convenience init(offlineWith devices: (any AudioDeviceProviding)? = nil, output: OutputSelection = OutputSelection()) {
        self.init(offline: true, devices: devices, selection: output)
    }

    private init(offline: Bool, devices: (any AudioDeviceProviding)?, selection: OutputSelection) {
        self.offline = offline
        scheduler = StemScheduler(clock: clock)
        timePitch.overlap = StudyPlayerConstants.timePitchOverlap
        for node in [submix, varispeed, timePitch, postMix] as [AVAudioNode] { engine.attach(node) }
        if let devices {
            let controller = OutputController(provider: devices, selection: selection)
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

    /// Carga los stems de un tema (quita la pista de toma).
    public func load(tracks newTracks: [Track]) throws {
        try rebuild(stems: newTracks, takes: [])
    }

    /// Pone o quita la pista de toma («Tú»): equivale a `setTakes` con una o ninguna.
    public func setTake(_ newTake: TakeTrack?) throws {
        try setTakes(newTake.map { [$0] } ?? [])
    }

    /// Pone las pistas de toma (Fase 6: la de la parte y las mejores de las otras, cada una con su canal).
    /// Conserva la mezcla de los stems, la posición y si sonaba. Las tomas deben estar a la frecuencia de los
    /// stems y sus ids no pueden repetirse ni coincidir con los de los stems.
    public func setTakes(_ newTakes: [TakeTrack]) throws {
        guard !stemTracks.isEmpty else { throw StudyPlayerError.noTracks }
        let ids = stemTracks.map(\.id) + newTakes.map(\.id)
        guard Set(ids).count == ids.count else { throw StudyPlayerError.duplicateTrackID }
        let wasPlaying = isPlaying
        let t = currentTime
        let stemMix = Array(mix.prefix(stemTracks.count))
        try rebuild(stems: stemTracks, takes: newTakes)
        for (i, m) in stemMix.enumerated() { mix[i] = m }
        applyMix()
        pausedTime = t
        if wasPlaying { try play() }
    }

    private static func open(_ url: URL) throws -> (AVAudioFile, AVAudioFile) {
        do {
            return (try AVAudioFile(forReading: url), try AVAudioFile(forReading: url))
        } catch {
            throw StudyPlayerError.unreadable(url.lastPathComponent)
        }
    }

    private func rebuild(stems newTracks: [Track], takes newTakes: [TakeTrack]) throws {
        guard !newTracks.isEmpty else { throw StudyPlayerError.noTracks }
        if isPlaying { pause() }
        scheduler.stop()
        var stems: [StemScheduler.Stem] = []
        var rate: Double?
        var length: Int64 = 0
        for track in newTracks {
            let (file, reader) = try Self.open(track.url)
            let r = file.processingFormat.sampleRate
            if let rate, rate != r { throw StudyPlayerError.sampleRateMismatch }
            rate = r
            length = max(length, file.length)
            stems.append(.init(player: AVAudioPlayerNode(), file: file, reader: reader))
        }
        let sr = rate!
        for newTake in newTakes {
            // Una toma a otra frecuencia (grabada antes de reconvertir el proyecto) se remuestrea al cargar, sin
            // tocar el original (`TakeResampling`); a la misma frecuencia se abre tal cual, como siempre.
            let url: URL
            do { url = try TakeResampling.readable(newTake.url, at: sr) } catch {
                throw StudyPlayerError.unreadable(newTake.url.lastPathComponent)
            }
            let (file, reader) = try Self.open(url)
            guard file.processingFormat.sampleRate == sr else { throw StudyPlayerError.sampleRateMismatch }
            var s = StemScheduler.Stem(player: AVAudioPlayerNode(), file: file, reader: reader)
            s.offset = Int64((newTake.songStart * sr).rounded())
            s.silence = StemScheduler.silence(format: file.processingFormat,
                                              frames: Int64(StudyPlayerConstants.chunkSeconds * sr))
            s.fadeOutFrom = newTake.silencedFrom.map { Int64(($0 * sr).rounded()) }
            stems.append(s)
        }
        // Alojado a otra frecuencia ya no vale: vuelve a su propia salida.
        if let host, host.sampleRate != sr { detach() }

        host?.deactivate()
        engine.stop()
        removeFeeds()
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
        stemFormats = stems.map(\.file.processingFormat)
        stemTracks = newTracks
        takes = newTakes
        tracks = newTracks + newTakes.map { Track(id: $0.id, url: $0.url) }
        mix = newTracks.map { _ in StemMix() } + newTakes.map { StemMix(gainDB: $0.gainDB, muted: $0.muted, solo: $0.solo) }
        lengthFrames = length
        duration = Double(length) / sr
        pausedTime = 0
        scheduler.configure(stems: stems, length: length, sampleRate: sr) { [weak self] generation in
            Task { @MainActor in await self?.reachedEnd(generation) }
        }
        scheduler.setEnd(endFrames())
        if host != nil && !offline { installFeeds() }
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
        let realtime = !offline && host == nil
        let latency = host?.presentationLatencyFrames ?? (realtime ? engine.outputNode.presentationLatency * sr : 0)
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
        runGeneration = scheduler.start(songFrame: frame, loop: loopFrames, realtime: !offline,
                                        buffered: host != nil && !offline)
        // En tiempo real (con dispositivo o alojado) el motor arranca en cada pasada: un `play()` sin hora
        // antes del primer render del motor empieza en ese render.
        if !offline {
            do { try engine.start() } catch {
                stopRun()
                throw StudyPlayerError.engine("\(error)")
            }
        }
        if host != nil && !offline {
            // Alojado en tiempo real suenan las fuentes, no los players: el render está apagado hasta
            // `activate()` y `start()` es síncrono, así que el primer bloque entrega la muestra 0 de la pasada.
            // El TimePitch en `manualRenderingMode(.realtime)` retrasa su salida lo que declara en `latency`
            // (medido: 4096 muestras a 44,1 y 48 kHz, con o sin bypass, cualquier bloque; en `.offline`
            // declara 0 y no retrasa): se suma al ancla.
            let extra = Self.timePitchRealtimeDelayFrames(timePitch, sampleRate: sampleRate)
            hostedTimePitchFrames = extra
            clock.update { $0.latencyFrames = s.latencyFrames + extra }
            for f in feeds { f.start() }
        } else {
            // En tiempo real el primer ciclo llega milisegundos después de `start()`: los players arrancan antes.
            // Alojado offline, el render está apagado hasta `activate()`: el primer bloque ya los encuentra en marcha.
            for p in players { p.play() }
        }
        host?.activate()
        isPlaying = true
    }

    private func stopRun() {
        host?.deactivate()
        scheduler.stop()
        if !offline { engine.stop() }
        for p in players { p.stop() }
        for f in feeds { f.stop() }
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
        pausedTime = Double(endFrames()) / sampleRate
    }

    /// Muestra del tema donde acaba la reproducción: `endTime` dentro del tema, o su longitud.
    private func endFrames() -> Int64 {
        guard let t = endValue, sampleRate > 0 else { return lengthFrames }
        return min(lengthFrames, max(0, Int64((t * sampleRate).rounded())))
    }

    // MARK: Mezcla

    public func setGain(_ id: String, dB: Double) {
        guard let i = index(of: id) else { return }
        mix[i].gainDB = dB
        if let k = takes.firstIndex(where: { $0.id == id }) { takes[k].gainDB = dB }
        applyMix()
    }

    public func setMute(_ id: String, _ muted: Bool) {
        guard let i = index(of: id) else { return }
        mix[i].muted = muted
        if let k = takes.firstIndex(where: { $0.id == id }) { takes[k].muted = muted }
        applyMix()
    }

    /// Con algún solo activo solo suenan los canales en solo; el mute siempre silencia.
    public func setSolo(_ id: String, _ solo: Bool) {
        guard let i = index(of: id) else { return }
        mix[i].solo = solo
        if let k = takes.firstIndex(where: { $0.id == id }) { takes[k].solo = solo }
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

    /// Fin de la reproducción en segundos de canción (`nil` = el final del tema). Se aplica al programar, no con un
    /// temporizador: tras esa muestra no se programa nada y la pasada acaba como al terminar los stems, así que no
    /// suena ni una muestra de más aunque quien para lo vea tarde («Ver toma», W2-V). Sobrevive a `load`/`setTakes`.
    /// En marcha vale para lo que aún no está programado (`StudyPlayerConstants.queueSeconds` por delante): ponerlo
    /// antes de `play`.
    public var endTime: Double? {
        get { endValue }
        set {
            endValue = newValue
            scheduler.setEnd(endFrames())
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
        if isPlaying && host == nil { pause() }
        applyRoute(route)
    }

    private func applyRoute(_ route: OutputRoute?) {
        appliedRoute = route
        outputDeviceName = route?.device.name ?? ""
        // Alojado, la salida es la de la sesión; la ruta se aplica al volver (`detach`).
        guard !offline, host == nil, let route else { return }
        engine.stop()
        do {
            try engine.outputNode.auAudioUnit.setDeviceID(route.device.id)
            engine.outputNode.auAudioUnit.channelMap = route.channelMap?.map { NSNumber(value: $0) }
        } catch {
            outputDeviceName = ""
        }
    }

    private func engineConfigurationChanged() {
        guard host == nil else { return }
        if isPlaying { pause() }
        output?.refresh()
        applyRoute(output?.route)
    }

    // MARK: Alojado en una sesión (mini-spec Fase 3, «Alineado con el backing» 1)

    /// El motor lo renderiza una `AudioSession`.
    public var isHosted: Bool { host != nil }

    /// Pasa a sonar dentro de `session` (por sus canales de backing), con el reloj del dispositivo. Hace
    /// falta un tema cargado a la frecuencia de la sesión. Conserva la posición y si sonaba. Si la sesión se
    /// corta (desconexión, cambio de frecuencia), vuelve solo a su propia salida.
    public func attach(to session: AudioSession) throws {
        guard sampleRate > 0, !players.isEmpty else { throw StudyPlayerError.noTracks }
        guard abs(session.sampleRate - sampleRate) < 0.5 else { throw StudyPlayerError.sampleRateMismatch }
        if host != nil { detach() }
        let wasPlaying = isPlaying
        let t = currentTime
        if isPlaying { pause() }
        engine.stop()
        let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        do {
            if offline {
                try engine.start()
            } else {
                // El bloque de render vale desde aquí; el motor arranca en cada pasada (`startRun`).
                try engine.enableManualRenderingMode(.realtime, format: stereo, maximumFrameCount: Self.hostedMaxFrames)
                installFeeds()
            }
        } catch {
            if !offline { engine.disableManualRenderingMode() }
            applyRoute(output?.route)
            throw StudyPlayerError.engine("\(error)")
        }
        let topUp: (@Sendable () -> Void)? = offline ? Self.topUpClosure(scheduler) : nil
        let block: AVAudioEngineManualRenderingBlock = engine.manualRenderingBlock
        let renderer = HostedRenderer(block: block, clock: clock,
                                      maxFrames: Int(engine.manualRenderingMaximumFrameCount), sampleRate: sampleRate,
                                      presentationLatencyFrames: session.outputLatencyFrames, topUp: topUp)
        host = renderer
        hostSession = session
        session.setPlayer(renderer) { [weak self] in
            Task { @MainActor in self?.sessionEnded(renderer) }
        }
        pausedTime = t
        if wasPlaying { try play() }
    }

    /// Vuelve a su propia salida (según `AudioRouting`). Conserva la posición y si sonaba.
    public func detach() {
        guard host != nil else { return }
        let wasPlaying = isPlaying
        let t = currentTime
        if isPlaying { pause() }
        hostSession?.setPlayer(nil, onEnd: nil)
        host?.deactivate()
        host = nil
        hostSession = nil
        engine.stop()
        removeFeeds()
        clock.update { $0.hostOffset = nil }
        if offline {
            try? engine.start()
        } else {
            engine.disableManualRenderingMode()
            applyRoute(output?.route)
        }
        pausedTime = t
        if wasPlaying { try? play() }
    }

    /// Crea una `StemFeed` por stem, conectada a la entrada 1 del mezclador de su canal, y se las da al
    /// programador. Con el motor parado.
    private func installFeeds() {
        removeFeeds()
        for (i, format) in stemFormats.enumerated() where i < channels.count {
            let feed = StemFeed(format: format)
            let node = feed.makeNode()
            engine.attach(node)
            engine.connect(node, to: channels[i], fromBus: 0, toBus: 1, format: format)
            feeds.append(feed)
            feedNodes.append(node)
        }
        scheduler.setFeeds(feeds)
    }

    /// Quita las fuentes del modo alojado en tiempo real. Con el motor parado.
    private func removeFeeds() {
        guard !feeds.isEmpty || !feedNodes.isEmpty else { return }
        scheduler.setFeeds([])
        for f in feeds { f.stop() }
        for n in feedNodes { engine.detach(n) }
        feeds = []
        feedNodes = []
    }

    /// Retardo que declara el TimePitch, en muestras enteras (en `.realtime`, 4096; en `.offline`, 0).
    static func timePitchRealtimeDelayFrames(_ node: AVAudioNode, sampleRate: Double) -> Double {
        (node.latency * sampleRate).rounded()
    }

    /// Muestras dadas como silencio por falta de datos en las fuentes del modo alojado en tiempo real.
    var feedUnderrunFrames: Int { feeds.reduce(0) { $0 + $1.underrunFrames } }

    /// Retardo del TimePitch sumado al ancla en la última pasada alojada en tiempo real.
    private var hostedTimePitchFrames = 0.0

    /// Diagnóstico del modo alojado (`nil` sin alojar): vacíos de las fuentes, saltos y recuperaciones del
    /// render, y la latencia de nodos sumada al ancla.
    public var hostedDiagnostics: HostedPlaybackDiagnostics? {
        guard let host else { return nil }
        return HostedPlaybackDiagnostics(render: host.stats, feedUnderrunFrames: feedUnderrunFrames,
                                         timePitchLatencyFrames: hostedTimePitchFrames,
                                         anchorLatencyFrames: clock.read { $0.latencyFrames })
    }

    /// Fuera del actor: se llama en el hilo de render.
    private nonisolated static func topUpClosure(_ scheduler: StemScheduler) -> @Sendable () -> Void {
        { scheduler.topUp() }
    }

    private func sessionEnded(_ renderer: HostedRenderer) {
        guard host === renderer else { return }
        detach()
    }

    // MARK: Ancla de reproducción (mini-spec Fase 3, «Alineado con el backing» 1)

    /// Qué posición del tema suena en qué muestra de salida en la pasada en curso, contando la latencia de
    /// Varispeed y TimePitch. La muestra está en la línea de tiempo del render del motor (en offline,
    /// `manualRenderingSampleTime`) o, alojado en una sesión, en la de la sesión (`AudioIOBuffer.sampleTime`).
    /// `nil` parado o antes del primer ciclo de render de la pasada.
    public var playbackAnchor: PlaybackAnchor? {
        if let host { return host.anchor }
        let sr = sampleRate
        return clock.read { s -> PlaybackAnchor? in
            guard s.running, !s.pendingStart, sr > 0 else { return nil }
            return PlaybackAnchor(songTime: s.startSongFrame / sr, outputSample: s.runStartFrame + s.latencyFrames,
                                  sampleRate: sr, rate: s.rate)
        }
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

#endif // canImport(AVFoundation)
