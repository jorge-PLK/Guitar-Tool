import AudioKit
import XCTest
@testable import AppCore

/// Motivos de bloqueo por código (regla 6 de `docs/flutter/arquitectura.md`): cada caso de `RecordBlock` tiene su código y args.
final class BlockMessageTests: XCTestCase {
    func testEveryRecordBlockHasCodeAndArgs() {
        let cases: [(RecordBlock, String, [String: JSONValue]?)] = [
            (.noInputDevice, "no-input-device", nil),
            (.noGuitarInput, "no-guitar-input", nil),
            (.invalidChannels, "invalid-channels", nil),
            (.inputDisconnected, "input-disconnected", nil),
            (.outputDisconnected, "output-disconnected", nil),
            (.rateMismatch(device: 44_100, working: 48_000), "rate-mismatch",
             ["deviceHz": .double(44_100), "workingHz": .double(48_000)]),
            (.sessionUnavailable("fallo"), "session-unavailable", ["detail": .string("fallo")]),
            (.speed(0.75), "speed", ["rate": .double(0.75)]),
            (.loop, "loop", nil),
            (.busy, "busy", nil)
        ]
        for (block, code, args) in cases {
            for prefix in ["record", "audio"] {
                let m = block.coreMessage(prefix: prefix)
                XCTAssertEqual(m.code, "\(prefix)-block-\(code)")
                XCTAssertEqual(m.args, args)
                XCTAssertEqual(m.message, block.message)
            }
        }
    }

    func testJSONShapeOmitsEmptyArgsAndRoundTrips() throws {
        let plain = RecordBlock.loop.coreMessage(prefix: "audio")
        let json = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        XCTAssertFalse(json.contains("args"), json)
        let withArgs = RecordBlock.rateMismatch(device: 44_100, working: 48_000).coreMessage(prefix: "audio")
        let back = try JSONDecoder().decode(CoreMessage.self, from: JSONEncoder().encode(withArgs))
        // 44100.0 viaja como `44100` y vuelve como entero: se compara lo que se vuelve a codificar.
        XCTAssertEqual(back.code, withArgs.code)
        // `args` es un diccionario: sin `sortedKeys` el orden de las claves cambia de un proceso a otro.
        let sorted = JSONEncoder()
        sorted.outputFormatting = .sortedKeys
        XCTAssertEqual(try sorted.encode(back.args), try sorted.encode(withArgs.args))
    }
}
