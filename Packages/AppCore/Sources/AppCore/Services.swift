import AudioKit
import Foundation
import ModelKit
import StemKit
import Store
import StudyKit

// Servicios portátiles de la cola (8.3a): copia adaptada de `App/Sources/Adapters.swift` (Mac) sin AppKit.
// Library (Store) recibe estos protocolos; los tests inyectan simulados con `JobServices`.

/// Conjunto de servicios que necesita `Library`.
struct JobServices: Sendable {
    var importer: any AudioImporting
    var separator: any StemSeparating
    var levelMeter: (any StemLevelMeasuring)?
    var analyzer: (any StudyAnalyzing)?
    /// Pistas de guitarra (L/R/solo): solo se usa si el tema lo pide (`GuitarOptions.needsProcessing`).
    var guitarSplitter: (any GuitarSplitting)?

    /// Servicios reales. `supportDir`: carpeta de soporte (`Models/` va dentro); sin ella, la del sistema.
    static func production(supportDir: URL?, environment: [String: String] = ProcessInfo.processInfo.environment) -> JobServices {
        let store = ModelStore(root: supportDir.map { $0.appendingPathComponent("Models", isDirectory: true) } ?? ModelStore.defaultRoot,
                               bundleResourceDirectory: Bundle.main.resourceURL)
        let resolver = ModelResolver(store: store, environment: environment)
        return JobServices(
            importer: PortableAudioImporter(),
            separator: PortableStemSeparator(models: resolver, helperURL: HelperLocator.separateHelper(environment: environment)),
            levelMeter: PortableStemLevelMeter(),
            analyzer: PortableStudyAnalyzer(models: resolver),
            guitarSplitter: PortableGuitarSplitter(models: resolver))
    }
}

/// Dónde está `tf-separate`: `TF_SEPARATE` si existe, si no junto al ejecutable de la app.
enum HelperLocator {
    static let environmentKey = "TF_SEPARATE"

    static var helperFileName: String {
        #if os(Windows)
        "tf-separate.exe"
        #else
        "tf-separate"
        #endif
    }

