import Foundation
import XCTest
@testable import StemKit

/// Separador falso: solista = la mitad de la entrada. Apunta cada llamada (primera muestra global, longitud),
/// que se lee del canal izquierdo de la entrada de prueba (`left[n] = n / 2^20`, exacto en float32).
private final class HalfSeparator: LeadGuitarSeparating, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [Range<Int>] = []
    var calls: [Range<Int>] { lock.withLock { _calls } }

    func separateLead(left: [Float], right: [Float], sampleRate: Double) throws -> (left: [Float], right: [Float]) {
        let first = Int((Double(left[0]) * GuitarStemComposerTests.indexScale).rounded())
        lock.withLock { _calls.append(first..<(first + left.count)) }
        return (left.map { $0 * 0.5 }, right.map { $0 * 0.5 })
    }
}

final class GuitarStemComposerTests: XCTestCase {
    static let rate = 44_100.0
    static let seconds = 6.0
    static let indexScale = 1_048_576.0  // 2^20
    static var frameCount: Int { Int(seconds * rate) }
    static let fade = Int((GuitarStemComposer.fadeSeconds * rate).rounded())  // 4410

    /// Tres tramos: dos a 150 ms (los fundidos se solapan) y uno lejos.
    static let spans = [GuitarSoloSpan(start: 1.0, end: 2.0), GuitarSoloSpan(start: 4.0, end: 5.0),
                        GuitarSoloSpan(start: 2.15, end: 2.5)]

    /// Izquierdo = índice codificado (rampa exacta), derecho = ruido.
    static func makeInput() -> StereoAudio {
        var rng = SeededRandom(7)
        let n = frameCount
        return StereoAudio(left: (0..<n).map { Float(Double($0) / indexScale) },
                           right: (0..<n).map { _ in rng.unit() * 0.5 }, sampleRate: rate)
    }

    private func setUp(_ name: String) throws -> (dir: URL, input: URL, audio: StereoAudio) {
        let dir = try makeTempDir(name)
        let input = dir.appendingPathComponent("guitar.wav")
        let audio = Self.makeInput()
        try writeStereo(audio, to: input)
        return (dir, input, audio)
    }

    /// Bloque pequeño y que no divide a nada, para cruzar bordes de bloque dentro y fuera de los tramos.
    private func composer(context: Double = GuitarStemComposer.defaultContextSeconds) -> GuitarStemComposer {
        var c = GuitarStemComposer(contextSeconds: context)
        c.blockFrames = 3_001
        return c
    }

