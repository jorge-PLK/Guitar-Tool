import XCTest
@testable import AppCore

// K-KEY: `tab.keyMap` y `handleKey` salen de la misma tabla; el test recorre el mapa entero.

extension TabTests {
    private var tab: TabTests { self }

    private func rules(_ f: TabTests.Fixture) async throws -> [TabKeyRule] {
        // El método es estático: responde también con la tablatura cerrada.
        let r = try await tab.result(f, "tab.keyMap")
        let data = try JSONSerialization.data(withJSONObject: r)
        return try JSONDecoder().decode(TabKeyMapResult.self, from: data).rules
    }

    func testTabKeyMapIsStaticAndShapedAsContract() async throws {
        let f = try await tab.makeFixture()
        let raw = try await tab.result(f, "tab.keyMap")
        let list = try XCTUnwrap(raw["rules"] as? [[String: Any]])
        XCTAssertFalse(list.isEmpty)
        XCTAssertTrue(list.allSatisfy { Set($0.keys) == ["key", "shift", "ctrl", "alt", "when"] })
        XCTAssertTrue(list.contains { $0["shift"] is NSNull })
        let again = try await rules(f)
        XCTAssertEqual(again.count, list.count)
    }

    func testTabKeyMapEveryRuleIsHandledInItsWhenAndNotOutside() async throws {
        let f = try await tab.makeFixture()
        let all = try await rules(f)
        _ = try await tab.openAndTranscribe(f)
        let svc = f.bridge.tabService
        func select(_ id: String) async throws { _ = try await tab.result(f, "tab.selectTrack", "{\"track\":\"\(id)\"}") }
        func setEdit(_ on: Bool) async throws { _ = try await tab.result(f, "tab.edit", "{\"op\":\"editMode\",\"on\":\(on)}") }

        for rule in all {
            let shifts = rule.shift.map { [$0] } ?? [false, true]
            for shift in shifts {
                switch rule.when {
                case .span:
                    try await setEdit(false)
                    try await select("bass")
                    _ = try await tab.result(f, "tab.beatClick", "{\"track\":0,\"bar\":1,\"beat\":0}")
                    _ = try await tab.result(f, "tab.beatClick", "{\"track\":0,\"bar\":1,\"beat\":4,\"shift\":true}")
                    XCTAssertNotNil(svc.span)
                    XCTAssertTrue(svc.handleKey(rule.key, shift: shift, ctrl: rule.ctrl, alt: rule.alt), "\(rule)")
                    XCTAssertNil(svc.span, "\(rule)")
                    // Sin tramo y sin modo edición: nada.
                    XCTAssertFalse(svc.handleKey(rule.key, shift: shift, ctrl: rule.ctrl, alt: rule.alt), "\(rule)")
                default:
                    for (track, isDrums) in [("bass", false), ("drums", true)] {
                        try await select(track)
                        let applies = rule.when == .edit || (rule.when == .editDrums) == isDrums
                        try await setEdit(true)
                        let others = all.contains { $0 != rule && $0.when != .span && $0.matches(
                            key: rule.key, shift: shift, ctrl: rule.ctrl, alt: rule.alt, span: false, edit: true, drums: isDrums) }
                        let on = svc.handleKey(rule.key, shift: shift, ctrl: rule.ctrl, alt: rule.alt)
                        XCTAssertEqual(on, applies || others, "\(rule) en \(track)")
                        // Fuera del modo edición no se queda nada (Escape con tramo es la regla `span`).
                        try await setEdit(false)
                        XCTAssertFalse(svc.handleKey(rule.key, shift: shift, ctrl: rule.ctrl, alt: rule.alt), "\(rule) sin edición")
                    }
                }
            }
        }
    }

    func testTabKeyMapKeysOutsideTheMap() async throws {
        let f = try await tab.makeFixture()
        let all = try await rules(f)
        _ = try await tab.openAndTranscribe(f)
        let svc = f.bridge.tabService
        _ = try await tab.result(f, "tab.edit", "{\"op\":\"editMode\",\"on\":true}")
        // Barrido: toda combinación de tecla/modificadores sobre el mapa y unas extras coincide con el mapa, ni más ni menos.
        let keys = Set(all.map(\.key)).union(["q", "Tab", "Enter", " ", "a", "A", "d", "B", "Z", "F1"])
        for track in ["bass", "drums"] {
            _ = try await tab.result(f, "tab.selectTrack", "{\"track\":\"\(track)\"}")
            for key in keys.sorted() { for bits in 0..<8 {
                let (shift, ctrl, alt) = (bits & 1 != 0, bits & 2 != 0, bits & 4 != 0)
                let expected = all.contains {
                    $0.when != .span && $0.matches(key: key, shift: shift, ctrl: ctrl, alt: alt, span: false, edit: true, drums: track == "drums")
                }
                XCTAssertEqual(svc.handleKey(key, shift: shift, ctrl: ctrl, alt: alt), expected, "\(key) s\(shift) c\(ctrl) a\(alt) \(track)")
            } }
        }
        // Muestras concretas (comparación exacta, sensible a mayúsculas).
        _ = try await tab.result(f, "tab.selectTrack", "{\"track\":\"bass\"}")
        for (k, shift, ctrl, alt, want) in [("q", false, false, false, false), ("Tab", false, false, false, false),
                                            ("a", false, true, false, false), ("b", false, false, false, true),
                                            ("B", false, false, false, false), ("d", false, false, false, false),
                                            ("D", true, false, false, true), ("Z", true, true, false, true),
                                            ("y", false, false, true, true), ("ArrowLeft", true, true, false, false)] {
            XCTAssertEqual(svc.handleKey(k, shift: shift, ctrl: ctrl, alt: alt), want, "\(k)")
        }
        _ = try await tab.result(f, "tab.selectTrack", "{\"track\":\"drums\"}")
        XCTAssertFalse(svc.handleKey("y", shift: false, ctrl: false, alt: true))
        XCTAssertTrue(svc.handleKey("B", shift: false, ctrl: false, alt: false))
    }
}
