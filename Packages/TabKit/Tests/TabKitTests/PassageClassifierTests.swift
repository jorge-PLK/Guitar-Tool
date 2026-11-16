import XCTest
@testable import TabKit

/// `PassageClassifier` con listas de notas sintéticas, sin modelo (mini-spec Fase 4, «Pruebas»).
/// 4/4 a 120 BPM: compás de 2 s, pulso de 0,5 s.
final class PassageClassifierTests: XCTestCase {
    static let bar = 2.0
    static let beat = 0.5

    enum Kind { case chords, powerChords, powerChords3, highPowerChords, line, octaveLine, doubleStops, held, stray, empty, arpeggio }

    /// Notas de un compás que empieza en `t0`.
    static func bar(_ kind: Kind, at t0: Double) -> [NoteEvent] {
        func hits(_ pitches: [Int], every step: Double, length: Double) -> [NoteEvent] {
            stride(from: t0, to: t0 + bar - 1e-9, by: step).flatMap { t in
                pitches.map { NoteEvent(start: t, end: t + length, pitch: $0, amplitude: 0.6) }
            }
        }
        let scale = [64, 66, 67, 69, 71, 72, 74, 76]
        func line(_ extra: (Int) -> [Int]) -> [NoteEvent] {
            (0..<8).flatMap { i in
                ([scale[i]] + extra(scale[i])).map {
                    NoteEvent(start: t0 + Double(i) * beat / 2, end: t0 + Double(i + 1) * beat / 2 - 0.02, pitch: $0, amplitude: 0.5)
                }
            }
        }
        switch kind {
        case .chords: return hits([40, 47, 52, 56], every: beat, length: 0.45)          // E mayor abierto, negras
        case .powerChords: return hits([40, 47], every: beat / 2, length: 0.22)          // E5, corcheas
        case .powerChords3: return hits([45, 52, 57], every: beat / 2, length: 0.22)     // A5 con octava
        case .highPowerChords: return hits([64, 71], every: beat, length: 0.45)          // E5 en el traste 12
        case .line: return line { _ in [] }
        case .octaveLine: return line { [$0 + 12] }                                       // armónico de octava
        case .doubleStops: return line { p in p % 2 == 0 ? [p + 4] : [] }                // terceras sueltas
        case .held: return [NoteEvent(start: t0 + 0.1, end: t0 + 1.9, pitch: 69, amplitude: 0.7)]
        case .stray: return [NoteEvent(start: t0 + 0.5, end: t0 + 0.6, pitch: 60, amplitude: 0.3)]
        case .arpeggio:                                                                    // E mayor arpegiado, cada nota deja sonar 0,5 s
            return [40, 47, 52, 56, 59, 56, 52, 47].enumerated().map {
                NoteEvent(start: t0 + Double($0.offset) * beat / 2, end: t0 + Double($0.offset) * beat / 2 + 0.5, pitch: $0.element, amplitude: 0.5)
            }
        case .empty: return []
        }
    }

    static func song(_ kinds: [Kind]) -> (notes: [NoteEvent], downbeats: [Double], duration: Double) {
        let notes = kinds.enumerated().flatMap { bar($1, at: Double($0) * bar) }
        return (notes, kinds.indices.map { Double($0) * bar }, Double(kinds.count) * bar)
    }

    static func classify(_ kinds: [Kind]) -> [GuitarPassage] {
        let s = song(kinds)
        return PassageClassifier.classify(notes: s.notes, downbeats: s.downbeats, duration: s.duration)
    }

