import AVFoundation

/// Remuestreo mono en memoria con `AVAudioConverter` (calidad máxima, algoritmo Mastering), sin retardo
/// (lo miden `BeatTests.testResamplerKeepsPulseTime` y `ChordAudioTests`). Lo comparten pulso y acordes; cada
/// uno fija la longitud de salida de su referencia en Python.
enum MonoResampler {
    struct Failure: Error {
        let message: String
    }

    /// Devuelve exactamente `length` muestras (recorta la cola o rellena con ceros).
    static func resample(_ x: [Float], from sourceRate: Double, to targetRate: Double, length: Int) throws -> [Float] {
        guard let inFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sourceRate, channels: 1, interleaved: false),
              let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFmt, to: outFmt) else {
            throw Failure(message: "AVAudioConverter no admite \(sourceRate) → \(targetRate) Hz")
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
                throw Failure(message: "remuestreo falló: \(convError?.localizedDescription ?? "?")")
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
