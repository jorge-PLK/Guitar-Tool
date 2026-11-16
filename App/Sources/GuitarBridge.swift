import Foundation
import ModelKit
import StemKit
import Store

// Puente de la Fase 4 entre Store y StemKit. `GuitarSoloSpan` existe en los dos módulos: aquí se cualifica.

/// Separador Core ML de StemKit (Mel-Band RoFormer «Lead_Rhythm_Guitar»), instalado desde el zip embebido
/// la primera vez que hace falta. Es el único sitio que lo construye.
func makeLeadSeparator(modelStore: ModelStore) async throws -> any LeadGuitarSeparating {
    let url = try await modelStore.ensureInstalled(ModelCatalog.leadRhythmMelRoformer.id) { _ in }
    return CoreMLLeadSeparator(compiledModelURL: url)
}

/// Adaptador `GuitarSplitting` sobre `GuitarStemComposer` (mini-spec Fase 4, «Opciones de guitarras y tramos de solo»),
/// fuera del hilo principal.
struct AppGuitarSplitter: GuitarSplitting {
    let modelStore: ModelStore
    /// Sustituye al separador Core ML; inyectable para tests y demos.
    var separatorFactory: (@Sendable () async throws -> (any LeadGuitarSeparating)?)? = nil

    struct LeadModelUnavailable: LocalizedError {
        var detail: String?
        var errorDescription: String? {
            detail.map { "Modelo de solista no disponible: \($0)" } ?? "Modelo de solista no disponible"
        }
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
                    separator = try await makeLeadSeparator(modelStore: modelStore)
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
