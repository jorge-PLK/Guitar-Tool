import Foundation

/// ffmpeg → WAV de 24 bits, a la frecuencia del original y sin remuestrear (spec, «Recorrido» paso 5).
/// Acepta `.webm` (Opus, 48 kHz) y `.m4a` (AAC, 44,1 kHz); mismo comando.
public struct AudioTranscoder: Sendable {
    private let ffmpeg: URL
    private let runner: ProcessRunning

    public init(ffmpeg: URL, runner: ProcessRunning) {
        self.ffmpeg = ffmpeg
        self.runner = runner
    }

    public func convert(input: URL, output: URL) async throws {
        let args = ["-nostdin", "-y", "-hide_banner", "-i", input.path, "-c:a", "pcm_s24le", output.path]
        let r = try await runner.run(.init(executable: ffmpeg, arguments: args))
        guard r.status == 0 else {
            throw SourceError.ffmpegFailed(r.stderr.split(separator: "\n").suffix(8).joined(separator: "\n"))
        }
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw SourceError.ffmpegFailed("ffmpeg no dejó \(output.lastPathComponent)")
        }
    }
}
