import AudioKit
import Foundation
import Store

/// `--audio` (8.5): qué salida de audio usa el reproductor de estudio.
public enum AudioMode: String, Sendable, Equatable {
    /// `SimulatedAudioIO` con reloj real: el tiempo avanza como si sonara, sin abrir ningún dispositivo.
    case simulated
    /// La salida elegida en el perfil o la del sistema (CoreAudio en el Mac, WASAPI en Windows).
    case device
}

/// Aloja el reproductor de estudio y su salida de audio (de `AudioController.swift` del Mac solo lo necesario para abrir la
/// salida y alojar el reproductor; calibración, medidores de entrada y grabación son de otras partes).
@MainActor
final class StudyAudio {
    /// Bloque de la salida simulada (el de la sesión real: `AudioSetup.defaultBufferFrames`).
    static let simulatedBlockFrames = AudioSetup.defaultBufferFrames
    /// Latencia de ida y vuelta de la salida simulada, en muestras (mínimo causal de `SimulatedAudioIO` = 33).
    static let simulatedLatencyFrames = 256.0
    static let simulatedOutputName = "Salida simulada"

    let mode: AudioMode
    let player: StudyPlayer
    private var session: AudioSession?
    private var pump: RealtimePump?

    /// `output`: salida elegida en el perfil (`nil` UID = la del sistema).
    init(mode: AudioMode, output: OutputSelection) {
        self.mode = mode
        switch mode {
        case .simulated:
            // Render offline: nunca crea un dispositivo; alojado en la sesión simulada lo renderiza la sesión.
            player = StudyPlayer(offlineWith: nil)
        case .device:
            #if canImport(AVFoundation)
            player = StudyPlayer(devices: CoreAudioDeviceProvider(), output: output)
            #else
            // Windows: salida propia por WASAPI; el endpoint elegido en el perfil o, sin él, el del sistema. El
            // reproductor lee su nombre al crearse (sin abrirlo) y lo cambia por el del flujo al abrirlo (8.6d-A).
            let uid = output.deviceUID ?? ""
            player = StudyPlayer(devices: nil, output: output, outputIO: { _ in try WASAPIAudioIO(outputUID: uid) })
            #endif
        }
    }

    /// Mac: aparato de la ruta de salida. Windows: el endpoint que abrirá (o abrió) la salida propia. Los dos ya al abrir
    /// el tema (8.6d-A); en Windows se relee en cada `study.open` (un `StudyAudio` nuevo) y al dar a play.
    var outputName: String {
        if mode == .simulated { return Self.simulatedOutputName }
        return player.outputDeviceName
    }

    /// Tras cargar los stems: en simulado abre la sesión simulada (a la frecuencia de los stems) y aloja el reproductor.
    /// En `device` no hace nada: la salida se abre al dar a play.
    func prepare(firstTrack url: URL) throws {
        guard mode == .simulated else { return }
        if player.isHosted, session?.isOpen == true { return }
        teardownSimulation()
        let rate = try TakeResampling.sampleRate(of: url)
        let io = SimulatedAudioIO(sampleRate: rate, inputs: [SimulatedInput(source: nil)],
                                  latencySamples: Self.simulatedLatencyFrames,
                                  declaredLatencySamples: Self.simulatedLatencyFrames / 2,
                                  bufferFrames: Self.simulatedBlockFrames)
        let s = AudioSession(setup: AudioSetup(inputDeviceUID: io.inputDeviceUID, outputDeviceUID: io.outputDeviceUID,
                                               sampleRate: rate),
                             makeIO: { _ in io })
        try s.open()
        do { try player.attach(to: s) } catch {
            s.close()
            throw error
        }
        session = s
        let p = RealtimePump(io: io, sampleRate: rate, block: Self.simulatedBlockFrames)
        pump = p
        p.start()
    }

    private func teardownSimulation() {
        pump?.stop()
        pump = nil
        player.detach()
        session?.close()
        session = nil
    }

    /// Para, suelta la salida y los ficheros del reproductor.
    func shutdown() {
        player.pause()
        teardownSimulation()
    }
}

/// Hilo que da cuerda a `SimulatedAudioIO.pump` con el reloj real (el modo automático del simulador va lo más rápido
/// que puede): cada vuelta pide los bloques que habría pedido un dispositivo hasta ahora.
private final class RealtimePump: @unchecked Sendable {
    private let io: SimulatedAudioIO
    private let sampleRate: Double
    private let block: Int
    private let lock = NSLock()
    private var running = false

    init(io: SimulatedAudioIO, sampleRate: Double, block: Int) {
        self.io = io
        self.sampleRate = sampleRate
        self.block = block
    }

    func start() {
        lock.withLock { running = true }
        let t = Thread { [self] in
            let origin = ProcessInfo.processInfo.systemUptime
            var done = 0
            while lock.withLock({ running }) {
                let target = Int((ProcessInfo.processInfo.systemUptime - origin) * sampleRate)
                while done + block <= target, lock.withLock({ running }) {
                    io.pump(frames: block)
                    done += block
                }
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
        t.name = "ToneForge.StudyAudio.simulatedPump"
        t.qualityOfService = .userInitiated
        t.start()
    }

    func stop() { lock.withLock { running = false } }
}
