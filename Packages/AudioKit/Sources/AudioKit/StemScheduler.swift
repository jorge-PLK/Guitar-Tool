import Accelerate
import AVFoundation

/// Programa los stems por trozos en sus `AVAudioPlayerNode`, todos con las mismas piezas, para que
/// sigan en la misma muestra. Mantiene la cola 0,5 s por delante de lo renderizado (lo dice el reloj;
/// `.dataConsumed` no sirve: con `scheduleSegment` avisa al leer del disco, ~1 s antes de sonar).
///
/// Concurrencia: todo el estado vive en `queue` (serie). En tiempo real un temporizador de la cola
/// rellena cada 20 ms; en offline, el render llama a `topUp()` tras cada bloque; el actor principal
/// entra con `queue.sync`. Es `@unchecked Sendable` porque players y ficheros no son `Sendable`,
/// pero solo se tocan desde la cola.
final class StemScheduler: @unchecked Sendable {
    struct Stem {
        let player: AVAudioPlayerNode
        /// Fichero que lee el player (`scheduleSegment`).
        let file: AVAudioFile
        /// Segunda instancia para leer los fundidos (AVAudioFile no admite lecturas concurrentes).
        let reader: AVAudioFile
    }

    private let queue = DispatchQueue(label: "ToneForge.StudyPlayer.scheduler", qos: .userInteractive)
    private let clock: PlaybackClock

    // Solo en `queue`.
    private var stems: [Stem] = []
    private var planner = SchedulePlanner(length: 0, chunkFrames: 1, halfFade: 1, songPos: 0, loop: nil)
    private var queueFrames: Int64 = 0
    private var historyFrames: Double = 0
    private var cumScheduled: Int64 = 0
    private var generation = 0
    private var timer: (any DispatchSourceTimer)?
    private var active = false
    private var endReported = false
    private var onEnd: (@Sendable (Int) -> Void)?
    private var fadeCache: (from: Int64, to: Int64, buffers: [AVAudioPCMBuffer])?

    init(clock: PlaybackClock) {
        self.clock = clock
    }

    var halfFadeFrames: Int64 { queue.sync { planner.halfFade } }

    func configure(stems: [Stem], length: Int64, sampleRate: Double, onEnd: @escaping @Sendable (Int) -> Void) {
        queue.sync {
            self.stems = stems
            self.onEnd = onEnd
            active = false
            generation += 1
            fadeCache = nil
            let half = max(1, Int64((StudyPlayerConstants.loopCrossfadeSeconds * sampleRate / 2).rounded()))
            planner = SchedulePlanner(length: length,
                                      chunkFrames: Int64(StudyPlayerConstants.chunkSeconds * sampleRate),
                                      halfFade: half, songPos: 0, loop: nil)
            queueFrames = Int64(StudyPlayerConstants.queueSeconds * sampleRate)
            historyFrames = StudyPlayerConstants.historySeconds * sampleRate
        }
    }

    /// Nueva pasada desde `songFrame`. Devuelve su número. Los players deben estar parados.
    @discardableResult
    func start(songFrame: Int64, loop: Range<Int64>?, realtime: Bool) -> Int {
        queue.sync {
            generation += 1
            active = true
            endReported = false
            cumScheduled = 0
            planner.songPos = songFrame
            planner.loop = loop
            topUpOnQueue()
            if realtime {
                let t = DispatchSource.makeTimerSource(queue: queue)
                let ms = Int(StudyPlayerConstants.refillInterval * 1_000)
                t.schedule(deadline: .now() + .milliseconds(ms), repeating: .milliseconds(ms))
                t.setEventHandler { [weak self] in self?.topUpOnQueue() }
                t.resume()
                timer = t
            }
            return generation
        }
    }

    /// Deja de programar. Llamar antes de `player.stop()`.
    func stop() {
        queue.sync {
            active = false
            generation += 1
            timer?.cancel()
            timer = nil
        }
    }

    /// Cambia el bucle para lo que aún no está programado (el cambio entra sin cortes).
    func setLoop(_ loop: Range<Int64>?) {
        queue.sync { planner.loop = loop }
    }

