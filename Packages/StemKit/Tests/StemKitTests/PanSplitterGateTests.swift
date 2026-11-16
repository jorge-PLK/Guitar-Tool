import Foundation
import XCTest
@testable import StemKit

/// Puerta del centro (mini-spec Fase 4, «Separación por panorama», viñeta «Centro con puerta», y editor «Aislar
/// solo»): sin tramos no hay C y L, R son los canales exactos; con tramo, la fuente central sale en C dentro y
/// C = 0 exacto fuera (más allá del fundido y media ventana); franja y panorama restringen C; la suma de las
/// pistas es la entrada (< 1e-5) con fundidos y bloques; entrada mono → todo a C, sin puerta.
///
/// Platero (opt-in, solo lectura): TF_PAN_PLATERO=<…/stems/guitar.wav> escribe recortes en
/// Temp/bench/platero/gate-final/{157-187s,60-90s}/guitar_{L,C,R}.wav e informa números.
final class PanSplitterGateTests: XCTestCase {
    typealias T = PanSplitterTests
    static let rate = 44_100.0
    /// 6 s + resto que no es múltiplo del hop.
    static let n = 6 * 44_100 + 123
    static let span = PanSoloSpan(start: 2, end: 4)
    /// Diafonía exigida a C frente a la fuente central esperada dentro del tramo (la de la mini-spec).
    static let maxCrosstalkDB = PanSplitterTests.maxCrosstalkDB
    /// Mitad del fundido: puerta 0,5 → C a −6 dB de la fuente central. Tolerancia por la ventana de la STFT.
    static let midFadeDB = 20 * log10(0.5)
    static let midFadeToleranceDB = 1.0
    /// Pan range que excluye el centro: C debe quedar por debajo de esto frente a la fuente central.
    static let excludedCenterMaxDB = -40.0

    struct Tracks {
        var l: StereoAudio, c: StereoAudio, r: StereoAudio
        subscript(side: GuitarSide) -> StereoAudio { side == .left ? l : side == .center ? c : r }
    }

    // MARK: - Utilidades

    static func silence(_ n: Int, rate: Double = rate) -> StereoAudio {
        StereoAudio(left: [Float](repeating: 0, count: n), right: [Float](repeating: 0, count: n), sampleRate: rate)
    }

    /// Suma de parciales con modulación lenta (como `PanSplitterTests.source`, con parciales a elegir).
    static func tone(_ partials: [Double], am: Double, n: Int = n, rate: Double = rate) -> [Float] {
        var out = [Float](repeating: 0, count: n)
        for (j, hz) in partials.enumerated() {
            let w = 2 * Double.pi * hz / rate
            let a = 0.12 / Double(j + 1).squareRoot()
            for k in 0..<n {
                let env = 0.75 + 0.25 * sin(2 * Double.pi * am * Double(k) / rate + Double(j))
                out[k] += Float(a * env * cos(w * Double(k) + Double(j)))
            }
        }
        return out
    }

    static func slice(_ a: StereoAudio, _ t0: Double, _ t1: Double) -> StereoAudio {
        let r = max(0, Int(t0 * a.sampleRate))..<min(a.frameCount, Int(t1 * a.sampleRate))
        return StereoAudio(left: Array(a.left[r]), right: Array(a.right[r]), sampleRate: a.sampleRate)
    }

    static func energy(_ a: StereoAudio, _ r: Range<Int>? = nil) -> Double {
        let r = r ?? 0..<a.frameCount
        var e = 0.0
        for k in r { e += Double(a.left[k]) * Double(a.left[k]) + Double(a.right[k]) * Double(a.right[k]) }
        return e
    }

    static func db(_ a: Double, _ b: Double) -> Double { 10 * log10(max(a, 1e-30) / max(b, 1e-30)) }

    static func fmt(_ x: Double) -> String { x < -200 ? "−∞" : String(format: "%+.1f", x) }

