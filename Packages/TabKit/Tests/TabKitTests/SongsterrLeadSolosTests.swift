import Foundation
import XCTest
@testable import TabKit

/// Guitarra solista por secciones de solo (decisión de Jorge, 17/11/2026): en cada sección, la pista de guitarra de
/// Songsterr que mejor encaja con el stem solista (saliencia en la altura exacta, `SongsterrPairing.soloSalience`);
/// fuera de los solos, nada. Tema sintético de `SyntheticSong`.
final class SongsterrLeadSolosTests: XCTestCase {
    typealias S = SyntheticSong

    /// Pulsos cada 0,5 s desde 1 s y desfase 1: el compás b empieza en 1,5 + 2b s.
    static func barTime(_ b: Int) -> Double { 1.5 + 2 * Double(b) }
    /// Solo 1 en los compases 2–5 (lo toca la pista aguda), solo 2 en los 10–13 (la grave).
    static let solos = [barTime(2)...barTime(6), barTime(10)...barTime(14)]

    static let slots = [
        SongsterrStemSlot(id: "guitar-left", name: "Guitarra izq.", kind: .guitar, role: .guitarLeft),
        SongsterrStemSlot(id: "guitar-right", name: "Guitarra der.", kind: .guitar, role: .guitarRight),
        SongsterrStemSlot(id: "guitar-lead", name: "Guitarra solista", kind: .guitar, role: .guitarLead),
    ]

    /// Pista grave (0) en L, aguda (1) en R; el stem solista toca la aguda en el solo 1 y la grave en el 2, y nada más.
    func alignment(withLead: Bool = true) throws -> (SongsterrAlignment, [SongsterrTrack]) {
        let bars = 16
        let low = S.track(name: "Grave", kind: .guitar, bars: bars, seed: 51, pitches: 40...55)
        let high = S.track(name: "Aguda", kind: .guitar, bars: bars, seed: 52, pitches: 60...76)
        let beats = S.beats(count: 80)
        let line = BeatLine(beats)
        let truth = S.Truth(offset: 1, fine: 0, blockShifts: [0, 0, 0, 0])
        let duration = beats.last! + 2
        let lowEvents = S.events(low, truth: truth, line: line), highEvents = S.events(high, truth: truth, line: line)
        let left = S.render(lowEvents, duration: duration), right = S.render(highEvents, duration: duration)
        let lead = S.render(highEvents.filter { Self.solos[0].contains($0.time) && $0.time < Self.solos[0].upperBound }
                            + lowEvents.filter { Self.solos[1].contains($0.time) && $0.time < Self.solos[1].upperBound },
                            duration: duration)
        var audio: [SongsterrStemRole: [Float]] = [.guitarLeft: left, .guitarRight: right,
                                                   .guitar: zip(left, right).map { $0 + $1 }]
        if withLead { audio[.guitarLead] = lead }
        let a = try SongsterrAligner.align(tracks: [low, high], beats: BeatTimes(beats: beats, downbeats: []),
                                           audio: audio, soloSpans: Self.solos.reversed())
        return (a, [low, high])
    }

    func testEachSoloPicksItsOwnTrack() throws {
        let (a, _) = try alignment()
        for (k, p) in a.soloPairs.enumerated() {
            print("SINT solo \(k + 1) ← \(p.track.map(String.init) ?? "-") confianza \(p.confidence ?? .nan) margen \(p.margin ?? .nan) "
                  + "\(p.candidates.map { "\($0.track): \($0.similarity ?? .nan)" })")
        }
        XCTAssertEqual(a.soloPairs.map(\.span), Self.solos, "en orden de tiempo")
        XCTAssertEqual(a.soloPairs.map(\.track), [1, 0])
        // Margen claro frente a la otra pista en cada sección (la medida es la saliencia en la altura exacta, 0…1).
        for p in a.soloPairs { XCTAssertGreaterThan(p.margin ?? 0, 0.1) }
        XCTAssertEqual(a.soloPairs.map { $0.candidates.map(\.track) }, [[0, 1], [0, 1]])
        // El solista ya no tiene pareja de pista entera; L y R siguen con la suya.
        XCTAssertNil(a.pairs.first { $0.role == .guitarLead })
        XCTAssertEqual(a.pairs.first { $0.role == .guitarLeft }?.track, 0)
        XCTAssertEqual(a.pairs.first { $0.role == .guitarRight }?.track, 1)
        XCTAssertFalse(a.candidates.contains { $0.role == .guitarLead })

        let (noLead, _) = try alignment(withLead: false)
        XCTAssertEqual(noLead.soloPairs, [], "sin stem solista no hay secciones")
    }

