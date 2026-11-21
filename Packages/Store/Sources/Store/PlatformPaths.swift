import Foundation

/// Carpeta de soporte de la app. En Windows `%LOCALAPPDATA%` (plan, «Fase 7c», paso 6: rutas en
/// `%LOCALAPPDATA%\ToneForge`); en Apple, Application Support. Mínimo y local a Store para no depender de NativeKit.
enum PlatformPaths {
    static var appSupport: URL {
        #if os(Windows)
        if let p = ProcessInfo.processInfo.environment["LOCALAPPDATA"], !p.isEmpty {
            return URL(fileURLWithPath: p, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("AppData/Local", isDirectory: true)
        #else
        return URL.applicationSupportDirectory
        #endif
    }
}
