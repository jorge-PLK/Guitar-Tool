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

    /// Volumen global en dB (del perfil de equipo, igual en todos los temas).
    private(set) var masterGainDB: Double
    /// La app lo usa para guardar el perfil.
    var onMasterChange: ((Double) -> Void)?

    init(session: StudySession, masterGainDB: Double = 0) {
        self.session = session
        self.masterGainDB = masterGainDB
        player = StudyPlayer(devices: CoreAudioDeviceProvider())
        player.masterGainDB = masterGainDB
        loadTracks()
    }

    var duration: Double { player.duration > 0 ? player.duration : session.project.song.duration }
    var settings: PlayerSettings { session.study.player }

    // MARK: Carga

    /// Carga los stems audibles y reaplica mezcla y ajustes guardados.
    func loadTracks() {
        // Un stem sin fichero (p. ej. a medio medir) se salta en vez de impedir toda la carga.
        let tracks = session.audibleStems.map { Track(id: $0.rawValue, url: session.layout.stemURL($0)) }
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
        guard !tracks.isEmpty else { loadError = nil; return }
        do {
            try player.load(tracks: tracks)
            loadError = nil
        } catch {
            loadError = "No se pudieron cargar los stems (\(error))."
            return
        }
        for kind in session.audibleStems where tracks.contains(where: { $0.id == kind.rawValue }) {
            let m = session.mix(for: kind)
            player.setGain(kind.rawValue, dB: m.gainDB)
            player.setMute(kind.rawValue, m.muted)
            player.setSolo(kind.rawValue, m.solo)
        }
        player.rate = settings.rate
        applyPitch()
        player.loop = loop
        refreshMetronome()
    }

    /// Recalcula los clics tras un análisis nuevo o un cambio del metrónomo.
    func refreshMetronome() {
        var clicks: [Click] = []
        if let grid = session.beats {
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
        player.setMute(kind.rawValue, m)
    }

    func toggleSolo(_ kind: StemKind) {
        let s = !session.mix(for: kind).solo
        session.updateMix(kind) { $0.solo = s }
        player.setSolo(kind.rawValue, s)
    }

    /// Preajuste «Sin guitarras»: silencia el stem guitar; otra pulsación lo restaura.
    var hasGuitar: Bool { session.audibleStems.contains(.guitar) }
    var guitarsOff: Bool { session.mix(for: .guitar).muted }
    func toggleWithoutGuitars() { if hasGuitar { toggleMute(.guitar) } }

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
