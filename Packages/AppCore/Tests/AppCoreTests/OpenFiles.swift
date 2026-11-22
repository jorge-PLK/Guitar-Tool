import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Semántica de NTFS verificable en el Mac (relevo 10, familia «fichero abierto»): NTFS no deja sustituir ni borrar un
/// fichero abierto (`MoveFileEx` error 5) y POSIX sí, así que en el Mac se comprueba directamente que ningún descriptor
/// de este proceso apunta al fichero en el momento de sustituirlo (`fcntl(F_GETPATH)` por descriptor).
/// En Windows devuelve nil: allí el propio sistema hace fallar la sustitución si queda abierto.
enum OpenFiles {
    /// Rutas (sin enlaces) que este proceso tiene abiertas ahora.
    static func paths() -> Set<String>? {
        #if canImport(Darwin)
        var out = Set<String>()
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        for fd in 0..<min(getdtablesize(), 65_536) where fcntl(fd, F_GETPATH, &buf) != -1 {
            out.insert(normalized(String(cString: buf)))
        }
        return out
        #else
        return nil
        #endif
    }

    /// Las de `urls` que siguen abiertas (nil fuera del Mac).
    static func stillOpen(_ urls: [URL]) -> [String]? {
        guard let open = paths() else { return nil }
        return urls.map { normalized($0.path) }.filter(open.contains)
    }

    /// `/var` y `/private/var` son la misma carpeta: se compara sin enlaces y sin el prefijo `/private`.
    private static func normalized(_ path: String) -> String {
        let p = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return p.hasPrefix("/private/") ? String(p.dropFirst("/private".count)) : p
    }
}