    /// Separa y lee las tres pistas (las descartadas, silencio).
    func run(_ mix: StereoAudio, _ name: String, splitter: PanSplitter) throws -> (PanSplitResult, Tracks) {
        let dir = try makeTempDir(name)
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("guitar.wav")
        try writeStereo(mix, to: input)
        let out = dir.appendingPathComponent("stems", isDirectory: true)
        let result = try splitter.split(input: input, outputDirectory: out)
        func read(_ side: GuitarSide) throws -> StereoAudio {
            guard let t = result.tracks.first(where: { $0.side == side }) else {
                return Self.silence(mix.frameCount, rate: mix.sampleRate)
            }
            return try AudioIO.readStereo(t.url)
        }
        return (result, Tracks(l: try read(.left), c: try read(.center), r: try read(.right)))
    }

    /// Máximo |L + C + R − entrada|.
    static func sumError(_ t: Tracks, _ mix: StereoAudio) -> Float {
        var e: Float = 0
        for k in 0..<mix.frameCount {
            e = max(e, abs(t.l.left[k] + t.c.left[k] + t.r.left[k] - mix.left[k]),
                    abs(t.l.right[k] + t.c.right[k] + t.r.right[k] - mix.right[k]))
        }
        return e
    }

    /// Máximas desviaciones en `r`: |L − canal L| (y su canal derecho), |R − canal R| (y su izquierdo), |C|.
    static func closedDeviation(_ t: Tracks, _ mix: StereoAudio, _ r: Range<Int>) -> (l: Float, r: Float, c: Float) {
        var dl: Float = 0, dr: Float = 0, dc: Float = 0
        for k in r {
            dl = max(dl, abs(t.l.left[k] - mix.left[k]), abs(t.l.right[k]))
            dr = max(dr, abs(t.r.right[k] - mix.right[k]), abs(t.r.left[k]))
            dc = max(dc, abs(t.c.left[k]), abs(t.c.right[k]))
        }
        return (dl, dr, dc)
    }

    /// Muestras en las que ninguna trama de la puerta llega: fuera de [inicio − fundido, fin + fundido]
    /// ampliado media ventana de la STFT (n_fft/2) a cada lado.
    static func closedRanges(_ s: PanSoloSpan, frames n: Int, rate: Double) -> [Range<Int>] {
        let half = Double(RoformerContract.nFFT / 2)
        let a = Int(((s.start - PanSoloSpan.fadeSeconds) * rate - half).rounded(.down))
        let b = Int(((s.end + PanSoloSpan.fadeSeconds) * rate + half).rounded(.up))
        return [0..<max(0, a), min(n, b)..<n]
    }

    // MARK: - Sin tramos

    func testNoSpansDropsCenterAndKeepsExactChannels() throws {
        let mix = T.sum([T.panned(T.source(0), pan: -1), T.panned(T.source(1), pan: 0), T.panned(T.source(2), pan: 0.3)])
        let (result, t) = try run(mix, "gate-none", splitter: PanSplitter())
        XCTAssertEqual(result.tracks.map(\.side), [.left, .right])
        XCTAssertEqual(result.discarded.map(\.side), [.center])
        XCTAssertEqual(result.discarded.first?.reason, .empty)
        let d = Self.closedDeviation(t, mix, 0..<mix.frameCount)
        print("Puerta sin tramos: máx |L − canal L| \(d.l), |R − canal R| \(d.r), |C| \(d.c)")
        XCTAssertEqual(d.l, 0, "L = canal L exacto")
        XCTAssertEqual(d.r, 0, "R = canal R exacto")
        XCTAssertEqual(d.c, 0)
    }

    // MARK: - Con tramo

