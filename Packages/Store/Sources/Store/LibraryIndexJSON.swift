import Foundation

#if !canImport(SwiftData)
/// Índice de la biblioteca sin SwiftData (Windows): un único `Library.json` con escritura atómica.
/// Es una caché reconstruible (la verdad son los project.json) y pequeña (una fila de ~250 bytes por tema:
/// cientos de temas son decenas de KB), con escrituras solo al importar/editar; basta JSON entero en memoria.
/// Misma interfaz pública que la versión SwiftData.
public actor LibraryIndex {
    private struct Record: Codable {
        var id: UUID
        var title: String
        var artist: String?
        var folderName: String
        var createdAt: Date
        var updatedAt: Date
        var duration: Double
        var sampleRate: Double
        var separationState: String
        var stemCount: Int
        var takeCount: Int
        var rigCount: Int
        var diskBytes: Int64
    }

    private struct FileContents: Codable {
        var version = 1
        var entries: [Record] = []
    }

    public static var defaultStoreURL: URL {
        PlatformPaths.appSupport.appendingPathComponent("ToneForge/Library.json")
    }

    private let url: URL
    private var byID: [UUID: Record] = [:]

    private init(url: URL) {
        self.url = url
        // Un índice ilegible o de otra versión se descarta: se reconstruye con `rebuild`.
        if let data = try? Data(contentsOf: url),
           let f = try? Self.decoder.decode(FileContents.self, from: data), f.version == 1 {
            byID = Dictionary(f.entries.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        }
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Crea el índice en `storeURL` (por defecto `%LOCALAPPDATA%\ToneForge\Library.json`).
    public static func make(storeURL: URL? = nil) throws -> LibraryIndex {
        let url = storeURL ?? defaultStoreURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return LibraryIndex(url: url)
    }

    private func save() throws {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        let sorted = byID.values.sorted { $0.id.uuidString < $1.id.uuidString }
        try e.encode(FileContents(entries: sorted)).write(to: url, options: .atomic)
    }

    /// Devuelve true si la entrada es nueva.
    @discardableResult
    private func apply(_ p: Project, folder: URL) -> Bool {
        let isNew = byID[p.id] == nil
        byID[p.id] = Record(
            id: p.id, title: p.song.title, artist: p.song.artist, folderName: folder.lastPathComponent,
            createdAt: p.createdAt, updatedAt: p.updatedAt, duration: p.song.duration, sampleRate: p.song.sampleRate,
            separationState: p.separation.state.rawValue, stemCount: p.stems.count, takeCount: p.takes.count,
            rigCount: p.rigs.count, diskBytes: DiskSize.allocatedBytes(of: folder))
        return isNew
    }

    public func upsert(project: Project, folder: URL) throws {
        apply(project, folder: folder)
        try save()
    }

    public func remove(id: UUID) throws {
        byID[id] = nil
        try save()
    }

    public func folderName(for id: UUID) -> String? { byID[id]?.folderName }

    public func rebuild(root: URL) throws -> RebuildReport {
        let scan = ProjectScanner.scan(root: root)
        var report = RebuildReport(skipped: scan.skipped)
        let foundIDs = Set(scan.found.map(\.project.id))
        for id in byID.keys where !foundIDs.contains(id) {
            byID[id] = nil
            report.removed += 1
        }
        for s in scan.found {
            if apply(s.project, folder: s.folder) { report.added += 1 } else { report.updated += 1 }
        }
        try save()
        return report
    }

    /// Ordenadas por `updatedAt` descendente.
    public func entries() throws -> [LibraryEntryInfo] {
        byID.values.sorted { $0.updatedAt > $1.updatedAt }.map {
            LibraryEntryInfo(id: $0.id, title: $0.title, artist: $0.artist, folderName: $0.folderName,
                             createdAt: $0.createdAt, updatedAt: $0.updatedAt, duration: $0.duration,
                             sampleRate: $0.sampleRate, separationState: $0.separationState, stemCount: $0.stemCount,
                             takeCount: $0.takeCount, rigCount: $0.rigCount, diskBytes: $0.diskBytes)
        }
    }
}
#endif
