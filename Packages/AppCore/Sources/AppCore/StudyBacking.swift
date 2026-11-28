import AudioKit
import Foundation
import Store

/// Une el reproductor de estudio con el estado de estudio del proyecto (copia portátil de
/// `App/Sources/BackingController.swift`, mini-spec Fase 2 §2, P7b): todo cambio va al reproductor y a `StudySession`, que
/// lo guarda en `project.json`. El A/B de tomas (Fase 3) es de la parte de Grabar y no se porta aquí.
@MainActor
final class BackingController {
    /// Rango del fader en dB (de −60 a +6); 0 dB es la ganancia neutra.
    static let faderRange = -60.0...6.0

    let session: StudySession
    let audio: StudyAudio
    var player: StudyPlayer { audio.player }
    private(set) var loadError: String?
    /// Último fallo al abrir la salida de audio o al reproducir (nil si va bien).
    private(set) var audioError: String?
    /// Código estable de `audioError` (`audioErrorCode(_:)`); nil cuando no hay error.
    private(set) var audioErrorCode: String?
    /// Bucle activo (no se guarda: cada sesión empieza sin bucle).
    private(set) var loop: ClosedRange<Double>?
    private(set) var loopName: String?
    /// Marca propia del bucle del tramo de Tablatura (decisiones-interfaz): no depende del nombre.
    private(set) var loopIsSpan = false
    /// Pistas extra del reproductor (Fase 5: transcripción sintetizada de Tablatura, `cache/tab/synth_*.wav`).
    /// Entran con ganancia 0 dB y sin tocar la mezcla guardada; al cambiarlas hay que llamar a `loadTracks()`.
    var extraTracks: [Track] = []
    /// Stems silenciados por la app sin tocar el mute guardado (Fase 5: «Oír transcripción» silencia el stem).
    private(set) var substitutedStems: Set<String> = []
    /// Se llama tras cambiar mute o solo de un stem o una guitarra (Tablatura lo usa para que la síntesis de esa pista
    /// siga la misma mezcla, Fase 5c decisión 2).
    var onMixChanged: (() -> Void)?

    /// Volumen global en dB (del perfil de equipo, igual en todos los temas).
    private(set) var masterGainDB: Double
    /// El servicio lo usa para guardar el perfil.
    var onMasterChange: ((Double) -> Void)?

    init(session: StudySession, audio: StudyAudio, masterGainDB: Double = 0) {
        self.session = session
        self.audio = audio
        self.masterGainDB = masterGainDB
        audio.player.masterGainDB = masterGainDB
        loadTracks()
    }

    var duration: Double { player.duration > 0 ? player.duration : session.project.song.duration }
    var settings: PlayerSettings { session.study.player }

    // MARK: Carga

    /// Carga los stems audibles y reaplica mezcla y ajustes guardados. `excluding` (rutas estandarizadas) deja fuera
    /// ficheros que otro va a sustituir o borrar: el reproductor los cierra al recargar (NTFS, `MoveFileEx` error 5).
    func loadTracks(excluding: Set<String> = []) {
        // Un stem sin fichero (p. ej. a medio medir) se salta en vez de impedir toda la carga.
        // Con pistas de guitarra separadas suenan ellas en lugar de `stems/guitar.wav` (no se suman dos veces).
        let layout = session.layout
        let guitarTracks = session.guitarTracks.map { Track(id: $0.role.trackID, url: layout.guitarURL($0.role)) }
        let tracks = (session.mixerStems.map { Track(id: $0.rawValue, url: layout.stemURL($0)) } + guitarTracks + extraTracks)
            .filter { FileManager.default.fileExists(atPath: $0.url.path) && !excluding.contains($0.url.standardizedFileURL.path) }
        guard let first = tracks.first else { loadError = nil; return }
        do {
            try player.load(tracks: tracks)
            loadError = nil
        } catch {
            loadError = "No se pudieron cargar los stems (\(error))."
            return
        }
        do {
            try audio.prepare(firstTrack: first.url)
            audioError = nil
            audioErrorCode = nil
        } catch {
            audioError = AudioErrorText.openMessage(error)
            audioErrorCode = AudioErrorText.code(error)
        }
        for kind in session.mixerStems where tracks.contains(where: { $0.id == kind.rawValue }) {
            apply(session.mix(for: kind), to: kind.rawValue)
        }
        for g in session.guitarTracks where tracks.contains(where: { $0.id == g.role.trackID }) {
            apply(session.mix(forGuitar: g.role), to: g.role.trackID)
        }
        for id in substitutedStems where tracks.contains(where: { $0.id == id }) { player.setMute(id, true) }
        player.masterGainDB = masterGainDB
        player.rate = settings.rate
        applyPitch()
        player.loop = loop
        refreshMetronome()
        onMixChanged?()   // las pistas extra (síntesis de Tablatura) reaplican su mute y su solo
    }

