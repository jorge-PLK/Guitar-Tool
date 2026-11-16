import Foundation

/// Partitura de la tablatura (mini-spec Fase 5, «Partitura, sonido y exportación»). Se guarda en `tab/score.json`
/// y la app la traduce a alphaTab.
///
/// Rejilla común a todas las pistas: `bars` y `beats` salen del `BeatGrid` del tema (con la extensión del principio
/// y el final). Cada pulso se mide en `ticksPerBeat` ticks; cada pista elige por pulso semicorcheas (4 puntos, uno
/// cada 3 ticks) o tresillo de corchea (3 puntos, uno cada 4 ticks). Las posiciones y duraciones son enteros de
/// ticks; los silencios no se guardan: son los huecos entre notas.
public struct TabScore: Codable, Sendable, Equatable {
    /// 12 = mcm(4, 3): semicorcheas y tresillos de corchea caen en ticks enteros.
    public static let ticksPerBeat = 12
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var bars: [TabBar]
    public var beats: [TabBeat]
    /// Final del último pulso en segundos de canción (el «pulso siguiente» del último).
    public var endTime: Double
    public var tracks: [TabTrack]

    public init(bars: [TabBar], beats: [TabBeat], endTime: Double, tracks: [TabTrack] = []) {
        formatVersion = Self.currentFormatVersion
        self.bars = bars
        self.beats = beats
        self.endTime = endTime
        self.tracks = tracks
    }

    /// Ticks totales de la rejilla (un punto final exclusivo: `beats.count * ticksPerBeat`).
    public var totalTicks: Int { beats.count * Self.ticksPerBeat }

    public func trackIndex(id: String) -> Int? { tracks.firstIndex { $0.id == id } }

    /// Sustituye la pista con el mismo `id` o la añade al final.
    public mutating func upsert(_ track: TabTrack) {
        if let i = trackIndex(id: track.id) { tracks[i] = track } else { tracks.append(track) }
    }
}

/// Un compás. `start` es exactamente el tiempo de su primer pulso (el downbeat del `BeatGrid`).
public struct TabBar: Codable, Sendable, Equatable {
    public var start: Double
    /// Índice en `TabScore.beats` de su primer pulso.
    public var firstBeat: Int
    /// Numerador del compás (pulsos); el denominador es `beatUnit`.
    public var beatCount: Int
    public var beatUnit: Int
    /// Tempo escrito en negras por minuto, siempre entero (lo que admiten alphaTab y Guitar Pro sin decimales). Solo
    /// cambia cuando el compás se aleja > 2 % del tempo real vigente o cuando el inicio escrito acumulado se separa
    /// del real más de `TabScore.maxWrittenDrift`.
    public var tempo: Double

    public init(start: Double, firstBeat: Int, beatCount: Int, beatUnit: Int = 4, tempo: Double) {
        self.start = start
        self.firstBeat = firstBeat
        self.beatCount = beatCount
        self.beatUnit = beatUnit
        self.tempo = tempo
    }
}

/// Un pulso de la rejilla común.
public struct TabBeat: Codable, Sendable, Equatable {
    public var time: Double
    public var bar: Int
    public var indexInBar: Int

    public init(time: Double, bar: Int, indexInBar: Int) {
        self.time = time
        self.bar = bar
        self.indexInBar = indexInBar
    }
}

/// Punto de la rejilla: pulso global y tick dentro de él (0..<`TabScore.ticksPerBeat`).
public struct GridPoint: Codable, Sendable, Hashable, Comparable {
    public var beat: Int
    public var tick: Int

    public init(beat: Int, tick: Int) {
        self.beat = beat
        self.tick = tick
    }

    public init(absoluteTick: Int) {
        beat = absoluteTick / TabScore.ticksPerBeat
        tick = absoluteTick % TabScore.ticksPerBeat
    }

    public var absoluteTick: Int { beat * TabScore.ticksPerBeat + tick }