    private func guitarFiles(_ dir: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0 != "guitar.wav" })
    }

    private func read(_ tracks: [GuitarStemTrack], _ role: GuitarStemRole) throws -> StereoAudio {
        try AudioIO.readStereo(XCTUnwrap(tracks.first { $0.role == role }).url)
    }

    /// Muestras en `[s, e)` por tramo (mismo redondeo que el compositor).
    static func sampleSpans(_ spans: [GuitarSoloSpan]) -> [Range<Int>] {
        GuitarSoloSpan.normalized(spans, duration: seconds).map {
            Int(($0.start * rate).rounded())..<Int(($0.end * rate).rounded())
        }
    }

    /// Distancia en muestras al tramo más cercano (0 dentro).
    static func distance(_ k: Int, _ spans: [Range<Int>]) -> Int {
        spans.map { s in s.contains(k) ? 0 : (k < s.lowerBound ? s.lowerBound - k : k - (s.upperBound - 1)) }.min()!
    }

    // MARK: - Ficheros por combinación

    func testFourCombinationsWriteExactlyTheExpectedFiles() throws {
        let (dir, input, _) = try setUp("combos")
        try Data([1]).write(to: dir.appendingPathComponent("vocals.wav"))  // ajeno: no se toca
        let cases: [(Bool, [GuitarSoloSpan], [GuitarStemRole])] = [
            (false, [], []),
            (true, [], [.left, .right]),
            (false, Self.spans, [.rhythm, .lead]),
            (true, Self.spans, [.left, .right, .lead])
        ]
        for (stereo, spans, roles) in cases {
            let tracks = try composer().compose(input: input, outputDirectory: dir, stereo: stereo, soloSpans: spans,
                                                separator: HalfSeparator())
            XCTAssertEqual(tracks.map(\.role), roles, "stereo \(stereo), \(spans.count) tramos")
            XCTAssertEqual(try guitarFiles(dir), Set(roles.map(\.fileName) + ["vocals.wav"]),
                           "stereo \(stereo), \(spans.count) tramos")
            for t in tracks { XCTAssertEqual(try AudioIO.readStereo(t.url).frameCount, Self.frameCount) }
        }
    }

    func testObsoleteTracksAreRemoved() throws {
        let (dir, input, _) = try setUp("cleanup")
        try Data([1]).write(to: dir.appendingPathComponent("guitar_C.wav"))  // resto de la separación por panorama
        let c = composer()
        _ = try c.compose(input: input, outputDirectory: dir, stereo: true, soloSpans: Self.spans, separator: HalfSeparator())
        XCTAssertEqual(try guitarFiles(dir), ["guitar_L.wav", "guitar_R.wav", "guitar_lead.wav"])
        _ = try c.compose(input: input, outputDirectory: dir, stereo: false, soloSpans: Self.spans, separator: HalfSeparator())
        XCTAssertEqual(try guitarFiles(dir), ["guitar_rhythm.wav", "guitar_lead.wav"])
        _ = try c.compose(input: input, outputDirectory: dir, stereo: true, soloSpans: [], separator: nil)
        XCTAssertEqual(try guitarFiles(dir), ["guitar_L.wav", "guitar_R.wav"])
        _ = try c.compose(input: input, outputDirectory: dir, stereo: false, soloSpans: [], separator: nil)
        XCTAssertEqual(try guitarFiles(dir), [])
    }

    func testSpansWithoutSeparatorThrowAndKeepPreviousTracks() throws {
        let (dir, input, _) = try setUp("noseparator")
        _ = try composer().compose(input: input, outputDirectory: dir, stereo: true, soloSpans: [], separator: nil)
        XCTAssertThrowsError(try composer().compose(input: input, outputDirectory: dir, stereo: false,
                                                    soloSpans: Self.spans, separator: nil))
        XCTAssertEqual(try guitarFiles(dir), ["guitar_L.wav", "guitar_R.wav"])
    }

    // MARK: - Suma, fuera y dentro de los tramos

    func testTracksSumToInputAndAreExactOutsideSpans() throws {
        for stereo in [false, true] {
            for spans in [[], Self.spans] where stereo || !spans.isEmpty {
                let (dir, input, x) = try setUp("sum")
                let tracks = try composer().compose(input: input, outputDirectory: dir, stereo: stereo,
                                                    soloSpans: spans, separator: HalfSeparator())
                let n = Self.frameCount
                let zero = StereoAudio(left: .init(repeating: 0, count: n), right: .init(repeating: 0, count: n),
                                       sampleRate: Self.rate)
                let lead = spans.isEmpty ? zero : try read(tracks, .lead)
                var parts: [StereoAudio] = [lead]
                if stereo {
                    let l = try read(tracks, .left), r = try read(tracks, .right)
                    XCTAssertEqual(l.right, zero.right, "L tiene el canal derecho a 0")
                    XCTAssertEqual(r.left, zero.left, "R tiene el canal izquierdo a 0")
                    parts += [l, r]
                } else {
                    parts.append(try read(tracks, .rhythm))
                }
                var maxSumError: Float = 0
                for k in 0..<n {
                    let sl = parts.reduce(Float(0)) { $0 + $1.left[k] }, sr = parts.reduce(Float(0)) { $0 + $1.right[k] }
                    maxSumError = max(maxSumError, abs(sl - x.left[k]), abs(sr - x.right[k]))
                }
                XCTAssertLessThan(maxSumError, 1e-5, "stereo \(stereo), \(spans.count) tramos")

                // Fuera de tramos y fundidos: solista 0 exacto y rítmica (o L/R) la entrada exacta.
                let ss = Self.sampleSpans(spans)
                var outside = 0, mismatches = 0
                for k in 0..<n where spans.isEmpty || Self.distance(k, ss) >= Self.fade {
                    outside += 1
                    if lead.left[k] != 0 || lead.right[k] != 0 { mismatches += 1 }
                    let (rl, rr) = stereo ? (parts[1].left[k], parts[2].right[k]) : (parts[1].left[k], parts[1].right[k])
                    if rl != x.left[k] || rr != x.right[k] { mismatches += 1 }
                }
                XCTAssertGreaterThan(outside, n / 3)
                XCTAssertEqual(mismatches, 0, "stereo \(stereo), \(spans.count) tramos: muestras no exactas fuera")
                print("GuitarStemComposer suma stereo=\(stereo) tramos=\(spans.count): error máx \(maxSumError), " +
                      "\(outside) muestras fuera exactas")
            }
        }
    }

    /// Dentro de cada tramo la solista es exactamente la salida del separador; el fundido dura 100 ms (4410 muestras
    /// a 44,1 kHz) por fuera de cada borde, con ganancia 0,5 a mitad.
    func testInsideSpanLeadIsSeparatorOutputWithHundredMillisecondFades() throws {
        let (dir, input, x) = try setUp("inside")
        let tracks = try composer().compose(input: input, outputDirectory: dir, stereo: false, soloSpans: Self.spans,
                                            separator: HalfSeparator())
        let lead = try read(tracks, .lead)
        let ss = Self.sampleSpans(Self.spans)
        var inside = 0, wrong = 0
        for s in ss {
            for k in s {
                inside += 1
                if lead.left[k] != x.left[k] * 0.5 || lead.right[k] != x.right[k] * 0.5 { wrong += 1 }
            }
        }
        XCTAssertEqual(inside, ss.map(\.count).reduce(0, +))
        XCTAssertEqual(wrong, 0)

        // Bordes del fundido sobre el canal izquierdo (rampa > 0, así que solista ≠ 0 ⇔ ganancia > 0).
        let first = ss[0].lowerBound, last = ss[2].upperBound - 1  // tramo 1 s y tramo 4–5 s
        XCTAssertEqual(lead.left[first - Self.fade], 0)
        XCTAssertGreaterThan(lead.left[first - Self.fade + 1], 0)
        XCTAssertEqual(lead.left[last + Self.fade], 0)
        XCTAssertGreaterThan(lead.left[last + Self.fade - 1], 0)
        let firstNonZero = (0..<first).first { lead.left[$0] != 0 }!
        XCTAssertEqual(first - firstNonZero, Self.fade - 1, "muestras de fundido antes del tramo")
        let mid = first - Self.fade / 2
        let gainAtMid = Double(lead.left[mid]) / Double(x.left[mid] * 0.5)
        XCTAssertEqual(gainAtMid, 0.5, accuracy: 1e-6)
        // Entre 2,0 y 2,15 s (150 ms < 2 fundidos) la ganancia no baja de la del punto medio.
        let gapMid = (ss[0].upperBound + ss[1].lowerBound) / 2
        let gainGap = Double(lead.left[gapMid]) / Double(x.left[gapMid] * 0.5)
        XCTAssertEqual(gainGap, Double(GuitarStemComposer.fadeGain(distance: gapMid - ss[0].upperBound + 1,
                                                                    fadeFrames: Self.fade)), accuracy: 1e-6)
        print("GuitarStemComposer fundido: \(first - firstNonZero + 1) muestras = " +
              "\(Double(first - firstNonZero + 1) / Self.rate * 1000) ms, ganancia a mitad \(gainAtMid), hueco \(gainGap)")
    }

    // MARK: - El separador solo ve los tramos

    func testSeparatorOnlySeesSpansPlusMargin() throws {
        let (dir, input, _) = try setUp("calls")
        let context = 0.2
        let sep = HalfSeparator()
        _ = try composer(context: context).compose(input: input, outputDirectory: dir, stereo: true,
                                                   soloSpans: Self.spans, separator: sep)
        let pad = Self.fade + Int((context * Self.rate).rounded())
        let ss = Self.sampleSpans(Self.spans)
        // 1–2 s y 2,15–2,5 s se solapan con el margen → una llamada; 4–5 s otra.
        let expected = [(ss[0].lowerBound - pad)..<(ss[1].upperBound + pad),
                        (ss[2].lowerBound - pad)..<(ss[2].upperBound + pad)]
        XCTAssertEqual(sep.calls, expected)
        let seen = sep.calls.map(\.count).reduce(0, +)
        print("GuitarStemComposer separador: \(sep.calls.count) llamadas, \(seen) de \(Self.frameCount) muestras " +
              "(\(Double(seen) / Double(Self.frameCount) * 100) %)")
        // Lo visto = muestras de los tramos + hueco entre los dos primeros + 2 márgenes por llamada.
        let gap = ss[1].lowerBound - ss[0].upperBound
        XCTAssertEqual(seen, ss.map(\.count).reduce(0, +) + gap + 4 * pad)
    }

    func testNoSpansNeverCallsSeparator() throws {
        let (dir, input, _) = try setUp("nocalls")
        let sep = HalfSeparator()
        _ = try composer().compose(input: input, outputDirectory: dir, stereo: true, soloSpans: [], separator: sep)
        XCTAssertEqual(sep.calls, [])
    }

    // MARK: - Normalización

    func testNormalizationMergesSortsAndClips() {
        let raw = [GuitarSoloSpan(start: 5, end: 9), GuitarSoloSpan(start: -1, end: 0.5),
                   GuitarSoloSpan(start: 2, end: 3), GuitarSoloSpan(start: 2.5, end: 4),
                   GuitarSoloSpan(start: 4, end: 4.2), GuitarSoloSpan(start: 7, end: 6),
                   GuitarSoloSpan(start: 10, end: 12), GuitarSoloSpan(start: .nan, end: 1)]
        XCTAssertEqual(GuitarSoloSpan.normalized(raw, duration: 6),
                       [GuitarSoloSpan(start: 0, end: 0.5), GuitarSoloSpan(start: 2, end: 4.2),
                        GuitarSoloSpan(start: 5, end: 6)])
    }

    func testUnnormalizedSpansGiveSameTracksAsNormalized() throws {
        let messy = [GuitarSoloSpan(start: 4.5, end: 8), GuitarSoloSpan(start: 1.5, end: 2),
                     GuitarSoloSpan(start: 1, end: 1.8), GuitarSoloSpan(start: -3, end: -1)]
        let clean = GuitarSoloSpan.normalized(messy, duration: Self.seconds)
        XCTAssertEqual(clean, [GuitarSoloSpan(start: 1, end: 2), GuitarSoloSpan(start: 4.5, end: 6)])
        let (dirA, inputA, _) = try setUp("messy")
        let (dirB, inputB, _) = try setUp("clean")
        let a = try composer().compose(input: inputA, outputDirectory: dirA, stereo: false, soloSpans: messy,
                                       separator: HalfSeparator())
        let b = try composer().compose(input: inputB, outputDirectory: dirB, stereo: false, soloSpans: clean,
                                       separator: HalfSeparator())
        for role in [GuitarStemRole.rhythm, .lead] {
            let ta = try read(a, role), tb = try read(b, role)
            XCTAssertEqual(ta.left, tb.left)
            XCTAssertEqual(ta.right, tb.right)
        }
        // El tramo que acaba en el fin del tema llega hasta la última muestra.
        XCTAssertEqual(try read(a, .lead).left.last, Self.makeInput().left.last.map { $0 * 0.5 })
    }

    func testSpansOutsideSongMeanNoLead() throws {
        let (dir, input, _) = try setUp("outside")
        let sep = HalfSeparator()
        let mono = try composer().compose(input: input, outputDirectory: dir, stereo: false,
                                          soloSpans: [GuitarSoloSpan(start: 7, end: 9)], separator: sep)
        XCTAssertEqual(mono, [])
        let stereo = try composer().compose(input: input, outputDirectory: dir, stereo: true,
                                            soloSpans: [GuitarSoloSpan(start: 7, end: 9)], separator: nil)
        XCTAssertEqual(stereo.map(\.role), [.left, .right])
        XCTAssertEqual(sep.calls, [])
    }
}