    func testSpanSendsCenterSourceToCenterOnlyInsideSpan() throws {
        let center = T.panned(T.source(1, n: Self.n), pan: 0)
        let mix = T.sum([T.panned(T.source(0, n: Self.n), pan: -1), center, T.panned(T.source(2, n: Self.n), pan: 1)])
        let (result, t) = try run(mix, "gate-span", splitter: PanSplitter(soloSpans: [Self.span]))
        XCTAssertEqual(result.tracks.map(\.side), [.left, .center, .right])

        // Dentro (lejos de los bordes la puerta vale 1): C ≈ fuente central.
        let core = (Self.span.start + 0.05, Self.span.end - 0.05)
        let inside = T.crosstalkDB(Self.slice(t.c, core.0, core.1), expected: Self.slice(center, core.0, core.1))
        // Fuera: C = 0 y L, R canales exactos a partir de fundido + n_fft/2 del borde.
        let closed = Self.closedRanges(Self.span, frames: Self.n, rate: Self.rate)
        var dev: (l: Float, r: Float, c: Float) = (0, 0, 0)
        for r in closed {
            let d = Self.closedDeviation(t, mix, r)
            dev = (max(dev.l, d.l), max(dev.r, d.r), max(dev.c, d.c))
        }
        // Justo dentro de ese límite C ya no es 0 (el límite es ajustado, no holgado).
        let edge = closed[0].upperBound
        let justInside = Self.energy(t.c, edge..<edge + RoformerContract.hop)
        // Mitad del fundido de entrada (inicio − 50 ms), ventana de 20 ms: puerta 0,5 → −6 dB.
        let mid = Self.span.start - PanSoloSpan.fadeSeconds / 2
        let fadeDB = Self.db(Self.energy(Self.slice(t.c, mid - 0.01, mid + 0.01)),
                             Self.energy(Self.slice(center, mid - 0.01, mid + 0.01)))
        let sumErr = Self.sumError(t, mix)
        print("Puerta con tramo 2–4 s: diafonía C dentro \(Self.fmt(inside)) dB; fuera (a > \(PanSoloSpan.fadeSeconds) s + "
              + "\(RoformerContract.nFFT / 2) muestras) máx |C| \(dev.c), |L − canal| \(dev.l), |R − canal| \(dev.r); "
              + "energía de C en la trama siguiente \(justInside); mitad del fundido \(Self.fmt(fadeDB)) dB; "
              + "suma − entrada \(sumErr)")
        XCTAssertLessThan(inside, Self.maxCrosstalkDB)
        XCTAssertEqual(dev.c, 0, "C = 0 exacto fuera del tramo")
        XCTAssertEqual(dev.l, 0, "L = canal L exacto fuera del tramo")
        XCTAssertEqual(dev.r, 0, "R = canal R exacto fuera del tramo")
        XCTAssertGreaterThan(justInside, 0)
        XCTAssertEqual(fadeDB, Self.midFadeDB, accuracy: Self.midFadeToleranceDB)
        XCTAssertLessThan(sumErr, T.maxSumError)
    }

    /// Franja 500–2000 Hz: los parciales centrales de dentro van a C; los de fuera vuelven a L y R por canal.
    func testFrequencyBandRestrictsCenterToBand() throws {
        let inBand = T.panned(Self.tone([740, 1_530], am: 5), pan: 0)
        let outBand = T.panned(Self.tone([311, 3_150, 6_100], am: 4), pan: 0)
        let left = T.panned(T.source(0, n: Self.n), pan: -1), right = T.panned(T.source(2, n: Self.n), pan: 1)
        let mix = T.sum([left, inBand, outBand, right])
        var span = Self.span
        span.frequencyRange = .init(lower: 500, upper: 2_000)
        let (_, t) = try run(mix, "gate-band", splitter: PanSplitter(soloSpans: [span]))
        let (_, whole) = try run(mix, "gate-band-all", splitter: PanSplitter(soloSpans: [Self.span]))
        let (a, b) = (span.start + 0.05, span.end - 0.05)
        let cBand = T.crosstalkDB(Self.slice(t.c, a, b), expected: Self.slice(inBand, a, b))
        let cWhole = T.crosstalkDB(Self.slice(whole.c, a, b), expected: Self.slice(inBand, a, b))
        // L esperada: canal L de la izquierda + canal L de los parciales centrales fuera de la franja.
        let expL = T.sum([left, StereoAudio(left: outBand.left, right: [Float](repeating: 0, count: Self.n),
                                            sampleRate: Self.rate)])
        let lBack = T.crosstalkDB(Self.slice(t.l, a, b), expected: Self.slice(expL, a, b))
        let sumErr = Self.sumError(t, mix)
        print("Puerta con franja 500–2000 Hz: C frente a los parciales de la franja \(Self.fmt(cBand)) dB "
              + "(sin franja \(Self.fmt(cWhole)) dB); L frente a izquierda + centro fuera de franja \(Self.fmt(lBack)) dB; "
              + "suma − entrada \(sumErr)")
        XCTAssertLessThan(cBand, Self.maxCrosstalkDB)
        XCTAssertGreaterThan(cWhole, 0, "sin franja C lleva también los parciales de fuera")
        XCTAssertLessThan(lBack, Self.maxCrosstalkDB)
        XCTAssertLessThan(sumErr, T.maxSumError)
    }

