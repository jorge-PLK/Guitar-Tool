import Foundation
import NativePlatform

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
    /// Programa GM (base 0) de una voz sin programa propio: 53 Voice Oohs.
    static let vocalProgram: UInt8 = 53
    /// Velocidad MIDI fija de notas y golpes (la partitura no guarda dinámica).
    static let velocity: UInt8 = 100
    // Técnicas en la transcripción sonora (Fase 5b): el sampler no las conoce, se aproximan con velocidad, duración y
    // rueda de inflexión del canal (rango por defecto de ±2 semitonos; con acordes la rueda mueve todas las notas
    // que suenan en el canal, aproximación aceptada).
    /// Factor de velocidad de una nota fantasma.
    static let ghostVelocityFactor = 0.55
    /// Factor de velocidad de un acento normal y de uno fuerte.
    static let accentVelocityFactor = 1.2, heavyAccentVelocityFactor = 1.35
    /// Fracción de la duración que suena una nota con palm mute y una staccato.
    static let palmMuteLengthFactor = 0.45, staccatoLengthFactor = 0.5
    /// Duración máxima, en segundos, de una nota muerta (x).
    static let deadNoteSeconds = 0.06
    /// Semitonos por unidad de valor de un bend (4 unidades = un tono; `TabBend.quarterTonesPerTone`).
    static let semitonesPerBendUnit = 2.0 / Double(TabBend.quarterTonesPerTone)
    /// Semitonos de la rueda de inflexión a fondo de escala por defecto (GM) y tope al ampliarlo por RPN (mini-spec
    /// Fase 5c, «Sonido de los adornos»: «con tope de 12 semitonos»). El rango de una pista es el que pide su curva
    /// más amplia (bend, palanca, vibrato o slide), redondeado hacia arriba, entre los dos.
    static let pitchBendRangeSemitones = 2.0, maxPitchBendRangeSemitones = 12.0
    /// Profundidad (semitonos), frecuencia (Hz) y retraso (s) del vibrato; separación entre eventos de rueda (s).
    static let vibratoDepthSlight = 0.25, vibratoDepthWide = 0.5
    static let vibratoRateHz = 5.5, vibratoDelaySeconds = 0.2
    static let pitchBendStepSeconds = 0.012
    // Adornos (mini-spec Fase 5c, «Sonido de los adornos»). La rueda de inflexión es una por sampler (el
    // `AVAudioUnitSampler` no separa el estado por canal MIDI; `TabSynthAdornmentTests`), así que en cuanto una pista
    // tiene alguna curva cada cuerda va a su canal y cada canal a su sampler: la curva de una cuerda no mueve las otras.
    /// Tope, en segundos desde el ataque, de una nota con let ring («con tope de 4 s»).
    static let letRingMaxSeconds = 4.0
    /// Glisando de un slide legato o shift: dura la fracción final de la primera nota, sin pasar de este máximo (s).
    static let slideGlideMaxSeconds = 0.15, slideGlideFraction = 0.5
    /// Slides de entrada y salida: «glisando corto (unos 3 trastes)», como mucho `slideShortSeconds`, al empezar o al
    /// acabar la nota (y nunca más de `slideGlideFraction` de ella). Los pick slide suenan como salida.
    static let slideShortSemitones = 3.0, slideShortSeconds = 0.1
    /// Factor de velocidad de la segunda nota de un ligado (sin púa) y de la principal tras un adorno ligado.
    static let legatoVelocityFactor = 0.7
    /// Duración de cada nota de adorno, en segundos («unos 60 ms antes del pulso»).
    static let graceSeconds = 0.06
    /// Flam: el golpe de adorno va `flamSeconds` antes del principal, con su velocidad por este factor.
    static let flamSeconds = 0.03, flamVelocityFactor = 0.6
    /// Armónicos: se buscan nodos de los armónicos 2…`harmonicMaxPartial` a `harmonicFretTolerance` trastes del
    /// traste escrito (12 → +12, 7 y 19 → +19, 5 y 24 → +24, 4, 9 y 16 → +28, 3,2 → +31, 2,7 → +34, 2,4 → +36).
    static let harmonicMaxPartial = 8, harmonicFretTolerance = 0.35
    /// Distancia, en trastes, de un armónico artificial (pinch, tap…) que no la trae: la octava.
    static let defaultArtificialHarmonicFret = 12.0
    /// Canal MIDI de la batería (10 en notación GM).
    static let drumChannel: UInt8 = 9
    /// Frames por bloque de render: los eventos se colocan dentro del bloque con su desfase, así que el tamaño no
    /// afecta a la precisión, solo al número de llamadas.
    static let blockFrames: UInt32 = 4096
    /// Bancos MSB de un soundfont GM en el sampler: melódico 0x79 y percusión 0x78 (los valores de
    /// `kAUSampler_DefaultMelodicBankMSB` y `kAUSampler_DefaultPercussionBankMSB`; `TabSynthTests` lo comprueba).
    static let melodicBankMSB: UInt8 = 0x79, percussionBankMSB: UInt8 = 0x78
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
        let (program, bankMSB) = instrument(for: track)

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
            if error is CancellationError || error is TabSynthError || error is PlatformError { throw error }
            throw TabSynthError.write(error.localizedDescription)
        }
    }

    func instrument(for kind: TabTrackKind) -> (program: UInt8, bankMSB: UInt8) {
        switch kind {
        case .guitar: (guitarSound.program, Self.melodicBankMSB)
        case .bass: (Self.bassProgram, Self.melodicBankMSB)
        case .drums: (0, Self.percussionBankMSB)
        case .vocal: (Self.vocalProgram, Self.melodicBankMSB)
        }
    }

    /// Instrumento de una pista: el de su tipo y, en las voces, su programa GM (`TabTrack.program`; mini-spec Fase 5c,
    /// decisión 4) si es válido.
    func instrument(for track: TabTrack) -> (program: UInt8, bankMSB: UInt8) {
        if track.kind == .vocal, let p = track.program, (0...127).contains(p) {
            return (UInt8(p), Self.melodicBankMSB)
        }
        return instrument(for: track.kind)
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

    /// Eventos ordenados por frame (en un mismo frame: note-off, luego controladores y rueda, luego note-on; dentro de
    /// cada grupo, en el orden en que se generan), ya adelantados `delayFrames`. Lo que empieza antes del 0 del tema
    /// se omite si también ha terminado (notas) o es un golpe; lo que empieza en o después de `totalFrames`, también.
    static func events(track: TabTrack, in score: TabScore, sampleRate: Double, delayFrames: Int,
                       totalFrames: Int) -> [Event] {
        var out: [Event]
        switch track.kind {
        case .guitar, .bass, .vocal:
            out = pitchedEvents(track: track, in: score, sampleRate: sampleRate, totalFrames: totalFrames)
        case .drums:
            out = drumEvents(track: track, in: score, sampleRate: sampleRate, totalFrames: totalFrames)
        }
        for i in out.indices { out[i].frame = max(0, out[i].frame - delayFrames) }
        func rank(_ e: Event) -> Int {
            switch e.status & 0xF0 {
            case 0x80: 0
            case 0x90: 2
            default: 1
            }
        }
        return out.enumerated()
            .sorted { ($0.element.frame, rank($0.element), $0.offset) < ($1.element.frame, rank($1.element), $1.offset) }
            .map(\.element)
    }

    /// Cada golpe suena hasta el siguiente de la misma nota GM (o hasta el final). Un flam añade su golpe de adorno
    /// `flamSeconds` antes, con su nota GM y `flamVelocityFactor` de la velocidad del principal.
    static func drumEvents(track: TabTrack, in score: TabScore, sampleRate: Double, totalFrames: Int) -> [Event] {
        func frame(_ t: Double) -> Int { Int((t * sampleRate).rounded()) }
        var strikes: [(on: Int, key: UInt8, velocity: UInt8)] = []
        for hit in track.hits {
            let on = frame(score.time(of: hit.at))
            let velocity = hitVelocity(hit)
            if let g = hit.grace {
                let key = (0...127).contains(g.fret) ? UInt8(g.fret) : UInt8(hit.piece.rawValue)
                strikes.append((on - frame(flamSeconds), key,
                                UInt8(max(1, (Double(velocity) * flamVelocityFactor).rounded()))))
            }
            strikes.append((on, UInt8(hit.piece.rawValue), velocity))
        }
        var out: [Event] = []
        var sounding: Set<UInt8> = []
        for s in strikes.enumerated().sorted(by: { ($0.element.on, $0.offset) < ($1.element.on, $1.offset) })
            .map(\.element) where s.on >= 0 && s.on < totalFrames {
            if sounding.contains(s.key) {
                out.append(Event(frame: s.on, status: 0x80 | drumChannel, data1: s.key, data2: 0))
            }
            out.append(Event(frame: s.on, status: 0x90 | drumChannel, data1: s.key, data2: s.velocity))
            sounding.insert(s.key)
        }
        return out
    }

    // MARK: Guitarra y bajo

    /// Unión de una nota con la siguiente de su cuerda.
    enum Link: Equatable {
        case none
        /// Ligado: la siguiente empieza justo al acabar esta, sin púa (menos velocidad).
        case hammer
        /// Slide legato: glisando al final de esta y la siguiente sin ataque (la misma voz MIDI sigue sonando).
        case legato
        /// Slide shift: glisando al final de esta y la siguiente con ataque.
        case shift
        /// Ligadura de duración (Fase 5c, tecla L): la siguiente es su continuación a la misma altura, sin ataque (la
        /// misma voz MIDI sigue sonando hasta el final de la cadena).
        case tie
    }

    /// Una nota o nota de adorno colocada en frames, con la altura que suena (armónicos ya resueltos).
    struct Strike {
        var pitch: Int
        var string: Int
        var on: Int
        /// Fin escrito: el de la duración de la nota, o el de la casilla de una nota de adorno.
        var writtenOff: Int
        var velocity: UInt8
        var techniques: TabTechniques
        var link: Link = .none
        /// Fin del tramo let ring donde está (frame), si tiene let ring.
        var letRingEnd: Int?
        /// Fin real (lo calcula `pitchedEvents`).
        var off = 0
        /// Glisando de un slide legato o shift hacia la siguiente nota: semitonos y ventana [desde, hasta).
        var glide: (semitones: Double, from: Int, to: Int)?
        /// Slide de salida corto (semitonos al acabar), también el de un legato o shift sin nota a la que ir.
        var exit: Double?
        /// Continuación de una ligadura de duración: frame del ataque de la cadena (el tope de let ring cuenta desde
        /// ahí).
        var tieAttack: Int?
        /// Continuación de una ligadura cuyo origen tiene vibrato: frame desde el que cuenta su fase (sin salto).
        var vibratoFrom: Int?
        /// Continuación sin bend ni palanca de una ligadura que acaba doblada: semitonos que mantiene.
        var bendHold: Double?
    }

    /// Una voz MIDI (un note-on y su note-off) con los tramos de notas que suenan en ella: varias si van unidas por
    /// slide legato. `offset` de cada tramo: semitonos de su nota sobre la de la voz.
    struct Voice {
        var pitch: Int
        var string: Int
        var on: Int
        var off: Int
        var velocity: UInt8
        var pieces: [(strike: Strike, offset: Double)]
    }

    static func pitchedEvents(track: TabTrack, in score: TabScore, sampleRate: Double, totalFrames: Int) -> [Event] {
        func frame(_ t: Double) -> Int { Int((t * sampleRate).rounded()) }
        let notes = inheritingTies(track.notes.enumerated()
            .sorted { ($0.element.start.absoluteTick, $0.offset) < ($1.element.start.absoluteTick, $1.offset) }
            .map(\.element))
        let letRingEnd = letRingRunEnds(notes: notes, score: score, frame: frame)

        // 1. Notas y notas de adorno en frames, con la altura que suena.
        var strikes: [Strike] = []
        for note in notes {
            let t = note.techniques
            var on = frame(score.time(of: note.start))
            let off = frame(score.time(of: note.end))
            guard off > on else { continue }
            let pitch = soundingPitch(note, in: track)
            let velocity = noteVelocity(t)
            let graces = t.graces.filter { $0.step >= 1 }
            if let maxStep = graces.map(\.step).max() {
                let onBeat = graces.contains { $0.type != .beforeBeat }
                let slot = onBeat ? min(frame(graceSeconds), (off - on) / (maxStep + 1)) : frame(graceSeconds)
                for g in graces {
                    let string = g.string ?? note.string
                    guard let strings = track.tuning?.strings, strings.indices.contains(string - 1),
                          (0...127).contains(strings[string - 1] + g.fret) else { continue }
                    let open = strings[string - 1]
                    let start = onBeat ? on + (maxStep - g.step) * slot : on - g.step * slot
                    var gt = TabTechniques()
                    gt.dead = g.dead
                    var s = Strike(pitch: open + g.fret, string: string, on: start, writtenOff: start + slot,
                                   velocity: noteVelocity(t), techniques: gt)
                    if string == note.string {
                        if g.slide { s.link = .legato } else if g.hammerPull { s.link = .hammer }
                    }
                    strikes.append(s)
                }
                if onBeat { on += maxStep * slot }
            }
            guard (0...127).contains(pitch), off > on else { continue }
            // Voz: sin cuerdas ni canales por cuerda; todas las notas en la misma línea y canal.
            var s = Strike(pitch: pitch, string: track.kind == .vocal ? 1 : note.string, on: on, writtenOff: off, velocity: velocity, techniques: t)
            s.letRingEnd = letRingEnd[note.id]
            switch t.slideOut {
            case .legato?: s.link = .legato
            case .shift?: s.link = .shift
            default: if t.hammerPull { s.link = .hammer }
            }
            strikes.append(s)
        }

        // 2. Por cuerda: uniones, fin de cada nota y voces.
        var voices: [Voice] = []
        let byString = Dictionary(grouping: strikes.enumerated(), by: { $0.element.string })
        for string in byString.keys.sorted() {
            var line = byString[string]!.sorted { ($0.element.on, $0.offset) < ($1.element.on, $1.offset) }.map(\.element)
            for i in line.indices {
                let next = i + 1 < line.count && line[i + 1].on > line[i].on ? line[i + 1] : nil
                // Ligadura de duración: la siguiente, marcada como continuación, a la misma altura y empezando justo
                // donde acaba esta (la regla de `TabEditError.noTieOrigin`), sigue la voz sin ataque.
                if let n = next, n.techniques.tieDestination, n.pitch == line[i].pitch, n.on == line[i].writtenOff {
                    line[i].link = .tie
                    line[i + 1].tieAttack = line[i].tieAttack ?? line[i].on
                    if line[i].techniques.vibrato != nil { line[i + 1].vibratoFrom = line[i].vibratoFrom ?? line[i].on }
                    if n.techniques.bend == nil, n.techniques.whammy == nil {
                        let hold = (line[i].techniques.bend ?? line[i].techniques.whammy)
                            .flatMap { $0.points.count >= 2 ? $0.points.last : nil }
                            .map { Double($0.value) * semitonesPerBendUnit } ?? line[i].bendHold
                        if let h = hold, h != 0 { line[i + 1].bendHold = h }
                    }
                }
                // Un legato de más de lo que da la rueda suena como shift (la segunda nota, con su altura y ataque).
                if line[i].link == .legato, let n = next, abs(n.pitch - line[i].pitch) > Int(maxPitchBendRangeSemitones) {
                    line[i].link = .shift
                }
                line[i].off = endFrame(of: line[i], next: next, frame: frame)
                // El origen de una ligadura no acaba ahí: sin slide de salida.
                if line[i].link != .tie { switch line[i].techniques.slideOut {
                case .outDown?, .pickSlideDown?: line[i].exit = -slideShortSemitones
                case .outUp?, .pickSlideUp?: line[i].exit = slideShortSemitones
                default: break
                } }
                if line[i].link == .legato || line[i].link == .shift {
                    if let n = next {
                        line[i].glide = glide(line[i], toPitch: n.pitch, sampleRate: sampleRate)
                    } else {
                        line[i].exit = -slideShortSemitones
                    }
                }
            }
            var current: Voice?
            for (i, s) in line.enumerated() {
                guard s.off > s.on else { continue }
                let previous = i > 0 ? line[i - 1] : nil
                if var v = current, let p = previous, p.link == .legato || p.link == .tie, p.off == s.on {
                    v.pieces.append((s, Double(s.pitch - v.pitch)))
                    v.off = s.off
                    current = v
                } else {
                    if let v = current { voices.append(v) }
                    var velocity = s.velocity
                    if let p = previous, p.link == .hammer, p.off == s.on { velocity = scaled(velocity, legatoVelocityFactor) }
                    current = Voice(pitch: s.pitch, string: string, on: s.on, off: s.off, velocity: velocity,
                                    pieces: [(s, 0)])
                }
            }
            if let v = current { voices.append(v) }
        }

        // 3. Curvas de rueda (en semitonos) y rango de la pista.
        let step = max(1, frame(pitchBendStepSeconds))
        var curves: [[(frame: Int, semitones: Double)]] = voices.map { bendCurve($0, step: step, sampleRate: sampleRate) }
        let needed = curves.joined().map { abs($0.semitones) }.max() ?? 0
        let range = min(maxPitchBendRangeSemitones, max(pitchBendRangeSemitones, (needed - 1e-9).rounded(.up)))
        let perString = !curves.allSatisfy(\.isEmpty)
        func channel(_ string: Int) -> UInt8 {
            guard perString else { return 0 }
            let c = max(0, string - 1)
            return UInt8(min(15, c >= Int(drumChannel) ? c + 1 : c))
        }

        // 4. Una sola voz por altura y canal: si una empieza antes de que acabe otra igual, la anterior se corta ahí
        // (si no, su note-off apagaría la nueva).
        let order = voices.indices.sorted { (voices[$0].on, $0) < (voices[$1].on, $1) }
        var openByKey: [Int: Int] = [:]
        for i in order {
            let key = Int(channel(voices[i].string)) << 8 | voices[i].pitch
            if let j = openByKey[key], voices[j].off > voices[i].on {
                voices[j].off = voices[i].on
                curves[j] = curves[j].filter { $0.frame < voices[i].on }
            }
            openByKey[key] = i
        }

        // 5. Eventos.
        var out: [Event] = []
        var bentChannels: Set<UInt8> = []
        for (v, curve) in zip(voices, curves) where v.off > v.on && v.off > 0 && v.on < totalFrames {
            let ch = channel(v.string)
            if !curve.isEmpty { bentChannels.insert(ch) }
            for p in curve {
                let value = pitchBendValue(semitones: p.semitones, range: range)
                out.append(Event(frame: p.frame, status: 0xE0 | ch, data1: UInt8(value & 0x7F),
                                 data2: UInt8((value >> 7) & 0x7F)))
            }
            out.append(Event(frame: max(0, v.on), status: 0x90 | ch, data1: UInt8(v.pitch), data2: v.velocity))
            out.append(Event(frame: v.off, status: 0x80 | ch, data1: UInt8(v.pitch), data2: 0))
            if !curve.isEmpty { out.append(Event(frame: v.off, status: 0xE0 | ch, data1: 0, data2: 64)) }
        }
        // Rango de la rueda por RPN 0 en cada canal con curvas, antes de todo.
        let rpn = bentChannels.sorted().flatMap { ch in
            [(101, 0), (100, 0), (6, Int(range)), (38, 0), (101, 127), (100, 127)].map {
                Event(frame: Int.min / 2, status: 0xB0 | ch, data1: UInt8($0.0), data2: UInt8($0.1))
            }
        }
        return rpn + out
    }

    /// Fin real de una nota en su cuerda: unida a la siguiente, hasta su ataque; si no, el escrito, alargado por let
    /// ring (hasta la siguiente de la cuerda, el fin del tramo o `letRingMaxSeconds` desde el ataque, que en una
    /// cadena de ligaduras es el de su origen) o acortado por palm mute,
    /// staccato o nota muerta, y nunca más allá del ataque de la siguiente (la cuerda suena con una nota a la vez).
    /// Deja puesto el glisando de los slides.
    static func endFrame(of s: Strike, next: Strike?, frame: (Double) -> Int) -> Int {
        let t = s.techniques
        let adjacent = next.map { $0.on > s.on && $0.on <= s.writtenOff } ?? false
        var off = s.writtenOff
        if s.link != .none, adjacent, let n = next {
            off = n.on
        } else {
            if t.letRing, !t.palmMute, !t.dead {
                off = max(off, min(s.letRingEnd ?? off, (s.tieAttack ?? s.on) + frame(letRingMaxSeconds)))
            }
            func shorten(_ factor: Double) {
                off = min(off, s.on + max(1, Int(Double(s.writtenOff - s.on) * factor)))
            }
            if t.palmMute { shorten(palmMuteLengthFactor) }
            if t.staccato { shorten(staccatoLengthFactor) }
            if t.dead { off = min(off, s.on + max(1, frame(deadNoteSeconds))) }
            if let n = next, n.on > s.on { off = min(off, n.on) }
        }
        return off
    }

    /// Fin, en frames, del tramo let ring de cada nota que lo lleva: el tramo es la serie de ataques seguidos (por
    /// tiempo) con alguna nota con let ring, y acaba con el final más tardío de sus notas.
    static func letRingRunEnds(notes: [TabNote], score: TabScore, frame: (Double) -> Int) -> [Int: Int] {
        var ends: [Int: Int] = [:]
        var run: [TabNote] = []
        func close() {
            guard let last = run.map(\.end).max() else { return }
            let end = frame(score.time(of: last))
            for n in run where n.techniques.letRing { ends[n.id] = end }
            run = []
        }
        let groups = Dictionary(grouping: notes, by: { $0.start.absoluteTick })
        for tick in groups.keys.sorted() {
            let group = groups[tick]!
            if group.contains(where: { $0.techniques.letRing }) { run += group } else { close() }
        }
        close()
        return ends
    }

    /// Ligaduras de duración (Fase 5c, tecla L): cada continuación (`tieDestination`) hereda de su origen (la nota de
    /// la misma cuerda y altura que acaba donde empieza ella) lo que sigue sonando: let ring, palm mute, vibrato y
    /// armónico; así la cadena suena con ellos hasta su final. `notes` en orden de inicio.
    static func inheritingTies(_ notes: [TabNote]) -> [TabNote] {
        var out = notes
        var endingAt: [[Int]: Int] = [:]   // [cuerda, altura, tick final] → índice en `out`
        for i in out.indices {
            let n = out[i]
            if n.techniques.tieDestination, let o = endingAt[[n.string, n.pitch, n.start.absoluteTick]] {
                let origin = out[o].techniques
                out[i].techniques.letRing = n.techniques.letRing || origin.letRing
                out[i].techniques.palmMute = n.techniques.palmMute || origin.palmMute
                out[i].techniques.vibrato = n.techniques.vibrato ?? origin.vibrato
                out[i].techniques.harmonic = n.techniques.harmonic ?? origin.harmonic
            }
            endingAt[[n.string, n.pitch, n.end.absoluteTick]] = i
        }
        return out
    }

    /// Altura que suena: la pisada o la del armónico. Natural: la cuerda al aire más los semitonos del nodo tocado
    /// (`harmonic.fret`, o el traste de la nota); artificial, pinch, tap, semi y feedback: la pisada más los del nodo a
    /// `harmonic.fret` trastes de ella (como alphaTab). Si no cae en un nodo, la pisada.
    ///
    /// Suenan con el programa de la pista, no con el 31 (Guitar Harmonics) de GM: el render es de un solo programa,
    /// los armónicos de los temas de prueba están en guitarras distorsionadas (un armónico con distorsión suena a nota
    /// aguda distorsionada, no a la campana limpia del 31), y así comparten canal con la cuerda y les llegan el
    /// vibrato, los bends y los slides.
    static func soundingPitch(_ note: TabNote, in track: TabTrack) -> Int {
        guard let h = note.techniques.harmonic else { return note.pitch }
        if h.type == .natural {
            guard let fret = track.fret(of: note) else { return note.pitch }
            let up = harmonicSemitones(fret: h.fret ?? Double(fret))
            return up > 0 ? note.pitch - fret + up : note.pitch
        }
        return note.pitch + harmonicSemitones(fret: h.fret ?? defaultArtificialHarmonicFret)
    }

    /// Semitonos sobre la cuerda (al aire o pisada) del armónico que suena tocando a `fret` trastes: si cae a
    /// `harmonicFretTolerance` de un nodo k/n de la cuerda, suena el armónico n, 12·log2(n) por encima (el del nodo
    /// más cercano; a igual distancia, el n más bajo); si no, 0.
    static func harmonicSemitones(fret: Double) -> Int {
        guard fret > 0 else { return 0 }
        var best: (distance: Double, n: Int)?
        for n in 2...harmonicMaxPartial {
            for k in 1..<n {
                let d = abs(-12 * log2(1 - Double(k) / Double(n)) - fret)
                if d <= harmonicFretTolerance, d < (best?.distance ?? .infinity) - 1e-9 { best = (d, n) }
            }
        }
        return best.map { Int((12 * log2(Double($0.n))).rounded()) } ?? 0
    }

    /// Puntos de rueda (semitonos sobre la nota de la voz) cada `step` frames entre el ataque y el fin de la voz, más
    /// uno al empezar cada tramo; vacío si la voz no se mueve de su nota.
    static func bendCurve(_ v: Voice, step: Int, sampleRate: Double) -> [(frame: Int, semitones: Double)] {
        func moves(_ s: Strike) -> Bool {
            let t = s.techniques
            return t.bend != nil || t.whammy != nil || t.vibrato != nil || t.slideIn != nil || s.glide != nil
                || s.exit != nil || s.bendHold != nil
        }
        guard v.pieces.contains(where: { $0.offset != 0 || moves($0.strike) }) else { return [] }
        var out: [(frame: Int, semitones: Double)] = []
        for (i, p) in v.pieces.enumerated() {
            let end = i + 1 < v.pieces.count ? v.pieces[i + 1].strike.on : v.off
            var marks = Array(stride(from: p.strike.on, to: end, by: step))
            // Último frame de la ventana del glisando: llega exacto a la altura de destino.
            if let g = p.strike.glide, g.to - 1 > p.strike.on, g.to - 1 < end { marks.append(g.to - 1) }
            // Y el último del slide de salida, en su desvío entero.
            if p.strike.exit != nil, p.strike.off - 1 > p.strike.on, p.strike.off - 1 < end {
                marks.append(p.strike.off - 1)
            }
            for f in Set(marks).sorted() {
                out.append((f, p.offset + strikeSemitones(p.strike, at: f, sampleRate: sampleRate)))
            }
        }
        return out
    }

    /// Glisando de un slide legato o shift hacia `pitch`: la diferencia de alturas (con tope del rango de la rueda) en
    /// la fracción final de la nota, que llega entera al último frame que suena.
    static func glide(_ s: Strike, toPitch pitch: Int, sampleRate: Double) -> (semitones: Double, from: Int, to: Int)? {
        guard pitch != s.pitch, s.off > s.on + 1 else { return nil }
        let length = min(slideGlideMaxSeconds * sampleRate, slideGlideFraction * Double(s.off - s.on))
        let semitones = max(-maxPitchBendRangeSemitones, min(maxPitchBendRangeSemitones, Double(pitch - s.pitch)))
        return (semitones, s.off - max(1, Int(length.rounded())), s.off)
    }

    /// Semitonos de una nota sobre su altura en el frame `f`: bend o palanca, vibrato, slide de entrada, glisando hacia
    /// la siguiente y slide de salida; en la continuación de una ligadura, el bend que mantiene.
    static func strikeSemitones(_ s: Strike, at f: Int, sampleRate: Double) -> Double {
        let t = s.techniques
        var v = techniqueSemitones(t, at: f, on: s.on, off: s.writtenOff, vibratoFrom: s.vibratoFrom,
                                   sampleRate: sampleRate) + (s.bendHold ?? 0)
        let short = max(1, min(slideShortSeconds * sampleRate, slideGlideFraction * Double(s.off - s.on)))
        if let into = t.slideIn {
            let x = Double(f - s.on) / short
            if x < 1 { v += (into == .intoFromBelow ? -1 : 1) * slideShortSemitones * (1 - x) }
        }
        if let g = s.glide, f >= g.from {
            v += g.semitones * min(1, Double(f - g.from) / Double(max(1, g.to - 1 - g.from)))
        }
        if let exit = s.exit {
            let from = Double(s.off - 1) - short
            if Double(f) > from { v += exit * min(1, (Double(f) - from) / short) }
        }
        return v
    }

    static func scaled(_ factor: Double) -> UInt8 { UInt8(max(1, min(127, (Double(velocity) * factor).rounded()))) }

    static func scaled(_ v: UInt8, _ factor: Double) -> UInt8 { UInt8(max(1, min(127, (Double(v) * factor).rounded()))) }

    static func noteVelocity(_ t: TabTechniques) -> UInt8 { attackVelocity(ghost: t.ghost, accent: t.accent) }

    static func hitVelocity(_ h: TabDrumHit) -> UInt8 { attackVelocity(ghost: h.ghost, accent: h.accent) }

    static func attackVelocity(ghost: Bool, accent: TabAccent?) -> UInt8 {
        if ghost { return scaled(ghostVelocityFactor) }
        switch accent {
        case .normal?: return scaled(accentVelocityFactor)
        case .heavy?: return scaled(heavyAccentVelocityFactor)
        default: return velocity
        }
    }

    /// Valor de la rueda de inflexión (14 bits, 8192 = centro) para `semitones` de desvío con la rueda a fondo de
    /// escala en `range` semitonos.
    static func pitchBendValue(semitones: Double, range: Double = pitchBendRangeSemitones) -> Int {
        8192 + Int((max(-1, min(1, semitones / range)) * 8191).rounded())
    }

    /// Semitonos de bend o palanca (curva sobre [`on`, `off`]) más vibrato (su tiempo cuenta desde `vibratoFrom`, o
    /// desde `on`) en el frame `f`.
    static func techniqueSemitones(_ t: TabTechniques, at f: Int, on: Int, off: Int, vibratoFrom: Int? = nil,
                                   sampleRate: Double) -> Double {
        var v = 0.0
        if let c = t.bend ?? t.whammy, c.points.count >= 2 {
            let pos = Double(f - on) / Double(max(1, off - on)) * Double(TabBend.maxPosition)
            let pts = c.points
            if pos <= Double(pts[0].position) {
                v = Double(pts[0].value)
            } else if pos >= Double(pts[pts.count - 1].position) {
                v = Double(pts[pts.count - 1].value)
            } else {
                for (a, b) in zip(pts, pts.dropFirst()) where pos >= Double(a.position) && pos <= Double(b.position) {
                    let span = Double(max(1, b.position - a.position))
                    v = Double(a.value) + (pos - Double(a.position)) / span * Double(b.value - a.value)
                    break
                }
            }
            v *= semitonesPerBendUnit
        }
        if let vib = t.vibrato {
            let secs = Double(f - (vibratoFrom ?? on)) / sampleRate
            if secs > vibratoDelaySeconds {
                let depth = vib == .wide ? vibratoDepthWide : vibratoDepthSlight
                v += depth * sin(2 * .pi * vibratoRateHz * (secs - vibratoDelaySeconds))
            }
        }
        return v
    }

    /// Curva de bend, palanca y vibrato de una nota sola como eventos de rueda (canal 0, rango GM por defecto);
    /// vuelve al centro al terminar.
    static func pitchBendEvents(_ t: TabTechniques, on: Int, off: Int, sampleRate: Double,
                                delayFrames: Int) -> [Event] {
        guard t.bend != nil || t.whammy != nil || t.vibrato != nil else { return [] }
        let step = max(1, Int(pitchBendStepSeconds * sampleRate))
        var out: [Event] = []
        var f = on
        while f < off {
            let value = pitchBendValue(semitones: techniqueSemitones(t, at: f, on: on, off: off, sampleRate: sampleRate))
            out.append(Event(frame: max(0, f) - delayFrames, status: 0xE0, data1: UInt8(value & 0x7F),
                             data2: UInt8((value >> 7) & 0x7F)))
            f += step
        }
        out.append(Event(frame: max(0, off - 1) - delayFrames, status: 0xE0, data1: 0, data2: 64))
        return out
    }

    // MARK: Render

    /// El sintetizador: `AVAudioUnitSampler` en el Mac; TinySoundFont en Windows (paso 7, parte 7.4).
    #if canImport(AVFoundation)
    static let synth: any TabSynthBackend = SamplerTabSynth()
    #else
    static let synth: any TabSynthBackend = TinySoundFontTabSynth()
    #endif

    static func renderFile(events: [Event], totalFrames: Int, sampleRate: Double, soundFontURL: URL,
                           program: UInt8, bankMSB: UInt8, to url: URL) throws {
        try synth.renderFile(events: events, totalFrames: totalFrames, sampleRate: sampleRate,
                             soundFontURL: soundFontURL, program: program, bankMSB: bankMSB, to: url)
    }
}

/// Lo que depende del sintetizador: eventos MIDI con su frame (ordenados) → WAV estéreo float32 de `totalFrames`
/// frames a `sampleRate`, con cada evento en su muestra exacta, un sampler por canal MIDI y el instrumento
/// (`program`, `bankMSB`) del soundfont en todos. Cancelable con `Task.checkCancellation()` entre bloques.
protocol TabSynthBackend: Sendable {
    func renderFile(events: [TabSynthRenderer.Event], totalFrames: Int, sampleRate: Double, soundFontURL: URL,
                    program: UInt8, bankMSB: UInt8, to url: URL) throws
}
