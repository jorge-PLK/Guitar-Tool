import Foundation
import XCTest
@testable import StemKit

final class StemLevelMeterTests: XCTestCase {
    private func wav(_ name: String, amplitude: Float, seconds: Double = 1.5, rate: Double = 48_000,
                     hz: Double = 440) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lvl-\(UUID().uuidString)-\(name).wav")
        let n = Int(seconds * rate)
        let x = (0..<n).map { amplitude * Float(sin(2 * Double.pi * hz * Double($0) / rate)) }
        let w = try AudioIO.StereoWriter(url: url, sampleRate: rate)
        try x.withUnsafeBufferPointer { try w.write(left: $0.baseAddress!, right: $0.baseAddress!, count: n) }
        w.close()
        return url
    }

    func testSilenceIsEmpty() throws {
        let url = try wav("silence", amplitude: 0)
        let l = try StemLevelMeter.measure(url: url)
        XCTAssertLessThan(l.rmsDB, -150)
        XCTAssertLessThan(l.peakDB, -150)
        XCTAssertTrue(StemLevelMeter.isEmpty(l))
        XCTAssertTrue(try StemLevelMeter.isEmpty(url: url))
    }

    func testMinus70dBSineIsEmpty() throws {
        let a = Float(pow(10.0, -70.0 / 20))
        let l = try StemLevelMeter.measure(url: try wav("m70", amplitude: a))
        XCTAssertEqual(l.peakDB, -70, accuracy: 0.1)
        XCTAssertEqual(l.rmsDB, -73.01, accuracy: 0.1)   // seno: RMS = pico − 3,01 dB
        XCTAssertTrue(StemLevelMeter.isEmpty(l))
    }

    func testMinus20dBSineIsNotEmpty() throws {
        let a = Float(pow(10.0, -20.0 / 20))
        let l = try StemLevelMeter.measure(url: try wav("m20", amplitude: a))
        XCTAssertEqual(l.peakDB, -20, accuracy: 0.1)
        XCTAssertEqual(l.rmsDB, -23.01, accuracy: 0.1)
        XCTAssertFalse(StemLevelMeter.isEmpty(l))
    }

    func testRuleNeedsBothThresholds() {
        // Ejemplos reales de la spec: other −84/−44 y piano −91/−72 → vacíos.
        XCTAssertTrue(StemLevelMeter.isEmpty(StemLevel(rmsDB: -84, peakDB: -44)))
        XCTAssertTrue(StemLevelMeter.isEmpty(StemLevel(rmsDB: -91, peakDB: -72)))
        // RMS bajo pero con un pico fuerte (un golpe suelto): no es vacío.
        XCTAssertFalse(StemLevelMeter.isEmpty(StemLevel(rmsDB: -65, peakDB: -30)))
        XCTAssertFalse(StemLevelMeter.isEmpty(StemLevel(rmsDB: -55, peakDB: -45)))
    }

    func testPeakAcrossBlocks() throws {
        // Más de un bloque de 65 536 muestras; el pico está en el último.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lvl-\(UUID().uuidString).wav")
        let n = 200_000
        var x = [Float](repeating: 0, count: n)
        x[n - 5] = 0.5
        let w = try AudioIO.StereoWriter(url: url, sampleRate: 44_100)
        try x.withUnsafeBufferPointer { try w.write(left: $0.baseAddress!, right: $0.baseAddress!, count: n) }
        w.close()
        let l = try StemLevelMeter.measure(url: url)
        XCTAssertEqual(l.peakDB, -6.02, accuracy: 0.05)
    }
}
