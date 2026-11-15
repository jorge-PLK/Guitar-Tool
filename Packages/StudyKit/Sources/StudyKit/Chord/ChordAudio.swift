import AVFoundation
import Accelerate

/// Entrada de BTC: suma de stems, media de canales y remuestreo a 22 050 Hz (`btc_common.to_mono_22k`:
/// suma, `mean(axis=0)`, `librosa.resample` soxr HQ). Aquí el remuestreo es `MonoResampler` (AVAudioConverter,
/// calidad máxima) y la longitud la de librosa: ceil(n · 22 050 / sr).
enum ChordAudio {
    static func loadMono(_ urls: [URL], sampleRate target: Double = ChordContract.sampleRate) throws -> [Float] {
        guard !urls.isEmpty else { throw ChordError.unreadableAudio("lista de stems vacía") }
        var files: [AVAudioFile] = []
        for url in urls {
            do {
                files.append(try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false))
            } catch {
                throw ChordError.unreadableAudio("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        let rate = files[0].processingFormat.sampleRate
        guard files.allSatisfy({ $0.processingFormat.sampleRate == rate }) else {
            throw ChordError.unreadableAudio("los stems tienen frecuencias de muestreo distintas")
        }
        // Como to_mono_22k: los stems se recortan al más corto.
        let total = files.map { Int($0.length) }.min()!
        var mono = [Float](repeating: 0, count: total)
        let block: AVAudioFrameCount = 1 << 16
        for file in files {
            let fmt = file.processingFormat
            let channels = Int(fmt.channelCount)
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: block) else {
                throw ChordError.unreadableAudio("sin búfer para \(fmt)")
            }
            var k = 1 / Float(max(channels, 1))
            var pos = 0
            while pos < total {
                try file.read(into: buf, frameCount: min(block, AVAudioFrameCount(total - pos)))
                let n = Int(buf.frameLength)
                if n == 0 { break }
                let ch = buf.floatChannelData!
                mono.withUnsafeMutableBufferPointer { m in
                    let dst = m.baseAddress! + pos
                    // media de canales del stem, sumada a la mezcla
                    for c in 0..<channels { vDSP_vsma(ch[c], 1, &k, dst, 1, dst, 1, vDSP_Length(n)) }
                }
                pos += n
            }
        }
        if rate == target { return mono }
        return try resample(mono, from: rate, to: target)
    }

    /// Longitud ceil(n · destino / origen), como `librosa.resample(fix=True)`.
    static func resample(_ x: [Float], from sourceRate: Double, to targetRate: Double) throws -> [Float] {
        let length = Int((Double(x.count) * targetRate / sourceRate).rounded(.up))
        do {
            return try MonoResampler.resample(x, from: sourceRate, to: targetRate, length: length)
        } catch let e as MonoResampler.Failure {
            throw ChordError.unreadableAudio(e.message)
        }
    }
}