    static func separateHelper(environment: [String: String], executableDirectory: URL? = nil) -> URL? {
        if let p = environment[environmentKey], !p.isEmpty, isHelper(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        let dir = executableDirectory ?? Bundle.main.executableURL?.deletingLastPathComponent()
        if let candidate = dir?.appendingPathComponent(helperFileName), isHelper(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    /// Windows no tiene bit de ejecución: `isExecutableFile` de Foundation allí no es fiable, así que basta con que sea un
    /// fichero (el nombre ya lleva `.exe`). En el resto, ejecutable de verdad.
    static func isHelper(atPath path: String) -> Bool {
        let fm = FileManager.default
        #if os(Windows)
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
        #else
        return fm.isExecutableFile(atPath: path)
        #endif
    }
}

/// Modelo de un tema: carpeta de desarrollo `TF_MODELS_DIR` (solo Windows; mismas carpetas que
/// `OnnxDevelopmentModels`: `<dir>\<carpeta>\model.onnx`) o `ModelStore`.
struct ModelResolver: Sendable {
    let store: ModelStore
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory

    static let environmentKey = "TF_MODELS_DIR"

    /// `<TF_MODELS_DIR>/<folder>/model.onnx` si la variable está puesta y el fichero existe.
    static func developmentModel(folder: String, environment: [String: String]) -> URL? {
        guard let dir = environment[environmentKey], !dir.isEmpty else { return nil }
        let url = URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent("model.onnx")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Carpeta de desarrollo del separador: siempre T=345. T575 sigue con GLU en Split, roto en DirectML; vuelve cuando
    /// se reescriba y se publique en models-win-v1 (con `separationLargeChunkMemory`).
    static func separatorFolders(physicalMemory: UInt64) -> [String] {
        ["bs_roformer"]
    }

    /// `lead_rhythm`: misma carpeta que `LeadSeparatorHeavyTests` y que la salida de tf-ml (parte 7.3).
    private static let folders = [ModelCatalog.beatsBeatThis.id: "beat_this", ModelCatalog.chordsBTC.id: "btc",
                                  ModelCatalog.transcriptionBasicPitch.id: "basic_pitch", ModelCatalog.drumsADTOF.id: "adtof",
                                  ModelCatalog.leadRhythmMelRoformer.id: "lead_rhythm"]

    /// Carpetas de desarrollo de un modelo, en orden de preferencia (vacío: solo `ModelStore`).
    static func developmentFolders(for id: String, physicalMemory: UInt64) -> [String] {
        id == ModelCatalog.separatorBSRoformerSW.id
            ? separatorFolders(physicalMemory: physicalMemory) : folders[id].map { [$0] } ?? []
    }

    func resolve(_ id: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        #if os(Windows)
        for f in Self.developmentFolders(for: id, physicalMemory: physicalMemory) {
            if let url = Self.developmentModel(folder: f, environment: environment) { return url }
        }
        #endif
        do {
            return try await store.ensureInstalled(id, progress: progress)
        } catch {
            // Mejora 1: el error nombra el modelo (en el Mac la descarga es HuggingFace/zip; mismo envoltorio).
            throw ModelUnavailableError.wrapping(error, modelID: id)
        }
    }

    func isInstalled(_ id: String) async -> Bool {
        if case .installed = await store.state(id) { return true }
        #if os(Windows)
        return Self.developmentFolders(for: id, physicalMemory: physicalMemory)
            .contains { Self.developmentModel(folder: $0, environment: environment) != nil }
        #else
        return false
        #endif
    }
}

/// Adaptador `AudioImporting` sobre `AudioKit.AudioImporter`.
struct PortableAudioImporter: AudioImporting {
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

/// Error con mensaje legible (queda en `separation.error` y llega a la página).
struct SeparationFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Adaptador `StemSeparating`: asegura el modelo y lanza `tf-separate` con `SeparationRunner`.
struct PortableStemSeparator: StemSeparating {
    /// Límite de memoria del helper (plan, Fase 1: separación vigilada a 10 GB).
    static let memoryLimitBytes: UInt64 = 10_000_000_000
    /// Reparto del progreso cuando hay que preparar el modelo: 0–15 % preparación, 15–100 % separación.
    static let preparationShare = 0.15

    let models: ModelResolver
    let helperURL: URL?

    var modelIdentifier: String? {
        let d = ModelCatalog.separatorBSRoformerSW
        return "\(d.id)@\(d.version)"
    }

    func separate(input: URL, outputDirectory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let helperURL else {
            throw SeparationFailure(message: "No se encuentra el helper de separación (tf-separate) junto a la app.")
        }
        let share = await models.isInstalled(ModelCatalog.separatorBSRoformerSW.id) ? 0 : Self.preparationShare
        if share > 0 { progress(0) }
        let model = try await models.resolve(ModelCatalog.separatorBSRoformerSW.id) { p in progress(p * share) }
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

/// Adaptador `StemLevelMeasuring` (regla de «Stems vacíos»: RMS < −60 y pico < −30 dBFS).
struct PortableStemLevelMeter: StemLevelMeasuring {
    func isSilent(stem: URL) async throws -> Bool {
        try await Task.detached(priority: .utility) { try StemLevelMeter.isEmpty(url: stem) }.value
    }
}

/// Adaptador `StudyAnalyzing` sobre StudyKit: pulso sobre la mezcla, acordes sobre los stems armónicos no vacíos
/// (o la mezcla si no hay stems), tonalidad y caché con huella en `cache/analysis.json`.
struct PortableStudyAnalyzer: StudyAnalyzing {
    /// Una sola constante para el analizador y el estudio (`StudyKitBridge.algorithmVersion`, igual que
    /// `AppStudyAnalyzer` del Mac: comparten `cache/analysis.json`). Súbela allí al cambiar un algoritmo de StudyKit.
    static let algorithmVersion = StudyKitBridge.algorithmVersion
    /// Mini-spec Fase 2 §1 StudyKit: acordes sobre bass + guitar + other + piano.
    static let harmonicStems: [StemKind] = [.bass, .guitar, .other, .piano]

    let models: ModelResolver

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
        let beatModel = try await models.resolve(ModelCatalog.beatsBeatThis.id) { _ in }
        let chordModel = try await models.resolve(ModelCatalog.chordsBTC.id) { _ in }
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
