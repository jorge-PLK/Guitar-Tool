import Foundation
import XCTest
@testable import Store

func makeTempDir(_ name: String = "store") throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ToneForgeStoreTests-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func whole(_ d: Date = Date()) -> Date { Date(timeIntervalSince1970: d.timeIntervalSince1970.rounded()) }

func makeSong(title: String = "Song", sha: String = "abc", rate: Double = 44100) -> Song {
    Song(title: title, artist: "Artist", source: "source/original.mp3", sourceSHA256: sha, sourceFormat: "mp3",
         sourceSampleRate: 44100, sourceChannels: 2, sampleRate: rate, duration: 123.5)
}

func makeFullProject() -> Project {
    let guitar = Guitar(name: "Strat", stem: .guitar, side: "left", role: "rhythm")
    let section = Section(name: "Solo", start: 10, end: 20, kind: "solo")
    let take = Take(guitarId: guitar.id, sectionId: section.id, diFile: "takes/a-di.wav",
                    processedFile: "takes/a-proc.wav", micFile: "takes/a-mic.wav", discarded: false, createdAt: whole())
    return Project(
        song: makeSong(),
        separation: SeparationState(state: .done, model: "bs-roformer-sw@gridshift-fp16", finishedAt: whole(), error: nil),
        stems: StemKind.allCases.map { Stem(kind: $0, file: ProjectLayout.stemRelativePath($0)) },
        guitars: [guitar], sections: [section], rigs: [Rig(name: "Lead", scene: "A", file: "rigs/lead.rig")],
        takes: [take], videos: [Video(takeId: take.id, file: "video/a.mov", fps: 30, cameraOffsetMs: -12.5)],
        createdAt: whole(), updatedAt: whole())
}

/// Importador simulado: escribe ficheros de texto con la frecuencia pedida.
actor MockImporter: AudioImporting {
    var failResampleAt: Int?          // índice (0-based) de la llamada a resample que falla
    private(set) var resampleCalls = 0
    var title: String? = nil
    var artist: String? = nil

    func setFailResample(at n: Int?) { failResampleAt = n }
    func setMeta(title: String?, artist: String?) { self.title = title; self.artist = artist }

    func importAudio(from source: URL, to destination: URL, sampleRate: Double,
                     progress: @escaping @Sendable (Double) -> Void) async throws -> ImportedAudioInfo {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "wav@\(Int(sampleRate))".write(to: destination, atomically: true, encoding: .utf8)
        progress(1)
        return ImportedAudioInfo(title: title, artist: artist, duration: 10, sourceFormat: source.pathExtension,
                                 sourceSampleRate: 44100, sourceChannels: 2)
    }

    func resample(_ file: URL, to destination: URL, sampleRate: Double) async throws {
        let n = resampleCalls
        resampleCalls += 1
        if failResampleAt == n { throw NSError(domain: "mock", code: 1) }
        try "stem@\(Int(sampleRate))".write(to: destination, atomically: true, encoding: .utf8)
    }
}

enum SeparatorBehavior: Sendable { case succeed, fail, hang }

/// Separador simulado: cuenta solapes, puede fallar o quedarse colgado hasta cancelación / `release()`.
actor MockSeparator: StemSeparating {
    nonisolated let modelIdentifier: String? = "mock@1"
    var behavior: SeparatorBehavior = .succeed
    private(set) var active = 0
    private(set) var maxActive = 0
    private(set) var calls = 0
    private(set) var statesSeen: [String] = []
    private var gated = false

    func setBehavior(_ b: SeparatorBehavior) { behavior = b }
    func setGated(_ g: Bool) { gated = g }

    func separate(input: URL, outputDirectory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        active += 1
        maxActive = max(maxActive, active)
        calls += 1
        defer { active -= 1 }
        // Estado persistido en el momento de separar (carpeta = input/../..)
        let folder = input.deletingLastPathComponent().deletingLastPathComponent()
        if let p = try? ProjectFile.load(folder: folder) { statesSeen.append(p.separation.state.rawValue) }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try "partial".write(to: outputDirectory.appendingPathComponent("drums.wav"), atomically: true, encoding: .utf8)
        switch behavior {
        case .fail:
            throw NSError(domain: "mock", code: 2, userInfo: [NSLocalizedDescriptionKey: "modelo roto"])
        case .hang:
            try await Task.sleep(for: .seconds(60))
        case .succeed:
            while gated { try await Task.sleep(for: .milliseconds(10)) }
            try await Task.sleep(for: .milliseconds(30))
        }
        for kind in StemKind.allCases {
            try "stem".write(to: outputDirectory.appendingPathComponent("\(kind.rawValue).wav"), atomically: true, encoding: .utf8)
        }
        progress(1)
    }
}

