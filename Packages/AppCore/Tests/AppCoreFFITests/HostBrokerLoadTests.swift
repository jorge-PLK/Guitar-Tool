import AppCore
import Foundation
import Testing
@testable import AppCoreFFI

/// `load` de `HostBroker`: la petición de página oculta que Dart debe atender (docs/flutter/contrato-anfitrion-hilos.md, #10).
@Suite struct HostBrokerLoadTests {
    /// Anfitrión falso: responde a cada `hostRequest` con `reply(params)`.
    private func broker(_ reply: @escaping @Sendable ([String: Any]) -> String) -> (HostBroker, Box) {
        let b = HostBroker()
        let box = Box()
        b.emit = { [unowned b] text in
            let obj = try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
            let hr = obj["hostRequest"] as! [String: Any]
            box.set(hr)
            let id = hr["id"] as! Int
            _ = b.resolve(reply(hr["params"] as! [String: Any]).replacingOccurrences(of: "$ID", with: "\(id)"))
        }
        return (b, box)
    }

    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value: [String: Any] = [:]
        func set(_ v: [String: Any]) { lock.lock(); value = v; lock.unlock() }
        var last: [String: Any] { lock.lock(); defer { lock.unlock() }; return value }
    }

    @Test func loadSendsUrlUserAgentReadyScriptAndTimeoutAndReturnsHtml() async throws {
        let (b, box) = broker { _ in #"{"hostResponse":{"id":$ID,"result":{"status":200,"html":"<html>ok</html>"}}}"# }
        let page = try await b.load(url: URL(string: "https://www.songsterr.com/a/wsa/x-s1")!, userAgent: "UA",
                                    readyScript: "ready()", timeout: 30)
        #expect(page == HiddenPage(status: 200, html: "<html>ok</html>"))
        #expect(box.last["method"] as? String == "load")
        let p = try #require(box.last["params"] as? [String: Any])
        #expect(p["url"] as? String == "https://www.songsterr.com/a/wsa/x-s1")
        #expect(p["userAgent"] as? String == "UA")
        #expect(p["readyScript"] as? String == "ready()")
        #expect(p["timeout"] as? Double == 30)
    }

    @Test func loadMapsErrorCodes() async throws {
        let cases: [(String, HiddenPageError)] = [
            (#"{"code":"offline","message":"x"}"#, .offline),
            (#"{"code":"readyTimeout","message":"x"}"#, .readyTimeout),
            (#"{"code":"httpStatus","message":"x","status":429}"#, .httpStatus(429)),
            (#"{"code":"cancelled","message":"x"}"#, .cancelled),
            (#"{"code":"unsupported","message":"x"}"#, .unsupported),
        ]
        for (error, expected) in cases {
            let (b, _) = broker { _ in #"{"hostResponse":{"id":$ID,"error":\#(error)}}"# }
            await #expect(throws: expected) {
                try await b.load(url: URL(string: "https://www.songsterr.com/")!, userAgent: nil, readyScript: nil, timeout: 5)
            }
        }
    }
}
