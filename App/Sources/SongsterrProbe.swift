#if DEBUG
import AppKit
import SourceKit
import TabKit

/// Solo DEBUG: `--songsterr-probe <songId> --songsterr-out <dir>` comprueba de verdad (WKWebView + CDN) la lectura de la
/// página de un tema, la descarga de sus pistas y su conversión, escribe `<dir>/probe.txt` con el resumen y sale.
/// Los JSON descargados quedan en `<dir>/cache/` (carpeta sin versionar: `Temp/`).
@MainActor
enum SongsterrProbe {
    static func run(songId: Int, out: URL, artist: String?, title: String?) {
        Task {
            var lines: [String] = []
            func log(_ s: String) { lines.append(s); print("[songsterr-probe] \(s)") }
            let t0 = Date()
            func lap() -> String { String(format: "%.1f s", Date().timeIntervalSince(t0)) }
            do {
                try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                let client = SongsterrClient(loader: SongsterrWebLoader())
                if let artist, let title {
                    let found = try await client.search(artist: artist, title: title)
                    log("búsqueda: \(found.count) resultados (\(lap())); primero: \(found.first.map { "\($0.artist) - \($0.title) #\($0.songId)" } ?? "-")")
                }
                let song = try await client.song(songId: songId)
                log("página: \(song.artist) - \(song.title), revisión \(song.revisionId), \(song.tracks.count) pistas (\(lap()))")
                for t in song.tracks { log("  pista \(t.index) «\(t.name)» \(t.instrument) afinación \(t.tuning.map(String.init(describing:)) ?? "-")") }
                let dir = out.appendingPathComponent("cache/\(song.songId)/\(song.revisionId)", isDirectory: true)
                let files = try await client.downloadTracks(song.tracks, to: dir)
                log("descargadas \(files.count)/\(song.tracks.count) pistas (\(lap()))")
                for t in song.tracks {
                    guard let f = files[t.partId] else { continue }
                    let data = try Data(contentsOf: f)
                    let c = try SongsterrTrackConverter.convert(data, isDrums: t.isDrums)
                    log("  \(t.name): \(data.count) bytes, \(c.bars.count) compases, \(c.notes.count) notas, \(c.hits.count) golpes, afinación \(c.tuning.map { $0.preset.rawValue } ?? "-")")
                }
                log("OK")
            } catch {
                log("ERROR: \(error)")
            }
            try? lines.joined(separator: "\n").write(to: out.appendingPathComponent("probe.txt"), atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }
}
#endif
