#if canImport(AVFoundation)
import AVFoundation
#elseif os(Windows)
import NativeResample
#endif
import Foundation
import NativeAudioFile
import NativePlatform

/// Audio estéreo planar en memoria.
struct StereoAudio {
    var left: [Float]
    var right: [Float]
    var sampleRate: Double
    var frameCount: Int { left.count }
}

enum AudioIO {
    /// Abre un fichero para leer por bloques (`AVAudioFile` float32 no intercalado en el Mac, dr_* en Windows).
    /// Los errores de apertura salen como `SeparationError.invalidInput("no se puede leer <fichero>: …")`.
    static func openReader(_ url: URL) throws -> AudioFileReader {
        do {
            return try AudioFileReader(url: url)
        } catch AudioFileError.unreadable(let why) {
            throw SeparationError.invalidInput("no se puede leer \(why)")
        } catch {
            throw SeparationError.invalidInput("no se puede leer \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Lee `count` fotogramas estéreo desde `start` en `left`/`right`. Devuelve los leídos.
    /// Un fichero mono se duplica en los dos canales (`right` = `left`).
    @discardableResult
    static func read(_ reader: AudioFileReader, from start: Int, count: Int,
                     left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) throws -> Int {
        try reader.seek(toFrame: start)
        var done = 0
        while done < count {
            let ptrs = reader.channelCount == 1 ? [left + done] : [left + done, right + done]
            let got = try reader.read(into: ptrs, maxFrames: count - done)
            if got == 0 { break }
            if reader.channelCount == 1 { (right + done).update(from: left + done, count: got) }
            done += got
        }
        return done
    }

    /// Lee un WAV estéreo a 44,1 o 48 kHz entero en memoria.
    static func readStereo(_ url: URL) throws -> StereoAudio {
        let reader = try openReader(url)
        guard reader.channelCount == 2 else {
            throw SeparationError.invalidInput("se esperaba audio estéreo y tiene \(reader.channelCount) canales")
        }
        guard RoformerContract.acceptedInputRates.contains(reader.sampleRate) else {
            throw SeparationError.invalidInput("frecuencia \(reader.sampleRate) Hz no admitida (44100 o 48000)")
        }
        let n = reader.frameCount
        guard n > 0 else { throw SeparationError.invalidInput("el audio está vacío") }
        var left = [Float](repeating: 0, count: n), right = [Float](repeating: 0, count: n)
        var got = 0
        try left.withUnsafeMutableBufferPointer { l in
            try right.withUnsafeMutableBufferPointer { r in
                got = try read(reader, from: 0, count: n, left: l.baseAddress!, right: r.baseAddress!)
            }
        }
        if got < n {
            left.removeLast(n - got)
            right.removeLast(n - got)
        }
        return StereoAudio(left: left, right: right, sampleRate: reader.sampleRate)
    }

    /// Escritor WAV float32 estéreo en streaming (`AudioFileWriter`: `AVAudioFile` en el Mac, dr_wav en Windows).
    final class StereoWriter {
        let url: URL
        private let file: AudioFileWriter
        private let blockFrames: Int
        private(set) var written = 0

        init(url: URL, sampleRate: Double, blockFrames: Int = 1 << 16) throws {
            self.url = url
            self.blockFrames = blockFrames
            file = try AudioFileWriter(url: url, sampleRate: sampleRate, channelCount: 2, format: .float32)
        }

        func write(left: UnsafePointer<Float>, right: UnsafePointer<Float>, count: Int) throws {
            try file.write([left, right], count: count)
            written += count
        }

        func writeSilence(_ count: Int) throws {
            let zeros = [Float](repeating: 0, count: min(count, blockFrames))
            var left = count
            while left > 0 {
                let n = min(left, zeros.count)
                try zeros.withUnsafeBufferPointer { try write(left: $0.baseAddress!, right: $0.baseAddress!, count: n) }
                left -= n
            }
        }

        func close() { try? file.close() }
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
        let input = try openReader(src)
        let block = 1 << 15
        var bl = [Float](repeating: 0, count: block), br = [Float](repeating: 0, count: block)
        let writer = try StereoWriter(url: dst, sampleRate: targetRate)
        defer { writer.close() }
        try resample(from: input.sampleRate, to: targetRate, pull: { dl, dr, maxN in
            let want = min(maxN, block, input.frameCount - input.framePosition)
            guard want > 0 else { return 0 }
            let n = try bl.withUnsafeMutableBufferPointer { l in
                try br.withUnsafeMutableBufferPointer { r in
                    try read(input, from: input.framePosition, count: want, left: l.baseAddress!, right: r.baseAddress!)
                }
            }
            if n > 0 {
                dl.update(from: bl, count: n)
                dr.update(from: br, count: n)
            }
            return n
        }, push: { sl, sr, n in
            let room = exactLength - writer.written
            if room > 0 { try writer.write(left: sl, right: sr, count: min(n, room)) }
        })
        if writer.written < exactLength { try writer.writeSilence(exactLength - writer.written) }
    }

    #if canImport(AVFoundation)
    /// Formato de proceso: float32 estéreo no intercalado.
    static func processingFormat(_ rate: Double) -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: false)!
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
    #else
    /// Sin `AVAudioConverter` (Windows): r8brain por `StreamResampler` (plan, «Corte del paso 7», parte 7.8, como
    /// `PortableImport` de AudioKit en la 7.1). Muestra 0 de la salida = muestra 0 de la entrada (r8brain recorta su
    /// latencia) y longitud total round(n · destino / origen); `resampleFile` ajusta luego a `exactLength`.
    static func resample(from sourceRate: Double, to targetRate: Double,
                         pull: (UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>, Int) throws -> Int,
                         push: (UnsafePointer<Float>, UnsafePointer<Float>, Int) throws -> Void) throws {
        let resampler: StreamResampler
        do {
            resampler = try StreamResampler(from: sourceRate, to: targetRate, channels: 2)
        } catch {
            throw SeparationError.invalidInput("remuestreador no disponible para \(sourceRate) → \(targetRate) Hz: \(error)")
        }
        let block = 1 << 15
        var l = [Float](repeating: 0, count: block), r = [Float](repeating: 0, count: block)
        func emit(_ out: [[Float]]) throws {
            guard out.count == 2, !out[0].isEmpty else { return }
            try out[0].withUnsafeBufferPointer { a in
                try out[1].withUnsafeBufferPointer { b in try push(a.baseAddress!, b.baseAddress!, out[0].count) }
            }
        }
        while true {
            let n = try l.withUnsafeMutableBufferPointer { lp in
                try r.withUnsafeMutableBufferPointer { rp in try pull(lp.baseAddress!, rp.baseAddress!, block) }
            }
            if n == 0 { break }
            try emit(resampler.process([Array(l[0..<n]), Array(r[0..<n])]))
        }
        try emit(resampler.flush())
    }
    #endif
}
