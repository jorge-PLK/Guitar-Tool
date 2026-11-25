#if canImport(CoreVideo) || os(Windows)
import AppCore
import CAppCoreFFI
import Foundation

// Productores reales del canal de fotogramas (arquitectura.md, «Canal de fotogramas»): con AppCoreFFI activo la cámara
// (canal 0) y Montaje (canal 1) entregan sus píxeles al registro de texturas en lugar de `frames.<canal>` en JPEG
// (decisiones-interfaz.md, «frames.montage»). Sin cola: cada canal retiene solo el último fotograma (el último gana).

/// Publica un fotograma en el canal. Sin tabla de texturas (nula) o sin textura creada solo retiene el último.
/// Mac sin copia: se entrega el CVPixelBuffer (32BGRA o NV12) del pipeline. Windows: BGRA compacto a la textura D3D11.
func publishFrame(_ pixels: MontageFramePixels, channel: Int32) {
    frameChannels.channel(channel, textures: frameTextures)?.publish(pixels)
}

/// Cablea los sumideros de cámara y Montaje del `Bridge` a los canales de textura. Antes de `bridge.start()`.
func installFrameSinks(on bridge: Bridge) {
    bridge.setCameraFrameSink(cameraFrameSink)
    bridge.setMontageFrameSink(montageFrameSink)
    #if canImport(AVFoundation)
    bridge.setTakeVideoSink(takeVideoSink)
    #endif
    // TODO(Windows, pasada del PC): reproductor de tomas con Media Foundation y reloj externo
    // (base `Probes/P9-flutter/AppCoreFFI/Sources/CAppCoreFFI/tf_mfvideo.c`); hasta entonces el canal take es nulo.
}

#if canImport(AVFoundation)
/// Canal de la toma: el reproductor nativo entrega por demanda (`copyFrame` en cada `tf_frame_copy`) y avisa al runner
/// cuando hay fotograma nuevo. Con nil (visor cerrado) se quita el productor y se suelta el último fotograma.
let takeVideoSink: @Sendable (TakeVideoPlayer?) -> Void = { player in
    guard let channel = frameChannels.channel(Int32(TF_CHANNEL_TAKE), textures: frameTextures) else { return }
    if let player {
        channel.setPull { player.copyFrame() }
        player.onFrameAvailable = { channel.signal() }
    } else {
        channel.setPull(nil)
        channel.clear()
    }
}
#endif

let cameraFrameSink: @Sendable (MontageFramePixels, Double) -> Void = { pixels, _ in
    publishFrame(pixels, channel: Int32(TF_CHANNEL_CAMERA))
}
let montageFrameSink: @Sendable (MontageFramePixels, Double) -> Void = { pixels, _ in
    publishFrame(pixels, channel: Int32(TF_CHANNEL_MONTAGE))
}

#if os(Windows)
private let scratch = ScratchBuffers()

/// Búfer BGRA compacto reutilizable por canal (el productor de cada canal es un solo hilo).
private final class ScratchBuffers: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [Int32: UnsafeMutablePointer<UInt8>] = [:]
    private var sizes: [Int32: Int] = [:]
    func buffer(channel: Int32, count: Int) -> UnsafeMutablePointer<UInt8> {
        lock.lock(); defer { lock.unlock() }
        if let b = buffers[channel], sizes[channel] == count { return b }
        buffers[channel]?.deallocate()
        let b = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        buffers[channel] = b; sizes[channel] = count
        return b
    }
}

extension FrameChannel {
    /// BGRA con filas alineadas o NV12 (BT.709, rango limitado) → BGRA compacto y subida a la textura D3D11.
    func publish(_ pixels: MontageFramePixels) {
        let w = pixels.width, h = pixels.height
        let out = scratch.buffer(channel: channel, count: w * h * 4)
        switch pixels.pixelFormat {
        case .bgra:
            let src = pixels.baseAddress.assumingMemoryBound(to: UInt8.self)
            for y in 0..<h { memcpy(out + y * w * 4, src + y * pixels.bytesPerRow, w * 4) }
        case .nv12:
            let yp = pixels.planeBaseAddress(0).assumingMemoryBound(to: UInt8.self)
            let uv = pixels.planeBaseAddress(1).assumingMemoryBound(to: UInt8.self)
            for y in 0..<h {
                for x in 0..<w {
                    let yy = 1.164 * (Double(yp[y * pixels.bytesPerRow + x]) - 16)
                    let u = Double(uv[(y / 2) * pixels.bytesPerRow + (x / 2) * 2]) - 128
                    let v = Double(uv[(y / 2) * pixels.bytesPerRow + (x / 2) * 2 + 1]) - 128
                    let o = (y * w + x) * 4
                    out[o] = UInt8(max(0, min(255, yy + 2.112 * u)))
                    out[o + 1] = UInt8(max(0, min(255, yy - 0.213 * u - 0.533 * v)))
                    out[o + 2] = UInt8(max(0, min(255, yy + 1.793 * v)))
                    out[o + 3] = 255
                }
            }
        }
        publish(bgra: out, width: w, height: h)
    }
}
#endif
#endif
