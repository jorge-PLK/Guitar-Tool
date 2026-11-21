import Foundation
#if canImport(SwiftData)
import SwiftData
#endif

#if canImport(SwiftData)
/// Índice SwiftData de la biblioteca: solo una caché reconstruible; la verdad son los project.json.
@Model
public final class LibraryEntry {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var artist: String?
    /// Relativa a la raíz de proyectos.
    public var folderName: String
    public var createdAt: Date
    public var updatedAt: Date
    public var duration: Double
    public var sampleRate: Double
    public var separationState: String
    public var stemCount: Int
    public var takeCount: Int
    public var rigCount: Int
    public var diskBytes: Int64

    public init(id: UUID, title: String, artist: String?, folderName: String, createdAt: Date, updatedAt: Date,
                duration: Double, sampleRate: Double, separationState: String, stemCount: Int, takeCount: Int,
                rigCount: Int, diskBytes: Int64) {
        self.id = id
        self.title = title
        self.artist = artist
        self.folderName = folderName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.duration = duration
        self.sampleRate = sampleRate
        self.separationState = separationState
        self.stemCount = stemCount
        self.takeCount = takeCount
        self.rigCount = rigCount
        self.diskBytes = diskBytes
    }
}

#endif

/// Copia inmutable y Sendable de una entrada (los `@Model` no cruzan actores).
public struct LibraryEntryInfo: Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let artist: String?
    public let folderName: String
    public let createdAt: Date
    public let updatedAt: Date
    public let duration: Double
    public let sampleRate: Double
    public let separationState: String
    public let stemCount: Int
    public let takeCount: Int
    public let rigCount: Int
    public let diskBytes: Int64
}

public struct SkippedProject: Sendable, Equatable {
    public let folderName: String
    public let reason: String
}

public struct RebuildReport: Sendable, Equatable {
    public var added = 0
    public var updated = 0
    public var removed = 0
    public var skipped: [SkippedProject] = []
}

public struct ScannedProject: Sendable {
    public let folder: URL
    public let project: Project
}

public enum ProjectScanner {
    /// Subcarpetas (no ocultas) de `root` con `project.json`; las ilegibles van a `skipped`.
    public static func scan(root: URL) -> (found: [ScannedProject], skipped: [SkippedProject]) {
        let fm = FileManager.default
        let dirs = ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var found: [ScannedProject] = []
        var skipped: [SkippedProject] = []
        for dir in dirs {
            guard fm.fileExists(atPath: ProjectLayout(folder: dir).projectFile.path) else { continue }
            do {
                found.append(ScannedProject(folder: dir, project: try ProjectFile.load(folder: dir)))
            } catch {
                skipped.append(SkippedProject(folderName: dir.lastPathComponent, reason: String(describing: error)))
            }
        }
        return (found, skipped)
    }
}

#if canImport(SwiftData)
@ModelActor
public actor LibraryIndex {
    public static var defaultStoreURL: URL {
        PlatformPaths.appSupport.appendingPathComponent("ToneForge/Library.store")
    }

    /// Crea el contenedor en `storeURL` (por defecto Application Support/ToneForge/Library.store).
    public static func make(storeURL: URL? = nil) throws -> LibraryIndex {
        let url = storeURL ?? defaultStoreURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let container = try ModelContainer(for: LibraryEntry.self, configurations: ModelConfiguration(url: url))
        return LibraryIndex(modelContainer: container)
    }

    private func fetch(id: UUID) -> LibraryEntry? {
        let d = FetchDescriptor<LibraryEntry>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(d))?.first
    }

    /// Devuelve true si la entrada es nueva.
    @discardableResult
    private func apply(_ p: Project, folder: URL) -> Bool {
        let name = folder.lastPathComponent
        let bytes = DiskSize.allocatedBytes(of: folder)
        if let e = fetch(id: p.id) {
            e.title = p.song.title
            e.artist = p.song.artist
            e.folderName = name
            e.createdAt = p.createdAt
            e.updatedAt = p.updatedAt
            e.duration = p.song.duration
            e.sampleRate = p.song.sampleRate
            e.separationState = p.separation.state.rawValue
            e.stemCount = p.stems.count
            e.takeCount = p.takes.count
            e.rigCount = p.rigs.count
            e.diskBytes = bytes
            return false
        }
        modelContext.insert(LibraryEntry(
            id: p.id, title: p.song.title, artist: p.song.artist, folderName: name, createdAt: p.createdAt,
            updatedAt: p.updatedAt, duration: p.song.duration, sampleRate: p.song.sampleRate,
            separationState: p.separation.state.rawValue, stemCount: p.stems.count, takeCount: p.takes.count,
            rigCount: p.rigs.count, diskBytes: bytes))
        return true
    }

    public func upsert(project: Project, folder: URL) throws {
        apply(project, folder: folder)
        try modelContext.save()
    }

    public func remove(id: UUID) throws {
        if let e = fetch(id: id) { modelContext.delete(e) }
        try modelContext.save()
    }

    public func folderName(for id: UUID) -> String? { fetch(id: id)?.folderName }

    public func rebuild(root: URL) throws -> RebuildReport {
        let scan = ProjectScanner.scan(root: root)
        var report = RebuildReport(skipped: scan.skipped)
        let foundIDs = Set(scan.found.map(\.project.id))
        for e in (try modelContext.fetch(FetchDescriptor<LibraryEntry>())) where !foundIDs.contains(e.id) {
            modelContext.delete(e)
            report.removed += 1
        }
        for s in scan.found {
            if apply(s.project, folder: s.folder) { report.added += 1 } else { report.updated += 1 }
        }
        try modelContext.save()
        return report
    }

    /// Ordenadas por `updatedAt` descendente.
    public func entries() throws -> [LibraryEntryInfo] {
        let d = FetchDescriptor<LibraryEntry>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try modelContext.fetch(d).map {
            LibraryEntryInfo(id: $0.id, title: $0.title, artist: $0.artist, folderName: $0.folderName,
                             createdAt: $0.createdAt, updatedAt: $0.updatedAt, duration: $0.duration,
                             sampleRate: $0.sampleRate, separationState: $0.separationState, stemCount: $0.stemCount,
                             takeCount: $0.takeCount, rigCount: $0.rigCount, diskBytes: $0.diskBytes)
        }
    }
}
#endif
