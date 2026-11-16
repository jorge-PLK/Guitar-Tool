import AVFoundation
import Accelerate

/// Entrada de Basic Pitch: `librosa.load(sr=22 050, mono=True)`, media de canales y remuestreo (soxr HQ en
/// librosa; aquí `AVAudioConverter` a calidad máxima, como `MonoResampler` de StudyKit) con la longitud de
/// librosa, ceil(n · destino / origen).
enum MonoAudio {
    static func load(_ url: URL, sampleRate target: Double) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw TranscriptionError.unreadableAudio("\(url.lastPathComponent): \(error.localizedDescription)")
        }
        let fmt = file.processingFormat
        let channels = Int(fmt.channelCount)
        let total = Int(file.length)
        var mono = [Float](repeating: 0, count: total)
        let block: AVAudioFrameCount = 1 << 16
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: block) else {
            throw TranscriptionError.unreadableAudio("sin búfer para \(fmt)")
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
                for c in 0..<channels { vDSP_vsma(ch[c], 1, &k, dst, 1, dst, 1, vDSP_Length(n)) }
            }
            pos += n
        }
        if pos < total { mono.removeLast(total - pos) }
        let rate = fmt.sampleRate
        if rate == target { return mono }
        let length = Int((Double(mono.count) * target / rate).rounded(.up))
        return try resample(mono, from: rate, to: target, length: length)
    }

    /// Devuelve exactamente `length` muestras (recorta la cola o rellena con ceros).
    static func resample(_ x: [Float], from sourceRate: Double, to targetRate: Double, length: Int) throws -> [Float] {
        guard let inFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sourceRate, channels: 1, interleaved: false),
              let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFmt, to: outFmt) else {
            throw TranscriptionError.unreadableAudio("AVAudioConverter no admite \(sourceRate) → \(targetRate) Hz")
        }
        converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        var out = [Float]()
        out.reserveCapacity(length + 1024)
        let block = 1 << 15
        let source = ArraySource(samples: x, buffer: AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: AVAudioFrameCount(block))!)
        let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: AVAudioFrameCount(block))!
        while true {
            outBuf.frameLength = 0
            var convError: NSError?
            // El bloque se invoca de forma síncrona dentro de convert(), en este hilo.
            let status = converter.convert(to: outBuf, error: &convError) { want, inStatus in
                source.next(want: Int(want), status: inStatus)
            }
            if status == .error {
                throw TranscriptionError.unreadableAudio("remuestreo falló: \(convError?.localizedDescription ?? "?")")
            }
            let got = Int(outBuf.frameLength)
            if got > 0 { out.append(contentsOf: UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: got)) }
            if status == .endOfStream || (status == .inputRanDry && got == 0) { break }
        }
        if out.count > length { out.removeLast(out.count - length) }
        if out.count < length { out.append(contentsOf: repeatElement(0, count: length - out.count)) }
        return out
    }

    /// `@unchecked Sendable`: AVAudioConverter declara el bloque @Sendable pero lo llama síncronamente.
    private final class ArraySource: @unchecked Sendable {
        let samples: [Float]
        let buffer: AVAudioPCMBuffer
        var pos = 0

        init(samples: [Float], buffer: AVAudioPCMBuffer) {
            self.samples = samples
            self.buffer = buffer
        }

        func next(want: Int, status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
            let n = min(want, Int(buffer.frameCapacity), samples.count - pos)
            guard n > 0 else {
                status.pointee = .endOfStream
                return nil
            }
            samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress! + pos, count: n) }
            buffer.frameLength = AVAudioFrameCount(n)
            pos += n
            status.pointee = .haveData
            return buffer
        }
    }
}
