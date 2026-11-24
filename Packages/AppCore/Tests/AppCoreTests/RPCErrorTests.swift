import Foundation
import XCTest
@testable import AppCore

// 0.S2: forma de error `{code, message[, args]}`; `args` solo viaja si no está vacío y los números van como número.
final class RPCErrorTests: XCTestCase {
    private func errorObject(_ e: RPCError) throws -> [String: Any] {
        let s = Router.errorResponse(id: 7, e)
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
        XCTAssertEqual(o["id"] as? Int, 7)
        return try XCTUnwrap(o["error"] as? [String: Any])
    }

    func testErrorWithoutArgsOmitsKey() throws {
        let e = RPCError(code: "busy", message: "Ocupado")
        XCTAssertTrue(e.args.isEmpty)
        let body = try errorObject(e)
        XCTAssertEqual(body["code"] as? String, "busy")
        XCTAssertEqual(body["message"] as? String, "Ocupado")
        XCTAssertNil(body["args"])
        XCTAssertEqual(Set(body.keys), ["code", "message"])
    }

    func testErrorWithArgsEncodesNumbersAsNumbers() throws {
        let e = RPCError(code: "too-short", message: "Muy corto",
                         args: ["seconds": 2.5, "count": 3, "name": "x", "ok": true,
                                "nested": .object(["list": .array([1, "a", .null])])])
        let s = Router.errorResponse(id: 1, e)
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
        let body = try XCTUnwrap(o["error"] as? [String: Any])
        let args = try XCTUnwrap(body["args"] as? [String: Any])
        XCTAssertEqual(args["seconds"] as? Double, 2.5)
        XCTAssertEqual(args["count"] as? Int, 3)
        XCTAssertFalse(args["count"] is String)
        XCTAssertEqual(args["name"] as? String, "x")
        XCTAssertEqual(args["ok"] as? Bool, true)
        let nested = try XCTUnwrap(args["nested"] as? [String: Any])
        XCTAssertEqual((nested["list"] as? [Any])?.count, 3)
    }

    func testThrownErrorWithArgsReachesTheWire() async throws {
        let router = Router()
        router.register("t.fail") { (_: Empty) -> Empty in
            throw RPCError(code: "c", message: "m", args: ["n": 4])
        }
        let r = await router.handle("{\"id\":2,\"method\":\"t.fail\"}")
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
        let args = try XCTUnwrap((o["error"] as? [String: Any])?["args"] as? [String: Any])
        XCTAssertEqual(args["n"] as? Int, 4)
    }
}