    /// Plan y tablatura: la pista solista lleva solo las notas de cada solo, de la pista elegida en él, y se puede
    /// cambiar por solo.
    func testLeadTrackHoldsOnlySoloNotes() throws {
        let (a, tracks) = try alignment()
        var plan = SongsterrImportPlan(alignment: a, tracks: tracks, slots: Self.slots, songId: 1, revisionId: 2)
        let lead = try XCTUnwrap(plan.assignment(for: "guitar-lead"))
        XCTAssertNil(lead.track)
        XCTAssertEqual(lead.solos.map(\.track), [1, 0])
        XCTAssertEqual(lead.solos.map(\.confidence), a.soloPairs.map(\.confidence))
        XCTAssertTrue(lead.usesSongsterr)
        XCTAssertEqual(plan.automaticStemIDs, [])
        XCTAssertEqual(plan.soloChoices(for: "guitar-lead", solo: 1).map(\.track), [0, 1])
        XCTAssertEqual(plan.soloChoices(for: "guitar-lead", solo: 1).first?.similarity, a.soloPairs[1].candidates[0].similarity)
        XCTAssertFalse(plan.assign(stemID: "guitar-lead", track: 0), "el solista no lleva pistas enteras")

        func leadNotes(_ plan: SongsterrImportPlan) throws -> (TabTrack, TabScore) {
            let r = plan.build()
            return (try XCTUnwrap(r.score.tracks.first { $0.id == "guitar-lead" }), r.score)
        }
        func source(_ i: Int, _ span: ClosedRange<Double>) -> [Int] {
            let t = a.score.tracks.first { $0.id == SongsterrImportPlan.extraID(i) }!
            return t.notes.filter { let s = a.score.time(of: $0.start); return span.lowerBound <= s && s < span.upperBound }.map(\.pitch)
        }
        var (track, score) = try leadNotes(plan)
        let expected = source(1, Self.solos[0]) + source(0, Self.solos[1])
        XCTAssertGreaterThan(expected.count, 40)
        XCTAssertEqual(track.notes.map(\.pitch), expected)
        XCTAssertTrue(track.notes.allSatisfy { n in Self.solos.contains { $0.contains(score.time(of: n.start)) } })
        XCTAssertEqual(track.notes.map(\.id), Array(1...track.notes.count))
        XCTAssertEqual(track.name, "Guitarra solista")
        XCTAssertEqual(track.imported?.revisionId, 2)
        // Ninguna pista entera duplicada: L y R son las de Songsterr, el solista una fracción.
        let left = try XCTUnwrap(score.tracks.first { $0.id == "guitar-left" })
        XCTAssertLessThan(track.notes.count, left.notes.count / 2)

        // Cambio por solo: el 2 pasa a la aguda, y el 1 a ninguna.
        XCTAssertTrue(plan.assign(stemID: "guitar-lead", solo: 1, track: 1))
        XCTAssertEqual(plan.assignment(for: "guitar-lead")?.solos[1].confidence, a.soloPairs[1].candidates[1].similarity)
        XCTAssertTrue(plan.assign(stemID: "guitar-lead", solo: 0, track: nil))
        (track, score) = try leadNotes(plan)
        XCTAssertEqual(track.notes.map(\.pitch), source(1, Self.solos[1]))
        XCTAssertFalse(plan.assign(stemID: "guitar-lead", solo: 5, track: 0))

        // Sin pista en ningún solo: automática.
        XCTAssertTrue(plan.assign(stemID: "guitar-lead", solo: 1, track: nil))
        XCTAssertEqual(plan.automaticStemIDs, ["guitar-lead"])
        XCTAssertNil(plan.build().score.tracks.first { $0.id == "guitar-lead" })
    }

