#if os(Windows)
import CAppCoreFFI
import Foundation

/// Último fotograma de un canal en Windows: `publish` sube los píxeles BGRA a la textura D3D11 compartida del canal
/// (`tf_d3d.c`, anillo de 3; el handle se publica cuando la GPU lo ha recibido) y `copyForTexture` (`tf_frame_copy`,
/// hilo de raster del motor) entrega el HANDLE DXGI compartido de la última textura publicada.
final class FrameChannel: @unchecked Sendable {
    let channel: Int32
    private let textures: FrameTextures
    private let lock = NSLock()
    private var uploaded = false

    init(channel: Int32, textures: FrameTextures) {
        self.channel = channel
        self.textures = textures
    }

    /// `bgra` = fotograma compacto (`width * height * 4` bytes). Desde el hilo productor del canal.
    func publish(bgra: UnsafePointer<UInt8>, width: Int, height: Int) {
        guard tf_d3d_upload(channel, bgra, Int32(width), Int32(height)) == 0 else { return }
        lock.lock(); uploaded = true; lock.unlock()
        if let id = textures.id(for: channel) { textures.host?.frame_available?(id) }
    }

    /// Avisa al runner de que hay fotograma nuevo sin publicarlo.
    func signal() {
        if let id = textures.id(for: channel) { textures.host?.frame_available?(id) }
    }

    func clear() {
        lock.lock(); uploaded = false; lock.unlock()
    }

    func copyForTexture() -> UnsafeMutableRawPointer? {
        lock.lock(); let ready = uploaded; lock.unlock()
        return ready ? tf_d3d_handle(channel) : nil
    }
}
#endif
