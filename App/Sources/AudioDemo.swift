#if DEBUG
import AudioKit
import Foundation
import Store

/// Capturas sin hardware (solo DEBUG): `--screen settings-audio | calibration-sheet | backing-ab` usan dispositivos
/// y E/S simulados (`SimulatedDeviceProvider`, `SimulatedAudioIO`), sin tocar la tarjeta de sonido.
enum AudioDemo {
    static let screens: Set<String> = ["settings-audio", "calibration-sheet", "backing-ab"]

    /// `SimulatedAudioIO` con el tiempo de la pared: rig con saturación y retardo en el canal 1, canal 3 de
    /// referencia interno (sin rig) y ruido en los demás para que los medidores se muevan.
    static let makeIO: AudioSession.IOFactory = { setup in
        let fs = setup.sampleRate
        let inputs = [
            SimulatedInput(source: 1, extraDelaySamples: 150.37, drive: 2, gain: 0.5, noiseDBFS: -60),
            SimulatedInput(source: nil, noiseDBFS: -26),
            SimulatedInput(source: 1, noiseDBFS: -60),
            SimulatedInput(source: nil, noiseDBFS: -42),
        ]
        let sim = SimulatedAudioIO(sampleRate: fs, outputChannels: 4, inputs: inputs,
                                   latencySamples: fs == 44_100 ? 2_205.37 : 2_400.81, declaredLatencySamples: 1_200,
                                   bufferFrames: setup.bufferFrames, inputDeviceUID: setup.inputDeviceUID,
                                   outputDeviceUID: setup.outputDeviceUID.isEmpty ? "sim-builtin" : setup.outputDeviceUID)
        return PacedSimulatedIO(sim)
    }
}

/// Conduce un `SimulatedAudioIO` no automático a ritmo de reloj (el automático corre lo más rápido que puede).
final class PacedSimulatedIO: AudioIO, @unchecked Sendable {
    private let sim: SimulatedAudioIO
    private let lock = NSLock()
    private var thread: Thread?
    private let finished = DispatchSemaphore(value: 0)

    init(_ sim: SimulatedAudioIO) { self.sim = sim }

    var format: AudioIOFormat { sim.format }
    var inputDeviceUID: String { sim.inputDeviceUID }
    var outputDeviceUID: String { sim.outputDeviceUID }
    var clock: AudioIOClock { sim.clock }
    var declaredLatencySamples: Double { sim.declaredLatencySamples }
    var isRunning: Bool { sim.isRunning }

    func start(render: @escaping AudioIORenderHandler, capture: @escaping AudioIOCaptureHandler) throws {
        try sim.start(render: render, capture: capture)
        let interval = Double(sim.format.bufferFrames) / sim.format.sampleRate
        let t = Thread { [sim, finished] in
            while sim.isRunning {
                sim.pump()
                Thread.sleep(forTimeInterval: interval)
            }
            finished.signal()
        }
        lock.withLock { thread = t }
        t.start()
    }

    func stop() {
        sim.stop()
        let t = lock.withLock { () -> Thread? in defer { thread = nil }; return thread }
        if let t, t != Thread.current { finished.wait() }
    }

    func setInterruptionHandler(_ handler: (@Sendable (AudioIOInterruption) -> Void)?) {
        sim.setInterruptionHandler(handler)
    }
}

extension AppModel {
    /// `--screen backing-ab`: con el tema abierto, calibra contra la E/S simulada, graba unos segundos desde el
    /// segundo 20 y deja el A/B en «B · Última toma» (necesita `--snapshot-delay` de unos 30 s).
    func runAudioDemo() {
        guard let backing, let study else { return }
        let rate = study.project.song.sampleRate
        if EquipmentProfile.allowedSampleRates.contains(rate) { profile.workingSampleRate = rate }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            await audio.calibrate()
            audio.dismissCalibration()
            backing.setRate(1)   // el tema puede traer otro tempo guardado y solo se graba al 100 %
            backing.seek(to: 20)
            audio.startRecording(playbackRate: 1, loopActive: false)
            try? await Task.sleep(for: .seconds(8))
            audio.stopRecording()
            try? await Task.sleep(for: .seconds(1))
            await backing.loadLastTake()
            backing.setCompare(.lastTake)
            try? await Task.sleep(for: .seconds(2))
        }
    }
}
#endif
