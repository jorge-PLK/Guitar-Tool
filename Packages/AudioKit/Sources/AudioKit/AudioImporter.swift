import AVFoundation
import Foundation

/// Resultado de importar un tema al formato de trabajo.
public struct ImportedAudio: Sendable, Equatable {
    public var title: String?
    public var artist: String?
    /// Duración del resultado, en segundos.
    public var duration: Double
    /// "wav" | "flac" | "mp3"
    public var sourceFormat: String
    public var sourceSampleRate: Double
    public var sourceChannels: Int

    public init(title: String?, artist: String?, duration: Double, sourceFormat: String,
                sourceSampleRate: Double, sourceChannels: Int) {
        self.title = title
        self.artist = artist
        self.duration = duration
        self.sourceFormat = sourceFormat
        self.sourceSampleRate = sourceSampleRate
        self.sourceChannels = sourceChannels
    }
}

public enum AudioImportError: Error, Equatable {
    case unsupportedFormat(String)
    case unreadable(String)
    case emptyAudio
    case unsupportedSampleRate(Double)
    case writeFailed(String)
}

/// Importa WAV/FLAC/MP3 y los convierte a estéreo, float32, WAV, a la frecuencia de trabajo.
public struct AudioImporter: Sendable {
    public static let supportedSampleRates: [Double] = [44_100, 48_000]
    public static let supportedExtensions: Set<String> = ["wav", "flac", "mp3"]

    /// Frames por bloque de lectura/escritura (no se carga el tema entero).
    private static let blockFrames: AVAudioFrameCount = 16_384

    public init() {}

