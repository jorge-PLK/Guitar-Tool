import Foundation

// MARK: - Utilidades de fichero

public enum FileOps {
    /// Sustituye `destination` por `temporary` (misma carpeta/volumen) de forma atómica; si no existía, lo mueve.
    /// Pública para la conversión HEVC → H.264 de las tomas en Windows (AppCore, `VideoConversionEngine`).
    public static func atomicReplace(_ destination: URL, with temporary: URL) throws {
        let fm = FileManager.default
        #if os(Windows)
        // `replaceItemAt` no está implementado en Foundation para Windows: MoveFileEx con reemplazo es atómico en NTFS.
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try windowsMoveReplacing(temporary, to: destination)
        #else
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: temporary, to: destination)
        }
        #endif
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

    /// Intentos del borrado con reintento (relevo 10 del paso 8 de la 7c, caso 5; no lo fija la spec): en Windows el
    /// `<video>` de WebView2 recién desmontado o el antivirus pueden retener un fichero un instante (`MoveFileEx` error 5).
    static let removeRetryAttempts = 5
    /// Primera espera entre intentos (s); se dobla en cada reintento: 50 + 100 + 200 + 400 ms = 750 ms de tope (≤ ~1 s).
    static let removeRetryFirstDelay = 0.05

    /// Borra `url` (fichero o carpeta) reintentando hasta `attempts` veces con espera creciente si falla. Si entre
    /// intentos ya no existe, da el borrado por hecho. Agotados los intentos, lanza el último error. Devuelve los intentos
    /// usados (tests). `remove`/`sleep` inyectables para simular un lector que suelta el fichero tarde.
    @discardableResult
    static func removeRetrying(_ url: URL, attempts: Int = removeRetryAttempts, firstDelay: Double = removeRetryFirstDelay,
                               remove: @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
                               sleep: @Sendable (Double) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1e9)) })
        async throws -> Int {
        var delay = firstDelay
        var n = 0
        while true {
            n += 1
            do {
                try remove(url)
                return n
            } catch {
                if !FileManager.default.fileExists(atPath: url.path) { return n }
                if n >= max(attempts, 1) { throw error }
            }
            await sleep(delay)
            delay *= 2
        }
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
            if let a = v?.totalFileAllocatedSize ?? v?.fileAllocatedSize { return Int64(a) }
            #if os(Windows)
            // Foundation en Windows no da el tamaño asignado: se usa el lógico (los directorios cuentan 0).
            if v?.isDirectory != true { return logicalBytes(of: u) }
            #endif
            return 0
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
        try save(project, to: folder, now: Date())
    }

    static func save(_ project: Project, to folder: URL, now: Date) throws {
        let data = try makeEncoder().encode(project)
        let file = ProjectLayout(folder: folder).projectFile
        // Un fallo al copiar nunca impide guardar (Store no tiene mecanismo de registro).
        ProjectBackup.backUpIfNeeded(existing: file, newData: data, now: now)
        try FileOps.atomicWrite(data, to: file)
    }
}

// MARK: - Copias de seguridad de project.json

