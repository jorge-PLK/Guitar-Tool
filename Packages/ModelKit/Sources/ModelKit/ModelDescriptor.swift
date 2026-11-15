import Foundation

public enum ModelRole: String, Sendable, Equatable, Codable, CaseIterable {
    case separation, chords, beats, guitarTranscription, drumTranscription
}

public enum ModelArchiveKind: String, Sendable, Equatable, Codable {
    case zippedMLPackage
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

    public static let all: [ModelDescriptor] = [separatorBSRoformerSW]
}
