import AudioKit
import Foundation
import ModelKit
import StemKit
import Store

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
