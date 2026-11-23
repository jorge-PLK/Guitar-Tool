#if canImport(CoreVideo) || os(Windows)
import CAppCoreFFI
import Foundation

// Compartido por Frames.swift (Apple) y Frames+Windows.swift: host de texturas del runner, ids y fuentes por canal.

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

final class FrameSources: @unchecked Sendable {
    private let lock = NSLock()
    private var map: [Int32: FrameSource] = [:]
    func get(_ ch: Int32) -> FrameSource? { lock.lock(); defer { lock.unlock() }; return map[ch] }
    func replace(_ ch: Int32, with s: FrameSource?) -> FrameSource? {
        lock.lock(); defer { lock.unlock() }
        let old = map[ch]; map[ch] = s; return old
    }
}

let frameTextures = FrameTextures()
let frameSources = FrameSources()
#endif
