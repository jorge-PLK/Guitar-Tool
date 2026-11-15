import Foundation

public enum ModelRole: String, Sendable, Equatable, Codable, CaseIterable {
    case separation, chords, beats, guitarTranscription, drumTranscription
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

    public static let all: [ModelDescriptor] = [separatorBSRoformerSW, chordsBTC, beatsBeatThis]
}
