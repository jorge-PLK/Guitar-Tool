import Foundation

// MARK: - Utilidades de fichero

enum FileOps {
    /// Sustituye `destination` por `temporary` (misma carpeta/volumen) de forma atómica; si no existía, lo mueve.
    static func atomicReplace(_ destination: URL, with temporary: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: temporary, to: destination)
        }
    }

    static func atomicWrite(_ data: Data, to destination: URL) throws {
        let tmp = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: tmp)
            try atomicReplace(destination, with: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
    }

    static func removeIfExists(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Tamaños en disco.
public enum DiskSize {
    /// Bytes asignados (como Finder «tamaño en disco») de un fichero o carpeta (recursivo, incluye ocultos).
    public static func allocatedBytes(of url: URL) -> Int64 {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
        func size(_ u: URL) -> Int64 {
            let v = try? u.resourceValues(forKeys: keys)
            return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        guard fm.fileExists(atPath: url.path) else { return 0 }
        var total = size(url)
        guard let names = try? fm.subpathsOfDirectory(atPath: url.path) else { return total }
        for n in names { total += size(url.appendingPathComponent(n)) }
        return total
    }

    /// Bytes lógicos de un fichero.
    static func logicalBytes(of url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

// MARK: - project.json

public enum ProjectFileError: Error, Equatable, Sendable {
    /// El fichero lo escribió una versión más nueva de la app.
    case unsupportedSchema(found: Int, supported: Int)
}

public enum ProjectFile {
    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private struct VersionProbe: Decodable { var schemaVersion: Int }

    public static func load(folder: URL) throws -> Project {
        let data = try Data(contentsOf: ProjectLayout(folder: folder).projectFile)
        let decoder = makeDecoder()
        let probe = try decoder.decode(VersionProbe.self, from: data)
        guard probe.schemaVersion <= Project.currentSchemaVersion else {
            throw ProjectFileError.unsupportedSchema(found: probe.schemaVersion, supported: Project.currentSchemaVersion)
        }
        return try decoder.decode(Project.self, from: data)
    }

    public static func save(_ project: Project, to folder: URL) throws {
        let data = try makeEncoder().encode(project)
        try FileOps.atomicWrite(data, to: ProjectLayout(folder: folder).projectFile)
    }
}

// MARK: - Layout

public struct ProjectLayout: Sendable, Equatable {
    public static let audioRelativePath = "audio/song.wav"
    /// Carátula de un tema importado desde un enlace (mini-spec Fase 2b, «Datos»).
    public static let coverRelativePath = "source/cover.jpg"

    public let folder: URL

    public init(folder: URL) { self.folder = folder }

    public var projectFile: URL { folder.appendingPathComponent("project.json") }
    public var sourceDir: URL { folder.appendingPathComponent("source", isDirectory: true) }
    public var coverFile: URL { folder.appendingPathComponent(Self.coverRelativePath) }
    public var audioDir: URL { folder.appendingPathComponent("audio", isDirectory: true) }
    public var audioFile: URL { folder.appendingPathComponent(Self.audioRelativePath) }
    public var stemsDir: URL { folder.appendingPathComponent("stems", isDirectory: true) }
    public var stemsPartialDir: URL { stemsDir.appendingPathComponent(".partial", isDirectory: true) }
    public var takesDir: URL { folder.appendingPathComponent("takes", isDirectory: true) }
    public var videoDir: URL { folder.appendingPathComponent("video", isDirectory: true) }
    public var rigsDir: URL { folder.appendingPathComponent("rigs", isDirectory: true) }
    public var cacheDir: URL { folder.appendingPathComponent("cache", isDirectory: true) }

    /// Análisis automático de estudio (pulso, acordes, tonalidad); regenerable, lo limpia `ProjectCleaner` con `cache/`.
    public var analysisCache: URL { cacheDir.appendingPathComponent("analysis.json") }

    /// Tablatura (mini-spec Fase 5, «Datos»): `tab/score.json` lleva las ediciones y NO es caché (`ProjectCleaner` no
    /// lo toca); `cache/tab/` (WAV sintetizados) sí es regenerable y se limpia con `cache/`.
    public var tabDir: URL { folder.appendingPathComponent("tab", isDirectory: true) }
    public var tabScoreFile: URL { tabDir.appendingPathComponent("score.json") }
    public var tabCacheDir: URL { cacheDir.appendingPathComponent("tab", isDirectory: true) }
    public func tabSynthURL(trackID: String) -> URL { tabCacheDir.appendingPathComponent("synth_\(trackID).wav") }

    /// Salida provisional del paso de guitarras.
    public var guitarsPartialDir: URL { stemsDir.appendingPathComponent(".partial-guitars", isDirectory: true) }

    public func guitarURL(_ role: GuitarRole) -> URL { url(relative: role.relativePath) }

    /// Huella de un fichero (tamaño + fecha de modificación); nil si no existe.
    static func fileFingerprint(_ url: URL) -> String? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let size = (a[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size)-\(String(format: "%.6f", mtime))"
    }

    /// Huella de la entrada del paso de guitarras: `stems/guitar.wav`.
    public var guitarInputFingerprint: String? { Self.fileFingerprint(stemURL(.guitar)) }

    public func stemURL(_ kind: StemKind) -> URL {
        stemsDir.appendingPathComponent("\(kind.rawValue).wav")
    }

    /// Ruta relativa de un stem (`stems/drums.wav`).
    public static func stemRelativePath(_ kind: StemKind) -> String { "stems/\(kind.rawValue).wav" }

    /// Toma grabada y alineada (mini-spec Fase 3, «Grabación»): `takes/<id>/processed.wav`.
    public static func processedRelativePath(takeId: UUID) -> String { "takes/\(takeId.uuidString)/processed.wav" }

    public func processedURL(takeId: UUID) -> URL { url(relative: Self.processedRelativePath(takeId: takeId)) }

    /// Resuelve una ruta relativa (con `/`) dentro de la carpeta.
    public func url(relative: String) -> URL { folder.appendingPathComponent(relative) }

    public func createSkeleton() throws {
        let fm = FileManager.default
        for dir in [folder, sourceDir, audioDir, stemsDir, takesDir, videoDir, rigsDir, cacheDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

// MARK: - Nombres de carpeta

public enum FolderNaming {
    /// `"<Artista> - <Título>"` o solo el título; sin `/ : \` ni caracteres de control; mantiene acentos.
    public static func baseName(title: String, artist: String?) -> String {
        let t = sanitize(title)
        let a = artist.map(sanitize) ?? ""
        let name = a.isEmpty ? t : (t.isEmpty ? a : "\(a) - \(t)")
        return name.isEmpty ? "Sin título" : name
    }

    static func sanitize(_ s: String) -> String {
        let banned = CharacterSet(charactersIn: "/:\\").union(.controlCharacters).union(.newlines)
        let cleaned = String(String.UnicodeScalarView(s.unicodeScalars.filter { !banned.contains($0) }))
        var r = cleaned.trimmingCharacters(in: .whitespaces)
        while r.hasPrefix(".") { r.removeFirst() }
        return r.trimmingCharacters(in: .whitespaces)
    }

    /// Si `base` existe en `root` → `base (2)`, `base (3)`…
    public static func uniqueName(base: String, in root: URL) -> String {
        let fm = FileManager.default
        var candidate = base
        var n = 2
        while fm.fileExists(atPath: root.appendingPathComponent(candidate).path) {
            candidate = "\(base) (\(n))"
            n += 1
        }
        return candidate
    }
}

// MARK: - Limpieza

public struct CleanupPlan: Sendable, Equatable {
    public let folder: URL
    /// Elementos que se borrarán (hijos de `stems/` y `cache/`, `audio/song.wav`, ficheros de tomas descartadas).
    public let urls: [URL]
    public let bytes: Int64
    public let discardedTakeIDs: [UUID]
    /// project.json resultante: `stems = []`, `separation.state = none`, sin tomas descartadas.
    public let resultingProject: Project
}

public enum ProjectCleaner {
    public static func plan(folder: URL, project: Project) -> CleanupPlan {
        let fm = FileManager.default
        let layout = ProjectLayout(folder: folder)
        var urls: [URL] = []

        func children(_ dir: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])) ?? [])
                .sorted { $0.path < $1.path }
        }
        urls += children(layout.stemsDir)   // incluye .partial
        if fm.fileExists(atPath: layout.audioFile.path) { urls.append(layout.audioFile) }
        urls += children(layout.cacheDir)

        let discarded = project.takes.filter(\.discarded)
        let liveFiles = Set(project.takes.filter { !$0.discarded }.flatMap(\.files))
        for take in discarded {
            for rel in take.files where !liveFiles.contains(rel) && isRemovable(rel) {
                let u = layout.url(relative: rel)
                if fm.fileExists(atPath: u.path) { urls.append(u) }
            }
        }

        var result = project
        result.stems = []
        // Las pistas `stems/guitar_*.wav` se borran; opciones y nombres se conservan.
        result.guitarApplied = nil
        result.guitars = project.guitars.map { Guitar(role: $0.role, name: $0.name) }
        result.separation = SeparationState(state: .none)
        result.takes = project.takes.filter { !$0.discarded }
        result.updatedAt = Date()

        let bytes = urls.reduce(Int64(0)) { $0 + DiskSize.allocatedBytes(of: $1) }
        return CleanupPlan(folder: folder, urls: urls, bytes: bytes, discardedTakeIDs: discarded.map(\.id), resultingProject: result)
    }

    /// Nunca fuera de la carpeta ni dentro de lo protegido.
    private static func isRemovable(_ relative: String) -> Bool {
        let parts = relative.split(separator: "/").map(String.init)
        guard let first = parts.first, !parts.contains("..") else { return false }
        return !["source", "rigs", "video"].contains(first) && relative != "project.json"
    }

    public static func execute(_ plan: CleanupPlan) throws {
        for u in plan.urls { FileOps.removeIfExists(u) }
        try ProjectFile.save(plan.resultingProject, to: plan.folder)
    }
}
