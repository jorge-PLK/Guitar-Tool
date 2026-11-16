import Foundation
import XCTest
@testable import StemKit

/// Mini-spec Fase 4, «Pruebas»: diafonía < −20 dB con tres señales paneadas, suma = entrada (< 1e-5),
/// mono → solo centro, descarte por −24 dB.
extension PanSplitter {
    /// Copia sin puerta del centro (C en todo el tema, como antes de la puerta): tests de máscara y barridos.
    func withoutGate() -> PanSplitter {
        var s = self
        s.ungated = true
        return s
    }
}

final class PanSplitterTests: XCTestCase {
    static let rate = 44_100.0
    /// 3 s + un resto que no es múltiplo del hop: comprueba la longitud exacta.
    static let n = 3 * 44_100 + 123

    /// Diafonía (mini-spec): energía de (pista − fuente esperada) frente a la fuente, en dB.
    /// Cuenta a la vez lo que entra de las otras fuentes y lo que se pierde de la propia.
    static let maxCrosstalkDB = -20.0
    /// Suma de las pistas frente a la entrada (mini-spec).
    static let maxSumError: Float = 1e-5

    /// Sin puerta (C en todo el tema): estos tests miden la máscara; la puerta, PanSplitterGateTests.
    static var ungated: PanSplitter { PanSplitter().withoutGate() }

    // MARK: - Señales

    /// Parciales separados ≥ 5 bins (21,5 Hz/bin a 44,1 kHz) entre fuentes, con modulación lenta distinta.
    static let partials: [[Double]] = [
        [196, 523, 1_187, 2_411, 4_870],    // izquierda
        [311, 740, 1_530, 3_150, 6_100],    // centro
        [415, 932, 1_870, 3_800, 7_300]     // derecha
    ]

    static func source(_ index: Int, n: Int = n, rate: Double = rate, gainDB: Double = 0) -> [Float] {
        let am = [3.0, 5.0, 7.0][index]
        let g = pow(10, gainDB / 20) * 0.12
        var out = [Float](repeating: 0, count: n)
        for (j, hz) in partials[index].enumerated() {
            let w = 2 * Double.pi * hz / rate
            let a = g / Double(j + 1).squareRoot()
            for k in 0..<n {
                let env = 0.75 + 0.25 * sin(2 * Double.pi * am * Double(k) / rate + Double(j))
                out[k] += Float(a * env * cos(w * Double(k) + Double(index + j)))
            }
        }
        return out
    }

    /// Ley de potencia constante, como Probes/testaudio/prepare.py (−1 izquierda, +1 derecha).
    static func panned(_ x: [Float], pan: Double, rate: Double = rate) -> StereoAudio {
        let th = (pan + 1) * Double.pi / 4
        let gl = Float(cos(th)), gr = Float(sin(th))
        return StereoAudio(left: x.map { $0 * gl }, right: x.map { $0 * gr }, sampleRate: rate)
    }

    static func sum(_ parts: [StereoAudio]) -> StereoAudio {
        var out = StereoAudio(left: [Float](repeating: 0, count: parts[0].frameCount),
                              right: [Float](repeating: 0, count: parts[0].frameCount),
                              sampleRate: parts[0].sampleRate)
        for p in parts {
            for k in 0..<out.frameCount {
                out.left[k] += p.left[k]
                out.right[k] += p.right[k]
            }
        }
        return out
    }

    static func crosstalkDB(_ out: StereoAudio, expected: StereoAudio) -> Double { -snrDB(expected, out) }

    private func split(_ audio: StereoAudio, _ name: String,
                       splitter: PanSplitter = PanSplitterTests.ungated) throws -> (PanSplitResult, URL) {
        let dir = try makeTempDir(name)
        let input = dir.appendingPathComponent("guitar.wav")
        try writeStereo(audio, to: input)
        let out = dir.appendingPathComponent("stems", isDirectory: true)
        return (try splitter.split(input: input, outputDirectory: out), out)
    }

    // MARK: - Diafonía

