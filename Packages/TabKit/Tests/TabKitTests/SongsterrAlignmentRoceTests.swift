import Foundation
import XCTest
@testable import TabKit

/// Puerta de la alineación con El roce frente al prototipo (`Probes/P5b-guitarra/eval_reference.py`, log en
/// `Temp/p5b/eval_reference.log`). Lee datos sin versionar (pistas de Songsterr en `Temp/p5b/songsterr/50624/`, stems y
/// pulsos del proyecto de El roce). Apagado por defecto:
///   TF_P5B_TESTS=1 Tools/test.sh TabKit SongsterrAlignmentRoceTests
final class SongsterrAlignmentRoceTests: XCTestCase {
    static let project = P5BProjects.project("El roce de tu cuerpo - Platero Y Tu")
    static let songsterr = Fixture.repo.appendingPathComponent("Temp/p5b/songsterr/50624")
    static let p5b = Fixture.repo.appendingPathComponent("Temp/p5b")
    /// Tramo del solo del prototipo (`SOLO`).
    static let solo = 158.3...183.52

    // Lo que dio el prototipo (log del 16/11/2026, 20:16).
    static let prototypeOffset = 0
    static let prototypeFine = 0.025
    /// Cambios de desfase por bloques: (primer compás tocado, base 0; negras sobre el global).
    static let prototypeChanges = [(0, 1), (4, -2), (72, 0), (168, 4)]
    /// F1 por nota de Basic Pitch del bajo frente a la referencia alineada (`reference_metrics.tsv`).
    static let prototypeBassF1 = 0.456

    // Tolerancias de la puerta.
    /// El ajuste fino puede salir distinto (el prototipo lo saca de la F de ataques de librosa en pasos de 5 ms).
    static let fineTolerance = 0.010
    /// F1 de control: la alineación Swift no puede quedar claramente por debajo de la del prototipo.
    static let f1Tolerance = 0.03
    /// Margen mínimo de Uoho sobre Fito en el solo (saliencia 0…1; salió 0,72). Con croma era −0,044.
    static let minimumSoloMargin = 0.3

