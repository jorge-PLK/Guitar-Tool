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
    /// Productor por demanda (canal de la toma): `copyForTexture` le pide el fotograma de «ahora».
    private var pull: (@Sendable () -> CVPixelBuffer?)?

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

    /// Instala o quita el productor por demanda.
    func setPull(_ p: (@Sendable () -> CVPixelBuffer?)?) {
        lock.lock(); pull = p; lock.unlock()
    }

    /// Avisa al runner de que hay fotograma nuevo sin publicarlo (el productor por demanda lo da en la copia).
    func signal() {
        if let id = textures.id(for: channel) { textures.host?.frame_available?(id) }
    }

    /// `CVPixelBufferRef` retenido (+1) del último fotograma; lo suelta Flutter.
    func copyForTexture() -> UnsafeMutableRawPointer? {
        lock.lock()
        let p = pull
        lock.unlock()
        let fresh = p?()
        lock.lock(); defer { lock.unlock() }
        if let fresh { last = fresh }
        guard let last else { return nil }
        return Unmanaged.passRetained(last).toOpaque()
    }
}

#endif