    private func checkCrosstalk(pans: [Double], name: String) throws {
        let refs = (0..<3).map { Self.panned(Self.source($0), pan: pans[$0]) }
        let (result, _) = try split(Self.sum(refs), name)
        XCTAssertEqual(result.tracks.map(\.side), [.left, .center, .right])
        XCTAssertTrue(result.discarded.isEmpty)
        for (i, track) in result.tracks.enumerated() {
            let out = try AudioIO.readStereo(track.url)
            let x = Self.crosstalkDB(out, expected: refs[i])
            print("PanSplitter diafonía pans \(pans) \(track.side.rawValue): \(String(format: "%.1f", x)) dB")
            XCTAssertLessThan(x, Self.maxCrosstalkDB, "\(track.side)")
        }
    }

    func testCrosstalkHardPanned() throws {
        try checkCrosstalk(pans: [-1, 0, 1], name: "pan-hard")
    }

    /// Máscara por canal: una guitarra sola a −30 % deja su canal derecho (−4,3 dB = 20·log10 tan(0,175π))
    /// en la pista R. Las dos pistas tienen la misma envolvente, así que el riesgo de mezcla lo marca.
    func testLoneThirtyPercentGuitarIsFlaggedByMixRisk() throws {
        let (result, _) = try split(Self.panned(Self.source(0), pan: -0.3), "pan-30")
        XCTAssertEqual(result.tracks.map(\.side), [.left, .right])
        let rel = result.tracks[1].level.rmsDB - result.tracks[0].level.rmsDB
        XCTAssertEqual(rel, 20 * log10(tan(0.175 * Double.pi)), accuracy: 0.3)   // ley de potencia constante
        for t in result.tracks {
            print("PanSplitter −30 % sola \(t.side.rawValue): riesgo \(String(format: "%.2f", t.confidence.mixRisk))")
            XCTAssertGreaterThan(t.confidence.mixRisk, 0.9)
            XCTAssertEqual(t.confidence.level, .low)
        }
    }

    /// Dos tomas de lo mismo abiertas a L y R (la segunda 15 ms tarde): riesgo alto, confianza no alta.
    func testDoubledGuitarsAreNotHighConfidence() throws {
        let a = Self.source(0)
        let delay = Int(0.015 * Self.rate)
        let b = [Float](repeating: 0, count: delay) + Array(a.prefix(Self.n - delay))
        let (result, _) = try split(StereoAudio(left: a, right: b, sampleRate: Self.rate), "pan-doubled")
        XCTAssertEqual(result.tracks.map(\.side).filter { $0 != .center }, [.left, .right])
        for t in result.tracks where t.side != .center {
            print("PanSplitter dobladas \(t.side.rawValue): \(t.confidence)")
            XCTAssertNotEqual(t.confidence.level, .high)
        }
    }

    // MARK: - Suma, longitud y frecuencia

    func testTracksSumToInputAt48k() throws {
        let rate = 48_000.0
        let n = 2 * 48_000 + 77
        let mix = Self.sum([Self.panned(Self.source(0, n: n, rate: rate), pan: -1, rate: rate),
                            Self.panned(Self.source(1, n: n, rate: rate), pan: 0, rate: rate),
                            Self.panned(Self.source(2, n: n, rate: rate), pan: 0.3, rate: rate)])
        let (result, _) = try split(mix, "pan-sum")
        XCTAssertEqual(result.tracks.count, 3)
        var maxErr: Float = 0
        var acc = StereoAudio(left: [Float](repeating: 0, count: n), right: [Float](repeating: 0, count: n),
                              sampleRate: rate)
        for t in result.tracks {
            let a = try AudioIO.readStereo(t.url)
            XCTAssertEqual(a.frameCount, n, "longitud exacta")
            XCTAssertEqual(a.sampleRate, rate, "misma frecuencia")
            for k in 0..<n {
                acc.left[k] += a.left[k]
                acc.right[k] += a.right[k]
            }
        }
        for k in 0..<n {
            maxErr = max(maxErr, abs(acc.left[k] - mix.left[k]), abs(acc.right[k] - mix.right[k]))
        }
        print("PanSplitter suma − entrada: error máximo \(maxErr)")
        XCTAssertLessThan(maxErr, Self.maxSumError)
    }

