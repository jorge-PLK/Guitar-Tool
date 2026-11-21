// Reproductor sobre AVAudioEngine: solo macOS (paso 7: reproductor).
#if canImport(AVFoundation)
import NativeDSP
import AVFoundation
import os

/// Fuente del metrónomo, después del TimePitch. En cada ciclo de render calcula, con el reloj, qué
/// clics empiezan en el bloque (también los que vienen de bloques anteriores) y los suma. No guarda
/// voces: el mismo clic sale igual en todos los bloques que pisa. También anota el reloj de salida.
final class ClickRenderer: @unchecked Sendable {
    private static let maxEvents = 32
    private let clock: PlaybackClock
    private let normal: [Float]
    private let accent: [Float]
    /// Solo la usa el hilo de render.
    private let scratch: UnsafeMutablePointer<(Double, Bool)>

    init(clock: PlaybackClock, sampleRate: Double) {
        self.clock = clock
        normal = ClickSynth.template(accent: false, sampleRate: sampleRate)
        accent = ClickSynth.template(accent: true, sampleRate: sampleRate)
        scratch = .allocate(capacity: Self.maxEvents)
    }

    deinit { scratch.deallocate() }

    var clickFrames: Int { normal.count }

    func makeNode(format: AVAudioFormat) -> AVAudioSourceNode {
        Self.makeNode(format: format, renderer: self)
    }

    /// Fuera de cualquier actor: el bloque se llama en el hilo de render.
    private static func makeNode(format: AVAudioFormat, renderer: ClickRenderer) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, timestamp, frameCount, abl in
            renderer.render(timestamp: timestamp.pointee, frames: Int(frameCount), abl: abl)
            return noErr
        }
    }

    private func render(timestamp: AudioTimeStamp, frames n: Int, abl: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        for b in buffers { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }
        guard timestamp.mFlags.contains(.sampleTimeValid) else { return }
        let y = timestamp.mSampleTime
        let len = Double(clickFrames)
        var count = 0
        var gain: Float = 0
        let scratch = self.scratch
        clock.update { s in
            if s.pendingStart {
                s.runStartFrame = y
                s.pendingStart = false
            }
            s.lastRenderStart = y
            s.lastRenderFrames = Double(n)
            s.lastRenderHostTime = timestamp.mFlags.contains(.hostTimeValid) ? timestamp.mHostTime : 0
            guard s.running, s.metronomeOn else { return }
            gain = s.metronomeGain
            s.forEachClick(outputFrom: y - len, to: y + Double(n)) { yc, acc in
                guard count < Self.maxEvents else { return }
                scratch[count] = (yc, acc)
                count += 1
            }
        }
        guard count > 0, gain > 0, let first = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return }
        let base = Int64(y.rounded())
        for e in 0..<count {
            let (yc, acc) = scratch[e]
            let start = Int(Int64(yc.rounded()) - base)
            let t = acc ? accent : normal
            let i0 = max(0, start), i1 = min(n, start + t.count)
            guard i1 > i0 else { continue }
            t.withUnsafeBufferPointer { tp in
                var g = gain
                DSP.vsma(tp.baseAddress! + (i0 - start), 1, &g, first + i0, 1, first + i0, 1, DSPLength(i1 - i0))
            }
        }
        for b in buffers.dropFirst() {
            if let d = b.mData { memcpy(d, first, n * MemoryLayout<Float>.size) }
        }
    }
}

/// Niveles por canal, escritos desde los taps y leídos por el actor principal.
final class MeterStore: Sendable {
    private let levels = OSAllocatedUnfairLock<[Int: ChannelMeter]>(initialState: [:])

    func set(_ index: Int, _ meter: ChannelMeter) { levels.withLock { $0[index] = meter } }
    func get(_ index: Int) -> ChannelMeter { levels.withLock { $0[index] } ?? .silent }
    func reset() { levels.withLock { $0.removeAll() } }

    /// Instala el tap fuera de cualquier actor (el bloque llega en un hilo de AVFoundation).
    static func installTap(on node: AVAudioNode, index: Int, store: MeterStore) {
        node.installTap(onBus: 0, bufferSize: 1_024, format: nil) { buffer, _ in
            store.set(index, measure(buffer))
        }
    }

    static func measure(_ buffer: AVAudioPCMBuffer) -> ChannelMeter {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return .silent }
        let n = DSPLength(buffer.frameLength)
        var peak: Float = 0, sumSq: Float = 0
        for ch in 0..<Int(buffer.format.channelCount) {
            var p: Float = 0, ms: Float = 0
            DSP.maxmgv(data[ch], 1, &p, n)
            DSP.measqv(data[ch], 1, &ms, n)
            peak = max(peak, p)
            sumSq += ms
        }
        let rms = sqrt(sumSq / Float(buffer.format.channelCount))
        func db(_ x: Float) -> Float { x > 1e-6 ? 20 * log10(x) : -120 }
        return ChannelMeter(rmsDB: db(rms), peakDB: db(peak))
    }
}

#endif // canImport(AVFoundation)

import Foundation

/// Clic sintetizado: ráfaga corta con caída exponencial; el acento, más agudo. Fuera del `#if`: también lo usa el
/// motor portátil (`PortablePlaybackEngine`, paso 7c).
enum ClickSynth {
    static let durationSeconds = 0.015
    static let normalHz = 1_000.0
    static let accentHz = 2_000.0
    static let decaySeconds = 0.004
    static let releaseSeconds = 0.001
    static let peak: Float = 0.5

    static func template(accent: Bool, sampleRate: Double) -> [Float] {
        let n = Int(durationSeconds * sampleRate)
        let rel = Int(releaseSeconds * sampleRate)
        let f = accent ? accentHz : normalHz
        return (0..<n).map { i in
            let t = Double(i) / sampleRate
            var env = exp(-t / decaySeconds)
            if i >= n - rel { env *= Double(n - i) / Double(rel) }
            return Float(sin(2 * Double.pi * f * t) * env) * peak
        }
    }
}
