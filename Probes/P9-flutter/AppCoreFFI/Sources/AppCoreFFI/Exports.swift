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

@_cdecl("tf_debug_mainactor_selftest")
public func ffiDebugMainActorSelftest(_ timeoutMs: Int32) -> Int32 {
    coreState.debugMainActorSelftest(timeoutMs: timeoutMs)
}
