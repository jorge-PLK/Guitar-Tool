import XCTest
@testable import StemKit

final class SpectralTransformTests: XCTestCase {
    /// STFT → iSTFT con ruido, en longitudes múltiplo y no múltiplo del hop. Tolerancia: error máximo < 1e-5.
    func testRoundTripNoiseMaxErrorBelow1e5() {
        var rng = SeededRandom(42)
        for length in [1_025, 2_048, 4_097, 12_345, 44_100, 100_001, RoformerContract.chunk] {
            let stft = SpectralTransform(length: length)
            let x = (0..<length).map { _ in rng.unit() }
            var spec = [Float](repeating: 0, count: stft.specCount)
            var y = [Float](repeating: 0, count: length)
            x.withUnsafeBufferPointer { stft.forward($0.baseAddress!, channel: 1, into: &spec) }
            spec.withUnsafeBufferPointer { stft.inverse($0.baseAddress!, channel: 1, into: &y) }
            var maxErr: Float = 0
            for k in 0..<length { maxErr = max(maxErr, abs(x[k] - y[k])) }
            XCTAssertLessThan(maxErr, 1e-5, "longitud \(length): error máximo \(maxErr)")
            print("STFT ida y vuelta, longitud \(length) (frames \(stft.frames)): error máximo \(maxErr)")
        }
    }

    /// Hop 441 del modelo de solista (`MaskModelContract.leadRhythm`): misma tolerancia de ida y vuelta (< 1e-5),
    /// y un impulso vuelve en su muestra exacta (alineación de 0 muestras, sin retardo del enventanado).
    func testRoundTripHop441AndImpulseAlignment() {
        let hop = MaskModelContract.leadRhythm.hop
        var rng = SeededRandom(441)
        for length in [1_025, 44_100, MaskModelContract.leadRhythm.chunk] {
            let stft = SpectralTransform(length: length, hop: hop)
            let x = (0..<length).map { _ in rng.unit() }
            var spec = [Float](repeating: 0, count: stft.specCount)
            var y = [Float](repeating: 0, count: length)
            x.withUnsafeBufferPointer { stft.forward($0.baseAddress!, channel: 0, into: &spec) }
            spec.withUnsafeBufferPointer { stft.inverse($0.baseAddress!, channel: 0, into: &y) }
            var maxErr: Float = 0
            for k in 0..<length { maxErr = max(maxErr, abs(x[k] - y[k])) }
            XCTAssertLessThan(maxErr, 1e-5, "hop \(hop), longitud \(length): error máximo \(maxErr)")
            print("STFT hop \(hop) ida y vuelta, longitud \(length): error máximo \(maxErr)")
        }
        let length = 10_000
        let stft = SpectralTransform(length: length, hop: hop)
        for p in [0, 1, 1_023, 4_567, length - 1] {
            var x = [Float](repeating: 0, count: length)
            x[p] = 1
            var spec = [Float](repeating: 0, count: stft.specCount)
            var y = [Float](repeating: 0, count: length)
            x.withUnsafeBufferPointer { stft.forward($0.baseAddress!, channel: 1, into: &spec) }
            spec.withUnsafeBufferPointer { stft.inverse($0.baseAddress!, channel: 1, into: &y) }
            let peak = y.indices.max { abs(y[$0]) < abs(y[$1]) }!
            var leak: Float = 0
            for k in 0..<length where k != p { leak = max(leak, abs(y[k])) }
            XCTAssertEqual(peak, p, "impulso en \(p) vuelve en \(peak)")
            XCTAssertEqual(y[p], 1, accuracy: 1e-5)
            XCTAssertLessThan(leak, 1e-5, "impulso en \(p): fuga máxima \(leak)")
        }
    }

