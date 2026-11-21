import Foundation
import NativeAudioFile
import NativeDSP

/// Lectura para el pulso: media de canales y remuestreo a 22 050 Hz con `AVAudioConverter` (calidad máxima,
/// algoritmo Mastering), como `bt_common.to_mono_22k` (media + soxr HQ). Decodifica `AudioFileReader`
/// (`AVAudioFile` en el Mac, dr_* en Windows).
enum BeatAudio {
    static func loadMono(_ url: URL, sampleRate: Double = BeatContract.sampleRate) throws -> [Float] {
        let file: AudioFileReader
        do {
            file = try AudioFileReader(url: url)
        } catch {
            throw BeatError.unreadableAudio("\(url.lastPathComponent): \(error.localizedDescription)")
        }
        let channels = file.channelCount
        let total = file.frameCount
        var mono = [Float](repeating: 0, count: total)
        let block = 1 << 16
        let ch = (0..<max(channels, 1)).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: block) }
        defer { ch.forEach { $0.deallocate() } }
        var pos = 0
        while pos < total {
            let n = try file.read(into: Array(ch.prefix(channels)), maxFrames: min(block, total - pos))
            if n == 0 { break }
            mono.withUnsafeMutableBufferPointer { m in
                let dst = m.baseAddress! + pos
                dst.update(from: ch[0], count: n)
                for c in 1..<max(channels, 1) { DSP.vadd(dst, 1, ch[c], 1, dst, 1, DSPLength(n)) }
                if channels > 1 {
                    var k = 1 / Float(channels)
                    DSP.vsmul(dst, 1, &k, dst, 1, DSPLength(n))
                }
            }
            pos += n
        }
        if pos < total { mono.removeLast(total - pos) }
        if file.sampleRate == sampleRate { return mono }
        return try resample(mono, from: file.sampleRate, to: sampleRate)
    }

    /// Remuestreo mono en memoria (`MonoResampler`). La salida tiene round(n · destino / origen) muestras y no
    /// lleva retardo (lo mide `BeatAudioTests.testResamplerKeepsPulseTime`).
    static func resample(_ x: [Float], from sourceRate: Double, to targetRate: Double) throws -> [Float] {
        let expected = Int((Double(x.count) * targetRate / sourceRate).rounded())
        do {
            return try MonoResampler.resample(x, from: sourceRate, to: targetRate, length: expected)
        } catch let e as MonoResampler.Failure {
            throw BeatError.unreadableAudio(e.message)
        }
    }
}
