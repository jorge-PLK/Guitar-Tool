import Foundation
import Observation
import NativeAudioFile
import NativePlatform

/// Reproductor de estudio sin AVFoundation (plan, «Corte del paso 7», parte 7.6): la misma API pública y el mismo
/// comportamiento que `StudyPlayer` del Mac (mini-spec Fase 2 §1 AudioKit, Fase 3 «Alineado con el backing»), sobre
/// `PortablePlaybackEngine`. En Windows es `StudyPlayer` (typealias); en el Mac solo lo usan los tests.
///
/// Diferencias medidas frente al de AVAudioEngine (los números, en `PortablePlayerMeasurementTests`):
/// - Velocidad y tono con Signalsmith Stretch tras la submezcla, arrancado con `outputSeek`: latencia de modelo 0 (el
///   Mac modela la de Varispeed + TimePitch). A velocidad 1 y tono 0 la salida es la suma exacta de los stems.
/// - Cambiar la lista de clics en marcha se oye en ≤ 0,75 s (los ya programados se rehacen desde lo que suena);
///   activar el metrónomo y su volumen, al momento.
/// - Salida propia (sin sesión): un `AudioIO` de `outputIO` (en Windows, WASAPI: parte 7.10). Si su frecuencia no es la
///   de los stems, cada stem se remuestrea con r8brain en el hilo lector.
@MainActor
@Observable
public final class PortableStudyPlayer {
    public private(set) var tracks: [Track] = []
    public private(set) var takes: [TakeTrack] = []
    public var take: TakeTrack? { takes.first }
    public private(set) var duration: Double = 0
    public private(set) var isPlaying = false
    public private(set) var outputDeviceName = ""

    /// Abre la salida propia para una ruta (`nil` = la del sistema). La da quien crea el reproductor; en Windows la
    /// parte 7.10 pone WASAPI. Por defecto lanza `PlatformError.unsupported`.
    public typealias OutputIOFactory = @MainActor (OutputRoute?) throws -> any AudioIO

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

    @ObservationIgnored private var engine: PortablePlaybackEngine?
    @ObservationIgnored private var stems: [PortableStem] = []
    @ObservationIgnored private var stemTracks: [Track] = []
    @ObservationIgnored private var sampleRate: Double = 0
    @ObservationIgnored private var lengthFrames: Int64 = 0
    @ObservationIgnored private var runGeneration = 0
    @ObservationIgnored private var stretchRun = false
    @ObservationIgnored private let offline: Bool
    @ObservationIgnored private let forcedOutputRate: Double?
    @ObservationIgnored private let outputIO: OutputIOFactory
    @ObservationIgnored private var ownIO: (any AudioIO)?
    @ObservationIgnored private var output: OutputController?
    @ObservationIgnored private(set) var appliedRoute: OutputRoute?
    @ObservationIgnored private var host: PortableHostedRenderer?
    @ObservationIgnored private weak var hostSession: AudioSession?
    @ObservationIgnored private var offlineTime: Int64 = 0
    /// Solo para medir Signalsmith a velocidad 1 y tono 0 (`PortablePlayerMeasurementTests`).
    @ObservationIgnored var forceStretchForTests = false

    static let offlineBlock = 512

    /// Reproductor en tiempo real con salida propia según `AudioRouting` (o alojado en una sesión con `attach`).
    public convenience init(devices: (any AudioDeviceProviding)? = nil, output: OutputSelection = OutputSelection(),
                            outputIO: OutputIOFactory? = nil) {
        self.init(offline: false, devices: devices, selection: output, outputIO: outputIO, outputRate: nil)
    }

    /// Render offline para tests y `tf-audio --simulated`; no suena. Alojado en una sesión, la sesión lo renderiza.
    public convenience init(offlineWith devices: (any AudioDeviceProviding)? = nil, output: OutputSelection = OutputSelection()) {
        self.init(offline: true, devices: devices, selection: output, outputIO: nil, outputRate: nil)
    }

    /// Offline con la salida a otra frecuencia que los stems (prueba del remuestreo).
    convenience init(offlineAt outputRate: Double) {
        self.init(offline: true, devices: nil, selection: OutputSelection(), outputIO: nil, outputRate: outputRate)
    }

