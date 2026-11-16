import Foundation

/// Opciones de guitarras por proyecto y pistas resultantes (mini-spec Fase 4, «Opciones de guitarras y tramos de solo»
/// y «Datos»). Todo aditivo: sin subir `schemaVersion`; un proyecto sin estos campos es una pista y sin tramos.

/// Papel de una pista de guitarra; `rawValue` = nombre guardado. Sustituye al lado L/C/R (sin centro).
public enum GuitarRole: String, Codable, Sendable, Equatable, CaseIterable, Hashable {
    case rhythm, left, right, lead

    /// Nombre por defecto (mini-spec: «Canales»); el usuario lo edita en `Guitar.name`.
    public var defaultName: String {
        switch self {
        case .rhythm: "Guitarra rítmica"
        case .left: "Guitarra izq."
        case .right: "Guitarra der."
        case .lead: "Guitarra solista"
        }
    }

    /// Nombre del WAV en `stems/`.
    public var fileName: String {
        switch self {
        case .rhythm: "guitar_rhythm.wav"
        case .left: "guitar_L.wav"
        case .right: "guitar_R.wav"
        case .lead: "guitar_lead.wav"
        }
    }

    /// Ruta relativa a la carpeta del proyecto (`stems/guitar_L.wav`).
    public var relativePath: String { "stems/\(fileName)" }
}

/// Confianza de la separación de una pista (solo L/R la rellenan).
public enum GuitarConfidence: String, Codable, Sendable, Equatable, CaseIterable {
    case high, medium, low
}

/// Tramo de solo marcado a mano, en segundos de canción (mini-spec: «Tramos de solo»).
public struct GuitarSoloSpan: Codable, Sendable, Equatable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

/// Ajustes de guitarras guardados en `project.json` (campo `guitarOptions`): solo el interruptor L/R. Los tramos de
/// solo salen de las secciones con «Solo» (`Section.solo`), fuente única de verdad.
public struct GuitarSettings: Codable, Sendable, Equatable {
    public var stereoSplit: Bool

    public init(stereoSplit: Bool = false) { self.stereoSplit = stereoSplit }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stereoSplit = try c.decodeIfPresent(Bool.self, forKey: .stereoSplit) ?? false
    }
}

/// Opciones efectivas del paso de guitarras: `Project.guitarOptions` (interruptor + tramos derivados de las secciones
/// con «Solo»). Se pasa al separador y se guarda en `guitarApplied` como huella de lo que produjo las pistas.
public struct GuitarOptions: Codable, Sendable, Equatable {
    /// «Guitarras en L y R»: L = canal izquierdo, R = canal derecho de `stems/guitar.wav`. Por defecto falso.
    public var stereoSplit: Bool
    /// Tramos de solo (`guitar_lead.wav`); sin tramos no hay solista.
    public var soloSpans: [GuitarSoloSpan]

    public init(stereoSplit: Bool = false, soloSpans: [GuitarSoloSpan] = []) {
        self.stereoSplit = stereoSplit
        self.soloSpans = soloSpans
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stereoSplit = try c.decodeIfPresent(Bool.self, forKey: .stereoSplit) ?? false
        soloSpans = try c.decodeIfPresent([GuitarSoloSpan].self, forKey: .soloSpans) ?? []
    }

    /// Con una pista y sin tramos no hay nada que procesar (todo vale `stems/guitar.wav`).
    public var needsProcessing: Bool { stereoSplit || !soloSpans.isEmpty }

    /// Tramos válidos (fin > inicio, inicio >= 0), ordenados y con los solapados fundidos.
    public var normalized: GuitarOptions {
        let valid = soloSpans.filter { $0.end > $0.start && $0.start >= 0 }.sorted { $0.start < $1.start }
        var merged: [GuitarSoloSpan] = []
        for s in valid {
            if var last = merged.last, s.start <= last.end {
                last.end = max(last.end, s.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(s)
            }
        }
        return GuitarOptions(stereoSplit: stereoSplit, soloSpans: merged)
    }
}

/// Pista de guitarra de un proyecto, indexada por papel. `file == nil`: ahora no hay pista de ese papel, pero el
/// nombre editado se conserva por si vuelve a producirse.
public struct Guitar: Codable, Sendable, Equatable {
    public var role: GuitarRole
    public var name: String
    /// Ruta relativa de su pista (`stems/guitar_L.wav`); regenerable.
    public var file: String?
    public var confidence: GuitarConfidence?

