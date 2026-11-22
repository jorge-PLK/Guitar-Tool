import Foundation
import ModelKit
import StemKit
import Store

/// Adaptador `GuitarSplitting` portátil sobre `GuitarStemComposer` (mini-spec Fase 4, «Opciones de guitarras y tramos
/// de solo»): copia de `AppGuitarSplitter` (`App/Sources/GuitarBridge.swift`, Mac) con el modelo de solista resuelto
/// por `ModelResolver`. Mac: el `.mlmodelc` que instala ModelStore desde el zip embebido. Windows (ADR-020): el `.onnx`
/// de `<TF_MODELS_DIR>\lead_rhythm\model.onnx` si está, si no el que descarga ModelStore de `models-win-v1`.
/// Sin tramos de solo no hace falta modelo (solo L/R).
struct PortableGuitarSplitter: GuitarSplitting {
    let models: ModelResolver
    /// Sustituye al separador del modelo; inyectable para tests.
    var separatorFactory: (@Sendable () async throws -> (any LeadGuitarSeparating)?)? = nil

    /// Mismo error y mismo texto que el Mac: la cola lo deja en `guitarSplitFailed` y llega a la página.
    struct LeadModelUnavailable: LocalizedError {
        var detail: String?
        var errorDescription: String? {
            detail.map { "Modelo de solista no disponible: \($0)" } ?? "Modelo de solista no disponible"
        }
    }

    /// Asegura el modelo (instalación o descarga) y construye el separador; no lo carga todavía.
    static func makeLeadSeparator(models: ModelResolver) async throws -> any LeadGuitarSeparating {
        let url = try await models.resolve(ModelCatalog.leadRhythmMelRoformer.id) { _ in }
        return RoformerLeadSeparator(compiledModelURL: url)
    }

    func split(projectFolder: URL, input: URL, outputDirectory: URL, options: GuitarOptions,
               progress: @escaping @Sendable (Double) -> Void) async throws -> GuitarSplitResult {
        let spans = options.soloSpans.map { StemKit.GuitarSoloSpan(start: $0.start, end: $0.end) }
        var separator: (any LeadGuitarSeparating)?
        if !spans.isEmpty {
            do {
                if let factory = separatorFactory {
                    separator = try await factory()
                } else {
                    separator = try await Self.makeLeadSeparator(models: models)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw LeadModelUnavailable(detail: error.localizedDescription)
            }
            if separator == nil { throw LeadModelUnavailable() }
        }
        progress(0)
        let tracks = try await Task.detached(priority: .utility) {
            try GuitarStemComposer().compose(input: input, outputDirectory: outputDirectory,
                                             stereo: options.stereoSplit, soloSpans: spans,
                                             separator: separator, progress: progress)
        }.value
        try Task.checkCancellation()
        progress(1)
        return GuitarSplitResult(tracks: tracks.compactMap { t in
            GuitarRole(rawValue: t.role.rawValue).map { SeparatedGuitar(role: $0, file: t.url.lastPathComponent) }
        })
    }
}