/// Red de seguridad antes de sobrescribir `project.json`: una app con un esquema más antiguo puede perder claves que no
/// conoce al guardar.
/// - `project.json.bak-YYYYMMDD`: una por día (la primera escritura del día conserva el estado con el que empezó); se
///   conservan las `keptDailyBackups` más recientes.
/// - `project.json.lost-YYYYMMDD-HHMMSS`: siempre que el contenido nuevo pierda claves de primer nivel o tomas con
///   `videoFile` respecto al existente; no se rota.
enum ProjectBackup {
    static let keptDailyBackups = 7
    static let dailyPrefix = "project.json.bak-"
    static let lostPrefix = "project.json.lost-"

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = format
        return f
    }

    static func backUpIfNeeded(existing file: URL, newData: Data, now: Date) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path), let old = try? Data(contentsOf: file), old != newData else { return }
        let dir = file.deletingLastPathComponent()

        if losesData(old: old, new: newData) {
            let url = dir.appendingPathComponent(lostPrefix + formatter("yyyyMMdd-HHmmss").string(from: now))
            if !fm.fileExists(atPath: url.path) { try? old.write(to: url, options: .atomic) }
        }

        let daily = dir.appendingPathComponent(dailyPrefix + formatter("yyyyMMdd").string(from: now))
        if !fm.fileExists(atPath: daily.path) {
            guard (try? old.write(to: daily, options: .atomic)) != nil else { return }
        }
        rotate(in: dir)
    }

    static func isDailyBackupName(_ name: String) -> Bool {
        guard name.hasPrefix(dailyPrefix) else { return false }
        let suffix = name.dropFirst(dailyPrefix.count)
        return suffix.count == 8 && suffix.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func rotate(in dir: URL) {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter(isDailyBackupName).sorted(by: >)
        for name in names.dropFirst(keptDailyBackups) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// Compara como JSON genérico, sin el modelo: claves de primer nivel que desaparecen o tomas con `videoFile` que
    /// lo pierden.
    static func losesData(old: Data, new: Data) -> Bool {
        guard let o = (try? JSONSerialization.jsonObject(with: old)) as? [String: Any] else { return false }
        guard let n = (try? JSONSerialization.jsonObject(with: new)) as? [String: Any] else { return true }
        if !Set(o.keys).subtracting(n.keys).isEmpty { return true }
        return !videoTakeIDs(o).subtracting(videoTakeIDs(n)).isEmpty
    }

    private static func videoTakeIDs(_ root: [String: Any]) -> Set<String> {
        var ids = Set<String>()
        for case let take as [String: Any] in (root["takes"] as? [Any]) ?? [] {
            if let v = take["videoFile"] as? String, !v.isEmpty, let id = take["id"] as? String { ids.insert(id) }
        }
        return ids
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
    /// Rejilla del metrónomo corregida desde Songsterr (pulsos y downbeats, con `songId` y `revisionId`): manda sobre la
    /// del análisis mientras `Project.tabSource` sea ese tema de Songsterr. Va con `score.json` (no es caché: rehacerla
    /// pide descargar y alinear otra vez).
    public var tabSongsterrGridFile: URL { tabDir.appendingPathComponent("songsterr-grid.json") }
    /// Pistas crudas de Songsterr (mini-spec Fase 5b, «Datos»): regenerables, entran en la limpieza con `cache/`.
    public var songsterrCacheDir: URL { cacheDir.appendingPathComponent("songsterr", isDirectory: true) }
    public func songsterrCacheDir(songId: Int, revisionId: Int) -> URL {
        songsterrCacheDir.appendingPathComponent("\(songId)", isDirectory: true)
            .appendingPathComponent("\(revisionId)", isDirectory: true)
    }
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

    /// Tamaño en bytes que lleva una huella de `fileFingerprint` (lo que va antes del primer «-»); nil si no se lee.
    static func fingerprintSize(_ fingerprint: String) -> Int64? {
        fingerprint.split(separator: "-", maxSplits: 1).first.flatMap { Int64($0) }
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

    /// Vídeo de una toma (mini-spec Fase 6): `takes/<id>/video.mov`.
    public static func videoRelativePath(takeId: UUID) -> String { "takes/\(takeId.uuidString)/video.mov" }
    public static func baseProcessedRelativePath(takeId: UUID) -> String { "takes/\(takeId.uuidString)/base/processed.wav" }
    public static func punchRelativeDirectory(takeId: UUID, n: Int) -> String { "takes/\(takeId.uuidString)/punch-\(n)" }

    public func videoURL(takeId: UUID) -> URL { url(relative: Self.videoRelativePath(takeId: takeId)) }
    public func baseProcessedURL(takeId: UUID) -> URL { url(relative: Self.baseProcessedRelativePath(takeId: takeId)) }
    public func punchDirectory(takeId: UUID, n: Int) -> URL {
        folder.appendingPathComponent(Self.punchRelativeDirectory(takeId: takeId, n: n), isDirectory: true)
    }
    /// Carpeta de la toma: `takes/<id>/`.
    public func takeDirectory(takeId: UUID) -> URL {
        takesDir.appendingPathComponent(takeId.uuidString, isDirectory: true)
    }

    /// Análisis de encuadre de una toma (mini-spec Fase 7); regenerable, dentro de `cache/`.
    public static func framingCacheRelativePath(takeId: UUID) -> String { "cache/framing/\(takeId.uuidString).json" }

    public func framingCacheURL(takeId: UUID) -> URL { url(relative: Self.framingCacheRelativePath(takeId: takeId)) }

    /// Vídeo montado: `video/<tema>-<layout>.mov`. `songName` por defecto es el nombre de la carpeta del proyecto
    /// (`<Artista> - <Título>`); se sanea como los nombres de carpeta.
    public func montageVideoURL(layout: MontageLayoutKind, songName: String? = nil,
                                container: MontageContainer = .mov) -> URL {
        videoDir.appendingPathComponent("\(montageBaseName(layout: layout, songName: songName)).\(container.fileExtension)")
    }

    /// WAV por pista del montaje: `video/<tema>-<layout>-pistas/`.
    public func montageTracksDirectory(layout: MontageLayoutKind, songName: String? = nil) -> URL {
        videoDir.appendingPathComponent("\(montageBaseName(layout: layout, songName: songName))-pistas", isDirectory: true)
    }

    private func montageBaseName(layout: MontageLayoutKind, songName: String?) -> String {
        var name = FolderNaming.sanitize(songName ?? folder.lastPathComponent)
        if name.isEmpty { name = "Sin título" }
        return "\(name)-\(layout.rawValue)"
    }

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
