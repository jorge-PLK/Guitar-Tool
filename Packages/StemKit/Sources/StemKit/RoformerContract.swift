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

/// Lo que cambia entre modelos de máscara compleja de la familia RoFormer exportados sin STFT. Lo común
/// (44,1 kHz estéreo, n_fft 2048, Hann periódica, center reflect, layout de `spec`, bin 0 a cero) está en
/// `RoformerContract`.
struct MaskModelContract: Equatable, Sendable {
    let hop: Int
    /// Tramas de la entrada `spec` `[1, 2·bins, frames, 2]`.
    let frames: Int
    /// `num_overlap` de MSST: paso = trozo / overlaps.
    let overlaps: Int
    /// Máscaras de la salida `[1, stems, 2·bins, frames, 2]`.
    let stemCount: Int
    let inputName: String
    let outputName: String

    /// Trozo en muestras: `(frames − 1) · hop`.
    var chunk: Int { (frames - 1) * hop }

    /// BS-RoFormer SW, 6 stems (ADR-004; docs/probes/P4-modelos.md, «Contrato del modelo elegido»).
    static let bsRoformerSW = MaskModelContract(
        hop: RoformerContract.hop, frames: RoformerContract.frames, overlaps: RoformerContract.overlaps,
        stemCount: RoformerContract.stemCount, inputName: RoformerContract.inputName,
        outputName: RoformerContract.outputName)

    /// Mel-Band RoFormer «Lead_Rhythm_Guitar», 1 stem: la solista (mini-spec Fase 4, «Opciones de guitarras y tramos
    /// de solo»; contrato de tf-ml en ModelCatalog.leadRhythmMelRoformer): hop 441, 301 tramas → trozo de 132 300
    /// muestras (3 s), salida `mask`.
    /// num_overlap 2, no el 1 de la config de MSST (decisión de Jorge, Fase 4): con 1 los trozos van uno tras otro y
    /// el demix deja a 0 la muestra de cada lado de cada corte (peso 0 del fundido), con saltos medidos de 0,262 en
    /// Platero y bordes duros cada 3 s. Con 2 cada corte cae en mitad del trozo vecino y se funde. Cuesta el doble.
    static let leadRhythm = MaskModelContract(
        hop: 441, frames: 301, overlaps: 2, stemCount: 1, inputName: "spec", outputName: "mask")

    /// El mismo modelo con num_overlap 1, como el demix de MSST con que tf-ml generó la referencia PyTorch del
    /// fixture. Solo para medir paridad.
    static let leadRhythmMSST = MaskModelContract(
        hop: 441, frames: 301, overlaps: 1, stemCount: 1, inputName: "spec", outputName: "mask")
}