    static func describe(_ error: Error) -> String { (error as? LocalizedError)?.errorDescription ?? "\(error)" }

    /// Fase 5: silencia (o restaura) un stem del reproductor sin tocar la mezcla guardada del proyecto.
    func setSubstituted(_ id: String, _ on: Bool) {
        if on { substitutedStems.insert(id) } else { substitutedStems.remove(id) }
        if on { player.setMute(id, true); return }
        if let kind = StemKind(rawValue: id) {
            player.setMute(id, session.mix(for: kind).muted)
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
            clicks = StudyKitBridge.clicks(beats: grid.beats, downbeats: grid.downbeats, in: 0...max(duration, 0.001))
                .map { Click(time: $0.time, accent: $0.accent) }
        }
        player.metronome = Metronome(clicks: clicks, isEnabled: settings.metronomeOn, gainDB: settings.metronomeGainDB)
    }

    func stop() { player.pause() }

    // MARK: Transporte

    var isPlaying: Bool { player.isPlaying }

    /// Da a play; si la salida no abre, lo deja dicho en `audioError` y lanza `audio-unavailable`.
    func play() throws {
        if let loadError { throw RPCError(code: "load-failed", message: loadError) }
        guard !player.tracks.isEmpty else { throw RPCError(code: "load-failed", message: "El tema no tiene stems que reproducir.") }
        do {
            try player.play()
            audioError = nil
            audioErrorCode = nil
        } catch {
            let message = AudioErrorText.playMessage(error)
            audioError = message
            audioErrorCode = AudioErrorText.code(error)
            throw AudioErrorText.playRPCError(error, message: message)
        }
    }

    func pause() { player.pause() }

    func seek(to t: Double) { player.seek(to: min(max(t, 0), duration)) }