    public func importAudio(from source: URL, to destination: URL, sampleRate: Double,
                            progress: @escaping @Sendable (Double) -> Void) async throws -> ImportedAudio {
        guard Self.supportedSampleRates.contains(sampleRate) else {
            throw AudioImportError.unsupportedSampleRate(sampleRate)
        }
        let ext = source.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw AudioImportError.unsupportedFormat(ext)
        }
        let info = try Self.convert(source, to: destination, sampleRate: sampleRate, progress: progress)
        let meta = await metadata(of: source)
        return ImportedAudio(title: meta.title, artist: meta.artist, duration: info.duration,
                             sourceFormat: ext, sourceSampleRate: info.sourceRate,
                             sourceChannels: info.sourceChannels)
    }

    /// Remuestrea un WAV ya convertido a otra frecuencia de trabajo.
    public func resample(_ file: URL, to destination: URL, sampleRate: Double) async throws {
        guard Self.supportedSampleRates.contains(sampleRate) else {
            throw AudioImportError.unsupportedSampleRate(sampleRate)
        }
        _ = try Self.convert(file, to: destination, sampleRate: sampleRate, progress: { _ in })
    }

    /// Título y artista de las etiquetas; si no hay título, se deduce del nombre del fichero.
    public func metadata(of source: URL) async -> (title: String?, artist: String?) {
        var title: String?
        var artist: String?
        let asset = AVURLAsset(url: source)
        if let items = try? await asset.load(.commonMetadata) {
            title = await Self.string(items, .commonIdentifierTitle)
            artist = await Self.string(items, .commonIdentifierArtist)
        }
        if title == nil {
            let base = source.deletingPathExtension().lastPathComponent
            if let range = base.range(of: " - ") {
                let a = base[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let t = base[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !a.isEmpty && !t.isEmpty {
                    title = t
                    if artist == nil { artist = a }
                } else {
                    title = base
                }
            } else {
                title = base
            }
        }
        return (title, artist)
    }

    private static func string(_ items: [AVMetadataItem], _ id: AVMetadataIdentifier) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: id).first,
              let value = try? await item.load(.stringValue) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Conversión

    private struct ConversionInfo {
        var duration: Double
        var sourceRate: Double
        var sourceChannels: Int
    }

    private static func convert(_ source: URL, to destination: URL, sampleRate: Double,
                                progress: @escaping @Sendable (Double) -> Void) throws -> ConversionInfo {
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: source.path))?[.size] as? NSNumber, size.intValue == 0 {
            throw AudioImportError.emptyAudio
        }
        let input: AVAudioFile
        do {
            input = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw AudioImportError.unreadable(error.localizedDescription)
        }
        let inFormat = input.processingFormat
        let channels = Int(inFormat.channelCount)
        guard channels == 1 || channels == 2 else {
            throw AudioImportError.unsupportedFormat("\(channels) canales")
        }
        guard input.length > 0 else { throw AudioImportError.emptyAudio }

        guard let stereoIn = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inFormat.sampleRate,
                                           channels: 2, interleaved: false),
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                            channels: 2, interleaved: false),
              let readBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: blockFrames),
              let stereoBuf = AVAudioPCMBuffer(pcmFormat: stereoIn, frameCapacity: blockFrames)
        else { throw AudioImportError.unreadable("formato no soportado") }

        let needsResample = inFormat.sampleRate != sampleRate
        var converter: AVAudioConverter?
        if needsResample {
            guard let c = AVAudioConverter(from: stereoIn, to: outFormat) else {
                throw AudioImportError.unreadable("conversor no disponible")
            }
            c.sampleRateConverterQuality = AVAudioQuality.max.rawValue
            c.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
            converter = c
        }

        // Temporal junto al destino; se mueve al final.
        let tmp = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp.wav")
        func cleanup() { try? fm.removeItem(at: tmp) }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        var outFrames: AVAudioFramePosition = 0
        do {
            let output = try AVAudioFile(forWriting: tmp, settings: settings,
                                         commonFormat: .pcmFormatFloat32, interleaved: false)
            let total = Double(input.length)
            var lastProgress = 0.0
            func report(_ v: Double) {
                let clamped = min(max(v, lastProgress), 1)
                lastProgress = clamped
                progress(clamped)
            }
            var readError: Error?
            var finished = false

            /// Lee un bloque y lo deja en `stereoBuf` (mono duplicado). Falso si no hay más.
            func fillStereo() -> Bool {
                if finished { return false }
                // AVAudioFile.read lanza al llegar al final: no se lee más allá de `length`.
                if input.framePosition >= input.length { finished = true; return false }
                do {
                    try input.read(into: readBuf, frameCount: blockFrames)
                } catch {
                    readError = error
                    finished = true
                    return false
                }
                let n = readBuf.frameLength
                if n == 0 { finished = true; return false }
                stereoBuf.frameLength = n
                let src = readBuf.floatChannelData!
                let dst = stereoBuf.floatChannelData!
                let count = Int(n)
                dst[0].update(from: src[0], count: count)
                dst[1].update(from: src[channels == 2 ? 1 : 0], count: count)
                report(Double(input.framePosition) / total * 0.999)
                return true
            }

            if let converter {
                let ratio = sampleRate / inFormat.sampleRate
                let outCap = AVAudioFrameCount(Double(blockFrames) * ratio) + 1024
                guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCap) else {
                    throw AudioImportError.writeFailed("sin memoria")
                }
                loop: while true {
                    outBuf.frameLength = 0
                    var convError: NSError?
                    let status = converter.convert(to: outBuf, error: &convError) { _, inStatus in
                        if fillStereo() {
                            inStatus.pointee = .haveData
                            return stereoBuf
                        }
                        inStatus.pointee = .endOfStream
                        return nil
                    }
                    if let readError { throw AudioImportError.unreadable(readError.localizedDescription) }
                    if status == .error {
                        throw AudioImportError.unreadable(convError?.localizedDescription ?? "conversión fallida")
                    }
                    if outBuf.frameLength > 0 {
                        try output.write(from: outBuf)
                        outFrames += AVAudioFramePosition(outBuf.frameLength)
                    }
                    if status == .endOfStream { break loop }
                }
            } else {
                while fillStereo() {
                    try output.write(from: stereoBuf)
                    outFrames += AVAudioFramePosition(stereoBuf.frameLength)
                }
                if let readError { throw AudioImportError.unreadable(readError.localizedDescription) }
            }

            guard outFrames > 0 else { throw AudioImportError.emptyAudio }
            // Cierra el fichero (la liberación finaliza la cabecera WAV) antes de moverlo.
            report(1)
            _ = output
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
                              sourceRate: inFormat.sampleRate, sourceChannels: channels)
    }
}