    private init(offline: Bool, devices: (any AudioDeviceProviding)?, selection: OutputSelection, outputIO: OutputIOFactory?,
                 outputRate: Double?) {
        self.offline = offline
        forcedOutputRate = outputRate
        #if os(Windows)
        // Salida propia por WASAPI a la frecuencia de mezcla del endpoint (parte 7.10); `nil` = render por defecto.
        self.outputIO = outputIO ?? { route in try WASAPIAudioIO(outputUID: route?.device.uid ?? "") }
        #else
        self.outputIO = outputIO ?? { _ in throw PlatformError.unsupported("paso 7: wasapi") }
        #endif
        if let devices {
            let controller = OutputController(provider: devices, selection: selection)
            output = controller
            controller.onRouteChange = { [weak self] route in self?.routeChanged(route) }
            applyRoute(controller.route)
        }
        #if os(Windows)
        // Sin proveedor de dispositivos: el nombre del endpoint que abrirá el primer play (el de la selección o el de
        // consola por defecto), leído sin abrirlo (parte 8.6d-A). Al abrir la salida pasa a ser el del flujo (`startRun`).
        if devices == nil, !offline {
            outputDeviceName = WASAPIAudioIO.renderName(outputUID: selection.deviceUID ?? "") ?? ""
        }
        #endif
    }

    /// Soltar el reproductor cierra sus stems antes de volver, aunque siga alojado o la sesión (o la salida propia)
    /// retenga el motor un rato: en Windows un fichero abierto no se puede borrar ni reescribir (plan, «Pendiente tras
    /// el paso 7»). `shutdown` espera al bloque de render en curso; el render no toca los lectores.
    deinit { engine?.shutdown() }

    public func setOutput(_ selection: OutputSelection) { output?.select(selection) }

    // MARK: Carga

    public func load(tracks newTracks: [Track]) throws {
        try rebuild(stems: newTracks, takes: [])
    }

    public func setTake(_ newTake: TakeTrack?) throws {
        try setTakes(newTake.map { [$0] } ?? [])
    }

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

    private static func info(_ url: URL) throws -> (rate: Double, frames: Int64) {
        do {
            let r = try AudioFileReader(url: url)
            return (r.sampleRate, Int64(r.frameCount))
        } catch {
            throw StudyPlayerError.unreadable(url.lastPathComponent)
        }
    }

    private func rebuild(stems newTracks: [Track], takes newTakes: [TakeTrack]) throws {
        guard !newTracks.isEmpty else { throw StudyPlayerError.noTracks }
        if isPlaying { pause() }
        var list: [PortableStem] = []
        var rate: Double?
        var length: Int64 = 0
        for track in newTracks {
            let (r, n) = try Self.info(track.url)
            if let rate, rate != r { throw StudyPlayerError.sampleRateMismatch }
            rate = r
            length = max(length, n)
            list.append(PortableStem(url: track.url))
        }
        let sr = rate!
        for newTake in newTakes {
            // Como en el Mac: una toma a otra frecuencia se remuestrea al cargar sin tocar el original.
            let url: URL
            do { url = try TakeResampling.readable(newTake.url, at: sr) } catch {
                throw StudyPlayerError.unreadable(newTake.url.lastPathComponent)
            }
            guard try Self.info(url).rate == sr else { throw StudyPlayerError.sampleRateMismatch }
            list.append(PortableStem(url: url, offset: Int64((newTake.songStart * sr).rounded()),
                                     fadeOutFrom: newTake.silencedFrom.map { Int64(($0 * sr).rounded()) }))
        }
        // Alojado a otra frecuencia ya no vale: vuelve a su propia salida.
        if host != nil, abs((hostSession?.sampleRate ?? sr) - sr) >= 0.5 { detach() }
        stems = list
        sampleRate = sr
        lengthFrames = length
        try installEngine(outputRate: currentOutputRate())
        stemTracks = newTracks
        takes = newTakes
        tracks = newTracks + newTakes.map { Track(id: $0.id, url: $0.url) }
        mix = newTracks.map { _ in StemMix() } + newTakes.map { StemMix(gainDB: $0.gainDB, muted: $0.muted, solo: $0.solo) }
        duration = Double(length) / sr
        pausedTime = 0
        applyMix()
        loop = loopValue
        applyMetronome()
    }

