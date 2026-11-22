import CAppCoreFFI
import Foundation

// Solo traduce: la ABI de `tf_core.h`.

@_cdecl("tf_core_start")
public func ffiCoreStart(_ optionsJSON: UnsafePointer<CChar>?, _ onMessage: tf_message_cb?, _ textures: UnsafeRawPointer?) -> Int32 {
    guard let optionsJSON, let onMessage else { return 2 }
    return coreState.start(optionsJSON: String(cString: optionsJSON), sink: .callback(onMessage))
}

@_cdecl("tf_core_send")
public func ffiCoreSend(_ utf8: UnsafePointer<UInt8>?, _ len: Int32) {
    guard let utf8, len > 0 else { return }
    coreState.send(String(decoding: UnsafeBufferPointer(start: utf8, count: Int(len)), as: UTF8.self))
}

@_cdecl("tf_core_free")
public func ffiCoreFree(_ ptr: UnsafePointer<UInt8>?) {
    guard let ptr else { return }
    coreState.free(ptr)
}

@_cdecl("tf_core_shutdown")
public func ffiCoreShutdown(_ timeoutMs: Int32) {
    coreState.shutdown(timeoutMs: timeoutMs)
}

@_cdecl("tf_debug_live_buffers")
public func ffiDebugLiveBuffers() -> Int64 {
    coreState.live()
}

@_cdecl("tf_core_start_port")
public func ffiCoreStartPort(_ optionsJSON: UnsafePointer<CChar>?, _ port: Int64) -> Int32 {
    guard let optionsJSON else { return 2 }
    return coreState.start(optionsJSON: String(cString: optionsJSON), sink: .port(port))
}

@_cdecl("tf_debug_emit")
public func ffiDebugEmit(_ hz: Int32, _ count: Int32, _ bytes: Int32) -> Int32 {
    coreState.debugEmit(hz: hz, count: count, bytes: bytes)
}

// P9 prueba 7 (hilos en Windows). `tf_core_main_queue_handle`, `tf_core_pump`, `tf_debug_apartment` y
// `tf_debug_is_main_thread` están en C (tf_core.c). En Windows, `public` + `@_cdecl` en un producto `.dynamic`
// exporta el símbolo de la DLL (Swift marca dllexport lo público); si falta algún símbolo: `dumpbin /exports`.

/// Vía 1: el hilo principal se queda aquí sirviendo `DispatchQueue.main` / `@MainActor`. No vuelve.
@_cdecl("tf_core_run_main")
public func ffiCoreRunMain() {
    tf_internal_mark_main_thread()
    dispatchMain()
}

// P9 prueba 3: fotogramas. Fuera de Apple (Windows) las funciones existen y devuelven 0/nulo/-1.

@_cdecl("tf_core_set_texture_host")
public func ffiCoreSetTextureHost(_ host: UnsafePointer<tf_texture_host>?) {
    #if canImport(CoreVideo)
    frameTextures.set(host?.pointee)
    #endif
}

@_cdecl("tf_texture_create")
public func ffiTextureCreate(_ channel: Int32) -> Int64 {
    #if canImport(CoreVideo)
    guard let reg = frameTextures.host?.register_texture else { return -1 }
    let id = reg(channel)
    frameTextures.setID(id, for: channel)
    return id
    #else
    return -1
    #endif
}

@_cdecl("tf_texture_dispose")
public func ffiTextureDispose(_ channel: Int32) {
    #if canImport(CoreVideo)
    guard let id = frameTextures.id(for: channel) else { return }
    frameTextures.setID(nil, for: channel)
    frameTextures.host?.unregister_texture?(id)
    #endif
}

@_cdecl("tf_frame_copy")
public func ffiFrameCopy(_ channel: Int32) -> UnsafeMutableRawPointer? {
    #if canImport(AVFoundation)
    if let v = videoProbes.get(channel) { return v.copyForTexture() }
    #endif
    #if canImport(CoreVideo)
    return frameSources.get(channel)?.copyForTexture()
    #else
    return nil
    #endif
}

@_cdecl("tf_debug_frames_start")
public func ffiDebugFramesStart(_ channel: Int32, _ width: Int32, _ height: Int32, _ fps: Int32) -> Int32 {
    #if canImport(CoreVideo)
    guard let s = FrameSource(channel: channel, width: Int(width), height: Int(height), fps: Int(fps)) else { return 1 }
    frameSources.replace(channel, with: s)?.stop()
    s.start()
    return 0
    #else
    return 1
    #endif
}

@_cdecl("tf_debug_frames_stop")
public func ffiDebugFramesStop(_ channel: Int32) {
    #if canImport(CoreVideo)
    frameSources.get(channel)?.stop()
    #endif
}

