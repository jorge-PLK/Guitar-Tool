import AVFoundation
import Foundation

/// Audio estéreo planar en memoria.
struct StereoAudio {
    var left: [Float]
    var right: [Float]
    var sampleRate: Double
    var frameCount: Int { left.count }
}

enum AudioIO {
    /// Formato de proceso: float32 estéreo no intercalado.
    static func processingFormat(_ rate: Double) -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: false)!
    }

    /// Lee un WAV estéreo a 44,1 o 48 kHz entero en memoria.
    static func readStereo(_ url: URL) throws -> StereoAudio {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw SeparationError.invalidInput("no se puede leer \(url.lastPathComponent): \(error.localizedDescription)")
        }
        let fmt = file.processingFormat
        guard fmt.channelCount == 2 else {
            throw SeparationError.invalidInput("se esperaba audio estéreo y tiene \(fmt.channelCount) canales")
        }
        guard RoformerContract.acceptedInputRates.contains(fmt.sampleRate) else {
            throw SeparationError.invalidInput("frecuencia \(fmt.sampleRate) Hz no admitida (44100 o 48000)")
        }
        let n = Int(file.length)
        guard n > 0 else { throw SeparationError.invalidInput("el audio está vacío") }
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)) else {
            throw SeparationError.invalidInput("no hay memoria para \(n) muestras")
        }
        try file.read(into: buf, frameCount: AVAudioFrameCount(n))
        let got = Int(buf.frameLength)
        let ch = buf.floatChannelData!
        return StereoAudio(left: Array(UnsafeBufferPointer(start: ch[0], count: got)),
                           right: Array(UnsafeBufferPointer(start: ch[1], count: got)),
                           sampleRate: fmt.sampleRate)
    }

    /// Escritor WAV float32 estéreo en streaming.
    final class StereoWriter {
        let url: URL
        private let file: AVAudioFile
        private let buffer: AVAudioPCMBuffer
        private(set) var written = 0

        init(url: URL, sampleRate: Double, blockFrames: Int = 1 << 16) throws {
            self.url = url
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
            buffer = AVAudioPCMBuffer(pcmFormat: processingFormat(sampleRate),
                                      frameCapacity: AVAudioFrameCount(blockFrames))!
        }

        func write(left: UnsafePointer<Float>, right: UnsafePointer<Float>, count: Int) throws {
            var done = 0
            let cap = Int(buffer.frameCapacity)
            let ch = buffer.floatChannelData!
            while done < count {
                let n = min(cap, count - done)
                ch[0].update(from: left + done, count: n)
                ch[1].update(from: right + done, count: n)
                buffer.frameLength = AVAudioFrameCount(n)
                try file.write(from: buffer)
                done += n
            }
            written += count
        }

        func writeSilence(_ count: Int) throws {
            let zeros = [Float](repeating: 0, count: min(count, Int(buffer.frameCapacity)))
            var left = count
            while left > 0 {
                let n = min(left, zeros.count)
                try zeros.withUnsafeBufferPointer { try write(left: $0.baseAddress!, right: $0.baseAddress!, count: n) }
                left -= n
            }
        }

        func close() { file.close() }
    }

    /// Conversión de frecuencia en streaming con `AVAudioConverter` (calidad .max, algoritmo Mastering).
    /// `pull(left, right, max)` rellena hasta `max` muestras y devuelve cuántas dio (0 = fin);
    /// `push(left, right, n)` recibe la salida por bloques.
    static func resample(from sourceRate: Double, to targetRate: Double,
                         pull: (UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>, Int) throws -> Int,
                         push: (UnsafePointer<Float>, UnsafePointer<Float>, Int) throws -> Void) throws {
        let inFormat = processingFormat(sourceRate)
        let outFormat = processingFormat(targetRate)
        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw SeparationError.invalidInput("AVAudioConverter no admite \(sourceRate) → \(targetRate) Hz")
        }
        converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        let block = 1 << 15
        let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(block))!
        try withoutActuallyEscaping(pull) { pull in
            let source = PullSource(pull: pull, buffer: AVAudioPCMBuffer(
                pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(block))!)
            while true {
                outBuf.frameLength = 0
                var convError: NSError?
                // El bloque se llama de forma síncrona dentro de convert(), en este mismo hilo.
                let status = converter.convert(to: outBuf, error: &convError) { want, inStatus in
                    source.next(want: Int(want), status: inStatus)
                }
                if let e = source.error { throw e }
                if status == .error {
                    throw SeparationError.invalidInput("remuestreo falló: \(convError?.localizedDescription ?? "?")")
                }
                let got = Int(outBuf.frameLength)
                if got > 0 {
                    let ch = outBuf.floatChannelData!
                    try push(ch[0], ch[1], got)
                }
                if status == .endOfStream { break }
            }
        }
    }

    /// Entrada del conversor. `@unchecked Sendable` porque AVAudioConverter declara su bloque de entrada
    /// @Sendable pero lo invoca de forma síncrona dentro de `convert(to:error:withInputFrom:)`.
    private final class PullSource: @unchecked Sendable {
        let pull: (UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>, Int) throws -> Int
        let buffer: AVAudioPCMBuffer
        var ended = false
        var error: Error?

        init(pull: @escaping (UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>, Int) throws -> Int,
             buffer: AVAudioPCMBuffer) {
            self.pull = pull
            self.buffer = buffer
        }

        func next(want: Int, status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
            guard !ended, error == nil else {
                status.pointee = .endOfStream
                return nil
            }
            let ch = buffer.floatChannelData!
            do {
                let n = try pull(ch[0], ch[1], min(want, Int(buffer.frameCapacity)))
                if n == 0 {
                    ended = true
                    status.pointee = .endOfStream
                    return nil
                }
                buffer.frameLength = AVAudioFrameCount(n)
                status.pointee = .haveData
                return buffer
            } catch {
                self.error = error
                status.pointee = .endOfStream
                return nil
            }
        }
    }

    /// Remuestrea audio en memoria.
    static func resample(_ audio: StereoAudio, to targetRate: Double) throws -> StereoAudio {
        var out = StereoAudio(left: [], right: [], sampleRate: targetRate)
        let expected = Int((Double(audio.frameCount) * targetRate / audio.sampleRate).rounded(.up)) + 1024
        out.left.reserveCapacity(expected)
        out.right.reserveCapacity(expected)
        var pos = 0
        try audio.left.withUnsafeBufferPointer { l in
            try audio.right.withUnsafeBufferPointer { r in
                try resample(from: audio.sampleRate, to: targetRate, pull: { dl, dr, maxN in
                    let n = min(maxN, audio.frameCount - pos)
                    if n > 0 {
                        dl.update(from: l.baseAddress! + pos, count: n)
                        dr.update(from: r.baseAddress! + pos, count: n)
                        pos += n
                    }
                    return n
                }, push: { sl, sr, n in
                    out.left.append(contentsOf: UnsafeBufferPointer(start: sl, count: n))
                    out.right.append(contentsOf: UnsafeBufferPointer(start: sr, count: n))
                })
            }
        }
        return out
    }

    /// Remuestrea un WAV estéreo en streaming y escribe exactamente `exactLength` muestras
    /// (recorta o completa con silencio el final).
    static func resampleFile(_ src: URL, to dst: URL, targetRate: Double, exactLength: Int) throws {
        let input = try AVAudioFile(forReading: src, commonFormat: .pcmFormatFloat32, interleaved: false)
        let fmt = input.processingFormat
        let readBuf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1 << 15)!
        let writer = try StereoWriter(url: dst, sampleRate: targetRate)
        defer { writer.close() }
        try resample(from: fmt.sampleRate, to: targetRate, pull: { dl, dr, maxN in
            // AVAudioFile.read al final del fichero devuelve false sin NSError (Swift lanza "nilError").
            let want = min(maxN, Int(readBuf.frameCapacity), Int(input.length - input.framePosition))
            guard want > 0 else { return 0 }
            try input.read(into: readBuf, frameCount: AVAudioFrameCount(want))
            let n = Int(readBuf.frameLength)
            if n > 0 {
                let ch = readBuf.floatChannelData!
                dl.update(from: ch[0], count: n)
                dr.update(from: ch[1], count: n)
            }
            return n
        }, push: { sl, sr, n in
            let room = exactLength - writer.written
            if room > 0 { try writer.write(left: sl, right: sr, count: min(n, room)) }
        })
        if writer.written < exactLength { try writer.writeSilence(exactLength - writer.written) }
    }
}
