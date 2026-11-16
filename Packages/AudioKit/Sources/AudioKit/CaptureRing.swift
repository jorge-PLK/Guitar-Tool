import Foundation
import Synchronization

/// Búfer circular de un productor (hilo de E/S) y un consumidor, sin cerrojos ni reservas de memoria al
/// escribir (mini-spec Fase 3, «Código»: el `capture` en tiempo real no puede bloquear). Va delante de
/// `TakeRecorder`, `LatencyCalibrator` y los medidores, que toman cerrojos y reservan memoria.
///
/// Guarda bloques enteros con su `sampleTime`. Si el consumidor se retrasa y no cabe un bloque, se descarta
/// entero y se cuenta en `droppedFrames`: el hueco que deja en la línea de tiempo lo rellena de silencio
/// quien lea (`TakeRecorder` lo hace), así que una pérdida no desalinea lo que sigue.
final class CaptureRing: @unchecked Sendable {
    let channels: Int
    let capacity: Int
    let maxBlock: Int
    private let mask: Int
    private let metaCapacity: Int
    private let data: [UnsafeMutablePointer<Float>]
    private let metaTime: UnsafeMutablePointer<Int64>
    private let metaHost: UnsafeMutablePointer<Double>
    private let metaFrames: UnsafeMutablePointer<Int>
    private let metaStart: UnsafeMutablePointer<Int>
    /// Bloques publicados (lo escribe el productor) y consumidos (el consumidor).
    private let written = Atomic<Int>(0)
    private let read = Atomic<Int>(0)
    /// Muestras liberadas por el consumidor (posición de datos leída).
    private let dataRead = Atomic<Int>(0)
    private let dropped = Atomic<Int>(0)
    /// Solo del productor.
    private var dataWrite = 0
    /// Solo del consumidor.
    private let outData: [UnsafeMutablePointer<Float>]
    private let outPointers: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>>

    /// `capacity` en muestras por canal (se redondea a potencia de 2).
    init(channels: Int, capacity: Int, maxBlock: Int = 8_192) {
        self.channels = channels
        var c = 1
        while c < max(capacity, 2 * maxBlock) { c <<= 1 }
        self.capacity = c
        self.maxBlock = maxBlock
        mask = c - 1
        metaCapacity = c / 32 + 64
        data = (0..<channels).map { _ in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: c)
            p.initialize(repeating: 0, count: c)
            return p
        }
        metaTime = .allocate(capacity: metaCapacity)
        metaHost = .allocate(capacity: metaCapacity)
        metaFrames = .allocate(capacity: metaCapacity)
        metaStart = .allocate(capacity: metaCapacity)
        outData = (0..<channels).map { _ in .allocate(capacity: maxBlock) }
        outPointers = .allocate(capacity: max(channels, 1))
        _ = outPointers.initialize(from: outData)
    }

    deinit {
        data.forEach { $0.deallocate() }
        outData.forEach { $0.deallocate() }
        metaTime.deallocate()
        metaHost.deallocate()
        metaFrames.deallocate()
        metaStart.deallocate()
        outPointers.deallocate()
    }

    var droppedFrames: Int { dropped.load(ordering: .relaxed) }

    /// Productor (hilo de E/S). Copia los primeros `channels` canales del bloque.
    func write(_ buffer: AudioIOBuffer) {
        let n = min(buffer.frameCount, maxBlock)
        let w = written.load(ordering: .relaxed)
        let r = read.load(ordering: .acquiring)
        let freeData = capacity - (dataWrite - dataRead.load(ordering: .acquiring))
        guard w - r < metaCapacity, n <= freeData else {
            dropped.add(n, ordering: .relaxed)
            return
        }
        let start = dataWrite
        let at = start & mask
        let first = min(n, capacity - at)
        for ch in 0..<channels {
            let dst = data[ch]
            if ch < buffer.channelCount, let src = buffer[ch].baseAddress {
                (dst + at).update(from: src, count: first)
                if first < n { dst.update(from: src + first, count: n - first) }
            } else {
                (dst + at).update(repeating: 0, count: first)
                if first < n { dst.update(repeating: 0, count: n - first) }
            }
        }
        let slot = w % metaCapacity
        metaTime[slot] = buffer.sampleTime
        metaHost[slot] = buffer.hostSeconds
        metaFrames[slot] = n
        metaStart[slot] = start
        dataWrite = start + n
        written.store(w + 1, ordering: .releasing)
    }

    /// Consumidor: entrega cada bloque pendiente, en orden, como `AudioIOBuffer` (válido solo dentro de
    /// `body`). Devuelve cuántos entregó. Un solo consumidor a la vez.
    @discardableResult
    func drain(_ body: (AudioIOBuffer) -> Void) -> Int {
        var r = read.load(ordering: .relaxed)
        let w = written.load(ordering: .acquiring)
        var count = 0
        while r < w {
            let slot = r % metaCapacity
            let n = metaFrames[slot], start = metaStart[slot]
            let at = start & mask
            let first = min(n, capacity - at)
            for ch in 0..<channels {
                outData[ch].update(from: data[ch] + at, count: first)
                if first < n { (outData[ch] + first).update(from: data[ch], count: n - first) }
            }
            body(AudioIOBuffer(sampleTime: metaTime[slot], frameCount: n,
                               channels: UnsafeBufferPointer(rebasing: outPointers[0..<channels]), hostSeconds: metaHost[slot]))
            dataRead.store(start + n, ordering: .releasing)
            r += 1
            read.store(r, ordering: .releasing)
            count += 1
        }
        return count
    }
}