    /// Cada trama coincide con la DFT directa (e^{-i}, como numpy.rfft/torch.stft) de la trama rellenada
    /// con reflect y enventanada con Hann periódica. Incluye DC y Nyquist (imaginaria 0).
    func testForwardMatchesDirectDFT() {
        var rng = SeededRandom(7)
        let length = 8_000
        let x = (0..<length).map { _ in rng.unit() }
        let stft = SpectralTransform(length: length)
        var spec = [Float](repeating: 0, count: stft.specCount)
        x.withUnsafeBufferPointer { stft.forward($0.baseAddress!, channel: 0, into: &spec) }
        let n = 2048, half = 1024
        func padded(_ p: Int) -> Double {      // reflect de numpy sobre la señal original
            let q = p - half
            if q < 0 { return Double(x[-q]) }
            if q >= length { return Double(x[2 * (length - 1) - q]) }
            return Double(x[q])
        }
        var worst = 0.0
        for t in [0, 1, 7, stft.frames - 1] {
            let frame = (0..<n).map { k in padded(t * 512 + k) * (0.5 - 0.5 * cos(2 * Double.pi * Double(k) / Double(n))) }
            for f in [0, 1, 2, 100, 511, 1000, 1023, 1024] {
                var re = 0.0, im = 0.0
                for k in 0..<n {
                    let a = -2 * Double.pi * Double(f * k % n) / Double(n)
                    re += frame[k] * cos(a)
                    im += frame[k] * sin(a)
                }
                let i = stft.specIndex(bin: f, channel: 0, frame: t)
                worst = max(worst, abs(Double(spec[i]) - re), abs(Double(spec[i + 1]) - im))
            }
        }
        XCTAssertLessThan(worst, 1e-3, "diferencia máxima con la DFT directa \(worst)")
        print("STFT frente a DFT directa: diferencia máxima \(worst)")
    }

    /// Layout `spec`: fila 2·f + canal, re/im en el último eje. Canal 0 = cos en el bin 64,
    /// canal 1 = sin en el bin 128. Con Hann periódica: X[64] = +512 (real) solo en la fila 128,
    /// X[128] = −512i solo en la fila 257, y los vecinos k ± 1 valen −256 (cos) / +256i (sin).
    func testPackingRowIsTwoFPlusChannel() {
        let length = 16_384
        let stft = SpectralTransform(length: length)
        let cosine = (0..<length).map { Float(cos(2 * Double.pi * 64 * Double($0) / 2048)) }
        let sine = (0..<length).map { Float(sin(2 * Double.pi * 128 * Double($0) / 2048)) }
        var spec = [Float](repeating: 0, count: stft.specCount)
        cosine.withUnsafeBufferPointer { stft.forward($0.baseAddress!, channel: 0, into: &spec) }
        sine.withUnsafeBufferPointer { stft.forward($0.baseAddress!, channel: 1, into: &spec) }
        let t = 10, T = stft.frames
        func at(_ row: Int, _ ri: Int) -> Float { spec[(row * T + t) * 2 + ri] }
        let tol: Float = 1e-2
        XCTAssertEqual(at(2 * 64 + 0, 0), 512, accuracy: tol)
        XCTAssertEqual(at(2 * 64 + 0, 1), 0, accuracy: tol)
        XCTAssertEqual(at(2 * 63 + 0, 0), -256, accuracy: tol)
        XCTAssertEqual(at(2 * 65 + 0, 0), -256, accuracy: tol)
        XCTAssertEqual(at(2 * 64 + 1, 0), 0, accuracy: tol)   // el canal 1 no tiene nada en el bin 64
        XCTAssertEqual(at(2 * 128 + 1, 0), 0, accuracy: tol)
        XCTAssertEqual(at(2 * 128 + 1, 1), -512, accuracy: tol)
        XCTAssertEqual(at(2 * 127 + 1, 1), 256, accuracy: tol)
        XCTAssertEqual(at(2 * 128 + 0, 0), 0, accuracy: tol)  // el canal 0 no tiene nada en el bin 128
        XCTAssertEqual(at(2 * 128 + 0, 1), 0, accuracy: tol)
        XCTAssertEqual(stft.specCount, 2 * 1025 * T * 2)
    }

    func testContractShapes() {
        XCTAssertEqual(RoformerContract.chunk, 588_800)
        XCTAssertEqual(SpectralTransform(length: RoformerContract.chunk).frames, 1151)
        XCTAssertEqual(Stem.allCases.map(\.rawValue), ["bass", "drums", "other", "vocals", "guitar", "piano"])
    }

    func testReflectPadMatchesNumpy() {
        let x: [Float] = [0, 1, 2, 3, 4]
        var out = [Float](repeating: -1, count: 5 + 3 + 2)
        x.withUnsafeBufferPointer { reflectPad($0.baseAddress!, count: 5, left: 3, right: 2, into: &out) }
        XCTAssertEqual(out, [3, 2, 1, 0, 1, 2, 3, 4, 3, 2])   // np.pad([0..4], (3, 2), "reflect")
    }
}
