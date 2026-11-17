import Foundation
import XCTest
@testable import TabKit

/// Puerta de la alineación con Benito Kamelas «Aquellas Cosas Que Solíamos Hacer» (Songsterr 3470719, revisión
/// 4550952): tablatura correcta a 170 BPM, el modelo de pulso a ~167. Importada el 17/11/2026 a las 21:20 dio +1 −0
/// pulsos, desfase 0 y 0 diferencias de estructura (`Temp/p5b/kamelas/summary4.txt`); tras los cambios de Tornado Of
/// Souls salían avisos de ±2–3 compases (97, 117, 129…) y 993 notas fuera del audio. Lee datos sin versionar de la
/// copia aislada (`P5BProjects`). Apagado por defecto:
///   TF_P5B_TESTS=1 Tools/test.sh TabKit SongsterrAlignmentKamelasTests
/// El detalle va a `Temp/p5b/kamelas/gate.txt` y la bisección a `Temp/p5b/kamelas/bisect.txt`.
final class SongsterrAlignmentKamelasTests: XCTestCase {
    static let project = P5BProjects.project("Benito Kamelas - Aquellas Cosas Que Solíamos Hacer")
    static let revision = project.appendingPathComponent("cache/songsterr/3470719/4550952")
    static let out = Fixture.repo.appendingPathComponent("Temp/p5b/kamelas")

    // Puerta: lo de la importación buena.
    static let maximumWarnings = 0
    /// Notas fuera del audio (fuera de la rejilla más en pulsos sobrantes, lo que avisa la app).
    static let maximumDroppedNotes = 10
    /// Pulsos que `prepare` puede tocar (la buena: +1 −0).
    static let maximumTouchedBeats = 4

    static func load() throws -> (tracks: [SongsterrTrack], beats: BeatTimes, audio: [SongsterrStemRole: [Float]]) {
        guard ProcessInfo.processInfo.environment["TF_P5B_TESTS"] == "1" else {
            throw XCTSkip("puerta de Benito Kamelas desactivada (TF_P5B_TESTS != 1)")
        }
        try XCTSkipUnless(FileManager.default.fileExists(atPath: revision.path), "falta \(revision.path)")
        let tracks = try P5BProjects.tracks(revision)
        let beats = try P5BProjects.beats(project)
        var audio: [SongsterrStemRole: [Float]] = [:]
        for (r, u) in P5BProjects.stems(project) { audio[r] = try MonoAudio.load(u, sampleRate: SemitoneSpectrogram.sampleRate) }
        return (tracks, beats, audio)
    }