    /// Rango de panorama: si excluye el centro, la fuente central no va a C; si lo incluye, como sin rango.
    func testPanRangeRestrictsCenter() throws {
        let center = T.panned(T.source(1, n: Self.n), pan: 0)
        let mix = T.sum([T.panned(T.source(0, n: Self.n), pan: -1), center, T.panned(T.source(2, n: Self.n), pan: 1)])
        var excl = Self.span, incl = Self.span
        excl.panRange = .init(lower: 0.5, upper: 1)
        incl.panRange = .init(lower: 0.2, upper: -0.2)   // al revés: se ordena
        let (_, te) = try run(mix, "gate-pan-excl", splitter: PanSplitter(relativeDiscardDB: 200, soloSpans: [excl]))
        let (_, ti) = try run(mix, "gate-pan-incl", splitter: PanSplitter(soloSpans: [incl]))
        let (a, b) = (Self.span.start + 0.05, Self.span.end - 0.05)
        let excluded = Self.db(Self.energy(Self.slice(te.c, a, b)), Self.energy(Self.slice(center, a, b)))
        let included = T.crosstalkDB(Self.slice(ti.c, a, b), expected: Self.slice(center, a, b))
        print("Puerta con panorama: rango 0,5…1 → C \(Self.fmt(excluded)) dB frente a la fuente central; "
              + "rango −0,2…0,2 → diafonía C \(Self.fmt(included)) dB; suma − entrada \(Self.sumError(te, mix))")
        XCTAssertLessThan(excluded, Self.excludedCenterMaxDB)
        XCTAssertLessThan(included, Self.maxCrosstalkDB)
        XCTAssertLessThan(Self.sumError(te, mix), T.maxSumError)
    }

    // MARK: - Suma y bloques

    /// Tramos solapados, con franja, panorama, anchura propia y uno que pasa del final; bloques de 4096 frente a
    /// uno solo, a 48 kHz.
    func testTracksSumToInputWithFadesAndBlocks() throws {
        let rate = 48_000.0
        let n = 2 * 48_000 + 77
        let mix = T.sum([T.panned(T.source(0, n: n, rate: rate), pan: -1, rate: rate),
                         T.panned(T.source(1, n: n, rate: rate), pan: 0.05, rate: rate),
                         T.panned(T.source(2, n: n, rate: rate), pan: 0.3, rate: rate)])
        let spans = [
            PanSoloSpan(start: 0.4, end: 0.9, frequencyRange: .init(lower: 300, upper: 3_000)),
            PanSoloSpan(start: 0.85, end: 1.4, panRange: .init(lower: -0.3, upper: 0.3), centerWidth: 0.2,
                        coherenceFloor: 0.3),
            PanSoloSpan(start: 1.9, end: 5)
        ]
        var small = PanSplitter(relativeDiscardDB: 200, soloSpans: spans)
        small.blockFrames = 8 * RoformerContract.hop
        var whole = PanSplitter(relativeDiscardDB: 200, soloSpans: spans)
        whole.blockFrames = 1 << 22
        let (_, a) = try run(mix, "gate-sum-small", splitter: small)
        let (_, b) = try run(mix, "gate-sum-whole", splitter: whole)
        var blockDiff: Float = 0
        for side in GuitarSide.allCases {
            for k in 0..<n {
                blockDiff = max(blockDiff, abs(a[side].left[k] - b[side].left[k]), abs(a[side].right[k] - b[side].right[k]))
            }
        }
        let errA = Self.sumError(a, mix), errB = Self.sumError(b, mix)
        let cEnergy = Self.energy(a.c)
        print("Puerta, suma con fundidos a 48 kHz: error máx \(errA) (bloques de 4096), \(errB) (uno); "
              + "bloques frente a uno: \(blockDiff); C \(Self.fmt(Self.db(cEnergy, Self.energy(mix)))) dB")
        XCTAssertGreaterThan(cEnergy, 0)
        XCTAssertLessThan(errA, T.maxSumError)
        XCTAssertLessThan(errB, T.maxSumError)
        XCTAssertLessThan(blockDiff, 1e-6)
    }

