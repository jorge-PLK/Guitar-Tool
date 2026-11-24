#if os(Windows)
import Foundation
import WinSDK  // Aislado aquí: WinSDK define su propio `UUID` y chocaría con el de Foundation en otros ficheros.

/// Carpeta Música del usuario (KnownFolder `FOLDERID_Music`, respeta redirecciones como `D:\Música`). `nil` si Windows no la da.
/// B3 (plan, «Fase 7c»): el primer arranque propone `<Música>\ToneForge`.
public func windowsMusicFolder() -> URL? {
    // FOLDERID_Music = {4BD8D571-6D19-48D3-BE97-422220080E43}; se construye a mano porque WinSDK no exporta la constante.
    var id = GUID(Data1: 0x4BD8_D571, Data2: 0x6D19, Data3: 0x48D3,
                  Data4: (0xBE, 0x97, 0x42, 0x22, 0x20, 0x08, 0x0E, 0x43))
    var raw: PWSTR?
    guard SHGetKnownFolderPath(&id, DWORD(KF_FLAG_DEFAULT.rawValue), nil, &raw) == S_OK, let raw else {
        if let raw { CoTaskMemFree(raw) }
        return nil
    }
    defer { CoTaskMemFree(raw) }
    let path = String(decodingCString: raw, as: UTF16.self)
    return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
}
#endif
