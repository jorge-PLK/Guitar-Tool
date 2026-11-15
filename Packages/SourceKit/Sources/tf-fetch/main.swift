import Foundation
import SourceKit

// tf-fetch <enlace> --helpers <dir> --out <dir> [--pick N | --video <id>]
// Sin --pick lista los candidatos; con --pick N (desde 1) descarga y convierte; con --video <id> descarga ese vídeo
// sin repetir la búsqueda. Con un enlace de lista o de álbum imprime sus temas y no busca ni descarga nada.
// Imprime el tiempo de cada etapa. En <dir> de helpers:
// yt-dlp, deno y ffmpeg.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var link: String?, helpers: String?, out: String?, pick: Int?, video: String?
var args = Array(CommandLine.arguments.dropFirst())[...]
while let a = args.popFirst() {
    switch a {
    case "--helpers": helpers = args.popFirst()
    case "--out": out = args.popFirst()
    case "--pick": pick = args.popFirst().flatMap(Int.init)
    case "--video": video = args.popFirst()
    default: link = a
    }
}
guard let link, let helpers, let out else { fail("uso: tf-fetch <enlace> --helpers <dir> --out <dir> [--pick N | --video <id>]") }

let helpersDir = URL(fileURLWithPath: helpers, isDirectory: true)
let outDir = URL(fileURLWithPath: out, isDirectory: true)
let runner = SystemProcessRunner()
let http = URLSessionFetcher()
let ytDlpURL = helpersDir.appendingPathComponent("yt-dlp")
let denoURL = helpersDir.appendingPathComponent("deno")
let ffmpegURL = helpersDir.appendingPathComponent("ffmpeg")
for u in [ytDlpURL, denoURL, ffmpegURL] where !FileManager.default.isExecutableFile(atPath: u.path) {
    fail("falta el helper \(u.path)")
}

func fmt(_ s: Double?) -> String { s.map { String(format: "%.1f s", $0) } ?? "?" }

let importer = SourceImporter(
    ytDlp: YtDlpClient(executable: ytDlpURL, deno: denoURL, runner: runner),
    transcoder: AudioTranscoder(ffmpeg: ffmpegURL, runner: runner),
    http: http, spotify: SpotifyEmbedClient(http: http),
    workRoot: outDir.appendingPathComponent(".work"))
// Tiempos por etapa: cada cambio de estado cierra la etapa anterior.
var stageName: String?
var stageStart = Date()
@MainActor func closeStage() {
    if let n = stageName { print(String(format: "  [%@: %.1f s]", n, Date().timeIntervalSince(stageStart))) }
    stageName = nil
}
@MainActor func openStage(_ n: String) { closeStage(); stageName = n; stageStart = Date() }
importer.onStateChange = { state in
    switch state {
    case .resolving(.metadata): print("Leyendo metadatos…"); openStage("metadatos")
    case .resolving(.searching): print("Buscando en YouTube…"); openStage("búsqueda")
    case .downloading(.downloading, nil): if stageName != "descarga" { openStage("descarga") }
    case .downloading(.converting, _): print("Convirtiendo…"); openStage("conversión")
    case .candidates, .finished, .failed, .idle: closeStage()
    default: break
    }
}

if let list = try? PlaylistLink.parse(link) {
    let t0 = Date()
    let spotify = SpotifyEmbedClient(http: http)
    let ytDlp = YtDlpClient(executable: ytDlpURL, deno: denoURL, runner: runner)
    do {
        var name = "", rows: [(String, String, Double?)] = [], truncated = false
        switch list {
        case .spotify(let id), .spotifyAlbum(let id):
            let p: SpotifyPlaylist
            if case .spotifyAlbum = list { p = try await spotify.album(id: id) } else { p = try await spotify.playlist(id: id) }
            name = p.name
            truncated = p.mayBeTruncated
            rows = p.tracks.map { ($0.title, $0.artists.joined(separator: ", "), $0.durationSeconds) }
        case .youtube:
            let p = try await ytDlp.playlist(url: list.canonicalURL)
            name = p.title
            rows = p.entries.map { ($0.title, $0.channel ?? "?", $0.durationSeconds) }
        }
        print("\(name)  (\(rows.count) temas)")
        for (i, r) in rows.enumerated() { print("\(i + 1). \(r.0) | \(r.1) | \(fmt(r.2))") }
        if truncated { print("Aviso: llegaron 100 temas; Spotify puede haber cortado la lista.") }
        print(String(format: "  [lectura: %.1f s]", Date().timeIntervalSince(t0)))
        exit(0)
    } catch {
        fail("Error: \(error)")
    }
}

do {
    let r: ResolvedSource
    if let video {
        // Sin búsqueda: solo metadatos del tema (Spotify) o del vídeo, y descarga directa de `video`.
        r = try await importer.resolveWithoutSearch(link)
    } else {
        r = try await importer.resolve(link)
    }
    print("\(r.artist) - \(r.title)  (\(fmt(r.durationSeconds)))")
    var options: [Candidate] = []
    if let c = r.confirmation {
        options = [c]
        print("1. \(c.title) | \(c.channel ?? "?") | \(fmt(c.durationSeconds))")
    } else {
        for (i, rc) in r.candidates.enumerated() {
            let d = rc.difference.map { String(format: "%+.1f s", $0) } ?? "?"
            print("\(i + 1). \(rc.candidate.title) | \(rc.candidate.channel ?? "?") | \(fmt(rc.candidate.durationSeconds)) | \(d)\(rc.isClose ? " | cercano" : "")  \(rc.candidate.url.absoluteString)")
        }
        options = r.candidates.map(\.candidate)
        if r.noCloseCandidate { print("Aviso: ningún candidato cercano.") }
    }
    guard pick != nil || video != nil else { exit(0) }
    let chosen: Candidate
    if let video {
        guard let u = try? SourceLink.parse("https://www.youtube.com/watch?v=\(video)"), case .youtube = u else { fail("--video: id no válido") }
        chosen = options.first { $0.id == video } ?? Candidate(id: video, url: u.canonicalURL, title: r.title)
    } else {
        guard let pick, options.indices.contains(pick - 1) else { fail("--pick fuera de rango (1...\(options.count))") }
        chosen = options[pick - 1]
    }
    let imported = try await importer.download(candidate: chosen, title: r.title, artist: r.artist)
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let dest = outDir.appendingPathComponent("audio.wav")
    try? FileManager.default.removeItem(at: dest)
    try FileManager.default.copyItem(at: imported.wavURL, to: dest)
    if let art = imported.artworkURL {
        let d = outDir.appendingPathComponent(art.lastPathComponent)
        try? FileManager.default.removeItem(at: d)
        try FileManager.default.copyItem(at: art, to: d)
    }
    imported.cleanUp()
    for n in imported.notices { print("Aviso: \(n.message)") }
    print("OK \(dest.path)  códec \(imported.origin.codec)  yt-dlp \(imported.origin.ytDlpVersion)")
} catch {
    fail("Error: \(error)")
}
