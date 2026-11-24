#if canImport(CoreVideo)
import CAppCoreFFI
import CoreVideo
import Foundation

/// Último fotograma de un canal (arquitectura.md, «Canal de fotogramas»). Lo escribe el productor del núcleo con
/// `publish` desde cualquier hilo y lo lee el runner con `tf_frame_copy` (`copyForTexture`).
final class FrameChannel: @unchecked Sendable {
    let channel: Int32
    private let textures: FrameTextures
    private let lock = NSLock()
    private var last: CVPixelBuffer?

    init(channel: Int32, textures: FrameTextures) {
        self.channel = channel
        self.textures = textures
    }

    /// Sustituye el último fotograma (el último gana) y avisa al runner, que reencola al hilo de plataforma si hace falta.
    func publish(_ buffer: CVPixelBuffer) {
        lock.lock(); last = buffer; lock.unlock()
        if let id = textures.id(for: channel) { textures.host?.frame_available?(id) }
    }

    /// Suelta el fotograma (al cerrar el canal).
    func clear() {
        lock.lock(); last = nil; lock.unlock()
    }

    /// `CVPixelBufferRef` retenido (+1) del último fotograma; lo suelta Flutter.
    func copyForTexture() -> UnsafeMutableRawPointer? {
        lock.lock(); defer { lock.unlock() }
        guard let last else { return nil }
        return Unmanaged.passRetained(last).toOpaque()
    }
}

#endif
