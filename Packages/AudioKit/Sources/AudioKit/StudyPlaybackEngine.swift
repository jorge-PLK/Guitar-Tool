import Foundation

/// Costura del reproductor de estudio (plan, «Corte del paso 7», parte 7.6): lo que la app (y la de Windows, paso 8)
/// pide al reproductor. En el Mac la cumple `StudyPlayer` sobre AVAudioEngine, sin cambios; en Windows, `StudyPlayer`
/// es `PortableStudyPlayer` (mezclador propio por extracción + Signalsmith Stretch).
///
/// Tiempo: `currentTime` es la posición del tema que se oye; `playbackAnchor` liga esa posición con una muestra de la
/// línea de salida (la de la `AudioSession` si está alojado). Con `AudioSession.outputHostClock` (muestra → segundos de
/// `HostClock`) da la marca de host que necesitan el alineado de tomas y el vídeo.
@MainActor
public protocol StudyPlaybackEngine: AnyObject {
    /// Stems y, al final, las pistas de toma en su orden.
    var tracks: [Track] { get }
    var takes: [TakeTrack] { get }
    var take: TakeTrack? { get }
    var duration: Double { get }
    var isPlaying: Bool { get }
    /// Nombre de la salida en uso («» si no hay ninguna).
    var outputDeviceName: String { get }
    func setOutput(_ selection: OutputSelection)

    /// Carga los stems de un tema (quita las pistas de toma). Todos a la misma frecuencia.
    func load(tracks: [Track]) throws
    func setTake(_ take: TakeTrack?) throws
    /// Pistas de toma; conserva la mezcla de los stems, la posición y si sonaba.
    func setTakes(_ takes: [TakeTrack]) throws

    func play() throws
    func pause()
    func seek(to time: Double)
    /// Segundos de canción de lo que se oye.
    var currentTime: Double { get }

    func setGain(_ id: String, dB: Double)
    func setMute(_ id: String, _ muted: Bool)
    func setSolo(_ id: String, _ solo: Bool)
    var masterGainDB: Double { get set }
    var meters: [String: ChannelMeter] { get }

    /// 0,5…2,0.
    var rate: Double { get set }
    /// ±1250 cents.
    var pitchCents: Double { get set }
    var loop: ClosedRange<Double>? { get set }
    /// Fin de la reproducción (s de canción, `nil` = final del tema): parada exacta por muestras al programar.
    var endTime: Double? { get set }
    var metronome: Metronome { get set }

    /// Alojado en una sesión de `AudioIO`: backing y grabación con el reloj del dispositivo.
    var isHosted: Bool { get }
    func attach(to session: AudioSession) throws
    func detach()
    /// Posición del tema ↔ muestra de salida de la pasada en curso; `nil` parado o antes del primer bloque.
    var playbackAnchor: PlaybackAnchor? { get }
    var hostedDiagnostics: HostedPlaybackDiagnostics? { get }
}

extension PortableStudyPlayer: StudyPlaybackEngine {}

#if canImport(AVFoundation)
extension StudyPlayer: StudyPlaybackEngine {}
#else
/// En Windows el reproductor de estudio es el portátil.
public typealias StudyPlayer = PortableStudyPlayer
#endif
