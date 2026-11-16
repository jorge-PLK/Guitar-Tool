import Foundation
import XCTest
@testable import StemKit

/// Guía por notas del centro (`PanSplitter.centerNotes`): un solo mono en el centro bajo un ruido fuerte
/// solo a la izquierda (el panorama de sus bins se va a la izquierda y el solo se cuela en L). La sonda
/// aplica las mismas máscaras al solo aislado: su energía en L + R es la fuga exacta.
final class PanSplitterGuideTests: XCTestCase {
    static let rate = 44_100.0
    static let seconds = 4.0
    static let note = PanCenterNote(start: 0.5, end: 3.5, midi: 64)

    /// Solo: 6 armónicos (1/k) de E4 con vibrato de ±30 cents a 5 Hz, en `note`.
    static func solo(_ n: Int) -> [Float] {
        let f0 = 440 * pow(2, (note.midi - 69) / 12)
        var phase = 0.0
        return (0..<n).map { i in
            let t = Double(i) / rate
            let f = f0 * pow(2, 30 / 1200 * sin(2 * Double.pi * 5 * t))
            phase += 2 * Double.pi * f / rate
            guard t >= note.start && t < note.end else { return 0 }
            return Float((1...6).reduce(0.0) { $0 + 0.05 / Double($1) * sin(Double($1) * phase) })
        }
    }

    func testGuideMovesCenterSoloOutOfSides() throws {
        let n = Int(Self.seconds * Self.rate)
        let s = Self.solo(n)
        var rng = SeededRandom(11)
        let a = (0..<n).map { _ in 0.3 * rng.unit() }   // ruido fuerte solo a la izquierda
        let b = (0..<n).map { _ in 0.03 * rng.unit() }  // y uno débil a la derecha
        let mix = StereoAudio(left: (0..<n).map { s[$0] + a[$0] }, right: (0..<n).map { s[$0] + b[$0] },
                              sampleRate: Self.rate)
        let dir = try makeTempDir("pan-guide-unit")
        let input = dir.appendingPathComponent("mix.wav"), probe = dir.appendingPathComponent("solo.wav")
        try writeStereo(mix, to: input)
        try writeStereo(StereoAudio(left: s, right: s, sampleRate: Self.rate), to: probe)
        let eSolo = 2 * PanSplitterT1Tests.energy(s)

        func run(_ notes: [PanCenterNote], _ name: String) throws -> (leakDB: Double, sideNoiseDB: Double) {
            var splitter = PanSplitter(relativeDiscardDB: 200, centerNotes: notes).withoutGate()
            splitter.probeInput = probe
            let out = dir.appendingPathComponent(name)
            _ = try splitter.split(input: input, outputDirectory: out)
            let tracks = try GuitarSide.allCases.map { try AudioIO.readStereo(out.appendingPathComponent($0.fileName)) }
            // Las pistas siguen sumando la entrada.
            var maxErr: Float = 0
            for k in 0..<n {
                maxErr = max(maxErr, abs(tracks.reduce(0) { $0 + $1.left[k] } - mix.left[k]),
                             abs(tracks.reduce(0) { $0 + $1.right[k] } - mix.right[k]))
            }
            XCTAssertLessThan(maxErr, 1e-5, name)
            var leak = 0.0
            var probeL: [Float] = []
            for side in [GuitarSide.left, .right] {
                let p = try AudioIO.readStereo(out.appendingPathComponent("probe-\(side.fileName)"))
                leak += PanSplitterT1Tests.energy(p.left) + PanSplitterT1Tests.energy(p.right)
                if side == .left { probeL = p.left }
            }
            // Ruido que se queda en su pista L (lo que la guía no debe robar): pista L menos su parte de solo.
            let kept = PanSplitterT1Tests.energy(zip(tracks[0].left, probeL).map { $0 - $1 })
            let noise = PanSplitterT1Tests.energy(a)
            return (10 * log10(leak / eSolo), 10 * log10(kept / noise))
        }

        let off = try run([], "sin-guia")
        let on = try run([Self.note], "con-guia")
        print("PanSplitter guía: solo en L+R \(String(format: "%.1f", off.leakDB)) → \(String(format: "%.1f", on.leakDB)) dB; "
              + "pista L frente al ruido L \(String(format: "%+.2f", off.sideNoiseDB)) → \(String(format: "%+.2f", on.sideNoiseDB)) dB")
        // Umbral del experimento 2 (orquestador, 15/11/2026): la fuga del solo baja al menos 3 dB.
        XCTAssertLessThan(on.leakDB, off.leakDB - 3)
        // Y la pista L no pierde más de 1 dB del ruido que es suyo.
        XCTAssertGreaterThan(on.sideNoiseDB, off.sideNoiseDB - 1)
    }

    /// Sin notas, la guía no cambia nada (mismo resultado que antes, muestra a muestra).
    func testNoNotesIsIdentical() throws {
        let n = Int(1.5 * Self.rate)
        var rng = SeededRandom(5)
        let mix = StereoAudio(left: (0..<n).map { _ in 0.2 * rng.unit() }, right: (0..<n).map { _ in 0.1 * rng.unit() },
                              sampleRate: Self.rate)
        let dir = try makeTempDir("pan-guide-none")
        let input = dir.appendingPathComponent("mix.wav")
        try writeStereo(mix, to: input)
        let ra = try PanSplitter(relativeDiscardDB: 200).withoutGate().split(input: input, outputDirectory: dir.appendingPathComponent("a"))
        // Una nota fuera del audio no toca ningún bin.
        let rb = try PanSplitter(relativeDiscardDB: 200, centerNotes: [PanCenterNote(start: 10, end: 11, midi: 60)]).withoutGate()
            .split(input: input, outputDirectory: dir.appendingPathComponent("b"))
        XCTAssertEqual(ra.tracks.map(\.side), rb.tracks.map(\.side))
        for side in ra.tracks.map(\.side) {
            let x = try AudioIO.readStereo(dir.appendingPathComponent("a/\(side.fileName)"))
            let y = try AudioIO.readStereo(dir.appendingPathComponent("b/\(side.fileName)"))
            XCTAssertEqual(x.left, y.left, side.rawValue)
            XCTAssertEqual(x.right, y.right, side.rawValue)
        }
    }
}
