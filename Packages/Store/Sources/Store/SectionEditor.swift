import Foundation

/// Lógica de edición de las secciones de una canción (mini-spec Fase 4, «El solo es una sección más» e «Interfaz»):
/// crear, renombrar, mover un borde con imán, partir al marcar dentro de otra, borrar y alternar «Solo».
/// Sin UI ni estado propio más allá de la lista: la app la envuelve en la sesión de estudio y la prueba aquí.
public struct SectionEditor: Sendable, Equatable {
    /// Longitud mínima (s) de una sección.
    public static let minLength = 0.5
    /// Dos tiempos a menos de esto (s) son el mismo límite.
    public static let sameTime = 0.01

    public var sections: [Section]
    /// Duración de la canción (tope del fin de la última sección).
    public var duration: Double

    public init(sections: [Section], duration: Double) {
        self.sections = sections
        self.duration = duration
    }

    public func section(_ id: UUID) -> Section? { sections.first { $0.id == id } }

    // MARK: Nombres

    /// Nombre por defecto libre: «Solo», «Solo 2»… o «Sección N».
    func defaultName(solo: Bool, excluding id: UUID? = nil) -> String {
        let used = Set(sections.filter { $0.id != id }.map(\.name))
        if solo {
            if !used.contains("Solo") { return "Solo" }
            return (2...).lazy.map { "Solo \($0)" }.first { !used.contains($0) }!
        }
        return (1...).lazy.map { "Sección \($0)" }.first { !used.contains($0) }!
    }

    static func isDefaultName(_ name: String) -> Bool {
        if name == "Solo" || name == "Sección" { return true }
        for prefix in ["Solo ", "Sección "] where name.hasPrefix(prefix) { return Int(name.dropFirst(prefix.count)) != nil }
        return false
    }

    // MARK: Crear

    /// Marca una sección (o un solo) en `r`. Las secciones que solapa se recortan; una que contiene a `r` se parte
    /// en dos (antes y después, cada una con al menos `minLength`). Un rango igual al de una existente solo cambia su
    /// marca de solo. Devuelve la sección marcada, o nil si `r` es más corta que `minLength`.
    @discardableResult
    public mutating func mark(_ r: ClosedRange<Double>, solo: Bool) -> UUID? {
        guard r.upperBound - r.lowerBound >= Self.minLength else { return nil }
        if let i = sections.firstIndex(where: { abs($0.start - r.lowerBound) < Self.sameTime && abs($0.end - r.upperBound) < Self.sameTime }) {
            if solo { setSolo(sections[i].id, true) }
            return sections[i].id
        }
        var result: [Section] = []
        for s in sections {
            guard s.start < r.upperBound, s.end > r.lowerBound else { result.append(s); continue }
            if s.start + Self.minLength <= r.lowerBound {
                var left = s; left.end = r.lowerBound; result.append(left)
            }
            if s.end - Self.minLength >= r.upperBound {
                var right = s; right.id = UUID(); right.start = r.upperBound; result.append(right)
            }
        }
        var new = Section(name: "", start: r.lowerBound, end: r.upperBound, solo: solo ? true : nil)
        sections = (result + [new]).sorted { $0.start < $1.start }
        new.name = defaultName(solo: solo, excluding: new.id)
        if let i = sections.firstIndex(where: { $0.id == new.id }) { sections[i].name = new.name }
        return new.id
    }

    // MARK: Nombre y solo

    /// Renombra; un nombre vacío vuelve al por defecto.
    public mutating func rename(_ id: UUID, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = sections.firstIndex(where: { $0.id == id }) else { return }
        sections[i].name = n.isEmpty ? defaultName(solo: sections[i].isSolo, excluding: id) : n
    }

    /// Alterna «Solo»; un nombre por defecto sigue a la marca («Sección 2» y «Solo»), uno puesto a mano no.
    public mutating func setSolo(_ id: UUID, _ on: Bool) {
        guard let i = sections.firstIndex(where: { $0.id == id }), sections[i].isSolo != on else { return }
        let wasDefault = Self.isDefaultName(sections[i].name)
        sections[i].solo = on ? true : nil
        if wasDefault { sections[i].name = defaultName(solo: on, excluding: id) }
    }

