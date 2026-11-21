import Foundation
@testable import NativePlatform
import XCTest

final class PlatformTests: XCTestCase {
    /// Segundos y nanosegundos del reloj de host frente al reloj de pared durante una espera de 200 ms.
    /// Tolerancia: 50 ms por la planificación del hilo (una VM puede ir lenta); la unidad tiene que cuadrar.
    func testHostClockAdvancesInSeconds() throws {
        let wallTolerance = 0.05
        let t0 = HostClock.now(), w0 = Date()
        Thread.sleep(forTimeInterval: 0.2)
        let t1 = HostClock.now(), w1 = Date()
        let host = HostClock.seconds(ticks: t1 - t0), wall = w1.timeIntervalSince(w0)
        XCTAssertEqual(host, wall, accuracy: wallTolerance, "host \(host) s, pared \(wall) s")
        let ns = Double(HostClock.nanoseconds(ticks: t1 - t0))
        XCTAssertEqual(ns / 1e9, host, accuracy: 1e-6)
        // ticks(seconds:) es la inversa de seconds(ticks:) al tick.
        let back = HostClock.ticks(seconds: HostClock.seconds(ticks: t1))
        XCTAssertLessThanOrEqual(back > t1 ? back - t1 : t1 - back, 1 + t1 / 1_000_000_000_000)
    }

    #if canImport(Darwin)
    /// En el Mac, mismos segundos que la cuenta actual de AudioKit/VideoKit (`mach_absolute_time` · base / 1e9).
    func testHostClockMatchesMachFormula() {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let base = Double(tb.numer) / Double(max(1, tb.denom))
        let t: UInt64 = 123_456_789_012_345
        XCTAssertEqual(HostClock.seconds(ticks: t), Double(t) * base / 1e9)   // exacto, bit a bit
    }
    #endif

    func testSupportFolder() {
        let url = SupportFolder.toneForge
        XCTAssertEqual(url.lastPathComponent, "ToneForge")
        #if os(Windows)
        if let local = ProcessInfo.processInfo.environment["LOCALAPPDATA"] {
            XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL.path,
                           URL(fileURLWithPath: local, isDirectory: true).standardizedFileURL.path)
        }
        #else
        XCTAssertTrue(url.path.hasSuffix("Library/Application Support/ToneForge"), url.path)
        #endif
    }

    func testPlatformErrorMessage() {
        let e = PlatformError.unsupported("paso 7: WASAPI")
        XCTAssertEqual(e, .unsupported("paso 7: WASAPI"))
        XCTAssertTrue(e.localizedDescription.contains("paso 7: WASAPI"))
    }
}
