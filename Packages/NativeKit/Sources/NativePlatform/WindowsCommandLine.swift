import Foundation

/// Lo que `ChildProcess` le pasa a `CreateProcessW` en Windows (plan, «Fase 7c», paso 8: hijos sin ventana de
/// consola). Funciones puras: se prueban también en el Mac.
enum WindowsCommandLine {
    /// Línea de órdenes: ejecutable y argumentos citados para que `CommandLineToArgvW` (y el CRT de MSVC, que
    /// siguen las mismas reglas) devuelvan exactamente `[executable] + arguments`.
    static func build(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map(quote).joined(separator: " ")
    }

    /// Cita un argumento. Sin espacio, tabulador, salto de línea, tabulador vertical ni comillas, va tal cual. Si
    /// no, entre comillas: las barras inversas solo son especiales delante de una comilla, así que una tanda de n
    /// barras seguida de comilla se escribe como 2n + 1 barras y la comilla, y una tanda al final (antes de la
    /// comilla de cierre) como 2n barras; el resto se copia sin tocar.
    /// Se recorre por escalares Unicode, no por `Character`: una comilla seguida de un acento combinante es un
    /// solo `Character` y se escaparía sin citar.
    static func quote(_ argument: String) -> String {
        let special: Set<Unicode.Scalar> = [" ", "\t", "\n", "\u{0B}", "\""]
        let scalars = argument.unicodeScalars
        if !scalars.isEmpty, !scalars.contains(where: { special.contains($0) }) { return argument }
        var out = String.UnicodeScalarView()
        out.append("\"")
        var backslashes = 0
        func slashes(_ n: Int) { for _ in 0..<n { out.append("\\") } }
        for s in scalars {
            if s == "\\" {
                backslashes += 1
                continue
            }
            slashes(s == "\"" ? 2 * backslashes + 1 : backslashes)
            out.append(s)
            backslashes = 0
        }
        slashes(2 * backslashes)
        out.append("\"")
        return String(out)
    }

    /// Bloque de entorno UTF-16 para `CREATE_UNICODE_ENVIRONMENT`: `clave=valor\0` por variable, ordenadas por
    /// clave sin distinguir mayúsculas (lo que espera Windows), y un `\0` final. Vacío: dos `\0`. Se omiten las
    /// claves vacías y lo que lleve un `\0` dentro (cortaría el bloque).
    static func environmentBlock(_ environment: [String: String]) -> [UInt16] {
        let entries = environment
            .filter { !$0.key.isEmpty && !$0.key.contains("\0") && !$0.value.contains("\0") }
            .sorted { a, b in
                let (ua, ub) = (a.key.uppercased(), b.key.uppercased())
                return ua == ub ? a.key < b.key : ua < ub
            }
        var block: [UInt16] = []
        for (key, value) in entries {
            block.append(contentsOf: "\(key)=\(value)".utf16)
            block.append(0)
        }
        if block.isEmpty { block.append(0) }
        block.append(0)
        return block
    }

    /// Ruta nativa a partir de `URL.path`: sin la barra inicial de `/C:/…` y con barras inversas.
    static func nativePath(_ path: String) -> String {
        var p = Substring(path)
        let chars = Array(p.prefix(3))
        if chars.count == 3, chars[0] == "/", chars[1].isLetter, chars[2] == ":" { p = p.dropFirst() }
        return p.replacingOccurrences(of: "/", with: "\\")
    }
}
