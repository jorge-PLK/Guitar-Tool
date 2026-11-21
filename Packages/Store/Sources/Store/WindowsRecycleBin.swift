#if os(Windows)
import Foundation
import WinSDK  // Aislado aquí: WinSDK define su propio `UUID` y chocaría con el de Foundation en otros ficheros.

/// Manda un fichero o una carpeta a la Papelera de reciclaje (SHFileOperationW con FOF_ALLOWUNDO).
/// Nunca borra en firme: si Windows no puede reciclarlo (p. ej. demasiado grande para la Papelera del disco)
/// lanza error y el elemento sigue donde estaba (FOF_WANTNUKEWARNING lo convierte en aviso, que sin interfaz aborta).
func windowsMoveToRecycleBin(_ url: URL) throws {
    let path = url.standardizedFileURL.path.replacingOccurrences(of: "/", with: "\\")
    guard FileManager.default.fileExists(atPath: path) else {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: path])
    }
    // pFrom es una lista de rutas separadas por NUL y terminada con un doble NUL.
    var from = Array(path.utf16)
    from.append(0)
    from.append(0)
    let flags = FILEOP_FLAGS(FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT | FOF_WANTNUKEWARNING)
    let (rc, aborted): (Int32, Bool) = from.withUnsafeBufferPointer { buf in
        var op = SHFILEOPSTRUCTW()
        op.hwnd = nil
        op.wFunc = UINT(FO_DELETE)
        op.pFrom = buf.baseAddress
        op.pTo = nil
        op.fFlags = flags
        let r = SHFileOperationW(&op)
        return (r, op.fAnyOperationsAborted != false)
    }
    guard rc == 0, !aborted else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: path,
                                                       NSLocalizedDescriptionKey: "SHFileOperation error \(rc)\(aborted ? " (cancelada)" : "")"])
    }
    // Si Windows dijo "bien" pero el elemento sigue ahí, no lo damos por reciclado.
    if FileManager.default.fileExists(atPath: path) {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: path,
                                                       NSLocalizedDescriptionKey: "el elemento sigue en su ruta tras SHFileOperation"])
    }
}
#endif
