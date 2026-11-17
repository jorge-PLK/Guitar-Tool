import AudioKit
import Foundation
import Observation
import Store

/// Une el reproductor de estudio con el estado de estudio del proyecto (mini-spec Fase 2 §2, P7b):
/// todo cambio va al reproductor y a `StudySession`, que lo guarda en `project.json`.
@MainActor @Observable
final class BackingController {
    /// Rango del fader en dB (de −60 a +6); 0 dB es la ganancia neutra.
    static let faderRange = -60.0...6.0
    static let meterFloorDB = -60.0

    let session: StudySession
    let player: StudyPlayer
    private(set) var loadError: String?
    /// Bucle activo (no se guarda: cada sesión empieza sin bucle).
    private(set) var loop: ClosedRange<Double>?
    private(set) var loopName: String?
    /// Pistas extra del reproductor (Fase 5: transcripción sintetizada de Tablatura, `cache/tab/synth_*.wav`).
    /// Entran con ganancia 0 dB y sin tocar la mezcla guardada; al cambiarlas hay que llamar a `loadTracks()`.
    var extraTracks: [Track] = []
    /// Stems silenciados por la app sin tocar el mute guardado (Fase 5: «Oír transcripción» silencia el stem).
    private(set) var substitutedStems: Set<String> = []
    /// Audio con el dispositivo (grabar y A/B); lo asigna la app al abrir el tema.
    @ObservationIgnored weak var audio: AudioController?

    // A/B (mini-spec Fase 3, «A/B dentro de la mezcla»).
    /// Id del canal «Tú» en el reproductor (no coincide con el de ningún stem).
    static let takeChannelID = "take"
    private(set) var compareMode: CompareMode = .original
    /// Toma cargada en el reproductor (canal «Tú»).
    private(set) var loadedTake: Take?
    /// Ganancia de `LoudnessMatch` aplicada al cargarla; nil si no se pudo medir (silencio).
    private(set) var takeGainDB: Double?
    /// Fader actual del canal «Tú» (arranca en la ganancia igualada).
    private(set) var takeFaderDB = 0.0
    private(set) var takeError: String?
    /// Tu nivel en directo menos el del stem (dB), mientras el A/B está en «Tú en directo».
    private(set) var liveDifferenceDB: Double?

    /// Volumen global en dB (del perfil de equipo, igual en todos los temas).
    private(set) var masterGainDB: Double
    /// La app lo usa para guardar el perfil.
    var onMasterChange: ((Double) -> Void)?

    init(session: StudySession, masterGainDB: Double = 0, output: OutputSelection = OutputSelection()) {
        self.session = session
        self.masterGainDB = masterGainDB
        player = StudyPlayer(devices: CoreAudioDeviceProvider(), output: output)
        player.masterGainDB = masterGainDB
        loadTracks()
    }

    var duration: Double { player.duration > 0 ? player.duration : session.project.song.duration }
    var settings: PlayerSettings { session.study.player }

    // MARK: Carga

    /// Carga los stems audibles y reaplica mezcla y ajustes guardados.
    func loadTracks() {
        // Un stem sin fichero (p. ej. a medio medir) se salta en vez de impedir toda la carga.
        // Con pistas de guitarra separadas suenan ellas en lugar de `stems/guitar.wav` (no se suman dos veces).
        let layout = session.layout
        let guitarTracks = session.guitarTracks.map { Track(id: $0.role.trackID, url: layout.guitarURL($0.role)) }
        let tracks = (session.mixerStems.map { Track(id: $0.rawValue, url: layout.stemURL($0)) } + guitarTracks + extraTracks)
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
        guard !tracks.isEmpty else { loadError = nil; return }
        do {
            try player.load(tracks: tracks)
            loadError = nil
        } catch {
            loadError = "No se pudieron cargar los stems (\(error))."
            return
        }
        for kind in session.mixerStems where tracks.contains(where: { $0.id == kind.rawValue }) {
            apply(session.mix(for: kind), to: kind.rawValue)
            // A/B de la Fase 3: en B el stem de guitarra suena silenciado sin tocar el mute guardado.
            if kind == .guitar { player.setMute(kind.rawValue, effectiveGuitarMute) }
        }
        for g in session.guitarTracks where tracks.contains(where: { $0.id == g.role.trackID }) {
            apply(session.mix(forGuitar: g.role), to: g.role.trackID)
        }
        for id in substitutedStems where tracks.contains(where: { $0.id == id }) { player.setMute(id, true) }
        player.rate = settings.rate
        applyPitch()
        player.loop = loop
        refreshMetronome()
    }

