import Foundation
@testable import NativeDSP
import XCTest

final class DSPEngineTests: XCTestCase {
    /// Motor portátil frente a la salida de vDSP guardada (`DSPReferenceData.swift`), caso a caso. Es la
    /// prueba que cuenta en Windows; en el Mac comprueba además que la referencia sigue al día.
    func testPortableMatchesStoredVDSPReference() throws {
        var lines: [String] = []
        for name in DSPCases.names {
            guard let ref = DSPReference.values(name) else {
                XCTFail("\(name): sin referencia; regenerar con TF_NATIVEKIT_WRITE_REFS=1 Tools/test.sh NativeKit WriteReference")
                continue
            }
            let tol = DSPCases.tolerances[name]!
            let (rel, worst) = relativeError(DSPCases.run(name, DSPPortable.self), ref)
            lines.append(String(format: "%-22@ %.2e (tol %.1e, peor %d)", name as NSString, rel, tol, worst))
            XCTAssertLessThanOrEqual(rel, tol, "\(name): error relativo \(rel) en el elemento \(worst)")
        }
        print("DSP portátil vs referencia vDSP:\n" + lines.joined(separator: "\n"))
    }

    /// Latencia: pico de la correlación analítica (SignalMath) del motor portátil frente a vDSP guardado.
    func testCorrelationPeakMatchesStoredVDSPReference() throws {
        guard let ref = DSPReference.values("corr_peak") else { return XCTFail("sin referencia corr_peak") }
        let p = DSPCases.correlationPeak(DSPPortable.self)
        print(String(format: "pico de correlación portátil %d, %.9f (vDSP %d, %.9f), Δ %.2e muestras",
                     p.index, p.position, Int(ref[0]), ref[1], abs(p.position - ref[1])))
        XCTAssertEqual(p.index, Int(ref[0]))
        XCTAssertEqual(p.position, ref[1], accuracy: DSPTolerance.correlationPeakSamples)
        XCTAssertEqual(p.value, ref[2], accuracy: ref[2] * DSPTolerance.fftDouble)
    }

