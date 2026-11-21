import CTinySoundFont
import Foundation
import NativeAudioFile

/// `TabSynthBackend` de Windows (plan, «Fase 7c», paso 7, parte 7.4): render fuera de tiempo real con TinySoundFont
/// 0.9 (MIT, `CTinySoundFont` de NativeKit) y el mismo SoundFont 2 del Mac, a un WAV estéreo float32. Compila también
/// en el Mac, donde solo lo usan las pruebas que lo comparan con `SamplerTabSynth`.
///
/// Mismo contrato que el sampler: cada evento cae en su muestra exacta (se renderiza hasta su frame, se aplica y se
/// sigue) y el instrumento (`program`, `bankMSB`) va en los 16 canales. tsf guarda rueda, rango y controladores por
/// canal, así que basta una instancia (el Mac necesita un sampler por canal).
struct TinySoundFontTabSynth: TabSynthBackend {
    /// Banco SF2 donde tsf busca los presets: 0 los melódicos y 128 la percusión GM. Traducen los MSB del sampler
    /// (`TabSynthRenderer.melodicBankMSB` 0x79 y `percussionBankMSB` 0x78, convención de AudioToolbox).
    static let melodicBank: Int32 = 0, percussionBank: Int32 = 128
    /// Canales MIDI que se inicializan con el instrumento (todos los de MIDI 1.0).
    static let midiChannels: Int32 = 16
    /// Ganancia global de tsf en dB. Calibrada para que el nivel RMS de cada nota quede cerca del del sampler: con 0 dB,
    /// tsf sonaba +4,4 dB en las 8 notas de guitarra (con la fantasma y el acento) y en bombo y caja, +4,5…+5,5 en
    /// tom, crash y charles (`TabSynthEngineComparisonTests`, sonivox.sf2 a 48 kHz).
    static let outputGainDB: Float = -4.4
    /// Exponente de la curva de velocidad: tsf aplica la ganancia lineal `vel` que recibe, el sampler la curva
    /// cóncava del modulador por defecto de SF2 (≈ 40·log10(v/127) dB). Con `vel = (v/127)²` coinciden.
    static let velocityExponent: Float = 2

    func renderFile(events: [TabSynthRenderer.Event], totalFrames: Int, sampleRate: Double, soundFontURL: URL,
                    program: UInt8, bankMSB: UInt8, to url: URL) throws {
        guard let bank = Self.sf2Bank(bankMSB: bankMSB) else {
            throw TabSynthError.invalidRequest("banco MSB \(bankMSB) sin equivalente SF2")
        }
        // tsf trabaja a frecuencia entera; el WAV lleva la misma.
        guard sampleRate.rounded() == sampleRate, sampleRate >= 1, sampleRate <= Double(Int32.max) else {
            throw TabSynthError.invalidRequest("frecuencia \(sampleRate) Hz no entera")
        }
        let name = soundFontURL.lastPathComponent
        let data: Data
        do { data = try Data(contentsOf: soundFontURL) } catch {
            throw TabSynthError.soundFont("\(name): \(error.localizedDescription)")
        }
        guard Self.isSoundFont2(data), data.count <= Int(Int32.max) else {
            throw TabSynthError.soundFont("\(name): no es un SoundFont 2 (RIFF sfbk)")
        }
        guard let synth = data.withUnsafeBytes({ tsf_load_memory($0.baseAddress, Int32($0.count)) }) else {
            throw TabSynthError.soundFont("\(name): TinySoundFont no lo carga")
        }
        defer { tsf_close(synth) }
        tsf_set_output(synth, TSF_STEREO_INTERLEAVED, Int32(sampleRate), Self.outputGainDB)
        for channel in 0..<Self.midiChannels where tsf_channel_set_bank_preset(synth, channel, bank, Int32(program)) == 0 {
            throw TabSynthError.soundFont("\(name) programa \(program) banco \(bankMSB): no está en el SoundFont")
        }

        let writer: AudioFileWriter
        do {
            writer = try AudioFileWriter(url: url, sampleRate: sampleRate, channelCount: 2, format: .float32)
        } catch {
            throw TabSynthError.write(error.localizedDescription)
        }
        let blockFrames = Int(TabSynthRenderer.blockFrames)
        var interleaved = [Float](repeating: 0, count: 2 * blockFrames)
        var left = [Float](repeating: 0, count: blockFrames), right = left
        var done = 0
        var next = 0
        while done < totalFrames {
            try Task.checkCancellation()
            let n = min(blockFrames, totalFrames - done)
            interleaved.withUnsafeMutableBufferPointer { buf in
                var at = 0
                while at < n {
                    // Eventos que caen en este frame (los anteriores al 0, como el RPN, en el primero).
                    while next < events.count, events[next].frame <= done + at {
                        Self.apply(events[next], to: synth)
                        next += 1
                    }
                    let until = next < events.count ? min(n, events[next].frame - done) : n
                    tsf_render_float(synth, buf.baseAddress! + 2 * at, Int32(until - at), 0)
                    at = until
                }
            }
            for i in 0..<n {
                left[i] = interleaved[2 * i]
                right[i] = interleaved[2 * i + 1]
            }
            do {
                try left.withUnsafeBufferPointer { l in
                    try right.withUnsafeBufferPointer { r in try writer.write([l.baseAddress!, r.baseAddress!], count: n) }
                }
            } catch {
                throw TabSynthError.write(error.localizedDescription)
            }
            done += n
        }
        do { try writer.close() } catch { throw TabSynthError.write(error.localizedDescription) }
    }

    /// Banco SF2 de un MSB del sampler; `nil` si no es ninguno de los dos GM.
    static func sf2Bank(bankMSB: UInt8) -> Int32? {
        switch bankMSB {
        case TabSynthRenderer.melodicBankMSB: melodicBank
        case TabSynthRenderer.percussionBankMSB: percussionBank
        default: nil
        }
    }

    /// Cabecera RIFF de forma `sfbk` (SoundFont 2); DLS (`DLS `) u otros, no.
    static func isSoundFont2(_ data: Data) -> Bool {
        data.count >= 12 && data.prefix(4) == Data("RIFF".utf8) && data.dropFirst(8).prefix(4) == Data("sfbk".utf8)
    }

    /// Velocidad MIDI → ganancia que espera tsf (ver `velocityExponent`).
    static func gain(velocity: UInt8) -> Float {
        powf(Float(velocity) / 127, velocityExponent)
    }

    /// Aplica un evento MIDI de canal a tsf en el punto actual del render.
    static func apply(_ e: TabSynthRenderer.Event, to synth: OpaquePointer) {
        let channel = Int32(e.status & 0x0F)
        switch e.status & 0xF0 {
        case 0x90 where e.data2 > 0:
            _ = tsf_channel_note_on(synth, channel, Int32(e.data1), gain(velocity: e.data2))
        case 0x80, 0x90:
            tsf_channel_note_off(synth, channel, Int32(e.data1))
        case 0xB0:
            _ = tsf_channel_midi_control(synth, channel, Int32(e.data1), Int32(e.data2))
        case 0xE0:
            _ = tsf_channel_set_pitchwheel(synth, channel, Int32(e.data1) | Int32(e.data2) << 7)
        default:
            break
        }
    }
}
