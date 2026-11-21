import Foundation
import XCTest
@testable import StemKit

/// Medidas informativas, sin umbral (mini-spec Fase 4, «Pruebas»): diafonía en 12 s de T1 frente a
/// `guitar_parts/`, y tiempo de la separación. Desactivadas salvo con variables de entorno:
///
///   TF_PAN_T1=<Probes/testaudio/out/T1>          referencia: stems/guitar.wav y guitar_parts/
///   TF_PAN_BSR=<…/bs_roformer_sw/out/stems/T1>   opcional: guitar.wav separada por BS-RoFormer SW
///   TF_PAN_PERF=1                                 opcional: tiempo con 4 min sintéticos
final class PanSplitterT1Tests: XCTestCase {
    /// Ventana de 12 s con las guitarras de los extremos y las de ±30 % sonando (barrido por segundos con
    /// las partes: máximo del mínimo de energía de los cuatro grupos).
    /// T1 (y T2): 40 s. Otro tramo con TF_PAN_START=<segundos> (T3: 14, con Gtr1/Gtr1DT abiertas y Gtr2 a −30 %;
    /// Gtr3 nunca suena a la vez que las otras).
    static let cropStart = ProcessInfo.processInfo.environment["TF_PAN_START"].flatMap(Double.init) ?? 40.0
    static let cropSeconds = 12.0