/// Medidor simulado: son silencio los stems cuyo nombre de fichero esté en `silent` (p. ej. `other.wav`).
actor MockMeter: StemLevelMeasuring {
    var silent: Set<String> = []
    private(set) var measured: [String] = []
    func setSilent(_ names: Set<String>) { silent = names }
    func isSilent(stem: URL) async throws -> Bool {
        measured.append(stem.lastPathComponent)
        return silent.contains(stem.lastPathComponent)
    }
}

/// Analizador simulado: escribe `cache/analysis.json` con una «huella» (`version`); cambiarla lo desfasa.
actor MockAnalyzer: StudyAnalyzing {
    var version = "v1"
    var failNext = false
    var gated = false
    private(set) var calls: [UUID] = []
    private(set) var stemsSeen: [[StemKind]] = []
    private(set) var active = 0
    private(set) var maxActive = 0

    func setVersion(_ v: String) { version = v }
    func setFailNext(_ f: Bool) { failNext = f }
    func setGated(_ g: Bool) { gated = g }

    func isCurrent(project: Project, layout: ProjectLayout) async -> Bool {
        (try? String(contentsOf: layout.analysisCache, encoding: .utf8)) == "\(version)|\(project.separation.finishedAt?.timeIntervalSince1970 ?? 0)"
    }

    func analyze(project: Project, layout: ProjectLayout) async throws {
        active += 1
        maxActive = max(maxActive, active)
        defer { active -= 1 }
        calls.append(project.id)
        stemsSeen.append(project.stems.filter { !$0.isEmpty }.map(\.kind))
        while gated { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(20))
        if failNext { failNext = false; throw NSError(domain: "mock", code: 3, userInfo: [NSLocalizedDescriptionKey: "sin modelo"]) }
        try FileManager.default.createDirectory(at: layout.cacheDir, withIntermediateDirectories: true)
        try "\(version)|\(project.separation.finishedAt?.timeIntervalSince1970 ?? 0)"
            .write(to: layout.analysisCache, atomically: true, encoding: .utf8)
    }
}

func waitUntil(timeout: TimeInterval = 5, _ cond: @Sendable () async -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if await cond() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await cond()
}

struct Env {
    let dir: URL
    let root: URL
    let profile: ProfileStore
    let index: LibraryIndex
    let importer = MockImporter()
    let separator = MockSeparator()
    let meter = MockMeter()
    let analyzer = MockAnalyzer()
    let library: Library

    init(autoSeparate: Bool = true, rate: Double = 44100, withMeter: Bool = false, withAnalyzer: Bool = false) async throws {
        dir = try makeTempDir("lib")
        root = dir.appendingPathComponent("Projects", isDirectory: true)
        profile = ProfileStore(url: dir.appendingPathComponent("profile.json"))
        try profile.save(EquipmentProfile(projectsFolder: root, workingSampleRate: rate))
        index = try LibraryIndex.make(storeURL: dir.appendingPathComponent("idx/Library.store"))
        library = Library(root: root, profile: profile, index: index, importer: importer, separator: separator,
                          autoSeparate: autoSeparate, levelMeter: withMeter ? meter : nil,
                          analyzer: withAnalyzer ? analyzer : nil)
    }

    func makeSource(_ name: String, content: String) throws -> URL {
        let u = dir.appendingPathComponent(name)
        try content.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    func project(_ id: UUID) async throws -> Project {
        let f = try XCTUnwrap(ProjectScanner.scan(root: root).found.first { $0.project.id == id }?.folder)
        return try ProjectFile.load(folder: f)
    }

    func folder(_ id: UUID) throws -> URL {
        try XCTUnwrap(ProjectScanner.scan(root: root).found.first { $0.project.id == id }?.folder)
    }
}