    /// Elección dentro de una sección: la de más parecido; empate, la de menor índice; sin medidas, ninguna.
    func testSoloPairRule() {
        let span = 10.0...20.0
        func c(_ t: Int, _ s: Double?) -> SongsterrPairCandidate { SongsterrPairCandidate(role: .guitarLead, track: t, similarity: s) }
        let p = SongsterrPairing.soloPair(span: span, candidates: [c(0, 0.3), c(1, 0.5), c(2, nil)])
        XCTAssertEqual(p.track, 1)
        XCTAssertEqual(p.confidence, 0.5)
        XCTAssertEqual(p.margin!, 0.2, accuracy: 1e-12)
        XCTAssertEqual(SongsterrPairing.soloPair(span: span, candidates: [c(3, 0.4), c(1, 0.4)]).track, 1)
        let none = SongsterrPairing.soloPair(span: span, candidates: [c(0, nil)])
        XCTAssertNil(none.track)
        XCTAssertNil(none.confidence)
        XCTAssertNil(SongsterrPairing.soloPair(span: span, candidates: [c(0, 0.4)]).margin)
    }

    /// El caso de El roce en sintético: en el solo, el stem solista lleva el solo (notas sueltas agudas) y, más bajos,
    /// los acordes de la rítmica que se cuelan por la separación. Por croma ganan los acordes (cubren más clases); por
    /// saliencia en la altura exacta gana el solo con margen.
    func testRhythmBleedDoesNotStealTheSolo() throws {
        let bars = 16
        // Rítmica: tríadas mayores a negras con la fundamental en 45–52 (índice 0); solista: corcheas sueltas en 64–84
        // (índice 1).
        var chords = S.track(name: "Acordes", kind: .guitar, bars: bars, seed: 61, pitches: 45...52,
                             step: SongsterrTrack.ticksPerQuarter)
        chords.notes = chords.notes.flatMap { n in
            var used = Set<Int>()
            return [0, 4, 7].map { d in
                var c = n
                c.pitch = n.pitch + d
                let s = S.guitarTuning.indices.last { !used.contains($0) && (0...24).contains(c.pitch - S.guitarTuning[$0]) }!
                used.insert(s)
                c.string = s + 1
                c.fret = c.pitch - S.guitarTuning[s]
                return c
            }
        }
        let solo = S.track(name: "Solo", kind: .guitar, bars: bars, seed: 62, pitches: 64...84)
        let beats = S.beats(count: 80)
        let line = BeatLine(beats)
        let truth = S.Truth(offset: 1, fine: 0, blockShifts: [0, 0, 0, 0])
        let duration = beats.last! + 2
        let span = Self.solos[0]
        func inSolo(_ t: Double) -> Bool { span.lowerBound <= t && t < span.upperBound }
        let chordEvents = S.events(chords, truth: truth, line: line), soloEvents = S.events(solo, truth: truth, line: line)
        // Cada voz de las tríadas por separado (`render` es monofónico).
        func voices(_ events: [(time: Double, pitch: Int)], gain: Float) -> [Float] {
            let byTime = Dictionary(grouping: events, by: \.time).values.map { $0.sorted { $0.pitch < $1.pitch } }
            var out = [Float](repeating: 0, count: Int(duration * S.sr))
            for k in 0..<3 {
                let v = S.render(byTime.compactMap { $0.indices.contains(k) ? $0[k] : nil }, duration: duration, gain: gain)
                for i in out.indices { out[i] += v[i] }
            }
            return out
        }
        let left = voices(chordEvents, gain: 0.2)
        let right = S.render(soloEvents.filter { !inSolo($0.time) }, duration: duration)
        let leadOnly = S.render(soloEvents.filter { inSolo($0.time) }, duration: duration)
        for (gain, minimumMargin, chromaFails) in Self.bleeds {
            let bleed = voices(chordEvents.filter { inSolo($0.time) }, gain: gain)
            let lead = zip(leadOnly, bleed).map { $0 + $1 }
            let guitar = (0..<left.count).map { left[$0] + right[$0] + lead[$0] }
            let audio: [SongsterrStemRole: [Float]] = [.guitarLeft: left, .guitarRight: right, .guitarLead: lead, .guitar: guitar]
            let a = try SongsterrAligner.align(tracks: [chords, solo], beats: BeatTimes(beats: beats, downbeats: []),
                                               audio: audio, soloSpans: [span])
            let p = try XCTUnwrap(a.soloPairs.first)
            // La medida de antes, croma, con los mismos tiempos alineados.
            let chroma = StemAnalysis(audio: audio).spectrum(.guitarLead).chroma(pool: SongsterrPairing.chromaPool)
            let old = (0..<2).map { SongsterrPairing.chromaSimilarity(chroma, notes: a.timedNotes[$0], spans: [span]) ?? .nan }
            print("SINT sangrado \(gain): croma acordes \(old[0]) solo \(old[1]); saliencia "
                  + "\(p.candidates.map { "\($0.track): \($0.similarity ?? .nan)" }) margen \(p.margin ?? .nan)")
            if chromaFails { XCTAssertGreaterThan(old[0], old[1], "por croma ganan los acordes (el fallo de El roce), sangrado \(gain)") }
            XCTAssertEqual(p.track, 1, "sangrado \(gain)")
            XCTAssertGreaterThan(p.margin ?? 0, minimumMargin, "sangrado \(gain)")
        }
    }

