import Foundation

/// Los 6 stems del separador, en el orden de salida del modelo.
/// docs/probes/P4-modelos.md, «Contrato del modelo elegido»: bass, drums, other, vocals, guitar, piano.
public enum Stem: String, CaseIterable, Sendable {
    case bass, drums, other, vocals, guitar, piano

    /// Nombre del fichero que escribe el separador: `<stem>.wav`.
    public var fileName: String { rawValue + ".wav" }
}

/// Contrato del modelo BS-RoFormer SW publicado en Core ML (ADR-004;
/// docs/probes/P4-modelos.md, «Contrato del modelo elegido»). Semántica de referencia:
/// Probes/P4-modelos/bs_roformer_sw/sw_common.py (`stft_np`, `istft_np`, `demix_np`)
/// y compare.py (vía `coremlpub`).
enum RoformerContract {
    /// Frecuencia nativa del modelo (P4: «Audio: estéreo, 44,1 kHz»).
    static let sampleRate: Double = 44_100
    /// Frecuencias de entrada que admite el separador (frecuencia de trabajo elegible de la app).
    static let acceptedInputRates: Set<Double> = [44_100, 48_000]
    static let channels = 2

    /// STFT: n_fft 2048, hop 512, Hann periódica, center con relleno reflect, 1025 bins.
    static let nFFT = 2048
    static let hop = 512
    static let bins = nFFT / 2 + 1

    /// Tramas por trozo de la entrada `spec` `[1, 2050, 1151, 2]`.
    static let frames = 1151
    /// Trozo de 588 800 muestras = (1151 − 1) · 512.
    static let chunk = (frames - 1) * hop
    /// 2 solapes → paso de 294 400.
    static let overlaps = 2

    static let inputName = "spec"
    static let outputName = "permute_97"
    static let stemCount = Stem.allCases.count
}
