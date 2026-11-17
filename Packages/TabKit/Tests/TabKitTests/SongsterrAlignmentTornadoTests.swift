import Foundation
import XCTest
@testable import TabKit

/// Puerta de la alineación con Megadeth «Tornado Of Souls» (Songsterr 12824, revisión 10230610): un solo tempo
/// escrito (196) y 317 s a ese tempo frente a 318 s de audio, pero el modelo de pulso marca los estribillos a
/// mitad de tempo (40–60 s y 90–110 s a ~100 BPM) y el «Break» a corcheas sueltas (130–150 s, 250–260 s). Lee datos sin
/// versionar (pistas en la caché del proyecto, stems y pulsos del análisis). Apagado por defecto:
///   TF_P5B_TESTS=1 Tools/test.sh TabKit SongsterrAlignmentTornadoTests
/// El detalle va a `Temp/p5b/tornado/gate.txt`.
final class SongsterrAlignmentTornadoTests: XCTestCase {
    static let project = P5BProjects.project("Megadeth - Tornado Of Souls")
    static let revision = project.appendingPathComponent("cache/songsterr/12824/10230610")
    static let out = Fixture.repo.appendingPathComponent("Temp/p5b/tornado/gate.txt")

    // Puerta. Antes del arreglo (17/11/2026): pulsos preparados con tramos a 97 y 375 BPM; desfase 6–7, 19–33 avisos,
    // 419 notas en pulsos sobrantes y saltos de bloque de ±8–15 pulsos.
    /// BPM mediano de cada ventana de 10 s de los pulsos preparados frente al del tema.
    static let windowTempoTolerance = 0.06
    /// Avisos de estructura: los que quedan son pasos de ±1 pulso donde el modelo cambia de fase (medio pulso) y no se
    /// puede repartir.
    static let maximumWarnings = 15
    static let maximumExtraBeatNotes = 120
    /// Ningún bloque se aparta más que esto de la mediana de sus 5 vecinos (salto de 2 compases y vuelta).
    static let maximumBlockOutlier = 4

    static func load() throws -> (tracks: [SongsterrTrack], beats: BeatTimes, stems: [SongsterrStemRole: URL]) {
        guard ProcessInfo.processInfo.environment["TF_P5B_TESTS"] == "1" else {
            throw XCTSkip("puerta de Tornado desactivada (TF_P5B_TESTS != 1)")
        }
        try XCTSkipUnless(FileManager.default.fileExists(atPath: revision.path), "falta \(revision.path)")
        let tracks = try (0..<6).map { try SongsterrTrackConverter.convert(Data(contentsOf: revision.appendingPathComponent("\($0).json"))) }
        let an = try JSONSerialization.jsonObject(with: Data(contentsOf: project.appendingPathComponent("cache/analysis.json"))) as! [String: Any]
        let b = (an["analysis"] as! [String: Any])["beats"] as! [String: Any]
        let beats = BeatTimes(beats: b["beats"] as! [Double], downbeats: b["downbeats"] as! [Double],
                              beatsPerBar: b["beatsPerBar"] as? Int)
        var stems: [SongsterrStemRole: URL] = [:]
        for r in SongsterrStemRole.allCases {
            let u = project.appendingPathComponent("stems/\(r.rawValue).wav")
            if FileManager.default.fileExists(atPath: u.path) { stems[r] = u }
        }
        return (tracks, beats, stems)
    }

    func testTornadoAlignsWithPreparedBeats() throws {
        let (tracks, beats, stems) = try Self.load()
        var log: [String] = []
        defer {
            try? FileManager.default.createDirectory(at: Self.out.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? log.joined(separator: "\n").write(to: Self.out, atomically: true, encoding: .utf8)
        }
        let ref = try XCTUnwrap(SongsterrBeatGrid.referenceBars(tracks))
        let tpq = Double(SongsterrTrack.ticksPerQuarter)
        let tabSeconds = ref.map { Double($0.length) / tpq * 60 / $0.tempo }.reduce(0, +)
        log.append("tablatura \(ref.count) compases, tempos \(Set(ref.map(\.tempo)).sorted()), \(String(format: "%.1f", tabSeconds)) s a tempo escrito")
        log.append("pulsos del análisis \(beats.beats.count) " + Self.profile(beats.beats).map { String(format: "%.0f:%.0f", $0.0, $0.1) }.joined(separator: " "))

        let written = try XCTUnwrap(SongsterrBeatGrid.writtenTempo(tracks))
        let prepared = SongsterrBeatGrid.prepare(beats, writtenTempo: written)
        let windows = Self.profile(prepared.beats.beats)
        log.append("preparados \(prepared.beats.beats.count) +\(prepared.insertedBeats) −\(prepared.removedBeats) "
                   + windows.map { String(format: "%.0f:%.0f", $0.0, $0.1) }.joined(separator: " "))
        for (t, bpm) in windows where t < 310 {  // la última ventana tiene la cola del tema
            XCTAssertEqual(bpm / prepared.detectedTempo, 1, accuracy: Self.windowTempoTolerance, "ventana \(t) s: \(bpm) BPM")
        }

        let raw = try SongsterrAligner.align(tracks: tracks, beats: beats, stems: stems)
        log.append(Self.report("crudos", raw))
        let a = try SongsterrAligner.align(tracks: tracks, beats: prepared.beats, stems: stems)
        log.append(Self.report("preparados", a))
        for w in a.structureWarnings {
            log.append("  aviso compás \(w.bar + 1) " + String(format: "%.1f s", w.time) + " pulsos \(w.beats)")
        }
        let extra = a.placements.map(\.droppedInExtraBeats).reduce(0, +)
        XCTAssertLessThanOrEqual(a.structureWarnings.count, Self.maximumWarnings)
        XCTAssertLessThanOrEqual(extra, Self.maximumExtraBeatNotes)
        XCTAssertEqual(a.placements.map(\.droppedOutsideGrid).reduce(0, +), 0)
        let shifts = a.blocks.map(\.shift)
        for b in shifts.indices {
            let near = shifts[max(0, b - 2)...min(shifts.count - 1, b + 2)].sorted()
            XCTAssertLessThanOrEqual(abs(shifts[b] - near[near.count / 2]), Self.maximumBlockOutlier, "bloque \(b * 4)")
        }
    }

    static func report(_ name: String, _ a: SongsterrAlignment) -> String {
        let outside = a.placements.map(\.droppedOutsideGrid).reduce(0, +)
        let extra = a.placements.map(\.droppedInExtraBeats).reduce(0, +)
        var changes: [String] = []
        var last: Int?
        for blk in a.blocks where last != blk.shift { changes.append("\(blk.firstBar):\(blk.shift)"); last = blk.shift }
        return "[\(name)] desfase \(a.offsetBeats) fino \(Int((1000 * a.fineOffset).rounded())) ms saliencia "
            + String(format: "%.3f/%.3f", a.globalSalience, a.blockSalience) + " bloques \(a.usesBlocks) avisos \(a.structureWarnings.count) "
            + "fuera \(outside) sobrantes \(extra) cambios \(changes.joined(separator: " "))"
    }

    /// (inicio, BPM mediano) cada 10 s.
    static func profile(_ bt: [Double]) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        var t0 = 0.0
        while t0 < (bt.last ?? 0) {
            let ibi = zip(bt.dropFirst(), bt).filter { $0.1 >= t0 && $0.1 < t0 + 10 }.map { $0.0 - $0.1 }.sorted()
            if !ibi.isEmpty { out.append((t0, 60 / ibi[ibi.count / 2])) }
            t0 += 10
        }
        return out
    }
}
