import XCTest
@testable import P2Core

final class P2CoreTests: XCTestCase {
    func testSelfTestChecksPass() {
        let checks = SelfTest.run()
        XCTAssertFalse(checks.isEmpty)
        for c in checks {
            XCTAssertTrue(c.pass, "\(c.name): esperado \(c.expected) ± \(c.tolerance), obtenido \(c.got)")
        }
    }

    func testFFTRoundTrip() {
        var re = (0..<64).map { sin(Double($0) * 0.3) }
        let orig = re
        var im = [Double](repeating: 0, count: 64)
        FFT.transform(&re, &im)
        FFT.transform(&re, &im, inverse: true)
        for i in 0..<64 { XCTAssertEqual(re[i], orig[i], accuracy: 1e-12) }
    }
}
