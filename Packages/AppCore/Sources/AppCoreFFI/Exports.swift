import CAppCoreFFI
import Foundation

// Solo traduce: la ABI de `tf_core.h` (docs/flutter/arquitectura.md, «AppCoreFFI (Swift)»). En Windows, `public` + `@_cdecl`
// en un producto `.dynamic` exporta el símbolo de la DLL; si falta alguno: `dumpbin /exports`.

@_cdecl("tf_core_start")
public func ffiCoreStart(_ optionsJSON: UnsafePointer<CChar>?, _ port: Int64) -> Int32 {
    guard let optionsJSON else { return 2 }
    return coreState.start(optionsJSON: String(cString: optionsJSON), sink: .port(port))
}

@_cdecl("tf_core_send")
public func ffiCoreSend(_ utf8: UnsafePointer<UInt8>?, _ len: Int32) {
    guard let utf8, len > 0 else { return }
    // `String(decoding:)` copia: el búfer es de Dart y se libera al volver.
    coreState.send(String(decoding: UnsafeBufferPointer(start: utf8, count: Int(len)), as: UTF8.self))
}

@_cdecl("tf_core_free")
public func ffiCoreFree(_ ptr: UnsafePointer<UInt8>?) {
    guard let ptr else { return }
    Foundation.free(UnsafeMutableRawPointer(mutating: ptr))
}

@_cdecl("tf_core_shutdown")
public func ffiCoreShutdown(_ timeoutMs: Int32) {
    coreState.shutdown(timeoutMs: timeoutMs)
}

/// Windows: el hilo principal se queda aquí sirviendo `DispatchQueue.main` / `@MainActor`. No vuelve. En Mac no hace nada.
@_cdecl("tf_core_run_main")
public func ffiCoreRunMain() {
    #if os(Windows)
    dispatchMain()
    #endif
}

// Fotogramas. Fuera de Apple y Windows las funciones existen y devuelven -1/nulo.

@_cdecl("tf_core_set_texture_host")
public func ffiCoreSetTextureHost(_ host: UnsafePointer<tf_texture_host>?) {
    #if canImport(CoreVideo) || os(Windows)
    frameTextures.set(host?.pointee)
    #endif
}

@_cdecl("tf_texture_create")
public func ffiTextureCreate(_ channel: Int32) -> Int64 {
    #if canImport(CoreVideo) || os(Windows)
    guard let reg = frameTextures.host?.register_texture else { return -1 }
    let id = reg(channel)
    frameTextures.setID(id, for: channel)
    // El productor pudo dejar fotograma antes de que existiera la textura (la toma abre en pausa y Dart crea la
    // textura tras `takeview.open`): sin este aviso el runner no lo pide hasta el siguiente, y en pausa no hay otro.
    if id >= 0 { frameChannels.get(channel)?.signal() }
    return id
    #else
    return -1
    #endif
}

@_cdecl("tf_texture_dispose")
public func ffiTextureDispose(_ channel: Int32) {
    #if canImport(CoreVideo) || os(Windows)
    guard let id = frameTextures.id(for: channel) else { return }
    frameTextures.setID(nil, for: channel)
    frameTextures.host?.unregister_texture?(id)
    frameChannels.get(channel)?.clear()
    #if os(Windows)
    tf_d3d_release(channel)  // la textura D3D compartida del canal (Flutter ya no la pide tras unregister)
    #endif
    #endif
}

/// El canal de la toma (`TF_CHANNEL_TAKE`) lo alimenta el reproductor nativo en el Mac; en Windows, nulo por ahora.
@_cdecl("tf_frame_copy")
public func ffiFrameCopy(_ channel: Int32) -> UnsafeMutableRawPointer? {
    #if canImport(CoreVideo) || os(Windows)
    return frameChannels.get(channel)?.copyForTexture()
    #else
    return nil
    #endif
}
