import Foundation
import ModelKit
import TabKit

// Servicios de la Tablatura (8.7): transcripción y síntesis detrás de protocolos para que los tests inyecten simulados.

/// Transcripción de un stem a notas o golpes (Basic Pitch para guitarra y bajo, ADTOF para batería).
protocol TabTranscribing: Sendable {
    func pitched(url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [NoteEvent]
    func drums(url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [TranscribedDrumHit]
}

/// Pintado fuera de tiempo real de una pista a WAV (`TabSynthRenderer` en producción).
protocol TabSynthesizing: Sendable {
    func render(track: TabTrack, in score: TabScore, sampleRate: Double, duration: Double, to url: URL) async throws
}

/// Conjunto de servicios de la Tablatura; `Bridge` recibe uno simulado en los tests.
struct TabServices: Sendable {
    var transcriber: any TabTranscribing
    var synth: any TabSynthesizing
    /// Songsterr (W2-G): nil = los de producción sobre el navegador oculto del anfitrión.
    var songsterr: SongsterrServices?

    static func production(supportDir: URL?, environment: [String: String] = ProcessInfo.processInfo.environment) -> TabServices {
        let store = ModelStore(root: supportDir.map { $0.appendingPathComponent("Models", isDirectory: true) } ?? ModelStore.defaultRoot,
                               bundleResourceDirectory: Bundle.main.resourceURL)
        let resolver = ModelResolver(store: store, environment: environment)
        return TabServices(transcriber: ProductionTabTranscriber(models: resolver),
                           synth: ProductionTabSynth(environment: environment), songsterr: nil)
    }
}

struct TabFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Basic Pitch y ADTOF con el modelo resuelto por `ModelResolver` (Windows: `TF_MODELS_DIR\basic_pitch|adtof`).
final class ProductionTabTranscriber: TabTranscribing, @unchecked Sendable {
    private let models: ModelResolver
    private let lock = NSLock()
    private var pitchedModel: BasicPitchTranscriber?
    private var drumModel: DrumTranscriber?

    init(models: ModelResolver) { self.models = models }

    func pitched(url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [NoteEvent] {
        progress(0)
        let existing = lock.withLock { pitchedModel }
        let transcriber: BasicPitchTranscriber
        if let existing { transcriber = existing } else {
            let m = try await models.resolve(ModelCatalog.transcriptionBasicPitch.id) { _ in }
            transcriber = BasicPitchTranscriber(modelURL: m)
            lock.withLock { pitchedModel = transcriber }
        }
        let events = try await transcriber.transcribe(url: url)
        progress(1)
        return events
    }

    func drums(url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [TranscribedDrumHit] {
        let existing = lock.withLock { drumModel }
        let transcriber: DrumTranscriber
        if let existing { transcriber = existing } else {
            let m = try await models.resolve(ModelCatalog.drumsADTOF.id) { _ in }
            transcriber = DrumTranscriber(modelURL: m)
            lock.withLock { drumModel = transcriber }
        }
        return try await transcriber.transcribe(url: url, progress: progress)
    }
}

/// Sintetizador de producción: el soundfont se busca al renderizar (`TF_SOUNDFONT`, recursos de la app o junto al ejecutable).
struct ProductionTabSynth: TabSynthesizing {
    static let environmentKey = "TF_SOUNDFONT"
    static let relativePath = "alphaTab/soundfont/sonivox.sf2"
    var environment: [String: String]

    static func soundFont(environment: [String: String]) -> URL? {
        let fm = FileManager.default
        if let p = environment[environmentKey], !p.isEmpty, fm.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        let bases = [Bundle.main.resourceURL, Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        // En Windows alphaTab va dentro de `Web\` junto al .exe (lo sirve la página): se mira también ahí.
        let candidates = bases.flatMap { [$0.appendingPathComponent(relativePath), $0.appendingPathComponent("Web/" + relativePath)] }
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    func render(track: TabTrack, in score: TabScore, sampleRate: Double, duration: Double, to url: URL) async throws {
        guard let sf = Self.soundFont(environment: environment) else {
            throw TabFailure(message: "Falta el soundfont de la síntesis (\(Self.relativePath)).")
        }
        try await TabSynthRenderer(soundFontURL: sf).render(track: track, in: score, sampleRate: sampleRate, duration: duration, to: url)
    }
}