    func setLoop(_ range: ClosedRange<Double>?, name: String? = nil, span: Bool = false) {
        player.loop = range
        loop = player.loop
        loopName = loop == nil ? nil : name
        loopIsSpan = loop != nil && span
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

    func setMetronome(on: Bool? = nil, gainDB: Double? = nil) {
        session.updatePlayer {
            if let on { $0.metronomeOn = on }
            if let gainDB { $0.metronomeGainDB = min(max(gainDB, Self.faderRange.lowerBound), Self.faderRange.upperBound) }
        }
        player.metronome.isEnabled = settings.metronomeOn
        player.metronome.gainDB = settings.metronomeGainDB
    }

    private func applyPitch() { player.pitchCents = Double(settings.transpose) * 100 + settings.fineCents }

    // MARK: Mezclador

    func setGain(_ kind: StemKind, _ dB: Double) {
        let g = Self.clampFader(dB)
        session.updateMix(kind) { $0.gainDB = g }
        player.setGain(kind.rawValue, dB: g)
    }

    func setMaster(_ dB: Double) {
        let g = Self.clampFader(dB)
        masterGainDB = g
        player.masterGainDB = g
        onMasterChange?(g)
    }

    static func clampFader(_ dB: Double) -> Double { min(max(dB, faderRange.lowerBound), faderRange.upperBound) }

    func setMute(_ kind: StemKind, _ muted: Bool) {
        session.updateMix(kind) { $0.muted = muted }
        player.setMute(kind.rawValue, substitutedStems.contains(kind.rawValue) || muted)
        onMixChanged?()
    }

    func setSolo(_ kind: StemKind, _ solo: Bool) {
        session.updateMix(kind) { $0.solo = solo }
        player.setSolo(kind.rawValue, solo)
        onMixChanged?()
    }

    // Pistas de guitarra (Fase 4): el mismo mezclador, con la mezcla guardada por papel.

    func setGain(guitar role: GuitarRole, _ dB: Double) {
        let v = Self.clampFader(dB)
        session.updateMix(guitar: role) { $0.gainDB = v }
        player.setGain(role.trackID, dB: v)
    }

    func setMute(guitar role: GuitarRole, _ muted: Bool) {
        session.updateMix(guitar: role) { $0.muted = muted }
        player.setMute(role.trackID, substitutedStems.contains(role.trackID) || muted)
        onMixChanged?()
    }

    func setSolo(guitar role: GuitarRole, _ solo: Bool) {
        session.updateMix(guitar: role) { $0.solo = solo }
        player.setSolo(role.trackID, solo)
        onMixChanged?()
    }

    func toggleMute(_ kind: StemKind) { setMute(kind, !session.mix(for: kind).muted) }
    func toggleSolo(_ kind: StemKind) { setSolo(kind, !session.mix(for: kind).solo) }
    func toggleMute(guitar role: GuitarRole) { setMute(guitar: role, !session.mix(forGuitar: role).muted) }
    func toggleSolo(guitar role: GuitarRole) { setSolo(guitar: role, !session.mix(forGuitar: role).solo) }

    // Mezcla por id de canal del reproductor (Tablatura, Fase 5c decisión 2): la misma mezcla guardada que Backing.

    private func guitarRole(ofPlayerTrack id: String) -> GuitarRole? { session.guitarTracks.first { $0.role.trackID == id }?.role }

    /// Mezcla guardada del stem o la guitarra con ese canal; nil si no es un canal de estudio.
    func mix(ofPlayerTrack id: String) -> StemMix? {
        if let kind = StemKind(rawValue: id) { return session.mix(for: kind) }
        return guitarRole(ofPlayerTrack: id).map { session.mix(forGuitar: $0) }
    }

    func toggleMute(playerTrack id: String) {
        if let kind = StemKind(rawValue: id) { toggleMute(kind) } else if let r = guitarRole(ofPlayerTrack: id) { toggleMute(guitar: r) }
    }

    func toggleSolo(playerTrack id: String) {
        if let kind = StemKind(rawValue: id) { toggleSolo(kind) } else if let r = guitarRole(ofPlayerTrack: id) { toggleSolo(guitar: r) }
    }

    /// Fija ganancia, mute y solo de un canal del mezclador (el id del reproductor); false si no es un canal de estudio.
    @discardableResult
    func setMix(playerTrack id: String, gainDB: Double?, mute: Bool?, solo: Bool?) -> Bool {
        if let kind = StemKind(rawValue: id), session.mixerStems.contains(kind) {
            if let gainDB { setGain(kind, gainDB) }
            if let mute { setMute(kind, mute) }
            if let solo { setSolo(kind, solo) }
            return true
        }
        if let r = guitarRole(ofPlayerTrack: id) {
            if let gainDB { setGain(guitar: r, gainDB) }
            if let mute { setMute(guitar: r, mute) }
            if let solo { setSolo(guitar: r, solo) }
            return true
        }
        return false
    }

    /// Algún stem o guitarra en solo (la misma cuenta que el mezclador de Backing).
    var anyStemSolo: Bool { session.study.mixer.contains { $0.solo } }

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

    /// Suelta el reproductor y su salida (cierra los ficheros de audio).
    func shutdown() {
        player.pause()
        audio.shutdown()
    }
}
