import AudioKit
import Foundation
import ModelKit
import StemKit
import Store
import StudyKit

/// Adaptador `AudioImporting` sobre `AudioKit.AudioImporter`.
struct AppAudioImporter: AudioImporting {
    private let importer = AudioImporter()

    func importAudio(from source: URL, to destination: URL, sampleRate: Double,
                     progress: @escaping @Sendable (Double) -> Void) async throws -> ImportedAudioInfo {
        let r = try await importer.importAudio(from: source, to: destination, sampleRate: sampleRate, progress: progress)
        return ImportedAudioInfo(title: r.title, artist: r.artist, duration: r.duration, sourceFormat: r.sourceFormat,
                                 sourceSampleRate: r.sourceSampleRate, sourceChannels: r.sourceChannels)
    }

    func resample(_ file: URL, to destination: URL, sampleRate: Double) async throws {
        try await importer.resample(file, to: destination, sampleRate: sampleRate)
    }
}

/// Error con mensaje legible para el tooltip del chip y las alertas.
struct SeparationFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Adaptador `StemSeparating`: asegura el modelo (descarga la primera vez) y lanza `tf-separate` con `SeparationRunner`.
struct AppStemSeparator: StemSeparating {
    static let modelID = ModelCatalog.separatorBSRoformerSW.id
    /// Límite de memoria del helper (plan, Fase 1: separación vigilada a 10 GB).
    static let memoryLimitBytes: UInt64 = 10_000_000_000
    /// Reparto del progreso cuando hay que descargar/preparar el modelo: 0–15 % preparación, 15–100 % separación.
    static let preparationShare = 0.15

    let modelStore: ModelStore
    let helperURL: URL?

    var modelIdentifier: String? {
        let d = ModelCatalog.separatorBSRoformerSW
        return "\(d.id)@\(d.version)"
    }

    func separate(input: URL, outputDirectory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let helperURL else {
            throw SeparationFailure(message: "No se encuentra el helper de separación (tf-separate) en la app.")
        }
        var wasInstalled = false
        if case .installed = await modelStore.state(Self.modelID) { wasInstalled = true }
        let share = wasInstalled ? 0 : Self.preparationShare
        if !wasInstalled { progress(0) }
        let model = try await modelStore.ensureInstalled(Self.modelID) { p in progress(p * share) }
        try Task.checkCancellation()
        progress(share)

        let runner = SeparationRunner(helperURL: helperURL, memoryLimitBytes: Self.memoryLimitBytes)
        do {
            for try await event in runner.run(model: model, input: input, outputDirectory: outputDirectory) {
                if case .progress(let f) = event { progress(share + (1 - share) * min(max(f, 0), 1)) }
            }
        } catch let e as SeparationError {
            throw Self.translate(e, limit: Self.memoryLimitBytes)
        }
        try Task.checkCancellation()
    }

    static func translate(_ e: SeparationError, limit: UInt64) -> Error {
        switch e {
        case .memoryLimitExceeded:
            let gb = Double(limit) / 1_000_000_000
            return SeparationFailure(message: "La separación superó el límite de memoria (\(String(format: "%g", gb)) GB).")
        case .helperFailed(let code, let tail):
            let t = tail.trimmingCharacters(in: .whitespacesAndNewlines)
            return SeparationFailure(message: "El helper de separación falló (código \(code))." + (t.isEmpty ? "" : " " + t))
        case .cancelled: return CancellationError()
        case .invalidInput(let m): return SeparationFailure(message: "Entrada no válida: \(m)")
        }
    }
}

/// Adaptador `StemLevelMeasuring` sobre `StemLevelMeter` (regla de «Stems vacíos»: RMS < −60 y pico < −40 dBFS).
struct AppStemLevelMeter: StemLevelMeasuring {
    func isSilent(stem: URL) async throws -> Bool {
        try await Task.detached(priority: .utility) { try StemLevelMeter.isEmpty(url: stem) }.value
    }
}

/// Adaptador `StudyAnalyzing` sobre StudyKit: pulso sobre la mezcla, acordes sobre los stems armónicos no vacíos
/// (o la mezcla si no hay stems), tonalidad y caché con huella en `cache/analysis.json`.
struct AppStudyAnalyzer: StudyAnalyzing {
    /// Súbela al cambiar cualquier algoritmo de StudyKit que altere el resultado: invalida las cachés.
    static let algorithmVersion = 1
    /// Mini-spec Fase 2 §1 StudyKit: acordes sobre bass + guitar + other + piano.
    static let harmonicStems: [StemKind] = [.bass, .guitar, .other, .piano]

    let modelStore: ModelStore

    struct MissingSeparation: LocalizedError {
        var errorDescription: String? { "El tema no tiene una separación terminada." }
    }

    static func fingerprint(for project: Project) -> AnalysisFingerprint? {
        guard let finished = project.separation.finishedAt else { return nil }
        let beat = ModelCatalog.beatsBeatThis, chord = ModelCatalog.chordsBTC
        return AnalysisFingerprint(
            beatModelID: beat.id, beatModelVersion: beat.version,
            chordModelID: chord.id, chordModelVersion: chord.version,
            algorithmVersion: algorithmVersion,
            separationModel: project.separation.model ?? "", separationFinishedAt: finished,
            sourceSHA256: project.song.sourceSHA256)
    }

    /// El análisis guardado si existe y su huella coincide con la del proyecto; nil si falta o está desfasado.
    static func loadCached(project: Project, layout: ProjectLayout) -> StudyAnalysis? {
        guard let fp = fingerprint(for: project) else { return nil }
        return AnalysisCache.load(StudyAnalysis.self, at: layout.analysisCache, expecting: fp)
    }

    /// Stems que alimentan los acordes: los armónicos no vacíos y con fichero; si no hay, la mezcla.
    static func chordInputs(project: Project, layout: ProjectLayout) -> [URL] {
        let fm = FileManager.default
        let stems = harmonicStems.compactMap { kind -> URL? in
            guard let s = project.stems.first(where: { $0.kind == kind }), !s.isEmpty else { return nil }
            let url = layout.stemURL(kind)
            return fm.fileExists(atPath: url.path) ? url : nil
        }
        return stems.isEmpty ? [layout.audioFile] : stems
    }

    func isCurrent(project: Project, layout: ProjectLayout) async -> Bool {
        Self.loadCached(project: project, layout: layout) != nil
    }

    func analyze(project: Project, layout: ProjectLayout) async throws {
        guard let fingerprint = Self.fingerprint(for: project) else { throw MissingSeparation() }
        let beatModel = try await modelStore.ensureInstalled(ModelCatalog.beatsBeatThis.id) { _ in }
        let chordModel = try await modelStore.ensureInstalled(ModelCatalog.chordsBTC.id) { _ in }
        try Task.checkCancellation()
        let beats = try await BeatAnalyzer(modelURL: beatModel).analyze(mix: layout.audioFile)
        try Task.checkCancellation()
        let chords = try await ChordRecognizer(modelURL: chordModel)
            .analyze(stems: Self.chordInputs(project: project, layout: layout))
        let key = KeyDetector.detect(chroma: chords.chroma, segments: chords.segments)
        try AnalysisCache.save(StudyAnalysis(beats: beats, chords: chords, key: key),
                               fingerprint: fingerprint, to: layout.analysisCache)
    }
}
