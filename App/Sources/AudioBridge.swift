import AVFoundation
import AudioKit
import Foundation
import Store

/// Puente Store ↔ AudioKit de la calibración y las tomas (mini-spec Fase 3, «Código»): los tipos tienen nombres
/// distintos a propósito (`LatencyCalibrationKey` / `CalibrationKey`, etc.) y aquí se convierten campo a campo.
/// Lo no trivial (claves en términos del perfil, calibración restaurada) vive en AudioKit, con tests.
enum AudioBridge {
    // MARK: Claves

    static func storeKey(_ k: LatencyCalibrationKey) -> CalibrationKey {
        CalibrationKey(inputUID: k.inputUID, outputUID: k.outputUID, sampleRate: k.sampleRate, bufferFrames: k.bufferFrames,
                       inputChannel: k.inputChannel, outputChannel: k.outputChannel)
    }

    static func kitKey(_ k: CalibrationKey) -> LatencyCalibrationKey {
        LatencyCalibrationKey(inputUID: k.inputUID, outputUID: k.outputUID, sampleRate: k.sampleRate,
                              bufferFrames: k.bufferFrames, inputChannel: k.inputChannel, outputChannel: k.outputChannel)
    }

    // MARK: Sesión

    /// Configuración de la sesión; nil sin dispositivo de entrada.
    static func setup(_ a: AudioSettings, workingRate: Double) -> AudioSetup? {
        guard let input = a.inputDeviceUID else { return nil }
        return AudioSetup(inputDeviceUID: input, outputDeviceUID: a.outputDeviceUID ?? "", sampleRate: workingRate,
                          backingLeft: a.backingOut.left, backingRight: a.backingOut.right, guitarIn: a.guitarIn ?? [],
                          bufferFrames: a.bufferFrames)
    }

    // MARK: Calibración

    /// Lo que se guarda en el perfil tras calibrar con éxito.
    static func calibration(_ r: LatencyCalibrationResult, audio: AudioSettings) -> LatencyCalibration {
        LatencyCalibration(latencySamples: r.latencySamples, spreadSamples: r.spreadSamples, date: r.date,
                           key: storeKey(r.key.inProfileTerms(outputDeviceUID: audio.outputDeviceUID)),
                           referenceIn: r.reference.map { ReferenceChannel(channel: $0.channel, latencySamples: $0.latencySamples) })
    }

    /// La calibración guardada, lista para la sesión, si su clave vale para ella (si no, nil: «Sin calibrar»).
    static func restored(_ saved: LatencyCalibration, audio: AudioSettings, sessionKey: LatencyCalibrationKey,
                         guitarIn: [Int], inputChannels: Int) -> LatencyCalibrationResult? {
        guard storeKey(sessionKey.inProfileTerms(outputDeviceUID: audio.outputDeviceUID)) == saved.key else { return nil }
        return .restored(key: sessionKey, date: saved.date, guitarIn: guitarIn, latencySamples: saved.latencySamples,
                         spreadSamples: saved.spreadSamples, inputChannels: inputChannels,
                         reference: saved.referenceIn.map { ReferenceInput(channel: $0.channel, latencySamples: $0.latencySamples) })
    }

    // MARK: Tomas

    static func take(_ t: RecordedTake, id: UUID, audio: AudioSettings, createdAt: Date = Date()) -> Take {
        Take(id: id, processedFile: ProjectLayout.processedRelativePath(takeId: id), createdAt: createdAt,
             songStart: t.songStart, sampleRate: t.sampleRate, latencySamples: t.latencySamples,
             rigDelaySamples: t.rigDelaySamples, rigDelayReliable: t.rigDelayReliable, latencyCalibrated: t.latencyCalibrated,
             calibrationKey: storeKey(t.calibrationKey.inProfileTerms(outputDeviceUID: audio.outputDeviceUID)),
             clock: ClockMode(rawValue: t.clock.rawValue))
    }

    /// La toma guardada como la ve AudioKit para corregirla al calibrar; nil si no es una toma de esta fase o falta el fichero.
    static func recorded(_ take: Take, folder: URL, resolvedOutputUID: String) -> (take: RecordedTake, file: URL)? {
        guard let rel = take.processedFile, let songStart = take.songStart, let fs = take.sampleRate,
              let latency = take.latencySamples, let key = take.calibrationKey, let clock = take.clock else { return nil }
        let url = folder.appendingPathComponent(rel)
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let r = RecordedTake(restoring: songStart, sampleRate: fs, frameCount: Int(file.length),
                             channelCount: Int(file.processingFormat.channelCount), latencySamples: latency,
                             rigDelaySamples: take.rigDelaySamples, rigDelayReliable: take.rigDelayReliable,
                             latencyCalibrated: take.latencyCalibrated ?? false,
                             calibrationKey: kitKey(key).resolvingDefaultOutput(to: resolvedOutputUID),
                             clock: AudioIOClock(rawValue: clock.rawValue) ?? .single)
        return (r, url)
    }

    /// La toma de Store con lo que cambió al volver a desplazarla.
    static func applying(_ r: RecordedTake, to take: Take) -> Take {
        var t = take
        t.songStart = r.songStart
        t.latencySamples = r.latencySamples
        t.rigDelaySamples = r.rigDelaySamples
        t.rigDelayReliable = r.rigDelayReliable
        t.latencyCalibrated = r.latencyCalibrated
        return t
    }
}