    // MARK: - Mono

    /// Entrada mono con un tramo marcado: todo a C en todo el tema, sin puerta.
    func testMonoInputIgnoresGate() throws {
        let mono = T.sum([0, 1, 2].map { T.panned(T.source($0, n: Self.n), pan: 0) })
        let x = StereoAudio(left: mono.left, right: mono.left, sampleRate: Self.rate)
        let (result, t) = try run(x, "gate-mono", splitter: PanSplitter(soloSpans: [Self.span]))
        XCTAssertEqual(result.tracks.map(\.side), [.center])
        var err: Float = 0
        for k in 0..<Self.n { err = max(err, abs(t.c.left[k] - x.left[k]), abs(t.c.right[k] - x.right[k])) }
        print("Puerta, entrada mono con tramo: máx |C − entrada| \(err) en todo el tema")
        XCTAssertLessThan(err, T.maxSumError)
    }

    // MARK: - Tipo y propuesta

    func testSoloSpanCodableRoundTripAndDefaults() throws {
        let s = PanSoloSpan(start: 157, end: 187, frequencyRange: .init(lower: 800, upper: 5_000),
                            panRange: .init(lower: -0.2, upper: 0.25), centerWidth: 0.4)
        let data = try JSONEncoder().encode([s])
        XCTAssertEqual(try JSONDecoder().decode([PanSoloSpan].self, from: data), [s])
        let bare = try JSONDecoder().decode(PanSoloSpan.self, from: Data(#"{"start":157,"end":187}"#.utf8))
        XCTAssertEqual(bare, PanSoloSpan(start: 157, end: 187))
        XCTAssertEqual(bare.effectiveCenterWidth, 0.30)
        XCTAssertEqual(bare.effectiveCoherenceFloor, 0.15)
        XCTAssertEqual(s.effectiveCenterWidth, 0.4)
    }

    /// Pasajes «lead» de la C de una primera pasada de Platero (Temp/bench/platero/sweep/firstpass): ninguno es
    /// de confianza alta y la propuesta sale vacía. Con un umbral de 0,7 saldrían dos falsos (4–9 y 13–22 s).
    func testProposalsOnlyHighConfidence() {
        let platero = [PanSoloCandidate(start: 4, end: 9, confidence: 0.86),
                       PanSoloCandidate(start: 13, end: 22, confidence: 0.76),
                       PanSoloCandidate(start: 39, end: 51, confidence: 0.60),
                       PanSoloCandidate(start: 65, end: 96, confidence: 0.66),
                       PanSoloCandidate(start: 102, end: 231, confidence: 0.64)]
        XCTAssertEqual(PanSoloSpan.proposals(from: platero), [])
        XCTAssertEqual(PanSoloSpan.proposals(from: platero, minimumConfidence: 0.7).map { [$0.start, $0.end] },
                       [[4, 9], [13, 22]])
        XCTAssertEqual(PanSoloSpan.proposals(from: []), [])
        let sure = PanSoloCandidate(start: 157, end: 187, confidence: 0.95)
        XCTAssertEqual(PanSoloSpan.proposals(from: platero + [sure]), [PanSoloSpan(start: 157, end: 187)])
    }

    // MARK: - Platero (opt-in)

    func testPlateroGateClips() throws {
        guard let path = ProcessInfo.processInfo.environment["TF_PAN_PLATERO"], !path.isEmpty else {
            throw XCTSkip("Platero desactivado (TF_PAN_PLATERO sin definir)")
        }
        let input = URL(fileURLWithPath: path)
        let span = PanSoloSpan(start: 157, end: 187)
        let dir = try makeTempDir("platero-gate")
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = try AudioIO.readStereo(input)
        let rate = src.sampleRate
        let clock = Date()
        let gated = try PanSplitter(relativeDiscardDB: 200, soloSpans: [span])
            .split(input: input, outputDirectory: dir.appendingPathComponent("gated"))
        let gatedSeconds = Date().timeIntervalSince(clock)
        let ungated = try PanSplitter(relativeDiscardDB: 200).withoutGate()
            .split(input: input, outputDirectory: dir.appendingPathComponent("ungated"))
        func tracks(_ r: PanSplitResult) throws -> Tracks {
            func read(_ s: GuitarSide) throws -> StereoAudio {
                guard let t = r.tracks.first(where: { $0.side == s }) else { return Self.silence(src.frameCount, rate: rate) }
                return try AudioIO.readStereo(t.url)
            }
            return Tracks(l: try read(.left), c: try read(.center), r: try read(.right))
        }
        let g = try tracks(gated), u = try tracks(ungated)

        // Fuera del tramo (más fundido y media ventana): C exacto 0, L y R canales exactos.
        var dev: (l: Float, r: Float, c: Float) = (0, 0, 0)
        var cOut = 0.0, inOut = 0.0, cOutUngated = 0.0
        for r in Self.closedRanges(span, frames: src.frameCount, rate: rate) {
            let d = Self.closedDeviation(g, src, r)
            dev = (max(dev.l, d.l), max(dev.r, d.r), max(dev.c, d.c))
            cOut += Self.energy(g.c, r)
            cOutUngated += Self.energy(u.c, r)
            inOut += Self.energy(src, r)
        }
        let cLevel = gated.tracks.first { $0.side == .center }?.level ?? gated.discarded.first { $0.side == .center }!.level
        let cWholeDB = cLevel.rmsDB - gated.inputLevel.rmsDB
        var lines = [
            "PLATERO puerta 157–187 s (\(String(format: "%.0f", gatedSeconds)) s de proceso): fuera del tramo C "
                + "\(Self.fmt(Self.db(cOut, inOut))) dB frente a la entrada (sin puerta \(Self.fmt(Self.db(cOutUngated, inOut))) dB), "
                + "máx |C| \(dev.c), |L − canal| \(dev.l), |R − canal| \(dev.r)",
            "PLATERO C del tema entero con puerta \(Self.fmt(cWholeDB)) dB frente a la entrada → con el descarte de "
                + "−\(Int(PanSplitter.defaultRelativeDiscardDB)) dB \(cWholeDB < -PanSplitter.defaultRelativeDiscardDB ? "SE DESCARTARÍA" : "se guarda")"
        ]
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let out = repo.appendingPathComponent("Temp/bench/platero/gate-final", isDirectory: true)
        for s0 in [157, 60] {
            let r = Int(Double(s0) * rate)..<min(src.frameCount, Int(Double(s0 + 30) * rate))
            let eIn = Self.energy(src, r)
            func line(_ t: Tracks) -> String {
                GuitarSide.allCases.map { "\($0.rawValue) \(Self.fmt(Self.db(Self.energy(t[$0], r), eIn)))" }.joined(separator: ", ")
            }
            let gain = Self.db(Self.energy(g.c, r), Self.energy(u.c, r))
            lines.append("PLATERO \(s0)–\(s0 + 30) s frente a la entrada: con puerta \(line(g)) dB; sin puerta \(line(u)) dB; "
                         + "C con puerta − C sin puerta \(Self.fmt(gain)) dB")
            let folder = out.appendingPathComponent("\(s0)-\(s0 + 30)s", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for side in GuitarSide.allCases {
                let a = g[side]
                try writeStereo(StereoAudio(left: Array(a.left[r]), right: Array(a.right[r]), sampleRate: rate),
                                to: folder.appendingPathComponent(side.fileName))
            }
        }
        lines.append("PLATERO recortes en \(out.path)")
        print(lines.joined(separator: "\n"))
        XCTAssertEqual(dev.c, 0)
        XCTAssertEqual(dev.l, 0)
        XCTAssertEqual(dev.r, 0)
    }
}
