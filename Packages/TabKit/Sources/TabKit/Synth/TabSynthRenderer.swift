import AVFoundation
import AudioToolbox

public enum TabSynthError: Error, Equatable, Sendable {
    case invalidRequest(String)
    case soundFont(String)
    case engine(String)
    case write(String)
}

/// Transcripción sintetizada de una pista (mini-spec Fase 5, «Partitura, sonido y exportación»): render fuera de
/// tiempo real con `AVAudioUnitSampler` y el soundfont GM de alphaTab a un WAV estéreo float32 que empieza en el
/// segundo 0 del tema y dura exactamente lo pedido, para entrar al reproductor de estudio como un stem más.
///
/// Las notas suenan en `TabScore.time(of:)` (el tiempo real de la rejilla, no el tempo escrito) con precisión de
/// muestra: cada evento MIDI se programa con su desfase dentro del bloque que se va a renderizar.
public struct TabSynthRenderer: Sendable {
    /// Programa GM de las guitarras.
    public enum GuitarSound: String, Sendable, CaseIterable {
        case distortion, overdrive, clean

        /// Programa GM (base 0): 30 Distortion Guitar, 29 Overdriven Guitar, 27 Electric Guitar (clean).
        var program: UInt8 {
            switch self {
            case .distortion: 30
            case .overdrive: 29
            case .clean: 27
            }
        }
    }

    /// Programa GM (base 0) del bajo: 33 Electric Bass (finger).
    static let bassProgram: UInt8 = 33
    /// Velocidad MIDI fija de notas y golpes (la partitura no guarda dinámica).
    static let velocity: UInt8 = 100
    /// Canal MIDI de la batería (10 en notación GM).
    static let drumChannel: UInt8 = 9
    /// Frames por bloque de render: los eventos se colocan dentro del bloque con su desfase, así que el tamaño no
    /// afecta a la precisión, solo al número de llamadas.
    static let blockFrames: AVAudioFrameCount = 4096
    /// Retardo fijo entre el evento MIDI y el ataque en la salida del sampler, en muestras; se compensa adelantando
    /// los eventos. Medido con `TabSynthTests.testSamplerAttackDelay` sobre las cinco piezas de batería y notas de
    /// guitarra y bajo a 44,1 y 48 kHz.
    static let samplerAttackDelayFrames = 0

    public let soundFontURL: URL
    public var guitarSound: GuitarSound

    public init(soundFontURL: URL, guitarSound: GuitarSound = .distortion) {
        self.soundFontURL = soundFontURL
        self.guitarSound = guitarSound
    }

