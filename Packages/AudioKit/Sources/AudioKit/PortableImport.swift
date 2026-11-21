import Foundation
import NativeAudioFile
import NativeResample

/// Conversión de `AudioImporter` sin AVFoundation (plan, «Corte del paso 7», parte 7.1): decodifica con
/// `AudioFileReader` (dr_wav / dr_flac / dr_mp3 en Windows), remuestrea con r8brain (`StreamResampler`) y escribe
/// WAV estéreo float32 con `AudioFileWriter`. Es el camino de Windows; en el Mac solo lo usan las pruebas
/// (`AudioImporter.forcePortable`) para validar el motor con los mismos casos que AVAudioConverter.
///
/// Mismo contrato que el conversor del Mac: muestra 0 del resultado = muestra 0 del original (r8brain recorta su
/// latencia; desfase medido < 1e-7 muestras en `ResamplerValidationTests`), mono duplicado en los dos canales
/// (idénticos bit a bit), longitud round(n · destino / origen) (AVAudioConverter da a veces una muestra menos).
extension AudioImporter {
    /// Fotogramas por bloque de lectura (no se carga el tema entero).
    static let portableBlockFrames = 16_384

    static func portableConvert(_ source: URL, to destination: URL, sampleRate: Double,
                                progress: @escaping @Sendable (Double) -> Void) throws -> ConversionInfo {
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: source.path))?[.size] as? NSNumber, size.intValue == 0 {
            throw AudioImportError.emptyAudio
        }
        let input: AudioFileReader
        do {
            input = try AudioFileReader(url: source)
        } catch {
            throw AudioImportError.unreadable(error.localizedDescription)
        }
        let channels = input.channelCount
        guard channels == 1 || channels == 2 else {
            throw AudioImportError.unsupportedFormat("\(channels) canales")
        }
        guard input.frameCount > 0 else { throw AudioImportError.emptyAudio }

        var resampler: StreamResampler?
        if input.sampleRate != sampleRate {
            do {
                // Mono: un solo canal remuestreado y duplicado (L y R idénticos, la mitad de trabajo).
                resampler = try StreamResampler(from: input.sampleRate, to: sampleRate, channels: channels)
            } catch {
                throw AudioImportError.unreadable("conversor no disponible: \(error)")
            }
        }

        // Temporal junto al destino; se mueve al final.
        let tmp = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp.wav")
        func cleanup() { try? fm.removeItem(at: tmp) }

        var outFrames = 0
        do {
            let output = try AudioFileWriter(url: tmp, sampleRate: sampleRate, channelCount: 2, format: .float32)
            func write(_ block: [[Float]]) throws {
                guard let n = block.first?.count, n > 0 else { return }
                try output.write(channels == 2 ? block : [block[0], block[0]])
                outFrames += n
            }
            let total = Double(input.frameCount)
            var lastProgress = 0.0
            func report(_ v: Double) {
                let clamped = min(max(v, lastProgress), 1)
                lastProgress = clamped
                progress(clamped)
            }
            while true {
                let block: [[Float]]
                do {
                    block = try input.read(maxFrames: portableBlockFrames)
                } catch {
                    throw AudioImportError.unreadable(error.localizedDescription)
                }
                if (block.first?.count ?? 0) == 0 { break }
                try write(resampler?.process(block) ?? block)
                report(Double(input.framePosition) / total * 0.999)
            }
            if let resampler { try write(resampler.flush()) }
            guard outFrames > 0 else { throw AudioImportError.emptyAudio }
            try output.close()
            report(1)
        } catch let e as AudioImportError {
            cleanup()
            throw e
        } catch {
            cleanup()
            throw AudioImportError.writeFailed(error.localizedDescription)
        }

        do {
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: tmp, to: destination)
        } catch {
            cleanup()
            throw AudioImportError.writeFailed(error.localizedDescription)
        }
        return ConversionInfo(duration: Double(outFrames) / sampleRate,
                              sourceRate: input.sampleRate, sourceChannels: channels)
    }
}
