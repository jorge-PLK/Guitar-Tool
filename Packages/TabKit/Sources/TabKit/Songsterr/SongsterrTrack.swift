import Foundation

/// Pista de Songsterr convertida a tiempo musical (mini-spec Fase 5b, «Código», parte 2). Sin tiempos reales: la
/// alineación (parte 3) coloca `bars` sobre los pulsos del `BeatGrid` y de ahí salen los puntos de `TabScore`.
///
/// Las posiciones y duraciones son enteros de `ticksPerQuarter` por negra, con las repeticiones y los finales
/// alternativos ya desplegados en el orden en que se tocan (el del audio).
public struct SongsterrTrack: Codable, Sendable, Equatable {
    /// 3360 = 2⁵·3·5·7: fusas, tresillos, cinquillos y seisillos de semicorchea y septillos caen en ticks enteros.
    public static let ticksPerQuarter = 3360

    public var name: String
    /// Instrumento de Songsterr (programa GM; 1024 = batería).
    public var instrumentId: Int?
    public var songId: Int?
    public var revisionId: Int?
    public var partId: Int?
    public var kind: TabTrackKind
    /// Alturas MIDI al aire de la cuerda 1 (la más aguda) a la última, como `Tuning.strings`. Vacío en batería.
    public var tuningStrings: [Int]
    /// Compases tocados, en orden.
    public var bars: [SongsterrBar]
    /// Cambios de tempo en orden de reproducción (el del principio incluido).
    public var tempoChanges: [SongsterrTempoChange]
    /// Guitarra o bajo; ordenadas por inicio y cuerda.
    public var notes: [SongsterrNote]
    /// Batería; ordenados por inicio y pieza, uno por pieza y punto.
    public var hits: [SongsterrHit]
    public var report: SongsterrImportReport

    /// Final del último compás en ticks.
    public var totalTicks: Int { bars.last.map { $0.start + $0.length } ?? 0 }

    /// La afinación de `TabKit` que coincide con `tuningStrings` (guitarra o bajo); nil si no es ningún preset.
    public var tuning: Tuning? {
        guard kind != .drums else { return nil }
        return TuningPreset.fixed
            .map { kind == .bass ? Tuning.bass($0) : Tuning.guitar($0) }
            .first { $0.strings == tuningStrings }
    }
}

/// Un compás tocado.
public struct SongsterrBar: Codable, Sendable, Equatable {
    /// Índice del compás en la pista de Songsterr (antes de desplegar repeticiones).
    public var sourceMeasure: Int
    /// Inicio en ticks desde el principio del tema.
    public var start: Int
    public var beatCount: Int
    public var beatUnit: Int
    /// BPM de negra vigente al empezar el compás.
    public var tempo: Double
    /// Nombre de sección de Songsterr («Intro», «Solo»…), si lo hay.
    public var marker: String?

    public var beatLength: Int { SongsterrTrack.ticksPerQuarter * 4 / beatUnit }
    public var length: Int { beatCount * beatLength }
}

public struct SongsterrTempoChange: Codable, Sendable, Equatable {
    /// Compás tocado (índice en `SongsterrTrack.bars`).
    public var bar: Int
    /// Ticks desde el inicio del compás.
    public var position: Int
    /// BPM de negra.
    public var bpm: Double
}

/// Nota de guitarra o bajo con la cuerda y el traste de Songsterr.
public struct SongsterrNote: Codable, Sendable, Equatable {
    /// Compás tocado donde empieza (índice en `SongsterrTrack.bars`).
    public var bar: Int
    /// Ticks desde el inicio del compás.
    public var position: Int
    /// Ticks desde el principio del tema (`bars[bar].start + position`).
    public var start: Int
    /// Ticks, con las ligaduras sumadas (puede pasar del compás).
    public var duration: Int
    /// 1 = la más aguda, como `TabNote.string`.
    public var string: Int
    public var fret: Int
    public var pitch: Int
    /// Técnicas de la nota y de sus ligadas (bend de las ligadas encadenado sobre la duración total). La colocación
    /// las copia tal cual a `TabNote.techniques`: los puntos del bend son relativos a la duración.
    public var techniques = TabTechniques()
}

public struct SongsterrHit: Codable, Sendable, Equatable {
    public var bar: Int
    public var position: Int
    public var start: Int
    public var piece: DrumPiece
    /// Golpe fantasma (va a `TabDrumHit.ghost`).
    public var ghost = false
    /// Flam: nota de adorno de la misma pieza justo delante (va a `TabDrumHit.grace`).
    public var grace: TabGrace?
    /// Acento (`accentuated`, va a `TabDrumHit.accent`).
    public var accent: TabAccent?
}

/// Adornos de Songsterr que `TabScore` sigue sin representar (mini-spec Fase 5b, «Errores»): la nota se importa sin
/// ellos (la nota de adorno, entera se quita) y se cuentan para el aviso.
public enum SongsterrOrnament: String, Codable, Sendable, CaseIterable {
    /// Nota de adorno sin beat con notas justo detrás en su voz (silencio, solo ligadas, final del tema): se quita.
    /// Las demás van en `TabTechniques.graces` de una nota principal (la de su cuerda o la más cercana).
    case graceNote
    /// `slide` con un valor que el conversor no conoce.
    case unknownSlide
    /// `harmonic` con un valor que el conversor no conoce.
    case unknownHarmonic
    /// `tremolo` (trémolo de púa) con una figura que no es corchea, semicorchea ni fusa.
    case unknownTremolo
    /// Técnica en un golpe de batería que no es ghost ni acento (los que `TabDrumHit` guarda).
    case drumTechnique
    /// Clave que el conversor no conoce (cuáles, en `SongsterrImportReport.unknownKeys`).
    case unknownKey
}

/// Lo que la conversión importó como técnica y lo que no pudo representar tal cual.
public struct SongsterrImportReport: Codable, Sendable, Equatable {
    /// Notas (o golpes) importados con cada técnica; una nota con dos cuenta en las dos.
    public var techniques: [TabTechniqueKind: Int] = [:]
    /// Notas (o golpes) con cada adorno sin representar; una nota con dos cuenta en los dos.
    public var ornaments: [SongsterrOrnament: Int] = [:]
    /// Notas (o golpes) con al menos un adorno sin representar, cada una una vez (la cifra del aviso).
    public var notesWithOrnaments = 0
    /// Notas (o golpes) con cada clave desconocida, «beat.x» o «note.x» (detalle de `SongsterrOrnament.unknownKey`).
    public var unknownKeys: [String: Int] = [:]
    /// Golpes de percusión GM sin pieza en `DrumPiece` (cencerro, pandereta…): se quitan.
    public var unknownDrumNotes = 0
    /// Notas con cuerda fuera de la afinación o que empiezan pasado el final del compás: se quitan.
    public var invalidNotes = 0
    /// Notas con traste fuera de `Tuning.fretRange`: se importan igual.
    public var fretsOutOfRange = 0
    /// Duraciones que no caen en ticks enteros: redondeadas.
    public var inexactDurations = 0

    public init() {}
}

public struct SongsterrFormatError: Error, Equatable, Sendable {
    public var reason: String
}
