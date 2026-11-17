import Foundation
@testable import TabKit

/// Proyectos reales de las puertas de la Fase 5b (`TF_P5B_TESTS=1`). Se leen de una copia aislada, nunca de
/// `~/Music/ToneForge` (la rama de la Fase 5b borra datos de la Fase 6). `TF_P5B_PROJECTS` cambia la carpeta.
enum P5BProjects {
    static let root: URL = {
        if let p = ProcessInfo.processInfo.environment["TF_P5B_PROJECTS"], !p.isEmpty {
            return URL(fileURLWithPath: p, isDirectory: true)
        }
        return URL(fileURLWithPath: "/private/tmp/claude-501/-Volumes-SSD-Mac-Personales-Guitar-Tool--claude-worktrees-fase-5/a4ceb755-444a-4d43-b0c5-95e0b2520235/scratchpad/sandbox/projects", isDirectory: true)
    }()

    static func project(_ name: String) -> URL { root.appendingPathComponent(name) }

    /// Pulsos del análisis del proyecto (`cache/analysis.json`), como `session.beats` en la app.
    static func beats(_ project: URL) throws -> BeatTimes {
        let an = try JSONSerialization.jsonObject(with: Data(contentsOf: project.appendingPathComponent("cache/analysis.json"))) as! [String: Any]
        let b = (an["analysis"] as! [String: Any])["beats"] as! [String: Any]
        return BeatTimes(beats: b["beats"] as! [Double], downbeats: b["downbeats"] as! [Double],
                         beatsPerBar: b["beatsPerBar"] as? Int)
    }

    /// Stems del proyecto que existen, por papel.
    static func stems(_ project: URL) -> [SongsterrStemRole: URL] {
        var stems: [SongsterrStemRole: URL] = [:]
        for r in SongsterrStemRole.allCases {
            let u = project.appendingPathComponent("stems/\(r.rawValue).wav")
            if FileManager.default.fileExists(atPath: u.path) { stems[r] = u }
        }
        return stems
    }

    /// Pistas `0.json`, `1.json`… de una revisión, hasta la primera que falte.
    static func tracks(_ revision: URL) throws -> [SongsterrTrack] {
        var out: [SongsterrTrack] = []
        while let d = try? Data(contentsOf: revision.appendingPathComponent("\(out.count).json")) {
            out.append(try SongsterrTrackConverter.convert(d))
        }
        return out
    }
}
