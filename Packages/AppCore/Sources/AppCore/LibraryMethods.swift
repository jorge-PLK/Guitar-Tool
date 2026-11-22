import Foundation
import NativeAudioFile
import Store

/// Resumen de un tema para la lista de la Biblioteca (campos exactos en `Temp/win/step8-contract.md`).
public struct ProjectSummary: Codable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var artist: String?
    public var folderName: String
    public var duration: Double
    public var sampleRate: Double
    /// Relativa a la carpeta de proyectos; solo si el fichero existe.
    public var cover: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var separationState: String
    public var stemCount: Int
    public var takeCount: Int
    public var rigCount: Int
    public var hasAnalysis: Bool
    public var origin: String?
    /// Nombres de las pistas de guitarra separadas (`project.guitars`); vacía si no hay.
    public var guitars: [String]
}

public struct SkippedInfo: Codable, Sendable, Equatable {
    public var folderName: String
    public var reason: String
}

struct LibraryListResult: Codable, Sendable {
    var projects: [ProjectSummary]
    var skipped: [SkippedInfo]
}

struct StemInfo: Codable, Sendable, Equatable {
    var kind: String
    var bytes: Int64
    var isEmpty: Bool
}

struct TakeInfo: Codable, Sendable, Equatable {
    var id: UUID
    var number: Int
    var createdAt: Date
    var discarded: Bool
    var isBest: Bool
    var hasVideo: Bool
    var punchCount: Int
    /// Segundos del WAV procesado (`ProjectRecordingsView.durationText`); nil si no hay fichero o no se lee («–»).
    var duration: Double?
    var audio: String?
    var video: String?
    /// Tiempo del tema en que empieza la toma (segundos).
    var songStart: Double?
    /// Desfase audio/vídeo (ms, positivo = la imagen llega tarde).
    var videoOffsetMs: Double?
    /// Giro de la imagen en grados horarios (0, 90, 180, 270).
    var videoRotation: Int
    var punches: [TakePunchInfo]
}

struct TakePunchInfo: Codable, Sendable, Equatable {
    var start: Double
    var end: Double
    /// Ruta relativa a la carpeta de proyectos, o nil si el punch no tiene vídeo.
    var videoPath: String?
    var videoOffsetMs: Double?
}

/// `library.takeBacking`: lo que suena en «Ver toma» con el botón «Backing» (`TakeViewPlanning.plan` del Mac).
struct TakeBackingResult: Codable, Sendable, Equatable {
    var takeStart: Double
    /// Volumen lineal del canal «Tú · parte» para la toma.
    var takeVolume: Double
    var tracks: [TakeBackingTrack]
}

struct TakeBackingTrack: Codable, Sendable, Equatable {
    var kind: String
    /// Ruta relativa a la carpeta de proyectos; sus tiempos son los del tema (empiezan en 0).
    var path: String
    /// Volumen lineal (mezcla de Grabar).
    var volume: Double
    /// Tramo del tema (segundos) en que esta pista se silencia (la guitarra que la parte sustituye); nil = nunca.
    var mutedSpan: MontageRangeInfo?
}

struct TakeBackingParams: Codable, Sendable { var id: String; var takeId: String }

struct PartInfo: Codable, Sendable, Equatable {
    var id: UUID
    var name: String
    var isLead: Bool
    var takes: [TakeInfo]
}

/// `library.project`: el resumen más el detalle de `ProjectDetailView` (Swift sintetiza el aplanado a mano).
struct ProjectDetailResult: Codable, Sendable {
    var summary: ProjectSummary
    var separationError: String?
    var stems: [StemInfo]
    var parts: [PartInfo]
    var videoCount: Int

    private struct Keys: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    func encode(to encoder: Encoder) throws {
        try summary.encode(to: encoder)
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(separationError, forKey: Keys(stringValue: "separationError")!)
        try c.encode(stems, forKey: Keys(stringValue: "stems")!)
        try c.encode(parts, forKey: Keys(stringValue: "parts")!)
        try c.encode(videoCount, forKey: Keys(stringValue: "videoCount")!)
    }

