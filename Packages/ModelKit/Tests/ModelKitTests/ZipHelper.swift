import Foundation
import NativePlatform

/// Crea un zip que contiene la carpeta `folder` (con su nombre como raíz). Mac: `ditto`; Windows: `tar.exe`.
func makeTestZip(folder: URL, zip: URL) throws {
    #if os(Windows)
    let exe = URL(fileURLWithPath: (ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows") + "\\System32\\tar.exe")
    let args = ["-a", "-c", "-f", zip.path, "-C", folder.deletingLastPathComponent().path, folder.lastPathComponent]
    #else
    let exe = URL(fileURLWithPath: "/usr/bin/ditto")
    let args = ["-c", "-k", "--keepParent", folder.path, zip.path]
    #endif
    let p = ChildProcess(executableURL: exe, arguments: args)
    try p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { throw PlatformError.unsupported("zip falló: \(p.terminationStatus)") }
}
