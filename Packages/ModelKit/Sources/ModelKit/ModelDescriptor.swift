import Foundation

public enum ModelRole: String, Sendable, Equatable, Codable, CaseIterable {
    case separation, chords, beats, guitarTranscription, drumTranscription
    /// Guitarra solista frente a rítmica dentro de los tramos de solo (mini-spec de la Fase 4).
    case leadGuitarSeparation
}

public enum ModelArchiveKind: String, Sendable, Equatable, Codable {
    /// Zip descargado con un `.mlpackage`: se verifica, se descomprime y se compila.
    case zippedMLPackage
    /// Zip descargado con un `.mlmodelc` ya compilado: se verifica y se descomprime, sin compilar.
    case zippedCompiledModel
    /// Zip con un `.mlpackage` dentro del bundle de la app (el recurso se busca por `url.lastPathComponent`
    /// en el directorio inyectado en `ModelStore`): se copia, se verifica y se compila.
    case bundledZippedMLPackage
}

public struct ModelDescriptor: Sendable, Equatable, Identifiable {
    public let id: String
    public let version: String
    public let displayName: String
    public let role: ModelRole
    public let url: URL
    public let sha256: String
    public let archiveBytes: Int64
    public let archiveKind: ModelArchiveKind
    /// Nombre del `.mlpackage` dentro del zip.
    public let packageName: String
    public let license: String

    public init(id: String, version: String, displayName: String, role: ModelRole, url: URL,
                sha256: String, archiveBytes: Int64, archiveKind: ModelArchiveKind = .zippedMLPackage,
                packageName: String, license: String) {
        self.id = id
        self.version = version
        self.displayName = displayName
        self.role = role
        self.url = url
        self.sha256 = sha256
        self.archiveBytes = archiveBytes
        self.archiveKind = archiveKind
        self.packageName = packageName
        self.license = license
    }

    /// Nombre del `.mlmodelc` resultante (`packageName` sin extensión).
    public var compiledName: String {
        (packageName as NSString).deletingPathExtension + ".mlmodelc"
    }
}

public enum ModelCatalog {
    /// Separador de stems de la Fase 1. Datos del manifest de Probes/P4-modelos/bs_roformer_sw.
    public static let separatorBSRoformerSW = ModelDescriptor(
        id: "bs-roformer-sw",
        version: "gridshift-fp16",
        displayName: "Separación de stems",
        role: .separation,
        url: URL(string: "https://huggingface.co/gridshiftstudio/bs-roformer-sw-coreml/resolve/main/BSRoformerSW.mlpackage.zip")!,
        sha256: "faa91950a15ce4a4deb2692f367ec416dd6420e74cbfb490e851ded111208e7f",
        archiveBytes: 327_743_996,
        archiveKind: .zippedMLPackage,
        packageName: "BSRoformerSW.mlpackage",
        license: "Pesos de licencia desconocida: uso personal, no redistribuir")

    /// Pulso y downbeats (mini-spec Fase 2, §1 ModelKit). Se descarga en el primer análisis.
    public static let beatsBeatThis = ModelDescriptor(
        id: "beat-this",
        version: "supracut-33fe1a5",
        displayName: "Pulso y compás",
        role: .beats,
        url: URL(string: "https://huggingface.co/jessengatai/supracut-beat-this/resolve/33fe1a5a3edb44f6063d71e549d8ea774a41eaa1/BeatThis.mlmodelc.zip")!,
        sha256: "0464b7497165e82cf68e94bfd3aecf989cb88be3c6ba0ca4ae3f3657cafcd4b5",
        archiveBytes: 81_000_000,
        archiveKind: .zippedCompiledModel,
        packageName: "BeatThis.mlmodelc",
        license: "MIT")

    /// SHA-256 y tamaño de `App/Resources/Models/BTC_large_voca_fp16.mlpackage.zip`.
    static let chordsBTCSHA256 = "32a981d4d157d4bf0e0133f220e43c280bf642ee90e73e6a76b54c8c390cd0bf"
    static let chordsBTCBytes: Int64 = 5_435_958

    /// Acordes (mini-spec Fase 2, §1 ModelKit). Embebido en la app: no se redistribuye.
    public static let chordsBTC = ModelDescriptor(
        id: "btc-chords",
        version: "large-voca-fp16",
        displayName: "Acordes",
        role: .chords,
        url: URL(string: "bundle:///BTC_large_voca_fp16.mlpackage.zip")!,
        sha256: chordsBTCSHA256,
        archiveBytes: chordsBTCBytes,
        archiveKind: .bundledZippedMLPackage,
        packageName: "BTC_large_voca_fp16.mlpackage",
        license: "Pesos no comerciales, uso personal")

    /// SHA-256 y tamaño de `App/Resources/Models/BasicPitch_nmp.mlpackage.zip` (lo genera, idéntico en cada
    /// ejecución, `Probes/P4-modelos/basic_pitch/convert.py --install`).
    static let transcriptionBasicPitchSHA256 = "c2faf4ae9da4ad7acd726b92748c63e6707b21301e1291d420dda563006f0653"
    static let transcriptionBasicPitchBytes: Int64 = 116_293