    /// Fase 5: silencia (o restaura) un stem del reproductor sin tocar la mezcla guardada del proyecto.
    func setSubstituted(_ id: String, _ on: Bool) {
        if on { substitutedStems.insert(id) } else { substitutedStems.remove(id) }
        if on { player.setMute(id, true); return }
        if let kind = StemKind(rawValue: id) {
            player.setMute(id, kind == .guitar ? effectiveGuitarMute : session.mix(for: kind).muted)
        } else if let g = session.guitarTracks.first(where: { $0.role.trackID == id }) {
            player.setMute(id, session.mix(forGuitar: g.role).muted)
        }
    }

    /// Fase 5: mute de una pista extra (la sintetizada suena solo con «Oír transcripción»).
    func setExtraMuted(_ id: String, _ muted: Bool) { player.setMute(id, muted) }

    private func apply(_ m: StemMix, to id: String) {
        player.setGain(id, dB: m.gainDB)
        player.setMute(id, m.muted)
        player.setSolo(id, m.solo)
    }

    /// Recalcula los clics tras un análisis nuevo o un cambio del metrónomo.
    func refreshMetronome() {
        var clicks: [Click] = []
        if let grid = session.metronomeBeats {
            clicks = StudyBridge.clicks(grid, in: 0...max(duration, 0.001)).map { Click(time: $0.time, accent: $0.accent) }
        }
        player.metronome = Metronome(clicks: clicks, isEnabled: settings.metronomeOn, gainDB: settings.metronomeGainDB)
    }

    func stop() { player.pause() }

    // MARK: Transporte

    var isPlaying: Bool { player.isPlaying }

    func togglePlay() {
        if player.isPlaying { player.pause(); return }
        do { try player.play() } catch { loadError = "No se pudo reproducir (\(error))." }
    }

    func seek(to t: Double) { player.seek(to: min(max(t, 0), duration)) }

    func setLoop(_ range: ClosedRange<Double>?, name: String? = nil) {
        player.loop = range
        loop = player.loop
        loopName = loop == nil ? nil : name
    }

    // MARK: Ajustes del reproductor

    func setRate(_ r: Double) {
        session.updatePlayer { $0.rate = r }
        player.rate = settings.rate
    }

    func setTranspose(_ n: Int) {
        session.updatePlayer { $0.transpose = n }
        applyPitch()
    }

    func setFineCents(_ c: Double) {
        session.updatePlayer { $0.fineCents = c }
        applyPitch()
    }

    /// Solo cambia los diagramas.
    func setCapo(_ n: Int) { session.updatePlayer { $0.capo = min(max(n, 0), 12) } }

    func setMetronome(_ on: Bool) {
        session.updatePlayer { $0.metronomeOn = on }
        player.metronome.isEnabled = on
    }

    private func applyPitch() { player.pitchCents = Double(settings.transpose) * 100 + settings.fineCents }

    // MARK: Mezclador

    func setGain(_ kind: StemKind, _ dB: Double) {
        let g = min(max(dB, Self.faderRange.lowerBound), Self.faderRange.upperBound)
        session.updateMix(kind) { $0.gainDB = g }
        player.setGain(kind.rawValue, dB: g)
    }

    func setMaster(_ dB: Double) {
        let g = min(max(dB, Self.faderRange.lowerBound), Self.faderRange.upperBound)
        masterGainDB = g
        player.masterGainDB = g
        onMasterChange?(g)
    }

    func toggleMute(_ kind: StemKind) {
        let m = !session.mix(for: kind).muted
        session.updateMix(kind) { $0.muted = m }
        player.setMute(kind.rawValue, kind == .guitar ? effectiveGuitarMute : m)
    }

    func toggleSolo(_ kind: StemKind) {
        let s = !session.mix(for: kind).solo
        session.updateMix(kind) { $0.solo = s }
        player.setSolo(kind.rawValue, s)
    }

    // Pistas de guitarra (Fase 4): el mismo mezclador, con la mezcla guardada por papel.

    func setGain(guitar role: GuitarRole, _ dB: Double) {
        let v = min(max(dB, Self.faderRange.lowerBound), Self.faderRange.upperBound)
        session.updateMix(guitar: role) { $0.gainDB = v }
        player.setGain(role.trackID, dB: v)
    }

    func toggleMute(guitar role: GuitarRole) {
        let m = !session.mix(forGuitar: role).muted
        session.updateMix(guitar: role) { $0.muted = m }
        player.setMute(role.trackID, m)
    }

    func toggleSolo(guitar role: GuitarRole) {
        let s = !session.mix(forGuitar: role).solo
        session.updateMix(guitar: role) { $0.solo = s }
        player.setSolo(role.trackID, s)
    }