    /// Frecuencia de salida: la de los stems alojado u offline; la del `AudioIO` propio si ya está abierto.
    private func currentOutputRate() -> Double {
        if let forcedOutputRate { return forcedOutputRate }
        if host == nil, !offline, let io = ownIO { return io.format.sampleRate }
        return sampleRate
    }

    /// Crea el motor para los stems cargados (y lo vuelve a poner en la sesión si está alojado).
    private func installEngine(outputRate: Double) throws {
        engine?.shutdown()
        engine = nil
        // Los `Task` no retienen el reproductor ni el motor mientras esperan: soltar el reproductor cierra sus stems ya.
        let e = try PortablePlaybackEngine(stems: stems, songRate: sampleRate, length: lengthFrames, outputRate: outputRate,
                                           realtime: !offline) { [weak self] generation in
            Task { @MainActor [weak self] in
                // Lo último entregado a Signalsmith tarda en sonar; se espera antes de parar (como en el Mac).
                try? await Task.sleep(for: .milliseconds(300))
                self?.reachedEnd(generation)
            }
        }
        engine = e
        e.setEnd(endFrames())
        if let session = hostSession, host != nil {
            let renderer = PortableHostedRenderer(engine: e, presentationLatencyFrames: session.outputLatencyFrames)
            host = renderer
            session.setPlayer(renderer) { [weak self, weak renderer] in
                Task { @MainActor [weak self, weak renderer] in
                    guard let renderer else { return }
                    self?.sessionEnded(renderer)
                }
            }
        }
        applyMix()
        e.setMasterGain(Float(pow(10, masterGainValue / 20)))
        applyMetronome()
    }

    // MARK: Transporte

    public func play() throws {
        guard !isPlaying, engine != nil else { return }
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
        guard isPlaying, sampleRate > 0, let engine else { return pausedTime }
        let s = engine.snapshot()
        guard !s.pendingStart else { return s.startSongFrame / sampleRate }
        let own = !offline && host == nil
        var y = s.lastRenderStart + s.lastRenderFrames
        let h = engine.lastRenderHostSeconds
        if own, h != 0 {
            let elapsed = HostClock.nowSeconds - h
            y = s.lastRenderStart + min(max(0, elapsed * engine.outputRate), 2 * s.lastRenderFrames)
        }
        let latency = host?.presentationLatencyFrames ?? (own ? (ownIO?.declaredLatencySamples ?? 0) / 2 : 0)
        return s.songFrame(atOutput: y - latency) / sampleRate
    }

    private func startRun(at time: Double, declick: Bool = false) throws {
        guard var e = engine else { return }
        stopRun()
        let own = !offline && host == nil
        if own && ownIO == nil {
            do { ownIO = try outputIO(appliedRoute) } catch { throw StudyPlayerError.engine("\(error)") }
            #if os(Windows)
            // Sin ruta: el nombre pasa a ser el del endpoint que se abrió de verdad (parte 8.6d-A).
            if output == nil, let w = ownIO as? WASAPIAudioIO, !w.streamInfo.renderName.isEmpty {
                outputDeviceName = w.streamInfo.renderName
            }
            #endif
            if let io = ownIO, abs(io.format.sampleRate - e.outputRate) >= 0.5 {
                try installEngine(outputRate: io.format.sampleRate)
                e = engine!
            }
        }
        var frame = Int64((min(max(time, 0), duration) * sampleRate).rounded())
        let loopFrames = loopRange()
        if let l = loopFrames, frame >= l.upperBound { frame = l.lowerBound }
        stretchRun = forceStretchForTests || !(rateValue == 1 && pitchValue == 0)
        runGeneration = e.start(songFrame: frame, loop: loopFrames, rate: rateValue, cents: pitchValue, declick: declick,
                                forceStretch: forceStretchForTests)
        if own, let io = ownIO {
            let (l, r) = Self.channels(of: appliedRoute)
            let e = e
            do {
                try io.start(render: { b in
                    let lp = l < b.channelCount ? b[l].baseAddress : nil
                    let rp = r < b.channelCount ? b[r].baseAddress : nil
                    e.render(at: b.sampleTime, frames: b.frameCount, hostSeconds: b.hostSeconds, left: lp, right: rp)
                }, capture: { _ in })
            } catch {
                stopRun()
                throw StudyPlayerError.engine("\(error)")
            }
        }
        isPlaying = true
    }