    private func assertTiles(_ p: [GuitarPassage], _ duration: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.first?.start, 0, file: file, line: line)
        XCTAssertEqual(p.last?.end, duration, file: file, line: line)
        for (a, b) in zip(p, p.dropFirst()) { XCTAssertEqual(a.end, b.start, file: file, line: line) }
    }

    // MARK: Un papel

    func testChordsAreRhythm() {
        let p = Self.classify(Array(repeating: .chords, count: 4))
        XCTAssertEqual(p, [GuitarPassage(start: 0, end: 8, role: .rhythm, confidence: 1)])
    }

    func testSingleNoteLineIsLead() {
        let p = Self.classify(Array(repeating: .line, count: 4))
        XCTAssertEqual(p.map(\.role), [.lead])
        XCTAssertEqual(p[0].confidence, 1, accuracy: 1e-9)
        assertTiles(p, 8)
    }

    func testNoNotesIsSilent() {
        XCTAssertEqual(Self.classify(Array(repeating: .empty, count: 4)),
                       [GuitarPassage(start: 0, end: 8, role: .silent, confidence: 1)])
        // Un roce de 0,1 s por compás (5 % del compás) sigue siendo «sin guitarra».
        let stray = Self.classify(Array(repeating: .stray, count: 4))
        XCTAssertEqual(stray.map(\.role), [.silent])
        XCTAssertEqual(stray[0].confidence, 1 - 0.05 / PassageClassifier.silentActiveFraction, accuracy: 1e-9)
    }

    func testPowerChordsAreRhythm() {
        for kind in [Kind.powerChords, .powerChords3, .highPowerChords] {
            let p = Self.classify(Array(repeating: kind, count: 4))
            XCTAssertEqual(p.map(\.role), [.rhythm], "\(kind)")
            XCTAssertGreaterThan(p[0].confidence, 0.3, "\(kind)")
        }
    }

    /// En una pista que calla casi todo, una línea con su octava (armónico que Basic Pitch suele sacar con
    /// distorsión), una con terceras sueltas y una nota larga sostenida son un solo, no acordes.
    func testOctaveDoubledLineDoubleStopsAndHeldNoteAreLeadInSparseTrack() {
        for kind in [Kind.octaveLine, .doubleStops, .held] {
            let p = Self.classify(Array(repeating: .empty, count: 6) + Array(repeating: kind, count: 4)
                                  + Array(repeating: .empty, count: 6))
            XCTAssertEqual(p.map(\.role), [.silent, .lead, .silent], "\(kind)")
            XCTAssertEqual(p.map(\.start), [0, 12, 20], "\(kind)")
        }
    }

    // MARK: Contexto de la pista (solista es solo un solo de verdad)

    /// Rítmica continua con frases melódicas de 1–2 compases entre acordes: todo rítmica.
    func testContinuousRhythmWithShortPhrasesIsAllRhythm() {
        let p = Self.classify([.chords, .chords, .line, .chords, .chords, .line, .line, .chords, .chords, .chords,
                               .powerChords, .line, .powerChords, .powerChords])
        XCTAssertEqual(p.map(\.role), [.rhythm])
        assertTiles(p, 28)
    }

    /// Acompañamiento: arpegios, adornos y una frase de 3 compases en una pista que suena todo el tema → rítmica.
    func testAccompanimentWithArpeggiosAndFillsIsRhythm() {
        let kinds: [Kind] = [.chords, .chords, .chords, .chords, .arpeggio, .arpeggio, .arpeggio, .arpeggio,
                             .line, .line, .chords, .chords, .arpeggio, .arpeggio, .arpeggio, .octaveLine,
                             .doubleStops, .line, .chords, .chords]
        let p = Self.classify(kinds)
        XCTAssertEqual(p.map(\.role), [.rhythm], "\(p.map { ($0.start, $0.end, $0.role) })")
        assertTiles(p, 40)
    }

    /// Pista casi vacía (roces y fragmentos melódicos sueltos de 1–2 compases, como los restos de otra guitarra en
    /// la pista del centro) que entra con un solo, con un compás de respiro dentro: sin guitarra, solista (un solo
    /// pasaje), sin guitarra.
    func testSparseTrackWithSoloIsSilentLeadSilent() {
        let kinds: [Kind] = [.empty, .stray, .line, .empty, .stray, .empty, .empty, .empty,
                             .line, .line, .line, .empty, .line, .held, .line,
                             .empty, .stray, .empty, .line, .line, .stray, .empty, .empty, .empty]
        let p = Self.classify(kinds)
        XCTAssertEqual(p.map(\.role), [.silent, .lead, .silent])
        XCTAssertEqual(p.map(\.start), [0, 16, 30])
        XCTAssertEqual(p[1].end, 30)
    }

    /// Pista que suena todo el tema: un solo claro (línea aguda de notas sueltas, ≥ 4 compases) entre acordes sigue
    /// siendo solista; tras un silencio largo basta una línea menos clara.
    func testClearSoloInBusyTrackAndSoloAfterLongSilence() {
        let busy = Self.classify(Array(repeating: .chords, count: 6) + Array(repeating: .line, count: 6)
                                 + Array(repeating: .chords, count: 6))
        XCTAssertEqual(busy.map(\.role), [.rhythm, .lead, .rhythm])
        XCTAssertEqual(busy.map(\.start), [0, 12, 24])
        // Línea con octava: confianza de línea ≈ 0,53, por debajo de la «prueba muy fuerte» (0,7).
        let weak = Self.classify(Array(repeating: .chords, count: 8) + Array(repeating: .octaveLine, count: 4)
                                 + Array(repeating: .chords, count: 8))
        XCTAssertEqual(weak.map(\.role), [.rhythm])
        let afterSilence = Self.classify(Array(repeating: .chords, count: 8) + Array(repeating: .empty, count: 4)
                                         + Array(repeating: .octaveLine, count: 4) + Array(repeating: .chords, count: 8))
        XCTAssertEqual(afterSilence.map(\.role), [.rhythm, .silent, .lead, .rhythm])
    }

    // MARK: Histéresis

    /// Puntuaciones que oscilan dentro de la banda (0,43 / 0,60 alrededor de 0,5 ± 0,15) no cambian el papel del
    /// compás; una que la cruza con margen (0,0), sí.
    func testHysteresisKeepsRoleInsideBand() {
        let high = PassageClassifier.BarFeatures(activeFraction: 0.9, meanPolyphony: 2.0, threeOrMoreFraction: 0.6,
                                                 powerChordFraction: 0, density: 6, register: 60)
        let low = PassageClassifier.BarFeatures(activeFraction: 0.9, meanPolyphony: 1.6, threeOrMoreFraction: 0.5,
                                                powerChordFraction: 0, density: 6, register: 62)
        let clear = PassageClassifier.BarFeatures(activeFraction: 0.9, meanPolyphony: 1, threeOrMoreFraction: 0,
                                                  powerChordFraction: 0, density: 6, register: 72)
        XCTAssertEqual(PassageClassifier.rhythmScore(high), 0.5967, accuracy: 1e-3)
        XCTAssertEqual(PassageClassifier.rhythmScore(low), 0.4317, accuracy: 1e-3)
        let fromHigh = PassageClassifier.barVerdicts([high, low, high, low, high, low])
        XCTAssertEqual(Set(fromHigh.map(\.role)), [.rhythm])
        let fromLow = PassageClassifier.barVerdicts([low, high, low, high, low, high])
        XCTAssertEqual(Set(fromLow.map(\.role)), [.lead])
        XCTAssertEqual(PassageClassifier.barVerdicts([high, low, clear, low, high]).map(\.role),
                       [.rhythm, .rhythm, .lead, .lead, .lead])
    }

    // MARK: Medidas

    func testBarFeaturesOfChordsAndLine() {
        let chords = PassageClassifier.features(notes: Self.bar(.chords, at: 0), start: 0, end: 2)
        XCTAssertEqual(chords.meanPolyphony, 4, accuracy: 1e-9)
        XCTAssertEqual(chords.threeOrMoreFraction, 1, accuracy: 1e-9)
        XCTAssertEqual(chords.activeFraction, 0.9, accuracy: 1e-9)     // 4 × 0,45 s de 2 s
        XCTAssertEqual(chords.density, 8, accuracy: 1e-9)              // 16 notas en 2 s
        XCTAssertEqual(chords.register, 48.75, accuracy: 1e-9)
        let power = PassageClassifier.features(notes: Self.bar(.powerChords, at: 0), start: 0, end: 2)
        XCTAssertEqual(power.meanPolyphony, 2, accuracy: 1e-9)
        XCTAssertEqual(power.powerChordFraction, 1, accuracy: 1e-9)
        XCTAssertEqual(power.threeOrMoreFraction, 0, accuracy: 1e-9)
        let line = PassageClassifier.features(notes: Self.bar(.line, at: 0), start: 0, end: 2)
        XCTAssertEqual(line.meanPolyphony, 1, accuracy: 1e-9)
        XCTAssertEqual(line.threeOrMoreFraction, 0)
        XCTAssertEqual(line.powerChordFraction, 0)
    }

    func testPowerChordShapes() {
        XCTAssertTrue(PassageClassifier.isPowerChord([40, 47]))          // quinta
        XCTAssertTrue(PassageClassifier.isPowerChord([47, 40, 52]))      // quinta + octava, en cualquier orden
        XCTAssertTrue(PassageClassifier.isPowerChord([40, 52, 59]))      // octava + duodécima
        XCTAssertFalse(PassageClassifier.isPowerChord([40, 52]))         // octava sola
        XCTAssertFalse(PassageClassifier.isPowerChord([40, 44, 47]))     // tríada mayor
        XCTAssertFalse(PassageClassifier.isPowerChord([40, 47, 52, 59])) // 4 notas
        XCTAssertFalse(PassageClassifier.isPowerChord([40]))
    }

    /// Nota que cruza el borde de compás: cuenta en los dos, recortada a cada uno.
    func testNoteCrossingBarLineCountsInBoth() {
        let n = [NoteEvent(start: 1.5, end: 2.5, pitch: 60, amplitude: 0.5)]
        let a = PassageClassifier.features(notes: n, start: 0, end: 2)
        let b = PassageClassifier.features(notes: n, start: 2, end: 4)
        XCTAssertEqual(a.activeFraction, 0.25, accuracy: 1e-9)
        XCTAssertEqual(b.activeFraction, 0.25, accuracy: 1e-9)
        XCTAssertEqual(a.density, 0.5, accuracy: 1e-9)   // empieza en el primero
        XCTAssertEqual(b.density, 0, accuracy: 1e-9)
    }

    // MARK: Unión de compases

    /// Compases iguales seguidos → un pasaje, con los bordes en los pulsos fuertes.
    func testJoinsEqualBarsIntoPassagesAtDownbeats() {
        let p = Self.classify([.chords, .chords, .chords, .line, .line, .line, .line, .empty, .empty])
        XCTAssertEqual(p.map(\.role), [.rhythm, .lead, .silent])
        XCTAssertEqual(p.map(\.start), [0, 6, 14])
        XCTAssertEqual(p.map(\.end), [6, 14, 18])
        assertTiles(p, 18)
    }

    /// Un compás suelto entre dos del mismo papel se absorbe; la confianza baja (el compás discrepante cuenta 0).
    func testSingleBarIsAbsorbedIntoMatchingNeighbours() {
        let p = Self.classify([.chords, .chords, .chords, .line, .chords, .chords, .chords])
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p[0].role, .rhythm)
        XCTAssertEqual(p[0].confidence, 6.0 / 7.0, accuracy: 1e-9)
        assertTiles(p, 14)
    }

    /// Un compás suelto entre papeles distintos va al vecino más largo; el primero y el último van a su único vecino.
    func testSingleBarBetweenDifferentRolesGoesToLongerNeighbour() {
        let p = Self.classify([.chords, .chords, .chords, .empty, .line, .line, .line, .line])
        XCTAssertEqual(p.map(\.role), [.rhythm, .lead])
        XCTAssertEqual(p.map(\.end), [6, 16])
        let edges = Self.classify([.line, .chords, .chords, .chords, .empty])
        XCTAssertEqual(edges, [GuitarPassage(start: 0, end: 10, role: .rhythm, confidence: 3.0 / 5.0)])
    }

    /// Mínimo de 2 compases: pasajes de 2 se mantienen; ningún pasaje queda de 1 compás.
    func testTwoBarPassagesAreKeptAndNoneIsShorter() {
        let p = Self.classify([.chords, .chords, .empty, .empty, .chords, .chords])
        XCTAssertEqual(p.map(\.role), [.rhythm, .silent, .rhythm])
        XCTAssertEqual(p.map(\.start), [0, 4, 8])
        let mixed = Self.classify([.chords, .line, .empty, .chords, .line, .line, .empty, .chords, .chords, .line, .empty])
        XCTAssertFalse(mixed.contains { ($0.end - $0.start) < 2 * Self.bar - 1e-9 }, "\(mixed.map { ($0.start, $0.end, $0.role) })")
        assertTiles(mixed, 22)
    }

    /// Anacrusa de 0,5 s y cola de 0,6 s (menos de medio compás) se suman al compás vecino; una cola de 1,5 s es
    /// compás propio.
    func testPickupAndTailBars() {
        let short = PassageClassifier.bars(downbeats: [0.5, 2.5, 4.5, 6.5], duration: 7.1)
        XCTAssertEqual(short.map(\.start), [0, 2.5, 4.5])
        XCTAssertEqual(short.last?.end, 7.1)
        let long = PassageClassifier.bars(downbeats: [0, 2, 4, 6], duration: 7.5)
        XCTAssertEqual(long.map(\.start), [0, 2, 4, 6])
        XCTAssertTrue(PassageClassifier.bars(downbeats: [], duration: 0).isEmpty)
        XCTAssertEqual(PassageClassifier.bars(downbeats: [], duration: 5), [.init(start: 0, end: 5)])
    }
}
