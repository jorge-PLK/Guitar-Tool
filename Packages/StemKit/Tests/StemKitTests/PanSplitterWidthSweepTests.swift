import Foundation
import XCTest
@testable import StemKit

/// Barrido de la anchura del centro, con y sin puerta de solo (orquestador, Fase 4), solo informa, sin guía por
/// notas. Desactivado salvo con:
///
///   TF_PAN_WIDTHS=0.15,0.22,0.30,0.40,0.50     variantes `anchura[:transición[:suelo]]` (por defecto 0,1 y 0,25)
///   TF_PAN_UNGATED=w0.15,w0.30                 variantes que se miden también sin puerta
///   TF_PAN_T1 / TF_PAN_T2 / TF_PAN_T3           carpetas de Probes/testaudio/out/T<n> (stems/guitar.wav, guitar_parts/)
///   TF_PAN_PLATERO=<stems/guitar.wav>           se lee, nunca se escribe ahí
///   TF_PAN_PLATERO_GATES=ideal=157-187;real=40-79,88-224   puertas de Platero (s); la primera da los recortes
///
/// Puerta (propuesta de Jorge, 15/11/2026): C solo existe en los pasajes de solo. Se aplica aquí después de la
/// separación, sobre las pistas: C' = g·C, L' = g·L + (1 − g)·canal L, R' = g·R + (1 − g)·canal R (por canal,
/// así que las pistas siguen sumando la entrada y con g = 0 L' y R' son exactamente los canales). Equivale a la
/// máscara de C × g(t) salvo la ventana de la STFT (46 ms frente a fundidos de 100 ms).
/// Excepción: si sin puerta L y R quedan las dos por debajo de −24 dB (entrada casi mono), g = 1.
final class PanSplitterWidthSweepTests: XCTestCase {
    struct Variant {
        let width: Float, transition: Float, floor: Float
        var name: String {
            floor == PanSplitter.defaultCoherenceFloor ? String(format: "w%.2f", width)
                : String(format: "w%.2f-s%.2f", width, floor)
        }
        var splitter: PanSplitter {
            var s = PanSplitter(centerWidth: width, transitionWidth: transition, relativeDiscardDB: 200).withoutGate()
            s.coherenceLow = floor
            return s
        }
    }

    /// Pistas por lado, siempre las tres (relativeDiscardDB 200).
    typealias Tracks = [GuitarSide: StereoAudio]

    static let cropStart = 40.0
    static let cropSeconds = 12.0
    static let plateroSegments = [157, 60]
    static let clipSeconds = 30
    /// Fundido de la puerta en cada borde, por fuera del pasaje (encargo: ~100 ms).
    static let gateFade = 0.1
    /// Actividad de la solista de referencia: ventanas de 50 ms a menos de 30 dB de su RMS medio, ampliadas 100 ms.
    static let activityWindow = 0.05
    static let activityRelDB = -30.0
    static let activityHold = 0.1

