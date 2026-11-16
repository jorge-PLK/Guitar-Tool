import Foundation
import XCTest
@testable import StemKit

/// Banco real sin referencia, solo informa (sin diafonía ni umbrales):
///
///   TF_PAN_BENCH=<ruta a stems/guitar.wav>     se lee, nunca se escribe ahí
///   TF_PAN_BENCH_OUT=<directorio de salida>     por defecto Temp/bench/pan del repositorio
///
/// Escribe las pistas en `<salida>/stems/` y recortes de 30 s a su nivel real en `<salida>/clips/`
/// (`guitar.wav` y cada pista, del tramo con más energía a la vez en L y R).
final class PanSplitterBenchTests: XCTestCase {
    static let clipSeconds = 30

    func testBench() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["TF_PAN_BENCH"], !path.isEmpty else {
            throw XCTSkip("banco real desactivado (TF_PAN_BENCH sin definir)")
        }
        let input = URL(fileURLWithPath: path)
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let out = env["TF_PAN_BENCH_OUT"].map { URL(fileURLWithPath: $0) }
            ?? repo.appendingPathComponent("Temp/bench/pan")
        XCTAssertFalse(out.path.hasPrefix(input.deletingLastPathComponent().path), "no se escribe junto a la entrada")
        let stems = out.appendingPathComponent("stems", isDirectory: true)

