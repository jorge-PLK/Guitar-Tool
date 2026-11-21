#if canImport(AVFoundation)
import AVFoundation
import AudioToolbox

/// `TabSynthBackend` del Mac: render fuera de tiempo real con `AVAudioUnitSampler` (un sampler por canal MIDI de
/// los eventos, porque el sampler comparte rueda y controladores entre canales) a un WAV estéreo float32.
struct SamplerTabSynth: TabSynthBackend {
    func renderFile(events: [TabSynthRenderer.Event], totalFrames: Int, sampleRate: Double, soundFontURL: URL,
                    program: UInt8, bankMSB: UInt8, to url: URL) throws {
        let blockFrames = AVAudioFrameCount(TabSynthRenderer.blockFrames)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw TabSynthError.invalidRequest("formato estéreo a \(sampleRate) Hz")
        }
        // Un sampler por canal MIDI de los eventos (el sampler comparte rueda y controladores entre canales).
        let channels = Array(Set(events.map { $0.status & 0x0F })).sorted()
        let engine = AVAudioEngine()
        let samplers = (channels.isEmpty ? [0] : channels).map { ($0, AVAudioUnitSampler()) }
        for (_, sampler) in samplers {
            engine.attach(sampler)
            engine.connect(sampler, to: engine.mainMixerNode, format: format)
        }
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: blockFrames)
        } catch {
            throw TabSynthError.engine("modo de render manual: \(error.localizedDescription)")
        }
        for (_, sampler) in samplers {
            do {
                try sampler.loadSoundBankInstrument(at: soundFontURL, program: program, bankMSB: bankMSB,
                                                    bankLSB: UInt8(kAUSampler_DefaultBankLSB))
            } catch {
                throw TabSynthError.soundFont("\(soundFontURL.lastPathComponent) programa \(program) banco \(bankMSB): "
                                              + error.localizedDescription)
            }
        }
        do { try engine.start() } catch { throw TabSynthError.engine("start: \(error.localizedDescription)") }
        defer { engine.stop() }
        var midiByChannel: [UInt8: AUScheduleMIDIEventBlock] = [:]
        for (channel, sampler) in samplers {
            guard let block = sampler.auAudioUnit.scheduleMIDIEventBlock else {
                throw TabSynthError.engine("el sampler no acepta eventos MIDI programados")
            }
            midiByChannel[channel] = block
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        defer { file.close() }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                            frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw TabSynthError.engine("sin búfer de render")
        }

        var done = 0
        var next = 0
        while done < totalFrames {
            try Task.checkCancellation()
            let n = min(Int(blockFrames), totalFrames - done)
            // Eventos de este bloque con su desfase de muestra respecto al inicio del bloque.
            while next < events.count, events[next].frame < done + n {
                let e = events[next]
                let offset = AUEventSampleTime(max(0, e.frame - done))
                var bytes = (e.status, e.data1, e.data2)
                if let midi = midiByChannel[e.status & 0x0F] {
                    withUnsafeBytes(of: &bytes) { raw in
                        midi(AUEventSampleTimeImmediate + offset, 0, 3, raw.bindMemory(to: UInt8.self).baseAddress!)
                    }
                }
                next += 1
            }
            let status = try engine.renderOffline(AVAudioFrameCount(n), to: buffer)
            guard status == .success, Int(buffer.frameLength) == n else {
                throw TabSynthError.engine("renderOffline: estado \(status.rawValue), \(buffer.frameLength)/\(n) frames")
            }
            try file.write(from: buffer)
            done += n
        }
    }
}
#endif
