import Foundation
import XCTest
@testable import StemKit

/// Generador determinista (SplitMix64) para ruido reproducible.
struct SeededRandom {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// Uniforme en [-1, 1).
    mutating func unit() -> Float { Float(Double(next() >> 11) / Double(1 << 53) * 2 - 1) }
}

/// Suma de cosenos sin componente continua: Σ A·cos(ω n + φ). `quadrature` da Σ A·sin(ω n + φ).
struct ToneMix {
    struct Tone { let hz: Double; let amp: Double; let phase: Double }
    let tones: [Tone]
    let rate: Double

    static func standard(rate: Double, channel: Int) -> ToneMix {
        let base: [(Double, Double)] = [(220.7, 0.20), (443.3, 0.15), (1_031.9, 0.10), (2_718.2, 0.08),
                                        (5_003.1, 0.05), (9_871.4, 0.03), (15_123.4, 0.02)]
        return ToneMix(tones: base.enumerated().map { i, t in
            Tone(hz: t.0 * (channel == 0 ? 1 : 1.0137), amp: t.1, phase: Double(i) * 0.7 + Double(channel))
        }, rate: rate)
    }

    /// Fundido de entrada/salida por defecto (coseno alzado). Sin él, el relleno reflect de la canción crea
    /// un pico en la derivada en los extremos y el algoritmo de referencia, al poner a cero el bin 0 de
    /// esas tramas, pierde unos 52-60 dB de SNR global en señales de pocos segundos (medido: Swift coincide
    /// con la referencia Python a 136 dB también ahí; ver PythonReferenceTests).
    static let defaultTaper = 8_192

    func render(_ n: Int, quadrature: Bool = false, taper: Int = ToneMix.defaultTaper) -> [Float] {
        var out = [Float](repeating: 0, count: n)
        for t in tones {
            let w = 2 * Double.pi * t.hz / rate
            for k in 0..<n {
                let a = w * Double(k) + t.phase
                out[k] += Float(t.amp * (quadrature ? sin(a) : cos(a)))
            }
        }
        let m = min(taper, n / 2)
        for k in 0..<m {
            let g = Float(0.5 - 0.5 * cos(Double.pi * Double(k) / Double(m)))
            out[k] *= g
            out[n - 1 - k] *= g
        }
        return out
    }
}

/// SNR (= SDR global de Probes/P4-modelos/common/metrics.py): 10·log10(Σ ref² / Σ (ref − est)²).
func snrDB(_ ref: [Float], _ est: [Float]) -> Double {
    let n = min(ref.count, est.count)
    var num = 0.0, den = 0.0
    for k in 0..<n {
        let r = Double(ref[k]), e = Double(est[k])
        num += r * r
        den += (r - e) * (r - e)
    }
    return 10 * log10(max(num, 1e-30) / max(den, 1e-30))
}

func snrDB(_ ref: StereoAudio, _ est: StereoAudio) -> Double {
    snrDB(ref.left + ref.right, est.left + est.right)
}

func writeStereo(_ audio: StereoAudio, to url: URL) throws {
    let w = try AudioIO.StereoWriter(url: url, sampleRate: audio.sampleRate)
    try audio.left.withUnsafeBufferPointer { l in
        try audio.right.withUnsafeBufferPointer { r in
            try w.write(left: l.baseAddress!, right: r.baseAddress!, count: audio.frameCount)
        }
    }
    w.close()
}

func makeTempDir(_ name: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("stemkit-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Directorio de los productos compilados (junto al bundle .xctest): ahí están tf-separate y tf-memhog.
func builtProduct(_ name: String) -> URL {
    let bundle = Bundle(for: BundleLocator.self).bundleURL
    return bundle.deletingLastPathComponent().appendingPathComponent(name)
}

private final class BundleLocator {}

/// `true` mientras exista un proceso con ese pid.
func processAlive(_ pid: pid_t) -> Bool {
    kill(pid, 0) == 0 || errno == EPERM
}