@_cdecl("tf_debug_frame_bgra")
public func ffiDebugFrameBGRA(_ channel: Int32, _ dst: UnsafeMutablePointer<UInt8>?, _ capacity: Int32,
                              _ outWidth: UnsafeMutablePointer<Int32>?, _ outHeight: UnsafeMutablePointer<Int32>?,
                              _ outSeq: UnsafeMutablePointer<Int64>?) -> Int32 {
    #if canImport(CoreVideo)
    guard let s = frameSources.get(channel), let dst else { return 0 }
    let n = s.copyBGRA(dst: dst, capacity: Int(capacity), seqInOut: outSeq)
    if n > 0 { outWidth?.pointee = Int32(s.width); outHeight?.pointee = Int32(s.height) }
    return Int32(n)
    #else
    return 0
    #endif
}

@_cdecl("tf_debug_frames_stats")
public func ffiDebugFramesStats(_ channel: Int32, _ produced: UnsafeMutablePointer<Int64>?, _ textureCopies: UnsafeMutablePointer<Int64>?,
                                _ distinctTextureCopies: UnsafeMutablePointer<Int64>?, _ bgraCopies: UnsafeMutablePointer<Int64>?) {
    #if canImport(CoreVideo)
    let st = frameSources.get(channel)?.stats() ?? (0, 0, 0, 0, 0)
    produced?.pointee = st.0; textureCopies?.pointee = st.1; distinctTextureCopies?.pointee = st.2; bgraCopies?.pointee = st.3
    #else
    produced?.pointee = 0; textureCopies?.pointee = 0; distinctTextureCopies?.pointee = 0; bgraCopies?.pointee = 0
    #endif
}

/// Extra de prueba: coste medio del generador en µs por fotograma (solo relleno del búfer, sin la copia).
@_cdecl("tf_debug_frames_cost_us")
public func ffiDebugFramesCostUs(_ channel: Int32) -> Int64 {
    #if canImport(CoreVideo)
    return frameSources.get(channel)?.stats().4 ?? 0
    #else
    return 0
    #endif
}

#if canImport(AVFoundation)
// P9.5b prueba 5 (vídeo de tomas, candidata nativa). Solo Apple. Los JSON se devuelven con malloc: liberar con free().

@_cdecl("tf_debug_video_open")
public func ffiDebugVideoOpen(_ channel: Int32, _ path: UnsafePointer<CChar>?) -> Int32 {
    guard let path else { return 1 }
    // Apertura asíncrona: devuelve ya; consultar tf_debug_video_state.
    videoProbes.replace(channel, with: VideoProbe(channel: channel, path: String(cString: path)))?.stop()
    return 0
}

/// 0 abriendo, 1 listo, 2 fallo, -1 sin canal.
@_cdecl("tf_debug_video_state")
public func ffiDebugVideoState(_ channel: Int32) -> Int32 {
    videoProbes.get(channel)?.state ?? -1
}

@_cdecl("tf_debug_video_close")
public func ffiDebugVideoClose(_ channel: Int32) {
    videoProbes.replace(channel, with: nil)?.stop()
}

@_cdecl("tf_debug_video_clock")
public func ffiDebugVideoClock(_ channel: Int32, _ seconds: Double, _ rate: Double, _ playing: Int32, _ epochJump: Int32) {
    videoProbes.get(channel)?.setClock(seconds: seconds, rate: rate, playing: playing != 0, jump: epochJump != 0)
}

@_cdecl("tf_debug_video_loop")
public func ffiDebugVideoLoop(_ channel: Int32, _ start: Double, _ end: Double, _ enabled: Int32) {
    videoProbes.get(channel)?.setLoop(start: start, end: end, enabled: enabled != 0)
}

@_cdecl("tf_debug_video_info")
public func ffiDebugVideoInfo(_ channel: Int32) -> UnsafeMutablePointer<UInt8>? {
    guard let json = videoProbes.get(channel)?.infoOrNil else { return nil }
    return UnsafeMutableRawPointer(strdup(json))?.assumingMemoryBound(to: UInt8.self)
}

@_cdecl("tf_debug_video_stats")
public func ffiDebugVideoStats(_ channel: Int32, _ reset: Int32) -> UnsafeMutablePointer<UInt8>? {
    guard let p = videoProbes.get(channel) else { return nil }
    return UnsafeMutableRawPointer(strdup(p.statsJSON(reset: reset != 0)))?.assumingMemoryBound(to: UInt8.self)
}
#endif

@_cdecl("tf_debug_mainactor_selftest")
public func ffiDebugMainActorSelftest(_ timeoutMs: Int32) -> Int32 {
    coreState.debugMainActorSelftest(timeoutMs: timeoutMs)
}