    /// Rellena la cola ya (render offline de los tests; en tiempo real lo hacen los avisos).
    func topUp() {
        queue.sync { topUpOnQueue() }
    }

    private func topUpOnQueue() {
        guard active, !stems.isEmpty else { return }
        let rendered = clock.read { s -> Int64 in
            s.pendingStart ? 0 : Int64(max(0, s.cumFrame(atOutput: s.lastRenderStart + s.lastRenderFrames)))
        }
        while cumScheduled - rendered < queueFrames {
            guard let piece = planner.next() else {
                if !endReported && rendered >= cumScheduled {
                    endReported = true
                    onEnd?(generation)
                }
                return
            }
            let spans = planner.spans(of: piece, at: cumScheduled)
            switch piece {
            case let .body(s, n):
                for stem in stems {
                    stem.player.scheduleSegment(stem.file, startingFrame: AVAudioFramePosition(s),
                                                frameCount: AVAudioFrameCount(n), at: nil)
                }
            case let .crossfade(from, to):
                let buffers = crossfadeBuffers(from: from, to: to)
                for (i, stem) in stems.enumerated() { stem.player.scheduleBuffer(buffers[i], at: nil) }
            }
            clock.update { $0.spans.append(contentsOf: spans) }
            cumScheduled += spans.reduce(0) { $0 + $1.length }
        }
        let keep = historyFrames
        clock.update { $0.prune(keepFrames: keep) }
    }

    // MARK: Fundidos

    private func crossfadeBuffers(from: Int64, to: Int64) -> [AVAudioPCMBuffer] {
        if let c = fadeCache, c.from == from, c.to == to { return c.buffers }
        let h = planner.halfFade
        let buffers = stems.map { stem -> AVAudioPCMBuffer in
            let out = read(stem.reader, at: from, frames: 2 * h)
            let incoming = read(stem.reader, at: to - h, frames: 2 * h)
            Self.mix(out: out, in: incoming)
            return out
        }
        fadeCache = (from, to, buffers)
        return buffers
    }

    /// `out = out·(1 − w) + in·w`, `w = sin²(π/2 · (i + ½)/n)` (suma constante, derivada suave).
    static func crossfadeWeight(_ i: Int, _ n: Int) -> Float {
        let s = sin(Double.pi / 2 * (Double(i) + 0.5) / Double(n))
        return Float(s * s)
    }

    private static func mix(out: AVAudioPCMBuffer, in incoming: AVAudioPCMBuffer) {
        let n = Int(out.frameLength)
        let w = (0..<n).map { crossfadeWeight($0, n) }
        let ones = [Float](repeating: 1, count: n)
        var wOut = [Float](repeating: 0, count: n)
        vDSP_vsub(w, 1, ones, 1, &wOut, 1, vDSP_Length(n))   // 1 − w
        guard let a = out.floatChannelData, let b = incoming.floatChannelData else { return }
        for ch in 0..<Int(out.format.channelCount) {
            vDSP_vmul(a[ch], 1, wOut, 1, a[ch], 1, vDSP_Length(n))
            vDSP_vma(b[ch], 1, w, 1, a[ch], 1, a[ch], 1, vDSP_Length(n))
        }
    }

    /// Lee `[start, start + frames)` rellenando con ceros fuera del fichero.
    private func read(_ file: AVAudioFile, at start: Int64, frames: Int64) -> AVAudioPCMBuffer {
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames))!
        buf.frameLength = AVAudioFrameCount(frames)
        let chans = Int(file.processingFormat.channelCount)
        for ch in 0..<chans { buf.floatChannelData![ch].initialize(repeating: 0, count: Int(frames)) }
        let lo = max(0, start), hi = min(file.length, start + frames)
        guard hi > lo,
              let tmp = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(hi - lo))
        else { return buf }
        file.framePosition = lo
        do { try file.read(into: tmp, frameCount: AVAudioFrameCount(hi - lo)) } catch { return buf }
        let offset = Int(lo - start)
        for ch in 0..<chans {
            (buf.floatChannelData![ch] + offset).update(from: tmp.floatChannelData![ch], count: Int(tmp.frameLength))
        }
        return buf
    }
}