    static func write(_ log: [String], _ name: String) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? log.joined(separator: "\n").write(to: out.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    static func dropped(_ a: SongsterrAlignment) -> (outside: Int, extra: Int) {
        (a.placements.map(\.droppedOutsideGrid).reduce(0, +), a.placements.map(\.droppedInExtraBeats).reduce(0, +))
    }

    func testKamelasAlignsWithPreparedBeats() throws {
        let (tracks, beats, audio) = try Self.load()
        var log: [String] = []
        defer { Self.write(log, "gate.txt") }
        let written = try XCTUnwrap(SongsterrBeatGrid.writtenTempo(tracks))
        let p = SongsterrBeatGrid.prepare(beats, writtenTempo: written)
        log.append("pulsos: tempo escrito \(Int(written)), detectado \(String(format: "%.2f", p.detectedTempo)), pliegue \(p.fold.rawValue), "
                   + "+\(p.insertedBeats) −\(p.removedBeats) (\(beats.beats.count) → \(p.beats.beats.count))")
        let a = try SongsterrAligner.align(tracks: tracks, beats: p.beats, audio: audio, soloSpans: [])
        log.append(SongsterrAlignmentTornadoTests.report("preparados", a))
        for w in a.structureWarnings {
            log.append("  aviso compás \(w.bar + 1) " + String(format: "%.1f s", w.time) + " pulsos \(w.beats)")
        }
        let (outside, extra) = Self.dropped(a)
        XCTAssertEqual(p.fold, .same)
        XCTAssertLessThanOrEqual(p.insertedBeats + p.removedBeats, Self.maximumTouchedBeats)
        XCTAssertLessThanOrEqual(a.structureWarnings.count, Self.maximumWarnings)
        XCTAssertLessThanOrEqual(outside + extra, Self.maximumDroppedNotes)
        XCTAssertEqual(a.offsetBeats, 0)
    }

    /// Las dos versiones que importó Jorge al ver el fallo (993 notas fuera, avisos en 97, 117, 129, 133, 145): las
    /// mismas notas que 3470719 con 14 compases más de riff de intro delante (desfase real −56 pulsos, fuera de los ±48
    /// del prototipo). Fuera del audio solo pueden quedar las notas de esos 14 compases.
    static let longerIntroRevisions = ["6187196/8080223", "3490233/4622859"]
    static let longerIntroOffset = -56
    /// Notas de los 14 compases de intro que la grabación no tiene (216 medidas el 17/11/2026).
    static let maximumIntroNotes = 230

    func testKamelasVersionsWithLongerIntro() throws {
        let (_, beats, audio) = try Self.load()
        for rev in Self.longerIntroRevisions {
            let tracks = try P5BProjects.tracks(Self.project.appendingPathComponent("cache/songsterr/\(rev)"))
            let written = try XCTUnwrap(SongsterrBeatGrid.writtenTempo(tracks))
            let p = SongsterrBeatGrid.prepare(beats, writtenTempo: written)
            let a = try SongsterrAligner.align(tracks: tracks, beats: p.beats, audio: audio, soloSpans: [])
            let (outside, extra) = Self.dropped(a)
            XCTAssertEqual(a.offsetBeats, Self.longerIntroOffset, rev)
            XCTAssertEqual(a.structureWarnings.count, 0, rev)
            XCTAssertEqual(extra, 0, rev)
            XCTAssertLessThanOrEqual(outside, Self.maximumIntroNotes, rev)
        }
    }

    /// Todas las versiones de la caché del proyecto con la configuración de la app (solo informe).
    func testKamelasAllCachedVersions() throws {
        let (_, beats, audio) = try Self.load()
        var log: [String] = []
        defer { Self.write(log, "versions.txt") }
        let fm = FileManager.default
        let cache = Self.project.appendingPathComponent("cache/songsterr")
        for song in try fm.contentsOfDirectory(atPath: cache.path).sorted() where !song.hasPrefix(".") {
            for rev in try fm.contentsOfDirectory(atPath: cache.appendingPathComponent(song).path).sorted() where !rev.hasPrefix(".") {
                let tracks = try P5BProjects.tracks(cache.appendingPathComponent("\(song)/\(rev)"))
                // Huella de cada compás tocado (alturas del bajo) para comparar estructuras entre versiones.
                if let bass = tracks.first(where: { $0.kind == .bass }) {
                    let byBar = Dictionary(grouping: bass.notes, by: \.bar)
                    let lines = bass.bars.indices.map { j in
                        "\(bass.bars[j].length) " + (byBar[j] ?? []).map { "\($0.pitch)" }.joined(separator: ",")
                    }
                    try? lines.joined(separator: "\n").write(to: Self.out.appendingPathComponent("bars-\(song).txt"),
                                                             atomically: true, encoding: .utf8)
                }
                guard let written = SongsterrBeatGrid.writtenTempo(tracks) else { log.append("\(song)/\(rev): sin tempo"); continue }
                let p = SongsterrBeatGrid.prepare(beats, writtenTempo: written)
                let a = try SongsterrAligner.align(tracks: tracks, beats: p.beats, audio: audio, soloSpans: [])
                log.append("\(song)/\(rev) \(tracks.count) pistas, tempo \(written) +\(p.insertedBeats) −\(p.removedBeats) "
                           + SongsterrAlignmentTornadoTests.report("app", a))
                for w in a.structureWarnings { log.append("  aviso compás \(w.bar + 1) " + String(format: "%.1f s", w.time) + " pulsos \(w.beats)") }
            }
        }
    }

    /// Bisección (solo informe): reglas de `prepare` y penalización por pulso de los bloques, encendidas y apagadas.
    func testKamelasBisect() throws {
        let (_, beats, audio) = try Self.load()
        var log: [String] = []
        defer { Self.write(log, "bisect.txt") }
        for rev in ["3470719/4550952", "6187196/8080223", "3490233/4622859"] {
        let tracks = try P5BProjects.tracks(Self.project.appendingPathComponent("cache/songsterr/\(rev)"))
        log.append("== \(rev)")
        let written = try XCTUnwrap(SongsterrBeatGrid.writtenTempo(tracks))
        log.append("periodo | reparto | penalización/pulso | +ins −quit | desfase | bloques | avisos | fuera | sobrantes | cambios")
        let raw = try SongsterrAligner.align(tracks: tracks, beats: beats, audio: audio, soloSpans: [])
        log.append("crudos: " + SongsterrAlignmentTornadoTests.report("crudos", raw))
        for period in [false, true] {
            for reg in [false, true] {
                let p = SongsterrBeatGrid.prepare(beats, writtenTempo: written,
                                                  options: .init(periodCheck: period, regularize: reg))
                for pen in [0, SongsterrAligner.blockChangePenaltyPerBeat] {
                    let a = try SongsterrAligner.align(tracks: tracks, beats: p.beats, audio: audio, soloSpans: [],
                                                       perBeatPenalty: pen)
                    let (o, e) = Self.dropped(a)
                    var changes: [String] = []
                    var last: Int?
                    for blk in a.blocks where last != blk.shift { changes.append("\(blk.firstBar):\(blk.shift)"); last = blk.shift }
                    log.append("\(period ? "sí" : "no") | \(reg ? "sí" : "no") | \(pen) | +\(p.insertedBeats) −\(p.removedBeats) | "
                               + "\(a.offsetBeats) | \(a.usesBlocks) | \(a.structureWarnings.count) | \(o) | \(e) | \(changes.joined(separator: " "))")
                }
            }
        }
        }
    }
}