    /// Preajuste «Sin guitarras»: silencia el stem guitar (o todas las pistas separadas); otra pulsación lo restaura.
    var hasGuitar: Bool { session.audibleStems.contains(.guitar) }
    var guitarsOff: Bool {
        session.usesSeparatedGuitars ? session.guitarTracks.allSatisfy { session.mix(forGuitar: $0.role).muted }
                                     : session.mix(for: .guitar).muted
    }
    func toggleWithoutGuitars() {
        guard hasGuitar else { return }
        guard session.usesSeparatedGuitars else { toggleMute(.guitar); return }
        let off = !guitarsOff
        for g in session.guitarTracks where session.mix(forGuitar: g.role).muted != off { toggleMute(guitar: g.role) }
    }

    // MARK: A/B

    /// Mute del stem de guitarra tal como lo ve el reproductor: el del usuario, salvo en B (silenciado).
    /// El del usuario (el guardado en el proyecto) no se toca nunca.
    private var effectiveGuitarMute: Bool {
        MixCompare.stemMuted(mode: compareMode, userMuted: session.mix(for: .guitar).muted)
    }

    var lastTake: Take? { session.playableTakes.last }

    func applyCompareMute() {
        if hasGuitar { player.setMute(StemKind.guitar.rawValue, effectiveGuitarMute) }
        if loadedTake != nil { player.setMute(Self.takeChannelID, compareMode != .lastTake) }
    }

    func setCompare(_ mode: CompareMode) {
        guard mode != compareMode, hasGuitar else { return }
        compareMode = mode
        liveDifferenceDB = nil
        applyCompareMute()
        if mode == .lastTake, let t = lastTake, loadedTake != t { Task { await loadLastTake() } }
    }

    /// Lo llama el controlador de audio al guardar una toma (nueva) o corregir las sin calibrar.
    func takesChanged(isNew: Bool) {
        Task { await loadLastTake() }
    }

    /// Carga la última toma no descartada como canal «Tú», igualada en sonoridad al stem de guitarra.
    func loadLastTake() async {
        guard let t = lastTake, let rel = t.processedFile, let start = t.songStart, let fs = t.sampleRate else { return }
        if loadedTake == t { return }
        let url = session.layout.folder.appendingPathComponent(rel)
        let stemURL = session.layout.stemURL(.guitar)
        let hasStem = hasGuitar
        let match = await Task.detached { () -> LoudnessMatch.Result? in
            guard hasStem, let take = try? AudioSamples.read(url), let frames = take.first?.count, frames > 0,
                  let stem = try? AudioSamples.read(stemURL, from: start, seconds: Double(frames) / fs) else { return nil }
            return LoudnessMatch.gain(take: take, stem: stem, sampleRate: fs)
        }.value
        let gain = match?.unclampedGainDB == nil ? nil : match?.gainDB
        do {
            try player.setTake(TakeTrack(id: Self.takeChannelID, url: url, songStart: start, gainDB: gain ?? 0,
                                         muted: compareMode != .lastTake))
            loadedTake = t
            takeGainDB = gain
            takeFaderDB = gain ?? 0
            takeError = nil
        } catch {
            loadedTake = nil
            takeGainDB = nil
            takeError = "No se pudo cargar la toma (\(error))."
        }
        applyCompareMute()
    }

    func setTakeGain(_ dB: Double) {
        let g = min(max(dB, Self.faderRange.lowerBound), Self.faderRange.upperBound)
        takeFaderDB = g
        player.setGain(Self.takeChannelID, dB: g)
    }

    /// Diferencia de nivel en directo: tu procesada (3 s) frente al stem en el tramo recién tocado, con su fader.
    func refreshLiveDifference() async {
        guard compareMode == .live, hasGuitar else { liveDifferenceDB = nil; return }
        let live = audio?.liveGuitarLevelDB()
        let seconds = AudioSession.liveLevelSeconds
        let from = max(0, player.currentTime - seconds)
        let url = session.layout.stemURL(.guitar)
        let stemRMS = await Task.detached { () -> Double? in
            guard let x = try? AudioSamples.read(url, from: from, seconds: seconds) else { return nil }
            return AudioSamples.rmsDB(x)
        }.value
        guard compareMode == .live else { return }
        liveDifferenceDB = MixCompare.liveDifferenceDB(liveDB: live, stemRMSDB: stemRMS,
                                                       faderDB: session.mix(for: .guitar).gainDB)
    }

    #if DEBUG
    /// Estado inicial para capturas, sin reproducir.
    func apply(rate: Double?, transpose: Int?, capo: Int?, muted: [String], loop: ClosedRange<Double>?, seek: Double?) {
        if let rate { setRate(rate) }
        if let transpose { setTranspose(transpose) }
        if let capo { setCapo(capo) }
        for k in muted { if let kind = StemKind(rawValue: k), !session.mix(for: kind).muted { toggleMute(kind) } }
        if let loop { setLoop(loop) }
        if let seek { self.seek(to: seek) }
    }
    #endif
}
