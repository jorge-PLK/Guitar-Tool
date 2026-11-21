import XCTest
@testable import Store

/// Vectores conocidos (FIPS 180-4): CryptoKit en Apple y swift-crypto en Windows deben dar lo mismo.
final class HashTests: XCTestCase {
    private func hash(_ data: Data) throws -> String {
        let dir = try makeTempDir("hash")
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("x.bin")
        try data.write(to: f)
        return try Library.sha256(of: f)
    }

    func testEmpty() throws {
        XCTAssertEqual(try hash(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testAbc() throws {
        XCTAssertEqual(try hash(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testMillionA() throws {
        // Vector largo del estándar (un millón de «a»).
        XCTAssertEqual(try hash(Data(repeating: 0x61, count: 1_000_000)),
                       "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }
}