    public mutating func remove(_ id: UUID) { sections.removeAll { $0.id == id } }

    // MARK: Color

    /// Colores de la paleta de secciones (el naranja queda reservado para los solos y no está en ella).
    public static let paletteCount = 7

    /// Cambia el color elegido de la sección (nil = automático). Índices fuera de la paleta se ignoran.
    public mutating func setColor(_ id: UUID, _ index: Int?) {
        guard let i = sections.firstIndex(where: { $0.id == id }) else { return }
        if let index, !(0..<Self.paletteCount).contains(index) { return }
        sections[i].color = index
    }

    /// Color de paleta de cada sección que no es solo (los solos no tienen: son naranjas). El elegido a mano manda; si
    /// no, mismo nombre = mismo color, y un nombre nuevo toma el siguiente color libre (por orden de aparición; si la
    /// paleta se agota, se reutiliza empezando por el primero).
    public static func paletteIndices(_ sections: [Section]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        var byName: [String: Int] = [:]
        var used = Set(sections.filter { !$0.isSolo }.compactMap(\.color))
        var next = 0
        for s in sections.sorted(by: { $0.start < $1.start }) where !s.isSolo {
            if let c = s.color, (0..<paletteCount).contains(c) { result[s.id] = c; continue }
            if let c = byName[s.name] { result[s.id] = c; continue }
            var c = (0..<paletteCount).first { !used.contains($0) }
            if c == nil { c = next % paletteCount; next += 1 }
            byName[s.name] = c!
            used.insert(c!)
            result[s.id] = c!
        }
        return result
    }

    // MARK: Bordes

    /// Tiempo al que quedaría un borde sin pasar de su vecina ni bajar del largo mínimo.
    public func clampedEdge(_ id: UUID, start moveStart: Bool, to time: Double) -> Double? {
        guard let i = sections.firstIndex(where: { $0.id == id }) else { return nil }
        let s = sections[i]
        if moveStart {
            let lo = sections[..<i].map(\.end).max() ?? 0
            return min(max(time, lo), s.end - Self.minLength)
        }
        let hi = sections[(i + 1)...].map(\.start).min() ?? max(duration, s.end)
        return max(min(time, hi), s.start + Self.minLength)
    }

    /// Mueve un borde a `time` (con `clampedEdge`).
    public mutating func setEdge(_ id: UUID, start moveStart: Bool, to time: Double) {
        guard let i = sections.firstIndex(where: { $0.id == id }), let t = clampedEdge(id, start: moveStart, to: time) else { return }
        if moveStart { sections[i].start = t } else { sections[i].end = t }
    }

    /// Límite de `boundaries` (ordenado) más cercano a `time`; `time` si no hay ninguno.
    public static func snap(_ time: Double, to boundaries: [Double]) -> Double {
        boundaries.min { abs($0 - time) < abs($1 - time) } ?? time
    }

    /// Mueve un borde al límite más cercano a `time` (imán al acorde, o al compás con otros límites).
    public mutating func snapEdge(_ id: UUID, start moveStart: Bool, to time: Double, boundaries: [Double]) {
        setEdge(id, start: moveStart, to: Self.snap(time, to: boundaries))
    }

    /// Mueve un borde al límite siguiente (`forward`) o anterior de `boundaries` (ordenado), uno por pulsación.
    /// Sin límites en esa dirección, o si el tope de la vecina lo impide, no se mueve.
    public mutating func nudgeEdge(_ id: UUID, start moveStart: Bool, forward: Bool, boundaries: [Double]) {
        guard let s = section(id) else { return }
        let now = moveStart ? s.start : s.end
        let target = forward ? boundaries.first { $0 > now + Self.sameTime } : boundaries.last { $0 < now - Self.sameTime }
        guard let target else { return }
        setEdge(id, start: moveStart, to: target)
    }
}
