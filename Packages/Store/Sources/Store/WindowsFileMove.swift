#if os(Windows)
import Foundation
import WinSDK  // Aislado aquí: WinSDK define su propio `UUID` y chocaría con el de Foundation en otros ficheros.

/// Mueve `temporary` sobre `destination` reemplazándolo (MoveFileEx, atómico en NTFS).
func windowsMoveReplacing(_ temporary: URL, to destination: URL) throws {
    let flags = DWORD(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)
    let moved = temporary.path.withCString(encodedAs: UTF16.self) { src in
        destination.path.withCString(encodedAs: UTF16.self) { dst in MoveFileExW(src, dst, flags) }
    }
    guard moved else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path,
                                                       NSLocalizedDescriptionKey: "MoveFileEx error \(GetLastError())"])
    }
}
#endif
