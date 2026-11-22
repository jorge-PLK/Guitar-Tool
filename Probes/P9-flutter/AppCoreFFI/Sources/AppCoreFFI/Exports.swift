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