        // Notas del centro (JSON `[{start, end, pitch}]`, segundos del tema) para la guía por notas.
        struct Note: Decodable { let start: Double, end: Double, pitch: Double }
        let notes = try env["TF_PAN_BENCH_NOTES"].map {
            try JSONDecoder().decode([Note].self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
                .map { PanCenterNote(start: $0.start, end: $0.end, midi: $0.pitch) }
        } ?? []
        print("BENCH \(notes.count) notas guía del centro")
        let t0 = Date()
        let result = try PanSplitter(centerNotes: notes).withoutGate().split(input: input, outputDirectory: stems)
        let dt = Date().timeIntervalSince(t0)
        let src = try AudioIO.readStereo(input)
        let minutes = Double(src.frameCount) / src.sampleRate / 60
        print("BENCH \(input.path)")
        print("BENCH \(String(format: "%.2f", minutes)) min en \(String(format: "%.1f", dt)) s; entrada RMS "
              + "\(String(format: "%.1f", result.inputLevel.rmsDB)) dBFS")
        for t in result.tracks {
            print("BENCH \(t.side.rawValue) guardada: \(String(format: "%+.1f", t.level.rmsDB - result.inputLevel.rmsDB)) dB "
                  + "frente a la entrada, " + PanSplitterT1Tests.confidenceText(t.confidence))
        }
        for d in result.discarded {
            print("BENCH \(d.side.rawValue) descartada (\(d.reason)): "
                  + "\(String(format: "%+.1f", d.level.rmsDB - result.inputLevel.rmsDB)) dB frente a la entrada")
        }
        print("BENCH parecido de envolventes " + PanSplitterT1Tests.similarityText(result))

        // Tramo de 30 s con más energía a la vez en L y R (por segundos, mínimo de las dos).
        let rate = Int(src.sampleRate)
        let seconds = src.frameCount / rate
        func perSecond(_ side: GuitarSide) throws -> [Double] {
            guard let t = result.tracks.first(where: { $0.side == side }) else { return [Double](repeating: 0, count: seconds) }
            let a = try AudioIO.readStereo(t.url)
            return (0..<seconds).map { s in
                PanSplitterT1Tests.energy(Array(a.left[s * rate..<(s + 1) * rate]))
                    + PanSplitterT1Tests.energy(Array(a.right[s * rate..<(s + 1) * rate]))
            }
        }
        let el = try perSecond(.left), er = try perSecond(.right), ec = try perSecond(.center)
        let ein: [Double] = (0..<seconds).map { s in
            PanSplitterT1Tests.energy(Array(src.left[s * rate..<(s + 1) * rate]))
                + PanSplitterT1Tests.energy(Array(src.right[s * rate..<(s + 1) * rate]))
        }
        let w = min(Self.clipSeconds, seconds)
        // Con C guardada, el tramo de más energía de C (el solo); si no, el de más energía a la vez en L y R.
        let useCenter = ec.reduce(0, +) > 0
        var best = 0, bestScore = -1.0
        for s in 0...(seconds - w) {
            let score = useCenter ? ec[s..<s + w].reduce(0, +)
                : min(el[s..<s + w].reduce(0, +), er[s..<s + w].reduce(0, +))
            if score > bestScore { best = s; bestScore = score }
        }
        func db(_ a: Double, _ b: Double) -> String { String(format: "%+.1f", 10 * log10(max(a, 1e-30) / max(b, 1e-30))) }
        let inside = best..<best + w
        let outside = (0..<seconds).filter { !inside.contains($0) }
        let sum = { (x: [Double], r: [Int]) in r.reduce(0) { $0 + x[$1] } }
        print("BENCH C frente a la entrada: en el tramo \(db(sum(ec, Array(inside)), sum(ein, Array(inside)))) dB, "
              + "fuera \(db(sum(ec, outside), sum(ein, outside))) dB")
        if let prev = env["TF_PAN_BENCH_PREV"] {
            // Misma medida con las pistas de una versión anterior (L y R) en el mismo tramo.
            for side in [GuitarSide.left, .right] {
                let old = try AudioIO.readStereo(URL(fileURLWithPath: prev).appendingPathComponent(side.fileName))
                let r = best * rate..<(best + w) * rate
                let eOld = PanSplitterT1Tests.energy(Array(old.left[r])) + PanSplitterT1Tests.energy(Array(old.right[r]))
                let eNew = sum(side == .left ? el : er, Array(inside))
                print("BENCH \(side.rawValue) en el tramo frente a la versión anterior: \(db(eNew, eOld)) dB")
            }
        }
        let clips = out.appendingPathComponent("clips", isDirectory: true)
        try FileManager.default.createDirectory(at: clips, withIntermediateDirectories: true)
        func clip(_ audio: StereoAudio, _ name: String) throws {
            let r = best * rate..<(best + w) * rate
            let url = clips.appendingPathComponent(name)
            try writeStereo(StereoAudio(left: Array(audio.left[r]), right: Array(audio.right[r]),
                                        sampleRate: audio.sampleRate), to: url)
            print("BENCH recorte \(url.path)")
        }
        guard let starts = env["TF_PAN_BENCH_CLIPS"] else {
            print("BENCH tramo de los recortes: \(best)–\(best + w) s")
            try clip(src, "guitar.wav")
            for t in result.tracks { try clip(try AudioIO.readStereo(t.url), t.side.fileName) }
            return
        }
        // Tramos pedidos (TF_PAN_BENCH_CLIPS=157,60): clips/<inicio>-<fin>s/, con las pistas anteriores
        // (TF_PAN_BENCH_PREV) como `prev-guitar_X.wav` para comparar.
        let prev = try env["TF_PAN_BENCH_PREV"].map { dir in
            try GuitarSide.allCases.map { (s: $0, a: try AudioIO.readStereo(URL(fileURLWithPath: dir).appendingPathComponent($0.fileName))) }
        } ?? []
        let tracks = try result.tracks.map { (s: $0.side, a: try AudioIO.readStereo($0.url)) }
        for s0 in starts.split(separator: ",").compactMap({ Int($0) }) {
            let r = s0 * rate..<min(src.frameCount, (s0 + Self.clipSeconds) * rate)
            let folder = clips.appendingPathComponent("\(s0)-\(s0 + Self.clipSeconds)s", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            func cut(_ a: StereoAudio, _ name: String) throws {
                try writeStereo(StereoAudio(left: Array(a.left[r]), right: Array(a.right[r]), sampleRate: a.sampleRate),
                                to: folder.appendingPathComponent(name))
            }
            try cut(src, "guitar.wav")
            let eIn = PanSplitterT1Tests.energy(Array(src.left[r])) + PanSplitterT1Tests.energy(Array(src.right[r]))
            var line = "BENCH recortes \(folder.path):"
            for t in tracks {
                try cut(t.a, t.s.fileName)
                let e = PanSplitterT1Tests.energy(Array(t.a.left[r])) + PanSplitterT1Tests.energy(Array(t.a.right[r]))
                line += " \(t.s.rawValue) \(db(e, eIn)) dB"
            }
            for p in prev {
                try cut(p.a, "prev-" + p.s.fileName)
                let e = PanSplitterT1Tests.energy(Array(p.a.left[r])) + PanSplitterT1Tests.energy(Array(p.a.right[r]))
                line += " · antes \(p.s.rawValue) \(db(e, eIn)) dB"
            }
            print(line + " (frente a la entrada)")
        }
    }
}
