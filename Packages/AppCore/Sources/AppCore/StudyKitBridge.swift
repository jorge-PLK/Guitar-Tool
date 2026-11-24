import Foundation
import ModelKit
import StudyKit

/// Único fichero de AppCore que nombra tipos de StudyKit: `Store` y `StudyKit` definen cada uno su `ChordOverride`
/// (y el enum `StudyKit` tapa el nombre del módulo), y `Click` existe en StudyKit y en AudioKit. Igual que
/// `App/Sources/StudyBridge.swift` en el Mac; aquí además cuelga la lectura de la caché de `AppStudyAnalyzer`.
/// Fuera de aquí solo circulan valores simples.
enum StudyKitBridge {
    /// Misma constante que `AppStudyAnalyzer.algorithmVersion` (App/Sources/Adapters.swift): si cambia allí, cambia aquí;
    /// si no, la caché del Mac aparecería como desfasada.
    static let algorithmVersion = 1

    struct Chord: Equatable, Sendable {
        var start: Double
        var end: Double
        var index: Int
    }

    /// Lo que se pinta del análisis (acordes detectados, sin correcciones).
    struct Analysis: Sendable, Equatable {
        var beats: [Double]
        var downbeats: [Double]
        var bpm: Double?
        var beatsPerBar: Int?
        var chords: [Chord]
        var key: String
        var keyConfidence: Double
    }

    /// Lo que de un proyecto entra en la huella (este fichero no importa Store).
    struct Source: Sendable {
        var separationModel: String?
        var separationFinishedAt: Date?
        var sourceSHA256: String
    }

    /// Huella de `AppStudyAnalyzer.fingerprint(for:)`.
    static func fingerprint(_ s: Source) -> AnalysisFingerprint? {
        guard let finished = s.separationFinishedAt else { return nil }
        let beat = ModelCatalog.beatsBeatThis, chord = ModelCatalog.chordsBTC
        return AnalysisFingerprint(
            beatModelID: beat.id, beatModelVersion: beat.version,
            chordModelID: chord.id, chordModelVersion: chord.version,
            algorithmVersion: algorithmVersion,
            separationModel: s.separationModel ?? "", separationFinishedAt: finished,
            sourceSHA256: s.sourceSHA256)
    }

    /// El análisis guardado si existe y su huella coincide con la del proyecto; nil si falta o está desfasado.
    static func loadCached(_ source: Source, cache: URL) -> Analysis? {
        guard let fp = fingerprint(source),
              let a = AnalysisCache.load(StudyAnalysis.self, at: cache, expecting: fp) else { return nil }
        return Analysis(beats: a.beats?.beats ?? [], downbeats: a.beats?.downbeats ?? [],
                        bpm: a.beats?.bpm, beatsPerBar: a.beats?.beatsPerBar,
                        chords: a.chords.segments.map { Chord(start: $0.start, end: $0.end, index: $0.index) },
                        key: a.key.key, keyConfidence: a.key.confidence)
    }

    /// Escribe una caché vigente (solo tests: en la app la escribe el analizador).
    static func saveCache(_ a: Analysis, source: Source, cache: URL) throws {
        guard let fp = fingerprint(source) else { return }
        let grid = a.beats.count >= 2 ? BeatGrid(beats: a.beats, downbeats: a.downbeats) : nil
        let chords = ChordAnalysis(segments: a.chords.map { ChordSegment(start: $0.start, end: $0.end, index: $0.index) },
                                   chroma: [])
        try AnalysisCache.save(StudyAnalysis(beats: grid, chords: chords,
                                             key: KeyEstimate(key: a.key, confidence: a.keyConfidence, alternative: a.key)),
                               fingerprint: fp, to: cache)
    }

    /// Acordes detectados con las correcciones del usuario encima (`ChordTimeline.effective`).
    static func effectiveChords(detected: [Chord], overrides: [(start: Double, end: Double, index: Int)]) -> [Chord] {
        ChordTimeline.effective(
            detected: detected.map { ChordSegment(start: $0.start, end: $0.end, index: $0.index) },
            overrides: overrides.map { ChordOverride(start: $0.start, end: $0.end, index: $0.index) })
            .map { Chord(start: $0.start, end: $0.end, index: $0.index) }
    }

    /// Nombre del acorde («C», «F#:7»…); «?» y «N» para desconocido y sin acorde.
    static func chordName(_ index: Int) -> String {
        guard let label = ChordLabel(index: index) else { return "?" }
        if label == .noChord { return "N" }
        if label == .unknown { return "?" }
        return label.name
    }

    /// K8: nombre del acorde ya transpuesto `transpose` semitonos (como `BackingTimeline.shown`); «?» y «N» no cambian.
    static func shownChordName(_ index: Int, transpose: Int) -> String {
        chordName(shownIndex(index, transpose: transpose))
    }

    /// Índice del acorde transpuesto `transpose` semitonos (X y N no cambian).
    static func shownIndex(_ index: Int, transpose: Int) -> Int {
        (ChordLabel(index: index) ?? .unknown).transposed(by: transpose).index
    }

    /// K7: forma del acorde mostrado (transpuesto) con capo `capo`, igual que `ChordShapes.shape(for:capo:)` en el Mac.
    /// nil para «?» y «N».
    static func shape(index: Int, transpose: Int, capo: Int) -> StudyChordShape? {
        guard let label = ChordLabel(index: index) else { return nil }
        guard let s = ChordShapes.shape(for: label.transposed(by: transpose), capo: capo) else { return nil }
        return StudyChordShape(frets: s.frets, baseFret: s.baseFret,
                               barre: s.barre.map { StudyBarre(fret: $0.fret, fromString: $0.fromString, toString: $0.toString) })
    }

    /// K8: tonalidad guardada («C:maj») vista con la transposición; nil si no es mayor ni menor.
    static func shownKey(_ stored: String?, transpose: Int) -> StudyShownKey? {
        guard let stored, let c = ChordLabel(labName: stored), let q = c.quality, q == .maj || q == .min else { return nil }
        let t = c.transposed(by: transpose)
        guard let tonic = t.labName.split(separator: ":").first else { return nil }
        return StudyShownKey(tonic: String(tonic), mode: q == .min ? "min" : "maj")
    }

    /// K8, camino inverso (`storedKeyLabel` de `chords.js`): la tonalidad que ve la interfaz -> la que se guarda.
    static func storedKey(tonic: String, mode: String, transpose: Int) -> String? {
        guard mode == "maj" || mode == "min", let c = ChordLabel(labName: "\(tonic):\(mode)") else { return nil }
        return c.transposed(by: -transpose).labName
    }

    /// Clics de la rejilla como pares, para que el controlador los convierta a `AudioKit.Click`.
    static func clicks(beats: [Double], downbeats: [Double], in range: ClosedRange<Double>) -> [(time: Double, accent: Bool)] {
        guard beats.count >= 2 else { return [] }
        return BeatGrid(beats: beats, downbeats: downbeats).clicks(in: range).map { ($0.time, $0.accent) }
    }
}