    /// Renderiza `track` (de `score`) a `url`: WAV estéreo float32 a `sampleRate` con `round(duration · sampleRate)`
    /// frames. Escribe en un temporal junto a `url` y lo mueve al terminar; si se cancela, lanza
    /// `CancellationError` y no deja fichero.
    public func render(track: TabTrack, in score: TabScore, sampleRate: Double, duration: Double,
                       to url: URL) async throws {
        guard sampleRate > 0, duration >= 0, duration.isFinite else {
            throw TabSynthError.invalidRequest("sampleRate \(sampleRate), duration \(duration)")
        }
        let totalFrames = Int((duration * sampleRate).rounded())
        let events = Self.events(track: track, in: score, sampleRate: sampleRate,
                                 delayFrames: Self.samplerAttackDelayFrames, totalFrames: totalFrames)
        let (program, bankMSB) = instrument(for: track.kind)

        let fm = FileManager.default
        let partial = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).partial.wav")
        do {
            try Self.renderFile(events: events, totalFrames: totalFrames, sampleRate: sampleRate,
                                soundFontURL: soundFontURL, program: program, bankMSB: bankMSB, to: partial)
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            try fm.moveItem(at: partial, to: url)
        } catch {
            try? fm.removeItem(at: partial)
            if error is CancellationError || error is TabSynthError { throw error }
            throw TabSynthError.write(error.localizedDescription)
        }
    }

    func instrument(for kind: TabTrackKind) -> (program: UInt8, bankMSB: UInt8) {
        switch kind {
        case .guitar: (guitarSound.program, UInt8(kAUSampler_DefaultMelodicBankMSB))
        case .bass: (Self.bassProgram, UInt8(kAUSampler_DefaultMelodicBankMSB))
        case .drums: (0, UInt8(kAUSampler_DefaultPercussionBankMSB))
        }
    }

    // MARK: Eventos

    /// Evento MIDI de canal en un frame del WAV.
    struct Event: Equatable {
        var frame: Int
        var status: UInt8
        var data1: UInt8
        var data2: UInt8

        var isNoteOff: Bool { status & 0xF0 == 0x80 }
    }

    /// Eventos ordenados por frame (en un mismo frame, los note-off antes que los note-on), ya adelantados
    /// `delayFrames`. Lo que empieza antes del 0 del tema se omite si también ha terminado (notas) o es un golpe;
    /// lo que empieza en o después de `totalFrames`, también.
    static func events(track: TabTrack, in score: TabScore, sampleRate: Double, delayFrames: Int,
                       totalFrames: Int) -> [Event] {
        func frame(_ t: Double) -> Int { Int((t * sampleRate).rounded()) }
        var out: [Event] = []
        switch track.kind {
        case .guitar, .bass:
            // Por altura, una sola voz: si una nota empieza antes de que acabe otra de la misma altura, la anterior
            // se corta ahí (si no, su note-off apagaría la nueva).
            var spans: [(on: Int, off: Int, pitch: UInt8)] = []
            var openByPitch: [UInt8: Int] = [:]
            let notes = track.notes.sorted { $0.start.absoluteTick < $1.start.absoluteTick }
            for note in notes {
                guard (0...127).contains(note.pitch) else { continue }
                let pitch = UInt8(note.pitch)
                let on = frame(score.time(of: note.start)), off = frame(score.time(of: note.end))
                guard off > on else { continue }
                if let i = openByPitch[pitch], spans[i].off > on { spans[i].off = on }
                openByPitch[pitch] = spans.count
                spans.append((on, off, pitch))
            }
            for s in spans where s.off > s.on && s.off > 0 && s.on < totalFrames {
                out.append(Event(frame: max(0, s.on) - delayFrames, status: 0x90, data1: s.pitch, data2: velocity))
                out.append(Event(frame: s.off - delayFrames, status: 0x80, data1: s.pitch, data2: 0))
            }
        case .drums:
            // Cada golpe suena hasta el siguiente de la misma pieza (o hasta el final).
            var lastOn: [DrumPiece: Int] = [:]
            let hits = track.hits.sorted { $0.at.absoluteTick < $1.at.absoluteTick }
            for hit in hits {
                let on = frame(score.time(of: hit.at))
                guard on >= 0, on < totalFrames else { continue }
                let key = UInt8(hit.piece.rawValue)
                if lastOn[hit.piece] != nil {
                    out.append(Event(frame: on - delayFrames, status: 0x80 | drumChannel, data1: key, data2: 0))
                }
                out.append(Event(frame: on - delayFrames, status: 0x90 | drumChannel, data1: key, data2: velocity))
                lastOn[hit.piece] = on
            }
        }
        for i in out.indices where out[i].frame < 0 { out[i].frame = 0 }
        out.sort { ($0.frame, $0.isNoteOff ? 0 : 1) < ($1.frame, $1.isNoteOff ? 0 : 1) }
        return out
    }

    // MARK: Render

    static func renderFile(events: [Event], totalFrames: Int, sampleRate: Double, soundFontURL: URL,
                           program: UInt8, bankMSB: UInt8, to url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw TabSynthError.invalidRequest("formato estéreo a \(sampleRate) Hz")
        }
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: format)
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: blockFrames)
        } catch {
            throw TabSynthError.engine("modo de render manual: \(error.localizedDescription)")
        }
        do {
            try sampler.loadSoundBankInstrument(at: soundFontURL, program: program, bankMSB: bankMSB,
                                                bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        } catch {
            throw TabSynthError.soundFont("\(soundFontURL.lastPathComponent) programa \(program) banco \(bankMSB): "
                                          + error.localizedDescription)
        }
        do { try engine.start() } catch { throw TabSynthError.engine("start: \(error.localizedDescription)") }
        defer { engine.stop() }
        guard let midi = sampler.auAudioUnit.scheduleMIDIEventBlock else {
            throw TabSynthError.engine("el sampler no acepta eventos MIDI programados")
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
                withUnsafeBytes(of: &bytes) { raw in
                    midi(AUEventSampleTimeImmediate + offset, 0, 3, raw.bindMemory(to: UInt8.self).baseAddress!)
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
