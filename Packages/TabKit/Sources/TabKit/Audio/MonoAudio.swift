#if canImport(AVFoundation)
import AVFoundation
#else
import NativeResample
#endif
import Foundation
import NativeAudioFile
import NativePlatform

/// Entrada de Basic Pitch: `librosa.load(sr=22 050, mono=True)`, media de canales y remuestreo (soxr HQ en
/// librosa; aquí `AVAudioConverter` a calidad máxima, como `MonoResampler` de StudyKit) con la longitud de
/// librosa, ceil(n · destino / origen). La lectura y la mezcla van por `NativeAudioFile.readMono` (`AVAudioFile` y
/// `vsma` canal a canal en el Mac, las mismas muestras de antes); el remuestreo, en Windows, con r8brain (paso 7).
enum MonoAudio {
    static func load(_ url: URL, sampleRate target: Double) throws -> [Float] {
        let mono: [Float], rate: Double
        do {
            (mono, rate) = try NativeAudioFile.readMono(url)
        } catch {
            throw TranscriptionError.unreadableAudio("\(url.lastPathComponent): \(error.localizedDescription)")
        }
        if rate == target { return mono }
        let length = Int((Double(mono.count) * target / rate).rounded(.up))
        return try resample(mono, from: rate, to: target, length: length)
    }

    #if canImport(AVFoundation)
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
    #else
    /// Windows (paso 7, parte 7.4): r8brain por `NativeResample`, sin retardo (la latencia del filtro va compensada).
    /// Devuelve exactamente `length` muestras (recorta la cola o rellena con ceros).
    static func resample(_ x: [Float], from sourceRate: Double, to targetRate: Double, length: Int) throws -> [Float] {
        var out: [Float]
        do {
            out = try Resampler.resample(x, from: sourceRate, to: targetRate)
        } catch {
            throw TranscriptionError.unreadableAudio("remuestreo \(sourceRate) → \(targetRate) Hz: \(error)")
        }
        if out.count > length { out.removeLast(out.count - length) }
        if out.count < length { out.append(contentsOf: repeatElement(0, count: length - out.count)) }
        return out
    }
    #endif
}
