import XCTest
@testable import AudioKit

/// Detector de escalones en las marcas de host del HAL (diagnóstico de los saltos de 12 muestras de la Flex Prime,
/// 15/11/2026). Marcas sintéticas como las de la pedalera: 512 muestras por ciclo a 48 kHz, salida 1112 muestras
/// por delante de la entrada, deriva de 2 ppm entre el reloj del Mac y el del aparato y ±1 muestra de ruido en la
/// hora de host de cada ciclo.
final class HostTimingTests: XCTestCase {
    static let fs = 48_000.0
    static let block = 512.0
    static let skew = 1_112.0
    /// Tolerancia del tamaño de un escalón detectado, en muestras.
    static let sizeTolerance = 0.5

    /// `inputSlip`/`outputSlip`: (instante en s, muestras) en que la hora de host de ese lado se adelanta.
    static func cycles(seconds: Double, inputSlip: [(Double, Double)] = [], outputSlip: [(Double, Double)] = [],
                       jitterSamples: Double = 1, driftPPM: Double = 2) -> [HostTimingCycle] {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func noise() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return (Double(seed >> 11) / Double(1 << 53) * 2 - 1) * jitterSamples / fs
        }
        let h0 = 86_400.0, s0 = 1_000_000.0
        let n = Int(seconds * fs / block)
        return (0..<n).map { k in
            let inS = s0 + Double(k) * block
            let t = Double(k) * block / fs
            let shiftIn = inputSlip.filter { t >= $0.0 }.reduce(0) { $0 + $1.1 } / fs
            let shiftOut = outputSlip.filter { t >= $0.0 }.reduce(0) { $0 + $1.1 } / fs
            let hIn = h0 + t * (1 + driftPPM * 1e-6) - shiftIn + noise()
            let hOut = h0 + (t + skew / fs) * (1 + driftPPM * 1e-6) - shiftOut + noise()
            return HostTimingCycle(inputSampleTime: inS, outputSampleTime: inS + skew, inputHostSeconds: hIn,
                                   outputHostSeconds: hOut, inputRateScalar: 1 + driftPPM * 1e-6,
                                   outputRateScalar: 1 + driftPPM * 1e-6)
        }
    }

    /// 300 s limpios: ni un escalón, y la media por segundo de la diferencia de host es 1112 muestras a 0,3 (el
    /// ruido de ±1 muestra promediado en ~94 ciclos deja σ ≈ 0,08).
    func testCleanSessionHasNoSteps() {
        let r = HostTimingAnalysis.analyze(cycles: Self.cycles(seconds: 300), latencies: [], sampleRate: Self.fs)
        XCTAssertEqual(r.steps, [])
        XCTAssertEqual(r.seconds.count, 300)
        for s in r.seconds { XCTAssertEqual(s.hostOutMinusInSamples, Self.skew, accuracy: 0.3) }
    }

    /// Como la pasada C: −24 en 68,25 s y −12 en 247,75 s, en la entrada. Se ven en el residuo de entrada y en la
    /// diferencia salida − entrada, con su tamaño a ±0,5 muestras y en el segundo en que ocurren.
    func testInputSlipsAreFoundWithTimeAndSize() throws {
        let c = Self.cycles(seconds: 300, inputSlip: [(68.25, 24), (247.75, 12)])
        let r = HostTimingAnalysis.analyze(cycles: c, latencies: [], sampleRate: Self.fs)
        let t0 = r.seconds[0].hostSeconds
        let input = r.steps.filter { $0.series == .inputResidual }
        let skew = r.steps.filter { $0.series == .hostOutMinusIn }
        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(skew.count, 2)
        XCTAssertTrue(r.steps.filter { $0.series == .outputResidual }.isEmpty)
        for (found, want) in zip(input, [(68.25, -24.0), (247.75, -12.0)]) {
            XCTAssertEqual(found.sizeSamples, want.1, accuracy: Self.sizeTolerance)
            XCTAssertLessThanOrEqual(abs(found.hostSeconds - t0 - want.0), 1)
        }
        for (found, want) in zip(skew, [24.0, 12.0]) { XCTAssertEqual(found.sizeSamples, want, accuracy: Self.sizeTolerance) }
    }

    /// Un deslizamiento de la salida sale en su residuo y con signo contrario en la diferencia; el de 3 muestras
    /// (el umbral) también cuenta, el de 2 no.
    func testOutputSlipAndThreshold() {
        let r = HostTimingAnalysis.analyze(cycles: Self.cycles(seconds: 60, outputSlip: [(17.75, 12), (40.5, 3)]),
                                           latencies: [], sampleRate: Self.fs)
        let out = r.steps.filter { $0.series == .outputResidual }.map(\.sizeSamples)
        let skew = r.steps.filter { $0.series == .hostOutMinusIn }.map(\.sizeSamples)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0], -12, accuracy: Self.sizeTolerance)
        XCTAssertEqual(out[1], -3, accuracy: Self.sizeTolerance)
        XCTAssertEqual(skew.count, 2)
        XCTAssertEqual(skew[0], -12, accuracy: Self.sizeTolerance)
        let small = HostTimingAnalysis.analyze(cycles: Self.cycles(seconds: 60, outputSlip: [(30.5, 2)]), latencies: [],
                                               sampleRate: Self.fs)
        XCTAssertEqual(small.steps, [])
    }

    /// Un cambio en las latencias declaradas cuenta como escalón con la diferencia del total.
    func testDeclaredLatencyChangeIsAStep() {
        let c = Self.cycles(seconds: 10)
        let t0 = c[0].inputHostSeconds
        func l(_ t: Double, _ stream: Int) -> DeclaredLatencySnapshot {
            DeclaredLatencySnapshot(hostSeconds: t0 + t, inputDevice: 100, inputSafety: 20, inputStream: stream,
                                    outputDevice: 100, outputSafety: 20, outputStream: 0)
        }
        let r = HostTimingAnalysis.analyze(cycles: c, latencies: [l(0, 0), l(1, 0), l(2, 12), l(3, 12)], sampleRate: Self.fs)
        XCTAssertEqual(r.steps, [HostTimingStep(series: .declaredLatency, hostSeconds: t0 + 2, sizeSamples: 12)])
        XCTAssertEqual(r.seconds[2].latencies?.inputStream, 12)
    }
}
