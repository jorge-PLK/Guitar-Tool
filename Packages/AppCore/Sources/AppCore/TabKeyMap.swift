import Foundation
import TabKit

// Mapa de teclas de la tablatura (desvío de núcleo, Fase 7f, K-KEY). Una sola tabla: `TabService.handleKey` decide y ejecuta
// con ella y `tab.keyMap` la entrega tal cual al cliente, que la cachea y decide síncronamente si se queda una tecla.

/// Cuándo vale una regla. `span` = fase lista y hay tramo; `edit` = fase lista y modo edición; `editDrums` / `editNotDrums` =
/// `edit` y la pista seleccionada es / no es de batería (sin pista seleccionada cuenta como no batería).
enum TabKeyWhen: String, Codable, Sendable { case span, edit, editDrums, editNotDrums }

/// Regla de tecla. El cliente se queda la tecla si existe una regla con:
/// - `key` IGUAL, comparación EXACTA y sensible a mayúsculas (la tabla ya trae las dos variantes de las letras que el núcleo
///   acepta sin distinguir caso: `z`/`Z`, `y`/`Y` y los golpes de batería `b c h t p` / `B C H T P`; los adornos `D` y `U`
///   solo existen en mayúscula);
/// - `ctrl` y `alt` iguales a los del evento, y `shift` igual salvo que la regla lo traiga a `nil` (da igual);
/// - `when` satisfecho por el estado actual.
struct TabKeyRule: Codable, Equatable, Sendable {
    var key: String
    var shift: Bool?
    var ctrl: Bool
    var alt: Bool
    var when: TabKeyWhen

    private enum CodingKeys: String, CodingKey { case key, shift, ctrl, alt, when }

    init(key: String, shift: Bool?, ctrl: Bool = false, alt: Bool = false, when: TabKeyWhen) {
        self.key = key; self.shift = shift; self.ctrl = ctrl; self.alt = alt; self.when = when
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        shift = try c.decodeIfPresent(Bool.self, forKey: .shift)
        ctrl = try c.decode(Bool.self, forKey: .ctrl)
        alt = try c.decode(Bool.self, forKey: .alt)
        when = try c.decode(TabKeyWhen.self, forKey: .when)
    }

    /// `shift` siempre presente (`null` = da igual).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(shift, forKey: .shift)
        try c.encode(ctrl, forKey: .ctrl)
        try c.encode(alt, forKey: .alt)
        try c.encode(when, forKey: .when)
    }

    func matches(key k: String, shift s: Bool, ctrl c: Bool, alt a: Bool, span: Bool, edit: Bool, drums: Bool) -> Bool {
        guard key == k, ctrl == c, alt == a, shift == nil || shift == s else { return false }
        switch when {
        case .span: return span
        case .edit: return edit
        case .editDrums: return edit && drums
        case .editNotDrums: return edit && !drums
        }
    }
}

struct TabKeyMapResult: Codable, Sendable { var rules: [TabKeyRule] }

/// Acción que ejecuta `handleKey` para una regla.
enum TabKeyAction: Equatable, Sendable {
    case clearSpan, undoRedo, artificialHarmonic
    case arrowUp, arrowDown, arrowLeft, arrowRight
    case delete, deselect, digit
    case durationUp, durationDown
    case hit(DrumPiece)
    case ornament(TabOrnament)
}

extension TabService {
    /// Tabla única regla -> acción. El orden importa solo para la acción (primera regla que casa).
    nonisolated static let keyEntries: [(rule: TabKeyRule, action: TabKeyAction)] = {
        var e: [(TabKeyRule, TabKeyAction)] = []
        func add(_ key: String, _ shift: Bool?, ctrl: Bool = false, alt: Bool = false, _ when: TabKeyWhen, _ a: TabKeyAction) {
            e.append((TabKeyRule(key: key, shift: shift, ctrl: ctrl, alt: alt, when: when), a))
        }
        add("Escape", false, .span, .clearSpan)
        for k in ["z", "Z"] { add(k, nil, ctrl: true, .edit, .undoRedo) }
        for k in ["y", "Y"] { add(k, false, alt: true, .editNotDrums, .artificialHarmonic) }
        add("ArrowUp", nil, .edit, .arrowUp)
        add("ArrowDown", nil, .edit, .arrowDown)
        add("ArrowLeft", nil, .edit, .arrowLeft)
        add("ArrowRight", nil, .edit, .arrowRight)
        add("Backspace", nil, .edit, .delete)
        add("Delete", nil, .edit, .delete)
        add("Escape", nil, .edit, .deselect)
        for d in 0...9 { add("\(d)", false, .edit, .digit) }
        add("+", nil, .edit, .durationUp)
        add("=", nil, .edit, .durationUp)
        add("-", nil, .edit, .durationDown)
        let hits: [(String, DrumPiece)] = [("b", .kick), ("c", .snare), ("h", .hiHat), ("t", .tom), ("p", .crash)]
        for (k, piece) in hits { for key in [k, k.uppercased()] { add(key, false, .editDrums, .hit(piece)) } }
        // Adornos: se derivan de `ornament(forKey:)` sobre ASCII imprimible para no duplicar la tabla de la Fase 5c.
        for scalar in 0x20...0x7E {
            let ch = String(UnicodeScalar(UInt8(scalar)))
            if ch.count == 1, Int(ch) != nil { continue }   // los dígitos van antes
            var cells: [Bool: (drums: TabOrnament?, notDrums: TabOrnament?)] = [:]
            for s in [false, true] { cells[s] = (ornament(forKey: ch, shift: s, drums: true), ornament(forKey: ch, shift: s, drums: false)) }
            let f = cells[false]!, t = cells[true]!
            let same = f.drums == t.drums && f.notDrums == t.notDrums
            for s in same ? [Bool?.none] : [false, true] {
                let c = cells[s ?? false]!
                switch (c.drums, c.notDrums) {
                case let (d?, n?) where d == n: add(ch, s, .edit, .ornament(d))
                case let (d?, n?): add(ch, s, .editDrums, .ornament(d)); add(ch, s, .editNotDrums, .ornament(n))
                case let (d?, nil): add(ch, s, .editDrums, .ornament(d))
                case let (nil, n?): add(ch, s, .editNotDrums, .ornament(n))
                case (nil, nil): break
                }
            }
        }
        return e
    }()

    nonisolated static var keyRules: [TabKeyRule] { keyEntries.map(\.rule) }

    func keyMap() -> TabKeyMapResult { TabKeyMapResult(rules: Self.keyRules) }
}