    private func env(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func e(_ a: StereoAudio, _ r: Range<Int>? = nil) -> Double {
        let r = r ?? 0..<a.frameCount
        return PanSplitterT1Tests.energy(Array(a.left[r])) + PanSplitterT1Tests.energy(Array(a.right[r]))
    }

    private static func db(_ a: Double, _ b: Double) -> String {
        let x = 10 * log10(max(a, 1e-30) / max(b, 1e-30))
        return x < -200 ? "−∞" : String(format: "%+.1f", x)
    }

    private static func f1(_ x: Double) -> String { String(format: "%.1f", x) }

    /// Partes de `guitar_parts/` sumadas por lado según su propio panorama (como PanSplitterT1Tests).
    private static func loadRefs(_ song: URL) throws -> Tracks {
        let dir = song.appendingPathComponent("guitar_parts")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".wav") }.sorted()
        let n = Int(cropSeconds * 44_100)
        var refs: Tracks = [:]
        for side in GuitarSide.allCases { refs[side] = PanSplitterT1Tests.silence(n) }
        for name in names {
            let part = try PanSplitterT1Tests.readCrop(dir.appendingPathComponent(name), start: cropStart, seconds: cropSeconds)
            guard e(part) > 1e-6 else { continue }
            PanSplitterT1Tests.add(part, into: &refs[PanSplitterT1Tests.side(of: part)]!)
        }
        return refs
    }

    /// Puerta por muestra: 1 dentro de los tramos, coseno alzado de `gateFade` por fuera de cada borde.
    static func gate(_ spans: [(Double, Double)], frames: Int, rate: Double) -> [Float] {
        var g = [Float](repeating: 0, count: frames)
        let fade = gateFade * rate
        for (a, b) in spans {
            let s = a * rate, t = b * rate
            let lo = max(0, Int((s - fade).rounded(.down))), hi = min(frames, Int((t + fade).rounded(.up)))
            for k in lo..<max(lo, hi) {
                let x = Double(k)
                let v: Double = x < s ? 0.5 - 0.5 * cos(.pi * (x - (s - fade)) / fade)
                    : x >= t ? 0.5 + 0.5 * cos(.pi * (x - t) / fade) : 1
                g[k] = max(g[k], Float(v))
            }
        }
        return g
    }

    /// Tramos con nivel de una fuente (ventanas de `activityWindow`, ampliadas `activityHold`).
    static func activity(_ a: StereoAudio) -> [(Double, Double)] {
        let w = Int(activityWindow * a.sampleRate), n = a.frameCount / w
        let en = (0..<n).map { e(a, $0 * w..<($0 + 1) * w) }
        let mean = en.reduce(0, +) / Double(max(n, 1))
        let thr = mean * pow(10, activityRelDB / 10)
        var spans: [(Double, Double)] = []
        for i in 0..<n where en[i] > thr {
            let s = max(0, Double(i) * activityWindow - activityHold), t = Double(i + 1) * activityWindow + activityHold
            if let last = spans.last, s <= last.1 { spans[spans.count - 1].1 = t } else { spans.append((s, t)) }
        }
        return spans
    }

    /// Pistas con puerta (ver la cabecera); con entrada casi mono, sin puerta.
    static func gated(_ t: Tracks, input x: StereoAudio, gate g: [Float]) -> Tracks {
        let rel = { (s: GuitarSide) in 10 * log10(max(e(t[s]!), 1e-30) / max(e(x), 1e-30)) }
        if rel(.left) < -PanSplitter.defaultRelativeDiscardDB && rel(.right) < -PanSplitter.defaultRelativeDiscardDB {
            return t
        }
        var l = t[.left]!, r = t[.right]!, c = t[.center]!
        for k in 0..<x.frameCount {
            let a = g[k], b = 1 - g[k]
            l.left[k] = a * l.left[k] + b * x.left[k]
            l.right[k] = a * l.right[k]
            r.left[k] = a * r.left[k]
            r.right[k] = a * r.right[k] + b * x.right[k]
            c.left[k] *= a
            c.right[k] *= a
        }
        return [.left: l, .right: r, .center: c]
    }

    private static func split(_ v: Variant, _ input: URL, probe: URL? = nil) throws -> (Tracks, Tracks?, PanSplitResult) {
        let dir = try makeTempDir("sweep")
        defer { try? FileManager.default.removeItem(at: dir) }
        var s = v.splitter
        s.probeInput = probe
        let r = try s.split(input: input, outputDirectory: dir)
        var t: Tracks = [:], p: Tracks = [:]
        for side in GuitarSide.allCases {
            t[side] = try AudioIO.readStereo(dir.appendingPathComponent(side.fileName))
            if probe != nil { p[side] = try AudioIO.readStereo(dir.appendingPathComponent("probe-\(side.fileName)")) }
        }
        return (t, probe == nil ? nil : p, r)
    }

    func testCenterWidthSweep() throws {
        guard let spec = env("TF_PAN_WIDTHS") else { throw XCTSkip("barrido de anchura desactivado (TF_PAN_WIDTHS sin definir)") }
        let variants: [Variant] = spec.split(separator: ",").map { item in
            let v = item.split(separator: ":").compactMap { Float($0) }
            return Variant(width: v[0], transition: v.count > 1 ? v[1] : PanSplitter.defaultTransitionWidth,
                           floor: v.count > 2 ? v[2] : PanSplitter.defaultCoherenceFloor)
        }
        let ungated = Set((env("TF_PAN_UNGATED") ?? "").split(separator: ",").map(String.init))
        let t1 = env("TF_PAN_T1").map { URL(fileURLWithPath: $0) }
        let t2 = env("TF_PAN_T2").map { URL(fileURLWithPath: $0) }
        let songs = [t1, t2, env("TF_PAN_T3").map { URL(fileURLWithPath: $0) }].compactMap { $0 }

        // (1) T2 + solista 05 de T1 en mono en el centro (misma mezcla que testCenterSoloOverT2Doubles);
        // puerta de la actividad de la solista de referencia.
        if let t1, let t2 {
            var refs = try Self.loadRefs(t2)
            let part = try PanSplitterT1Tests.readCrop(t1.appendingPathComponent("guitar_parts/23_ElecGtr05.wav"),
                                                       start: Self.cropStart, seconds: Self.cropSeconds)
            let th = 1.3 * Double.pi / 4
            let mono = (0..<part.frameCount).map { Float(Double(part.left[$0]) * cos(th) + Double(part.right[$0]) * sin(th)) }
            let side = (Self.e(refs[.left]!) + Self.e(refs[.right]!)) / 2
            let gain = Float((side / (2 * PanSplitterT1Tests.energy(mono))).squareRoot())
            let solo = StereoAudio(left: mono.map { $0 * gain }, right: mono.map { $0 * gain }, sampleRate: 44_100)
            refs[.center] = solo
            var mix = PanSplitterT1Tests.silence(part.frameCount)
            for s in GuitarSide.allCases { PanSplitterT1Tests.add(refs[s]!, into: &mix) }
            let spans = Self.activity(solo)
            let g = Self.gate(spans, frames: mix.frameCount, rate: 44_100)
            print("SWEEP 1 puerta de actividad: \(spans.count) tramos, abierta \(String(format: "%.0f", 100 * Double(g.reduce(0, +)) / Double(g.count))) % de 12 s")
            let dir = try makeTempDir("sweep-solo")
            defer { try? FileManager.default.removeItem(at: dir) }
            let input = dir.appendingPathComponent("mix.wav"), probe = dir.appendingPathComponent("solo.wav")
            try writeStereo(mix, to: input)
            try writeStereo(solo, to: probe)
            let eSolo = Self.e(solo)
            for v in variants {
                let (t, p, _) = try Self.split(v, input, probe: probe)
                var cases: [(String, Tracks, Tracks)] = [("gate-" + v.name, Self.gated(t, input: mix, gate: g),
                                                          Self.gated(p!, input: solo, gate: g))]
                if ungated.contains(v.name) { cases.insert((v.name, t, p!), at: 0) }
                for (name, tt, pp) in cases {
                    let leak = Self.e(pp[.left]!) + Self.e(pp[.right]!)
                    var line = "SWEEP 1 \(name) · solo en L+R \(Self.db(leak, eSolo)) dB, solo en C \(Self.db(Self.e(pp[.center]!), eSolo)) dB;"
                    for s in GuitarSide.allCases {
                        line += " diafonía \(s.rawValue) \(Self.f1(PanSplitterTests.crosstalkDB(tt[s]!, expected: refs[s]!))) dB"
                    }
                    print(line + "; C frente al solo \(Self.db(Self.e(tt[.center]!), eSolo)) dB")
                }
            }
        }

        // (2) Temas completos sin centro, sin puerta: C frente a la entrada y decisión a −24 dB.
        // Con puerta la puerta está vacía: C' = 0 exacto (descartada) y L', R' = canales.
        for song in songs {
            for v in variants where ungated.contains(v.name) {
                let (_, _, r) = try Self.split(v, song.appendingPathComponent("stems/guitar.wav"))
                let rel = r.tracks.first { $0.side == .center }!.level.rmsDB - r.inputLevel.rmsDB
                print("SWEEP 2 \(v.name) · \(song.lastPathComponent) completo: C \(String(format: "%+.1f", rel)) dB frente a la "
                      + "entrada → \(rel < -PanSplitter.defaultRelativeDiscardDB ? "descartada" : "SE GUARDA")")
            }
        }

        // (3) Diafonía L/R en 12 s de T1 y T2 frente a guitar_parts (con puerta vacía: L', R' = canales).
        for song in [t1, t2].compactMap({ $0 }) {
            let refs = try Self.loadRefs(song)
            let crop = try PanSplitterT1Tests.readCrop(song.appendingPathComponent("stems/guitar.wav"),
                                                       start: Self.cropStart, seconds: Self.cropSeconds)
            let dir = try makeTempDir("sweep-crop")
            defer { try? FileManager.default.removeItem(at: dir) }
            let input = dir.appendingPathComponent("guitar.wav")
            try writeStereo(crop, to: input)
            func line(_ name: String, _ t: Tracks) -> String {
                "SWEEP 3 \(name) · \(song.lastPathComponent) 12 s:"
                    + [GuitarSide.left, .right].map {
                        " diafonía \($0.rawValue) \(Self.f1(PanSplitterTests.crosstalkDB(t[$0]!, expected: refs[$0]!))) dB"
                    }.joined() + ", C \(Self.db(Self.e(t[.center]!), Self.e(crop))) dB frente a la entrada"
            }
            let n = crop.frameCount
            print(line("gate-*", Self.gated([.left: crop, .right: crop, .center: crop], input: crop,
                                            gate: [Float](repeating: 0, count: n))))
            for v in variants where ungated.contains(v.name) { print(line(v.name, try Self.split(v, input).0)) }
        }

        // (4) Platero: C dentro (157–187 s) y fuera (60–90 s) del solo, por puerta, y recortes a su nivel real.
        guard let platero = env("TF_PAN_PLATERO").map({ URL(fileURLWithPath: $0) }) else { return }
        let gates: [(String, [(Double, Double)])] = (env("TF_PAN_PLATERO_GATES") ?? "ideal=157-187")
            .split(separator: ";").map { item in
                let kv = item.split(separator: "=")
                return (String(kv[0]), kv[1].split(separator: ",").map {
                    let ab = $0.split(separator: "-").compactMap { Double($0) }
                    return (ab[0], ab[1])
                })
            }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let sweep = repo.appendingPathComponent("Temp/bench/platero/sweep", isDirectory: true)
        try FileManager.default.createDirectory(at: sweep, withIntermediateDirectories: true)
        let src = try AudioIO.readStereo(platero)
        let rate = Int(src.sampleRate)
        func range(_ s0: Int) -> Range<Int> { s0 * rate..<min(src.frameCount, (s0 + Self.clipSeconds) * rate) }
        func cut(_ a: StereoAudio, _ r: Range<Int>, _ url: URL) throws {
            try writeStereo(StereoAudio(left: Array(a.left[r]), right: Array(a.right[r]), sampleRate: a.sampleRate), to: url)
        }
        for s0 in Self.plateroSegments {
            let url = sweep.appendingPathComponent("guitar_\(s0)-\(s0 + Self.clipSeconds)s.wav")
            if !FileManager.default.fileExists(atPath: url.path) { try cut(src, range(s0), url) }
        }
        let gateArrays = gates.map { ($0.0, Self.gate($0.1, frames: src.frameCount, rate: src.sampleRate)) }
        for v in variants {
            let (t, _, _) = try Self.split(v, platero)
            var cases: [(label: String, folder: String?, tracks: Tracks)] = gateArrays.enumerated().map { i, g in
                ("gate-\(g.0)-\(v.name)", i == 0 ? "gate-\(v.name)" : nil, Self.gated(t, input: src, gate: g.1))
            }
            if ungated.contains(v.name) { cases.insert((v.name, v.name, t), at: 0) }
            for c in cases {
                let cAll = Self.e(c.tracks[.center]!)
                var line = "SWEEP 4 \(c.label) · Platero completo C \(Self.db(cAll, Self.e(src))) dB;"
                for s0 in Self.plateroSegments {
                    let rr = range(s0)
                    let eIn = Self.e(src, rr)
                    line += " \(s0)-\(s0 + Self.clipSeconds) s:"
                    for s in GuitarSide.allCases { line += " \(s.rawValue) \(Self.db(Self.e(c.tracks[s]!, rr), eIn))" }
                    line += " dB;"
                    if let f = c.folder {
                        let folder = sweep.appendingPathComponent("\(f)/\(s0)-\(s0 + Self.clipSeconds)s", isDirectory: true)
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        for s in GuitarSide.allCases { try cut(c.tracks[s]!, rr, folder.appendingPathComponent(s.fileName)) }
                    }
                }
                if c.label.hasPrefix("gate-\(gates[0].0)-") {
                    // Fuera de la puerta las pistas deben ser exactamente los canales y C silencio.
                    let rr = range(60)
                    var dl: Float = 0, dr: Float = 0, cm: Float = 0
                    for k in rr {
                        dl = max(dl, abs(c.tracks[.left]!.left[k] - src.left[k]), abs(c.tracks[.right]!.left[k]))
                        dr = max(dr, abs(c.tracks[.right]!.right[k] - src.right[k]), abs(c.tracks[.left]!.right[k]))
                        cm = max(cm, abs(c.tracks[.center]!.left[k]), abs(c.tracks[.center]!.right[k]))
                    }
                    line += " 60–90 s máx |L−canal| \(dl), |R−canal| \(dr), |C| \(cm);"
                    XCTAssertEqual(dl, 0); XCTAssertEqual(dr, 0); XCTAssertEqual(cm, 0)
                }
                print(line + (c.folder.map { " recortes \(sweep.appendingPathComponent($0).path)" } ?? ""))
            }
        }
    }
}
