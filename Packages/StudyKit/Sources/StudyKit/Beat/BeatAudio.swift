import AVFoundation
import Accelerate

/// Lectura para el pulso: media de canales y remuestreo a 22 050 Hz con `AVAudioConverter` (calidad máxima,
/// algoritmo Mastering), como `bt_common.to_mono_22k` (media + soxr HQ).
enum BeatAudio {
    static func loadMono(_ url: URL, sampleRate: Double = BeatContract.sampleRate) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw BeatError.unreadableAudio("\(url.lastPathComponent): \(error.localizedDescription)")
        }
        let fmt = file.processingFormat
        let channels = Int(fmt.channelCount)
        let total = Int(file.length)
        var mono = [Float](repeating: 0, count: total)
        let block: AVAudioFrameCount = 1 << 16
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: block) else {
            throw BeatError.unreadableAudio("sin búfer para \(fmt)")
        }
        var pos = 0
        while pos < total {
            try file.read(into: buf, frameCount: min(block, AVAudioFrameCount(total - pos)))
            let n = Int(buf.frameLength)
            if n == 0 { break }
            let ch = buf.floatChannelData!
            mono.withUnsafeMutableBufferPointer { m in
                let dst = m.baseAddress! + pos
                dst.update(from: ch[0], count: n)
                for c in 1..<max(channels, 1) { vDSP_vadd(dst, 1, ch[c], 1, dst, 1, vDSP_Length(n)) }
                if channels > 1 {
                    var k = 1 / Float(channels)
                    vDSP_vsmul(dst, 1, &k, dst, 1, vDSP_Length(n))
                }
            }
            pos += n
        }
        if pos < total { mono.removeLast(total - pos) }
        if fmt.sampleRate == sampleRate { return mono }
        return try resample(mono, from: fmt.sampleRate, to: sampleRate)
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
