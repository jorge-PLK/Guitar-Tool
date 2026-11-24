#if canImport(CoreVideo) || os(Windows)
import CAppCoreFFI
import Foundation

// Compartido por Frames.swift (Apple) y Frames+Windows.swift: host de texturas del runner, ids y canales.

/// Tabla del host de texturas (runner) e ids por canal.
final class FrameTextures: @unchecked Sendable {
    private let lock = NSLock()
    private var _host: tf_texture_host?
    private var ids: [Int32: Int64] = [:]
    var host: tf_texture_host? { lock.lock(); defer { lock.unlock() }; return _host }
    func set(_ h: tf_texture_host?) { lock.lock(); _host = h; lock.unlock() }
    func id(for ch: Int32) -> Int64? { lock.lock(); defer { lock.unlock() }; return ids[ch] }
    func setID(_ id: Int64?, for ch: Int32) { lock.lock(); ids[ch] = id; lock.unlock() }
}

/// Canales con fotogramas por textura (`TF_CHANNEL_CAMERA`, `TF_CHANNEL_MONTAGE`). El de la toma (`TF_CHANNEL_TAKE`)
/// no está aquí: llega con el reproductor nativo (ola 3) y `tf_frame_copy(2)` devuelve nulo mientras tanto.
final class FrameChannels: @unchecked Sendable {
    static let supported: Set<Int32> = [Int32(TF_CHANNEL_CAMERA), Int32(TF_CHANNEL_MONTAGE)]
    private let lock = NSLock()
    private var map: [Int32: FrameChannel] = [:]

    func get(_ ch: Int32) -> FrameChannel? { lock.lock(); defer { lock.unlock() }; return map[ch] }

    /// El canal, creado si hace falta; nil si el canal no usa texturas.
    func channel(_ ch: Int32, textures: FrameTextures) -> FrameChannel? {
        guard Self.supported.contains(ch) else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let c = map[ch] { return c }
        let c = FrameChannel(channel: ch, textures: textures)
        map[ch] = c
        return c
    }
}

let frameTextures = FrameTextures()
let frameChannels = FrameChannels()
#endif