    /// Transcripción de guitarra y bajo (mini-spec Fase 4): `nmp.mlpackage` oficial de spotify/basic-pitch
    /// (ICASSP 2022, commit `fa5997a`), FP32, sin convertir. Embebido en la app como BTC.
    /// Contrato: `input_2` [1, 43844, 1] a 22050 Hz → `Identity_1` note [1, 172, 88], `Identity_2` onset
    /// [1, 172, 88], `Identity` contour [1, 172, 264].
    public static let transcriptionBasicPitch = ModelDescriptor(
        id: "basic-pitch",
        version: "icassp2022-fa5997a",
        displayName: "Transcripción de notas",
        role: .guitarTranscription,
        url: URL(string: "bundle:///BasicPitch_nmp.mlpackage.zip")!,
        sha256: transcriptionBasicPitchSHA256,
        archiveBytes: transcriptionBasicPitchBytes,
        archiveKind: .bundledZippedMLPackage,
        packageName: "BasicPitch_nmp.mlpackage",
        license: "Apache-2.0")

    /// SHA-256 y tamaño de `App/Resources/Models/LeadRhythmMelRoformer_fp16.mlpackage.zip` (lo genera
    /// `Probes/P4-modelos/lead_rhythm/convert.py fp16 --install`; una nueva conversión cambia el hash).
    static let leadRhythmSHA256 = "130f33efcdd10bc4e0d5d94deebb79049ca9c57647111c85ed125d44f0ac3401"
    static let leadRhythmBytes: Int64 = 156_007_134
    /// SHA-256 del checkpoint original (`model_mel_band_roformer_ep_72_sdr_3.2232.ckpt`, HF
    /// RandomFilteredStuff/RVC_V2_Stuff, commit c3ac4e45), cargado solo con `torch.load(weights_only=True)`.
    public static let leadRhythmCheckpointSHA256 = "b3c47bca33609ca1ba0bb2d2076410bfd1eb941b051b72afc1f3e24d12b17eef"

    /// Guitarra solista frente a rítmica (mini-spec Fase 4, tramos de solo): núcleo del Mel-Band RoFormer
    /// «Lead_Rhythm_Guitar» sin STFT, convertido a Core ML FP16 (CPU+GPU). Embebido en la app como BTC.
    /// Contrato (como BS-RoFormer SW, 1 stem): `spec` [1, 2050, 301, 2] float32 (fila 2·f + canal, STFT
    /// n_fft 2048, hop 441, 44,1 kHz, trozo 132300) → `mask` [1, 1, 2050, 301, 2] float32, máscara compleja
    /// de la solista; rítmica = entrada − solista.
    public static let leadRhythmMelRoformer = ModelDescriptor(
        id: "lead-rhythm-guitar",
        version: "melroformer-ep72-c3ac4e45-fp16",
        displayName: "Guitarra solista",
        role: .leadGuitarSeparation,
        url: URL(string: "bundle:///LeadRhythmMelRoformer_fp16.mlpackage.zip")!,
        sha256: leadRhythmSHA256,
        archiveBytes: leadRhythmBytes,
        archiveKind: .bundledZippedMLPackage,
        packageName: "LeadRhythmMelRoformer_fp16.mlpackage",
        license: "openrail; pesos anónimos de HF, uso personal")

    /// SHA-256 y tamaño de `App/Resources/Models/ADTOF_FrameRNN_fp32.mlpackage.zip` (lo genera, idéntico en cada
    /// ejecución, `Probes/P4-modelos/adtof/package.py --install`; una nueva conversión cambia el hash).
    static let drumsADTOFSHA256 = "5135e35e277b60d0f7e61a411442b25f706adafaac35c13859ee6c2d26683206"
    static let drumsADTOFBytes: Int64 = 1_676_155

    /// Transcripción de batería (mini-spec Fase 5): ADTOF Frame_RNN, puerto PyTorch xavriley/ADTOF-pytorch
    /// (commit `85c192e`), Core ML FP32 con GRU nativa de MIL (macOS 15). Cargar **solo con `.cpuOnly`**: la GPU
    /// calcula mal la GRU nativa. Embebido en la app como BTC.
    /// Contrato: `spec` [1, T, 84, 1] float32 (T 100…60 000, 100 fps; log10(1 + banco log 12 b/oct de |STFT| 2048,
    /// hop 441, Hann, 44,1 kHz mono) → `act` [1, T, 5] float32 sigmoide: bombo 35, caja 38, tom 47, charles 42, platos 49.
    public static let drumsADTOF = ModelDescriptor(
        id: "adtof-drums",
        version: "framernn-85c192e-fp32-grunative",
        displayName: "Transcripción de batería",
        role: .drumTranscription,
        url: URL(string: "bundle:///ADTOF_FrameRNN_fp32.mlpackage.zip")!,
        sha256: drumsADTOFSHA256,
        archiveBytes: drumsADTOFBytes,
        archiveKind: .bundledZippedMLPackage,
        packageName: "ADTOF_FrameRNN_fp32.mlpackage",
        license: "CC BY-NC-SA 4.0 (ADTOF; puerto sin licencia): uso personal, no redistribuir")

    public static let all: [ModelDescriptor] = [separatorBSRoformerSW, chordsBTC, beatsBeatThis,
                                                transcriptionBasicPitch, leadRhythmMelRoformer, drumsADTOF]
}