    public static func < (a: GridPoint, b: GridPoint) -> Bool { a.absoluteTick < b.absoluteTick }
}

/// Subdivisión de un pulso en una pista.
public enum Subdivision: String, Codable, Sendable, CaseIterable {
    case sixteenths
    case eighthTriplets

    /// Puntos por pulso.
    public var steps: Int { self == .sixteenths ? 4 : 3 }
    /// Ticks entre puntos.
    public var tickStep: Int { TabScore.ticksPerBeat / steps }
}

public enum TabTrackKind: String, Codable, Sendable {
    case guitar, bass, drums
}

/// Piezas de batería con su nota de percusión GM (mini-spec Fase 5, «Transcripción»).
public enum DrumPiece: Int, Codable, Sendable, CaseIterable {
    case kick = 35
    case snare = 38
    case hiHat = 42
    case tom = 47
    case crash = 49
}

/// Nota de guitarra o bajo. La cuerda 1 es la más aguda, como en la tablatura y en alphaTab; el traste es
/// `pitch - tuning.strings[string - 1]` (ver `TabTrack.fret(of:)`).
public struct TabNote: Codable, Sendable, Equatable, Identifiable {
    /// Único dentro de la pista.
    public var id: Int
    public var pitch: Int
    public var string: Int
    public var start: GridPoint
    /// Duración en ticks (> 0).
    public var duration: Int
    public var amplitude: Float

    public init(id: Int, pitch: Int, string: Int, start: GridPoint, duration: Int, amplitude: Float) {
        self.id = id
        self.pitch = pitch
        self.string = string
        self.start = start
        self.duration = duration
        self.amplitude = amplitude
    }

    public var end: GridPoint { GridPoint(absoluteTick: start.absoluteTick + duration) }
}

/// Golpe de batería en un punto de la rejilla (el `DrumHit` de `Drums/` es el golpe detectado, en segundos).
public struct TabDrumHit: Codable, Sendable, Hashable {
    public var piece: DrumPiece
    public var at: GridPoint

    public init(piece: DrumPiece, at: GridPoint) {
        self.piece = piece
        self.at = at
    }
}

/// Una pista: guitarra o bajo (`notes`, `tuning`) o batería (`hits`).
public struct TabTrack: Codable, Sendable, Equatable, Identifiable {
    /// Estable entre transcripciones (p. ej. «guitar-L», «bass», «drums»); lo elige la app.
    public var id: String
    public var name: String
    public var kind: TabTrackKind
    /// nil en batería.
    public var tuning: Tuning?
    /// Huella del WAV y del modelo con que se transcribió; nil si no se conoce.
    public var source: TrackSourceFingerprint?
    /// Una por pulso de `TabScore.beats`.
    public var subdivisions: [Subdivision]
    /// Ordenadas por inicio y cuerda.
    public var notes: [TabNote]
    /// Ordenados por punto y pieza.
    public var hits: [TabDrumHit]

    public init(id: String, name: String, kind: TabTrackKind, tuning: Tuning?, source: TrackSourceFingerprint?,
                subdivisions: [Subdivision], notes: [TabNote] = [], hits: [TabDrumHit] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.tuning = tuning
        self.source = source
        self.subdivisions = subdivisions
        self.notes = notes
        self.hits = hits
    }

    /// Traste de la nota con la afinación de la pista; nil sin afinación o con cuerda fuera de rango.
    public func fret(of note: TabNote) -> Int? {
        guard let tuning, (1...tuning.strings.count).contains(note.string) else { return nil }
        return note.pitch - tuning.strings[note.string - 1]
    }

    mutating func sortContents() {
        notes.sort { ($0.start.absoluteTick, $0.string) < ($1.start.absoluteTick, $1.string) }
        hits.sort { ($0.at.absoluteTick, $0.piece.rawValue) < ($1.at.absoluteTick, $1.piece.rawValue) }
    }
}