    private func env(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// TF_PAN_T1 puede apuntar también a T2 o T3: las partes se asignan a un lado por su propio panorama.
    private var tag: String { env("TF_PAN_T1").map { URL(fileURLWithPath: $0).lastPathComponent } ?? "T1" }

    static func readCrop(_ url: URL, start: Double, seconds: Double) throws -> StereoAudio {
        let file = try AudioIO.openReader(url)
        let rate = file.sampleRate
        let s = Int(start * rate), n = min(Int(seconds * rate), max(0, file.frameCount - s))
        var left = [Float](repeating: 0, count: n), right = left
        let got = try left.withUnsafeMutableBufferPointer { l in
            try right.withUnsafeMutableBufferPointer { r in
                try AudioIO.read(file, from: s, count: n, left: l.baseAddress!, right: r.baseAddress!)
            }
        }
        return StereoAudio(left: Array(left.prefix(got)), right: Array(right.prefix(got)), sampleRate: rate)
    }

    static func energy(_ x: [Float]) -> Double { x.reduce(0) { $0 + Double($1) * Double($1) } }

    static func confidenceText(_ c: PanConfidence) -> String {
        "confianza \(c.level.rawValue) (score \(String(format: "%.2f", c.score)), foco "
            + "\(String(format: "%.2f", c.focus)), riesgo \(String(format: "%.2f", c.mixRisk)))"
    }

    static func similarityText(_ r: PanSplitResult) -> String {
        [(GuitarSide.left, GuitarSide.right), (.left, .center), (.center, .right)].map { a, b in
            "\(a.rawValue)-\(b.rawValue) \(String(format: "%.2f", r.envelopeSimilarity[.init(a: a, b: b)] ?? .nan))"
        }.joined(separator: ", ")
    }

    /// Lado de una parte suelta por su propio panorama (mismo índice que PanSplitter, sobre la energía).
    static func side(of part: StereoAudio) -> GuitarSide {
        let p = atan2(energy(part.right).squareRoot(), energy(part.left).squareRoot()) * 4 / Double.pi - 1
        let edge = Double(PanSplitter.defaultCenterWidth + PanSplitter.defaultTransitionWidth / 2)
        return p < -edge ? .left : p > edge ? .right : .center
    }

    static func silence(_ n: Int) -> StereoAudio {
        StereoAudio(left: [Float](repeating: 0, count: n), right: [Float](repeating: 0, count: n), sampleRate: 44_100)
    }

    static func add(_ x: StereoAudio, into acc: inout StereoAudio, gain: Float = 1) {
        for k in 0..<acc.frameCount {
            acc.left[k] += gain * x.left[k]
            acc.right[k] += gain * x.right[k]
        }
    }

    /// Partes sueltas de `guitar_parts/` sumadas por lado (según su propio panorama).
    private func loadRefs(_ song: URL) throws -> [GuitarSide: StereoAudio] {
        let partsDir = song.appendingPathComponent("guitar_parts")
        let names = try FileManager.default.contentsOfDirectory(atPath: partsDir.path)
            .filter { $0.hasSuffix(".wav") }.sorted()
        let n = Int(Self.cropSeconds * 44_100)
        var refs: [GuitarSide: StereoAudio] = [:]
        for side in GuitarSide.allCases { refs[side] = Self.silence(n) }
        for name in names {
            let part = try Self.readCrop(partsDir.appendingPathComponent(name), start: Self.cropStart,
                                         seconds: Self.cropSeconds)
            guard Self.energy(part.left) + Self.energy(part.right) > 1e-6 else {
                print("\(song.lastPathComponent) · parte \(name) → en silencio en la ventana")
                continue
            }
            let side = Self.side(of: part)
            print("\(song.lastPathComponent) · parte \(name) → \(side.rawValue)")
            Self.add(part, into: &refs[side]!)
        }
        return refs
    }

    /// Separa `crop` e imprime, por lado, diafonía+pérdida frente a su referencia (si la hay), nivel frente a
    /// la entrada y confianza o motivo del descarte.
    private func report(_ label: String, crop: StereoAudio, refs: [GuitarSide: StereoAudio],
                        splitter: PanSplitter = PanSplitter().withoutGate()) throws {
        let dir = try makeTempDir("pan-report")
        let input = dir.appendingPathComponent("guitar.wav")
        try writeStereo(crop, to: input)
        let result = try splitter.split(input: input, outputDirectory: dir.appendingPathComponent("stems"))
        let eIn = Self.energy(crop.left) + Self.energy(crop.right)
        var line = "\(label):"
        for side in GuitarSide.allCases {
            let ref = refs[side]!
            let track = result.tracks.first { $0.side == side }
            let out = try track.map { try AudioIO.readStereo($0.url) } ?? Self.silence(crop.frameCount)
            let eOut = Self.energy(out.left) + Self.energy(out.right)
            line += "\n    \(side.rawValue):"
            if Self.energy(ref.left) + Self.energy(ref.right) > 0 {
                line += " diafonía+pérdida \(String(format: "%.1f", PanSplitterTests.crosstalkDB(out, expected: ref))) dB,"
            }
            line += " nivel \(String(format: "%.1f", 10 * log10(max(eOut, 1e-30) / eIn))) dB"
            if let t = track {
                line += ", " + Self.confidenceText(t.confidence)
            } else if let d = result.discarded.first(where: { $0.side == side }) {
                line += ", descartada \(d.reason)"
            }
        }
        print(line + "\n    envolventes " + Self.similarityText(result))
    }

    /// Variantes para los barridos (TF_PAN_SWEEP=1): centro, transición, radio y umbrales de coherencia.
    static var sweepVariants: [(String, PanSplitter)] {
        let rows: [(PanCenterModel, Float, Float, Int, Float, Float, Float)] = [
            (.gate, 0.15, 0.05, 6, 0.6, 0.85, 0),
            (.wiener, 0.15, 0.1, 10, 0.25, 1, 0), (.wiener, 0.15, 0.1, 10, 0.25, 1, 2),
            (.wiener, 0.15, 0.1, 10, 0.25, 1, 4), (.wiener, 0.15, 0.1, 20, 0.25, 1, 2),
            (.wiener, 0.15, 0.1, 10, 0.4, 1, 2)
        ]
        return rows.map { model, cw, tw, r, lo, hi, k in
            var s = PanSplitter(centerWidth: cw, transitionWidth: tw, relativeDiscardDB: 200).withoutGate()
            s.centerModel = model
            s.coherenceRadius = r
            s.coherenceLow = lo
            s.coherenceHigh = hi
            s.phasePenalty = k
            return ("\(model) centro \(cw)/\(tw) radio \(r) suelo \(lo) k \(k)", s)
        }
    }

    func testT1CrosstalkAgainstGuitarParts() throws {
        guard let t1 = env("TF_PAN_T1").map({ URL(fileURLWithPath: $0) }) else {
            throw XCTSkip("medida informativa de T1 desactivada (TF_PAN_T1 sin definir)")
        }
        let refs = try loadRefs(t1)
        var inputs: [(String, URL)] = [("stems/guitar.wav", t1.appendingPathComponent("stems/guitar.wav"))]
        if let bsr = env("TF_PAN_BSR") {
            inputs.append(("BS-RoFormer SW", URL(fileURLWithPath: bsr).appendingPathComponent("guitar.wav")))
        }
        for (label, url) in inputs {
            let crop = try Self.readCrop(url, start: Self.cropStart, seconds: Self.cropSeconds)
            try report("\(tag) · \(label)", crop: crop, refs: refs)
            if env("TF_PAN_SWEEP") == "1" && label == inputs[0].0 {
                for (name, s) in Self.sweepVariants { try report("\(tag) · barrido \(name)", crop: crop, refs: refs, splitter: s) }
            }
        }
    }

    /// Banco con referencia (orquestador): las dobladas abiertas de T2 más la solista 23_ElecGtr05 de T1
    /// devuelta a mono y puesta en el centro, al RMS medio de un lado de T2. TF_PAN_T1 y TF_PAN_T2.
    func testCenterSoloOverT2Doubles() throws {
        guard let t1 = env("TF_PAN_T1").map({ URL(fileURLWithPath: $0) }),
              let t2 = env("TF_PAN_T2").map({ URL(fileURLWithPath: $0) }) else {
            throw XCTSkip("banco solista en el centro desactivado (TF_PAN_T1 / TF_PAN_T2 sin definir)")
        }
        var refs = try loadRefs(t2)
        let part = try Self.readCrop(t1.appendingPathComponent("guitar_parts/23_ElecGtr05.wav"),
                                     start: Self.cropStart, seconds: Self.cropSeconds)
        // Pan +0,3 con potencia constante: L = x·cos θ, R = x·sin θ → x = L·cos θ + R·sin θ.
        let th = 1.3 * Double.pi / 4
        let mono = (0..<part.frameCount).map { Float(Double(part.left[$0]) * cos(th) + Double(part.right[$0]) * sin(th)) }
        let side = (Self.energy(refs[.left]!.left) + Self.energy(refs[.left]!.right)
                    + Self.energy(refs[.right]!.left) + Self.energy(refs[.right]!.right)) / 2
        let gain = Float((side / (2 * Self.energy(mono))).squareRoot())   // energía estéreo del centro = la de un lado
        let center = StereoAudio(left: mono.map { $0 * gain }, right: mono.map { $0 * gain }, sampleRate: 44_100)
        refs[.center] = center
        var mix = Self.silence(part.frameCount)
        for s in GuitarSide.allCases { Self.add(refs[s]!, into: &mix) }
        let eC = Self.energy(center.left) + Self.energy(center.right)
        print("solista: centro \(String(format: "%.1f", 10 * log10(eC / side))) dB frente a un lado de T2")
        try report("T2 + solista en el centro", crop: mix, refs: refs)
        if let dump = env("TF_PAN_DUMP").map({ URL(fileURLWithPath: $0) }) {
            // Para sacar las notas fuera (Basic Pitch): mezcla, solo y pistas actuales.
            try FileManager.default.createDirectory(at: dump, withIntermediateDirectories: true)
            try writeStereo(mix, to: dump.appendingPathComponent("mix.wav"))
            try writeStereo(center, to: dump.appendingPathComponent("solo.wav"))
            _ = try PanSplitter(relativeDiscardDB: 200).withoutGate().split(input: dump.appendingPathComponent("mix.wav"),
                                                              outputDirectory: dump.appendingPathComponent("stems"))
        }
        if let notesPath = env("TF_PAN_NOTES") {
            try guidedSoloReport(mix: mix, refs: refs, notes: URL(fileURLWithPath: notesPath))
        }
        if env("TF_PAN_SWEEP") == "1" {
            for (name, s) in Self.sweepVariants { try report("solista · barrido \(name)", crop: mix, refs: refs, splitter: s) }
        }
    }
    /// Experimento 2: notas del solo (JSON `[{start, end, pitch}]`, segundos del recorte) como guía. La sonda
    /// aplica las mismas máscaras al solo aislado: su energía en L + R es la fuga exacta del solo.
    private func guidedSoloReport(mix: StereoAudio, refs: [GuitarSide: StereoAudio], notes url: URL) throws {
        struct Note: Decodable { let start: Double, end: Double, pitch: Double }
        let notes = try JSONDecoder().decode([Note].self, from: Data(contentsOf: url))
            .map { PanCenterNote(start: $0.start, end: $0.end, midi: $0.pitch) }
        let dir = try makeTempDir("pan-guide")
        let input = dir.appendingPathComponent("mix.wav"), probe = dir.appendingPathComponent("solo.wav")
        try writeStereo(mix, to: input)
        try writeStereo(refs[.center]!, to: probe)
        let eSolo = Self.energy(refs[.center]!.left) + Self.energy(refs[.center]!.right)
        var variants: [(String, PanSplitter)] = [("sin guía", PanSplitter(relativeDiscardDB: 200).withoutGate())]
        for (mode, cents) in [(PanGuideMode.hard, 50.0), (.amplitude, 100), (.amplitude, 200)] {
            var s = PanSplitter(relativeDiscardDB: 200).withoutGate()
            s.centerNotes = notes
            s.guideMode = mode
            s.guideWidthCents = cents
            variants.append(("guía \(mode) ±\(Int(cents)) cents", s))
        }
        print("exp2 · \(notes.count) notas de \(url.lastPathComponent)")
        for (label, base) in variants {
            var s = base
            s.probeInput = probe
            let out = dir.appendingPathComponent(label.replacingOccurrences(of: " ", with: "_"))
            _ = try s.split(input: input, outputDirectory: out)
            var line = "exp2 · \(label):"
            var eLeak = 0.0
            for side in [GuitarSide.left, .right] {
                let p = try AudioIO.readStereo(out.appendingPathComponent("probe-\(side.fileName)"))
                eLeak += Self.energy(p.left) + Self.energy(p.right)
                let t = try AudioIO.readStereo(out.appendingPathComponent(side.fileName))
                line += " \(side.rawValue) diafonía \(String(format: "%.1f", PanSplitterTests.crosstalkDB(t, expected: refs[side]!))) dB,"
            }
            let c = try AudioIO.readStereo(out.appendingPathComponent(GuitarSide.center.fileName))
            line += " C diafonía \(String(format: "%.1f", PanSplitterTests.crosstalkDB(c, expected: refs[.center]!))) dB,"
            line += " solo en L+R \(String(format: "%.1f", 10 * log10(max(eLeak, 1e-30) / eSolo))) dB"
            print(line)
        }
    }

    func testFullLengthTiming() throws {
        let url: URL
        if let bsr = env("TF_PAN_BSR") {
            url = URL(fileURLWithPath: bsr).appendingPathComponent("guitar.wav")
        } else if let t1 = env("TF_PAN_T1") {
            url = URL(fileURLWithPath: t1).appendingPathComponent("stems/guitar.wav")
        } else {
            throw XCTSkip("tiempo con T1 desactivado (TF_PAN_T1 / TF_PAN_BSR sin definir)")
        }
        try timeSplit(url, label: "\(tag) ·completo")
    }

    func testFourMinuteTiming() throws {
        guard env("TF_PAN_PERF") == "1" else { throw XCTSkip("tiempo con 4 min desactivado (TF_PAN_PERF != 1)") }
        let rate = 44_100.0, n = Int(240 * rate)
        var rng = SeededRandom(7)
        var left = [Float](repeating: 0, count: n), right = [Float](repeating: 0, count: n)
        var a: Float = 0, b: Float = 0
        for k in 0..<n {
            // Dos ruidos de banda baja, uno a cada lado, más un poco de común.
            a = 0.98 * a + 0.02 * rng.unit()
            b = 0.98 * b + 0.02 * rng.unit()
            left[k] = a + 0.3 * b
            right[k] = b + 0.3 * a
        }
        let dir = try makeTempDir("pan-perf")
        let input = dir.appendingPathComponent("guitar.wav")
        try writeStereo(StereoAudio(left: left, right: right, sampleRate: rate), to: input)
        try timeSplit(input, label: "4 min sintéticos")
    }

    private func timeSplit(_ url: URL, label: String) throws {
        let file = try AudioIO.openReader(url)
        let minutes = Double(file.frameCount) / file.sampleRate / 60
        let dir = try makeTempDir("pan-time")
        let me = ProcessInfo.processInfo.processIdentifier
        let before = MemoryGuard.footprint(pid: me) ?? 0
        let t0 = Date()
        let result = try PanSplitter().withoutGate().split(input: url, outputDirectory: dir)
        let dt = Date().timeIntervalSince(t0)
        let after = MemoryGuard.footprint(pid: me) ?? 0
        print("PanSplitter \(label): \(String(format: "%.2f", minutes)) min en \(String(format: "%.2f", dt)) s → "
              + "\(String(format: "%.2f", dt / minutes)) s por minuto; pistas \(result.tracks.map(\.side.rawValue)); "
              + "huella \(before >> 20) → \(after >> 20) MB")
    }
}