    /// Setups ejecutados a la vez desde varios hilos (los paquetes comparten un setup en `concurrentPerform`).
    func testPortableSetupsAreThreadSafe() {
        let setup = DSPPortable.RealDFT(count: 512, direction: .forward)!
        let x = DSPCases.tones(512)
        @Sendable func once() -> [Float] {
            var ir = [Float](repeating: 0, count: 256), ii = ir, or = ir, oi = ir
            for j in 0..<256 { ir[j] = x[2 * j]; ii[j] = x[2 * j + 1] }
            setup.execute(ir, ii, &or, &oi)
            return or + oi
        }
        let expected = once()
        let lock = NSLock()
        nonisolated(unsafe) var mismatches = 0
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            if once() != expected { lock.withLock { mismatches += 1 } }
        }
        XCTAssertEqual(mismatches, 0)
    }

    #if canImport(Accelerate)
    /// Los dos motores, operación por operación, en el Mac.
    func testEnginesAgreeOperationByOperation() throws {
        var lines: [String] = []
        for name in DSPCases.names {
            let tol = DSPCases.tolerances[name]!
            let v = DSPCases.run(name, DSPAccelerate.self), p = DSPCases.run(name, DSPPortable.self)
            let (rel, worst) = relativeError(p, v)
            lines.append(String(format: "%-22@ %.2e (tol %.1e)", name as NSString, rel, tol))
            XCTAssertLessThanOrEqual(rel, tol, "\(name): error relativo \(rel) en el elemento \(worst)")
        }
        print("DSP portátil vs vDSP:\n" + lines.joined(separator: "\n"))
    }

    /// La convención empaquetada ×2 de zrop con n = 4096 (la de P8) y n = 2048 (LogMel, DrumSpectrogram).
    func testRealDFTPackedConventionAtProductionSizes() {
        for len in [2048, 4096] {
            let half = len / 2, x = DSPCases.tones(len)
            var ir = [Float](repeating: 0, count: half), ii = ir
            for j in 0..<half { ir[j] = x[2 * j]; ii[j] = x[2 * j + 1] }
            func run<E: DSPEngine>(_: E.Type) -> [Double] {
                let s = E.RealDFT(count: len, direction: .forward)!
                var or = [Float](repeating: 0, count: half), oi = or
                s.execute(ir, ii, &or, &oi)
                return flat(or + oi)
            }
            let (rel, worst) = relativeError(run(DSPPortable.self), run(DSPAccelerate.self))
            print(String(format: "zrop %d: error relativo %.2e (tolerancia %.0e)", len, rel, DSPTolerance.fft))
            XCTAssertLessThanOrEqual(rel, DSPTolerance.fft, "n = \(len), elemento \(worst)")
        }
    }

    /// Disposición del estado del biquad: medio filtrado con vDSP y la otra mitad con el portátil partiendo
    /// del `delay` que dejó vDSP debe dar lo mismo que todo con vDSP.
    func testBiquadDelayLayoutIsInterchangeable() {
        let v = DSPAccelerate.Biquad(coefficients: kWeighting48k, sections: 2)!
        let p = DSPPortable.Biquad(coefficients: kWeighting48k, sections: 2)!
        let x = noise(4096, seed: 31, scale: 0.5), cut = 2000
        var whole = [Float](repeating: 0, count: 4096), mixed = whole
        var d1 = [Float](repeating: 0, count: 6), d2 = d1
        v.execute(&d1, x, 1, &whole, 1, 4096)
        x.withUnsafeBufferPointer { xp in mut(&mixed) { yp in mut(&d2) { dp in
            v.execute(dp, xp.baseAddress!, 1, yp, 1, DSPLength(cut))
            p.execute(dp, xp.baseAddress! + cut, 1, yp + cut, 1, DSPLength(4096 - cut))
        } } }
        let (rel, worst) = relativeError(flat(mixed + d2), flat(whole + d1))
        print(String(format: "biquad vDSP→portátil a mitad: error relativo %.2e (tolerancia %.0e)", rel, DSPTolerance.biquad))
        XCTAssertLessThanOrEqual(rel, DSPTolerance.biquad, "elemento \(worst)")
    }

    func testCorrelationPeakEnginesAgree() {
        let v = DSPCases.correlationPeak(DSPAccelerate.self), p = DSPCases.correlationPeak(DSPPortable.self)
        print(String(format: "pico de correlación vDSP %d, %.9f; portátil %d, %.9f; Δ %.2e muestras",
                     v.index, v.position, p.index, p.position, abs(v.position - p.position)))
        XCTAssertEqual(v.index, p.index)
        XCTAssertEqual(v.position, p.position, accuracy: DSPTolerance.correlationPeakSamples)
    }

    /// Escribe `DSPReferenceData.swift` con la salida de vDSP de cada caso (bits exactos de cada Double).
    /// Solo con TF_NATIVEKIT_WRITE_REFS=1.
    func testWriteReferenceData() throws {
        guard ProcessInfo.processInfo.environment["TF_NATIVEKIT_WRITE_REFS"] == "1" else {
            throw XCTSkip("solo con TF_NATIVEKIT_WRITE_REFS=1")
        }
        var entries: [(String, [Double])] = DSPCases.names.map { ($0, DSPCases.run($0, DSPAccelerate.self)) }
        let c = DSPCases.correlationPeak(DSPAccelerate.self)
        entries.append(("corr_peak", [Double(c.index), c.position, c.value]))
        var src = """
        // Generado por DSPEngineTests.testWriteReferenceData con vDSP en el Mac. No editar a mano:
        // TF_NATIVEKIT_WRITE_REFS=1 Tools/test.sh NativeKit WriteReference
        // Cada valor es el patrón de bits de un Double en hexadecimal.

        enum DSPReference {
            static let hex: [String: String] = [

        """
        for (name, values) in entries {
            let hex = values.map { String($0.bitPattern, radix: 16) }.joined(separator: " ")
            src += "        \"\(name)\": \"\(hex)\",\n"
        }
        src += """
            ]

            static func values(_ name: String) -> [Double]? {
                hex[name].map { $0.split(separator: " ").map { Double(bitPattern: UInt64($0, radix: 16)!) } }
            }
        }

        """
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("DSPReferenceData.swift")
        try src.write(to: url, atomically: true, encoding: .utf8)
        print("escrito \(url.path) con \(entries.count) casos")
    }
    #endif
}
