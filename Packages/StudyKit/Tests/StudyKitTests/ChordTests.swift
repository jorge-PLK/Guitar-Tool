import XCTest
@testable import StudyKit

final class ChordLabelTests: XCTestCase {
    func testIndexNameRoundTrip() throws {
        XCTAssertEqual(ChordLabel(index: 0)?.labName, "C:min")
        XCTAssertEqual(ChordLabel(index: 1)?.labName, "C:maj")
        XCTAssertEqual(ChordLabel(index: 168)?.labName, "X")
        XCTAssertEqual(ChordLabel(index: 169)?.labName, "N")
        XCTAssertNil(ChordLabel(index: 170))
        XCTAssertNil(ChordLabel(index: -1))
        for i in 0...169 {
            let l = try XCTUnwrap(ChordLabel(index: i))
            XCTAssertEqual(ChordLabel(labName: l.labName)?.index, i, "i=\(i)")
        }
        let names = Set((0...169).compactMap { ChordLabel(index: $0)?.labName })
        XCTAssertEqual(names.count, 170)
    }

    func testReadableNames() {
        XCTAssertEqual(ChordLabel(labName: "F#:min7")?.name, "F#m7")
        XCTAssertEqual(ChordLabel(labName: "C:hdim7")?.name, "Cø7")
        XCTAssertEqual(ChordLabel(labName: "C:minmaj7")?.name, "Cm(maj7)")
        XCTAssertEqual(ChordLabel(labName: "A#:maj")?.name, "A#")
        XCTAssertEqual(ChordLabel(labName: "A#:maj")?.name(preferFlats: true), "Bb")
        XCTAssertEqual(ChordLabel(labName: "Db:dim7")?.name, "C#°7")
        XCTAssertEqual(ChordLabel(labName: "G")?.labName, "G:maj")
        XCTAssertNil(ChordLabel(labName: "H:maj"))
        XCTAssertNil(ChordLabel(labName: "C:foo"))
        XCTAssertEqual(ChordLabel(index: 14 * 9 + 6)?.name, "Am7")
    }

    func testTransposeWrapsAround() throws {
        for i in 0..<168 {
            let l = try XCTUnwrap(ChordLabel(index: i))
            XCTAssertEqual(l.transposed(by: 12), l)
            XCTAssertEqual(l.transposed(by: 5).transposed(by: -5), l)
            XCTAssertEqual(l.transposed(by: -7).root, ((l.root! - 7) % 12 + 12) % 12)
            XCTAssertEqual(l.transposed(by: 3).quality, l.quality)
        }
        XCTAssertEqual(ChordLabel.noChord.transposed(by: 4), .noChord)
        XCTAssertEqual(ChordLabel.unknown.transposed(by: 4), .unknown)
    }
}

final class ChordShapesTests: XCTestCase {
    func testAll168HaveSixStringShapeWithinFourFrets() throws {
        for i in 0..<168 {
            let l = try XCTUnwrap(ChordLabel(index: i))
            let s = try XCTUnwrap(ChordShapes.shape(for: l), l.name)
            XCTAssertEqual(s.frets.count, 6, l.name)
            let pressed = s.frets.compactMap { $0 }.filter { $0 > 0 }
            if let lo = pressed.min(), let hi = pressed.max() {
                XCTAssertLessThanOrEqual(hi - lo + 1, 4, "\(l.name) \(s.frets)")
            }
            XCTAssertGreaterThanOrEqual(s.frets.compactMap { $0 }.count, 3, l.name)
        }
        XCTAssertNil(ChordShapes.shape(for: .noChord))
        XCTAssertNil(ChordShapes.shape(for: .unknown))
    }

    func testShapesSoundOnlyChordTonesAndIncludeRoot() throws {
        for i in 0..<168 {
            let l = try XCTUnwrap(ChordLabel(index: i))
            let s = try XCTUnwrap(ChordShapes.shape(for: l))
            let sounded = s.pitchClasses.compactMap { $0 }
            let tones = Set(l.pitchClasses)
            XCTAssertTrue(Set(sounded).isSubset(of: tones), "\(l.name) \(s.frets) -> \(sounded)")
            XCTAssertTrue(sounded.contains(l.root!), "\(l.name) sin raíz")
            // Todas las notas del acorde salvo quinta omitida en los de 3 notas no se exige; la tercera/cuarta sí.
            XCTAssertTrue(Set(sounded).count >= 3, l.name)
        }
    }