    init(summary: ProjectSummary, separationError: String?, stems: [StemInfo], parts: [PartInfo], videoCount: Int) {
        self.summary = summary
        self.separationError = separationError
        self.stems = stems
        self.parts = parts
        self.videoCount = videoCount
    }

    init(from decoder: Decoder) throws {
        summary = try ProjectSummary(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        separationError = try c.decodeIfPresent(String.self, forKey: Keys(stringValue: "separationError")!)
        stems = try c.decode([StemInfo].self, forKey: Keys(stringValue: "stems")!)
        parts = try c.decode([PartInfo].self, forKey: Keys(stringValue: "parts")!)
        videoCount = try c.decode(Int.self, forKey: Keys(stringValue: "videoCount")!)
    }
}

struct RevealResult: Codable, Sendable { var revealed: Bool }

struct ProjectIDParams: Codable, Sendable { var id: String }

/// Lectura de la Biblioteca con Store (sin índice: `ProjectScanner` lee los `project.json`, que son la verdad).
struct LibraryService: Sendable {
    let root: URL

    private func summary(_ s: ScannedProject) -> ProjectSummary {
        let layout = ProjectLayout(folder: s.folder)
        let name = s.folder.lastPathComponent
        let fm = FileManager.default
        let p = s.project
        return ProjectSummary(
            id: p.id, title: p.song.title, artist: p.song.artist, folderName: name,
            duration: p.song.duration, sampleRate: p.song.sampleRate,
            cover: fm.fileExists(atPath: layout.coverFile.path) ? "\(name)/\(ProjectLayout.coverRelativePath)" : nil,
            createdAt: p.createdAt, updatedAt: p.updatedAt,
            separationState: p.separation.state.rawValue,
            stemCount: p.stems.count, takeCount: p.takes.count, rigCount: p.rigs.count,
            hasAnalysis: fm.fileExists(atPath: layout.analysisCache.path),
            origin: p.song.origin?.kind.rawValue,
            guitars: p.guitars.map(\.name))
    }

    func list() -> LibraryListResult {
        let scan = ProjectScanner.scan(root: root)
        let projects = scan.found.map(summary).sorted {
            LibraryFilter.fold($0.title) < LibraryFilter.fold($1.title)
        }
        return LibraryListResult(projects: projects,
                                 skipped: scan.skipped.map { SkippedInfo(folderName: $0.folderName, reason: $0.reason) })
    }

    /// Carpeta del tema (para `library.reveal`).
    func folder(id: UUID) throws -> URL {
        guard let s = ProjectScanner.scan(root: root).found.first(where: { $0.project.id == id }) else {
            throw RPCError(code: "not-found", message: "No hay ningún tema con id \(id.uuidString).")
        }
        return s.folder
    }

    /// Duración del WAV (s) o nil si no se puede leer (`TakeViewPlanning.duration(of:)` del Mac).
    static func duration(of url: URL) -> Double? {
        guard let f = try? AudioFileReader(url: url), f.sampleRate > 0 else { return nil }
        return Double(f.frameCount) / f.sampleRate
    }

