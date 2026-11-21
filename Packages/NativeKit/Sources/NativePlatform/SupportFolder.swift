import Foundation

/// Carpeta de soporte de la app (plan, «Fase 7c», mini-spec: rutas en `%LOCALAPPDATA%\ToneForge`).
/// No crea nada: quien escriba crea lo que necesite.
public enum SupportFolder {
    /// `~/Library/Application Support` en el Mac; `%LOCALAPPDATA%` en Windows (o `~/AppData/Local` si la
    /// variable no está).
    public static var base: URL {
        #if os(Windows)
        if let p = ProcessInfo.processInfo.environment["LOCALAPPDATA"], !p.isEmpty {
            return URL(fileURLWithPath: p, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("AppData/Local", isDirectory: true)
        #else
        return URL.applicationSupportDirectory
        #endif
    }

    /// `base/ToneForge`.
    public static var toneForge: URL { base.appendingPathComponent("ToneForge", isDirectory: true) }
}