    func testKnownOpenShapes() throws {
        func frets(_ n: String) throws -> [Int?] {
            try XCTUnwrap(ChordShapes.shape(for: XCTUnwrap(ChordLabel(labName: n)))).frets
        }
        XCTAssertEqual(try frets("C:maj"), [nil, 3, 2, 0, 1, 0])
        XCTAssertEqual(try frets("E:min"), [0, 2, 2, 0, 0, 0])
        XCTAssertEqual(try frets("A:min"), [nil, 0, 2, 2, 1, 0])
        XCTAssertEqual(try frets("F:maj"), [1, 3, 3, 2, 1, 1])
        XCTAssertEqual(try frets("F:maj7"), [nil, nil, 3, 2, 1, 0])
        let f = try XCTUnwrap(ChordShapes.shape(for: XCTUnwrap(ChordLabel(labName: "F:maj"))))
        XCTAssertEqual(f.barre, ChordShape.Barre(fret: 1, fromString: 6, toString: 1))
    }

    func testCapoShiftsShape() throws {
        let d = try XCTUnwrap(ChordLabel(labName: "D:maj"))
        let c = try XCTUnwrap(ChordLabel(labName: "C:maj"))
        XCTAssertEqual(ChordShapes.shape(for: d, capo: 2), ChordShapes.shape(for: c))
        XCTAssertNotEqual(ChordShapes.shape(for: d, capo: 2), ChordShapes.shape(for: d))
        XCTAssertEqual(ChordShapes.shape(for: d, capo: 0), ChordShapes.shape(for: d))
        XCTAssertNil(ChordShapes.shape(for: .noChord, capo: 3))
        // Con capo 12 vuelve a la misma forma.
        XCTAssertEqual(ChordShapes.shape(for: d, capo: 12), ChordShapes.shape(for: d))
    }
}

final class ChordTimelineTests: XCTestCase {
    private func seg(_ s: Double, _ e: Double, _ i: Int) -> ChordSegment { ChordSegment(start: s, end: e, index: i) }
    private func ov(_ s: Double, _ e: Double, _ i: Int) -> ChordOverride { ChordOverride(start: s, end: e, index: i) }

    func testNoOverridesKeepsDetectedAndMergesAdjacentEqual() {
        let det = [seg(0, 1, 1), seg(1, 2, 1), seg(2, 3, 5)]
        XCTAssertEqual(ChordTimeline.effective(detected: det, overrides: []), [seg(0, 2, 1), seg(2, 3, 5)])
    }

    func testPartialOverrideSplits() {
        let r = ChordTimeline.effective(detected: [seg(0, 4, 1)], overrides: [ov(1, 2, 7)])
        XCTAssertEqual(r, [seg(0, 1, 1), seg(1, 2, 7), seg(2, 4, 1)])
    }

    func testExactOverrideReplaces() {
        let r = ChordTimeline.effective(detected: [seg(0, 2, 1), seg(2, 4, 3)], overrides: [ov(2, 4, 9)])
        XCTAssertEqual(r, [seg(0, 2, 1), seg(2, 4, 9)])
    }

    func testOverrideSpanningSeveralSegments() {
        let det = [seg(0, 2, 1), seg(2, 4, 3), seg(4, 6, 5)]
        let r = ChordTimeline.effective(detected: det, overrides: [ov(1, 5, 7)])
        XCTAssertEqual(r, [seg(0, 1, 1), seg(1, 5, 7), seg(5, 6, 5)])
    }