    func detail(id: UUID) throws -> ProjectDetailResult {
        guard let s = ProjectScanner.scan(root: root).found.first(where: { $0.project.id == id }) else {
            throw RPCError(code: "not-found", message: "No hay ningún tema con id \(id.uuidString).")
        }
        let layout = ProjectLayout(folder: s.folder)
        let name = s.folder.lastPathComponent
        let p = s.project
        let stems = p.stems.map { st -> StemInfo in
            let size = (try? FileManager.default.attributesOfItem(atPath: layout.stemURL(st.kind).path)[.size] as? Int64) ?? 0
            return StemInfo(kind: st.kind.rawValue, bytes: size, isEmpty: st.isEmpty)
        }
        let parts = (p.recording?.parts ?? []).filter { !$0.takeIDs.isEmpty }.map { part -> PartInfo in
            var takes: [TakeInfo] = []
            for (i, tid) in part.takeIDs.enumerated() {
                guard let t = p.takes.first(where: { $0.id == tid }) else { continue }
                takes.append(TakeInfo(
                    id: t.id, number: i + 1, createdAt: t.createdAt, discarded: t.discarded,
                    isBest: part.bestTakeID == t.id, hasVideo: t.videoFile != nil || (t.punches ?? []).contains { $0.videoFile != nil },
                    punchCount: t.punches?.count ?? 0,
                    duration: t.processedFile.flatMap { Self.duration(of: layout.url(relative: $0)) },
                    audio: t.processedFile.map { "\(name)/\($0)" }, video: t.videoFile.map { "\(name)/\($0)" },
                    songStart: t.songStart, videoOffsetMs: t.videoOffset.map { $0 * 1000 }, videoRotation: t.rotationDegrees,
                    punches: (t.punches ?? []).map {
                        TakePunchInfo(start: $0.start, end: $0.end, videoPath: $0.videoFile.map { "\(name)/\($0)" },
                                      videoOffsetMs: ($0.videoOffset ?? t.videoOffset).map { $0 * 1000 })
                    }))
            }
            return PartInfo(id: part.id, name: part.name, isLead: part.isLead, takes: takes)
        }
        return ProjectDetailResult(summary: summary(s), separationError: p.separation.error, stems: stems,
                                   parts: parts, videoCount: p.videos.count)
    }

    /// Pistas del backing de «Ver toma»: stems audibles según la mezcla de Grabar (sin la guitarra completa si hay guitarras
    /// separadas), una por guitarra separada, y la guitarra que la parte sustituye silenciada durante la toma.
    func takeBacking(id: UUID, takeId: UUID) throws -> TakeBackingResult {
        guard let s = ProjectScanner.scan(root: root).found.first(where: { $0.project.id == id }) else {
            throw RPCError(code: "not-found", message: "No hay ningún tema con id \(id.uuidString).")
        }
        let p = s.project
        let layout = ProjectLayout(folder: s.folder)
        let name = s.folder.lastPathComponent
        guard let take = p.takes.first(where: { $0.id == takeId }), let rel = take.processedFile, let start = take.songStart else {
            throw RPCError(code: "not-found", message: "La toma no existe o no tiene audio procesado.")
        }
        let dur = Self.duration(of: layout.url(relative: rel)) ?? 0
        let span = MontageRangeInfo(start: start, end: start + dur)
        let rec = p.recordingOrInitial()
        let part = rec.part(containingTake: takeId)
        let replaced = part?.replaces
        let fm = FileManager.default
        let separated = p.guitarTracks.filter { g in g.file.map { fm.fileExists(atPath: layout.url(relative: $0).path) } == true }
        let anySolo = rec.mix.contains { $0.solo }
        func audible(_ m: StemMix) -> Bool { !m.muted && (!anySolo || m.solo) }
        func linear(_ dB: Double) -> Double { pow(10, dB / 20) }
        var tracks: [TakeBackingTrack] = []
        for st in p.stems where !st.isEmpty {
            let kind = st.kind
            let url = layout.stemURL(kind)
            guard !(kind == .guitar && !separated.isEmpty), fm.fileExists(atPath: url.path) else { continue }
            let m = rec.mix.first { $0.kind == kind && $0.guitarRole == nil } ?? StemMix(kind: kind)
            guard audible(m) else { continue }
            tracks.append(TakeBackingTrack(kind: kind.rawValue, path: "\(name)/" + Self.relative(url, in: s.folder), volume: linear(m.gainDB),
                                           mutedSpan: kind == .guitar && replaced != nil ? span : nil))
        }
        for g in separated {
            let m = rec.mix.first { $0.guitarRole == g.role } ?? StemMix(kind: .guitar, guitarRole: g.role)
            guard audible(m) else { continue }
            tracks.append(TakeBackingTrack(kind: "guitar", path: "\(name)/\(g.role.relativePath)", volume: linear(m.gainDB),
                                           mutedSpan: g.role == replaced ? span : nil))
        }
        return TakeBackingResult(takeStart: start, takeVolume: linear(rec.partMix(for: part?.id ?? takeId).gainDB), tracks: tracks)
    }

    private static func relative(_ url: URL, in folder: URL) -> String {
        let base = folder.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        return full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : url.lastPathComponent
    }
}