    public init(role: GuitarRole, name: String? = nil, file: String? = nil, confidence: GuitarConfidence? = nil) {
        self.role = role
        self.name = name ?? role.defaultName
        self.file = file
        self.confidence = confidence
    }

    public var isPresent: Bool { file != nil }
}

public extension Project {
    /// Opciones efectivas: interruptor L/R guardado + tramos de las secciones con «Solo» (normalizados).
    var guitarOptions: GuitarOptions {
        GuitarOptions(stereoSplit: guitarSettings.stereoSplit,
                      soloSpans: sections.filter(\.isSolo).map { GuitarSoloSpan(start: $0.start, end: $0.end) }).normalized
    }

    /// Pistas de guitarra que existen ahora, en el orden de `GuitarRole.allCases`.
    var guitarTracks: [Guitar] {
        GuitarRole.allCases.compactMap { r in guitars.first { $0.role == r && $0.isPresent } }
    }

    /// Nombre editable de un papel (o el por defecto).
    func guitarName(_ role: GuitarRole) -> String {
        guitars.first { $0.role == role }?.name ?? role.defaultName
    }
}

/// Qué opciones y qué `stems/guitar.wav` produjeron las pistas actuales (persistido, `guitarApplied`). Si cambia
/// cualquiera de las dos cosas, se rehace el paso de guitarras.
public struct GuitarAppliedState: Codable, Sendable, Equatable {
    /// Huella de `stems/guitar.wav` al procesar (`ProjectLayout.guitarInputFingerprint`).
    public var inputFingerprint: String
    public var options: GuitarOptions
    public var finishedAt: Date

    public init(inputFingerprint: String, options: GuitarOptions, finishedAt: Date = Date()) {
        self.inputFingerprint = inputFingerprint
        self.options = options
        self.finishedAt = finishedAt
    }
}

/// Estado (no persistido) del paso de guitarras de un proyecto: `Library.guitarSplitState(id:)` y los eventos
/// `guitarSplit*`.
public enum GuitarSplitState: Sendable, Equatable {
    case pending
    case processing
    case done
    case failed(String)
}

// MARK: - Protocolo que implementa la app (Store no conoce StemKit ni TabKit)

/// Una pista producida por el paso de guitarras.
public struct SeparatedGuitar: Sendable, Equatable {
    public var role: GuitarRole
    /// Nombre del WAV escrito en `outputDirectory` (p. ej. `guitar_L.wav`); sin carpetas.
    public var file: String
    /// Solo L/R la rellenan.
    public var confidence: GuitarConfidence?

    public init(role: GuitarRole, file: String, confidence: GuitarConfidence? = nil) {
        self.role = role
        self.file = file
        self.confidence = confidence
    }
}

public struct GuitarSplitResult: Sendable, Equatable {
    public var tracks: [SeparatedGuitar]

    public init(tracks: [SeparatedGuitar]) { self.tracks = tracks }
}

/// Paso de guitarras: parte `stems/guitar.wav` según las opciones (L/R y/o tramos de solo). Lo implementa la app.
/// La cola solo lo llama si `options.needsProcessing`.
public protocol GuitarSplitting: Sendable {
    /// Escribe las pistas en `outputDirectory` (la cola las promueve a `stems/`); cancelable con la cancelación de Task.
    /// `projectFolder` es la carpeta del proyecto e `input` su `stems/guitar.wav`.
    func split(projectFolder: URL, input: URL, outputDirectory: URL, options: GuitarOptions,
               progress: @escaping @Sendable (Double) -> Void) async throws -> GuitarSplitResult
}
