import CDirect2D
import CMediaFoundation
import CSignalsmith
import CTinySoundFont
import CWASAPI
import Foundation
import NativeONNX
import NativePlatform
import NativeResample
import XCTest

/// Pruebas de humo de los objetivos del paso 7 (parte 7.0): cada uno compila, enlaza y responde.
final class NativeSmokeTests: XCTestCase {
    /// Seno de 1 kHz a 44,1 kHz -> 48 kHz: longitud `round(n·48/44,1)`, amplitud ±0,01 dB y forma de onda
    /// (error RMS frente al seno ideal) en el tramo central.
    func testResamplerKeepsSineFrequencyAndAmplitude() throws {
        let amplitudeToleranceDB = 0.01
        let n = 44_100
        let input = (0..<n).map { Float(0.5 * sin(2 * Double.pi * 1000 * Double($0) / 44_100)) }
        let out = try Resampler.resample(input, from: 44_100, to: 48_000)
        XCTAssertEqual(out.count, Int((Double(n) * 48_000 / 44_100).rounded()))
        // 0,2 s .. 0,8 s = 600 ciclos enteros; amplitud por correlación con 1 kHz.
        let lo = 9_600, hi = 38_400
        var re = 0.0, im = 0.0, err = 0.0
        for i in lo..<hi {
            let w = 2 * Double.pi * 1000 * Double(i) / 48_000
            re += Double(out[i]) * cos(w)
            im += Double(out[i]) * sin(w)
            let e = Double(out[i]) - 0.5 * sin(w)
            err += e * e
        }
        let amp = 2 * (re * re + im * im).squareRoot() / Double(hi - lo)
        XCTAssertEqual(20 * log10(amp / 0.5), 0, accuracy: amplitudeToleranceDB)
        XCTAssertLessThan((err / Double(hi - lo)).squareRoot(), 1e-3, "forma de onda o latencia mal compensada")
    }

    func testStreamResamplerMatchesOfflineLength() throws {
        let stream = try StreamResampler(from: 48_000, to: 44_100, channels: 2)
        XCTAssertGreaterThanOrEqual(stream.latencyFrames, 0)  // r8brain 7.x ya descarta su latencia entera
        let block = [[Float]](repeating: [Float](repeating: 0.25, count: 5_000), count: 2)
        var total = 0
        for _ in 0..<5 { total += stream.process(block)[0].count }
        let tail = stream.flush()
        XCTAssertEqual(tail[0].count, tail[1].count)
        XCTAssertEqual(total + tail[0].count, Int((25_000.0 * 44_100 / 48_000).rounded()))
    }

    func testSignalsmithStretchRuns() {
        let s = tf_stretch_create(1, 48_000)
        XCTAssertNotNil(s)
        guard let s else { return }
        defer { tf_stretch_destroy(s) }
        XCTAssertGreaterThan(tf_stretch_input_latency(s), 0)
        XCTAssertGreaterThan(tf_stretch_output_latency(s), 0)
        tf_stretch_set_transpose_factor(s, 1.5, 0)
        var input = [Float](repeating: 0, count: 4_800), output = [Float](repeating: 1, count: 4_800)
        input.withUnsafeMutableBufferPointer { i in
            output.withUnsafeMutableBufferPointer { o in
                var ip: UnsafePointer<Float>? = UnsafePointer(i.baseAddress!)
                var op: UnsafeMutablePointer<Float>? = o.baseAddress!
                tf_stretch_process(s, &ip, 4_800, &op, 4_800)
            }
        }
        XCTAssertEqual(output.map { abs($0) }.max() ?? 1, 0, "silencio de entrada, silencio de salida")
        tf_stretch_reset(s)
    }

    func testTinySoundFontRejectsGarbage() {
        XCTAssertNil(tsf_load_memory(nil, 0))
    }

    #if os(Windows)
    func testWindowsShimsReportVersion() {
        XCTAssertEqual(wasapi_shim_version(), 1)
        XCTAssertEqual(mf_shim_version(), 1)
        XCTAssertEqual(d2d_shim_version(), 1)
    }

    func testOnnxRuntimeVersionAndProviders() throws {
        XCTAssertTrue(try OnnxRuntime.version.hasPrefix("1.32."))
        XCTAssertTrue(try OnnxRuntime.availableProviders.contains("CPUExecutionProvider"))
    }
    #else
    func testOnnxIsWindowsOnlyOnMac() {
        XCTAssertThrowsError(try OnnxRuntime.version) {
            XCTAssertEqual($0 as? PlatformError, .unsupported("onnx solo en Windows"))
        }
        XCTAssertThrowsError(try OnnxSession(modelURL: URL(fileURLWithPath: "/x.onnx"), provider: .cpu, threads: nil))
    }
    #endif
}
