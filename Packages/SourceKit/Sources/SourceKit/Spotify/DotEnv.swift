import Foundation

/// Lector mínimo de ficheros `.env` (spec Fase 7b, punto 4).
public enum DotEnv {
    /// `CLAVE=valor`; ignora vacías, `#` y líneas sin `=`; `export ` opcional; quita comillas simples o dobles.
    public static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") || line.hasPrefix("export\t") {
                line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            if key.isEmpty { continue }
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let f = value.first, f == value.last, f == "\"" || f == "'" {
                value = String(value.dropFirst().dropLast())
            }
            out[key] = value
        }
        return out
    }
}
