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

    /// Clics de la rejilla como pares, para que el controlador los convierta a `AudioKit.Click`.
    static func clicks(beats: [Double], downbeats: [Double], in range: ClosedRange<Double>) -> [(time: Double, accent: Bool)] {
        guard beats.count >= 2 else { return [] }
        return BeatGrid(beats: beats, downbeats: downbeats).clicks(in: range).map { ($0.time, $0.accent) }
    }
}