    func testRoceMatchesPrototype() throws {
        guard ProcessInfo.processInfo.environment["TF_P5B_TESTS"] == "1" else {
            throw XCTSkip("puerta de El roce desactivada (TF_P5B_TESTS != 1)")
        }
        let fm = FileManager.default
        try XCTSkipUnless(fm.fileExists(atPath: Self.project.path), "falta \(Self.project.path)")
        try XCTSkipUnless(fm.fileExists(atPath: Self.songsterr.path), "falta \(Self.songsterr.path)")

        let tracks = try (0..<3).map { try SongsterrTrackConverter.convert(Data(contentsOf: Self.songsterr.appendingPathComponent("\($0).json"))) }
        let an = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.project.appendingPathComponent("cache/analysis.json"))) as! [String: Any]
        let b = (an["analysis"] as! [String: Any])["beats"] as! [String: Any]
        let beats = BeatTimes(beats: b["beats"] as! [Double], downbeats: b["downbeats"] as! [Double],
                              beatsPerBar: b["beatsPerBar"] as? Int)
        var stems: [SongsterrStemRole: URL] = [:]
        for r in SongsterrStemRole.allCases { stems[r] = Self.project.appendingPathComponent("stems/\(r.rawValue).wav") }

        let clock = ContinuousClock()
        let t0 = clock.now
        let a = try SongsterrAligner.align(tracks: tracks, beats: beats, stems: stems, soloSpans: [Self.solo])
        print("ROCE tiempo \(clock.now - t0)")
        print("ROCE pistas \(tracks.map { "\($0.name) \($0.kind) \($0.notes.count) notas" })")
        print("ROCE desfase \(a.offsetBeats) negras \(Int((a.fineOffset * 1000).rounded())) ms; saliencia global "
              + String(format: "%.3f bloques %.3f usa bloques %@", a.globalSalience, a.blockSalience, "\(a.usesBlocks)"))
        var changes: [(Int, Int)] = []
        for blk in a.blocks where changes.last?.1 != blk.shift { changes.append((blk.firstBar, blk.shift)) }
        print("ROCE cambios de bloque \(changes)")
        for w in a.structureWarnings {
            print("ROCE aviso compás tocado \(w.bar + 1) (Songsterr \(w.sourceMeasure + 1)) "
                  + String(format: "%.1f s", w.time) + " pulsos \(w.beats) compases \(w.wholeBars.map(String.init) ?? "-")")
        }
        for p in a.pairs {
            print("ROCE pareja \(p.role.rawValue) ← \(tracks[p.track].name) "
                  + String(format: "confianza %.3f margen %@", p.confidence, p.margin.map { String(format: "%.3f", $0) } ?? "-"))
        }
        for c in a.candidates {
            print("ROCE candidata \(c.role.rawValue) ← \(tracks[c.track].name) \(c.similarity.map { String(format: "%.3f", $0) } ?? "nil")")
        }
        print("ROCE extra \(a.extraTracks) colocación \(a.placements)")
        print("ROCE score: \(a.score.bars.count) compases, \(a.score.beats.count) pulsos, tempos \(Set(a.score.bars.map(\.tempo)).sorted()), "
              + "notas \(a.score.tracks.map(\.notes.count))")
        Self.printMeter("pulsos del análisis", a.score)
        Self.printOrnaments()

        // Bajo frente a la referencia del prototipo, nota a nota (misma altura, ataque más cercano).
        let bassIndex = tracks.firstIndex { $0.kind == .bass }!
        let swiftBass = a.timedNotes[bassIndex]
        let refURL = Self.p5b.appendingPathComponent("El_roce/reference_aligned_remfx_L.json")
        if let data = try? Data(contentsOf: refURL),
           let ref = try JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]], let bass = ref["bass"] {
            let protoOnsets = Dictionary(grouping: bass, by: { $0["pitch"] as! Int }).mapValues { $0.map { $0["onset"] as! Double }.sorted() }
            var deltas: [Double] = []
            for n in swiftBass {
                guard let list = protoOnsets[n.pitch], let near = list.min(by: { abs($0 - n.onset) < abs($1 - n.onset) }) else { continue }
                deltas.append(abs(near - n.onset))
            }
            deltas.sort()
            let within5 = Double(deltas.filter { $0 <= 0.005 }.count) / Double(max(1, deltas.count))
            print("ROCE bajo frente al prototipo: \(deltas.count) notas, mediana |Δ| \(String(format: "%.1f", 1000 * deltas[deltas.count / 2])) ms, "
                  + "≤ 5 ms \(String(format: "%.3f", within5)), p90 \(String(format: "%.1f", 1000 * deltas[deltas.count * 9 / 10])) ms")
        }

        // Control: F1 de Basic Pitch (notas de la sonda, `bass_basic_pitch.json`) frente a la referencia Swift.
        let bpURL = Self.p5b.appendingPathComponent("El_roce/bass_basic_pitch.json")
        let bp = (try JSONSerialization.jsonObject(with: Data(contentsOf: bpURL)) as! [String: Any])["notes"] as! [[String: Any]]
        let est = bp.map { TimedNote(onset: $0["onset"] as! Double, offset: $0["offset"] as! Double, pitch: $0["pitch"] as! Int) }
        let f1 = NoteF1.f1(reference: swiftBass, estimate: est, tolerance: 0.05)
        print("ROCE F1 Basic Pitch bajo: \(String(format: "%.3f", f1)) (prototipo \(Self.prototypeBassF1))")
        for df in stride(from: -0.04, through: 0.0401, by: 0.01) {
            let shifted = swiftBass.map { TimedNote(onset: $0.onset + df, offset: $0.offset + df, pitch: $0.pitch) }
            print("ROCE F1 con ajuste fino \(Int((1000 * (a.fineOffset + df)).rounded())) ms: "
                  + String(format: "%.3f", NoteF1.f1(reference: shifted, estimate: est, tolerance: 0.05)))
        }

        XCTAssertEqual(a.offsetBeats, Self.prototypeOffset)
        XCTAssertEqual(a.fineOffset, Self.prototypeFine, accuracy: Self.fineTolerance)
        XCTAssertTrue(a.usesBlocks)
        // Desde el compás tocado 5, el mismo camino que el prototipo. El primer bloque (6 notas por guitarra, pulsos
        // irregulares al principio) era un empate de saliencia (0 → 0,4997, +1 → 0,4974; el prototipo daba +1): desde
        // el 17/11/2026 toma el desfase del bloque siguiente (−2) por `SongsterrBeatGrid.leadingShifts`, como la
        // rejilla del metrónomo, y la intro cae en el primer acorde (3,51 s). Antes: [(0, 0), (4, −2), …] y un aviso
        // de 2 pulsos de menos en el compás 5 que ya no sale.
        func protoShift(_ bar: Int) -> Int { Self.prototypeChanges.last { $0.0 <= bar }!.1 }
        for blk in a.blocks where blk.firstBar >= 4 { XCTAssertEqual(blk.shift, protoShift(blk.firstBar), "bloque \(blk.firstBar)") }
        XCTAssertEqual(a.blocks[0].shift, protoShift(4))
        XCTAssertEqual(changes.map(\.0), [0, 72, 168])
        // Avisos: 2 pulsos de más antes del compás 73 (~100 s) y un compás (4 negras) de más antes del final a 130 BPM.
        XCTAssertEqual(a.structureWarnings.map(\.bar), [72, 168])
        XCTAssertEqual(a.structureWarnings.map(\.beats), [2, 4])
        XCTAssertEqual(a.structureWarnings.map(\.wholeBars), [nil, 1])
        // Parejas del prototipo en L, R y bajo (el solista va por secciones de solo, abajo).
        let pair = Dictionary(uniqueKeysWithValues: a.pairs.map { ($0.role, tracks[$0.track].name) })
        XCTAssertEqual(pair[.guitarLeft], "Fito")
        XCTAssertEqual(pair[.guitarRight], "Uoho")
        XCTAssertEqual(pair[.bass], "Mongol")
        XCTAssertGreaterThanOrEqual(f1, Self.prototypeBassF1 - Self.f1Tolerance)
        // Solo 1 (2:38): lo toca Uoho (Jorge, de oído, 17/11/2026). Por croma salía Fito 0,393 frente a Uoho 0,349;
        // por saliencia en la altura exacta, Uoho 0,755 frente a Fito 0,036.
        for p in a.soloPairs {
            print("ROCE solo \(p.span) ← \(p.track.map { tracks[$0].name } ?? "-") "
                  + String(format: "confianza %.3f margen %.3f ", p.confidence ?? .nan, p.margin ?? .nan)
                  + p.candidates.map { "\(tracks[$0.track].name) \($0.similarity.map { String(format: "%.3f", $0) } ?? "nil")" }.joined(separator: ", "))
        }
        XCTAssertEqual(a.soloPairs.map { $0.track.map { tracks[$0].name } }, ["Uoho"])
        XCTAssertGreaterThanOrEqual(a.soloPairs.first?.margin ?? 0, Self.minimumSoloMargin)

        // Como en la app: pulsos preparados con el tempo escrito (`SongsterrBeatGrid.prepare`).
        let written = try XCTUnwrap(SongsterrBeatGrid.writtenTempo(tracks))
        let prepared = SongsterrBeatGrid.prepare(beats, writtenTempo: written)
        let ap = try SongsterrAligner.align(tracks: tracks, beats: prepared.beats, stems: stems, soloSpans: [Self.solo])
        Self.printMeter("pulsos preparados", ap.score)
        for (name, score) in [("análisis", a.score), ("preparados", ap.score)] {
            // Intro en 4/4 desde el primer acorde (3,51 s) y tempo escrito 172 salvo el final de Songsterr a 130.
            let firstChord = try XCTUnwrap(Self.firstGuitarOnset(score))
            XCTAssertEqual(firstChord, Self.firstChordTime, accuracy: Self.firstChordTolerance, name)
            let bar = try XCTUnwrap(score.bars.firstIndex { abs($0.start - firstChord) < 1e-6 }, name)
            XCTAssertTrue(score.bars[bar..<(bar + 8)].allSatisfy { $0.beatCount == 4 && $0.beatUnit == 4 }, name)
            let tempos = Dictionary(grouping: score.bars, by: \.tempo).mapValues(\.count)
            XCTAssertEqual(tempos.max { $0.value < $1.value }?.key, written, name)
            XCTAssertFalse(score.bars.contains { $0.tempo == 130 }, "130 no cuadra con la batería (±15 %): \(name)")
            // Los pulsos de más de la grabación van en compás aparte (como en el metrónomo): 4/4 + 2/4 y 4/4 + 4/4.
            XCTAssertFalse(score.bars.contains { $0.beatCount > 4 }, name)
        }
    }

    /// Primer acorde de la intro en el audio (rejilla de Songsterr, `SongsterrBeatGridRoceTests`).
    static let firstChordTime = 3.514
    /// La tablatura va con los pulsos del modelo más el ajuste fino (tramas de 20 ms), no con la rejilla anclada.
    static let firstChordTolerance = 0.040

    static func firstGuitarOnset(_ score: TabScore) -> Double? {
        score.tracks.filter { $0.kind == .guitar }.compactMap { $0.notes.first.map { score.time(of: $0.start) } }.min()
    }

    static func printMeter(_ name: String, _ score: TabScore) {
        let head = score.bars.prefix(8).map { String(format: "%.2f s ", $0.start) + "\($0.beatCount)/\($0.beatUnit) ♩=\(Int($0.tempo))" }
        print("ROCE [\(name)] primeros compases: \(head.joined(separator: " · "))")
        var runs: [String] = []
        var last = -1.0
        for (i, b) in score.bars.enumerated() where b.tempo != last {
            runs.append("c\(i + 1) " + String(format: "%.1f s", b.start) + " ♩=\(Int(b.tempo))")
            last = b.tempo
        }
        let meters = Dictionary(grouping: score.bars, by: { "\($0.beatCount)/\($0.beatUnit)" }).mapValues(\.count)
        print("ROCE [\(name)] tramos de tempo: \(runs.joined(separator: ", ")); compases \(meters.sorted { $0.key < $1.key })")
        print("ROCE [\(name)] primer ataque de guitarra " + (firstGuitarOnset(score).map { String(format: "%.3f s", $0) } ?? "-"))
    }

    /// Desglose de adornos de las pistas del tema en la caché del proyecto (las 4 de la app, con la batería).
    static func printOrnaments() {
        let dir = project.appendingPathComponent("cache/songsterr/50624/6707291")
        var total: [SongsterrOrnament: Int] = [:]
        var notes = 0, withOrnaments = 0
        for i in 0..<8 {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("\(i).json")),
                  let t = try? SongsterrTrackConverter.convert(data) else { continue }
            let list = SongsterrOrnament.allCases.compactMap { o in t.report.ornaments[o].map { "\(o.rawValue) \($0)" } }
            print("ROCE adornos «\(t.name)» \(t.kind): \(t.notes.count + t.hits.count) notas, \(t.report.notesWithOrnaments) con adorno: \(list.joined(separator: ", "))")
            for (o, n) in t.report.ornaments { total[o, default: 0] += n }
            notes += t.notes.count + t.hits.count
            withOrnaments += t.report.notesWithOrnaments
        }
        print("ROCE adornos total: \(notes) notas, \(withOrnaments) con adorno: "
              + SongsterrOrnament.allCases.compactMap { o in total[o].map { "\(o.rawValue) \($0)" } }.joined(separator: ", "))
    }
}