    /// Canales del dispositivo (desde 0) para izquierda y derecha según el mapa de la ruta.
    private static func channels(of route: OutputRoute?) -> (Int, Int) {
        guard let map = route?.channelMap else { return (0, 1) }
        return (map.firstIndex(of: 0) ?? 0, map.firstIndex(of: 1) ?? 1)
    }

    private func stopRun() {
        if !offline && host == nil { ownIO?.stop() }
        engine?.stop()
    }

    private func restart(at time: Double) {
        do { try startRun(at: time, declick: isPlaying) } catch {
            isPlaying = false
            pausedTime = time
        }
    }

    private func reachedEnd(_ generation: Int) {
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

    /// Ganancia global (stems + metrónomo) en dB. Mini-spec Fase 2, P8.
    public var masterGainDB: Double {
        get { masterGainValue }
        set {
            masterGainValue = newValue
            engine?.setMasterGain(Float(pow(10, newValue / 20)))
        }
    }

    /// Nivel por canal tras ganancia, mute y solo (el último bloque renderizado).
    public var meters: [String: ChannelMeter] {
        var out: [String: ChannelMeter] = [:]
        for (i, t) in tracks.enumerated() { out[t.id] = engine?.meter(i) ?? .silent }
        return out
    }

    private func index(of id: String) -> Int? { tracks.firstIndex { $0.id == id } }

    private func applyMix() {
        let anySolo = mix.contains { $0.solo }
        for (i, m) in mix.enumerated() {
            let audible = !m.muted && (!anySolo || m.solo)
            engine?.setGain(i, audible ? Float(pow(10, m.gainDB / 20)) : 0)
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

    /// ±1250 cents. En vivo, salvo cuando a velocidad 1 se pasa de tono 0 a ≠ 0 o al revés (de la suma exacta a
    /// Signalsmith o al revés): entonces reinicia la pasada, como el Mac con su TimePitch.
    public var pitchCents: Double {
        get { pitchValue }
        set {
            let c = min(max(newValue, StudyPlayerConstants.pitchCentsRange.lowerBound),
                        StudyPlayerConstants.pitchCentsRange.upperBound)
            guard c != pitchValue else { return }
            let flips = rateValue == 1 && ((pitchValue == 0) != (c == 0))
            pitchValue = c
            if isPlaying && (flips || !stretchRun) {
                restart(at: currentTime)
            } else {
                engine?.setCents(c)
            }
        }
    }

    /// Bucle en segundos de canción. Menor de 50 ms o fuera del tema → sin bucle.
    public var loop: ClosedRange<Double>? {
        get { loopValue }
        set {
            loopValue = newValue
            if sampleRate > 0, newValue != nil, loopRange() == nil { loopValue = nil }
            engine?.setLoop(loopRange())
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
            engine?.setEnd(endFrames())
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
        guard let engine else { return }
        let sr = sampleRate
        let frames = metronomeValue.clicks
            .map { ClickFrame(songFrame: $0.time * sr, accent: $0.accent) }
            .sorted { $0.songFrame < $1.songFrame }
        engine.setClicks(frames)
        engine.setMetronome(on: metronomeValue.isEnabled, gain: Float(pow(10, metronomeValue.gainDB / 20)))
    }

    // MARK: Salida

    private func routeChanged(_ route: OutputRoute?) {
        if isPlaying && host == nil { pause() }
        applyRoute(route)
    }

    private func applyRoute(_ route: OutputRoute?) {
        appliedRoute = route
        outputDeviceName = route?.device.name ?? ""
        // La salida propia se reabre en el próximo `play` con la ruta nueva.
        guard host == nil else { return }
        ownIO?.stop()
        ownIO = nil
    }

    // MARK: Alojado en una sesión (mini-spec Fase 3, «Alineado con el backing» 1)

    public var isHosted: Bool { host != nil }

    /// Pasa a sonar dentro de `session` (por sus canales de backing), con el reloj del dispositivo. Hace falta un tema
    /// cargado a la frecuencia de la sesión. Conserva la posición y si sonaba.
    public func attach(to session: AudioSession) throws {
        guard sampleRate > 0, engine != nil else { throw StudyPlayerError.noTracks }
        guard abs(session.sampleRate - sampleRate) < 0.5 else { throw StudyPlayerError.sampleRateMismatch }
        if host != nil { detach() }
        let wasPlaying = isPlaying
        let t = currentTime
        if isPlaying { pause() }
        ownIO?.stop()
        ownIO = nil
        hostSession = session
        host = PortableHostedRenderer(engine: engine!, presentationLatencyFrames: session.outputLatencyFrames)
        do { try installEngine(outputRate: sampleRate) } catch {
            host = nil
            hostSession = nil
            throw error
        }
        pausedTime = t
        if wasPlaying { try play() }
    }

    /// Vuelve a su propia salida. Conserva la posición y si sonaba.
    public func detach() {
        guard host != nil else { return }
        let wasPlaying = isPlaying
        let t = currentTime
        if isPlaying { pause() }
        hostSession?.setPlayer(nil, onEnd: nil)
        engine?.stop()
        host = nil
        hostSession = nil
        pausedTime = t
        if wasPlaying { try? play() }
    }

    private func sessionEnded(_ renderer: PortableHostedRenderer) {
        guard host === renderer else { return }
        detach()
    }

    /// Diagnóstico del modo alojado (`nil` sin alojar).
    public var hostedDiagnostics: HostedPlaybackDiagnostics? {
        guard host != nil, let engine else { return nil }
        return HostedPlaybackDiagnostics(render: engine.renderStats, feedUnderrunFrames: engine.underrunFrames,
                                         timePitchLatencyFrames: 0, anchorLatencyFrames: engine.modelLatencyFrames)
    }

    // MARK: Ancla de reproducción

    /// Qué posición del tema suena en qué muestra de salida en la pasada en curso: en la línea de la sesión alojado, en
    /// la del `AudioIO` propio, o en la del render offline. `nil` parado o antes del primer bloque.
    public var playbackAnchor: PlaybackAnchor? { engine?.anchor }

    // MARK: Solo para tests (render offline)

    func renderOffline(frames: Int) throws -> (start: Int64, channels: [[Float]]) {
        guard let engine else { throw StudyPlayerError.noTracks }
        let start = offlineTime
        var out: [[Float]] = [[], []]
        out[0].reserveCapacity(frames)
        out[1].reserveCapacity(frames)
        var l = [Float](repeating: 0, count: Self.offlineBlock), r = l
        var left = frames
        while left > 0 {
            let n = min(Self.offlineBlock, left)
            l.withUnsafeMutableBufferPointer { lp in
                r.withUnsafeMutableBufferPointer { rp in
                    if !engine.render(at: offlineTime, frames: n, hostSeconds: 0, left: lp.baseAddress!, right: rp.baseAddress!) {
                        lp.baseAddress!.update(repeating: 0, count: n)
                        rp.baseAddress!.update(repeating: 0, count: n)
                    }
                }
            }
            out[0].append(contentsOf: l[0..<n])
            out[1].append(contentsOf: r[0..<n])
            offlineTime += Int64(n)
            left -= n
            engine.topUp()
        }
        return (start, out)
    }

    var runStartFrame: Double { engine?.snapshot().runStartFrame ?? 0 }
    var modelLatencyFrames: Double { engine?.modelLatencyFrames ?? 0 }
    var halfFadeFrames: Int64 { engine?.halfFade ?? 0 }
    var feedUnderrunFrames: Int { engine?.underrunFrames ?? 0 }
    var engineForTests: PortablePlaybackEngine? { engine }

    func songTime(atOutputFrame y: Double) -> Double {
        (engine?.snapshot().songFrame(atOutput: y) ?? 0) / sampleRate
    }
}