    /// (ganancia por voz de los acordes en el stem solista, margen mínimo del solo en saliencia 0…1, si por croma ganan
    /// los acordes). El solo va a 0,2. A 0,1 (−6 dB por voz, tres voces graves que en el CQT pesan como el solo) es el
    /// peor caso: margen 0,17 (croma: acordes 0,63, solo 0,47); a 0,05, 0,54 (croma 0,55 frente a 0,52); a 0,025, 0,77
    /// (ahí el croma ya acierta). En El roce real los acordes de Fito quedan a 0,036 de saliencia.
    static let bleeds: [(Float, Double, Bool)] = [(0.1, 0.1, true), (0.05, 0.3, true), (0.025, 0.5, false)]

    /// La medida en una rejilla a mano: la nota más fuerte de cada trama vale 1, las demás su fracción; menos de
    /// `minimumSoloNotes` notas en la sección, sin medida.
    func testSoloSalienceUsesExactPitch() {
        let frames = 2000, rate = SemitoneSpectrogram.sampleRate / Double(SemitoneSpectrogram.hop)
        var values = [Float](repeating: 0, count: SemitoneSpectrogram.binCount * frames)
        func set(_ midi: Int, _ v: Float) {
            for f in 0..<frames { values[(midi - SemitoneSpectrogram.lowestMIDI) * frames + f] = v }
        }
        set(76, 1)      // solo
        set(48, 0.25)   // acorde que se cuela
        set(52, 0.25)
        set(55, 0.25)
        let map = SalienceMap(values: values, frames: frames)
        let span = 1.0...5.0
        func notes(_ pitches: [Int], count: Int) -> [TimedNote] {
            (0..<count).flatMap { k in pitches.map { TimedNote(onset: 1 + 0.3 * Double(k), offset: 1.2 + 0.3 * Double(k), pitch: $0) } }
        }
        XCTAssertEqual(SongsterrPairing.soloSalience(map, notes: notes([76], count: 12), span: span)!, 1, accuracy: 1e-6)
        XCTAssertEqual(SongsterrPairing.soloSalience(map, notes: notes([48, 52, 55], count: 12), span: span)!, 0.25, accuracy: 1e-6)
        // Una octava por encima del solo no cuenta (en croma sería la misma clase).
        XCTAssertEqual(SongsterrPairing.soloSalience(map, notes: notes([88], count: 12), span: span)!, 0, accuracy: 1e-6)
        // Notas fuera de la sección no cuentan; con 9 dentro, sin medida.
        XCTAssertNil(SongsterrPairing.soloSalience(map, notes: notes([76], count: 9) + notes([76], count: 30).filter { $0.onset >= 5 },
                                                   span: span))
        XCTAssertGreaterThan(Double(frames) / rate, 5)
    }

    /// Plan sin secciones de solo: el solista queda en automática (no hereda una pista entera).
    func testNoSolosMeansAutomaticLead() {
        let tracks = [SongsterrImportPlanTests.track("G", .guitar, partId: 0)]
        let alignment = SongsterrImportPlanTests.alignment(
            tracks: tracks, pairs: [SongsterrImportPlanTests.pair(.guitarLead, 0, 0.9)])
        let plan = SongsterrImportPlan(alignment: alignment, tracks: tracks, slots: [Self.slots[2]], songId: 1, revisionId: 2)
        XCTAssertEqual(plan.assignment(for: "guitar-lead"), SongsterrAssignment(stemID: "guitar-lead", track: nil, confidence: nil))
        XCTAssertEqual(plan.automaticStemIDs, ["guitar-lead"])
    }
}