/// F1 por nota como `mir_eval.transcription` sin final: misma altura y ataque a ≤ `tolerance`. Para cada altura, el
/// emparejamiento voraz por orden de tiempo es máximo (todas las ventanas miden lo mismo).
enum NoteF1 {
    static func f1(reference: [TimedNote], estimate: [TimedNote], tolerance: Double) -> Double {
        guard !reference.isEmpty, !estimate.isEmpty else { return 0 }
        let r = Dictionary(grouping: reference.map(\.onset).indices, by: { reference[$0].pitch })
        let e = Dictionary(grouping: estimate.indices, by: { estimate[$0].pitch })
        var matched = 0
        for (pitch, ri) in r {
            guard let ei = e[pitch] else { continue }
            let a = ri.map { reference[$0].onset }.sorted(), b = ei.map { estimate[$0].onset }.sorted()
            var i = 0, j = 0
            while i < a.count && j < b.count {
                if abs(a[i] - b[j]) <= tolerance + 1e-9 { matched += 1; i += 1; j += 1 }
                else if a[i] < b[j] { i += 1 } else { j += 1 }
            }
        }
        let p = Double(matched) / Double(estimate.count), rc = Double(matched) / Double(reference.count)
        return p + rc == 0 ? 0 : 2 * p * rc / (p + rc)
    }
}