    func testOverlappingOverridesLastWins() {
        let r = ChordTimeline.effective(detected: [seg(0, 6, 1)], overrides: [ov(1, 4, 7), ov(3, 5, 8)])
        XCTAssertEqual(r, [seg(0, 1, 1), seg(1, 3, 7), seg(3, 5, 8), seg(5, 6, 1)])
        let r2 = ChordTimeline.effective(detected: [seg(0, 6, 1)], overrides: [ov(1, 5, 7), ov(2, 3, 8)])
        XCTAssertEqual(r2, [seg(0, 1, 1), seg(1, 2, 7), seg(2, 3, 8), seg(3, 5, 7), seg(5, 6, 1)])
    }

    func testOverrideEqualToNeighbourMerges() {
        let r = ChordTimeline.effective(detected: [seg(0, 2, 1), seg(2, 4, 3)], overrides: [ov(1, 2, 3)])
        XCTAssertEqual(r, [seg(0, 1, 1), seg(1, 4, 3)])
    }

    func testOverrideOutsideDetectedIsKept() {
        let r = ChordTimeline.effective(detected: [seg(0, 1, 1)], overrides: [ov(3, 4, 2)])
        XCTAssertEqual(r, [seg(0, 1, 1), seg(3, 4, 2)])
    }
}

final class AnalysisCacheTests: XCTestCase {
    private struct Payload: Codable, Equatable { var bpm: Double; var chords: [ChordSegment] }

    private func fingerprint() -> AnalysisFingerprint {
        AnalysisFingerprint(beatModelID: "beat-this", beatModelVersion: "1",
                            chordModelID: "btc", chordModelVersion: "1",
                            algorithmVersion: 1,
                            separationModel: "bs-roformer", separationFinishedAt: Date(timeIntervalSince1970: 1_700_000_000.123),
                            sourceSHA256: "abc")
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("analysis-\(UUID().uuidString)/cache/analysis.json")
    }

    func testRoundTrip() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        let p = Payload(bpm: 110, chords: [ChordSegment(start: 0, end: 1, index: 3)])
        try AnalysisCache.save(p, fingerprint: fingerprint(), to: url)
        let loaded: Payload? = AnalysisCache.load(Payload.self, at: url, expecting: fingerprint())
        XCTAssertEqual(loaded, p)
    }

    func testMissingOrCorruptIsNil() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        XCTAssertNil(AnalysisCache.load(Payload.self, at: url, expecting: fingerprint()))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("no es json".utf8).write(to: url)
        XCTAssertNil(AnalysisCache.load(Payload.self, at: url, expecting: fingerprint()))
        // Otro tipo de contenido tampoco decodifica.
        struct Other: Codable { var x: String }
        try AnalysisCache.save(Payload(bpm: 1, chords: []), fingerprint: fingerprint(), to: url)
        XCTAssertNil(AnalysisCache.load(Other.self, at: url, expecting: fingerprint()))
    }

    func testAnyFingerprintFieldInvalidates() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        try AnalysisCache.save(Payload(bpm: 1, chords: []), fingerprint: fingerprint(), to: url)
        let mutations: [(String, (inout AnalysisFingerprint) -> Void)] = [
            ("beatModelID", { $0.beatModelID = "x" }),
            ("beatModelVersion", { $0.beatModelVersion = "2" }),
            ("chordModelID", { $0.chordModelID = "x" }),
            ("chordModelVersion", { $0.chordModelVersion = "2" }),
            ("algorithmVersion", { $0.algorithmVersion = 2 }),
            ("separationModel", { $0.separationModel = "x" }),
            ("separationFinishedAt", { $0.separationFinishedAt = Date(timeIntervalSince1970: 1) }),
            ("sourceSHA256", { $0.sourceSHA256 = "def" }),
        ]
        for (name, mutate) in mutations {
            var f = fingerprint()
            mutate(&f)
            XCTAssertNil(AnalysisCache.load(Payload.self, at: url, expecting: f), name)
        }
        XCTAssertNotNil(AnalysisCache.load(Payload.self, at: url, expecting: fingerprint()))
    }

    func testFingerprintHasNoSampleRate() throws {
        let json = String(decoding: try JSONEncoder().encode(fingerprint()), as: UTF8.self).lowercased()
        XCTAssertFalse(json.contains("samplerate"))
    }
}
