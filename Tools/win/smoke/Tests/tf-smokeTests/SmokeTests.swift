import XCTest

// Pruebas de humo de `Tools/win/build.sh --test` (plan, Fase 7c, paso 6.1).
final class SmokeTests: XCTestCase {
    func testPasa() {
        XCTAssertEqual(1 + 1, 2)
    }

    func testSeSalta() throws {
        throw XCTSkip("[paso 7] humo")
    }
}
