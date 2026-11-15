import XCTest
@testable import AudioKit

/// Igualado de sonoridad (mini-spec Fase 3, «A/B dentro de la mezcla»).
final class LoudnessMatchTests: XCTestCase {
    func testKWeightingMatchesTheBS1770TableAt48k() {
        let c = LoudnessMatch.kWeightingCoefficients(sampleRate: 48_000)
        let shelf = [1.53512485958697, -2.69169618940638, 1.19839281085285, -1.69065929318241, 0.73248077421585]
        let highpass = [1.0, -2.0, 1.0, -1.99004745483398, 0.99007225036621]
        for (got, want) in zip(c[0] + c[1], shelf + highpass) { XCTAssertEqual(got, want, accuracy: 1e-6) }
    }

    func testFullScale997HzSineOnOneChannelIsMinus3_01LKFS() {
        for fs in [44_100.0, 48_000.0] {
            let n = Int(5 * fs)
            let sine = (0..<n).map { Float(sin(2 * Double.pi * 997 * Double($0) / fs)) }
            let l = LoudnessMatch.loudness([sine, [Float](repeating: 0, count: n)], sampleRate: fs) ?? .nan
            print(String(format: "F3 sonoridad 997 Hz 0 dBFS a %.0f Hz: %.4f LKFS (norma −3,01)", fs, l))
            XCTAssertEqual(l, -3.01, accuracy: 0.05)
        }
    }

    func testGainIgnoresSilencesAndIsCappedAt12dB() {
        let fs = TakeAlignmentTests.fs
        let s = TakeAlignmentTests.plucks(seconds: 30, seed: 5)
        let stem = [s, s]
        // Toma mono a la mitad (−6,02 dB), con 2 s de silencio cada 6 s (un tercio del tramo).
        var take = s.map { 0.5 * $0 }
        for start in stride(from: Int(4 * fs), to: take.count, by: Int(6 * fs)) {
            for i in start..<min(take.count, start + Int(2 * fs)) { take[i] = 0 }
        }
        let r = LoudnessMatch.gain(take: [take], stem: stem, sampleRate: fs)
        // Contando el silencio saldrían 6,02 + 10·log10(3/2) = 7,78 dB. Los bloques de 400 ms que pisan el
        // borde de un silencio pasan la puerta con menos energía: sesgo de unas décimas.
        print(String(format: "F3 igualado con silencios: %.3f dB (esperado 6,021; contando silencio 7,78); toma %.2f, stem %.2f LKFS",
                     r.gainDB, r.takeLKFS ?? .nan, r.stemLKFS ?? .nan))
        XCTAssertEqual(r.gainDB, 6.021, accuracy: 0.5)

        let full = LoudnessMatch.gain(take: [s.map { 0.5 * $0 }], stem: stem, sampleRate: fs)
        XCTAssertEqual(full.gainDB, 6.021, accuracy: 0.01)

        let quiet = LoudnessMatch.gain(take: [s.map { 0.01 * $0 }], stem: stem, sampleRate: fs)
        XCTAssertEqual(quiet.gainDB, 12)
        XCTAssertEqual(quiet.unclampedGainDB ?? 0, 40, accuracy: 0.01)
        let loud = LoudnessMatch.gain(take: [s.map { 0.5 * $0 }], stem: [s.map { 0.01 * $0 }, s.map { 0.01 * $0 }], sampleRate: fs)
        XCTAssertEqual(loud.gainDB, -12)

        let silent = LoudnessMatch.gain(take: [[Float](repeating: 0, count: s.count)], stem: stem, sampleRate: fs)
        XCTAssertEqual(silent.gainDB, 0)
        XCTAssertNil(silent.unclampedGainDB)

        // El tramo del stem sale de `songStart`.
        let long = [[Float](repeating: 0, count: Int(10 * fs)) + s, [Float](repeating: 0, count: Int(10 * fs)) + s]
        let sliced = LoudnessMatch.gain(take: [s.map { 0.5 * $0 }], stem: long, songStart: 10, sampleRate: fs)
        XCTAssertEqual(sliced.gainDB, 6.021, accuracy: 0.01)
    }
}