    // MARK: - Mono

    func testMonoInputKeepsOnlyCenter() throws {
        let mono = Self.sum([0, 1, 2].map { Self.panned(Self.source($0), pan: 0) })
        let (result, dir) = try split(StereoAudio(left: mono.left, right: mono.left, sampleRate: Self.rate), "pan-mono",
                                      splitter: PanSplitter())   // con puerta: la excepción de mono
        XCTAssertEqual(result.tracks.map(\.side), [.center])
        XCTAssertEqual(result.discarded.map(\.side), [.left, .right])
        XCTAssertEqual(result.discarded.map(\.reason), [.empty, .empty])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("guitar_L.wav").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("guitar_R.wav").path))
        let c = try AudioIO.readStereo(result.tracks[0].url)
        var maxErr: Float = 0
        for k in 0..<Self.n { maxErr = max(maxErr, abs(c.left[k] - mono.left[k]), abs(c.right[k] - mono.left[k])) }
        XCTAssertLessThan(maxErr, Self.maxSumError)
        XCTAssertEqual(result.tracks[0].confidence.level, .low)
        XCTAssertEqual(result.tracks[0].confidence.score, 0)
        // Ningún fichero temporal se queda en el directorio.
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(left, ["guitar_C.wav"])
    }

    // MARK: - Descarte por −24 dB (propuesta 1)

    /// Izquierda y derecha a 0 dB, centro a `centerDB`: la pista C queda a ≈ centerDB − 3 dB de la entrada
    /// (la entrada lleva L y R, cada una en su canal; ver cuenta en el test).
    private func splitWithCenter(at centerDB: Double, name: String,
                                 stale: Bool = false) throws -> (PanSplitResult, URL) {
        let mix = Self.sum([Self.panned(Self.source(0), pan: -1),
                            Self.panned(Self.source(1, gainDB: centerDB), pan: 0),
                            Self.panned(Self.source(2), pan: 1)])
        let dir = try makeTempDir(name)
        let input = dir.appendingPathComponent("guitar.wav")
        try writeStereo(mix, to: input)
        let out = dir.appendingPathComponent("stems", isDirectory: true)
        if stale {
            // Una pista C de una ejecución anterior: debe desaparecer si ahora se descarta.
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try writeStereo(Self.panned(Self.source(1), pan: 0), to: out.appendingPathComponent("guitar_C.wav"))
        }
        return (try Self.ungated.split(input: input, outputDirectory: out), out)
    }

    func testCenterMoreThan24dBBelowIsDiscarded() throws {
        let (result, dir) = try splitWithCenter(at: -30, name: "pan-discard", stale: true)
        XCTAssertEqual(result.tracks.map(\.side), [.left, .right])
        XCTAssertEqual(result.discarded.map(\.side), [.center])
        guard case .belowInput(let rel)? = result.discarded.first?.reason else {
            return XCTFail("motivo esperado: belowInput, es \(String(describing: result.discarded.first?.reason))")
        }
        // Fuentes de igual potencia σ²: entrada (σ² + σ² + c²)/2 por muestra y canal, C = c²/2 → c²/(2σ² + c²).
        // Con c² = σ²·10^−3 → −33 dB; con el centro estrecho una parte del centro débil se va a los lados
        // (medido −35,7 dB), así que solo se exige que caiga por debajo de −24 dB y cerca de lo esperado.
        print("PanSplitter centro a −30 dB: \(String(format: "%.1f", rel)) dB frente a la entrada")
        XCTAssertEqual(rel, -34.5, accuracy: 2.5)
        XCTAssertFalse(StemLevelMeter.isEmpty(result.discarded[0].level), "descartada por nivel relativo, no por vacía")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("guitar_C.wav").path))
    }

    func testCenterLessThan24dBBelowIsKept() throws {
        let (result, _) = try splitWithCenter(at: -15, name: "pan-keep")
        XCTAssertEqual(result.tracks.map(\.side), [.left, .center, .right])
        let c = result.tracks[1].level.rmsDB - result.inputLevel.rmsDB
        XCTAssertEqual(c, -18, accuracy: 1.5)
    }

    // MARK: - Bloques

    /// El proceso por bloques (con solape de n_fft y rejilla alineada al hop) da lo mismo que el tema entero.
    func testBlockProcessingMatchesWholeSignal() throws {
        let mix = Self.sum([Self.panned(Self.source(0), pan: -0.6),
                            Self.panned(Self.source(1), pan: 0.12),
                            Self.panned(Self.source(2), pan: 0.9)])
        var small = Self.ungated
        small.blockFrames = 8 * RoformerContract.hop          // 4096: más pequeño que los márgenes
        var whole = Self.ungated
        whole.blockFrames = 1 << 22                            // un solo bloque
        let (a, _) = try split(mix, "pan-blocks-small", splitter: small)
        let (b, _) = try split(mix, "pan-blocks-whole", splitter: whole)
        XCTAssertEqual(a.tracks.map(\.side), b.tracks.map(\.side))
        var maxDiff: Float = 0
        for (ta, tb) in zip(a.tracks, b.tracks) {
            let xa = try AudioIO.readStereo(ta.url), xb = try AudioIO.readStereo(tb.url)
            XCTAssertEqual(xa.frameCount, Self.n)
            for k in 0..<Self.n {
                maxDiff = max(maxDiff, abs(xa.left[k] - xb.left[k]), abs(xa.right[k] - xb.right[k]))
            }
            XCTAssertEqual(ta.confidence.score, tb.confidence.score, accuracy: 1e-6)
        }
        print("PanSplitter bloques de 4096 frente a uno solo: diferencia máxima \(maxDiff)")
        XCTAssertLessThan(maxDiff, 1e-6)
    }

    // MARK: - Confianza

    func testHardPannedIndependentGuitarsGiveHighConfidence() throws {
        let mix = Self.sum([Self.panned(Self.source(0), pan: -1), Self.panned(Self.source(2), pan: 1)])
        let (result, _) = try split(mix, "pan-conf")
        XCTAssertEqual(result.tracks.map(\.side), [.left, .right])
        for t in result.tracks {
            print("PanSplitter independientes \(t.side.rawValue): \(t.confidence)")
            XCTAssertLessThan(t.confidence.mixRisk, 0.2)
            XCTAssertEqual(t.confidence.level, .high, "\(t.side): \(t.confidence)")
        }
    }

    /// Una sola guitarra abierta: la otra pista sale vacía y la que queda, sin con quién mezclarse, es alta.
    func testSingleHardPannedGuitarIsHighConfidence() throws {
        let (result, _) = try split(Self.panned(Self.source(2), pan: 1), "pan-single")
        XCTAssertEqual(result.tracks.map(\.side), [.right])
        XCTAssertEqual(result.tracks[0].confidence.mixRisk, 0)
        XCTAssertEqual(result.tracks[0].confidence.level, .high)
    }

    func testConfidenceLevels() {
        XCTAssertEqual(PanSplitter.confidence(focus: 1, mixRisk: 0, monoInput: true).level, .low)
        XCTAssertEqual(PanSplitter.confidence(focus: 1, mixRisk: 0, monoInput: false).level, .high)
        XCTAssertEqual(PanSplitter.confidence(focus: 0.9, mixRisk: 0.5, monoInput: false).level, .medium)
        XCTAssertEqual(PanSplitter.confidence(focus: 0.9, mixRisk: 0.9, monoInput: false).level, .low)
    }

    func testRejectsTooShortInput() throws {
        let x = [Float](repeating: 0.1, count: RoformerContract.nFFT)
        XCTAssertThrowsError(try split(StereoAudio(left: x, right: x, sampleRate: Self.rate), "pan-short"))
    }
}
